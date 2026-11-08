## These metrics are shared with scene3d.js / annotation-text CSS.
extends SceneTree
func _initialize() -> void:
 var annotation = load("res://scripts/scene_annotation.gd")
 for size in [.4,1.0,2.0,4.0]:
  var node: Node3D = annotation.create({"points":[[2,4],[6,8]],"style":"text","text":"3 м","textSize":size})
  var label := node.get_child(0) as Label3D
  assert(label.position.is_equal_approx(Vector3(4,1,6)))
  assert(label.font.resource_path == "res://fonts/Onest-Bold.ttf")
  assert(label.font_size == 64)
  assert(is_equal_approx(label.font.get_height(64),83))
  assert(is_equal_approx(label.pixel_size,.018*size))
  assert(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
  assert(label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER)
  node.free()
 print("PASS text runtime font, centre anchor and world scale")
 quit()
