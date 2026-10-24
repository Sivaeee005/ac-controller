import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the Android debug report (crashes, app log, system log) and lets
/// the user copy or share it.
class DebugReportPage extends StatefulWidget {
  const DebugReportPage({super.key, this.simulated = false});

  final bool simulated;

  @override
  State<DebugReportPage> createState() => _DebugReportPageState();
}

class _DebugReportPageState extends State<DebugReportPage> {
  static const _channel = MethodChannel('ac_controller/debug');
  String? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _report = null;
      _error = null;
    });
    if (widget.simulated) {
      setState(() => _report = 'Simulated build: no Android debug data.');
      return;
    }
    try {
      final r = await _channel.invokeMethod<String>('build');
      setState(() => _report = r ?? '');
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } on MissingPluginException {
      setState(() => _error = 'Debug report is not available on this platform.');
    }
  }

  Future<void> _share() async {
    final r = _report;
    if (r == null) return;
    try {
      await _channel.invokeMethod<void>('share', {'report': r});
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Share failed: ${e.message}')));
      }
    }
  }

  Future<void> _copy() async {
    final r = _report;
    if (r == null) return;
    await Clipboard.setData(ClipboardData(text: r));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report copied')));
    }
  }

  Future<void> _clear() async {
    await _channel.invokeMethod<void>('clear');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug report'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(tooltip: 'Clear logs', onPressed: _clear, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Contains: app version, phone model, recent crashes and app logs. '
              'Setup codes are masked; Wi-Fi passwords are never logged. '
              'Please check it before sharing.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: report == null ? null : _share,
                    icon: const Icon(Icons.share),
                    label: const Text('Share file'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: report == null ? null : _copy,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : report == null
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(report,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ),
          ),
        ],
      ),
    );
  }
}
