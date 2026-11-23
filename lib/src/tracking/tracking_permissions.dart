import 'package:permission_handler/permission_handler.dart';

import '../device/device_channel.dart';

/// What tracking needs from Android, checked in one go.
///
/// The Traccar Client SDK checks fine + background location, notifications
/// and activity recognition itself when tracking starts, and shows its own
/// prompts for anything missing; it also opens the battery optimisation
/// list once. The permission screen asks for all of these first, so the SDK
/// finds them granted and shows nothing.
class PermissionState {
  const PermissionState({
    required this.notifications,
    required this.location,
    required this.locationAlways,
    required this.activityRecognition,
    required this.locationServiceOn,
    required this.batteryOptimizationOff,
    required this.bluetooth,
  });

  /// Notification permission (Android 13+). Without it the foreground
  /// service notification is hidden.
  final PermissionStatus notifications;

  /// Precise location while in use.
  final PermissionStatus location;

  /// "Allow all the time".
  final PermissionStatus locationAlways;

  /// "Physical activity": stop detection (pause GPS while parked).
  final PermissionStatus activityRecognition;

  /// Whether location is switched on in the phone's quick settings.
  final bool locationServiceOn;

  /// Whether the app is exempt from battery optimisation, so Android does
  /// not stop tracking to save power.
  final bool batteryOptimizationOff;

  /// "Nearby devices" (BLUETOOTH_SCAN) for tag scanning.
  final PermissionStatus bluetooth;

  bool get notificationsGranted => notifications.isGranted;
  bool get locationWhileInUse => location.isGranted;
  bool get locationDeniedForever => location.isPermanentlyDenied;
  bool get locationAlwaysGranted => locationAlways.isGranted;
  bool get activityGranted => activityRecognition.isGranted;
  bool get bluetoothGranted => bluetooth.isGranted;

  /// Everything tracking cannot work without (or that the SDK would
  /// otherwise prompt for when tracking starts).
  bool get requiredGranted =>
      notificationsGranted &&
      locationWhileInUse &&
      locationAlwaysGranted &&
      activityGranted &&
      locationServiceOn &&
      batteryOptimizationOff;

  bool get allGranted => requiredGranted && bluetoothGranted;
}

class TrackingPermissions {
  const TrackingPermissions();

  Future<PermissionState> check() async => PermissionState(
    notifications: await Permission.notification.status,
    location: await Permission.location.status,
    locationAlways: await Permission.locationAlways.status,
    activityRecognition: await Permission.activityRecognition.status,
    locationServiceOn: await Permission.location.serviceStatus.isEnabled,
    batteryOptimizationOff:
        await Permission.ignoreBatteryOptimizations.status.isGranted,
    bluetooth: await Permission.bluetoothScan.status,
  );

  Future<void> requestNotifications() => _request(Permission.notification);

  /// "While using the app" (precise).
  Future<void> requestLocation() => _request(Permission.location);

  /// "Allow all the time" (Android shows its settings page for that on
  /// Android 11+). Needs [requestLocation] first.
  Future<void> requestLocationAlways() => _request(Permission.locationAlways);

  Future<void> requestActivityRecognition() =>
      _request(Permission.activityRecognition);

  Future<void> requestBluetooth() => _request(Permission.bluetoothScan);

  Future<void> requestBatteryExemption() =>
      _request(Permission.ignoreBatteryOptimizations);

  Future<void> openSettings() => openAppSettings();

  Future<void> openLocationSettings() async {
    try {
      await DeviceChannel().openLocationSettings();
    } on Exception {
      // Kiosk mode or no such settings page; the step stays open.
    }
  }

  /// Requests [p], or opens the app settings if Android will not ask again.
  static Future<void> _request(Permission p) async {
    if (await p.status.isPermanentlyDenied) {
      await openAppSettings();
      return;
    }
    await p.request();
  }
}
