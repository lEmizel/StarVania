extends Node2D
## ============================================================================
## PILIER DE FOUDRE (2 oct. 2026, piège imaginé par Kaoru : « quand il est
## visible à l'écran, il lance des éclairs qui viennent du ciel sur le joueur,
## avec un effet qui prévient à l'avance »).
##
## Tant que le pilier est À L'ÉCRAN (VisibleOnScreenNotifier2D « Ecran ») et le
## joueur en vie, il appelle la foudre toutes les `intervalle` secondes :
##   1. il se CHARGE (`duree_charge` : sa rune se remplit, le cristal s'embrase) ;
##   2. il APPELLE : un arc part de son cristal vers le ciel (l'arc de la Lame de
##      foudre, SCRIPT/SHADER/arc_foudre.tscn) ;
##   3. là où se tient le joueur À CET INSTANT (au sol sous lui), la FOUDRE DU
##      CIEL s'annonce (SCRIPT/SHADER/foudre_ciel.tscn) : marque crépitante et
##      trait de visée pendant `delai_avertissement` — le temps de s'écarter —
##      puis l'éclair tombe : la bande blesse joueur ET monstres.
## Le premier appel vient `premier_appel` s après l'entrée à l'écran.
##
## Le visuel du pilier : SCRIPT/SHADER/pilier_foudre.gdshader (nœud Pilier),
## PROVISOIRE (obélisque + cristal) — Kaoru pourra le remplacer par son dessin,
## les effets restent. L'origine du nœud est le PIED DU PILIER, au ras du sol.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (il se charge et appelle en
## boucle) ; la foudre du ciel se juge seule avec F6 sur foudre_ciel.tscn.
## ============================================================================

const FOUDRE_CIEL := preload("res://SCRIPT/SHADER/foudre_ciel.tscn")
const ARC_FOUDRE := preload("res://SCRIPT/SHADER/arc_foudre.tscn")

## Cœurs perdus par le joueur
@export var damage: int = 1
## Dégâts aux monstres pris dans l'éclair (999999 = mort en un coup, comme les pièges)
@export var degats_monstres: int = 999999
## lancé seul (F6) : il se charge et appelle en boucle
@export var demo_boucle := true

@export_group("Rythme")
## entre deux appels (s)
@export var intervalle := 2.6
## le premier appel, après l'entrée à l'écran (s)
@export var premier_appel := 1.0
## il se charge avant d'appeler (s) — compris dans l'intervalle
@export var duree_charge := 0.6
## l'éclair s'annonce pendant… avant de tomber : le temps de s'écarter (s)
@export var delai_avertissement := 0.9

@export_group("Éclair")
## largeur de la bande frappée (px)
@export var largeur_frappe := 70.0
## au-delà, le joueur est trop loin pour être visé (px)
@export var portee := 1800.0
## la caméra tremble quand l'éclair tombe (0 = pas du tout)
@export var secousse := 7.0

@onready var _pilier: ColorRect = $Pilier
@onready var _ecran: VisibleOnScreenNotifier2D = $Ecran

var _attente := 0.0          # avant le prochain appel (s)
var _visible_avant := false
var _eveil := 0.0
var _appel := 0.0
var _temps := 0.0
var _demo := false


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * Vector2(0.5, 0.85)
	_attente = premier_appel
	_appliquer(0.0)


func _physics_process(delta: float) -> void:
	var actif := _demo or (_ecran.is_on_screen() and _joueur_vise() != null)
	if actif and not _visible_avant:
		_attente = premier_appel           # il vient d'entrer à l'écran
	_visible_avant = actif
	_eveil = move_toward(_eveil, 1.0 if actif else 0.0, delta * 2.0)
	_appel = maxf(_appel - delta * 3.0, 0.0)
	if not actif:
		return
	_attente -= delta
	if _attente <= 0.0:
		_attente = intervalle
		_appeler()


func _process(delta: float) -> void:
	_temps += delta
	var charge := 0.0
	if _visible_avant or _demo:
		charge = clampf(1.0 - _attente / maxf(duree_charge, 0.001), 0.0, 1.0)
	_appliquer(charge)


## le joueur visé : en vie et à portée (sinon null)
func _joueur_vise() -> Node2D:
	var j := get_tree().get_first_node_in_group("Player") as Node2D
	if j == null or Player.hp <= 0:
		return null
	if j.global_position.distance_to(global_position) > portee:
		return null
	return j


## il appelle la foudre : un arc vers le ciel, et l'éclair qui s'annonce sous le joueur
func _appeler() -> void:
	_appel = 1.0
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = get_parent()
	var haut_pilier := global_position + Vector2(0.0, -222.0)
	var arc := ARC_FOUDRE.instantiate()
	arc.demo_boucle = false
	hote.add_child(arc)
	arc.tendre(haut_pilier, haut_pilier + Vector2(randf_range(-40.0, 40.0), -420.0))
	if _demo:
		return
	var j := _joueur_vise()
	if j == null:
		return
	var vp := get_viewport()
	var vue: Rect2 = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	# le point d'impact : TOUJOURS le sol sous le joueur, même s'il est en l'air
	# (Kaoru : « l'éclair devrait toujours aller jusqu'au sol même s'il me
	# détecte en l'air » — le rayon s'arrêtait à 900 px et, au-dessus d'un vide,
	# la foudre s'annonçait en plein air). On cherche loin sous l'écran, sols
	# solides ET plateformes traversables (couches 1 et 2) ; au-dessus d'un
	# gouffre sans fond, l'impact est posé sous le bas de la vue : l'éclair
	# traverse tout l'écran.
	var sol := Vector2(j.global_position.x, vue.end.y + 60.0)
	var rayon_sol := PhysicsRayQueryParameters2D.create(j.global_position + Vector2(0.0, -4.0),
		Vector2(j.global_position.x, vue.end.y + 2000.0), 0b11)
	rayon_sol.exclude = [j.get_rid()]
	var touche := get_world_2d().direct_space_state.intersect_ray(rayon_sol)
	if not touche.is_empty():
		sol = touche["position"]
	# du ciel jusqu'au sol : il part une HAUTEUR D'ÉCRAN au-dessus du haut de la
	# vue (Kaoru : « l'éclair ne démarre pas d'assez haut, si je saute je peux
	# voir le dessus » — la caméra monte avec le saut pendant l'avertissement)
	var f := FOUDRE_CIEL.instantiate()
	f.demo_boucle = false
	f.hauteur = maxf(sol.y - vue.position.y, 200.0) + vue.size.y
	f.largeur = largeur_frappe
	f.delai = delai_avertissement
	f.damage = damage
	f.degats_monstres = degats_monstres
	f.secousse = secousse
	hote.add_child(f)
	f.global_position = sol
	print("[PILIER] f=", Engine.get_physics_frames(), " appelle la foudre sur ", sol)


func _appliquer(charge: float) -> void:
	var mat := _pilier.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _pilier.size)
	mat.set_shader_parameter("base", -_pilier.position)
	mat.set_shader_parameter("eveil", _eveil)
	mat.set_shader_parameter("charge", charge)
	mat.set_shader_parameter("appel", _appel)
	mat.set_shader_parameter("temps", _temps)
