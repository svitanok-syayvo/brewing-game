class_name DayState
extends RefCounted
## Everything that lasts for one Day: the Brew, the supply and Form of each Ingredient,
## whether the Shifter has been used, the Requests still waiting, the Gold Coins and the
## Resolution of each served Request (GDD 4–7).
##
## Pure logic with no Node dependencies, so tests can run it headless. Views read it and
## redraw on `changed` (and on `brew.changed`); they hold no rules of their own.
##
## T7 only needs the state the main screen shows. The actions that change it (adding an
## Ingredient, Empty, the Shifter, Serve) arrive with T8, T10 and T11.

## Emitted after anything this DayState holds has changed (not the Brew: see brew.changed).
signal changed

var day := 0
var brew: Brew
## Gold Coins earned so far. They carry over between Days, so start_day() keeps them.
var coins := 0
var shifter_used := false
## request_id -> true for 'Success', false for 'Failure'. Filled by Serve (T10).
var results: Dictionary[String, bool] = {}

## Ingredient IDs in Data Sheet order, so the tray always shows them in the same order.
var _ingredient_ids: Array[String] = []
var _supply_rows: Array = []
var _request_rows: Array = []
## ingredient_id -> units left today.
var _supply: Dictionary[String, int] = {}
## ingredient_id -> true while that Ingredient is in its Shifted Form (decision D3).
var _shifted: Dictionary[String, bool] = {}
## Request IDs not yet served today, in Data Sheet order.
var _waiting: Array[String] = []


## Rows come from GameData: rows("parameters"), rows("ingredients"), rows("supply"),
## rows("requests"). Call start_day() before reading anything.
func _init(parameter_rows: Array, ingredient_rows: Array, supply_rows: Array, request_rows: Array) -> void:
	brew = Brew.new(parameter_rows.size())
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
