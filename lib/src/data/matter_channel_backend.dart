import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/attribute_reducer.dart';
import '../domain/matter_ids.dart';
import 'ac_backend.dart';

/// Talks to the Android Matter bridge (`MatterBridge.kt`).
class MatterChannelBackend implements AcBackend {
  static const _method = MethodChannel('ac_controller/matter');
  static const _eventChannel = EventChannel('ac_controller/matter/events');
  Stream<BackendEvent>? _events;

  @override
  bool get isSimulated => false;

  @override
  Stream<BackendEvent> get events =>
      _events ??= _eventChannel.receiveBroadcastStream().map(_decodeEvent).where((e) => e != null).cast<BackendEvent>();

  static BackendEvent? _decodeEvent(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['type']) {
      case 'reports':
        final list = (raw['reports'] as List).cast<Map<Object?, Object?>>();
        return ReportsEvent([for (final m in list) AttributeReport.fromMap(m)]);
      case 'linkUp':
        return const LinkUpEvent();
      case 'linkDown':
        return LinkDownEvent(raw['reason'] as String? ?? 'Connection lost',
            retryInMs: (raw['retryInMs'] as num?)?.toInt());
      case 'stage':
        return CommissioningStageEvent(raw['stage'] as String? ?? '');
      case 'attestationFailed':
        return AttestationFailedEvent((raw['errorCode'] as num?)?.toInt() ?? -1);
    }
    return null;
  }

  Future<T?> _call<T>(String name, [Map<String, Object?>? args]) async {
    try {
      return await _method.invokeMethod<T>(name, args);
    } on PlatformException catch (e) {
      throw BackendException(e.code, e.message ?? e.code);
    }
  }

  @override
  Future<PairedAc?> loadPairedDevice() async {
    final map = await _call<Map<Object?, Object?>>('loadPairedDevice');
    return map == null ? null : PairedAc.fromMap(map);
  }

  @override
  Future<PairedAc> commission({
    required String setupCode,
    required String wifiSsid,
    required String wifiPassword,
    bool onNetworkOnly = false,
  }) async {
    final map = await _call<Map<Object?, Object?>>('commission', {
      'setupCode': setupCode,
      'ssid': wifiSsid,
      'password': wifiPassword,
      'onNetworkOnly': onNetworkOnly,
    });
    if (map == null) throw const BackendException('no_result', 'Pairing returned no device.');
    return PairedAc.fromMap(map);
  }

  @override
  Future<void> continueCommissioning({required bool ignoreAttestationFailure}) =>
      _call<void>('continueCommissioning', {'ignore': ignoreAttestationFailure});

  @override
  Future<void> connect(PairedAc ac) => _call<void>('connect', {'nodeId': ac.nodeId});

  @override
  Future<void> disconnect() => _call<void>('disconnect');

  @override
  Future<void> setPower(int endpoint, bool on) =>
      _call<void>('setPower', {'endpoint': endpoint, 'on': on});

  @override
  Future<void> writeSystemMode(int endpoint, int mode) => _call<void>('writeAttribute',
      _write(endpoint, ClusterId.thermostat, ThermostatAttr.systemMode, mode));

  @override
  Future<void> writeCoolingSetpoint(int endpoint, int centiCelsius) => _call<void>('writeAttribute',
      _write(endpoint, ClusterId.thermostat, ThermostatAttr.occupiedCoolingSetpoint, centiCelsius));

  @override
  Future<void> writeFanMode(int endpoint, int mode) => _call<void>('writeAttribute',
      _write(endpoint, ClusterId.fanControl, FanControlAttr.fanMode, mode));

  @override
  Future<void> writeRockSetting(int endpoint, int rockBits) => _call<void>('writeAttribute',
      _write(endpoint, ClusterId.fanControl, FanControlAttr.rockSetting, rockBits));

  @override
  Future<void> forget(PairedAc ac) => _call<void>('forget', {'nodeId': ac.nodeId});

  Map<String, Object?> _write(int endpoint, int cluster, int attribute, int value) =>
      {'endpoint': endpoint, 'cluster': cluster, 'attribute': attribute, 'value': value};
}
