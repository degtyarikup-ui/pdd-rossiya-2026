## The preloader of the game screens: the app's background and a spinner (the Flutter screens'
## CircularProgressIndicator), over the first frames of a scene, faded out once the scene is up. The road,
## the scenery and the UI are built and shaded in the first seconds, so the screen must not show a blank
## or a half-built frame meanwhile. It takes the touches until it is gone.
class_name Loader
extends CanvasLayer

const FADE := 0.25
const SPINNER := 36.0

var _root: Control


## Puts a loader over the screen of `parent`; the caller calls dismiss() once the scene is ready.
static func attach(parent: Node) -> Loader:
	var loader := Loader.new()
	parent.add_child(loader)
	return loader


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
	tween.tween_callback(queue_free)


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
