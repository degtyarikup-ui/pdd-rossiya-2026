extends SceneTree
var checks := 0
var failures := 0
func expect(value: bool,label: String)->void:
	checks+=1
	if not value: failures+=1;push_error(label)
func _initialize()->void: run.call_deferred()
func run()->void:
	for sid: String in ['ticket_8_2','ticket_19_3','ticket_24_5']:
		var sit := Situation.load_scene(sid,Scenery.new('summer'))
		root.add_child(sit)
		var data: Dictionary = sit.network.data.terrain
		var map := sit.ground_map()
		for z in range(-70,71):
			var x := -1.5 if sid!='ticket_19_3' else 0.0
			var p := Vector3(x,0,z)
			if (map.at(p)&GroundMap.ROAD)==0:continue
			expect(absf(map.height_at(p,GroundMap.ROAD)-TerrainProfile.height(data,x,z))<.006,sid+': rendered road height agrees with driving height '+str(z))
		var arrow := RouteArrow.new()
		arrow.build(Situation._smooth([[-1.5,-15],[-1.5,0],[-1.5,15]]),Color.WHITE,true,data)
		var vertices: PackedVector3Array = arrow.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		expect(vertices.size()>20,'route has actual ribbon geometry')
		expect(Array(vertices).all(func(p):return absf(p.y-Situation.GUIDE_LIFT-TerrainProfile.height(data,p.x,p.z))<.001),sid+': route ribbon follows terrain')
		arrow.free()
		var junction := Junction.new(sit)
		var player := Drive.new();player.pos=sit.network.stop_point();player.yaw=sit.network.stop_yaw()
		for motion in junction.motions:
			var expected := TerrainProfile.placement(data,motion.pos.x,motion.pos.z,motion.yaw,motion.hl*.65)
			expect(absf(motion.node.position.y-expected.x)<.02,sid+': posed actor grounded')
		junction.release()
		for frame in 600: junction.update_actors(1.0/60.0,player.footprint(),0)
		for motion in junction.motions:
			expect(motion.distance>20,sid+': actor leaves across grade')
			var expected := TerrainProfile.placement(data,motion.pos.x,motion.pos.z,motion.yaw,motion.hl*.65)
			expect(absf(motion.node.position.y-expected.x)<.02,sid+': moving actor follows grade')
		if sid=='ticket_24_5':
			expect(absf(map.height_at(Vector3(0,0,3.8),GroundMap.ROAD)-.08)<.002,'bump is a physical 8 cm surface')
			expect(absf(map.height_at(Vector3(0,0,1.9),GroundMap.ROAD))<.002,'bump starts at original road height')
			var up := TerrainProfile.placement(data,0,2.5,0,.5)
			var down := TerrainProfile.placement(data,0,5.0,0,.5)
			expect(up.y<0 and down.y>0,'body pitch changes on bump entry and exit')
		sit.free();Situation.forget(sid)
	print('Terrain rendered ground/vehicle poses: ',checks,' checks, ',failures,' failures')
	quit(0 if failures==0 else 1)
