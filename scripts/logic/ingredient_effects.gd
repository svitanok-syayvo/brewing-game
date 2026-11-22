class_name IngredientEffects
extends RefCounted
## Every Ingredient's effect in both Forms, parsed from the Data Sheet at load time,
## and the one entry point that adds an Ingredient's effect to a Brew (GDD 5.1, 5.2).
##
## Pure logic: it takes table rows instead of reading GameData, so tests can build it
## headless. In the game: IngredientEffects.new(GameData.rows("ingredients"),
## GameData.rows("parameters")).
##
## Not handled here: supply, the 3-Ingredient cap (Brew.count_ingredient()) and which
## Form an Ingredient is in. The caller (DayState, T8/T11) owns those and passes `shifted`.

var _normal: Dictionary[String, IngredientEffect] = {}
var _shifted: Dictionary[String, IngredientEffect] = {}


func _init(ingredient_rows: Array, parameter_rows: Array) -> void:
	var parameter_ids: Array = parameter_rows.map(func(r: Dictionary) -> String: return r.get("parameter_id", ""))
	for row: Dictionary in ingredient_rows:
		var id: String = row.get("ingredient_id", "")
		var normal := IngredientEffect.parse(row.get("effect", ""), parameter_ids)
		var shifted := IngredientEffect.parse(row.get("shifted_effect", ""), parameter_ids)
		if normal == null or shifted == null:
			push_error("IngredientEffects: %s is skipped because an effect did not parse" % id)
			continue
		_normal[id] = normal
		_shifted[id] = shifted


func has_ingredient(ingredient_id: String) -> bool:
	return _normal.has(ingredient_id)


## The parsed effect of one Form, or null for an unknown Ingredient. Tooltips (T13)
## read it to describe the effect.
func get_effect(ingredient_id: String, shifted: bool) -> IngredientEffect:
	if not has_ingredient(ingredient_id):
		push_error("IngredientEffects: unknown Ingredient '%s'" % ingredient_id)
		return null
	return _shifted[ingredient_id] if shifted else _normal[ingredient_id]


## Applies one Ingredient, in the given Form, to the Brew, honouring and consuming any
## pending ing_05 modifier (D1, D2). Does not count the Ingredient toward the cap.
func apply(brew: Brew, ingredient_id: String, shifted: bool) -> void:
	var effect := get_effect(ingredient_id, shifted)
	if effect == null:
		return

	# Take the pending modifier first: if this Ingredient is itself a modifier,
	# run() would overwrite brew.pending_mask before we could read it.
	var mask := brew.pending_mask.duplicate()
	brew.pending_mask.clear()

	# D2: a modifier straight after a modifier has no effect. It only uses up the
	# pending one, so the Ingredient after it works normally.
	if not mask.is_empty() and effect.is_modifier():
		return

	# D1: run the effect normally, then put the masked Parameters back as they were.
	var before := brew.get_states()
	effect.run(brew)
	for p: int in mask:
		brew.set_state(p, before[p])
