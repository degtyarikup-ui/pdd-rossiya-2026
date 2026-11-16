package ru.pdd.pdd_app

import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/** Calendar days rather than 24-hour durations, including DST and travel. */
internal data class StreakWidgetState(val current: Int, val best: Int, val done: Boolean) {
    val progressPercent: Int
        get() = if (best > 0) ((current.toDouble() / best) * 100).toInt().coerceIn(0, 100) else 0

    companion object {
        fun from(storedCurrent: Int, storedBest: Int, lastActive: String?, now: Calendar = Calendar.getInstance()): StreakWidgetState {
            val format = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).apply {
                isLenient = false
                timeZone = now.timeZone
            }
            val last = try { lastActive?.let { format.parse(it) } } catch (_: Exception) { null }
            val today = (now.clone() as Calendar).apply {
                set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            }
            val yesterday = (today.clone() as Calendar).apply { add(Calendar.DATE, -1) }
            val current = if (last != null && !last.before(yesterday.time)) storedCurrent.coerceAtLeast(0) else 0
            return StreakWidgetState(current, maxOf(current, storedBest.coerceAtLeast(0)),
                last != null && format.format(last) == format.format(today.time))
        }
    }
}
