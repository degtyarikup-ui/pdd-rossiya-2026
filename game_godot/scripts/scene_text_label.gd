## Face the camera while preserving the author's screen-space rotation.
extends Label3D
var text_angle := 0.0
func _process(_delta: float) -> void:
 var camera := get_viewport().get_camera_3d()
 if camera:
  global_basis = camera.global_basis.rotated(camera.global_basis.z, -deg_to_rad(text_angle))
