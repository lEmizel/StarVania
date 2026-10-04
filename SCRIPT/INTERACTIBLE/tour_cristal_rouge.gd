extends Node2D
## ============================================================================
## TOUR AU CRISTAL ROUGE (4 oct. 2026) : une variante du pilier de foudre. Son
## cristal VISE LE JOUEUR et lui tire dessus, en ligne droite, un éclair rouge.
##
## Tant que la tour est À L'ÉCRAN (VisibleOnScreenNotifier2D « Ecran ») et le
## joueur en vie et à portée, son cristal se tourne vers lui. Toutes les
## `intervalle` secondes, si elle le VOIT (aucun mur entre eux) :
##   1. elle VISE (`duree_visee`) : elle se charge, et une ligne pointillée part
##      du cristal et SUIT le joueur ;
##   2. la visée se VERROUILLE (`delai_avertissement`) : la ligne ne bouge plus,
##      elle se remplit et presse — le temps de sortir de la ligne ;
##   3. l'ÉCLAIR part le long de cette ligne, du cristal jusqu'au premier mur
##      derrière le point visé : toute la bande blesse joueur ET monstres.
## La réponse : sortir de la ligne une fois qu'elle est figée (s'écarter,
## sauter), ou se mettre derrière un mur — elle ne commence à viser que si elle
## voit le joueur, et son éclair s'arrête au premier mur. Il traverse les
## plateformes qu'on traverse soi-même.
## Le premier tir vient `premier_appel` s après l'entrée à l'écran.
##
## Le visuel : le MÊME pilier que le pilier de foudre (son dessin, posé par
## SCRIPT/SHADER/pilier_foudre.gdshader, nœud Pilier), avec un joyau rouge qui
## pivote vers sa cible ; l'éclair et sa visée : SCRIPT/SHADER/eclair_rouge.tscn.
## L'origine du nœud est le PIED DU PILIER, au ras du sol.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (elle vise un point qui se
## promène, se verrouille et tire, en boucle).
## ============================================================================

const ECLAIR := preload("res://SCRIPT/SHADER/eclair_rouge.tscn")
const HAUTEUR_JOYAU := 372.0     # le milieu du joyau, au-dessus du pied (px) : l'éclair part de là
## les murs et les sols pleins (pas les plateformes qu'on traverse) : ils cachent
## le joueur et arrêtent l'éclair
const MASQUE_MURS := 0b1
## sans mur sur son chemin, l'éclair va jusque-là (px)
const TIR_MAX := 2600.0
enum Phase { VEILLE, VISEE, VERROU }

## Cœurs perdus par le joueur
@export var damage: int = 1
## Dégâts aux monstres pris dans l'éclair (999999 = mort en un coup, comme les pièges)
@export var degats_monstres: int = 999999
## lancée seule (F6) : elle vise et tire en boucle
@export var demo_boucle := true

@export_group("Rythme")
## entre deux tirs (s)
@export var intervalle := 2.6
## le premier tir, après l'entrée à l'écran (s)
@export var premier_appel := 1.0
## elle vise en suivant le joueur pendant… (s) — compris dans l'intervalle
@export var duree_visee := 0.7
## la visée reste figée pendant… avant l'éclair : le temps de sortir de la ligne (s)
@export var delai_avertissement := 0.6

@export_group("Éclair")
## largeur de la bande frappée (px)
@export var largeur_frappe := 46.0
## au-delà, le joueur est trop loin pour être visé (px)
@export var portee := 1800.0
## la caméra tremble quand l'éclair part (0 = pas du tout)
@export var secousse := 5.0
## le rouge du cristal, de sa lumière et de l'éclair
@export var couleur := Color(1.0, 0.13, 0.16)
## le cœur de l'éclair et les éclats du cristal
@export var couleur_coeur := Color(1.0, 0.88, 0.84)

@onready var _pilier: ColorRect = $Pilier
@onready var _ecran: VisibleOnScreenNotifier2D = $Ecran

var _eclair: Node2D
var _phase := Phase.VEILLE
var _attente := 0.0          # avant la prochaine visée (s)
var _t := 0.0                # depuis le début de la phase (s)
var _actif_avant := false
var _eveil := 0.0
var _appel := 0.0
var _temps := 0.0
var _tourne := 0.0           # l'angle du joyau (0 : debout)
var _cible := Vector2.ZERO   # le point visé (le milieu du corps du joueur)
var _demo := false


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * Vector2(0.25, 0.9)
	_attente = premier_appel
	_eclair = ECLAIR.instantiate()
	_eclair.demo_boucle = false
	add_child(_eclair)
	_eclair.tire.connect(func() -> void: _appel = 1.0)
	_appliquer(0.0)


func _physics_process(delta: float) -> void:
	var j := _joueur_vise()
	var actif := _demo or (_ecran.is_on_screen() and j != null)
	if actif and not _actif_avant and _phase == Phase.VEILLE:
		_attente = premier_appel           # elle vient d'entrer à l'écran
	_actif_avant = actif
	_eveil = move_toward(_eveil, 1.0 if actif else 0.0, delta * 2.0)
	_appel = maxf(_appel - delta * 3.0, 0.0)
	var joyau := _joyau()
	if _demo:
		var vue := get_viewport_rect().size
		_cible = Vector2(vue.x * (0.7 + 0.12 * sin(_temps * 0.9)), vue.y * (0.72 + 0.16 * sin(_temps * 1.7)))
	elif j != null and _phase != Phase.VERROU:
		_cible = j.centre_corps() if j.has_method("centre_corps") else j.global_position
	# son joyau se tourne vers sa cible tant qu'elle la regarde, et se redresse sinon
	var voulu := 0.0
	if actif:
		voulu = wrapf((_cible - joyau).angle() - PI * 0.5, -PI * 0.5, PI * 0.5)
	_tourne = lerp_angle(_tourne, voulu, clampf(delta * 8.0, 0.0, 1.0))

	match _phase:
		Phase.VEILLE:
			if not actif:
				return
			_attente -= delta
			# elle ne commence à viser que si elle voit le joueur
			if _attente <= 0.0 and not _eclair.occupe() and (_demo or _voit(joyau, j)):
				_phase = Phase.VISEE
				_t = 0.0
		Phase.VISEE:
			_t += delta
			_regler_eclair()
			_eclair.viser(joyau, _bout_du_tir(joyau, j)["position"])
			if _t >= duree_visee:
				var bout := _bout_du_tir(joyau, j)
				_eclair.verrouiller(joyau, bout["position"], bout["normal"])
				_phase = Phase.VERROU
				_t = 0.0
				print("[TOUR ROUGE] f=", Engine.get_physics_frames(), " verrouille ", (bout["position"] as Vector2).round())
		Phase.VERROU:
			_t += delta
			if _t >= delai_avertissement:
				_phase = Phase.VEILLE
				# le reste de l'intervalle, et au moins le temps que l'éclair s'éteigne
				_attente = maxf(intervalle - duree_visee - delai_avertissement, 0.9)


func _process(delta: float) -> void:
	_temps += delta
	var charge := 0.0
	match _phase:
		Phase.VISEE:
			charge = clampf(_t / maxf(duree_visee, 0.001), 0.0, 1.0)
		Phase.VERROU:
			charge = 1.0
	_appliquer(charge)


## le milieu du joyau, dans le monde (à l'échelle du nœud)
func _joyau() -> Vector2:
	return to_global(Vector2(0.0, -HAUTEUR_JOYAU))


## le joueur visé : en vie et à portée (sinon null)
func _joueur_vise() -> Node2D:
	var j := get_tree().get_first_node_in_group("Player") as Node2D
	if j == null or Player.hp <= 0:
		return null
	if j.global_position.distance_to(global_position) > portee:
		return null
	return j


## aucun mur entre le joyau et le joueur ?
func _voit(joyau: Vector2, j: Node2D) -> bool:
	if j == null:
		return false
	var rayon := PhysicsRayQueryParameters2D.create(joyau, _cible, MASQUE_MURS)
	rayon.exclude = [j.get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(rayon).is_empty()


## où finit le tir : le premier mur sur la ligne joyau → cible, prolongée
## (sans mur : loin hors de l'écran). Rend sa position et la normale du mur.
func _bout_du_tir(joyau: Vector2, j: Node2D) -> Dictionary:
	var sens := (_cible - joyau).normalized()
	if sens == Vector2.ZERO:
		sens = Vector2.DOWN
	var loin := joyau + sens * TIR_MAX
	if _demo:
		return {"position": _cible, "normal": Vector2.LEFT}
	var rayon := PhysicsRayQueryParameters2D.create(joyau, loin, MASQUE_MURS)
	if j != null:
		rayon.exclude = [j.get_rid()]
	var touche := get_world_2d().direct_space_state.intersect_ray(rayon)
	if touche.is_empty():
		return {"position": loin, "normal": Vector2.ZERO}
	return {"position": touche["position"], "normal": touche["normal"]}


func _regler_eclair() -> void:
	_eclair.largeur = largeur_frappe
	_eclair.delai = delai_avertissement
	_eclair.damage = damage
	_eclair.degats_monstres = degats_monstres
	_eclair.secousse = secousse
	_eclair.couleur = couleur
	_eclair.couleur_coeur = couleur_coeur


func _appliquer(charge: float) -> void:
	var mat := _pilier.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _pilier.size)
	mat.set_shader_parameter("base", -_pilier.position)
	mat.set_shader_parameter("hauteur_cristal", HAUTEUR_JOYAU)
	mat.set_shader_parameter("eveil", _eveil)
	mat.set_shader_parameter("charge", charge)
	mat.set_shader_parameter("appel", _appel)
	mat.set_shader_parameter("temps", _temps)
	mat.set_shader_parameter("tourne", _tourne)
	mat.set_shader_parameter("couleur", couleur_coeur)
	mat.set_shader_parameter("couleur_foudre", couleur)
