/// One location fix of the bus, as it is queued and sent to Traccar.
class PositionRecord {
  PositionRecord({
    required DateTime timestamp,
    required this.latitude,
    required this.longitude,
    this.speed,
    this.bearing,
    this.altitude,
    this.accuracy,
    this.battery,
    this.deviceId,
    Map<String, String> attributes = const {},
  }) : timestamp = timestamp.toUtc(),
       attributes = Map.unmodifiable(attributes);

  /// Time of the fix (UTC).
  final DateTime timestamp;

  /// Degrees, WGS 84.
  final double latitude;
  final double longitude;

  /// Metres per second, as reported by Android.
  final double? speed;

  /// Degrees clockwise from north, 0-360.
  final double? bearing;

  /// Metres above the WGS 84 ellipsoid.
  final double? altitude;

  /// Horizontal accuracy radius in metres.
  final double? accuracy;

  /// Phone battery level in percent, 0-100.
  final int? battery;

  /// Traccar device ID this position was recorded under. Stored with the
  /// queued position so that a backlog is still sent under the right ID
  /// after the device ID was changed in the settings.
  final String? deviceId;

  /// Extra OsmAnd query parameters, stored by Traccar as position attributes
  /// (for example BLE tags seen at this position). Keys must not clash with
  /// the standard OsmAnd parameters, see `reservedOsmAndKeys`.
  final Map<String, String> attributes;

  PositionRecord copyWith({Map<String, String>? attributes}) => PositionRecord(
    timestamp: timestamp,
    latitude: latitude,
    longitude: longitude,
    speed: speed,
    bearing: bearing,
    altitude: altitude,
    accuracy: accuracy,
    battery: battery,
    deviceId: deviceId,
    attributes: attributes ?? this.attributes,
  );

  Map<String, Object?> toJson() => {
    't': timestamp.millisecondsSinceEpoch,
    'lat': latitude,
    'lon': longitude,
    if (speed != null) 'spd': speed,
    if (bearing != null) 'brg': bearing,
    if (altitude != null) 'alt': altitude,
    if (accuracy != null) 'acc': accuracy,
    if (battery != null) 'bat': battery,
    if (deviceId != null) 'dev': deviceId,
    if (attributes.isNotEmpty) 'attr': attributes,
  };

  /// Throws [FormatException] if [json] is not a valid record.
  factory PositionRecord.fromJson(Map<String, Object?> json) {
    try {
      final attr = json['attr'] as Map<String, Object?>?;
      return PositionRecord(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          json['t']! as int,
          isUtc: true,
        ),
        latitude: (json['lat']! as num).toDouble(),
        longitude: (json['lon']! as num).toDouble(),
        speed: (json['spd'] as num?)?.toDouble(),
        bearing: (json['brg'] as num?)?.toDouble(),
        altitude: (json['alt'] as num?)?.toDouble(),
        accuracy: (json['acc'] as num?)?.toDouble(),
        battery: json['bat'] as int?,
        deviceId: json['dev'] as String?,
        attributes: attr == null
            ? const {}
            : attr.map((k, v) => MapEntry(k, v! as String)),
      );
    } on TypeError catch (e) {
      throw FormatException('Invalid position record: $e');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PositionRecord &&
      other.timestamp == timestamp &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.speed == speed &&
      other.bearing == bearing &&
      other.altitude == altitude &&
      other.accuracy == accuracy &&
      other.battery == battery &&
      other.deviceId == deviceId &&
      _mapEquals(other.attributes, attributes);

  @override
  int get hashCode => Object.hash(
    timestamp,
    latitude,
    longitude,
    speed,
    bearing,
    altitude,
    accuracy,
    battery,
    deviceId,
    Object.hashAllUnordered(
      attributes.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'PositionRecord(${timestamp.toIso8601String()}, $latitude, $longitude)';
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
