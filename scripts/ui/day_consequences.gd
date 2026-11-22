class_name DayConsequences
extends Control
## The Day Consequences screen (T12, GDD 7.2, grey-box). It covers the shop once every
## Client has been served and lists, in the order they were served, each Client, the
## Resolution, the Gold Coins it paid and its flavour text. Then the Gold Coin total.
##
## First Playable has only Day 1, so the screen always ends with "End of First Playable"
## and a Restart button (decision D9). A view only: the text comes from ConsequenceText.

## Restart was clicked. main.gd reloads the scene, which starts a new game at Day 1.
signal restart_requested

const SUCCESS_COLOR := Color(0.55, 0.95, 0.55)
const FAILURE_COLOR := Color(1.0, 0.55, 0.5)

@onready var _title_label: Label = %TitleLabel
@onready var _entry_list: VBoxContainer = %EntryList
@onready var _coins_label: Label = %CoinsLabel
@onready var _restart_button: Button = %RestartButton


func _ready() -> void:
	_restart_button.pressed.connect(restart_requested.emit)


## Fills the screen from a DayState whose Day is over.
func show_day(day_state: DayState) -> void:
	_title_label.text = "Day %d: Day Consequences" % day_state.day
	for child: Node in _entry_list.get_children():
		child.queue_free()

	for entry: Dictionary in ConsequenceText.entries(day_state.results, GameData.rows("requests"), GameData.rows("characters")):
		var coins: int = entry["coins"]
		var heading := Label.new()
		heading.text = "%s: %s, %d Gold Coin%s" % [
			entry["character_name"],
			ConsequenceText.resolution_name(entry["success"]),
			coins,
			"" if coins == 1 else "s",
		]
		heading.modulate = SUCCESS_COLOR if entry["success"] else FAILURE_COLOR
		var text := Label.new()
		text.text = entry["text"]
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var box := VBoxContainer.new()
		box.add_child(heading)
		box.add_child(text)
		_entry_list.add_child(box)

	_coins_label.text = "Gold Coins: %d" % day_state.coins
	_restart_button.grab_focus()
