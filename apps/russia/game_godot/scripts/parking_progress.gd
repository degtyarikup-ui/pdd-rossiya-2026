## Stars of «Парковка»: one to three per level, the best result kept. Levels go in catalogue
## order and a level opens once the one before it has at least one star. The app owns the
## record (`--stars=3,2,0,…` in, `stars` of the session summary out) and syncs it with the account.
class_name ParkingProgress
extends RefCounted

const MAX_STARS := 3

var stars: Array[int] = []


func _init(count := ParkingLevels.COUNT) -> void:
	stars.resize(count)
	stars.fill(0)


## "3,2,0,1": missing levels are unplayed, anything out of range is clamped.
static func parse(text: String, count := ParkingLevels.COUNT) -> ParkingProgress:
	var progress := ParkingProgress.new(count)
	var parts := text.split(",", false)
	for i in mini(count, parts.size()):
		progress.stars[i] = clampi(int(parts[i]), 0, MAX_STARS)
	return progress


## A level is finished with as many stars as lives are left: three lives, a touch costs one.
static func rating(lives_left: int) -> int:
	return clampi(lives_left, 0, MAX_STARS)


func count() -> int:
	return stars.size()


func total() -> int:
	var sum := 0
	for value in stars: sum += value
	return sum


func unlocked(index: int) -> bool:
	if index < 0 or index >= stars.size(): return false
	return index == 0 or stars[index - 1] > 0


## The level to play next: the first open one without a star, or the last when all are done.
func current() -> int:
	for i in stars.size():
		if stars[i] == 0: return i
	return stars.size() - 1


func completed() -> bool:
	return not stars.has(0)


## Keeps the best result. Returns true when it is a new best for the level.
func record(index: int, earned: int) -> bool:
	if index < 0 or index >= stars.size(): return false
	earned = clampi(earned, 0, MAX_STARS)
	if earned <= stars[index]: return false
	stars[index] = earned
	return true


func to_array() -> Array:
	return Array(stars)
