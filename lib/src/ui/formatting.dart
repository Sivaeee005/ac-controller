import '../domain/ac_state.dart';
import '../domain/matter_ids.dart';

const notReported = 'Not reported';

String formatPower(bool? power) => switch (power) {
      true => 'ON',
      false => 'OFF',
      null => notReported,
    };

String formatTemp(double? c) => c == null ? notReported : '${c.toStringAsFixed(1)} °C';

String formatMode(AcMode? m) => switch (m) {
      null => notReported,
      AcMode.off => 'Off',
      AcMode.auto => 'Auto',
      AcMode.cool => 'Cool',
      AcMode.heat => 'Heat',
      AcMode.fanOnly => 'Fan only',
      AcMode.dry => 'Dry',
    };

String formatFan(FanSpeed? f) => switch (f) {
      null => notReported,
      FanSpeed.off => 'Off',
      FanSpeed.low => 'Low',
      FanSpeed.medium => 'Medium',
      FanSpeed.high => 'High',
      FanSpeed.on => 'On',
      FanSpeed.auto => 'Auto',
      FanSpeed.smart => 'Smart',
    };

String formatSwing(int? rock) {
  if (rock == null) return notReported;
  if (rock == 0) return 'Off';
  return [
    if (rock & RockBits.upDown != 0) 'Up-down',
    if (rock & RockBits.leftRight != 0) 'Left-right',
    if (rock & RockBits.round != 0) 'Round',
  ].join(' + ');
}

String formatSync(DateTime? t, {DateTime? now}) {
  if (t == null) return 'never';
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 5) return 'just now';
  if (d.inMinutes < 1) return '${d.inSeconds} s ago';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return 'at $hh:$mm';
}

String _hex(int v) => '0x${v.toRadixString(16).toUpperCase().padLeft(4, '0')}';

/// Plain-text report of the AC's Matter capabilities. It contains no
/// secrets (no setup code, no Wi-Fi details) and is safe to share.
String capabilityReport(AcCapabilities c, AcState s) {
  final clusters = (c.serverClusters.toList()..sort()).map(_hex).join(', ');
  return [
    'Vendor: ${c.vendorName ?? '?'} (${c.vendorId == null ? '?' : _hex(c.vendorId!)})',
    'Product: ${c.productName ?? '?'} (${c.productId == null ? '?' : _hex(c.productId!)})',
    'Firmware: ${c.softwareVersion ?? '?'}',
    'AC endpoint: ${c.endpoint ?? '?'}',
    'Server clusters: ${clusters.isEmpty ? '?' : clusters}',
    'Power (OnOff): ${c.hasPower ? 'yes' : 'no'}',
    'Thermostat features: ${c.thermostatFeatures == null ? '?' : _hex(c.thermostatFeatures!)}'
        ' (cool ${c.canCool}, heat ${c.canHeat}, auto ${c.hasAutoMode})',
    'Control sequence: ${c.controlSequence ?? '?'}',
    'Cooling range: ${formatTemp(c.minCoolSetpointC)} - ${formatTemp(c.maxCoolSetpointC)}',
    'Fan control: ${c.hasFanControl ? 'yes' : 'no'}'
        ', features ${c.fanFeatures == null ? '?' : _hex(c.fanFeatures!)}'
        ', sequence ${c.fanModeSequence ?? '?'}',
    'Fan speeds: ${c.fanSpeeds.isEmpty ? 'none reported' : c.fanSpeeds.map(formatFan).join(', ')}',
    'Swing: ${c.hasSwing ? formatSwing(c.rockSupport) : 'not supported'}',
    'Room temperature: ${s.roomTemperatureC == null ? 'not reported' : 'reported'}',
  ].join('\n');
}
