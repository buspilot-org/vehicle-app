import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:traccar_client_sdk/traccar_client_sdk.dart' as sdk;

import '../config/config_store.dart';
import '../config/tracking_config.dart';
import '../device/device_channel.dart';
import 'companion_status.dart';
import 'companion_task_handler.dart';
import 'traccar_config.dart';

/// Call once in `main()` before `runApp`.
void initTrackingCommunication() {
  FlutterForegroundTask.initCommunicationPort();
}

/// The Traccar Client SDK's notification ID and channel
/// (`TrackerService.NOTIFICATION_ID` / `CHANNEL_ID` in SDK 1.1.4).
///
/// Our background service posts its foreground notification with the same
/// ID, so both services share one notification: Android keeps a notification
/// that another foreground service of the app still uses when one of them
/// stops. If a future SDK changes the ID, the phone just shows two
/// notifications; nothing breaks.
const sharedNotificationId = 0x7AC0;
const sharedNotificationChannelId = 'tracker';

/// UI-side control of tracking.
///
/// Two parts run while tracking is on:
/// - The Traccar Client SDK sends positions to Traccar. It runs natively in
///   its own foreground service, pauses GPS while the bus is parked (stop
///   detection), buffers positions in SQLite and restarts itself after a
///   reboot. It has no position callback; the app only sees its log.
/// - Our background service ([companionTaskCallback], flutter_foreground_task)
///   runs tag scanning, device health and the vehicle event upload in a
///   Flutter engine of its own, so it keeps running without the UI and
///   restarts after a reboot (autoRunOnBoot).
class TrackingController extends ChangeNotifier {
  TrackingController({ConfigStore? store, sdk.TraccarClientSdk? traccar})
    : store = store ?? ConfigStore(),
      _sdk = traccar ?? sdk.TraccarClientSdk();

  final ConfigStore store;
  final sdk.TraccarClientSdk _sdk;

  /// Bump when the background service's callback, notification ID or type
  /// changes. A service started by an older app version (it keeps running
  /// across an app update, with the old settings) is then stopped and
  /// started again.
  static const serviceVersion = 2;

  /// Plain http:// servers are allowed in debug builds only.
  static const allowHttp = kDebugMode;

  TrackingConfig? config;

  /// Whether the SDK is tracking (positions).
  bool running = false;

  /// Whether our background service (tags, health, events) is running.
  bool companionRunning = false;
  CompanionStatus companion = const CompanionStatus();
  String? startError;
  List<sdk.LogEntry> logs = const [];
  Completer<void>? _tripEnded;
  bool _busy = false;

  bool get busy => _busy;
  bool get configValid => config?.isValid(allowHttp: allowHttp) ?? false;

  Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        // The SDK's channel: it exists already (the SDK creates it when the
        // process starts), so these name/importance values only apply if not.
        channelId: sharedNotificationChannelId,
        channelName: 'Location tracking',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Retry sending queued events every 15 seconds (the uploader's
        // backoff decides whether it actually sends).
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        // No wake lock of our own: the SDK holds one while the bus moves
        // (TrackingConfig → wakeLock), and the phone may sleep while parked.
        allowWakeLock: false,
        allowWifiLock: false,
      ),
    );
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    if (await FlutterForegroundTask.isRunningService &&
        await store.serviceVersion() != serviceVersion) {
      // Restarted after the update with the old version's task (version 1
      // sent positions itself); resumeIfEnabled starts the current one.
      await FlutterForegroundTask.stopService();
    }
    if (await store.serviceVersion() == null) await _removeVersion1Leftovers();
    config = await store.load();
    if (configValid) {
      try {
        // Installs the SDK's tracker with our settings unless it is already
        // running in this process (for example started after a reboot).
        await _sdk.init(toTraccarConfig(config!));
      } on PlatformException catch (e) {
        startError = 'Could not set up tracking: ${e.message ?? e.code}';
      }
    }
    await _refreshRunning();
    if (companionRunning) {
      FlutterForegroundTask.sendDataToTask(statusRequestMessage);
    }
    await refreshLogs();
  }

  /// Version 1 kept unsent positions in its own queue file and used its own
  /// notification channel. Positions now go through the SDK, so the file is
  /// never sent; delete it rather than keep location history on the phone.
  Future<void> _removeVersion1Leftovers() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/tracking/position_queue.jsonl');
      if (await file.exists()) await file.delete();
      await DeviceChannel().deleteNotificationChannel('buspilot_tracking');
    } on Exception {
      // Best effort; tried again on the next start until a service runs.
    }
  }

  Future<void> _refreshRunning() async {
    try {
      running = await _sdk.isTracking();
    } on PlatformException {
      running = false;
    }
    companionRunning = await FlutterForegroundTask.isRunningService;
    notifyListeners();
  }

  /// Starts tracking again if the user had it switched on but a part is not
  /// running (for example after the app was force-stopped).
  Future<void> resumeIfEnabled() async {
    await _refreshRunning();
    final staleService =
        companionRunning && await store.serviceVersion() != serviceVersion;
    if ((!running || !companionRunning || staleService) &&
        configValid &&
        await store.isTrackingEnabled()) {
      await start();
    }
  }

  void _onTaskData(Object data) {
    if (data is Map && data['type'] == tripEndedMessage) {
      _tripEnded?.complete();
      _tripEnded = null;
      return;
    }
    final s = CompanionStatus.fromMessage(data);
    if (s == null) return;
    companion = s;
    notifyListeners();
  }

  /// Reads the SDK's diagnostic log (newest last).
  Future<void> refreshLogs() async {
    try {
      final all = await _sdk.getLogs();
      logs = all.length > 200 ? all.sublist(all.length - 200) : all;
    } on PlatformException {
      logs = const [];
    }
    notifyListeners();
  }

  Future<void> clearLogs() async {
    try {
      await _sdk.clearLogs();
    } on PlatformException {
      // Nothing to clear.
    }
    await refreshLogs();
  }

  Future<void> start() => _guard(_start);

  Future<void> _start() async {
    startError = null;
    final config = this.config;
    if (config == null || !configValid) {
      startError = 'Complete the settings first.';
      return;
    }
    try {
      final c = toTraccarConfig(config);
      await _sdk.init(c); // no-op if a tracker exists
      // Apply the config even if a tracker exists: it may carry the config
      // an older app version saved (fixed values like wakeLock can change).
      await _sdk.setConfig(c);
      // Asks for missing permissions itself; the permission screen grants
      // them all beforehand, so normally nothing is shown here.
      await _sdk.start();
    } on PlatformException catch (e) {
      startError = 'Could not start tracking: ${e.message ?? e.code}';
      await _refreshRunning();
      return;
    }
    await store.setTrackingEnabled(true);
    await _startCompanion();
    await _refreshRunning();
  }

  Future<void> _startCompanion() async {
    if (await FlutterForegroundTask.isRunningService) {
      if (await store.serviceVersion() == serviceVersion) return;
      // An older version's task, restarted by the app update after init()
      // checked (MY_PACKAGE_REPLACED races with the app start).
      await FlutterForegroundTask.stopService();
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: sharedNotificationId,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: 'Buspilot',
      notificationText: trackingNotificationText,
      callback: companionTaskCallback,
    );
    if (result is ServiceRequestSuccess) {
      await store.setServiceVersion(serviceVersion);
    } else if (result is ServiceRequestFailure) {
      startError =
          'Positions are sent, but tags and device health are not: '
          '${result.error}';
    }
  }

  Future<void> stop() => _guard(() async {
    if (await FlutterForegroundTask.isRunningService) {
      // Let the service record the tags still on board and send what it can.
      final ended = _tripEnded = Completer<void>();
      FlutterForegroundTask.sendDataToTask(endTripMessage);
      try {
        await ended.future.timeout(const Duration(seconds: 8));
      } on TimeoutException {
        // Stop anyway; queued events are sent on the next start.
      }
      _tripEnded = null;
      await FlutterForegroundTask.stopService();
    }
    try {
      await _sdk.stop();
      // Only now: if the SDK did not stop, it would come back after a
      // reboot, and the app must still know that tracking is on.
      await store.setTrackingEnabled(false);
    } on PlatformException catch (e) {
      startError = 'Could not stop tracking: ${e.message ?? e.code}';
    }
    companion = const CompanionStatus();
    await _refreshRunning();
  });

  /// Saves new settings and applies them: the SDK gets the new
  /// configuration (it restarts its tracker internally) and our background
  /// service is restarted.
  Future<void> saveConfig(TrackingConfig newConfig) async {
    await store.save(newConfig);
    config = newConfig;
    notifyListeners();
    // Wait for a start/stop in progress, then apply as one guarded step so
    // the new settings always take effect.
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _guard(() async {
      startError = null;
      if (configValid) {
        try {
          final c = toTraccarConfig(newConfig);
          await _sdk.init(c); // no-op if a tracker exists
          await _sdk.setConfig(c);
        } on PlatformException catch (e) {
          startError = 'Could not apply the settings: ${e.message ?? e.code}';
        }
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        if (configValid) await _startCompanion();
      }
      await _refreshRunning();
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }
}
