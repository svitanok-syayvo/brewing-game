extends SceneTree
## Headless checks for DayState: start_day() (T7), add_ingredient() and empty_brew() (T8),
## Client switching and the Request text (T9). Run:
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

	_test_brewing_controls(data)
	_test_clients(data)
	_test_request_text(data)

	print("%s: %d failure(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	quit(1 if _failures > 0 else 0)


## T8: adding uses up supply and a slot, the cap and 0 supply block without side effects,
## a Shifted Ingredient is added Shifted and returns to Normal, and Empty refunds nothing.
## Supply is set by hand so the checks do not depend on the Data Sheet's numbers.
func _test_brewing_controls(data: Node) -> void:
	var state := DayState.new(data.rows("parameters"), data.rows("ingredients"), data.rows("supply"), data.rows("requests"))
	state.start_day(1)
	for id: String in state.ingredient_ids():
		state._supply[id] = 1
	state._supply["ing_02"] = 2

	var emitted := [0]
	state.changed.connect(func() -> void: emitted[0] += 1)

	_check("add ing_02 -> ADDED", state.add_ingredient("ing_02") == DayState.AddResult.ADDED)
	_check("ing_02 effect applied: (1,1,0)", state.brew.get_states() == [1, 1, 0])
	_check("ing_02 supply 2 -> 1", state.supply_of("ing_02") == 1)
	_check("1 Ingredient in the Brew", state.brew.get_ingredient_count() == 1)
	_check("changed emitted on add", emitted[0] == 1)

	_check("add ing_03 -> ADDED", state.add_ingredient("ing_03") == DayState.AddResult.ADDED)
	_check("ing_03 supply 1 -> 0", state.supply_of("ing_03") == 0)
	_check("ing_03 again -> NONE_LEFT", state.add_ingredient("ing_03") == DayState.AddResult.NONE_LEFT)
	_check("NONE_LEFT leaves 2 Ingredients", state.brew.get_ingredient_count() == 2)

	state._shifted["ing_06"] = true
	var before := state.brew.get_states()
	_check("add Shifted ing_06 -> ADDED", state.add_ingredient("ing_06") == DayState.AddResult.ADDED)
	_check("Shifted effect used: Nature and Taste = 2", state.brew.get_states() == [2, 2, before[2]])
	_check("ing_06 back to Normal after use", not state.is_shifted("ing_06"))
	_check("Brew is full at 3", state.brew.is_full())

	var full_states := state.brew.get_states()
	emitted[0] = 0
	_check("4th Ingredient -> BREW_FULL", state.add_ingredient("ing_01") == DayState.AddResult.BREW_FULL)
	_check("BREW_FULL keeps ing_01 supply", state.supply_of("ing_01") == 1)
	_check("BREW_FULL keeps the States", state.brew.get_states() == full_states)
	_check("BREW_FULL emits nothing", emitted[0] == 0)
	_check("unknown Ingredient -> UNKNOWN", state.add_ingredient("ing_99") == DayState.AddResult.UNKNOWN)

	state._shifted["ing_04"] = true
	state.empty_brew()
	_check("Empty resets States", state.brew.get_states() == [0, 0, 0])
	_check("Empty frees the slots", state.brew.get_ingredient_count() == 0)
	_check("Empty does not refund supply", state.supply_of("ing_02") == 1 and state.supply_of("ing_03") == 0)
	_check("Empty keeps the tray's Forms", state.is_shifted("ing_04"))

	state.add_ingredient("ing_05")
	state.empty_brew()
	state.add_ingredient("ing_01")
	_check("Empty clears a pending ing_05 mask", state.brew.get_states() == [0, 2, 1])


## T9: one Client is always selected, switching is limited to waiting Requests, and it
## leaves the Brew (with a pending ing_05 mask), the supply and the Forms untouched.
func _test_clients(data: Node) -> void:
	var state := DayState.new(data.rows("parameters"), data.rows("ingredients"), data.rows("supply"), data.rows("requests"))
	state.start_day(1)
	var waiting := state.waiting_requests()
	_check("first waiting Request is selected", state.current_request() == waiting[0])

	for request_id: String in waiting:
		var request: Dictionary = data.row("requests", request_id)
		var character_id: String = request.get("character_id", "")
		_check("%s has a Client in characters" % request_id, not data.row("characters", character_id).is_empty())

	for id: String in state.ingredient_ids():
		state._supply[id] = 1
	state.add_ingredient("ing_02")
	state.add_ingredient("ing_05")
	state._shifted["ing_04"] = true
	var states := state.brew.get_states()

	var emitted := [0]
	state.changed.connect(func() -> void: emitted[0] += 1)
	var last: String = waiting[-1]
	_check("select %s -> true" % last, state.select_request(last))
	_check("selection moved", state.current_request() == last)
	_check("select emits changed once", emitted[0] == 1)
	_check("switching keeps the States", state.brew.get_states() == states)
	_check("switching keeps the Ingredient count", state.brew.get_ingredient_count() == 2)
	_check("switching keeps the supply", state.supply_of("ing_02") == 0 and state.supply_of("ing_05") == 0)
	_check("switching keeps the Forms", state.is_shifted("ing_04"))
	_check("switching keeps the Requests waiting", state.waiting_requests() == waiting)

	emitted[0] = 0
	_check("selecting the same Client -> true", state.select_request(last))
	_check("selecting the same Client emits nothing", emitted[0] == 0)
	_check("unknown Request -> false", not state.select_request("req_99"))
	var other_day := ""
	for row: Dictionary in data.rows("requests"):
		if int(row.get("day", 0)) != 1:
			other_day = row["request_id"]
			break
	if not other_day.is_empty():
		_check("another Day's Request -> false", not state.select_request(other_day))
	_check("refused select keeps the selection", state.current_request() == last and emitted[0] == 0)

	# ing_05 (Normal) masks Taste and Smell of the next Ingredient: ing_01 then only
	# changes Nature, which it does not touch, so the Brew stays as it was.
	state.add_ingredient("ing_01")
	_check("pending ing_05 mask survives switching", state.brew.get_states() == states)

	state.start_day(1)
	_check("start_day selects the first Request again", state.current_request() == waiting[0])


## T9: the Data Sheet text wins; without it a placeholder lists the requested Parameters
## by name and State name, in Parameter order, and skips the ones not requested.
func _test_request_text(data: Node) -> void:
	var parameters: Array = data.rows("parameters")
	var p1: Dictionary = parameters[0]
	var p3: Dictionary = parameters[2]
	var request := {"request_id": "req_test", "param_03_target": 0, "param_01_target": 1}
	var expected := "%sI need: %s = %s, %s = %s" % [
		RequestText.PLACEHOLDER_PREFIX,
		p1["name"], p1["state_1_name"],
		p3["name"], p3["state_0_name"],
	]
	_check("placeholder text: '%s'" % expected, RequestText.describe(request, parameters) == expected)
	request["text"] = "  I want a SWEET rat POISON  "
	_check("Data Sheet text wins (trimmed)", RequestText.describe(request, parameters) == "I want a SWEET rat POISON")

	for row: Dictionary in data.rows("requests"):
		if int(row.get("day", 0)) != 1:
			continue
		var text := RequestText.describe(row, parameters)
		var readable := not text.is_empty() and not text.contains("State ") and not text.contains("param_")
		_check("%s is readable: %s" % [row["request_id"], text], readable)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1
