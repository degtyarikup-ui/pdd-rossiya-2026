extends SceneTree
func _initialize():
 var net := RoadNetwork.new()
 net.data={"roads":[],"routes":[]}
 net.build=JSON.parse_string(FileAccess.get_file_as_string("res://../scratch/shoulder.json"))
 var scenery:=Scenery.new("summer")
 var mesh:=net.surface_mesh(scenery)
 var ground:=GroundMap.new(mesh,scenery)
 for x in [-6.0,-5.0,5.0,6.0]:
  assert((ground.at(Vector3(x,0,0)) & GroundMap.WALK)==0)
  assert(not is_finite(ground.walk_height(Vector3(x,0,0))))
 assert((ground.at(Vector3(0,0,0)) & GroundMap.ROAD)!=0)
 print("PASS actual Godot shoulder mesh excludes pedestrian navigation")
 quit()
