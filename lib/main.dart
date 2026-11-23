import 'package:material_ui/material_ui.dart';

import 'src/tracking/tracking_controller.dart';
import 'src/tracking/tracking_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.indigo)),
      home: TrackingScreen(controller: trackingController),
    );
  }
}
