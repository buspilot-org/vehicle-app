import 'dart:math';

import '../ble/tag_filter.dart';

/// Location accuracy preset, passed on to the Traccar Client SDK.
enum TrackingAccuracy {
  /// GPS for every fix; the SDK then ignores interval and distance and
  /// sends every fix (about one per second).
  highest,

  /// GPS, with the interval / distance settings. Default for buses.
  high,

  /// Wi-Fi and cell towers, roughly 100 m.
  medium,

  /// Cell towers, roughly 1 km.
  low,
}

/// Settings of the vehicle app: positions (Traccar Client SDK), the vehicle
/// event channel to the Buspilot engine and the operator's tag IDs.
///
/// Holds no personal data: the device ID identifies the bus phone in Traccar,
/// not a person, and is generated at random (never derived from IMEI,
/// Android ID or similar hardware identifiers). The vehicle token is a
/// secret; it is never shown in [toString].
class TrackingConfig {
  const TrackingConfig({
    required this.serverUrl,
    required this.deviceId,
    this.intervalSeconds = defaultIntervalSeconds,
    this.distanceFilterMeters = defaultDistanceFilterMeters,
    this.accuracy = defaultAccuracy,
    this.stopDetection = true,
    this.stopTimeoutSeconds = defaultStopTimeoutSeconds,
    this.heartbeatSeconds = defaultHeartbeatSeconds,
    this.engineUrl = '',
    this.vehicleToken = '',
    this.iBeaconUuids = const [],
    this.eddystoneNamespaces = const [],
  });

  static const defaultIntervalSeconds = 10;
  static const defaultDistanceFilterMeters = 0;
  static const defaultAccuracy = TrackingAccuracy.high;

  /// Longer than a stop at a bus stop or a red light, so GPS only pauses
  /// when the bus is really parked.
  static const defaultStopTimeoutSeconds = 300;

  /// One position every 15 minutes while parked, so Traccar still sees the
  /// phone. Each heartbeat costs one short GPS fix.
  static const defaultHeartbeatSeconds = 900;

  static const minIntervalSeconds = 1;
  static const maxIntervalSeconds = 3600;
  static const maxDistanceFilterMeters = 10000;
  static const maxDeviceIdLength = 64;
  static const minStopTimeoutSeconds = 30;
  static const maxStopTimeoutSeconds = 3600;
  static const minHeartbeatSeconds = 60;
  static const maxHeartbeatSeconds = 86400;
  static const maxVehicleTokenLength = 512;

  /// Traccar OsmAnd endpoint, for example `https://traccar.example.org:5055`.
  final String serverUrl;

  /// Traccar device identifier ("unique ID" in Traccar). Also sent with the
  /// vehicle events, so the engine can join them with positions.
  final String deviceId;

  /// Minimum time between two sent positions while moving.
  final int intervalSeconds;

  /// 0: send a position every [intervalSeconds]. More than 0: send after the
  /// bus moved this far; the SDK then ignores [intervalSeconds] (with GPS this
  /// can mean one position every one or two seconds at speed).
  final int distanceFilterMeters;

  final TrackingAccuracy accuracy;

  /// Pause GPS while the bus is parked (activity recognition and a geofence
  /// detect when it moves again).
  final bool stopDetection;

  /// How long the phone must be still before GPS pauses.
  final int stopTimeoutSeconds;

  /// While paused, send one position this often. 0 = none.
  final int heartbeatSeconds;

  /// Base URL of the Buspilot engine. Empty: vehicle events are kept on the
  /// phone and not sent.
  final String engineUrl;

  /// Bearer token for the engine, issued per vehicle by the operator.
  final String vehicleToken;

  /// The operator's iBeacon proximity UUIDs.
  final List<String> iBeaconUuids;

  /// The operator's Eddystone-UID namespaces (20 hex digits).
  final List<String> eddystoneNamespaces;

  /// Whether the settings are complete and valid for tracking.
  ///
  /// [allowHttp] permits plain `http://` URLs (debug builds only).
  bool isValid({required bool allowHttp}) =>
      validateServerUrl(serverUrl, allowHttp: allowHttp) == null &&
      validateDeviceId(deviceId) == null &&
      validateInterval(intervalSeconds) == null &&
      validateDistanceFilter(distanceFilterMeters) == null &&
      validateStopTimeout(stopTimeoutSeconds) == null &&
      validateHeartbeat(heartbeatSeconds) == null &&
      validateEngineUrl(engineUrl, allowHttp: allowHttp) == null &&
      validateVehicleToken(vehicleToken) == null &&
      validateTagIds(iBeaconUuids, eddystoneNamespaces) == null;

  /// Events are sent only with an engine URL; the token may be empty while
  /// the engine does not check it yet.
  bool get engineConfigured => engineUrl.trim().isNotEmpty;

  /// The operator's tags. Throws [FormatException] for invalid IDs (checked
  /// by [isValid]). Empty when no IDs are configured: then nothing is
  /// scanned and no tag events are recorded.
  TagFilter get tagFilter => TagFilter(
    iBeaconUuids: iBeaconUuids,
    eddystoneNamespaces: eddystoneNamespaces,
  );

  TrackingConfig copyWith({
    String? serverUrl,
    String? deviceId,
    int? intervalSeconds,
    int? distanceFilterMeters,
    TrackingAccuracy? accuracy,
    bool? stopDetection,
    int? stopTimeoutSeconds,
    int? heartbeatSeconds,
    String? engineUrl,
    String? vehicleToken,
    List<String>? iBeaconUuids,
    List<String>? eddystoneNamespaces,
  }) => TrackingConfig(
    serverUrl: serverUrl ?? this.serverUrl,
    deviceId: deviceId ?? this.deviceId,
    intervalSeconds: intervalSeconds ?? this.intervalSeconds,
    distanceFilterMeters: distanceFilterMeters ?? this.distanceFilterMeters,
    accuracy: accuracy ?? this.accuracy,
    stopDetection: stopDetection ?? this.stopDetection,
    stopTimeoutSeconds: stopTimeoutSeconds ?? this.stopTimeoutSeconds,
    heartbeatSeconds: heartbeatSeconds ?? this.heartbeatSeconds,
    engineUrl: engineUrl ?? this.engineUrl,
    vehicleToken: vehicleToken ?? this.vehicleToken,
    iBeaconUuids: iBeaconUuids ?? this.iBeaconUuids,
    eddystoneNamespaces: eddystoneNamespaces ?? this.eddystoneNamespaces,
  );

  @override
  bool operator ==(Object other) =>
      other is TrackingConfig &&
      other.serverUrl == serverUrl &&
      other.deviceId == deviceId &&
      other.intervalSeconds == intervalSeconds &&
      other.distanceFilterMeters == distanceFilterMeters &&
      other.accuracy == accuracy &&
      other.stopDetection == stopDetection &&
      other.stopTimeoutSeconds == stopTimeoutSeconds &&
      other.heartbeatSeconds == heartbeatSeconds &&
      other.engineUrl == engineUrl &&
      other.vehicleToken == vehicleToken &&
      _listEquals(other.iBeaconUuids, iBeaconUuids) &&
      _listEquals(other.eddystoneNamespaces, eddystoneNamespaces);

  @override
  int get hashCode => Object.hash(
    serverUrl,
    deviceId,
    intervalSeconds,
    distanceFilterMeters,
    accuracy,
    stopDetection,
    stopTimeoutSeconds,
    heartbeatSeconds,
    engineUrl,
    vehicleToken,
    Object.hashAll(iBeaconUuids),
    Object.hashAll(eddystoneNamespaces),
  );

  @override
  String toString() =>
      'TrackingConfig(server: $serverUrl, device: $deviceId, '
      'engine: ${engineConfigured ? engineUrl : '-'}, '
      'token: ${vehicleToken.isEmpty ? 'none' : 'set'})';
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Returns an error message, or null if [value] is a usable server URL.
String? validateServerUrl(String value, {required bool allowHttp}) {
  final text = value.trim();
  if (text.isEmpty) return 'Enter the Traccar server URL.';
  return _validateUrl(
    text,
    allowHttp: allowHttp,
    example: 'https://traccar.example.org:5055',
  );
}

/// Returns an error message, or null if [value] is empty or a usable engine
/// URL.
String? validateEngineUrl(String value, {required bool allowHttp}) {
  final text = value.trim();
  if (text.isEmpty) return null;
  final error = _validateUrl(
    text,
    allowHttp: allowHttp,
    example: 'https://engine.example.org',
  );
  if (error != null) return error;
  if (Uri.parse(text).hasQuery) return 'Remove the ? part from the URL.';
  return null;
}

String? _validateUrl(
  String text, {
  required bool allowHttp,
  required String example,
}) {
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return 'Enter a full URL, for example $example';
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

String? validateStopTimeout(int? value) {
  if (value == null ||
      value < TrackingConfig.minStopTimeoutSeconds ||
      value > TrackingConfig.maxStopTimeoutSeconds) {
    return 'Enter ${TrackingConfig.minStopTimeoutSeconds} to '
        '${TrackingConfig.maxStopTimeoutSeconds} seconds.';
  }
  return null;
}

String? validateHeartbeat(int? value) {
  if (value == null) return 'Enter a number of seconds (0 = off).';
  if (value == 0) return null;
  if (value < TrackingConfig.minHeartbeatSeconds ||
      value > TrackingConfig.maxHeartbeatSeconds) {
    return 'Enter 0 (off) or ${TrackingConfig.minHeartbeatSeconds} to '
        '${TrackingConfig.maxHeartbeatSeconds} seconds.';
  }
  return null;
}

String? validateVehicleToken(String value) {
  if (value.length > TrackingConfig.maxVehicleTokenLength) {
    return 'Use at most ${TrackingConfig.maxVehicleTokenLength} characters.';
  }
  // Header values must be visible ASCII; spaces would break "Bearer <token>".
  if (!RegExp(r'^[\x21-\x7E]*$').hasMatch(value)) {
    return 'Use only letters, digits and symbols, without spaces.';
  }
  return null;
}

/// Returns an error message, or null if all tag IDs are valid.
String? validateTagIds(List<String> iBeaconUuids, List<String> namespaces) {
  for (final u in iBeaconUuids) {
    try {
      TagFilter(iBeaconUuids: [u]);
    } on FormatException {
      return 'Not an iBeacon UUID: $u';
    }
  }
  for (final n in namespaces) {
    try {
      TagFilter(eddystoneNamespaces: [n]);
    } on FormatException {
      return 'Not an Eddystone namespace (20 hex digits): $n';
    }
  }
  return null;
}

/// Splits a settings text field into IDs (separated by commas, spaces or new
/// lines).
List<String> splitIds(String text) => [
  for (final part in text.split(RegExp(r'[\s,;]+')))
    if (part.trim().isNotEmpty) part.trim(),
];

/// A random 8-digit device ID, like the IDs Traccar Client generates.
String generateDeviceId([Random? random]) {
  final rng = random ?? Random.secure();
  // First digit 1-9 so the ID keeps 8 digits if someone treats it as a number.
  return '${rng.nextInt(9) + 1}'
      '${List.generate(7, (_) => rng.nextInt(10)).join()}';
}
