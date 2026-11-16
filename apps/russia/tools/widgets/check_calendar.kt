package ru.pdd.pdd_app

import java.util.Calendar
import java.util.TimeZone

/** Runs on a JVM against the provider's production calendar model. */
fun main() {
    fun day(year: Int, month: Int, date: Int, zone: String = "Europe/Minsk") =
        Calendar.getInstance(TimeZone.getTimeZone(zone)).apply {
            clear(); set(year, month - 1, date, 0, 1)
        }
    fun state(last: String?, now: Calendar) = StreakWidgetState.from(7, 21, last, now)
    check(state("2026-11-16", day(2026, 11, 16)) == StreakWidgetState(7, 21, true))
    check(state("2026-11-16", day(2026, 11, 17)) == StreakWidgetState(7, 21, false))
    check(state("2026-11-16", day(2026, 11, 18)) == StreakWidgetState(0, 21, false))
    check(state("2026-12-31", day(2027, 1, 1)).current == 7)
    check(state("2024-02-29", day(2024, 3, 1)).current == 7)
    check(state("2026-03-07", day(2026, 3, 9, "America/New_York")).current == 0)
    check(state("2026-03-08", day(2026, 3, 9, "America/New_York")).current == 7)
    check(state("2026-10-31", day(2026, 11, 2, "America/New_York")).current == 0)
    check(state("2026-11-01", day(2026, 11, 2, "America/New_York")).current == 7)
    check(state(null, day(2026, 11, 16)).current == 0)
    check(state("bad-date", day(2026, 11, 16)).current == 0)
    check(StreakWidgetState.from(0, 0, null, day(2026, 11, 16)) == StreakWidgetState(0, 0, false))
    check(StreakWidgetState.from(7, 2, "2026-11-16", day(2026, 11, 16)).best == 7)
    check(StreakWidgetState(0, 0, false).progressPercent == 0)
    check(StreakWidgetState(7, 14, true).progressPercent == 50)
    check(StreakWidgetState(14, 14, true).progressPercent == 100)
    check(StreakWidgetState(0, 14, false).progressPercent == 0)
    check(StreakWidgetState(Int.MAX_VALUE, Int.MAX_VALUE, true).progressPercent == 100)
    println("18 native calendar and progress checks passed (grace day, expiry, DST, leap day, year boundary, empty/reset).")
}
