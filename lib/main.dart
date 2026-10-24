import 'package:flutter/material.dart';

import 'src/data/ac_backend.dart';
import 'src/data/matter_channel_backend.dart';
import 'src/data/simulated_backend.dart';
import 'src/services/ac_controller.dart';
import 'src/ui/app.dart';

/// Build with `--dart-define=SIMULATED=true` for the demo build that uses a
/// simulated AC instead of the real one.
const simulated = bool.fromEnvironment('SIMULATED');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final AcBackend backend = simulated ? SimulatedBackend() : MatterChannelBackend();
  final controller = AcController(backend)..start();
  runApp(AcApp(controller: controller));
}
