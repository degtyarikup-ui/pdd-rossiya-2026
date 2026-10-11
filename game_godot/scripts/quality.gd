## Quality tiers, chosen from the GPU name (same table as assets/game/quality-tier.js).
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
