package com.chaplyk.memory

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/// Runs the Dart side of an activity transition without the app being open.
///
/// Starts a headless Flutter engine on `activityTransitionMain` (lib/activity_watch.dart),
/// waits for Dart to say it is ready, sends the activity over the "activity/transition"
/// channel and waits for Dart to finish showing the reminders.
class ActivityTransitionWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    companion object {
        const val ACTIVITY = "activity"
        private const val TIMEOUT_MS = 60_000L
    }

    override suspend fun doWork(): Result {
        val activity = inputData.getString(ACTIVITY) ?: return Result.failure()

        // A Flutter engine must be created and used on the main thread.
        return withContext(Dispatchers.Main) {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)

            val engine = FlutterEngine(applicationContext)
            try {
                val done = CompletableDeferred<Boolean>()
                val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "activity/transition")
                channel.setMethodCallHandler { call, result ->
                    if (call.method != "ready") {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                    result.success(null)
                    channel.invokeMethod(
                        "transition",
                        mapOf("activity" to activity),
                        object : MethodChannel.Result {
                            override fun success(value: Any?) {
                                done.complete(true)
                            }

                            override fun error(code: String, message: String?, details: Any?) {
                                done.complete(false)
                            }

                            override fun notImplemented() {
                                done.complete(false)
                            }
                        },
                    )
                }
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        "package:nagadai/activity_watch.dart",
                        "activityTransitionMain",
                    ),
                )
                val ok = withTimeoutOrNull(TIMEOUT_MS) { done.await() } ?: false
                if (ok) Result.success() else Result.failure()
            } finally {
                engine.destroy()
            }
        }
    }
}
