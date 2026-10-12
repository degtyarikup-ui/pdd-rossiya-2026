package ru.pdd.pdd_app

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Channel `pdd/godot_game` (Dart: lib/presentation/screens/game/godot_game.dart):
 * `available` — the game's files are in this build; `start(args)` opens the game and
 * answers with the run's summary (JSON) or null when it was left without one.
 *
 * No Godot classes here: a build without the engine (android/godot/ not prepared)
 * leaves game/ out, and the game reports itself unavailable.
 */
class GodotGameBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        const val REQUEST = 4207
        const val GAME_ACTIVITY = "ru.pdd.pdd_app.game.GodotGameActivity"
    }

    private var pending: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, "pdd/godot_game").setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(available())
                "start" -> {
                    if (!available()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    pending?.success(null)
                    pending = result
                    val args = (call.argument<List<String>>("args") ?: emptyList()).toTypedArray()
                    val intent = Intent().setClassName(activity, GAME_ACTIVITY)
                        .putExtra("pdd_game_args", args)
                    activity.startActivityForResult(intent, REQUEST)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun available(): Boolean = try {
        Class.forName(GAME_ACTIVITY)
        // The engine is packed for arm64 only (build.gradle.kts).
        require(android.os.Build.SUPPORTED_ABIS.firstOrNull() == "arm64-v8a")
        activity.assets.open("project.binary").close()
        true
    } catch (_: Exception) {
        false
    }

    /** From MainActivity.onActivityResult; true when it was the game's result. */
    fun onResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val summary = if (resultCode == Activity.RESULT_OK) data?.getStringExtra("pdd_game_summary") else null
        pending?.success(summary)
        pending = null
        return true
    }
}
