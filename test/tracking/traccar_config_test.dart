import 'package:buspilot_vehicle/src/config/tracking_config.dart';
import 'package:buspilot_vehicle/src/tracking/traccar_config.dart';
import 'package:buspilot_vehicle/src/tracking/tracking_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart' as sdk;

void main() {
  const base = TrackingConfig(
    serverUrl: ' https://traccar.example.org:5055 ',
    deviceId: '12345678',
  );

  test('defaults map to bus-friendly SDK settings', () {
    final c = toTraccarConfig(base);
    expect(c.serverUrl, 'https://traccar.example.org:5055');
    expect(c.deviceId, '12345678');
    expect(c.headers, isEmpty);
    expect(c.buffer, isTrue);
    expect(c.wakeLock, isTrue);
    expect(c.preferPlatformProviders, isFalse);
    expect(c.notification.text, trackingNotificationText);
    final l = c.location;
    expect(l.accuracy, sdk.Accuracy.high);
    expect(l.intervalSeconds, 10);
    expect(l.distanceMeters, 0);
    expect(l.angleDegrees, 0);
    expect(l.stopDetection, isTrue);
    expect(l.stopTimeoutSeconds, 300);
    expect(l.stationaryRadiusMeters, 100);
    expect(l.heartbeatIntervalSeconds, 900);
  });

  test('settings are passed through', () {
    final c = toTraccarConfig(
      base.copyWith(
        accuracy: TrackingAccuracy.highest,
        intervalSeconds: 30,
        distanceFilterMeters: 20,
        stopTimeoutSeconds: 120,
        heartbeatSeconds: 600,
      ),
    );
    expect(c.location.accuracy, sdk.Accuracy.highest);
    expect(c.location.intervalSeconds, 30);
    expect(c.location.distanceMeters, 20);
    expect(c.location.stopTimeoutSeconds, 120);
    expect(c.location.heartbeatIntervalSeconds, 600);
  });

  test('every accuracy maps to the SDK value of the same name', () {
    for (final a in TrackingAccuracy.values) {
      expect(
        toTraccarConfig(base.copyWith(accuracy: a)).location.accuracy.name,
        a.name,
      );
    }
  });

  test('no heartbeat without stop detection', () {
    // The SDK only sends heartbeats while stop detection has paused GPS.
    final c = toTraccarConfig(base.copyWith(stopDetection: false));
    expect(c.location.stopDetection, isFalse);
    expect(c.location.heartbeatIntervalSeconds, 0);
  });

  test('engine settings do not reach Traccar', () {
    final c = toTraccarConfig(
      base.copyWith(engineUrl: 'https://engine.example', vehicleToken: 's'),
    );
    expect(c.headers, isEmpty);
  });

  test('lastUploadLine finds the newest upload result in the SDK log', () {
    expect(lastUploadLine(const []), isNull);
    expect(
      lastUploadLine(const [
        'Upload response 200',
        'Location accepted 35.1,139.2',
        'Upload error: timeout',
        'Location filtered 35.1,139.2',
      ]),
      'Upload error: timeout',
    );
  });
}
