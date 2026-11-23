import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'tracking_config.dart';

/// Edits [TrackingConfig]. [onSave] stores the settings (and applies them if
/// tracking is running).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initial,
    required this.onSave,
    required this.allowHttp,
  });

  final TrackingConfig initial;
  final Future<void> Function(TrackingConfig config) onSave;
  final bool allowHttp;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TrackingConfig _i = widget.initial;
  late final _serverUrl = TextEditingController(text: _i.serverUrl);
  late final _deviceId = TextEditingController(text: _i.deviceId);
  late final _interval = TextEditingController(text: '${_i.intervalSeconds}');
  late final _distance = TextEditingController(
    text: '${_i.distanceFilterMeters}',
  );
  late final _stopTimeout = TextEditingController(
    text: '${_i.stopTimeoutSeconds}',
  );
  late final _heartbeat = TextEditingController(text: '${_i.heartbeatSeconds}');
  late final _engineUrl = TextEditingController(text: _i.engineUrl);
  late final _token = TextEditingController(text: _i.vehicleToken);
  late final _iBeacon = TextEditingController(text: _i.iBeaconUuids.join('\n'));
  late final _eddystone = TextEditingController(
    text: _i.eddystoneNamespaces.join('\n'),
  );
  late TrackingAccuracy _accuracy = _i.accuracy;
  late bool _stopDetection = _i.stopDetection;
  bool _showToken = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _serverUrl,
      _deviceId,
      _interval,
      _distance,
      _stopTimeout,
      _heartbeat,
      _engineUrl,
      _token,
      _iBeacon,
      _eddystone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final config = TrackingConfig(
      serverUrl: _serverUrl.text.trim(),
      deviceId: _deviceId.text.trim(),
      intervalSeconds: int.parse(_interval.text),
      distanceFilterMeters: int.parse(_distance.text),
      accuracy: _accuracy,
      stopDetection: _stopDetection,
      // Hidden (and not validated) while stop detection is off.
      stopTimeoutSeconds: _validOr(
        _stopTimeout.text,
        validateStopTimeout,
        TrackingConfig.defaultStopTimeoutSeconds,
      ),
      heartbeatSeconds: _validOr(
        _heartbeat.text,
        validateHeartbeat,
        TrackingConfig.defaultHeartbeatSeconds,
      ),
      engineUrl: _engineUrl.text.trim(),
      vehicleToken: _token.text.trim(),
      iBeaconUuids: splitIds(_iBeacon.text),
      eddystoneNamespaces: splitIds(_eddystone.text),
    );
    try {
      await widget.onSave(config);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static int _validOr(
    String text,
    String? Function(int?) validate,
    int fallback,
  ) {
    final v = int.tryParse(text);
    return validate(v) == null ? v! : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final theme = Theme.of(context);
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(title, style: theme.textTheme.titleMedium),
    );
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Traccar', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _serverUrl,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://traccar.example.org:5055',
                helperText: 'Traccar OsmAnd endpoint',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (v) =>
                  validateServerUrl(v ?? '', allowHttp: widget.allowHttp),
            ),
            gap,
            TextFormField(
              controller: _deviceId,
              decoration: InputDecoration(
                labelText: 'Device ID',
                helperText: 'Register this ID in Traccar for this bus',
                suffixIcon: IconButton(
                  tooltip: 'New random ID',
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      setState(() => _deviceId.text = generateDeviceId()),
                ),
              ),
              autocorrect: false,
              validator: (v) => validateDeviceId((v ?? '').trim()),
            ),
            section('Positions'),
            DropdownButtonFormField<TrackingAccuracy>(
              initialValue: _accuracy,
              decoration: const InputDecoration(
                labelText: 'Accuracy',
                helperText:
                    'High: GPS with the interval below (recommended). '
                    'Highest: every GPS fix, about one per second.',
                helperMaxLines: 3,
              ),
              items: const [
                DropdownMenuItem(
                  value: TrackingAccuracy.highest,
                  child: Text('Highest'),
                ),
                DropdownMenuItem(
                  value: TrackingAccuracy.high,
                  child: Text('High (GPS)'),
                ),
                DropdownMenuItem(
                  value: TrackingAccuracy.medium,
                  child: Text('Medium (about 100 m)'),
                ),
                DropdownMenuItem(
                  value: TrackingAccuracy.low,
                  child: Text('Low (about 1 km)'),
                ),
              ],
              onChanged: (v) => setState(() => _accuracy = v ?? _accuracy),
            ),
            gap,
            TextFormField(
              controller: _interval,
              decoration: const InputDecoration(
                labelText: 'Interval (seconds)',
                helperText: 'Time between positions while driving',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              validator: (v) => validateInterval(int.tryParse(v ?? '')),
            ),
            gap,
            TextFormField(
              controller: _distance,
              decoration: const InputDecoration(
                labelText: 'Distance (metres)',
                helperText:
                    '0 = use the interval (recommended). More than 0: send '
                    'after moving this far instead; the interval is then '
                    'ignored.',
                helperMaxLines: 3,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              validator: (v) => validateDistanceFilter(int.tryParse(v ?? '')),
            ),
            gap,
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pause GPS while parked'),
              subtitle: const Text(
                'Saves battery: GPS stops when the phone has been still for '
                'a while and starts again when the bus moves.',
              ),
              value: _stopDetection,
              onChanged: (v) => setState(() => _stopDetection = v),
            ),
            if (_stopDetection) ...[
              TextFormField(
                controller: _stopTimeout,
                decoration: const InputDecoration(
                  labelText: 'Parked after (seconds)',
                  helperText:
                      'Longer than a stop at a bus stop or traffic light',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                validator: (v) => validateStopTimeout(int.tryParse(v ?? '')),
              ),
              gap,
              TextFormField(
                controller: _heartbeat,
                decoration: const InputDecoration(
                  labelText: 'Position while parked every (seconds)',
                  helperText: '0 = none. Each one switches GPS on briefly.',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                validator: (v) => validateHeartbeat(int.tryParse(v ?? '')),
              ),
            ],
            section('Buspilot engine'),
            TextFormField(
              controller: _engineUrl,
              decoration: const InputDecoration(
                labelText: 'Engine URL',
                hintText: 'https://engine.example.org',
                helperText:
                    'Receives tag and device events. Empty: events are kept '
                    'on the phone and sent once a URL is set.',
                helperMaxLines: 3,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: (v) =>
                  validateEngineUrl(v ?? '', allowHttp: widget.allowHttp),
            ),
            gap,
            TextFormField(
              controller: _token,
              obscureText: !_showToken,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Vehicle token',
                helperText: 'Issued by the operator for this bus',
                suffixIcon: IconButton(
                  tooltip: _showToken ? 'Hide' : 'Show',
                  icon: Icon(
                    _showToken ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _showToken = !_showToken),
                ),
              ),
              validator: (v) => validateVehicleToken((v ?? '').trim()),
            ),
            section('Tags'),
            TextFormField(
              controller: _iBeacon,
              decoration: const InputDecoration(
                labelText: 'iBeacon UUIDs',
                helperText: 'One per line. Only these tags are reported.',
              ),
              autocorrect: false,
              minLines: 1,
              maxLines: 4,
              validator: (v) => validateTagIds(splitIds(v ?? ''), const []),
            ),
            gap,
            TextFormField(
              controller: _eddystone,
              decoration: const InputDecoration(
                labelText: 'Eddystone namespaces',
                helperText:
                    'One per line, 20 hex digits. With no UUIDs and no '
                    'namespaces, the phone does not scan for tags.',
                helperMaxLines: 3,
              ),
              autocorrect: false,
              minLines: 1,
              maxLines: 4,
              validator: (v) => validateTagIds(const [], splitIds(v ?? '')),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
            const SizedBox(height: 16),
            Text(
              'Stored only on this phone. The app sends the bus position, '
              'speed, direction and battery level to Traccar, and tag IDs '
              'and battery state to the Buspilot engine. No names or other '
              'personal data.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
