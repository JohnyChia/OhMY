import 'package:flutter/material.dart';
import '../services/nova_voice_controller.dart';

/// Manual foreground invocation; never enables an always-listening mic.
class NovaSoloVoiceButton extends StatelessWidget {
  const NovaSoloVoiceButton({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 52,
    child: FloatingActionButton.small(
      heroTag: null,
      tooltip: 'Talk to Nova',
      backgroundColor: Colors.white,
      onPressed: () => NovaVoiceController.requestVoiceSession(
        source: NovaInvocationSource.manualMicrophone,
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Image.asset(
          'assets/images/navigation/aiBotOn.png',
          errorBuilder: (_, _, _) =>
              const Icon(Icons.mic, color: Color(0xff3266cc)),
        ),
      ),
    ),
  );
}
