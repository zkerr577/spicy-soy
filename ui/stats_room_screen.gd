## StatsRoomScreen — attach to a Control node in your Stats Room scene.
##
## Required scene structure:
##   StatsRoomScreen (Control) ← this script
##   └── VBoxContainer (named "StatsList")
##
## Reads all stats from GameManager and dynamically builds a display.
## Wire a "Back to Hub" button to _on_back_pressed(), or let the player
## walk back through a HubPortal placed in the stats room scene.
extends Control

@onready var _list: VBoxContainer = $StatsList


func _ready() -> void:
	_populate()


func _populate() -> void:
	for child in _list.get_children():
		child.queue_free()

	_add_header("PROGRESS")
	_add_row("Missions Completed", str(GameManager.get_stat("missions_completed")))
	_add_row("Levels Unlocked",    str(GameManager.get_unlocked_levels().size()) +
	                                " / " + str(GameManager.get_all_levels().size()))
	_add_row("Time Played",        _format_time(GameManager.get_stat("play_time_seconds")))

	_add_spacer()
	_add_header("COMBAT")
	_add_row("Kills",              str(GameManager.get_stat("kills")))
	_add_row("Deaths",             str(GameManager.get_stat("deaths")))
	var kd_ratio := 0.0
	if GameManager.get_stat("deaths") > 0:
		kd_ratio = float(GameManager.get_stat("kills")) / float(GameManager.get_stat("deaths"))
	_add_row("K/D Ratio",          "%.2f" % kd_ratio)

	_add_spacer()
	_add_header("MARKSMANSHIP")
	_add_row("Shots Fired",        str(GameManager.get_stat("shots_fired")))
	_add_row("Shots Hit",          str(GameManager.get_stat("shots_hit")))
	_add_row("Accuracy",           "%.1f%%" % GameManager.get_accuracy_percent())


# ─────────────────────────────────────────────────────────────────

func _add_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
	_list.add_child(lbl)


func _add_row(label: String, value: String) -> void:
	var hbox   := HBoxContainer.new()
	var key    := Label.new()
	var spacer := Control.new()
	var val    := Label.new()

	key.text    = label
	key.add_theme_font_size_override("font_size", 14)

	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	val.text    = value
	val.add_theme_font_size_override("font_size", 14)
	val.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	hbox.add_child(key)
	hbox.add_child(spacer)
	hbox.add_child(val)
	_list.add_child(hbox)


func _add_spacer() -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 12)
	_list.add_child(sp)


func _format_time(seconds) -> String:
	var s   := int(float(seconds))
	var h   := s / 3600
	var m   := (s % 3600) / 60
	var sec := s % 60
	return "%dh %02dm %02ds" % [h, m, sec]


## Wire a "Back to Hub" button's pressed signal here.
func _on_back_pressed() -> void:
	GameManager.travel_to("hub")
