package com.ayahreel.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.CoreComponentFactory
import com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Builds the app's components, and swaps the notification plugin's
 * alarm receiver for [OffMainReminderReceiver].
 *
 * The plugin's alarms name its receiver class outright, so only this
 * factory (Android 9 and up) can put another class behind them; below 9
 * the plugin's own receiver runs as before.
 */
@RequiresApi(Build.VERSION_CODES.P)
class AppComponents : CoreComponentFactory() {
    override fun instantiateReceiver(
        cl: ClassLoader,
        className: String,
        intent: Intent?,
    ): BroadcastReceiver {
        if (className == ScheduledNotificationReceiver::class.java.name) {
            return OffMainReminderReceiver()
        }
        return super.instantiateReceiver(cl, className, intent)
    }
}

/**
 * The plugin's alarm receiver, with its work moved off the main thread.
 *
 * For each reminder it shows, the plugin parses its whole saved list
 * with Gson, rewrites it and lays the next alarm, all on the main
 * thread, often in a process just started for the alarm. Play, 1.0.8:
 * "Broadcast of Intent ScheduledNotificationReceiver" ANRs (iotapk
 * BLK-L09, realme C63; Android 16). Here the broadcast is held open
 * with goAsync and the same work runs on [Reminders.worker].
 */
class OffMainReminderReceiver : ScheduledNotificationReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Reminders.worker.execute {
            try {
                super.onReceive(context, intent)
            } catch (e: RuntimeException) {
                Log.w("AyahReel", "reminder not shown", e)
            } finally {
                pending.finish()
            }
        }
    }
}

object Reminders {
    /**
     * One thread for the plugin's work outside the app: each job reads
     * and rewrites the plugin's saved list, so two at once would lose
     * one's change.
     */
    val worker: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "reminders")
    }
}
