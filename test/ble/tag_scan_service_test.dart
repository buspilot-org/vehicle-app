import 'dart:async';

import 'package:buspilot_ble_scanner/buspilot_ble_scanner.dart';
import 'package:buspilot_vehicle/src/ble/ble.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'beacon_test.dart' show hex;

class FakeScanner implements BuspilotBleScanner {
  bool enabled = true;
  StreamController<RawScanResult>? controller;
  BleScanFilter? lastFilter;
  int scans = 0;

  @override
  Future<bool> isBluetoothEnabled() async => enabled;

  @override
  Stream<RawScanResult> scan({
    BleScanFilter filter = const BleScanFilter(),
    BleScanMode mode = BleScanMode.lowLatency,
  }) {
    lastFilter = filter;
    scans++;
    controller = StreamController<RawScanResult>();
    return controller!.stream;
  }

  void emit(Uint8List bytes, {int rssi = -60}) => controller!.add(
    RawScanResult(address: 'C4:7C:8D:00:00:01', rssi: rssi, bytes: bytes),
  );
}

class FakePermissions implements BlePermissions {
  BlePermissionStatus status = BlePermissionStatus.granted;

  @override
  Future<BlePermissionStatus> check() async => status;

  @override
  Future<BlePermissionStatus> request() async => status;

  @override
  Future<bool> openSettings() async => true;
}

final iBeaconFrame = hex(
  '02 01 06 1A FF 4C 00 02 15 E2 C5 6D B5 DF FB 48 D2 B0 60 D0 F5 A7 10 96 E0 '
  '00 01 00 02 C5',
);
final otherIBeaconFrame = hex(
  '02 01 06 1A FF 4C 00 02 15 FD A5 06 93 A4 E2 4F B1 AF CF C6 EB 07 64 78 25 '
  '00 01 00 02 C5',
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeScanner scanner;
  late FakePermissions permissions;
  late TagScanService service;

  setUp(() {
    scanner = FakeScanner();
    permissions = FakePermissions();
    service = TagScanService(
      filter: TagFilter(iBeaconUuids: ['e2c56db5-dffb-48d2-b060-d0f5a71096e0']),
      scanner: scanner,
      permissions: permissions,
      // Long intervals: timers must not fire during these tests.
      evictInterval: const Duration(hours: 1),
      retryInterval: const Duration(hours: 1),
    );
  });

  tearDown(() => service.dispose());

  test(
    'start scans with the hardware filter and tracks matching tags',
    () async {
      await service.start();
      expect(service.state.value.status, TagScanStatus.scanning);
      expect(scanner.lastFilter!.iBeaconUuids, [
        'e2c56db5dffb48d2b060d0f5a71096e0',
      ]);
      expect(scanner.lastFilter!.includeEddystone, isFalse);

      scanner.emit(iBeaconFrame);
      scanner.emit(otherIBeaconFrame); // Not the operator's UUID.
      scanner.emit(hex('02 01 06')); // No beacon.
      await flush();

      expect(service.tracker.present.map((t) => t.tagId), [
        'ibeacon:e2c56db5-dffb-48d2-b060-d0f5a71096e0:1:2',
      ]);
    },
  );

  test('start twice does not start a second scan', () async {
    await service.start();
    await service.start();
    expect(scanner.scans, 1);
  });

  test('stop cancels the scan and clears present tags', () async {
    await service.start();
    scanner.emit(iBeaconFrame);
    await flush();
    await service.stop();
    expect(service.state.value.status, TagScanStatus.stopped);
    expect(service.tracker.present, isEmpty);
    expect(scanner.controller!.hasListener, isFalse);
  });

  test('reports missing permission and Bluetooth off', () async {
    permissions.status = BlePermissionStatus.denied;
    await service.start();
    expect(service.state.value.status, TagScanStatus.noPermission);
    expect(scanner.scans, 0);
    await service.stop();

    permissions.status = BlePermissionStatus.granted;
    scanner.enabled = false;
    await service.start();
    expect(service.state.value.status, TagScanStatus.waitingForBluetooth);
    expect(scanner.scans, 0);
  });

  test('not configured when the filter is empty', () async {
    final s = TagScanService(
      filter: TagFilter(),
      scanner: scanner,
      permissions: permissions,
    );
    await s.start();
    expect(s.state.value.status, TagScanStatus.notConfigured);
    await s.dispose();
  });

  test('a platform error stops the scan and is reported', () async {
    await service.start();
    scanner.controller!.addError(
      PlatformException(code: 'scan_failed', message: 'code 2'),
    );
    await flush();
    expect(service.state.value.status, TagScanStatus.error);
    expect(service.state.value.message, 'code 2');
  });

  test('retries after an error', () async {
    final s = TagScanService(
      filter: const TagFilter.any(),
      scanner: scanner,
      permissions: permissions,
      retryInterval: const Duration(milliseconds: 20),
      evictInterval: const Duration(hours: 1),
    );
    scanner.enabled = false;
    await s.start();
    expect(s.state.value.status, TagScanStatus.waitingForBluetooth);
    scanner.enabled = true;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(s.state.value.status, TagScanStatus.scanning);
    expect(scanner.scans, 1);
    await s.dispose();
  });
}
