import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:buspilot_vehicle/src/events/events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records batches; fails while [failWith] is set.
class FakeSender implements EventSender {
  final batches = <List<String>>[];
  EventSendException? failWith;
  Completer<void>? gate;

  @override
  Future<void> send(String deviceId, List<VehicleEvent> events) async {
    await gate?.future;
    final f = failWith;
    if (f != null) throw f;
    batches.add([for (final e in events) e.id]);
  }
}

void main() {
  late Directory dir;
  late JsonlQueue<VehicleEvent> queue;
  late FakeSender sender;
  var now = DateTime.utc(2026, 11, 23, 9);

  VehicleEvent ev(int i) => VehicleEvent.tagGone(
    id: 'e$i',
    tagId: 'tag$i',
    time: DateTime.utc(2026, 11, 23, 9, 0, i),
  );

  EventUploader uploader({EventSender? s, int batchSize = 100}) =>
      EventUploader(
        queue: queue,
        deviceId: '12345678',
        sender: s,
        batchSize: batchSize,
        clock: () => now,
      );

  setUp(() async {
    now = DateTime.utc(2026, 11, 23, 9);
    dir = await Directory.systemTemp.createTemp('events_test');
    queue = await JsonlQueue.open<VehicleEvent>(
      File('${dir.path}/events.jsonl'),
      toJson: (e) => e.toJson(),
      fromJson: VehicleEvent.fromJson,
    );
    sender = FakeSender();
  });

  tearDown(() => dir.delete(recursive: true));

  test('sends in batches, oldest first, and empties the queue', () async {
    final u = uploader(s: sender, batchSize: 2);
    for (var i = 0; i < 5; i++) {
      await queue.add(ev(i));
    }
    await u.flush();
    expect(sender.batches, [
      ['e0', 'e1'],
      ['e2', 'e3'],
      ['e4'],
    ]);
    expect(queue.isEmpty, isTrue);
    expect(u.sentCount, 5);
    expect(u.lastSentAt, now);
    expect(u.lastError, isNull);
  });

  test('record queues and sends right away', () async {
    final u = uploader(s: sender);
    await u.record(ev(1));
    await u.idle;
    await Future<void>.delayed(Duration.zero);
    await u.idle;
    expect(sender.batches, [
      ['e1'],
    ]);
    expect(queue.isEmpty, isTrue);
  });

  test('without an engine, events are only queued', () async {
    final u = uploader();
    await u.record(ev(1));
    await u.flushIfDue();
    await u.flush();
    expect(u.configured, isFalse);
    expect(queue.length, 1);
  });

  test('a failed send keeps the events and backs off exponentially', () async {
    final u = uploader(s: sender);
    sender.failWith = EventSendException('Engine error (HTTP 503)');
    await queue.add(ev(1));

    await u.flush();
    expect(queue.length, 1);
    expect(u.lastError, 'Engine error (HTTP 503)');
    expect(u.nextAttempt, now.add(const Duration(seconds: 5)));
    expect(u.isDue, isFalse);

    // Not due yet: nothing is tried.
    sender.failWith = null;
    await u.flushIfDue();
    expect(sender.batches, isEmpty);

    // Due, fails again: the delay doubles.
    sender.failWith = EventSendException('again');
    now = now.add(const Duration(seconds: 5));
    await u.flushIfDue();
    expect(u.nextAttempt, now.add(const Duration(seconds: 10)));

    // Due, succeeds: backoff is reset.
    sender.failWith = null;
    now = now.add(const Duration(seconds: 10));
    await u.flushIfDue();
    expect(sender.batches, [
      ['e1'],
    ]);
    expect(queue.isEmpty, isTrue);
    expect(u.nextAttempt, isNull);
    expect(u.lastError, isNull);

    sender.failWith = EventSendException('later');
    await u.record(ev(2));
    await u.idle;
    expect(u.nextAttempt, now.add(const Duration(seconds: 5)));
  });

  test('backoff is capped', () {
    final b = Backoff(
      initial: const Duration(seconds: 5),
      max: const Duration(minutes: 5),
    );
    final delays = [for (var i = 0; i < 9; i++) b.next().inSeconds];
    expect(delays, [5, 10, 20, 40, 80, 160, 300, 300, 300]);
    b.reset();
    expect(b.next().inSeconds, 5);
  });

  test('401 pauses sending for an hour', () async {
    final u = uploader(s: sender);
    sender.failWith = EventSendException('401', unauthorized: true);
    await queue.add(ev(1));
    await u.flush();
    expect(u.nextAttempt, now.add(const Duration(hours: 1)));
    expect(queue.length, 1);
  });

  test('unexpected errors are retried, not thrown', () async {
    final u = uploader(s: _ThrowingSender());
    await queue.add(ev(1));
    await u.flush();
    expect(u.lastError, startsWith('Unexpected error'));
    expect(u.isDue, isFalse);
    expect(queue.length, 1);
  });

  test('events added during a send are sent in the same flush', () async {
    final u = uploader(s: sender, batchSize: 1);
    sender.gate = Completer<void>();
    await queue.add(ev(1));
    final running = u.flush();
    await queue.add(ev(2));
    sender.gate!.complete();
    await running;
    expect(sender.batches, [
      ['e1'],
      ['e2'],
    ]);
  });

  test('concurrent flushes share one run', () async {
    final u = uploader(s: sender);
    sender.gate = Completer<void>();
    await queue.add(ev(1));
    final a = u.flush();
    final b = u.flush();
    sender.gate!.complete();
    await Future.wait([a, b]);
    expect(sender.batches, hasLength(1));
  });

  test('stop ends a flush after the current batch', () async {
    final u = uploader(s: sender, batchSize: 1);
    sender.gate = Completer<void>();
    await queue.add(ev(1));
    await queue.add(ev(2));
    final running = u.flush();
    u.stop();
    sender.gate!.complete();
    await running;
    expect(sender.batches, [
      ['e1'],
    ]);
    expect(queue.length, 1);
  });

  test('queued events survive a restart', () async {
    final u = uploader();
    await u.record(ev(1));
    await u.record(ev(2));
    final reopened = await JsonlQueue.open<VehicleEvent>(
      File('${dir.path}/events.jsonl'),
      toJson: (e) => e.toJson(),
      fromJson: VehicleEvent.fromJson,
    );
    expect(reopened.peek(10).map((e) => e.id), ['e1', 'e2']);
  });

  group('HttpEventSender', () {
    test('posts the batch as JSON with the Bearer token', () async {
      late http.Request request;
      final s = HttpEventSender(
        client: MockClient((r) async {
          request = r;
          return http.Response('{"accepted":1}', 200);
        }),
        engineUrl: 'https://engine.example/base/',
        vehicleToken: 'tok',
      );
      await s.send('12345678', [ev(1)]);
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://engine.example/base/v1/vehicle-events',
      );
      expect(request.headers['Authorization'], 'Bearer tok');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {
        'deviceId': '12345678',
        'events': [ev(1).toJson()],
      });
    });

    test('sends no Authorization header without a token', () async {
      late http.Request request;
      final s = HttpEventSender(
        client: MockClient((r) async {
          request = r;
          return http.Response('{"accepted":1}', 200);
        }),
        engineUrl: 'https://engine.example',
        vehicleToken: '',
      );
      await s.send('1', [ev(1)]);
      expect(request.url.path, '/v1/vehicle-events');
      expect(request.headers.containsKey('Authorization'), isFalse);
    });

    test('401 is reported as unauthorized, other errors as retryable', () {
      HttpEventSender sender(int status) => HttpEventSender(
        client: MockClient((_) async => http.Response('', status)),
        engineUrl: 'https://engine.example',
        vehicleToken: 't',
      );
      expect(
        sender(401).send('1', [ev(1)]),
        throwsA(
          isA<EventSendException>().having(
            (e) => e.unauthorized,
            'unauthorized',
            isTrue,
          ),
        ),
      );
      for (final status in [400, 404, 500, 503]) {
        expect(
          sender(status).send('1', [ev(1)]),
          throwsA(
            isA<EventSendException>().having(
              (e) => e.unauthorized,
              'unauthorized',
              isFalse,
            ),
          ),
        );
      }
    });

    test('connection problems become EventSendException', () {
      final s = HttpEventSender(
        client: MockClient((_) async => throw http.ClientException('down')),
        engineUrl: 'https://engine.example',
        vehicleToken: 't',
      );
      expect(s.send('1', [ev(1)]), throwsA(isA<EventSendException>()));
    });
  });

  test('vehicleEventsUri keeps a path prefix', () {
    expect(
      vehicleEventsUri('https://e.example').toString(),
      'https://e.example/v1/vehicle-events',
    );
    expect(
      vehicleEventsUri('https://e.example:8443/api').toString(),
      'https://e.example:8443/api/v1/vehicle-events',
    );
  });
}

class _ThrowingSender implements EventSender {
  @override
  Future<void> send(String deviceId, List<VehicleEvent> events) async =>
      throw const FormatException('bad response');
}
