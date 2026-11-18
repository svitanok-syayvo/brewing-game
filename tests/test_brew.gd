extends SceneTree
## Headless checks for the Brew model (T4). Run:
##   godot --headless --path . -s tests/test_brew.gd
## Prints PASS or FAIL per check and exits with code 1 if any check failed.
## Lines starting with "ERROR: Brew:" are expected: some checks pass invalid input on purpose.

var _failures := 0
var _signals := 0


func _initialize() -> void:
	_test_new_brew()
	_test_step_loops()
	_test_set_state()
	_test_ingredient_cap()
	_test_reset()
	_test_changed_signal()
	_test_invalid_input()

	print("\n%s: %d check(s) failed" % ["FAIL" if _failures else "PASS", _failures])
	quit(1 if _failures else 0)


func _test_new_brew() -> void:
	var brew := Brew.new(3)
	_check("new Brew has 3 Parameters", brew.parameter_count(), 3)
	_check("new Brew starts at (0,0,0)", brew.get_states(), [0, 0, 0])
	_check("new Brew has no Ingredients", brew.get_ingredient_count(), 0)
	_check("new Brew is not full", brew.is_full(), false)
	_check("new Brew has no pending modifier", brew.pending_mask, [])


func _test_step_loops() -> void:
	var brew := Brew.new(3)
	brew.step(0)
	_check("step once: 0 -> 1", brew.get_state(0), 1)
	brew.step(0)
	_check("step twice: 1 -> 2", brew.get_state(0), 2)
	brew.step(0)
	_check("step from the last State loops: 2 -> 0", brew.get_state(0), 0)

	brew.step(1, 2)
	_check("step by 2: 0 -> 2", brew.get_state(1), 2)
	brew.step(1, 2)
	_check("step by 2 loops: 2 -> 1", brew.get_state(1), 1)
	brew.step(2, 4)
	_check("step by more than STATE_COUNT: 0 + 4 -> 1", brew.get_state(2), 1)
	brew.step(2, 0)
	_check("step by 0 changes nothing", brew.get_state(2), 1)
	brew.step(2, -1)
	_check("step by -1 goes back one State: 1 -> 0", brew.get_state(2), 0)
	brew.step(2, -1)
	_check("step by -1 loops backwards: 0 -> 2", brew.get_state(2), 2)
	_check("stepping one Parameter leaves the others alone", brew.get_states(), [0, 1, 2])


func _test_set_state() -> void:
	var brew := Brew.new(3)
	brew.set_state(1, 2)
	_check("set_state sets the State", brew.get_states(), [0, 2, 0])
	brew.set_state(1, 0)
	_check("set_state can set State 0", brew.get_states(), [0, 0, 0])


func _test_ingredient_cap() -> void:
	var brew := Brew.new(3)
	for i in Brew.MAX_INGREDIENTS:
		_check("Ingredient %d fits" % (i + 1), brew.count_ingredient(), true)
	_check("Brew with 3 Ingredients is full", brew.is_full(), true)
	_check("a 4th Ingredient is refused", brew.count_ingredient(), false)
	_check("a refused Ingredient is not counted", brew.get_ingredient_count(), 3)


func _test_reset() -> void:
	var brew := Brew.new(3)
	brew.set_state(0, 2)
	brew.step(2)
	brew.count_ingredient()
	brew.pending_mask = [1, 2]
	brew.reset()
	_check("reset returns to (0,0,0)", brew.get_states(), [0, 0, 0])
	_check("reset clears the Ingredient count", brew.get_ingredient_count(), 0)
	_check("reset clears the pending modifier", brew.pending_mask, [])


func _test_changed_signal() -> void:
	var brew := Brew.new(3)
	brew.changed.connect(func() -> void: _signals += 1)

	_signals = 0
	brew.set_state(0, 1)
	_check("set_state emits changed", _signals, 1)
	_signals = 0
	brew.set_state(0, 1)
	_check("set_state to the same State does not emit", _signals, 0)
	_signals = 0
	brew.step(1)
	_check("step emits changed", _signals, 1)
	_signals = 0
	brew.step(1, 3)
	_check("a full loop (step by 3) does not emit", _signals, 0)
	_signals = 0
	brew.count_ingredient()
	_check("count_ingredient emits changed", _signals, 1)
	_signals = 0
	brew.reset()
	_check("reset emits changed", _signals, 1)


func _test_invalid_input() -> void:
	print("-- the next 3 ERROR lines are expected --")
	var brew := Brew.new(3)
	brew.set_state(0, 3)
	_check("set_state to State 3 is refused", brew.get_states(), [0, 0, 0])
	brew.step(3)
	_check("step on Parameter index 3 is refused", brew.get_states(), [0, 0, 0])
	_check("get_state on a bad index returns -1", brew.get_state(-1), -1)


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  %s: expected %s, got %s" % [label, expected, actual])
