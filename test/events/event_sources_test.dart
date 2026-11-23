import 'package:buspilot_vehicle/src/ble/beacon.dart';
import 'package:buspilot_vehicle/src/ble/presence_tracker.dart';
import 'package:buspilot_vehicle/src/ble/tag_filter.dart';
import 'package:buspilot_vehicle/src/device/battery_snapshot.dart';
import 'package:buspilot_vehicle/src/device/device_warnings.dart';
import 'package:buspilot_vehicle/src/events/events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uuid = 'e2c56db5-dffb-48d2-b060-d0f5a71096e0';
  const other = '11111111-2222-3333-4444-555555555555';
  final filter = TagFilter(iBeaconUuids: [uuid]);
  final first = DateTime.utc(2026, 11, 23, 8);
  final last = DateTime.utc(2026, 11, 23, 8, 10);

  PresentTag tag(String u) => PresentTag(
    beacon: IBeacon(uuid: u, major: 1, minor: 2),
    address: 'C4:7C:8D:00:00:01',
    firstSeen: first,
    lastSeen: last,
    rssi: -61,
    smoothedRssi: -63.4,
    sightings: 3,
  );

  group('tag events', () {
    test('enter becomes tag_seen with the first sighting', () {
      final e = tagEventFor(TagEntered(tag(uuid), first), filter)!;
      expect(e.type, 'tag_seen');
      expect(e.time, first);
      expect(e.payload, {
        'tag': {'id': 'ibeacon:$uuid:1:2', 'rssi': -61},
      });
    });

    test('leave becomes tag_gone at the time it was last heard', () {
      final detected = last.add(const Duration(seconds: 30));
      final e = tagEventFor(TagLeft(tag(uuid), detected), filter)!;
      expect(e.type, 'tag_gone');
      expect(e.time, last);
      expect(e.payload, {
        'tag': {'id': 'ibeacon:$uuid:1:2'},
      });
    });

    test('tags outside the filter give no event', () {
      expect(tagEventFor(TagEntered(tag(other), first), filter), isNull);
      expect(tagEventFor(TagLeft(tag(other), last), filter), isNull);
      expect(tagEventFor(TagEntered(tag(uuid), first), TagFilter()), isNull);
    });

    test('no MAC address in any event', () {
      for (final e in [
        tagEventFor(TagEntered(tag(uuid), first), filter)!,
        tagEventFor(TagLeft(tag(uuid), last), filter)!,
        tagsOnBoardEvent([tag(uuid)], filter, last),
      ]) {
        expect(e.toJson().toString(), isNot(contains('C4:7C')));
      }
    });

    test('tags_on_board lists only matching present tags', () {
      final e = tagsOnBoardEvent([tag(uuid), tag(other)], filter, last);
      expect(e.type, 'tags_on_board');
      expect(e.time, last);
      expect(e.payload['tags'], ['ibeacon:$uuid:1:2']);
      expect(tagsOnBoardEvent(const [], filter, last).payload['tags'], []);
    });
  });

  group('HealthEventScheduler', () {
    final t0 = DateTime.utc(2026, 11, 23, 8);
    BatterySnapshot reading(Duration after, {double temp = 30}) =>
        BatterySnapshot(
          timestamp: t0.add(after),
          level: 50,
          temperatureC: temp,
        );
    const hot = [DeviceWarning(DeviceWarningType.batteryHot, 'hot')];
    const old = [DeviceWarning(DeviceWarningType.batteryHealthNotGood, 'x')];

    test('first reading, then every 5 minutes', () {
      final s = HealthEventScheduler();
      final emitted = <int>[];
      for (var m = 0; m <= 12; m++) {
        if (s.onReading(reading(Duration(minutes: m)), const []) != null) {
          emitted.add(m);
        }
      }
      expect(emitted, [0, 5, 10]);
    });

    test('poll jitter does not delay the event by a whole poll', () {
      final s = HealthEventScheduler();
      expect(s.onReading(reading(Duration.zero), const []), isNotNull);
      expect(
        s.onReading(reading(const Duration(minutes: 4, seconds: 58)), const []),
        isNotNull,
      );
    });

    test('a new warning is sent at once, an ongoing one is not', () {
      final s = HealthEventScheduler();
      expect(s.onReading(reading(Duration.zero), const []), isNotNull);
      final e = s.onReading(reading(const Duration(minutes: 1)), hot);
      expect(e, isNotNull);
      expect(e!.payload['warnings'], ['batteryHot']);
      expect(s.onReading(reading(const Duration(minutes: 2)), hot), isNull);
      // Another new warning while the first continues.
      expect(
        s.onReading(reading(const Duration(minutes: 3)), [...hot, ...old]),
        isNotNull,
      );
      // Gone and back again counts as new.
      expect(
        s.onReading(reading(const Duration(minutes: 4)), const []),
        isNull,
      );
      expect(s.onReading(reading(const Duration(minutes: 4)), hot), isNotNull);
    });

    test('no reading, no event', () {
      expect(HealthEventScheduler().onReading(null, hot), isNull);
    });

    test('a clock set backwards does not stop the events', () {
      final s = HealthEventScheduler();
      expect(
        s.onReading(reading(const Duration(hours: 1)), const []),
        isNotNull,
      );
      expect(s.onReading(reading(Duration.zero), const []), isNotNull);
    });
  });
}
