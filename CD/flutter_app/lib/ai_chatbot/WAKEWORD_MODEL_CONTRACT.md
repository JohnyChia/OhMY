# Nova openWakeWord model contract

This document describes the required handoff for the next training phase. It
does not add a model, enable a detector, or permit a fallback to speech-to-text.

## Required Android assets

The future Android runtime must load these files from
`android/app/src/main/assets/`:

- `nova_hey_nova.onnx` — the trained and validated Nova wake classifier.
- `nova_wake_config.json` — validated runtime configuration:
  `{"modelAsset":"nova_hey_nova.onnx","threshold":0.0,"cooldownMs":2000}`.
  `threshold` must be replaced with the value justified by the model's
  validation report; `0.0` is only a schema illustration and is rejected by
  the provider.
- `melspectrogram.onnx` — the openWakeWord feature-extraction model.
- `embedding_model.onnx` — the openWakeWord embedding model.

`NovaWakeWordProvider.kt` uses both Nova assets as its availability gate, then
constructs the linked openWakeWord engine from their validated threshold. The
engine receives the exact relative model path. Supporting runtime assets retain
their upstream names because the engine opens them through Android's
AssetManager.

## Detection contract

- Provider: openWakeWord `WakeWordEngine`.
- Model name: `Hey Nova`.
- Audio: mono PCM from the engine's own Android `AudioRecord` path; its sample
  rate and frame shape must match the model-training/export specification.
- Threshold: supplied with the trained model's validation report. It must not
  be guessed or replaced with a constant solely to make testing pass.
- Event: only a score above that validated threshold may emit
  `WakeProviderEvent.Detected("hey nova", score)`.
- Cooldown: supplied to `WakeWordEngine` to prevent repeated detections.

## Lifecycle and handoff

1. `start()` obtains microphone permission and starts only the wake engine.
2. A detection stops the wake engine before `wakeWordDetected` crosses the
   MethodChannel.
3. Flutter's `NovaInvocationManager` starts the existing AudioRecorder for the
   actual spoken request.
4. `stop()`/`release()` cancel detection and release model/audio resources.
5. Missing assets, unavailable runtime, or permission denial emit an explicit
   unavailable/error event; they never start continuous ASR or upload audio.

## Acceptance evidence required before enabling the provider

- Model checksum/version and validation report.
- False-accept and false-reject measurements for Malaysian English, Bahasa
  Malaysia, and rojak speech.
- Physical-device test showing one detection, provider stop, then exactly one
  normal AudioRecorder request session.
- Interruption test while Nova TTS is speaking.
