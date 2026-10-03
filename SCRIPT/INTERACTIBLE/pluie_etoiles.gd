extends Node2D
## ============================================================================
## PLUIE D'ÉTOILES (2 oct. 2026) — une FAILLE ÉTOILÉE s'ouvre au-dessus d'une zone et y fait
## pleuvoir des comètes. Chaque comète est AVERTIE : sa trajectoire se dessine
## et une étoile marque le sol où elle tombera (`delai_avertissement`) — on
## slalome entre les marques. Simple et spectaculaire, la famille du pilier de
## foudre : lui te vise, elle arrose une zone.
##
##   • À L'ÉCRAN (VisibleOnScreenNotifier2D « Ecran »), la faille s'ouvre ; hors
##     de l'écran, elle se referme et ne fait plus rien ;
##   • toutes les `intervalle` s (± 30 %), une comète : sur le joueur
##     (`part_visee` des fois, s'il est dans la zone) ou au hasard dans la zone
##     (`largeur`) ; elle tombe sur le VRAI sol sous ce point (rayon vers le bas),
##     en biais depuis la faille, d'un côté ou de l'autre AU HASARD (jusqu'à
##     `pente`) ;
##   • l'impact blesse au-dessus de la marque (SCRIPT/SHADER/comete.gd) : le
##     joueur perd `damage` cœur(s) et il est repoussé, les monstres prennent
##     `degats_monstres` ; la roulade et le dash passent au travers.
##
## L'origine du nœud est le SOL au milieu de la zone ; la faille est à
## `hauteur_faille` au-dessus (sous un plafond, baisser la valeur).
##
## POUR LA JUGER : ouvrir la scène et faire F6 (la faille s'ouvre, les comètes
## pleuvent en boucle sur un sol imaginaire).
## ============================================================================

const COMETE := preload("res://SCRIPT/SHADER/comete.tscn")

## Cœurs perdus par le joueur touché
@export var damage: int = 1
## Dégâts aux monstres touchés (999999 = mort en un coup, comme les pièges)
@export var degats_monstres: int = 999999
## lancée seule (F6) : elle pleut en boucle
@export var demo_boucle := true

@export_group("Zone")
## la largeur de la zone arrosée (px)
@export var largeur := 900.0
## la faille, au-dessus du sol (px)
@export var hauteur_faille := 520.0

@export_group("Rythme")
## entre deux comètes (s, ± 30 %)
@export var intervalle := 0.55
## la première comète, après l'entrée à l'écran (s)
@export var premier_appel := 0.8
## une comète s'annonce pendant… avant de tomber : le temps de s'écarter (s)
@export var delai_avertissement := 0.9
## la part des comètes qui visent le joueur (s'il est dans la zone)
@export_range(0.0, 1.0, 0.01) var part_visee := 0.45

@export_group("Comètes")
## elles tombent en biais, au hasard vers la gauche ou la droite : au plus tant
## de px de côté par px de chute (0 = toutes à la verticale)
@export var pente := 0.45
## l'impact blesse à… de chaque côté de la marque (px)
@export var rayon_impact := 60.0
## la caméra tremble à chaque impact (0 = pas du tout)
@export var secousse := 4.0

@onready var _faille: ColorRect = $Faille
@onready var _ecran: VisibleOnScreenNotifier2D = $Ecran

var _attente := 0.0
var _actif_avant := false
var _eveil := 0.0
var _eclat := 0.0
var _eclat_x := 0.0
var _temps := 0.0
var _graine := 0.0
var _demo := false


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * Vector2(0.5, 0.88)
		hauteur_faille = minf(hauteur_faille, get_viewport_rect().size.y * 0.7)
	_graine = randf() * 50.0
	_attente = premier_appel
	# la faille et la zone surveillée, d'après les réglages
	var w := largeur + 200.0
	_faille.position = Vector2(-w * 0.5, -hauteur_faille - 90.0)
	_faille.size = Vector2(w, 180.0)
	_ecran.rect = Rect2(-largeur * 0.5, -hauteur_faille, largeur, hauteur_faille + 40.0)
	_appliquer()


func _physics_process(delta: float) -> void:
	var actif := _demo or _ecran.is_on_screen()
	if actif and not _actif_avant:
		_attente = premier_appel
	_actif_avant = actif
	_eveil = move_toward(_eveil, 1.0 if actif else 0.0, delta / (0.6 if actif else 1.0))
	_eclat = maxf(_eclat - delta / 0.35, 0.0)
	if not actif or _eveil < 1.0:
		return
	_attente -= delta
	if _attente <= 0.0:
		_attente = intervalle * randf_range(0.7, 1.3)
		_lancer()


func _process(delta: float) -> void:
	_temps += delta
	_appliquer()


## une comète : sur le joueur ou au hasard dans la zone, sur le vrai sol
func _lancer() -> void:
	var x := randf_range(-largeur * 0.5, largeur * 0.5)
	var j := get_tree().get_first_node_in_group("Player") as Node2D
	if not _demo and j != null and Player.hp > 0 and randf() < part_visee:
		var jx := j.global_position.x - global_position.x
		if absf(jx) <= largeur * 0.5:
			x = clampf(jx + randf_range(-50.0, 50.0), -largeur * 0.5, largeur * 0.5)
	var sol := global_position + Vector2(x, 0.0)
	if not _demo:
		var trouve := _sol_sous(global_position.x + x)
		if trouve == Vector2.INF:
			return                         # pas de sol sous ce point (un gouffre) : pas de comète
		sol = trouve
	var haut_faille := global_position.y - hauteur_faille
	var chute := sol.y - haut_faille
	# un biais au hasard, d'un côté ou de l'autre (avant, elles partaient toutes
	# dans le même sens) ; si le départ tombe hors de la faille, l'autre côté
	var biais := randf_range(-pente, pente)
	var depart := Vector2(sol.x - biais * chute, haut_faille)
	if absf(depart.x - global_position.x) > largeur * 0.5:
		depart.x = sol.x + biais * chute
	var c := COMETE.instantiate()
	c.demo_boucle = false
	c.depart = depart - sol
	c.delai = delai_avertissement
	c.damage = damage
	c.degats_monstres = degats_monstres
	c.rayon_impact = rayon_impact
	c.secousse = secousse
	var hote: Node = get_tree().current_scene
	if hote == null or _demo:
		hote = get_parent()
	hote.add_child(c)
	c.global_position = sol
	_eclat = 1.0
	_eclat_x = depart.x - global_position.x


## le sol (solide ou plateforme) sous la colonne `x`, de la faille vers le bas ;
## le joueur et les monstres ne comptent pas. INF : rien trouvé
func _sol_sous(x: float) -> Vector2:
	var depuis := Vector2(x, global_position.y - hauteur_faille + 10.0)
	var jusque := Vector2(x, global_position.y + 600.0)
	var exclus: Array[RID] = []
	for essai in 6:
		var rayon := PhysicsRayQueryParameters2D.create(depuis, jusque, 0b11)
		rayon.exclude = exclus
		var touche := get_world_2d().direct_space_state.intersect_ray(rayon)
		if touche.is_empty():
			return Vector2.INF
		if touche["collider"] is CharacterBody2D:
			exclus.append(touche["rid"])
			continue
		return touche["position"]
	return Vector2.INF


func _appliquer() -> void:
	var mat := _faille.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _faille.size)
	mat.set_shader_parameter("longueur", largeur)
	mat.set_shader_parameter("eveil", _eveil)
	mat.set_shader_parameter("eclat", _eclat)
	mat.set_shader_parameter("eclat_x", _eclat_x)
	mat.set_shader_parameter("temps", _temps)
	mat.set_shader_parameter("graine", _graine)
