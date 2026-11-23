import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config/config_store.dart';
import 'position_filter.dart';
import 'position_queue.dart';
import 'position_record.dart';
import 'position_uploader.dart';
import 'tracking_status.dart';

/// Entry point of the foreground service isolate. Also runs after a reboot
/// or app update (autoRunOnBoot), without the UI.
@pragma('vm:entry-point')
void trackingTaskCallback() {
  FlutterForegroundTask.setTaskHandler(TrackingTaskHandler());
}

/// Process-wide name that the isolate owning the queue file registers.
/// After a restart, the old service isolate can still be shutting down while
/// the new one starts (both run in the same process, so a file lock would
/// not tell them apart).
const _queueOwnerName = 'org.buspilot.tracking.queueOwner';

/// Message the UI sends to ask the service for a fresh [TrackingStatus].
const statusRequestMessage = 'trackingStatusRequest';

/// Runs inside the foreground service: receives location fixes, queues them
/// and sends them to Traccar.
class TrackingTaskHandler extends TaskHandler {
  final _battery = Battery();
  http.Client? _client;
  FilePositionQueue? _queue;
  PositionUploader? _uploader;
  PositionFilter? _filter;
  StreamSubscription<Position>? _positions;
  Duration _interval = const Duration(seconds: 10);
  DateTime? _lastFixAt;
  String? _locationError;
  String? _configError;
  String? _queueError;
  String _deviceId = '';
  bool _stopping = false;
  ReceivePort? _ownerPort;
  String _notificationText = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final config = await ConfigStore().load();
    if (!config.isValid(allowHttp: kDebugMode)) {
      _configError = 'Settings are incomplete. Open the app to fix them.';
      _publish();
      return;
    }
    await _acquireQueueOwnership();
    final dir = await getApplicationSupportDirectory();
    final queue = await FilePositionQueue.open(
      File('${dir.path}/tracking/position_queue.jsonl'),
    );
    final client = http.Client();
    _client = client;
    _queue = queue;
    _uploader = PositionUploader(
      queue: queue,
      sender: OsmAndSender(
        client: client,
        server: config.serverUri,
        deviceId: config.deviceId,
      ),
    );
    _deviceId = config.deviceId;
    _interval = Duration(seconds: config.intervalSeconds);
    _filter = PositionFilter(
      interval: _interval,
      distanceFilterMeters: config.distanceFilterMeters,
    );
    _listenToPositions();
    // Not awaited: the repeat event (which re-subscribes to locations after
    // an error) only starts once onStart returns, and a long backlog can take
    // a while to send.
    unawaited(_flush());
  }

  /// Waits until no other isolate owns the queue file. After 20 seconds the
  /// old owner is taken to be gone (for example killed during shutdown).
  Future<void> _acquireQueueOwnership() async {
    final port = ReceivePort();
    _ownerPort = port;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!IsolateNameServer.registerPortWithName(
      port.sendPort,
      _queueOwnerName,
    )) {
      if (DateTime.now().isAfter(deadline)) {
        IsolateNameServer.removePortNameMapping(_queueOwnerName);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  void _releaseQueueOwnership() {
    final port = _ownerPort;
    if (port == null) return;
    final owner = IsolateNameServer.lookupPortByName(_queueOwnerName);
    if (owner == port.sendPort) {
      IsolateNameServer.removePortNameMapping(_queueOwnerName);
    }
    port.close();
    _ownerPort = null;
  }

  void _listenToPositions() {
    _positions?.cancel();
    _positions =
        Geolocator.getPositionStream(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            intervalDuration: _interval,
            // Distance filtering is done by PositionFilter, so that a parked bus
            // still reports now and then.
            distanceFilter: 0,
          ),
        ).listen(
          _onPosition,
          onError: (Object error) {
            _locationError = error is LocationServiceDisabledException
                ? 'Location is switched off on the phone.'
                : error is PermissionDeniedException
                ? 'Location permission missing. Open the app.'
                : 'Location error: $error';
            _positions?.cancel();
            _positions = null; // Retried by onRepeatEvent.
            _publish();
          },
          cancelOnError: true,
        );
  }

  Future<void> _onPosition(Position p) async {
    if (_stopping) return;
    _lastFixAt = DateTime.now();
    _locationError = null;
    final record = PositionRecord(
      timestamp: p.timestamp,
      latitude: p.latitude,
      longitude: p.longitude,
      speed: p.speed >= 0 ? p.speed : null,
      bearing: p.heading >= 0 ? p.heading : null,
      altitude: p.altitude,
      accuracy: p.accuracy > 0 ? p.accuracy : null,
      battery: await _batteryLevel(),
      deviceId: _deviceId,
    );
    if (_stopping || _filter?.accept(record) != true) return;
    try {
      await _uploader?.enqueue(record);
      _queueError = null;
    } catch (e) {
      // For example a full disk. The position is lost; say so.
      _queueError = 'Could not store position: $e';
      _publish();
      return;
    }
    await _flush();
  }

  Future<int?> _batteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      return level >= 0 && level <= 100 ? level : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_uploader == null) return;
    if (_positions == null) _listenToPositions();
    unawaited(_flush());
  }

  @override
  void onReceiveData(Object data) {
    if (data == statusRequestMessage) _publish();
  }

  Future<void> _flush() async {
    final uploader = _uploader;
    if (uploader == null || _stopping) return;
    _publish(); // Show the new queue length right away.
    await uploader.flush();
    _publish();
  }

  void _publish() {
    final uploader = _uploader;
    final queue = _queue;
    final status = TrackingStatus(
      lastSent: uploader?.lastSent,
      lastSentAt: uploader?.lastSentAt,
      lastFixAt: _lastFixAt,
      queueLength: queue?.length ?? 0,
      droppedCount: queue?.droppedCount ?? 0,
      error:
          _configError ?? _locationError ?? _queueError ?? uploader?.lastError,
    );
    FlutterForegroundTask.sendDataToMain(status.toMessage());
    _updateNotification(status);
  }

  void _updateNotification(TrackingStatus status) {
    // Fixed texts only: the notification is visible on the lock screen, and
    // error details (which may name the server) stay inside the app.
    final text = status.error != null
        ? status.queueLength > 0
              ? 'Not sending · ${status.queueLength} positions waiting'
              : 'Problem · open the app for details'
        : status.queueLength > 1
        ? 'Sending positions · ${status.queueLength} waiting'
        : 'Sending positions';
    if (text == _notificationText) return;
    _notificationText = text;
    FlutterForegroundTask.updateService(notificationText: text);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _stopping = true;
    await _positions?.cancel();
    _positions = null;
    // Abort a running send, let the queue write that follows finish, then
    // hand the queue file over to a restarted service.
    _uploader?.stop();
    _client?.close();
    try {
      await _uploader?.idle.timeout(const Duration(seconds: 5));
      // Read the queue lock only now, so it includes writes the flush made
      // while finishing.
      await _queue?.idle.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Give up waiting; ownership is released below either way.
    }
    _releaseQueueOwnership();
  }
}
