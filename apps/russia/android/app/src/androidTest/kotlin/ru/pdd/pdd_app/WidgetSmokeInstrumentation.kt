package ru.pdd.pdd_app

import android.app.Activity
import android.app.Instrumentation
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.GradientDrawable
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.LocaleList
import android.os.SystemClock
import android.view.ContextThemeWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.RemoteViews
import android.widget.TextView
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executor

/** Exercises the actual Android inflater, remote actions, host, receiver and storage. */
class WidgetSmokeInstrumentation : Instrumentation() {
    private var passed = 0
    private var failed = 0
    private val report = StringBuilder()

    private fun progress(message: String) = sendStatus(0, Bundle().apply {
        putString("stream", "\n$message\n")
    })

    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        start()
    }

    private fun case(name: String, block: () -> Unit) {
        var error: Throwable? = null
        runOnMainSync {
            try { block() } catch (caught: Throwable) { error = caught }
        }
        if (error == null) passed++ else {
            failed++
            report.appendLine("FAIL $name: $error")
        }
        if ((passed + failed) % 200 == 0) progress("Completed ${passed + failed} native cases; failures: $failed")
    }

    override fun onStart() {
        try {
            progress("Checking calendar boundaries")
            case("calendar boundaries and record progress") { main() }
            progress("Rendering all sizes, languages and themes")
            renderMatrix()
            progress("Checking state transitions")
            transitionMatrix()
            progress("Checking fallback labels and responsive hosts")
            fallbackCopy()
            responsiveHosts()
            midnightPalette()
            calendarStrip()
            sharedPublication()
        } catch (error: Throwable) {
            failed++
            report.appendLine("FAIL test runner: ${error.stackTraceToString()}")
        }
        finish(if (failed == 0) Activity.RESULT_OK else Activity.RESULT_CANCELED,
            Bundle().apply {
                putString("stream", "\n$report\nPassed: $passed; failed: $failed\n")
                putInt("failures", failed)
            })
    }

    private fun configured(language: String, dark: Boolean, fontScale: Float): Context {
        val config = Configuration(targetContext.resources.configuration).apply {
            setLocales(LocaleList(Locale.forLanguageTag(language)))
            uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
                if (dark) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
            this.fontScale = fontScale
        }
        return ContextThemeWrapper(targetContext.createConfigurationContext(config),
            android.R.style.Theme_Material_Light_NoActionBar)
    }

    private fun layout(view: View, context: Context, width: Int, height: Int) {
        val density = context.resources.displayMetrics.density
        val w = (width * density).toInt()
        val h = (height * density).toInt()
        // Auto-size can request a second pass, just as it does in a real host.
        repeat(4) {
            view.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
            view.layout(0, 0, w, h)
            if (!view.isLayoutRequested) return
        }
        check(!view.isLayoutRequested) { "layout did not settle" }
    }

    private fun assertValues(view: View, state: StreakWidgetState) {
        val root = view.findViewById<View>(R.id.streak_root)
        val week = root.findViewById<View>(R.id.streak_week)
        if (week != null && root.findViewById<View>(R.id.streak_row_content) == null) {
            check(root.findViewById<View>(R.id.streak_status_icon).visibility ==
                (if (state.done) View.VISIBLE else View.GONE))
        }
        check(root.hasOnClickListeners()) { "widget tap listener missing" }
        val fill = (root.background as GradientDrawable).color!!.defaultColor
        val background = if (state.done) R.color.streak_widget_active_background else R.color.streak_widget_waiting_background
        check(fill == root.context.getColor(background))
        for ((id, count) in listOf(R.id.streak_current to state.current, R.id.streak_best to state.best)) {
            val text = view.findViewById<TextView>(id)
            check(text.text.toString() == count.toString()) { "stale count" }
            check(text.currentTextColor == android.graphics.Color.WHITE)
        }
        val flame = view.findViewById<ImageView>(R.id.streak_flame)
        check(flame.drawable != null && flame.alpha == if (state.done) 1f else 0.66f)
        check(view.findViewById<ImageView>(R.id.streak_rays).drawable != null)
        check(view.findViewById<ImageView>(R.id.streak_trophy).drawable != null)
    }

    private fun assertTextFits(root: ViewGroup, view: View = root) {
        if (view.visibility != View.VISIBLE) return
        if (view is TextView && view.text.isNotEmpty()) {
            val bounds = Rect(0, 0, view.width, view.height)
            root.offsetDescendantRectToMyCoords(view, bounds)
            val name = view.resources.getResourceEntryName(view.id)
            check(bounds.left >= -1 && bounds.top >= -1 && bounds.right <= root.width + 1 && bounds.bottom <= root.height + 1) {
                "$name outside ${root.width}x${root.height}: $bounds"
            }
            val textLayout = checkNotNull(view.layout) { "$name has no text layout" }
            check(textLayout.height <= view.height - view.compoundPaddingTop - view.compoundPaddingBottom + 1) {
                "$name clips vertically (${textLayout.height} > ${view.height})"
            }
            check(textLayout.lineCount > 0 && textLayout.getLineEnd(textLayout.lineCount - 1) == view.text.length) {
                "$name drops text"
            }
            for (line in 0 until textLayout.lineCount) {
                // Layout.getLineWidth includes trailing spaces, which can hang
                // beyond a line without clipping any visible letters.
                val lineText = view.text.subSequence(textLayout.getLineStart(line), textLayout.getLineEnd(line)).toString()
                val trailing = lineText.takeLastWhile { it.isWhitespace() }
                val visibleWidth = textLayout.getLineWidth(line) - view.paint.measureText(trailing)
                check(visibleWidth <= view.width - view.compoundPaddingLeft - view.compoundPaddingRight + 1) {
                    "$name clips horizontally ($visibleWidth > ${view.width})"
                }
            }
        }
        if (view is ViewGroup) for (i in 0 until view.childCount) assertTextFits(root, view.getChildAt(i))
    }

    private fun snapshot(context: Context, current: Int = 7, best: Int = 21) = linkedMapOf<String, Any?>(
        "current" to current, "longest" to best,
        "lastActiveDate" to if (current > 0) SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date()) else null,
        "currentLabel" to context.getString(R.string.currentLabel),
        "bestLabel" to context.getString(R.string.bestLabel),
        "doneLabel" to context.getString(R.string.doneLabel),
        "continueLabel" to context.getString(R.string.continueLabel),
        "startLabel" to context.getString(R.string.startLabel),
    )

    private fun capture(root: View, name: String) {
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        root.draw(Canvas(bitmap))
        val directory = File(targetContext.cacheDir, "widget-smoke").apply { mkdirs() }
        File(directory, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
    }

    private data class Scenario(
        val name: String, val storedCurrent: Int, val storedBest: Int, val lastActive: String?,
        val expected: StreakWidgetState, val statusKey: String, val statusResource: Int,
    )

    private val scenarios = listOf(
        Scenario("never studied", 0, 0, null, StreakWidgetState(0, 0, false), "startLabel", R.string.startLabel),
        Scenario("yesterday, no lesson today", 7, 21, "2026-11-16", StreakWidgetState(7, 21, false), "continueLabel", R.string.continueLabel),
        Scenario("lesson today", 8, 21, "2026-11-17", StreakWidgetState(8, 21, true), "doneLabel", R.string.doneLabel),
        Scenario("first lesson", 1, 1, "2026-11-17", StreakWidgetState(1, 1, true), "doneLabel", R.string.doneLabel),
        Scenario("new record", 22, 22, "2026-11-17", StreakWidgetState(22, 22, true), "doneLabel", R.string.doneLabel),
        Scenario("missed a day", 7, 21, "2026-11-15", StreakWidgetState(0, 21, false), "startLabel", R.string.startLabel),
        Scenario("restarted after missing a day", 1, 21, "2026-11-17", StreakWidgetState(1, 21, true), "doneLabel", R.string.doneLabel),
        Scenario("long series waiting for lesson", 999, 999, "2026-11-16", StreakWidgetState(999, 999, false), "continueLabel", R.string.continueLabel),
    )

    private fun state(scenario: Scenario): StreakWidgetState {
        val now = Calendar.getInstance(TimeZone.getTimeZone("Europe/Minsk")).apply {
            clear(); set(2026, Calendar.NOVEMBER, 17, 12, 0)
        }
        return StreakWidgetState.from(scenario.storedCurrent, scenario.storedBest, scenario.lastActive, now)
            .also { check(it == scenario.expected) { "${scenario.name}: $it != ${scenario.expected}" } }
    }

    private fun copy(context: Context, scenario: Scenario) = JSONObject(snapshot(context,
        scenario.storedCurrent, scenario.storedBest)).apply {
        put("lastActiveDate", scenario.lastActive ?: JSONObject.NULL)
    }

    private fun assertCopy(root: View, context: Context, scenario: Scenario, data: JSONObject) {
        val labels = listOf(
            "currentLabel" to R.string.currentLabel,
            "bestLabel" to R.string.bestLabel,
            scenario.statusKey to scenario.statusResource,
        )
        val description = root.findViewById<View>(R.id.streak_root).contentDescription.toString()
        for ((key, resource) in labels) {
            val expected = data.optString(key).takeIf { it.isNotBlank() } ?: context.getString(resource)
            check(description.contains(expected)) { "missing localized description: $expected" }
        }
    }

    private fun renderMatrix() {
        for (language in listOf("ru", "en", "kk")) for (dark in listOf(false, true)) {
            for (font in listOf(1f, 2f)) for ((width, height) in listOf(130 to 40, 250 to 40, 370 to 104, 130 to 130, 130 to 190, 250 to 130, 250 to 190, 360 to 300)) {
                for (scenario in scenarios) case("render $language dark=$dark font=$font ${width}x$height ${scenario.name}") {
                    val state = state(scenario)
                    val context = configured(language, dark, font)
                    val wide = width >= 250
                    val data = copy(context, scenario)
                    val remote = StreakWidgetRenderer.render(context, state, data, wide, singleRow = height < 124)
                    val root = remote.apply(context, FrameLayout(context)) as ViewGroup
                    layout(root, context, width, height)
                    assertValues(root, state)
                    assertCopy(root, context, scenario, data)
                    assertTextFits(root)
                    if (language == "ru" && !dark && font == 1f && scenario.name == "first lesson") {
                        capture(root, "flame-${width}x$height")
                    }
                }
            }
        }
        report.appendLine("Rendered eight sizes, three languages, light/dark, 100%/200% text and eight dated scenarios.")
    }

    private fun transitionMatrix() {
        for ((width, height) in listOf(130 to 130, 250 to 190)) for (language in listOf("ru", "en", "kk")) {
            for (before in scenarios) for (after in scenarios) case("transition ${before.name} -> ${after.name} $language $width") {
                val context = configured(language, true, 2f)
                val wide = width >= 250
                val root = StreakWidgetRenderer.render(context, state(before), copy(context, before), wide)
                    .apply(context, FrameLayout(context)) as ViewGroup
                layout(root, context, width, height)
                val data = copy(context, after)
                StreakWidgetRenderer.render(context, state(after), data, wide).reapply(context, root)
                layout(root, context, width, height)
                assertValues(root, after.expected)
                assertCopy(root, context, after, data)
                assertTextFits(root)
                if (wide) check(root.findViewById<LinearLayout>(R.id.streak_week).childCount == 7)
            }
        }
    }

    private fun fallbackCopy() {
        for (language in listOf("ru", "en", "kk")) for (scenario in scenarios.take(3)) {
            case("fallback copy $language ${scenario.name}") {
                val context = configured(language, false, 1f)
                val data = JSONObject().put("currentLabel", "  ")
                val root = StreakWidgetRenderer.render(context, state(scenario), data, true)
                    .apply(context, FrameLayout(context))
                assertCopy(root, context, scenario, data)
            }
        }
    }


    private class HostView(context: Context) : AppWidgetHostView(context) {
        var error = false
        init { if (Build.VERSION.SDK_INT >= 26) setExecutor(Executor { it.run() }) }
        override fun getErrorView(): View { error = true; return super.getErrorView() }
    }

    private fun widgetOptions(width: Int, height: Int) = Bundle().apply {
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, width)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, height)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, width)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, height)
    }

    private fun responsiveHosts() {
        var testHost: HostView? = null
        val state = StreakWidgetState(7, 21, true)
        val context = configured("ru", false, 1f)
        case("responsive host setup") {
            val providers = AppWidgetManager.getInstance(context).installedProviders.filter {
                it.provider.packageName == context.packageName
            }
            check(providers.size == 1 && providers.single().provider == ComponentName(context, StreakWidgetProvider::class.java))
            if (android.os.Build.VERSION.SDK_INT >= 31) {
                val density = context.resources.displayMetrics.density
                check(providers.single().maxResizeWidth / density in 394f..396f)
                check(providers.single().maxResizeHeight / density in 207f..209f)
            }
            val minimumHeight = providers.single().minResizeHeight / context.resources.displayMetrics.density
            check(minimumHeight in 39f..41f) { "provider advertises minimum resize height $minimumHeight dp" }
            testHost = HostView(context).apply {
                setAppWidget(-100, providers.single())
                setPadding(0, 0, 0, 0)
                updateAppWidget(StreakWidgetRenderer.responsive(context, state, JSONObject(snapshot(context)), widgetOptions(130, 130)))
            }
        }
        waitForIdleSync()
        val host = testHost ?: return
        for ((width, height) in listOf(130 to 130, 130 to 40, 250 to 40, 370 to 104, 370 to 124, 250 to 190, 130 to 190, 130 to 86, 130 to 130)) {
            case("responsive layout ${width}x$height") {
                if (Build.VERSION.SDK_INT < 31) {
                    host.updateAppWidget(StreakWidgetRenderer.responsive(context, state, JSONObject(snapshot(context)), widgetOptions(width, height)))
                }
                layout(host, context, width, height)
            }
            waitForIdleSync()
            case("responsive values ${width}x$height") {
                layout(host, context, width, height)
                check(!host.error)
                assertValues(host, state)
                val row = host.findViewById<View>(R.id.streak_row_content)
                check((row != null) == (height < 124)) { "incorrect height family for ${width}x$height" }
                val week = host.findViewById<LinearLayout>(R.id.streak_week)
                check((week?.visibility == View.VISIBLE) == (width >= 250))
                if (width >= 250) check(week.childCount == (if (width < 350) 5 else 7))
                assertTextFits(host)
            }
        }
    }

    private fun midnightPalette() {
        case("main flame changes at local midnight") {
            val context = configured("ru", false, 1f)
            val data = JSONObject(snapshot(context))
            val today = StreakWidgetState(7, 21, true)
            val tomorrow = today.copy(done = false)
            val root = StreakWidgetRenderer.render(context, today, data, false).apply(context, FrameLayout(context))
            assertValues(root, today)
            StreakWidgetRenderer.render(context, tomorrow, data, false).reapply(context, root)
            assertValues(root, tomorrow)
        }
    }

    private fun calendarStrip() {
        case("weekly flames roll across a year boundary and reset when data changes") {
            val context = configured("en", false, 1f)
            val now = Calendar.getInstance(TimeZone.getTimeZone("Europe/Minsk")).apply {
                clear(); set(2027, Calendar.JANUARY, 2, 0, 10)
            }
            val data = JSONObject().put("locale", "ru").put("activeDates",
                org.json.JSONArray(listOf("2026-12-28", "2026-12-31", "2027-01-02")))
            val state = StreakWidgetState(1, 21, true)
            val remote = StreakWidgetRenderer.render(context, state, data, true, now)
            val root = remote.apply(context, FrameLayout(context)) as ViewGroup
            val week = root.findViewById<LinearLayout>(R.id.streak_week)
            fun assertDays(labels: List<String>, active: Set<Int>) {
                check(week.childCount == 7)
                for (i in labels.indices) {
                    val day = week.getChildAt(i)
                    check(day.findViewById<TextView>(R.id.streak_day_label).text.toString().lowercase(Locale.ROOT) == labels[i])
                    val marker = day.findViewById<ImageView>(R.id.streak_day_icon)
                    val expected = context.getDrawable(if (i in active) R.drawable.streak_widget_flame else R.drawable.streak_widget_day_empty)!!
                    check(marker.drawable.intrinsicWidth == expected.intrinsicWidth)
                    check((day.findViewById<View>(R.id.streak_day_today).visibility == View.VISIBLE) == (i == 6))
                }
            }
            assertDays(listOf("вс", "пн", "вт", "ср", "чт", "пт", "сб"), setOf(1, 4, 6))
            layout(root, context, 250, 130)
            capture(root, "flame-week")
            val compact = StreakWidgetRenderer.render(context, state, data, false, now)
                .apply(context, FrameLayout(context))
            layout(compact, context, 130, 130)
            capture(compact, "flame-compact")
            for ((width, height) in listOf(130 to 40, 250 to 40, 195 to 105, 300 to 105, 130 to 90, 370 to 64, 407 to 105)) {
                val row = StreakWidgetRenderer.render(context, state, data, width >= 250, now, singleRow = true, dayCount = if (width < 350) 5 else 7)
                    .apply(context, FrameLayout(context)) as ViewGroup
                layout(row, context, width, height)
                assertTextFits(row)
                if (height >= 90) {
                    val count = row.findViewById<TextView>(R.id.streak_current)
                    check(count.textSize >= 30 * context.resources.displayMetrics.density)
                }
                if (width == 407) {
                    val label = row.findViewById<TextView>(R.id.streak_day_label)
                    check(label.textSize >= 12 * context.resources.displayMetrics.density)
                    check(row.findViewById<View>(R.id.streak_week).background == null)
                }
                capture(row, "flame-row-${width}x$height")
            }
            val large = StreakWidgetRenderer.render(context, state, data, true, now)
                .apply(context, FrameLayout(context))
            layout(large, context, 407, 222)
            capture(large, "flame-large")
            now.add(Calendar.DATE, 1)
            for ((width, height) in listOf(195 to 105, 300 to 105, 407 to 222)) {
                val waiting = StreakWidgetRenderer.render(context, state.copy(done = false), data,
                    width >= 250, now, singleRow = height < 124, dayCount = if (width < 350) 5 else 7)
                    .apply(context, FrameLayout(context))
                layout(waiting, context, width, height)
                capture(waiting, "flame-waiting-${width}x$height")
            }
            StreakWidgetRenderer.render(context, state.copy(done = false), data, true, now).reapply(context, root)
            assertDays(listOf("пн", "вт", "ср", "чт", "пт", "сб", "вс"), setOf(0, 3, 5))
        }
    }

    private fun await(name: String, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (SystemClock.elapsedRealtime() < deadline) {
            var ready = false
            runOnMainSync { ready = condition() }
            if (ready) { passed++; return }
            SystemClock.sleep(40)
        }
        failed++
        report.appendLine("FAIL $name: timed out waiting for native host update")
    }

    private fun sharedPublication() {
        val context = targetContext
        val manager = AppWidgetManager.getInstance(context)
        val prefs = context.getSharedPreferences("streak_home_widget", Context.MODE_PRIVATE)
        val before = prefs.getString("snapshot", null)
        val host = object : AppWidgetHost(context, 0x50444473) {
            override fun onCreateView(context: Context, id: Int, info: AppWidgetProviderInfo): AppWidgetHostView = HostView(context)
        }
        var view: HostView? = null
        uiAutomation.adoptShellPermissionIdentity("android.permission.BIND_APPWIDGET")
        try {
            case("bind isolated test host") {
                host.deleteHost()
                host.startListening()
                val id = host.allocateAppWidgetId()
                check(manager.bindAppWidgetIdIfAllowed(id, ComponentName(context, StreakWidgetProvider::class.java)))
                view = host.createView(context, id, manager.getAppWidgetInfo(id)) as HostView
            }
            val result = view ?: return
            val data = snapshot(context)
            case("publish to provider") { check(StreakWidgetProvider.publish(context, data)) }
            fun received(count: String) = !result.error && result.findViewById<TextView>(R.id.streak_current)?.text?.toString() == count
            await("widget received 7") { received("7") }
            case("clear host cache") { result.updateAppWidget(null) }
            case("republish unchanged snapshot") { check(StreakWidgetProvider.publish(context, data)) }
            await("unchanged publication repairs host") { received("7") }
            case("reset snapshot") { check(StreakWidgetProvider.publish(context, snapshot(context, 0, 0))) }
            await("reset reaches the widget") { received("0") }
        } finally {
            runOnMainSync {
                host.stopListening()
                host.deleteHost()
                if (before == null) prefs.edit().remove("snapshot").commit() else prefs.edit().putString("snapshot", before).commit()
                StreakWidgetProvider.refreshAll(context)
            }
            uiAutomation.dropShellPermissionIdentity()
        }
        report.appendLine("Checked publication, unchanged-snapshot recovery and reset; restored original data.")
    }
}
