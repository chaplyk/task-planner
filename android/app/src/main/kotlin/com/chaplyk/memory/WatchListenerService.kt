package com.chaplyk.memory

import androidx.work.BackoffPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import java.util.concurrent.TimeUnit

/// Receives what the user said on the watch (one data item per reminder, see the wear
/// module's RecordActivity) and hands it to [WatchReminderWorker]. Runs with the app closed.
class WatchListenerService : WearableListenerService() {
    companion object {
        const val PATH_PREFIX = "/watch-reminder/"
        const val ACK_PATH = "/watch-reminder/ack"
    }

    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val item = event.dataItem
            val uri = item.uri
            if (uri.path?.startsWith(PATH_PREFIX) != true) continue
            val text = DataMapItem.fromDataItem(item).dataMap.getString("text") ?: continue
            val work = OneTimeWorkRequestBuilder<WatchReminderWorker>()
                .setInputData(
                    workDataOf(
                        WatchReminderWorker.TEXT to text,
                        WatchReminderWorker.URI to uri.toString(),
                        WatchReminderWorker.NODE to uri.host,
                    ),
                )
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            // The same item can be delivered again (e.g. after a reconnect): save it once.
            WorkManager.getInstance(applicationContext)
                .enqueueUniqueWork("watch-reminder:$uri", ExistingWorkPolicy.KEEP, work)
        }
    }
}
