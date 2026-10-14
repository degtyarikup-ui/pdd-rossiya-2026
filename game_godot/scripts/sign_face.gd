## Official SVGs include padding, and four catalogue images include several examples.
## Keep their original layout slots; render the first complete individual panel without stretching.
class_name SignFace
extends RefCounted

static var _regions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://signs/face_regions.json"))
static var _layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://signs/face_layout.json"))
static var _textures := {}
static var _materials := {}
static var _dynamic_materials := {}
static var _quads := {}
static var _white: ImageTexture

static func texture(code: String) -> Texture2D:
	if not _textures.has(code):
		var source:=load("res://signs/%s.svg" % code) as Texture2D
		if source==null: return null
		if _regions.has(code):
			var r: Array=_regions[code]
			var atlas:=AtlasTexture.new()
			atlas.atlas=source
			var size: Array=_layout[code].sourceSize
			var sx: float=float(source.get_width())/size[0]
			var sy: float=float(source.get_height())/size[1]
			atlas.region=Rect2(r[0]*sx,r[1]*sy,r[2]*sx,r[3]*sy)
			atlas.filter_clip=true
			_textures[code]=atlas
		else: _textures[code]=source
		_textures[code].set_meta("sign_code",code)
		_textures[code].set_meta("canvas_size",Vector2(_regions[code][2],_regions[code][3]) if _regions.has(code) else Vector2(_layout[code].sourceSize[0],_layout[code].sourceSize[1]))
	return _textures[code]

static func legacy_size(code: String,width: float) -> Vector2:
	return Vector2(width,legacy_height(code,width))

static func legacy_height(code: String,width: float) -> float:
	var size: Array=_layout[code].sourceSize
	return width*float(size[1])/size[0]

static func fit(tex: Texture2D,slot: Vector2) -> Vector2:
	var size: Vector2=tex.get_meta("canvas_size",Vector2(tex.get_width(),tex.get_height()))
	return size*minf(slot.x/size.x,slot.y/size.y)

static func white() -> ImageTexture:
	if _white==null:
		var image:=Image.create(1,1,false,Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white=ImageTexture.create_from_image(image)
	return _white

static func picture(tex: Texture2D,at: Vector3,size: Vector2) -> MeshInstance3D:
	var face:=MeshInstance3D.new()
	face.position=at
	face.rotation.y=PI
	var mesh_key:=str(size)
	if not _quads.has(mesh_key):
		var quad:=QuadMesh.new()
		quad.size=size
		_quads[mesh_key]=quad
	face.mesh=_quads[mesh_key]
	# AtlasTexture is resolved explicitly for custom shaders (the original SVG is shared).
	var region:=Vector4(0,0,1,1)
	var image:=tex
	if tex is AtlasTexture:
		image=tex.atlas
		var full:=Vector2(image.get_width(),image.get_height())
		region=Vector4(tex.region.position.x/full.x,tex.region.position.y/full.y,tex.region.size.x/full.x,tex.region.size.y/full.y)
	var key:=str(image.get_instance_id())+str(region)
	var cache: Dictionary=_dynamic_materials if image is ImageTexture else _materials
	var limit:=16 if image is ImageTexture else 96
	if not cache.has(key):
		if cache.size()>=limit: cache.erase(cache.keys()[0])
		var material:=ShaderMaterial.new()
		material.shader=preload("res://shaders/sign_face.gdshader")
		material.set_shader_parameter("picture",image)
		material.set_shader_parameter("face_region",region)
		# Analytic silhouettes avoid magnifying the SVG raster's staircase/alpha holes.
		var code: String=tex.get_meta("sign_code",tex.resource_path.get_file().get_basename())
		var box:=Vector4(0,0,1,1)
		if _layout.has(code):
			var r: Array=_layout[code].outline
			box=Vector4(r[0],r[1],r[2],r[3])
		var canvas: Vector2=tex.get_meta("canvas_size",Vector2(tex.get_width(),tex.get_height()))
		material.set_shader_parameter("outline_rect",box)
		material.set_shader_parameter("outline_shape",outline_shape(code,tex is ImageTexture))
		material.set_shader_parameter("outline_aspect",canvas.x*box.z/(canvas.y*box.w))
		material.set_shader_parameter("corner_radius",float(tex.get_meta("corner_radius",0.0)) if tex is ImageTexture else .10)
		cache[key]=material
	face.material_override=cache[key]
	face.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return face

static func outline_shape(code: String,dynamic: bool=false) -> int:
	if dynamic:return 3
	if code in ["2.1","2.2"]:return 2
	if code=="2.4":return 5
	if code=="2.5":return 6
	if code.begins_with("3.") or code.begins_with("4."):return 1
	if code.begins_with("1.3."):return 0 # Saint Andrew's crosses have their own silhouette.
	if code.begins_with("1.4.") or code=="1.34.3":return 3
	if code.begins_with("1.") or code.begins_with("2.3."):return 4
	return 3
