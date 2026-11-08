## The local cover protects construction and shader warmup. Embedded Android/web hosts play the
## shared animated WebP above it; standalone Godot keeps this small ring as a fallback. Explicit
## Host.loading state releases the host only after the cover is gone and a real frame is presented.
class_name Loader
extends CanvasLayer

const FADE := 0.25
const SPINNER := 36.0

var _root: Control


## Puts a loader over the screen of `parent`; the caller calls dismiss() once the scene is ready.
static func attach(parent: Node) -> Loader:
	var loader := Loader.new()
	parent.add_child(loader)
	if Host.embedded():
		var plugin: Object = Engine.get_singleton("PddHost")
		if plugin.has_signal("cancel_loading"):
			plugin.connect("cancel_loading", loader._cancel_loading)
	Host.loading(true)
	return loader


func _cancel_loading() -> void:
	if not is_inside_tree() or Host.is_exiting(get_tree()): return
	var scene := get_parent()
	if scene.has_method("_on_exit"):
		scene.call_deferred("_on_exit")
	elif scene.has_method("_on_exit_pressed"):
		scene.call_deferred("_on_exit_pressed")


func _init() -> void:
	layer = 100
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Ui.c("background")
	_root.add_child(background)

	var spinner := Spinner.new()
	spinner.set_anchors_preset(Control.PRESET_CENTER)
	spinner.offset_left = -SPINNER / 2.0
	spinner.offset_right = SPINNER / 2.0
	spinner.offset_top = -SPINNER / 2.0
	spinner.offset_bottom = SPINNER / 2.0
	_root.add_child(spinner)


## Fades the loader out, then frees it. It stops taking the touches at once.
func dismiss() -> void:
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE)
	tween.tween_callback(_finish_dismiss)


func _finish_dismiss() -> void:
	_root.visible = false
	# The Android/web cover must never uncover the preceding spinner or an unshaded scene.
	# Present one frame with this Godot cover gone, then let the host release its WebP decoder.
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	if not is_inside_tree() or is_queued_for_deletion() or Host.is_exiting(get_tree()): return
	Host.loading(false)
	queue_free()


## An indeterminate ring: a 3/4 arc turning, stroke 4 like the app's spinner.
class Spinner extends Control:
	const TURN := 1.2
	const STROKE := 4.0
	var _angle := 0.0

	func _process(delta: float) -> void:
		_angle = fmod(_angle + delta * TAU * TURN, TAU)
		queue_redraw()

	func _draw() -> void:
		var radius := minf(size.x, size.y) / 2.0 - STROKE / 2.0
		draw_arc(size / 2.0, radius, _angle, _angle + PI * 1.5, 48, Ui.c("accent"), STROKE, true)
