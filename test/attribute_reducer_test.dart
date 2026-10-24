import 'package:ac_controller/src/domain/ac_state.dart';
import 'package:ac_controller/src/domain/attribute_reducer.dart';
import 'package:ac_controller/src/domain/matter_ids.dart';
import 'package:flutter_test/flutter_test.dart';

AttributeReport r(int ep, int cluster, int attr, Object? value) =>
    AttributeReport(endpoint: ep, cluster: cluster, attribute: attr, value: value);

void main() {
  test('temperatures are converted from 0.01 °C', () {
    final red = AttributeReducer()
      ..apply(r(1, ClusterId.thermostat, ThermostatAttr.occupiedCoolingSetpoint, 2550))
      ..apply(r(1, ClusterId.thermostat, ThermostatAttr.localTemperature, 2812));
    expect(red.state.coolingSetpointC, 25.5);
    expect(red.state.roomTemperatureC, 28.12);
  });

  test('null LocalTemperature clears a previous value', () {
    final red = AttributeReducer()
      ..apply(r(1, ClusterId.thermostat, ThermostatAttr.localTemperature, 2600))
      ..apply(r(1, ClusterId.thermostat, ThermostatAttr.localTemperature, null));
    expect(red.state.roomTemperatureC, isNull);
  });

  test('AC endpoint is the one hosting the Thermostat server', () {
    final red = AttributeReducer()
      ..apply(r(0, ClusterId.descriptor, DescriptorAttr.serverList, [0x1D, 0x28]))
      ..apply(r(1, ClusterId.descriptor, DescriptorAttr.serverList, [0x06, 0x1D, 0x201]));
    expect(red.capabilities.endpoint, 1);
    expect(red.capabilities.hasPower, isTrue);
    expect(red.capabilities.hasFanControl, isFalse);
  });

  test('reports from other endpoints do not change the state', () {
    final red = AttributeReducer()
      ..apply(r(1, ClusterId.descriptor, DescriptorAttr.serverList, [0x06, 0x201]))
      ..apply(r(1, ClusterId.onOff, OnOffAttr.onOff, true))
      ..apply(r(2, ClusterId.onOff, OnOffAttr.onOff, false));
    expect(red.state.power, isTrue);
  });

  test('unknown enum values are ignored, not guessed', () {
    final red = AttributeReducer()
      ..apply(r(1, ClusterId.thermostat, ThermostatAttr.systemMode, 3))
      ..apply(r(1, ClusterId.thermostat, ThermostatAttr.systemMode, 99));
    expect(red.state.mode, AcMode.cool);
  });

  test('fan speeds follow FanModeSequence', () {
    const caps = AcCapabilities(fanModeSequence: 1);
    expect(caps.fanSpeeds, [FanSpeed.low, FanSpeed.high]);
    expect(const AcCapabilities().fanSpeeds, isEmpty);
  });

  test('swing needs both the Rocking feature and RockSupport', () {
    const noFeature = AcCapabilities(serverClusters: {0x202}, fanFeatures: 0x01, rockSupport: 2);
    const ok = AcCapabilities(serverClusters: {0x202}, fanFeatures: 0x04, rockSupport: 2);
    expect(noFeature.hasSwing, isFalse);
    expect(ok.hasSwing, isTrue);
  });
}
