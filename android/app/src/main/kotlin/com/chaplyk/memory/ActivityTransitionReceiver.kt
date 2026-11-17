package com.chaplyk.memory

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import androidx.work.Constraints
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult

/// Receives activity transitions from Google Play services and hands each one to
/// [ActivityTransitionWorker], which looks up and shows the matching reminders.
/// Also restores the registration after a reboot, which clears it.
class ActivityTransitionReceiver : BroadcastReceiver() {
    companion object {
        // Play services can replay an old transition (e.g. right after registering).
        private const val MAX_AGE_NANOS = 5 * 60 * 1_000_000_000L
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
