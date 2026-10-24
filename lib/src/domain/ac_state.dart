import 'package:flutter/foundation.dart';

import 'matter_ids.dart';

/// Thermostat SystemModeEnum.
enum AcMode {
  off(0),
  auto(1),
  cool(3),
  heat(4),
  fanOnly(7),
  dry(8);

  const AcMode(this.matterValue);
  final int matterValue;

  static AcMode? fromMatter(int? value) {
    for (final m in values) {
      if (m.matterValue == value) return m;
    }
    return null;
  }
}

/// Fan Control FanModeEnum.
enum FanSpeed {
  off(0),
  low(1),
  medium(2),
  high(3),
  on(4),
  auto(5),
  smart(6);

  const FanSpeed(this.matterValue);
  final int matterValue;

  static FanSpeed? fromMatter(int? value) {
    for (final f in values) {
      if (f.matterValue == value) return f;
    }
    return null;
  }
}

/// Connection state of the link between this app and the AC.
enum LinkStatus { notPaired, connecting, connected, disconnected }

/// The AC state exactly as reported by the device.
///
/// Every field is nullable: `null` means "the AC has not reported this value"
/// and the UI must show it as unknown rather than guessing.
@immutable
class AcState {
  const AcState({
    this.power,
    this.mode,
    this.coolingSetpointC,
    this.roomTemperatureC,
    this.fanSpeed,
    this.rockSetting,
  });

  final bool? power;
  final AcMode? mode;
  final double? coolingSetpointC;

  /// Room temperature reported by the AC. `null` when not reported.
  final double? roomTemperatureC;
  final FanSpeed? fanSpeed;

  /// Fan Control RockSetting bitmap (swing). `null` when not reported.
  final int? rockSetting;

  AcState copyWith({
    bool? power,
    AcMode? mode,
    double? coolingSetpointC,
    double? roomTemperatureC,
    bool clearRoomTemperature = false,
    FanSpeed? fanSpeed,
    int? rockSetting,
  }) {
    return AcState(
      power: power ?? this.power,
      mode: mode ?? this.mode,
      coolingSetpointC: coolingSetpointC ?? this.coolingSetpointC,
      roomTemperatureC: clearRoomTemperature
          ? null
          : (roomTemperatureC ?? this.roomTemperatureC),
      fanSpeed: fanSpeed ?? this.fanSpeed,
      rockSetting: rockSetting ?? this.rockSetting,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AcState &&
      other.power == power &&
      other.mode == mode &&
      other.coolingSetpointC == coolingSetpointC &&
      other.roomTemperatureC == roomTemperatureC &&
      other.fanSpeed == fanSpeed &&
      other.rockSetting == rockSetting;

  @override
  int get hashCode => Object.hash(
      power, mode, coolingSetpointC, roomTemperatureC, fanSpeed, rockSetting);

  @override
  String toString() =>
      'AcState(power: $power, mode: $mode, setpoint: $coolingSetpointC, '
      'room: $roomTemperatureC, fan: $fanSpeed, rock: $rockSetting)';
}

/// What the paired AC exposes over Matter, discovered from its attributes.
@immutable
class AcCapabilities {
  const AcCapabilities({
    this.endpoint,
    this.serverClusters = const {},
    this.thermostatFeatures,
    this.controlSequence,
    this.minCoolSetpointC,
    this.maxCoolSetpointC,
    this.fanFeatures,
    this.fanModeSequence,
    this.rockSupport,
    this.vendorName,
    this.productName,
    this.vendorId,
    this.productId,
    this.softwareVersion,
  });

  /// Endpoint that hosts the AC clusters (usually 1).
  final int? endpoint;
  final Set<int> serverClusters;
  final int? thermostatFeatures;
  final int? controlSequence;
  final double? minCoolSetpointC;
  final double? maxCoolSetpointC;
  final int? fanFeatures;
  final int? fanModeSequence;
  final int? rockSupport;
  final String? vendorName;
  final String? productName;
  final int? vendorId;
  final int? productId;
  final String? softwareVersion;

  bool get hasPower => serverClusters.contains(ClusterId.onOff);
  bool get hasThermostat => serverClusters.contains(ClusterId.thermostat);
  bool get hasFanControl => serverClusters.contains(ClusterId.fanControl);
  bool get canCool =>
      hasThermostat && ((thermostatFeatures ?? 0) & ThermostatFeature.cooling) != 0;
  bool get canHeat =>
      hasThermostat && ((thermostatFeatures ?? 0) & ThermostatFeature.heating) != 0;
  bool get hasAutoMode =>
      hasThermostat && ((thermostatFeatures ?? 0) & ThermostatFeature.autoMode) != 0;
  bool get hasSwing =>
      hasFanControl &&
      ((fanFeatures ?? 0) & FanFeature.rocking) != 0 &&
      (rockSupport ?? 0) != 0;

  /// Modes the Matter data model says are possible for this AC.
  ///
  /// Dry and Fan-only are "candidates": Matter 1.2 has no attribute listing
  /// them, so the app only offers them after the AC has accepted them once.
  List<AcMode> get standardModes => [
        if (canCool) AcMode.cool,
        if (canHeat) AcMode.heat,
        if (hasAutoMode) AcMode.auto,
      ];

  /// Fan speeds allowed by FanModeSequenceEnum (Off is handled by power).
  List<FanSpeed> get fanSpeeds {
    switch (fanModeSequence) {
      case 0:
        return const [FanSpeed.low, FanSpeed.medium, FanSpeed.high];
      case 1:
        return const [FanSpeed.low, FanSpeed.high];
      case 2:
        return const [FanSpeed.low, FanSpeed.medium, FanSpeed.high, FanSpeed.auto];
      case 3:
        return const [FanSpeed.low, FanSpeed.high, FanSpeed.auto];
      case 4:
        return const [FanSpeed.high, FanSpeed.auto];
      case 5:
        return const [FanSpeed.high];
      default:
        return const [];
    }
  }

  AcCapabilities copyWith({
    int? endpoint,
    Set<int>? serverClusters,
    int? thermostatFeatures,
    int? controlSequence,
    double? minCoolSetpointC,
    double? maxCoolSetpointC,
    int? fanFeatures,
    int? fanModeSequence,
    int? rockSupport,
    String? vendorName,
    String? productName,
    int? vendorId,
    int? productId,
    String? softwareVersion,
  }) {
    return AcCapabilities(
      endpoint: endpoint ?? this.endpoint,
      serverClusters: serverClusters ?? this.serverClusters,
      thermostatFeatures: thermostatFeatures ?? this.thermostatFeatures,
      controlSequence: controlSequence ?? this.controlSequence,
      minCoolSetpointC: minCoolSetpointC ?? this.minCoolSetpointC,
      maxCoolSetpointC: maxCoolSetpointC ?? this.maxCoolSetpointC,
      fanFeatures: fanFeatures ?? this.fanFeatures,
      fanModeSequence: fanModeSequence ?? this.fanModeSequence,
      rockSupport: rockSupport ?? this.rockSupport,
      vendorName: vendorName ?? this.vendorName,
      productName: productName ?? this.productName,
      vendorId: vendorId ?? this.vendorId,
      productId: productId ?? this.productId,
      softwareVersion: softwareVersion ?? this.softwareVersion,
    );
  }
}
