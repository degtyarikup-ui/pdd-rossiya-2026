extends SceneTree
var failures := 0
var checks := 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: run.call_deferred()
func lit(head: Node3D, role: String) -> bool:
	var aperture := head.find_child("aperture_"+role,true,false) as MeshInstance3D
	return bool((aperture.material_override as ShaderMaterial).get_shader_parameter("lit"))
func run() -> void:
	var old := TrafficSignal.make({})
	expect(old.position == Vector3.ZERO,"legacy origin")
	expect(old.find_child("lamp_green",true,false).position == Vector3(0,2.95,.46),"legacy green anchor")
	expect(old.find_child("cantilever_post",true,false)==null,"legacy mast preserved")
	old.free()
	for state in ["off","red","green","yellow_left","yellow_right"]:
		var config := {"reversible":state,"mount":"cantilever","reach":7.5,"clearance":6.0,"armSide":"left"}
		var saved := JSON.stringify(config)
		expect(TrafficSignal.supports(config),"runtime selects shared model "+state)
		var assembly := TrafficSignal.make(config)
		var head := TrafficSignal.in_assembly(assembly)
		expect(head.position.is_equal_approx(Vector3(-7.5,3.4,0)),"reverse height and left reach "+state)
		var body := head.find_child("body",true,false) as MeshInstance3D
		expect(is_equal_approx(body.get_aabb().position.y,2.6),"head has no mast")
		for role in ["red","green","yellow_left","yellow_right"]:
			expect(lit(head,"reverse_"+role)==(role==state),"only selected lamp shines "+state+"/"+role)
		TrafficSignal.set_state(assembly,"green")
		expect(str(head.get_meta("reversible"))==state,"main cycle preserves lane signal")
		expect(JSON.stringify(config)==saved,"config untouched")
		assembly.free()
	var ordinary := TrafficSignal.make({"mount":"cantilever","armSide":"right","reach":6.25,"pedestrianSections":{"left":"off","right":"on"},"arrow":"left"})
	var head := TrafficSignal.in_assembly(ordinary)
	expect(head.position.is_equal_approx(Vector3(6.25,5.5-1.745,0)),"clearance includes lower pedestrian panel")
	expect(lit(head,"info_right") and not lit(head,"info_left"),"panels stay independent overhead")
	var mounted := RoadBuild.light_with_signs(ordinary,["2.4","8.13"],[],{"mount":"cantilever"})
	expect(ordinary.position==Vector3.ZERO,"signs do not lift roadside console off ground")
	expect(TrafficSignal.in_assembly(mounted)==head,"runtime finds head inside mounted assembly")
	TrafficSignal.set_state(head,"red")
	expect(lit(head,"red"),"ordinary overhead changes main colour")
	mounted.free()
	var tram := TrafficSignal.make({"mount":"cantilever","tram":"straight"})
	var tram_head := TrafficSignal.in_assembly(tram)
	expect(is_equal_approx(tram_head.position.y,5.5-1.91),"tram height covers lower control box")
	tram.free()
	var pole := TrafficSignal.make({"reversible":"red"})
	expect(TrafficSignal.in_assembly(pole).position==Vector3.ZERO,"reverse pole head origin")
	expect(pole.find_child("signal_mount_rod",true,false)!=null,"reverse pole support")
	pole.free()
	print("Signal mounts: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
