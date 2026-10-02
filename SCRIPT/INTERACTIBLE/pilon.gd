@tool
extends Node2D
## ============================================================================
## PILON (2 oct. 2026, idée de Kaoru) — un petit concasseur qui frappe le sol
## QUAND ON APPROCHE ; chaque coup lâche l'ONDE DE CHOC de l'attaque 2 du
## skeleton_boss (SCRIPT/PARTICLE/fx_shake.tscn : la même zone basse et large,
## le même déroulé, le même visuel) — on SAUTE au bon moment. Il apprend au
## joueur le coup du boss avant le combat.
##
##   • au repos, posé au sol ;
##   • le joueur à moins de `distance_eveil` (de côté, à son étage) : il MONTE
##     lentement (`duree_montee` — l'annonce : du gravier tombe), tremble en
##     haut (`duree_tenue`), puis S'ÉCRASE (`duree_chute`) : la caméra tremble,
##     la poussière gicle, l'onde part de son pied ;
##   • juste dessous au moment du coup : ÉCRASÉ (`damage` cœur, éjecté de côté) —
##     et l'onde de ce coup-là l'épargne (un seul cœur, pas deux) ;
##   • il reste au sol `repit` s, puis recommence tant que le joueur est près.
## Les monstres pris dans l'onde (ou dessous) prennent `degats_monstres`.
##
## Le dessin : SCRIPT/SHADER/pilon.gdshader (nœud Machine), SANS contour — il
## fait partie du décor (Kaoru) ; s'il ne va pas, Kaoru le redessinera. Le pilon
## n'a pas de collision : seuls le coup et l'onde comptent.
## L'origine du nœud est le SOL sous le pilon.
## @tool : dans l'ÉDITEUR, il se montre à sa VRAIE taille (`echelle`, `levee`),
## au repos, et suit les réglages en direct (Kaoru : « je ne peux pas voir sa
## vraie taille en éditeur ») ; tout le jeu (joueur, coups, onde) reste au jeu.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (il frappe en boucle).
## ============================================================================

enum Etat { REPOS, MONTE, TIENT, CHUTE, AU_SOL }

const ONDE := preload("res://SCRIPT/PARTICLE/fx_shake.tscn")

## Cœurs perdus par le joueur (écrasé, ou pris par l'onde)
@export var damage: int = 1
## Dégâts aux monstres (999999 = mort en un coup, comme les pièges)
@export var degats_monstres: int = 999999
## lancé seul (F6) : il frappe en boucle
@export var demo_boucle := true

@export_group("Déclenchement")
## il s'éveille quand le joueur est à moins de… de lui, de côté (px)
@export var distance_eveil := 380.0

@export_group("Rythme")
## il monte en… (s) — c'est l'annonce
@export var duree_montee := 0.9
## il tremble en haut pendant… (s)
@export var duree_tenue := 0.25
## il s'écrase en… (s)
@export var duree_chute := 0.09
## il reste au sol… avant de recommencer (s)
@export var repit := 0.8

@export_group("Onde")
## la largeur de l'onde (px) — 1111 : celle du boss
@export var largeur_onde := 1111.0
## la caméra tremble au coup (0 = pas du tout)
@export var secousse := 9.0

@export_group("Taille")
## la machine est dessinée à l'échelle 1 ; 0,5 = deux fois plus petite (Kaoru :
## « divise par 2 la taille de la machine »). L'onde garde la largeur du boss
@export var echelle := 0.5
## il se soulève de… (px du dessin : à l'écran, × `echelle`)
@export var levee := 120.0

const LARGEUR_BLOC := 84.0
const HAUTEUR_ECRASE := 90.0      # sous le bloc, jusqu'à cette hauteur : écrasé (px)

@onready var _machine: ColorRect = $Machine

var _etat := Etat.REPOS
var _t := 0.0
var _temps := 0.0
var _levee := 0.0
var _impact := 0.0
var _demo := false


func _ready() -> void:
	_demo = demo_boucle and not Engine.is_editor_hint() and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * Vector2(0.5, 0.85)
	_poser()
	_appliquer()


## le rectangle du dessin, à la taille voulue (aussi dans l'éditeur)
func _poser() -> void:
	if _machine == null:
		return
	var h := levee + 62.0 + 14.0 + 34.0 + levee + 30.0
	_machine.size = Vector2(220.0, h + 20.0)
	_machine.scale = Vector2(echelle, echelle)
	_machine.position = Vector2(-110.0, -h) * echelle


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	_impact = maxf(_impact - delta / 0.6, 0.0)
	match _etat:
		Etat.REPOS:
			_levee = 0.0
			if (_demo and _t > 0.8) or (not _demo and _joueur_proche()):
				_passer(Etat.MONTE)
		Etat.MONTE:
			var k := clampf(_t / maxf(duree_montee, 0.01), 0.0, 1.0)
			_levee = levee * (1.0 - pow(1.0 - k, 2.0))
			if k >= 1.0:
				_passer(Etat.TIENT)
		Etat.TIENT:
			_levee = levee
			if _t >= duree_tenue:
				_passer(Etat.CHUTE)
		Etat.CHUTE:
			var k := clampf(_t / maxf(duree_chute, 0.01), 0.0, 1.0)
			_levee = levee * (1.0 - k * k)
			if k >= 1.0:
				_levee = 0.0
				_frapper()
				_passer(Etat.AU_SOL)
		Etat.AU_SOL:
			_levee = 0.0
			if _t >= repit:
				_passer(Etat.REPOS)


func _process(delta: float) -> void:
	_temps += delta
	if Engine.is_editor_hint():
		_poser()                         # dans l'éditeur, il suit les réglages en direct
	_appliquer()


func _passer(etat: Etat) -> void:
	_etat = etat
	_t = 0.0


func _joueur_proche() -> bool:
	var j := get_tree().get_first_node_in_group("Player") as Node2D
	if j == null or Player.hp <= 0:
		return false
	var d := j.global_position - global_position
	return absf(d.x) <= distance_eveil and d.y > -300.0 and d.y < 150.0


## le coup : ce qui est sous le bloc est écrasé, puis l'onde part de son pied
func _frapper() -> void:
	_impact = 1.0
	var ecrase: Node = null
	if not _demo:
		var forme := RectangleShape2D.new()
		forme.size = Vector2(LARGEUR_BLOC * 0.9, HAUTEUR_ECRASE) * echelle
		var requete := PhysicsShapeQueryParameters2D.new()
		requete.shape = forme
		requete.transform = Transform2D(0.0, global_position + Vector2(0.0, -HAUTEUR_ECRASE * 0.5 * echelle))
		requete.collision_mask = 0b1011
		requete.collide_with_areas = false
		for resultat in get_world_2d().direct_space_state.intersect_shape(requete, 16):
			var corps = resultat["collider"]
			if corps.has_method("apply_environment_damage"):
				var cote := signf((corps as Node2D).global_position.x - global_position.x)
				if cote == 0.0:
					cote = 1.0
				if corps.apply_environment_damage(damage, Vector2(cote, -0.6).normalized()):
					ecrase = corps
			elif corps.has_method("apply_damage"):
				corps.apply_damage(degats_monstres, global_position.x, "pilon")
	# l'onde du boss : sans camp, elle blesse le joueur ET les monstres ; celui qui
	# vient d'être écrasé est son « lanceur » : elle l'épargne
	var onde := ONDE.instantiate()
	onde.faction = -1
	onde.damage = damage
	onde.degats_monstres = degats_monstres
	onde.tireur = ecrase
	var cs := onde.get_node("Area2D/CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is RectangleShape2D:
		var r := (cs.shape as RectangleShape2D).duplicate() as RectangleShape2D
		r.size.x = largeur_onde
		cs.shape = r
	var hote: Node = get_tree().current_scene
	if hote == null or _demo:
		hote = get_parent()
	hote.add_child(onde)
	onde.global_position = global_position
	if secousse > 0.0 and not _demo:
		var cam := get_tree().get_first_node_in_group("Camera")
		if cam != null and cam.has_method("shake"):
			cam.shake(secousse, 10.0)


func _appliquer() -> void:
	if _machine == null:
		return
	var mat := _machine.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _machine.size)
	mat.set_shader_parameter("sol", -_machine.position / echelle)
	mat.set_shader_parameter("levee", _levee)
	mat.set_shader_parameter("levee_max", levee)
	mat.set_shader_parameter("tremble", 1.0 if _etat == Etat.TIENT else 0.0)
	mat.set_shader_parameter("poussiere", 1.0 if _etat == Etat.MONTE or _etat == Etat.TIENT else 0.0)
	mat.set_shader_parameter("impact", _impact)
	mat.set_shader_parameter("temps", _temps)
