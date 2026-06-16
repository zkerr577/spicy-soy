## HubPortal — place one in the hub scene for each destination.
## The player controller's InteractRay will call interact() when the player
## presses F while looking at it. Alternatively, configure the Area3D's
## body_entered signal to auto-trigger on proximity.
##
## Required scene structure:
##   HubPortal (Area3D) ← this script
##   ├── CollisionShape3D   SphereShape3D radius ~1.2
##   ├── Label3D            (shows level name / LOCKED)
##   └── PromptLabel3D      (shows "[F] Enter" hint — optional)
class_name HubPortal
extends Area3D

## Must match one of the ids registered in GameManager._build_catalog().
@export var level_id: String = ""
## Override the display name shown on the label (defaults to catalog name).
@export var label_override: String = ""
## Colour of the portal label when unlocked.
@export var unlocked_color: Color = Color(1.0, 1.0, 1.0)
## Colour shown when the level is locked.
@export var locked_color: Color = Color(0.45, 0.45, 0.45)

@onready var _name_label:   Label3D = $Label3D
@onready var _prompt_label: Label3D = $PromptLabel3D   # may be null if not in scene


func _ready() -> void:
	_refresh_label()
	# Re-check whenever the player unlocks something mid-session
	GameManager.level_unlocked.connect(_on_level_unlocked)


func _refresh_label() -> void:
	var data := GameManager.get_level_data(level_id)
	if not data:
		return

	var unlocked := GameManager.is_unlocked(level_id)
	var display  := label_override if label_override != "" else data.display_name

	if _name_label:
		_name_label.text      = display if unlocked else display + "\n[LOCKED]"
		_name_label.modulate  = unlocked_color if unlocked else locked_color

	if _prompt_label:
		_prompt_label.text    = "[F] Enter" if unlocked else ""


## Called by the player controller's interact system (target.interact(player)).
func interact(_player: Node) -> void:
	if not GameManager.is_unlocked(level_id):
		_flash_locked()
		return
	GameManager.travel_to(level_id)


## Alternative: auto-enter when the player walks into the trigger volume.
## Connect this to body_entered in the editor if you prefer proximity over input.
func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		interact(body)


func _on_level_unlocked(_id: String) -> void:
	_refresh_label()


func _flash_locked() -> void:
	if not _name_label:
		return
	# Quick red flash to communicate "locked"
	var tw := create_tween()
	tw.tween_property(_name_label, "modulate", Color(1, 0.2, 0.2), 0.08)
	tw.tween_property(_name_label, "modulate", locked_color,        0.25)
