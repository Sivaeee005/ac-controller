import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/ac_state.dart';
import '../services/ac_controller.dart';
import 'formatting.dart';

/// Stage 1 screen: power control with confirmation, reported state, and a
/// report of what the AC exposes over Matter.
class DevicePage extends StatelessWidget {
  const DevicePage({super.key, required this.controller});

  final AcController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return RefreshIndicator(
      onRefresh: c.reconnectNow,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConnectionCard(controller: c),
          const SizedBox(height: 16),
          Center(child: PowerButton(controller: c)),
          const SizedBox(height: 12),
          OutcomeBanner(controller: c),
          const SizedBox(height: 16),
          _ReportedStateCard(state: c.state),
          const SizedBox(height: 16),
          _CapabilityCard(controller: c),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _confirmForget(context),
            icon: const Icon(Icons.link_off),
            label: const Text('Remove AC from this app'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmForget(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove AC?'),
        content: const Text(
            'This app will stop controlling the AC. You will need the Matter setup code to pair again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await controller.forget();
  }
}

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({super.key, required this.controller});

  final AcController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final (icon, color, label) = switch (c.link) {
      LinkStatus.connected => (Icons.wifi, Colors.green, 'Connected'),
      LinkStatus.connecting => (Icons.sync, Colors.blue, 'Connecting…'),
      LinkStatus.disconnected => (Icons.wifi_off, Colors.red, 'Not connected'),
      LinkStatus.notPaired => (Icons.link_off, Colors.grey, 'Not paired'),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        subtitle: Text([
          'Last update from AC: ${formatSync(c.lastSync)}',
          if (c.linkMessage != null) c.linkMessage!,
        ].join('\n')),
        isThreeLine: c.linkMessage != null,
        trailing: c.link == LinkStatus.disconnected
            ? TextButton(onPressed: c.reconnectNow, child: const Text('Retry'))
            : null,
      ),
    );
  }
}

class PowerButton extends StatelessWidget {
  const PowerButton({super.key, required this.controller});

  final AcController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final power = c.state.power;
    final busy = c.pendingCommand != null;
    final enabled = c.link == LinkStatus.connected && power != null && !busy;
    final scheme = Theme.of(context).colorScheme;
    final on = power == true;
    return Column(
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: FilledButton(
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: on ? scheme.primary : scheme.surfaceContainerHighest,
              foregroundColor: on ? scheme.onPrimary : scheme.onSurface,
            ),
            onPressed: enabled ? () => c.setPower(!on) : null,
            child: busy
                ? const CircularProgressIndicator()
                : const Icon(Icons.power_settings_new, size: 72),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          busy ? '${c.pendingCommand}…' : 'AC reports: ${formatPower(power)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

/// Shows the result of the last command. Success is shown only when the
/// AC's own report confirmed the change.
class OutcomeBanner extends StatelessWidget {
  const OutcomeBanner({super.key, required this.controller});

  final AcController controller;

  @override
  Widget build(BuildContext context) {
    final o = controller.lastOutcome;
    if (o == null) return const SizedBox.shrink();
    final (icon, color, text) = switch (o.status) {
      CommandStatus.confirmed => (Icons.check_circle, Colors.green, '${o.description}: confirmed by the AC'),
      CommandStatus.notConfirmed => (Icons.help, Colors.orange, '${o.description}: not confirmed'),
      CommandStatus.failed => (Icons.error, Colors.red, '${o.description}: failed'),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text),
        subtitle: o.message == null ? null : Text(o.message!),
        trailing: controller.canRetry
            ? TextButton(onPressed: controller.retryLast, child: const Text('Retry'))
            : null,
      ),
    );
  }
}

class _ReportedStateCard extends StatelessWidget {
  const _ReportedStateCard({required this.state});

  final AcState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reported by the AC', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _row('Mode', formatMode(state.mode)),
            _row('Target temperature', formatTemp(state.coolingSetpointC)),
            _row('Room temperature', formatTemp(state.roomTemperatureC)),
            _row('Fan', formatFan(state.fanSpeed)),
            _row('Swing', formatSwing(state.rockSetting)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(label)), Text(value)]),
      );
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.controller});

  final AcController controller;

  @override
  Widget build(BuildContext context) {
    final report = capabilityReport(controller.capabilities, controller.state);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What your AC exposes over Matter', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(report, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Report copied')));
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy report'),
            ),
          ],
        ),
      ),
    );
  }
}
