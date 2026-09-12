package com.example.flutter_app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log

/**
 * Short-lived foreground ASR used while Nova is speaking. Flutter's visible
 * owner interprets each transcript; this class only streams partial/final
 * text and never performs an Agent action or starts a journey itself.
 */
class NovaBargeInRecognizer(
    private val context: Context,
    private val onSpeechStarted: () -> Unit,
    private val onTranscript: (String, Boolean) -> Unit,
) : RecognitionListener {
    companion object {
        private const val TAG = "NovaBargeIn"
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var active = false
    private var languageCode = "en-MY"
    private var useLanguageHint = true
    private var fallbackLanguageAttempted = false
    private var speechStarted = false
    private var readyAtMillis = 0L
    private var rmsFloor: Float? = null
    private var elevatedRmsSamples = 0

    fun start(language: String): Boolean {
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            Log.w(TAG, "No Android speech recognition service is available")
            return false
        }
        languageCode = when {
            language.startsWith("zh", ignoreCase = true) -> "zh-CN"
            language.startsWith("ms", ignoreCase = true) -> "ms-MY"
            else -> "en-MY"
        }
        useLanguageHint = true
        fallbackLanguageAttempted = false
        active = true
        speechStarted = false
        readyAtMillis = 0L
        rmsFloor = null
        elevatedRmsSamples = 0
        if (recognizer == null) {
            recognizer = SpeechRecognizer.createSpeechRecognizer(context).also {
                it.setRecognitionListener(this)
            }
        }
        listen()
        Log.d(TAG, "Started foreground recognizer language=$languageCode")
        return true
    }

    fun stop() {
        active = false
        mainHandler.removeCallbacksAndMessages(null)
        recognizer?.cancel()
    }

    fun release() {
        stop()
        recognizer?.destroy()
        recognizer = null
    }

    private fun listen() {
        if (!active) return
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            // Some Android/Huawei recognizer providers reject otherwise valid
            // BCP-47 locales with ERROR_LANGUAGE_NOT_SUPPORTED.  The first
            // attempt honours Nova's current language; after that provider
            // error we retry in the recognizer's own multilingual/default
            // mode instead of spinning forever on an unsupported locale.
            if (useLanguageHint) {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageCode)
            }
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            if (useLanguageHint && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val supportedLanguages = arrayListOf("en-MY", "ms-MY", "zh-CN")
                putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, true)
                putStringArrayListExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_DETECTION_ALLOWED_LANGUAGES,
                    supportedLanguages,
                )
                putExtra(
                    RecognizerIntent.EXTRA_ENABLE_LANGUAGE_SWITCH,
                    RecognizerIntent.LANGUAGE_SWITCH_BALANCED,
                )
                putStringArrayListExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_SWITCH_ALLOWED_LANGUAGES,
                    supportedLanguages,
                )
            }
        }
        try {
            recognizer?.startListening(intent)
        } catch (_: Exception) {
            scheduleRestart()
        }
    }

    private fun emit(results: Bundle?, isFinal: Boolean) {
        val candidates = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            .orEmpty()
        candidates.firstOrNull { it.isNotBlank() }?.let { transcript ->
            signalSpeechStarted()
            Log.d(TAG, "Transcript final=$isFinal length=${transcript.length}")
            onTranscript(transcript, isFinal)
        }
    }

    private fun signalSpeechStarted() {
        if (speechStarted) return
        speechStarted = true
        onSpeechStarted()
    }

    private fun scheduleRestart() {
        if (!active) return
        mainHandler.postDelayed({ listen() }, 250)
    }

    override fun onPartialResults(partialResults: Bundle?) = emit(partialResults, false)

    override fun onResults(results: Bundle?) {
        emit(results, true)
        speechStarted = false
        scheduleRestart()
    }

    override fun onError(error: Int) {
        Log.w(TAG, "Recognition error=$error active=$active")
        speechStarted = false
        if (error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE)
        ) {
            if (!fallbackLanguageAttempted) {
                fallbackLanguageAttempted = true
                useLanguageHint = false
                Log.w(TAG, "Retrying with the recognizer's provider-default language mode")
                scheduleRestart()
            } else {
                // Do not spin forever on devices whose foreground recognizer
                // exposes no compatible language pack. TTS can finish and the
                // normal multilingual recorder will take the next turn.
                active = false
                Log.w(TAG, "Foreground recognizer has no compatible language pack")
            }
            return
        }
        if (error != SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
            scheduleRestart()
        }
    }

    override fun onReadyForSpeech(params: Bundle?) {
        readyAtMillis = System.currentTimeMillis()
        rmsFloor = null
        elevatedRmsSamples = 0
        Log.d(TAG, "Ready for speech")
    }
    override fun onBeginningOfSpeech() = signalSpeechStarted()
    override fun onRmsChanged(rmsdB: Float) {
        if (!active || speechStarted || !rmsdB.isFinite()) return
        val age = System.currentTimeMillis() - readyAtMillis
        if (readyAtMillis == 0L || age < 500L) {
            rmsFloor = rmsFloor?.let { (it * 0.72f) + (rmsdB * 0.28f) } ?: rmsdB
            return
        }
        val threshold = ((rmsFloor ?: rmsdB) + 6.0f).coerceIn(1.5f, 11.0f)
        elevatedRmsSamples = if (rmsdB >= threshold) elevatedRmsSamples + 1 else 0
        if (elevatedRmsSamples >= 3) {
            Log.d(TAG, "Speech onset inferred from sustained RMS")
            signalSpeechStarted()
        }
    }
    override fun onBufferReceived(buffer: ByteArray?) = Unit
    override fun onEndOfSpeech() = Unit
    override fun onEvent(eventType: Int, params: Bundle?) = Unit
}
