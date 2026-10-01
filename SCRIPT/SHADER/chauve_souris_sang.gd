@tool
extends Node2D
## ============================================================================
## CHAUVE-SOURIS DE SANG (1er oct. 2026) — talisman « Essaim » (id "essaim") :
## chaque ennemi TUÉ par le joueur (épée, boule, épines, brume, croissant… et
## les chauves-souris elles-mêmes : la chaîne est voulue) lâche
## `player.essaim_nombre` chauves-souris de son cadavre (player.gd,
## `_essaim_lacher`). Chacune :
##   1. JAILLIT du cadavre en éventail (`envol` s) ;
##   2. SUIT le joueur tant qu'elle n'a pas de proie (Kaoru, 1er oct. 2026) :
##      elle tourne AU-DESSUS de sa tête, à sa façon (`graine`) — jamais sur
##      sa tête ; sous un plafond trop bas, elle se range derrière lui — et
##      guette un ennemi toutes les `recherche` s ;
##   3. CHASSE l'ennemi vivant le plus proche (à moins de `portee` px, sans mur
##      entre eux au moment de choisir ; elle préfère une proie qu'aucune sœur
##      ne chasse), et fond dessus quand elle arrive à `plongee` px ;
##   4. le MORD (`degats`, sans recul) et éclate en gouttes.
##   Une chasse qui dure plus de `chasse_max` s (proie hors d'atteinte) : elle
##   lâche cette proie, la boude un moment et revient au joueur. Elle ne s'en
##   va (envol, fondu) que si le joueur disparaît ou retire le talisman.
## Pas de corps physique : elle mord quand son trajet passe à
## `morsure_distance` px du milieu de sa proie (elle peut naître pendant un
## rappel de physique, où l'on ne peut pas ajouter de zone).
##
## D'UN TABLEAU À L'AUTRE : le changement de tableau détruit tout (le niveau,
## le joueur, elles). `Player.essaim_en_vol` (l'autoload) tient leur compte :
## chacune s'y ajoute en naissant et s'en retire en mordant ou en s'en allant —
## PAS quand le tableau la détruit. Le joueur du tableau suivant relâche ce
## compte autour de lui, déjà en vol (player.gd, `_essaim_reprendre`, `deja_la`).
##
## Une chauve-souris DE PAPIER vue de côté (croquis de Kaoru) : le nœud se
## TOURNE dans le sens du vol (`_orienter`, en miroir quand elle vole vers la
## gauche) ; la silhouette est dans chauve_souris_forme.gdshaderinc.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (elle vole en huit, mord,
## renaît, en boucle — seulement lancée seule). Couleurs et encre : sur le
## matériau du nœud Corps ; vitesse, taille et battement : ci-dessous.
## ============================================================================

## vitesse de chasse (px/s) et nervosité de ses virages (px/s²)
@export var vitesse := 640.0
@export var acceleration := 2800.0
## à moins de cette distance de sa proie, elle fond droit dessus (px)
@export var plongee := 150.0
## durée du jaillissement hors du cadavre (s), avant la chasse
@export var envol := 0.22
## rayon dans lequel elle cherche une proie (px)
@export var portee := 800.0
## elle mord quand elle passe à cette distance du milieu de sa proie (px)
@export var morsure_distance := 24.0
## une chasse plus longue que ça (s) : la proie est lâchée, boudée `boude` s
@export var chasse_max := 3.0
@export var boude := 1.5
## elle guette une proie (et mesure le plafond) toutes les… (s)
@export var recherche := 0.1

@export_group("Suite du joueur")
## hauteur du point qu'elles entourent, au-dessus de ses pieds (px) : AU-DESSUS
## de sa tête (le haut de ses cheveux est vers 170, la couronne de la
## Vengeance vers 210)
@export var suite_hauteur := 270.0
## rayon de leur ronde autour de ce point (px : min, max), aplatie à `suite_aplat`
@export var suite_rayon := Vector2(70.0, 130.0)
@export var suite_aplat := 0.3
## au-dessus de lui, aucune ne vise plus bas que cette hauteur (px au-dessus
## de ses pieds) : elles ne se posent pas sur sa tête
@export var suite_degage := 215.0
## sous un plafond, elles gardent cette marge avec lui (px). S'il est trop bas
## pour qu'elles passent au-dessus de la tête, elles se rangent DERRIÈRE le
## joueur : à `suite_recul` px dans son dos, pas plus haut que `suite_hauteur_dos`
@export var suite_marge_plafond := 45.0
@export var suite_recul := 190.0
@export var suite_hauteur_dos := 120.0
## vitesse de croisière quand elles suivent (px/s) ; plus elles sont loin de
## leur place (il court à ~700 px/s, dashe à 1400), plus elles foncent : de
## `suite_vitesse` à `suite_loin.x` px jusqu'à `suite_rattrape` à `suite_loin.y`
@export var suite_vitesse := 480.0
@export var suite_loin := Vector2(120.0, 320.0)
@export var suite_rattrape := 1000.0
## elles se tiennent à cette distance les unes des autres (px)
@export var suite_ecart := 56.0
@export_group("")

## taille (1 = ~50 px de haut, ailes dressées), battement (rad/s), angle moyen
## des ailes et amplitude du battement (rad, + = levées)
@export var echelle := 1.0
@export var battement := 30.0
@export var repos := 0.35
@export var amplitude := 0.85
## lancée seule (F6) : vole sur place, mord, renaît, en boucle
@export var demo_boucle := true

## posés par le joueur (player.gd, `_essaim_lacher` / `_essaim_reprendre`)
var joueur: CharacterBody2D = null
var degats := 35
var vitesse_depart := Vector2(0.0, -480.0)
var graine := 0.0
## true : elle suivait déjà le joueur au tableau d'avant — elle naît en vol, à
## sa place dans la ronde (pas de jaillissement, pas de dépliage)
var deja_la := false

## la proie chassée (lue par les sœurs : chacune préfère une proie libre)
var cible: Node2D = null

const GROUPE := "chauve_souris_sang"
const TALISMAN := "essaim"
const DUREE_APPARITION := 0.14
const DUREE_MORSURE := 0.18
const DUREE_FUITE := 0.45
const TAILLE_BASE := Vector2(120.0, 110.0)

@onready var _corps: ColorRect = $Corps

var _vel := Vector2.ZERO
var _t := 0.0           # l'horloge du battement
var _age := 0.0         # depuis la naissance
var _fin := false
var _mord := false
var _t_fin := 0.0
var _demo := false
var _centre_demo := Vector2.ZERO
var _miroir := false
var _chasse_t := 0.0        # depuis le début de la chasse en cours
var _recherche_t := 0.0     # avant la prochaine recherche de proie
var _boudee: Node2D = null  # la proie lâchée, et pour combien de temps
var _boude_t := 0.0
var _ronde := 1.0           # vitesse angulaire de sa ronde (rad/s, signée)
var _plafond := INF         # hauteur libre au-dessus des pieds du joueur (px)
var _au_dessus := true      # sa place est au-dessus de la tête (sinon : dans le dos)
var _comptee := false       # elle est dans `Player.essaim_en_vol`


func _ready() -> void:
	if Engine.is_editor_hint():
		_appliquer()
		return
	add_to_group(GROUPE)
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		_centre_demo = get_viewport_rect().size * 0.5
		position = _centre_demo
	else:
		Player.essaim_en_vol += 1
		_comptee = true
	_vel = vitesse_depart
	# chacune tourne à sa vitesse, dans son sens
	_ronde = (0.8 + 0.5 * fmod(graine * 0.618, 1.0)) * (1.0 if fmod(graine, 2.0) < 1.0 else -1.0)
	_recherche_t = fmod(graine, recherche)
	if deja_la:
		_age = envol
		_vel = Vector2.ZERO
	_orienter(true)
	_appliquer()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	_age += delta
	if _demo:
		_demo_tick(delta)
		_appliquer()
		return
	if _fin:
		_t_fin += delta
		if _t_fin >= (DUREE_MORSURE if _mord else DUREE_FUITE):
			queue_free()
			return
		if not _mord:
			position += _vel * delta
		_appliquer()
		return
	if _age < envol:
		# elle jaillit du cadavre en éventail, freinée
		position += _vel * delta
		_vel = _vel.move_toward(Vector2.ZERO, 1400.0 * delta)
		_appliquer()
		return
	# plus de joueur (mort, respawn) ou talisman retiré : elle s'en va
	if not is_instance_valid(joueur) or not Player.talisman_equipe(TALISMAN):
		_partir()
		_appliquer()
		return
	_boude_t = maxf(_boude_t - delta, 0.0)
	_recherche_t -= delta
	var guet := _recherche_t <= 0.0
	if guet:
		_recherche_t = recherche
	if not _proie_valide(cible):
		cible = null
		_chasse_t = 0.0
		if guet:
			cible = _chercher_proie()
	if cible != null:
		_chasser(delta)
	else:
		if guet:
			_mesurer_plafond()
		_suivre(delta)
	_appliquer()


## la chasse : elle fonce sur sa proie et la mord au passage
func _chasser(delta: float) -> void:
	_chasse_t += delta
	if _chasse_t > chasse_max:
		# hors d'atteinte : elle la lâche, la boude, revient au joueur
		print("[ESSAIM] f=", Engine.get_physics_frames(), " ", cible.name, " lâché (chasse trop longue)")
		_boudee = cible
		_boude_t = boude
		cible = null
		_chasse_t = 0.0
		return
	var avant := global_position
	var vise := _centre(cible)
	var vers := vise - global_position
	if vers.length() < plongee:
		# tout près : elle fond droit dessus
		_vel = _vel.lerp(vers.normalized() * vitesse * 1.15, 1.0 - exp(-18.0 * delta))
	else:
		_vel = _vel.move_toward(vers.normalized() * vitesse, acceleration * delta)
	global_position += _vel * delta
	# son trajet de cette image est-il passé assez près de sa proie ?
	var au_plus_pres := Geometry2D.get_closest_point_to_segment(vise, avant, global_position)
	if au_plus_pres.distance_to(vise) <= morsure_distance:
		_mordre()


## la suite : elle rejoint sa place dans la ronde (`point_de_ronde`), en
## gardant ses distances avec ses sœurs ; loin de sa place (il a couru,
## dashé…), elle fonce
func _suivre(delta: float) -> void:
	var but := point_de_ronde()
	for s in get_tree().get_nodes_in_group(GROUPE):
		if s == self:
			continue
		var ecart: Vector2 = global_position - s.global_position
		var d := ecart.length()
		if d < suite_ecart and d > 0.001:
			but += ecart / d * (suite_ecart - d) * 1.5
	if _au_dessus:
		# ses sœurs peuvent la pousser, jamais sur la tête du joueur
		but.y = minf(but.y, joueur.global_position.y - suite_degage)
	var vers := but - global_position
	var dist := vers.length()
	var loin := clampf((dist - suite_loin.x) / maxf(suite_loin.y - suite_loin.x, 1.0), 0.0, 1.0)
	var v_max := lerpf(suite_vitesse, suite_rattrape, loin)
	# elle ralentit en arrivant sur son point (qui, lui, ne s'arrête jamais)
	var voulue := vers.normalized() * minf(v_max, dist * 4.0) if dist > 0.001 else Vector2.ZERO
	_vel = _vel.move_toward(voulue, acceleration * delta)
	global_position += _vel * delta


## SA PLACE dans la ronde, à cet instant : une ellipse aplatie AU-DESSUS de la
## tête du joueur. Si le plafond (`_plafond`) est trop bas pour ça, la ronde
## se resserre et se range DERRIÈRE lui, à hauteur d'épaule — jamais sur sa
## tête, jamais dans le plafond.
func point_de_ronde() -> Vector2:
	var pieds := joueur.global_position
	var ang := graine + _t * _ronde
	var rayon := lerpf(suite_rayon.x, suite_rayon.y, 0.5 + 0.5 * sin(_t * 0.7 + graine))
	var ry_max := suite_rayon.y * suite_aplat
	# le plus haut que le plafond laisse au CENTRE de la ronde
	var h := minf(suite_hauteur, _plafond - suite_marge_plafond - ry_max)
	_au_dessus = h - ry_max >= suite_degage
	if _au_dessus:
		return pieds + Vector2(cos(ang) * rayon, -h + sin(ang) * rayon * suite_aplat)
	var dos := -float(joueur.last_direction)
	h = clampf(h, 40.0, suite_hauteur_dos)
	return pieds + Vector2(dos * suite_recul + cos(ang) * rayon * 0.6, -h + sin(ang) * rayon * suite_aplat)


## la hauteur libre au-dessus du joueur : de ses pieds au premier mur (couche
## 1) à sa verticale ; INF = rien jusqu'en haut de la ronde
func _mesurer_plafond() -> void:
	var pieds := joueur.global_position
	var haut := suite_hauteur + suite_rayon.y * suite_aplat + suite_marge_plafond
	var q := PhysicsRayQueryParameters2D.create(pieds + Vector2(0.0, -40.0), pieds + Vector2(0.0, -haut), 1)
	q.exclude = [joueur.get_rid()]
	var touche := get_world_2d().direct_space_state.intersect_ray(q)
	_plafond = INF if touche.is_empty() else pieds.y - float(touche["position"].y)


## posée par le joueur à l'arrivée dans un tableau (`deja_la`) : droit à sa
## place dans la ronde
func se_placer() -> void:
	_mesurer_plafond()
	global_position = point_de_ronde()


func _mordre() -> void:
	var proie := cible
	_fin = true
	_mord = true
	_t_fin = 0.0
	_decompter()
	var porte = proie.apply_damage(degats, joueur.global_position.x, "essaim", false, joueur)
	print("[ESSAIM] f=", Engine.get_physics_frames(), " ", proie.name, " mordu : ", degats,
		" dégâts", "" if porte != false else " (n'a pas porté)")


func _partir() -> void:
	_fin = true
	_mord = false
	_t_fin = 0.0
	_decompter()
	var cote := signf(_vel.x)
	if cote == 0.0:
		cote = 1.0 if fmod(graine, 2.0) < 1.0 else -1.0
	_vel = Vector2(cote * 220.0, -340.0)


## elle quitte l'essaim (morsure, départ) — une seule fois. Détruite par un
## changement de tableau, elle ne passe PAS ici : le compte la garde.
func _decompter() -> void:
	if _comptee:
		_comptee = false
		Player.essaim_en_vol = maxi(Player.essaim_en_vol - 1, 0)


func _proie_valide(c: Node) -> bool:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree():
		return false
	if not (c is BaseAI) or c.hp <= 0 or c.invulnerable:
		return false
	return c.est_ennemi(joueur)


## l'ennemi vivant le plus proche, à portée, sans mur entre nous ; une proie
## qu'une sœur chasse déjà compte comme `portee` px plus loin (on la prend
## quand même s'il n'y a qu'elle) ; la proie boudée est ignorée
func _chercher_proie() -> Node2D:
	var espace := get_world_2d().direct_space_state
	var cercle := CircleShape2D.new()
	cercle.radius = portee
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = cercle
	requete.transform = Transform2D(0.0, global_position)
	requete.collision_mask = 8           # la couche des monstres
	requete.collide_with_areas = false
	var prises := []
	for s in get_tree().get_nodes_in_group(GROUPE):
		if s != self and is_instance_valid(s.cible):
			prises.append(s.cible)
	var meilleure: Node2D = null
	var meilleur_score := INF
	for resultat in espace.intersect_shape(requete, 32):
		var c: Node2D = resultat["collider"]
		if not _proie_valide(c):
			continue
		if _boude_t > 0.0 and c == _boudee:
			continue
		var la := _centre(c)
		var score := global_position.distance_to(la)
		if prises.has(c):
			score += portee
		if score >= meilleur_score:
			continue
		# un mur entre nous ? (murs solides = couche 1, où est aussi le joueur)
		var rayon := PhysicsRayQueryParameters2D.create(global_position, la, 1)
		rayon.exclude = [joueur.get_rid()]
		if not espace.intersect_ray(rayon).is_empty():
			continue
		meilleure = c
		meilleur_score = score
	return meilleure


func _centre(c: Node2D) -> Vector2:
	if c is BaseAI and c.collision != null:
		return c.collision.global_position     # le milieu du corps, pas ses pieds
	return c.global_position


## F6 : elle vole en huit autour du milieu de l'écran, mord au bout de 1,6 s,
## renaît
func _demo_tick(delta: float) -> void:
	position = _centre_demo + Vector2(sin(_t * 1.4) * 140.0, sin(_t * 2.8) * 36.0)
	_vel = Vector2(cos(_t * 1.4) * 196.0, cos(_t * 2.8) * 100.0)
	if _fin:
		_t_fin += delta
		if _t_fin >= DUREE_MORSURE + 0.3:
			_fin = false
			_age = 0.0
	elif _age >= 1.6:
		_fin = true
		_mord = true
		_t_fin = 0.0


## elle vole dans le sens de sa vitesse : tournée vers elle, et en MIROIR
## quand elle va vers la gauche (sinon elle volerait sur le dos). Le virage
## est lissé, sauf au changement de miroir, où l'angle saute avec lui.
func _orienter(sec: bool) -> void:
	if _vel.length_squared() < 1.0:
		return
	var vers_la_gauche := _vel.x < 0.0
	var angle := _vel.angle()
	if vers_la_gauche:
		angle += PI
	if vers_la_gauche != _miroir or sec:
		_miroir = vers_la_gauche
		scale.x = -1.0 if _miroir else 1.0
		rotation = angle
	else:
		rotation = lerp_angle(rotation, angle, 0.3)


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _corps.material as ShaderMaterial
	if mat == null:
		return
	var taille := TAILLE_BASE * echelle
	var phase := _t * battement + graine
	_corps.size = taille
	# le corps danse avec le battement : il monte quand les ailes s'abattent
	_corps.position = -taille * 0.5 + Vector2(0.0, 3.0 * echelle * cos(phase))
	_orienter(false)
	mat.set_shader_parameter("taille", taille)
	mat.set_shader_parameter("phase", phase)
	mat.set_shader_parameter("repos", repos)
	mat.set_shader_parameter("amplitude", amplitude)
	mat.set_shader_parameter("echelle", echelle)
	mat.set_shader_parameter("graine", graine)
	mat.set_shader_parameter("apparition", clampf(_age / DUREE_APPARITION, 0.0, 1.0))
	var duree_fin := DUREE_MORSURE if _mord else DUREE_FUITE
	mat.set_shader_parameter("fin", clampf(_t_fin / duree_fin, 0.0, 1.0) if _fin else 0.0)
	mat.set_shader_parameter("morsure", 1.0 if _mord else 0.0)
