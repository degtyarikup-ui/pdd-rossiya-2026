## Graphics tiers chosen from the GPU name, with decorative population budgets.
class_name Quality
extends RefCounted

const PROFILES := {
	"low":  { "scale": 0.75, "msaa": Viewport.MSAA_DISABLED, "shadows": false, "max_fps": 30 },
	"mid":  { "scale": 1.0,  "msaa": Viewport.MSAA_DISABLED, "shadows": true,  "max_fps": 60 },
	"high": { "scale": 1.0,  "msaa": Viewport.MSAA_2X,       "shadows": true,  "max_fps": 0 },
}

static func classify(gpu: String) -> String:
	var s := gpu.to_lower()
	var re := RegEx.create_from_string("adreno[^0-9]*([0-9]{3})")
	var m := re.search(s)
	if m:
		var n := int(m.get_string(1))
		if n >= 730 or (n >= 650 and n < 700):
			return "high"
		if n >= 620:
			return "mid"
		return "low"
	if s.contains("immortalis"):
		return "high"
	re = RegEx.create_from_string("mali[^a-z0-9]*-?(g|t)?-?([0-9]{2,4})")
	m = re.search(s)
	if m:
		var n := int(m.get_string(2))
		if m.get_string(1) == "g" and n >= 710:
			return "high"
		if m.get_string(1) == "g" and (n >= 76 or n == 68):
			return "mid"
		return "low"
	if s.contains("apple") or s.contains("xclipse"):
		return "high"
	if s.contains("powervr") or s.contains("vivante"):
		return "low"
	return "mid"


## A name alone does not prove that a phone can sustain desktop quality.
## In particular Godot's Apple adapter name does not distinguish older iPhones.
static func initial(gpu: String, mobile: bool) -> String:
	var tier := classify(gpu)
	return "mid" if mobile and gpu.to_lower().contains("apple") else tier


## Decorative street people only; task participants keep their authored population.
static func ambient_walkers(profile: String, configured: int, max_fps := 0) -> int:
	return mini(configured, 6) if profile == "low" or max_fps == 30 else configured


## Godot's Compatibility renderer lights a scene noticeably brighter while the sun
## casts shadows (measured: about 1.35× on asphalt, pavement and grass, on a desktop
## and on a Pixel 9). Weak phones and the frame budget switch shadows off, which used
## to dim the whole picture. Without shadows the sun and the ambient light are raised
## so the scene keeps its look (within ~10%); the shadowed look is the reference.
const NO_SHADOW_SUN := 2.8
const NO_SHADOW_AMBIENT := 1.15

static func set_sun_shadows(sun: DirectionalLight3D, environment: Environment, enabled: bool) -> void:
	if not sun.has_meta("lit_energy"):
		sun.set_meta("lit_energy", sun.light_energy)
		sun.set_meta("lit_ambient", environment.ambient_light_energy if environment != null else 1.0)
	sun.shadow_enabled = enabled
	sun.light_energy = float(sun.get_meta("lit_energy")) * (1.0 if enabled else NO_SHADOW_SUN)
	if environment != null:
		environment.ambient_light_energy = float(sun.get_meta("lit_ambient")) * (1.0 if enabled else NO_SHADOW_AMBIENT)
