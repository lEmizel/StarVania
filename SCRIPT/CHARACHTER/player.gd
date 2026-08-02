extends CharacterBody2D


enum States { IDLE, RUN, CHUTE, JUMP, WALL_GRIFFE, WALL_JUMP, CLIMB, ROLL, CHUTE_GRIFFE, GRAB, ATTACK_LIGHT_1, ATTACK_LIGHT_2, ATTACK_LIGHT_3, ATTACK_AIR, ATTACK_LOURDE, DEAD, HIT, HEAL, DROP, BLOODBALL, ECHELLE, DASH }



@onready var wall_right: RayCast2D = $POINT/wall_right
@onready var wall_left: RayCast2D = $POINT/wall_left
@onready var climbcast_up: RayCast2D = $POINT/climbcast_up
@onready var climbcast_down: RayCast2D = $POINT/climbcast_down
@onready var climbcast_left: RayCast2D = $POINT/climbcast_left
@onready var climbcast_right: RayCast2D = $POINT/climbcast_right
@onready var grab: RayCast2D = $POINT/GRAB
@onready var ancre_grab: Node2D = $POINT/ANCRE_GRAB
@onready var slash_attack: AnimatedSprite2D = $POINT/slash_attack

@onready var ANCRE_SOL_BACK: Node2D = $POINT/ANCRE_SOL_BACK
@onready var ANCRE_SOL: Node2D = $POINT/ANCRE_SOL
@onready var ANCRE_WALL: Node2D = $POINT/ANCRE_WALL

@onready var point: Node2D = $POINT # le node 2d qui sert a flip le personnage
@onready var animator = $POINT/animator
@onready var spellcast: Marker2D = $POINT/SPELLCAST
@onready var collision_normale: CollisionShape2D = $CollisionShape2D
@onready var collision_roulade: CollisionShape2D = $CollisionShaperoulage
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var current_state : States = States.IDLE
var previous_state : States = States.IDLE
var state_functions: Dictionary = {}

const GROUND_SPEED = 550            # FIX: renommé pour clarté
const AIR_SPEED    = 400            # FIX: anciennement var SPEED locale shadowed
@export var GROUND_SPEED_ATTACK: float = 450.0  # vitesse de course pendant les attaques
## Nombre de cœurs de vie max — synchronisé vers le singleton Player au spawn
@export var MAX_HEARTS: int = 5
var last_direction := 1  # 1 = droite, -1 = gauche

const CLIMB_SPEED := 200.0
const ROLL_SPEED := 700.0

const COYOTE_TIME := 0.08
var _coyote_timer := 0.0
const JUMP_BUFFER_TIME := 0.12  # très court — juste un filet de sécurité
var _jump_buffer_timer := 0.0

const GRAB_COOLDOWN := 0.2  # secondes avant de pouvoir re-grab
var _grab_cooldown_timer := 0.0
var current_grab_area: Area2D = null

const FOOTSTEP_SCENE = preload("uid://bc2iigjdyudgm")
const CHUTE_SCENE = preload("uid://bfwic6xtfgc4p")
const WALL_JUMP_SCENE = preload("uid://c5a6or75xrx3o")

# AMÉLIORATION: combo_count remplace le bool "combo" — plus clair et extensible
var combo_buffered := false   # true si le joueur a appuyé pendant l'anim en cours





func _enter_tree() -> void:
	# Synchro AVANT le _ready des enfants : le HUD (enfant de cette scène)
	# lit ces valeurs pour construire sa rangée de cœurs
	Player.max_hearts = MAX_HEARTS
	Player.MAX_HP = MAX_HEARTS
	Player.hp = mini(Player.hp, MAX_HEARTS)


func _ready() -> void:
	# Les raycasts de mur ne détectent QUE les corps solides : une Area2D
	# (checkpoint, grab, porte...) qui chevauche un mur arrêterait le rayon
	# avant le mur et ferait clignoter l'accroche du wall jump
	wall_right.collide_with_areas = false
	wall_left.collide_with_areas = false
	wall_right.collide_with_bodies = true
	wall_left.collide_with_bodies = true

	animator.connect("animation_finished", Callable(self, "_on_animation_finished"))
	set_floor_max_angle(deg_to_rad(60))
	set_floor_snap_length(6.0)
	print(Player.hp,"hp")
	initialize_states()
	change_state(States.IDLE)


var _facing_prev := 1.0

func _physics_process(delta: float) -> void:
	state_functions[current_state]["execute"].call(delta)
	# Le slash FX est enfant de POINT : si le perso se retourne pendant que
	# la traînée joue, elle partirait en miroir avec lui → on la coupe.
	# Détection centralisée ici pour couvrir tous les flips (run, jump, chute...)
	if signf(point.scale.x) != signf(_facing_prev):
		_cut_slash_fx()
	_facing_prev = point.scale.x
	# Recharge du double saut + référence des dégâts de chute : au sol elle
	# suit le perso ; en l'air elle garde le point le PLUS HAUT du vol —
	# un double saut ne peut donc jamais effacer une chute accumulée
	if is_on_floor():
		_double_jump_used = false
		_air_dash_used = false
		FALL_POINT = global_position.y
	else:
		FALL_POINT = minf(FALL_POINT, global_position.y)
	# accroche d'échelle en MAINTENU : le verrou posé en quittant une échelle
	# ne saute qu'une fois haut/bas relâchés, sinon on s'y raccrocherait
	# instantanément après un saut/esquive/hissage
	if _echelle_regrab_lock and not Input.is_action_pressed("up_move") \
		and not Input.is_action_pressed("down_move"):
		_echelle_regrab_lock = false
	# Knockback absolu — même principe que les monstres (BASE_IA) : tant qu'il
	# est actif, il remplace le déplacement horizontal, via velocity pour que
	# move_and_slide glisse le long du sol
	if _knock != Vector2.ZERO:
		velocity.x = _knock.x
	move_and_slide()
	_decay_knockback(delta)


var _knock := Vector2.ZERO

func _decay_knockback(delta: float) -> void:
	if _knock == Vector2.ZERO:
		return
	_knock = _knock.lerp(Vector2.ZERO, clamp(HIT_X_DAMP * delta, 0.0, 1.0))
	# Seuil de coupure haut (150 px/s) : dès que la poussée devient faible,
	# le joueur reprend IMMÉDIATEMENT le contrôle — pas de queue de knockback
	# qui écrase sa vitesse de course et donne une sensation de ralenti
	if _knock.length_squared() < 22500.0:
		_knock = Vector2.ZERO
		velocity.x = 0.0


## Contrecoup quand le joueur frappe un ennemi inébranlable (sans knockback) :
## si le joueur est en mouvement, une contre-poussée inverse annule son élan
func cancel_movement_recoil() -> void:
	if absf(velocity.x) < 1.0:
		return
	_knock.x = -velocity.x * 1.56  # contrecoup amplifié : 1.2 × 1.3 (+30%)
	velocity.x = 0.0


func _cut_slash_fx() -> void:
	slash_attack.stop()
	slash_attack.visible = false


### GESTION DES INPUTS ###
func _input(event):
	# DEBUG spell : l'événement arrive-t-il jusqu'au player, et dans quel état ?
	if event.is_action_pressed("spell"):
		print("[SPELL] événement reçu — état=", States.keys()[current_state])
	if state_functions[current_state].has("input"):
		state_functions[current_state]["input"].call(event)

# Dispatcher animation_finished (sans argument)
func _on_animation_finished() -> void:
	var funcs = state_functions[current_state]
	if funcs.has("animation_finished"):
		funcs["animation_finished"].call()


# ---------------------------------------------------------
#  UTILITAIRES
# ---------------------------------------------------------

## goto_state : transition DIFFÉRÉE (call_deferred) — à utiliser depuis execute/physics
## pour éviter de changer d'état pendant qu'on est encore dans le callback.
## change_state : transition IMMÉDIATE — à utiliser depuis input/animation_finished.
# AMÉLIORATION: documentation claire de la distinction



func _handle_landing() -> void:
	calcule_falling_damage()
	if current_state == States.DEAD or current_state == States.HIT:
		return
	var land_fx = instantiate_scene(CHUTE_SCENE)
	land_fx.global_position = ANCRE_SOL.global_position
	if land_fx is AnimatedSprite2D:
		land_fx.play()
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer = 0.0
		goto_state(States.JUMP)
		return
	if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
		goto_state(States.RUN)
	else:
		goto_state(States.IDLE)

func apply_damage(amount: int, source_x, source_tag := "?") -> void:
	if current_state in [States.ROLL, States.DASH, States.DEAD]:
		return
	if current_state == States.HIT:
		# DEBUG dégâts : coup ignoré pendant le stun
		print("[DMG bloqué/stun] f=", Engine.get_physics_frames(),
			" src=", source_tag, " amount=", amount)
		return
	print("[DMG] f=", Engine.get_physics_frames(),
		" src=", source_tag, " amount=", amount,
		" état=", States.keys()[current_state],
		" hp ", Player.hp, " -> ", Player.hp - amount)
	Player.changement_de_vie(-amount)
	if Player.hp <= 0:
		_knock = Vector2.ZERO
		change_state(States.DEAD)
		return
	# Knockback horizontal absolu, l'état HIT gère stun + anim
	var dir := 0
	if source_x != null:
		dir = 1 if (global_position.x - source_x) > 0 else -1
	_knock = Vector2(dir * HIT_KNOCK_X, 0.0)
	change_state(States.HIT)
	# Soulèvement : impulsion verticale one-shot, appliquée APRÈS hit_enter
	# (qui remet velocity à zéro) — la gravité gère la retombée
	velocity.y = HIT_KNOCK_Y


func goto_state(s: States) -> void:
	if current_state == s:
		return
	call_deferred("change_state", s)

## Détection de mur pour le wall jump : uniquement les StaticBody2D
## explicitement marqués (groupe "wall_jump") — l'opt-in permet au level
## design de décider quels murs sont grimpables
func _raycast_hits_wall(rc: RayCast2D) -> bool:
	rc.force_raycast_update()
	if not rc.is_colliding():
		return false
	var col := rc.get_collider()
	return col is StaticBody2D and col.is_in_group("wall_jump")


func _raycast_hits_group(rc: RayCast2D, group_name: String, body_only := false) -> bool:
	# AMÉLIORATION: note — cette fonction peut faire plusieurs force_raycast_update
	# par appel si des colliders sont empilés. Surveiller les perfs si besoin.
	var ignored: Array[RID] = []
	rc.clear_exceptions()

	while rc.is_colliding():
		var col := rc.get_collider()
		var ok := false
		if body_only:
			ok = col is PhysicsBody2D and col.is_in_group(group_name)
		else:
			ok = col is Area2D and col.is_in_group(group_name)

		if ok:
			for rid in ignored:
				rc.remove_exception_rid(rid)
			rc.force_raycast_update()
			return true

		var rid := rc.get_collider_rid()
		rc.add_exception_rid(rid)
		ignored.append(rid)
		rc.force_raycast_update()

	for rid in ignored:
		rc.remove_exception_rid(rid)
	rc.force_raycast_update()
	return false



const FALL_DAMAGE_ENABLED := true

## Dégâts de chute, à l'échelle CŒURS :
## - en dessous de SAFE_HEIGHT : rien
## - au-delà : 1 cœur, +1 par tranche de STEP_PX supplémentaire
## - plafonné à LETHAL_DAMAGE (10) : une très grande chute reste mortelle
##   quel que soit le nombre de cœurs du joueur
func calcule_falling_damage() -> int:
	const SAFE_HEIGHT: float   = 850.0
	const STEP_PX: float       = 250.0
	const LETHAL_DAMAGE: int   = 10

	# Sentinelle : aucun départ de chute enregistré → pas de dégâts possibles
	if FALL_POINT <= -1e8:
		return 0

	var impact_point: float  = global_position.y
	var fall_distance: float = max(0.0, impact_point - FALL_POINT)

	if fall_distance <= SAFE_HEIGHT:
		return 0

	var excess: float = fall_distance - SAFE_HEIGHT
	var damage: int = clampi(1 + int(excess / STEP_PX), 1, LETHAL_DAMAGE)
	if FALL_DAMAGE_ENABLED:
		apply_damage(damage, null, "chute")
	print("Dégâts de chute : ", damage, " cœur(s) | hauteur : ", int(fall_distance), " px")
	return damage


func instantiate_scene(scene_ref, parent_node: Node = null) -> Node:
	var packed: PackedScene
	if scene_ref is PackedScene:
		packed = scene_ref
	elif scene_ref is String:
		packed = load(scene_ref)
	else:
		push_error("instantiate_scene: scene_ref doit être PackedScene ou String")
		return null

	var instance = packed.instantiate()
	var target_parent: Node = parent_node if parent_node != null else get_tree().get_current_scene()
	target_parent.add_child(instance)
	return instance

func _flip_facing_on_wall() -> void:
	point.scale.x *= -1
	last_direction = -last_direction


func _flip_from_input() -> void:
	var dir := Input.get_axis("left_move", "right_move")
	if dir != 0:
		last_direction = sign(dir)
		point.scale.x  = last_direction

# ----------- Initialisation des états -------------------
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

func initialize_states() -> void:
	_register_states(States)

# ----------- Gestion du changement d'état ---------------

var _changing_now := false

func change_state(new_state: States) -> void:
	#print("[", Engine.get_physics_frames(), "] ",
		#"STATE: ", current_state, " -> ", new_state,
		#" | on_floor=", is_on_floor(), " | vel=", velocity)

	if _changing_now or new_state == current_state:
		return

	_changing_now = true
	state_functions[current_state]["exit"].call()
	previous_state = current_state
	current_state  = new_state
	_state_enter_frame = Engine.get_process_frames()
	state_functions[current_state]["enter"].call()
	_changing_now = false


# Frame d'entrée dans l'état courant : sert à ignorer les pressions "fantômes"
# quand deux actions partagent un bouton (ex. jump et griffe sur le bouton 0 :
# la pression qui fait ENTRER dans wall_griffe ne doit pas aussi déclencher
# le saut de sortie dans la même frame)
var _state_enter_frame := 0

## Comme is_action_just_pressed, mais ignore la pression qui a déclenché
## l'entrée dans l'état courant (même frame)
func _fresh_press(action: String) -> bool:
	return Input.is_action_just_pressed(action) \
		and Engine.get_process_frames() != _state_enter_frame

# =====================  IDLE  ===========================
#region IDLE

func idle_enter() -> void:
	animator.play("idle")
	velocity = Vector2.ZERO


func idle_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)


func idle_input(event: InputEvent) -> void:
	if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
		change_state(States.RUN)
	elif Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	elif Input.is_action_just_pressed("heal"):
		_try_heal()
		return
	elif Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_1)
		return
	elif Input.is_action_just_pressed("spell"):
		_try_cast_bloodball()
		return
	elif (Input.is_action_pressed("up_move") or Input.is_action_pressed("down_move")) \
		and _try_echelle():
		return
	elif Input.is_action_just_pressed("down_move") and is_on_floor():
		change_state(States.DROP)
		return

func idle_exit() -> void:
	pass
#endregion

# =====================  RUN  ===========================

var run_frame_counter : int = 0



func run_enter() -> void:
	animator.play("run")


func run_execute(delta: float) -> void:
	run_frame_counter += 1
	_flip_from_input()

	velocity.y += gravity * delta

	if not is_on_floor():
		goto_state(States.CHUTE)
		return

	var direction := Input.get_axis("left_move", "right_move")

	if direction == 0:
		goto_state(States.IDLE)
		return

	if animator.animation == "run" and run_frame_counter % 10 == 0:
		var foot = instantiate_scene(FOOTSTEP_SCENE)
		foot.global_position = ANCRE_SOL_BACK.global_position
		foot.scale.x        *= point.scale.x
		foot.play("run_to_ground")

	# FIX: utilise GROUND_SPEED au lieu de SPEED
	var target_speed: float = float(direction) * GROUND_SPEED
	velocity.x = lerp(velocity.x, target_speed, 0.15)


func run_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	elif Input.is_action_just_pressed("heal"):
		_try_heal()
		return
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	elif Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_1)
		return
	elif Input.is_action_just_pressed("spell"):
		_try_cast_bloodball()
		return
	elif (Input.is_action_pressed("up_move") or Input.is_action_pressed("down_move")) \
		and _try_echelle():
		return
	elif Input.is_action_just_pressed("down_move") and is_on_floor():
		change_state(States.DROP)
		return

func run_exit() -> void:
	pass


#region JUMP

## Impulsion de saut (négatif = vers le haut). Plus la valeur est grande
## en absolu, plus le saut monte haut.
@export var JUMP_VELOCITY: float = -700.0
const MIN_JUMP_TIME   := 0.01
const MAX_JUMP_HOLD   := 0.25
const GRAVITY_RISE    := 0.45    # hold long → monte bien haut
const GRAVITY_CUTOFF  := 3.50    # lâche tôt → coupe net
const GRAVITY_FALL    := 1.35

const AIR_CONTROL = 0.2
const DECELERATION_RATE = 0.95
var _jump_timer := 0.0
var _climb_auto_exit := false
const CLIMB_EXIT_VELOCITY := -1000.0  # plus fort que JUMP_VELOCITY (-700)

# --- DOUBLE SAUT ---
## Capacité metroidvania : désactivable tant qu'elle n'est pas débloquée
@export var double_jump_enabled := true
## Impulsion du second saut (souvent un peu plus faible que le premier)
@export var DOUBLE_JUMP_VELOCITY: float = -650.0
var _double_jump_used := false
var _dj_pending := false  # signal pour jump_enter : c'est un double saut


## Tente le double saut (appelé depuis JUMP et CHUTE sur appui de saut en l'air)
func _try_double_jump() -> bool:
	if not double_jump_enabled or _double_jump_used or is_on_floor():
		return false
	_double_jump_used = true
	if current_state == States.JUMP:
		# déjà dans l'état JUMP : on ré-applique l'impulsion directement
		velocity.y = DOUBLE_JUMP_VELOCITY
		_jump_timer = 0.0            # ré-arme la fenêtre de hold du saut
		animator.play("jump")
	else:
		_dj_pending = true
		change_state(States.JUMP)
	return true

func jump_enter():
	animator.play("jump")
	_jump_timer = 0.0
	# (FALL_POINT est géré en continu dans _physics_process : suivi au sol,
	# point le plus haut conservé en vol)

	if _climb_auto_exit:
		velocity.y = CLIMB_EXIT_VELOCITY
		velocity.x = 0.0
		_climb_auto_exit = false
		_jump_timer = MAX_JUMP_HOLD  # ← désactive le hold, gravité normale immédiate
	elif _echelle_top_exit:
		_echelle_top_exit = false
		velocity.y = ECHELLE_TOP_JUMP_VELOCITY
		velocity.x = 0.0
		_jump_timer = MAX_JUMP_HOLD  # hissage sec, sans hold
	elif _dj_pending:
		_dj_pending = false
		velocity.y = DOUBLE_JUMP_VELOCITY
	else:
		velocity.y = JUMP_VELOCITY


func jump_execute(delta):
	_jump_timer += delta
	_grab_cooldown_timer = max(_grab_cooldown_timer - delta, 0.0)

	var direction = Input.get_axis("left_move", "right_move")
	_flip_from_input()
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	if is_on_ceiling():
		velocity.y = 0.0

	var g_mul := 1.0
	if velocity.y < 0.0:
		var holding := Input.is_action_pressed("jump")
		var force_min := _jump_timer < MIN_JUMP_TIME
		var within_hold := _jump_timer < MAX_JUMP_HOLD

		if force_min or (holding and within_hold):
			g_mul = GRAVITY_RISE
		else:
			g_mul = GRAVITY_CUTOFF
	else:
		g_mul = GRAVITY_FALL

	velocity.y += gravity * g_mul * delta

	if _grab_cooldown_timer <= 0.0 and _raycast_hits_group(grab, "GRAB"):
		current_grab_area = grab.get_collider()
		change_state(States.GRAB)
		return

	if velocity.y > 0.0:
		change_state(States.CHUTE)

func jump_input(event: InputEvent) -> void:
	# PRIORITÉ griffe : jump et griffe partagent le bouton — près d'une
	# surface accrochable, la pression accroche au lieu de double-sauter
	if Input.is_action_just_pressed("griffe"):
		var hit_r := _raycast_hits_group(climbcast_right, "CLIMB")
		var hit_l := _raycast_hits_group(climbcast_left,  "CLIMB")
		if hit_r and hit_l:
			change_state(States.CLIMB)
			return
		if _raycast_hits_group(climbcast_right, "GRIFFE") and absf(velocity.x) > 0.0:
			change_state(States.WALL_GRIFFE)
			return
	if Input.is_action_just_pressed("jump"):
		if _try_double_jump():
			return
	if _fresh_press("esquive") and _try_air_dash():
		return
	if (Input.is_action_pressed("up_move") or Input.is_action_pressed("down_move")) \
		and _try_echelle():
		return
	if Input.is_action_just_pressed("spell"):
		_try_cast_bloodball()
		return
	if Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_AIR)
		return

func jump_exit():
	pass
#endregion




#region CHUTE

# =====================  CHUTE  ===========================
var FALL_POINT: float = -1e9

func chute_enter() -> void:
	if previous_state in [States.RUN, States.IDLE]:
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = 0.0
	animator.play("chute")


func chute_execute(delta: float) -> void:
	var direction := Input.get_axis("left_move", "right_move")
	_grab_cooldown_timer = max(_grab_cooldown_timer - delta, 0.0)
	_coyote_timer = max(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = max(_jump_buffer_timer - delta, 0.0)

	if direction != 0:
		if previous_state != States.WALL_JUMP or absf(velocity.x) < 100.0:
			last_direction = sign(direction)
			point.scale.x = last_direction

	velocity.y += gravity * delta

	if direction != 0:
		velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	if _grab_cooldown_timer <= 0.0 and _raycast_hits_group(grab, "GRAB"):
		current_grab_area = grab.get_collider()
		change_state(States.GRAB)
		return

	if _raycast_hits_wall(wall_right):
		change_state(States.WALL_JUMP)
		return

	if is_on_floor():
		_handle_landing()


func chute_input(event: InputEvent) -> void:
	# PRIORITÉ griffe : jump et griffe partagent le bouton — près d'une
	# surface accrochable, la pression accroche au lieu de (double-)sauter
	if Input.is_action_just_pressed("griffe"):
		if _raycast_hits_group(climbcast_up, "CHUTE"):
			change_state(States.CHUTE_GRIFFE)
			return
		var hit_r := _raycast_hits_group(climbcast_right, "CLIMB")
		var hit_l := _raycast_hits_group(climbcast_left,  "CLIMB")
		if hit_r and hit_l:
			change_state(States.CLIMB)
			return
		if _raycast_hits_group(climbcast_right, "GRIFFE") and absf(velocity.x) > 0.0:
			change_state(States.WALL_GRIFFE)
			return

	if Input.is_action_just_pressed("jump"):
		if _coyote_timer > 0.0:
			_coyote_timer = 0.0
			change_state(States.JUMP)
			return
		elif _try_double_jump():
			return
		else:
			_jump_buffer_timer = JUMP_BUFFER_TIME

	if _fresh_press("esquive") and _try_air_dash():
		return

	if (Input.is_action_pressed("up_move") or Input.is_action_pressed("down_move")) \
		and _try_echelle():
		return

	if Input.is_action_just_pressed("spell"):
		_try_cast_bloodball()
		return

	if Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_AIR)
		return


func chute_exit() -> void:
	pass
#endregion



#region WALL_GRIFFE
## S'accrocher à quelque chose (mur, griffe, échelle, point de grab…)
## recharge le double saut et le dash aérien
func _recharge_air_moves() -> void:
	_double_jump_used = false
	_air_dash_used = false


func wall_griffe_enter():
	animator.play("wall_griffe")
	velocity.y = 0
	_recharge_air_moves()

	# On détermine la direction selon la vélocité d'arrivée
	if velocity.x > 0:
		last_direction = 1
	elif velocity.x < 0:
		last_direction = -1

	point.scale.x = last_direction

	# On pousse le perso DANS le mur pour maintenir le contact raycast
	# Le mur bloque le déplacement réel, mais la vélocité garde le contact
	velocity.x = 500.0 * last_direction

func wall_griffe_execute(_delta: float) -> void:
	FALL_POINT = global_position.y  # appui légitime : accroché au mur
	if _raycast_hits_group(climbcast_right, "GRIFFE"):
		return
	change_state(States.CHUTE)

func wall_griffe_input(event: InputEvent):
	# _fresh_press : jump partage le bouton de griffe — la pression qui a
	# accroché le mur ne doit pas faire sauter dans la foulée
	if _fresh_press("jump"):
		change_state(States.JUMP)

func wall_griffe_animation_finished():
	change_state(States.CHUTE)

func wall_griffe_exit():
	pass
#endregion





#region WALL_JUMP
enum WallJumpPhase { SLIDING, JUMPING }
var _wj_phase: WallJumpPhase = WallJumpPhase.SLIDING
const WALL_YJUMP := -500.0
const WALL_XJUMP := 290.0
const WALL_GLIDE_SPEED := 300.0

func wall_jump_enter():
	_flip_facing_on_wall()
	velocity = Vector2.ZERO
	_wj_phase = WallJumpPhase.SLIDING
	_recharge_air_moves()
	animator.play("wall_jump")

func wall_jump_execute(delta: float) -> void:
	match _wj_phase:
		WallJumpPhase.SLIDING:
			# Vérif mur des DEUX côtés : les deux raycasts ne sont pas des
			# jumeaux parfaits (hauteur/longueur), et selon le point d'accroche
			# l'un peut rater là où l'autre touche → clignotement CHUTE↔WALL_JUMP.
			# Le test symétrique est insensible au flip et à leurs différences.
			var on_wall := _raycast_hits_wall(wall_left) or _raycast_hits_wall(wall_right)
			if not on_wall:
				change_state(States.CHUTE)
				return
			# Plaque le perso contre le mur (même technique que wall_griffe) :
			# le mur bloque le déplacement réel, mais le contact physique et
			# les raycasts restent stables — sans ça, il flotte à quelques px
			# du mur et l'accroche peut osciller frame à frame
			velocity.x = -last_direction * 150.0
			# Appui légitime : la glissade murale remet la chute à zéro
			FALL_POINT = global_position.y
			# Glissement
			velocity.y = lerp(velocity.y, WALL_GLIDE_SPEED, 0.05)
			if is_on_floor():
				change_state(States.IDLE)

		WallJumpPhase.JUMPING:
			velocity.y += gravity * delta
			if velocity.y > 0:
				change_state(States.CHUTE)

func wall_jump_input(event: InputEvent) -> void:
	if _wj_phase == WallJumpPhase.SLIDING:
		if Input.is_action_just_pressed("jump"):
			_wj_phase = WallJumpPhase.JUMPING
			var land_fx = instantiate_scene(WALL_JUMP_SCENE)
			land_fx.global_position = ANCRE_WALL.global_position
			land_fx.scale.x *= point.scale.x
			if land_fx is AnimatedSprite2D:
				land_fx.play()
			animator.play("jump")
			velocity.y = WALL_YJUMP
			velocity.x = WALL_XJUMP * last_direction
		elif Input.is_action_just_pressed("esquive"):
			change_state(States.CHUTE)

func wall_jump_exit():
	pass
#endregion



func climb_enter() -> void:
	velocity = Vector2.ZERO
	_recharge_air_moves()
	animator.play("climbidle")

func climb_execute(delta: float) -> void:
	FALL_POINT = global_position.y  # appui légitime : en escalade
	var dir := Input.get_vector("left_move", "right_move",
		"up_move",   "down_move")

	const DEAD_ZONE := 0.3
	if abs(dir.x) < DEAD_ZONE:
		dir.x = 0

	var can_climb_forward := _raycast_hits_group(climbcast_right, "CLIMB")

	if not can_climb_forward and animator.animation != "climbquit":
		animator.play("climbquit")

	if can_climb_forward and animator.animation == "climbquit":
		animator.play("climbidle")

	if not can_climb_forward:
		if sign(point.scale.x) > 0:
			dir.x = min(dir.x, 0)
		else:
			dir.x = max(dir.x, 0)
		dir.y = 0

	if animator.animation != "climbquit":
		if dir == Vector2.ZERO:
			animator.play("climbidle")
		else:
			if abs(dir.x) > abs(dir.y):
				animator.play("climb_move_up")
			elif dir.y < 0:
				animator.play("climb_move_up")
			else:
				animator.play("climb_move_down")

	velocity = dir * CLIMB_SPEED
	_flip_from_input()

	var hit_left  := _raycast_hits_group(climbcast_left,  "CLIMB")
	var hit_right := _raycast_hits_group(climbcast_right, "CLIMB")
	if not (hit_left or hit_right):
		change_state(States.CHUTE)
		return

	var hit_up := _raycast_hits_group(climbcast_up, "CLIMB")
	if not hit_up:
		_climb_auto_exit = true
		change_state(States.JUMP)
		return

func climb_input(event: InputEvent) -> void:
	# FIX: déplacé depuis climb_execute — just_pressed appartient à _input
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)
		return
	elif _fresh_press("jump"):  # même bouton que griffe → filtre la pression d'entrée
		change_state(States.JUMP)
		return

func climb_exit() -> void:
	pass


# =====================  ECHELLE  ===========================
#region ECHELLE
## État parallèle à CLIMB, dédié aux échelles (zones Area2D du groupe
## "ECHELLE") : on ne peut QUE monter et descendre. Seule échappatoire : sauter.

@export var ECHELLE_SPEED: float = 250.0
## Impulsion du saut automatique de hissage en sortie haute d'échelle
@export var ECHELLE_TOP_JUMP_VELOCITY: float = -1200.0
## Butée haute de grimpe : distance (px) entre le sommet de la ZONE de
## l'échelle et l'origine du perso au maximum de la montée. Plus grand =
## le perso s'arrête plus bas. À régler à l'œil dans l'inspecteur.
@export var ECHELLE_TOP_OFFSET: float = 150.0
## Portée de raccord entre échelles empilées : distance (px) au-dessus de la
## sonde torse où l'on cherche l'échelle suivante une fois la butée atteinte
@export var ECHELLE_CHAIN_REACH: float = 300.0
## Distance (px) sondée sous les pieds pour le raccord descendant entre
## deux échelles empilées
@export var ECHELLE_BELOW_REACH: float = 120.0
var _current_echelle: Area2D = null
var _echelle_top_exit := false  # signal pour jump_enter : hissage de sommet
var _echelle_regrab_lock := false  # posé en quittant l'échelle, levé au relâché haut/bas


## Bord haut (y global) de la zone d'une échelle, lu depuis son CollisionShape2D
func _echelle_zone_top(ladder: Area2D) -> float:
	for child in ladder.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			return child.global_position.y - child.shape.size.y * 0.5 * absf(child.global_scale.y)
	return ladder.global_position.y


## Bord bas (y global) de la zone d'une échelle
func _echelle_zone_bottom(ladder: Area2D) -> float:
	for child in ladder.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			return child.global_position.y + child.shape.size.y * 0.5 * absf(child.global_scale.y)
	return ladder.global_position.y


## Cherche une zone du groupe "ECHELLE" en un point donné.
## En cas de chevauchement, privilégie l'échelle qui monte le plus haut.
func _find_echelle_at(point: Vector2) -> Area2D:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = point
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var best: Area2D = null
	for hit in get_world_2d().direct_space_state.intersect_point(params, 8):
		var col = hit.get("collider")
		if col is Area2D and col.is_in_group("ECHELLE"):
			if best == null or _echelle_zone_top(col) < _echelle_zone_top(best):
				best = col
	return best


## Cherche une zone du groupe "ECHELLE" au niveau du torse du perso
func _find_echelle() -> Area2D:
	return _find_echelle_at(global_position + Vector2(0.0, -60.0))


## Tente d'accrocher une échelle (haut/bas maintenu dans les états qui le permettent)
func _try_echelle() -> bool:
	if _echelle_regrab_lock:
		return false
	var ladder := _find_echelle()
	if ladder == null:
		return false
	_current_echelle = ladder
	change_state(States.ECHELLE)
	return true


func echelle_enter() -> void:
	velocity = Vector2.ZERO
	_recharge_air_moves()
	# sur l'échelle, les plateformes traversables (one-way) ne bloquent plus :
	# indispensable pour descendre depuis un rebord ou croiser une plateforme
	set_collision_mask_value(ONEWAY_LAYER, false)
	# aimante le perso sur l'axe central de l'échelle
	if _current_echelle != null:
		global_position.x = _current_echelle.global_position.x
		var top := _echelle_zone_top(_current_echelle)
		print("[ECH] enter  perso_y=", snappedf(global_position.y, 0.1),
			" haut_zone=", snappedf(top, 0.1),
			" ecart(perso-haut)=", snappedf(global_position.y - top, 0.1),
			" au_sol=", is_on_floor())
		# accroché au-dessus de la butée (depuis un rebord) : on tombe en anim
		# de chute jusqu'à l'échelle, sinon pose de grimpe directe
		if global_position.y < top + ECHELLE_TOP_OFFSET - 4.0:
			animator.play("chute")
			return
	animator.play("climbidle")


func echelle_execute(_delta: float) -> void:
	# ancre légitime : pas de chute accumulée tant qu'on est sur l'échelle
	FALL_POINT = global_position.y

	# uniquement monter / descendre — aucun déplacement horizontal
	var dir := Input.get_axis("up_move", "down_move")
	var vy_prec := velocity.y  # conservé pour la vraie gravité pendant la glisse
	velocity.x = 0.0
	velocity.y = dir * ECHELLE_SPEED

	# échelles empilées : la sonde passe d'une échelle à l'autre en grimpant.
	# On ne monte jamais en grade vers le bas ici (sinon ping-pong avec le
	# raccord) : la descente vers une échelle plus basse passe uniquement
	# par le raccord descendant explicite plus bas.
	var ladder := _find_echelle()
	if ladder != null and (_current_echelle == null
		or _echelle_zone_top(ladder) <= _echelle_zone_top(_current_echelle)):
		_current_echelle = ladder

	# BUTÉE HAUTE géométrique : quoi que dise la sonde, l'origine du perso ne
	# reste jamais au-dessus du sommet de la zone + ECHELLE_TOP_OFFSET.
	# `au_dessus_butee` = accroché depuis un rebord ou re-grab trop haut :
	# au lieu de téléporter, on GLISSE vers la butée à vitesse d'échelle.
	var au_dessus_butee := false
	if _current_echelle != null:
		var limite := _echelle_zone_top(_current_echelle) + ECHELLE_TOP_OFFSET
		au_dessus_butee = global_position.y < limite - 4.0
		if global_position.y <= limite:
			if dir < 0.0:
				# une échelle continue-t-elle au-dessus ? raccord sans saut
				var next := _find_echelle_at(global_position
					+ Vector2(0.0, -60.0 - ECHELLE_CHAIN_REACH))
				if next != null and _echelle_zone_top(next) < _echelle_zone_top(_current_echelle):
					print("[ECH] raccord vers l'échelle du dessus")
					_current_echelle = next
					global_position.x = next.global_position.x  # ré-aimante en x
				else:
					# butée atteinte en montant, rien au-dessus : hissage
					print("[ECH] sortie HAUT (butée)  perso_y=", snappedf(global_position.y, 0.1))
					_echelle_top_exit = true
					goto_state(States.JUMP)
					return
			elif ladder != null:
				# (si ladder == null on est en transit de raccord descendant :
				#  on garde la vitesse d'échelle, ni glisse ni téléport)
				if au_dessus_butee:
					# chute libre (vraie gravité) jusqu'à la butée
					velocity.y = maxf(vy_prec, 0.0) + gravity * _delta
				else:
					global_position.y = limite
					velocity.y = maxf(velocity.y, 0.0)

	# animations : "chute" seulement en glisse d'accroche haute, jamais
	# pendant un transit de raccord (ladder == null)
	if au_dessus_butee and ladder != null:
		if animator.animation != "chute":
			animator.play("chute")
	elif dir < 0.0:
		if animator.animation != "climb_move_up":
			animator.play("climb_move_up")
	elif dir > 0.0:
		if animator.animation != "climb_move_down":
			animator.play("climb_move_down")
	else:
		if animator.animation != "climbidle":
			animator.play("climbidle")

	# plus d'échelle sous la main (au torse) → sortie selon la situation
	if ladder == null:
		# en glisse depuis un rebord vers la butée : on ne sort pas encore
		if au_dessus_butee:
			return
		# transit entre deux échelles raccordées : la sonde est encore sous la
		# zone de l'échelle adoptée au-dessus → on continue de grimper
		if dir < 0.0 and _current_echelle != null \
			and global_position.y - 60.0 > _echelle_zone_bottom(_current_echelle):
			return
		# raccord DESCENDANT échelle→échelle : une échelle continue en
		# dessous → on descend vers elle sans lâcher prise
		if dir > 0.0:
			var next_bas := _find_echelle_at(global_position + Vector2(0.0, ECHELLE_BELOW_REACH))
			if next_bas != null:
				if next_bas != _current_echelle:
					print("[ECH] raccord vers l'échelle du dessous")
					_current_echelle = next_bas
					global_position.x = next_bas.global_position.x  # ré-aimante en x
				return
		if dir < 0.0:
			# raccord MONTANT : même si la sonde a décroché, une échelle
			# continue peut-être au-dessus → on l'adopte au lieu de sauter
			var next_haut := _find_echelle_at(global_position
				+ Vector2(0.0, -60.0 - ECHELLE_CHAIN_REACH))
			if next_haut != null and (_current_echelle == null
				or _echelle_zone_top(next_haut) < _echelle_zone_top(_current_echelle)):
				print("[ECH] raccord vers l'échelle du dessus (sonde)")
				_current_echelle = next_haut
				global_position.x = next_haut.global_position.x  # ré-aimante en x
				return
			# sortie par le HAUT en montant : saut automatique pour se hisser
			print("[ECH] sortie HAUT (sonde)  perso_y=", snappedf(global_position.y, 0.1))
			_echelle_top_exit = true
			goto_state(States.JUMP)
		elif is_on_floor():
			print("[ECH] sortie SOL  perso_y=", snappedf(global_position.y, 0.1))
			goto_state(States.IDLE)
		else:
			print("[ECH] sortie CHUTE  perso_y=", snappedf(global_position.y, 0.1))
			goto_state(States.CHUTE)
		return

	# pieds au sol en descendant → arrivé en bas
	# (pas pendant la glisse depuis un rebord : is_on_floor y est encore
	# "vrai" au premier frame et éjectait l'état aussitôt)
	if is_on_floor() and dir > 0.0 and not au_dessus_butee:
		goto_state(States.IDLE)


func echelle_input(_event: InputEvent) -> void:
	# sauter depuis n'importe quel point de l'échelle
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	# esquive (rond) : lâcher prise et se laisser tomber
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)


func echelle_exit() -> void:
	_current_echelle = null
	velocity = Vector2.ZERO
	set_collision_mask_value(ONEWAY_LAYER, true)
	# pas de re-accroche tant que haut/bas n'est pas relâché (accroche maintenue)
	_echelle_regrab_lock = true
#endregion



var _roll_forced := false  # roulade relancée faute de place pour se relever

func roll_enter() -> void:
	_roll_forced = false
	var dir := Input.get_axis("left_move", "right_move")

	if dir != 0.0:
		dir = sign(dir)
		last_direction = dir
		point.scale.x  = dir
		velocity.x     = dir * ROLL_SPEED
		animator.play("roll")
		# Hitbox compacte pendant la roulade (la normale est restaurée par roll_exit)
		collision_normale.set_deferred("disabled", true)
		collision_roulade.set_deferred("disabled", false)
	else:
		# Pas de direction → on ne roll pas, retour IDLE
		call_deferred("change_state", States.IDLE)

func roll_execute(delta: float) -> void:
	velocity.y += gravity * delta
	# Réaffirme la vitesse à chaque frame : move_and_slide l'annule sur une
	# collision frontale (ex. obstacle à hauteur de tête percuté à la frame 1,
	# quand l'ancienne hitbox est encore active) — sans ça, roulade sur place.
	# Les roulades forcées (sous un plafond bas) avancent 2× moins vite.
	velocity.x = last_direction * ROLL_SPEED * (0.5 if _roll_forced else 1.0)

## Y a-t-il la place de se relever ici ? Teste la capsule debout contre les
## murs solides (layer 1 uniquement : les one-way ne bloquent pas le relevé)
func _can_stand_up() -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision_normale.shape
	var xf := collision_normale.global_transform
	xf.origin.y -= 4.0  # léger décalage vers le haut pour ignorer le contact au sol
	params.transform = xf
	params.collision_mask = 1
	params.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()


func roll_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump") and _can_stand_up():
		change_state(States.JUMP)

func roll_exit() -> void:
	collision_normale.set_deferred("disabled", false)
	collision_roulade.set_deferred("disabled", true)

# =====================  DASH AÉRIEN  ===========================
#region DASH
## Version aérienne de l'esquive (même touche) : mêmes vitesse et distance
## que la roulade (700 px/s pendant 0.727 s ≈ 509 px), horizontal pur.
## Un seul dash par phase aérienne, rechargé au sol / mur / grab.

## Capacité metroidvania : désactivable tant qu'elle n'est pas débloquée
@export var air_dash_enabled := true
## Vitesse du dash (2× la roulade — la distance reste identique grâce à
## la durée divisée par deux : ~509 px au total)
@export var DASH_SPEED: float = 1400.0
@export var DASH_DURATION: float = 0.3636
var _air_dash_used := false
var _dash_timer := 0.0


## Tente le dash aérien (touche esquive en l'air, depuis JUMP ou CHUTE)
func _try_air_dash() -> bool:
	if not air_dash_enabled or _air_dash_used or is_on_floor():
		return false
	_air_dash_used = true
	change_state(States.DASH)
	return true


func dash_enter() -> void:
	# direction : l'input s'il est tenu, sinon le regard
	var dir := Input.get_axis("left_move", "right_move")
	if dir != 0.0:
		last_direction = sign(dir)
		point.scale.x = last_direction
	_dash_timer = 0.0
	velocity = Vector2(last_direction * DASH_SPEED, 0.0)
	# TODO : jouer l'anim de dash dédiée quand elle existera
	# (volontairement aucune anim pour l'instant — l'anim en cours continue)


func dash_execute(delta: float) -> void:
	_dash_timer += delta
	# trajectoire figée : horizontal pur, la gravité est suspendue
	velocity.x = last_direction * DASH_SPEED
	velocity.y = 0.0

	if is_on_floor():
		_handle_landing()
		return
	if _dash_timer >= DASH_DURATION:
		goto_state(States.CHUTE)


func dash_exit() -> void:
	velocity.x = 0.0
#endregion


func roll_animation_finished() -> void:
	# Pas la place de se relever (fin de roulade sous un passage bas) :
	# on repart pour une roulade, en laissant le joueur choisir la direction
	# (maintenir la direction opposée permet de faire demi-tour)
	if not _can_stand_up():
		_roll_forced = true  # les relances avancent à demi-vitesse
		var dir := Input.get_axis("left_move", "right_move")
		if dir != 0.0:
			last_direction = sign(dir)
			point.scale.x = last_direction
		animator.play("roll")
		return

	var horiz := Input.get_action_strength("right_move") - Input.get_action_strength("left_move")

	if horiz != 0.0:
		goto_state(States.RUN)
	elif Input.is_action_pressed("jump"):
		goto_state(States.JUMP)
	elif not is_on_floor():
		goto_state(States.CHUTE)
	else:
		goto_state(States.IDLE)



func chute_griffe_enter() -> void:
	_recharge_air_moves()
	animator.play("chute_griffe")
	velocity.y = 250.0

func chute_griffe_execute(delta: float) -> void:
	FALL_POINT = global_position.y  # descente contrôlée : pas de chute accumulée
	const GLIDE_Y   := 250.0
	const GLIDE_X   := 150.0
	const DECELRATE := 0.50

	var dir := Input.get_axis("left_move", "right_move")
	if dir != 0:
		velocity.x = dir * GLIDE_X
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELRATE * delta)

	velocity.y = GLIDE_Y

	# is_action_pressed (pas just_pressed) → OK dans execute
	var still_holding := _raycast_hits_group(climbcast_up, "CHUTE") \
		and Input.is_action_pressed("griffe")

	if not still_holding:
		change_state(States.CHUTE)

func chute_griffe_input(event: InputEvent) -> void:
	pass

func chute_griffe_exit() -> void:
	pass



#region GRAB
const GRAB_LERP_SPEED := 600.0   # vitesse d'approche en pixels/sec
var _grab_locked := false          # true quand le perso a atteint le point

func grab_enter() -> void:
	velocity = Vector2.ZERO
	_grab_locked = false
	_recharge_air_moves()
	animator.play("chute")  # on garde l'anim de chute pendant l'approche

func grab_execute(delta: float) -> void:
	FALL_POINT = global_position.y  # appui légitime : accroché à un point
	if not current_grab_area:
		change_state(States.CHUTE)
		return

	var grab_pos = current_grab_area.global_position
	var offset = ancre_grab.global_position - global_position
	var target_pos = grab_pos - offset

	if not _grab_locked:
		# Phase d'approche — le perso glisse vers le point
		global_position = global_position.move_toward(target_pos, GRAB_LERP_SPEED * delta)
		if global_position.distance_to(target_pos) < 2.0:
			global_position = target_pos
			_grab_locked = true
			animator.play("suspendu")  # anim seulement quand on est accroché
	else:
		# Phase accrochée — on reste collé
		global_position = target_pos

func grab_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)

func grab_exit() -> void:
	_grab_locked = false
	current_grab_area = null
	_grab_cooldown_timer = GRAB_COOLDOWN
#endregion


# =====================  ATTAQUES  ===========================
# AMÉLIORATION: combo_buffered remplace le bool "combo"
# Chaque état d'attaque l'utilise de la même façon :
# - enter: reset combo_buffered = false
# - input: si le joueur appuie pendant l'anim principale → combo_buffered = true
# - animation_finished: si combo_buffered → chaîne, sinon → recovery (anim _r)

## Déplacement type RUN pendant les attaques : contrôle au stick, même vitesse
## et même inertie que run_execute. Pas de flip — le perso garde la direction
## de son attaque (il peut donc reculer en marche arrière pendant le coup).
func _attack_run_movement(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)
		return
	var direction := Input.get_axis("left_move", "right_move")
	var target_speed := float(direction) * GROUND_SPEED_ATTACK
	velocity.x = lerp(velocity.x, target_speed, 0.15)


## Le perso est-il en mouvement pendant une attaque ? (direction maintenue)
## Détermine si le combo peut sauter l'animation de retour (recovery) :
## en mouvement → enchaînement direct ; immobile → recovery obligatoire.
func _attack_is_moving() -> bool:
	return Input.get_axis("left_move", "right_move") != 0.0


func attack_light_1_enter() -> void:
	slash_attack.position = Vector2(98, -88)
	_flip_from_input()
	combo_buffered = false
	animator.play("attack")

func attack_light_1_execute(delta: float) -> void:
	_attack_run_movement(delta)

func attack_light_1_input(event: InputEvent) -> void:
	# Buffer pendant l'anim principale
	if event.is_action("light_attack") \
		and event.is_pressed() \
		and not event.is_echo() \
		and animator.animation == "attack":
		combo_buffered = true
	# Pendant la recovery
	if animator.animation == "attack_r":
		if Input.is_action_just_pressed("light_attack"):
			if _attack_is_moving():
				change_state(States.ATTACK_LIGHT_2)  # en mouvement : cancel direct
			else:
				combo_buffered = true  # immobile : partira à la fin de la recovery
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)

func attack_light_1_animation_finished() -> void:
	match animator.animation:
		"attack":
			# Skip de la recovery uniquement si le perso est en mouvement
			if combo_buffered and _attack_is_moving():
				change_state(States.ATTACK_LIGHT_2)
				return
			# Immobile : recovery obligatoire (le combo bufferisé reste en attente)
			animator.play("attack_r")
		"attack_r":
			if combo_buffered:
				change_state(States.ATTACK_LIGHT_2)
				return
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)

func attack_light_1_exit() -> void:
	combo_buffered = false




func attack_light_2_enter() -> void:
	_flip_from_input()
	combo_buffered = false
	animator.play("attack_02")


func attack_light_2_execute(delta: float) -> void:
	_attack_run_movement(delta)

func attack_light_2_input(event: InputEvent) -> void:
	if event.is_action("light_attack") \
		and event.is_pressed() \
		and not event.is_echo() \
		and animator.animation == "attack_02":
		combo_buffered = true
	if animator.animation == "attack_02_r":
		if Input.is_action_just_pressed("light_attack"):
			if _attack_is_moving():
				change_state(States.ATTACK_LIGHT_1)  # en mouvement : cancel direct
			else:
				combo_buffered = true  # immobile : partira à la fin de la recovery
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)

func attack_light_2_animation_finished() -> void:
	match animator.animation:
		"attack_02":
			# Skip de la recovery uniquement si le perso est en mouvement
			if combo_buffered and _attack_is_moving():
				change_state(States.ATTACK_LIGHT_1)
				return
			# Immobile : recovery obligatoire (le combo bufferisé reste en attente)
			animator.play("attack_02_r")
		"attack_02_r":
			if combo_buffered:
				change_state(States.ATTACK_LIGHT_1)
				return
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)

func attack_light_2_exit() -> void:
	combo_buffered = false




func attack_light_3_enter() -> void:
	_flip_from_input()
	combo_buffered = false
	animator.play("attack_03")

func attack_light_3_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)

func attack_light_3_input(event: InputEvent) -> void:
	if animator.animation == "attack_03_r":
		if Input.is_action_just_pressed("light_attack"):
			change_state(States.ATTACK_LIGHT_1)
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)

func attack_light_3_animation_finished() -> void:
	match animator.animation:
		"attack_03":
			animator.play("attack_03_r")
		"attack_03_r":
			if Input.is_action_just_pressed("light_attack"):
				change_state(States.ATTACK_LIGHT_1)
			elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)
				return

func attack_light_3_exit() -> void:
	combo_buffered = false



func attack_lourde_enter() -> void:
	slash_attack.position = Vector2(-32, -92)
	animator.play("attack_lourde")

func attack_lourde_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)

func attack_lourde_input(event: InputEvent) -> void:
	pass

func attack_lourde_animation_finished() -> void:
	match animator.animation:
		"attack_lourde":
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
			else:
				change_state(States.IDLE)

func attack_lourde_exit() -> void:
	pass



func attack_air_enter() -> void:
	animator.play("attack_air")
	if velocity.y < 0.0:
		velocity.y = 0.0  # stoppe la montée, la gravité prend le relais

func attack_air_execute(delta: float) -> void:
	velocity.y += gravity * delta

	if is_on_floor():
		_handle_landing()

func attack_air_input(event: InputEvent) -> void:
	pass

func attack_air_animation_finished() -> void:
	match animator.animation:
		"attack_air":
			change_state(States.CHUTE)

func attack_air_exit() -> void:
	pass



## Coût du soin, en SANG (la jauge remplie par les récoltes)
@export var HEAL_COST: int = 100
## Cœurs rendus par un soin complet
@export var HEAL_AMOUNT: int = 2

## Tente de lancer le soin : refuse si pas assez de sang ou déjà plein PV.
## Le coût n'est débité qu'à la FIN de l'animation (soin interrompu = gratuit)
func _try_heal() -> void:
	if Player.hp >= Player.MAX_HP:
		return
	if Player.sang < HEAL_COST:
		_notify_insufficient("sang")
		return
	change_state(States.HEAL)


func heal_enter() -> void:
	animator.play("heal")

func heal_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)

func heal_input(event: InputEvent) -> void:
	pass

func heal_animation_finished() -> void:
	match animator.animation:
		"heal":
			Player.changement_de_sang(-HEAL_COST)
			Player.changement_de_vie(HEAL_AMOUNT)
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
			else:
				change_state(States.IDLE)

func heal_exit() -> void:
	velocity.x = 0


# =====================  BLOODBALL (sort de boule de sang)  ==================
#region BLOODBALL

const BLOODBALL_SCENE := preload("res://SCRIPT/SPELL/bloodball.tscn")
## Durée du lancer avant de rendre la main (en attendant une anim de cast dédiée)
@export var BLOODBALL_CAST_TIME: float = 0.25
## Coût en sang d'une boule
@export var BLOODBALL_COST: int = 55
var _cast_timer := 0.0


## Tente de lancer le sort : vérifie la jauge de sang ; si insuffisante,
## déclenche le feedback UI (jauge qui tremble + clignote rouge) sans caster
func _try_cast_bloodball() -> void:
	if Player.sang < BLOODBALL_COST:
		_notify_insufficient("sang")
		return
	change_state(States.BLOODBALL)


## Feedback universel de coût refusé : fait trembler/clignoter l'UI de la
## ressource concernée ("sang" = jauge, "blood" = compteur)
func _notify_insufficient(kind: String) -> void:
	var huds := get_tree().get_nodes_in_group("UI_Sang")
	if not huds.is_empty() and huds[0].has_method("insufficient_feedback"):
		huds[0].insufficient_feedback(kind)

func bloodball_enter() -> void:
	print("[SPELL] cast ! spawn de la boule au marker ", spellcast.global_position)
	Player.changement_de_sang(-BLOODBALL_COST)  # le sort boit son sang
	# TODO : remplacer par une vraie animation de cast quand elle existera
	animator.play("idle")
	# Au sol : le perso se plante pour lancer. En l'air : comme l'attaque
	# aérienne, le cast ne touche pas à l'élan du saut
	if is_on_floor():
		velocity.x = 0.0
	_cast_timer = 0.0

	var ball := BLOODBALL_SCENE.instantiate()
	ball.dir = int(signf(point.scale.x))
	get_tree().current_scene.add_child(ball)
	ball.global_position = spellcast.global_position

func bloodball_execute(delta: float) -> void:
	velocity.y += gravity * delta
	_cast_timer += delta
	if _cast_timer >= BLOODBALL_CAST_TIME:
		if not is_on_floor():
			goto_state(States.CHUTE)
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			goto_state(States.RUN)
		else:
			goto_state(States.IDLE)

func bloodball_exit() -> void:
	pass
#endregion



# -------------------------------------------------
# HIT
# -------------------------------------------------




@export var HIT_STUN_TIME: float = 0.25
@export var HIT_KNOCK_X:  float = 1300.0
@export var HIT_KNOCK_Y:  float = -180.0
@export var HIT_X_DAMP:   float = 8.0

var _hit_elapsed := 0.0

func hit_enter() -> void:
	# Le déplacement est géré par le knockback superposé (_knock) ;
	# l'état HIT ne s'occupe que du stun et de l'animation
	velocity = Vector2.ZERO
	animator.play("hit")
	_hit_elapsed = 0.0


func hit_execute(delta: float) -> void:
	_hit_elapsed += delta
	velocity.y += gravity * delta

	if _hit_elapsed >= HIT_STUN_TIME:
		if is_on_floor():
			goto_state(States.IDLE)
		else:
			goto_state(States.CHUTE)

func hit_exit() -> void:
	velocity = Vector2.ZERO
	_knock = Vector2.ZERO  # fin du stun = contrôle rendu, aucune poussée résiduelle


# -------------------------------------------------
# DEAD — FIX: ajout de la gravité + blocage propre
# -------------------------------------------------
func dead_enter() -> void:
	animator.play("death")
	velocity.x = 0.0            # FIX: stoppe le mouvement horizontal



func dead_execute(delta: float) -> void:
	# FIX: gravité active pour que le corps tombe au sol
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
	# Le joueur est mort — aucun mouvement horizontal
	velocity.x = 0.0
	# TODO: ici tu pourras ajouter un timer pour afficher un écran de game over
	# ou relancer au checkpoint après X secondes / appui sur un bouton


func dead_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		print("okkkkkkkje suis mort")
		Player.hp = Player.MAX_HP
		Player.sang = Player.MAX_SANG
		Loader.load_scene_with_loading(Loader._target_scene_path)

func dead_exit() -> void:
	velocity = Vector2.ZERO

# =====================  DROP (passer à travers one-way)  ===========================
#region DROP
const ONEWAY_LAYER := 2
const DROP_THROUGH_TIME := 0.25
var _drop_timer := 0.0

func drop_enter() -> void:
	_drop_timer = DROP_THROUGH_TIME
	set_collision_mask_value(ONEWAY_LAYER, false)
	animator.play("chute")
	velocity.y = 50.0

func drop_execute(delta: float) -> void:
	_drop_timer -= delta
	velocity.y += gravity * delta

	var direction := Input.get_axis("left_move", "right_move")
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
		_flip_from_input()
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	if _drop_timer <= 0.0:
		change_state(States.CHUTE)
		return

	if is_on_floor():
		_handle_landing()

func drop_exit() -> void:
	set_collision_mask_value(ONEWAY_LAYER, true)
#endregion
