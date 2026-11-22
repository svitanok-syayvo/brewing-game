class_name RequestText
extends RefCounted
## What a Client says in the speech bubble (GDD 6.1, 8.1). Pure logic, so tests can check
## it headless.
##
## The Data Sheet's `text` column wins. While it is empty (decision D7) a Specific text is
## generated from the target States and marked as a placeholder, so the Day can still be
## played. Parameters the Request does not name are left out, because they are ignored
## (GDD 6.2).

const PLACEHOLDER_PREFIX := "[placeholder] "


## request: one row of GameData.rows("requests"). parameter_rows: GameData.rows("parameters"),
## in Parameter order.
static func describe(request: Dictionary, parameter_rows: Array) -> String:
	var text := str(request.get("text", "")).strip_edges()
	if not text.is_empty():
		return text
	var parts: PackedStringArray = []
	for row: Dictionary in parameter_rows:
		var target: Variant = request.get("%s_target" % row["parameter_id"])
		if target != null:
			parts.append("%s = %s" % [parameter_name(row), state_name(row, int(target))])
	if parts.is_empty():
		push_error("RequestText: '%s' has no text and no target States" % request.get("request_id", "?"))
		return PLACEHOLDER_PREFIX + "I need anything at all."
	return PLACEHOLDER_PREFIX + "I need: %s" % ", ".join(parts)


static func parameter_name(parameter_row: Dictionary) -> String:
	return parameter_row.get("name", parameter_row.get("parameter_id", "?"))


static func state_name(parameter_row: Dictionary, state: int) -> String:
	return parameter_row.get("state_%d_name" % state, "State %d" % state)
