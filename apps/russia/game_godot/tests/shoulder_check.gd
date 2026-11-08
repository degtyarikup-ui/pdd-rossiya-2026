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
 # Runtime stitch is inside the crop: its clipped edge must already be grass.
 net.stitch_bindings=[{"port":{"p":Vector3(0,0,20),"out":Vector3.BACK},"surface":"blend"}]
 var st:=SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for surface in net.build.surfaces:
  if surface.id=="rural_shoulder": net._add_field(st,surface,scenery,Transform3D.IDENTITY)
 var arrays:=st.commit().surface_get_arrays(0)
 var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var colours:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
 var checked:=0
 for i in vertices.size():
  if absf(vertices[i].z-20.0)<0.01:
   var grass:=scenery.color("ground")
   assert(Vector3(colours[i].r-grass.r,colours[i].g-grass.g,colours[i].b-grass.b).length()<0.002)
   checked+=1
 assert(checked>0)
 print("PASS runtime stitch edge fades to grass inside saved crop")
 quit()
