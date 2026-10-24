import 'package:flutter/material.dart';

import '../data/ac_backend.dart';
import '../services/ac_controller.dart';

class PairingPage extends StatefulWidget {
  const PairingPage({super.key, required this.controller});

  final AcController controller;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  final _code = TextEditingController();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;

  /// The AC is already on Wi-Fi and the code comes from MirAIe "Share Device".
  bool _shared = true;
  String? _error;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_maybeAskAttestation);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_maybeAskAttestation);
    _code.dispose();
    _ssid.dispose();
    // The password is only kept in this field while the page is open.
    _password.dispose();
    super.dispose();
  }

  Future<void> _maybeAskAttestation() async {
    final code = widget.controller.attestationError;
    if (code == null || _dialogOpen || !mounted) return;
    _dialogOpen = true;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Certificate check failed'),
        content: Text(
          'The AC\'s Matter certificate could not be verified (code $code).\n\n'
          'Continue only if this is your own Panasonic AC, the one with the sticker you scanned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    await widget.controller.answerAttestation(proceed: proceed ?? false);
  }

  Future<void> _pair() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.pair(
        setupCode: _code.text,
        wifiSsid: _ssid.text.trim(),
        wifiPassword: _password.text,
        onNetworkOnly: _shared,
      );
    } on BackendException catch (e) {
      setState(() => _error = e.message);
    } finally {
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.controller.commissioningStage;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Pair your AC', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _shared,
          onChanged: _busy ? null : (v) => setState(() => _shared = v),
          title: const Text('AC is already set up in MirAIe'),
          subtitle: const Text('Use the code from MirAIe "Share Device"'),
        ),
        Text(
          _shared
              ? '1. In MirAIe, open the AC settings and tap "Share Device".\n'
                    '2. Enter the 11-digit code it shows, then tap Pair AC within 3 minutes.\n'
                    '3. Keep this phone on the same Wi-Fi as the AC.'
              : '1. Put the AC in setup mode: press and hold the SMART button on the AC remote '
                    'for 5 seconds. The AC display shows a blinking Wi-Fi icon and "SE".\n'
                    '2. Stand near the AC with Bluetooth on, and keep this phone on the same Wi-Fi.\n'
                    '3. Enter the 11-digit number printed under the Matter QR code on the indoor unit.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _code,
          enabled: !_busy,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            labelText: 'Matter setup code',
            hintText: '1234-567-8901 or MT:...',
            border: OutlineInputBorder(),
          ),
        ),
        if (!_shared) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _ssid,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Wi-Fi name (2.4 GHz)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'Wi-Fi password',
              helperText: 'Sent only to the AC. Not saved by this app.',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _pair,
          icon: const Icon(Icons.link),
          label: const Text('Pair AC'),
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(stage ?? 'Working…'),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
