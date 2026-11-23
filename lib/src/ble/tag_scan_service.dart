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

  /// Permissions missing; the UI must request them. Retried automatically.
  noPermission,

  /// The filter matches nothing (no operator tag IDs configured).
  notConfigured,

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
/// Once started, it keeps trying: if Bluetooth is switched off, a permission
/// is missing or the scan fails, it retries every [retryInterval] until
/// [stop] is called.
class TagScanService {
  TagScanService({
    required this.filter,
    PresenceTracker? tracker,
    BuspilotBleScanner? scanner,
    this.permissions = const BlePermissions(),
    this.scanMode = BleScanMode.lowLatency,
    this.evictInterval = const Duration(seconds: 1),
    this.retryInterval = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : tracker = tracker ?? PresenceTracker(clock: clock),
       _scanner = scanner ?? BuspilotBleScanner(),
       _clock = clock ?? DateTime.now;

  final TagFilter filter;
  final PresenceTracker tracker;
  final BleScanMode scanMode;
  final Duration evictInterval;

  /// Android allows at most 5 scan starts per 30 s, so keep this well above 6 s.
  final Duration retryInterval;

  final BuspilotBleScanner _scanner;
  final BlePermissions permissions;
  final DateTime Function() _clock;

  final ValueNotifier<TagScanState> _state = ValueNotifier(
    const TagScanState(TagScanStatus.stopped),
  );
  StreamSubscription<RawScanResult>? _sub;
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
    tracker.clear();
    _state.value = const TagScanState(TagScanStatus.stopped);
  }

  Future<void> dispose() async {
    await stop();
    tracker.dispose();
    _state.dispose();
  }

  Future<void> _check() async {
    if (!_wanted || _busy) return;
    if (_sub == null) return _connect();
    // Android stops delivering results without an error when the adapter is
    // switched off, so poll it.
    if (!await _bluetoothEnabled()) {
      await _disconnect();
      _setState(TagScanStatus.waitingForBluetooth);
    }
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
      if (await permissions.check() != BlePermissionStatus.granted) {
        return _setState(TagScanStatus.noPermission);
      }
      if (!await _bluetoothEnabled()) {
        return _setState(TagScanStatus.waitingForBluetooth);
      }
      if (!_wanted) return; // Stopped while awaiting.
      _sub = _scanner
          .scan(filter: scanFilter, mode: scanMode)
          .listen(_onResult, onError: _onError, onDone: _onDone);
      _setState(TagScanStatus.scanning);
    } on PlatformException catch (e) {
      _setState(TagScanStatus.error, e.message ?? e.code);
    } finally {
      _busy = false;
    }
  }

  Future<void> _disconnect() async {
    final sub = _sub;
    _sub = null;
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
    final status = error is PlatformException && error.code == 'bluetooth_off'
        ? TagScanStatus.waitingForBluetooth
        : error is PlatformException && error.code == 'permission_denied'
        ? TagScanStatus.noPermission
        : TagScanStatus.error;
    final message = error is PlatformException ? error.message : '$error';
    unawaited(_disconnect());
    _setState(status, message);
  }

  void _onDone() {
    _sub = null;
    _setState(TagScanStatus.error, 'Scan ended unexpectedly');
  }

  Future<bool> _bluetoothEnabled() async {
    try {
      return await _scanner.isBluetoothEnabled();
    } on PlatformException {
      return false;
    }
  }

  void _setState(TagScanStatus status, [String? message]) {
    if (!_wanted) return;
    _state.value = TagScanState(status, message);
  }
}
