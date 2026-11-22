extends SceneTree
## Headless checks for Ingredient effects (T6). Run:
##   godot --headless --path . -s tests/test_effects.gd
## Prints PASS or FAIL per case and exits with code 1 if any case failed.
##
## The effects come from data/ingredients.json (through GameData), so this test checks the
## Data Sheet's notation as well as the parser. If the Data Sheet changes an effect, the
## cases below must be worked out again.
##
## Case format: [start States (p1, p2, p3), Ingredients added in order, expected States].
## An Ingredient is "ing_NN" (Normal Form) or "ing_NN*" (Shifted Form). Ingredients are
## only applied: supply, the 3-Ingredient cap and the Shifter are not part of this test.

## Single Ingredients from three start States, in both Forms (ing_05 alone changes no State).
const SINGLE_CASES := [
	[[0, 0, 0], ["ing_01"], [0, 2, 1]],
	[[0, 0, 0], ["ing_01*"], [2, 0, 1]],
	[[0, 0, 0], ["ing_02"], [1, 1, 0]],
	[[0, 0, 0], ["ing_02*"], [0, 0, 2]],
	[[0, 0, 0], ["ing_03"], [1, 1, 0]],
	[[0, 0, 0], ["ing_03*"], [0, 0, 2]],
	[[0, 0, 0], ["ing_04"], [2, 0, 0]],
	[[0, 0, 0], ["ing_04*"], [0, 1, 1]],
	[[0, 0, 0], ["ing_06"], [2, 0, 2]],
	[[0, 0, 0], ["ing_06*"], [2, 2, 0]],
	[[1, 2, 0], ["ing_01"], [1, 1, 1]],
	[[1, 2, 0], ["ing_01*"], [0, 2, 1]],
	[[1, 2, 0], ["ing_02"], [2, 0, 0]],
	[[1, 2, 0], ["ing_02*"], [1, 2, 2]],
	[[1, 2, 0], ["ing_03"], [1, 2, 2]],
	[[1, 2, 0], ["ing_03*"], [2, 0, 0]],
	[[1, 2, 0], ["ing_04"], [1, 0, 1]],
	[[1, 2, 0], ["ing_04*"], [0, 2, 0]],
	[[1, 2, 0], ["ing_06"], [2, 2, 2]],
	[[1, 2, 0], ["ing_06*"], [2, 2, 0]],
	[[2, 1, 1], ["ing_01"], [2, 0, 1]],
	[[2, 1, 1], ["ing_01*"], [1, 1, 1]],
	[[2, 1, 1], ["ing_02"], [0, 2, 1]],
	[[2, 1, 1], ["ing_02*"], [2, 1, 0]],
	[[2, 1, 1], ["ing_03"], [2, 1, 0]],
	[[2, 1, 1], ["ing_03*"], [0, 2, 1]],
	[[2, 1, 1], ["ing_04"], [2, 2, 2]],
	[[2, 1, 1], ["ing_04*"], [1, 1, 1]],
	[[2, 1, 1], ["ing_06"], [2, 1, 0]],
	[[2, 1, 1], ["ing_06*"], [2, 2, 1]],
]

## Sequences: the ing_05 modifier (D1, D2) and conditionals that read an earlier Ingredient.
const SEQUENCE_CASES := [
	[[0, 0, 0], ["ing_05", "ing_06"], [2, 0, 0]],
	[[0, 0, 0], ["ing_05*", "ing_06"], [0, 0, 2]],
	[[0, 0, 0], ["ing_05", "ing_01"], [0, 0, 0]],
	[[0, 0, 0], ["ing_05*", "ing_04"], [0, 0, 0]],
	[[0, 0, 0], ["ing_05", "ing_05", "ing_02"], [1, 1, 0]],
	[[0, 0, 0], ["ing_05*", "ing_05", "ing_02"], [1, 1, 0]],
	[[0, 0, 0], ["ing_02", "ing_05"], [1, 1, 0]],  # a trailing ing_05 does nothing (GDD 11.2)
	[[0, 0, 0], ["ing_04", "ing_04", "ing_04"], [2, 2, 2]],  # needs supply > 1; logic only
	[[0, 0, 0], ["ing_03", "ing_03"], [1, 1, 2]],
]

## Cases worked out by hand from the effect texts, not from the Python model. Each one
## targets a rule that a misreading would get wrong.
const HAND_CASES := [
	# ing_03* checks Taste = 1 (not 0), so the else branch runs; then ing_06 sets Nature to 2.
	[[0, 1, 2], ["ing_03*", "ing_06"], [2, 2, 1]],
	# ing_06 makes Nature 2, so ing_04's condition (Nature = 0) is now false: else branch.
	[[0, 0, 0], ["ing_06", "ing_04"], [2, 1, 0]],
	# ing_05* masks Nature, which ing_06 sets with "=" (not "+="); Smell still loops 1 -> 0.
	[[1, 1, 1], ["ing_05*", "ing_06"], [1, 1, 0]],
	# ing_05 masks Taste and Smell; ing_03's condition still reads the Brew normally.
	[[0, 0, 0], ["ing_05", "ing_03"], [1, 0, 0]],
	# Smell 2 + 2 Steps loops to 1.
	[[2, 2, 2], ["ing_02*"], [2, 2, 1]],
]

var _failures := 0
var _effects: IngredientEffects
var _game_data: Node


func _initialize() -> void:
	# Autoloads run _ready() after _initialize(), so wait one frame for GameData to load.
	# A -s script is compiled before autoloads are registered, so the global name
	# GameData does not exist here; fetch the node from the tree instead.
	await process_frame
	_game_data = root.get_node("GameData")
	_effects = IngredientEffects.new(_game_data.rows("ingredients"), _game_data.rows("parameters"))

	_check_all_effects_parsed()
	for cases: Array in [SINGLE_CASES, SEQUENCE_CASES, HAND_CASES]:
		for case: Array in cases:
			_run_case(case[0], case[1], case[2])
	_check_mask_left_pending()

	print("\n%s: %d check(s) failed" % ["FAIL" if _failures else "PASS", _failures])
	quit(1 if _failures else 0)


## Every Ingredient in the Data Sheet must parse in both Forms, or the cases below
## would fail with a confusing message.
func _check_all_effects_parsed() -> void:
	for row: Dictionary in _game_data.rows("ingredients"):
		var id: String = row["ingredient_id"]
		_check("%s parses in both Forms" % id, _effects.has_ingredient(id), true)


func _run_case(start: Array, added: Array, expected: Array) -> void:
	var brew := _brew_at(start)
	for token: String in added:
		_effects.apply(brew, token.trim_suffix("*"), token.ends_with("*"))
	_check("%s > %s" % [start, " > ".join(added)], brew.get_states(), expected)


## A modifier added last has nothing to mask yet, so its mask must still be pending
## (it is cleared later by Empty or Serve, which call brew.reset()).
func _check_mask_left_pending() -> void:
	var brew := _brew_at([0, 0, 0])
	_effects.apply(brew, "ing_05", false)
	_check("a trailing ing_05 leaves its mask pending", brew.pending_mask, [1, 2])


func _brew_at(states: Array) -> Brew:
	var brew := Brew.new(states.size())
	for p in states.size():
		brew.set_state(p, states[p])
	return brew


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  %s: expected %s, got %s" % [label, expected, actual])
