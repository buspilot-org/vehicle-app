import 'package:buspilot_vehicle/src/tracking/position_filter.dart';
import 'package:buspilot_vehicle/src/tracking/position_record.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 1, 1);

/// [north] is metres north of the start point.
PositionRecord at(int seconds, {double north = 0}) => PositionRecord(
  timestamp: t0.add(Duration(seconds: seconds)),
  latitude: 35 + north / 111195,
  longitude: 139,
);

void main() {
  test('distance is about right', () {
    expect(distanceMeters(at(0), at(0, north: 100)), closeTo(100, 0.5));
  });

  test('without distance filter, accepts one fix per interval', () {
    final f = PositionFilter(
      interval: const Duration(seconds: 10),
      distanceFilterMeters: 0,
    );
    expect(f.accept(at(0)), isTrue);
    expect(f.accept(at(3)), isFalse); // too soon
    expect(f.accept(at(9)), isTrue); // within the 80 % jitter allowance
    expect(f.accept(at(19)), isTrue);
  });

  test('drops fixes older than the last accepted one', () {
    final f = PositionFilter(
      interval: const Duration(seconds: 1),
      distanceFilterMeters: 0,
    );
    expect(f.accept(at(10)), isTrue);
    expect(f.accept(at(10)), isFalse);
    expect(f.accept(at(5)), isFalse);
  });

  test(
    'with distance filter, waits for movement or the stationary interval',
    () {
      final f = PositionFilter(
        interval: const Duration(seconds: 10),
        distanceFilterMeters: 50,
        stationaryInterval: const Duration(minutes: 5),
      );
      expect(f.accept(at(0)), isTrue);
      expect(f.accept(at(10, north: 20)), isFalse);
      expect(f.accept(at(20, north: 60)), isTrue);
      expect(f.accept(at(30, north: 70)), isFalse);
      expect(f.accept(at(320, north: 70)), isTrue); // parked: 5 min heartbeat
    },
  );
}
