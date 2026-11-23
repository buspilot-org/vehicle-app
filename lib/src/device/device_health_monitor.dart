import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'battery_snapshot.dart';
import 'device_channel.dart';
import 'device_health_config.dart';
import 'device_warnings.dart';

/// Polls the battery and dedicated-phone state and keeps the current warnings.
///
/// In the background service there is no activity, so pass
/// `readDeviceState: false` there: only the battery is read.
class DeviceHealthMonitor extends ChangeNotifier {
  DeviceHealthMonitor({
    DeviceChannel? channel,
    this.config = const DeviceHealthConfig(),
    this.readDeviceState = true,
  }) : channel = channel ?? DeviceChannel(),
       _tracker = FullChargeTracker(config: config);

  final DeviceChannel channel;
  final DeviceHealthConfig config;

  /// Whether to read [deviceState] (needs the activity's channel).
  final bool readDeviceState;
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

  bool _disposed = false;
  Future<void>? _inFlight;

  /// Reads the battery and device state once. Overlapping calls share one
  /// read, so readings reach the tracker in order.
  Future<void> refresh() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<void> _refresh() async {
    try {
      final battery = await channel.readBattery();
      final state = readDeviceState ? await channel.readDeviceState() : null;
      if (_disposed) return;
      if (state != null) deviceState = state;
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
    } on MissingPluginException {
      error = 'Device information is only available on Android.';
    } on PlatformException catch (e) {
      error = e.message ?? e.code;
    } catch (e) {
      // Unexpected data from the platform; keep polling.
      error = 'Could not read device state: $e';
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
