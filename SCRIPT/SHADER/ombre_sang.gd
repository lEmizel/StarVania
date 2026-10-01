extends Node2D
## ============================================================================
## OMBRE DE SANG (v2, 1er oct. 2026) — talisman « Ombre de sang » (id "ombre") :
## quand l'épée touche un ennemi, un double de sang du héros SURGIT DERRIÈRE
## LUI (de l'autre côté), tourné vers le héros, refait le même coup en miroir
## et le frappe à son tour pour `part` des dégâts d'un coup (bonus compris),
## SANS RECUL : un recul renvoyait l'ennemi sur le héros, qui prenait alors un
## coup de contact (Kaoru) — l'ennemi garde le recul du coup du héros, il
## s'éloigne. Puis le double se dissout. Un double par
## coup d'épée (derrière le premier ennemi touché ; son slash prend tout ce
## qu'il couvre).
##
## v1 : le double suivait le héros avec 0,25 s de retard et rejouait ses coups
## au même endroit — en jeu il ne touchait jamais : le coup du héros avait déjà
## repoussé l'ennemi hors de portée (Kaoru : « il touche jamais personne » ; mon
## test figeait les monstres, sans recul). Ici il frappe là où l'ennemi EST :
## jusqu'à son coup, le double reste collé derrière lui (à `ecart` px du bord
## de son corps) pendant qu'il recule, et s'arrête avant un mur.
##
## Il rejoue l'animation d'attaque du héros depuis le début (même dessin, teinté
## de sang par ombre_sang.gdshader) et frappe quand elle atteint l'image où le
## héros a touché (`image_coup`), pas avant `delai_min` s : son slash (le slash
## en shader, en rouge) et ses dégâts partent ensemble. Posé par player.gd
## (`ombre_surgir`, appelé par animator.gd quand un coup d'épée porte).
## ============================================================================

const TEINTE := preload("res://SCRIPT/SHADER/ombre_sang.gdshader")
const SLASH_SCENE := preload("res://SCRIPT/SHADER/slash_heros.tscn")
## SYNERGIE avec le SANG BOUILLANT (Kaoru, 1er oct. 2026 : « qu'Ombre de sang
## fasse aussi proc Sang bouillant ») : le coup du double fait bouillir l'ennemi
## comme un coup d'épée — une charge de plus (player.gd, `bouillant_charger`)
const TALISMAN_BOUILLANT := "bouillant"

## part des dégâts d'un coup d'épée, distance au bord du corps de l'ennemi (px)
@export var part := 0.5
@export var ecart := 70.0
## il frappe au plus tôt / au plus tard après son apparition (s)
@export var delai_min := 0.08
@export var delai_max := 0.3
## il apparaît en… ; il s'efface en… (s) ; son opacité
@export var duree_apparition := 0.06
@export var duree_fin := 0.2
@export var opacite := 0.9
## la couleur de son slash (le slash du héros est blanc)
@export var couleur_slash := Color(0.86, 0.06, 0.14, 1.0)

## posés par le joueur (player.gd, `ombre_surgir`)
var joueur: CharacterBody2D = null
var cible: Node2D = null
var cote := 1.0                 # de quel côté de l'ennemi il surgit (+1 : à droite)
var animation := "attack"       # l'attaque du héros, à rejouer
var image_coup := 2             # l'image de cette attaque où le héros a touché
var slash_nom := "new_slash_1"
var slash_position := Vector2(-4, -70)
var echelle := 1.0              # l'Allonge
var zone := 0                   # la zone de touche de l'épée qui a porté
var xf_attaque := Transform2D.IDENTITY

@onready var _point: Node2D = $POINT
@onready var _corps: AnimatedSprite2D = $POINT/Corps

var _slash: Node2D = null
var _t := 0.0
var _a_frappe := false
var _fini := false
var _t_fin := 0.0
var _demi := 30.0               # demi-largeur du corps de l'ennemi
var _dernier_poste := Vector2.ZERO


func _ready() -> void:
	if not is_instance_valid(joueur) or not is_instance_valid(cible):
		queue_free()
		return
	var anim: AnimatedSprite2D = joueur.animator
	_corps.sprite_frames = anim.sprite_frames
	_corps.position = anim.position
	_corps.offset = anim.offset
	_corps.centered = anim.centered
	_corps.texture_filter = anim.texture_filter
	_corps.light_mask = anim.light_mask
	var mat := ShaderMaterial.new()
	mat.shader = TEINTE
	mat.set_shader_parameter("opacite", 0.0)
	_corps.material = mat
	# il regarde le héros
	_point.scale.x = -cote
	if _corps.sprite_frames.has_animation(animation):
		_corps.play(animation)
	_slash = SLASH_SCENE.instantiate()
	_slash.demo_boucle = false
	_point.add_child(_slash)
	var lame := _slash.get_node_or_null("Lame") as ColorRect
	if lame != null and lame.material is ShaderMaterial:
		(lame.material as ShaderMaterial).set_shader_parameter("couleur", couleur_slash)
	_demi = _demi_largeur(cible)
	_dernier_poste = _poste()
	global_position = _dernier_poste


func _physics_process(delta: float) -> void:
	_t += delta
	if not _a_frappe:
		# collé derrière l'ennemi pendant qu'il recule
		if is_instance_valid(cible) and cible.hp > 0:
			_dernier_poste = _poste()
		global_position = _dernier_poste
		var pret := _corps.frame >= image_coup or not _corps.is_playing()
		if (_t >= delai_min and pret) or _t >= delai_max:
			_frapper()
	elif not _fini and (not _corps.is_playing() or _t >= delai_max + 0.35):
		_fini = true
	if _fini:
		_t_fin += delta
		if _t_fin >= duree_fin:
			queue_free()
			return
	var a := opacite * clampf(_t / maxf(duree_apparition, 0.001), 0.0, 1.0)
	if _fini:
		a *= 1.0 - clampf(_t_fin / maxf(duree_fin, 0.001), 0.0, 1.0)
	(_corps.material as ShaderMaterial).set_shader_parameter("opacite", a)


## où il se tient : de l'autre côté de l'ennemi, à `ecart` px du bord de son
## corps, les pieds à hauteur des siens ; avant un mur s'il y en a un
func _poste() -> Vector2:
	var c := _centre(cible)
	var x := c.x + cote * (_demi + ecart)
	var q := PhysicsRayQueryParameters2D.create(c, Vector2(x + cote * 20.0, c.y), 1)
	q.exclude = [joueur.get_rid()]
	var touche := get_world_2d().direct_space_state.intersect_ray(q)
	if not touche.is_empty():
		x = float(touche["position"].x) - cote * 22.0
	return Vector2(x, cible.global_position.y)


func _frapper() -> void:
	_a_frappe = true
	# son slash, en miroir (il est sous POINT, retourné vers le héros)
	if joueur.slash_en_shader and _slash.connait(slash_nom):
		_slash.position = slash_position
		_slash.scale = Vector2(echelle, echelle)
		_slash.effet = "aucun"
		_slash.jouer(slash_nom)
	# ses dégâts : la zone de touche du héros, posée sur lui
	var anim = joueur.animator
	var hbs := [anim.hitbox_1, anim.hitbox_2, anim.hitbox_3, anim.hitbox_4]
	var hb: CollisionPolygon2D = hbs[clampi(zone, 0, 3)]
	var xf := Transform2D(0.0, Vector2(-cote, 1.0), 0.0, global_position) * xf_attaque * hb.transform
	var degats := maxi(roundi(anim.degats_du_coup() * part), 1)
	var espace := get_world_2d().direct_space_state
	var touches: Array[Node] = []
	for poly in Geometry2D.decompose_polygon_in_convex(hb.polygon):
		var forme := ConvexPolygonShape2D.new()
		forme.points = poly
		var requete := PhysicsShapeQueryParameters2D.new()
		requete.shape = forme
		requete.transform = xf
		requete.collision_mask = 8                   # la couche des monstres
		requete.collide_with_areas = false
		for resultat in espace.intersect_shape(requete, 16):
			var c: Node = resultat["collider"]
			if not (c is BaseAI) or touches.has(c):
				continue
			if c.hp <= 0 or c.invulnerable or not c.est_ennemi(joueur):
				continue
			touches.append(c)
			# COUP DE GRÂCE : fissuré (à portée d'exécution), le coup du double
			# l'achève aussi (Kaoru, 1er oct. 2026)
			var grace: bool = c is BaseAI and c.executable()
			var d: int = maxi(degats, c.hp) if grace else degats
			# sans recul : il le renverrait sur le héros (coup de contact)
			var porte = c.apply_damage(d, global_position.x, "ombre", false, joueur)
			if grace and porte != false:
				joueur.grace_executer(c)
			# SANG BOUILLANT : son coup fait bouillir aussi (une charge)
			if porte != false and c.hp > 0 and Player.talisman_equipe(TALISMAN_BOUILLANT):
				joueur.bouillant_charger(c)
	print("[OMBRE] f=", Engine.get_physics_frames(), " frappe après ", snappedf(_t, 0.01), " s : ",
		touches.size(), " ennemi(s), ", degats, " dégâts")


func _centre(c: Node2D) -> Vector2:
	if c is BaseAI and c.collision != null:
		return c.collision.global_position       # le milieu du corps, pas ses pieds
	return c.global_position


func _demi_largeur(c: Node2D) -> float:
	if c is BaseAI and c.collision != null and c.collision.shape != null:
		var f: Shape2D = c.collision.shape
		var e := absf(c.collision.global_scale.x)
		if f is RectangleShape2D:
			return (f as RectangleShape2D).size.x * 0.5 * e
		if f is CapsuleShape2D:
			return (f as CapsuleShape2D).radius * e
		if f is CircleShape2D:
			return (f as CircleShape2D).radius * e
	return 30.0
