import 'package:buspilot_vehicle/src/device/device_status_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const channel = MethodChannel('org.buspilot.vehicle/device');
  // getBattery is served by the buspilot_battery plugin.
  const batteryChannel = MethodChannel('org.buspilot.vehicle/battery');

  void mock(Future<Object?> Function(MethodCall call)? handler) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, handler);
    messenger.setMockMethodCallHandler(batteryChannel, handler);
  }

  tearDown(() => mock(null));

  testWidgets('leaving kiosk mode needs a long-press and confirmation', (
    tester,
  ) async {
    final calls = <String>[];
    mock((call) async {
      calls.add(call.method);
      return switch (call.method) {
        'getBattery' => {'available': true, 'level': 50},
        'getDeviceState' => {'deviceOwner': true, 'lockTaskState': 'locked'},
        _ => null,
      };
    });

    await tester.pumpWidget(const MaterialApp(home: DeviceStatusScreen()));
    await tester.pump();
    final exit = find.text('Leave kiosk mode (long-press)');
    await tester.ensureVisible(exit);
    await tester.pumpAndSettle();

    await tester.tap(exit);
    await tester.pump();
    expect(find.text('Long-press to leave kiosk mode.'), findsOneWidget);
    expect(calls, isNot(contains('exitKiosk')));

    await tester.longPress(exit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('exitKiosk')));

    await tester.longPress(exit);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Leave kiosk mode'));
    await tester.pumpAndSettle();
    expect(calls, contains('exitKiosk'));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('status screen shows battery values and warnings', (
    tester,
  ) async {
    mock((call) async {
      switch (call.method) {
        case 'getBattery':
          return {
            'available': true,
            'level': 72,
            'status': 'charging',
            'plugged': 'usb',
            'health': 'good',
            'temperatureC': 48.5,
          };
        case 'getDeviceState':
          return {'deviceOwner': true, 'lockTaskState': 'locked'};
      }
      return null;
    });

    await tester.pumpWidget(const MaterialApp(home: DeviceStatusScreen()));
    await tester.pump();

    expect(find.text('Device status'), findsOneWidget);
    expect(find.textContaining('Battery is 48.5 °C'), findsOneWidget);
    expect(find.text('72 %'), findsOneWidget);
    expect(find.text('locked (device owner)'), findsOneWidget);
    expect(find.text('Leave kiosk mode (long-press)'), findsOneWidget);

    // Dispose the screen so its poll timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });
}
