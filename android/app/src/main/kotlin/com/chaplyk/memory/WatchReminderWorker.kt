package com.chaplyk.memory

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

/// Saves a reminder spoken on the watch without the app being open.
///
/// Starts a headless Flutter engine on `watchReminderMain` (lib/watch_reminder.dart), waits
/// for Dart to say it is ready, sends the text over the "watch/reminder" channel and gets
/// back what was saved. Then removes the watch's data item and tells the watch the result.
class WatchReminderWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    companion object {
        const val TEXT = "text"
        const val URI = "uri"
        const val NODE = "node"
        private const val TAG = "WatchReminderWorker"
        private const val TIMEOUT_MS = 90_000L
        private const val MAX_ATTEMPTS = 4
    }

    private sealed interface Outcome {
        data class Saved(val reply: Map<*, *>) : Outcome
        data class Failed(val code: String, val retry: Boolean) : Outcome
    }

    override suspend fun doWork(): Result {
        val text = inputData.getString(TEXT) ?: return Result.failure()
        val uri = inputData.getString(URI)?.let(Uri::parse) ?: return Result.failure()
        val node = inputData.getString(NODE)

        val outcome = withTimeoutOrNull(TIMEOUT_MS) { runDart(text) } ?: Outcome.Failed("timeout", retry = true)
        Log.i(TAG, "Watch reminder: $outcome (attempt ${runAttemptCount + 1})")

        if (outcome is Outcome.Failed && outcome.retry && runAttemptCount + 1 < MAX_ATTEMPTS) {
            return Result.retry()
        }

        val ack = JSONObject().put("id", uri.path)
        when (outcome) {
            is Outcome.Saved -> {
                ack.put("ok", true)
                for (key in listOf("summary", "emoji", "when")) {
                    (outcome.reply[key] as? String)?.let { ack.put(key, it) }
                }
            }
            is Outcome.Failed -> ack.put("ok", false).put("error", outcome.code)
        }
        withContext(Dispatchers.IO) {
            try {
                // Done with it, saved or given up on: stop the watch from sending it again.
                Tasks.await(Wearable.getDataClient(applicationContext).deleteDataItems(uri))
                if (node != null) {
                    Tasks.await(
                        Wearable.getMessageClient(applicationContext)
                            .sendMessage(node, WatchListenerService.ACK_PATH, ack.toString().toByteArray()),
                    )
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not answer the watch", e)
            }
        }
        return if (outcome is Outcome.Saved) Result.success() else Result.failure()
    }

    // A Flutter engine must be created and used on the main thread.
    private suspend fun runDart(text: String): Outcome = withContext(Dispatchers.Main) {
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val engine = FlutterEngine(applicationContext)
        try {
            val done = CompletableDeferred<Outcome>()
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "watch/reminder")
            channel.setMethodCallHandler { call, result ->
                if (call.method != "ready") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                result.success(null)
                channel.invokeMethod(
                    "reminder",
                    mapOf("text" to text),
                    object : MethodChannel.Result {
                        override fun success(value: Any?) {
                            done.complete(Outcome.Saved(value as? Map<*, *> ?: emptyMap<String, String>()))
                        }

                        override fun error(code: String, message: String?, details: Any?) {
                            // Signed out or nothing said: trying again won't help.
                            done.complete(Outcome.Failed(code, retry = code != "signed_out" && code != "empty"))
                        }

                        override fun notImplemented() {
                            done.complete(Outcome.Failed("not_implemented", retry = false))
                        }
                    },
                )
            }
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "package:nagadai/watch_reminder.dart",
                    "watchReminderMain",
                ),
            )
            done.await()
        } finally {
            engine.destroy()
        }
    }
}
