class_name ConsequenceText
extends RefCounted
## What the Day Consequences screen says about each served Request (GDD 7.2). Pure logic,
## so tests can check it headless.
##
## The Data Sheet's `success_text` / `failure_text` wins. While a cell is empty (decision
## D7) a placeholder naming the Resolution is shown, so the Day can still end. The text is
## flavour only and has no gameplay effect.

const PLACEHOLDER_PREFIX := "[placeholder] "


## The flavour text for one Request: its success_text on 'Success', its failure_text on
## 'Failure'. request: one row of GameData.rows("requests").
static func describe(request: Dictionary, success: bool) -> String:
	var text := str(request.get("success_text" if success else "failure_text", "")).strip_edges()
	if not text.is_empty():
		return text
	return PLACEHOLDER_PREFIX + "%s, no consequence written yet." % resolution_name(success)


static func resolution_name(success: bool) -> String:
	return "Success" if success else "Failure"


## One entry per served Request, in the order they were served (DayState.results keeps it):
## {"request_id", "character_name", "success", "coins", "text"}. coins is the Request's
## maximum_coins on 'Success' and 0 on 'Failure' (GDD 6.4). A Request or Character missing
## from the rows falls back to its ID, so a data gap shows up on screen instead of crashing.
static func entries(results: Dictionary, request_rows: Array, character_rows: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for request_id: String in results:
		var success: bool = results[request_id]
		var request := _find(request_rows, "request_id", request_id)
		if request.is_empty():
			push_error("ConsequenceText: unknown Request '%s'" % request_id)
		var character_id: String = request.get("character_id", "")
		var character := _find(character_rows, "character_id", character_id)
		out.append({
			"request_id": request_id,
			"character_name": character.get("name", character_id if not character_id.is_empty() else request_id),
			"success": success,
			"coins": int(request.get("maximum_coins", 0)) if success else 0,
			"text": describe(request, success),
		})
	return out


static func _find(rows: Array, id_key: String, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.get(id_key, "") == id:
			return row
	return {}
