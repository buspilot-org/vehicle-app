import 'dart:async';

import 'package:buspilot_vehicle/src/device/device_channel.dart';
import 'package:buspilot_vehicle/src/device/device_health_monitor.dart';
import 'package:buspilot_vehicle/src/device/device_warnings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.buspilot.vehicle/device');
  // getBattery is served by the buspilot_battery plugin.
  const batteryChannel = MethodChannel('org.buspilot.vehicle/battery');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final now = DateTime.utc(2026, 11, 23, 8);

  DeviceHealthMonitor monitor() =>
      DeviceHealthMonitor(channel: DeviceChannel(clock: () => now));

  void mock(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
    messenger.setMockMethodCallHandler(batteryChannel, handler);
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(batteryChannel, null);
  });

  test('reads battery and device state and evaluates warnings', () async {
    mock(
      (call) async => switch (call.method) {
        'getBattery' => {
          'available': true,
          'level': 50,
          'plugged': 'none',
          'health': 'dead',
          'temperatureC': 30.0,
        },
        'getDeviceState' => {'deviceOwner': true, 'lockTaskState': 'pinned'},
        _ => null,
      },
    );
    final m = monitor();
    await m.refresh();
    expect(m.snapshot?.level, 50);
    expect(m.deviceState.deviceOwner, isTrue);
    expect(m.deviceState.lockTaskState, LockTaskState.pinned);
    expect(m.warnings.map((w) => w.type), [
      DeviceWarningType.batteryHealthNotGood,
    ]);
    expect(m.error, isNull);
  });

  test('no battery reading gives no snapshot and no warnings', () async {
    mock(
      (call) async => call.method == 'getBattery' ? {'available': false} : {},
    );
    final m = monitor();
    await m.refresh();
    expect(m.snapshot, isNull);
    expect(m.warnings, isEmpty);
  });

  test('platform errors are shown, not thrown', () async {
    mock((call) async => throw PlatformException(code: 'x', message: 'boom'));
    final m = monitor();
    await m.refresh();
    expect(m.error, 'boom');
  });

  test('unexpected platform data is shown, not thrown', () async {
    mock((call) async => {'available': true, 'level': 'not a number'});
    final m = monitor();
    await m.refresh();
    expect(m.error, startsWith('Could not read device state'));
  });

  test('overlapping refreshes share one read', () async {
    var batteryReads = 0;
    mock((call) async {
      if (call.method == 'getBattery') batteryReads++;
      return {'available': true, 'level': 10};
    });
    final m = monitor();
    await Future.wait([m.refresh(), m.refresh(), m.refresh()]);
    expect(batteryReads, 1);
    await m.refresh();
    expect(batteryReads, 2);
  });

  test('dispose during a refresh does not notify', () async {
    final gate = Completer<void>();
    mock((call) async {
      await gate.future;
      return {'available': true, 'level': 10};
    });
    final m = monitor();
    var notified = false;
    m.addListener(() => notified = true);
    final pending = m.refresh();
    m.dispose();
    gate.complete();
    await pending; // Would fail the "used after dispose" assertion.
    expect(notified, isFalse);
  });

  test('readDeviceState: false reads only the battery', () async {
    final methods = <String>[];
    mock((call) async {
      methods.add(call.method);
      return {'available': true, 'level': 40};
    });
    final m = DeviceHealthMonitor(
      channel: DeviceChannel(clock: () => now),
      readDeviceState: false,
    );
    await m.refresh();
    expect(methods, ['getBattery']);
    expect(m.snapshot?.level, 40);
    expect(m.error, isNull);
  });
}
