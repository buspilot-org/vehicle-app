import 'package:shared_preferences/shared_preferences.dart';

import 'tracking_config.dart';

/// Stores [TrackingConfig] on the device with shared_preferences (app-private
/// storage).
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
  static const _kServiceVersion = 'tracking.serviceVersion';
  static const _kAccuracy = 'tracking.accuracy';
  static const _kStopDetection = 'tracking.stopDetection';
  static const _kStopTimeout = 'tracking.stopTimeoutSeconds';
  static const _kHeartbeat = 'tracking.heartbeatSeconds';
  static const _kEngineUrl = 'events.engineUrl';
  // Stored like the other settings (app-private storage). A configured
  // secret for the demo; move to the Android Keystore once tokens are
  // issued per vehicle by the admin console.
  static const _kVehicleToken = 'events.vehicleToken';
  static const _kIBeaconUuids = 'ble.iBeaconUuids';
  static const _kEddystoneNamespaces = 'ble.eddystoneNamespaces';

  /// Loads the settings. On first use a random device ID is generated and
  /// saved, so it stays the same across restarts.
  Future<TrackingConfig> load() async {
    var deviceId = await _prefs.getString(_kDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = generateDeviceId();
      await _prefs.setString(_kDeviceId, deviceId);
    }
    final accuracy = await _prefs.getString(_kAccuracy);
    return TrackingConfig(
      serverUrl: await _prefs.getString(_kServerUrl) ?? '',
      deviceId: deviceId,
      intervalSeconds:
          await _prefs.getInt(_kInterval) ??
          TrackingConfig.defaultIntervalSeconds,
      distanceFilterMeters:
          await _prefs.getInt(_kDistance) ??
          TrackingConfig.defaultDistanceFilterMeters,
      accuracy: TrackingAccuracy.values.firstWhere(
        (a) => a.name == accuracy,
        orElse: () => TrackingConfig.defaultAccuracy,
      ),
      stopDetection: await _prefs.getBool(_kStopDetection) ?? true,
      stopTimeoutSeconds:
          await _prefs.getInt(_kStopTimeout) ??
          TrackingConfig.defaultStopTimeoutSeconds,
      heartbeatSeconds:
          await _prefs.getInt(_kHeartbeat) ??
          TrackingConfig.defaultHeartbeatSeconds,
      engineUrl: await _prefs.getString(_kEngineUrl) ?? '',
      vehicleToken: await _prefs.getString(_kVehicleToken) ?? '',
      iBeaconUuids: await _prefs.getStringList(_kIBeaconUuids) ?? const [],
      eddystoneNamespaces:
          await _prefs.getStringList(_kEddystoneNamespaces) ?? const [],
    );
  }

  Future<void> save(TrackingConfig config) async {
    await _prefs.setString(_kServerUrl, config.serverUrl.trim());
    await _prefs.setString(_kDeviceId, config.deviceId);
    await _prefs.setInt(_kInterval, config.intervalSeconds);
    await _prefs.setInt(_kDistance, config.distanceFilterMeters);
    await _prefs.setString(_kAccuracy, config.accuracy.name);
    await _prefs.setBool(_kStopDetection, config.stopDetection);
    await _prefs.setInt(_kStopTimeout, config.stopTimeoutSeconds);
    await _prefs.setInt(_kHeartbeat, config.heartbeatSeconds);
    await _prefs.setString(_kEngineUrl, config.engineUrl.trim());
    await _prefs.setString(_kVehicleToken, config.vehicleToken);
    await _prefs.setStringList(_kIBeaconUuids, config.iBeaconUuids);
    await _prefs.setStringList(
      _kEddystoneNamespaces,
      config.eddystoneNamespaces,
    );
  }

  /// Whether the user switched tracking on (remembered across app restarts).
  Future<bool> isTrackingEnabled() async =>
      await _prefs.getBool(_kEnabled) ?? false;

  Future<void> setTrackingEnabled(bool enabled) =>
      _prefs.setBool(_kEnabled, enabled);

  /// Version of the background service setup that was last started (see
  /// `TrackingController`); null before this was recorded.
  Future<int?> serviceVersion() => _prefs.getInt(_kServiceVersion);

  Future<void> setServiceVersion(int version) =>
      _prefs.setInt(_kServiceVersion, version);
}
