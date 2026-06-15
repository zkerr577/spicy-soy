extends CharacterBody3D

# Required scene structure:
#
#   Player (CharacterBody3D)  ← this script
#   ├── CollisionShape3D        CapsuleShape3D  radius=0.3 height=1.8  position=(0, 0.9, 0)
#   ├── Head (Node3D)           position=(0, 1.6, 0)
#   │   ├── Camera3D
#   │   └── InteractRay (RayCast3D)  target_position=(0, 0, -2.5)  enabled=true
#   └── CeilingCheck (ShapeCast3D)   SphereShape3D radius=0.25  position=(0, 0.45, 0)  enabled=true
#
# Required Input Map actions (Project > Project Settings > Input Map):
#   move_forward / move_backward / move_left / move_right  (W A S D)
#   run            (Left Shift)
#   jump           (Space)
#   crouch         (C)
#   prone          (Z)
#   lean_left      (Q)
#   lean_right     (E)
#   interact       (F)
#   aim            (Mouse Button Right)
#   fire           (Mouse Button Left)
#   reload         (R)
#   throw          (G)
#   cycle_weapon_next  (Mouse Wheel Down)
#   cycle_weapon_prev  (Mouse Wheel Up)
#   audio_callout  (T)

# ── Movement ──────────────────────────────────────────────────────
const WALK_SPEED   := 3.5
const RUN_SPEED    := 7.0
const CROUCH_SPEED := 1.8
const PRONE_SPEED  := 0.8
const ACCELERATION := 10.0
const DECELERATION := 12.0

# ── Jump ──────────────────────────────────────────────────────────
const JUMP_VELOCITY := 4.5

# ── Mouse look ────────────────────────────────────────────────────
const MOUSE_SENSITIVITY := 0.002
const PITCH_CLAMP       := 80.0  # degrees

# ── Stance geometry ───────────────────────────────────────────────
const STAND_HEIGHT  := 1.80
const CROUCH_HEIGHT := 1.10
const PRONE_HEIGHT  := 0.45

const STAND_HEAD_Y  := 1.60
const CROUCH_HEAD_Y := 0.90
const PRONE_HEAD_Y  := 0.30

const STANCE_SPEED  := 8.0  # transition reciprocal seconds (higher = snappier)

# ── Lean ──────────────────────────────────────────────────────────
const LEAN_ANGLE    := 15.0  # degrees max roll
const LEAN_OFFSET_X := 0.30  # metres of lateral head shift
const LEAN_SPEED    := 10.0

# ── Interaction ───────────────────────────────────────────────────
const INTERACT_REACH := 2.5

# ── Nodes ─────────────────────────────────────────────────────────
@onready var _head:          Node3D           = $Head
@onready var _col_shape:     CollisionShape3D = $CollisionShape3D
@onready var _interact_ray:  RayCast3D        = $Head/InteractRay
@onready var _ceiling_check: ShapeCast3D      = $CeilingCheck

# ── State ─────────────────────────────────────────────────────────
enum Stance { STAND, CROUCH, PRONE }

var _stance:       Stance = Stance.STAND
var _pitch:        float  = 0.0
var _lean_angle:   float  = 0.0   # smoothed roll (radians)
var _lean_offset:  float  = 0.0   # smoothed lateral offset

var _is_aiming:    bool        = false
var _weapons:      Array[Node] = []
var _weapon_index: int         = 0

var _stance_tween: Tween

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# ── Signals ───────────────────────────────────────────────────────
signal interacted(target: Node)
signal weapon_fired
signal weapon_reloaded
signal weapon_thrown
signal weapon_cycled(new_index: int)
signal audio_callout


# ─────────────────────────────────────────────────────────────────
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ─────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_apply_mouse_look(event.relative)


func _apply_mouse_look(rel: Vector2) -> void:
	rotate_y(-rel.x * MOUSE_SENSITIVITY)
	_pitch = clampf(
		_pitch - rel.y * MOUSE_SENSITIVITY,
		-deg_to_rad(PITCH_CLAMP),
		deg_to_rad(PITCH_CLAMP)
	)
	_head.rotation.x = _pitch


# ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_process_movement(delta)
	_process_lean(delta)
	_process_stance_input()
	_process_jump()
	_process_actions()
	move_and_slide()


# ── Gravity ───────────────────────────────────────────────────────
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta


# ── Movement ──────────────────────────────────────────────────────
func _process_movement(delta: float) -> void:
	var input := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward"
	)
	var dir   := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := _current_move_speed()
	var accel := ACCELERATION if dir != Vector3.ZERO else DECELERATION

	velocity.x = move_toward(velocity.x, dir.x * speed, accel * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, accel * delta)


func _current_move_speed() -> float:
	match _stance:
		Stance.CROUCH: return CROUCH_SPEED
		Stance.PRONE:  return PRONE_SPEED
		_:
			return RUN_SPEED if Input.is_action_pressed("run") else WALK_SPEED


# ── Lean ──────────────────────────────────────────────────────────
func _process_lean(delta: float) -> void:
	var target_angle  := 0.0
	var target_offset := 0.0

	if Input.is_action_pressed("lean_left"):
		target_angle  = -deg_to_rad(LEAN_ANGLE)
		target_offset = -LEAN_OFFSET_X
	elif Input.is_action_pressed("lean_right"):
		target_angle  =  deg_to_rad(LEAN_ANGLE)
		target_offset =  LEAN_OFFSET_X

	var t := LEAN_SPEED * delta
	_lean_angle  = lerp(_lean_angle,  target_angle,  t)
	_lean_offset = lerp(_lean_offset, target_offset, t)

	# rotation.z is lean roll; rotation.x is pitch (set separately in mouse look).
	# Both can coexist cleanly at these angles.
	_head.rotation.z = _lean_angle
	_head.position.x = _lean_offset


# ── Stance ────────────────────────────────────────────────────────
func _process_stance_input() -> void:
	if Input.is_action_just_pressed("crouch"):
		_request_stance(_next_crouch_stance())
	if Input.is_action_just_pressed("prone"):
		_request_stance(_next_prone_stance())


func _next_crouch_stance() -> Stance:
	match _stance:
		Stance.STAND:
			return Stance.CROUCH
		Stance.CROUCH:
			return Stance.STAND if _overhead_clear(STAND_HEIGHT) else Stance.CROUCH
		Stance.PRONE:
			return Stance.CROUCH if _overhead_clear(CROUCH_HEIGHT) else Stance.PRONE
	return _stance


func _next_prone_stance() -> Stance:
	match _stance:
		Stance.PRONE:
			if _overhead_clear(CROUCH_HEIGHT):
				return Stance.CROUCH
			if _overhead_clear(STAND_HEIGHT):
				return Stance.STAND
			return Stance.PRONE
		_:
			return Stance.PRONE


func _request_stance(new_stance: Stance) -> void:
	if new_stance == _stance:
		return
	_stance = new_stance

	var cap := _col_shape.shape as CapsuleShape3D
	if not cap:
		return

	var new_height  := _stance_capsule_height(new_stance)
	var new_head_y  := _stance_head_y(new_stance)
	var duration    := 1.0 / STANCE_SPEED

	if _stance_tween:
		_stance_tween.kill()
	_stance_tween = create_tween().set_parallel(true)
	_stance_tween.tween_property(cap,        "height",     new_height,          duration)
	_stance_tween.tween_property(_col_shape, "position:y", new_height / 2.0,    duration)
	_stance_tween.tween_property(_head,      "position:y", new_head_y,          duration)


func _stance_capsule_height(s: Stance) -> float:
	match s:
		Stance.CROUCH: return CROUCH_HEIGHT
		Stance.PRONE:  return PRONE_HEIGHT
		_:             return STAND_HEIGHT


func _stance_head_y(s: Stance) -> float:
	match s:
		Stance.CROUCH: return CROUCH_HEAD_Y
		Stance.PRONE:  return PRONE_HEAD_Y
		_:             return STAND_HEAD_Y


func _overhead_clear(required_height: float) -> bool:
	# Cast upward from PRONE_HEIGHT (above prone body) to required_height.
	# ShapeCast excludes the parent CharacterBody3D automatically.
	var check_dist := required_height - PRONE_HEIGHT
	if check_dist <= 0.0:
		return true
	_ceiling_check.target_position = Vector3(0.0, check_dist, 0.0)
	_ceiling_check.force_shapecast_update()
	return not _ceiling_check.is_colliding()


# ── Jump ──────────────────────────────────────────────────────────
func _process_jump() -> void:
	if not is_on_floor():
		return
	if not Input.is_action_just_pressed("jump"):
		return
	if _stance == Stance.PRONE:
		return  # can't jump from prone
	if not _overhead_clear(STAND_HEIGHT):
		return  # ceiling too low to jump
	if _stance == Stance.CROUCH:
		_request_stance(Stance.STAND)  # auto-stand before jumping
	velocity.y = JUMP_VELOCITY


# ── Actions ───────────────────────────────────────────────────────
func _process_actions() -> void:
	if Input.is_action_just_pressed("interact"):
		_try_interact()

	_is_aiming = Input.is_action_pressed("aim")

	if Input.is_action_just_pressed("fire"):
		weapon_fired.emit()
	if Input.is_action_just_pressed("reload"):
		weapon_reloaded.emit()
	if Input.is_action_just_pressed("throw"):
		weapon_thrown.emit()
	if Input.is_action_just_pressed("cycle_weapon_next"):
		_cycle_weapon(1)
	if Input.is_action_just_pressed("cycle_weapon_prev"):
		_cycle_weapon(-1)
	if Input.is_action_just_pressed("audio_callout"):
		audio_callout.emit()


# ── Interaction ───────────────────────────────────────────────────
func _try_interact() -> void:
	if not _interact_ray.is_colliding():
		return
	var target := _interact_ray.get_collider()
	if target and target.has_method("interact"):
		target.interact(self)
	interacted.emit(target)


# ── Weapons ───────────────────────────────────────────────────────
func _cycle_weapon(dir: int) -> void:
	if _weapons.is_empty():
		return
	_weapon_index = wrapi(_weapon_index + dir, 0, _weapons.size())
	weapon_cycled.emit(_weapon_index)


## Register a weapon node so the controller can cycle to it.
func register_weapon(weapon: Node) -> void:
	if not _weapons.has(weapon):
		_weapons.append(weapon)


## Remove a weapon node (e.g. when dropped or destroyed).
func unregister_weapon(weapon: Node) -> void:
	_weapons.erase(weapon)
	_weapon_index = clampi(_weapon_index, 0, max(0, _weapons.size() - 1))


## Returns the currently selected weapon node, or null if none registered.
func get_current_weapon() -> Node:
	if _weapons.is_empty():
		return null
	return _weapons[_weapon_index]


## True while the aim action is held.
func is_aiming() -> bool:
	return _is_aiming


## Current stance as an enum value.
func get_stance() -> Stance:
	return _stance
