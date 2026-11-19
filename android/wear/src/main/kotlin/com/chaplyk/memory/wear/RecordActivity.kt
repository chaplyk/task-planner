package com.chaplyk.memory.wear

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.HapticFeedbackConstants
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

/// Records a reminder (mic only, no keyboard), sends what was said to the phone and shows
/// what the phone saved. From the Tile it listens right away ([EXTRA_AUTOSTART]); opened
/// from the app list it waits for a tap on the mic.
///
/// The text goes out as a data item, which Wear OS keeps and delivers when the phone is
/// back in range, so nothing is lost when the phone is away.
class RecordActivity : ComponentActivity() {
    companion object {
        /// Set by the Tile: start listening as soon as the screen opens.
        const val EXTRA_AUTOSTART = "autostart"

        // The phone parses the text with an AI model, which can take a while.
        const val ACK_TIMEOUT_MS = 25_000L
        const val CLOSE_AFTER_MS = 3_000L
        val ACCENT = Color(0xFF4F6BED)
        val DIM = Color(0xFFB0B0B8)
    }

    private sealed interface Screen {
        data object Idle : Screen
        data class Listening(val partial: String) : Screen
        data class Sending(val text: String) : Screen
        data class Saved(val title: String, val time: String?) : Screen
        data class Queued(val text: String, val message: String) : Screen
        data class Failed(val message: String) : Screen
    }

    private var screen by mutableStateOf<Screen>(Screen.Idle)
    /// Loudness of the voice, 0..1, for the pulsing mic.
    private var level by mutableFloatStateOf(0f)
    private var recognizer: SpeechRecognizer? = null
    private var sendJob: Job? = null

    private val micPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) listen() else screen = Screen.Failed("Allow the microphone to record reminders")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { Content() } }
        if (intent.autostart) listen()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Tapped the Tile again while a result was showing: record another one.
        if (intent.autostart && screen !is Screen.Sending) listen()
    }

    private val Intent?.autostart: Boolean get() = this?.getBooleanExtra(EXTRA_AUTOSTART, false) == true

    override fun onStop() {
        super.onStop()
        // Left mid-sentence (e.g. palm over the screen): don't keep the mic open.
        if (screen is Screen.Listening) {
            recognizer?.cancel()
            finish()
        }
    }

    override fun onDestroy() {
        recognizer?.destroy()
        recognizer = null
        super.onDestroy()
    }

    private fun listen() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            micPermission.launch(Manifest.permission.RECORD_AUDIO)
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            screen = Screen.Failed("Speech recognition isn't available on this watch")
            return
        }
        screen = Screen.Listening("")
        level = 0f
        val r = recognizer ?: SpeechRecognizer.createSpeechRecognizer(this).also {
            it.setRecognitionListener(listener)
            recognizer = it
        }
        r.cancel()
        r.startListening(
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                .putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName),
        )
    }

    /// Tap on the mic while listening: done talking.
    private fun stopListening() {
        recognizer?.stopListening()
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {
            level = 0f
        }
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onRmsChanged(rmsdB: Float) {
            // Roughly -2 (silence) to 10 (loud speech).
            level = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f)
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = partialResults.firstResult() ?: return
            if (screen is Screen.Listening) screen = Screen.Listening(text)
        }

        override fun onResults(results: Bundle?) {
            val text = results.firstResult()
                ?: (screen as? Screen.Listening)?.partial?.takeIf { it.isNotBlank() }
            if (text.isNullOrBlank()) screen = Screen.Failed("Didn't catch that") else send(text.trim())
        }

        override fun onError(error: Int) {
            if (screen !is Screen.Listening) return
            // Stopped early with words already heard: use them.
            val partial = (screen as Screen.Listening).partial
            if (partial.isNotBlank() && error != SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                send(partial.trim())
                return
            }
            screen = Screen.Failed(
                when (error) {
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Didn't catch that"
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
                    SpeechRecognizer.ERROR_SERVER, SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "No connection for speech"
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Allow the microphone to record reminders"
                    else -> "Speech failed. Try again"
                },
            )
        }

        private fun Bundle?.firstResult(): String? =
            this?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.takeIf { it.isNotBlank() }
    }

    private fun send(text: String) {
        screen = Screen.Sending(text)
        sendJob?.cancel()
        sendJob = lifecycleScope.launch {
            val path = WatchLink.PATH_PREFIX + System.currentTimeMillis()
            val ack = CompletableDeferred<WatchLink.Ack>()
            val ackListener = MessageClient.OnMessageReceivedListener { event ->
                if (event.path != WatchLink.ACK_PATH) return@OnMessageReceivedListener
                val parsed = WatchLink.Ack.parse(event.data)
                if (parsed?.id == path) ack.complete(parsed)
            }
            val messages = Wearable.getMessageClient(this@RecordActivity)
            try {
                messages.addListener(ackListener).await()
                val request = PutDataMapRequest.create(path).apply {
                    dataMap.putString("text", text)
                    dataMap.putLong("ts", System.currentTimeMillis())
                }.asPutDataRequest().setUrgent()
                Wearable.getDataClient(this@RecordActivity).putDataItem(request).await()

                val phoneNearby = try {
                    Wearable.getNodeClient(this@RecordActivity).connectedNodes.await().isNotEmpty()
                } catch (e: Exception) {
                    false
                }
                if (!phoneNearby) {
                    screen = Screen.Queued(text, "Will save when your phone is nearby")
                    closeSoon()
                    return@launch
                }

                val answer = withTimeoutOrNull(ACK_TIMEOUT_MS) { ack.await() }
                screen = when {
                    answer == null -> Screen.Queued(text, "Sent. Your phone is still saving it")
                    answer.ok -> Screen.Saved(answer.title, answer.time)
                    else -> Screen.Failed(answer.errorMessage)
                }
                if (answer?.ok != false) closeSoon()
            } catch (e: Exception) {
                screen = Screen.Failed("Couldn't send it to your phone")
            } finally {
                messages.removeListener(ackListener)
            }
        }
    }

    private suspend fun closeSoon() {
        delay(CLOSE_AFTER_MS)
        finish()
    }

    @Composable
    private fun Content() {
        val view = LocalView.current
        Box(
            modifier = Modifier.fillMaxSize().padding(horizontal = 22.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                when (val s = screen) {
                    Screen.Idle -> {
                        Text("New reminder", fontSize = 15.sp)
                        Spacer(Modifier.height(12.dp))
                        Mic(listening = false, onClick = ::listen)
                        Spacer(Modifier.height(10.dp))
                        Text("Tap and speak", fontSize = 13.sp, color = DIM)
                    }
                    is Screen.Listening -> {
                        Text(if (s.partial.isEmpty()) "Listening…" else "Tap when done", fontSize = 13.sp, color = DIM)
                        Spacer(Modifier.height(10.dp))
                        Mic(listening = true, onClick = ::stopListening)
                        Spacer(Modifier.height(10.dp))
                        Text(
                            s.partial,
                            textAlign = TextAlign.Center,
                            fontSize = 14.sp,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    is Screen.Sending -> {
                        CircularProgressIndicator(indicatorColor = ACCENT, modifier = Modifier.size(28.dp))
                        Spacer(Modifier.height(10.dp))
                        Quote(s.text)
                    }
                    is Screen.Saved -> {
                        LaunchedEffect(s) { view.performHapticFeedback(HapticFeedbackConstants.CONFIRM) }
                        Text("✓ Saved", color = ACCENT, fontSize = 14.sp)
                        Spacer(Modifier.height(6.dp))
                        Text(s.title, textAlign = TextAlign.Center, fontSize = 16.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                        s.time?.let {
                            Spacer(Modifier.height(4.dp))
                            Text(it, textAlign = TextAlign.Center, fontSize = 13.sp, color = DIM)
                        }
                    }
                    is Screen.Queued -> {
                        Quote(s.text)
                        Spacer(Modifier.height(8.dp))
                        Text(s.message, textAlign = TextAlign.Center, fontSize = 13.sp, color = DIM)
                    }
                    is Screen.Failed -> {
                        LaunchedEffect(s) { view.performHapticFeedback(HapticFeedbackConstants.REJECT) }
                        Text(s.message, textAlign = TextAlign.Center, fontSize = 14.sp)
                        Spacer(Modifier.height(12.dp))
                        Mic(listening = false, onClick = ::listen)
                    }
                }
            }
        }
    }

    /// Round mic button; while listening it pulses and grows with the voice.
    @Composable
    private fun Mic(listening: Boolean, onClick: () -> Unit) {
        val pulse = if (listening) {
            rememberInfiniteTransition(label = "pulse").animateFloat(
                initialValue = 1f,
                targetValue = 1.08f,
                animationSpec = infiniteRepeatable(tween(700), RepeatMode.Reverse),
                label = "pulse",
            ).value
        } else {
            1f
        }
        val size = if (listening) 72.dp else 56.dp
        Box(
            modifier = Modifier
                .size(size)
                .scale(pulse + level * 0.25f)
                .background(ACCENT, CircleShape)
                .clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                painterResource(R.drawable.ic_mic),
                contentDescription = if (listening) "Done talking" else "Record a reminder",
                modifier = Modifier.size(size / 2),
            )
        }
    }

    @Composable
    private fun Quote(text: String) {
        Text(
            "“$text”",
            textAlign = TextAlign.Center,
            fontSize = 14.sp,
            maxLines = 4,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
