package ru.pdd.pdd_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
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
                if (!publish(context, data)) {
                    result.error("write_failed", "Could not store widget snapshot", null)
                    return@setMethodCallHandler
                }
                result.success(null)
            }
        }

        internal fun publish(context: Context, data: Map<*, *>): Boolean {
            val json = JSONObject(data).toString()
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString("snapshot", null) != json &&
                !prefs.edit().putString("snapshot", json).commit()) return false
            refreshAll(context)
            return true
        }

        private fun ids(context: Context, manager: AppWidgetManager, style: StreakWidgetStyle) =
            manager.getAppWidgetIds(ComponentName(context, style.providerClass))

        internal fun refreshAll(context: Context) {
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
            val options = manager.getAppWidgetOptions(id)
            val views = StreakWidgetRenderer.responsive(context, style, state, data,
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT))
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
