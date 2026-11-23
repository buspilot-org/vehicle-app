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

/// Knots per metre per second. Traccar's OsmAnd decoder reads `speed` in
/// knots, like Traccar Client sends it.
const _knotsPerMps = 1.943844;

/// Builds the OsmAnd request URI for one position.
///
/// The request has the same shape as Traccar Client's: all values go in the
/// query string (`?id=...&lat=...&lon=...`). Query parameters already in
/// [server] are kept; position parameters win on a clash.
///
/// Throws [ArgumentError] if an extra attribute uses an empty or reserved key.
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
  for (final entry in position.attributes.entries) {
    final key = entry.key;
    if (key.isEmpty || reservedOsmAndKeys.contains(key.toLowerCase())) {
      throw ArgumentError.value(
        key,
        'attributes',
        'Empty or reserved OsmAnd parameter name',
      );
    }
    params[key] = entry.value;
  }
  return server.replace(
    path: server.path.isEmpty ? '/' : server.path,
    queryParameters: params,
  );
}
