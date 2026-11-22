extends SceneTree
## Headless checks for PlaytestLog, the playtest record of a Day (T14). Run:
##   godot --headless --path . -s tests/test_playtest_log.gd
## Prints PASS or FAIL per check and exits with code 1 if any check failed.
##
## It plays a scripted Day 1 through DayState with a fake clock, so it checks both that
## DayState feeds the log at each action and what format() prints.

var _failures := 0
var _fake_ms := 0


func _initialize() -> void:
	# Autoloads run _ready() after _initialize(), so wait a frame for GameData to load,
	# and look it up by path: the global name is not known when a -s script is compiled.
	await process_frame
	var data: Node = root.get_node("GameData")
	var state := DayState.new(data.rows("parameters"), data.rows("ingredients"), data.rows("supply"), data.rows("requests"))
	state.playtest_log.clock = func() -> int: return _fake_ms
	_fake_ms = 5000 # The clock does not start at 0; times are counted from start_day().
	state.start_day(1)
	var log := state.playtest_log

	_check("a new Day starts with no Serves", log.serves.is_empty() and log.shift.is_empty())

	# Luk goes in and is wasted by Empty.
	state.add_ingredient("ing_01")
	state.empty_brew()
	# Shift Vetka while Baba Yaga (req_01) is selected, 10 s in.
	_fake_ms = 15000
	state.shift("ing_06")
	# Switch to Ryurik and serve the Shifted Vetka: (2,2,0) is req_04's 'Success'.
	state.select_request("req_04")
	state.add_ingredient("ing_06")
	_fake_ms = 70000
	state.serve()
	# Back to Baba Yaga: Ananas gives (1,1,0), req_01's 'Success'.
	state.select_request("req_01")
	state.add_ingredient("ing_02")
	_fake_ms = 95000
	state.serve()
	# Refuse the last two with an empty Brew.
	state.serve()
	_fake_ms = 130000
	state.serve()
	_check("the scripted Day is over", state.is_day_over())

	_check("4 Serves recorded in order", log.serves.map(func(e: Dictionary) -> String: return e["request_id"]) == ["req_04", "req_01", "req_02", "req_03"])
	var first: Dictionary = log.serves[0]
	_check("1st Serve: Success, 2 Gold Coins", first["success"] and first["coins"] == 2)
	_check("1st Serve: the Brew is Vetka (Shifted)", first["brew"] == [{"id": "ing_06", "shifted": true}])
	_check("1st Serve: 1 Empty that lost Luk", first["empties"] == 1 and first["lost"] == [{"id": "ing_01", "shifted": false}])
	_check("1st Serve: time counted from start_day()", first["at_ms"] == 65000)
	_check("2nd Serve: Ananas, nothing emptied", log.serves[1]["brew"] == [{"id": "ing_02", "shifted": false}] and log.serves[1]["empties"] == 0)
	_check("3rd and 4th Serves: empty Brews, 'Failure'", log.serves[2]["brew"].is_empty() and not log.serves[3]["success"])
	_check("Shifter: Vetka to Shifted while req_01 was selected",
		log.shift == {"id": "ing_06", "to_shifted": true, "at_ms": 10000, "request_id": "req_01"})
	_check("the Shifted unit was added", log.shifted_unit_added)
	_check("2 Client switches", log.client_switches == 2)
	_check("unused supply read before the Day end", log.unused_supply == {"ing_03": 1, "ing_04": 1, "ing_05": 1})
	_check("Day length", log.day_ms == 125000)

	var text := log.format(data.rows("ingredients"), data.rows("requests"), data.rows("characters"))
	print(text)
	var ing := func(id: String) -> String: return data.row("ingredients", id)["name"]
	var who := func(request_id: String) -> String:
		return data.row("characters", data.row("requests", request_id)["character_id"])["name"]
	_check("header has the Day and its length", text.begins_with("Playtest log, Day 1 (2:05)"))
	_check("Serve line", text.contains("1. %s (req_04): Success, 2 Gold Coins, at 1:05" % who.call("req_04")))
	_check("Brew line marks the Shifted Form", text.contains("   Brew: %s (Shifted)" % ing.call("ing_06")))
	_check("Empty line names what was lost", text.contains("   Emptied 1×, lost: %s" % ing.call("ing_01")))
	_check("an empty Brew is called out", text.contains("Brew: empty (served an empty Brew)"))
	_check("Shifter line", text.contains("Shifter: %s → Shifted at 0:10, while %s was selected; the Shifted unit was added" % [ing.call("ing_06"), who.call("req_01")]))
	_check("unused line", text.contains("Unused at Day end: %s ×1, %s ×1, %s ×1" % [ing.call("ing_03"), ing.call("ing_04"), ing.call("ing_05")]))

	# start_day() clears the record, and an unused Shifter says so.
	state.start_day(1)
	_check("start_day() clears the log", log.serves.is_empty() and log.shift.is_empty() and log.client_switches == 0 and not log.shifted_unit_added)
	state.shift("ing_03")
	_check("a Shifted unit never added says so", log.format(data.rows("ingredients"), data.rows("requests"), data.rows("characters")).contains("the Shifted unit was never added"))
	var fresh := PlaytestLog.new()
	fresh.clock = func() -> int: return 0
	fresh.start_day(1)
	_check("an unused Shifter says so", fresh.format([], [], []).contains("Shifter: not used"))

	print("%s: %d failure(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1
