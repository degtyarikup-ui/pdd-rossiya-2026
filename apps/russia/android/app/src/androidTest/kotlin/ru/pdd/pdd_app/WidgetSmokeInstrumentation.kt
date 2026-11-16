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
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.LocaleList
import android.os.SystemClock
import android.view.ContextThemeWrapper
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.RemoteViews
import android.widget.TextView
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
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
            responsiveHosts()
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
        check(view.findViewById<TextView>(R.id.streak_current)?.text?.toString() == state.current.toString()) { "current count missing or stale" }
        check(view.findViewById<TextView>(R.id.streak_best)?.text?.contains(state.best.toString()) == true) { "best count missing or stale" }
        if (style == StreakWidgetStyle.RECORD) {
            check(view.findViewById<ProgressBar>(R.id.streak_progress).progress == state.progressPercent)
        }
        check(view.findViewById<View>(R.id.streak_root).hasOnClickListeners()) { "widget tap listener missing" }
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

    private fun renderMatrix() {
        val states = listOf(StreakWidgetState(0, 0, false), StreakWidgetState(7, 21, true),
            StreakWidgetState(0, 21, false), StreakWidgetState(999, 999, false))
        for (style in StreakWidgetStyle.entries) {
            for (language in listOf("ru", "en", "kk")) for (dark in listOf(false, true)) {
                for (font in listOf(1f, 2f)) for ((width, height) in listOf(130 to 130, 130 to 190, 250 to 130, 250 to 190, 360 to 300)) {
                    for (state in states) case("render $style $language dark=$dark font=$font ${width}x$height $state") {
                        val context = configured(language, dark, font)
                        val wide = width >= 250
                        val tall = height >= 190
                        // Also inflate the gallery preview, without any remote actions.
                        RemoteViews(context.packageName, style.layout(wide)).apply(context, FrameLayout(context))
                        val data = JSONObject(snapshot(context, state.current, state.best))
                        val remote = StreakWidgetRenderer.render(context, style, state, data, wide, tall)
                        val root = remote.apply(context, FrameLayout(context)) as ViewGroup
                        layout(root, context, width, height)
                        try {
                            assertValues(root, state, style)
                            assertTextFits(root)
                        } finally {
                            if (language == "ru" && state.current == 7 && height == 130) {
                                capture(root, "${style.name}-$width-dark$dark-font$font")
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
        report.appendLine("Rendered/reapplied all designs, 5 sizes, ru/en/kk, light/dark, 100%/200% text and 4 states.")
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
                    check(host.findViewById<View>(R.id.streak_status).visibility ==
                        if (width >= 250 || height >= 190) View.VISIBLE else View.GONE) {
                        "status visibility did not adapt at ${width}x$height: ${host.findViewById<View>(R.id.streak_status).visibility}"
                    }
                }
            }
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
