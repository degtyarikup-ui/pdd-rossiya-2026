## Traffic Controller rules according to Russian PDD clause 6.10.
## Supports both motor cars and trams ("tram goes sleeve-to-sleeve").
class_name RegulatorRules
extends RefCounted

enum Gesture {
	HANDS_DOWN,
	HANDS_SIDES,
	RIGHT_ARM_FORWARD,
	ARM_UP,
}

enum Approach {
	FRONT,
	BACK,
	LEFT,
	RIGHT,
}

enum Move {
	STRAIGHT,
	RIGHT,
	LEFT,
	UTURN,
	NONE,
}


static func allowed_moves(gesture: Gesture, approach: Approach, vehicle: String = "car") -> Array[Move]:
	# 1. Arm raised straight up: all traffic stops
	if gesture == Gesture.ARM_UP:
		return [Move.NONE]

	# 2. Arms extended sideways or lowered
	if gesture == Gesture.HANDS_SIDES or gesture == Gesture.HANDS_DOWN:
		match approach:
			Approach.LEFT, Approach.RIGHT:
				if vehicle == "tram":
					return [Move.STRAIGHT]
				return [Move.STRAIGHT, Move.RIGHT]
			Approach.FRONT, Approach.BACK:
				return [Move.NONE]

	# 3. Right arm pointed forward
	if gesture == Gesture.RIGHT_ARM_FORWARD:
		match approach:
			Approach.LEFT:
				if vehicle == "tram":
					return [Move.LEFT]
				return [Move.STRAIGHT, Move.RIGHT, Move.LEFT, Move.UTURN]
			Approach.FRONT:
				return [Move.RIGHT]
			Approach.RIGHT, Approach.BACK:
				return [Move.NONE]

	return [Move.NONE]


static func is_move_allowed(gesture: Gesture, approach: Approach, move: Move, vehicle: String = "car") -> bool:
	var allowed := allowed_moves(gesture, approach, vehicle)
	if move == Move.NONE:
		return allowed.has(Move.NONE)
	return allowed.has(move)


static func mnemonic_verse(gesture: Gesture, approach: Approach, vehicle: String = "car") -> String:
	if gesture == Gesture.ARM_UP:
		return Ui.t("gameTrafficHintArmUp")

	if gesture == Gesture.RIGHT_ARM_FORWARD:
		match approach:
			Approach.FRONT:
				return Ui.t("gameTrafficHintForwardFront")
			Approach.RIGHT:
				return Ui.t("gameTrafficHintForwardRight")
			Approach.LEFT:
				if vehicle == "tram":
					return Ui.t("gameTrafficHintTramLeft")
				return Ui.t("gameTrafficHintForwardLeft")
			Approach.BACK:
				return Ui.t("gameTrafficHintBack")

	if gesture == Gesture.HANDS_SIDES or gesture == Gesture.HANDS_DOWN:
		match approach:
			Approach.FRONT:
				return Ui.t("gameTrafficHintWall")
			Approach.BACK:
				return Ui.t("gameTrafficHintBack")
			Approach.LEFT, Approach.RIGHT:
				if vehicle == "tram":
					return Ui.t("gameTrafficHintTramStraight")
				return Ui.t("gameTrafficHintSide")

	return ""


static func gesture_name(g: Gesture) -> String:
	match g:
		Gesture.HANDS_DOWN: return "handsDown"
		Gesture.HANDS_SIDES: return "handsSides"
		Gesture.RIGHT_ARM_FORWARD: return "rightArmForward"
		Gesture.ARM_UP: return "armUp"
	return "handsDown"


static func parse_gesture(s: String) -> Gesture:
	match s:
		"handsDown", "arms_down": return Gesture.HANDS_DOWN
		"handsSides", "arms_sides": return Gesture.HANDS_SIDES
		"rightArmForward", "right_arm_forward": return Gesture.RIGHT_ARM_FORWARD
		"armUp", "arm_up": return Gesture.ARM_UP
	return Gesture.HANDS_DOWN


static func approach_name(a: Approach) -> String:
	match a:
		Approach.FRONT: return "front"
		Approach.BACK: return "back"
		Approach.LEFT: return "left"
		Approach.RIGHT: return "right"
	return "front"


static func parse_approach(s: String) -> Approach:
	match s:
		"front": return Approach.FRONT
		"back": return Approach.BACK
		"left": return Approach.LEFT
		"right": return Approach.RIGHT
	return Approach.FRONT


static func move_name(m: Move) -> String:
	match m:
		Move.STRAIGHT: return "straight"
		Move.RIGHT: return "right"
		Move.LEFT: return "left"
		Move.UTURN: return "uTurn"
		Move.NONE: return "none"
	return "none"


static func parse_move(s: String) -> Move:
	match s:
		"straight": return Move.STRAIGHT
		"right": return Move.RIGHT
		"left": return Move.LEFT
		"uTurn", "uturn": return Move.UTURN
		"none", "stand": return Move.NONE
	return Move.NONE
