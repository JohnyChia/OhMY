package com.example.flutter_app

import android.content.Context
import com.rementia.openwakeword.lib.WakeWordEngine
import com.rementia.openwakeword.lib.model.WakeWordModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Android-only boundary for a local wake-word engine. The provider owns only
 * the short wake capture. After [WakeProviderEvent.Detected], MainActivity
 * must stop it before Flutter's AudioRecorder starts the actual request.
 */
interface NovaWakeWordProvider {
    /** True only when the active provider can really open microphone capture. */
    val requiresAudioPermission: Boolean
    fun start()
    fun stop()
    fun release()
}

sealed interface WakeProviderEvent {
    data object Started : WakeProviderEvent
    data object Stopped : WakeProviderEvent
    data class Detected(val phrase: String, val score: Float) : WakeProviderEvent
    data class Unavailable(val reason: String) : WakeProviderEvent
    data class Error(val reason: String) : WakeProviderEvent
}

/**
 * openWakeWord provider configuration boundary.
 *
 * The bundled openWakeWord source requires a trained Nova ONNX asset and a
 * linked runtime module. Neither is fabricated here. Until both are supplied,
 * start reports an explicit unavailable state and never falls back to
 * SpeechRecognizer transcript matching.
 */
class OpenWakeWordProvider(
    private val context: Context,
    private val onEvent: (WakeProviderEvent) -> Unit,
) : NovaWakeWordProvider {
    companion object {
        const val MODEL_ASSET = "nova_hey_nova.onnx"
        const val CONFIG_ASSET = "nova_wake_config.json"
    }

    private var started = false
    private var engine: WakeWordEngine? = null
    private var detectionJob: Job? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override val requiresAudioPermission: Boolean
        get() = configurationOrNull() != null

    override fun start() {
        if (started) return
        val configuration = configurationOrNull()
        if (configuration == null) {
            onEvent(WakeProviderEvent.Unavailable("MODEL_ASSET_OR_CONFIG_NOT_CONFIGURED"))
            return
        }
        try {
            val activeEngine = engine ?: WakeWordEngine(
                context = context,
                models = listOf(
                    WakeWordModel(
                        name = "Hey Nova",
                        modelPath = MODEL_ASSET,
                        threshold = configuration.threshold,
                    ),
                ),
                detectionCooldownMs = configuration.cooldownMs,
            ).also { engine = it }
            detectionJob?.cancel()
            detectionJob = scope.launch {
                activeEngine.detections.collect { detection ->
                    onEvent(WakeProviderEvent.Detected("hey nova", detection.score))
                }
            }
            activeEngine.start()
            started = true
            onEvent(WakeProviderEvent.Started)
        } catch (error: Exception) {
            started = false
            detectionJob?.cancel()
            detectionJob = null
            // A constructor/start failure can still have allocated model or
            // recorder resources. Do not retain a half-started engine for a
            // later lifecycle retry.
            engine?.stop()
            engine?.release()
            engine = null
            onEvent(WakeProviderEvent.Error("OPENWAKEWORD_START_FAILED:${error.javaClass.simpleName}"))
        }
    }

    override fun stop() {
        if (!started) return
        started = false
        detectionJob?.cancel()
        detectionJob = null
        // WakeWordEngine owns its own AudioRecord coroutine. Cancelling this
        // provider's Flow collector alone would leave that recorder active and
        // race Flutter's AudioRecorder after a genuine wake detection.
        engine?.stop()
        onEvent(WakeProviderEvent.Stopped)
    }

    override fun release() {
        stop()
        engine?.release()
        engine = null
        scope.cancel()
    }

    private data class Configuration(val threshold: Float, val cooldownMs: Long)

    private fun configurationOrNull(): Configuration? = try {
        context.assets.open(MODEL_ASSET).close()
        val json = context.assets.open(CONFIG_ASSET).bufferedReader().use { it.readText() }
        val objectValue = JSONObject(json)
        val modelName = objectValue.optString("modelAsset")
        val threshold = objectValue.optDouble("threshold", Double.NaN).toFloat()
        val cooldownMs = objectValue.optLong("cooldownMs", -1L)
        if (modelName != MODEL_ASSET || !threshold.isFinite() || threshold <= 0f ||
            threshold >= 1f || cooldownMs < 0L
        ) {
            null
        } else {
            Configuration(threshold, cooldownMs)
        }
    } catch (_: Exception) {
        null
    }
}
