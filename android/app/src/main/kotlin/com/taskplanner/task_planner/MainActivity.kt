package com.taskplanner.task_planner

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
import java.util.Locale

/// Bridges ML Kit GenAI Speech Recognition (a Kotlin coroutine/Flow API) to Flutter.
/// - MethodChannel "speech/methods": start / stop.
/// - EventChannel  "speech/events" : streams recognized text (and status/errors) to Dart.
class MainActivity : FlutterActivity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var recognizer: SpeechRecognizer? = null
    private var recognitionJob: Job? = null
    private var events: EventChannel.EventSink? = null

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

    private fun emit(message: String) {
        events?.success(message)
    }

    private fun start() {
        if (recognitionJob != null) return

        val options = speechRecognizerOptions { locale = Locale.US }
        val client = SpeechRecognition.getClient(options).also { recognizer = it }

        recognitionJob = scope.launch {
            try {
                val status = client.checkStatus()
                emit("status: $status")

                if (status == FeatureStatus.DOWNLOADABLE || status == FeatureStatus.DOWNLOADING) {
                    emit("downloading model...")
                    client.download().collect { d ->
                        when (d) {
                            is DownloadStatus.DownloadCompleted -> emit("download completed")
                            is DownloadStatus.DownloadFailed -> emit("download failed: ${d.e}")
                            else -> {}
                        }
                    }
                }

                val request = speechRecognizerRequest { audioSource = AudioSource.fromMic() }
                client.startRecognition(request).collect { response ->
                    when (response) {
                        is SpeechRecognizerResponse.PartialTextResponse -> emit(response.text)
                        is SpeechRecognizerResponse.FinalTextResponse -> emit(response.text)
                        is SpeechRecognizerResponse.ErrorResponse -> emit("error: ${response.e}")
                        else -> {}
                    }
                }
            } catch (e: Exception) {
                emit("error: $e")
            }
        }
    }

    private fun stop() {
        val client = recognizer ?: return
        scope.launch {
            try {
                client.stopRecognition()
            } catch (_: Exception) {
            }
            recognitionJob?.cancel()
            recognitionJob = null
            client.close()
            recognizer = null
        }
    }

    override fun onDestroy() {
        scope.cancel()
        recognizer?.close()
        recognizer = null
        super.onDestroy()
    }
}
