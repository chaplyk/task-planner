package com.chaplyk.memory

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionEvent
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Receives activity transitions from Google Play services and hands each one to
/// [ActivityTransitionWorker], which looks up and shows the matching reminders.
/// Also restores the registration after a reboot, which clears it.
class ActivityTransitionReceiver : BroadcastReceiver() {
    companion object {
        // Play services can replay an old transition (e.g. right after registering).
        private const val MAX_AGE_NANOS = 5 * 60 * 1_000_000_000L
    }

    /// Saves whether the user is in a vehicle, for store reminders (lib/store_detection.dart).
    /// Written to the file Flutter's shared_preferences reads, under its "flutter." prefix.
    private fun recordVehicleState(context: Context, events: List<ActivityTransitionEvent>, now: Long) {
        val latest = events.maxByOrNull { it.elapsedRealTimeNanos } ?: return
        val inVehicle = latest.activityType == DetectedActivity.IN_VEHICLE &&
            latest.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER
        val atMillis = System.currentTimeMillis() - (now - latest.elapsedRealTimeNanos) / 1_000_000
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .putString("flutter.vehicle_state", if (inVehicle) "in" else "out")
            .putLong("flutter.vehicle_state_at", atMillis)
            .apply()
        val what = ActivityTransitions.name(latest.activityType) ?: "activity ${latest.activityType}"
        val how = if (latest.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER) "started" else "stopped"
        appendStoreLog(context, "Activity: $how $what → vehicle state \"${if (inVehicle) "in" else "out"}\"")
    }

    /// Same file as lib/store_log.dart (path_provider's application support dir is filesDir).
    private fun appendStoreLog(context: Context, message: String) {
        try {
            val time = SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(Date())
            File(context.filesDir, "store_log.txt").appendText("$time  $message\n")
        } catch (e: Exception) {
            Log.w("ActivityTransition", "Store log write failed", e)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            if (!ActivityTransitions.isEnabled(context)) return
            val pending = goAsync()
            ActivityTransitions.register(context.applicationContext) { pending.finish() }
            return
        }

        val result = ActivityTransitionResult.extractResult(intent) ?: return
        val now = SystemClock.elapsedRealtimeNanos()
        recordVehicleState(context, result.transitionEvents, now)
        val activities = result.transitionEvents
            .filter { it.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER }
            .filter { now - it.elapsedRealTimeNanos <= MAX_AGE_NANOS }
            .mapNotNull { ActivityTransitions.name(it.activityType) }
            .distinct()

        for (activity in activities) {
            val work = OneTimeWorkRequestBuilder<ActivityTransitionWorker>()
                .setInputData(workDataOf(ActivityTransitionWorker.ACTIVITY to activity))
                // The reminders are looked up in Firestore.
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueue(work)
        }
    }
}
