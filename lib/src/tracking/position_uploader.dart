import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'osmand_request.dart';
import 'position_queue.dart';
import 'position_record.dart';

/// Thrown when a position could not be delivered to Traccar.
class SendException implements Exception {
  SendException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sends single positions to a Traccar server with the OsmAnd protocol.
class OsmAndSender {
  OsmAndSender({
    required this.client,
    required this.server,
    required this.deviceId,
    this.timeout = const Duration(seconds: 15),
  });

  final http.Client client;
  final Uri server;
  final String deviceId;
  final Duration timeout;

  /// Throws [SendException] unless Traccar answered with a 2xx status.
  Future<void> send(PositionRecord position) async {
    final uri = buildOsmAndUri(
      server: server,
      deviceId: deviceId,
      position: position,
    );
    final http.Response response;
    try {
      // POST with the values in the query string, as Traccar Client does.
      response = await client.post(uri).timeout(timeout);
    } on TimeoutException {
      throw SendException('No answer from server (timeout)');
    } on SocketException catch (e) {
      throw SendException('No connection: ${e.osError?.message ?? e.message}');
    } on HandshakeException {
      throw SendException('TLS handshake failed');
    } on http.ClientException catch (e) {
      throw SendException('Connection failed: ${e.message}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SendException(
        response.statusCode == 400
            ? 'Server rejected the position (HTTP 400). '
                  'Is the device ID registered in Traccar?'
            : 'Server error (HTTP ${response.statusCode})',
      );
    }
  }
}

/// Result of one [PositionUploader.flush] run.
class FlushResult {
  const FlushResult({required this.sent, this.error});
  final int sent;
  final String? error;
}

/// Queues positions and sends them to Traccar strictly in order.
///
/// Every position goes through the [FilePositionQueue] first, so a position
/// is only removed after Traccar confirmed it. When a send fails, the flush
/// stops and the remaining positions wait for the next flush.
class PositionUploader {
  PositionUploader({
    required this.queue,
    required this.sender,
    this.commitEvery = 50,
  });

  final FilePositionQueue queue;
  final OsmAndSender sender;

  /// Sent positions are removed from the queue file in groups of this size,
  /// so a long backlog does not rewrite the file after every position. After
  /// a crash, at most this many positions may be sent twice.
  final int commitEvery;

  PositionRecord? lastSent;
  DateTime? lastSentAt;
  String? lastError;

  Future<FlushResult>? _running;

  /// Adds [position] to the queue (it is sent by the next [flush]).
  Future<void> enqueue(PositionRecord position) => queue.add(position);

  /// Sends queued positions, oldest first, until the queue is empty or a send
  /// fails. Concurrent calls share the same run.
  Future<FlushResult> flush() => _running ??= _flush().whenComplete(() {
    _running = null;
  });

  Future<FlushResult> _flush() async {
    var sent = 0;
    final uncommitted = <PositionRecord>[];
    String? error;
    try {
      while (true) {
        final batch = queue.peek(commitEvery);
        if (batch.isEmpty) break;
        for (final position in batch) {
          await sender.send(position);
          sent++;
          uncommitted.add(position);
          lastSent = position;
          lastSentAt = DateTime.now();
        }
        await queue.removeSent(uncommitted);
        uncommitted.clear();
      }
      lastError = null;
    } on SendException catch (e) {
      error = e.message;
      lastError = error;
    } on ArgumentError catch (e) {
      // A record that can never be sent (bad attribute key). Drop it so it
      // does not block the queue forever.
      final bad = queue.peek(uncommitted.length + 1);
      if (bad.length > uncommitted.length) uncommitted.add(bad.last);
      error = 'Dropped an invalid position: ${e.message}';
      lastError = error;
    } finally {
      if (uncommitted.isNotEmpty) await queue.removeSent(uncommitted);
    }
    return FlushResult(sent: sent, error: error);
  }
}
