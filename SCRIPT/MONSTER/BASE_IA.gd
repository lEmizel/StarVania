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
## Dégâts des attaques, EN CŒURS (lu par l'animator au moment du coup)
@export var attack_power: int = 1

# Distance & tracking
var max_tracking_distance: float = 1000.0
var confort_zone_max: float = 200.0
var confort_zone_min: float = 50.0

# Knockback — pas un état : un effet superposé au mouvement de l'état courant
@export var HIT_KNOCK_X: float = 1300.0
@export var HIT_KNOCK_Y: float = 0.0
@export var HIT_X_DAMP: float = 8.0
var _knock := Vector2.ZERO

## INÉBRANLABLE : aucun recul quand touché, et le joueur qui le frappe
## subit un contrecoup ×1.56 (voir animator.gd du player). Permanent
## (boss, via l'export) ou fenêtré par code (larve en boule de piques).
@export var inebranlable := false
## INVULNÉRABLE : les dégâts sont ignorés — aucun flash, aucune barre de
## vie, aucun feedback : l'absence de réaction EST le message
var invulnerable := false

# Flash blanc quand le monstre est touché
const HIT_FLASH_SHADER := preload("res://SCRIPT/MONSTER/hit_flash.gdshader")
@export var FLASH_DURATION: float = 0.15
var _flash_material: ShaderMaterial
var _flash_tween: Tween

# Dégâts de contact : toucher le corps d'un monstre vivant blesse le joueur (en cœurs)
@export var contact_damage: int = 1
var _contact_area: Area2D

# Récolte de sang lâchée à la mort (les particules volent vers le joueur
# et créditent du blood à l'arrivée)
const BLOOD_PARTICLE_SCENE := preload("res://SCRIPT/PARTICLE/BLOOD_PARTICLE.tscn")


# ============================================================
#  CYCLE DE VIE
# ============================================================

func _ready() -> void:
	initial_position = global_position
	# Miroir posé dans l'éditeur (tiroir d'assets, scale.x négatif) : la
	# physique n'aime pas les échelles négatives et l'IA marcherait à
	# l'envers → on normalise la racine et on convertit le miroir en
	# orientation de départ (regard + visuel à gauche)
	if scale.x < 0.0:
		scale.x = absf(scale.x)
		last_direction = -1
		point.scale.x = -1
	# Material créé par code → unique par instance (deux monstres touchés
	# ne clignotent pas ensemble), et aucune scène à modifier
	_flash_material = ShaderMaterial.new()
	_flash_material.shader = HIT_FLASH_SHADER
	animator.material = _flash_material
	_setup_contact_area()
	animator.connect("animation_finished", Callable(self, "_on_animation_finished"))
	animator.connect("animation_looped", Callable(self, "_on_animation_looped"))
	vision.connect("body_entered", Callable(self, "_on_vision_body_entered"))
	vision.connect("body_exited", Callable(self, "_on_vision_body_exited"))
	_setup_states()
	_start()
	vie.max_health = max_hp
	vie.init_vie()


## Oubli HORS DE VUE (commun à tous les monstres) : une cible tenue mais
## absente du cône de vision pendant ce temps est lâchée. 0 = n'oublie
## jamais faute de vue (boss).
@export var oubli_hors_vue := 4.0
var _hors_vue_temps := 0.0


func _physics_process(delta: float) -> void:
	if current_state < 0:
		return
	_tick_oubli_hors_vue(delta)
	state_functions[current_state]["execute"].call(delta)
	# Knockback absolu : tant qu'il est actif, il REMPLACE le déplacement
	# horizontal de l'état (l'ennemi ne peut pas compenser en marchant contre).
	# Injecté dans velocity pour que move_and_slide glisse le long du sol,
	# au lieu de move_and_collide qui se bloquait sur les jointures de tiles.
	if _knock != Vector2.ZERO:
		velocity.x = _knock.x
	move_and_slide()
	_decay_knockback(delta)
	_check_contact_damage()


func _tick_oubli_hors_vue(delta: float) -> void:
	if oubli_hors_vue <= 0.0 or target == null or _is_dead():
		_hors_vue_temps = 0.0
		return
	if vision.overlaps_body(target):
		_hors_vue_temps = 0.0
		return
	_hors_vue_temps += delta
	if _hors_vue_temps >= oubli_hors_vue:
		_hors_vue_temps = 0.0
		_oublier_cible()


## Décrochage de la cible — surchargable par les enfants (le squelette et
## la larve y ajoutent leur délai de grâce anti re-scan)
func _oublier_cible() -> void:
	target = null


# ============================================================
#  DÉGÂTS DE CONTACT
# ============================================================

## Zone de contact créée par code : copie la forme de $Collision,
## détecte le corps du joueur (layer 1)
func _setup_contact_area() -> void:
	_contact_area = Area2D.new()
	_contact_area.collision_layer = 0
	_contact_area.collision_mask = 1
	var cs := CollisionShape2D.new()
	cs.shape = collision.shape
	cs.position = collision.position
	cs.rotation = collision.rotation
	cs.scale = collision.scale
	_contact_area.add_child(cs)
	add_child(_contact_area)


func _check_contact_damage() -> void:
	if _is_dead():
		return
	for body in _contact_area.get_overlapping_bodies():
		if body.is_in_group("Player") and body.has_method("apply_damage"):
			# L'invulnérabilité du joueur (état HIT / ROLL) limite la cadence
			body.apply_damage(contact_damage, global_position.x, "contact:" + name)


## Décroissance du knockback ; à la fin, on purge la vitesse résiduelle
func _decay_knockback(delta: float) -> void:
	if _knock == Vector2.ZERO:
		return
	_knock = _knock.lerp(Vector2.ZERO, clamp(HIT_X_DAMP * delta, 0.0, 1.0))
	if _knock.length_squared() < 25.0:
		_knock = Vector2.ZERO
		velocity.x = 0.0


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

func _flash_white() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_material.set_shader_parameter("flash_amount", 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_material,
		"shader_parameter/flash_amount", 0.0, FLASH_DURATION)


## _source_tag : étiquette de provenance optionnelle (parité avec le player,
## utilisée par les logs de debug — sans effet sur la logique)
func apply_damage(amount: int, source_x, _source_tag := "?") -> void:
	if _is_dead():
		return
	if invulnerable:
		return
	hp -= amount
	vie.emit_signal("health_request", -amount)
	vie.apparition_temp()
	_flash_white()
	if hp <= 0:
		_knock = Vector2.ZERO
		# Cadavre inerte : plus détectable ni bloquant (layer 0), mais il garde
		# son mask pour continuer de reposer sur le sol
		set_deferred("collision_layer", 0)
		if _contact_area != null:
			_contact_area.set_deferred("monitoring", false)
		# Récolte de sang à l'endroit de la mort
		var blood := BLOOD_PARTICLE_SCENE.instantiate()
		get_tree().current_scene.add_child(blood)
		blood.global_position = global_position
		_on_dead()
		return
	# Attaqué — même de dos, même hors vision, même par un projectile : le
	# monstre prend le joueur pour cible, se retourne vers LUI (pas vers le
	# projectile, qui est déjà au contact) et réagit immédiatement sans
	# attendre le prochain cycle de décision de son état
	if target == null:
		var players := get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			target = players[0]
			if has_method("decide"):
				call_deferred("decide")
	if target != null:
		flip_toward(target.global_position.x)
	elif source_x != null:
		flip_toward(source_x)
	# Knockback appliqué par-dessus l'état courant, sans l'interrompre —
	# sauf inébranlable : aucun recul, c'est le joueur qui encaisse
	if inebranlable:
		return
	var dir := 0
	if source_x != null:
		dir = 1 if (global_position.x - source_x) > 0 else -1
	_knock = Vector2(dir * HIT_KNOCK_X, HIT_KNOCK_Y)

func _is_dead() -> bool:
	return false

func _on_dead() -> void:
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

		# L'enum est un contrat : tout état déclaré doit être implémenté.
		# enter + execute sont obligatoires (appelés sans vérification) —
		# on le signale dès le lancement plutôt que de crasher le jour
		# où l'état est sélectionné (cf. l'ancien état WALK fantôme)
		if not dict.has("enter") or not dict.has("execute"):
			push_error("[%s] État '%s' déclaré dans l'enum mais incomplet : il manque %s%s" % [
				name, state_name,
				"" if dict.has("enter") else "%s_enter() " % name_lower,
				"" if dict.has("execute") else "%s_execute()" % name_lower,
			])


func change_state(new_state: int) -> void:
	if _changing_now or new_state == current_state:
		return
	# Garde-fou : refuse un état inconnu ou incomplet au lieu de crasher
	if not state_functions.has(new_state) or not state_functions[new_state].has("enter"):
		push_error("[%s] change_state vers un état invalide ou non implémenté : %d" % [name, new_state])
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

## Y a-t-il un danger d'environnement (Area2D du groupe DEGATS — piques…)
## sur le trajet de ce raycast de détection de vide ? Les terrestres le
## traitent comme un trou : demi-tour au lieu d'y marcher.
## (le groupe peut être sur l'Area2D ou sur son CollisionShape2D enfant)
func danger_devant(rc: RayCast2D) -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	var seg := SegmentShape2D.new()
	seg.a = rc.global_position
	seg.b = rc.to_global(rc.target_position)
	params.shape = seg
	params.transform = Transform2D.IDENTITY
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 8):
		var col = hit.get("collider")
		if col is Area2D:
			if col.is_in_group("DEGATS"):
				return true
			for child in col.get_children():
				if child.is_in_group("DEGATS"):
					return true
	return false


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
