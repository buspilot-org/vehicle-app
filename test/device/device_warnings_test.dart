import 'package:buspilot_vehicle/src/device/battery_snapshot.dart';
import 'package:buspilot_vehicle/src/device/device_health_config.dart';
import 'package:buspilot_vehicle/src/device/device_warnings.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 11, 23, 8);

BatterySnapshot snap({
  Duration at = Duration.zero,
  int? level = 80,
  BatteryChargeStatus status = BatteryChargeStatus.discharging,
  PowerSource source = PowerSource.none,
  BatteryHealth health = BatteryHealth.good,
  double? temperatureC = 30,
}) => BatterySnapshot(
  timestamp: t0.add(at),
  level: level,
  status: status,
  source: source,
  health: health,
  temperatureC: temperatureC,
);

BatterySnapshot fullOnPower(Duration at) => snap(
  at: at,
  level: 100,
  status: BatteryChargeStatus.full,
  source: PowerSource.usb,
);

Set<DeviceWarningType> types(List<DeviceWarning> w) =>
    w.map((e) => e.type).toSet();

void main() {
  const config = DeviceHealthConfig(
    hotThresholdC: 45,
    fullChargeWarnAfter: Duration(hours: 6),
    maxSampleGap: Duration(minutes: 30),
  );

  group('battery too hot', () {
    test('no warning below the threshold', () {
      expect(
        evaluateDeviceWarnings(snap(temperatureC: 44.9), config: config),
        isEmpty,
      );
    });

    test('warns at the threshold', () {
      final w = evaluateDeviceWarnings(snap(temperatureC: 45), config: config);
      expect(types(w), {DeviceWarningType.batteryHot});
      expect(w.single.code, 'batteryHot');
      expect(w.single.message, contains('45.0 °C'));
    });

    test('threshold is configurable', () {
      const cool = DeviceHealthConfig(hotThresholdC: 40);
      expect(
        types(evaluateDeviceWarnings(snap(temperatureC: 41), config: cool)),
        {DeviceWarningType.batteryHot},
      );
    });

    test('missing temperature gives no warning', () {
      expect(
        evaluateDeviceWarnings(snap(temperatureC: null), config: config),
        isEmpty,
      );
    });
  });

  group('battery health', () {
    test('good and unknown give no warning', () {
      expect(evaluateDeviceWarnings(snap(health: BatteryHealth.good)), isEmpty);
      expect(
        evaluateDeviceWarnings(snap(health: BatteryHealth.unknown)),
        isEmpty,
      );
    });

    for (final health in [
      BatteryHealth.overheat,
      BatteryHealth.dead,
      BatteryHealth.overVoltage,
      BatteryHealth.failure,
      BatteryHealth.cold,
    ]) {
      test('${health.name} warns', () {
        final w = evaluateDeviceWarnings(snap(health: health));
        expect(types(w), {DeviceWarningType.batteryHealthNotGood});
        expect(w.single.message, contains(health.name));
      });
    }
  });

  group('100 % on power for a long time', () {
    List<DeviceWarning> run(List<BatterySnapshot> readings) {
      final tracker = FullChargeTracker(config: config);
      var warnings = <DeviceWarning>[];
      for (final r in readings) {
        tracker.update(r);
        warnings = evaluateDeviceWarnings(
          r,
          config: config,
          fullSince: tracker.fullSince,
        );
      }
      return warnings;
    }

    List<BatterySnapshot> everyTenMinutes(
      Duration from,
      Duration to,
      BatterySnapshot Function(Duration) make,
    ) => [
      for (var at = from; at <= to; at += const Duration(minutes: 10)) make(at),
    ];

    test('no warning just before the limit', () {
      final readings = everyTenMinutes(
        Duration.zero,
        const Duration(hours: 5, minutes: 50),
        fullOnPower,
      );
      expect(run(readings), isEmpty);
    });

    test('warns once the limit is reached', () {
      final readings = everyTenMinutes(
        Duration.zero,
        const Duration(hours: 6),
        fullOnPower,
      );
      final w = run(readings);
      expect(types(w), {DeviceWarningType.fullChargeTooLong});
      expect(w.single.message, contains('6h 0min'));
    });

    test('unplugging resets the timer', () {
      final readings = [
        ...everyTenMinutes(
          Duration.zero,
          const Duration(hours: 4),
          fullOnPower,
        ),
        snap(at: const Duration(hours: 4, minutes: 10), level: 99),
        ...everyTenMinutes(
          const Duration(hours: 4, minutes: 20),
          const Duration(hours: 8),
          fullOnPower,
        ),
      ];
      expect(run(readings), isEmpty);
    });

    test('100 % on battery (unplugged) does not count', () {
      final readings = everyTenMinutes(
        Duration.zero,
        const Duration(hours: 8),
        (at) => snap(at: at, level: 100, source: PowerSource.none),
      );
      expect(run(readings), isEmpty);
    });

    test('a long gap between readings restarts the timer', () {
      final readings = [
        ...everyTenMinutes(
          Duration.zero,
          const Duration(hours: 5),
          fullOnPower,
        ),
        // App not running for an hour; the phone may have been unplugged.
        ...everyTenMinutes(
          const Duration(hours: 6),
          const Duration(hours: 11, minutes: 50),
          fullOnPower,
        ),
      ];
      expect(run(readings), isEmpty);
      expect(
        types(run([...readings, fullOnPower(const Duration(hours: 12))])),
        {DeviceWarningType.fullChargeTooLong},
      );
    });

    test('without a tracker there is no full-charge warning', () {
      expect(
        evaluateDeviceWarnings(fullOnPower(const Duration(hours: 10))),
        isEmpty,
      );
    });
  });

  test('several warnings at once', () {
    final w = evaluateDeviceWarnings(
      snap(temperatureC: 50, health: BatteryHealth.overheat),
      config: config,
    );
    expect(types(w), {
      DeviceWarningType.batteryHot,
      DeviceWarningType.batteryHealthNotGood,
    });
  });
}
