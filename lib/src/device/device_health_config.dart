/// Thresholds for the device health warnings.
class DeviceHealthConfig {
  const DeviceHealthConfig({
    this.hotThresholdC = 45.0,
    this.fullChargeWarnAfter = const Duration(hours: 6),
    this.maxSampleGap = const Duration(minutes: 30),
    this.pollInterval = const Duration(minutes: 1),
  });

  /// Battery temperature at or above which the battery counts as too hot.
  /// Lithium-ion cells age fast above about 45 °C, especially while charging.
  final double hotThresholdC;

  /// How long the battery may sit at 100 % on external power before warning.
  /// Phones that support a charging limit (for example 80–85 %) never reach
  /// 100 %, so this warning also tells the operator to turn the limit on.
  final Duration fullChargeWarnAfter;

  /// If two battery readings are further apart than this (app not running,
  /// phone off), the "full since" time starts again, because the battery may
  /// have been unplugged in between.
  final Duration maxSampleGap;

  /// How often the status screen reads the battery.
  final Duration pollInterval;
}
