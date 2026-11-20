package ru.pdd.pdd_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

internal object StreakWidgetRenderer {
    private const val WEEK_WIDTH = 250
    private const val TALL_HEIGHT = 124

    fun render(
        context: Context,
        state: StreakWidgetState,
        data: JSONObject,
        wide: Boolean,
        now: Calendar = Calendar.getInstance(),
        singleRow: Boolean = false,
    ): RemoteViews {
        val layout = when {
            singleRow -> R.layout.streak_widget_row
            wide -> R.layout.streak_widget_wide
            else -> R.layout.streak_widget
        }
        val views = RemoteViews(context.packageName, layout)
        views.setTextViewText(R.id.streak_current, state.current.toString())
        views.setTextViewText(R.id.streak_best, state.best.toString())
        views.setFloat(R.id.streak_flame, "setAlpha", if (state.done) 1f else 0.66f)
        if (singleRow) {
            views.setViewVisibility(R.id.streak_week, if (wide) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.streak_status_icon, if (wide) View.GONE else View.VISIBLE)
        }
        if (!wide) {
            views.setImageViewResource(R.id.streak_status_icon,
                if (state.done) R.drawable.streak_widget_check else R.drawable.streak_widget_clock)
        }
        fun label(key: String, fallback: Int) =
            data.optString(key).takeIf { it.isNotBlank() } ?: context.getString(fallback)
        val status = when {
            state.done -> label("doneLabel", R.string.doneLabel)
            state.current > 0 -> label("continueLabel", R.string.continueLabel)
            else -> label("startLabel", R.string.startLabel)
        }
        val description = mutableListOf(
            "${label("currentLabel", R.string.currentLabel)}: ${state.current}",
            "${label("bestLabel", R.string.bestLabel)}: ${state.best}",
            status,
        )
        if (wide) {
            val locale = data.optString("locale").takeIf { it.isNotBlank() }?.let(Locale::forLanguageTag)
                ?: context.resources.configuration.locales[0]
            val dates = data.optJSONArray("activeDates")
            val active = buildSet {
                if (dates != null) {
                    for (i in 0 until dates.length()) add(dates.optString(i))
                } else {
                    // Pre-upgrade snapshots have only the last known day of activity.
                    add(data.optString("lastActiveDate"))
                }
            }
            val dateKey = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply { timeZone = now.timeZone }
            val weekday = SimpleDateFormat("EEE", locale).apply { timeZone = now.timeZone }
            val fullDay = SimpleDateFormat("d MMMM", locale).apply { timeZone = now.timeZone }
            val cursor = (now.clone() as Calendar).apply { add(Calendar.DATE, -6) }
            views.removeAllViews(R.id.streak_week)
            val dayLayout = if (singleRow) R.layout.streak_day_row else R.layout.streak_day
            repeat(7) { index ->
                val day = RemoteViews(context.packageName, dayLayout)
                val studied = dateKey.format(cursor.time) in active
                day.setTextViewText(R.id.streak_day_label, weekday.format(cursor.time).trimEnd('.'))
                day.setImageViewResource(R.id.streak_day_icon,
                    if (studied) R.drawable.streak_widget_flame else R.drawable.streak_widget_day_empty)
                day.setViewVisibility(R.id.streak_day_today, if (index == 6) View.VISIBLE else View.INVISIBLE)
                views.addView(R.id.streak_week, day)
                if (studied) description.add(fullDay.format(cursor.time))
                cursor.add(Calendar.DATE, 1)
            }
        }
        views.setContentDescription(R.id.streak_root, description.joinToString(", "))
        val launch = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        }
        views.setOnClickPendingIntent(R.id.streak_root, PendingIntent.getActivity(context, 0, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        return views
    }

    fun responsive(
        context: Context,
        state: StreakWidgetState,
        data: JSONObject,
        options: Bundle,
        now: Calendar = Calendar.getInstance(),
    ): RemoteViews {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return RemoteViews(mapOf(
                SizeF(130f, 40f) to render(context, state, data, false, now, singleRow = true),
                SizeF(WEEK_WIDTH.toFloat(), 40f) to render(context, state, data, true, now, singleRow = true),
                SizeF(130f, TALL_HEIGHT.toFloat()) to render(context, state, data, false, now),
                SizeF(WEEK_WIDTH.toFloat(), TALL_HEIGHT.toFloat()) to render(context, state, data, true, now),
            ))
        }
        // On older launchers minWidth/maxHeight describe portrait, maxWidth/minHeight landscape.
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 130)
        val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, minWidth)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 130)
        val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, minHeight)
        return RemoteViews(
            render(context, state, data, maxWidth >= WEEK_WIDTH, now, singleRow = minHeight < TALL_HEIGHT),
            render(context, state, data, minWidth >= WEEK_WIDTH, now, singleRow = maxHeight < TALL_HEIGHT),
        )
    }
}
