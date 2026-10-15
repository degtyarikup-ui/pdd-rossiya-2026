package ru.pdd.pdd_app.game

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/** `Engine.get_singleton("PddHost")` in the game (game_godot/scripts/host.gd). */
class PddHostPlugin(godot: Godot, private val host: GodotGameActivity) : GodotPlugin(godot) {
    override fun getPluginName() = "PddHost"

    private var performanceExecutor: java.util.concurrent.ExecutorService? = null
    private val performanceState = lazy {
        val executor = java.util.concurrent.Executors.newSingleThreadExecutor { task ->
            Thread(task, "pdd-performance").apply { isDaemon = true }
        }
        performanceExecutor = executor
        PerformanceSnapshotCache(executor, android.os.SystemClock::elapsedRealtime,
            { collectPerformanceSnapshot() }, 5000)
    }

    /** No memory-map scan runs on the Godot/JNI caller. Hidden release HUDs never start it. */
    @UsedByGodot
    fun setPerformanceSamplingEnabled(enabled: Boolean) {
        if (enabled) performanceState.value.setEnabled(true)
        else if (performanceState.isInitialized()) performanceState.value.setEnabled(false)
    }

    /** Returns immediately with the latest immutable sample, and requests at most one refresh. */
    @UsedByGodot
    fun performanceSnapshot(): String =
        if (performanceState.isInitialized()) performanceState.value.read() else ""

    private fun collectPerformanceSnapshot(): String {
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
        val started = android.os.SystemClock.elapsedRealtimeNanos()
        // PSS walks shared-page accounting and can be slow. Record its own duration.
        val pss = try { (android.os.Debug.getPss() / 1024).toInt() } catch (_: RuntimeException) { -1 }
        val pssFinished = android.os.SystemClock.elapsedRealtimeNanos()
        val power = host.getSystemService(android.os.PowerManager::class.java)
        val thermal = if (android.os.Build.VERSION.SDK_INT >= 29) power?.currentThermalStatus ?: -1 else -1
        return org.json.JSONObject().apply {
            put("pss_mb", if (pss >= 0) pss else org.json.JSONObject.NULL)
            put("thermal_state", if (thermal >= 0) thermal else org.json.JSONObject.NULL)
            put("low_power", power?.isPowerSaveMode ?: org.json.JSONObject.NULL)
            put("sample_time", System.currentTimeMillis() / 1000.0)
            put("pss_duration_ms", (pssFinished - started) / 1000000.0)
            put("sample_duration_ms", (android.os.SystemClock.elapsedRealtimeNanos() - started) / 1000000.0)
        }.toString()
    }

    /** App-owned external storage lets adb pull retrieve counters without a debug Flutter build. */
    @UsedByGodot
    fun performanceLogDirectory(): String = (host.getExternalFilesDir(null) ?: host.filesDir).absolutePath

    /** The canonical Flutter picture, with no second copy in the Godot assets. */
    @UsedByGodot
    fun pictureBytes(hash: String): ByteArray {
        if (!hash.matches(Regex("[a-f0-9]{32}"))) return byteArrayOf()
        for (category in listOf("ab", "cd")) {
            try {
                return host.assets.open("flutter_assets/assets/countries/ru/images/questions_$category/$hash.webp")
                    .use { it.readBytes() }
            } catch (_: java.io.IOException) {
                // Some CD photographs are shared with AB; the hash identifies the source bytes.
            }
        }
        return byteArrayOf()
    }

    /** The same answer effects used by the Flutter feed and exams. */
    @UsedByGodot
    fun answerAudioBytes(kind: String): ByteArray {
        if (kind !in setOf("correct", "incorrect", "tick", "streak")) return byteArrayOf()
        return try {
            host.assets.open("flutter_assets/assets/audio/$kind.wav").use { it.readBytes() }
        } catch (_: java.io.IOException) {
            byteArrayOf()
        }
    }

    /** The existing studio voice, converted once into the shared Flutter MP3 assets. */
    @UsedByGodot
    fun questionAudioBytes(hash: String): ByteArray {
        if (!hash.matches(Regex("[a-f0-9]{32}"))) return byteArrayOf()
        return try {
            host.assets.open("flutter_assets/assets/audio/game_questions/q_$hash.mp3")
                .use { it.readBytes() }
        } catch (_: java.io.IOException) {
            byteArrayOf()
        }
    }

    /** Any event of the game; «run_finished» carries the final summary. */
    @UsedByGodot
    fun send(json: String) {
        if (json.contains("\"run_finished\"")) {
            val summary = org.json.JSONObject(json).optJSONObject("summary")?.toString() ?: return
            host.runOnUiThread { host.keepSummary(summary) }
        }
    }

    /** The player leaves the game: the summary is kept as the result. The game then stops itself
     *  (Host.exit calls quit), and the activity closes in onGodotTerminating. Closing the activity
     *  from here, while the engine still draws a frame, crashed the render thread (SIGSEGV). */
    @UsedByGodot
    fun result(summary: String) {
        host.runOnUiThread {
            host.keepSummary(summary)
            host.prepareExit()
        }
    }

    override fun onGodotTerminating() {
        if (performanceState.isInitialized()) performanceState.value.close()
        performanceExecutor?.shutdownNow()
        host.runOnUiThread { host.finish() }
    }
}
