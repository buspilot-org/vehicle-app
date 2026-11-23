import 'package:material_ui/material_ui.dart';

import 'tracking_permissions.dart';

/// Walks through the Android permissions tracking needs, one step at a time.
/// Shown on first start and whenever a required permission is missing.
class PermissionScreen extends StatefulWidget {
  const PermissionScreen({
    super.key,
    this.permissions = const TrackingPermissions(),
  });

  final TrackingPermissions permissions;

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  PermissionState? _state;

  /// Set once "all the time" was requested. If Android then still reports
  /// "while in use", it no longer shows the request (the user denied it
  /// before), so the step offers the app settings instead.
  bool _backgroundRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may come back from Android's settings pages.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await widget.permissions.check();
    if (mounted) setState(() => _state = s);
  }

  Future<void> _run(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final p = widget.permissions;
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'This phone sends the bus position to the Buspilot server, '
                  'also with the screen off. Please allow the following. '
                  'The app collects no personal data.',
                ),
                const SizedBox(height: 16),
                _Step(
                  number: 1,
                  title: 'Notifications',
                  text:
                      'A permanent notification shows that tracking is '
                      'running.',
                  done: s.notifications,
                  action: 'Allow',
                  onPressed: () => _run(p.requestNotifications),
                ),
                _Step(
                  number: 2,
                  title: 'Location',
                  text: s.locationDeniedForever
                      ? 'Location was denied. Open the app settings and '
                            'allow location.'
                      : 'Needed to know where the bus is.',
                  done: s.locationWhileInUse,
                  action: s.locationDeniedForever ? 'Open settings' : 'Allow',
                  onPressed: () => _run(p.requestLocation),
                ),
                _Step(
                  number: 3,
                  title: 'Location all the time',
                  text:
                      'Choose "Allow all the time", so tracking keeps '
                      'running with the screen off and restarts after the '
                      'phone reboots.'
                      '${_backgroundRequested ? ' In the app settings, open '
                                'Permissions › Location.' : ''}',
                  done: s.locationAlways,
                  enabled: s.locationWhileInUse,
                  action: _backgroundRequested ? 'Open settings' : 'Allow',
                  onPressed: _backgroundRequested
                      ? () => _run(p.openAppSettings)
                      : () => _run(() async {
                          await p.requestLocation();
                          _backgroundRequested = true;
                        }),
                ),
                _Step(
                  number: 4,
                  title: 'Location switched on',
                  text: 'Location must be on in the phone settings.',
                  done: s.locationServiceOn,
                  action: 'Open settings',
                  onPressed: () => _run(p.openLocationSettings),
                ),
                _Step(
                  number: 5,
                  title: 'No battery optimisation (recommended)',
                  text: 'Stops Android from pausing tracking to save power.',
                  done: s.batteryOptimizationOff,
                  action: 'Allow',
                  onPressed: () => _run(p.requestBatteryExemption),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: s.requiredGranted
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: Text(s.requiredGranted ? 'Done' : 'Steps 1–4 needed'),
                ),
              ],
            ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.text,
    required this.done,
    required this.action,
    required this.onPressed,
    this.enabled = true,
  });

  final int number;
  final String title;
  final String text;
  final bool done;
  final bool enabled;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: done
            ? const Icon(Icons.check_circle, color: Colors.green)
            : CircleAvatar(radius: 14, child: Text('$number')),
        title: Text(title),
        subtitle: Text(text),
        trailing: done
            ? null
            : TextButton(
                onPressed: enabled ? onPressed : null,
                child: Text(action),
              ),
      ),
    );
  }
}
