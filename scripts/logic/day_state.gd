class_name DayState
extends RefCounted
## Everything that lasts for one Day: the Brew, the supply and Form of each Ingredient,
## whether the Shifter has been used, the Requests still waiting, the Gold Coins and the
## Resolution of each served Request (GDD 4–7).
##
## Pure logic with no Node dependencies, so tests can run it headless. Views read it and
## redraw on `changed` (and on `brew.changed`); they hold no rules of their own.
##
## Actions so far: add_ingredient() and empty_brew() (T8), select_request() (T9). The
## Shifter (T11) and Serve (T10) are still to come.

## Emitted after anything this DayState holds has changed (not the Brew: see brew.changed).
signal changed

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

var day := 0
var brew: Brew
## Gold Coins earned so far. They carry over between Days, so start_day() keeps them.
var coins := 0
var shifter_used := false
## request_id -> true for 'Success', false for 'Failure'. Filled by Serve (T10).
var results: Dictionary[String, bool] = {}

## Ingredient IDs in Data Sheet order, so the tray always shows them in the same order.
var _ingredient_ids: Array[String] = []
var _effects: IngredientEffects
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


## Request IDs still waiting to be served today, in Data Sheet order.
func waiting_requests() -> Array[String]:
	return _waiting.duplicate()


func requests_left() -> int:
	return _waiting.size()


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


## Empty (GDD 4.4): the Brew goes back to State 0 on every Parameter with no Ingredients
## and no pending modifier. The Ingredients already added are lost: supply is not
## refunded, and the Forms of the Ingredients still in the tray do not change.
func empty_brew() -> void:
	brew.reset()
