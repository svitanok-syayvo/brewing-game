class_name DayState
extends RefCounted
## Everything that lasts for one Day: the Brew, the supply and Form of each Ingredient,
## whether the Shifter has been used, the Requests still waiting, the Gold Coins and the
## Resolution of each served Request (GDD 4–7).
##
## Pure logic with no Node dependencies, so tests can run it headless. Views read it and
## redraw on `changed` (and on `brew.changed`); they hold no rules of their own.
##
## Actions: add_ingredient() and empty_brew() (T8), select_request() (T9), serve() (T10)
## and shift() (T11).

## Emitted after anything this DayState holds has changed (not the Brew: see brew.changed).
signal changed
## Emitted once, after the last waiting Request of the Day has been served (GDD 7.1).
## `results` then holds the Resolution of every Request of the Day.
signal day_ended

## What add_ingredient() did. Anything but ADDED means nothing changed.
enum AddResult {
	ADDED,
	## The Ingredient has 0 left today (GDD 5.4).
	NONE_LEFT,
	## The Brewing Station already holds 3 Ingredients (GDD 4.3).
	BREW_FULL,
	## The ID is not an Ingredient in the Data Sheet.
	UNKNOWN,
}

## What shift() did. Anything but SHIFTED means nothing changed.
enum ShiftResult {
	SHIFTED,
	## The Shifter's 1 use today is already spent (GDD 5.3).
	SHIFTER_USED,
	## The Ingredient has 0 left today, so there is nothing to shift (D5).
	NONE_LEFT,
	## The ID is not an Ingredient in the Data Sheet.
	UNKNOWN,
}

var day := 0
var brew: Brew
## Gold Coins earned so far. They carry over between Days, so start_day() keeps them.
var coins := 0
var shifter_used := false
## request_id -> true for 'Success', false for 'Failure', in the order they were served.
## Filled by serve(); the Day Consequences screen (T12) reads it.
var results: Dictionary[String, bool] = {}

## Ingredient IDs in Data Sheet order, so the tray always shows them in the same order.
var _ingredient_ids: Array[String] = []
var _effects: IngredientEffects
## Parameter IDs in Data Sheet order, so index p of the Brew is _parameter_ids[p].
var _parameter_ids: Array[String] = []
var _supply_rows: Array = []
var _request_rows: Array = []
## ingredient_id -> units left today.
var _supply: Dictionary[String, int] = {}
## ingredient_id -> true while that Ingredient is in its Shifted Form (decision D3).
var _shifted: Dictionary[String, bool] = {}
## Request IDs not yet served today, in Data Sheet order.
var _waiting: Array[String] = []
## The Request of the Client the player is talking to, or "" when none is waiting. Serve
## (T10) resolves this one. Switching it never touches the Brew (GDD 4.2, 6.1).
var _current_request := ""


## Rows come from GameData: rows("parameters"), rows("ingredients"), rows("supply"),
## rows("requests"). Call start_day() before reading anything.
func _init(parameter_rows: Array, ingredient_rows: Array, supply_rows: Array, request_rows: Array) -> void:
	brew = Brew.new(parameter_rows.size())
	_effects = IngredientEffects.new(ingredient_rows, parameter_rows)
	for row: Dictionary in parameter_rows:
		_parameter_ids.append(row["parameter_id"])
	for row: Dictionary in ingredient_rows:
		_ingredient_ids.append(row["ingredient_id"])
	_supply_rows = supply_rows
	_request_rows = request_rows


## Starts Day n (counted from 1): fresh supply from the Data Sheet's "day_n" column, every
## Ingredient back in Normal Form, an unused Shifter, a new Brew and that Day's Requests.
## Leftover supply from the previous Day is discarded (GDD 5.4).
func start_day(n: int) -> void:
	day = n
	shifter_used = false
	results.clear()

	var column := "day_%d" % n
	_supply.clear()
	_shifted.clear()
	for id: String in _ingredient_ids:
		_supply[id] = 0
		_shifted[id] = false
	for row: Dictionary in _supply_rows:
		var id: String = row["ingredient_id"]
		if not _supply.has(id):
			push_error("DayState: supply row for unknown Ingredient '%s'" % id)
			continue
		_supply[id] = int(row.get(column, 0))

	_waiting.clear()
	for row: Dictionary in _request_rows:
		if int(row.get("day", 0)) == n:
			_waiting.append(row["request_id"])
	if _waiting.is_empty():
		push_error("DayState: Day %d has no Requests in the Data Sheet" % n)
	_current_request = _waiting[0] if not _waiting.is_empty() else ""

	brew.reset()
	changed.emit()


func ingredient_ids() -> Array[String]:
	return _ingredient_ids.duplicate()


## Units of an Ingredient left today. Returns 0 for an unknown ID.
func supply_of(ingredient_id: String) -> int:
	return _supply.get(ingredient_id, 0)


func is_shifted(ingredient_id: String) -> bool:
	return _shifted.get(ingredient_id, false)


## The parsed effect of one Form of an Ingredient (read-only, for tooltips, T13), or null
## for an unknown ID.
func get_effect(ingredient_id: String, shifted: bool) -> IngredientEffect:
	return _effects.get_effect(ingredient_id, shifted)


## Request IDs still waiting to be served today, in Data Sheet order.
func waiting_requests() -> Array[String]:
	return _waiting.duplicate()


func requests_left() -> int:
	return _waiting.size()


## True once every Client of the Day has been served (GDD 7.1).
func is_day_over() -> bool:
	return day > 0 and _waiting.is_empty()


## The Request of the selected Client, or "" when no Client is waiting.
func current_request() -> String:
	return _current_request


## Switches to another waiting Client (GDD 6.1: all Clients are present at once and can be
## served in any order). Only the selection changes: the Brew, its pending ing_05 modifier,
## the supply and the Forms stay as they are (GDD 4.2). Returns false, and changes nothing,
## for a Request that is not waiting today.
func select_request(request_id: String) -> bool:
	if not _waiting.has(request_id):
		push_error("DayState: Request '%s' is not waiting today" % request_id)
		return false
	if request_id != _current_request:
		_current_request = request_id
		changed.emit()
	return true


## Adds one unit of an Ingredient, in its current Form, to the Brew (GDD 4.3, 5.1–5.4).
## On success it uses up one unit of supply and one of the Brewing Station's 3 slots, and
## a Shifted Ingredient goes back to Normal, because a shift lasts for 1 use (GDD 5.3, D3).
## A blocked add changes nothing and emits nothing; the view decides how to show it.
func add_ingredient(ingredient_id: String) -> AddResult:
	if not _supply.has(ingredient_id) or not _effects.has_ingredient(ingredient_id):
		push_error("DayState: unknown Ingredient '%s'" % ingredient_id)
		return AddResult.UNKNOWN
	if _supply[ingredient_id] <= 0:
		return AddResult.NONE_LEFT
	# Take the slot first: count_ingredient() refuses a full Brew without changing it.
	if not brew.count_ingredient():
		return AddResult.BREW_FULL

	_effects.apply(brew, ingredient_id, _shifted[ingredient_id])
	_supply[ingredient_id] -= 1
	_shifted[ingredient_id] = false
	changed.emit()
	return AddResult.ADDED


## The Shifter (GDD 5.3): switches an Ingredient between its Normal and Shifted Form and
## spends the Shifter's 1 use for the Day. The use is spent now, even if the Ingredient is
## never added. The Form belongs to the Ingredient's stack, and the next unit added uses it
## and goes back to Normal (D3, see add_ingredient()). The Brew is not touched.
## Blocked, with no change and no signal, once the Shifter is used or when the Ingredient
## has 0 left (D5). Checks run in that order, so a used Shifter is reported first.
func shift(ingredient_id: String) -> ShiftResult:
	if not _supply.has(ingredient_id):
		push_error("DayState: unknown Ingredient '%s'" % ingredient_id)
		return ShiftResult.UNKNOWN
	if shifter_used:
		return ShiftResult.SHIFTER_USED
	if _supply[ingredient_id] <= 0:
		return ShiftResult.NONE_LEFT
	_shifted[ingredient_id] = not _shifted[ingredient_id]
	shifter_used = true
	changed.emit()
	return ShiftResult.SHIFTED


## Empty (GDD 4.4): the Brew goes back to State 0 on every Parameter with no Ingredients
## and no pending modifier. The Ingredients already added are lost: supply is not
## refunded, and the Forms of the Ingredients still in the tray do not change.
func empty_brew() -> void:
	brew.reset()


## Serve (GDD 4.4, 6.2–6.4): resolves the selected Client's Request against the Brew as it
## is now. 'Success' needs every requested Parameter in its target State; anything else is
## 'Failure', with no partial credit. 'Success' pays the Request's maximum_coins and
## 'Failure' pays 0. Serving an empty Brew is allowed: it is how a Request is refused (D11).
##
## Then the Client leaves, a new Brew starts (the pending ing_05 modifier goes too; supply
## is not refunded), and the next waiting Client is selected. Serving the last one ends the
## Day. Returns {"request_id", "success", "coins"}, or {} if no Client is waiting.
func serve() -> Dictionary:
	if _current_request.is_empty():
		push_error("DayState: no Client is waiting to be served")
		return {}
	var request_id := _current_request
	var request := _request_row(request_id)
	var success := is_success(request)
	var gained := int(request.get("maximum_coins", 0)) if success else 0

	coins += gained
	results[request_id] = success
	var index := _waiting.find(request_id)
	_waiting.remove_at(index)
	# The Client to the right takes the served one's place; after the last, the one before.
	_current_request = _waiting[mini(index, _waiting.size() - 1)] if not _waiting.is_empty() else ""
	brew.reset()

	if _waiting.is_empty():
		_end_day()
	changed.emit()
	if _waiting.is_empty():
		day_ended.emit()
	return {"request_id": request_id, "success": success, "coins": gained}


## True if every Parameter the Request names ("param_NN_target") is in that State in the
## Brew. Parameters set to "any" in the Data Sheet have no key and are ignored (GDD 6.2).
func is_success(request: Dictionary) -> bool:
	for p: int in _parameter_ids.size():
		var key := "%s_target" % _parameter_ids[p]
		if request.has(key) and brew.get_state(p) != int(request[key]):
			return false
	return true


## The Day is over (GDD 5.4, 7.1): unused Ingredients disappear and are worth nothing.
func _end_day() -> void:
	for id: String in _supply:
		_supply[id] = 0
		_shifted[id] = false


func _request_row(request_id: String) -> Dictionary:
	for row: Dictionary in _request_rows:
		if row.get("request_id", "") == request_id:
			return row
	return {}
