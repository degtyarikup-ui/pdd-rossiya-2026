## State of one run (game_controller.dart GameState): 10 questions, score by
## streak (GameEconomy.city), violations, distance. Pure data, no nodes.
class_name Run
extends RefCounted

const QUESTIONS := 10

var answered := 0
var correct := 0
var mistakes: Array[String] = []   # situation ids answered wrong
var answer_log: Array[Dictionary] = [] # canonical scene, result, original answer time
var streak := 0
var score := 0
var violations := 0
var distance_m := 0


## GameEconomy.city / crossroads: 40 + 2 per streak step (max +10).
static func points_for(streak_count: int) -> int:
	return 40 + clampi(streak_count - 1, 0, 5) * 2


func answer(situation_id: String, is_correct: bool) -> void:
	var stamp := int(Time.get_unix_time_from_system() * 1000.0)
	if not answer_log.is_empty(): stamp = maxi(stamp, int(answer_log.back().answeredAt) + 1)
	answer_log.append({"situation": situation_id, "correct": is_correct, "answeredAt": stamp})
	answered += 1
	if is_correct:
		streak += 1
		correct += 1
		score += points_for(streak)
	else:
		streak = 0
		mistakes.append(situation_id)


func finished() -> bool:
	return answered >= QUESTIONS


func summary() -> Dictionary:
	return { "answered": answered, "correct": correct, "mistakes": mistakes, "score": score,
		"violations": violations, "distance_m": distance_m, "streak": streak,
		"answer_log": answer_log.duplicate(true) }


## Continues a run left in the middle (the app keeps its progress): the counters as they were.
func restore(saved: Dictionary) -> void:
	answered = int(saved.get("answered", 0))
	correct = int(saved.get("correct", 0))
	score = int(saved.get("score", 0))
	streak = int(saved.get("streak", 0))
	violations = int(saved.get("violations", 0))
	distance_m = int(saved.get("distance_m", 0))
	mistakes.assign(saved.get("mistakes", []))
	answer_log.assign(saved.get("answer_log", []))
