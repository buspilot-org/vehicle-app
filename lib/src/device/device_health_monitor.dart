import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'battery_snapshot.dart';
import 'device_channel.dart';
import 'device_health_config.dart';
import 'device_warnings.dart';

/// Polls the battery and dedicated-phone state and keeps the current warnings.
///
/// [snapshot] is what tracking can attach to positions later
/// (see [BatterySnapshot.toPositionAttributes]).
class DeviceHealthMonitor extends ChangeNotifier {
  DeviceHealthMonitor({
    DeviceChannel? channel,
    this.config = const DeviceHealthConfig(),
  }) : channel = channel ?? DeviceChannel(),
       _tracker = FullChargeTracker(config: config);

  final DeviceChannel channel;
  final DeviceHealthConfig config;
  final FullChargeTracker _tracker;
  Timer? _timer;

  BatterySnapshot? snapshot;
  DeviceState deviceState = const DeviceState();
  List<DeviceWarning> warnings = const [];

  /// Set when the platform side is missing (tests, non-Android).
  String? error;

  void start() {
    _timer?.cancel();
    unawaited(refresh());
    _timer = Timer.periodic(config.pollInterval, (_) => refresh());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    try {
      final battery = await channel.readBattery();
      deviceState = await channel.readDeviceState();
      snapshot = battery;
      if (battery != null) {
        _tracker.update(battery);
        warnings = evaluateDeviceWarnings(
          battery,
          config: config,
          fullSince: _tracker.fullSince,
        );
      } else {
        warnings = const [];
      }
      error = null;
    } on PlatformException catch (e) {
      error = e.message ?? e.code;
    } on MissingPluginException {
      error = 'Device information is only available on Android.';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
