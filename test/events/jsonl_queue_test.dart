import 'dart:io';

import 'package:buspilot_vehicle/src/events/jsonl_queue.dart';
import 'package:flutter_test/flutter_test.dart';

/// A small record type for the generic queue.
class Rec {
  const Rec(this.n, this.label);

  factory Rec.fromJson(Map<String, Object?> json) =>
      Rec(json['n']! as int, json['label']! as String);

  final int n;
  final String label;

  Map<String, Object?> toJson() => {'n': n, 'label': label};

  @override
  bool operator ==(Object other) =>
      other is Rec && other.n == n && other.label == label;

  @override
  int get hashCode => Object.hash(n, label);

  @override
  String toString() => 'Rec($n)';
}

Rec rec(int i) => Rec(i, i.isEven ? 'even $i' : 'odd');

Future<JsonlQueue<Rec>> openQueue(File file, {int? maxLength}) =>
    JsonlQueue.open<Rec>(
      file,
      toJson: (r) => r.toJson(),
      fromJson: Rec.fromJson,
      maxLength: maxLength ?? JsonlQueue.defaultMaxLength,
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
    final q = await openQueue(file);
    expect(q.length, 0);
    expect(q.isEmpty, isTrue);
    expect(await file.parent.exists(), isTrue);
  });

  test('keeps first-in, first-out order', () async {
    final q = await openQueue(file);
    for (var i = 0; i < 5; i++) {
      await q.add(rec(i));
    }
    expect(q.peek(3), [rec(0), rec(1), rec(2)]);
    await q.removeFirst(2);
    expect(q.peek(10), [rec(2), rec(3), rec(4)]);
  });

  test('survives a restart', () async {
    var q = await openQueue(file);
    for (var i = 0; i < 4; i++) {
      await q.add(rec(i));
    }
    await q.removeFirst(1);
    await q.add(rec(4));

    q = await openQueue(file);
    expect(q.peek(10), [rec(1), rec(2), rec(3), rec(4)]);
  });

  test('concurrent adds are all stored in call order', () async {
    final q = await openQueue(file);
    await Future.wait([for (var i = 0; i < 20; i++) q.add(rec(i))]);
    final reopened = await openQueue(file);
    expect(reopened.peek(100), [for (var i = 0; i < 20; i++) rec(i)]);
  });

  test('skips a line cut off by a crash and repairs the file', () async {
    var q = await openQueue(file);
    await q.add(rec(0));
    await q.add(rec(1));
    await file.writeAsString('{"n":12', mode: FileMode.append); // no newline

    q = await openQueue(file);
    expect(q.peek(10), [rec(0), rec(1)]);
    await q.add(rec(2));

    q = await openQueue(file);
    expect(q.peek(10), [rec(0), rec(1), rec(2)]);
  });

  test('skips lines with wrong types', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString('{"n":"x","label":"a"}\n[1,2]\n');
    final q = await openQueue(file);
    expect(q.length, 0);
  });

  test('drops the oldest records when full', () async {
    final q = await openQueue(file, maxLength: 10);
    for (var i = 0; i < 11; i++) {
      await q.add(rec(i));
    }
    // 1 over the limit + 10 % of 10 = 2 dropped.
    expect(q.length, 9);
    expect(q.droppedCount, 2);
    expect(q.peek(1).single, rec(2));
    final reopened = await openQueue(file, maxLength: 10);
    expect(reopened.peek(100), [for (var i = 2; i < 11; i++) rec(i)]);
  });

  test('removeSent skips records that were dropped meanwhile', () async {
    final q = await openQueue(file, maxLength: 10);
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
    final q = await openQueue(file);
    await q.add(rec(0));
    await q.removeFirst(5);
    expect(q.isEmpty, isTrue);
    expect((await openQueue(file)).isEmpty, isTrue);
  });
}
