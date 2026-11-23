import 'package:material_ui/material_ui.dart';

import 'battery_snapshot.dart';
import 'device_channel.dart';
import 'device_health_monitor.dart';
import 'device_warnings.dart';

/// Small status screen: battery values, warnings and dedicated-phone state.
class DeviceStatusScreen extends StatefulWidget {
  const DeviceStatusScreen({super.key, this.monitor});

  /// Injected in tests; otherwise the screen creates and owns one.
  final DeviceHealthMonitor? monitor;

  @override
  State<DeviceStatusScreen> createState() => _DeviceStatusScreenState();
}

class _DeviceStatusScreenState extends State<DeviceStatusScreen>
    with WidgetsBindingObserver {
  late final DeviceHealthMonitor _monitor;
  late final bool _ownsMonitor;

  @override
  void initState() {
    super.initState();
    _ownsMonitor = widget.monitor == null;
    _monitor = widget.monitor ?? DeviceHealthMonitor();
    if (_ownsMonitor) _monitor.start();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock task state changes while the app is paused (pinning dialog).
    if (state == AppLifecycleState.resumed) _monitor.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsMonitor) _monitor.dispose();
    super.dispose();
  }

  Future<void> _enterKiosk() async {
    await _monitor.channel.enterKiosk();
    await _monitor.refresh();
  }

  Future<void> _exitKiosk() async {
    await _monitor.channel.exitKiosk();
    await _monitor.refresh();
  }

  Future<void> _openBatterySettings() async {
    final opened = await _monitor.channel.openBatteryOptimizationSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the settings. Leave kiosk mode first.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device status')),
      body: ListenableBuilder(
        listenable: _monitor,
        builder: (context, _) => RefreshIndicator(
          onRefresh: _monitor.refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_monitor.error != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(_monitor.error!),
                  ),
                ),
              _WarningsCard(warnings: _monitor.warnings),
              _BatteryCard(snapshot: _monitor.snapshot),
              _DedicatedPhoneCard(
                state: _monitor.deviceState,
                onEnterKiosk: _enterKiosk,
                onExitKiosk: _exitKiosk,
                onOpenBatterySettings: _openBatterySettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningsCard extends StatelessWidget {
  const _WarningsCard({required this.warnings});

  final List<DeviceWarning> warnings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (warnings.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.check_circle_outline),
          title: Text('No warnings'),
        ),
      );
    }
    return Card(
      color: scheme.errorContainer,
      child: Column(
        children: [
          for (final w in warnings)
            ListTile(
              leading: Icon(
                Icons.warning_amber,
                color: scheme.onErrorContainer,
              ),
              title: Text(
                w.message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
        ],
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({required this.snapshot});

  final BatterySnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    String orDash(Object? v, [String unit = '']) => v == null ? '–' : '$v$unit';
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(title: Text('Battery')),
          if (s == null)
            const ListTile(title: Text('No reading yet'))
          else ...[
            _row('Level', orDash(s.level, ' %')),
            _row('Status', s.status.name),
            _row('Power source', s.source.name),
            _row(
              'Temperature',
              orDash(s.temperatureC?.toStringAsFixed(1), ' °C'),
            ),
            _row('Health', s.health.name),
            _row('Voltage', orDash(s.voltageMv, ' mV')),
            _row('Charge cycles', orDash(s.cycleCount)),
          ],
        ],
      ),
    );
  }
}

class _DedicatedPhoneCard extends StatelessWidget {
  const _DedicatedPhoneCard({
    required this.state,
    required this.onEnterKiosk,
    required this.onExitKiosk,
    required this.onOpenBatterySettings,
  });

  final DeviceState state;
  final VoidCallback onEnterKiosk;
  final VoidCallback onExitKiosk;
  final VoidCallback onOpenBatterySettings;

  @override
  Widget build(BuildContext context) {
    final inLockTask = state.lockTaskState != LockTaskState.none;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(title: Text('Dedicated phone')),
          _row('Device owner', state.deviceOwner ? 'yes' : 'no'),
          _row('Kiosk', switch (state.lockTaskState) {
            LockTaskState.locked => 'locked (device owner)',
            LockTaskState.pinned => 'screen pinned',
            LockTaskState.none => 'off',
          }),
          _row(
            'Battery optimisation',
            state.ignoringBatteryOptimizations
                ? 'disabled for this app'
                : 'active',
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!inLockTask)
                  FilledButton(
                    onPressed: onEnterKiosk,
                    child: const Text('Start kiosk mode'),
                  ),
                if (inLockTask)
                  // Long press only, so a stray tap does not leave kiosk mode.
                  OutlinedButton(
                    onPressed: () {},
                    onLongPress: onExitKiosk,
                    child: const Text('Leave kiosk mode (long-press)'),
                  ),
                if (!state.ignoringBatteryOptimizations)
                  OutlinedButton(
                    onPressed: onOpenBatterySettings,
                    child: const Text('Battery optimisation settings'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _row(String label, String value) =>
    ListTile(dense: true, title: Text(label), trailing: Text(value));
