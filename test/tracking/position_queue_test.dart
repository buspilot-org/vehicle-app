import 'dart:io';

import 'package:buspilot_vehicle/src/tracking/position_queue.dart';
import 'package:buspilot_vehicle/src/tracking/position_record.dart';
import 'package:flutter_test/flutter_test.dart';

PositionRecord rec(int i) => PositionRecord(
  timestamp: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
  latitude: 35 + i / 1000,
  longitude: 139 + i / 1000,
  speed: i.toDouble(),
  battery: 50,
  attributes: i.isEven ? {'ble': 'tag$i'} : const {},
);

void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('queue_test');
    file = File('${dir.path}/sub/queue.jsonl');
  });

  tearDown(() => dir.delete(recursive: true));

  test('starts empty and creates the folder', () async {
    final q = await FilePositionQueue.open(file);
    expect(q.length, 0);
    expect(q.isEmpty, isTrue);
    expect(await file.parent.exists(), isTrue);
  });

  test('keeps first-in, first-out order', () async {
    final q = await FilePositionQueue.open(file);
    for (var i = 0; i < 5; i++) {
      await q.add(rec(i));
    }
    expect(q.peek(3), [rec(0), rec(1), rec(2)]);
    await q.removeFirst(2);
    expect(q.peek(10), [rec(2), rec(3), rec(4)]);
  });

  test('survives a restart', () async {
    var q = await FilePositionQueue.open(file);
    for (var i = 0; i < 4; i++) {
      await q.add(rec(i));
    }
    await q.removeFirst(1);
    await q.add(rec(4));

    q = await FilePositionQueue.open(file);
    expect(q.peek(10), [rec(1), rec(2), rec(3), rec(4)]);
  });

  test('concurrent adds are all stored in call order', () async {
    final q = await FilePositionQueue.open(file);
    await Future.wait([for (var i = 0; i < 20; i++) q.add(rec(i))]);
    final reopened = await FilePositionQueue.open(file);
    expect(reopened.peek(100), [for (var i = 0; i < 20; i++) rec(i)]);
  });

  test('skips a line cut off by a crash and repairs the file', () async {
    var q = await FilePositionQueue.open(file);
    await q.add(rec(0));
    await q.add(rec(1));
    await file.writeAsString('{"t":12', mode: FileMode.append); // no newline

    q = await FilePositionQueue.open(file);
    expect(q.peek(10), [rec(0), rec(1)]);
    await q.add(rec(2));

    q = await FilePositionQueue.open(file);
    expect(q.peek(10), [rec(0), rec(1), rec(2)]);
  });

  test('skips lines with wrong types', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString('{"t":"x","lat":1,"lon":2}\n[1,2]\n');
    final q = await FilePositionQueue.open(file);
    expect(q.length, 0);
  });

  test('drops the oldest positions when full', () async {
    final q = await FilePositionQueue.open(file, maxLength: 10);
    for (var i = 0; i < 11; i++) {
      await q.add(rec(i));
    }
    // 1 over the limit + 10 % of 10 = 2 dropped.
    expect(q.length, 9);
    expect(q.droppedCount, 2);
    expect(q.peek(1).single, rec(2));
    final reopened = await FilePositionQueue.open(file, maxLength: 10);
    expect(reopened.peek(100), [for (var i = 2; i < 11; i++) rec(i)]);
  });

  test('removeSent skips records that were dropped meanwhile', () async {
    final q = await FilePositionQueue.open(file, maxLength: 10);
    for (var i = 0; i < 10; i++) {
      await q.add(rec(i));
    }
    final sending = q.peek(3); // rec 0-2
    await q.add(rec(10)); // full: drops rec 0 and 1
    await q.removeSent(sending); // only rec 2 is still at the head
    expect(q.peek(1).single, rec(3));
    expect(q.length, 8); // rec 3-10
  });

  test('removeFirst with more than the length empties the queue', () async {
    final q = await FilePositionQueue.open(file);
    await q.add(rec(0));
    await q.removeFirst(5);
    expect(q.isEmpty, isTrue);
    expect((await FilePositionQueue.open(file)).isEmpty, isTrue);
  });
}
