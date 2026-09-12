import 'api_service.dart';

/// Single post-capture boundary for manual-chat and wake-initiated speech.
/// The backend returns one canonical corrected transcript; raw ASR remains
/// diagnostic-only and is never sent as an additional Agent or memory turn.
class VoiceTextPipeline {
  VoiceTextPipeline._();

  static Future<VoiceTranscript> processAudio(
    String audioPath, {
    String? context,
  }) => ApiService.transcribeAudio(audioPath, context: context);
}
