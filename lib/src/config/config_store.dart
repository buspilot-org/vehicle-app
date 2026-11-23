import 'package:shared_preferences/shared_preferences.dart';

import 'tracking_config.dart';

/// Stores [TrackingConfig] on the device with shared_preferences.
///
/// Uses [SharedPreferencesAsync] (no in-memory cache) because the settings are
/// read both by the UI and by the foreground service, which runs in its own
/// isolate.
class ConfigStore {
  ConfigStore([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const _kServerUrl = 'tracking.serverUrl';
  static const _kDeviceId = 'tracking.deviceId';
  static const _kInterval = 'tracking.intervalSeconds';
  static const _kDistance = 'tracking.distanceFilterMeters';
  static const _kEnabled = 'tracking.enabled';

  /// Loads the settings. On first use a random device ID is generated and
  /// saved, so it stays the same across restarts.
  Future<TrackingConfig> load() async {
    var deviceId = await _prefs.getString(_kDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = generateDeviceId();
      await _prefs.setString(_kDeviceId, deviceId);
    }
    return TrackingConfig(
      serverUrl: await _prefs.getString(_kServerUrl) ?? '',
      deviceId: deviceId,
      intervalSeconds:
          await _prefs.getInt(_kInterval) ??
          TrackingConfig.defaultIntervalSeconds,
      distanceFilterMeters:
          await _prefs.getInt(_kDistance) ??
          TrackingConfig.defaultDistanceFilterMeters,
    );
  }

  Future<void> save(TrackingConfig config) async {
    await _prefs.setString(_kServerUrl, config.serverUrl.trim());
    await _prefs.setString(_kDeviceId, config.deviceId);
    await _prefs.setInt(_kInterval, config.intervalSeconds);
    await _prefs.setInt(_kDistance, config.distanceFilterMeters);
  }

  /// Whether the user switched tracking on (remembered across app restarts).
  Future<bool> isTrackingEnabled() async =>
      await _prefs.getBool(_kEnabled) ?? false;

  Future<void> setTrackingEnabled(bool enabled) =>
      _prefs.setBool(_kEnabled, enabled);
}
