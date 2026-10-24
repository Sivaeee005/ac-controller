import 'package:flutter/material.dart';

import '../domain/ac_state.dart';
import '../services/ac_controller.dart';
import 'device_page.dart';
import 'pairing_page.dart';

class AcApp extends StatelessWidget {
  const AcApp({super.key, required this.controller});

  final AcController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AC Controller',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.blue, brightness: Brightness.dark, useMaterial3: true),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('AC Controller')),
          body: Column(
            children: [
              if (controller.isSimulated) const SimulatedBanner(),
              Expanded(
                child: controller.link == LinkStatus.notPaired
                    ? PairingPage(controller: controller)
                    : DevicePage(controller: controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Always visible in the simulated build, so results are never mistaken
/// for real AC results.
class SimulatedBanner extends StatelessWidget {
  const SimulatedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade800,
      padding: const EdgeInsets.all(8),
      child: const Text(
        'SIMULATED AC — not connected to a real air conditioner',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}
