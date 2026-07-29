package com.adhd.reminders

import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.audio.AudioSource
import com.google.mlkit.genai.speechrecognition.SpeechRecognition
import com.google.mlkit.genai.speechrecognition.SpeechRecognizer
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerResponse
import com.google.mlkit.genai.speechrecognition.speechRecognizerOptions
import com.google.mlkit.genai.speechrecognition.speechRecognizerRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale

/// Bridges ML Kit GenAI Speech Recognition to Flutter.
/// - MethodChannel "speech/methods": start / stop.
/// - EventChannel  "speech/events" : {"type": ..., "text": ...} maps.
///
/// Partial results are collected here and sent as one "transcript" event on stop.
class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var recognizer: SpeechRecognizer? = null
    private var recognitionJob: Job? = null
    private var events: EventChannel.EventSink? = null
    private val segments = mutableListOf<String>()
    private var partial = ""

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "speech/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                }

                override fun onCancel(arguments: Any?) {
                    events = null
                }
            },
        )

        MethodChannel(messenger, "speech/methods").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    start()
                    result.success(null)
                }
                "stop" -> {
                    stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun emit(type: String, text: String) {
        events?.success(mapOf("type" to type, "text" to text))
    }

    private fun start() {
        if (recognitionJob != null) return

        segments.clear()
        partial = ""

        val options = speechRecognizerOptions { locale = Locale.US }
        val client = SpeechRecognition.getClient(options).also { recognizer = it }

        recognitionJob = scope.launch {
            try {
                val status = client.checkStatus()
                emit("status", "feature status: $status")

                if (status == FeatureStatus.DOWNLOADABLE || status == FeatureStatus.DOWNLOADING) {
                    emit("status", "downloading model...")
                    client.download().collect { d ->
                        when (d) {
                            is DownloadStatus.DownloadCompleted -> emit("status", "download completed")
                            is DownloadStatus.DownloadFailed -> emit("error", "download failed: ${d.e}")
                            else -> {}
                        }
                    }
                }

                emit("status", "listening")

                val request = speechRecognizerRequest { audioSource = AudioSource.fromMic() }
                client.startRecognition(request).collect { response ->
                    when (response) {
                        is SpeechRecognizerResponse.PartialTextResponse -> partial = response.text
                        is SpeechRecognizerResponse.FinalTextResponse -> {
                            segments.add(response.text)
                            partial = ""
                        }
                        is SpeechRecognizerResponse.ErrorResponse -> emit("error", "${response.e}")
                        else -> {}
                    }
                }
            } catch (e: Exception) {
                emit("error", "$e")
            }
        }
    }

    private fun stop() {
        val client = recognizer ?: return
        val job = recognitionJob
        recognizer = null
        recognitionJob = null

        scope.launch {
            try {
                client.stopRecognition()
            } catch (_: Exception) {
            }
            withTimeoutOrNull(3000) { job?.join() }
            job?.cancel()
            client.close()

            val text = (segments + partial).filter { it.isNotBlank() }.joinToString(" ")
            emit("transcript", text)
        }
    }

    override fun onDestroy() {
        scope.cancel()
        recognitionJob = null
        recognizer?.close()
        recognizer = null
        super.onDestroy()
    }
}
