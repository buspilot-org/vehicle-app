import 'package:flutter/services.dart';

/// Channel name used by `BuspilotBatteryPlugin.kt`.
const batteryChannelName = 'org.buspilot.vehicle/battery';

/// Reads the battery state. Works in any Flutter engine of the app.
class BuspilotBattery {
  BuspilotBattery([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(batteryChannelName);

  final MethodChannel _channel;

  /// The raw reading (see `BatteryReader.kt` for the keys), or null if the
  /// platform returned nothing. `available` is false when Android has no
  /// battery broadcast.
  Future<Map<Object?, Object?>?> read() =>
      _channel.invokeMapMethod<Object?, Object?>('getBattery');
}
