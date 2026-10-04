extends Node2D
## ============================================================================
## GARDIENNES DE SANG (1er oct. 2026) — talisman « Gardiennes » (id
## "gardiennes"). Tant qu'il est porté, `nombre` gouttes de sang tournent
## autour du héros, sur une RONDE vue en perspective : elles passent DERRIÈRE
## lui (plus petites, plus sombres) puis DEVANT.
##   • elles BLESSENT l'ennemi qu'elles touchent — une part d'un coup d'épée,
##     bonus compris (player.gd, `gardiennes_degats`), sans recul ; un même
##     ennemi ne peut être blessé par elles qu'une fois toutes les `intervalle` s ;
##   • elles GARDENT le héros des tirs : un projectile ennemi qui fonce sur lui
##     (à moins de `garde_portee` px, et qui passera à moins de `garde_couloir`
##     px de lui) — la boule de feu du squelette bleu, et tout projectile du
##     groupe "projectiles_ennemis" qui sait `intercepter()` — et la goutte
##     libre la plus proche quitte la ronde, FOND dessus et ÉCLATE avec lui ;
##     elle se reforme ensuite à sa place dans la ronde en `recharge` s (on la
##     voit renaître, petite et pâle). Un tir qui passe sur une goutte de la
##     ronde éclate aussi ;
##   • un tir ANNONCÉ mais trop rapide pour être poursuivi (la comète de la
##     pluie d'étoiles) prévient lui-même : `garder_passage(tir, point, dans)` —
##     une goutte va SE POSTER sur sa trajectoire, et éclate avec lui quand il y
##     passe (`tir_arrive`).
## Deux rectangles dessinent le tout (gardiennes_sang.gdshader) : `Derriere`,
## sous le sprite du héros, et `Devant`, par-dessus ; chacun ne dessine que ce
## qui est de son côté. Ils partagent le même matériau dans la scène (le régler
## sur l'un règle l'autre) ; au lancement, `Derriere` en reçoit une copie, qui
## dessine l'autre côté.
## Enfant du joueur (player.gd, `_gardiennes_preparer`), créé une fois ; il se
## montre et se cache seul selon le talisman.
##
## POUR LES JUGER : ouvrir la scène et faire F6 — elles tournent au milieu de
## l'écran, et de vraies boules de feu arrivent de chaque côté toutes les
## `demo_cadence` s : une goutte fond dessus et éclate avec elle.
## ============================================================================

## lancé seul (F6) : la ronde au milieu de l'écran, des boules de feu à garder
@export var demo_boucle := true
## le centre de la ronde (repère du joueur : ses pieds à 0) — le milieu du corps
@export var centre := Vector2(0.0, -80.0)
@export_range(1, 4) var nombre := 2
## la ronde : ses demi-axes (px — large, aplatie par la perspective), son
## inclinaison (degrés) et sa vitesse (rad/s : 4,4 ≈ un tour en 1,4 s). Assez
## large pour traverser un ennemi qui nous frappe au corps à corps : un
## squelette frappe à 120-150 px de nous (à 82 px, elles ne l'atteignaient pas)
@export var rayons := Vector2(115.0, 28.0)
@export var inclinaison := -8.0
@export var vitesse := 4.4
@export_group("Blesser")
## une goutte touche ce qui passe à moins de… (px) ; un même ennemi ne peut être
## blessé par elles qu'une fois toutes les… (s)
@export var rayon_touche := 18.0
@export var intervalle := 0.5
@export_group("Garder")
## un tir est gardé quand il arrive à moins de `garde_portee` px du héros et
## qu'il passera à moins de `garde_couloir` px de lui ; la goutte fond dessus à
## `vitesse_garde` px/s
@export var garde_portee := 240.0
@export var garde_couloir := 110.0
@export var vitesse_garde := 1500.0
## une goutte qui a éclaté sur un tir se reforme en… (s)
@export var recharge := 4.0
@export_group("")
## (F6) une boule de feu toutes les… (s)
@export var demo_cadence := 1.8

const TALISMAN := "gardiennes"
const GROUPE_TIRS := "projectiles_ennemis"
## le groupe de ce nœud : les tirs annoncés y cherchent qui prévenir
const GROUPE := "gardiennes"
const COUCHE_MONSTRES := 8
const BOULE_DE_FEU := preload("res://SCRIPT/SPELL/projectile_feu.tscn")
## l'éclatement ; le gonflement d'une goutte qui redevient pleine ; l'écrasement
## d'une goutte qui touche (s)
const DUREE_ECLAT := 0.32
const DUREE_POP := 0.22
const DUREE_CHOC := 0.14
## une goutte qui a perdu son tir de vue (il a touché autre chose, il s'est
## éteint) se dissipe en… et se reforme en… (s)
const DUREE_DISSIPATION := 0.15
const RECHARGE_COURTE := 0.8
## elle n'ira pas plus loin que ça du centre (px) : le bord des rectangles
const PORTEE_MAX := Vector2(240.0, 160.0)
## (s) au plus, la poursuite d'un tir
const GARDE_MAX := 0.6
## une goutte postée attend son tir au plus… après l'heure annoncée (s)
const POSTE_PATIENCE := 0.25
## elle part AU DERNIER MOMENT : de quoi être à son poste au plus… avant le tir
## (s). Partie plus tôt, elle attendait immobile dans le vide.
const POSTE_AVANCE := 0.05
## elle part encore si elle doit arriver… après le tir, au plus (s) : elle
## l'arrête d'un peu loin (voir `tir_arrive`)
const POSTE_RETARD := 0.02
## la silhouette du héros vue du centre de la ronde : sa demi-largeur, et la
## hauteur du dessus de sa tête (px)
const SILHOUETTE := Vector2(45.0, 75.0)

enum { RONDE, GARDE, DISSIPE, RECHARGE, POSTE }

class Goutte:
	var etat := RONDE
	var t := 0.0                    # depuis le début de l'état en cours (s)
	var pos := Vector2.ZERO         # depuis le centre de la ronde (px)
	var sens := Vector2.RIGHT       # le sens de sa course
	var etirement := 1.0
	var cible: Node2D = null        # le tir sur lequel elle fond, ou qu'elle attend à son poste
	var poste := Vector2.ZERO       # (postée) le point du monde où elle attend son tir
	var poste_fin := 0.0            # (postée) elle n'attend pas plus longtemps que ça (s)
	var derriere := 0.0             # (postée) partie de derrière le héros : sa profondeur d'alors (< 0), gardée tant qu'elle est dans sa silhouette
	var attente := 0.0              # (recharge) avant de commencer à renaître (s)
	var duree_recharge := 0.0
	var eclat_t := -1.0             # depuis son éclatement (s ; < 0 : aucun)
	var eclat_global := Vector2.ZERO
	var choc_t := 10.0              # depuis son dernier coup porté (s)
	var pop_t := 10.0               # depuis qu'elle est (re)devenue pleine (s)

## posé par le joueur
var joueur: CharacterBody2D = null

@onready var _derriere: ColorRect = $Derriere
@onready var _devant: ColorRect = $Devant

var _gouttes: Array[Goutte] = []
var _angle := 0.0
var _temps := 0.0
var _presence := 0.0                # 0 → 1 : elles naissent quand on le porte
var _demo := false
var _demo_t := 0.0
var _demo_cote := 1.0
var _derniers_coups := {}           # id d'ennemi → instant de sa dernière blessure
var _requete := PhysicsShapeQueryParameters2D.new()
var _cercle := CircleShape2D.new()


func _ready() -> void:
	add_to_group(GROUPE)
	_demo = demo_boucle and get_parent() == get_tree().root
	for i in nombre:
		_gouttes.append(Goutte.new())
	# un seul matériau à régler (celui de Devant) ; Derriere en dessine l'autre côté
	if _devant.material != null:
		_derriere.material = _devant.material.duplicate()
		(_devant.material as ShaderMaterial).set_shader_parameter("devant", 1.0)
		(_derriere.material as ShaderMaterial).set_shader_parameter("devant", 0.0)
	_cercle.radius = rayon_touche
	_requete.shape = _cercle
	_requete.collision_mask = COUCHE_MONSTRES
	_requete.collide_with_areas = false
	if _demo:
		position = get_viewport_rect().size * 0.5
		_presence = 1.0
	else:
		position = centre
	visible = _presence > 0.0
	_appliquer()


func _physics_process(delta: float) -> void:
	var porte := _demo or (Player.talisman_equipe(TALISMAN) and Player.hp > 0)
	_presence = move_toward(_presence, 1.0 if porte else 0.0, delta / 0.25)
	visible = _presence > 0.0
	if not visible:
		# rangées : elles renaîtront entières, à leur place
		for g in _gouttes:
			g.etat = RONDE
			g.cible = null
			g.eclat_t = -1.0
		return
	_temps += delta
	_angle = wrapf(_angle + vitesse * delta, 0.0, TAU)
	if _demo:
		_demo_tick(delta)
	if porte:
		_guetter_tirs()
	for i in _gouttes.size():
		_faire_vivre(i, delta, porte)
	if _derniers_coups.size() > 48:
		_derniers_coups.clear()
	_appliquer()


# --------------------------------------------------------------------------
#  La ronde
# --------------------------------------------------------------------------

func _angle_de(i: int) -> float:
	return wrapf(_angle + TAU * float(i) / float(_gouttes.size()), 0.0, TAU)


## sa place sur la ronde à l'angle `theta` (depuis le centre, px) ; devant le
## héros quand sin(theta) > 0
func _sur_ronde(theta: float) -> Vector2:
	return Vector2(cos(theta) * rayons.x, sin(theta) * rayons.y).rotated(deg_to_rad(inclinaison))


func _tangente(theta: float) -> Vector2:
	return Vector2(-sin(theta) * rayons.x, cos(theta) * rayons.y).rotated(deg_to_rad(inclinaison)).normalized()


func _faire_vivre(i: int, delta: float, porte: bool) -> void:
	var g := _gouttes[i]
	var theta := _angle_de(i)
	g.t += delta
	g.choc_t += delta
	g.pop_t += delta
	if g.eclat_t >= 0.0:
		g.eclat_t += delta
		if g.eclat_t >= DUREE_ECLAT:
			g.eclat_t = -1.0
	match g.etat:
		RONDE:
			g.pos = _sur_ronde(theta)
			g.sens = _tangente(theta)
			g.etirement = 1.0
			if porte:
				_blesser(g)
				_toucher_tirs(g)
		GARDE:
			_fondre(g, delta)
		POSTE:
			_se_poster(g, delta)
		DISSIPE:
			if g.t >= DUREE_DISSIPATION:
				_recharger(g, 0.0, RECHARGE_COURTE)
		RECHARGE:
			g.pos = _sur_ronde(theta)
			g.sens = _tangente(theta)
			g.etirement = 1.0
			if g.t >= g.duree_recharge:
				g.etat = RONDE
				g.t = 0.0
				g.pop_t = 0.0


# --------------------------------------------------------------------------
#  Blesser
# --------------------------------------------------------------------------

## les ennemis sous la goutte (leur corps, couche des monstres) : blessés, une
## fois toutes les `intervalle` s chacun, sans recul
func _blesser(g: Goutte) -> void:
	if not is_instance_valid(joueur):
		return
	_requete.transform = Transform2D(0.0, global_position + g.pos)
	var espace := get_world_2d().direct_space_state
	for resultat in espace.intersect_shape(_requete, 8):
		var c = resultat["collider"]
		if not (c is BaseAI) or c.hp <= 0 or c.invulnerable or not c.est_ennemi(joueur):
			continue
		var id: int = c.get_instance_id()
		if _temps - float(_derniers_coups.get(id, -INF)) < intervalle:
			continue
		_derniers_coups[id] = _temps
		var degats: int = joueur.gardiennes_degats()
		var porte = c.apply_damage(degats, joueur.global_position.x, "gardiennes", false, joueur)
		g.choc_t = 0.0
		print("[GARDIENNES] f=", Engine.get_physics_frames(), " ", c.name, " touché : ", degats,
			" dégâts", "" if porte != false else " (n'a pas porté)")


# --------------------------------------------------------------------------
#  Garder
# --------------------------------------------------------------------------

func _faction_joueur() -> int:
	return BaseAI.faction_de(joueur) if is_instance_valid(joueur) else 1


## un tir ennemi encore en vol, qu'on sait arrêter
func _tir_valide(tir: Node) -> bool:
	if tir == null or not is_instance_valid(tir) or not tir.is_inside_tree():
		return false
	if not tir.has_method("intercepter"):
		return false
	if tir.has_method("interceptable") and not tir.interceptable():
		return false
	return BaseAI.faction_de(tir) != _faction_joueur()


func _vitesse_tir(tir: Node) -> Vector2:
	if "direction" in tir and "speed" in tir:
		return Vector2(tir.direction) * float(tir.speed)
	return Vector2.ZERO


## les tirs qui foncent sur le héros : la goutte libre la plus proche fond dessus
func _guetter_tirs() -> void:
	for tir in get_tree().get_nodes_in_group(GROUPE_TIRS):
		if not _tir_valide(tir) or _deja_garde(tir):
			continue
		var rel: Vector2 = tir.global_position - global_position
		if rel.length() > garde_portee:
			continue
		var v := _vitesse_tir(tir)
		if v.length_squared() < 1.0:
			continue
		var dir := v.normalized()
		# il s'éloigne, ou il passera loin de nous
		if dir.dot(-rel) <= 0.0 or absf(rel.cross(dir)) > garde_couloir:
			continue
		var g := _goutte_libre(tir.global_position)
		if g == null:
			return
		g.etat = GARDE
		g.t = 0.0
		g.cible = tir
		print("[GARDIENNES] f=", Engine.get_physics_frames(), " une goutte fond sur ", tir.name,
			" (à ", roundi(rel.length()), " px)")


func _deja_garde(tir: Node) -> bool:
	for g in _gouttes:
		if (g.etat == GARDE or g.etat == POSTE) and g.cible == tir:
			return true
	return false


## la goutte de la ronde la plus proche de `vers` — parmi celles qu'on peut
## lancer sans qu'elle saute de derrière le héros à devant lui sous nos yeux :
## de notre côté de la ronde, ou sur ses bouts (hors de sa silhouette)
func _goutte_libre(vers: Vector2) -> Goutte:
	var meilleure: Goutte = null
	var meilleure_d := INF
	for i in _gouttes.size():
		var g := _gouttes[i]
		if g.etat != RONDE:
			continue
		if sin(_angle_de(i)) < -0.25 and absf(g.pos.x) < 45.0:
			continue
		var d := (global_position + g.pos).distance_to(vers)
		if d < meilleure_d:
			meilleure_d = d
			meilleure = g
	return meilleure


## la goutte fond sur son tir (en visant un peu devant lui) et éclate avec lui
func _fondre(g: Goutte, delta: float) -> void:
	if not _tir_valide(g.cible) or g.t > GARDE_MAX:
		_dissiper(g)
		return
	var ici := global_position + g.pos
	var cible_pos: Vector2 = g.cible.global_position
	var vise := cible_pos + _vitesse_tir(g.cible) * (ici.distance_to(cible_pos) / vitesse_garde) * 0.6
	var vers := vise - ici
	if vers.length() > 0.01:
		g.sens = vers.normalized()
	var avant := ici
	g.pos += vers.limit_length(vitesse_garde * delta)
	g.etirement = 2.0
	_blesser(g)
	# son trajet de cette image est-il passé assez près du tir ?
	var pres := Geometry2D.get_closest_point_to_segment(cible_pos, avant, global_position + g.pos)
	if pres.distance_to(cible_pos) <= rayon_touche + 14.0:
		_intercepter(g, g.cible)
	elif absf(g.pos.x) > PORTEE_MAX.x or absf(g.pos.y) > PORTEE_MAX.y:
		_dissiper(g)


## un tir qui passe sur une goutte de la ronde éclate aussi
func _toucher_tirs(g: Goutte) -> void:
	var ici := global_position + g.pos
	for tir in get_tree().get_nodes_in_group(GROUPE_TIRS):
		if _tir_valide(tir) and tir.global_position.distance_to(ici) <= rayon_touche + 12.0:
			_intercepter(g, tir)
			return


func _intercepter(g: Goutte, tir: Node) -> void:
	var nom := String(tir.name)
	g.eclat_t = 0.0
	g.eclat_global = global_position + g.pos
	tir.intercepter()
	_recharger(g, DUREE_ECLAT, recharge)
	print("[GARDIENNES] f=", Engine.get_physics_frames(), " ", nom,
		" arrêté ; la goutte se reforme en ", recharge, " s")


## UN TIR ANNONCÉ, trop rapide pour être poursuivi (la comète de la pluie
## d'étoiles) : il passera au point `point` (monde) dans `dans` secondes. Le
## tir rappelle cette fonction À CHAQUE IMAGE tant que personne ne le garde :
## une goutte libre ne part que lorsque c'est l'heure POUR ELLE — juste le temps
## de son trajet, pour arriver quand le tir passe (partie dès l'annonce, elle
## attendait dans le vide). Rend vrai quand une goutte part ; le tir appellera
## `tir_arrive` en passant au point.
func garder_passage(tir: Node2D, point: Vector2, dans: float) -> bool:
	if _demo or not visible or _presence < 1.0 or tir == null:
		return false
	if _deja_garde(tir):
		return true
	var rel := point - global_position
	if absf(rel.x) > PORTEE_MAX.x or absf(rel.y) > PORTEE_MAX.y:
		return false
	var choisie: Goutte = null
	var trajet_choisi := INF
	var derriere_choisie := 0.0
	for i in _gouttes.size():
		var g := _gouttes[i]
		if g.etat != RONDE:
			continue
		var trajet := (global_position + g.pos).distance_to(point)
		var voyage := trajet / maxf(vitesse_garde, 1.0)
		if voyage > dans + POSTE_RETARD:
			continue              # elle n'y serait pas à temps
		if dans > voyage + POSTE_AVANCE:
			continue              # trop tôt pour elle
		if trajet < trajet_choisi:
			trajet_choisi = trajet
			choisie = g
			# derrière le héros : elle part quand même (sinon, seule goutte libre,
			# elle laissait passer le tir une fois sur huit), mais reste dessinée
			# derrière lui tant qu'elle est dans sa silhouette — elle n'en sort
			# qu'au-dessus de sa tête, sans sauter devant lui sous nos yeux
			var fond := sin(_angle_de(i))
			derriere_choisie = fond if (fond < -0.25 and absf(g.pos.x) < SILHOUETTE.x) else 0.0
	if choisie == null:
		return false
	choisie.etat = POSTE
	choisie.derriere = derriere_choisie
	choisie.t = 0.0
	choisie.cible = tir
	choisie.poste = point
	choisie.poste_fin = maxf(dans, 0.0) + POSTE_PATIENCE
	print("[GARDIENNES] f=", Engine.get_physics_frames(), " une goutte part se poster sur le passage de ", tir.name,
		" (", roundi(trajet_choisi), " px à faire, le tir y passe dans ", snappedf(dans, 0.01), " s)")
	return true


## le tir annoncé passe à son point gardé : si la goutte y est, elle l'arrête et
## éclate avec lui. Rend vrai s'il est arrêté (c'est au tir de s'éteindre).
func tir_arrive(tir: Node) -> bool:
	for g in _gouttes:
		if g.etat != POSTE or g.cible != tir:
			continue
		if (global_position + g.pos).distance_to(g.poste) > rayon_touche + 14.0:
			_dissiper(g)          # elle n'y était pas
			return false
		g.eclat_t = 0.0
		g.eclat_global = global_position + g.pos
		_recharger(g, DUREE_ECLAT, recharge)
		print("[GARDIENNES] f=", Engine.get_physics_frames(), " ", tir.name,
			" arrêté à son passage ; la goutte se reforme en ", recharge, " s")
		return true
	return false


## la goutte va à son poste (un point du monde : elle y reste même si le héros
## bouge) et y attend son tir
func _se_poster(g: Goutte, delta: float) -> void:
	if g.cible == null or not is_instance_valid(g.cible) or g.t > g.poste_fin:
		_dissiper(g)
		return
	var vers := g.poste - (global_position + g.pos)
	if vers.length() > 0.5:
		g.sens = vers.normalized()
	g.pos += vers.limit_length(vitesse_garde * delta)
	g.etirement = 2.0 if vers.length() > 8.0 else 1.0
	# sortie de la silhouette du héros : elle passe devant
	if g.derriere < 0.0 and (absf(g.pos.x) >= SILHOUETTE.x or g.pos.y < -SILHOUETTE.y):
		g.derriere = 0.0
	if absf(g.pos.x) > PORTEE_MAX.x or absf(g.pos.y) > PORTEE_MAX.y:
		_dissiper(g)


## son tir lui a échappé (il a touché autre chose, il s'est éteint) : elle se
## dissipe là où elle est, et se reforme vite dans la ronde
func _dissiper(g: Goutte) -> void:
	g.etat = DISSIPE
	g.t = 0.0
	g.cible = null


func _recharger(g: Goutte, attente: float, duree: float) -> void:
	g.etat = RECHARGE
	g.t = 0.0
	g.cible = null
	g.attente = attente
	g.duree_recharge = maxf(duree, attente + 0.05)


# --------------------------------------------------------------------------
#  Ce que voit le shader
# --------------------------------------------------------------------------

## sa taille (0 = absente, 1 = pleine)
func _forme(g: Goutte) -> float:
	match g.etat:
		DISSIPE:
			return 1.0 - clampf(g.t / DUREE_DISSIPATION, 0.0, 1.0)
		RECHARGE:
			# rien pendant que son éclatement claque, puis elle renaît, petite
			if g.t < g.attente:
				return 0.0
			var u := clampf((g.t - g.attente) / maxf(g.duree_recharge - g.attente, 0.01), 0.0, 1.0)
			return lerpf(0.3, 0.75, u)
	# (re)devenue pleine : elle gonfle un instant, puis se pose
	var v := clampf(g.pop_t / DUREE_POP, 0.0, 1.0)
	if v >= 1.0:
		return 1.0
	return 0.75 + 0.25 * v + 0.2 * sin(v * PI)


func _appliquer() -> void:
	var pos := PackedVector4Array()
	var mouv := PackedVector4Array()
	var eclat := PackedVector4Array()
	var etat := PackedVector4Array()
	var presence := smoothstep(0.0, 1.0, _presence)
	for i in 4:
		if i >= _gouttes.size():
			pos.append(Vector4.ZERO)
			mouv.append(Vector4(1.0, 0.0, 1.0, 0.0))
			eclat.append(Vector4(0.0, 0.0, -1.0, 0.0))
			etat.append(Vector4.ZERO)
			continue
		var g := _gouttes[i]
		var theta := _angle_de(i)
		var hors_ronde := g.etat == GARDE or g.etat == DISSIPE or g.etat == POSTE
		var profondeur := 1.0 if hors_ronde else sin(theta)
		if g.etat == POSTE and g.derriere < 0.0:
			profondeur = g.derriere
		pos.append(Vector4(g.pos.x, g.pos.y, profondeur, _forme(g) * presence))
		var sillage := clampf(g.pop_t / 0.25, 0.0, 1.0) if g.etat == RONDE else 0.0
		mouv.append(Vector4(g.sens.x, g.sens.y, g.etirement, sillage))
		var e := g.eclat_global - global_position
		eclat.append(Vector4(e.x, e.y, g.eclat_t / DUREE_ECLAT if g.eclat_t >= 0.0 else -1.0, theta))
		var choc := 1.0 - clampf(g.choc_t / DUREE_CHOC, 0.0, 1.0)
		etat.append(Vector4(0.5 if g.etat == RECHARGE else 1.0, choc, 0.0, 0.0))
	for rect in [_derriere, _devant]:
		var mat := (rect as ColorRect).material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("taille", (rect as ColorRect).size)
		mat.set_shader_parameter("temps", _temps)
		mat.set_shader_parameter("nombre", _gouttes.size())
		mat.set_shader_parameter("g_pos", pos)
		mat.set_shader_parameter("g_mouv", mouv)
		mat.set_shader_parameter("g_eclat", eclat)
		mat.set_shader_parameter("g_etat", etat)
		mat.set_shader_parameter("rayons", rayons)
		mat.set_shader_parameter("inclinaison", deg_to_rad(inclinaison))


# --------------------------------------------------------------------------
#  F6
# --------------------------------------------------------------------------

## de vraies boules de feu, de chaque côté à tour de rôle, droit sur la ronde
func _demo_tick(delta: float) -> void:
	_demo_t += delta
	if _demo_t < demo_cadence:
		return
	_demo_t = 0.0
	var b := BOULE_DE_FEU.instantiate()
	b.direction = Vector2(-_demo_cote, 0.0)
	b.faction = 0
	get_parent().add_child(b)
	b.global_position = global_position + Vector2(_demo_cote * 560.0, randf_range(-30.0, 30.0))
	_demo_cote = -_demo_cote
