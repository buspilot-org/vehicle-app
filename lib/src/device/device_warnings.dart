import 'battery_snapshot.dart';
import 'device_health_config.dart';

enum DeviceWarningType {
  /// Battery temperature at or above [DeviceHealthConfig.hotThresholdC].
  batteryHot,

  /// At 100 % on power for longer than [DeviceHealthConfig.fullChargeWarnAfter].
  fullChargeTooLong,

  /// Android reports a battery health other than "good".
  batteryHealthNotGood,
}

class DeviceWarning {
  const DeviceWarning(this.type, this.message);

  final DeviceWarningType type;

  /// Short English text for the status screen.
  final String message;

  /// Stable code to send to the server later.
  String get code => type.name;

  @override
  String toString() => 'DeviceWarning($code: $message)';
}

/// Remembers since when the battery has been at 100 % on external power.
class FullChargeTracker {
  FullChargeTracker({this.config = const DeviceHealthConfig()});

  final DeviceHealthConfig config;
  DateTime? _fullSince;
  DateTime? _lastSample;

  /// Start of the current "100 % on power" period, or null if not full.
  DateTime? get fullSince => _fullSince;

  void update(BatterySnapshot snapshot) {
    final now = snapshot.timestamp;
    final last = _lastSample;
    _lastSample = now;
    if (!snapshot.isFullOnPower) {
      _fullSince = null;
      return;
    }
    final gapTooLong =
        last == null || now.difference(last) > config.maxSampleGap;
    if (_fullSince == null || gapTooLong) {
      _fullSince = now;
    }
  }
}

/// Applies the warning rules to one battery reading.
///
/// [fullSince] comes from a [FullChargeTracker] fed with the same readings.
List<DeviceWarning> evaluateDeviceWarnings(
  BatterySnapshot snapshot, {
  DeviceHealthConfig config = const DeviceHealthConfig(),
  DateTime? fullSince,
}) {
  final warnings = <DeviceWarning>[];

  final temp = snapshot.temperatureC;
  if (temp != null && temp >= config.hotThresholdC) {
    warnings.add(
      DeviceWarning(
        DeviceWarningType.batteryHot,
        'Battery is ${temp.toStringAsFixed(1)} °C '
        '(limit ${config.hotThresholdC.toStringAsFixed(0)} °C). '
        'Keep the phone out of direct sun and away from heater vents.',
      ),
    );
  }

  if (snapshot.isFullOnPower && fullSince != null) {
    final duration = snapshot.timestamp.difference(fullSince);
    if (duration >= config.fullChargeWarnAfter) {
      warnings.add(
        DeviceWarning(
          DeviceWarningType.fullChargeTooLong,
          'Battery has been at 100 % on power for ${_formatDuration(duration)}. '
          'Turn on the charging limit, or power the phone only while the engine runs.',
        ),
      );
    }
  }

  final health = snapshot.health;
  if (health != BatteryHealth.good && health != BatteryHealth.unknown) {
    warnings.add(
      DeviceWarning(
        DeviceWarningType.batteryHealthNotGood,
        'Android reports battery health "${health.name}". '
        'Check the phone and plan to replace it.',
      ),
    );
  }

  return warnings;
}

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  return hours > 0 ? '${hours}h ${minutes}min' : '${minutes}min';
}
