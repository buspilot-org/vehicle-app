/// Android BLE advertisement scanner. See README.md.
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// Scan power mode, mapped to Android `ScanSettings.SCAN_MODE_*`.
enum BleScanMode { lowPower, balanced, lowLatency }

/// One advertisement as reported by Android.
class RawScanResult {
  const RawScanResult({
    required this.address,
    required this.rssi,
    required this.bytes,
  });

  /// Bluetooth device address (MAC), e.g. `C4:7C:8D:12:34:56`.
  final String address;

  /// Received signal strength in dBm.
  final int rssi;

  /// Raw advertisement data (AD structures), may include the scan response.
  final Uint8List bytes;
}

/// Filters handed to the Android scanner. Empty lists mean "any iBeacon" or
/// "any Eddystone-UID" respectively; set [includeIBeacon] or
/// [includeEddystone] to false to skip that format entirely.
class BleScanFilter {
  const BleScanFilter({
    this.includeIBeacon = true,
    this.iBeaconUuids = const [],
    this.includeEddystone = true,
    this.eddystoneNamespaces = const [],
  });

  final bool includeIBeacon;

  /// 16-byte proximity UUIDs as 32 hex digits (dashes allowed).
  final List<String> iBeaconUuids;

  final bool includeEddystone;

  /// 10-byte namespaces as 20 hex digits.
  final List<String> eddystoneNamespaces;

  Map<String, Object?> toMap() => {
    'includeIBeacon': includeIBeacon,
    'iBeaconUuids': iBeaconUuids,
    'includeEddystone': includeEddystone,
    'eddystoneNamespaces': eddystoneNamespaces,
  };
}

class BuspilotBleScanner {
  BuspilotBleScanner({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methods = methodChannel ?? const MethodChannel(_methodName),
      _events = eventChannel ?? const EventChannel(_eventName);

  static const _methodName = 'org.buspilot/ble_scanner';
  static const _eventName = 'org.buspilot/ble_scanner/scan';

  final MethodChannel _methods;
  final EventChannel _events;

  /// Whether the device has BLE and the adapter is switched on.
  Future<bool> isBluetoothEnabled() async =>
      await _methods.invokeMethod<bool>('isBluetoothEnabled') ?? false;

  /// Starts scanning when listened to and stops when the subscription is
  /// cancelled. Errors (e.g. `bluetooth_off`, `permission_denied`,
  /// `scan_failed`) arrive as [PlatformException]s on the stream.
  ///
  /// Only one scan can run at a time; listening again replaces the scan.
  Stream<RawScanResult> scan({
    BleScanFilter filter = const BleScanFilter(),
    BleScanMode mode = BleScanMode.lowLatency,
  }) {
    final args = {...filter.toMap(), 'scanMode': mode.name};
    return _events.receiveBroadcastStream(args).map((event) {
      final map = event as Map<Object?, Object?>;
      return RawScanResult(
        address: map['address'] as String,
        rssi: map['rssi'] as int,
        bytes: map['bytes'] as Uint8List,
      );
    });
  }
}
