@tool
extends Node2D
## ============================================================================
## SANG BOUILLANT — ÉBULLITION (v2, 1er oct. 2026) — talisman « Sang
## bouillant » (id "bouillant") : chaque coup d'épée ou de boule de sang qui
## touche un ennemi (et le laisse en vie) fait BOUILLIR son sang — une CHARGE de
## plus, des bulles qui bouillonnent sur lui. À la `CHARGES_MAX`-ième (la
## troisième ; essayé à deux coups le même jour, avec la boule en plus :
## « 2 c'est trop fort », Kaoru), il INSPIRE puis EXPLOSE : il prend `part`
## d'un coup d'épée (bonus compris), et ses voisins à
## moins de `rayon` px (sans mur entre eux) aussi. SANS RECUL (comme l'Ombre de
## sang : un recul renverrait des ennemis sur le héros). Sans coup pendant
## `duree_charge` s, les bulles crèvent et les charges retombent à zéro.
##
## La v1 (1er oct. 2026) faisait exploser les ennemis TUÉS, en cascade : « il
## sert à rien, il y a peu de groupes, et même en groupe la Lame de foudre le
## supplante » (Kaoru) → il frappe maintenant dans le combat contre un seul
## ennemi aussi (un boum tous les trois coups).
##
## Trois temps, dans ce nœud qui suit l'ennemi :
##   1. il BOUT (nœud Bulles, bouillon_sang.gdshader) : des bulles naissent,
##      crèvent et renaissent sur lui, plus nombreuses et plus grosses à chaque
##      charge (`BOUT_PAR_CHARGE`) ;
##   2. il INSPIRE (`DUREE_GONFLE`) : les bulles se fondent dans une boule de
##      sang qui enfle en tremblant ;
##   3. BOUM (nœud Explosion, explosion_sang.gdshader, `DUREE_EXPLOSION` s) :
##      un éclair bref, des traits de force, un anneau de feu creux qui se
##      déchire, l'onde de choc jusqu'au rayon des dégâts, des braises ; la
##      caméra tremble (`secousse`, 0 = pas du tout).
## Un seul bouillon par ennemi : il est rangé sur lui (méta "bouillon").
## Posé et rechargé par player.gd (`bouillant_charger`), sur chaque coup
## d'épée qui porte (animator.gd), chaque boule de sang qui touche
## (bloodball.gd, la Tornade de sang comprise) et chaque coup du double de
## l'Ombre de sang (ombre_sang.gd : la synergie voulue par Kaoru).
##
## POUR LE JUGER : ouvrir la scène et faire F6 (trois charges, boum, en boucle
## — seulement lancé seul). Les bulles se règlent sur le matériau du nœud
## Bulles, l'explosion sur celui du nœud Explosion.
## ============================================================================

## lancé seul (F6) : trois charges, boum, en boucle
@export var demo_boucle := true

## posés par le joueur (player.gd, `bouillant_charger`)
var joueur: CharacterBody2D = null
var cible: Node2D = null
var rayon := 180.0
var part := 1.0
var duree_charge := 3.0
var secousse := 6.0
## combien de fois son sang a bouilli (posé à 1 par le joueur au premier coup)
var charges := 1

const CHARGES_MAX := 3
## combien il bout (les bulles : nombre, taille) à 0, 1, 2, 3 charges — dès
## la première, il faut le voir (avec un tiers, une seule petite bulle)
const BOUT_PAR_CHARGE := [0.0, 0.45, 0.8, 1.0]
const META := "bouillon"
## l'inspiration, juste avant le boum (s)
const DUREE_GONFLE := 0.07
## l'explosion dure… (s) — les dernières braises comprises
const DUREE_EXPLOSION := 0.6
## les bulles crèvent en… (s), quand les charges retombent
const DUREE_CREVE := 0.15
## jusqu'où chercher le sol sous l'explosion (px) : la boule n'y passe pas
const SOL_MAX := 320.0

@onready var _bulles: ColorRect = $Bulles
@onready var _explosion: ColorRect = $Explosion

var _depuis_coup := 0.0         # depuis la dernière charge (s)
var _bout := 0.0                # la taille des bulles affichée (0 → 1)
var _temps := 0.0               # l'horloge du bouillonnement (s)
var _gonfle := -1.0             # l'inspiration en cours (s ; < 0 : pas encore)
var _boum := -1.0               # depuis le boum (s ; < 0 : pas encore)
var _retombe := -1.0            # les bulles crèvent sans boum (s ; < 0 : non)
var _sol := -1.0                # px sous le centre jusqu'au sol (< 0 : aucun)
var _demo := false
var _graine := 0.0


func _ready() -> void:
	_graine = randf() * 10.0
	if Engine.is_editor_hint():
		_appliquer()
		return
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
		_sol = 90.0
	elif is_instance_valid(cible):
		cible.set_meta(META, self)
		global_position = _centre(cible)
	if charges >= CHARGES_MAX:
		_gonfle = 0.0
	_appliquer()


## un coup d'épée de plus a porté sur l'ennemi
func ajouter_charge() -> void:
	if _gonfle >= 0.0 or _boum >= 0.0 or _retombe >= 0.0:
		return
	charges = mini(charges + 1, CHARGES_MAX)
	_depuis_coup = 0.0
	if charges >= CHARGES_MAX:
		_gonfle = 0.0


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _demo:
		_demo_tick(delta)
	elif _boum < 0.0:
		var vivant: bool = is_instance_valid(cible) and cible.hp > 0
		# il suit l'ennemi ; mort ou parti avant le boum : les bulles crèvent
		if vivant:
			global_position = _centre(cible)
		elif _retombe < 0.0 and _gonfle < 0.0:
			_retombe = 0.0
		_depuis_coup += delta
		if _gonfle < 0.0 and _retombe < 0.0 and _depuis_coup >= duree_charge:
			_retombe = 0.0
	if _retombe >= 0.0:
		_retombe += delta
		if _retombe >= DUREE_CREVE:
			_finir()
			return
	elif _gonfle >= 0.0 and _boum < 0.0:
		_gonfle += delta
		if _gonfle >= DUREE_GONFLE:
			_boum = 0.0
			_exploser()
	elif _boum >= 0.0:
		_boum += delta
		if _boum >= DUREE_EXPLOSION:
			_finir()
			return
	# les bulles grossissent à chaque charge, et bouillonnent plus vite
	_bout = move_toward(_bout, BOUT_PAR_CHARGE[clampi(charges, 0, CHARGES_MAX)], delta * 5.0)
	_temps += delta * (0.7 + 0.6 * _bout)
	_appliquer()


## F6 : une charge toutes les 0,35 s, boum, et on recommence
var _demo_t := 0.0
func _demo_tick(delta: float) -> void:
	_demo_t += delta
	if _gonfle < 0.0 and _boum < 0.0 and _demo_t >= 0.35:
		_demo_t = 0.0
		ajouter_charge()


func _finir() -> void:
	if _demo:
		charges = 1
		_bout = 0.0
		_gonfle = -1.0
		_boum = -1.0
		_retombe = -1.0
		_demo_t = 0.0
		_graine = randf() * 10.0
		return
	if is_instance_valid(cible) and cible.has_meta(META) and cible.get_meta(META) == self:
		cible.remove_meta(META)
	queue_free()


func _exploser() -> void:
	if _demo:
		return
	_sol = _chercher_sol()
	var cam := get_tree().get_first_node_in_group("Camera")
	if secousse > 0.0 and cam != null and cam.has_method("shake"):
		cam.shake(secousse, 9.0)
	if is_instance_valid(cible) and cible.has_meta(META) and cible.get_meta(META) == self:
		cible.remove_meta(META)      # un nouveau coup recommence un nouveau bouillon
	if joueur == null or not is_instance_valid(joueur):
		return
	var degats := maxi(roundi(joueur.animator.degats_du_coup() * part), 1)
	var espace := get_world_2d().direct_space_state
	var cercle := CircleShape2D.new()
	cercle.radius = rayon
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = cercle
	requete.transform = Transform2D(0.0, global_position)
	requete.collision_mask = 8               # la couche des monstres
	requete.collide_with_areas = false
	var touches := 0
	for resultat in espace.intersect_shape(requete, 32):
		var c: Node = resultat["collider"]
		if not (c is BaseAI):
			continue
		if c.hp <= 0 or c.invulnerable or not c.est_ennemi(joueur):
			continue
		# un mur entre eux ? (murs solides = couche 1, où est aussi le joueur) ;
		# l'ennemi qui explose est au centre, toujours touché
		var la := _centre(c)
		if c != cible:
			var vue := PhysicsRayQueryParameters2D.create(global_position, la, 1)
			vue.exclude = [joueur.get_rid()]
			if not espace.intersect_ray(vue).is_empty():
				continue
		touches += 1
		c.apply_damage(degats, global_position.x, "bouillant", false, joueur)
	print("[BOUILLANT] f=", Engine.get_physics_frames(), " ébullition : boum, ", touches,
		" ennemi(s) touché(s), ", degats, " dégâts chacun")


## le sol sous l'explosion (couche 1) : la boule ne passe pas dessous
func _chercher_sol() -> float:
	var q := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(0.0, SOL_MAX), 1)
	if joueur != null and is_instance_valid(joueur):
		q.exclude = [joueur.get_rid()]
	var touche := get_world_2d().direct_space_state.intersect_ray(q)
	return -1.0 if touche.is_empty() else float(touche["position"].y) - global_position.y


func _centre(c: Node2D) -> Vector2:
	if c is BaseAI and c.collision != null:
		return c.collision.global_position     # le milieu du corps, pas ses pieds
	return c.global_position


func _appliquer() -> void:
	if not is_node_ready():
		return
	var editeur := Engine.is_editor_hint()
	var g := clampf(_gonfle / DUREE_GONFLE, 0.0, 1.0) if _gonfle >= 0.0 else 0.0
	var creve := g
	if _retombe >= 0.0:
		creve = clampf(_retombe / DUREE_CREVE, 0.0, 1.0)
	# les bulles : elles grossissent à chaque charge, puis se fondent dans la
	# boule qui enfle (ou crèvent si les charges retombent)
	var mb := _bulles.material as ShaderMaterial
	if mb != null:
		_bulles.visible = editeur or _boum < 0.0
		mb.set_shader_parameter("taille", _bulles.size)
		mb.set_shader_parameter("graine", _graine)
		mb.set_shader_parameter("temps", _temps)
		mb.set_shader_parameter("bout", 0.8 if editeur else _bout)
		mb.set_shader_parameter("creve", 0.0 if editeur else creve)
	# l'explosion
	var me := _explosion.material as ShaderMaterial
	if me != null:
		_explosion.visible = not editeur and (g > 0.0 or _boum >= 0.0)
		me.set_shader_parameter("taille", _explosion.size)
		me.set_shader_parameter("origine", -_explosion.position)
		me.set_shader_parameter("gonfle", g)
		me.set_shader_parameter("t", _boum)
		me.set_shader_parameter("rayon", rayon)
		me.set_shader_parameter("sol", _sol)
		me.set_shader_parameter("graine", _graine)
