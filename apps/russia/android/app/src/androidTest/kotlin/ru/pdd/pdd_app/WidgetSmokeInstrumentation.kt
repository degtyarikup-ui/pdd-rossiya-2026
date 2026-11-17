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
import android.widget.ProgressBar
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
    }

    override fun onStart() {
        try {
            case("calendar boundaries and record progress") { main() }
            renderMatrix()
            transitionMatrix()
            fallbackCopy()
            responsiveHosts()
            midnightPalette()
            legacyHiddenStatus()
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

    private fun assertValues(view: View, state: StreakWidgetState, style: StreakWidgetStyle) {
        check(view.findViewById<TextView>(R.id.streak_status).visibility == View.VISIBLE) { "today's status is hidden" }
        check(view.findViewById<TextView>(R.id.streak_current)?.text?.toString() == state.current.toString()) { "current count missing or stale" }
        check(view.findViewById<TextView>(R.id.streak_best)?.text?.toString() == state.best.toString()) { "best count missing or stale" }
        if (style == StreakWidgetStyle.RECORD) {
            check(view.findViewById<ProgressBar>(R.id.streak_progress).progress == state.progressPercent)
        }
        check(view.findViewById<View>(R.id.streak_root).hasOnClickListeners()) { "widget tap listener missing" }
        val root = view.findViewById<View>(R.id.streak_root)
        val gold = root.context.getColor(R.color.streak_widget_active_background)
        val fill = (root.background as GradientDrawable).color!!.defaultColor
        check((fill == gold) == state.done) { "background does not match today's activity" }
        if (state.done) {
            check(view.findViewById<TextView>(R.id.streak_current).currentTextColor ==
                root.context.getColor(R.color.streak_widget_active_text))
        }
        for (id in listOf(R.id.streak_flame, R.id.streak_trophy)) {
            check(view.findViewById<ImageView>(id)?.drawable != null) { "missing vector icon" }
        }
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
                check(textLayout.getLineWidth(line) <= view.width - view.compoundPaddingLeft - view.compoundPaddingRight + 1) {
                    "$name clips horizontally (${textLayout.getLineWidth(line)} > ${view.width})"
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
            Triple(R.id.streak_label, "currentLabel", R.string.currentLabel),
            Triple(R.id.streak_best_label, "bestLabel", R.string.bestLabel),
            Triple(R.id.streak_status, scenario.statusKey, scenario.statusResource),
        )
        for ((id, key, resource) in labels) {
            val expected = data.optString(key).takeIf { it.isNotBlank() } ?: context.getString(resource)
            check(root.findViewById<TextView>(id).text.toString() == expected) {
                "${scenario.name}: wrong $key (including stale text after reapply)"
            }
        }
    }

    private fun renderMatrix() {
        for (style in StreakWidgetStyle.entries) {
            for (language in listOf("ru", "en", "kk")) for (dark in listOf(false, true)) {
                for (font in listOf(1f, 2f)) for ((width, height) in listOf(130 to 130, 130 to 190, 250 to 130, 250 to 190, 360 to 300)) {
                    for (scenario in scenarios) case("render $style $language dark=$dark font=$font ${width}x$height ${scenario.name}") {
                        val state = state(scenario)
                        val context = configured(language, dark, font)
                        val wide = width >= 250
                        val tall = height >= 190
                        // Also inflate the gallery preview, without any remote actions.
                        RemoteViews(context.packageName, style.layout(wide)).apply(context, FrameLayout(context))
                        val data = copy(context, scenario)
                        val remote = StreakWidgetRenderer.render(context, style, state, data, wide, tall)
                        val root = remote.apply(context, FrameLayout(context)) as ViewGroup
                        layout(root, context, width, height)
                        try {
                            assertValues(root, state, style)
                            assertCopy(root, context, scenario, data)
                            assertTextFits(root)
                        } finally {
                            if (language == "ru" && height == 130 && scenario.name in listOf("yesterday, no lesson today", "lesson today")) {
                                capture(root, "${style.name}-$width-dark$dark-font$font-active${state.done}")
                            }
                        }
                        // Reapply must clear old counts, progress, and today's state.
                        val reset = StreakWidgetState(0, 0, false)
                        StreakWidgetRenderer.render(context, style, reset, JSONObject(snapshot(context, 0, 0)), wide, tall)
                            .reapply(context, root)
                        layout(root, context, width, height)
                        assertValues(root, reset, style)
                    }
                }
            }
        }
        report.appendLine("Rendered/reapplied all designs, 5 sizes, ru/en/kk, light/dark, 100%/200% text and 8 dated scenarios; checked exact labels and statuses.")
    }

    private fun transitionMatrix() {
        // Every ordered pair catches stale text/colors in both directions, including
        // imports, reset, restart, a new record and unchanged repeated publications.
        for (style in StreakWidgetStyle.entries) for (language in listOf("ru", "en", "kk")) {
            for (dark in listOf(false, true)) for ((width, height) in listOf(130 to 130, 250 to 190)) {
                for (before in scenarios) for (after in scenarios) {
                        case("transition $style $language dark=$dark ${width}x$height ${before.name} -> ${after.name}") {
                            val context = configured(language, dark, 2f)
                            val wide = width >= 250
                            val tall = height >= 190
                            val root = StreakWidgetRenderer.render(context, style, state(before), copy(context, before), wide, tall)
                                .apply(context, FrameLayout(context)) as ViewGroup
                            layout(root, context, width, height)
                            assertValues(root, before.expected, style)
                            assertCopy(root, context, before, copy(context, before))
                            val data = copy(context, after)
                            StreakWidgetRenderer.render(context, style, state(after), data, wide, tall).reapply(context, root)
                            layout(root, context, width, height)
                            assertValues(root, after.expected, style)
                            assertCopy(root, context, after, data)
                            assertTextFits(root)
                            if (language == "ru" && !dark && before.name == "long series waiting for lesson" && after.name == "never studied") {
                                capture(root, "${style.name}-reapply-999-to-0-$width")
                            }
                        }
                }
            }
        }
        report.appendLine("Checked all 64 ordered state transitions per design/language/theme with 200% text in small and wide layouts.")
    }

    private fun fallbackCopy() {
        // A newly added widget may have no translated snapshot yet. Blank legacy
        // values must fall back too, and a language update must replace old copy.
        for (style in StreakWidgetStyle.entries) for (language in listOf("ru", "en", "kk")) {
            for (scenario in scenarios.take(3)) for (blank in listOf(false, true)) {
                case("fallback copy $style $language ${scenario.name} blank=$blank") {
                    val context = configured(language, false, 2f)
                    val data = JSONObject()
                    if (blank) for (key in listOf("currentLabel", "bestLabel", "startLabel", "continueLabel", "doneLabel")) {
                        data.put(key, "   ")
                    }
                    val root = StreakWidgetRenderer.render(context, style, state(scenario),
                        copy(configured("en", false, 2f), scenario), true, true)
                        .apply(context, FrameLayout(context)) as ViewGroup
                    StreakWidgetRenderer.render(context, style, state(scenario), data, true, true).reapply(context, root)
                    layout(root, context, 250, 190)
                    assertCopy(root, context, scenario, data)
                    assertTextFits(root)
                }
            }
        }
        report.appendLine("Checked missing/blank translations and replacement of previous-language copy for all three statuses.")
    }

    private class HostView(context: Context) : AppWidgetHostView(context) {
        var error = false
        init { if (Build.VERSION.SDK_INT >= 26) setExecutor(Executor { it.run() }) }
        override fun getErrorView(): View { error = true; return super.getErrorView() }
    }

    private fun responsiveHosts() {
        for (style in StreakWidgetStyle.entries) {
            var testHost: HostView? = null
            var testContext: Context? = null
            val state = StreakWidgetState(7, 21, true)
            case("responsive host setup $style") {
                val context = configured("ru", false, 1f)
                testContext = context
                val info = AppWidgetManager.getInstance(context).installedProviders.first {
                    it.provider == ComponentName(context, style.providerClass)
                }
                testHost = HostView(context).apply {
                    setAppWidget(-100, info)
                    setPadding(0, 0, 0, 0)
                    updateAppWidget(StreakWidgetRenderer.responsive(context, style, state,
                        JSONObject(snapshot(context)), 130, 130))
                }
            }
            // RemoteViews.applyAsync posts its completion to the main looper.
            // Even an inline worker executor must yield before asserting its result.
            waitForIdleSync()
            val host = testHost ?: continue
            val context = testContext ?: continue
            for ((width, height) in listOf(130 to 130, 250 to 130, 250 to 190, 130 to 190, 130 to 130)) {
                case("responsive layout $style ${width}x$height") {
                    if (Build.VERSION.SDK_INT < 31) {
                        // Older launchers ask the provider to render again after resizing.
                        host.updateAppWidget(StreakWidgetRenderer.responsive(context, style, state,
                            JSONObject(snapshot(context)), width, height))
                    }
                    layout(host, context, width, height)
                }
                waitForIdleSync()
                case("responsive values $style ${width}x$height") {
                    layout(host, context, width, height)
                    check(!host.error) { "host fell back to its error view" }
                    assertValues(host, state, style)
                    check(host.findViewById<View>(R.id.streak_status).visibility == View.VISIBLE) {
                        "status disappeared at ${width}x$height"
                    }
                }
            }
        }
    }

    private fun midnightPalette() {
        for (style in StreakWidgetStyle.entries) case("background changes at local midnight $style") {
            val context = configured("ru", false, 1f)
            fun day(date: Int) = Calendar.getInstance().apply {
                clear(); set(2026, Calendar.NOVEMBER, date, 0, 1)
            }
            val data = JSONObject(snapshot(context))
            val today = StreakWidgetState.from(7, 21, "2026-11-16", day(16))
            val tomorrow = StreakWidgetState.from(7, 21, "2026-11-16", day(17))
            check(today.done && !tomorrow.done && tomorrow.current == 7)
            val root = StreakWidgetRenderer.render(context, style, today, data, false, false)
                .apply(context, FrameLayout(context))
            layout(root, context, 130, 130)
            assertValues(root, today, style)
            StreakWidgetRenderer.render(context, style, tomorrow, data, false, false).reapply(context, root)
            layout(root, context, 130, 130)
            assertValues(root, tomorrow, style)
        }
    }

    private fun legacyHiddenStatus() {
        for (style in StreakWidgetStyle.entries) case("old compact host reveals today's status $style") {
            val context = configured("ru", true, 2f)
            val scenario = scenarios.first()
            val data = copy(context, scenario)
            val remote = StreakWidgetRenderer.render(context, style, state(scenario), data, false, false)
            val root = remote.apply(context, FrameLayout(context)) as ViewGroup
            layout(root, context, 130, 130)
            // A launcher may retain a view whose visibility came from the old APK.
            root.findViewById<TextView>(R.id.streak_status).visibility = View.GONE
            remote.reapply(context, root)
            layout(root, context, 130, 130)
            assertValues(root, scenario.expected, style)
            assertCopy(root, context, scenario, data)
            assertTextFits(root)
            capture(root, "${style.name}-compact-status-visible")
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
        val views = linkedMapOf<StreakWidgetStyle, HostView>()
        val ids = linkedMapOf<StreakWidgetStyle, Int>()
        uiAutomation.adoptShellPermissionIdentity("android.permission.BIND_APPWIDGET")
        try {
            case("bind isolated test host") {
                host.deleteHost()
                host.startListening()
                for (style in StreakWidgetStyle.entries) {
                    val id = host.allocateAppWidgetId()
                    check(manager.bindAppWidgetIdIfAllowed(id, ComponentName(context, style.providerClass))) { "widget bind denied" }
                    ids[style] = id
                    views[style] = host.createView(context, id, manager.getAppWidgetInfo(id)) as HostView
                }
            }
            if (views.size != 3) return
            val data = snapshot(context)
            case("publish to all providers") { check(StreakWidgetProvider.publish(context, data)) }
            await("all three providers received 7", {
                views.values.all { !it.error && it.findViewById<TextView>(R.id.streak_current)?.text?.toString() == "7" }
            })
            case("clear host cache without changing snapshot") { views.values.forEach { it.updateAppWidget(null) } }
            case("republish unchanged snapshot") { check(StreakWidgetProvider.publish(context, data)) }
            await("unchanged publication repairs all hosts", {
                views.values.all { it.findViewById<TextView>(R.id.streak_current)?.text?.toString() == "7" }
            })
            val format = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT)
            fun previousDay(days: Int) = format.format(Calendar.getInstance().apply {
                add(Calendar.DATE, -days)
            }.time)
            val publications = listOf(
                Triple("opened without a lesson", snapshot(context).apply { put("lastActiveDate", previousDay(1)) },
                    StreakWidgetState(7, 21, false)),
                Triple("still no lesson after republishing", snapshot(context).apply { put("lastActiveDate", previousDay(1)) },
                    StreakWidgetState(7, 21, false)),
                Triple("lesson extends the series", snapshot(context, 8, 21), StreakWidgetState(8, 21, true)),
                Triple("missed day expires the series", snapshot(context, 8, 21).apply { put("lastActiveDate", previousDay(2)) },
                    StreakWidgetState(0, 21, false)),
                Triple("lesson restarts the series", snapshot(context, 1, 21), StreakWidgetState(1, 21, true)),
            )
            for ((name, publication, expected) in publications) {
                case("publish $name") { check(StreakWidgetProvider.publish(context, publication)) }
                val status = context.getString(when {
                    expected.done -> R.string.doneLabel
                    expected.current > 0 -> R.string.continueLabel
                    else -> R.string.startLabel
                })
                await("all providers show $name with matching background and status", {
                    views.all { (style, view) -> runCatching {
                        assertValues(view, expected, style)
                        check(view.findViewById<TextView>(R.id.streak_status).text.toString() == status)
                    }.isSuccess }
                })
            }
            case("remove only one design") { host.deleteAppWidgetId(ids.getValue(StreakWidgetStyle.FLAME)) }
            case("midnight refresh continues for remaining providers") {
                prefs.edit().putString("snapshot", JSONObject(snapshot(context, 9, 21)).toString()).commit()
                StreakWidgetProvider().onReceive(context, Intent("ru.pdd.pdd_app.STREAK_MIDNIGHT"))
            }
            await("remaining designs updated after removal", {
                views.filterKeys { it != StreakWidgetStyle.FLAME }.values.all {
                    it.findViewById<TextView>(R.id.streak_current)?.text?.toString() == "9"
                }
            })
            case("reset snapshot") { check(StreakWidgetProvider.publish(context, snapshot(context, 0, 0))) }
            await("reset reaches remaining designs", {
                views.filterKeys { it != StreakWidgetStyle.FLAME }.values.all {
                    it.findViewById<TextView>(R.id.streak_current)?.text?.toString() == "0" &&
                        it.findViewById<TextView>(R.id.streak_best)?.text?.contains("0") == true
                }
            })
        } finally {
            runOnMainSync {
                host.stopListening()
                host.deleteHost()
                if (before == null) prefs.edit().remove("snapshot").commit() else prefs.edit().putString("snapshot", before).commit()
                StreakWidgetProvider.refreshAll(context)
            }
            uiAutomation.dropShellPermissionIdentity()
        }
        report.appendLine("Checked shared publication, unchanged-snapshot recovery, reset, and refresh after removing one design; restored original data.")
    }
}
