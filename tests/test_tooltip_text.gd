extends SceneTree
## Headless checks for TooltipText, the hover texts of the shop screen (T13). Run:
##   godot --headless --path . -s tests/test_tooltip_text.gd
## Prints PASS or FAIL per check and exits with code 1 if any check failed.
##
## It describes the real Data Sheet effects, so it also checks that no ID or "State n"
## leaks into what the player reads.

var _failures := 0


func _initialize() -> void:
	# Autoloads run _ready() after _initialize(), so wait a frame for GameData to load,
	# and look it up by path: the global name is not known when a -s script is compiled.
	await process_frame
	var data: Node = root.get_node("GameData")
	var parameters: Array = data.rows("parameters")
	var ingredients: Array = data.rows("ingredients")
	var effects := IngredientEffects.new(ingredients, parameters)

	_test_effect_shapes(parameters)
	_test_every_effect(effects, ingredients, parameters)
	_test_ingredient_forms(effects, data.row("ingredients", "ing_03"), parameters)
	_test_others(parameters, data.rows("tools"))

	print("%s: %d failure(s)" % ["FAIL" if _failures > 0 else "PASS", _failures])
	quit(1 if _failures > 0 else 0)


## Each kind of effect, with hand-made notation and fixed names, so the exact wording is pinned.
func _test_effect_shapes(parameters: Array) -> void:
	var ids: Array = parameters.map(func(r: Dictionary) -> String: return r["parameter_id"])
	var p1 := RequestText.parameter_name(parameters[0])
	var p2 := RequestText.parameter_name(parameters[1])
	var p3 := RequestText.parameter_name(parameters[2])

	var conditional := IngredientEffect.parse("if param_02 = 0 then param_01 += 1 and param_02 += 1 else param_03 += 2", ids)
	var expected := "If %s is %s: %s +1 Step, %s +1 Step;\notherwise: %s +2 Steps." % [
		p2, RequestText.state_name(parameters[1], 0), p1, p2, p3]
	_check("conditional shows both branches", TooltipText.effect(conditional, parameters) == expected)

	var setting := IngredientEffect.parse("param_03 = 1 and param_02 += 2", ids)
	_check("'=' reads 'becomes <State>', in order",
		TooltipText.effect(setting, parameters) == "%s becomes %s, %s +2 Steps." % [p3, RequestText.state_name(parameters[2], 1), p2])

	var modifier := IngredientEffect.parse("the next ingredient added has no effect on param_02 and param_03", ids)
	_check("modifier names the masked Parameters",
		TooltipText.effect(modifier, parameters) == "The next Ingredient added has no effect on %s or %s." % [p2, p3])
	_check("a null effect does not crash", TooltipText.effect(null, parameters) == "Unknown effect.")


## All 12 Data Sheet effects read as names only.
func _test_every_effect(effects: IngredientEffects, ingredients: Array, parameters: Array) -> void:
	var id_pattern := RegEx.create_from_string("param_\\d|ing_\\d|State \\d")
	for row: Dictionary in ingredients:
		var id: String = row["ingredient_id"]
		for shifted: bool in [false, true]:
			var text := TooltipText.effect(effects.get_effect(id, shifted), parameters)
			var label := "%s%s" % [id, "*" if shifted else ""]
			_check("%s has text" % label, text.length() > 10)
			_check("%s shows no IDs: %s" % [label, text], id_pattern.search(text) == null)


## D6: the other Form is hidden unless the flag is on, in both directions.
func _test_ingredient_forms(effects: IngredientEffects, row: Dictionary, parameters: Array) -> void:
	var normal_text := TooltipText.effect(effects.get_effect("ing_03", false), parameters)
	var shifted_text := TooltipText.effect(effects.get_effect("ing_03", true), parameters)
	_check("ing_03's two Forms read differently", normal_text != shifted_text)

	var hidden := TooltipText.ingredient(row, false, effects.get_effect("ing_03", false), effects.get_effect("ing_03", true), parameters, false)
	_check("Normal tooltip names the Ingredient and Form", hidden.begins_with("%s (Normal Form)" % row["name"]))
	_check("Normal tooltip shows the Normal effect", hidden.contains(normal_text))
	_check("Normal tooltip hides the Shifted effect", not hidden.contains(shifted_text) and not hidden.contains("Shifted"))

	var shifted := TooltipText.ingredient(row, true, effects.get_effect("ing_03", true), effects.get_effect("ing_03", false), parameters, false)
	_check("Shifted tooltip says Shifted Form", shifted.begins_with("%s (Shifted Form)" % row["name"]))
	_check("Shifted tooltip shows the Shifted effect", shifted.contains(shifted_text))
	_check("Shifted tooltip hides the Normal effect", not shifted.contains(normal_text))

	var shown := TooltipText.ingredient(row, false, effects.get_effect("ing_03", false), effects.get_effect("ing_03", true), parameters, true)
	_check("with the flag on, Normal tooltip adds the Shifted effect", shown.contains("Shifted Form: " + shifted_text))
	_check("Config keeps the Shifted effect hidden by default (D6)", not Config.SHOW_SHIFTED_IN_TOOLTIP)

	var described := row.duplicate()
	described["description"] = "  A knobbly root.  "
	_check("a Data Sheet description is shown, trimmed",
		TooltipText.ingredient(described, false, effects.get_effect("ing_03", false), null, parameters, false).contains("\nA knobbly root.\n"))


func _test_others(parameters: Array, tools: Array) -> void:
	var loop := TooltipText.parameter(parameters[0])
	var s := func(n: int) -> String: return RequestText.state_name(parameters[0], n)
	_check("Parameter tooltip lists its States in loop order",
		loop.begins_with("%s: %s → %s → %s → back to %s." % [RequestText.parameter_name(parameters[0]), s.call(0), s.call(1), s.call(2), s.call(0)]))

	var unused := TooltipText.shifter(tools[0], false)
	var used := TooltipText.shifter(tools[0], true)
	_check("Shifter tooltip has the Data Sheet effect", unused.begins_with(str(tools[0]["effect"]).strip_edges()))
	_check("unused Shifter: 1 use left", unused.contains("1 use left today."))
	_check("used Shifter: already used", used.contains("Already used today.") and not used.contains("1 use left"))

	_check("Serve tooltip explains no partial credit", TooltipText.serve().contains("0 Gold Coins"))
	var empty := TooltipText.empty(parameters)
	for row: Dictionary in parameters:
		_check("Empty tooltip names %s at State 0" % row["parameter_id"],
			empty.contains("%s %s" % [RequestText.parameter_name(row), RequestText.state_name(row, 0)]))
	_check("Empty tooltip says Ingredients are lost", empty.contains("lost"))


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1
