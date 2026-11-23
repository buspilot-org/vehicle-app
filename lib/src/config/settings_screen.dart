import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'tracking_config.dart';

/// Edits [TrackingConfig]. [onSave] stores the settings (and restarts
/// tracking if it is running).
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
  late final _serverUrl = TextEditingController(text: widget.initial.serverUrl);
  late final _deviceId = TextEditingController(text: widget.initial.deviceId);
  late final _interval = TextEditingController(
    text: '${widget.initial.intervalSeconds}',
  );
  late final _distance = TextEditingController(
    text: '${widget.initial.distanceFilterMeters}',
  );
  bool _saving = false;

  @override
  void dispose() {
    _serverUrl.dispose();
    _deviceId.dispose();
    _interval.dispose();
    _distance.dispose();
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
    );
    try {
      await widget.onSave(config);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _interval,
              decoration: const InputDecoration(
                labelText: 'Interval (seconds)',
                helperText: 'How often to take a position',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              validator: (v) => validateInterval(int.tryParse(v ?? '')),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _distance,
              decoration: const InputDecoration(
                labelText: 'Distance filter (metres)',
                helperText:
                    '0 = send every position. Otherwise send after moving '
                    'this far (and every 5 minutes when parked).',
                helperMaxLines: 3,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              validator: (v) => validateDistanceFilter(int.tryParse(v ?? '')),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
            const SizedBox(height: 16),
            Text(
              'Stored only on this phone. The app sends the bus position, '
              'speed, direction and battery level, and no personal data.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
