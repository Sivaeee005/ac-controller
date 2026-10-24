import 'dart:async';

import '../domain/attribute_reducer.dart';
import '../domain/matter_ids.dart';
import 'ac_backend.dart';

/// A simulated Matter room AC for tests and demo mode.
///
/// It is NOT the real AC. Results obtained with it are simulated results.
/// The capabilities below are an assumption (cooling-only AC with fan and
/// vertical swing) and must be replaced by what the real AC reports.
class SimulatedBackend implements AcBackend {
  SimulatedBackend({
    this.latency = const Duration(milliseconds: 150),
    this.startPaired = false,
    this.rejectedModes = const {},
  });

  final Duration latency;
  final bool startPaired;

  /// SystemMode values the simulated AC rejects (CONSTRAINT_ERROR).
  final Set<int> rejectedModes;

  /// Failure injection for tests.
  bool failNextCommand = false;
  bool dropNextReport = false;
  bool unreachable = false;

  static const endpoint = 1;
  final _events = StreamController<BackendEvent>.broadcast();
  PairedAc? _paired;
  bool _connected = false;

  // Simulated device attributes.
  bool _power = false;
  int _mode = 3; // Cool
  int _setpoint = 2400;
  int? _localTemp; // null: not reported, like an AC without a room sensor
  int _fanMode = 5; // Auto
  int _rock = 0;

  @override
  bool get isSimulated => true;

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  Future<PairedAc?> loadPairedDevice() async {
    if (startPaired) _paired ??= const PairedAc(nodeId: 1, label: 'Simulated AC');
    return _paired;
  }

  @override
  Future<PairedAc> commission({
    required String setupCode,
    required String wifiSsid,
    required String wifiPassword,
  }) async {
    for (final stage in ['Scanning Bluetooth', 'Connecting', 'Sending Wi-Fi', 'Finishing']) {
      _events.add(CommissioningStageEvent(stage));
      await Future<void>.delayed(latency);
    }
    if (setupCode.trim().isEmpty) {
      throw const BackendException('invalid_code', 'The setup code is not valid.');
    }
    return _paired = const PairedAc(nodeId: 1, label: 'Simulated AC');
  }

  @override
  Future<void> continueCommissioning({required bool ignoreAttestationFailure}) async {}

  @override
  Future<void> connect(PairedAc ac) async {
    await Future<void>.delayed(latency);
    if (unreachable) {
      throw const BackendException('unreachable', 'The AC could not be reached on the network.');
    }
    _connected = true;
    _events.add(ReportsEvent(_fullReport()));
    _events.add(const LinkUpEvent());
  }

  @override
  Future<void> disconnect() async => _connected = false;

  /// Simulates a lost connection (for example, Wi-Fi dropped).
  void simulateLinkLoss() {
    _connected = false;
    _events.add(const LinkDownEvent('Connection to the AC was lost.'));
  }

  /// Simulates a change made with the IR remote control.
  void simulateRemoteChange({bool? power, int? setpoint}) {
    if (power != null) _power = power;
    if (setpoint != null) _setpoint = setpoint;
    _events.add(ReportsEvent([
      _r(ClusterId.onOff, OnOffAttr.onOff, _power),
      _r(ClusterId.thermostat, ThermostatAttr.occupiedCoolingSetpoint, _setpoint),
    ]));
  }

  @override
  Future<void> setPower(int endpoint, bool on) =>
      _command(() => _power = on, [() => _r(ClusterId.onOff, OnOffAttr.onOff, _power)]);

  @override
  Future<void> writeSystemMode(int endpoint, int mode) {
    if (rejectedModes.contains(mode)) {
      return Future<void>.delayed(latency, () {
        throw const BackendException('constraint_error', 'The AC does not support this mode.');
      });
    }
    return _command(() => _mode = mode,
        [() => _r(ClusterId.thermostat, ThermostatAttr.systemMode, _mode)]);
  }

  @override
  Future<void> writeCoolingSetpoint(int endpoint, int centiCelsius) {
    if (centiCelsius < 1600 || centiCelsius > 3000) {
      return Future<void>.delayed(latency, () {
        throw const BackendException('constraint_error', 'Temperature outside the AC range.');
      });
    }
    return _command(() => _setpoint = centiCelsius,
        [() => _r(ClusterId.thermostat, ThermostatAttr.occupiedCoolingSetpoint, _setpoint)]);
  }

  @override
  Future<void> writeFanMode(int endpoint, int mode) => _command(
      () => _fanMode = mode, [() => _r(ClusterId.fanControl, FanControlAttr.fanMode, _fanMode)]);

  @override
  Future<void> writeRockSetting(int endpoint, int rockBits) => _command(
      () => _rock = rockBits, [() => _r(ClusterId.fanControl, FanControlAttr.rockSetting, _rock)]);

  @override
  Future<void> forget(PairedAc ac) async {
    _paired = null;
    _connected = false;
  }

  Future<void> _command(void Function() apply, List<AttributeReport Function()> report) async {
    await Future<void>.delayed(latency);
    if (!_connected) {
      throw const BackendException('not_connected', 'The AC is not connected.');
    }
    if (failNextCommand) {
      failNextCommand = false;
      throw const BackendException('failure', 'The AC rejected the command.');
    }
    apply();
    if (dropNextReport) {
      dropNextReport = false;
      return;
    }
    // Reports arrive shortly after the command response, as with Matter.
    unawaited(Future<void>.delayed(latency, () {
      if (_connected) _events.add(ReportsEvent([for (final r in report) r()]));
    }));
  }

  AttributeReport _r(int cluster, int attribute, Object? value) =>
      AttributeReport(endpoint: endpoint, cluster: cluster, attribute: attribute, value: value);

  List<AttributeReport> _fullReport() => [
        const AttributeReport(
            endpoint: 0,
            cluster: ClusterId.descriptor,
            attribute: DescriptorAttr.serverList,
            value: [ClusterId.descriptor, ClusterId.basicInformation]),
        AttributeReport(
            endpoint: 0, cluster: ClusterId.basicInformation, attribute: BasicInfoAttr.vendorName, value: 'Simulated'),
        AttributeReport(
            endpoint: 0, cluster: ClusterId.basicInformation, attribute: BasicInfoAttr.productName, value: 'Simulated Room AC'),
        _r(ClusterId.descriptor, DescriptorAttr.serverList,
            [ClusterId.onOff, ClusterId.descriptor, ClusterId.thermostat, ClusterId.fanControl]),
        _r(ClusterId.onOff, OnOffAttr.onOff, _power),
        _r(ClusterId.thermostat, ThermostatAttr.featureMap, ThermostatFeature.cooling),
        _r(ClusterId.thermostat, ThermostatAttr.controlSequenceOfOperation, 0),
        _r(ClusterId.thermostat, ThermostatAttr.minCoolSetpointLimit, 1600),
        _r(ClusterId.thermostat, ThermostatAttr.maxCoolSetpointLimit, 3000),
        _r(ClusterId.thermostat, ThermostatAttr.systemMode, _mode),
        _r(ClusterId.thermostat, ThermostatAttr.occupiedCoolingSetpoint, _setpoint),
        _r(ClusterId.thermostat, ThermostatAttr.localTemperature, _localTemp),
        _r(ClusterId.fanControl, FanControlAttr.featureMap, FanFeature.multiSpeed | FanFeature.auto | FanFeature.rocking),
        _r(ClusterId.fanControl, FanControlAttr.fanModeSequence, 2),
        _r(ClusterId.fanControl, FanControlAttr.rockSupport, RockBits.upDown),
        _r(ClusterId.fanControl, FanControlAttr.fanMode, _fanMode),
        _r(ClusterId.fanControl, FanControlAttr.rockSetting, _rock),
      ];
}
