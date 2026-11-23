import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'ble_permissions.dart';
import 'presence_tracker.dart';
import 'tag_filter.dart';
import 'tag_scan_service.dart';

/// Debug screen: start/stop scanning, list present tags and recent events.
///
/// Uses [TagFilter.any] unless a [service] is passed, so every iBeacon and
/// Eddystone-UID nearby shows up; handy to read a new tag's IDs.
class BleDebugScreen extends StatefulWidget {
  const BleDebugScreen({super.key, this.service});

  /// Service to show. If null, the screen creates and owns one.
  final TagScanService? service;

  @override
  State<BleDebugScreen> createState() => _BleDebugScreenState();
}

class _BleDebugScreenState extends State<BleDebugScreen> {
  late final TagScanService _service;
  late final bool _ownsService;
  final _log = <PresenceEvent>[];
  StreamSubscription<PresenceEvent>? _eventSub;
  Timer? _ticker;
  final _permissions = const BlePermissions();

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? TagScanService(filter: const TagFilter.any());
    _eventSub = _service.tracker.events.listen((e) {
      setState(() {
        _log.insert(0, e);
        if (_log.length > 30) _log.removeLast();
      });
    });
    // Refresh "seen N s ago" even when no new sightings arrive.
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _eventSub?.cancel();
    if (_ownsService) unawaited(_service.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_service.isRunning) {
      await _service.stop();
      return;
    }
    if (await _permissions.check() != BlePermissionStatus.granted) {
      final result = await _permissions.request();
      if (result == BlePermissionStatus.permanentlyDenied) {
        await _permissions.openSettings();
        return;
      }
    }
    await _service.start();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('BLE tags (debug)')),
      floatingActionButton: ValueListenableBuilder(
        valueListenable: _service.state,
        builder: (context, state, _) => FloatingActionButton.extended(
          onPressed: _toggle,
          icon: Icon(
            _service.isRunning ? Icons.stop : Icons.bluetooth_searching,
          ),
          label: Text(_service.isRunning ? 'Stop' : 'Scan'),
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_service.state, _service.tracker]),
        builder: (context, _) {
          final tags = _service.tracker.present;
          final now = DateTime.now();
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              ListTile(
                title: Text('State: ${_service.state.value}'),
                subtitle: Text('${tags.length} tag(s) present'),
              ),
              const Divider(),
              for (final tag in tags)
                ListTile(
                  dense: true,
                  title: Text(tag.tagId, style: theme.textTheme.bodySmall),
                  subtitle: Text(
                    '${tag.address} · seen ${now.difference(tag.lastSeen).inSeconds} s ago'
                    ' · ${tag.sightings} sightings',
                  ),
                  trailing: Text(
                    '${tag.smoothedRssi.round()} dBm\n(${tag.rssi})',
                    textAlign: TextAlign.end,
                  ),
                ),
              if (_log.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('Events', style: theme.textTheme.titleSmall),
                ),
                for (final e in _log)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      e is TagEntered ? Icons.login : Icons.logout,
                      size: 18,
                    ),
                    title: Text(e.tagId, style: theme.textTheme.bodySmall),
                    subtitle: Text(_time(e.time)),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}
