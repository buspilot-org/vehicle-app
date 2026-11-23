import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../ble/presence_tracker.dart';
import '../ble/tag_filter.dart';
import '../ble/tag_scan_service.dart';
import '../config/config_store.dart';
import '../device/device_health_monitor.dart';
import '../events/events.dart';
import 'companion_status.dart';

/// Entry point of the background service isolate. Also runs after a reboot
/// or app update (autoRunOnBoot), without the UI.
@pragma('vm:entry-point')
void companionTaskCallback() {
  FlutterForegroundTask.setTaskHandler(CompanionTaskHandler());
}

/// Process-wide name that the isolate owning the event queue file registers.
/// After a restart, the old service isolate can still be shutting down while
/// the new one starts (both run in the same process, so a file lock would
/// not tell them apart).
const _queueOwnerName = 'org.buspilot.events.queueOwner';

/// Message the UI sends to ask the service for a fresh [CompanionStatus].
const statusRequestMessage = 'companionStatusRequest';

/// Message the UI sends before it stops tracking: the service records
/// `tags_on_board`, stops scanning, tries to send the queue and answers with
/// [tripEndedMessage].
const endTripMessage = 'companionEndTrip';
const tripEndedMessage = 'companionTripEnded';

/// Runs inside our foreground service, next to the Traccar Client SDK's own
/// service (which sends the positions): scans for the operator's tags, reads
/// the battery, turns both into vehicle events and sends them to the engine.
class CompanionTaskHandler extends TaskHandler {
  JsonlQueue<VehicleEvent>? _queue;
  EventUploader? _uploader;
  http.Client? _client;
  TagFilter _filter = TagFilter();
  TagScanService? _scan;
  StreamSubscription<PresenceEvent>? _presence;
  DeviceHealthMonitor? _health;
  final _healthEvents = HealthEventScheduler();
  String? _error;
  bool _stopping = false;
  bool _tripEnded = false;
  ReceivePort? _ownerPort;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final config = await ConfigStore().load();
    if (!config.isValid(allowHttp: kDebugMode)) {
      _error = 'Settings are incomplete. Open the app to fix them.';
      _publish();
      return;
    }
    if (!await _acquireQueueOwnership()) return; // Stopped while waiting.
    try {
      final dir = await getApplicationSupportDirectory();
      _queue = await JsonlQueue.open<VehicleEvent>(
        File('${dir.path}/events/vehicle_events.jsonl'),
        toJson: (e) => e.toJson(),
        fromJson: VehicleEvent.fromJson,
        maxLength: 20000,
      );
    } on Exception catch (e) {
      _error = 'Could not open the event queue: $e';
      _publish();
      return;
    }
    if (_stopping) return;
    EventSender? sender;
    if (config.engineConfigured) {
      final client = http.Client();
      _client = client;
      sender = HttpEventSender(
        client: client,
        engineUrl: config.engineUrl,
        vehicleToken: config.vehicleToken,
      );
    }
    _uploader = EventUploader(
      queue: _queue!,
      deviceId: config.deviceId,
      sender: sender,
    );

    _filter = config.tagFilter;
    if (!_filter.isEmpty) {
      final scan = TagScanService(filter: _filter);
      _scan = scan;
      _presence = scan.tracker.events.listen(
        (e) => _record(tagEventFor(e, _filter)),
      );
      scan.state.addListener(_publish);
      unawaited(scan.start());
    }

    final health = DeviceHealthMonitor(readDeviceState: false);
    _health = health;
    health.addListener(_onHealth);
    health.start();

    unawaited(_flush());
  }

  void _onHealth() {
    final health = _health;
    if (health == null) return;
    _record(_healthEvents.onReading(health.snapshot, health.warnings));
    _publish();
  }

  void _record(VehicleEvent? event) {
    final uploader = _uploader;
    if (event == null || uploader == null || _stopping) return;
    unawaited(
      uploader
          .record(event)
          .then(
            (_) => _publish(),
            onError: (Object e) {
              // For example a full disk. The event is lost; say so.
              _error = 'Could not store an event: $e';
              _publish();
            },
          ),
    );
  }

  /// Waits until no other isolate owns the queue file. After 20 seconds the
  /// old owner is taken to be gone (for example killed during shutdown).
  /// Returns false if this service is stopped while waiting.
  Future<bool> _acquireQueueOwnership() async {
    final port = ReceivePort();
    _ownerPort = port;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!IsolateNameServer.registerPortWithName(
      port.sendPort,
      _queueOwnerName,
    )) {
      if (_stopping || _ownerPort != port) {
        port.close();
        return false;
      }
      if (DateTime.now().isAfter(deadline)) {
        IsolateNameServer.removePortNameMapping(_queueOwnerName);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    if (_stopping) {
      _releaseQueueOwnership();
      return false;
    }
    return true;
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

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_flush());

  @override
  void onReceiveData(Object data) {
    if (data == statusRequestMessage) _publish();
    if (data == endTripMessage) unawaited(_endTrip());
  }

  /// Records which tags are still on board, stops scanning and tries to send
  /// everything before the UI stops the service.
  Future<void> _endTrip() async {
    if (!_tripEnded) {
      _tripEnded = true;
      final scan = _scan;
      final uploader = _uploader;
      if (scan != null && uploader != null) {
        // Read before stop(): stopping forgets the present tags.
        final event = tagsOnBoardEvent(
          scan.tracker.present,
          _filter,
          DateTime.now(),
        );
        await _presence?.cancel();
        _presence = null;
        await scan.stop();
        try {
          await uploader.queue.add(event);
        } on Exception catch (e) {
          _error = 'Could not store an event: $e';
        }
      }
      try {
        await _flush().timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // Sent on the next start.
      }
    }
    FlutterForegroundTask.sendDataToMain({'type': tripEndedMessage});
  }

  Future<void> _flush() async {
    final uploader = _uploader;
    if (uploader == null || _stopping) return;
    await uploader.flushIfDue();
    _publish();
  }

  void _publish() {
    final uploader = _uploader;
    final scan = _scan;
    final health = _health;
    final status = CompanionStatus(
      engineConfigured: uploader?.configured ?? false,
      eventQueueLength: uploader?.queue.length ?? 0,
      eventsDropped: uploader?.queue.droppedCount ?? 0,
      eventsSent: uploader?.sentCount ?? 0,
      lastEventsSentAt: uploader?.lastSentAt,
      nextEventAttempt: uploader?.nextAttempt,
      eventError: uploader?.lastError,
      tagsConfigured: !_filter.isEmpty,
      tagScan: scan?.state.value.toString(),
      tagsPresent: scan?.tracker.present.length ?? 0,
      batteryLevel: health?.snapshot?.level,
      warnings: [for (final w in health?.warnings ?? const []) w.code],
      error: _error ?? health?.error,
    );
    FlutterForegroundTask.sendDataToMain(status.toMessage());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _stopping = true;
    await _presence?.cancel();
    _presence = null;
    _health?.removeListener(_onHealth);
    _health?.dispose();
    final scan = _scan;
    scan?.state.removeListener(_publish);
    // Abort a running send, let the queue write that follows finish, then
    // hand the queue file over to a restarted service.
    _uploader?.stop();
    _client?.close();
    try {
      await scan?.dispose().timeout(const Duration(seconds: 5));
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
