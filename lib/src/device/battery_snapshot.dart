/// Battery state as read from Android's `ACTION_BATTERY_CHANGED` broadcast.
library;

enum BatteryChargeStatus { charging, discharging, full, notCharging, unknown }

enum PowerSource { none, ac, usb, wireless, dock, unknown }

enum BatteryHealth { good, overheat, dead, overVoltage, failure, cold, unknown }

T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

class BatterySnapshot {
  const BatterySnapshot({
    required this.timestamp,
    this.level,
    this.status = BatteryChargeStatus.unknown,
    this.source = PowerSource.unknown,
    this.health = BatteryHealth.unknown,
    this.temperatureC,
    this.voltageMv,
    this.cycleCount,
  });

  /// Parses the map sent by `BatteryReader.kt` (packages/buspilot_battery).
  factory BatterySnapshot.fromMap(
    Map<Object?, Object?> map,
    DateTime timestamp,
  ) {
    return BatterySnapshot(
      timestamp: timestamp,
      level: (map['level'] as num?)?.round(),
      status: _byName(
        BatteryChargeStatus.values,
        map['status'],
        BatteryChargeStatus.unknown,
      ),
      source: _byName(PowerSource.values, map['plugged'], PowerSource.unknown),
      health: _byName(
        BatteryHealth.values,
        map['health'],
        BatteryHealth.unknown,
      ),
      temperatureC: (map['temperatureC'] as num?)?.toDouble(),
      voltageMv: (map['voltageMv'] as num?)?.toInt(),
      cycleCount: (map['cycleCount'] as num?)?.toInt(),
    );
  }

  final DateTime timestamp;

  /// Charge level in percent (0–100), or null if the phone did not report it.
  final int? level;
  final BatteryChargeStatus status;
  final PowerSource source;
  final BatteryHealth health;
  final double? temperatureC;
  final int? voltageMv;

  /// Charge cycles; only reported on Android 14+ and not by every phone.
  final int? cycleCount;

  /// Whether external power is connected.
  bool get isPlugged =>
      source != PowerSource.none && source != PowerSource.unknown;

  /// Whether the battery is at 100 % with power connected.
  bool get isFullOnPower => isPlugged && (level ?? 0) >= 100;
}
