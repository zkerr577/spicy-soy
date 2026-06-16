## GameManager — autoload singleton.
## Add to Project > Project Settings > Autoload as "GameManager".
## Also add transition_layer.tscn as a second autoload named "Transition".
extends Node

const SAVE_PATH    := "user://save_data.json"
const SAVE_VERSION := 1

# ── Level catalog ─────────────────────────────────────────────────
# Edit _build_catalog() below to add or change levels.
var _catalog: Array[LevelData] = []

# ── Persistent state ──────────────────────────────────────────────
var _unlocked_levels:  Array[String] = []
var _completed_levels: Array[String] = []
var _stats: Dictionary = {
    "play_time_seconds": 0.0,
    "missions_completed": 0,
    "kills":              0,
    "deaths":             0,
    "shots_fired":        0,
    "shots_hit":          0,
}

# ── Internal ──────────────────────────────────────────────────────
var _current_level_id: String = ""
var _play_timer:       float  = 0.0
var _is_transitioning: bool   = false

# ── Signals ───────────────────────────────────────────────────────
signal level_changed(new_id: String)
signal level_unlocked(new_id: String)


# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_catalog()
	load_game()


func _process(delta: float) -> void:
	_play_timer                  += delta
	_stats["play_time_seconds"]   = _play_timer


# ─────────────────────────────────────────────────────────────────
# CATALOG — add every level/room/screen here
# ─────────────────────────────────────────────────────────────────
func _build_catalog() -> void:
	# ── Core locations (always unlocked) ─────────────────────────
	_register("hub",        "The Hub",         "res://levels/hub/hub.tscn",              true,  [])
	_register("training",   "Training Ground", "res://levels/training/training.tscn",   true,  [])
	_register("stats_room", "Stats Room",      "res://levels/stats_room/stats_room.tscn", true, [])

	# ── Unlockable locations ──────────────────────────────────────
	# Armory unlocks after completing the training level.
	_register("armory",     "Armory",          "res://levels/armory/armory.tscn",       false, ["training"])

	# ── Future missions — uncomment and fill in as you add them ──
	# _register("mission_01", "Mission 01",   "res://levels/m01/m01.tscn", false, ["training"])
	# _register("mission_02", "Mission 02",   "res://levels/m02/m02.tscn", false, ["mission_01"])


func _register(
	id:           String,
	display_name: String,
	scene_path:   String,
	always:       bool,
	requirements: Array
) -> void:
	var d                   := LevelData.new()
	d.id                    = id
	d.display_name          = display_name
	d.scene_path            = scene_path
	d.always_unlocked       = always
	d.unlock_requirements   = requirements
	_catalog.append(d)
	if always and id not in _unlocked_levels:
		_unlocked_levels.append(id)


# ─────────────────────────────────────────────────────────────────
# TRAVEL
# ─────────────────────────────────────────────────────────────────

## Travel to a level by its id. Does nothing if the level is locked
## or a transition is already in progress.
func travel_to(level_id: String) -> void:
	if _is_transitioning:
		return
	if not is_unlocked(level_id):
		push_warning("GameManager: tried to travel to locked level '%s'" % level_id)
		return
	var data := get_level_data(level_id)
	if not data:
		push_error("GameManager: no level with id '%s' in catalog" % level_id)
		return
	_is_transitioning = true
	save_game()

	# Fade out → swap scene → fade in
	var transition := get_node_or_null("/root/Transition")
	if transition:
		await transition.fade_out()

	get_tree().change_scene_to_file(data.scene_path)
	await get_tree().process_frame   # let the new scene initialise

	_current_level_id = level_id
	level_changed.emit(level_id)

	if transition:
		await transition.fade_in()
	_is_transitioning = false


# ─────────────────────────────────────────────────────────────────
# LEVEL UNLOCKING
# ─────────────────────────────────────────────────────────────────

## Mark a level as completed and automatically unlock anything
## whose requirements are now satisfied.
func complete_level(level_id: String) -> void:
	if level_id not in _completed_levels:
		_completed_levels.append(level_id)
	_stats["missions_completed"] = _completed_levels.size()
	_check_unlocks()
	save_game()


## Directly unlock a level (e.g., from a shop or cutscene).
func unlock_level(level_id: String) -> void:
	if level_id not in _unlocked_levels:
		_unlocked_levels.append(level_id)
		level_unlocked.emit(level_id)
		save_game()


func _check_unlocks() -> void:
	for data in _catalog:
		if is_unlocked(data.id):
			continue
		var met := data.unlock_requirements.all(
			func(req: String) -> bool: return req in _completed_levels
		)
		if met:
			unlock_level(data.id)


func is_unlocked(level_id: String) -> bool:
	return level_id in _unlocked_levels


func is_completed(level_id: String) -> bool:
	return level_id in _completed_levels


# ─────────────────────────────────────────────────────────────────
# STATS
# ─────────────────────────────────────────────────────────────────

func get_stat(key: String, default = 0):
	return _stats.get(key, default)

func set_stat(key: String, value) -> void:
	_stats[key] = value

func increment_stat(key: String, amount: float = 1.0) -> void:
	_stats[key] = _stats.get(key, 0) + amount

func get_all_stats() -> Dictionary:
	return _stats.duplicate()

func get_accuracy_percent() -> float:
	var fired := float(_stats.get("shots_fired", 0))
	if fired == 0.0:
		return 0.0
	return float(_stats.get("shots_hit", 0)) / fired * 100.0


# ─────────────────────────────────────────────────────────────────
# CATALOG QUERIES
# ─────────────────────────────────────────────────────────────────

func get_level_data(level_id: String) -> LevelData:
	for d in _catalog:
		if d.id == level_id:
			return d
	return null

## Returns all levels in catalog order.
func get_all_levels() -> Array[LevelData]:
	return _catalog

## Returns only the levels the player can currently access.
func get_unlocked_levels() -> Array[LevelData]:
	return _catalog.filter(func(d: LevelData) -> bool: return is_unlocked(d.id))

func get_current_level_id() -> String:
	return _current_level_id


# ─────────────────────────────────────────────────────────────────
# SAVE / LOAD
# ─────────────────────────────────────────────────────────────────

func save_game() -> void:
	var data := {
		"version":          SAVE_VERSION,
		"unlocked_levels":  _unlocked_levels,
		"completed_levels": _completed_levels,
		"stats":            _stats,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	else:
		push_error("GameManager: could not write save file to " + SAVE_PATH)


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		# First run — seed the always-unlocked levels
		for d in _catalog:
			if d.always_unlocked and d.id not in _unlocked_levels:
				_unlocked_levels.append(d.id)
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("GameManager: could not read save file from " + SAVE_PATH)
		return

	var result := JSON.parse_string(file.read_as_text())
	file.close()

	if not result is Dictionary:
		push_error("GameManager: save file is corrupt, starting fresh")
		return

	_unlocked_levels  = Array(result.get("unlocked_levels",  []))
	_completed_levels = Array(result.get("completed_levels", []))
	var saved_stats   := result.get("stats", {}) as Dictionary
	for key in saved_stats:
		_stats[key] = saved_stats[key]
	_play_timer = float(_stats.get("play_time_seconds", 0.0))

	# Always ensure always-unlocked levels are present even after a save from
	# an older version of the catalog.
	for d in _catalog:
		if d.always_unlocked and d.id not in _unlocked_levels:
			_unlocked_levels.append(d.id)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_unlocked_levels  = []
	_completed_levels = []
	for key in _stats:
		_stats[key] = 0
	_play_timer = 0.0
	for d in _catalog:
		if d.always_unlocked:
			_unlocked_levels.append(d.id)
