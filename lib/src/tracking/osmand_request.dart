import 'position_record.dart';

/// Query parameters of the OsmAnd protocol that Traccar interprets itself.
/// Extra attributes on a [PositionRecord] must not use these keys.
const reservedOsmAndKeys = {
  'id',
  'deviceid',
  'lat',
  'lon',
  'timestamp',
  'speed',
  'bearing',
  'heading',
  'altitude',
  'accuracy',
  'batt',
};

/// Thrown for an extra attribute that cannot be sent as an OsmAnd parameter.
class InvalidOsmAndAttribute implements Exception {
  InvalidOsmAndAttribute(this.key);
  final String key;
  @override
  String toString() => 'Empty or reserved OsmAnd parameter name: "$key"';
}

/// Throws [InvalidOsmAndAttribute] if a key in [attributes] is empty or
/// clashes with a standard OsmAnd parameter.
void validateOsmAndAttributes(Map<String, String> attributes) {
  for (final key in attributes.keys) {
    if (key.isEmpty || reservedOsmAndKeys.contains(key.toLowerCase())) {
      throw InvalidOsmAndAttribute(key);
    }
  }
}

/// Knots per metre per second. Traccar's OsmAnd decoder reads `speed` in
/// knots, like Traccar Client sends it.
const _knotsPerMps = 1.943844;

/// Builds the OsmAnd request URI for one position.
///
/// The request has the same shape as Traccar Client's: all values go in the
/// query string (`?id=...&lat=...&lon=...`). Query parameters already in
/// [server] are kept; position parameters win on a clash.
///
/// Throws [InvalidOsmAndAttribute] if an extra attribute uses an empty or
/// reserved key.
Uri buildOsmAndUri({
  required Uri server,
  required String deviceId,
  required PositionRecord position,
}) {
  final params = <String, String>{
    ...server.queryParameters,
    'id': deviceId,
    'timestamp': (position.timestamp.millisecondsSinceEpoch ~/ 1000).toString(),
    'lat': position.latitude.toStringAsFixed(7),
    'lon': position.longitude.toStringAsFixed(7),
    if (position.speed != null)
      'speed': (position.speed! * _knotsPerMps).toStringAsFixed(2),
    if (position.bearing != null)
      'bearing': position.bearing!.toStringAsFixed(1),
    if (position.altitude != null)
      'altitude': position.altitude!.toStringAsFixed(1),
    if (position.accuracy != null)
      'accuracy': position.accuracy!.toStringAsFixed(1),
    if (position.battery != null) 'batt': position.battery!.toString(),
  };
  validateOsmAndAttributes(position.attributes);
  params.addAll(position.attributes);
  return server.replace(
    path: server.path.isEmpty ? '/' : server.path,
    queryParameters: params,
  );
}
