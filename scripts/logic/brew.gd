class_name Brew
extends RefCounted
## The Brew in the Brewing Station: the current State of each Parameter, how many
## Ingredients have gone in, and the pending ing_05 modifier (GDD 4.1–4.4, 5.1).
##
## Pure logic with no Node dependencies, so tests can run it headless. The Brew does not
## know what any Ingredient does: Ingredient effects (T5) change it only through
## set_state() and step(), so the looping rule lives in one place.
##
## Parameters are addressed by index, counted from 0 in the order of GameData's
## "parameters" table, so index 0 is param_01. States are counted from 0 (State 0, 1, 2).

## Emitted after anything the Brew holds has changed. Views redraw from get_states().
signal changed

## GDD 4.1: each Parameter has 3 States, and a Step moves 0 → 1 → 2 → 0.
const STATE_COUNT := 3
## GDD 4.3: the Brewing Station holds at most 3 Ingredients per Brew.
const MAX_INGREDIENTS := 3

## Parameter indices that the next Ingredient added cannot change (the ing_05 modifier,
## GDD 5.1 and decision D1). Empty means no modifier is pending. Ingredient effects (T5)
## set it, apply it and clear it; reset() also clears it. It is not shown to the player,
## so changing it does not emit `changed`.
var pending_mask: Array[int] = []

var _states: Array[int] = []
var _ingredient_count := 0


## parameter_count comes from the Data Sheet: GameData.rows("parameters").size().
func _init(parameter_count: int) -> void:
	_states.resize(parameter_count)
	_states.fill(0)


func parameter_count() -> int:
	return _states.size()


## The State (0, 1 or 2) of Parameter p. Returns -1 for an invalid index.
func get_state(p: int) -> int:
	if not _is_valid_parameter(p):
		return -1
	return _states[p]


## A copy of every State, in Parameter order. Changing the copy does not change the Brew.
func get_states() -> Array[int]:
	return _states.duplicate()


## Sets Parameter p to State v (the "param = n" effect).
func set_state(p: int, v: int) -> void:
	if not _is_valid_parameter(p):
		return
	if v < 0 or v >= STATE_COUNT:
		push_error("Brew: State %d is out of range for Parameter %d (valid: 0–%d)" % [v, p, STATE_COUNT - 1])
		return
	if _states[p] == v:
		return
	_states[p] = v
	changed.emit()


## Moves Parameter p forward by n Steps, looping past the last State back to State 0
## (the "param += n" effect).
func step(p: int, n: int = 1) -> void:
	if not _is_valid_parameter(p):
		return
	# posmod, not %: in GDScript (-1) % 3 is -1, but posmod(-1, 3) is 2, so a negative
	# n still lands on a real State. set_state() handles the "no change, no signal" rule.
	set_state(p, posmod(_states[p] + n, STATE_COUNT))


func get_ingredient_count() -> int:
	return _ingredient_count


func is_full() -> bool:
	return _ingredient_count >= MAX_INGREDIENTS


## Takes up one of the Brewing Station's slots for an Ingredient. Returns false, and
## changes nothing, if the Brew is already full. Call this before applying the effect.
func count_ingredient() -> bool:
	if is_full():
		return false
	_ingredient_count += 1
	changed.emit()
	return true


## Starts a new Brew at State 0 on every Parameter, with no Ingredients and no pending
## modifier. Used by Empty, after Serve and at the start of a Day (GDD 4.4).
func reset() -> void:
	_states.fill(0)
	_ingredient_count = 0
	pending_mask.clear()
	changed.emit()


func _is_valid_parameter(p: int) -> bool:
	if p < 0 or p >= _states.size():
		push_error("Brew: no Parameter at index %d (valid: 0–%d)" % [p, _states.size() - 1])
		return false
	return true
