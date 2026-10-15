package ru.pdd.pdd_app.game

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Process
import android.util.Log
import android.view.View
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import androidx.activity.OnBackPressedCallback
import androidx.fragment.app.FragmentActivity
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotFragment
import org.godotengine.godot.GodotHost
import org.godotengine.godot.plugin.GodotPlugin
import ru.pdd.pdd_app.R
import java.io.DataInputStream

/**
 * The 3D game «Живой город» (Godot, game_godot/) on its own screen.
 *
 * Runs in the separate process `:game` (AndroidManifest.xml): Godot cannot be
 * started twice in one process, and its shutdown ends the process — the app's
 * Flutter process must not be touched by either. The game's files are the
 * exported project in the APK's assets (scripts/godot_android_assets.sh).
 *
 * In: [EXTRA_ARGS] — the game's command line (`--lang=ru`, `--dark`, ...).
 * Out: RESULT_OK with [EXTRA_SUMMARY] — the run's JSON summary (run.gd), set by
 * [PddHostPlugin] when the player leaves.
 */
class GodotGameActivity : FragmentActivity(), GodotHost {
    companion object {
        const val EXTRA_ARGS = "pdd_game_args"
        const val EXTRA_SUMMARY = "pdd_game_summary"
    }

    private var summary: String? = null
    private var fragment: GodotFragment? = null
    private var hostPlugin: PddHostPlugin? = null
    private var loaderProfiler: LoaderFrameProfiler? = null
    private var loadingPhase = "loading"
    private lateinit var surface: FrameLayout
    private lateinit var loader: MascotLoadingOverlay
    private val arguments by lazy { intent?.getStringArrayExtra(EXTRA_ARGS)?.toList() ?: emptyList() }
    private var engineMounted = false
    private var closing = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // GodotActivity initializes the engine synchronously in super.onCreate. Embed its
        // standard fragment directly so Android presents the loader before that work starts.
        // This isolated process always starts a fresh run, never a restored engine fragment.
        super.onCreate(null)
        // Leaving with «back» before the game sent anything is a run without a summary.
        setResult(Activity.RESULT_CANCELED)
        val content = FrameLayout(this)
        surface = FrameLayout(this).apply { id = View.generateViewId() }
        content.addView(surface, FrameLayout.LayoutParams(-1, -1))
        loader = MascotLoadingOverlay(this, "--dark" in arguments, "--reduce-motion" in arguments)
        content.addView(loader, FrameLayout.LayoutParams(-1, -1))
        setContentView(content)
        if ("--loader-profile" in arguments && android.os.Build.VERSION.SDK_INT >= 24) {
            loaderProfiler = LoaderFrameProfiler(window).also { it.start(loadingPhase) }
        }
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = handleGameBack()
        })
        loader.show(argument("--loading-label"))
        loader.viewTreeObserver.addOnDrawListener(object : ViewTreeObserver.OnDrawListener {
            private var dispatched = false
            override fun onDraw() {
                if (dispatched) return
                dispatched = true
                Log.i("PddLoader", "first loader draw before engine initialization")
                loader.post {
                    if (loader.viewTreeObserver.isAlive) loader.viewTreeObserver.removeOnDrawListener(this)
                    // Let the already-recorded loader reach the screen before the engine's
                    // UI-thread initialization. The cover stays until the game's draw signal.
                    loader.postOnAnimation { mountEngine() }
                }
            }
        })
    }

    private fun mountEngine() {
        if (engineMounted || closing || isFinishing || isDestroyed) return
        engineMounted = true
        Log.i("PddLoader", "engine initialization started")
        val game = GodotFragment()
        fragment = game
        supportFragmentManager.beginTransaction().replace(surface.id, game)
            .setPrimaryNavigationFragment(game).commitNowAllowingStateLoss()
    }

    override fun getCommandLine(): MutableList<String> {
        val list = try {
            // Godot's exporter writes little-endian lengths followed by UTF-8 arguments.
            // Its Kotlin parser is engine-internal, so use the small public file format.
            DataInputStream(assets.open("_cl_")).use { input ->
                val count = Integer.reverseBytes(input.readInt())
                if (count !in 0..4096) throw java.io.IOException("Invalid Godot argument count")
                MutableList(count) {
                    val length = Integer.reverseBytes(input.readInt())
                    if (length !in 0..65535) throw java.io.IOException("Invalid Godot argument length")
                    val bytes = ByteArray(length)
                    input.readFully(bytes)
                    String(bytes, Charsets.UTF_8)
                }
            }
        } catch (_: java.io.IOException) { mutableListOf() }
        if (arguments.isNotEmpty()) {
            list.add("--")
            list.addAll(arguments)
        }
        return list
    }

    override fun getHostPlugins(engine: Godot): MutableSet<GodotPlugin> {
        val plugin = PddHostPlugin(engine, this)
        hostPlugin = plugin
        return mutableSetOf(plugin)
    }

    override fun getActivity(): Activity = this

    override fun getGodot(): Godot? = fragment?.godot

    private fun argument(name: String): String =
        arguments.firstOrNull { it.startsWith("$name=") }?.substringAfter('=') ?: ""

    /** The game sends ready only after its playable scene has actually been rendered. */
    fun setLoading(visible: Boolean, phase: String) {
        if (!::loader.isInitialized || closing) return
        if (visible) {
            loadingPhase = phase
            loader.show(argument(if (phase == "returning") "--returning-label" else "--loading-label"))
            loaderProfiler?.start(loadingPhase)
        } else {
            loader.hide()
            loaderProfiler?.stop()
            Log.i("PddLoader", "playable frame ready; loader released")
        }
    }

    /** The latest summary of the run (also after «run finished»), kept for the result. */
    fun keepSummary(json: String) {
        summary = json
        setResult(Activity.RESULT_OK, Intent().putExtra(EXTRA_SUMMARY, json))
    }

    fun leave(json: String) {
        keepSummary(json)
        finish()
    }

    /** Keep Surface destruction behind the same native mascot; Godot owns safe termination. */
    fun prepareExit() {
        loadingPhase = "returning"
        if (::loader.isInitialized) loader.show(argument("--returning-label"))
        loaderProfiler?.start(loadingPhase)
    }

    override fun finish() {
        if (closing) return
        closing = true
        prepareExit()
        super.finish()
        // No slide/scale of the road or the Flutter menu while the game process stops.
        @Suppress("DEPRECATION")
        overridePendingTransition(R.anim.godot_game_return_in, R.anim.godot_game_return_out)
    }

    override fun onGodotForceQuit(instance: Godot) {
        // Godot quit by itself (an error, get_tree().quit()): close the screen, keep the result.
        runOnUiThread { finish() }
    }

    override fun onResume() {
        super.onResume()
        if (::loader.isInitialized) loader.setForeground(true)
        if (::loader.isInitialized && loader.visibility == View.VISIBLE) loaderProfiler?.start(loadingPhase)
    }

    override fun onPause() {
        if (::loader.isInitialized) loader.setForeground(false)
        loaderProfiler?.stop()
        super.onPause()
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        fragment?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        fragment?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun handleGameBack() {
        if (closing) return
        if (::loader.isInitialized && loader.visibility == View.VISIBLE && engineMounted) {
            // A paused game menu would be hidden beneath the native startup cover.
            // Ask the loading scene to leave through Host.exit instead of detaching its Surface.
            hostPlugin?.requestLoadingCancel()
            return
        }
        // Godot dispatches NOTIFICATION_WM_GO_BACK_REQUEST after its main loop begins.
        if (fragment?.godot?.isInitialized() == true) fragment?.onBackPressed() else finish()
    }

    override fun onDestroy() {
        if (::loader.isInitialized) loader.close()
        loaderProfiler?.close()
        super.onDestroy()
        // A fresh process for the next run: Godot does not restart inside one.
        if (isFinishing) Process.killProcess(Process.myPid())
    }
}
