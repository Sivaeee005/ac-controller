import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/ac_backend.dart';
import '../domain/ac_state.dart';
import '../domain/attribute_reducer.dart';

enum CommandStatus { confirmed, notConfirmed, failed }

/// Result of a user command, as shown to the user.
class CommandOutcome {
  const CommandOutcome(this.status, this.description, {this.message});

  final CommandStatus status;
  final String description;
  final String? message;

  bool get isConfirmed => status == CommandStatus.confirmed;
}

/// Timing settings, adjustable for tests.
class ControllerTimings {
  const ControllerTimings({
    this.sendTimeout = const Duration(seconds: 15),
    this.confirmTimeout = const Duration(seconds: 10),
    this.reconnectBase = const Duration(seconds: 2),
    this.reconnectMax = const Duration(seconds: 60),
  });

  final Duration sendTimeout;
  final Duration confirmTimeout;
  final Duration reconnectBase;
  final Duration reconnectMax;
}

/// Owns the AC state and runs commands with confirmation.
///
/// A command is reported as successful only when the AC's own report shows
/// the requested value. Acceptance by the AC alone is "not confirmed".
class AcController extends ChangeNotifier {
  AcController(this.backend, {this.timings = const ControllerTimings(), Random? random})
      : _random = random ?? Random() {
    _sub = backend.events.listen(_onEvent);
  }

  final AcBackend backend;
  final ControllerTimings timings;
  final Random _random;
  late final StreamSubscription<BackendEvent> _sub;
  final _reducer = AttributeReducer();
  final _stateChanges = StreamController<AcState>.broadcast();

  PairedAc? _paired;
  LinkStatus _link = LinkStatus.notPaired;
  DateTime? _lastSync;
  String? _linkMessage;
  String? _pending;
  CommandOutcome? _lastOutcome;
  Future<CommandOutcome> Function()? _retry;
  String? _commissioningStage;
  int? _attestationError;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;
  Future<void> _queue = Future.value();

  PairedAc? get pairedAc => _paired;
  LinkStatus get link => _link;
  String? get linkMessage => _linkMessage;
  AcState get state => _reducer.state;
  AcCapabilities get capabilities => _reducer.capabilities;

  /// Time of the last attribute report received from the AC.
  DateTime? get lastSync => _lastSync;
  String? get pendingCommand => _pending;
  CommandOutcome? get lastOutcome => _lastOutcome;
  bool get canRetry => _retry != null && _lastOutcome?.isConfirmed == false;
  String? get commissioningStage => _commissioningStage;

  /// Non-null while the user must decide about a failed attestation.
  int? get attestationError => _attestationError;
  bool get isSimulated => backend.isSimulated;

  Future<void> start() async {
    _paired = await backend.loadPairedDevice();
    if (_paired == null) {
      _setLink(LinkStatus.notPaired);
      return;
    }
    await _connect();
  }

  Future<void> pair({
    required String setupCode,
    required String wifiSsid,
    required String wifiPassword,
  }) async {
    _commissioningStage = 'Starting';
    notifyListeners();
    try {
      _paired = await backend.commission(
          setupCode: setupCode, wifiSsid: wifiSsid, wifiPassword: wifiPassword);
    } finally {
      _commissioningStage = null;
      _attestationError = null;
      notifyListeners();
    }
    await _connect();
  }

  Future<void> answerAttestation({required bool proceed}) async {
    _attestationError = null;
    notifyListeners();
    await backend.continueCommissioning(ignoreAttestationFailure: proceed);
  }

  /// Reconnects immediately, cancelling any scheduled retry.
  Future<void> reconnectNow() async {
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    await _connect();
  }

  Future<void> forget() async {
    final ac = _paired;
    if (ac == null) return;
    _reconnectTimer?.cancel();
    await backend.forget(ac);
    _paired = null;
    _reducer
      ..state = const AcState()
      ..capabilities = const AcCapabilities();
    _lastSync = null;
    _setLink(LinkStatus.notPaired);
  }

  Future<CommandOutcome> setPower(bool on) => _run(
        on ? 'Power ON' : 'Power OFF',
        () => backend.setPower(_endpoint, on),
        (s) => s.power == on,
      );

  Future<CommandOutcome> setMode(AcMode mode) => _run(
        'Mode ${mode.name}',
        () => backend.writeSystemMode(_endpoint, mode.matterValue),
        (s) => s.mode == mode,
      );

  /// Sets the cooling target, clamped to the limits reported by the AC.
  Future<CommandOutcome> setTargetTemperature(double celsius) {
    final c = clampSetpoint(celsius);
    final centi = (c * 100).round();
    return _run(
      'Temperature ${c.toStringAsFixed(1)} °C',
      () => backend.writeCoolingSetpoint(_endpoint, centi),
      (s) => s.coolingSetpointC != null && (s.coolingSetpointC! * 100).round() == centi,
    );
  }

  /// Raises or lowers the target by [deltaC] from the reported setpoint.
  Future<CommandOutcome> adjustTemperature(double deltaC) {
    final current = state.coolingSetpointC;
    if (current == null) {
      return Future.value(_finish(const CommandOutcome(CommandStatus.failed,
          'Change temperature',
          message: 'The AC has not reported its target temperature yet.')));
    }
    return setTargetTemperature(current + deltaC);
  }

  Future<CommandOutcome> setFanSpeed(FanSpeed speed) => _run(
        'Fan ${speed.name}',
        () => backend.writeFanMode(_endpoint, speed.matterValue),
        (s) => s.fanSpeed == speed,
      );

  Future<CommandOutcome> setSwing(int rockBits) => _run(
        'Swing',
        () => backend.writeRockSetting(_endpoint, rockBits),
        (s) => s.rockSetting == rockBits,
      );

  Future<CommandOutcome> retryLast() {
    final r = _retry;
    if (r == null) {
      return Future.value(const CommandOutcome(CommandStatus.failed, 'Retry',
          message: 'Nothing to retry.'));
    }
    return r();
  }

  double clampSetpoint(double c) {
    final caps = capabilities;
    // Matter default absolute cooling limits (16-32 °C) apply only when the
    // AC does not report its own limits.
    final lo = caps.minCoolSetpointC ?? 16.0;
    final hi = caps.maxCoolSetpointC ?? 32.0;
    return c.clamp(lo, hi).toDouble();
  }

  int get _endpoint => capabilities.endpoint ?? 1;

  Future<CommandOutcome> _run(
    String description,
    Future<void> Function() send,
    bool Function(AcState) isConfirmed,
  ) {
    // Commands run one at a time, in order.
    final completer = Completer<CommandOutcome>();
    _queue = _queue.then((_) async {
      completer.complete(await _execute(description, send, isConfirmed));
    });
    return completer.future;
  }

  Future<CommandOutcome> _execute(
    String description,
    Future<void> Function() send,
    bool Function(AcState) isConfirmed,
  ) async {
    _retry = () => _run(description, send, isConfirmed);
    if (_link != LinkStatus.connected) {
      return _finish(CommandOutcome(CommandStatus.failed, description,
          message: 'The AC is not connected.'));
    }
    _pending = description;
    _lastOutcome = null;
    notifyListeners();

    // Listen before sending, so a fast report is not missed.
    final confirmed = Completer<void>();
    final listener = _stateChanges.stream.listen((s) {
      if (isConfirmed(s) && !confirmed.isCompleted) confirmed.complete();
    });
    try {
      await send().timeout(timings.sendTimeout);
    } on TimeoutException {
      await listener.cancel();
      return _finish(CommandOutcome(CommandStatus.failed, description,
          message: 'The AC did not answer in time.'));
    } on BackendException catch (e) {
      await listener.cancel();
      return _finish(CommandOutcome(CommandStatus.failed, description, message: e.message));
    }

    if (isConfirmed(state)) {
      await listener.cancel();
      return _finish(CommandOutcome(CommandStatus.confirmed, description));
    }
    try {
      await confirmed.future.timeout(timings.confirmTimeout);
      return _finish(CommandOutcome(CommandStatus.confirmed, description));
    } on TimeoutException {
      return _finish(CommandOutcome(CommandStatus.notConfirmed, description,
          message: 'The AC accepted the command but did not report the new state.'));
    } finally {
      await listener.cancel();
    }
  }

  CommandOutcome _finish(CommandOutcome outcome) {
    _pending = null;
    _lastOutcome = outcome;
    if (outcome.isConfirmed) _retry = null;
    if (!_disposed) notifyListeners();
    return outcome;
  }

  Future<void> _connect() async {
    final ac = _paired;
    if (ac == null) return;
    _setLink(LinkStatus.connecting);
    try {
      await backend.connect(ac);
      _reconnectAttempt = 0;
      _setLink(LinkStatus.connected);
    } on BackendException catch (e) {
      _linkMessage = e.message;
      _setLink(LinkStatus.disconnected);
      _scheduleReconnect();
    }
  }

  /// Exponential backoff with jitter, capped at [ControllerTimings.reconnectMax].
  Duration nextReconnectDelay({int? attempt}) {
    final base = timings.reconnectBase.inMilliseconds * pow(2, attempt ?? _reconnectAttempt);
    final capped = min(base.toDouble(), timings.reconnectMax.inMilliseconds.toDouble());
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    return Duration(milliseconds: (capped * jitter).round());
  }

  void _scheduleReconnect() {
    if (_disposed || _paired == null) return;
    final delay = nextReconnectDelay();
    _reconnectAttempt = min(_reconnectAttempt + 1, 16);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }

  void _onEvent(BackendEvent e) {
    switch (e) {
      case ReportsEvent(:final reports):
        var changed = false;
        for (final r in reports) {
          changed = _reducer.apply(r) || changed;
        }
        _lastSync = DateTime.now();
        if (changed) _stateChanges.add(_reducer.state);
        notifyListeners();
      case LinkUpEvent():
        _linkMessage = null;
        if (_paired != null) _setLink(LinkStatus.connected);
      case LinkDownEvent(:final reason):
        _linkMessage = reason;
        _setLink(LinkStatus.disconnected);
      case CommissioningStageEvent(:final stage):
        _commissioningStage = stage;
        notifyListeners();
      case AttestationFailedEvent(:final errorCode):
        _attestationError = errorCode;
        notifyListeners();
    }
  }

  void _setLink(LinkStatus s) {
    _link = s;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub.cancel();
    _stateChanges.close();
    super.dispose();
  }

  @visibleForTesting
  AttributeReducer get reducer => _reducer;
}
