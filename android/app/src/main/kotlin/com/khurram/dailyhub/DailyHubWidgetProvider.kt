package com.khurram.dailyhub

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews

/**
 * Home-screen widget showing today's agenda.
 *
 * It deliberately has no Flutter dependency: the app writes everything it needs
 * into the SharedPreferences file that shared_preferences already uses, and
 * this provider just reads it. That means the widget draws instantly on boot,
 * with no Flutter engine to start and no plugin in the build.
 */
class DailyHubWidgetProvider : AppWidgetProvider() {

    companion object {
        /** shared_preferences writes into this file and prefixes every key. */
        private const val PREFS = "FlutterSharedPreferences"
        private const val PREFIX = "flutter."

        const val ACTION_REFRESH = "com.khurram.dailyhub.WIDGET_REFRESH"

        /** Redraws every instance of the widget. Safe when none are placed. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, DailyHubWidgetProvider::class.java)
            )
            if (ids.isEmpty()) return
            val provider = DailyHubWidgetProvider()
            provider.onUpdate(context, manager, ids)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            manager.updateAppWidget(id, buildViews(context))
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            refreshAll(context)
        }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Reads a string the Flutter side stored, tolerating the missing prefix. */
    private fun str(p: SharedPreferences, key: String, fallback: String = ""): String =
        try {
            p.getString(PREFIX + key, null) ?: p.getString(key, null) ?: fallback
        } catch (_: Exception) {
            fallback
        }

    /** Agenda lines are stored as one string: entries split on U+0002. */
    private fun agendaItems(p: SharedPreferences): List<String> {
        val raw = str(p, "widget_items")
        if (raw.isEmpty()) return emptyList()
        return raw.split('\u0002').filter { it.isNotEmpty() }
    }

    private fun buildViews(context: Context): RemoteViews {
        val p = prefs(context)
        val views = RemoteViews(context.packageName, R.layout.widget_daily)

        views.setTextViewText(R.id.widget_title, str(p, "widget_date", "Today"))

        val open = str(p, "widget_open", "0")
        val done = str(p, "widget_done", "0")
        val leftLabel = str(p, "widget_l_left", "left")
        val doneLabel = str(p, "widget_l_done", "done")
        views.setTextViewText(R.id.widget_counts, "$open $leftLabel · $done $doneLabel")

        val items = agendaItems(p)
        val rows = intArrayOf(R.id.widget_row_1, R.id.widget_row_2, R.id.widget_row_3)
        val times = intArrayOf(R.id.widget_time_1, R.id.widget_time_2, R.id.widget_time_3)
        val texts = intArrayOf(R.id.widget_text_1, R.id.widget_text_2, R.id.widget_text_3)

        for (i in rows.indices) {
            val item = items.getOrNull(i)
            if (item == null) {
                views.setViewVisibility(rows[i], View.GONE)
                continue
            }
            // Each entry is "HH:mm\u0001title"; the time may be blank for all-day items.
            val parts = item.split("\u0001", limit = 2)
            val time = parts.getOrNull(0).orEmpty()
            val title = parts.getOrNull(1).orEmpty().ifEmpty { item }
            views.setViewVisibility(rows[i], View.VISIBLE)
            views.setTextViewText(times[i], time)
            views.setViewVisibility(times[i], if (time.isEmpty()) View.GONE else View.VISIBLE)
            views.setTextViewText(texts[i], title)
        }

        views.setViewVisibility(
            R.id.widget_empty,
            if (items.isEmpty()) View.VISIBLE else View.GONE
        )
        views.setTextViewText(R.id.widget_empty, str(p, "widget_l_empty", "Nothing due today"))

        val money = str(p, "widget_money")
        val habits = str(p, "widget_habits")
        val footer = buildString {
            if (money.isNotEmpty()) append("${str(p, "widget_l_spent", "Spent")} $money")
            if (habits.isNotEmpty()) {
                if (isNotEmpty()) append("   ")
                append("${str(p, "widget_l_habits", "Habits")} $habits")
            }
        }
        views.setTextViewText(R.id.widget_footer, footer)
        views.setViewVisibility(R.id.widget_footer, if (footer.isEmpty()) View.GONE else View.VISIBLE)

        views.setOnClickPendingIntent(R.id.widget_root, launchIntent(context, null))
        views.setOnClickPendingIntent(R.id.widget_add, launchIntent(context, "add"))
        return views
    }

    /** Opens the app, optionally asking it to jump somewhere. */
    private fun launchIntent(context: Context, route: String?): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (route != null) intent.putExtra("dailyhub_route", route)
        // A distinct request code per route, or Android reuses the first intent.
        val code = if (route == null) 0 else 1
        return PendingIntent.getActivity(
            context,
            code,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
