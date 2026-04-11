# base_ai.gd
class_name BaseAI
extends CharacterBody2D

@onready var point: Node2D = $POINT
@onready var animator = $POINT/animator
@onready var vision: Area2D = $POINT/vision
@onready var collision: CollisionShape2D = $Collision
@onready var vie: HealthBar = $bare_de_vie

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var current_state: int = -1
var previous_state: int = 0
var state_functions: Dictionary = {}
var _changing_now := false

var last_direction := 1
var target: Node2D = null
var initial_position: Vector2

# Stats communes
var hp: int = 100
var max_hp: int = 100
var attack_power: int = 10
var position_x_attacker = null

# Distance & tracking
var max_tracking_distance: float = 1000.0
var confort_zone_max: float = 200.0
var confort_zone_min: float = 50.0

# Knockback
@export var HIT_STUN_TIME: float = 0.25
@export var HIT_KNOCK_X: float = 500.0
@export var HIT_KNOCK_Y: float = -180.0
@export var HIT_X_DAMP: float = 8.0
var _hit_elapsed := 0.0


# ============================================================
#  CYCLE DE VIE
# ============================================================

func _ready() -> void:
	initial_position = global_position
	animator.connect("animation_finished", Callable(self, "_on_animation_finished"))
	animator.connect("animation_looped", Callable(self, "_on_animation_looped"))
	vision.connect("body_entered", Callable(self, "_on_vision_body_entered"))
	vision.connect("body_exited", Callable(self, "_on_vision_body_exited"))
	_setup_states()
	_start()
	vie.max_health = max_hp
	vie.init_vie()


func _physics_process(delta: float) -> void:
	if current_state < 0:
		return
	state_functions[current_state]["execute"].call(delta)
	move_and_slide()


func _on_animation_finished() -> void:
	if current_state < 0:
		return
	if state_functions[current_state].has("animation_finished"):
		state_functions[current_state]["animation_finished"].call()


func _on_animation_looped() -> void:
	if current_state < 0:
		return
	if state_functions[current_state].has("animation_looped"):
		state_functions[current_state]["animation_looped"].call()


# ============================================================
#  VISION & TRACKING
# ============================================================

func _on_vision_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		target = body

func _on_vision_body_exited(body: Node2D) -> void:
	pass

func check_tracking() -> bool:
	if not target:
		return false
	if distance_to_target() > max_tracking_distance:
		target = null
		return false
	return true


# ============================================================
#  DÉGÂTS
# ============================================================

func apply_damage(amount: int, source_x) -> void:
	if _is_dead():
		return
	if _is_hit():
		return
	hp -= amount
	vie.emit_signal("health_request", -amount)
	vie.apparition_temp()
	if hp <= 0:
		_on_dead()
		return
	position_x_attacker = source_x
	_on_hit()

func _is_dead() -> bool:
	return false

func _is_hit() -> bool:
	return false

func _on_dead() -> void:
	pass

func _on_hit() -> void:
	pass


# ============================================================
#  À OVERRIDE DANS CHAQUE ENNEMI
# ============================================================

func _setup_states() -> void:
	pass

func _start() -> void:
	pass

func decide() -> void:
	pass


# ============================================================
#  STATE MACHINE
# ============================================================

func _register_states(states_enum: Dictionary) -> void:
	for state_name in states_enum:
		var key: int = states_enum[state_name]
		var name_lower: String = state_name.to_lower()
		var dict := {}

		for suffix in ["enter", "execute", "input", "exit", "animation_finished", "animation_looped"]:
			var func_name: String = name_lower + "_" + suffix
			if has_method(func_name):
				dict[suffix] = Callable(self, func_name)

		state_functions[key] = dict


func change_state(new_state: int) -> void:
	if _changing_now or new_state == current_state:
		return
	_changing_now = true
	if current_state >= 0 and state_functions[current_state].has("exit"):
		state_functions[current_state]["exit"].call()
	velocity.x = 0.0
	previous_state = current_state
	current_state = new_state
	state_functions[current_state]["enter"].call()
	_changing_now = false


func goto_state(new_state: int) -> void:
	if current_state == new_state:
		return
	call_deferred("change_state", new_state)


# ============================================================
#  UTILITAIRES
# ============================================================

const HORIZONTAL_DEAD_ZONE := 25.0

func flip_toward(target_x: float) -> void:
	var diff := target_x - global_position.x
	if absf(diff) < HORIZONTAL_DEAD_ZONE:
		return
	if diff > 0:
		last_direction = 1
	else:
		last_direction = -1
	point.scale.x = last_direction


func distance_to_target() -> float:
	if target:
		return global_position.distance_to(target.global_position)
	return INF


func direction_to_target() -> int:
	if target:
		var diff := target.global_position.x - global_position.x
		if absf(diff) < HORIZONTAL_DEAD_ZONE:
			return last_direction
		return 1 if diff > 0 else -1
	return last_direction

func force_reenter_state() -> void:
	_changing_now = true
	if state_functions[current_state].has("exit"):
		state_functions[current_state]["exit"].call()
	velocity.x = 0.0
	state_functions[current_state]["enter"].call()
	_changing_now = false

func apply_gravity(delta: float) -> void:
	velocity.y += gravity * delta

func move_toward_target(spd: float) -> void:
	if not target:
		return
	var diff := target.global_position.x - global_position.x
	flip_toward(target.global_position.x)
	if absf(diff) < HORIZONTAL_DEAD_ZONE:
		velocity.x = 0.0
		return
	velocity.x = last_direction * spd

func move_away_from_target(spd: float) -> void:
	if not target:
		return
	var diff := target.global_position.x - global_position.x
	flip_toward(target.global_position.x)
	if absf(diff) < HORIZONTAL_DEAD_ZONE:
		velocity.x = 0.0
		return
	velocity.x = -last_direction * spd

func move_toward_position(pos: Vector2, spd: float) -> void:
	var dir := 1 if pos.x > global_position.x else -1
	velocity.x = dir * spd
	point.scale.x = dir

# ============================================================
#  SYSTÈME DE DÉCISION
# ============================================================

func pick_weighted(options: Array) -> int:
	var total := 0.0
	for opt in options:
		total += opt[1]
	var roll := randf() * total
	var current := 0.0
	for opt in options:
		current += opt[1]
		if roll <= current:
			return opt[0]
	return options[0][0]
