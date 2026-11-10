package ru.pdd.pdd_app.game

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot

/** UI-thread measurements, read by the engine without accessing Android Views. */
class GameInsetsPlugin(godot: Godot, private val host: GodotGameActivity) : GodotPlugin(godot) {
    override fun getPluginName() = "PddInsets"

    @UsedByGodot
    fun bottomDp(): Double = host.safeBottomDp
}
