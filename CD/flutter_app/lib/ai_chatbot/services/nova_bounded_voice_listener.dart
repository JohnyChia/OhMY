import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'nova_voice_controller.dart';
import 'voice_text_pipeline.dart';

/// A short, foreground-only cloud ASR turn owned by the page that asked the
/// question. It does not depend on the AI Chat widget or the optional wake
/// model being mounted.
class NovaBoundedVoiceListener {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  Timer? _silenceTimer;
  Timer? _maximumTimer;
  DateTime? _startedAt;
  double? _noiseFloorDb;
  bool _speechDetected = false;
  bool _recording = false;
  bool _stopping = false;
  int _generation = 0;

  bool get isRecording => _recording;

  Future<bool> start({
    required FutureOr<void> Function(String transcript) onTranscript,
    String? context,
    FutureOr<void> Function(Object error)? onError,
    FutureOr<void> Function()? onSilence,
  }) async {
    await stop(discard: true);
    final generation = ++_generation;
    try {
      if (!await _recorder.hasPermission()) return false;
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/nova-choice-$generation.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      _recording = true;
      _speechDetected = false;
      _noiseFloorDb = null;
      _startedAt = DateTime.now();
      NovaVoiceController.update(
        phase: NovaVoicePhase.listening,
        clearMessage: true,
        clearResponse: true,
      );
      _amplitudeSubscription = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amplitude) {
            if (!_recording || generation != _generation) return;
            final age = DateTime.now().difference(_startedAt!);
            if (!_speechDetected &&
                age < const Duration(milliseconds: 450) &&
                amplitude.current.isFinite) {
              _noiseFloorDb = _noiseFloorDb == null
                  ? amplitude.current
                  : (_noiseFloorDb! * .72) + (amplitude.current * .28);
            }
            final threshold = ((_noiseFloorDb ?? -55) + 7).clamp(-58, -20);
            if (age > const Duration(milliseconds: 240) &&
                amplitude.current > threshold) {
              _speechDetected = true;
              _silenceTimer?.cancel();
              _silenceTimer = Timer(const Duration(milliseconds: 850), () {
                unawaited(
                  _finish(
                    generation,
                    context,
                    onTranscript,
                    onError,
                    onSilence,
                  ),
                );
              });
            }
          });
      _maximumTimer = Timer(const Duration(seconds: 12), () {
        unawaited(
          _finish(generation, context, onTranscript, onError, onSilence),
        );
      });
      return true;
    } catch (error) {
      await stop(discard: true);
      await onError?.call(error);
      return false;
    }
  }

  Future<void> _finish(
    int generation,
    String? context,
    FutureOr<void> Function(String transcript) onTranscript,
    FutureOr<void> Function(Object error)? onError,
    FutureOr<void> Function()? onSilence,
  ) async {
    if (!_recording || _stopping || generation != _generation) return;
    _stopping = true;
    try {
      final path = await _recorder.stop();
      _recording = false;
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      _silenceTimer?.cancel();
      _maximumTimer?.cancel();
      if (!_speechDetected || path == null) {
        await onSilence?.call();
        return;
      }
      NovaVoiceController.update(phase: NovaVoicePhase.thinking);
      final transcript = await VoiceTextPipeline.processAudio(
        path,
        context: context,
      );
      if (generation == _generation) {
        await onTranscript(transcript.correctedText);
      }
    } catch (error) {
      if (generation == _generation) await onError?.call(error);
    } finally {
      _stopping = false;
    }
  }

  Future<void> stop({bool discard = false}) async {
    _generation++;
    _silenceTimer?.cancel();
    _maximumTimer?.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    if (_recording && !_stopping) {
      _stopping = true;
      try {
        await _recorder.stop();
      } finally {
        _recording = false;
        _stopping = false;
      }
    }
  }

  Future<void> dispose() async {
    await stop(discard: true);
    await _recorder.dispose();
  }
}
