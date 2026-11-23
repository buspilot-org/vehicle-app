import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../ble/ble_debug_screen.dart';
import '../config/settings_screen.dart';
import '../device/device_status_screen.dart';
import 'permission_screen.dart';
import 'tracking_controller.dart';
import 'tracking_permissions.dart';
import 'companion_status.dart';

/// Main screen: tracking on/off, the background service (tags, health,
/// events) and the Traccar Client SDK's log (the SDK reports no positions to
/// the app, so its log is the only window into it).
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({
    super.key,
    required this.controller,
    this.permissions = const TrackingPermissions(),
  });

  final TrackingController controller;
  final TrackingPermissions permissions;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with WidgetsBindingObserver {
  PermissionState? _permissions;
  bool _permissionScreenOpen = false;
  Timer? _logTimer;

  TrackingController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startup();
    _startLogTimer();
  }

  @override
  void dispose() {
    _logTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      _c.refreshLogs();
      _startLogTimer();
    } else if (state == AppLifecycleState.paused) {
      _logTimer?.cancel();
      _logTimer = null;
    }
  }

  /// The SDK has no callbacks; poll its log while the screen is visible.
  void _startLogTimer() {
    _logTimer?.cancel();
    _logTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _c.refreshLogs(),
    );
  }

  Future<void> _startup() async {
    await _c.init();
    await _checkPermissions(openFlow: true);
    if (_permissions?.requiredGranted ?? false) await _c.resumeIfEnabled();
  }

  Future<void> _checkPermissions({bool openFlow = false}) async {
    final s = await widget.permissions.check();
    if (!mounted) return;
    setState(() => _permissions = s);
    if (openFlow && !s.requiredGranted) await _openPermissions();
  }

  Future<void> _openPermissions() async {
    if (_permissionScreenOpen) return;
    _permissionScreenOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => PermissionScreen(permissions: widget.permissions),
      ),
    );
    _permissionScreenOpen = false;
    await _checkPermissions();
  }

  Future<void> _openSettings() async {
    final config = _c.config;
    if (config == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          initial: config,
          onSave: _c.saveConfig,
          allowHttp: TrackingController.allowHttp,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buspilot'),
        actions: [
          // Not in release builds: the debug screen shows MAC addresses.
          if (!kReleaseMode)
            IconButton(
              tooltip: 'BLE tags (debug)',
              icon: const Icon(Icons.bluetooth_searching),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BleDebugScreen()),
              ),
            ),
          IconButton(
            tooltip: 'Device status',
            icon: const Icon(Icons.battery_std),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DeviceStatusScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_permissions != null && !_permissions!.requiredGranted)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning),
                  title: const Text('Permissions missing'),
                  subtitle: const Text('Tracking cannot run without them.'),
                  trailing: TextButton(
                    onPressed: _openPermissions,
                    child: const Text('Fix'),
                  ),
                ),
              ),
            if (_c.config != null && !_c.configValid)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Settings incomplete'),
                  subtitle: const Text('Check the server URL and the IDs.'),
                  trailing: TextButton(
                    onPressed: _openSettings,
                    child: const Text('Open'),
                  ),
                ),
              ),
            _StateCard(controller: _c, canStart: _canStart),
            _CompanionCard(
              status: _c.companion,
              running: _c.companionRunning,
              deviceId: _c.config?.deviceId,
            ),
            _SdkLogCard(controller: _c),
          ],
        ),
      ),
    );
  }

  bool get _canStart =>
      _c.configValid && (_permissions?.requiredGranted ?? false);
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.controller, required this.canStart});

  final TrackingController controller;
  final bool canStart;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  c.running ? Icons.gps_fixed : Icons.gps_off,
                  color: c.running ? Colors.green : theme.disabledColor,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    c.running ? 'Tracking is on' : 'Tracking is off',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              c.running
                  ? 'Positions go to Traccar. GPS pauses while the bus is '
                        'parked.'
                  : 'Positions are not sent.',
            ),
            if (c.startError != null) ...[
              const SizedBox(height: 8),
              Text(
                c.startError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            c.running
                ? OutlinedButton(
                    onPressed: c.busy ? null : c.stop,
                    child: const Text('Stop tracking'),
                  )
                : FilledButton(
                    onPressed: c.busy || !canStart ? null : c.start,
                    child: const Text('Start tracking'),
                  ),
          ],
        ),
      ),
    );
  }
}

class _CompanionCard extends StatelessWidget {
  const _CompanionCard({
    required this.status,
    required this.running,
    required this.deviceId,
  });

  final CompanionStatus status;
  final bool running;
  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final theme = Theme.of(context);
    final eventText = StringBuffer(
      '${s.eventQueueLength} waiting · ${s.eventsSent} sent',
    );
    if (s.lastEventsSentAt != null) {
      eventText.write(' · last ${_time(s.lastEventsSentAt)}');
    }
    if (s.eventsDropped > 0) {
      eventText.write(' · ${s.eventsDropped} dropped (queue full)');
    }
    if (!s.engineConfigured) {
      eventText.write('\nNo engine URL set: events stay on the phone.');
    }
    if (s.eventError != null) {
      eventText.write('\n${s.eventError}');
      if (s.nextEventAttempt != null) {
        eventText.write(' · retry ${_time(s.nextEventAttempt)}');
      }
    }
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              running ? Icons.sync : Icons.sync_disabled,
              color: running ? Colors.green : theme.disabledColor,
            ),
            title: const Text('Tags and device health'),
            subtitle: Text(
              running ? 'Running in the background' : 'Not running',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.outbox),
            title: const Text('Events to the Buspilot engine'),
            subtitle: Text(eventText.toString()),
          ),
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('Tags'),
            subtitle: Text(
              !s.tagsConfigured
                  ? 'No tag IDs set: not scanning'
                  : '${s.tagsPresent} on board · ${s.tagScan ?? '–'}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.battery_std),
            title: const Text('Battery'),
            subtitle: Text(
              '${s.batteryLevel != null ? '${s.batteryLevel} %' : '–'}'
              '${s.warnings.isEmpty ? '' : ' · ${s.warnings.join(', ')}'}',
            ),
          ),
          if (s.error != null)
            ListTile(
              leading: Icon(Icons.error, color: theme.colorScheme.error),
              title: const Text('Problem'),
              subtitle: Text(s.error!),
            ),
          ListTile(
            leading: const Icon(Icons.badge),
            title: const Text('Device ID'),
            subtitle: Text(deviceId ?? '–'),
          ),
        ],
      ),
    );
  }
}

/// The Traccar Client SDK's diagnostic log, newest first.
class _SdkLogCard extends StatelessWidget {
  const _SdkLogCard({required this.controller});

  final TrackingController controller;

  @override
  Widget build(BuildContext context) {
    final logs = controller.logs;
    final theme = Theme.of(context);
    final upload = lastUploadLine(logs.map((e) => e.message).toList());
    final uploadEntry = upload == null
        ? null
        : logs.lastWhere((e) => e.message == upload);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('Last position upload'),
            subtitle: Text(
              uploadEntry == null
                  ? 'None in the log'
                  : '${_time(DateTime.fromMillisecondsSinceEpoch(uploadEntry.time))} · '
                        '${uploadEntry.message}',
            ),
          ),
          ExpansionTile(
            leading: const Icon(Icons.article),
            title: const Text('Traccar SDK log'),
            subtitle: Text('${logs.length} entries'),
            expandedAlignment: Alignment.centerLeft,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in logs.reversed.take(50))
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  child: Text(
                    '${_time(DateTime.fromMillisecondsSinceEpoch(e.time))}  '
                    '${e.message}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: controller.refreshLogs,
                    child: const Text('Refresh'),
                  ),
                  TextButton(
                    onPressed: controller.clearLogs,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The newest SDK log line about a position upload ("Upload response 200",
/// "Upload error: ..."), or null.
@visibleForTesting
String? lastUploadLine(List<String> messages) {
  for (final m in messages.reversed) {
    if (m.startsWith('Upload response') || m.startsWith('Upload error')) {
      return m;
    }
  }
  return null;
}

String _time(DateTime? t) {
  if (t == null) return '–';
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay =
      l.year == now.year && l.month == now.month && l.day == now.day;
  final date = sameDay ? '' : '${l.year}-${two(l.month)}-${two(l.day)} ';
  return '$date${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}
