import 'package:buspilot_vehicle/src/device/battery_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 23);

  test('parses the platform map', () {
    final s = BatterySnapshot.fromMap({
      'available': true,
      'level': 87,
      'status': 'charging',
      'plugged': 'usb',
      'health': 'good',
      'temperatureC': 31.5,
      'voltageMv': 4123,
      'cycleCount': 42,
    }, now);
    expect(s.level, 87);
    expect(s.status, BatteryChargeStatus.charging);
    expect(s.source, PowerSource.usb);
    expect(s.health, BatteryHealth.good);
    expect(s.temperatureC, 31.5);
    expect(s.voltageMv, 4123);
    expect(s.cycleCount, 42);
    expect(s.isPlugged, isTrue);
  });

  test('unknown or missing values fall back safely', () {
    final s = BatterySnapshot.fromMap({
      'status': 'weird',
      'plugged': null,
    }, now);
    expect(s.level, isNull);
    expect(s.status, BatteryChargeStatus.unknown);
    expect(s.source, PowerSource.unknown);
    expect(s.health, BatteryHealth.unknown);
    expect(s.isPlugged, isFalse);
  });
}
