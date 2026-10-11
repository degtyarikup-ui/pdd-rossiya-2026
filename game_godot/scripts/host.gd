## The app around the game (Flutter, android/app/.../game/): the Android plugin
## `PddHost` takes the game's events as JSON. Without it (desktop, the spike APK)
## every call is a no-op and «exit» simply quits.
class_name Host
extends RefCounted


static func embedded() -> bool:
	return Engine.has_singleton("PddHost")


static func send(data: Dictionary) -> void:
	if embedded():
		Engine.get_singleton("PddHost").send(JSON.stringify(data))


## Leaves the game: the app gets the run's summary and closes the game screen.
static func exit(summary: Dictionary, tree: SceneTree) -> void:
	if embedded():
		Engine.get_singleton("PddHost").exit(JSON.stringify(summary))
	else:
		tree.quit()
