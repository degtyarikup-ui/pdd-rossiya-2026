"""PSS collection never runs in the caller; one bounded worker request owns each sample."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "android/app/src/godot/kotlin/ru/pdd/pdd_app/game/PerformanceSnapshotCache.java"
HARNESS = r"""
package ru.pdd.pdd_app.game;
import java.util.ArrayDeque;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

public class PerformanceSnapshotCacheCheck {
    static int checks;
    static void expect(boolean ok, String label) {
        checks++;
        if (!ok) throw new AssertionError(label);
    }
    public static void main(String[] args) {
        ArrayDeque<Runnable> queue = new ArrayDeque<>();
        AtomicLong clock = new AtomicLong(1000);
        AtomicInteger samples = new AtomicInteger();
        PerformanceSnapshotCache cache = new PerformanceSnapshotCache(queue::add, clock::get, () -> {
            int count = samples.incrementAndGet();
            clock.addAndGet(547); // Simulated expensive scan, with no sleep.
            return "sample-" + count;
        }, 5000);
        expect(cache.read().isEmpty() && queue.isEmpty() && samples.get() == 0, "hidden cache does no collection");
        cache.setEnabled(true);
        expect(samples.get() == 0 && queue.size() == 1, "enabling only enqueues work");
        for (int i = 0; i < 10000; i++) expect(cache.read().isEmpty(), "pending result remains unavailable");
        expect(queue.size() == 1 && samples.get() == 0, "requests cannot grow the queue or scan inline");
        queue.remove().run();
        expect(cache.read().equals("sample-1") && samples.get() == 1, "completed immutable snapshot becomes readable");
        expect(queue.isEmpty(), "five-second minimum prevents repeat sampling");
        clock.set(6000);
        expect(cache.read().equals("sample-1") && queue.size() == 1, "refresh returns previous result without waiting");
        cache.setEnabled(false);
        expect(cache.read().isEmpty(), "disable invalidates prior snapshot");
        queue.remove().run();
        expect(samples.get() == 1 && queue.isEmpty(), "disabled queued work never scans memory");
        cache.setEnabled(true);
        queue.remove().run();
        expect(cache.read().equals("sample-2"), "reenabling gets a new generation");
        clock.addAndGet(5000);
        cache.read();
        cache.setEnabled(false);
        cache.setEnabled(true);
        expect(queue.size() == 1, "toggling cannot pile up queued generations");
        queue.remove().run();
        expect(samples.get() == 2 && cache.read().isEmpty() && queue.size() == 1, "stale queued generation skipped; new request remains bounded");
        queue.remove().run();
        expect(cache.read().equals("sample-3"), "new generation publishes after stale task is dropped");
        cache.close();
        cache.setEnabled(true);
        expect(cache.read().isEmpty() && queue.isEmpty(), "termination permanently stops collection");

        PerformanceSnapshotCache[] holder = new PerformanceSnapshotCache[1];
        holder[0] = new PerformanceSnapshotCache(queue::add, clock::get, () -> {
            holder[0].setEnabled(false); // A scan already in flight cannot be cancelled safely.
            return "stale-in-flight";
        }, 5000);
        holder[0].setEnabled(true);
        queue.remove().run();
        expect(holder[0].read().isEmpty(), "disable during a scan rejects late publication");
        holder[0].close();

        PerformanceSnapshotCache unavailable = new PerformanceSnapshotCache(queue::add, clock::get, () -> {
            throw new IllegalStateException("unavailable");
        }, 5000);
        unavailable.setEnabled(true);
        queue.remove().run();
        expect(unavailable.read().isEmpty() && queue.isEmpty(), "failed background sample remains unavailable without hot retry");
        unavailable.close();
        System.out.println("performance snapshot cache: " + checks + " checks");
    }
}
"""


class PerformanceSnapshotCacheTests(unittest.TestCase):
    def test_bounded_background_lifecycle_and_no_inline_memory_scan(self):
        jdk = Path("/opt/homebrew/opt/openjdk@17/bin")
        javac = str(jdk / "javac") if (jdk / "javac").exists() else shutil.which("javac")
        java = str(jdk / "java") if (jdk / "java").exists() else shutil.which("java")
        self.assertTrue(javac and java, "Java runtime required for native cache check")
        scratch = ROOT / "scratch"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="performance-cache-", dir=scratch) as folder:
            temporary = Path(folder)
            harness = temporary / "PerformanceSnapshotCacheCheck.java"
            harness.write_text(HARNESS)
            compile_result = subprocess.run([javac, "--release", "8", "-d", str(temporary), str(SOURCE), str(harness)],
                                            text=True, capture_output=True, timeout=60)
            self.assertEqual(compile_result.returncode, 0, compile_result.stdout + compile_result.stderr)
            result = subprocess.run([java, "-cp", str(temporary), "ru.pdd.pdd_app.game.PerformanceSnapshotCacheCheck"],
                                    text=True, capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("performance snapshot cache:", result.stdout)


if __name__ == "__main__":
    unittest.main()
