## Reduce the phone's GPU work after sustained slow frames. UI resolution stays unchanged.
## Loading/pause intervals are excluded; performance cannot oscillate between quality levels.
extends RefCounted

const WINDOW := 4.0
const MIN_SCALE := 0.65
var elapsed := 0.0
var frames := 0
var scale := 1.0
var shadows := true
var antialias := true
var changes := 0
var capped := false

func reset(render_scale: float, has_shadows: bool, has_antialias: bool) -> void:
	scale = render_scale
	shadows = has_shadows
	antialias = has_antialias
	elapsed = 0.0
	frames = 0
	changes = 0
	capped = false

func sample(delta: float, eligible: bool, target_fps: int) -> Dictionary:
	if not eligible or delta <= 0.0 or delta > 0.25:
		elapsed = 0.0
		frames = 0
		return {}
	elapsed += delta
	frames += 1
	if elapsed < WINDOW: return {}
	var average := elapsed / frames
	elapsed = 0.0
	frames = 0
	# 60 FPS: act below about 48 sustained FPS; low-tier 30 FPS: below about 24.
	if average <= 1.25 / maxi(target_fps, 1): return {}
	if antialias:
		antialias = false
	elif scale > MIN_SCALE + 0.001:
		scale = maxf(MIN_SCALE, snappedf(scale - 0.1, 0.05))
	elif shadows:
		shadows = false
	elif target_fps > 30 and not capped:
		# At the minimum GPU budget, favor a sustainable frame rate on CPU-bound phones.
		capped = true
		changes += 1
		return {"scale": scale, "shadows": shadows, "antialias": antialias, "max_fps": 30}
	else:
		return {}
	changes += 1
	return {"scale": scale, "shadows": shadows, "antialias": antialias}
