import 'ac_state.dart';
import 'matter_ids.dart';

/// One attribute value reported by the AC over Matter.
class AttributeReport {
  const AttributeReport({
    required this.endpoint,
    required this.cluster,
    required this.attribute,
    required this.value,
  });

  /// Builds a report from the map sent by the Android Matter bridge.
  factory AttributeReport.fromMap(Map<Object?, Object?> map) {
    return AttributeReport(
      endpoint: (map['endpoint'] as num).toInt(),
      cluster: (map['cluster'] as num).toInt(),
      attribute: (map['attribute'] as num).toInt(),
      value: map['value'],
    );
  }

  final int endpoint;
  final int cluster;
  final int attribute;

  /// Decoded value: int, bool, String, List, or null (Matter null).
  final Object? value;

  @override
  String toString() =>
      'AttributeReport(ep $endpoint, cluster 0x${cluster.toRadixString(16)}, '
      'attr 0x${attribute.toRadixString(16)}, value $value)';
}

int? _asInt(Object? v) => v is num ? v.toInt() : null;

/// Matter temperatures are int16 in 0.01 °C.
double? _asCelsius(Object? v) => v is num ? v.toInt() / 100.0 : null;

/// Applies attribute reports to [AcState] and [AcCapabilities].
///
/// Only reports for the AC endpoint change the state. Reports from other
/// endpoints are used for discovery only.
class AttributeReducer {
  AttributeReducer({this.state = const AcState(), this.capabilities = const AcCapabilities()});

  AcState state;
  AcCapabilities capabilities;

  /// Applies one report. Returns true if the AC state changed.
  bool apply(AttributeReport r) {
    final before = state;
    _applyCapability(r);
    final ep = capabilities.endpoint;
    if (ep != null && r.endpoint != ep && r.cluster != ClusterId.temperatureMeasurement) {
      return false;
    }
    switch (r.cluster) {
      case ClusterId.onOff:
        if (r.attribute == OnOffAttr.onOff && r.value is bool) {
          state = state.copyWith(power: r.value as bool);
        }
      case ClusterId.thermostat:
        switch (r.attribute) {
          case ThermostatAttr.systemMode:
            final mode = AcMode.fromMatter(_asInt(r.value));
            if (mode != null) state = state.copyWith(mode: mode);
          case ThermostatAttr.occupiedCoolingSetpoint:
            final c = _asCelsius(r.value);
            if (c != null) state = state.copyWith(coolingSetpointC: c);
          case ThermostatAttr.localTemperature:
            // Nullable in Matter: null means the AC does not know the value.
            final c = _asCelsius(r.value);
            state = c == null
                ? state.copyWith(clearRoomTemperature: true)
                : state.copyWith(roomTemperatureC: c);
        }
      case ClusterId.temperatureMeasurement:
        // Used only when the Thermostat has not reported LocalTemperature.
        if (r.attribute == MeasurementAttr.measuredValue && state.roomTemperatureC == null) {
          final c = _asCelsius(r.value);
          if (c != null) state = state.copyWith(roomTemperatureC: c);
        }
      case ClusterId.fanControl:
        switch (r.attribute) {
          case FanControlAttr.fanMode:
            final f = FanSpeed.fromMatter(_asInt(r.value));
            if (f != null) state = state.copyWith(fanSpeed: f);
          case FanControlAttr.rockSetting:
            final v = _asInt(r.value);
            if (v != null) state = state.copyWith(rockSetting: v);
        }
    }
    return state != before;
  }

  void _applyCapability(AttributeReport r) {
    final c = capabilities;
    switch ((r.cluster, r.attribute)) {
      case (ClusterId.descriptor, DescriptorAttr.serverList):
        final list = r.value is List ? (r.value as List).whereType<num>().map((e) => e.toInt()).toSet() : <int>{};
        // The AC endpoint is the one that hosts a Thermostat server.
        if (list.contains(ClusterId.thermostat) &&
            (c.endpoint == null || c.endpoint == r.endpoint)) {
          capabilities = c.copyWith(endpoint: r.endpoint, serverClusters: list);
        }
      case (ClusterId.thermostat, ThermostatAttr.featureMap):
        capabilities = c.copyWith(thermostatFeatures: _asInt(r.value));
      case (ClusterId.thermostat, ThermostatAttr.controlSequenceOfOperation):
        capabilities = c.copyWith(controlSequence: _asInt(r.value));
      case (ClusterId.thermostat, ThermostatAttr.minCoolSetpointLimit):
        capabilities = c.copyWith(minCoolSetpointC: _asCelsius(r.value));
      case (ClusterId.thermostat, ThermostatAttr.maxCoolSetpointLimit):
        capabilities = c.copyWith(maxCoolSetpointC: _asCelsius(r.value));
      case (ClusterId.thermostat, ThermostatAttr.absMinCoolSetpointLimit):
        if (c.minCoolSetpointC == null) {
          capabilities = c.copyWith(minCoolSetpointC: _asCelsius(r.value));
        }
      case (ClusterId.thermostat, ThermostatAttr.absMaxCoolSetpointLimit):
        if (c.maxCoolSetpointC == null) {
          capabilities = c.copyWith(maxCoolSetpointC: _asCelsius(r.value));
        }
      case (ClusterId.fanControl, FanControlAttr.featureMap):
        capabilities = c.copyWith(fanFeatures: _asInt(r.value));
      case (ClusterId.fanControl, FanControlAttr.fanModeSequence):
        capabilities = c.copyWith(fanModeSequence: _asInt(r.value));
      case (ClusterId.fanControl, FanControlAttr.rockSupport):
        capabilities = c.copyWith(rockSupport: _asInt(r.value));
      case (ClusterId.basicInformation, BasicInfoAttr.vendorName):
        capabilities = c.copyWith(vendorName: r.value as String?);
      case (ClusterId.basicInformation, BasicInfoAttr.productName):
        capabilities = c.copyWith(productName: r.value as String?);
      case (ClusterId.basicInformation, BasicInfoAttr.vendorId):
        capabilities = c.copyWith(vendorId: _asInt(r.value));
      case (ClusterId.basicInformation, BasicInfoAttr.productId):
        capabilities = c.copyWith(productId: _asInt(r.value));
      case (ClusterId.basicInformation, BasicInfoAttr.softwareVersionString):
        capabilities = c.copyWith(softwareVersion: r.value as String?);
    }
  }
}
