package ru.pdd.pdd_app

import android.app.PendingIntent
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
        views.setTextViewText(R.id.streak_best, "🏆 $best")
        views.setTextViewText(R.id.streak_label, label("currentLabel", R.string.currentLabel))
        views.setTextViewText(R.id.streak_best_label, label("bestLabel", R.string.bestLabel))
        views.setTextViewText(R.id.streak_status, when {
            done -> label("doneLabel", R.string.doneLabel)
            current > 0 -> label("continueLabel", R.string.continueLabel)
            else -> label("startLabel", R.string.startLabel)
        })
        views.setViewVisibility(R.id.streak_status, if (wide || tall) View.VISIBLE else View.GONE)
        views.setFloat(R.id.streak_flame, "setAlpha", if (current > 0) 1f else 0.4f)
        if (style == StreakWidgetStyle.RECORD) {
            views.setProgressBar(R.id.streak_progress, 100, state.progressPercent, false)
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
