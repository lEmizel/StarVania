extends Node2D
## ============================================================================
## SCEAU DE RUNES (2 oct. 2026) — un cercle magique gravé
## au sol. Quelqu'un marche dessus (joueur ou monstre) : le sceau s'ARME — le
## cercle se trace, les runes s'allument une à une pendant `delai_armement` (le
## temps de fuir) — puis une COLONNE DE LUMIÈRE jaillit vers le ciel : ce qui est
## dedans est blessé et projeté vers le HAUT (le joueur perd `damage` cœur(s),
## les monstres prennent `degats_monstres`). Une fois armé, il part quoi qu'il
## arrive. Puis la colonne maigrit et s'éteint, des braises montent, et le sceau
## se rendort (`pause_apres` avant de pouvoir se réarmer).
##
## Le visuel : SCRIPT/SHADER/sceau_runes.gdshader, sur le nœud Sceau (couleurs,
## traits, lueur : sur son matériau). L'origine du nœud est le MILIEU DU SCEAU,
## AU RAS DU SOL : le poser sur le sol. Les zones (détection au sol, colonne qui
## blesse) sont fabriquées au démarrage d'après les réglages ci-dessous.
## Comme les piques : la détection est dans le groupe "DEGATS" (les monstres au
## sol la contournent, `monstres_l_evitent`) ; un même jet ne blesse qu'une fois.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (il s'arme, jaillit et se
## rendort, en boucle).
## ============================================================================

enum Etat { REPOS, ARME, JAILLIT, RETOMBE, PAUSE }

## Cœurs perdus par le joueur
@export var damage: int = 1
## Dégâts aux monstres (999999 = mort en un coup, comme les piques)
@export var degats_monstres: int = 999999
## les monstres au sol le voient comme un trou et le contournent
@export var monstres_l_evitent := true
## lancé seul (F6) : il s'arme, jaillit, se rendort, en boucle
@export var demo_boucle := true

@export_group("Rythme")
## le temps de fuir : le cercle se trace, les runes s'allument une à une
@export var delai_armement := 1.0
## la colonne blesse pendant…
@export var duree_colonne := 0.45
## puis elle maigrit et s'éteint en…
@export var duree_retombee := 0.65
## repos avant de pouvoir se réarmer
@export var pause_apres := 0.8

@export_group("Taille")
## demi-largeur du sceau (px)
@export var rayon := 70.0
@export var nb_runes := 8
@export var largeur_colonne := 110.0
@export var hauteur_colonne := 320.0
## la caméra tremble au jet (0 = pas du tout), si le joueur est à moins de 900 px
@export var secousse := 6.0

@onready var _sceau: ColorRect = $Sceau
@onready var _detection: Area2D = $Detection
@onready var _colonne: Area2D = $Colonne

var _etat := Etat.REPOS
var _t := 0.0
var _temps := 0.0
var _depuis_jet := -1.0
var _deja_touches := {}
var _demo := false
var _demo_t := 0.0


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * Vector2(0.5, 0.85)
	# joueur (couche 1) ET monstres (couches 2 et 4), comme les piques
	for zone in [_detection, _colonne]:
		zone.collision_layer = 0
		zone.collision_mask = 0b1011
	if monstres_l_evitent:
		_detection.add_to_group("DEGATS")
	_regler_formes()
	_appliquer()


## les zones et le rectangle du dessin, d'après les réglages
func _regler_formes() -> void:
	var sol := RectangleShape2D.new()
	sol.size = Vector2(rayon * 1.8, 24.0)
	var f_sol := CollisionShape2D.new()
	f_sol.shape = sol
	f_sol.position = Vector2(0.0, -12.0)
	_detection.add_child(f_sol)
	var haut := RectangleShape2D.new()
	haut.size = Vector2(largeur_colonne, hauteur_colonne)
	var f_haut := CollisionShape2D.new()
	f_haut.shape = haut
	f_haut.position = Vector2(0.0, -hauteur_colonne * 0.5)
	_colonne.add_child(f_haut)
	# le dessin : le sceau et toute la colonne, avec de la marge pour la lueur
	var w := maxf(rayon * 2.0, largeur_colonne) + 80.0
	var dessus := hauteur_colonne + 60.0
	_sceau.position = Vector2(-w * 0.5, -dessus)
	_sceau.size = Vector2(w, dessus + 40.0)
	var mat := _sceau.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("taille", _sceau.size)
		mat.set_shader_parameter("centre", Vector2(w * 0.5, dessus))
		mat.set_shader_parameter("rayon", rayon)
		mat.set_shader_parameter("nb_runes", nb_runes)
		mat.set_shader_parameter("largeur_colonne", largeur_colonne)
		mat.set_shader_parameter("hauteur_colonne", hauteur_colonne)


func _physics_process(delta: float) -> void:
	_t += delta
	if _depuis_jet >= 0.0:
		_depuis_jet += delta
	match _etat:
		Etat.REPOS:
			if _demo:
				_demo_t += delta
				if _demo_t >= 1.0:
					_demo_t = 0.0
					_passer(Etat.ARME)
			elif _quelqu_un_dessus():
				_passer(Etat.ARME)
		Etat.ARME:
			if _t >= delai_armement:
				_passer(Etat.JAILLIT)
		Etat.JAILLIT:
			_blesser()
			if _t >= duree_colonne:
				_passer(Etat.RETOMBE)
		Etat.RETOMBE:
			if _t >= duree_retombee:
				_passer(Etat.PAUSE)
		Etat.PAUSE:
			if _t >= pause_apres:
				_depuis_jet = -1.0
				_passer(Etat.REPOS)


func _process(delta: float) -> void:
	_temps += delta
	_appliquer()


func _passer(etat: Etat) -> void:
	_etat = etat
	_t = 0.0
	if etat == Etat.JAILLIT:
		_deja_touches.clear()
		_depuis_jet = 0.0
		_secouer()


## une entité compatible (qui sait encaisser des dégâts) est-elle sur le sceau ?
func _quelqu_un_dessus() -> bool:
	for body in _detection.get_overlapping_bodies():
		if body.has_method("apply_environment_damage") or body.has_method("apply_damage"):
			return true
	return false


## tant que la colonne brûle : ce qui est dedans est blessé, une fois par jet
## (un joueur en roulade ou en dash reste « à toucher » : seul un coup qui a
## PORTÉ est retenu, comme les piques)
func _blesser() -> void:
	for body in _colonne.get_overlapping_bodies():
		if _deja_touches.has(body):
			continue
		var porte = false
		if body.has_method("apply_environment_damage"):
			porte = body.apply_environment_damage(damage, Vector2.UP)
		elif body.has_method("apply_damage"):
			porte = body.apply_damage(degats_monstres, global_position.x, "sceau")
		if porte == true:
			_deja_touches[body] = true


func _secouer() -> void:
	if secousse <= 0.0:
		return
	var joueur := get_tree().get_first_node_in_group("Player") as Node2D
	if joueur == null or joueur.global_position.distance_to(global_position) > 900.0:
		return
	var cam := get_tree().get_first_node_in_group("Camera")
	if cam != null and cam.has_method("shake"):
		cam.shake(secousse, 10.0)


## ce que voit le shader, selon l'état
func _appliquer() -> void:
	var mat := _sceau.material as ShaderMaterial
	if mat == null:
		return
	var trace := 0.0
	var runes := 0.0
	var charge := 0.0
	var jaillit := 0.0
	var apres := 0.0
	match _etat:
		Etat.ARME:
			var k := clampf(_t / maxf(delai_armement, 0.001), 0.0, 1.0)
			trace = smoothstep(0.0, 0.3, k)
			runes = clampf((k - 0.18) / 0.7, 0.0, 1.0) * float(nb_runes)
			charge = smoothstep(0.6, 1.0, k)
		Etat.JAILLIT:
			trace = 1.0
			runes = float(nb_runes)
			charge = 1.0
			jaillit = clampf(_t / maxf(duree_colonne, 0.001), 0.0, 1.0)
		Etat.RETOMBE:
			trace = 1.0
			runes = float(nb_runes)
			charge = 1.0
			jaillit = 1.0
			apres = clampf(_t / maxf(duree_retombee, 0.001), 0.0, 1.0)
	mat.set_shader_parameter("trace", trace)
	mat.set_shader_parameter("runes", runes)
	mat.set_shader_parameter("charge", charge)
	mat.set_shader_parameter("jaillit", jaillit)
	mat.set_shader_parameter("apres", apres)
	mat.set_shader_parameter("depuis_jet", _depuis_jet)
	mat.set_shader_parameter("temps", _temps)
