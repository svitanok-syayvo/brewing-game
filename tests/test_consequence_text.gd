extends SceneTree
## Headless checks for ConsequenceText, the text of the Day Consequences screen (T12). Run:
##   godot --headless --path . -s tests/test_consequence_text.gd
## Prints PASS or FAIL per check and exits with code 1 if any check failed.
##
## It plays a whole Day 1 through DayState (serving with the Brew set by hand), so it also
## checks that DayState.results feeds the screen in the order Requests were served.

var _failures := 0


func _initialize() -> void:
	# Autoloads run _ready() after _initialize(), so wait a frame for GameData to load,
	# and look it up by path: the global name is not known when a -s script is compiled.
	await process_frame
	var data: Node = root.get_node("GameData")

	_test_describe()
	_test_day(data)

	print("%s: %d failure(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	quit(1 if _failures > 0 else 0)


## The sheet's text wins and is trimmed; an empty or missing cell gives a placeholder that
## names the Resolution (D7).
func _test_describe() -> void:
	var row := {"request_id": "req_x", "success_text": "  Glad.  ", "failure_text": "Sad."}
	_check("Success uses success_text, trimmed", ConsequenceText.describe(row, true) == "Glad.")
	_check("Failure uses failure_text", ConsequenceText.describe(row, false) == "Sad.")

	var empty := {"request_id": "req_y", "success_text": "   "}
	var placeholder_success := ConsequenceText.describe(empty, true)
	var placeholder_failure := ConsequenceText.describe(empty, false)
	_check("blank success_text gives a placeholder", placeholder_success.begins_with(ConsequenceText.PLACEHOLDER_PREFIX))
	_check("placeholder names 'Success'", placeholder_success.contains("Success"))
	_check("missing failure_text gives a placeholder", placeholder_failure.begins_with(ConsequenceText.PLACEHOLDER_PREFIX))
	_check("placeholder names 'Failure'", placeholder_failure.contains("Failure"))


## Day 1 served in reverse sheet order: the last Request succeeds, the rest fail.
func _test_day(data: Node) -> void:
	var parameters: Array = data.rows("parameters")
	var state := DayState.new(parameters, data.rows("ingredients"), data.rows("supply"), data.rows("requests"))
	state.start_day(1)

	var order := state.waiting_requests()
	order.reverse()
	var success_id := order[0]
	for request_id: String in order:
		state.select_request(request_id)
		if request_id == success_id:
			var request: Dictionary = data.row("requests", request_id)
			for p: int in parameters.size():
				var key := "%s_target" % parameters[p]["parameter_id"]
				if request.has(key):
					state.brew.set_state(p, int(request[key]))
		state.serve()
	_check("Day 1 is over", state.is_day_over())

	var entries := ConsequenceText.entries(state.results, data.rows("requests"), data.rows("characters"))
	_check("1 entry per Day 1 Request", entries.size() == order.size())
	var ids: Array[String] = []
	for entry: Dictionary in entries:
		ids.append(entry["request_id"])
	_check("entries keep the served order", ids == order)

	var total := 0
	for entry: Dictionary in entries:
		var id: String = entry["request_id"]
		var request: Dictionary = data.row("requests", id)
		var character: Dictionary = data.row("characters", request["character_id"])
		var success: bool = id == success_id
		_check("%s Resolution" % id, entry["success"] == success)
		_check("%s Client name from data" % id, entry["character_name"] == character.get("name", ""))
		_check("%s coins = %s" % [id, "maximum_coins" if success else "0"],
			entry["coins"] == (int(request["maximum_coins"]) if success else 0))
		_check("%s text matches its Resolution" % id, entry["text"] == ConsequenceText.describe(request, success))
		_check("%s text is not empty" % id, not str(entry["text"]).is_empty())
		total += int(entry["coins"])
	_check("entry coins add up to the Day's Gold Coins", total == state.coins)

	print("-- the next ERROR line is expected --")
	var unknown := ConsequenceText.entries({"req_99": true}, data.rows("requests"), data.rows("characters"))
	_check("unknown Request falls back to its ID", unknown.size() == 1 and unknown[0]["character_name"] == "req_99")


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1
