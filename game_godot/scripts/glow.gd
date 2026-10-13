## Light a phone can read from a distance: emissive lamps and soft halos. Plain shapes with an additive
## radial texture, no post-processing: cheap on the Compatibility renderer.
class_name Glow
extends RefCounted

static var _radial: ImageTexture


## A soft round falloff (white, alpha 1 in the middle, 0 at the rim), made once.
static func radial() -> ImageTexture:
	if _radial == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var mid := Vector2(n / 2.0, n / 2.0)
		for y in n:
			for x in n:
				var d := clampf(1.0 - Vector2(x + 0.5, y + 0.5).distance_to(mid) / mid.x, 0.0, 1.0)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, d * d * (3.0 - 2.0 * d)))
		_radial = ImageTexture.create_from_image(img)
	return _radial


## A soft disc of `colour`, `size` metres across, always facing the camera.
static func halo(colour: Color, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = colour
	m.albedo_texture = radial()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A lamp: bright and emissive when lit, the dark tone otherwise.
static func lamp_material(colour: Color, dark: Color, lit: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour if lit else dark
	if lit:
		m.emission_enabled = true
		m.emission = colour
		m.emission_energy_multiplier = 4.0
	return m
