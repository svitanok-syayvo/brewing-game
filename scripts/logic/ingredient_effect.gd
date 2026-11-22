class_name IngredientEffect
extends RefCounted
## The effect of one Form (Normal or Shifted) of one Ingredient, parsed from the Data
## Sheet's effect notation (GDD 5.2). Parse once with IngredientEffect.parse(), then
## run() it against a Brew as many times as needed.
##
## Grammar (keywords are case-insensitive, Parameters are IDs such as param_02):
##   effect   := cond | actions | modifier
##   cond     := "if" PARAM "=" N "then" actions "else" actions
##   actions  := action ("and" action)*
##   action   := PARAM "=" N | PARAM "+=" N
##   modifier := "the next ingredient added has no effect on" PARAM ("and" PARAM)*
##
## run() does not handle the pending ing_05 modifier on the Brew (D1, D2); that is
## IngredientEffects.apply()'s job, because it spans two Ingredients.

enum Kind {
	ACTIONS,     ## Apply `actions` in order.
	CONDITIONAL, ## Apply `actions` if the condition holds, else `else_actions`.
	MODIFIER,    ## Mask `masked_parameters` for the next Ingredient (ing_05).
}

const MODIFIER_PREFIX := "the next ingredient added has no effect on"


## One "param = n" (is_set) or "param += n" (not is_set) action.
class Action:
	var parameter: int
	var is_set: bool
	var amount: int


var kind := Kind.ACTIONS
## For ACTIONS: every action. For CONDITIONAL: the "then" branch.
var actions: Array[Action] = []
## For CONDITIONAL: the "else" branch.
var else_actions: Array[Action] = []
## For CONDITIONAL: the Parameter index and State that the condition compares.
var condition_parameter := -1
var condition_state := -1
## For MODIFIER: the Parameter indices the next Ingredient cannot change.
var masked_parameters: Array[int] = []


## Parses Data Sheet notation. parameter_ids lists the Parameter IDs in Brew index
## order (index 0 is param_01). Returns null and pushes an error if the text is invalid.
static func parse(text: String, parameter_ids: Array) -> IngredientEffect:
	var effect := IngredientEffect.new()
	var source := text.strip_edges().to_lower()

	if source.begins_with(MODIFIER_PREFIX):
		effect.kind = Kind.MODIFIER
		var rest := source.substr(MODIFIER_PREFIX.length())
		for part: String in rest.split(" and ", false):
			var p := parameter_ids.find(part.strip_edges())
			if p == -1:
				return _fail(text, "unknown Parameter '%s'" % part.strip_edges())
			effect.masked_parameters.append(p)
		if effect.masked_parameters.is_empty():
			return _fail(text, "the modifier names no Parameter")
		return effect

	if source.begins_with("if "):
		effect.kind = Kind.CONDITIONAL
		var then_at := source.find(" then ")
		var else_at := source.find(" else ")
		if then_at == -1 or else_at == -1 or else_at < then_at:
			return _fail(text, "expected 'if … then … else …'")
		var condition := _parse_action(source.substr(3, then_at - 3), parameter_ids)
		if condition == null or not condition.is_set:
			return _fail(text, "the condition must be 'param_NN = N'")
		effect.condition_parameter = condition.parameter
		effect.condition_state = condition.amount
		var then_part := source.substr(then_at + 6, else_at - then_at - 6)
		var else_part := source.substr(else_at + 6)
		if not _parse_actions(then_part, parameter_ids, effect.actions):
			return _fail(text, "bad 'then' branch")
		if not _parse_actions(else_part, parameter_ids, effect.else_actions):
			return _fail(text, "bad 'else' branch")
		return effect

	if not _parse_actions(source, parameter_ids, effect.actions):
		return _fail(text, "expected actions such as 'param_01 += 1 and param_02 = 2'")
	return effect


## Changes the Brew by this effect. A condition is checked against the Brew as it is
## before any action of this effect runs (GDD 5.2).
func run(brew: Brew) -> void:
	match kind:
		Kind.ACTIONS:
			_run_actions(brew, actions)
		Kind.CONDITIONAL:
			var holds := brew.get_state(condition_parameter) == condition_state
			_run_actions(brew, actions if holds else else_actions)
		Kind.MODIFIER:
			brew.pending_mask = masked_parameters.duplicate()


func is_modifier() -> bool:
	return kind == Kind.MODIFIER


static func _run_actions(brew: Brew, list: Array[Action]) -> void:
	for action in list:
		if action.is_set:
			brew.set_state(action.parameter, action.amount)
		else:
			brew.step(action.parameter, action.amount)


## Parses "action and action …" into `into`. Returns false if any action is invalid.
static func _parse_actions(text: String, parameter_ids: Array, into: Array[Action]) -> bool:
	var parts := text.split(" and ", false)
	if parts.is_empty():
		return false
	for part: String in parts:
		var action := _parse_action(part, parameter_ids)
		if action == null:
			return false
		into.append(action)
	return true


## Parses "param_NN = N" or "param_NN += N". Returns null if invalid.
static func _parse_action(text: String, parameter_ids: Array) -> Action:
	var tokens := text.strip_edges().split(" ", false)
	if tokens.size() != 3 or not tokens[2].is_valid_int():
		return null
	var p := parameter_ids.find(tokens[0])
	if p == -1 or tokens[1] not in ["=", "+="]:
		return null
	var action := Action.new()
	action.parameter = p
	action.is_set = tokens[1] == "="
	action.amount = tokens[2].to_int()
	if action.is_set and (action.amount < 0 or action.amount >= Brew.STATE_COUNT):
		return null
	return action


static func _fail(text: String, reason: String) -> IngredientEffect:
	push_error("IngredientEffect: cannot parse '%s': %s" % [text, reason])
	return null
