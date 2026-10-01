@tool
extends Node2D
## ============================================================================
## SANG BOUILLANT (1er oct. 2026) — talisman « Sang bouillant » (id
## "bouillant") : chaque ennemi que le joueur tue se met à BOUILLIR, puis
## EXPLOSE : à moins de `rayon` px, sans mur entre eux, ses voisins prennent
## `degats` et sont repoussés. Ceux qui en meurent sont tués par le joueur :
## ils bouillent et explosent à leur tour — la cascade est voulue (et l'Essaim
## lâche ses chauves-souris sur chaque mort).
##
## Trois temps (`delai` en tout avant le boum) :
##   1. il BOUT : des bulles de sang gonflent sur son corps (nœud Bulles,
##      bouillon_sang.gdshader) ;
##   2. il INSPIRE (les `DUREE_GONFLE` dernières secondes) : les bulles se
##      fondent dans une boule de sang qui enfle en tremblant ;
##   3. BOUM (nœud Explosion, explosion_sang.gdshader, `DUREE_EXPLOSION` s) :
##      LÉGÈRE ET IMPACTANTE — un éclair bref, des traits de force qui
##      jaillissent et se détachent, un anneau de feu CREUX qui se déchire,
##      l'onde de choc jusqu'au rayon des dégâts, des braises (sans fumée) ;
##      la caméra tremble (`secousse`, 0 = pas du tout).
## v1 : l'éclaboussure de la boule de sang (« manque de punch ») ; v2 : jets
## et gouttes de sang (« trop goutte de sang, plus explosion tout court ») ;
## v3 : une boule de feu pleine (« trop grosse boule opaque, plus léger et
## impactant »).
##
## Posé par player.gd (`_bouillant_poser`, sur le signal `Player.monstre_tue`)
## au milieu du corps ; il suit le cadavre tant qu'il bout, puis reste où il a
## explosé.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (il bout, explose, en boucle —
## seulement lancé seul). Les bulles se règlent sur le matériau du nœud Bulles,
## l'explosion sur celui du nœud Explosion.
## ============================================================================

## lancé seul (F6) : bout, explose, en boucle
@export var demo_boucle := true

## posés par le joueur (player.gd, `_bouillant_poser`)
var joueur: CharacterBody2D = null
var cadavre: Node2D = null
var rayon := 180.0
var delai := 0.2
var degats := 70
var secousse := 6.0

## l'inspiration : la fin du `delai`, où la boule enfle (s)
const DUREE_GONFLE := 0.07
## l'explosion dure… (s) — les dernières braises comprises
const DUREE_EXPLOSION := 0.6
## jusqu'où chercher le sol sous l'explosion (px) : la boule n'y passe pas
const SOL_MAX := 320.0

@onready var _bulles: ColorRect = $Bulles
@onready var _explosion: ColorRect = $Explosion

var _t := 0.0
var _boum := -1.0          # depuis le boum (< 0 : pas encore)
var _sol := -1.0           # px sous le centre jusqu'au sol (< 0 : aucun)
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
	_appliquer()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	if _boum < 0.0:
		# il suit le cadavre tant qu'il bout
		if cadavre != null and is_instance_valid(cadavre):
			global_position = _centre(cadavre)
		if _t >= delai:
			_boum = 0.0
			_exploser()
	else:
		_boum += delta
		if _boum >= DUREE_EXPLOSION:
			if _demo:
				_t = 0.0
				_boum = -1.0
				_graine = randf() * 10.0
			else:
				queue_free()
				return
	_appliquer()


func _exploser() -> void:
	if _demo:
		return
	_sol = _chercher_sol()
	var cam := get_tree().get_first_node_in_group("Camera")
	if secousse > 0.0 and cam != null and cam.has_method("shake"):
		cam.shake(secousse, 9.0)
	if joueur == null or not is_instance_valid(joueur):
		return
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
		if not (c is BaseAI) or c == cadavre:
			continue
		if c.hp <= 0 or c.invulnerable or not c.est_ennemi(joueur):
			continue
		# un mur entre eux ? (murs solides = couche 1, où est aussi le joueur)
		var la := _centre(c)
		var vue := PhysicsRayQueryParameters2D.create(global_position, la, 1)
		vue.exclude = [joueur.get_rid()]
		if not espace.intersect_ray(vue).is_empty():
			continue
		touches += 1
		c.apply_damage(degats, global_position.x, "bouillant", true, joueur)
	print("[BOUILLANT] f=", Engine.get_physics_frames(), " explosion : ", touches,
		" voisin(s) touché(s), ", degats, " dégâts chacun")


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
	var avant_gonfle := maxf(delai - DUREE_GONFLE, 0.001)
	var gonfle := clampf((_t - avant_gonfle) / DUREE_GONFLE, 0.0, 1.0)
	# les bulles : elles gonflent, puis se fondent dans la boule qui enfle
	var mb := _bulles.material as ShaderMaterial
	if mb != null:
		_bulles.visible = editeur or _boum < 0.0
		mb.set_shader_parameter("taille", _bulles.size)
		mb.set_shader_parameter("graine", _graine)
		mb.set_shader_parameter("bout", 0.8 if editeur else clampf(_t / avant_gonfle, 0.0, 1.0))
		mb.set_shader_parameter("creve", 0.0 if editeur else gonfle)
	# l'explosion
	var me := _explosion.material as ShaderMaterial
	if me != null:
		_explosion.visible = not editeur and (gonfle > 0.0 or _boum >= 0.0)
		me.set_shader_parameter("taille", _explosion.size)
		me.set_shader_parameter("origine", -_explosion.position)
		me.set_shader_parameter("gonfle", gonfle)
		me.set_shader_parameter("t", _boum)
		me.set_shader_parameter("rayon", rayon)
		me.set_shader_parameter("sol", _sol)
		me.set_shader_parameter("graine", _graine)
