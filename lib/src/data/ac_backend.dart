import '../domain/attribute_reducer.dart';

/// An AC paired to this app's own Matter fabric.
class PairedAc {
  const PairedAc({required this.nodeId, this.label});

  factory PairedAc.fromMap(Map<Object?, Object?> map) => PairedAc(
        nodeId: (map['nodeId'] as num).toInt(),
        label: map['label'] as String?,
      );

  final int nodeId;
  final String? label;

  Map<String, Object?> toMap() => {'nodeId': nodeId, 'label': label};
}

/// Error raised by a backend, with a user-readable message.
class BackendException implements Exception {
  const BackendException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'BackendException($code): $message';
}

sealed class BackendEvent {
  const BackendEvent();
}

/// Attribute values reported by the AC (initial report and later changes).
class ReportsEvent extends BackendEvent {
  const ReportsEvent(this.reports);
  final List<AttributeReport> reports;
}

/// The Matter session with the AC is up (subscription established).
class LinkUpEvent extends BackendEvent {
  const LinkUpEvent();
}

/// The Matter session with the AC was lost; the SDK may be resubscribing.
class LinkDownEvent extends BackendEvent {
  const LinkDownEvent(this.reason, {this.retryInMs});
  final String reason;
  final int? retryInMs;
}

/// A step of the pairing process, for progress display.
class CommissioningStageEvent extends BackendEvent {
  const CommissioningStageEvent(this.stage);
  final String stage;
}

/// Device attestation failed; the user must decide whether to continue.
class AttestationFailedEvent extends BackendEvent {
  const AttestationFailedEvent(this.errorCode);
  final int errorCode;
}

/// Transport to the AC (real Matter bridge or simulator).
abstract interface class AcBackend {
  /// True for the simulator. The UI must show a "SIMULATED" banner.
  bool get isSimulated;

  Stream<BackendEvent> get events;

  /// Returns the AC already paired to this app, if any.
  Future<PairedAc?> loadPairedDevice();

  /// Pairs a new AC over Bluetooth and sends it the Wi-Fi credentials.
  ///
  /// [setupCode] is the QR text (`MT:...`) or the 11-digit manual code.
  /// The credentials are passed to the AC only and are not stored.
  Future<PairedAc> commission({
    required String setupCode,
    required String wifiSsid,
    required String wifiPassword,
  });

  /// Answer to an [AttestationFailedEvent].
  Future<void> continueCommissioning({required bool ignoreAttestationFailure});

  /// Connects to the paired AC and subscribes to its attributes.
  /// Completes when the first full report has been delivered.
  Future<void> connect(PairedAc ac);

  Future<void> disconnect();

  /// Each command completes when the AC accepts it, and throws
  /// [BackendException] when the AC rejects it or cannot be reached.
  /// Acceptance is not confirmation: the caller must wait for a report.
  Future<void> setPower(int endpoint, bool on);
  Future<void> writeSystemMode(int endpoint, int mode);
  Future<void> writeCoolingSetpoint(int endpoint, int centiCelsius);
  Future<void> writeFanMode(int endpoint, int mode);
  Future<void> writeRockSetting(int endpoint, int rockBits);

  /// Removes this app from the AC (its Matter fabric) and forgets it locally.
  Future<void> forget(PairedAc ac);
}
