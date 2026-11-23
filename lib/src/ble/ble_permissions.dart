import 'package:permission_handler/permission_handler.dart';

/// Result of a permission check for tag scanning.
enum BlePermissionStatus {
  granted,
  denied,

  /// The user chose "don't ask again"; only the system settings can fix it.
  permanentlyDenied,
}

/// Runtime permissions needed to receive beacon advertisements.
///
/// - Android 12+: `BLUETOOTH_SCAN`. permission_handler reports it as granted
///   on older versions, where it does not exist.
/// - Location (fine) on all versions: Android 11 and older require it for
///   scanning; on 12+ it is required because our `BLUETOOTH_SCAN` does not
///   carry `neverForLocation` (that flag filters out beacons), and Android only
///   delivers results to such apps if they hold location permission. The
///   tracking module needs location anyway.
///
/// Background location is not requested here; the tracking foreground
/// service (type `location`) keeps the while-in-use grant valid.
class BlePermissions {
  const BlePermissions();

  static const _required = [Permission.bluetoothScan, Permission.location];

  Future<BlePermissionStatus> check() async =>
      _combine([for (final p in _required) await p.status]);

  /// Shows the system dialogs for missing permissions. Call from the UI only,
  /// never from the background.
  Future<BlePermissionStatus> request() async {
    final results = await _required.request();
    return _combine(results.values);
  }

  /// Opens the app's system settings page.
  Future<bool> openSettings() => openAppSettings();

  static BlePermissionStatus _combine(Iterable<PermissionStatus> statuses) {
    if (statuses.every((s) => s.isGranted || s.isLimited)) {
      return BlePermissionStatus.granted;
    }
    if (statuses.any((s) => s.isPermanentlyDenied)) {
      return BlePermissionStatus.permanentlyDenied;
    }
    return BlePermissionStatus.denied;
  }
}
