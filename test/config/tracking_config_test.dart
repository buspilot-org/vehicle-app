import 'dart:math';

import 'package:buspilot_vehicle/src/config/tracking_config.dart';
import 'package:buspilot_vehicle/src/tracking/position_record.dart';
import 'package:buspilot_vehicle/src/tracking/tracking_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateServerUrl', () {
    test('accepts https URLs', () {
      expect(
        validateServerUrl('https://traccar.example.org:5055', allowHttp: false),
        isNull,
      );
      expect(
        validateServerUrl(' https://example.org/osmand ', allowHttp: false),
        isNull,
      );
    });

    test('allows http only when permitted', () {
      expect(
        validateServerUrl('http://10.0.2.2:5055', allowHttp: true),
        isNull,
      );
      expect(
        validateServerUrl('http://10.0.2.2:5055', allowHttp: false),
        isNotNull,
      );
    });

    test('rejects incomplete or unsafe URLs', () {
      for (final url in [
        '',
        'traccar.example.org',
        'ftp://example.org',
        'https://user:pw@example.org',
        'https://example.org/#x',
        'https://',
      ]) {
        expect(validateServerUrl(url, allowHttp: true), isNotNull, reason: url);
      }
    });
  });

  test('validateDeviceId', () {
    expect(validateDeviceId('12345678'), isNull);
    expect(validateDeviceId('bus-01_a.b'), isNull);
    expect(validateDeviceId(''), isNotNull);
    expect(validateDeviceId('with space'), isNotNull);
    expect(validateDeviceId('a' * 65), isNotNull);
  });

  test('interval and distance ranges', () {
    expect(validateInterval(1), isNull);
    expect(validateInterval(3600), isNull);
    expect(validateInterval(0), isNotNull);
    expect(validateInterval(null), isNotNull);
    expect(validateDistanceFilter(0), isNull);
    expect(validateDistanceFilter(-1), isNotNull);
    expect(validateDistanceFilter(10001), isNotNull);
  });

  test('generateDeviceId gives 8 digits not starting with 0', () {
    final rng = Random(1);
    for (var i = 0; i < 100; i++) {
      final id = generateDeviceId(rng);
      expect(id, matches(RegExp(r'^[1-9][0-9]{7}$')));
    }
  });

  test('isValid', () {
    const ok = TrackingConfig(serverUrl: 'https://a.example', deviceId: '1');
    expect(ok.isValid(allowHttp: false), isTrue);
    expect(ok.copyWith(serverUrl: '').isValid(allowHttp: true), isFalse);
    expect(ok.copyWith(intervalSeconds: 0).isValid(allowHttp: true), isFalse);
  });

  test('TrackingStatus round-trips through an isolate message', () {
    final status = TrackingStatus(
      lastSent: PositionRecord(
        timestamp: DateTime.utc(2026),
        latitude: 1,
        longitude: 2,
        attributes: const {'ble': 'x'},
      ),
      lastSentAt: DateTime.fromMillisecondsSinceEpoch(1000),
      queueLength: 3,
      droppedCount: 1,
      error: 'offline',
    );
    // Simulate what the isolate port delivers: untyped maps.
    final message = Map<Object?, Object?>.from(status.toMessage());
    message['lastSent'] = Map<Object?, Object?>.from(
      (message['lastSent']! as Map).map(
        (k, v) => MapEntry(k, v is Map ? Map<Object?, Object?>.from(v) : v),
      ),
    );
    final back = TrackingStatus.fromMessage(message)!;
    expect(back.lastSent, status.lastSent);
    expect(back.lastSentAt, status.lastSentAt);
    expect(back.queueLength, 3);
    expect(back.droppedCount, 1);
    expect(back.error, 'offline');
    expect(TrackingStatus.fromMessage('other'), isNull);
  });
}
