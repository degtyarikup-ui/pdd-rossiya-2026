package ru.pdd.pdd_app.game

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/** `Engine.get_singleton("PddHost")` in the game (game_godot/scripts/host.gd). */
class PddHostPlugin(godot: Godot, private val host: GodotGameActivity) : GodotPlugin(godot) {
    override fun getPluginName() = "PddHost"

    /** Whole game-process memory, including engine/native allocations and mapped assets. */
    @UsedByGodot
    fun processMemoryMb(): Int = (android.os.Debug.getPss() / 1024).toInt()

    /** Android thermal status (0–6), sampled with the memory counter, never every frame. */
    @UsedByGodot
    fun thermalState(): Int = if (android.os.Build.VERSION.SDK_INT >= 29) {
        host.getSystemService(android.os.PowerManager::class.java)?.currentThermalStatus ?: -1
    } else -1

    @UsedByGodot
    fun lowPowerMode(): Boolean = host.getSystemService(android.os.PowerManager::class.java)?.isPowerSaveMode ?: false

    /** App-owned external storage lets adb pull retrieve counters without a debug Flutter build. */
    @UsedByGodot
    fun performanceLogDirectory(): String = (host.getExternalFilesDir(null) ?: host.filesDir).absolutePath

    /** The canonical Flutter picture, with no second copy in the Godot assets. */
    @UsedByGodot
    fun pictureBytes(hash: String): ByteArray {
        if (!hash.matches(Regex("[a-f0-9]{32}"))) return byteArrayOf()
        return try {
            host.assets.open("flutter_assets/assets/countries/ru/images/questions_ab/$hash.webp")
                .use { it.readBytes() }
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
        host.runOnUiThread { host.keepSummary(summary) }
    }

    override fun onGodotTerminating() {
        host.runOnUiThread { host.finish() }
    }
}
