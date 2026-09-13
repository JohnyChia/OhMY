import 'package:flutter_app/ai_chatbot/services/nova_voice_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(NovaVoiceController.reset);

  test('dismiss clears thinking and pending microphone invocation', () {
    NovaVoiceController.requestVoiceSession();
    NovaVoiceController.update(phase: NovaVoicePhase.thinking);
    final starts = NovaVoiceController.startRequests.value;
    final cancellations = NovaVoiceController.cancelRequests.value;
    NovaVoiceController.dismiss();
    expect(NovaVoiceController.state.value.phase, NovaVoicePhase.idle);
    expect(NovaVoiceController.takePendingInvocation(), isNull);
    expect(NovaVoiceController.startRequests.value, starts);
    expect(NovaVoiceController.cancelRequests.value, cancellations + 1);
  });

  test(
    'dismiss notifies the session owner before late work can restart it',
    () {
      var cancelled = false;
      void listener() => cancelled = true;
      NovaVoiceController.cancelRequests.addListener(listener);
      NovaVoiceController.dismiss();
      expect(cancelled, isTrue);
      NovaVoiceController.cancelRequests.removeListener(listener);
    },
  );
}
