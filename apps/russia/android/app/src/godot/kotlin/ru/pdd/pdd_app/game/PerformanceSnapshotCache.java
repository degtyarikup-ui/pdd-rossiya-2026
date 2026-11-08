package ru.pdd.pdd_app.game;

import java.util.concurrent.Executor;
import java.util.function.LongSupplier;
import java.util.function.Supplier;

/** One bounded background request; callers only read an immutable cached snapshot. */
final class PerformanceSnapshotCache {
    private final Executor executor;
    private final LongSupplier clockMillis;
    private final Supplier<String> sample;
    private final long intervalMillis;
    private volatile String cached = "";
    private boolean enabled;
    private boolean closed;
    private boolean inFlight;
    private long generation;
    private long lastStartedMillis = -1;

    PerformanceSnapshotCache(Executor executor, LongSupplier clockMillis,
                             Supplier<String> sample, long intervalMillis) {
        this.executor = executor;
        this.clockMillis = clockMillis;
        this.sample = sample;
        this.intervalMillis = intervalMillis;
    }

    void setEnabled(boolean value) {
        synchronized (this) {
            if (closed || enabled == value) return;
            enabled = value;
            generation++;
            cached = "";
            lastStartedMillis = -1;
        }
        if (value) requestIfDue();
    }

    String read() {
        requestIfDue();
        return cached;
    }

    void close() {
        synchronized (this) {
            closed = true;
            enabled = false;
            generation++;
            cached = "";
        }
    }

    private void requestIfDue() {
        final long token;
        synchronized (this) {
            if (!enabled || closed || inFlight) return;
            long now = clockMillis.getAsLong();
            if (lastStartedMillis >= 0 && now - lastStartedMillis < intervalMillis) return;
            inFlight = true;
            lastStartedMillis = now;
            token = generation;
        }
        try {
            executor.execute(() -> collect(token));
        } catch (RuntimeException rejected) {
            synchronized (this) { inFlight = false; }
        }
    }

    private void collect(long token) {
        synchronized (this) {
            // Disabling a queued request prevents even its expensive collection.
            if (!enabled || closed || token != generation) {
                inFlight = false;
                return;
            }
        }
        String next = null;
        try {
            next = sample.get();
        } catch (RuntimeException unavailable) {
            // Keep the previous timestamped result; the HUD rejects stale samples.
        } finally {
            synchronized (this) {
                if (enabled && !closed && token == generation && next != null) cached = next;
                inFlight = false;
            }
        }
    }
}
