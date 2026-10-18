package com.ayahreel.app

import android.content.Context
import android.content.Intent
import android.util.Log
import com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver

/**
 * The notification plugin's boot receiver, with its failures kept inside.
 *
 * At boot and after an update it re-arms every saved reminder, and the
 * first one the phone refuses throws out of onReceive and crashes the
 * app in the background. Play, 1.0.8: Infinix HOT 50i (Android 14),
 * an IllegalStateException from AlarmManager.setAndAllowWhileIdle,
 * the per-app alarm ceiling. On 1.0.2–1.0.4 it was Gson's "Missing type
 * parameter". Reminders it couldn't re-arm are laid again at the next
 * launch (ReminderService in Dart).
 *
 * The work runs on [Reminders.worker], off the main thread, with the
 * broadcast held open by goAsync: at boot it parses the whole list and
 * lays every alarm, in a process that just started.
 */
class BootReceiver : ScheduledNotificationBootReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        Reminders.worker.execute {
            try {
                super.onReceive(context, intent)
            } catch (e: RuntimeException) {
                Log.w("AyahReel", "reminders not all re-armed after ${intent.action}", e)
            } finally {
                pending.finish()
            }
        }
    }
}
