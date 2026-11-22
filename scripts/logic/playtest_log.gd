class_name PlaytestLog
extends RefCounted
## A light record of one Day for the First Playable playtest (T14, GDD 11.3). DayState feeds
## it at each action; the Day Consequences screen shows format() so the tester's run can be
## copied into docs/playtest_first_playable.md. Pure logic, so tests can check it headless.
##
## What it is for:
## - 11.3 Q2 (remembering the Brew without a queue): the Ingredients in each served Brew,
##   how often the Brew was emptied and which Ingredients that wasted.
## - 11.3 Q4 (failing on purpose): each Resolution, and whether an empty Brew was served.
## - 11.3 Q6 (does the Shifter matter): what was shifted, when, for which Client, and
##   whether the Shifted unit was ever added; plus the supply left unused at Day end.
## It records IDs; format() turns them into names from the Data Sheet rows.

## Returns milliseconds. Tests replace it with a fake clock.
var clock: Callable = Time.get_ticks_msec

var day := 0
## One {"request_id", "success", "coins", "at_ms", "brew", "lost", "empties"} per Serve, in
## order. brew and lost are lists of {"id", "shifted"}.
var serves: Array[Dictionary] = []
## {"id", "to_shifted", "at_ms", "request_id"} once the Shifter is used, else {}.
var shift: Dictionary = {}
## True once the unit that was shifted has been added to a Brew.
var shifted_unit_added := false
var client_switches := 0
## ingredient_id -> units left when the Day ended (only Ingredients with some left).
var unused_supply: Dictionary[String, int] = {}
var day_ms := 0

var _start_ms := 0
## Ingredients in the current Brew, and those lost to Empty since the last Serve.
var _brew: Array[Dictionary] = []
var _lost: Array[Dictionary] = []
var _empties := 0


func start_day(n: int) -> void:
	day = n
	serves.clear()
	shift = {}
	shifted_unit_added = false
	client_switches = 0
	unused_supply.clear()
	day_ms = 0
	_brew.clear()
	_lost.clear()
	_empties = 0
	_start_ms = clock.call()


func switched_client() -> void:
	client_switches += 1


func added(ingredient_id: String, shifted: bool) -> void:
	_brew.append({"id": ingredient_id, "shifted": shifted})
	if shifted and not shift.is_empty() and shift["id"] == ingredient_id:
		shifted_unit_added = true


func emptied() -> void:
	_empties += 1
	_lost.append_array(_brew)
	_brew.clear()


func shifted(ingredient_id: String, to_shifted: bool, request_id: String) -> void:
	shift = {"id": ingredient_id, "to_shifted": to_shifted, "at_ms": _now(), "request_id": request_id}


func served(request_id: String, success: bool, coins: int) -> void:
	serves.append({
		"request_id": request_id,
		"success": success,
		"coins": coins,
		"at_ms": _now(),
		"brew": _brew.duplicate(),
		"lost": _lost.duplicate(),
		"empties": _empties,
	})
	_brew.clear()
	_lost.clear()
	_empties = 0


## supply: ingredient_id -> units left, read before the Day end discards them (GDD 5.4).
func ended_day(supply: Dictionary) -> void:
	day_ms = _now()
	for id: String in supply:
		if int(supply[id]) > 0:
			unused_supply[id] = int(supply[id])


## The log as plain text, with names from the Data Sheet rows (GameData.rows(...)).
func format(ingredient_rows: Array, request_rows: Array, character_rows: Array) -> String:
	var lines: PackedStringArray = []
	lines.append("Playtest log, Day %d (%s)" % [day, _clock_text(day_ms)])
	var number := 0
	for entry: Dictionary in serves:
		number += 1
		var request := _find(request_rows, "request_id", entry["request_id"])
		var character := _find(character_rows, "character_id", request.get("character_id", ""))
		var coins: int = entry["coins"]
		lines.append("%d. %s (%s): %s, %d Gold Coin%s, at %s" % [
			number,
			character.get("name", request.get("character_id", "?")),
			entry["request_id"],
			"Success" if entry["success"] else "Failure",
			coins,
			"" if coins == 1 else "s",
			_clock_text(entry["at_ms"]),
		])
		var brew: Array = entry["brew"]
		lines.append("   Brew: %s" % ("empty (served an empty Brew)" if brew.is_empty() else _names(brew, ingredient_rows)))
		if entry["empties"] > 0:
			var lost: Array = entry["lost"]
			lines.append("   Emptied %d×, lost: %s" % [entry["empties"], "nothing" if lost.is_empty() else _names(lost, ingredient_rows)])

	if shift.is_empty():
		lines.append("Shifter: not used")
	else:
		var request := _find(request_rows, "request_id", shift["request_id"])
		var character := _find(character_rows, "character_id", request.get("character_id", ""))
		lines.append("Shifter: %s → %s at %s, while %s was selected; the Shifted unit was %s" % [
			_ingredient_name(shift["id"], ingredient_rows),
			"Shifted" if shift["to_shifted"] else "Normal",
			_clock_text(shift["at_ms"]),
			character.get("name", "no Client"),
			"added" if shifted_unit_added else "never added",
		])
	lines.append("Client switches: %d" % client_switches)
	var unused: PackedStringArray = []
	for id: String in unused_supply:
		unused.append("%s ×%d" % [_ingredient_name(id, ingredient_rows), unused_supply[id]])
	lines.append("Unused at Day end: %s" % ("none" if unused.is_empty() else ", ".join(unused)))
	return "\n".join(lines)


func _now() -> int:
	return int(clock.call()) - _start_ms


## "Ananas, Vetka (Shifted)", in the order they were added.
static func _names(items: Array, ingredient_rows: Array) -> String:
	var parts: PackedStringArray = []
	for item: Dictionary in items:
		parts.append(_ingredient_name(item["id"], ingredient_rows) + (" (Shifted)" if item["shifted"] else ""))
	return ", ".join(parts)


static func _ingredient_name(id: String, ingredient_rows: Array) -> String:
	return _find(ingredient_rows, "ingredient_id", id).get("name", id)


## "m:ss" since the Day started.
static func _clock_text(ms: int) -> String:
	var seconds := maxi(ms, 0) / 1000
	return "%d:%02d" % [seconds / 60, seconds % 60]


static func _find(rows: Array, id_key: String, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.get(id_key, "") == id:
			return row
	return {}
