## Cache internal road profiles without changing public values, geometry or prop placement.
extends SceneTree
var checks := 0
var failed := 0
class OracleStreet extends Street:
	func _road_profile_at(z: float) -> Dictionary: return profile_at(z)
func _initialize() -> void: run.call_deferred()
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1; print("FAIL ",label)
func run() -> void:
	var holder := Node3D.new(); root.add_child(holder)
	var scenery := Scenery.new("autumn")
	var cached := Street.new(holder,scenery,60.0,1)
	var oracle := OracleStreet.new(holder,scenery,60.0,1)
	var ordinary := {"width":8.4,"lanes":2,"walk":true,"edge":true,"centre":"dashed","surface":"asphalt"}
	var avenue := {"width":14.0,"lanes":4,"walk":true,"edge":true,"centre":"double","surface":"asphalt"}
	var highway := {"width":22.4,"lanes":6,"median":1.2,"walk":false,"edge":true,"centre":"solid","surface":"asphalt"}
	var dirt := {"width":10.4,"lanes":2,"walk":false,"edge":false,"centre":"dashed","surface":"sand"}
	var cases := [{"profile":{}},{"profile":ordinary},{"profile":avenue},{"profile":highway},{"profile":dirt},
		{"profile":ordinary,"connector":{"from":ordinary,"to":avenue,"start":-30.0,"end":60.0}},
		{"profile":highway,"connector":{"from":highway,"to":dirt,"start":0.0,"end":90.0}}]
	for case_index in cases.size():
		var data: Dictionary = cases[case_index]
		for street in [cached,oracle]:
			street.profile = data.profile.duplicate(true)
			street.connector = data.get("connector",{}).duplicate(true)
		for z in [-80.0,-30.0,0.0,15.25,60.0,100.0]:
			expect(cached.half_width_at(z) == float(cached.profile_at(z).width) * 0.5, "direct width matches full profile exactly " + str(case_index) + "/" + str(z))
		for index in [-1,0,1]:
			var a := cached.build_chunk(0,index,false,Callable(),[[0.0,23.25],[31.5,60.0]])
			var b := oracle.build_chunk(0,index,false,Callable(),[[0.0,23.25],[31.5,60.0]])
			expect(a.get_surface_count() == b.get_surface_count(), "surface count " + str(case_index))
			for surface in a.get_surface_count():
				expect(a.surface_get_arrays(surface) == b.surface_get_arrays(surface), "all raw road attributes exact " + str(case_index) + "/" + str(index))
				expect(a.surface_get_material(surface) == b.surface_get_material(surface), "material preserved")
			for prop in cached.pools:
				expect(cached.pools[prop].transforms == oracle.pools[prop].transforms and cached.pools[prop].tints == oracle.pools[prop].tints, "same prop poses/seasonal colour " + prop)
			expect(cached.parked_spots == oracle.parked_spots and cached.parked_bodies == oracle.parked_bodies, "same parked collision footprints")
			expect(not cached._profile_build_active and cached._build_profiles.is_empty() and cached._constant_build_profile.is_empty(), "cache cleared after chunk")
		cached._begin_profile_build()
		var expected := cached.profile_at(0.0)
		var internal := cached._road_profile_at(0.0)
		var public := cached.profile_at(0.0)
		expect(internal.is_read_only() and not public.is_read_only(), "cached profiles enforce read-only while public profiles remain mutable")
		public.width = -999.0
		expect(internal == expected and cached.profile_at(0.0) == expected, "public mutations cannot corrupt internal cached profiles")
		for i in 1000: cached._road_profile_at(i * 0.123)
		expect(cached._build_profiles.size() <= cached.PROFILE_CACHE_LIMIT, "per-build cache bounded")
		cached._end_profile_build()
		cached.build_chunk(0,0,true)
		expect(not cached._profile_build_active and cached._build_profiles.is_empty() and cached._constant_build_profile.is_empty(), "blank chunk clears profile cache")
	holder.free()
	print("street profile cache: ",checks," checks, ",failed," failures")
	quit(1 if failed else 0)
