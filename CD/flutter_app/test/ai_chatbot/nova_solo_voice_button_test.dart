import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/ai_chatbot/widgets/nova_solo_voice_button.dart';
import 'package:flutter_app/ai_chatbot/services/nova_voice_controller.dart';

void main() {
  testWidgets('tiger opens manual voice mode without navigating to chat', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: NovaSoloVoiceButton())),
    );
    final starts = NovaVoiceController.startRequests.value;
    await tester.tap(find.byTooltip('Talk to Nova'));
    await tester.pump();
    expect(NovaVoiceController.startRequests.value, starts + 1);
    final invocation = NovaVoiceController.takePendingInvocation();
    expect(invocation?.source, NovaInvocationSource.manualMicrophone);
    expect(invocation?.announce, isFalse);
    expect(find.byType(NovaSoloVoiceButton), findsOneWidget);
    NovaVoiceController.dismiss();
  });
}
