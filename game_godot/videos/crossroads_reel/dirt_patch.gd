extends "res://videos/crossroads_reel/junction_episodes.gd"

## Episode 024. No signs. The west road is unpaved; only a short asphalt patch
## lies before the junction. A paved road has priority over an unpaved one
## (1.2 «Главная дорога», 13.9): red (north, paved) goes before blue (west, dirt).
const PATCH_END := -9.5
const TURN_C := Vector2(-4.0, -4.0)
const TURN_R := 5.8
var dirt: MeshInstance3D

func actor_count() -> int:return 2

func _build_road() -> void:
	super._build_road()
	# Packed earth with wheel ruts, everywhere west of the short asphalt patch.
	var length:=FAR+PATCH_END;dirt=MeshInstance3D.new();dirt.name="DirtRoad";var box:=BoxMesh.new();box.size=Vector3(length,.02,2*W+.3)
	dirt.mesh=box;dirt.position=Vector3(-FAR+length*.5,.003,0)
	var material:=ShaderMaterial.new();var shader:=Shader.new()
	shader.code="""shader_type spatial;
	varying vec3 world;
	void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
	float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
	float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
	void fragment(){
	float grain=n(world.xz*9.0),clods=n(world.xz*1.7);
	float rut=0.0;
	for(int k=0;k<4;k++){float z=float(k<2?-1:1)*1.8+float(k%2==0?-0.8:0.8);rut+=smoothstep(0.32,0.0,abs(world.z-z));}
	vec3 earth=mix(vec3(0.47,0.36,0.24),vec3(0.62,0.50,0.35),0.55*grain+0.45*clods);
	ALBEDO=earth*(1.0-0.22*clamp(rut,0.0,1.0));
	ROUGHNESS=0.97;
	}
	"""
	material.shader=shader;dirt.material_override=material;add_child(dirt)

func _build_markings() -> void:
	for d in range(9,72,8):
		_paint(0,d+1.4,.12,2.8);_paint(0,-(d+1.4),.12,2.8);_paint(d+1.4,0,2.8,.12)

func _build_traffic_lights() -> void:pass

func blue_entry() -> float:return D+TURN_C.x
func blue_end() -> float:return blue_entry()+TURN_R*PI*.5

func _pose_car(i:int,distance:float) -> Transform3D:
	if i==0:return Transform3D(Basis.IDENTITY,Vector3(-L,0,-D+distance))
	if distance<=blue_entry():return Transform3D(Basis(Vector3.UP,PI*.5),Vector3(-D+distance,0,L))
	if distance<blue_end():
		var a:=(distance-blue_entry())/TURN_R
		return Transform3D(Basis(Vector3.UP,PI*.5+a),Vector3(TURN_C.x+TURN_R*sin(a),0,TURN_C.y+TURN_R*cos(a)))
	return Transform3D(Basis(Vector3.UP,PI),Vector3(L,0,TURN_C.y-(distance-blue_end())))

func turn_finish(i:int) -> float:return blue_end() if i==1 else 0.0

func _hint_range(i:int) -> Vector2:return Vector2(2.8,blue_end()+1.6) if i==1 else Vector2(2.8,5.2)

func is_dirt_dolly(t:float) -> bool:return t>=timings.red+.3 and t<timings.red+2.6

func set_time(t:float) -> void:
	_t=t
	if cars.size()<2:return
	for i in 2:
		var key:String=["red","blue"][i]
		var distance:=_motion(t-float(timings[key])-float(episode.motionDelays[key]))
		if t>=timings.cta:distance=0
		cars[i].transform=_pose_car(i,distance)
		_rig(i,distance,i==1 and distance>blue_entry() and distance<blue_end(),.37)
	signal_insert=is_dirt_dolly(t)
	if t<timings.answer:_overview(t);_cam.size=lerpf(63,60,smoothstep(0,3,t))
	elif signal_insert:
		# Down the dirt approach towards the junction: earth, then the patch.
		var u:=smoothstep(float(timings.red)+.3,float(timings.red)+2.6,t)
		_camera(Vector3(lerpf(-34,-22,u),3.2,4.6),Vector3(lerpf(-14,-4,u),.4,0),46)
	elif t<timings.blue+1.2:_overview(t)
	else:
		var p:=cars[1].position;var f:=cars[1].basis.z.normalized()
		_camera(p-f*8.5+f.cross(Vector3.UP)*3.0+Vector3.UP*8.5,p+Vector3(0,.65,0),55)
	if t>=timings.cta:_overview(t)
	_sign_visibility()

func _overview(t:float) -> void:
	# Shifted west so a long stretch of the dirt approach is in the question.
	var a:=.025*sin(t*.28)
	_camera(Vector3(-5.5+sin(a)*52,54,35.5+cos(a)*2),Vector3(-5.5,0,5.5),48)
	_cam.projection=Camera3D.PROJECTION_ORTHOGONAL;_cam.size=60
