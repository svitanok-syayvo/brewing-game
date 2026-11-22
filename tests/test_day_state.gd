extends SceneTree
## Headless checks for DayState: start_day() (T7), add_ingredient() and empty_brew() (T8),
## Client switching and the Request text (T9), Serve and the Day end (T10), the Shifter
## (T11). Run:
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
	_test_serve(data)
	_test_shifter(data)

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


## T10: Serve pays maximum_coins only when every requested Parameter is on target, ignores
## Parameters set to "any", records the Resolution, starts a new Brew without refunding
## supply, selects the next Client, and ends the Day after the last one. The Brew is set
## to each Request's targets by hand, so no Ingredient solution is assumed.
func _test_serve(data: Node) -> void:
	var state := DayState.new(data.rows("parameters"), data.rows("ingredients"), data.rows("supply"), data.rows("requests"))
	state.coins = 1
	state.start_day(1)
	var waiting := state.waiting_requests()
	var parameters: Array = data.rows("parameters")
	var day_ended := [0]
	state.day_ended.connect(func() -> void: day_ended[0] += 1)

	# Pick a Request with a Parameter set to "any", to check that it is ignored.
	var partial := ""
	for request_id: String in waiting:
		for row: Dictionary in parameters:
			if not data.row("requests", request_id).has("%s_target" % row["parameter_id"]):
				partial = request_id
		if not partial.is_empty():
			break
	_check("Day 1 has a Request with an 'any' Parameter", not partial.is_empty())

	# 'Success': every target met; the "any" Parameter is pushed off State 0 on purpose.
	var request: Dictionary = data.row("requests", partial)
	state.select_request(partial)
	for id: String in state.ingredient_ids():
		state._supply[id] = 1
	state.add_ingredient("ing_02")
	var supply_after_add := state.supply_of("ing_02")
	state.brew.pending_mask.append(0)
	_set_to_targets(state, request, parameters, 1)
	var emitted := [0]
	state.changed.connect(func() -> void: emitted[0] += 1)
	var result := state.serve()
	var index := waiting.find(partial)
	waiting.remove_at(index)

	_check("Success: result says so", result.get("request_id") == partial and result.get("success") == true)
	_check("Success pays maximum_coins (%d)" % int(request["maximum_coins"]), result.get("coins") == int(request["maximum_coins"]))
	_check("coins added to the total", state.coins == 1 + int(request["maximum_coins"]))
	_check("Resolution recorded as Success", state.results.get(partial) == true)
	_check("served Client left", state.waiting_requests() == waiting)
	_check("Requests left -1", state.requests_left() == waiting.size())
	_check("next Client is selected", state.current_request() == waiting[mini(index, waiting.size() - 1)])
	_check("new Brew at State 0", state.brew.get_states() == [0, 0, 0])
	_check("new Brew has no Ingredients", state.brew.get_ingredient_count() == 0)
	_check("new Brew has no pending modifier", state.brew.pending_mask.is_empty())
	_check("Serve does not refund supply", state.supply_of("ing_02") == supply_after_add)
	_check("serve emits changed once", emitted[0] == 1)
	_check("Day not over yet", not state.is_day_over() and day_ended[0] == 0)

	# 'Failure': every target met but one. No partial credit.
	var near_id := state.current_request()
	var near: Dictionary = data.row("requests", near_id)
	_set_to_targets(state, near, parameters, 0)
	for p: int in parameters.size():
		var key := "%s_target" % parameters[p]["parameter_id"]
		if near.has(key):
			state.brew.set_state(p, (int(near[key]) + 1) % Brew.STATE_COUNT)
			break
	var coins_before := state.coins
	result = state.serve()
	_check("one Parameter off -> Failure", result.get("success") == false and result.get("coins") == 0)
	_check("Failure pays nothing", state.coins == coins_before)
	_check("Resolution recorded as Failure", state.results.get(near_id) == false)

	# Serving an empty Brew is allowed (D11). It fails unless every target is State 0.
	while state.requests_left() > 1:
		var refused := state.current_request()
		var all_zero := true
		for row: Dictionary in parameters:
			all_zero = all_zero and int(data.row("requests", refused).get("%s_target" % row["parameter_id"], 0)) == 0
		result = state.serve()
		_check("empty Brew for %s -> %s" % [refused, "Success" if all_zero else "Failure"], result.get("success") == all_zero)
	_check("day_ended not emitted before the last Client", day_ended[0] == 0)

	var last := state.current_request()
	_set_to_targets(state, data.row("requests", last), parameters, 0)
	result = state.serve()
	_check("last Client: Success", result.get("success") == true)
	_check("day_ended emitted once", day_ended[0] == 1)
	_check("Day is over", state.is_day_over() and state.requests_left() == 0)
	_check("no Client selected", state.current_request().is_empty())
	_check("results hold every Day 1 Request", state.results.size() == _day_requests(data, 1).size())
	var discarded := true
	for id: String in state.ingredient_ids():
		discarded = discarded and state.supply_of(id) == 0
	_check("unused supply discarded at Day end", discarded)
	_check("adding after the Day -> NONE_LEFT", state.add_ingredient("ing_01") == DayState.AddResult.NONE_LEFT)
	_check("serve with no Client -> {}", state.serve().is_empty())
	_check("refused serve keeps the coins and results", state.coins == coins_before + int(data.row("requests", last)["maximum_coins"]) and state.results.size() == _day_requests(data, 1).size())
	_check("day_ended still emitted once", day_ended[0] == 1)


## T11: the Shifter switches one Ingredient's Form once per Day, the use is spent even if
## the Ingredient is never added, a blocked shift changes nothing, the Shifted Form is used
## by the next add and then returns to Normal, and a new Day gives a fresh use.
func _test_shifter(data: Node) -> void:
	var state := DayState.new(data.rows("parameters"), data.rows("ingredients"), data.rows("supply"), data.rows("requests"))
	state.start_day(1)
	for id: String in state.ingredient_ids():
		state._supply[id] = 1
	state._supply["ing_02"] = 0

	var emitted := [0]
	state.changed.connect(func() -> void: emitted[0] += 1)

	_check("shift with 0 left -> NONE_LEFT", state.shift("ing_02") == DayState.ShiftResult.NONE_LEFT)
	_check("blocked shift keeps the Shifter unused", not state.shifter_used)
	_check("blocked shift keeps the Form", not state.is_shifted("ing_02"))
	_check("blocked shift emits nothing", emitted[0] == 0)
	_check("unknown Ingredient -> UNKNOWN", state.shift("ing_99") == DayState.ShiftResult.UNKNOWN)
	_check("unknown shift keeps the Shifter unused", not state.shifter_used)

	state.brew.step(0, 1)
	state.brew.count_ingredient()
	var brew_before := state.brew.get_states()
	_check("shift ing_06 -> SHIFTED", state.shift("ing_06") == DayState.ShiftResult.SHIFTED)
	_check("ing_06 is Shifted", state.is_shifted("ing_06"))
	_check("the Shifter is used", state.shifter_used)
	_check("shift emits changed once", emitted[0] == 1)
	_check("shift leaves the Brew alone", state.brew.get_states() == brew_before and state.brew.get_ingredient_count() == 1)
	_check("shift uses no supply", state.supply_of("ing_06") == 1)
	_check("other Ingredients stay Normal", not state.is_shifted("ing_01"))

	_check("second shift -> SHIFTER_USED", state.shift("ing_01") == DayState.ShiftResult.SHIFTER_USED)
	_check("second shift keeps ing_01 Normal", not state.is_shifted("ing_01"))
	_check("shifting back -> SHIFTER_USED", state.shift("ing_06") == DayState.ShiftResult.SHIFTER_USED)
	_check("ing_06 is still Shifted", state.is_shifted("ing_06"))
	_check("blocked second shift emits nothing", emitted[0] == 1)

	state.empty_brew()
	_check("Empty keeps the Shifted Form", state.is_shifted("ing_06"))
	_check("Empty does not refund the Shifter", state.shifter_used)
	state.add_ingredient("ing_06")
	_check("Shifted ing_06 effect applied: (2,2,0)", state.brew.get_states() == [2, 2, 0])
	_check("ing_06 back to Normal after use", not state.is_shifted("ing_06"))
	_check("the Shifter stays used after the add", state.shifter_used)

	state.start_day(1)
	_check("a new Day gives the Shifter back", not state.shifter_used)
	var any_shifted := false
	for id: String in state.ingredient_ids():
		any_shifted = any_shifted or state.is_shifted(id)
	_check("a new Day starts every Form Normal", not any_shifted)

	# The use is spent even if the Shifted Ingredient is never added (GDD 5.3).
	state._supply["ing_01"] = 1
	state.shift("ing_01")
	var requests := state.waiting_requests()
	for request_id: String in requests:
		state.serve()
	_check("a never-added shift still spends the use", state.shifter_used)
	_check("Day end puts Shifted Ingredients back to Normal", not state.is_shifted("ing_01"))
	_check("shift after the Day -> SHIFTER_USED", state.shift("ing_03") == DayState.ShiftResult.SHIFTER_USED)


## Sets every requested Parameter to its target. A Parameter the Request does not name is
## set to `other` instead, so a check can show it is ignored.
func _set_to_targets(state: DayState, request: Dictionary, parameters: Array, other: int) -> void:
	for p: int in parameters.size():
		var key := "%s_target" % parameters[p]["parameter_id"]
		state.brew.set_state(p, int(request[key]) if request.has(key) else other)


func _day_requests(data: Node, n: int) -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in data.rows("requests"):
		if int(row.get("day", 0)) == n:
			ids.append(row["request_id"])
	return ids


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1
