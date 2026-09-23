extends CharacterBody2D


enum States { IDLE, RUN, CHUTE, JUMP, WALL_GRIFFE, WALL_JUMP, CLIMB, ROLL, CHUTE_GRIFFE, GRAB, ATTACK_LIGHT_1, ATTACK_LIGHT_2, ATTACK_LIGHT_3, ATTACK_AIR, ATTACK_LOURDE, DEAD, HIT, HEAL, DROP, BLOODBALL, ECHELLE, DASH, CORDE, GRAPPIN }



# CAMP (23 sept. 2026) : même système que les monstres (`faction` de BASE_IA).
# Un monstre du même camp ne nous attaque pas. 1 par défaut, les monstres à 0.
@export_range(0, 10) var faction: int = 1

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

const GROUND_SPEED = 700            # FIX: renommé pour clarté
## Vitesse horizontale en l'air (sept. 2026 : 400 → 480, garde la portée du
## saut ≈ 440 px malgré le vol raccourci — et rend l'air moins pataud)
@export var AIR_SPEED: float = 610.0
@export var GROUND_SPEED_ATTACK: float = 550.0  # vitesse de course pendant les attaques
## Nombre de cœurs de vie max — synchronisé vers le singleton Player au spawn
@export var MAX_HEARTS: int = 5
var last_direction := 1  # 1 = droite, -1 = gauche

## vitesse de déplacement en escalade (surfaces CLIMB)
@export var CLIMB_SPEED: float = 200.0
const ROLL_SPEED := 760.0

const COYOTE_TIME := 0.08
## Coyote élargi pour les chutes SUBIES depuis une accroche (griffe qui
## expire, échelle, grab…) : la chute n'étant pas choisie, la pression de
## saut du joueur arrive naturellement plus tard
@export var GRIP_COYOTE_TIME: float = 0.3
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
	# lit ces valeurs pour construire sa rangée de cœurs.
	# L'export n'est que la valeur de DÉPART : au premier spawn seulement —
	# ensuite l'autoload fait foi, les cœurs ramassés survivent au respawn
	if not Player.hearts_initialized:
		Player.hearts_initialized = true
		Player.max_hearts = MAX_HEARTS
		Player.MAX_HP = MAX_HEARTS
		# début de partie : la jauge de sang offre exactement un soin,
		# comme au respawn
		Player.bloodheal = HEAL_COST
	Player.hp = mini(Player.hp, Player.MAX_HP)


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
	# Knockback absolu — même principe que les monstres (BASE_IA) : tant qu'il
	# est actif, il remplace le déplacement horizontal, via velocity pour que
	# move_and_slide glisse le long du sol
	if _knock != Vector2.ZERO:
		velocity.x = _knock.x
	move_and_slide()
	# le câble du grappin se trace APRÈS le déplacement (sinon il part de la
	# main du pas précédent et dépasse du bras, voir _grappin_tracer_cable)
	if current_state == States.GRAPPIN:
		_grappin_tracer_cable()
	_decay_knockback(delta)
	_corde_cooldown = maxf(_corde_cooldown - delta, 0.0)
	_grappin_cooldown = maxf(_grappin_cooldown - delta, 0.0)
	_grappin_scanner()


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
	# GRAPPIN : touche dédiée, valable dans les états listés (sol et air)
	if event.is_action_pressed("grapin") and _try_grappin():
		return
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

## `perce_stun` : réservé aux sources qui ne frappent QU'UNE FOIS (le souffle
## d'un kamikaze). Les sources continues — contact d'un monstre, piques, jet de
## flammes — sont relues à chaque frame et ont besoin du stun pour ne pas vider
## la barre en une seconde ; un souffle, lui, ne part qu'un coup par bombe, et
## sans ça quatre kamikazes qui explosent ensemble ne coûtent qu'un seul cœur
## (vécu le 18 sept. 2026). La roulade et le dash restent des parades absolues.
func apply_damage(amount: int, source_x, source_tag := "?", perce_stun := false) -> void:
	if current_state in [States.ROLL, States.DASH, States.DEAD]:
		return
	if current_state == States.HIT and not perce_stun:
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


## Renvoi des dégâts d'environnement (piques, scie). Le danger fournit une
## DIRECTION de repoussée et chaque axe a sa force (sept. 2026 : avant, le renvoi
## était toujours vers le haut : une pique de plafond nous renvoyait DANS elle).
@export var ENV_KNOCK_Y: float = -1100.0           ## vers le HAUT (piques au sol), inchangé
@export var ENV_KNOCK_BAS: float = 500.0           ## vers le BAS (piques de plafond) : on décroche, la gravité fait le reste
@export var ENV_KNOCK_X: float = 1300.0            ## sur le CÔTÉ (piques murales, flanc d'une scie), comme un coup de monstre
@export var ENV_KNOCK_SOULEVEMENT: float = 450.0   ## petit saut ajouté à une poussée latérale, pour décoller du sol


## centre du corps (milieu de la hitbox debout), pour les dangers à repoussée
## radiale (scie) : les pieds sont trop bas pour donner une bonne direction
func centre_corps() -> Vector2:
	return collision_normale.global_position


## Dégâts d'environnement (piques & co) : perte de cœur(s), renvoi fort dans la
## `direction` fournie par le danger (le sens où pointent les piques, ou du
## centre de la scie vers nous), et recharge du double saut + dash pour pouvoir
## se rattraper. Roulade et dash rendent invulnérable, comme contre les
## ennemis. Sans direction : vers le haut, comme avant.
## Retourne true si le coup a PORTÉ (false : mort, déjà sonné, en roulade ou en dash)
## — les pièges qui ne doivent toucher qu'une fois par sortie s'en servent.
func apply_environment_damage(amount: int, direction: Vector2 = Vector2.UP) -> bool:
	if current_state in [States.DEAD, States.HIT, States.ROLL, States.DASH]:
		return false
	print("[DMG] f=", Engine.get_physics_frames(),
		" src=environnement amount=", amount,
		" état=", States.keys()[current_state],
		" hp ", Player.hp, " -> ", Player.hp - amount)
	Player.changement_de_vie(-amount)
	if Player.hp <= 0:
		_knock = Vector2.ZERO
		change_state(States.DEAD)
		return true
	var d := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.UP
	# latéral : poussée absolue amortie, le même mécanisme que les coups de monstres
	_knock = Vector2(d.x * ENV_KNOCK_X, 0.0)
	change_state(States.HIT)
	# vertical : impulsion one-shot, APRÈS hit_enter (qui remet velocity à zéro)
	# haut, bas et soulèvement se raccordent SANS seuil : une pique murale donne
	# d.y = ±0,00000004 (flottants) et un joueur qui tombe est vite quelques
	# pixels sous le centre d'une scie ; un test « d.y <= 0 » sautait dans ces cas
	var haut := maxf(-d.y, 0.0) * absf(ENV_KNOCK_Y)
	var bas := maxf(d.y, 0.0) * ENV_KNOCK_BAS
	# poussée latérale : petit soulèvement pour décoller du sol, qui s'efface à
	# mesure que le danger pousse vers le bas
	var soulevement := ENV_KNOCK_SOULEVEMENT * absf(d.x) * (1.0 - maxf(d.y, 0.0))
	velocity.y = bas - maxf(haut, soulevement)
	_recharge_air_moves()
	return true


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
	# wall jump universel (pour le moment) : tout mur StaticBody2D est valide
	return col is StaticBody2D


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



## Dégâts de chute activables/désactivables depuis l'inspecteur
## (désactivés pour le moment — la logique reste calculée et loguée)
@export var FALL_DAMAGE_ENABLED := false

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
	elif (Input.is_action_just_pressed("up_move") or Input.is_action_just_pressed("down_move")) \
		and _try_echelle():
		return
	elif Input.is_action_just_pressed("down_move") and is_on_floor() \
		and _standing_on_oneway():
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
	elif (Input.is_action_just_pressed("up_move") or Input.is_action_just_pressed("down_move")) \
		and _try_echelle():
		return
	elif Input.is_action_just_pressed("down_move") and is_on_floor() \
		and _standing_on_oneway():
		change_state(States.DROP)
		return

func run_exit() -> void:
	pass


#region JUMP

## Impulsion de saut (négatif = vers le haut). Plus la valeur est grande
## en absolu, plus le saut monte haut.
## Réglage "nerveux" (sept. 2026, retour playtest "sauts et chutes mollassons",
## validé par Kaoru contre un réglage intermédiaire) : montée 0,35 s et chute
## 0,38 s au lieu de 0,47 / 0,63, HAUTEURS INCHANGÉES (saut ≈ 232 px, petit
## saut ≈ 80 px, comme l'ancien −750 forcé par la scène) et portée conservée
## (≈ 445 px).
@export var JUMP_VELOCITY: float = -1062.0   # −15 % (16 sept.) avec la gravité −15 % : mêmes durées, hauteur ≈ 257 px
const MIN_JUMP_TIME   := 0.01
const MAX_JUMP_HOLD   := 0.25
## multiplicateurs de la gravité projet (2500 depuis le 16 sept. 2026 : gravité
## UNIFIÉE, la chute du joueur = la gravité de tout le monde)
@export var GRAVITY_RISE: float = 0.6       # bouton maintenu → monte haut (gravité projet 2500 : 1 = chute normale)
@export var GRAVITY_CUTOFF: float = 2.5     # relâché tôt → coupe net
@export var GRAVITY_FALL: float = 1.0       # chute, attaque aérienne, drop = la gravité du projet telle quelle
@export var MAX_FALL_SPEED: float = 1360.0  # vitesse de chute plafond (px/s) (1600 × 0,85)
## Gravité de montée des LANCERS (grappin, corde, sortie d'escalade) : c'est
## l'ancienne coupure, gardée pour ne pas changer les hauteurs déjà réglées
@export var GRAVITY_LANCEMENT: float = 1.37  # = l'ancien 3,5 × 980 ramené à 2500 : hauteurs de lancer inchangées
var _saut_lance := false   # saut issu d'un lancer → GRAVITY_LANCEMENT à la montée

const AIR_CONTROL = 0.2
const DECELERATION_RATE = 0.95
var _jump_timer := 0.0
# vrai quand la phase aérienne a commencé SANS saut (marche dans le vide,
# lâcher d'accroche…) : le saut simple reste dû, sans limite de temps
var _walkoff_jump := false
var _climb_auto_exit := false
const CLIMB_EXIT_VELOCITY := -1000.0  # plus fort que JUMP_VELOCITY (-700)

# --- DOUBLE SAUT ---
## Capacité metroidvania : désactivable tant qu'elle n'est pas débloquée
@export var double_jump_enabled := true
## Impulsion du second saut (souvent un peu plus faible que le premier)
@export var DOUBLE_JUMP_VELOCITY: float = -944.0   # −15 % aussi (≈ 214 px)
var _double_jump_used := false
var _dj_pending := false  # signal pour jump_enter : c'est un double saut


## Tente le double saut (appelé depuis JUMP et CHUTE sur appui de saut en l'air)
func _try_double_jump() -> bool:
	if not double_jump_enabled or _double_jump_used or is_on_floor():
		print("[DJ] refusé  deja_utilise=", _double_jump_used,
			" au_sol=", is_on_floor(), " état=", States.keys()[current_state])
		return false
	# grâce anti-spam post-saut mural : pression ignorée, double saut intact
	if _wj_lock_timer > WALL_JUMP_LOCK_TIME - WALL_JUMP_DJ_GRACE:
		print("[WJ] pression saut ignorée (grâce anti-spam)")
		return false
	print("[DJ] double saut  depuis=", States.keys()[current_state])
	_double_jump_used = true
	if _wj_lock_timer > 0.0:
		print("[WJ] verrou coupé par DOUBLE SAUT")
	_wj_lock_timer = 0.0  # le double saut interrompt le verrou du saut mural
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
	_saut_lance = false
	_walkoff_jump = false  # tout saut solde le saut de chute libre
	# (FALL_POINT est géré en continu dans _physics_process : suivi au sol,
	# point le plus haut conservé en vol)

	if _climb_auto_exit:
		velocity.y = CLIMB_EXIT_VELOCITY
		velocity.x = 0.0
		_climb_auto_exit = false
		_jump_timer = MAX_JUMP_HOLD  # ← désactive le hold
		_saut_lance = true
	elif _grappin_pending:
		# catapulte du grappin : vitesse imposée, gravité normale, pas de hold
		_grappin_pending = false
		velocity = _grappin_velocite
		_jump_timer = MAX_JUMP_HOLD
		_saut_lance = true
	elif _corde_pending:
		# lâcher de corde : l'élan du balancier + une impulsion, gravité normale
		_corde_pending = false
		velocity = _corde_velocite_sortie
		_jump_timer = MAX_JUMP_HOLD
		_saut_lance = true
	elif _dj_pending:
		_dj_pending = false
		velocity.y = DOUBLE_JUMP_VELOCITY
	elif _wj_pending:
		# saut mural : impulsion verticale normale + diagonale imposée
		_wj_pending = false
		velocity.y = JUMP_VELOCITY
		_wj_lock_dir = last_direction
		_wj_lock_timer = WALL_JUMP_LOCK_TIME
		velocity.x = WALL_JUMP_PUSH_X * _wj_lock_dir
		print("[WJ] saut mural  dir_verrou=", _wj_lock_dir,
			" vx=", velocity.x, " verrou=", WALL_JUMP_LOCK_TIME, "s")
	else:
		velocity.y = JUMP_VELOCITY


func jump_execute(delta):
	_jump_timer += delta
	_grab_cooldown_timer = max(_grab_cooldown_timer - delta, 0.0)

	var direction = Input.get_axis("left_move", "right_move")
	if _wj_lock_timer > 0.0:
		# verrou du saut mural : diagonale imposée, stick ignoré.
		# Interruptible : toute action qui quitte JUMP (dash, coup, griffe,
		# échelle…) passe par jump_exit qui coupe le verrou, et le double
		# saut le coupe dans _try_double_jump.
		_wj_lock_timer = maxf(_wj_lock_timer - delta, 0.0)
		velocity.x = WALL_JUMP_PUSH_X * _wj_lock_dir
		if _wj_lock_timer == 0.0:
			print("[WJ] verrou expiré naturellement (", WALL_JUMP_LOCK_TIME, "s)")
	else:
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

		if _saut_lance:
			g_mul = GRAVITY_LANCEMENT   # lancer : montée comme avant le réglage nerveux
		elif force_min or (holding and within_hold):
			g_mul = GRAVITY_RISE
		else:
			g_mul = GRAVITY_CUTOFF
	else:
		g_mul = GRAVITY_FALL

	velocity.y = minf(velocity.y + gravity * g_mul * delta, MAX_FALL_SPEED)

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
	# _fresh_press et pas is_action_just_pressed : la pression qui vient de nous
	# faire ENTRER dans JUMP reste « juste pressée » toute la frame. Un 2e événement
	# dans cette frame (le stick tenu sur une échelle en envoie sans arrêt) repassait
	# ici et consommait le double saut aussitôt. Invisible depuis le sol (le double
	# saut y est refusé), mais pas depuis une échelle, une corde ou un saut de grâce.
	if _fresh_press("jump"):
		if _try_double_jump():
			return
	if _fresh_press("esquive") and _try_air_dash():
		return
	if (Input.is_action_just_pressed("up_move") or Input.is_action_just_pressed("down_move")) \
		and _try_echelle():
		return
	if Input.is_action_just_pressed("spell"):
		_try_cast_bloodball()
		return
	if Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_AIR)
		return

func jump_exit():
	# quitter JUMP (dash, coup, griffe, échelle, chute…) libère toujours
	# la trajectoire imposée du saut mural
	if _wj_lock_timer > 0.0:
		print("[WJ] verrou coupé par SORTIE de JUMP (reste ",
			snappedf(_wj_lock_timer, 0.01), "s)")
	_wj_lock_timer = 0.0
#endregion




#region CHUTE

# =====================  CHUTE  ===========================
var FALL_POINT: float = -1e9

func chute_enter() -> void:
	# coyote accordé en quittant le sol OU une surface d'accroche : sans ça,
	# tomber d'une griffe/échelle/mur faisait de la 1re pression un DOUBLE
	# saut ("la griffe ne recharge pas" — si, mais le saut normal sautait).
	# Les chutes SUBIES (griffe qui expire…) ont une fenêtre élargie :
	# le joueur n'a pas choisi de tomber, sa pression arrive plus tard.
	# ET dans tous ces cas : tomber sans avoir sauté ne coûte jamais le
	# saut simple — il reste disponible toute la chute (_walkoff_jump)
	if previous_state in [States.WALL_GRIFFE, States.CHUTE_GRIFFE,
		States.CLIMB, States.GRAB, States.ECHELLE, States.WALL_JUMP, States.CORDE]:
		_coyote_timer = GRIP_COYOTE_TIME
		_walkoff_jump = true
	elif previous_state in [States.RUN, States.IDLE]:
		_coyote_timer = COYOTE_TIME
		_walkoff_jump = true
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

	velocity.y = minf(velocity.y + gravity * GRAVITY_FALL * delta, MAX_FALL_SPEED)

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
		elif _walkoff_jump:
			# la chute a commencé sans saut : le saut simple est toujours dû
			change_state(States.JUMP)
			return
		elif _try_double_jump():
			return
		else:
			_jump_buffer_timer = JUMP_BUFFER_TIME

	if _fresh_press("esquive") and _try_air_dash():
		return

	if (Input.is_action_just_pressed("up_move") or Input.is_action_just_pressed("down_move")) \
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
	if _double_jump_used or _air_dash_used:
		print("[DJ] recharge par accroche  état=", States.keys()[current_state])
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
	velocity.x = 700.0 * last_direction   # 500 → 700 (Kaoru, sept. 2026) : c'est la "vitesse du wall run"

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
## vitesse de glisse le long du mur en état WALL_JUMP
@export var WALL_GLIDE_SPEED: float = 300.0

# --- Saut mural façon Hollow Knight : LÉGÈRE impulsion diagonale imposée,
# purement cosmétique (éviter de "baver" le long du mur en remontant) —
# on peut re-spammer le même mur juste après ---
## Poussée horizontale d'éloignement du mur pendant le verrou du saut mural
@export var WALL_JUMP_PUSH_X: float = 300.0
## Durée (s) du verrou : trajectoire diagonale incontrôlable au stick,
## mais interruptible par toute action aérienne (dash, coup, double saut…)
@export var WALL_JUMP_LOCK_TIME: float = 0.2
## Fenêtre (s) après un saut mural où une pression de saut est IGNORÉE (sans
## consommer le double saut) : évite que le spam du bouton transforme chaque
## saut mural en double saut vertical collé au mur
@export var WALL_JUMP_DJ_GRACE: float = 0.15


## De quel côté est le mur ? +1 droite, -1 gauche, 0 aucun.
## Rayons lancés au niveau du torse, en coordonnées MONDE — contrairement à
## une inversion aveugle du regard, le résultat est toujours fiable
func _wall_side() -> int:
	var space := get_world_2d().direct_space_state
	var origin := global_position + Vector2(0.0, -60.0)
	for side in [1, -1]:
		var q := PhysicsRayQueryParameters2D.create(
			origin, origin + Vector2(side * 45.0, 0.0), 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit and hit.collider is StaticBody2D:
			return side
	return 0
var _wj_pending := false     # signal pour jump_enter : saut depuis un mur
var _wj_lock_timer := 0.0
var _wj_lock_dir := 0.0

func wall_jump_enter():
	# regard DOS AU MUR déduit de la position réelle du mur — l'inversion
	# aveugle (_flip_facing_on_wall) se trompait quand on re-accrochait un
	# mur sans s'être retourné, et le saut opposé partait DANS le mur
	var side := _wall_side()
	if side != 0:
		last_direction = -side
		point.scale.x = last_direction
	else:
		_flip_facing_on_wall()  # secours si aucun rayon ne confirme le mur
	print("[WJ] accroche  mur_cote=", side, " regard=", last_direction,
		" depuis=", States.keys()[previous_state])
	velocity = Vector2.ZERO
	_recharge_air_moves()
	animator.play("wall_jump")

func wall_jump_execute(_delta: float) -> void:
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

func wall_jump_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		# saut mural = un VRAI saut via l'état JUMP normal, mais avec un
		# verrou diagonal façon Hollow Knight (voir jump_enter/_execute)
		var land_fx = instantiate_scene(WALL_JUMP_SCENE)
		land_fx.global_position = ANCRE_WALL.global_position
		land_fx.scale.x *= point.scale.x
		if land_fx is AnimatedSprite2D:
			land_fx.play()
		_wj_pending = true
		change_state(States.JUMP)
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)

func wall_jump_exit():
	velocity.x = 0.0  # annule la pression plaquée contre le mur
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
## Enfoncement immédiat (px) à l'accroche depuis une plateforme : sans lui,
## le perso reste en pose de grimpe flottant au-dessus de la planche
@export var ECHELLE_GRAB_SINK: float = 70.0
var _current_echelle: Area2D = null
var _echelle_enter_pframe := 0  # frame physique d'accroche (garde anti-éjection)


## Bord haut (y global) de la zone d'une échelle, lu depuis son CollisionShape2D
func _echelle_zone_top(ladder: Area2D) -> float:
	for child in ladder.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			return child.global_position.y - child.shape.size.y * 0.5 * absf(child.global_scale.y)
	return ladder.global_position.y


## Sortie haute d'échelle : pose le perso DEBOUT sur le sol au-dessus du
## sommet (l'échelle vit toujours sous une plateforme one-way dédiée).
## On restaure d'abord le masque one-way (coupé pendant l'état), on cherche
## la surface par rayon autour du sommet de la zone, puis on pose les pieds
## dessus avec une micro-poussée vers le bas pour valider le contact au sol
## dès le premier frame — ni chute parasite, ni particules d'atterrissage.
func _echelle_pose_au_sommet() -> void:
	set_collision_mask_value(ONEWAY_LAYER, true)
	var top := _echelle_zone_top(_current_echelle) if _current_echelle != null \
		else global_position.y
	# cherche la surface du sol depuis au-dessus du sommet de zone jusqu'au
	# niveau des pieds : couvre aussi bien une zone collée à la planche
	# qu'une zone volontairement étirée bien au-dessus (réglage d'émergence)
	var q := PhysicsRayQueryParameters2D.create(
		Vector2(global_position.x, top - 80.0),
		Vector2(global_position.x, global_position.y + 20.0),
		collision_mask)
	q.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit:
		global_position.y = hit.position.y
	else:
		global_position.y = top
	velocity = Vector2(0.0, 50.0)  # micro-poussée : contact sol immédiat
	print("[ECH] sortie HAUT (pose au sommet)  perso_y=",
		snappedf(global_position.y, 0.1), " sol_trouve=", not hit.is_empty())
	goto_state(States.IDLE)


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


## Tente d'accrocher une échelle (appui haut/bas dans les états qui le permettent)
func _try_echelle() -> bool:
	var ladder := _find_echelle()
	if ladder == null:
		# secours au niveau des pieds : accroche depuis une plateforme dont
		# la zone ne dépasse que peu au-dessus de la surface — l'échelle
		# garde ainsi la priorité sur le DROP
		ladder = _find_echelle_at(global_position + Vector2(0.0, -8.0))
	if ladder == null:
		return false
	_current_echelle = ladder
	change_state(States.ECHELLE)
	return true


func echelle_enter() -> void:
	velocity = Vector2.ZERO
	_recharge_air_moves()
	_echelle_enter_pframe = Engine.get_physics_frames()
	# sur l'échelle, les plateformes traversables (one-way) ne bloquent plus :
	# indispensable pour descendre depuis un rebord ou croiser une plateforme
	set_collision_mask_value(ONEWAY_LAYER, false)
	# aimante le perso sur l'axe central de l'échelle
	if _current_echelle != null:
		global_position.x = _current_echelle.global_position.x
		var top := _echelle_zone_top(_current_echelle)
		# accroche au-dessus de la butée (depuis une plateforme) : petit
		# enfoncement immédiat pour empoigner l'échelle au lieu de flotter
		var limite := top + ECHELLE_TOP_OFFSET
		if global_position.y < limite:
			global_position.y = minf(global_position.y + ECHELLE_GRAB_SINK, limite)
		print("[ECH] enter  perso_y=", snappedf(global_position.y, 0.1),
			" haut_zone=", snappedf(top, 0.1),
			" ecart(perso-haut)=", snappedf(global_position.y - top, 0.1),
			" au_sol=", is_on_floor())
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
					# butée atteinte en montant, rien au-dessus : pose debout
					# sur le sol au-dessus du sommet (plus de saut)
					_echelle_pose_au_sommet()
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

	# animations : toujours celles de l'échelle, même pendant la glisse
	# vers la butée (plus d'anim de chute parasite à l'accroche haute)
	if dir < 0.0:
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
			# sortie par le HAUT en montant : pose debout sur le sol au-dessus
			_echelle_pose_au_sommet()
		elif is_on_floor():
			print("[ECH] sortie SOL  perso_y=", snappedf(global_position.y, 0.1))
			goto_state(States.IDLE)
		else:
			print("[ECH] sortie CHUTE  perso_y=", snappedf(global_position.y, 0.1))
			goto_state(States.CHUTE)
		return

	# pieds au sol en descendant → arrivé en bas.
	# Garde de 3 frames après l'accroche : en s'accrochant depuis une
	# plateforme (appui bas au-dessus de l'échelle), is_on_floor est encore
	# "vrai" au premier frame et éjectait l'état avant la descente
	if is_on_floor() and dir > 0.0 and not au_dessus_butee \
		and Engine.get_physics_frames() > _echelle_enter_pframe + 3:
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

	# percuter un mur stoppe la roulade — sauf si pas la place de se relever
	# (tunnel bas : on reste en roulade, quitte à pousser contre le mur)
	if _raycast_hits_wall(wall_right) and _can_stand_up():
		goto_state(States.IDLE)
		return

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
@export var DASH_DURATION: float = 0.2363
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
	animator.play("dash")


func dash_execute(delta: float) -> void:
	_dash_timer += delta
	# trajectoire figée : horizontal pur, la gravité est suspendue
	velocity.x = last_direction * DASH_SPEED
	velocity.y = 0.0

	# percuter un mur interrompt le dash : accroche immédiate en glissade
	# (raycast avant uniquement — l'arrière raccrocherait le mur qu'on quitte)
	if _raycast_hits_wall(wall_right):
		change_state(States.WALL_JUMP)
		return
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
	slash_attack.position = Vector2(-4, -70)
	_flip_from_input()
	combo_buffered = false
	animator.play("attack")

func attack_light_1_execute(delta: float) -> void:
	_attack_run_movement(delta)

func attack_light_1_input(event: InputEvent) -> void:
	# CANCEL DÉFENSIF : sauter ou rouler interrompt l'attaque à tout moment
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
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
	# CANCEL DÉFENSIF : sauter ou rouler interrompt l'attaque à tout moment
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
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
	# CANCEL DÉFENSIF : sauter ou rouler interrompt l'attaque à tout moment
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
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
	# CANCEL DÉFENSIF : même la lourde s'interrompt pour esquiver
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)

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
	slash_attack.position = Vector2(-4, -73)
	animator.play("attack_air")
	if velocity.y < 0.0:
		velocity.y = 0.0  # stoppe la montée, la gravité prend le relais

func attack_air_execute(delta: float) -> void:
	velocity.y = minf(velocity.y + gravity * GRAVITY_FALL * delta, MAX_FALL_SPEED)

	if is_on_floor():
		_handle_landing()

func attack_air_input(event: InputEvent) -> void:
	# CANCEL DÉFENSIF aérien : dash ou double saut interrompent l'attaque
	if _fresh_press("esquive") and _try_air_dash():
		return
	if _fresh_press("jump") and _try_double_jump():
		return

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
	if Player.bloodheal < HEAL_COST:
		_notify_insufficient("bloodheal")
		return
	change_state(States.HEAL)


func heal_enter() -> void:
	# se soigner exige l'immobilité : on coupe tout élan résiduel
	velocity.x = 0.0
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
			Player.changement_de_bloodheal(-HEAL_COST)
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
## Coût en sang d'une boule — 0 pour le moment : tir ILLIMITÉ (rééquilibrage
## sept. 2026, remettre un coût ici le jour où le sort redevient payant)
@export var BLOODBALL_COST: int = 0
var _cast_timer := 0.0


## Tente de lancer le sort : vérifie la jauge de sang ; si insuffisante,
## déclenche le feedback UI (jauge qui tremble + clignote rouge) sans caster
func _try_cast_bloodball() -> void:
	if Player.bloodheal < BLOODBALL_COST:
		_notify_insufficient("bloodheal")
		return
	change_state(States.BLOODBALL)


## Feedback universel de coût refusé : fait trembler/clignoter l'UI de la
## ressource concernée ("sang" = jauge, "blood" = compteur)
func _notify_insufficient(kind: String) -> void:
	var huds := get_tree().get_nodes_in_group("UI_Bloodheal")
	if not huds.is_empty() and huds[0].has_method("insufficient_feedback"):
		huds[0].insufficient_feedback(kind)

func bloodball_enter() -> void:
	print("[SPELL] cast ! spawn de la boule au marker ", spellcast.global_position)
	Player.changement_de_bloodheal(-BLOODBALL_COST)  # le sort boit son sang
	# Au sol : le perso se plante pour lancer. En l'air : comme l'attaque
	# aérienne, le cast ne touche pas à l'élan du saut
	if is_on_floor():
		animator.play("cast")
		velocity.x = 0.0
	else:
		animator.play("cast_air")
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
@export var HIT_KNOCK_Y:  float = -287.0   # × 1,6 avec la gravité projet à 2500 : même soulèvement qu'à −180 sous 980
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
# ---- DÉMO : écran de mort (voile sombre + "Press X to revive") -----------
# À SUPPRIMER après la démo : cette constante, la ligne marquée DÉMO dans
# dead_enter, et le fichier SCRIPT/UTILITAIRE/ecran_mort_demo.gd.
const ECRAN_MORT_DEMO := preload("res://SCRIPT/UTILITAIRE/ecran_mort_demo.gd")
# --------------------------------------------------------------------------
func dead_enter() -> void:
	animator.play("death")
	velocity.x = 0.0            # FIX: stoppe le mouvement horizontal
	add_child(ECRAN_MORT_DEMO.new())   # DÉMO — écran de mort (se retire seul)



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
		# au respawn, la jauge de sang offre EXACTEMENT un soin : le joker
		# du joueur, à dépenser au bon moment
		Player.bloodheal = HEAL_COST
		# respawn dans la scène du dernier checkpoint croisé (peut être une
		# autre scène que celle où on est mort)
		var scene_path: String = Loader._target_scene_path
		if Player.has_checkpoint and Player.last_checkpoint_scene != "":
			scene_path = Player.last_checkpoint_scene
		Loader.load_scene_with_loading(scene_path)

func dead_exit() -> void:
	velocity = Vector2.ZERO

# =====================  DROP (passer à travers one-way)  ===========================
#region DROP
const ONEWAY_LAYER := 2
const DROP_THROUGH_TIME := 0.25
var _drop_timer := 0.0
var _drop_airborne := false  # vrai dès qu'on a réellement quitté le sol

## Le sol sous les pieds est-il RÉELLEMENT traversable ? Un DROP n'a de sens
## que si, une fois la couche one-way ignorée, plus rien ne retient le perso.
## Un bloc qui a coché couche 1 ET couche 2 reste solide → pas de DROP
## (sinon : anim de chute sur place + particules d'atterrissage fantômes).
func _standing_on_oneway() -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision_normale.shape
	var xf := collision_normale.global_transform
	xf.origin.y += 6.0  # léger décalage vers le bas : ce qu'il y a sous les pieds
	params.transform = xf
	params.collision_mask = 1 << (ONEWAY_LAYER - 1)
	params.exclude = [get_rid()]
	# masque restant pendant le DROP : ce qui colle encore n'est pas traversable
	var mask_apres_drop: int = collision_mask & ~(1 << (ONEWAY_LAYER - 1))
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 8):
		var body = hit.get("collider")
		if body is StaticBody2D and (body.collision_layer & mask_apres_drop) == 0:
			return true
	return false


func drop_enter() -> void:
	_drop_timer = DROP_THROUGH_TIME
	_drop_airborne = false
	set_collision_mask_value(ONEWAY_LAYER, false)
	animator.play("chute")
	velocity.y = 50.0

func drop_execute(delta: float) -> void:
	_drop_timer -= delta
	velocity.y = minf(velocity.y + gravity * GRAVITY_FALL * delta, MAX_FALL_SPEED)

	var direction := Input.get_axis("left_move", "right_move")
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
		_flip_from_input()
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	if not is_on_floor():
		_drop_airborne = true

	if _drop_timer <= 0.0:
		change_state(States.CHUTE)
		return

	# n'atterrit (particules, sortie d'état) qu'après avoir vraiment décollé :
	# au 1er frame is_on_floor() date encore du tick où on était posé
	if is_on_floor() and _drop_airborne:
		_handle_landing()

func drop_exit() -> void:
	set_collision_mask_value(ONEWAY_LAYER, true)
#endregion


# =====================  CORDE (balancier)  ===========================
#region CORDE
## Corde suspendue (SCRIPT/INTERACTIBLE/corde.tscn). Quand le joueur la
## touche en l'air, la corde appelle saisir_corde() ; c'est le joueur qui
## accepte selon son état. Le balancier est un pendule rigide simulé par la
## corde, le joueur y pend par ANCRE_GRAB. Stick = on pompe en rythme,
## haut/bas = on grimpe/descend, saut = on se lâche avec l'élan (+ impulsion),
## esquive = on se laisse tomber. Toute accroche recharge double saut et dash.

const CORDE_COOLDOWN := 0.35             # s avant de pouvoir reprendre une corde
## impulsion verticale ajoutée à l'élan quand on saute de la corde
@export var CORDE_SAUT_IMPULSION: float = -450.0
var _corde: Node2D = null
var _corde_cooldown := 0.0
var _corde_pending := false
var _corde_velocite_sortie := Vector2.ZERO
var _corde_est_pendule := false   # la « corde » est une accroche pendulaire (câble de grappin)


## Appelé par la corde qui touche le joueur. Retourne true s'il s'y accroche.
func saisir_corde(corde: Node2D) -> bool:
	if corde == null or _corde_cooldown > 0.0:
		return false
	if not (current_state in [States.JUMP, States.CHUTE, States.DASH, States.ATTACK_AIR]):
		return false
	_corde = corde
	change_state(States.CORDE)
	return true


## la main qui tient : ANCRE_GRAB sur une corde, l'ancre du grappin sur une
## accroche pendulaire (c'est de là que part le câble)
func _corde_ancre_main() -> Node2D:
	if _corde_est_pendule and ancre_grappin != null:
		return ancre_grappin
	return ancre_grab


func corde_enter() -> void:
	_recharge_air_moves()
	_corde_est_pendule = _corde.has_method("signaler_blocage")
	_corde.saisir(self, _corde_ancre_main().global_position, velocity)
	velocity = Vector2.ZERO
	if _corde_est_pendule and _anim_existe(ANIM_GRAPPIN_GRAB):
		animator.play(ANIM_GRAPPIN_GRAB)   # on tient le câble du grappin, pas une corde
	else:
		animator.play("suspendu")


func corde_execute(delta: float) -> void:
	if _corde == null or not is_instance_valid(_corde):
		change_state(States.CHUTE)
		return
	FALL_POINT = global_position.y   # appui légitime : suspendu
	var axe := Input.get_axis("left_move", "right_move")
	var grimpe := Input.get_axis("down_move", "up_move")
	var main: Vector2 = _corde.simuler_balancier(delta, axe, grimpe)
	# le perso pend par la main : le corps se place pour que ANCRE_GRAB soit sur la corde
	var ancre := _corde_ancre_main()
	var cible := main - (ancre.global_position - global_position)
	if _corde_est_pendule:
		# une accroche pendulaire se prend aussi depuis le sol ou près d'un mur :
		# déplacement AVEC collisions ; bloqué, le pendule repart de la position réelle
		var col := move_and_collide(cible - global_position)
		if col != null:
			_corde.signaler_blocage(ancre.global_position, col.get_normal(), delta)
		# câble tracé APRÈS le déplacement (sinon il part de la main du pas précédent)
		_corde.cable_montrer(ancre.global_position, _corde.point())
	else:
		global_position = cible   # corde classique : inchangé
	velocity = Vector2.ZERO
	# pas de retournement au gré du balancier (trop étrange) : le perso garde
	# le regard qu'il avait en attrapant la corde


func corde_input(_event: InputEvent) -> void:
	if _fresh_press("jump"):
		_corde_velocite_sortie = _corde.vitesse_main()
		_corde_velocite_sortie.y = minf(_corde_velocite_sortie.y, 0.0) + CORDE_SAUT_IMPULSION
		_corde_pending = true
		change_state(States.JUMP)
		return
	if Input.is_action_just_pressed("esquive"):
		velocity = _corde.vitesse_main()   # on se laisse tomber avec l'élan
		change_state(States.CHUTE)


func corde_exit() -> void:
	if _corde != null and is_instance_valid(_corde):
		_corde.lacher()
	if _corde_est_pendule:
		_grappin_cooldown = maxf(_grappin_cooldown, CORDE_COOLDOWN)
	_corde_est_pendule = false
	_corde = null
	_corde_cooldown = CORDE_COOLDOWN
#endregion


# =====================  GRAPPIN  ===========================
#region GRAPPIN
## Grappin (touche "grapin") vers une accroche (SCRIPT/INTERACTIBLE/
## accroche_grappin.tscn, groupe GRAPPIN). Pas de zone : comme Batman, Sekiro
## ou Ori, le joueur scanne chaque pas de physique les accroches à portée
## (GRAPPIN_PORTEE), au-dessus de lui (GRAPPIN_ANGLE_MAX depuis la verticale)
## et sans mur entre sa main et le point (rayon sur la couche 1) ; la plus
## proche prenable s'allume, R1 y envoie le grappin :
##   1) LANCER : le câble file de la main au point, le joueur est figé ;
##   2) TIRER  : le joueur est hissé d'un trait jusqu'au point (main dessus) ;
##   3) arrivé : catapulte au-dessus du point, grappin détaché, double saut
##      et dash rechargés. Aucune suspension. Un coup reçu interrompt tout
##      (le câble est caché par grappin_exit).

@export var GRAPPIN_ACCEL: float = 6520.0        ## force de traction MAX du câble (px/s²), la gravité (2500) tire contre — même traction nette qu'à 5000 sous 980
@export var GRAPPIN_VITESSE_MAX: float = 1600.0  ## vitesse plafond de la traction (px/s)
## durée minimale d'une traction (s) : une accroche toute proche est hissée
## aussi lentement qu'une lointaine — l'accélération est calculée pour ça
@export var GRAPPIN_DUREE_MIN: float = 0.4
## amortissement par seconde de l'élan perpendiculaire au câble (anti-orbite)
@export var GRAPPIN_AMORT_DERIVE: float = 10.0
var _grappin_accel := 0.0   # accélération effective de la traction en cours
@export var GRAPPIN_CABLE_DUREE: float = 0.08    ## temps de vol du câble (s)
@export var GRAPPIN_ELAN_Y: float = -1500.0      ## catapulte verticale à l'arrivée (saut normal = -700)
@export var GRAPPIN_ELAN_X: float = 250.0        ## élan horizontal, dans le sens de l'approche
@export var GRAPPIN_PORTEE: float = 520.0        ## distance max main → accroche (px) — +15 % le 16 sept.
@export var GRAPPIN_ANGLE_MAX: float = 75.0      ## écart max à la verticale, en degrés (l'accroche doit être au-dessus)
const GRAPPIN_COOLDOWN := 0.3
## animations (SpriteFrames du joueur), jouées si elles existent :
##   lancer   : "grappin_sol" les pieds au sol, "grappin_air" sinon
##   traction : "grappin_grab", la même au sol et en l'air
## Une anim de lancer de PLUSIEURS frames donne sa durée au vol du câble ;
## une pose d'une seule frame n'a pas de durée propre → GRAPPIN_CABLE_DUREE.
## Repli si l'anim manque : "jump".
const ANIM_GRAPPIN_SOL := "grappin_sol"
const ANIM_GRAPPIN_AIR := "grappin_air"
const ANIM_GRAPPIN_GRAB := "grappin_grab"
var _grappin_candidat: Node2D = null   # accroche prenable ce pas-ci (allumée)
var _grappin_duree_cable := 0.08       # durée effective du vol du câble (anim ou export)
## d'où part le câble : un Marker2D "ANCRE_GRAPPIN" sous POINT, à placer sur la
## main de l'anim de lancer (déplaçable dans l'éditeur) ; à défaut, l'ancre de grab
@onready var ancre_grappin: Node2D = get_node_or_null("POINT/ANCRE_GRAPPIN")


func _main_grappin() -> Vector2:
	if ancre_grappin != null:
		return ancre_grappin.global_position
	return ancre_grab.global_position
const ETATS_GRAPPIN_OK := [States.IDLE, States.RUN, States.JUMP, States.CHUTE, States.DASH, States.ATTACK_AIR]
var _grappin_cible: Node2D = null
var _grappin_cooldown := 0.0
var _grappin_t := 0.0
var _grappin_tire := false
var _grappin_dir := 1
var _grappin_pending := false
var _grappin_velocite := Vector2.ZERO


## Chaque pas de physique : quelle accroche est prenable ? À portée, au-dessus,
## et rien entre la main et le point. La plus proche s'allume, les autres
## s'éteignent. Quelques rayons par frame au plus : les accroches d'un niveau
## se comptent sur les doigts d'une main.
func _grappin_scanner() -> void:
	var meilleure: Node2D = null
	if current_state in ETATS_GRAPPIN_OK and _grappin_cooldown <= 0.0:
		var main := _main_grappin()
		var d_min := INF
		var espace := get_world_2d().direct_space_state
		var lim := deg_to_rad(GRAPPIN_ANGLE_MAX)
		for a in get_tree().get_nodes_in_group("GRAPPIN"):
			if not (a is Node2D and a.has_method("point")):
				continue
			var cible: Vector2 = a.point()
			var v := cible - main
			var d := v.length()
			if d > GRAPPIN_PORTEE or d < 20.0 or v.y > -10.0:
				continue                       # trop loin, trop près, ou pas au-dessus
			if absf(atan2(v.x, -v.y)) > lim:
				continue                       # trop sur le côté
			if d >= d_min:
				continue
			# rien entre la main et le point ? (murs solides seulement)
			var q := PhysicsRayQueryParameters2D.create(main, cible, 1)
			q.exclude = [get_rid()]
			if espace.intersect_ray(q).is_empty():
				d_min = d
				meilleure = a
	if meilleure != _grappin_candidat:
		if _grappin_candidat != null and is_instance_valid(_grappin_candidat):
			_grappin_candidat.surligner(false)
		_grappin_candidat = meilleure
		if _grappin_candidat != null:
			_grappin_candidat.surligner(true)


## Touche "grapin" : part vers l'accroche allumée. Retourne true si le grappin part.
func _try_grappin() -> bool:
	if _grappin_candidat == null or not is_instance_valid(_grappin_candidat):
		return false
	_grappin_cible = _grappin_candidat
	_grappin_candidat.surligner(false)
	_grappin_candidat = null
	change_state(States.GRAPPIN)
	return true


func grappin_enter() -> void:
	velocity.x = 0.0                 # on garde (un peu de) la chute en cours : le poids
	velocity.y = clampf(velocity.y, 0.0, 300.0)
	_recharge_air_moves()
	_grappin_t = 0.0
	_grappin_tire = false
	# on regarde vers le point ; l'élan final partira de ce côté
	var dx: float = _grappin_cible.point().x - global_position.x
	if absf(dx) > 8.0:
		_grappin_dir = 1 if dx > 0.0 else -1
	else:
		_grappin_dir = last_direction
	last_direction = _grappin_dir
	point.scale.x = _grappin_dir
	_grappin_duree_cable = maxf(GRAPPIN_CABLE_DUREE, 0.001)
	# lancer : l'anim "sol" les pieds par terre, l'anim "air" sinon
	var anim_lancer := ANIM_GRAPPIN_SOL if is_on_floor() else ANIM_GRAPPIN_AIR
	if _anim_existe(anim_lancer):
		animator.play(anim_lancer)
		# une vraie animation (plusieurs frames) donne sa durée au vol du câble ;
		# une pose d'une frame n'a pas de durée propre → l'export fait foi
		if animator.sprite_frames.get_frame_count(anim_lancer) > 1:
			_grappin_duree_cable = maxf(_anim_duree(anim_lancer), 0.001)
	else:
		animator.play("jump")


## l'animation existe-t-elle dans les SpriteFrames du joueur ?
func _anim_existe(nom: String) -> bool:
	return animator.sprite_frames != null and animator.sprite_frames.has_animation(nom)


## durée totale d'une animation (s), frames à durées variables comprises
func _anim_duree(nom: String) -> float:
	var sf = animator.sprite_frames
	if sf == null or not sf.has_animation(nom):
		return 0.0
	var fps := maxf(sf.get_animation_speed(nom), 0.001)
	var total := 0.0
	for i in sf.get_frame_count(nom):
		total += sf.get_frame_duration(nom, i) / fps
	return total


func grappin_execute(delta: float) -> void:
	if _grappin_cible == null or not is_instance_valid(_grappin_cible):
		change_state(States.CHUTE)
		return
	FALL_POINT = global_position.y
	var cible: Vector2 = _grappin_cible.point()
	var main := _main_grappin()
	if not _grappin_tire:
		# 1) le câble file vers le point ; le joueur, lui, continue de tomber :
		#    c'est son poids qu'on sent pendant ce court instant
		velocity.x = 0.0
		velocity.y += gravity * delta
		_grappin_t += delta
		var t := clampf(_grappin_t / _grappin_duree_cable, 0.0, 1.0)
		if t >= 1.0:
			if _grappin_cible.has_method("saisir"):
				# ACCROCHE PENDULAIRE (accroche_pendule.tscn, la bleue) : pas de traction,
				# on reste suspendu au câble et on joue comme à la corde — l'accroche
				# fournit l'API d'une corde, l'état CORDE fait le reste
				_corde = _grappin_cible
				change_state(States.CORDE)
				return
			_grappin_tire = true
			if _anim_existe(ANIM_GRAPPIN_GRAB):
				animator.play(ANIM_GRAPPIN_GRAB)
			# accélération taillée sur la distance : une traction courte doit
			# durer GRAPPIN_DUREE_MIN elle aussi (d = ½·a·t² → a = 2d/t²),
			# la gravité étant compensée, et jamais plus que GRAPPIN_ACCEL
			var d0 := (cible - main).length()
			var t_min := maxf(GRAPPIN_DUREE_MIN, 0.05)
			# + de quoi annuler la chute en cours dans le même temps
			var chute := maxf(velocity.y, 0.0)
			_grappin_accel = clampf(2.0 * d0 / (t_min * t_min) + gravity + chute / t_min,
				gravity * 1.5, GRAPPIN_ACCEL)
		return
	# 2) traction PHYSIQUE : le câble accélère la main vers le point pendant
	#    que la gravité tire vers le bas → léger affaissement au départ, puis
	#    montée qui prend de la vitesse (treuil qui hisse un corps). Le
	#    déplacement passe par move_and_slide : un mur arrête net.
	var dest := cible - (main - global_position)
	var vers := dest - global_position
	var dist := vers.length()
	if dist > 0.001:
		var u := vers / dist
		# l'élan HORS de l'axe du câble est amorti : sans ça, un élan latéral
		# fait rater le point de peu et on tourne autour comme un satellite
		var v_axe := velocity.dot(u)
		var v_perp := velocity - u * v_axe
		v_perp *= maxf(0.0, 1.0 - GRAPPIN_AMORT_DERIVE * delta)
		velocity = u * v_axe + v_perp
		velocity += u * _grappin_accel * delta
	velocity.y += gravity * delta
	velocity = velocity.limit_length(GRAPPIN_VITESSE_MAX)
	# arrivée : à portée d'un pas, main au niveau du point ou au-dessus (point
	# dépassé, on ne tourne JAMAIS autour), ou point dépassé de peu à l'approche
	# — jamais au départ : en l'air on tombe encore quelques frames
	var pas := velocity.length() * delta
	var a_portee := dist <= maxf(20.0, pas * 1.1)
	var depasse := main.y <= cible.y + 6.0 or (dist < pas * 2.0 and vers.dot(velocity) < 0.0)
	if a_portee or depasse:
		if a_portee:
			global_position = dest
		# 3) catapulte au-dessus du point ; jump_enter applique la vitesse
		_grappin_velocite = Vector2(_grappin_dir * GRAPPIN_ELAN_X, GRAPPIN_ELAN_Y)
		_grappin_pending = true
		change_state(States.JUMP)


## Trace le câble ; appelé par _physics_process APRÈS move_and_slide. Tracé dans
## grappin_execute, donc AVANT le déplacement du pas, il partait de la main du
## pas précédent : écart = vitesse / 60, mesuré 21 px à 1283 px/s → le bout du
## câble sortait du bras, de plus en plus à mesure que la traction accélère.
func _grappin_tracer_cable() -> void:
	if _grappin_cible == null or not is_instance_valid(_grappin_cible):
		return
	var main := _main_grappin()
	var cible: Vector2 = _grappin_cible.point()
	if _grappin_tire:
		_grappin_cible.cable_montrer(main, cible)
	else:
		# le câble file : sa pointe avance de la main vers le point
		var t := clampf(_grappin_t / _grappin_duree_cable, 0.0, 1.0)
		_grappin_cible.cable_montrer(main, main.lerp(cible, t))


func grappin_exit() -> void:
	if _grappin_cible != null and is_instance_valid(_grappin_cible):
		_grappin_cible.cable_cacher()
	_grappin_cible = null
	_grappin_cooldown = GRAPPIN_COOLDOWN
#endregion
