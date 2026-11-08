## Permission and precedence are separate: a prohibited signal never becomes
## permission just because the other participants have left the junction.
class_name CrossroadsRules
extends RefCounted

static func officer_approach(scenario: Dictionary, side: String) -> RegulatorRules.Approach:
	var officer: Dictionary = scenario.get("officer", {})
	var approach_yaw: float = {"front": 0.0, "back": PI, "left": -PI * 0.5, "right": PI * 0.5}.get(officer.get("approach", "front"), 0.0)
	var direction: Vector3 = {"south": Vector3.BACK, "north": Vector3.FORWARD, "east": Vector3.RIGHT, "west": Vector3.LEFT}.get(side, Vector3.ZERO)
	var local := direction.rotated(Vector3.UP, -float(officer.get("yaw", 0.0)) - approach_yaw)
	if local.z > 0.5: return RegulatorRules.Approach.FRONT
	if local.z < -0.5: return RegulatorRules.Approach.BACK
	return RegulatorRules.Approach.LEFT if local.x > 0.0 else RegulatorRules.Approach.RIGHT

static func officer_gesture(scenario: Dictionary) -> RegulatorRules.Gesture:
	return {"hands_down": RegulatorRules.Gesture.HANDS_DOWN, "hands_sides": RegulatorRules.Gesture.HANDS_SIDES,
		"right_arm_forward": RegulatorRules.Gesture.RIGHT_ARM_FORWARD, "arm_up": RegulatorRules.Gesture.ARM_UP}.get(
		scenario.get("officer", {}).get("gesture", "hands_sides"), RegulatorRules.Gesture.HANDS_SIDES)

static func movement_allowed(scenario: Dictionary, actor: Dictionary) -> bool:
	if scenario.has("officer"):
		# PDD 3.1 explicitly excludes the officer's signals from emergency exemptions.
		return RegulatorRules.is_move_allowed(officer_gesture(scenario), officer_approach(scenario, str(actor.get("side", ""))),
			RegulatorRules.parse_move(str(actor.get("maneuver", ""))), str(actor.get("type", "car")))
	if actor.get("hasSiren", false) or actor.get("type", "") == "pedestrian": return true
	for signal_data in scenario.get("trafficLights", []):
		if signal_data.get("side", "") != actor.get("side", ""): continue
		if signal_data.get("state", "") in ["red", "yellow", "red_yellow"]:
			return signal_data.get("arrowActive", false) and signal_data.get("arrow", "") == actor.get("maneuver", "")
	return true

static func must_yield(scenario: Dictionary, actor: Dictionary, other: Dictionary) -> bool:
	if actor.get("id", "") == other.get("id", "") or not movement_allowed(scenario, other): return false
	# Partial precedence, rather than an arbitrary single correct permutation.
	if scenario.has("yieldTo"):
		return scenario.yieldTo.get(actor.get("id", ""), []).has(other.get("id", ""))
	if scenario.has("officer"):
		return other.get("type", "") == "tram" and actor.get("type", "") != "tram"
	# The older authored lessons have a certified unique order (Dart rules solver).
	return int(other.get("order", 99)) < int(actor.get("order", 99))
