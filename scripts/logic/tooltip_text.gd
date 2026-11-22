class_name TooltipText
extends RefCounted
## The hover texts of the shop screen (T13, GDD 8.2). Pure logic, so tests can check them
## headless. Every name comes from the Data Sheet rows passed in; IDs never reach the text.
##
## Ingredient tooltips describe the effect of the Ingredient's current Form only. The other
## Form is added only when `show_other_form` is true (Config.SHOW_SHIFTED_IN_TOOLTIP, D6).

const FORM_NAMES := ["Normal", "Shifted"]


## A readable effect, for example
## "If Potency is Awakened: Nature +1 Step, Potency +1 Step;\n otherwise: Side Effects +2 Steps."
## A conditional puts "otherwise" on its own line, so the two branches are easy to tell apart.
## parameter_rows: GameData.rows("parameters"), in Brew index order.
static func effect(parsed: IngredientEffect, parameter_rows: Array) -> String:
	if parsed == null:
		return "Unknown effect."
	match parsed.kind:
		IngredientEffect.Kind.CONDITIONAL:
			var row: Dictionary = parameter_rows[parsed.condition_parameter]
			return "If %s is %s: %s;\notherwise: %s." % [
				RequestText.parameter_name(row),
				RequestText.state_name(row, parsed.condition_state),
				_actions(parsed.actions, parameter_rows),
				_actions(parsed.else_actions, parameter_rows),
			]
		IngredientEffect.Kind.MODIFIER:
			var names: PackedStringArray = []
			for p: int in parsed.masked_parameters:
				names.append(RequestText.parameter_name(parameter_rows[p]))
			return "The next Ingredient added has no effect on %s." % " or ".join(names)
		_:
			return _actions(parsed.actions, parameter_rows) + "."


## The whole Ingredient tooltip: name and Form, the Data Sheet description if any, and
## the effect of the current Form. The other Form's effect follows only if show_other_form.
static func ingredient(ingredient_row: Dictionary, shifted: bool, current: IngredientEffect,
		other: IngredientEffect, parameter_rows: Array, show_other_form: bool) -> String:
	var lines: PackedStringArray = []
	var display_name: String = ingredient_row.get("name", ingredient_row.get("ingredient_id", "?"))
	lines.append("%s (%s Form)" % [display_name, FORM_NAMES[int(shifted)]])
	var description := str(ingredient_row.get("description", "")).strip_edges()
	if not description.is_empty():
		lines.append(description)
	lines.append("If added now: %s" % effect(current, parameter_rows))
	if show_other_form:
		lines.append("%s Form: %s" % [FORM_NAMES[int(not shifted)], effect(other, parameter_rows)])
	return "\n".join(lines)


## One Parameter and its 3 States in loop order (GDD 4.1).
static func parameter(parameter_row: Dictionary) -> String:
	var states: PackedStringArray = []
	for s: int in Brew.STATE_COUNT:
		states.append(RequestText.state_name(parameter_row, s))
	return "%s: %s → back to %s.\nEach Step moves it one State along the loop." % [
		RequestText.parameter_name(parameter_row),
		" → ".join(states),
		states[0],
	]


## The Shifter's general effect from the Data Sheet and whether today's use is left (GDD 5.3).
static func shifter(tool_row: Dictionary, used: bool) -> String:
	var effect_text := str(tool_row.get("effect", "")).strip_edges()
	if not effect_text.is_empty() and not effect_text.ends_with("."):
		effect_text += "."
	var how := "Pick up an Ingredient and place it here. The shift lasts until that Ingredient is added."
	var status := "Already used today." if used else "1 use left today."
	return "\n".join([effect_text, how, status])


## GDD 6.3: no partial credit, and serving an empty Brew is a way to refuse (D11).
static func serve() -> String:
	return "\n".join([
		"Give the Brew to the selected Client.",
		"'Success' only if every Parameter they asked for is in the right State; anything else is 'Failure' and pays 0 Gold Coins.",
		"The Client then leaves and a new Brew starts.",
	])


## GDD 4.4: Empty resets the Brew to State 0 everywhere; used Ingredients are lost.
static func empty(parameter_rows: Array) -> String:
	var starts: PackedStringArray = []
	for row: Dictionary in parameter_rows:
		starts.append("%s %s" % [RequestText.parameter_name(row), RequestText.state_name(row, 0)])
	return "Start the Brew again: %s.\nThe Ingredients already added are lost." % ", ".join(starts)


## "Nature +1 Step, Side Effects becomes Stable", in the order they apply.
static func _actions(list: Array[IngredientEffect.Action], parameter_rows: Array) -> String:
	var parts: PackedStringArray = []
	for action in list:
		var row: Dictionary = parameter_rows[action.parameter]
		if action.is_set:
			parts.append("%s becomes %s" % [RequestText.parameter_name(row), RequestText.state_name(row, action.amount)])
		else:
			parts.append("%s +%d Step%s" % [RequestText.parameter_name(row), action.amount, "" if action.amount == 1 else "s"])
	return ", ".join(parts)
