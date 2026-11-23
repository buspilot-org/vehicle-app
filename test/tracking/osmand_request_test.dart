import 'package:buspilot_vehicle/src/tracking/osmand_request.dart';
import 'package:buspilot_vehicle/src/tracking/position_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final server = Uri.parse('https://traccar.example.org:5055');
  final time = DateTime.utc(2026, 11, 23, 3, 4, 5);

  PositionRecord position({
    double? speed = 10,
    Map<String, String> attributes = const {},
  }) => PositionRecord(
    timestamp: time,
    latitude: 35.6812362,
    longitude: 139.7671248,
    speed: speed,
    bearing: 90.25,
    altitude: 40.04,
    accuracy: 4.56,
    battery: 87,
    attributes: attributes,
  );

  test('builds all standard OsmAnd parameters', () {
    final uri = buildOsmAndUri(
      server: server,
      deviceId: '12345678',
      position: position(),
    );
    expect(uri.scheme, 'https');
    expect(uri.host, 'traccar.example.org');
    expect(uri.port, 5055);
    expect(uri.path, '/');
    expect(uri.queryParameters, {
      'id': '12345678',
      'timestamp': '${time.millisecondsSinceEpoch ~/ 1000}',
      'lat': '35.6812362',
      'lon': '139.7671248',
      'speed': '19.44', // 10 m/s in knots
      'bearing': '90.3',
      'altitude': '40.0',
      'accuracy': '4.6',
      'batt': '87',
    });
  });

  test('timestamp is UTC seconds even for local DateTime input', () {
    final local = DateTime(2026, 11, 23, 12, 4, 5);
    final uri = buildOsmAndUri(
      server: server,
      deviceId: 'a',
      position: PositionRecord(timestamp: local, latitude: 0, longitude: 0),
    );
    expect(
      uri.queryParameters['timestamp'],
      '${local.millisecondsSinceEpoch ~/ 1000}',
    );
  });

  test('omits optional values that are unknown', () {
    final uri = buildOsmAndUri(
      server: server,
      deviceId: 'bus-1',
      position: PositionRecord(timestamp: time, latitude: 1, longitude: 2),
    );
    expect(
      uri.queryParameters.keys,
      unorderedEquals(['id', 'timestamp', 'lat', 'lon']),
    );
  });

  test('never uses exponent notation for tiny coordinates', () {
    final uri = buildOsmAndUri(
      server: server,
      deviceId: 'a',
      position: PositionRecord(
        timestamp: time,
        latitude: 0.00000001,
        longitude: -0.0000001,
      ),
    );
    expect(uri.queryParameters['lat'], '0.0000000');
    expect(uri.queryParameters['lon'], '-0.0000001');
  });

  test('adds extra attributes as query parameters', () {
    final uri = buildOsmAndUri(
      server: server,
      deviceId: 'a',
      position: position(attributes: {'ble': 'tag1,tag2', 'trip': '7'}),
    );
    expect(uri.queryParameters['ble'], 'tag1,tag2');
    expect(uri.queryParameters['trip'], '7');
    expect(uri.toString(), contains('ble=tag1%2Ctag2'));
  });

  test('rejects attributes that clash with OsmAnd parameters', () {
    for (final key in ['lat', 'ID', 'timestamp', 'batt', '']) {
      expect(
        () => buildOsmAndUri(
          server: server,
          deviceId: 'a',
          position: position(attributes: {key: 'x'}),
        ),
        throwsA(isA<InvalidOsmAndAttribute>()),
        reason: key,
      );
    }
  });

  test('uses the device ID it is given', () {
    final uri = buildOsmAndUri(
      server: server,
      deviceId: 'bus-2',
      position: position(),
    );
    expect(uri.queryParameters['id'], 'bus-2');
  });

  test('keeps path and query of the server URL', () {
    final uri = buildOsmAndUri(
      server: Uri.parse('https://example.org/osmand?key=abc&id=wrong'),
      deviceId: 'bus-1',
      position: position(),
    );
    expect(uri.path, '/osmand');
    expect(uri.queryParameters['key'], 'abc');
    expect(uri.queryParameters['id'], 'bus-1');
  });

  test('encodes device IDs safely', () {
    final uri = buildOsmAndUri(
      server: server,
      deviceId: 'a&lat=0',
      position: position(),
    );
    expect(uri.queryParameters['id'], 'a&lat=0');
    expect(uri.queryParameters['lat'], '35.6812362');
  });
}
