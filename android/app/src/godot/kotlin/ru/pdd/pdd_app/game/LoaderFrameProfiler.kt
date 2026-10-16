package ru.pdd.pdd_app.game

import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.FrameMetrics
import android.view.Window

/** Opt-in dev diagnostics for the Android cover only; no PSS scans or gameplay sampling. */
internal class LoaderFrameProfiler(private val window: Window) {
    private val thread = HandlerThread("pdd-loader-metrics").apply { start() }
    private val handler = Handler(thread.looper)
    private val durations = ArrayList<Long>()
    private var phase: String? = null
    private var started = 0L
    private var droppedCallbacks = 0
    private var frameCount = 0
    private var maximum = 0L
    private var overBudget = 0
    private val listener = Window.OnFrameMetricsAvailableListener { _, metrics, dropped ->
        val total = metrics.getMetric(FrameMetrics.TOTAL_DURATION)
        frameCount += 1
        maximum = maxOf(maximum, total)
        if (total > 16_666_667L) overBudget += 1
        // Bounded even if an unrelated failed scene leaves its cover up indefinitely.
        if (durations.size < 4096) durations.add(total)
        droppedCallbacks += dropped
    }

    fun start(nextPhase: String) {
        if (Build.VERSION.SDK_INT < 24 || phase == nextPhase) return
        stop()
        phase = nextPhase
        handler.post {
            durations.clear()
            droppedCallbacks = 0
            frameCount = 0
            maximum = 0L
            overBudget = 0
            started = SystemClock.elapsedRealtimeNanos()
        }
        window.addOnFrameMetricsAvailableListener(listener, handler)
    }

    fun stop() {
        val completedPhase = phase ?: return
        phase = null
        if (Build.VERSION.SDK_INT < 24) return
        window.removeOnFrameMetricsAvailableListener(listener)
        handler.post {
            val wallMs = (SystemClock.elapsedRealtimeNanos() - started) / 1_000_000.0
            val sorted = durations.sorted()
            val p95 = if (sorted.isEmpty()) 0.0 else sorted[((sorted.size - 1) * 0.95).toInt()] / 1_000_000.0
            Log.i("LoaderPerf", "phase=$completedPhase frames=$frameCount wall_ms=${"%.1f".format(java.util.Locale.US, wallMs)} " +
                "total_p95_ms=${"%.2f".format(java.util.Locale.US, p95)} max_ms=${"%.2f".format(java.util.Locale.US, maximum / 1_000_000.0)} " +
                "over_16_67_ms=$overBudget dropped_callbacks=$droppedCallbacks")
            durations.clear()
        }
    }

    fun close() {
        stop()
        thread.quitSafely()
    }
}
