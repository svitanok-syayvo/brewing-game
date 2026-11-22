extends Control
## The shop screen (T7, grey-box). It shows everything GDD 8.1 asks for during a Request:
## the State of each Parameter, the selected Client's Request and its Additional Rules,
## each Ingredient with its Form and remaining supply, the Shifter's general effect and
## whether it is used, the number of Requests left today and the Gold Coin total.
##
## A view only: it reads DayState and the Brew and redraws when they emit `changed`. The
## rules live in scripts/logic/. Every name and value shown comes from GameData.
##
## Art: each picture slot loads res://assets/art/<Asset List file name> if Corgil has
## delivered it, and otherwise shows a grey box labelled with that file name.
##
## Brewing controls (T8, decision D4): click an Ingredient to pick it up (it follows the
## cursor), then click the Brewing Station to add it. Right-click, Esc, clicking the held
## Ingredient again or clicking empty space puts it back. Empty resets the Brew.
## Not wired yet: Serve and the Day end (T10) and placing on the Shifter (T11).

const ART_DIR := "res://assets/art/"
const PLACEHOLDER_COLOR := Color(0.38, 0.38, 0.40)
## Tint for a placeholder in the Shifted Form, so the Form is visible before art exists.
const SHIFTED_PLACEHOLDER_COLOR := Color(0.45, 0.30, 0.55)
const CLIENT_ART_SIZE := Vector2(110, 110)
const INGREDIENT_ART_SIZE := Vector2(72, 72)
const STATION_ART_SIZE := Vector2(180, 110)
const PARAMETER_ART_SIZE := Vector2(28, 28)
const SHIFTER_ART_SIZE := Vector2(110, 110)
const COIN_ART_SIZE := Vector2(20, 20)
const HELD_ART_SIZE := Vector2(56, 56)
## Where the held Ingredient sits relative to the cursor, so it does not hide the target.
const HELD_OFFSET := Vector2(14, 14)
const BLOCKED_FLASH_COLOR := Color(1.0, 0.45, 0.4)
const FEEDBACK_SECONDS := 2.5
## The Data Sheet's Shifter effect ends with a design-doc pointer such as "(see GDD 5.3)",
## which is not meant for players.
const DOC_REFERENCE := "\\s*\\(see GDD [^)]*\\)"

var day_state: DayState

## The Request whose Client is selected and shown in the speech bubble. UI state only:
## switching Clients changes nothing in the Brew (GDD 4.2).
var _selected_request_id := ""
var _client_group := ButtonGroup.new()
## request_id -> its Client's Button in the Client row.
var _client_buttons: Dictionary[String, Button] = {}
## The Request IDs the Client row was last built for.
var _client_row_ids: Array[String] = []
## ingredient_id -> {"card", "art", "form", "count"} for redrawing one tray item.
var _ingredient_views: Dictionary[String, Dictionary] = {}
## One {"art", "label"} per Parameter, in Parameter order (index 0 is param_01).
var _parameter_views: Array[Dictionary] = []
var _parameter_rows: Array = []
## The Ingredient picked up and following the cursor, or "" if nothing is held. UI state
## only: nothing in DayState changes until it is placed.
var _held_id := ""
var _held_view: Control
## Bumped on every new feedback message, so an old timer does not clear a newer one.
var _feedback_serial := 0

@onready var _day_label: Label = %DayLabel
@onready var _requests_left_label: Label = %RequestsLeftLabel
@onready var _coin_box: HBoxContainer = %CoinBox
@onready var _coins_label: Label = %CoinsLabel
@onready var _client_row: HBoxContainer = %ClientRow
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _request_label: Label = %RequestLabel
@onready var _additional_rules_label: Label = %AdditionalRulesLabel
@onready var _ingredient_tray: GridContainer = %IngredientTray
@onready var _station_art: CenterContainer = %StationArt
@onready var _parameter_list: VBoxContainer = %ParameterList
@onready var _ingredient_count_label: Label = %IngredientCountLabel
@onready var _feedback_label: Label = %FeedbackLabel
@onready var _station_panel: PanelContainer = %StationPanel
@onready var _empty_button: Button = %EmptyButton
@onready var _shifter_panel: PanelContainer = %ShifterPanel
@onready var _shifter_title: Label = %ShifterTitle
@onready var _shifter_art: CenterContainer = %ShifterArt
@onready var _shifter_effect_label: Label = %ShifterEffectLabel
@onready var _shifter_status_label: Label = %ShifterStatusLabel


func _ready() -> void:
	_parameter_rows = GameData.rows("parameters")
	day_state = DayState.new(
		_parameter_rows,
		GameData.rows("ingredients"),
		GameData.rows("supply"),
		GameData.rows("requests"),
	)

	_build_static_art()
	_build_parameters()
	_build_ingredient_tray()
	_build_shifter_text()

	_station_panel.gui_input.connect(_on_station_input)
	_shifter_panel.gui_input.connect(_on_shifter_input)
	_empty_button.pressed.connect(_on_empty_pressed)
	_feedback_label.text = ""

	day_state.changed.connect(_refresh)
	day_state.brew.changed.connect(_refresh_brew)
	day_state.start_day(1)


# --- Building (once) -------------------------------------------------------------------

func _build_static_art() -> void:
	_station_art.add_child(_make_art("brewing_station.png", STATION_ART_SIZE))
	_coin_box.add_child(_make_art("coin.png", COIN_ART_SIZE, false))
	_coin_box.move_child(_coin_box.get_child(-1), 0)


func _build_parameters() -> void:
	for p: int in _parameter_rows.size():
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var art_slot := CenterContainer.new()
		art_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		row.add_child(art_slot)
		row.add_child(label)
		_parameter_list.add_child(row)
		_parameter_views.append({"art": art_slot, "label": label})


func _build_ingredient_tray() -> void:
	for id: String in day_state.ingredient_ids():
		var row: Dictionary = GameData.row("ingredients", id)
		var card := _make_card(id)
		var box: VBoxContainer = card.get_meta("content")
		box.custom_minimum_size.x = 96
		var art_slot := CenterContainer.new()
		art_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label := _centered_label(row.get("name", id))
		var form_label := _centered_label("")
		var count_label := _centered_label("")
		for child: Control in [art_slot, name_label, form_label, count_label]:
			box.add_child(child)

		(card.get_meta("button") as Button).pressed.connect(_on_ingredient_pressed.bind(id))
		_ingredient_tray.add_child(card)
		_ingredient_views[id] = {"card": card, "art": art_slot, "form": form_label, "count": count_label}


func _build_shifter_text() -> void:
	var tools: Array = GameData.rows("tools")
	if tools.is_empty():
		return
	var shifter: Dictionary = tools[0]
	_shifter_title.text = shifter.get("name", "tool_01")
	var regex := RegEx.create_from_string(DOC_REFERENCE)
	_shifter_effect_label.text = regex.sub(str(shifter.get("effect", "")), "", true)


## The Client row is rebuilt when the set of waiting Requests changes (served Clients
## leave, GDD 6.1). Each Client is a toggle Button, and one of them is always selected.
func _build_client_row() -> void:
	for child: Node in _client_row.get_children():
		child.queue_free()
	_client_buttons.clear()
	_client_row_ids = day_state.waiting_requests()

	for request_id: String in day_state.waiting_requests():
		var request: Dictionary = GameData.row("requests", request_id)
		var character_id: String = request.get("character_id", "")
		var character: Dictionary = GameData.row("characters", character_id)

		var card := _make_card(request_id)
		var button: Button = card.get_meta("button")
		button.toggle_mode = true
		button.button_group = _client_group
		var box: VBoxContainer = card.get_meta("content")
		box.add_child(_make_art(_character_art_file(character_id), CLIENT_ART_SIZE))
		box.add_child(_centered_label(character.get("name", character_id)))
		button.pressed.connect(_select_client.bind(request_id))

		_client_row.add_child(card)
		_client_buttons[request_id] = button


# --- Redrawing --------------------------------------------------------------------------

func _refresh() -> void:
	_day_label.text = "Day %d" % day_state.day
	_requests_left_label.text = "Requests left: %d" % day_state.requests_left()
	_coins_label.text = "Gold Coins: %d" % day_state.coins

	var waiting := day_state.waiting_requests()
	if waiting != _client_row_ids:
		_build_client_row()
	if not waiting.has(_selected_request_id):
		_selected_request_id = waiting[0] if not waiting.is_empty() else ""
	_refresh_client_selection()
	_refresh_ingredients()
	_refresh_shifter()
	_refresh_brew()


func _refresh_brew() -> void:
	var brew := day_state.brew
	for p: int in _parameter_views.size():
		var row: Dictionary = _parameter_rows[p]
		var state := brew.get_state(p)
		var view: Dictionary = _parameter_views[p]
		_replace_art(view["art"], "brew_%s_state_%d.png" % [row["parameter_id"], state], PARAMETER_ART_SIZE)
		(view["label"] as Label).text = "%s: %s" % [row.get("name", row["parameter_id"]), _state_name(row, state)]
	_ingredient_count_label.text = "Ingredients in the Brew: %d / %d" % [brew.get_ingredient_count(), Brew.MAX_INGREDIENTS]


func _refresh_client_selection() -> void:
	for request_id: String in _client_buttons:
		_client_buttons[request_id].set_pressed_no_signal(request_id == _selected_request_id)

	if _selected_request_id.is_empty():
		_speaker_label.text = ""
		_request_label.text = ""
		_additional_rules_label.text = ""
		return
	var request: Dictionary = GameData.row("requests", _selected_request_id)
	var character: Dictionary = GameData.row("characters", request.get("character_id", ""))
	_speaker_label.text = "%s says:" % character.get("name", request.get("character_id", ""))
	_request_label.text = _request_text(request)
	var rule := str(request.get("additional_rule", ""))
	_additional_rules_label.text = "Additional Rules: %s" % (rule if not rule.is_empty() else "none")


func _refresh_ingredients() -> void:
	for id: String in _ingredient_views:
		var view: Dictionary = _ingredient_views[id]
		var shifted := day_state.is_shifted(id)
		var left := day_state.supply_of(id)
		_replace_art(view["art"], "%s_shifted.png" % id if shifted else "%s.png" % id, INGREDIENT_ART_SIZE, shifted)
		(view["form"] as Label).text = "Shifted" if shifted else "Normal"
		(view["count"] as Label).text = "× %d" % left
		# Dimmed, not disabled: T8 still needs the click to give "none left" feedback.
		(view["card"] as Control).modulate.a = 1.0 if left > 0 else 0.4


func _refresh_shifter() -> void:
	var used := day_state.shifter_used
	_replace_art(_shifter_art, "tool_01_drained.png" if used else "tool_01.png", SHIFTER_ART_SIZE)
	_shifter_status_label.text = "Used today" if used else "1 use left today"
	# GDD 5.3: once spent, the Shifter must look clearly unusable for the rest of the Day.
	_shifter_panel.modulate = Color(1, 1, 1, 0.35) if used else Color.WHITE


func _select_client(request_id: String) -> void:
	_selected_request_id = request_id
	_refresh_client_selection()


# --- Brewing controls (T8) -------------------------------------------------------------

func _on_ingredient_pressed(id: String) -> void:
	if _held_id == id:
		_drop_held()
		return
	if day_state.supply_of(id) <= 0:
		_drop_held()
		_show_blocked("No %s left today." % _ingredient_name(id), _ingredient_views[id]["card"].get_meta("button"))
		return
	_pick_up(id)


func _on_station_input(event: InputEvent) -> void:
	if not _is_left_click(event) or _held_id.is_empty():
		return
	accept_event()
	var id := _held_id
	match day_state.add_ingredient(id):
		DayState.AddResult.ADDED:
			# No "added X" message: the game deliberately keeps no list of what went in
			# (GDD 4.3, playtest question 11.3 Q2).
			_clear_feedback()
			_drop_held()
		DayState.AddResult.NONE_LEFT:
			_drop_held()
			_show_blocked("No %s left today." % _ingredient_name(id), _station_panel)
		DayState.AddResult.BREW_FULL:
			_drop_held()
			_show_blocked("The Brewing Station is full: %d / %d Ingredients." % [Brew.MAX_INGREDIENTS, Brew.MAX_INGREDIENTS], _station_panel)
		_:
			_drop_held()


## T11 places the held Ingredient on the Shifter. Until then the click only keeps it from
## counting as a click on empty space, so the Ingredient stays in hand.
func _on_shifter_input(event: InputEvent) -> void:
	if _is_left_click(event) and not _held_id.is_empty():
		accept_event()


func _on_empty_pressed() -> void:
	_drop_held()
	_clear_feedback()
	day_state.empty_brew()


## A left click that reaches the root Control landed on empty space: put the Ingredient back.
func _gui_input(event: InputEvent) -> void:
	if _is_left_click(event) and not _held_id.is_empty():
		accept_event()
		_drop_held()


## The held Ingredient follows the cursor. Right-click and Esc cancel from anywhere,
## even over a Button.
func _input(event: InputEvent) -> void:
	if _held_id.is_empty():
		return
	if event is InputEventMouseMotion:
		_held_view.global_position = (event as InputEventMouseMotion).position + HELD_OFFSET
		return
	var right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if right_click or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_drop_held()


func _pick_up(id: String) -> void:
	_drop_held()
	_held_id = id
	var shifted := day_state.is_shifted(id)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.top_level = true
	box.z_index = 100
	var art := _make_art("%s_shifted.png" % id if shifted else "%s.png" % id, HELD_ART_SIZE, false, shifted)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(art)
	box.add_child(_centered_label("%s (%s)" % [_ingredient_name(id), "Shifted" if shifted else "Normal"]))
	add_child(box)
	_held_view = box
	_held_view.global_position = get_global_mouse_position() + HELD_OFFSET
	(_ingredient_views[id]["card"].get_meta("button") as Button).modulate = Color(1, 1, 0.6)


func _drop_held() -> void:
	if _held_id.is_empty():
		return
	(_ingredient_views[_held_id]["card"].get_meta("button") as Button).modulate = Color.WHITE
	_held_id = ""
	if _held_view != null:
		_held_view.queue_free()
		_held_view = null


## A blocked action changes nothing, so it only flashes the target and shows a short line
## (sfx_error is a Should Have, GDD 1.7).
func _show_blocked(message: String, target: CanvasItem) -> void:
	print("Blocked: %s" % message)
	_feedback_serial += 1
	var serial := _feedback_serial
	_feedback_label.text = message
	target.self_modulate = BLOCKED_FLASH_COLOR
	var tween := create_tween()
	tween.tween_property(target, "self_modulate", Color.WHITE, 0.4)
	await get_tree().create_timer(FEEDBACK_SECONDS).timeout
	if serial == _feedback_serial:
		_feedback_label.text = ""


func _clear_feedback() -> void:
	_feedback_serial += 1
	_feedback_label.text = ""


func _is_left_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT


# --- Text helpers -----------------------------------------------------------------------

func _ingredient_name(id: String) -> String:
	return GameData.row("ingredients", id).get("name", id)


func _state_name(parameter_row: Dictionary, state: int) -> String:
	return parameter_row.get("state_%d_name" % state, "State %d" % state)


## The Request's own text from the Data Sheet. While that is empty (decision D7), a
## generated Specific text lists the target States, marked as a placeholder.
func _request_text(request: Dictionary) -> String:
	var text := str(request.get("text", ""))
	if not text.is_empty():
		return text
	var parts: PackedStringArray = []
	for row: Dictionary in _parameter_rows:
		var target: Variant = request.get("%s_target" % row["parameter_id"])
		if target != null:
			parts.append("%s = %s" % [row.get("name", row["parameter_id"]), _state_name(row, int(target))])
	return "[placeholder] I need: %s" % ", ".join(parts)


## A clickable card: a Button drawn behind a VBox of content. The MarginContainer gives both
## the same rect, so the content decides the size and the Button gets every click (the
## content ignores the mouse). Read the parts with get_meta("button") / get_meta("content").
func _make_card(node_name: String) -> MarginContainer:
	var card := MarginContainer.new()
	card.name = node_name
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	var padding := MarginContainer.new()
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 6)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_child(box)
	card.add_child(button)
	card.add_child(padding)
	card.set_meta("button", button)
	card.set_meta("content", box)
	return card


func _centered_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


# --- Art helpers ------------------------------------------------------------------------

## char_01.png stands in for every Client until char_02–char_04 exist (Asset List).
func _character_art_file(character_id: String) -> String:
	var own := "%s.png" % character_id
	if ResourceLoader.exists(ART_DIR + own) or not ResourceLoader.exists(ART_DIR + "char_01.png"):
		return own
	return "char_01.png"


## The delivered texture if res://assets/art/<file_name> exists, otherwise a grey box
## labelled with the file name. Mouse input passes through, so it can sit inside Buttons.
func _make_art(file_name: String, size: Vector2, show_name: bool = true, shifted: bool = false) -> Control:
	var path := ART_DIR + file_name
	if ResourceLoader.exists(path):
		var texture_rect := TextureRect.new()
		texture_rect.texture = load(path)
		texture_rect.custom_minimum_size = size
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return texture_rect

	var box := ColorRect.new()
	box.color = SHIFTED_PLACEHOLDER_COLOR if shifted else PLACEHOLDER_COLOR
	box.custom_minimum_size = size
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if show_name:
		var label := Label.new()
		label.text = file_name
		label.add_theme_font_size_override("font_size", 10)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.add_child(label)
	return box


## Swaps the picture inside a slot. Skipped if the slot already shows that file.
func _replace_art(slot: Control, file_name: String, size: Vector2, shifted: bool = false) -> void:
	if slot.get_meta("art_file", "") == file_name:
		return
	for child: Node in slot.get_children():
		child.queue_free()
	slot.add_child(_make_art(file_name, size, size.x >= 60, shifted))
	slot.set_meta("art_file", file_name)
