import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/ai_chatbot/services/nova_voice_choice_controller.dart';

void main() {
  test(
    'the active page receives a transcript without local phrase matching',
    () async {
      String? received;
      final registration = NovaVoiceChoiceController.register((transcript) {
        received = transcript;
        return true;
      });

      final transcript = DateTime.now().microsecondsSinceEpoch.toString();
      expect(await NovaVoiceChoiceController.consume(transcript), isTrue);
      expect(received, transcript);
      registration.dispose();
    },
  );

  test('a disposed page no longer receives voice choices', () async {
    final registration = NovaVoiceChoiceController.register((_) => true);
    registration.dispose();
    expect(await NovaVoiceChoiceController.consume(''), isFalse);
  });
}
