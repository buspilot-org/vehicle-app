import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

/// What tracking needs from Android, checked in one go.
class PermissionState {
  const PermissionState({
    required this.notifications,
    required this.location,
    required this.locationServiceOn,
    required this.batteryOptimizationOff,
  });

  /// Notification permission (Android 13+). Without it the foreground
  /// service notification is hidden.
  final bool notifications;

  final LocationPermission location;

  /// Whether location is switched on in the phone's quick settings.
  final bool locationServiceOn;

  /// Whether the app is exempt from battery optimisation. Recommended, so
  /// the phone does not stop tracking to save power.
  final bool batteryOptimizationOff;

  bool get locationWhileInUse =>
      location == LocationPermission.whileInUse ||
      location == LocationPermission.always;

  /// "Allow all the time": lets tracking restart after a reboot without
  /// anyone opening the app.
  bool get locationAlways => location == LocationPermission.always;

  bool get locationDeniedForever =>
      location == LocationPermission.deniedForever;

  /// Everything tracking cannot work without.
  bool get requiredGranted =>
      notifications && locationAlways && locationServiceOn;

  bool get allGranted => requiredGranted && batteryOptimizationOff;
}

class TrackingPermissions {
  const TrackingPermissions();

  Future<PermissionState> check() async => PermissionState(
    notifications:
        await FlutterForegroundTask.checkNotificationPermission() ==
        NotificationPermission.granted,
    location: await Geolocator.checkPermission(),
    locationServiceOn: await Geolocator.isLocationServiceEnabled(),
    batteryOptimizationOff:
        await FlutterForegroundTask.isIgnoringBatteryOptimizations,
  );

  Future<void> requestNotifications() async {
    final status = await FlutterForegroundTask.requestNotificationPermission();
    if (status == NotificationPermission.permanently_denied) {
      await Geolocator.openAppSettings();
    }
  }

  /// First call asks for "while using the app". When that is granted, the
  /// next call asks for "Allow all the time" (Android shows its settings
  /// page for that on Android 11+).
  Future<void> requestLocation() async {
    final current = await Geolocator.checkPermission();
    if (current == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return;
    }
    await Geolocator.requestPermission();
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  Future<void> requestBatteryExemption() =>
      FlutterForegroundTask.requestIgnoreBatteryOptimization();
}
