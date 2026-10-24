// All tests in this file run against SimulatedBackend. They are SIMULATED
// tests and say nothing about the real AC.
import 'dart:math';

import 'package:ac_controller/src/data/simulated_backend.dart';
import 'package:ac_controller/src/domain/ac_state.dart';
import 'package:ac_controller/src/services/ac_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const fast = ControllerTimings(
  sendTimeout: Duration(seconds: 2),
  confirmTimeout: Duration(milliseconds: 400),
  reconnectBase: Duration(milliseconds: 50),
  reconnectMax: Duration(milliseconds: 400),
);

Future<(SimulatedBackend, AcController)> connected() async {
  final backend = SimulatedBackend(latency: const Duration(milliseconds: 10), startPaired: true);
  final controller = AcController(backend, timings: fast, random: Random(1));
  await controller.start();
  await pumpEvents();
  return (backend, controller);
}

Future<void> pumpEvents() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  test('connects and builds state and capabilities from reports', () async {
    final (_, c) = await connected();
    expect(c.link, LinkStatus.connected);
    expect(c.lastSync, isNotNull);
    expect(c.state.power, isFalse);
    expect(c.state.mode, AcMode.cool);
    expect(c.state.coolingSetpointC, 24.0);
    expect(c.capabilities.endpoint, 1);
    expect(c.capabilities.canCool, isTrue);
    expect(c.capabilities.canHeat, isFalse);
    expect(c.capabilities.standardModes, [AcMode.cool]);
    expect(c.capabilities.fanSpeeds,
        [FanSpeed.low, FanSpeed.medium, FanSpeed.high, FanSpeed.auto]);
    expect(c.capabilities.hasSwing, isTrue);
    expect(c.capabilities.minCoolSetpointC, 16.0);
    expect(c.capabilities.maxCoolSetpointC, 30.0);
  });

  test('room temperature stays unknown when the AC does not report it', () async {
    final (_, c) = await connected();
    expect(c.state.roomTemperatureC, isNull);
  });

  test('power ON is confirmed only by the reported state', () async {
    final (_, c) = await connected();
    final outcome = await c.setPower(true);
    expect(outcome.status, CommandStatus.confirmed);
    expect(c.state.power, isTrue);
    expect(c.pendingCommand, isNull);
  });

  test('accepted command without a report is "not confirmed"', () async {
    final (b, c) = await connected();
    b.dropNextReport = true;
    final outcome = await c.setPower(true);
    expect(outcome.status, CommandStatus.notConfirmed);
    expect(c.state.power, isFalse, reason: 'UI must keep showing the reported state');
    expect(c.canRetry, isTrue);
  });

  test('rejected command fails and retry succeeds', () async {
    final (b, c) = await connected();
    b.failNextCommand = true;
    final first = await c.setPower(true);
    expect(first.status, CommandStatus.failed);
    expect(first.message, contains('rejected'));
    expect(c.canRetry, isTrue);
    final second = await c.retryLast();
    expect(second.status, CommandStatus.confirmed);
    expect(c.canRetry, isFalse);
  });

  test('commands fail clearly when the AC is not connected', () async {
    final (b, c) = await connected();
    b.simulateLinkLoss();
    await pumpEvents();
    expect(c.link, LinkStatus.disconnected);
    final outcome = await c.setPower(true);
    expect(outcome.status, CommandStatus.failed);
    expect(outcome.message, contains('not connected'));
  });

  test('unsupported mode is reported as failed, state unchanged', () async {
    final backend = SimulatedBackend(
        latency: const Duration(milliseconds: 10), startPaired: true, rejectedModes: {8});
    final c = AcController(backend, timings: fast);
    await c.start();
    await pumpEvents();
    final outcome = await c.setMode(AcMode.dry);
    expect(outcome.status, CommandStatus.failed);
    expect(c.state.mode, AcMode.cool);
  });

  test('temperature adjust uses reported setpoint and AC limits', () async {
    final (_, c) = await connected();
    expect((await c.adjustTemperature(1)).status, CommandStatus.confirmed);
    expect(c.state.coolingSetpointC, 25.0);
    final outcome = await c.setTargetTemperature(40);
    expect(outcome.status, CommandStatus.confirmed);
    expect(c.state.coolingSetpointC, 30.0, reason: 'clamped to MaxCoolSetpointLimit');
  });

  test('changes made with the IR remote are shown', () async {
    final (b, c) = await connected();
    final before = c.lastSync!;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    b.simulateRemoteChange(power: true, setpoint: 2200);
    await pumpEvents();
    expect(c.state.power, isTrue);
    expect(c.state.coolingSetpointC, 22.0);
    expect(c.lastSync!.isAfter(before), isTrue);
  });

  test('commands run in order', () async {
    final (_, c) = await connected();
    final results = await Future.wait(
        [c.setTargetTemperature(20), c.setTargetTemperature(21), c.setTargetTemperature(22)]);
    expect(results.every((r) => r.isConfirmed), isTrue);
    expect(c.state.coolingSetpointC, 22.0);
  });

  test('unreachable AC schedules reconnect and recovers', () async {
    final backend = SimulatedBackend(latency: const Duration(milliseconds: 10), startPaired: true)
      ..unreachable = true;
    final c = AcController(backend, timings: fast, random: Random(1));
    await c.start();
    expect(c.link, LinkStatus.disconnected);
    expect(c.linkMessage, contains('could not be reached'));
    backend.unreachable = false;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(c.link, LinkStatus.connected);
  });

  test('reconnect delay grows and is capped', () {
    final c = AcController(SimulatedBackend(), timings: fast, random: Random(1));
    // base 50 ms, +/-20 % jitter
    expect(c.nextReconnectDelay(attempt: 0).inMilliseconds, inInclusiveRange(40, 60));
    expect(c.nextReconnectDelay(attempt: 2).inMilliseconds, inInclusiveRange(160, 240));
    // capped at 400 ms, never wraps back to zero
    for (final a in [3, 5, 10, 16]) {
      expect(c.nextReconnectDelay(attempt: a).inMilliseconds, inInclusiveRange(320, 480));
    }
  });

  test('pairing reports progress and connects', () async {
    final backend = SimulatedBackend(latency: const Duration(milliseconds: 5));
    final c = AcController(backend, timings: fast);
    await c.start();
    expect(c.link, LinkStatus.notPaired);
    final stages = <String>[];
    c.addListener(() {
      final s = c.commissioningStage;
      if (s != null && (stages.isEmpty || stages.last != s)) stages.add(s);
    });
    await c.pair(setupCode: 'MT:TEST', wifiSsid: 'home', wifiPassword: 'x');
    await pumpEvents();
    expect(stages, containsAll(['Scanning Bluetooth', 'Sending Wi-Fi']));
    expect(c.link, LinkStatus.connected);
    expect(c.pairedAc, isNotNull);
  });

  test('forget clears state and returns to not paired', () async {
    final (_, c) = await connected();
    await c.forget();
    expect(c.link, LinkStatus.notPaired);
    expect(c.state.power, isNull);
  });
}
