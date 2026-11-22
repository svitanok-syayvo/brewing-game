extends SceneTree
## Headless checks for DayState.start_day() (T7). Run:
##   godot --headless --path . -s tests/test_day_state.gd
## Prints PASS or FAIL per check and exits with code 1 if any check failed.
##
## Expected values are read from GameData rather than copied, so a supply or Request change
## in the Data Sheet does not break this test. Only the rules are checked.

var _failures := 0


func _initialize() -> void:
	# Autoloads run _ready() after _initialize(), so wait a frame for GameData to load,
	# and look it up by path: the global name is not known when a -s script is compiled.
	await process_frame
	var data: Node = root.get_node("GameData")
	var state := DayState.new(data.rows("parameters"), data.rows("ingredients"), data.rows("supply"), data.rows("requests"))

	# Dirty the state so start_day() has something to reset.
	state.coins = 5
	state.shifter_used = true
	state.results["req_01"] = true
	state.brew.step(0, 1)
	state.brew.count_ingredient()

	var emitted := [false]
	state.changed.connect(func() -> void: emitted[0] = true)
	state.start_day(1)

	_check("changed is emitted", emitted[0])
	_check("day is 1", state.day == 1)
	_check("coins carry over", state.coins == 5)
	_check("Shifter is unused", not state.shifter_used)
	_check("results are cleared", state.results.is_empty())
	_check("Brew is back at State 0", state.brew.get_states() == [0, 0, 0])
	_check("Brew has no Ingredients", state.brew.get_ingredient_count() == 0)

	var ids := state.ingredient_ids()
	_check("6 Ingredients in Data Sheet order", ids.size() == data.rows("ingredients").size() and ids[0] == "ing_01")
	for id: String in ids:
		_check("%s supply = day_1 column" % id, state.supply_of(id) == int(data.row("supply", id).get("day_1", 0)))
		_check("%s starts Normal" % id, not state.is_shifted(id))
	_check("unknown Ingredient has 0 supply", state.supply_of("ing_99") == 0)

	var expected: Array[String] = []
	for row: Dictionary in data.rows("requests"):
		if int(row.get("day", 0)) == 1:
			expected.append(row["request_id"])
	_check("Day 1 Requests in sheet order", state.waiting_requests() == expected)
	_check("Requests left = %d" % expected.size(), state.requests_left() == expected.size())

	var copy := state.waiting_requests()
	copy.clear()
	_check("waiting_requests() returns a copy", state.requests_left() == expected.size())

	print("%s: %d failure(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1
