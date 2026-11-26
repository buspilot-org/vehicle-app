import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';

import 'src/tracking/tracking_controller.dart';
import 'src/tracking/tracking_screen.dart';
import 'src/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled brand font's licence, shown on the licence screen.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['M PLUS Rounded 1c'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  initTrackingCommunication();
  runApp(BuspilotVehicleApp(trackingController: TrackingController()));
}

class BuspilotVehicleApp extends StatelessWidget {
  const BuspilotVehicleApp({super.key, required this.trackingController});

  final TrackingController trackingController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Buspilot',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: TrackingScreen(controller: trackingController),
    );
  }
}
