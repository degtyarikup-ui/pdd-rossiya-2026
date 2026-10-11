package ru.pdd.pdd_app.game

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Process
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotActivity
import org.godotengine.godot.plugin.GodotPlugin

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
class GodotGameActivity : GodotActivity() {
    companion object {
        const val EXTRA_ARGS = "pdd_game_args"
        const val EXTRA_SUMMARY = "pdd_game_summary"
    }

    private var summary: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Leaving with «back» before the game sent anything is a run without a summary.
        setResult(Activity.RESULT_CANCELED)
    }

    override fun getCommandLine(): MutableList<String> {
        val list = super.getCommandLine().toMutableList()
        val args = intent?.getStringArrayExtra(EXTRA_ARGS) ?: emptyArray()
        if (args.isNotEmpty()) {
            list.add("--")
            list.addAll(args)
        }
        return list
    }

    override fun getHostPlugins(engine: Godot): MutableSet<GodotPlugin> =
        mutableSetOf(PddHostPlugin(engine, this))

    /** The latest summary of the run (also after «run finished»), kept for the result. */
    fun keepSummary(json: String) {
        summary = json
        setResult(Activity.RESULT_OK, Intent().putExtra(EXTRA_SUMMARY, json))
    }

    fun leave(json: String) {
        keepSummary(json)
        finish()
    }

    override fun onGodotForceQuit(instance: Godot) {
        // Godot quit by itself (an error, get_tree().quit()): close the screen, keep the result.
        runOnUiThread { finish() }
    }

    override fun onDestroy() {
        super.onDestroy()
        // A fresh process for the next run: Godot does not restart inside one.
        if (isFinishing) Process.killProcess(Process.myPid())
    }
}
