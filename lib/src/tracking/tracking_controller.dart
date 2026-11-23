import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../config/config_store.dart';
import '../config/tracking_config.dart';
import 'tracking_status.dart';
import 'tracking_task_handler.dart';

/// Call once in `main()` before `runApp`.
void initTrackingCommunication() {
  FlutterForegroundTask.initCommunicationPort();
}

/// UI-side control of the tracking foreground service.
class TrackingController extends ChangeNotifier {
  TrackingController({ConfigStore? store}) : store = store ?? ConfigStore();

  final ConfigStore store;

  static const _serviceId = 4711;

  /// Plain http:// servers are allowed in debug builds only.
  static const allowHttp = kDebugMode;

  TrackingConfig? config;
  bool running = false;
  TrackingStatus status = const TrackingStatus();
  String? startError;
  bool _busy = false;

  bool get busy => _busy;
  bool get configValid => config?.isValid(allowHttp: allowHttp) ?? false;

  Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'buspilot_tracking',
        channelName: 'Location tracking',
        channelDescription: 'Shown while the bus position is being sent.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Retry sending queued positions every 30 seconds.
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    config = await store.load();
    running = await FlutterForegroundTask.isRunningService;
    if (running) FlutterForegroundTask.sendDataToTask(statusRequestMessage);
    notifyListeners();
  }

  /// Starts tracking again if the user had it switched on but the service is
  /// not running (for example after the app was force-stopped).
  Future<void> resumeIfEnabled() async {
    if (!running && configValid && await store.isTrackingEnabled()) {
      await start();
    }
  }

  void _onTaskData(Object data) {
    final s = TrackingStatus.fromMessage(data);
    if (s == null) return;
    status = s;
    notifyListeners();
  }

  Future<void> start() => _guard(_startService);

  Future<void> _startService() async {
    startError = null;
    if (!configValid) {
      startError = 'Complete the settings first.';
      return;
    }
    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: 'Buspilot',
      notificationText: 'Starting location tracking',
      callback: trackingTaskCallback,
    );
    if (result is ServiceRequestFailure) {
      startError = 'Could not start tracking: ${result.error}';
    } else {
      await store.setTrackingEnabled(true);
    }
    running = await FlutterForegroundTask.isRunningService;
  }

  Future<void> stop() => _guard(() async {
    await store.setTrackingEnabled(false);
    await FlutterForegroundTask.stopService();
    running = await FlutterForegroundTask.isRunningService;
    status = TrackingStatus(
      lastSent: status.lastSent,
      lastSentAt: status.lastSentAt,
      queueLength: status.queueLength,
      droppedCount: status.droppedCount,
    );
  });

  /// Saves new settings and restarts the service so it uses them.
  Future<void> saveConfig(TrackingConfig newConfig) async {
    await store.save(newConfig);
    config = newConfig;
    notifyListeners();
    // Restart as one guarded step, so a start/stop tap in between cannot
    // interleave with it.
    await _guard(() async {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.stopService();
      running = false;
      await _startService();
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
