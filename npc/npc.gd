class_name NPC
extends CharacterBody3D

## Required scene structure:
##   NPC (CharacterBody3D) ← this script
##   ├── CollisionShape3D    CapsuleShape3D  radius=0.3  height=1.8  pos=(0, 0.9, 0)
##   └── NavigationAgent3D
##
## Player node must be in the "player" group, or assigned via set_player_target().
## Connect "callout_requested(line: String)" to your audio / subtitle manager.
##
## To alert this NPC to nearby combat, call notify_noise(pos) from your
## weapon/explosion system — the same call you make on Enemy nodes.

# ── States ────────────────────────────────────────────────────────
# WANDER:  bumbling around, minding their own business
# CROWD:   spotted the player or heard trouble — running to get in the way
enum State { WANDER, CROWD }

# ── Movement ──────────────────────────────────────────────────────
@export_group("Movement")
@export var wander_speed:    float = 1.5
@export var crowd_speed:     float = 4.0
@export var acceleration:    float = 7.0
@export var deceleration:    float = 9.0
@export var turn_speed:      float = 6.0   # rad/s
@export var wander_radius:   float = 8.0   # max distance from spawn for random wander
@export var wander_wait_min: float = 1.0
@export var wander_wait_max: float = 3.5

# ── Awareness ─────────────────────────────────────────────────────
@export_group("Awareness")
## Radius within which the NPC notices the player or nearby combat.
@export var awareness_radius:    float = 14.0
## Probability of switching to CROWD behaviour when triggered (0–1).
@export var crowd_chance:        float = 0.80
## How close the NPC tries to get to the player when crowding.
@export var crowd_close_dist:    float = 0.9
## How long the NPC crowds before giving up and wandering off (seconds).
@export var crowd_duration_min:  float = 12.0
@export var crowd_duration_max:  float = 28.0
## After ignoring a trigger, how long before re-rolling the chance.
@export var ignore_recheck_time: float = 6.0

# ── Audio Callouts ────────────────────────────────────────────────
@export_group("Audio Callouts")
@export var lines_wander: Array[String] = [
    "Lovely day, isn't it.",
    "Excuse me.",
    "Watch where you're going!",
    "Hmm...",
    "Did you see the news?",
    "Out of my way.",
    "...",
    "Incredible.",
]
@export var lines_crowd: Array[String] = [
    "Hey! Over here!",
    "What's going on?!",
    "Excuse me, excuse ME.",
    "Move! Move!",
    "Hey, you! Yeah, you!",
    "I just wanna talk!",
    "Come on, come on!",
    "Don't ignore me!",
]
## Idle chatter fires every 30–60 s by default.
@export var callout_interval_min: float = 30.0
@export var callout_interval_max: float = 60.0

# ── Nodes ─────────────────────────────────────────────────────────
@onready var _nav: NavigationAgent3D = $NavigationAgent3D

# ── Runtime ───────────────────────────────────────────────────────
var _state:          State  = State.WANDER
var _player:         Node3D = null
var _spawn_pos:      Vector3          # wander stays near here

var _state_timer:    float = 0.0     # time in current state
var _wander_wait:    float = 0.0     # idle pause before next wander point
var _is_waiting:     bool  = false

var _awareness_tick: float = 0.0     # seconds until next proximity check
var _callout_timer:  float = 0.0
var _last_callout:   String = ""

var _desired_speed:  float = 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# ── Signals ───────────────────────────────────────────────────────
signal callout_requested(line: String)
signal started_crowding
signal stopped_crowding


# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_spawn_pos     = global_position
	_callout_timer = randf_range(callout_interval_min, callout_interval_max)
	_awareness_tick = randf_range(0.5, 1.5)  # stagger checks across many NPCs

	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Node3D

	_pick_wander_point()


# ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	_state_timer    += delta
	_awareness_tick -= delta
	_callout_timer  -= delta

	_process_callout()

	if _awareness_tick <= 0.0:
		_awareness_tick = randf_range(0.8, 1.5)
		_check_awareness()

	match _state:
		State.WANDER: _state_wander(delta)
		State.CROWD:  _state_crowd(delta)

	_apply_movement(delta)


# ─────────────────────────────────────────────────────────────────
# MOVEMENT
# ─────────────────────────────────────────────────────────────────

func _apply_movement(delta: float) -> void:
	if _nav.is_navigation_finished() or _is_waiting:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
	else:
		var next    := _nav.get_next_path_position()
		var to_next := next - global_position
		to_next.y   = 0.0
		if to_next.length_squared() > 0.0025:
			var dir := to_next.normalized()
			velocity.x = move_toward(velocity.x, dir.x * _desired_speed, acceleration * delta)
			velocity.z = move_toward(velocity.z, dir.z * _desired_speed, acceleration * delta)
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), turn_speed * delta)

	move_and_slide()


# ─────────────────────────────────────────────────────────────────
# AWARENESS
# ─────────────────────────────────────────────────────────────────

func _check_awareness() -> void:
	if _state == State.CROWD or not _player:
		return
	if global_position.distance_to(_player.global_position) <= awareness_radius:
		_try_crowd()


## Call this when a loud noise (gunshot, explosion) occurs nearby.
## Wires cleanly into the same system used by Enemy nodes.
func notify_noise(noise_pos: Vector3) -> void:
	if _state == State.CROWD:
		return
	if global_position.distance_to(noise_pos) <= awareness_radius:
		_try_crowd()


func _try_crowd() -> void:
	if randf() <= crowd_chance:
		_change_state(State.CROWD)
	else:
		# Rolled to ignore — don't re-check for a while
		_awareness_tick = ignore_recheck_time


# ─────────────────────────────────────────────────────────────────
# STATE MACHINE
# ─────────────────────────────────────────────────────────────────

func _change_state(new_state: State) -> void:
	if new_state == _state:
		return
	_state       = new_state
	_state_timer = 0.0
	_is_waiting  = false

	match new_state:
		State.WANDER:
			_desired_speed = wander_speed
			_pick_wander_point()
			stopped_crowding.emit()
		State.CROWD:
			_desired_speed = crowd_speed
			_crowd_timeout = randf_range(crowd_duration_min, crowd_duration_max)
			started_crowding.emit()
			_play_callout(lines_crowd)


func _state_wander(delta: float) -> void:
	if _is_waiting:
		_wander_wait -= delta
		if _wander_wait <= 0.0:
			_is_waiting = false
			_pick_wander_point()
	elif _nav.is_navigation_finished():
		_is_waiting  = true
		_wander_wait = randf_range(wander_wait_min, wander_wait_max)


func _state_crowd(delta: float) -> void:
	if not _player:
		_change_state(State.WANDER)
		return

	if _state_timer >= _crowd_timeout:
		_change_state(State.WANDER)
		return

	# Also give up if player has moved far away
	if global_position.distance_to(_player.global_position) > awareness_radius * 1.6:
		_change_state(State.WANDER)
		return

	# Target slightly in front of the player so we step into their view
	_nav.target_position = _get_crowd_target()


# Crowd duration is fixed at entry — stored so it's consistent per visit
var _crowd_timeout: float = 0.0


func _get_crowd_target() -> Vector3:
	if not _player:
		return global_position
	# Step into the player's forward path to obstruct their view
	var forward := -_player.transform.basis.z
	forward.y   = 0.0
	forward     = forward.normalized() if forward.length_squared() > 0.01 else Vector3.FORWARD
	return _player.global_position + forward * crowd_close_dist


# ─────────────────────────────────────────────────────────────────
# WANDER HELPERS
# ─────────────────────────────────────────────────────────────────

func _pick_wander_point() -> void:
	var angle  := randf() * TAU
	var radius := randf_range(1.5, wander_radius)
	_nav.target_position = _spawn_pos + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	_desired_speed = wander_speed


# ─────────────────────────────────────────────────────────────────
# CALLOUTS
# ─────────────────────────────────────────────────────────────────

func _process_callout() -> void:
	if _callout_timer > 0.0:
		return
	_callout_timer = randf_range(callout_interval_min, callout_interval_max)
	match _state:
		State.WANDER: _play_callout(lines_wander)
		State.CROWD:  _play_callout(lines_crowd)


func _play_callout(pool: Array[String]) -> void:
	if pool.is_empty():
		return
	var choices := pool.filter(func(l: String) -> bool: return l != _last_callout)
	if choices.is_empty():
		choices = pool
	var line: String = choices[randi() % choices.size()]
	_last_callout = line
	callout_requested.emit(line)


# ─────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────

## Override the auto-detected player node.
func set_player_target(node: Node3D) -> void:
	_player = node

## Reposition the home point NPCs wander around (e.g., after being moved by a cutscene).
func set_spawn_position(pos: Vector3) -> void:
	_spawn_pos = pos

func get_state() -> State: return _state
func is_crowding() -> bool: return _state == State.CROWD
