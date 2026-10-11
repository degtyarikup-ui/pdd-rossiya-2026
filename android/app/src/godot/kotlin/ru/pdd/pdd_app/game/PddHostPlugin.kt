package ru.pdd.pdd_app.game

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/** `Engine.get_singleton("PddHost")` in the game (game_godot/scripts/host.gd). */
class PddHostPlugin(godot: Godot, private val host: GodotGameActivity) : GodotPlugin(godot) {
    override fun getPluginName() = "PddHost"

    /** Any event of the game; «run_finished» carries the final summary. */
    @UsedByGodot
    fun send(json: String) {
        if (json.contains("\"run_finished\"")) {
            val summary = org.json.JSONObject(json).optJSONObject("summary")?.toString() ?: return
            host.runOnUiThread { host.keepSummary(summary) }
        }
    }

    /** The player leaves the game: the summary goes back to the app. */
    @UsedByGodot
    fun exit(summary: String) {
        host.runOnUiThread { host.leave(summary) }
    }
}
