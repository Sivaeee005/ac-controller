// SIMULATED UI tests: they use SimulatedBackend, not the real AC.
import 'package:ac_controller/src/data/simulated_backend.dart';
import 'package:ac_controller/src/services/ac_controller.dart';
import 'package:ac_controller/src/ui/app.dart';
import 'package:ac_controller/src/ui/formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows pairing screen and SIMULATED banner when not paired', (tester) async {
    final c = AcController(SimulatedBackend(latency: Duration.zero));
    await tester.runAsync(c.start);
    await tester.pumpWidget(AcApp(controller: c));
    expect(find.textContaining('SIMULATED'), findsOneWidget);
    expect(find.text('Pair AC'), findsOneWidget);
  });

  testWidgets('power button shows reported state and confirmation', (tester) async {
    // Created inside runAsync so its streams and timers use real time,
    // as they do in the app (the widget-test zone uses fake time).
    late final AcController c;
    await tester.runAsync(() async {
      c = AcController(
          SimulatedBackend(latency: const Duration(milliseconds: 5), startPaired: true));
      await c.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpWidget(AcApp(controller: c));
    await tester.pump();
    expect(find.text('AC reports: OFF'), findsOneWidget);
    expect(find.text('Room temperature'), findsOneWidget);
    // Room temperature is not reported by the simulated AC and must not be invented.
    expect(find.text(notReported), findsWidgets);

    await tester.runAsync(() async {
      await c.setPower(true);
    });
    await tester.pump();
    expect(find.text('AC reports: ON'), findsOneWidget);
    expect(find.text('Power ON: confirmed by the AC'), findsOneWidget);
  });

  test('capability report contains no secrets and lists features', () {
    final c = AcController(SimulatedBackend());
    final text = capabilityReport(c.capabilities, c.state);
    expect(text, contains('Vendor:'));
    expect(text.toLowerCase(), isNot(contains('password')));
  });

  test('sync time formatting', () {
    final now = DateTime(2026, 10, 24, 12, 0, 0);
    expect(formatSync(null), 'never');
    expect(formatSync(now.subtract(const Duration(seconds: 2)), now: now), 'just now');
    expect(formatSync(now.subtract(const Duration(seconds: 30)), now: now), '30 s ago');
    expect(formatSync(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
  });

  test('swing formatting', () {
    expect(formatSwing(null), notReported);
    expect(formatSwing(0), 'Off');
    expect(formatSwing(2), 'Up-down');
    expect(formatSwing(3), 'Up-down + Left-right');
  });

  testWidgets('pairing page hides the Wi-Fi password by default', (tester) async {
    final c = AcController(SimulatedBackend(latency: Duration.zero));
    await tester.runAsync(c.start);
    await tester.pumpWidget(AcApp(controller: c));
    final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Wi-Fi password'));
    expect(field.obscureText, isTrue);
  });

  testWidgets('debug report opens from the app bar', (tester) async {
    final c = AcController(SimulatedBackend(latency: Duration.zero));
    await tester.runAsync(c.start);
    await tester.pumpWidget(AcApp(controller: c));
    await tester.tap(find.byTooltip('Debug report'));
    await tester.pumpAndSettle();
    expect(find.text('Debug report'), findsOneWidget);
    expect(find.textContaining('Simulated build'), findsOneWidget);
  });
}
