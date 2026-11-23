import 'dart:async';

import 'package:buspilot_ble_scanner/buspilot_ble_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'beacon.dart';
import 'ble_permissions.dart';
import 'presence_tracker.dart';
import 'tag_filter.dart';

enum TagScanStatus {
  stopped,
  scanning,

  /// Bluetooth is off or unavailable; retried automatically.
  waitingForBluetooth,

  /// The system Location switch is off, so Android delivers no beacon
  /// results; retried automatically.
  locationOff,

  /// Permissions missing (or only approximate location); the UI must request
  /// them. Retried automatically.
  noPermission,

  /// The filter matches nothing (no operator tag IDs configured).
  notConfigured,

  /// Another [TagScanService] is already scanning (only one scan per Flutter
  /// engine is possible).
  busy,

  /// The scan failed; retried automatically.
  error,
}

@immutable
class TagScanState {
  const TagScanState(this.status, [this.message]);

  final TagScanStatus status;
  final String? message;

  @override
  String toString() =>
      message == null ? status.name : '${status.name}: $message';
}

/// Scans for the operator's tags and feeds a [PresenceTracker].
///
/// [start] and [stop] are meant to be called by the trip/tracking logic. This
/// class does not keep the app alive in the background: the tracking
/// foreground service does. Create the service in the isolate that stays
/// alive with that foreground service.
///
/// Only one instance can scan at a time (the native scanner has a single
/// channel per engine): the first started instance holds the scanner until
/// [stop]; others report [TagScanStatus.busy] and retry. Share one instance,
/// e.g. pass it to the debug screen.
///
/// Once started, it keeps trying: if Bluetooth or Location is switched off, a
/// permission is missing or the scan fails, it retries every [retryInterval]
/// until [stop] is called. The scan is also restarted every [restartInterval],
/// because Android may throttle scans that run longer than 30 minutes.
class TagScanService {
  TagScanService({
    required this.filter,
    PresenceTracker? tracker,
    BuspilotBleScanner? scanner,
    this.permissions = const BlePermissions(),
    this.scanMode = BleScanMode.lowLatency,
    this.evictInterval = const Duration(seconds: 1),
    this.retryInterval = const Duration(seconds: 10),
    this.restartInterval = const Duration(minutes: 25),
    DateTime Function()? clock,
  }) : tracker = tracker ?? PresenceTracker(clock: clock),
       _scanner = scanner ?? BuspilotBleScanner(),
       _clock = clock ?? DateTime.now;

  final TagFilter filter;
  final PresenceTracker tracker;
  final BlePermissions permissions;
  final BleScanMode scanMode;
  final Duration evictInterval;

  /// Android allows at most 5 scan starts per 30 s, so keep this well above 6 s.
  final Duration retryInterval;

  /// Restart a running scan after this long (checked every [retryInterval]).
  final Duration restartInterval;

  final BuspilotBleScanner _scanner;
  final DateTime Function() _clock;

  /// The instance currently holding the native scanner, if any.
  static TagScanService? _owner;

  final ValueNotifier<TagScanState> _state = ValueNotifier(
    const TagScanState(TagScanStatus.stopped),
  );
  StreamSubscription<RawScanResult>? _sub;
  DateTime? _scanStarted;
  Timer? _evictTimer;
  Timer? _watchdog;
  bool _wanted = false;
  bool _busy = false;

  ValueListenable<TagScanState> get state => _state;

  bool get isRunning => _wanted;

  /// Starts scanning. Returns once the first attempt has finished; check
  /// [state] for the outcome. Calling it while running does nothing.
  Future<void> start() async {
    if (_wanted) return;
    _wanted = true;
    _evictTimer = Timer.periodic(evictInterval, (_) => tracker.evictAbsent());
    _watchdog = Timer.periodic(retryInterval, (_) => _check());
    await _connect();
  }

  /// Stops scanning and forgets all present tags (without leave events).
  /// Read [PresenceTracker.present] first if it matters, e.g. for the
  /// end-of-trip "tags still on board" check.
  Future<void> stop() async {
    _wanted = false;
    _evictTimer?.cancel();
    _watchdog?.cancel();
    _evictTimer = _watchdog = null;
    await _disconnect();
    if (_owner == this) _owner = null;
    tracker.clear();
    _state.value = const TagScanState(TagScanStatus.stopped);
  }

  Future<void> dispose() async {
    await stop();
    tracker.dispose();
    _state.dispose();
  }

  Future<void> _check() async {
    try {
      await _checkOnce();
    } catch (e) {
      // Runs from a timer: never let an error escape.
      _setState(TagScanStatus.error, '$e');
    }
  }

  Future<void> _checkOnce() async {
    if (!_wanted || _busy) return;
    if (_sub == null) return _connect();
    // Android stops delivering results without an error when the adapter or
    // Location is switched off, so poll both.
    final problem = await _environmentProblem();
    if (!_wanted || _sub == null) return;
    if (problem != null) {
      await _disconnect();
      return _setState(problem);
    }
    final started = _scanStarted;
    if (started != null && _clock().difference(started) >= restartInterval) {
      await _disconnect();
      await _connect();
    }
  }

  Future<TagScanStatus?> _environmentProblem() async {
    if (!await _call(_scanner.isBluetoothEnabled)) {
      return TagScanStatus.waitingForBluetooth;
    }
    if (!await _call(_scanner.isLocationEnabled)) {
      return TagScanStatus.locationOff;
    }
    return null;
  }

  Future<void> _connect() async {
    if (_busy || _sub != null) return;
    _busy = true;
    try {
      final scanFilter = filter.toScanFilter();
      if (scanFilter == null) {
        return _setState(
          TagScanStatus.notConfigured,
          'No tag UUIDs or namespaces configured',
        );
      }
      // Claim the scanner before any await, so two instances cannot both pass
      // this check. The claim is kept across retries and restarts and only
      // released by stop().
      if (_owner != null && _owner != this) {
        return _setState(TagScanStatus.busy, 'Another scan is running');
      }
      _owner = this;
      if (await permissions.check() != BlePermissionStatus.granted) {
        return _setState(TagScanStatus.noPermission);
      }
      final problem = await _environmentProblem();
      if (problem != null) return _setState(problem);
      if (!_wanted) return; // Stopped while awaiting.
      _scanStarted = _clock();
      _sub = _scanner
          .scan(filter: scanFilter, mode: scanMode)
          .listen(_onResult, onError: _onError, onDone: _onDone);
      _setState(TagScanStatus.scanning);
    } catch (e) {
      // Includes MissingPluginException and permission_handler errors; must
      // not escape from the watchdog timer.
      _setState(TagScanStatus.error, e is PlatformException ? e.message : '$e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _disconnect() async {
    final sub = _sub;
    _sub = null;
    _scanStarted = null;
    await sub?.cancel();
  }

  void _onResult(RawScanResult r) {
    final beacon = parseAdvertisement(r.bytes);
    if (beacon == null || !filter.matches(beacon)) return;
    tracker.addSighting(
      BeaconSighting(
        beacon: beacon,
        address: r.address,
        rssi: r.rssi,
        time: _clock(),
      ),
    );
  }

  void _onError(Object error) {
    final code = error is PlatformException ? error.code : null;
    final status = switch (code) {
      'bluetooth_off' => TagScanStatus.waitingForBluetooth,
      'location_off' => TagScanStatus.locationOff,
      'permission_denied' => TagScanStatus.noPermission,
      _ => TagScanStatus.error,
    };
    final message = error is PlatformException ? error.message : '$error';
    unawaited(_disconnect());
    _setState(status, message);
  }

  void _onDone() {
    _sub = null;
    _scanStarted = null;
    _setState(TagScanStatus.error, 'Scan ended unexpectedly');
  }

  static Future<bool> _call(Future<bool> Function() f) async {
    try {
      return await f();
    } on Exception {
      // PlatformException, MissingPluginException: treat as unavailable.
      return false;
    }
  }

  void _setState(TagScanStatus status, [String? message]) {
    if (!_wanted) return;
    _state.value = TagScanState(status, message);
  }
}
