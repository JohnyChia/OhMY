# Nova wake-word asset

Place the trained and validated openWakeWord classifier at
`nova_hey_nova.onnx`. The Android build already packages the compatible
`melspectrogram.onnx` and `embedding_model.onnx` preprocessing models from the
bundled openWakeWord source tree.

Train it as one binary classifier with both target phrases: `hi nova` and
`hey nova`. The Android loader reads one asset byte array, so if the exporter
creates `nova_hey_nova.onnx.data`, consolidate the external weights into the
ONNX file before copying it here. The final app asset must be the single file
`nova_hey_nova.onnx`. The classifier must use the standard openWakeWord
`[1, 16, 96]` feature input expected by the bundled Android runtime.

Do not rename an example classifier such as `hello_world.onnx`: its detected
phrase and accuracy do not match Nova. Keep the threshold and cooldown in
`nova_wake_config.json` tuned to validation results from representative phones,
accents, speakers, background noise, and negative phrases.
