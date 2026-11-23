import 'dart:math';

/// Settings for location tracking.
///
/// Holds no personal data: the device ID identifies the bus phone in Traccar,
/// not a person, and is generated at random (never derived from IMEI,
/// Android ID or similar hardware identifiers).
class TrackingConfig {
  const TrackingConfig({
    required this.serverUrl,
    required this.deviceId,
    this.intervalSeconds = defaultIntervalSeconds,
    this.distanceFilterMeters = defaultDistanceFilterMeters,
  });

  static const defaultIntervalSeconds = 10;
  static const defaultDistanceFilterMeters = 0;

  static const minIntervalSeconds = 1;
  static const maxIntervalSeconds = 3600;
  static const maxDistanceFilterMeters = 10000;
  static const maxDeviceIdLength = 64;

  /// Base URL of the Traccar OsmAnd endpoint, for example
  /// `https://traccar.example.org:5055`.
  final String serverUrl;

  /// Traccar device identifier ("unique ID" in Traccar).
  final String deviceId;

  /// How often the phone asks for a location fix.
  final int intervalSeconds;

  /// Minimum distance in metres between two sent positions while the bus is
  /// moving. 0 sends every fix.
  final int distanceFilterMeters;

  /// Whether the settings are complete and valid for tracking.
  ///
  /// [allowHttp] permits plain `http://` server URLs (debug builds only).
  bool isValid({required bool allowHttp}) =>
      validateServerUrl(serverUrl, allowHttp: allowHttp) == null &&
      validateDeviceId(deviceId) == null &&
      validateInterval(intervalSeconds) == null &&
      validateDistanceFilter(distanceFilterMeters) == null;

  Uri get serverUri => Uri.parse(serverUrl.trim());

  TrackingConfig copyWith({
    String? serverUrl,
    String? deviceId,
    int? intervalSeconds,
    int? distanceFilterMeters,
  }) => TrackingConfig(
    serverUrl: serverUrl ?? this.serverUrl,
    deviceId: deviceId ?? this.deviceId,
    intervalSeconds: intervalSeconds ?? this.intervalSeconds,
    distanceFilterMeters: distanceFilterMeters ?? this.distanceFilterMeters,
  );

  @override
  bool operator ==(Object other) =>
      other is TrackingConfig &&
      other.serverUrl == serverUrl &&
      other.deviceId == deviceId &&
      other.intervalSeconds == intervalSeconds &&
      other.distanceFilterMeters == distanceFilterMeters;

  @override
  int get hashCode =>
      Object.hash(serverUrl, deviceId, intervalSeconds, distanceFilterMeters);
}

/// Returns an error message, or null if [value] is a usable server URL.
String? validateServerUrl(String value, {required bool allowHttp}) {
  final text = value.trim();
  if (text.isEmpty) return 'Enter the Traccar server URL.';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'Enter a full URL, for example https://traccar.example.org:5055';
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' && !allowHttp) {
    return 'Use https://. Plain http:// is only allowed in debug builds.';
  }
  if (scheme != 'https' && scheme != 'http') {
    return 'The URL must start with https://';
  }
  if (uri.userInfo.isNotEmpty) {
    return 'Do not put a user name or password in the URL.';
  }
  if (uri.hasFragment) return 'Remove the # part from the URL.';
  return null;
}

final _deviceIdPattern = RegExp(r'^[A-Za-z0-9._-]+$');

/// Returns an error message, or null if [value] is a usable device ID.
String? validateDeviceId(String value) {
  if (value.isEmpty) return 'Enter a device ID.';
  if (value.length > TrackingConfig.maxDeviceIdLength) {
    return 'Use at most ${TrackingConfig.maxDeviceIdLength} characters.';
  }
  if (!_deviceIdPattern.hasMatch(value)) {
    return 'Use only letters, digits, dot, dash and underscore.';
  }
  return null;
}

String? validateInterval(int? value) {
  if (value == null ||
      value < TrackingConfig.minIntervalSeconds ||
      value > TrackingConfig.maxIntervalSeconds) {
    return 'Enter ${TrackingConfig.minIntervalSeconds} to '
        '${TrackingConfig.maxIntervalSeconds} seconds.';
  }
  return null;
}

String? validateDistanceFilter(int? value) {
  if (value == null ||
      value < 0 ||
      value > TrackingConfig.maxDistanceFilterMeters) {
    return 'Enter 0 to ${TrackingConfig.maxDistanceFilterMeters} metres.';
  }
  return null;
}

/// A random 8-digit device ID, like the IDs Traccar Client generates.
String generateDeviceId([Random? random]) {
  final rng = random ?? Random.secure();
  // First digit 1-9 so the ID keeps 8 digits if someone treats it as a number.
  return '${rng.nextInt(9) + 1}'
      '${List.generate(7, (_) => rng.nextInt(10)).join()}';
}
