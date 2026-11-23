import 'dart:convert';
import 'dart:math';

import 'package:buspilot_vehicle/src/device/battery_snapshot.dart';
import 'package:buspilot_vehicle/src/device/device_warnings.dart';
import 'package:buspilot_vehicle/src/events/vehicle_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime.utc(2026, 11, 23, 10, 30, 1, 456);

  // The examples from the internal concept, server.md › "Vehicle events".
  test('tag_seen matches the spec', () {
    final e = VehicleEvent.tagSeen(
      id: 'u1',
      tagId: 'ibeacon:e2c56db5-dffb-48d2-b060-d0f5a71096e0:1:2',
      rssi: -67,
      time: t,
    );
    expect(e.toJson(), {
      'id': 'u1',
      'type': 'tag_seen',
      'time': '2026-11-23T10:30:01Z',
      'tag': {
        'id': 'ibeacon:e2c56db5-dffb-48d2-b060-d0f5a71096e0:1:2',
        'rssi': -67,
      },
    });
  });

  test('tag_gone matches the spec', () {
    final e = VehicleEvent.tagGone(
      id: 'u2',
      tagId: 'eddystone:00112233445566778899:0bdb87539b67',
      time: DateTime.utc(2026, 11, 23, 10, 41, 12),
    );
    expect(e.toJson(), {
      'id': 'u2',
      'type': 'tag_gone',
      'time': '2026-11-23T10:41:12Z',
      'tag': {'id': 'eddystone:00112233445566778899:0bdb87539b67'},
    });
  });

  test('tags_on_board matches the spec (also when empty)', () {
    expect(
      VehicleEvent.tagsOnBoard(id: 'u3', tagIds: ['a', 'b'], time: t).toJson(),
      {
        'id': 'u3',
        'type': 'tags_on_board',
        'time': '2026-11-23T10:30:01Z',
        'tags': ['a', 'b'],
      },
    );
    expect(
      VehicleEvent.tagsOnBoard(id: 'u4', tagIds: [], time: t).toJson()['tags'],
      isEmpty,
    );
  });

  test('device_health matches the spec', () {
    final e = VehicleEvent.deviceHealth(
      id: 'u5',
      battery: BatterySnapshot(
        timestamp: t,
        level: 69,
        status: BatteryChargeStatus.charging,
        source: PowerSource.ac,
        health: BatteryHealth.good,
        temperatureC: 29.8,
        voltageMv: 4200, // not part of the event
      ),
      warnings: const [
        DeviceWarning(DeviceWarningType.batteryHot, 'long text, not sent'),
      ],
    );
    expect(e.toJson(), {
      'id': 'u5',
      'type': 'device_health',
      'time': '2026-11-23T10:30:01Z',
      'battery': {
        'level': 69,
        'charging': true,
        'source': 'ac',
        'temperatureC': 29.8,
        'health': 'good',
      },
      'warnings': ['batteryHot'],
    });
  });

  test('device_health leaves out unknown level and temperature', () {
    final json = VehicleEvent.deviceHealth(
      battery: BatterySnapshot(timestamp: t, status: BatteryChargeStatus.full),
      warnings: const [],
    ).toJson();
    expect(json['battery'], {
      'charging': false,
      'source': 'unknown',
      'health': 'unknown',
    });
    expect(json['warnings'], isEmpty);
  });

  test('batch body matches the spec', () {
    final events = [
      VehicleEvent.tagSeen(id: 'u1', tagId: 'x', rssi: -50, time: t),
      VehicleEvent.tagGone(id: 'u2', tagId: 'x', time: t),
    ];
    final body = jsonDecode(jsonEncode(vehicleEventBatch('12345678', events)));
    expect(body, {
      'deviceId': '12345678',
      'events': [
        {
          'id': 'u1',
          'type': 'tag_seen',
          'time': '2026-11-23T10:30:01Z',
          'tag': {'id': 'x', 'rssi': -50},
        },
        {
          'id': 'u2',
          'type': 'tag_gone',
          'time': '2026-11-23T10:30:01Z',
          'tag': {'id': 'x'},
        },
      ],
    });
  });

  test('round-trips through the queue format unchanged', () {
    final events = [
      VehicleEvent.tagSeen(tagId: 'x', rssi: -50, time: t),
      VehicleEvent.tagsOnBoard(tagIds: ['a'], time: t),
      VehicleEvent.deviceHealth(
        battery: BatterySnapshot(timestamp: t, level: 5),
        warnings: const [],
      ),
    ];
    for (final e in events) {
      final line = jsonEncode(e.toJson());
      final back = VehicleEvent.fromJson(
        jsonDecode(line) as Map<String, Object?>,
      );
      expect(jsonEncode(back.toJson()), line);
      expect(back.id, e.id);
      expect(back.type, e.type);
    }
  });

  test('fromJson rejects damaged lines', () {
    expect(
      () => VehicleEvent.fromJson({'type': 'tag_seen', 'time': 'x'}),
      throwsA(isA<TypeError>()),
    );
    expect(
      () => VehicleEvent.fromJson({'id': 'a', 'type': 't', 'time': 'nope'}),
      throwsFormatException,
    );
    expect(
      () => VehicleEvent.fromJson({
        'id': '',
        'type': 't',
        'time': '2026-01-01T00:00:00Z',
      }),
      throwsFormatException,
    );
  });

  test('times are UTC with second precision', () {
    expect(
      formatEventTime(DateTime.utc(2026, 1, 2, 3, 4, 5, 999)),
      '2026-01-02T03:04:05Z',
    );
    // A local time is converted.
    final local = DateTime.utc(2026, 1, 2, 3, 4, 5).toLocal();
    expect(formatEventTime(local), '2026-01-02T03:04:05Z');
  });

  test('event IDs are random version 4 UUIDs', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final rng = Random(7);
    final ids = {for (var i = 0; i < 1000; i++) newEventId(rng)};
    expect(ids, hasLength(1000));
    for (final id in ids) {
      expect(id, matches(pattern));
    }
    expect(newEventId(), matches(pattern));
    expect(
      VehicleEvent.tagGone(tagId: 'x', time: t).id,
      isNot(VehicleEvent.tagGone(tagId: 'x', time: t).id),
    );
  });
}
