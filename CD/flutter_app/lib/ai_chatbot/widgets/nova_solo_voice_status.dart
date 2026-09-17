import 'package:flutter/material.dart';

import '../services/nova_voice_controller.dart';
import 'nova_bottom_assistant.dart';

/// Voice status rendered in the same Flutter layer as Solo Trip map controls.
class NovaSoloVoiceStatus extends StatelessWidget {
  const NovaSoloVoiceStatus({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<NovaVoiceState>(
    valueListenable: NovaVoiceController.state,
    builder: (_, state, _) => state.phase == NovaVoicePhase.idle
        ? const SizedBox.shrink()
        : NovaBottomAssistant(
            state: state,
            onDismiss: NovaVoiceController.dismiss,
            compact: true,
          ),
  );
}
