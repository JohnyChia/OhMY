package com.example.flutter_app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Nova's Android host bridge. Wake invocation remains provider-based; Android
 * SpeechRecognizer is used only for the bounded, foreground route barge-in
 * session. Flutter AudioRecorder owns ordinary spoken requests after wake.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "ohmy/nova_invocation"
        private const val ATTACHMENT_CHANNEL = "ohmy/nova_attachment"
        private const val BARGE_IN_CHANNEL = "ohmy/nova_barge_in"
        private const val RECORD_AUDIO_REQUEST = 4102
        private const val PICK_DOCUMENT_REQUEST = 4103
        private const val TAG = "NovaWake"
        private const val MAX_ATTACHMENT_BYTES = 8L * 1024 * 1024
    }

    private var invocationChannel: MethodChannel? = null
    private var attachmentChannel: MethodChannel? = null
    private var bargeInChannel: MethodChannel? = null
    private lateinit var wakeWordProvider: NovaWakeWordProvider
    private lateinit var bargeInRecognizer: NovaBargeInRecognizer
    private var wantsWakeListener = false
    private var activityReady = false
    private var documentPickResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_DOCUMENT_REQUEST) return
        val result = documentPickResult ?: return
        documentPickResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        try {
            val uri = data.data!!
            val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
            if (mimeType !in setOf("image/jpeg", "image/png", "image/webp", "text/plain", "application/pdf")) {
                result.error("UNSUPPORTED_TYPE", "Nova supports JPEG, PNG, WebP, TXT, and PDF files.", null)
                return
            }
            val name = queryDisplayName(uri) ?: "nova_attachment"
            val destinationDir = File(cacheDir, "nova_attachments").apply { mkdirs() }
            val safeName = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val destination = File(destinationDir, "${System.currentTimeMillis()}_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(8192)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        total += read
                        if (total > MAX_ATTACHMENT_BYTES) {
                            throw IllegalArgumentException("Attachment exceeds the 8 MB limit.")
                        }
                        output.write(buffer, 0, read)
                    }
                }
            } ?: throw IllegalArgumentException("Unable to read selected file.")
            result.success(
                mapOf(
                    "path" to destination.absolutePath,
                    "name" to name,
                    "mimeType" to mimeType,
                ),
            )
        } catch (error: Exception) {
            result.error("PICK_FAILED", error.message, null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wakeWordProvider = OpenWakeWordProvider(applicationContext, ::handleWakeProviderEvent)
        bargeInRecognizer = NovaBargeInRecognizer(
            applicationContext,
            onSpeechStarted = {
                runOnUiThread {
                    bargeInChannel?.invokeMethod("bargeInSpeechStarted", null)
                }
            },
            onTranscript = { transcript, isFinal ->
                runOnUiThread {
                    bargeInChannel?.invokeMethod(
                        "bargeInTranscript",
                        mapOf("transcript" to transcript, "isFinal" to isFinal),
                    )
                }
            },
        )

        invocationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        invocationChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundWakeListener" -> {
                    wantsWakeListener = true
                    startWakeProviderWhenReady()
                    result.success(null)
                }
                "stopForegroundWakeListener" -> {
                    wantsWakeListener = false
                    wakeWordProvider.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        attachmentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ATTACHMENT_CHANNEL)
        attachmentChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickNovaDocument" -> launchDocumentPicker(result)
                else -> result.notImplemented()
            }
        }

        bargeInChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BARGE_IN_CHANNEL)
        bargeInChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBargeIn" -> {
                    if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        result.error("PERMISSION_DENIED", "Microphone permission is required.", null)
                    } else {
                        wakeWordProvider.stop()
                        val language = call.argument<String>("languageCode") ?: "en"
                        result.success(bargeInRecognizer.start(language))
                    }
                }
                "stopBargeIn" -> {
                    bargeInRecognizer.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        activityReady = true
        startWakeProviderWhenReady()
    }

    override fun onPause() {
        activityReady = false
        if (::wakeWordProvider.isInitialized) wakeWordProvider.stop()
        if (::bargeInRecognizer.isInitialized) bargeInRecognizer.stop()
        super.onPause()
    }

    override fun onDestroy() {
        wantsWakeListener = false
        if (::wakeWordProvider.isInitialized) wakeWordProvider.release()
        if (::bargeInRecognizer.isInitialized) bargeInRecognizer.release()
        attachmentChannel?.setMethodCallHandler(null)
        bargeInChannel?.setMethodCallHandler(null)
        invocationChannel?.setMethodCallHandler(null)
        attachmentChannel = null
        bargeInChannel = null
        invocationChannel = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != RECORD_AUDIO_REQUEST) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startWakeProviderWhenReady()
        } else {
            wantsWakeListener = false
            emit("wakeProviderUnavailable", mapOf("reason" to "PERMISSION_DENIED"))
        }
    }

    private fun startWakeProviderWhenReady() {
        if (!wantsWakeListener || !activityReady || isFinishing || isDestroyed) return
        if (wakeWordProvider.requiresAudioPermission &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                RECORD_AUDIO_REQUEST,
            )
            return
        }
        wakeWordProvider.start()
    }

    private fun handleWakeProviderEvent(event: WakeProviderEvent) {
        when (event) {
            WakeProviderEvent.Started -> emit("wakeProviderStarted", mapOf("source" to "openwakeword"))
            WakeProviderEvent.Stopped -> emit("wakeProviderStopped", mapOf("source" to "openwakeword"))
            is WakeProviderEvent.Detected -> {
                wantsWakeListener = false
                wakeWordProvider.stop()
                emit(
                    "wakeWordDetected",
                    mapOf(
                        "source" to "wake_word",
                        "phrase" to event.phrase,
                        "score" to event.score,
                    ),
                )
            }
            is WakeProviderEvent.Unavailable -> {
                wantsWakeListener = false
                emit(
                    "wakeProviderUnavailable",
                    mapOf("source" to "openwakeword", "reason" to event.reason),
                )
            }
            is WakeProviderEvent.Error -> emit(
                "wakeProviderError",
                mapOf("source" to "openwakeword", "reason" to event.reason),
            )
        }
    }

    private fun launchDocumentPicker(result: MethodChannel.Result) {
        if (documentPickResult != null) {
            result.error("PICK_IN_PROGRESS", "A document picker is already open.", null)
            return
        }
        documentPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("image/jpeg", "image/png", "image/webp", "text/plain", "application/pdf"),
            )
        }
        startActivityForResult(intent, PICK_DOCUMENT_REQUEST)
    }

    private fun queryDisplayName(uri: android.net.Uri): String? {
        contentResolver.query(uri, null, null, null, null)?.use { cursor: Cursor ->
            val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) return cursor.getString(index)
        }
        return null
    }

    private fun emit(method: String, payload: Map<String, Any>) {
        invocationChannel?.invokeMethod(method, payload)
        Log.d(TAG, "$method $payload")
    }
}
