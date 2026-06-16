## LevelSelectScreen — attach to a Control node.
##
## Required scene structure:
##   LevelSelectScreen (Control) ← this script
##   └── ScrollContainer
##       └── LevelGrid (GridContainer)
##
## The script dynamically creates one card per level in GameManager's catalog.
## Call show_screen() / hide_screen() to open and close it, or wire the
## portal in the hub to GameManager.travel_to("level_select") if you prefer
## a full scene approach.
extends Control

@onready var _grid: GridContainer = $ScrollContainer/LevelGrid

## Emitted when the player picks a level so parent UI can handle it.
signal level_selected(level_id: String)


func _ready() -> void:
	GameManager.level_unlocked.connect(_on_unlock_changed)
	_populate()
	# Start hidden; show via show_screen() or set Visible in editor
	hide()


func show_screen() -> void:
	_populate()   # refresh in case unlocks changed
	show()


func hide_screen() -> void:
	hide()


# ─────────────────────────────────────────────────────────────────

func _populate() -> void:
	# Clear old cards
	for child in _grid.get_children():
		child.queue_free()

	for data in GameManager.get_all_levels():
		# Skip internal-only locations (stats_room handled separately, etc.)
		# Remove this filter if you want everything in the select screen.
		if data.id in ["hub", "stats_room"]:
			continue
		_grid.add_child(_make_card(data))


func _make_card(data: LevelData) -> PanelContainer:
	var unlocked := GameManager.is_unlocked(data.id)
	var completed := GameManager.is_completed(data.id)

	# ── Container ─────────────────────────────────────────────────
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(220, 160)

	# ── Layout ────────────────────────────────────────────────────
	var vbox := VBoxContainer.new()
	card.add_child(vbox)

	# Thumbnail or colour placeholder
	var thumb := ColorRect.new()
	thumb.custom_minimum_size = Vector2(0, 90)
	if data.thumbnail:
		var tex := TextureRect.new()
		tex.texture = data.thumbnail
		tex.stretch_mode = TextureRect.STRETCH_COVER
		tex.custom_minimum_size = Vector2(0, 90)
		vbox.add_child(tex)
	else:
		thumb.color = Color(0.18, 0.22, 0.28) if unlocked else Color(0.12, 0.12, 0.12)
		vbox.add_child(thumb)

	# Name row
	var name_label := Label.new()
	name_label.text             = data.display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(name_label)

	# Status badge
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 12)
	if not unlocked:
		status.text = "🔒  LOCKED"
		status.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	elif completed:
		status.text = "✓  COMPLETED"
		status.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	else:
		status.text = "AVAILABLE"
		status.add_theme_color_override("font_color", Color(0.9, 0.85, 0.4))
	vbox.add_child(status)

	# Make unlocked cards clickable
	if unlocked:
		var btn := Button.new()
		btn.text = "Enter"
		btn.pressed.connect(func() -> void: _on_card_pressed(data.id))
		vbox.add_child(btn)
	else:
		# Show first missing requirement
		if not data.unlock_requirements.is_empty():
			var req_id   := data.unlock_requirements[0]
			var req_data := GameManager.get_level_data(req_id)
			var req_name := req_data.display_name if req_data else req_id
			var hint     := Label.new()
			hint.text    = "Complete: " + req_name
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.add_theme_font_size_override("font_size", 11)
			hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			vbox.add_child(hint)

	# Dim locked cards
	if not unlocked:
		card.modulate = Color(0.6, 0.6, 0.6)

	return card


func _on_card_pressed(level_id: String) -> void:
	level_selected.emit(level_id)
	hide_screen()
	GameManager.travel_to(level_id)


func _on_unlock_changed(_id: String) -> void:
	if is_visible():
		_populate()
