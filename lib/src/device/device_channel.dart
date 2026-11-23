import 'package:flutter/services.dart';

import 'battery_snapshot.dart';

enum LockTaskState { none, pinned, locked }

/// Dedicated-phone state reported by the platform.
class DeviceState {
  const DeviceState({
    this.deviceOwner = false,
    this.lockTaskState = LockTaskState.none,
    this.kioskEnabled = false,
    this.ignoringBatteryOptimizations = false,
  });

  factory DeviceState.fromMap(Map<Object?, Object?> map) => DeviceState(
    deviceOwner: map['deviceOwner'] == true,
    lockTaskState: LockTaskState.values.firstWhere(
      (s) => s.name == map['lockTaskState'],
      orElse: () => LockTaskState.none,
    ),
    kioskEnabled: map['kioskEnabled'] == true,
    ignoringBatteryOptimizations: map['ignoringBatteryOptimizations'] == true,
  );

  /// The app is provisioned as device owner (full kiosk, start on boot).
  final bool deviceOwner;
  final LockTaskState lockTaskState;

  /// Whether kiosk mode is switched on (re-entered on resume as device owner).
  final bool kioskEnabled;
  final bool ignoringBatteryOptimizations;
}

/// Talks to `DeviceChannel.kt`.
class DeviceChannel {
  DeviceChannel({MethodChannel? channel, DateTime Function()? clock})
    : _channel = channel ?? const MethodChannel('org.buspilot.vehicle/device'),
      _clock = clock ?? DateTime.now;

  final MethodChannel _channel;
  final DateTime Function() _clock;

  /// Current battery reading, or null if the platform has none.
  Future<BatterySnapshot?> readBattery() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('getBattery');
    if (map == null || map['available'] != true) return null;
    return BatterySnapshot.fromMap(map, _clock());
  }

  Future<DeviceState> readDeviceState() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'getDeviceState',
    );
    return map == null ? const DeviceState() : DeviceState.fromMap(map);
  }

  Future<void> enterKiosk() => _channel.invokeMethod<void>('enterKiosk');

  Future<void> exitKiosk() => _channel.invokeMethod<void>('exitKiosk');

  /// Opens the system list of battery optimisation exceptions. Returns false
  /// if it could not be opened (for example while in kiosk mode).
  Future<bool> openBatteryOptimizationSettings() async =>
      await _channel.invokeMethod<bool>('openBatteryOptimizationSettings') ??
      false;
}
