package com.ayahreel.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale

/**
 * The home-screen widget: a verse from the Quran over a photograph
 * from the scene library, turning twice a day.
 *
 * Nothing here talks to Flutter. The verse comes from the widget's own
 * copy of the list and the date (see [VerseSchedule]); the picture is
 * one of the drawables cut for it from the scene library
 * (tool/widget_backgrounds.sh); the font is the same KFGQPC face the
 * app renders with, as a font resource. The launcher draws all of it,
 * so the widget keeps turning on a phone where the app has not been
 * opened in weeks.
 *
 * Turning over: an inexact alarm is set for the next noon or midnight
 * every time the widget is drawn, and the 30-minute
 * `updatePeriodMillis` in the provider info is the safety net if the
 * alarm is dropped. Time, zone and locale changes and a reboot all
 * redraw too — a widget showing yesterday's verse after a flight is
 * the kind of thing nobody reports.
 */
class VerseWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        draw(context, manager, ids)
        scheduleTurn(context)
    }

    override fun onEnabled(context: Context) = scheduleTurn(context)

    /** The user resized this copy: it may need the other layout. */
    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, id: Int, options: Bundle,
    ) = draw(context, manager, intArrayOf(id))

    override fun onDisabled(context: Context) {
        alarmManager(context).cancel(turnIntent(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TURN,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> refreshAll(context)
        }
        super.onReceive(context, intent)
    }

    companion object {
        private const val TAG = "VerseWidget"
        const val ACTION_TURN = "com.ayahreel.app.widget.TURN"

        /** How many pictures tool/widget_backgrounds.sh cut. */
        private const val BACKGROUNDS = 100

        fun component(context: Context) = ComponentName(context, VerseWidget::class.java)

        /** The ids of every placed copy of the widget. */
        fun ids(context: Context): IntArray =
            AppWidgetManager.getInstance(context).getAppWidgetIds(component(context))

        /** Redraws every placed copy and re-arms the next turn. */
        fun refreshAll(context: Context) {
            val ids = ids(context)
            if (ids.isEmpty()) return
            draw(context, AppWidgetManager.getInstance(context), ids)
            scheduleTurn(context)
        }

        /** Under this many dp wide - three cells - the small layout is drawn. */
        private const val SMALL_BELOW_DP = 180

        /** Under this many dp tall - one row - the widget is short. */
        private const val SHORT_BELOW_DP = 100

        private fun draw(context: Context, manager: AppWidgetManager, ids: IntArray) {
            val now = LocalDateTime.now()
            for (id in ids) {
                val views = try {
                    val (small, short) = shape(manager, id)
                    build(context, now, small = small, short = short)
                } catch (e: Exception) {
                    // A widget that fails to draw is a blank slab on the
                    // home screen; the launcher keeps the last good frame
                    // if nothing is pushed.
                    Log.e(TAG, "could not build the widget", e)
                    return
                }
                manager.updateAppWidget(id, views)
            }
        }

        /**
         * Whether copy [id] is narrower than three cells, and whether it
         * is one row tall. The launcher reports the size it gave the
         * widget in its options; no options (an old launcher, a first
         * draw) means the default 4x2.
         */
        private fun shape(manager: AppWidgetManager, id: Int): Pair<Boolean, Boolean> {
            val o = manager.getAppWidgetOptions(id) ?: return false to false
            val w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
            val h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
            val short = h in 1 until SHORT_BELOW_DP
            return (short || w in 1 until SMALL_BELOW_DP) to short
        }

        /**
         * One frame of the widget, for [now]: the small layout when
         * [small], and when [short] - one row - the verse held to two
         * lines and the translation to one, so both still show.
         */
        fun build(
            context: Context, now: LocalDateTime, small: Boolean = false, short: Boolean = false,
        ): RemoteViews {
            val schedule = VerseSchedule.load(context)
            val verse = schedule.verseAt(now)
            val jumuah = schedule.isJumuah(now)
            val arabicUi = Locale.getDefault().language == "ar"
            val bg = context.resources.getIdentifier(
                String.format(Locale.ROOT, "wbg_%02d", schedule.backgroundAt(now, BACKGROUNDS)),
                "drawable", context.packageName,
            )

            val layout = if (small) R.layout.verse_widget_small else R.layout.verse_widget
            return RemoteViews(context.packageName, layout).apply {
                setImageViewResource(R.id.widget_bg, if (bg != 0) bg else R.drawable.wbg_00)
                setTextViewText(
                    R.id.widget_label,
                    context.getString(if (jumuah) R.string.widget_jumuah else R.string.widget_label),
                )
                setTextViewText(R.id.widget_ref, verse.reference(arabicUi))
                setTextViewText(R.id.widget_arabic, verse.shown)
                // The same step-down the card in the app uses, for the
                // phones (Android 7) where the layout's auto-size is
                // ignored; from Android 8 auto-size fits the box itself.
                setTextViewTextSize(
                    R.id.widget_arabic, TypedValue.COMPLEX_UNIT_SP,
                    arabicSizeSp(verse.shown) * (if (small) 0.78f else 1f),
                )
                if (arabicUi) {
                    setViewVisibility(R.id.widget_translation, View.GONE)
                } else {
                    setViewVisibility(R.id.widget_translation, View.VISIBLE)
                    setTextViewText(R.id.widget_translation, verse.translation)
                }
                if (short) {
                    setInt(R.id.widget_arabic, "setMaxLines", 2)
                    setInt(R.id.widget_translation, "setMaxLines", 1)
                }
                setOnClickPendingIntent(R.id.widget_root, openIntent(context, verse))
            }
        }

        /** Matches DayVerseCard.arabicSize in the app. */
        private fun arabicSizeSp(shown: String): Float {
            val words = shown.split(' ').count { it.length > 1 }
            return when {
                words <= 9 -> 18f
                words <= 12 -> 16.5f
                else -> 15f
            }
        }

        /** Opens the app on [verse]'s reel; see HomeWidgetService in Dart. */
        private fun openIntent(context: Context, verse: VerseSchedule.Verse): PendingIntent {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(verse.link))
                .setClass(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun alarmManager(context: Context) =
            context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        private fun turnIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context, 1,
            Intent(context, VerseWidget::class.java).setAction(ACTION_TURN),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        /**
         * Arms one alarm for the next noon or midnight. Inexact, and
         * allowed while idle: no permission needed on any Android, and
         * a minute or two late is nothing on a widget. Re-arming every
         * draw means a dropped alarm costs at most one 30-minute period.
         */
        private fun scheduleTurn(context: Context) {
            if (ids(context).isEmpty()) return
            val now = LocalDateTime.now()
            val at = VerseSchedule.load(context).nextTurn(now)
                .atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
            val am = alarmManager(context)
            val pi = turnIntent(context)
            // A phone at its per-app alarm ceiling throws here (see
            // BootReceiver); the widget then turns at its 30-minute
            // update instead of taking the app down.
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setAndAllowWhileIdle(AlarmManager.RTC, at, pi)
                } else {
                    am.set(AlarmManager.RTC, at, pi)
                }
            } catch (e: RuntimeException) {
                Log.w("AyahReel", "widget turn alarm refused", e)
            }
        }
    }
}
