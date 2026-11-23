import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../ble/ble_debug_screen.dart';
import '../config/settings_screen.dart';
import '../device/device_status_screen.dart';
import 'permission_screen.dart';
import 'tracking_controller.dart';
import 'tracking_permissions.dart';
import 'tracking_status.dart';

/// Main screen: tracking state, last sent position and queue length.
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

  TrackingController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermissions();
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
                  subtitle: const Text('Enter the server URL.'),
                  trailing: TextButton(
                    onPressed: _openSettings,
                    child: const Text('Open'),
                  ),
                ),
              ),
            _StateCard(controller: _c, canStart: _canStart),
            _StatusCard(status: _c.status, deviceId: _c.config?.deviceId),
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
                Text(
                  c.running ? 'Tracking is on' : 'Tracking is off',
                  style: theme.textTheme.titleLarge,
                ),
              ],
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.deviceId});

  final TrackingStatus status;
  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    final p = status.lastSent;
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_upload),
            title: const Text('Last sent position'),
            subtitle: Text(
              p == null
                  ? 'Nothing sent yet'
                  : '${p.latitude.toStringAsFixed(5)}, '
                        '${p.longitude.toStringAsFixed(5)}'
                        '${p.accuracy != null ? ' (±${p.accuracy!.round()} m)' : ''}\n'
                        'Fix ${_time(p.timestamp)} · '
                        'sent ${_time(status.lastSentAt)}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.inbox),
            title: const Text('Waiting to be sent'),
            subtitle: Text(
              '${status.queueLength} positions'
              '${status.droppedCount > 0 ? ' · ${status.droppedCount} dropped (queue full)' : ''}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.my_location),
            title: const Text('Last location fix'),
            subtitle: Text(_time(status.lastFixAt)),
          ),
          if (status.error != null)
            ListTile(
              leading: Icon(Icons.error, color: theme.colorScheme.error),
              title: const Text('Problem'),
              subtitle: Text(status.error!),
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
