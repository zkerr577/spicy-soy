class_name Enemy
extends CharacterBody3D

## Required scene structure:
##   Enemy (CharacterBody3D) ← this script
##   ├── CollisionShape3D      CapsuleShape3D  radius=0.3  height=1.8  pos=(0, 0.9, 0)
##   └── NavigationAgent3D
##
## Player node must be in the "player" group, or assigned via set_player_target().
## Connect "callout_requested(line: String)" to your audio / subtitle manager.
## Connect "fired / threw_object" to a weapon component on this enemy.
## Connect "alerted(pos)" to nearby enemies' alert_at() to implement squad awareness.

enum State { IDLE, PATROL, ALERT, CHASE, COMBAT, FLEE, DEAD }

# ── Movement ──────────────────────────────────────────────────────
@export_group("Movement")
@export var walk_speed:   float = 2.5
@export var run_speed:    float = 5.5
@export var flee_speed:   float = 6.5
@export var acceleration: float = 8.0
@export var deceleration: float = 10.0
@export var turn_speed:   float = 7.0   # rad/s body rotation

# ── Detection ─────────────────────────────────────────────────────
@export_group("Detection")
@export var vision_range:       float = 20.0
@export var vision_fov:         float = 90.0   # total cone angle, degrees
@export var hearing_range:      float = 12.0
@export var sight_loss_timeout: float = 4.0    # seconds of no LOS before going ALERT
@export var alert_timeout:      float = 8.0    # seconds investigating before giving up

# ── Combat ────────────────────────────────────────────────────────
@export_group("Combat")
@export var attack_range:       float = 15.0
@export var preferred_distance: float = 8.0    # desired gap to player during combat
@export var attack_interval:    float = 1.5
@export var throw_range:        float = 6.0
@export var throw_interval:     float = 4.5

# ── Health & Flee ─────────────────────────────────────────────────
@export_group("Health & Flee")
@export var max_health:     float = 100.0
@export var flee_threshold: float = 0.25   # flee when health fraction falls below this
@export var flee_chance:    float = 0.65   # probability roll when threshold first crossed

# ── Patrol ────────────────────────────────────────────────────────
@export_group("Patrol")
@export var patrol_waypoints: Array[NodePath] = []
@export var wander_radius:    float = 10.0   # random wander when no waypoints set
@export var patrol_wait_min:  float = 1.5
@export var patrol_wait_max:  float = 4.0

# ── Audio Callouts ────────────────────────────────────────────────
@export_group("Audio Callouts")
@export var lines_idle:   Array[String] = [
    "Quiet today.", "Nothing here.", "All clear.", "..."]
@export var lines_alert:  Array[String] = [
    "Hello?", "Who's there?", "Show yourself!"]
@export var lines_spot:   Array[String] = [
    "Contact!", "I see you!", "There!", "Enemy spotted!"]
@export var lines_combat: Array[String] = [
    "Take this!", "You won't escape!", "Fire!", "Got you now!"]
@export var lines_damage: Array[String] = [
    "Argh!", "I'm hit!", "Taking fire!", "Ugh!"]
@export var lines_flee:   Array[String] = [
    "Fall back!", "Too hot!", "Pulling out!", "Retreat!"]
@export var lines_death:  Array[String] = [
    "Not... like this...", "Ugh...", "You got me...", "Tell them I..."]
@export var callout_cooldown_min: float = 5.0
@export var callout_cooldown_max: float = 15.0

# ── Nodes ─────────────────────────────────────────────────────────
@onready var _nav: NavigationAgent3D = $NavigationAgent3D

# ── Runtime state ─────────────────────────────────────────────────
var _state:           State  = State.IDLE
var _health:          float
var _player:          Node3D = null

var _last_known_pos:  Vector3
var _has_last_known:  bool  = false
var _sight_lost_time: float = 0.0

var _state_timer:     float = 0.0
var _attack_timer:    float = 0.0
var _throw_timer:     float = 0.0
var _callout_timer:   float = 0.0
var _patrol_wait:     float = 0.0
var _patrol_index:    int   = 0
var _flee_triggered:  bool  = false

var _desired_speed:    float   = 0.0
var _face_toward:      Vector3 = Vector3.ZERO
var _override_facing:  bool    = false

var _last_callout: String = ""
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# ── Signals ───────────────────────────────────────────────────────
## Emit from a weapon component connected to this signal.
signal fired(origin: Vector3, direction: Vector3)
signal threw_object(origin: Vector3, target_pos: Vector3)
signal state_changed(new_state: State)
signal died
## Connect this to your audio manager / subtitle system.
signal callout_requested(line: String)
## Connect to nearby enemies' alert_at() for squad awareness.
signal alerted(at_position: Vector3)


# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	_health = max_health

	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		_player = players[0] as Node3D

	_callout_timer = randf_range(callout_cooldown_min, callout_cooldown_max)
	_enter_state(State.IDLE)


# ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_tick_timers(delta)
	_process_detection(delta)
	_process_state(delta)
	_process_callout_timer(delta)
	_apply_movement(delta)


func _tick_timers(delta: float) -> void:
	_state_timer  += delta
	_attack_timer += delta
	_throw_timer  += delta


# ─────────────────────────────────────────────────────────────────
# MOVEMENT
# ─────────────────────────────────────────────────────────────────

func _apply_movement(delta: float) -> void:
	if _nav.is_navigation_finished():
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
			if not _override_facing:
				rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), turn_speed * delta)

	if _override_facing and not _face_toward.is_zero_approx():
		var to := (_face_toward - global_position)
		to.y    = 0.0
		if not to.is_zero_approx():
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), turn_speed * delta)

	move_and_slide()


# ─────────────────────────────────────────────────────────────────
# DETECTION
# ─────────────────────────────────────────────────────────────────

func _process_detection(delta: float) -> void:
	if not _player:
		return

	var can_see := _can_see_player()

	if can_see:
		_last_known_pos  = _player.global_position
		_has_last_known  = true
		_sight_lost_time = 0.0
		_flee_triggered  = false

		match _state:
			State.IDLE, State.PATROL:
				_play_callout(lines_spot)
				alerted.emit(_player.global_position)
				_change_state(State.CHASE)
			State.ALERT:
				_change_state(State.CHASE)
	else:
		if _state in [State.CHASE, State.COMBAT]:
			_sight_lost_time += delta
			if _sight_lost_time >= sight_loss_timeout:
				_change_state(State.ALERT)
		elif _state == State.ALERT:
			if _state_timer >= alert_timeout:
				_change_state(State.PATROL)


func _can_see_player() -> bool:
	if not _player:
		return false
	var to_player := _player.global_position - global_position
	var dist      := to_player.length()
	if dist > vision_range:
		return false
	# Forward vector in Godot 3D is -Z
	if to_player.normalized().dot(-transform.basis.z) < cos(deg_to_rad(vision_fov * 0.5)):
		return false
	return _has_line_of_sight(_player.global_position)


func _has_line_of_sight(target: Vector3) -> bool:
	var space  := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 1.5   # eye level
	var dest   := target          + Vector3.UP * 1.0   # player chest height
	var query  := PhysicsRayQueryParameters3D.create(origin, dest)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == _player


## Call this from your audio/event system when a noise occurs near this enemy.
## @param noise_pos World position of the noise source.
func hear_noise(noise_pos: Vector3) -> void:
	if _state in [State.DEAD, State.FLEE]:
		return
	if global_position.distance_to(noise_pos) > hearing_range:
		return
	if _state in [State.IDLE, State.PATROL]:
		_last_known_pos = noise_pos
		_has_last_known = true
		_play_callout(lines_alert)
		_change_state(State.ALERT)


# ─────────────────────────────────────────────────────────────────
# STATE MACHINE
# ─────────────────────────────────────────────────────────────────

func _change_state(new_state: State) -> void:
	if new_state == _state:
		return
	_state           = new_state
	_state_timer     = 0.0
	_override_facing = false
	state_changed.emit(new_state)
	_enter_state(new_state)


func _enter_state(s: State) -> void:
	match s:
		State.IDLE:
			_desired_speed = 0.0
			_patrol_wait   = randf_range(patrol_wait_min, patrol_wait_max)

		State.PATROL:
			_desired_speed = walk_speed
			_set_next_patrol_target()

		State.ALERT:
			_desired_speed = walk_speed
			if _has_last_known:
				_nav.target_position = _last_known_pos
			_play_callout(lines_alert)

		State.CHASE:
			_desired_speed   = run_speed
			_sight_lost_time = 0.0

		State.COMBAT:
			_desired_speed   = walk_speed
			_override_facing = true
			# Allow an immediate first shot on entry
			_attack_timer = attack_interval
			_throw_timer  = throw_interval

		State.FLEE:
			_desired_speed = flee_speed
			_play_callout(lines_flee)
			_nav.target_position = _get_flee_point()

		State.DEAD:
			_desired_speed = 0.0
			velocity        = Vector3.ZERO
			_play_callout(lines_death)
			died.emit()
			set_physics_process(false)


func _process_state(delta: float) -> void:
	match _state:
		State.IDLE:   _state_idle()
		State.PATROL: _state_patrol()
		State.ALERT:  _state_alert()
		State.CHASE:  _state_chase()
		State.COMBAT: _state_combat(delta)
		State.FLEE:   _state_flee()


# ── IDLE ──────────────────────────────────────────────────────────

func _state_idle() -> void:
	if _state_timer >= _patrol_wait:
		_change_state(State.PATROL)


# ── PATROL ────────────────────────────────────────────────────────

func _state_patrol() -> void:
	if _nav.is_navigation_finished():
		_change_state(State.IDLE)


# ── ALERT ─────────────────────────────────────────────────────────

func _state_alert() -> void:
	# Nav target was set on entry; just wait at destination.
	# Timeout back to patrol is handled in _process_detection.
	pass


# ── CHASE ─────────────────────────────────────────────────────────

func _state_chase() -> void:
	if not _player:
		return
	_nav.target_position = _player.global_position
	if global_position.distance_to(_player.global_position) <= attack_range:
		_change_state(State.COMBAT)


# ── COMBAT ────────────────────────────────────────────────────────

func _state_combat(delta: float) -> void:
	if not _player:
		return

	_face_toward = _player.global_position
	var dist     := global_position.distance_to(_player.global_position)

	if dist > attack_range:
		_change_state(State.CHASE)
		return

	# Maintain preferred gap; strafe to stay unpredictable
	if dist < preferred_distance * 0.55:
		# Back off
		var retreat := global_position + (global_position - _player.global_position).normalized() * preferred_distance
		_nav.target_position = retreat
		_desired_speed = walk_speed
	elif dist > preferred_distance * 1.5:
		# Close in
		_nav.target_position = _player.global_position
		_desired_speed = run_speed
	else:
		# Strafe perpendicular, oscillating direction over time
		var perp  := (-transform.basis.z).cross(Vector3.UP).normalized()
		var side  := sign(sin(_state_timer * 0.7))
		_nav.target_position = global_position + perp * side * 2.5
		_desired_speed = walk_speed * 0.65

	# Ranged fire
	if _attack_timer >= attack_interval and _can_see_player():
		_attack_timer = 0.0
		_play_callout(lines_combat)
		var origin := global_position + Vector3.UP * 1.5
		var dir    := (_player.global_position + Vector3.UP * 1.0 - origin).normalized()
		fired.emit(origin, dir)

	# Throw when close enough
	if _throw_timer >= throw_interval and dist <= throw_range and _can_see_player():
		_throw_timer = 0.0
		threw_object.emit(global_position + Vector3.UP * 1.5, _player.global_position)


# ── FLEE ──────────────────────────────────────────────────────────

func _state_flee() -> void:
	# Keep updating flee destination so the enemy doesn't stop at the edge of the navmesh
	if _nav.is_navigation_finished():
		_nav.target_position = _get_flee_point()


# ─────────────────────────────────────────────────────────────────
# NAVIGATION HELPERS
# ─────────────────────────────────────────────────────────────────

func _set_next_patrol_target() -> void:
	if patrol_waypoints.is_empty():
		var angle  := randf() * TAU
		var radius := randf_range(2.0, wander_radius)
		_nav.target_position = global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	else:
		_patrol_index        = (_patrol_index + 1) % patrol_waypoints.size()
		var wp               := get_node_or_null(patrol_waypoints[_patrol_index])
		if wp is Node3D:
			_nav.target_position = (wp as Node3D).global_position


func _get_flee_point() -> Vector3:
	if not _player:
		return global_position
	var away := (global_position - _player.global_position).normalized()
	# Jitter so multiple fleeing enemies don't stack on the same point
	away = away.rotated(Vector3.UP, randf_range(-PI * 0.35, PI * 0.35))
	return global_position + away * randf_range(15.0, 25.0)


# ─────────────────────────────────────────────────────────────────
# HEALTH / DAMAGE
# ─────────────────────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if _state == State.DEAD:
		return
	_health = maxf(_health - amount, 0.0)
	_play_callout(lines_damage)

	if _health <= 0.0:
		_change_state(State.DEAD)
		return

	# Wake up if unaware
	if _state in [State.IDLE, State.PATROL, State.ALERT]:
		if _player:
			_last_known_pos = _player.global_position
			_has_last_known = true
			alerted.emit(_last_known_pos)
		_change_state(State.CHASE)

	# One-time flee roll when threshold crossed
	if not _flee_triggered and get_health_fraction() <= flee_threshold:
		_flee_triggered = true
		if randf() < flee_chance:
			_change_state(State.FLEE)


func heal(amount: float) -> void:
	_health = minf(_health + amount, max_health)

func get_health() -> float:          return _health
func get_health_fraction() -> float: return _health / max_health


# ─────────────────────────────────────────────────────────────────
# CALLOUTS
# ─────────────────────────────────────────────────────────────────

func _process_callout_timer(delta: float) -> void:
	_callout_timer -= delta
	if _callout_timer > 0.0:
		return
	_callout_timer = randf_range(callout_cooldown_min, callout_cooldown_max)
	match _state:
		State.IDLE, State.PATROL: _play_callout(lines_idle)
		State.ALERT:              _play_callout(lines_alert)
		State.COMBAT:             _play_callout(lines_combat)
		State.FLEE:               _play_callout(lines_flee)


func _play_callout(pool: Array[String]) -> void:
	if pool.is_empty():
		return
	# Avoid repeating the same line twice in a row
	var choices := pool.filter(func(l: String) -> bool: return l != _last_callout)
	if choices.is_empty():
		choices = pool
	var line: String = choices[randi() % choices.size()]
	_last_callout = line
	callout_requested.emit(line)


# ─────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────

## Override the auto-detected player target.
func set_player_target(node: Node3D) -> void:
	_player = node

## Force this enemy into ALERT at a world position — useful for squad reactions.
func alert_at(pos: Vector3) -> void:
	if _state in [State.DEAD, State.FLEE, State.CHASE, State.COMBAT]:
		return
	_last_known_pos = pos
	_has_last_known = true
	_change_state(State.ALERT)

## Feed a noise event into this enemy (e.g., gunshot heard from afar).
## Alias for hear_noise(), exposed for cleaner external calls.
func notify_noise(noise_pos: Vector3) -> void:
	hear_noise(noise_pos)

func get_state() -> State: return _state
func is_aware() -> bool:   return _state not in [State.IDLE, State.PATROL, State.DEAD]
func is_in_combat() -> bool: return _state in [State.CHASE, State.COMBAT]
func is_dead() -> bool:    return _state == State.DEAD
