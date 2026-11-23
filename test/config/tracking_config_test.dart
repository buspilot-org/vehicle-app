import 'dart:math';

import 'package:buspilot_vehicle/src/config/tracking_config.dart';
import 'package:buspilot_vehicle/src/tracking/companion_status.dart';
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

  test('new settings validators', () {
    expect(validateStopTimeout(30), isNull);
    expect(validateStopTimeout(29), isNotNull);
    expect(validateHeartbeat(0), isNull);
    expect(validateHeartbeat(60), isNull);
    expect(validateHeartbeat(59), isNotNull);
    expect(validateHeartbeat(null), isNotNull);
    expect(validateEngineUrl('', allowHttp: false), isNull);
    expect(
      validateEngineUrl('https://e.example/api', allowHttp: false),
      isNull,
    );
    expect(validateEngineUrl('http://e.example', allowHttp: false), isNotNull);
    expect(
      validateEngineUrl('https://e.example/?a=1', allowHttp: true),
      isNotNull,
    );
    expect(validateVehicleToken(''), isNull);
    expect(validateVehicleToken('abc.DEF-123_~'), isNull);
    expect(validateVehicleToken('with space'), isNotNull);
    expect(validateVehicleToken('ü'), isNotNull);
  });

  test('tag IDs', () {
    const uuid = 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0';
    expect(validateTagIds([uuid], ['00112233445566778899']), isNull);
    expect(validateTagIds(['nope'], const []), contains('nope'));
    expect(validateTagIds(const [], ['0011']), contains('0011'));
    expect(splitIds(' a, b\n\nc;d '), ['a', 'b', 'c', 'd']);
    expect(splitIds('  '), isEmpty);
    final c = TrackingConfig(
      serverUrl: 'https://a.example',
      deviceId: '1',
      iBeaconUuids: [uuid],
    );
    expect(c.tagFilter.isEmpty, isFalse);
    expect(
      const TrackingConfig(
        serverUrl: 'https://a.example',
        deviceId: '1',
      ).tagFilter.isEmpty,
      isTrue,
    );
    expect(c.copyWith(iBeaconUuids: ['x']).isValid(allowHttp: true), isFalse);
  });

  test('toString hides the vehicle token', () {
    const c = TrackingConfig(
      serverUrl: 'https://a.example',
      deviceId: '1',
      vehicleToken: 'secret-token',
    );
    expect(c.toString(), isNot(contains('secret-token')));
    expect(c.engineConfigured, isFalse);
    expect(c.copyWith(engineUrl: 'https://e.example').engineConfigured, isTrue);
  });

  test('equality covers the list fields', () {
    const a = TrackingConfig(
      serverUrl: 'https://a.example',
      deviceId: '1',
      eddystoneNamespaces: ['00112233445566778899'],
    );
    final b = a.copyWith(eddystoneNamespaces: ['00112233445566778899']);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == a.copyWith(eddystoneNamespaces: const []), isFalse);
  });

  test('CompanionStatus round-trips through an isolate message', () {
    final status = CompanionStatus(
      engineConfigured: true,
      eventQueueLength: 3,
      eventsDropped: 1,
      eventsSent: 7,
      lastEventsSentAt: DateTime.fromMillisecondsSinceEpoch(1000),
      nextEventAttempt: DateTime.fromMillisecondsSinceEpoch(2000),
      eventError: 'offline',
      tagsConfigured: true,
      tagScan: 'scanning',
      tagsPresent: 2,
      batteryLevel: 80,
      warnings: const ['batteryHot'],
    );
    // Simulate what the isolate port delivers: untyped maps and lists.
    final message = Map<Object?, Object?>.from(status.toMessage());
    message['warnings'] = List<Object?>.from(message['warnings']! as List);
    final back = CompanionStatus.fromMessage(message)!;
    expect(back.engineConfigured, isTrue);
    expect(back.eventQueueLength, 3);
    expect(back.eventsDropped, 1);
    expect(back.eventsSent, 7);
    expect(back.lastEventsSentAt, status.lastEventsSentAt);
    expect(back.nextEventAttempt, status.nextEventAttempt);
    expect(back.eventError, 'offline');
    expect(back.tagsConfigured, isTrue);
    expect(back.tagScan, 'scanning');
    expect(back.tagsPresent, 2);
    expect(back.batteryLevel, 80);
    expect(back.warnings, ['batteryHot']);
    expect(back.error, isNull);
    expect(CompanionStatus.fromMessage('other'), isNull);
  });
}
