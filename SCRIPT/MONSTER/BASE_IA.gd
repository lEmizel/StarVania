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
## l'état « DEAD » de l'enum du monstre (-1 s'il n'en a pas) : voir
## `_etats_de_mort()` et la garde de `change_state`
var _etat_dead := -1
## SONNÉ (talisman « Parade ») : l'état de repos de son enum, et le temps qui
## reste avant qu'il reprenne ses esprits (voir `etourdir`)
var _etat_idle := -1
var _etourdi_reste := 0.0
const ETOURDI_SCENE := preload("res://SCRIPT/SHADER/etourdi.tscn")

var last_direction := 1
var target: Node2D = null
var initial_position: Vector2

# Stats communes
var hp: int = 100
var max_hp: int = 100
## Dégâts des attaques, EN CŒURS (lu par l'animator au moment du coup)
@export var attack_power: int = 1

# CAMPS (23 sept. 2026, demande de Kaoru) : des groupes de monstres capables
# de se taper dessus. Même valeur = alliés, valeurs différentes = ennemis à vue,
# traités exactement comme le joueur. Le joueur a son propre camp (1 par
# défaut, `faction` dans player.gd) : un monstre du camp 1 ne l'attaque pas.
@export_group("Camp")
## camp du monstre, 0 à 10. Tous à 0 par défaut : rien ne change tant qu'on
## n'y touche pas
@export_range(0, 10) var faction: int = 0
## dégâts infligés aux AUTRES MONSTRES, en points de vie (70 = un coup d'épée
## du joueur). À régler par monstre pour rester cohérent avec sa force
@export var degats_monstres: int = 70
## temps mort entre deux dégâts de CONTACT sur un même monstre : ils n'ont pas
## le stun du joueur, sans ça deux ennemis qui se chevauchent se broient en
## une seconde
@export var contact_temps_mort := 0.6
@export_group("")

# VOL LIBRE (23 sept. 2026, demande de Kaoru) : un monstre VOLANT qui n'a pas de
# cible virevolte de point en point, au hasard, dans un rayon autour de son
# poste. Éteint par défaut ; les volants (orbe, kamikaze) appellent
# `virevolter()` dans leur idle quand la case est cochée. Les terrestres n'y
# touchent pas.
@export_group("Vol libre (volants)")
## coché = il virevolte au repos au lieu de rester à son poste
@export var virevolte := false
## rayon autour du poste, en pixels (200 px ≈ 2 m à l'échelle du jeu)
@export var virevolte_rayon := 200.0
## vitesse de vol entre deux points
@export var virevolte_vitesse := 140.0
## pause entre deux points, tirée entre ces deux valeurs (secondes)
@export var virevolte_pause_min := 0.2
@export var virevolte_pause_max := 0.9
@export_group("")
var _virevolte_cible := Vector2.INF     # INF = pas de point choisi
var _virevolte_attente := 0.0
var _virevolte_chrono := 0.0
var _contact_recents: Dictionary = {}   # corps → temps restant avant de pouvoir le retoucher

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
## UN VRAI BOSS : échappe au Coup de grâce (talisman du joueur). Le skeleton_boss
## n'en est PAS un — c'est un élite (Kaoru, 1er oct. 2026) : on peut l'achever.
## À cocher sur les vrais boss quand ils viendront.
@export var vrai_boss := false
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
# (la scène de récolte de sang est fabriquée et recyclée par l'autoload Pool)


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
	# COUP DE GRÂCE : porter ou retirer le talisman fissure (ou non) ceux qui
	# sont déjà bas en vie
	Player.talismans_changes.connect(_maj_fissures)
	_setup_contact_area()
	# Les zones ne regardaient que la couche du joueur (masque 1). Les monstres
	# sont sur la couche 8 : on l'ajoute par code, aucune scène à retoucher.
	vision.collision_mask |= 8
	var zone_attaque := get_node_or_null("POINT/collision_attack") as Area2D
	if zone_attaque != null:
		zone_attaque.collision_mask |= 8
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
	# sonné : il reste au repos (change_state refuse le reste) ; à la fin, il
	# reprend ses esprits et décide de nouveau
	if _etourdi_reste > 0.0:
		_etourdi_reste -= delta
		if _etourdi_reste <= 0.0:
			_etourdi_reste = 0.0
			call_deferred("decide")
	# à portée d'exécution (talisman « Coup de grâce ») : ses fissures battent
	if _fissuree:
		_fissure_t += delta
		_flash_material.set_shader_parameter("fissure", 0.72 + 0.28 * sin(_fissure_t * 6.0))
	state_functions[current_state]["execute"].call(delta)
	# Knockback absolu : tant qu'il est actif, il REMPLACE le déplacement
	# horizontal de l'état (l'ennemi ne peut pas compenser en marchant contre).
	# Injecté dans velocity pour que move_and_slide glisse le long du sol,
	# au lieu de move_and_collide qui se bloquait sur les jointures de tiles.
	if _knock != Vector2.ZERO:
		velocity.x = _knock.x
	move_and_slide()
	_decay_knockback(delta)
	_tick_contacts(delta)
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
	_contact_area.collision_mask = 1 | 8      # joueur + monstres
	var cs := CollisionShape2D.new()
	cs.shape = collision.shape
	cs.position = collision.position
	cs.rotation = collision.rotation
	cs.scale = collision.scale
	_contact_area.add_child(cs)
	add_child(_contact_area)


func _check_contact_damage() -> void:
	if _is_dead() or contact_damage <= 0:
		return
	for body in _contact_area.get_overlapping_bodies():
		if body == self or not est_ennemi(body):
			continue
		if body.is_in_group("Player"):
			# L'invulnérabilité du joueur (état HIT / ROLL) limite la cadence
			body.apply_damage(contact_damage, global_position.x, "contact:" + name)
		elif not _contact_recents.has(body):
			# un monstre n'a pas de stun : c'est NOUS qui tenons la cadence
			_contact_recents[body] = contact_temps_mort
			body.apply_damage(degats_monstres, global_position.x, "contact:" + name, true, self)


func _tick_contacts(delta: float) -> void:
	if _contact_recents.is_empty():
		return
	for body in _contact_recents.keys():
		if not is_instance_valid(body):
			_contact_recents.erase(body)
			continue
		_contact_recents[body] -= delta
		if _contact_recents[body] <= 0.0:
			_contact_recents.erase(body)


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
	# premier ennemi vu, premier servi : on ne lâche pas une cible pour une
	# autre, on en reprend une quand la nôtre meurt ou s'éloigne
	if target == null and est_ennemi(body):
		target = body

func _on_vision_body_exited(body: Node2D) -> void:
	pass

func check_tracking() -> bool:
	# une cible monstre peut MOURIR (ce que le joueur ne fait pas en plein
	# combat : sa mort recharge la scène) : on la lâche, sinon on frapperait
	# un cadavre jusqu'à la fin des temps
	if target != null and (not is_instance_valid(target) or (target is BaseAI and target._is_dead())):
		target = null
	if not target:
		return false
	if distance_to_target() > max_tracking_distance:
		target = null
		return false
	return true


## Re-scan de la zone de vision (les corps déjà présents n'émettent pas de
## signal d'entrée) : l'ennemi le plus proche, borné par la distance d'oubli.
## Commun à tous les monstres depuis les camps (chacun avait sa copie qui ne
## cherchait que le joueur).
func _rescan_vision() -> void:
	var meilleur: Node2D = null
	var meilleure_dist := max_tracking_distance
	for b in vision.get_overlapping_bodies():
		if b == self or not est_ennemi(b):
			continue
		if b is BaseAI and b._is_dead():
			continue
		var d: float = b.global_position.distance_to(global_position)
		if d <= meilleure_dist:
			meilleure_dist = d
			meilleur = b
	if meilleur != null:
		target = meilleur


# ============================================================
#  VOL LIBRE
# ============================================================

## Vitesse à appliquer cette frame pour virevolter (ZERO pendant les pauses
## entre deux points). Tire un point au hasard dans le disque autour du poste,
## y vole, marque une pause, recommence. Un point inaccessible (dans un mur, le
## sol) est abandonné au bout du temps qu'il aurait fallu pour l'atteindre.
func virevolter(delta: float) -> Vector2:
	if _virevolte_attente > 0.0:
		_virevolte_attente -= delta
		return Vector2.ZERO
	if _virevolte_cible == Vector2.INF:
		_virevolte_nouveau_point()
	var vers := _virevolte_cible - global_position
	_virevolte_chrono += delta
	var trop_long := virevolte_rayon * 2.0 / maxf(virevolte_vitesse, 1.0) + 1.0
	if vers.length() < 12.0 or _virevolte_chrono > trop_long:
		_virevolte_cible = Vector2.INF
		_virevolte_attente = randf_range(virevolte_pause_min, virevolte_pause_max)
		return Vector2.ZERO
	flip_toward(_virevolte_cible.x)
	return vers.normalized() * virevolte_vitesse


## un point uniforme dans le disque (le sqrt évite d'entasser les points au centre)
func _virevolte_nouveau_point() -> void:
	_virevolte_cible = initial_position \
		+ Vector2.from_angle(randf() * TAU) * virevolte_rayon * sqrt(randf())
	_virevolte_chrono = 0.0


# ============================================================
#  CAMPS
# ============================================================

## camp d'un nœud : le sien s'il en a un, −1 sinon (décor, projectile…)
static func faction_de(n: Node) -> int:
	if n != null and is_instance_valid(n) and "faction" in n:
		return int(n.faction)
	return -1


## un ennemi = quelqu'un qui a un camp, et pas le nôtre
func est_ennemi(n: Node) -> bool:
	if n == self:
		return false
	var f := faction_de(n)
	return f >= 0 and f != faction


## LE point d'entrée des coups de ce monstre : choisit l'échelle de dégâts
## (cœurs pour le joueur, points de vie pour un monstre), refuse les alliés,
## et se déclare comme attaquant pour que la victime riposte contre NOUS
func infliger(cible: Node, source_x: float, tag: String) -> void:
	if not est_ennemi(cible) or not cible.has_method("apply_damage"):
		return
	if cible.is_in_group("Player"):
		# le joueur sait qui le frappe : sa parade (talisman « Parade ») sonne
		# l'attaquant
		cible.apply_damage(attack_power, source_x, tag, false, self)
	else:
		cible.apply_damage(degats_monstres, source_x, tag, true, self)


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


## Une TEINTE d'état sur le dessin du monstre, MULTIPLIÉE (l'encre reste
## noire, le clair prend la couleur) ; 0 = aucune. Indépendante de l'éclair de
## coup. Le poison du talisman « Sang corrompu » le fait virer au violet
## (SCRIPT/SHADER/poison_sang.gd).
func teinter(couleur: Color, force: float) -> void:
	if _flash_material == null:
		return
	_flash_material.set_shader_parameter("teinte_couleur", couleur)
	_flash_material.set_shader_parameter("teinte_force", clampf(force, 0.0, 1.0))


## _source_tag : étiquette de provenance optionnelle (parité avec le player,
## utilisée par les logs de debug — sans effet sur la logique, sauf "poison" :
## le poison du talisman « Sang corrompu » a son propre clignotement violet
## (SCRIPT/SHADER/poison_sang.gd), pas d'éclair blanc à chaque morsure)
## `knockback` : false pour les dégâts qui piquent sans déplacer
## (ex. bloodball) — la réaction d'aggro/volte-face reste, seul le recul saute
## Retourne true si le coup a PORTÉ (false : déjà mort, ou invulnérable) — le
## joueur s'en sert pour recharger sa jauge bloodheal à chaque coup réel.
## `attaquant` : qui frappe (un monstre d'un autre camp se déclare). Sans lui,
## on suppose le joueur, comme avant.
func apply_damage(amount: int, source_x, _source_tag := "?", knockback := true, attaquant: Node = null) -> bool:
	if _is_dead():
		return false
	if invulnerable:
		return false
	# VENIN (talisman du joueur) : empoisonné, il prend plus de NOS coups
	amount = _venin(amount, attaquant)
	hp -= amount
	vie.emit_signal("health_request", -amount)
	vie.apparition_temp()
	if _source_tag != "poison":
		_flash_white()
	# COUP DE GRÂCE (talisman du joueur) : à portée d'exécution, il se fissure
	_maj_fissures()
	if hp <= 0:
		_knock = Vector2.ZERO
		# Cadavre inerte : plus détectable ni bloquant (layer 0), mais il garde
		# son mask pour continuer de reposer sur le sol
		set_deferred("collision_layer", 0)
		if _contact_area != null:
			_contact_area.set_deferred("monitoring", false)
		# Récolte de sang à l'endroit de la mort
		# (DEBUG PERF, à retirer après la démo : F6 ou `-- --sans-sang` supprime
		#  ces particules GPU pour isoler les freezes Mac)
		if not DebugPerf.sans_sang:
			Pool.sang(global_position)   # instance recyclée : zéro création en jeu
		_on_dead()
		# un monstre tué : qui l'a tué (le joueur réagit à ses victimes, talisman
		# « Essaim »). `attaquant` est nul pour les pièges et les sources anonymes.
		Player.monstre_tue.emit(self, attaquant)
		return true
	# Attaqué — même de dos, même hors vision, même par un projectile : le
	# monstre prend l'AGRESSEUR pour cible (le joueur si on ne sait pas qui a
	# frappé), se retourne vers LUI (pas vers le projectile, qui est déjà au
	# contact) et réagit immédiatement sans attendre le prochain cycle de
	# décision de son état. Un coup venant d'un ALLIÉ ne provoque rien : pas
	# de riposte, pas de changement de cible.
	var agresseur: Node = attaquant
	if agresseur == null:
		var players := get_tree().get_nodes_in_group("Player")
		if players.size() > 0:
			agresseur = players[0]
	if agresseur != null and est_ennemi(agresseur) and target != agresseur:
		target = agresseur
		if has_method("decide"):
			call_deferred("decide")
	if target != null:
		flip_toward(target.global_position.x)
	elif source_x != null:
		flip_toward(source_x)
	# Knockback appliqué par-dessus l'état courant, sans l'interrompre —
	# sauf inébranlable (aucun recul, c'est le joueur qui encaisse) ou
	# source sans recul (bloodball…)
	if inebranlable or not knockback:
		return true
	var dir := 0
	if source_x != null:
		dir = 1 if (global_position.x - source_x) > 0 else -1
	_knock = Vector2(dir * HIT_KNOCK_X, HIT_KNOCK_Y)
	return true

func _is_dead() -> bool:
	return false


## SONNÉ (1er oct. 2026, talisman « Parade ») : pendant `duree` s le monstre ne
## fait plus rien. Son coup en cours s'arrête net — il repasse au repos (IDLE :
## l'animation change, ses zones de coup s'éteignent) — et il n'en sort pas
## avant la fin (change_state refuse) ; la gravité et le recul jouent encore.
## Trois étoiles tournent au-dessus de sa tête (SCRIPT/SHADER/etourdi.tscn).
## Sans effet sur un mort, sur un monstre dans sa séquence de mort (le
## kamikaze qui gonfle) ou sans état IDLE. Sonné de nouveau : le plus long des
## deux temps.
func etourdir(duree: float) -> void:
	if duree <= 0.0 or _is_dead() or _etat_idle < 0 or current_state in _etats_de_mort():
		return
	var deja := _etourdi_reste > 0.0
	_etourdi_reste = maxf(_etourdi_reste, duree)
	if current_state != _etat_idle:
		change_state(_etat_idle)
	if not deja:
		var e := ETOURDI_SCENE.instantiate()
		e.demo_boucle = false
		e.monstre = self
		var hote: Node = get_tree().current_scene
		if hote == null:
			hote = get_parent()
		hote.add_child(e)


func est_etourdi() -> bool:
	return _etourdi_reste > 0.0


## VENIN (1er oct. 2026, talisman du joueur « Venin ») : un monstre EMPOISONNÉ
## (méta "poison", posée par poison_sang.gd) prend `venin_multiplicateur` fois
## les coups du joueur (player.gd) — tous : épée, boule, poison compris.
func _venin(amount: int, attaquant: Node) -> int:
	if attaquant == null or not attaquant.is_in_group("Player") or not Player.talisman_equipe("venin"):
		return amount
	var poison = get_meta("poison") if has_meta("poison") else null
	if not is_instance_valid(poison):
		return amount
	return roundi(amount * float(attaquant.get("venin_multiplicateur")))


## COUP DE GRÂCE (1er oct. 2026, talisman du joueur « Coup de grâce ») : à moins
## de `SEUIL_GRACE` de sa vie, un monstre est À PORTÉE D'EXÉCUTION — sauf un
## `vrai_boss` (d'abord : sauf un inébranlable, ce qui épargnait le
## skeleton_boss — un élite, pas un vrai boss, et la larve en boule de piques).
## Il se fissure de rouge (hit_flash.gdshader, `fissure`, qui bat dans
## `_physics_process`) et le prochain coup d'épée l'achève (animator.gd ;
## player.gd `grace_executer`) — celui du double de l'Ombre de sang aussi
## (ombre_sang.gd).
const SEUIL_GRACE := 0.25
var _fissuree := false
var _fissure_t := 0.0


func executable() -> bool:
	return Player.talisman_equipe("grace") and not vrai_boss and hp > 0 \
			and float(hp) <= float(max_hp) * SEUIL_GRACE


func _maj_fissures() -> void:
	_fissuree = executable()
	if not _fissuree and _flash_material != null:
		_flash_material.set_shader_parameter("fissure", 0.0)

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
	_etat_dead = int(states_enum.get("DEAD", -1))
	_etat_idle = int(states_enum.get("IDLE", -1))
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


## Les états où un monstre MORT a encore le droit d'aller : sa séquence de
## mort. Par défaut, l'état « DEAD » de son enum. Un monstre dont la mort se
## joue en plusieurs temps les liste lui-même (le kamikaze gonfle, puis explose).
func _etats_de_mort() -> Array:
	return [_etat_dead] if _etat_dead >= 0 else []


func change_state(new_state: int) -> void:
	if _changing_now or new_state == current_state:
		return
	# UN MORT NE SE RELÈVE PAS (1er oct. 2026). `goto_state` passe par
	# call_deferred : l'IA programme son prochain état pendant son pas de
	# physique, et ce changement n'arrive qu'en FIN d'image. Si le coup fatal
	# tombe entre les deux (la brume du sillage frappe dans son propre pas de
	# physique, juste après celui des monstres), le changement en attente
	# sortait le monstre de DEAD : PV à 0, plus de barre de vie, intouchable
	# (couche 0 depuis sa mort), mais son IA et ses attaques tournaient encore —
	# la « larve immortelle » de Kaoru. Reproduit sur larve, squelette et
	# kamikaze avant ce garde-fou.
	if _is_dead() and not (new_state in _etats_de_mort()):
		return
	# SONNÉ (talisman « Parade ») : il reste au repos jusqu'à la fin
	if _etourdi_reste > 0.0 and new_state != _etat_idle and not (new_state in _etats_de_mort()):
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
## Exception : un danger où l'on a DÉJÀ les pieds ne compte pas (poussé dessus
## par un coup, piège rétractable qui s'arme sous nous…). Il est « devant » des
## deux côtés : faire demi-tour ferait trembler le monstre sur place jusqu'à
## sa mort. La sortie est droit devant.
func danger_devant(rc: RayCast2D) -> bool:
	var devant := _dangers_sur_segment(rc.global_position, rc.to_global(rc.target_position))
	if devant.is_empty():
		return false
	var sous_pieds := _dangers_sur_segment(global_position + Vector2(0.0, -20.0),
		global_position + Vector2(0.0, 30.0))
	for aire in devant:
		if not sous_pieds.has(aire):
			return true
	return false


## les Area2D du groupe DEGATS traversées par le segment a→b (positions globales)
func _dangers_sur_segment(a: Vector2, b: Vector2) -> Array:
	var params := PhysicsShapeQueryParameters2D.new()
	var seg := SegmentShape2D.new()
	seg.a = a
	seg.b = b
	params.shape = seg
	params.transform = Transform2D.IDENTITY
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var trouves := []
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 8):
		var col = hit.get("collider")
		if not (col is Area2D) or trouves.has(col):
			continue
		var danger: bool = col.is_in_group("DEGATS")
		if not danger:
			for child in col.get_children():
				if child.is_in_group("DEGATS"):
					danger = true
					break
		if danger:
			trouves.append(col)
	return trouves


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
	# (un mort ne rejoue pas sa mort, ni rien d'autre)
	if _is_dead():
		return
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
