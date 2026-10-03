@tool
extends Node2D
## ============================================================================
## BARRE DE FEU (2 oct. 2026, demande de Kaoru : « autant faire des barres de feu
## comme dans Mario directement ») — une chaîne de boules de feu qui tourne sans
## fin autour de son axe. Une pièce à poser n'importe où, en autant
## d'exemplaires qu'on veut : dans le vide (avec son bloc de pierre, SOLIDE, comme
## le bloc des barres de Mario : on peut se tenir dessus), dans un mur ou au
## plafond (`socle` décoché).
##   • les boules sont LE visuel de la boule de feu du squelette bleu
##     (SCRIPT/SHADER/boule_de_feu.tscn), rondes, SANS traînée (Kaoru : « pas
##     nécessaire » — la v1 en avait une, d'autant plus longue que la boule
##     allait vite) ;
##   • elle blesse le joueur au contact (`damage`, repoussé loin de l'axe, un peu
##     vers le haut), pas plus d'une fois par `delai_entre_coups` ; roulade et
##     dash passent au travers. Elle tue les monstres qui s'y prennent
##     (`degats_monstres`), comme les autres pièges — sauf si
##     `monstres_l_evitent` est coché : les monstres au sol font alors demi-tour
##     au bord de la zone où leur corps toucherait la barre (le cercle balayé,
##     prolongé de HAUTEUR_MONSTRES vers le bas), comme devant les flammes. Les
##     volants ne regardent pas où ils vont : ils s'y brûlent dans les deux cas.
## RÉGLAGES : `nb_boules`, `nb_bras` (1 à 4, répartis), `taille_boule`,
## `vitesse` (degrés par seconde), `sens_horaire`, `angle_depart` (pour décaler
## plusieurs barres entre elles), `socle`, `monstres_l_evitent`. Toutes les
## barres d'un niveau partent ensemble au chargement : leurs écarts restent ceux
## de `angle_depart`.
## @tool : dans l'ÉDITEUR, elle se montre à sa vraie taille, à son angle de
## départ, avec le cercle qu'elle balaie et son sens de rotation (et, case
## `monstres_l_evitent` cochée, la zone évitée par les monstres, en bleu). Rien
## de tout ça n'est enregistré dans la scène : boules, bloc, corps et zone sont
## fabriqués par le script (enfants internes).
## POUR LA JUGER : ouvrir la scène et faire F6.
## ============================================================================

const BOULE := preload("res://SCRIPT/SHADER/boule_de_feu.tscn")
const SHADER_SOCLE := preload("res://SCRIPT/SHADER/barre_feu_socle.gdshader")
const RAYON_VISUEL := 0.38 * 80.0       # rayon de la boule du visuel à pleine puissance, à l'échelle 1 (px)
const ECART := 1.9                     # entre deux boules, en rayons : elles se touchent
const DEMI_SOCLE := 24.0                # le bloc de pierre : 48 × 48 px
const HAUTEUR_MONSTRES := 200.0         # la zone évitée descend d'autant sous le cercle : un squelette fait 183 px
const MARGE_EVITEMENT := 20.0           # … et déborde d'autant tout autour
const META := "genere_par_barre_feu"

## Cœurs perdus par le joueur touché
@export var damage: int = 1
## Dégâts aux monstres (999999 = mort en un coup, comme les pièges)
@export var degats_monstres: int = 999999

@export_group("Barre")
## boules par bras (la première est sur l'axe)
@export_range(1, 16) var nb_boules: int = 6:
	set(v):
		nb_boules = clampi(v, 1, 16)
		_reconstruire()
## nombre de bras, répartis autour de l'axe
@export_range(1, 4) var nb_bras: int = 1:
	set(v):
		nb_bras = clampi(v, 1, 4)
		_reconstruire()
## taille des boules (0,77 = la boule de feu du squelette bleu)
@export_range(0.3, 1.5, 0.01) var taille_boule := 0.6:
	set(v):
		taille_boule = clampf(v, 0.3, 1.5)
		_reconstruire()
## le bloc de pierre au centre, solide (décocher dans un mur ou un plafond)
@export var socle := true:
	set(v):
		socle = v
		_reconstruire()

@export_group("Rotation")
## vitesse de rotation, en degrés par seconde (0 = immobile)
@export_range(0.0, 720.0, 1.0) var vitesse := 100.0:
	set(v):
		vitesse = maxf(v, 0.0)
		_placer()
		queue_redraw()
## dans le sens des aiguilles d'une montre
@export var sens_horaire := true:
	set(v):
		sens_horaire = v
		_placer()
		queue_redraw()
## angle de départ en degrés (0 = vers la droite, 90 = vers le bas) : pour
## décaler plusieurs barres entre elles
@export_range(-180.0, 180.0, 1.0) var angle_depart := 0.0:
	set(v):
		angle_depart = v
		_placer()
		queue_redraw()

@export_group("Dégâts")
## délai avant de pouvoir re-blesser le même corps (sinon la barre le rattrape
## à la fin de son étourdissement)
@export var delai_entre_coups := 1.0
## coché : les monstres au sol ne s'en approchent pas — ils font demi-tour au
## bord de la zone où leur corps toucherait la barre (en bleu dans l'éditeur),
## comme devant les flammes. Décoché : ils s'y jettent et meurent (on peut les y
## attirer). Les volants s'y brûlent dans les deux cas.
@export var monstres_l_evitent := false:
	set(v):
		monstres_l_evitent = v
		_reconstruire()

var _boules: Array[Node2D] = []
var _rayons: Array[float] = []          # distance de chaque boule à l'axe (repère du nœud)
var _bras_de: Array[int] = []           # le bras de chaque boule
var _corps_socle: StaticBody2D = null
var _temps := 0.0
var _dernier_coup := {}                 # corps → instant de son dernier coup
var _forme := CapsuleShape2D.new()
var _requete := PhysicsShapeQueryParameters2D.new()


func _ready() -> void:
	if not Engine.is_editor_hint() and get_parent() == get_tree().root:
		position = get_viewport_rect().size * 0.5        # F6 : au milieu de l'écran
	if Engine.is_editor_hint():
		set_notify_transform(true)        # la zone bleue se redessine quand on la tourne
	_requete.shape = _forme
	_requete.collision_mask = 0b1011     # joueur (1) et monstres (2 et 4), comme les flammes
	_requete.collide_with_areas = false
	_construire()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_temps += delta
	_placer()
	_blesser()


func _rayon_boule() -> float:
	return RAYON_VISUEL * taille_boule


func _ecart() -> float:
	return ECART * _rayon_boule()


## de l'axe au centre de la dernière boule (repère du nœud)
func _longueur() -> float:
	return (nb_boules - 1) * _ecart()


## le rayon du cercle qu'elle balaie (repère du nœud)
func portee() -> float:
	return _longueur() + _rayon_boule()


## le rayon de la zone évitée par les monstres (repère du monde)
func _rayon_evite() -> float:
	return portee() * absf(global_transform.get_scale().x) + MARGE_EVITEMENT


func _omega() -> float:
	return deg_to_rad(vitesse) * (1.0 if sens_horaire else -1.0)


func _angle_bras(k: int) -> float:
	return deg_to_rad(angle_depart) + _omega() * _temps + TAU * k / nb_bras


func _reconstruire() -> void:
	if is_node_ready():
		_construire()


## fabrique le bloc, son corps et les boules (enfants internes : rien n'est
## enregistré dans la scène)
func _construire() -> void:
	for enfant in get_children(true):
		if enfant.has_meta(META):
			remove_child(enfant)
			enfant.queue_free()
	_boules.clear()
	_rayons.clear()
	_bras_de.clear()
	_corps_socle = null
	_requete.exclude = []
	if socle:
		var dessin := ColorRect.new()
		var mat := ShaderMaterial.new()
		mat.shader = SHADER_SOCLE
		dessin.material = mat
		dessin.size = Vector2.ONE * (DEMI_SOCLE * 2.0 + 16.0)
		dessin.position = -dessin.size * 0.5
		dessin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mat.set_shader_parameter("taille", dessin.size)
		mat.set_shader_parameter("demi_cote", DEMI_SOCLE)
		dessin.set_meta(META, true)
		add_child(dessin, false, Node.INTERNAL_MODE_FRONT)
		if not Engine.is_editor_hint():
			# solide, comme le bloc des barres de Mario : on peut se tenir dessus
			_corps_socle = StaticBody2D.new()
			_corps_socle.collision_layer = 3          # comme les blocs de grayboxing
			_corps_socle.collision_mask = 0
			var forme := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2.ONE * DEMI_SOCLE * 2.0
			forme.shape = rect
			_corps_socle.add_child(forme)
			_corps_socle.set_meta(META, true)
			add_child(_corps_socle, false, Node.INTERNAL_MODE_FRONT)
			_requete.exclude = [_corps_socle.get_rid()]
	if monstres_l_evitent and not Engine.is_editor_hint():
		_creer_zone_evitee()
	for k in nb_bras:
		for i in nb_boules:
			if k > 0 and i == 0:
				continue                   # la boule de l'axe est commune à tous les bras
			var b := BOULE.instantiate() as Node2D
			b.demo_vol = false
			# une lumière sur deux, à partir du bout (elles s'additionnent)
			b.energie_lumiere = 0.35 if (nb_boules - 1 - i) % 2 == 0 else 0.0
			b.set_meta(META, true)
			add_child(b, false, Node.INTERNAL_MODE_BACK)
			b.scale = Vector2.ONE * taille_boule
			b.regler_trainee(0.0)          # une boule ronde, sans traînée
			_boules.append(b)
			_rayons.append(_ecart() * i)
			_bras_de.append(k)
	_placer()
	queue_redraw()


## la zone que les monstres au sol voient comme un trou (groupe "DEGATS", lu par
## BASE_IA.danger_devant sur la sonde devant leurs pieds) : partout où leur
## corps, jusqu'à HAUTEUR_MONSTRES de haut, toucherait le cercle balayé — le
## cercle prolongé vers le bas. Une barre plus haute qu'eux ne les gêne pas.
func _creer_zone_evitee() -> void:
	var zone := Area2D.new()
	zone.top_level = true                 # repère monde : « vers le bas » reste le bas, barre tournée ou pas
	zone.collision_layer = 1 << 30        # une couche à elle seule (la 31) : la sonde des monstres la voit, rien d'autre
	zone.collision_mask = 0
	zone.monitoring = false
	var forme := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	var r := _rayon_evite()
	capsule.radius = r
	capsule.height = HAUTEUR_MONSTRES + 2.0 * r
	forme.shape = capsule
	zone.add_child(forme)
	zone.add_to_group("DEGATS")
	zone.set_meta(META, true)
	add_child(zone, false, Node.INTERNAL_MODE_FRONT)
	zone.global_position = global_position + Vector2(0.0, HAUTEUR_MONSTRES * 0.5)
	zone.global_rotation = 0.0


func _placer() -> void:
	if not is_node_ready():
		return
	var biais := PI * 0.5 if sens_horaire else -PI * 0.5
	for j in _boules.size():
		var b := _boules[j]
		if not is_instance_valid(b):
			continue
		var a := _angle_bras(_bras_de[j])
		b.position = Vector2.from_angle(a) * _rayons[j]
		b.rotation = a + biais            # tournée dans le sens de la rotation : son feu file vers l'arrière


## chaque bras = une capsule de l'axe à la dernière boule (les boules se
## touchent : aucun trou entre elles)
func _blesser() -> void:
	var xf := global_transform
	var axe := xf.origin
	var r_touche := _rayon_boule() * 0.8 * absf(xf.get_scale().x)
	var espace := get_world_2d().direct_space_state
	var vus := {}
	for k in nb_bras:
		var bout := xf * (Vector2.from_angle(_angle_bras(k)) * _longueur())
		var seg := bout - axe
		_forme.radius = r_touche
		_forme.height = seg.length() + 2.0 * r_touche
		_requete.transform = Transform2D(seg.angle() - PI * 0.5, (axe + bout) * 0.5)
		for res in espace.intersect_shape(_requete, 32):
			var corps: Object = res["collider"]
			if corps == null or vus.has(corps):
				continue
			vus[corps] = true
			if _temps - float(_dernier_coup.get(corps, -INF)) < delai_entre_coups:
				continue
			var porte := false
			if corps.has_method("apply_environment_damage"):
				# repoussé loin de l'axe, un peu vers le haut : hors du cercle (en
				# roulade ou en dash, « pas porté » : on retente tant qu'il est dedans)
				var c: Vector2 = corps.centre_corps() if corps.has_method("centre_corps") else (corps as Node2D).global_position
				var cote := signf(c.x - axe.x)
				if absf(c.x - axe.x) < 8.0:
					cote = signf(seg.orthogonal().x * (-1.0 if sens_horaire else 1.0))
				if cote == 0.0:
					cote = 1.0
				porte = corps.apply_environment_damage(damage, Vector2(cote, -0.6).normalized())
			elif corps is BaseAI and corps.hp > 0:
				porte = corps.apply_damage(degats_monstres, axe.x, "barre_feu")
			if porte:
				_dernier_coup[corps] = _temps


## ÉDITEUR seulement : le cercle balayé, le sens de rotation et la zone évitée
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var couleur := Color(1.0, 0.55, 0.15, 0.55)
	var r := portee()
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, couleur, 2.0)
	if vitesse > 0.0:
		# une flèche sur le cercle, un peu après le bout de la barre, dans son sens
		var s := 1.0 if sens_horaire else -1.0
		var a := deg_to_rad(angle_depart) + s * 0.35
		var pointe := Vector2.from_angle(a) * r
		var avance := Vector2.from_angle(a + s * PI * 0.5)
		var dehors := Vector2.from_angle(a)
		draw_line(pointe, pointe - avance * 14.0 + dehors * 8.0, couleur, 3.0)
		draw_line(pointe, pointe - avance * 14.0 - dehors * 8.0, couleur, 3.0)
	if monstres_l_evitent:
		# la zone évitée par les monstres au sol, tracée en repère MONDE (vers le bas)
		draw_set_transform_matrix(global_transform.affine_inverse())
		var bleu := Color(0.45, 0.7, 1.0, 0.6)
		var haut := global_position
		var bas := haut + Vector2(0.0, HAUTEUR_MONSTRES)
		var re := _rayon_evite()
		draw_arc(haut, re, PI, TAU, 48, bleu, 2.0)
		draw_arc(bas, re, 0.0, PI, 48, bleu, 2.0)
		draw_line(haut + Vector2(-re, 0.0), bas + Vector2(-re, 0.0), bleu, 2.0)
		draw_line(haut + Vector2(re, 0.0), bas + Vector2(re, 0.0), bleu, 2.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		queue_redraw()
