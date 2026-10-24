/// Matter cluster and attribute IDs used by this app.
///
/// Values are taken from the Matter data model (connectedhomeip v1.4.2.0,
/// `src/app/zap-templates/zcl/data-model/chip`).
library;

abstract final class ClusterId {
  static const onOff = 0x0006;
  static const descriptor = 0x001D;
  static const basicInformation = 0x0028;
  static const thermostat = 0x0201;
  static const fanControl = 0x0202;
  static const temperatureMeasurement = 0x0402;
  static const relativeHumidityMeasurement = 0x0405;
}

abstract final class OnOffAttr {
  static const onOff = 0x0000;
}

abstract final class DescriptorAttr {
  static const serverList = 0x0001;
  static const partsList = 0x0003;
}

abstract final class BasicInfoAttr {
  static const vendorName = 0x0001;
  static const vendorId = 0x0002;
  static const productName = 0x0003;
  static const productId = 0x0004;
  static const softwareVersionString = 0x000A;
}

abstract final class ThermostatAttr {
  static const localTemperature = 0x0000;
  static const absMinCoolSetpointLimit = 0x0005;
  static const absMaxCoolSetpointLimit = 0x0006;
  static const occupiedCoolingSetpoint = 0x0011;
  static const minCoolSetpointLimit = 0x0017;
  static const maxCoolSetpointLimit = 0x0018;
  static const controlSequenceOfOperation = 0x001B;
  static const systemMode = 0x001C;
  static const featureMap = 0xFFFC;
}

abstract final class FanControlAttr {
  static const fanMode = 0x0000;
  static const fanModeSequence = 0x0001;
  static const percentSetting = 0x0002;
  static const rockSupport = 0x0007;
  static const rockSetting = 0x0008;
  static const featureMap = 0xFFFC;
}

abstract final class MeasurementAttr {
  static const measuredValue = 0x0000;
}

/// Thermostat feature map bits.
abstract final class ThermostatFeature {
  static const heating = 0x01;
  static const cooling = 0x02;
  static const autoMode = 0x20;
}

/// Fan Control feature map bits.
abstract final class FanFeature {
  static const multiSpeed = 0x01;
  static const auto = 0x02;
  static const rocking = 0x04;
}

/// Fan Control RockBitmap bits.
abstract final class RockBits {
  static const leftRight = 0x01;
  static const upDown = 0x02;
  static const round = 0x04;
}
