class_name LevelData
extends Resource

## Unique string key used everywhere to refer to this level.
@export var id: String = ""
## Name shown in the level select screen and portal labels.
@export var display_name: String = ""
## Short blurb shown on the level select card.
@export var description: String = ""
## Path to the .tscn file for this level/room.
@export_file("*.tscn") var scene_path: String = ""
## Optional thumbnail shown on the level select card.
@export var thumbnail: Texture2D = null
## When true the level is accessible from the very start with no requirements.
@export var always_unlocked: bool = false
## IDs of levels that must be COMPLETED before this one becomes available.
@export var unlock_requirements: Array[String] = []
