import 'package:buspilot_vehicle/src/config/config_store.dart';
import 'package:buspilot_vehicle/src/config/tracking_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('first load gives defaults and a stable random device ID', () async {
    final store = ConfigStore();
    final a = await store.load();
    expect(a.serverUrl, '');
    expect(a.deviceId, matches(RegExp(r'^[1-9][0-9]{7}$')));
    expect(a.intervalSeconds, 10);
    expect(a.distanceFilterMeters, 0);
    expect(a.accuracy, TrackingAccuracy.high);
    expect(a.stopDetection, isTrue);
    expect(a.stopTimeoutSeconds, 300);
    expect(a.heartbeatSeconds, 900);
    expect(a.engineUrl, '');
    expect(a.vehicleToken, '');
    expect(a.iBeaconUuids, isEmpty);
    expect((await store.load()).deviceId, a.deviceId);
  });

  test('all settings round-trip', () async {
    final store = ConfigStore();
    const config = TrackingConfig(
      serverUrl: 'https://traccar.example.org',
      deviceId: 'bus-7',
      intervalSeconds: 20,
      distanceFilterMeters: 15,
      accuracy: TrackingAccuracy.medium,
      stopDetection: false,
      stopTimeoutSeconds: 120,
      heartbeatSeconds: 0,
      engineUrl: 'https://engine.example.org',
      vehicleToken: 'tok.123',
      iBeaconUuids: ['e2c56db5-dffb-48d2-b060-d0f5a71096e0'],
      eddystoneNamespaces: ['00112233445566778899', 'aabbccddeeff00112233'],
    );
    await store.save(config);
    expect(await ConfigStore().load(), config);
  });

  test('an unknown stored accuracy falls back to the default', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'tracking.accuracy': 'warp',
          'tracking.deviceId': '1',
        });
    expect((await ConfigStore().load()).accuracy, TrackingAccuracy.high);
  });

  test('tracking flag and service version', () async {
    final store = ConfigStore();
    expect(await store.isTrackingEnabled(), isFalse);
    expect(await store.serviceVersion(), isNull);
    await store.setTrackingEnabled(true);
    await store.setServiceVersion(2);
    expect(await store.isTrackingEnabled(), isTrue);
    expect(await store.serviceVersion(), 2);
  });
}
