import 'dart:convert';
import 'dart:io';

import 'package:buspilot_vehicle/src/tracking/osmand_request.dart';
import 'package:buspilot_vehicle/src/tracking/position_queue.dart';
import 'package:buspilot_vehicle/src/tracking/position_record.dart';
import 'package:buspilot_vehicle/src/tracking/position_uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

PositionRecord rec(int i) => PositionRecord(
  timestamp: DateTime.utc(2026, 1, 1).add(Duration(seconds: i * 10)),
  latitude: 35,
  longitude: 139 + i / 1000,
);

void main() {
  late Directory dir;
  late FilePositionQueue queue;
  final received = <Uri>[];
  var online = true;
  var status = 200;

  final client = MockClient((request) async {
    if (!online) throw http.ClientException('offline');
    expect(request.method, 'POST');
    received.add(request.url);
    return http.Response('', status);
  });

  PositionUploader uploader({int commitEvery = 50}) => PositionUploader(
    queue: queue,
    sender: OsmAndSender(
      client: client,
      server: Uri.parse('https://traccar.example.org:5055'),
      deviceId: 'bus-1',
    ),
    commitEvery: commitEvery,
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('uploader_test');
    queue = await FilePositionQueue.open(File('${dir.path}/q.jsonl'));
    received.clear();
    online = true;
    status = 200;
  });

  tearDown(() => dir.delete(recursive: true));

  List<String?> sentTimestamps() =>
      received.map((u) => u.queryParameters['timestamp']).toList();

  String ts(int i) => '${rec(i).timestamp.millisecondsSinceEpoch ~/ 1000}';

  test('sends queued positions in order and empties the queue', () async {
    final u = uploader(commitEvery: 2);
    for (var i = 0; i < 5; i++) {
      await u.enqueue(rec(i));
    }
    final result = await u.flush();
    expect(result.sent, 5);
    expect(result.error, isNull);
    expect(sentTimestamps(), [for (var i = 0; i < 5; i++) ts(i)]);
    expect(queue.isEmpty, isTrue);
    expect(u.lastSent, rec(4));
    expect(u.lastSentAt, isNotNull);
  });

  test('keeps positions while offline and sends them later in order', () async {
    final u = uploader();
    online = false;
    await u.enqueue(rec(0));
    await u.enqueue(rec(1));
    var result = await u.flush();
    expect(result.sent, 0);
    expect(result.error, contains('offline'));
    expect(u.lastError, isNotNull);
    expect(queue.length, 2);

    await u.enqueue(rec(2));
    online = true;
    result = await u.flush();
    expect(result.sent, 3);
    expect(sentTimestamps(), [ts(0), ts(1), ts(2)]);
    expect(queue.isEmpty, isTrue);
    expect(u.lastError, isNull);
  });

  test('stops at the first failure and keeps the rest queued', () async {
    var calls = 0;
    final flaky = MockClient((request) async {
      calls++;
      if (calls == 3) throw http.ClientException('lost');
      received.add(request.url);
      return http.Response('', 200);
    });
    final u = PositionUploader(
      queue: queue,
      sender: OsmAndSender(
        client: flaky,
        server: Uri.parse('https://x.example'),
        deviceId: 'a',
      ),
    );
    for (var i = 0; i < 5; i++) {
      await u.enqueue(rec(i));
    }
    final result = await u.flush();
    expect(result.sent, 2);
    expect(queue.peek(10), [rec(2), rec(3), rec(4)]);

    // The sent positions were removed from the file as well.
    final reopened = await FilePositionQueue.open(File('${dir.path}/q.jsonl'));
    expect(reopened.peek(10), [rec(2), rec(3), rec(4)]);
  });

  test('treats HTTP errors as failures and explains HTTP 400', () async {
    final u = uploader();
    status = 400;
    await u.enqueue(rec(0));
    final result = await u.flush();
    expect(result.sent, 0);
    expect(result.error, contains('device ID'));
    expect(queue.length, 1);

    status = 503;
    expect((await u.flush()).error, contains('503'));
    expect(queue.length, 1);
  });

  test('concurrent flushes share one run (no double sends)', () async {
    final u = uploader();
    for (var i = 0; i < 3; i++) {
      await u.enqueue(rec(i));
    }
    final results = await Future.wait([u.flush(), u.flush()]);
    expect(identical(results[0], results[1]), isTrue);
    expect(received.length, 3);
  });

  test('rejects a position with an invalid attribute at enqueue', () async {
    final u = uploader();
    await expectLater(
      u.enqueue(rec(0).copyWith(attributes: {'lat': 'bad'})),
      throwsA(isA<InvalidOsmAndAttribute>()),
    );
    expect(queue.isEmpty, isTrue);
  });

  test(
    'sends each position under the device ID it was recorded with',
    () async {
      final u = uploader(); // default device ID: bus-1
      PositionRecord withId(int i, String? id) => PositionRecord(
        timestamp: rec(i).timestamp,
        latitude: 35,
        longitude: 139,
        deviceId: id,
      );
      await u.enqueue(withId(0, 'old-bus'));
      await u.enqueue(withId(1, null));
      await u.flush();
      expect(received.map((u) => u.queryParameters['id']), [
        'old-bus',
        'bus-1',
      ]);
    },
  );

  test('device ID survives the queue file', () async {
    await queue.add(rec(0));
    await queue.add(
      PositionRecord(
        timestamp: rec(1).timestamp,
        latitude: 1,
        longitude: 2,
        deviceId: 'old-bus',
      ),
    );
    final reopened = await FilePositionQueue.open(File('${dir.path}/q.jsonl'));
    expect(reopened.peek(2).last.deviceId, 'old-bus');
  });

  test('stop ends a running flush and later flushes send nothing', () async {
    late PositionUploader u;
    var calls = 0;
    final stopping = MockClient((request) async {
      calls++;
      if (calls == 2) u.stop();
      return http.Response('', 200);
    });
    u = PositionUploader(
      queue: queue,
      sender: OsmAndSender(
        client: stopping,
        server: Uri.parse('https://x.example'),
        deviceId: 'a',
      ),
    );
    for (var i = 0; i < 5; i++) {
      await u.enqueue(rec(i));
    }
    final result = await u.flush();
    expect(result.sent, 2);
    expect(queue.length, 3);
    expect((await u.flush()).sent, 0);
    expect(calls, 2);
  });

  test('reports unexpected errors and keeps the queue', () async {
    final broken = MockClient(
      (request) async => throw const FileSystemException('boom'),
    );
    final u = PositionUploader(
      queue: queue,
      sender: OsmAndSender(
        client: broken,
        server: Uri.parse('https://x.example'),
        deviceId: 'a',
      ),
    );
    await u.enqueue(rec(0));
    final result = await u.flush();
    expect(result.error, contains('boom'));
    expect(u.lastError, contains('boom'));
    expect(queue.length, 1);
  });

  test('drops an unsendable record from a damaged queue file', () async {
    final file = File('${dir.path}/damaged.jsonl');
    final good = rec(1).toJson();
    await file.writeAsString(
      '{"t":0,"lat":1,"lon":2,"attr":{"lat":"x"}}\n${jsonEncode(good)}\n',
    );
    queue = await FilePositionQueue.open(file);
    final u = uploader();
    final result = await u.flush();
    expect(result.sent, 1);
    expect(result.error, contains('unsendable'));
    expect(queue.isEmpty, isTrue);
    expect(sentTimestamps(), [ts(1)]);
  });
}
