import 'package:buspilot_vehicle/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const channel = MethodChannel('org.buspilot.vehicle/device');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('app starts on the device status screen with warnings', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
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

    await tester.pumpWidget(const MyApp());
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
