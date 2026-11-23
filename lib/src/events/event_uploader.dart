import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'jsonl_queue.dart';
import 'vehicle_event.dart';

/// Thrown when a batch could not be delivered to the engine.
class EventSendException implements Exception {
  EventSendException(this.message, {this.unauthorized = false});

  final String message;

  /// The engine answered 401 (bad vehicle token).
  final bool unauthorized;

  @override
  String toString() => message;
}

/// Sends one batch of events. Throws [EventSendException] on failure.
abstract interface class EventSender {
  Future<void> send(String deviceId, List<VehicleEvent> events);
}

/// `POST {engineUrl}/v1/vehicle-events` with a Bearer vehicle token.
class HttpEventSender implements EventSender {
  HttpEventSender({
    required this.client,
    required String engineUrl,
    required this.vehicleToken,
    this.timeout = const Duration(seconds: 20),
  }) : endpoint = vehicleEventsUri(engineUrl);

  final http.Client client;
  final Uri endpoint;
  final String vehicleToken;
  final Duration timeout;

  @override
  Future<void> send(String deviceId, List<VehicleEvent> events) async {
    final http.Response response;
    try {
      response = await client
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              if (vehicleToken.isNotEmpty)
                'Authorization': 'Bearer $vehicleToken',
            },
            body: jsonEncode(vehicleEventBatch(deviceId, events)),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw EventSendException('No answer from the engine (timeout)');
    } on SocketException catch (e) {
      throw EventSendException(
        'No connection: ${e.osError?.message ?? e.message}',
      );
    } on HandshakeException {
      throw EventSendException('TLS handshake failed');
    } on http.ClientException catch (e) {
      throw EventSendException('Connection failed: ${e.message}');
    }
    final status = response.statusCode;
    if (status == 401) {
      throw EventSendException(
        'Engine rejected the vehicle token (HTTP 401)',
        unauthorized: true,
      );
    }
    if (status < 200 || status >= 300) {
      throw EventSendException('Engine error (HTTP $status)');
    }
  }
}

/// `{engineUrl}/v1/vehicle-events`, keeping a path prefix of [engineUrl].
Uri vehicleEventsUri(String engineUrl) {
  final base = Uri.parse(engineUrl.trim());
  final prefix = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  return base.replace(path: '$prefix/v1/vehicle-events');
}

/// Exponential backoff: [initial], doubled after every failure up to [max].
class Backoff {
  Backoff({
    this.initial = const Duration(seconds: 5),
    this.max = const Duration(minutes: 5),
  });

  final Duration initial;
  final Duration max;
  Duration? _last;

  /// The delay before the next attempt after one more failure.
  Duration next() {
    final last = _last;
    final d = last == null ? initial : last * 2;
    return _last = d > max ? max : d;
  }

  void reset() => _last = null;
}

/// Keeps vehicle events in a [JsonlQueue] and sends them to the engine in
/// batches, oldest first.
///
/// An event is removed only after the engine confirmed its batch, so a crash
/// can at worst send a batch twice (the engine ignores duplicate IDs). After
/// a failed send, nothing is sent until the backoff delay has passed; a 401
/// pauses sending for [unauthorizedPause] (fixing the token in the settings
/// restarts the service, which retries at once).
///
/// Without a [sender] (no engine URL configured) events are only queued.
class EventUploader {
  EventUploader({
    required this.queue,
    required this.deviceId,
    this.sender,
    this.batchSize = 100,
    Backoff? backoff,
    this.unauthorizedPause = const Duration(hours: 1),
    DateTime Function()? clock,
  }) : backoff = backoff ?? Backoff(),
       _clock = clock ?? DateTime.now;

  final JsonlQueue<VehicleEvent> queue;
  final String deviceId;
  final EventSender? sender;
  final int batchSize;
  final Backoff backoff;
  final Duration unauthorizedPause;
  final DateTime Function() _clock;

  DateTime? _nextAttempt;
  Future<void>? _running;
  bool _stopped = false;

  /// When the engine last confirmed a batch.
  DateTime? lastSentAt;

  /// Events confirmed since start.
  int sentCount = 0;

  /// Why the last send failed; null after a successful one.
  String? lastError;

  bool get configured => sender != null;

  /// Whether sending is allowed now (not waiting for a backoff).
  bool get isDue {
    final next = _nextAttempt;
    return next == null || !_clock().isBefore(next);
  }

  /// When the next send is allowed, if waiting for a backoff.
  DateTime? get nextAttempt => _nextAttempt;

  /// Makes a running flush stop after the current batch; later flushes do
  /// nothing. Used when the service shuts down.
  void stop() => _stopped = true;

  /// Completes when no flush is running.
  Future<void> get idle => _running ?? Future.value();

  /// Queues [event] and sends it right away unless waiting for a backoff.
  Future<void> record(VehicleEvent event) async {
    await queue.add(event);
    unawaited(flushIfDue());
  }

  /// Sends queued events unless not configured or waiting for a backoff.
  Future<void> flushIfDue() async {
    if (!configured || !isDue) return;
    await flush();
  }

  /// Sends queued events until the queue is empty or a send fails.
  /// Concurrent calls share the same run.
  Future<void> flush() =>
      _running ??= _flush().whenComplete(() => _running = null);

  Future<void> _flush() async {
    final sender = this.sender;
    if (sender == null) return;
    while (!_stopped) {
      final batch = queue.peek(batchSize);
      if (batch.isEmpty) return;
      try {
        await sender.send(deviceId, batch);
      } on EventSendException catch (e) {
        lastError = e.message;
        _nextAttempt = _clock().add(
          e.unauthorized ? unauthorizedPause : backoff.next(),
        );
        return;
      } on Exception catch (e) {
        // Unexpected (a bug or a platform problem): retry like a failed send
        // instead of letting the error escape from a timer.
        lastError = 'Unexpected error: $e';
        _nextAttempt = _clock().add(backoff.next());
        return;
      }
      backoff.reset();
      _nextAttempt = null;
      lastError = null;
      lastSentAt = _clock();
      sentCount += batch.length;
      try {
        await queue.removeSent(batch);
      } on Exception catch (e) {
        // For example a full disk while rewriting the queue file. The batch
        // stays queued and is sent again later (duplicates are ignored).
        lastError = 'Could not update the event queue: $e';
        _nextAttempt = _clock().add(backoff.next());
        return;
      }
    }
  }
}
