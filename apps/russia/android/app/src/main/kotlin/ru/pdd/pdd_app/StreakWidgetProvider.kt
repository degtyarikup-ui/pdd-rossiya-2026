package ru.pdd.pdd_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Build
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.Calendar

// Keep the original provider identity so already placed widgets survive updates.
open class StreakWidgetProvider : AppWidgetProvider() {
    private val style: StreakWidgetStyle
        get() = StreakWidgetStyle.entries.first { it.providerClass == javaClass }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it, style) }
        scheduleMidnight(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id, style)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in setOf(MIDNIGHT, Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED)) {
            refreshAll(context)
        }
    }

    override fun onDisabled(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        // Removing one design must not stop midnight updates for the others.
        if (StreakWidgetStyle.entries.none { ids(context, manager, it).isNotEmpty() }) {
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(midnightIntent(context))
        }
    }

    companion object {
        private const val PREFS = "streak_home_widget"
        private const val MIDNIGHT = "ru.pdd.pdd_app.STREAK_MIDNIGHT"

        fun register(context: Context, messenger: BinaryMessenger) {
            MethodChannel(messenger, "pdd/streak_widget").setMethodCallHandler { call, result ->
                if (call.method != "update") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val data = call.arguments as? Map<*, *>
                if (data == null) {
                    result.error("invalid_snapshot", "Missing streak snapshot", null)
                    return@setMethodCallHandler
                }
                val json = JSONObject(data).toString()
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                if (prefs.getString("snapshot", null) != json) {
                    if (!prefs.edit().putString("snapshot", json).commit()) {
                        result.error("write_failed", "Could not store widget snapshot", null)
                        return@setMethodCallHandler
                    }
                    refreshAll(context)
                }
                result.success(null)
            }
        }

        private fun ids(context: Context, manager: AppWidgetManager, style: StreakWidgetStyle) =
            manager.getAppWidgetIds(ComponentName(context, style.providerClass))

        private fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            var hasWidgets = false
            StreakWidgetStyle.entries.forEach { style ->
                val installed = ids(context, manager, style)
                hasWidgets = hasWidgets || installed.isNotEmpty()
                installed.forEach { update(context, manager, it, style) }
            }
            if (hasWidgets) scheduleMidnight(context)
        }

        private fun update(context: Context, manager: AppWidgetManager, id: Int, style: StreakWidgetStyle) {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("snapshot", null)
            val data = try { JSONObject(raw ?: "{}") } catch (_: Exception) { JSONObject() }
            val state = StreakWidgetState.from(data.optInt("current"), data.optInt("longest"),
                data.optString("lastActiveDate").takeIf { it.isNotBlank() })
            val (current, best, done) = state
            fun label(key: String, fallback: Int) = data.optString(key).takeIf { it.isNotBlank() } ?: context.getString(fallback)
            val options = manager.getAppWidgetOptions(id)
            val wide = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) >= 250
            val tall = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) >= 190
            fun render(wide: Boolean, tall: Boolean): RemoteViews {
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
            val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // The launcher selects the fitting layout during resize and rotation.
                RemoteViews(mapOf(
                    SizeF(130f, 130f) to render(false, false),
                    SizeF(130f, 190f) to render(false, true),
                    SizeF(250f, 130f) to render(true, false),
                    SizeF(250f, 190f) to render(true, true),
                ))
            } else render(wide, tall)
            manager.updateAppWidget(id, views)
        }

        private fun midnightIntent(context: Context) = PendingIntent.getBroadcast(context, 7401,
            Intent(context, StreakWidgetProvider::class.java).setAction(MIDNIGHT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        private fun scheduleMidnight(context: Context) {
            val next = Calendar.getInstance().apply {
                add(Calendar.DATE, 1)
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            // Inexact, no exact-alarm permission. Periodic widget updates are a fallback.
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                .set(AlarmManager.RTC, next.timeInMillis, midnightIntent(context))
        }
    }
}

class MinimalStreakWidgetProvider : StreakWidgetProvider()
class RecordStreakWidgetProvider : StreakWidgetProvider()

internal enum class StreakWidgetStyle(val providerClass: Class<out AppWidgetProvider>) {
    FLAME(StreakWidgetProvider::class.java),
    MINIMAL(MinimalStreakWidgetProvider::class.java),
    RECORD(RecordStreakWidgetProvider::class.java);

    fun layout(wide: Boolean): Int = when (this) {
        FLAME -> if (wide) R.layout.streak_widget_wide else R.layout.streak_widget
        MINIMAL -> if (wide) R.layout.streak_widget_minimal_wide else R.layout.streak_widget_minimal
        RECORD -> if (wide) R.layout.streak_widget_record_wide else R.layout.streak_widget_record
    }
}
