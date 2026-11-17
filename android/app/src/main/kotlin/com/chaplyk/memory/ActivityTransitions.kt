package com.chaplyk.memory

import android.Manifest
import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity

/// Registers for "the user started driving / cycling / running / walking" events.
///
/// Google Play services delivers them to [ActivityTransitionReceiver] through a
/// PendingIntent, so nothing of the app has to keep running in between.
object ActivityTransitions {
    private const val PREFS = "activity_transitions"
    private const val ENABLED = "enabled"
    const val ACTION = "com.chaplyk.memory.ACTIVITY_TRANSITION"

    // Names match the `activity` field of a reminder.
    private val names = mapOf(
        DetectedActivity.IN_VEHICLE to "IN_VEHICLE",
        DetectedActivity.ON_BICYCLE to "ON_BICYCLE",
        DetectedActivity.RUNNING to "RUNNING",
        DetectedActivity.WALKING to "WALKING",
    )

    fun name(activityType: Int): String? = names[activityType]

    /// Whether the app asked for transitions, so they can be restored after a reboot.
    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(ENABLED, false)

    private fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(ENABLED, enabled).apply()
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, ActivityTransitionReceiver::class.java).setAction(ACTION)
        // Mutable: Play services adds the transition result to the intent.
        val mutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or mutable)
    }

    private fun hasPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED

    /// Calls [onDone] with null on success, or the reason it failed.
    @SuppressLint("MissingPermission")
    fun register(context: Context, onDone: (Exception?) -> Unit = {}) {
        if (!hasPermission(context)) {
            onDone(SecurityException("Activity recognition permission is not granted"))
            return
        }
        val transitions = names.keys.map {
            ActivityTransition.Builder()
                .setActivityType(it)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build()
        }
        ActivityRecognition.getClient(context)
            .requestActivityTransitionUpdates(ActivityTransitionRequest(transitions), pendingIntent(context))
            .addOnSuccessListener {
                setEnabled(context, true)
                onDone(null)
            }
            .addOnFailureListener { onDone(it) }
    }

    @SuppressLint("MissingPermission")
    fun unregister(context: Context, onDone: () -> Unit = {}) {
        setEnabled(context, false)
        if (!hasPermission(context)) {
            onDone()
            return
        }
        ActivityRecognition.getClient(context)
            .removeActivityTransitionUpdates(pendingIntent(context))
            .addOnCompleteListener { onDone() }
    }
}
