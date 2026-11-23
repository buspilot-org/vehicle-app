/// Bluetooth tag scanning for the boarding check.
///
/// - [TagScanService]: start/stop scanning, owns a [PresenceTracker].
/// - [PresenceTracker]: tags currently present, enter/leave events.
/// - [TagFilter]: the operator's iBeacon UUIDs / Eddystone namespaces.
/// - [BlePermissions]: Android runtime permissions.
/// - [BleDebugScreen]: debug UI.
library;

export 'beacon.dart';
export 'ble_debug_screen.dart';
export 'ble_permissions.dart';
export 'presence_tracker.dart';
export 'tag_filter.dart';
export 'tag_scan_service.dart';
