extends SceneTree

func vertices(tr: Dictionary) -> PackedVector3Array:
	var sit := Situation.new()
	sit.data = {"trajectories":[tr]}
	var guide := sit._trajectory_guide()
	var result: PackedVector3Array = guide.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	guide.free();sit.free()
	return result

func _initialize() -> void:
	for length in [1.0,8.0]:
		var line := vertices({"label":"А","points":[[0,0],[0,length]],"arrowhead":false})
		var lo := INF;var hi := -INF
		for p in line:
			assert(absf(p.x)<=Situation.GUIDE_WIDTH*.5+.001,"No triangular arrow on a plain line")
			lo=minf(lo,p.z);hi=maxf(hi,p.z)
		assert(lo<0 and hi>length,"Both full-length endpoints have round caps")
	var old := vertices({"label":"Б","points":[[0,0],[0,8]]})
	var explicit := vertices({"label":"Б","points":[[0,0],[0,8]],"arrowhead":true})
	assert(old==explicit,"Old trajectories retain their arrow")
	var wide := false
	for p in old:
		if absf(p.x)>Situation.GUIDE_WIDTH: wide=true
	assert(wide,"Default arrow remains visible")
	print("Choice lines: full-length short/long lines, round caps and legacy arrows PASS")
	quit()
