package ru.pdd.pdd_app

import android.app.PendingIntent
import android.content.res.ColorStateList
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/** Shared by the real providers and on-device inflation/reapply regression tests. */
internal object StreakWidgetRenderer {
    fun render(
        context: Context,
        style: StreakWidgetStyle,
        state: StreakWidgetState,
        data: JSONObject,
        wide: Boolean,
        tall: Boolean,
    ): RemoteViews {
        val (current, best, done) = state
        fun label(key: String, fallback: Int) =
            data.optString(key).takeIf { it.isNotBlank() } ?: context.getString(fallback)
        val views = RemoteViews(context.packageName, style.layout(wide))
        views.setTextViewText(R.id.streak_current, current.toString())
        views.setTextViewText(R.id.streak_best, best.toString())
        views.setTextViewText(R.id.streak_label, label("currentLabel", R.string.currentLabel))
        views.setTextViewText(R.id.streak_best_label, label("bestLabel", R.string.bestLabel))
        views.setTextViewText(R.id.streak_status, when {
            done -> label("doneLabel", R.string.doneLabel)
            current > 0 -> label("continueLabel", R.string.continueLabel)
            else -> label("startLabel", R.string.startLabel)
        })
        // Also reset visibility when the launcher reapplies an older compact view.
        views.setViewVisibility(R.id.streak_status, View.VISIBLE)
        views.setFloat(R.id.streak_flame, "setAlpha", if (current > 0) 1f else 0.4f)
        val palette = StreakWidgetPalette.from(context, style, done)
        views.setInt(R.id.streak_root, "setBackgroundResource", palette.background)
        for (id in listOf(R.id.streak_current, R.id.streak_best)) views.setTextColor(id, palette.primary)
        for (id in listOf(R.id.streak_label, R.id.streak_best_label)) views.setTextColor(id, palette.secondary)
        views.setTextColor(R.id.streak_status, palette.accent)
        views.setInt(R.id.streak_flame, "setColorFilter", palette.icon)
        views.setInt(R.id.streak_trophy, "setColorFilter", palette.icon)
        if (style == StreakWidgetStyle.MINIMAL && !wide) {
            views.setInt(R.id.streak_divider, "setBackgroundColor", palette.divider)
        }
        if (style == StreakWidgetStyle.RECORD) {
            views.setProgressBar(R.id.streak_progress, 100, state.progressPercent, false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                views.setColorStateList(R.id.streak_progress, "setProgressTintList", ColorStateList.valueOf(palette.accent))
                views.setColorStateList(R.id.streak_progress, "setProgressBackgroundTintList", ColorStateList.valueOf(palette.track))
            }
            views.setContentDescription(R.id.streak_progress,
                "${label("currentLabel", R.string.currentLabel)}: $current; ${label("bestLabel", R.string.bestLabel)}: $best")
        }
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
        style: StreakWidgetStyle,
        state: StreakWidgetState,
        data: JSONObject,
        minWidth: Int,
        minHeight: Int,
    ): RemoteViews {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return RemoteViews(mapOf(
                SizeF(130f, 130f) to render(context, style, state, data, false, false),
                SizeF(130f, 190f) to render(context, style, state, data, false, true),
                SizeF(250f, 130f) to render(context, style, state, data, true, false),
                SizeF(250f, 190f) to render(context, style, state, data, true, true),
            ))
        }
        return render(context, style, state, data, minWidth >= 250, minHeight >= 190)
    }
}

internal data class StreakWidgetPalette(
    val background: Int,
    val primary: Int,
    val secondary: Int,
    val accent: Int,
    val icon: Int,
    val divider: Int,
    val track: Int,
) {
    companion object {
        fun from(context: Context, style: StreakWidgetStyle, done: Boolean): StreakWidgetPalette {
            fun color(id: Int) = context.getColor(id)
            if (done) return StreakWidgetPalette(
                R.drawable.streak_widget_active_background,
                color(R.color.streak_widget_active_text),
                color(R.color.streak_widget_active_secondary),
                color(R.color.streak_widget_active_text),
                color(R.color.streak_widget_active_icon),
                color(R.color.streak_widget_active_divider),
                color(R.color.streak_widget_active_divider),
            )
            val record = style == StreakWidgetStyle.RECORD
            val accent = color(if (record) R.color.streak_record_accent else R.color.streak_widget_accent)
            return StreakWidgetPalette(
                when (style) {
                    StreakWidgetStyle.FLAME -> R.drawable.streak_widget_background
                    StreakWidgetStyle.MINIMAL -> R.drawable.streak_widget_minimal_background
                    StreakWidgetStyle.RECORD -> R.drawable.streak_widget_record_background
                },
                color(if (record) R.color.streak_record_text else R.color.streak_widget_text),
                color(if (record) R.color.streak_record_secondary else R.color.streak_widget_secondary),
                accent, accent, color(R.color.streak_widget_border), color(R.color.streak_record_track),
            )
        }
    }
}
