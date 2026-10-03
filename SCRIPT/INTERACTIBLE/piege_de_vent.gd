@tool
extends Node2D
## ============================================================================
## PIÈGE DE VENT (2 oct. 2026) — une bouche d'aération qui
## SOUFFLE à intervalles réguliers et pousse TRÈS FORT le joueur et les
## monstres. Il souffle le long de son axe « haut » : posé au sol, un courant
## qui projette en l'air ; tourné de 90° contre un mur, un vent de côté qui
## balaie ; retourné au plafond, il plaque vers le bas.
##
## CYCLE : celui du PIÈGE DE FLAMMES (mêmes réglages, même calcul : des vents
## et des flammes réglés pareil restent synchronisés). `duree_souffle` de vent,
## `duree_repit` de calme, puis c'est le groupe `decale`, puis un répit…
## Cocher `decale` range le piège dans le second groupe : il souffle quand les
## autres se reposent.
## AVERTISSEMENT : une brise se lève `duree_avertissement` avant la rafale (des
## filets lents et fins, qui ne poussent pas) ; la rafale part avec deux
## anneaux d'air.
##
## LA POUSSÉE : `force` px/s à la bouche, `force_au_bout` de ça au bout de la
## `portee`, sur la largeur de la plateforme (`souffler` du joueur et des
## monstres). Le vent nous empoigne (sa vitesse en ~0,15 s) et nous donne de
## l'ÉLAN qui continue APRÈS le courant (pour envoyer loin et
## fort) : en l'air on file loin, au sol on glisse un peu,
## un mur l'arrête. À 1800 px/s, on recule même en courant (le héros court à
## 700). Un mur ou un plafond dans le courant l'arrête : la portée est
## raccourcie au lancement. Agrippé (échelle, corde, rebord, mur, grappin), on
## tient bon.
##
## Le visuel : SCRIPT/SHADER/vent.gdshader (nœud Vent), la famille du souffle du
## dash (filets blancs en fuseau, anneaux d'air au pinceau). La plateforme est
## celle de la scène (le grayboxing 200×50 pour l'instant) : la largeur du courant
## suit sa forme de collision.
## Visible dans l'éditeur, le cycle y tourne : on y règle portée et décalage.
## POUR LE JUGER : F6 (il souffle en boucle).
## ============================================================================

@export_group("Cycle")
## durée de la rafale (s)
@export var duree_souffle := 2.0
## RÉPIT entre les deux groupes : personne ne souffle (s)
@export var duree_repit := 1.0
## coché : ce piège est dans le SECOND groupe (il souffle quand les autres se reposent)
@export var decale := false
## la brise annonce la rafale ce temps-là avant (s)
@export var duree_avertissement := 0.6
## la rafale se lève en… (s)
@export var duree_montee := 0.15
## et retombe en… (s)
@export var duree_retombee := 0.3

@export_group("Vent")
## la vitesse du vent à la bouche (px/s)
@export var force := 1800.0
## au bout du courant, il ne reste que cette part de la force
@export_range(0.0, 1.0, 0.01) var force_au_bout := 0.9
## jusqu'où il porte (px)
@export var portee := 480.0
## largeur du courant (px) ; 0 = la largeur de la plateforme
@export var largeur := 0.0
## coché : les monstres au sol le contournent, comme les flammes (sinon ils y
## entrent et s'envolent)
@export var monstres_l_evitent := false

const EVASEMENT := 0.55             # le courant s'élargit d'autant au bout
const PUISSANCE_BRISE := 0.15
const VITESSE_VISUELLE := 1400.0    # la vitesse des filets en pleine rafale (px/s)

@onready var _vent: ColorRect = $Vent
@onready var _zone: Area2D = $Zone
@onready var _forme: CollisionShape2D = $Zone/Forme

var _temps := 0.0
var _temps_editeur := 0.0
var _defile := 0.0
var _graine := 0.0
var _portee_reelle := -1.0          # mesurée à la première image (un mur peut couper le courant)
var _bouche := Vector2(0.0, -25.0)  # le milieu du dessus de la plateforme (repère du nœud)
var _largeur_plateforme := 200.0
var _exclus: Array[RID] = []


func _ready() -> void:
	_graine = randf() * 50.0
	if decale:
		_temps = -_demi_periode()         # second groupe : démarre une demi-période plus tard
	if not Engine.is_editor_hint():
		if get_parent() == get_tree().root:
			position = get_viewport_rect().size * Vector2(0.5, 0.85)
		_zone.collision_layer = 0
		_zone.collision_mask = 0b1011     # joueur (1) et monstres (2 et 4), comme les flammes
		if monstres_l_evitent:
			_zone.add_to_group("DEGATS")
	_poser()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_temps += delta
	if _portee_reelle < 0.0:
		_mesurer_portee()
		_poser()
	# la brise ne pousse pas ; la rafale, de plus en plus
	var f := smoothstep(0.25, 1.0, _puissance_a(_temps))
	if f <= 0.0:
		return
	for corps in _zone.get_overlapping_bodies():
		if corps.has_method("souffler"):
			_pousser(corps, f)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# dans l'éditeur, le cycle tourne aussi, `decale` compris dès qu'on le coche
		_temps_editeur += delta
		_temps = _temps_editeur - (_demi_periode() if decale else 0.0)
		_poser()
	var p := _puissance_a(_temps)
	_defile += delta * VITESSE_VISUELLE * lerpf(0.2, 1.0, p)
	var mat := _vent.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("puissance", p)
	mat.set_shader_parameter("defilement", _defile)
	mat.set_shader_parameter("rafale", _rafale_t(_temps))
	mat.set_shader_parameter("temps", _temps)
	mat.set_shader_parameter("graine", _graine)


# ============================================================
#  LE CYCLE (le même calcul que piege_de_flamme.gd)
# ============================================================

## une rafale + un répit : le temps qui sépare les départs des deux groupes
func _demi_periode() -> float:
	return maxf(duree_souffle + duree_repit, 0.01)


## la puissance du vent à l'instant `t` du cycle (t < 0 : pas encore démarré)
func _puissance_a(t: float) -> float:
	var periode := 2.0 * _demi_periode()
	var brise := PUISSANCE_BRISE if duree_avertissement > 0.0 else 0.0
	if t < 0.0:
		return brise if -t <= duree_avertissement else 0.0
	var c := fposmod(t, periode)
	if c < duree_souffle:
		return lerpf(brise, 1.0, clampf(c / maxf(duree_montee, 0.001), 0.0, 1.0))
	if periode - c <= duree_avertissement:
		return brise                      # la brise annonce la prochaine rafale
	var depuis := c - duree_souffle
	if depuis < duree_retombee:
		return lerpf(1.0, 0.0, depuis / maxf(duree_retombee, 0.001))
	return 0.0


## depuis combien de temps la rafale a commencé (les anneaux d'air)
func _rafale_t(t: float) -> float:
	if t < 0.0:
		return 10.0
	var c := fposmod(t, 2.0 * _demi_periode())
	return c if c < duree_souffle else 10.0


# ============================================================
#  LE COURANT
# ============================================================

func _largeur_courant() -> float:
	return largeur if largeur > 0.0 else _largeur_plateforme


func _portee_effective() -> float:
	return _portee_reelle if _portee_reelle >= 0.0 else portee


## la plateforme (la forme de collision rectangulaire du décor) donne
## la bouche (le milieu de son dessus) et la largeur du courant
func _lire_plateforme() -> void:
	_exclus.clear()
	for n in find_children("*", "CollisionShape2D", true, false):
		if n == _forme or not (n.shape is RectangleShape2D):
			continue
		var t: Transform2D = global_transform.affine_inverse() * n.global_transform
		var taille: Vector2 = n.shape.size * t.get_scale().abs()
		_bouche = Vector2(t.origin.x, t.origin.y - taille.y * 0.5)
		_largeur_plateforme = taille.x
		var corps := n.get_parent() as CollisionObject2D
		if corps != null:
			_exclus.append(corps.get_rid())
		return


## un mur ou un plafond dans le courant l'arrête : la portée est raccourcie.
## Le joueur (couche 1 lui aussi) et les monstres ne comptent pas : le rayon les
## traverse (sinon un joueur debout devant au lancement coupait le vent à 75 px)
func _mesurer_portee() -> void:
	_lire_plateforme()
	var depart := to_global(_bouche + Vector2(0.0, -4.0))
	var arrivee := to_global(_bouche + Vector2(0.0, -portee))
	var exclus := _exclus.duplicate()
	_portee_reelle = portee
	for essai in 8:
		var rayon := PhysicsRayQueryParameters2D.create(depart, arrivee, 1)
		rayon.exclude = exclus
		var touche := get_world_2d().direct_space_state.intersect_ray(rayon)
		if touche.is_empty():
			return
		if touche["collider"] is CharacterBody2D:
			exclus.append(touche["rid"])
			continue
		_portee_reelle = maxf((_bouche - to_local(touche["position"])).length(), 20.0)
		return


## le rectangle du dessin et la zone de poussée, d'après la plateforme et la portée
func _poser() -> void:
	if _vent == null:
		return
	if _portee_reelle < 0.0:
		_lire_plateforme()
	var reach := _portee_effective()
	var demi_max := _largeur_courant() * 0.5 * (1.0 + EVASEMENT)
	var w := demi_max * 2.0 + 120.0
	_vent.position = Vector2(_bouche.x - w * 0.5, _bouche.y - reach - 60.0)
	_vent.size = Vector2(w, reach + 80.0)
	var mat := _vent.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("taille", _vent.size)
		mat.set_shader_parameter("bouche", Vector2(w * 0.5, reach + 60.0))
		mat.set_shader_parameter("largeur", _largeur_courant())
		mat.set_shader_parameter("portee", reach)
		mat.set_shader_parameter("evasement", EVASEMENT)
	var r := _forme.shape as RectangleShape2D
	if r != null:
		r.size = Vector2(demi_max * 2.0 + 36.0, reach + 60.0)
		_forme.position = Vector2(_bouche.x, _bouche.y - reach * 0.5)


## pousse `corps` (joueur ou monstre) selon où il est dans le courant
func _pousser(corps: Node2D, f: float) -> void:
	var c := corps.global_position
	if corps.has_method("centre_corps"):
		if Player.hp <= 0:
			return
		c = corps.centre_corps()
	elif corps is BaseAI:
		if corps.hp <= 0:
			return
		if corps.collision != null:
			c = corps.collision.global_position
	var l := to_local(c)
	var h := _bouche.y - l.y                # hauteur dans le courant
	var reach := _portee_effective()
	if h < -30.0 or h > reach + 30.0:
		return
	var hn := clampf(h / reach, 0.0, 1.0)
	var demi := _largeur_courant() * 0.5 * (1.0 + EVASEMENT * pow(hn, 1.5))
	var k_x := 1.0 - smoothstep(demi * 0.85, demi + 18.0, absf(l.x - _bouche.x))
	var k_h := lerpf(1.0, force_au_bout, hn) * (1.0 - smoothstep(reach * 0.92, reach + 30.0, h))
	if k_x * k_h <= 0.0:
		return
	var axe := global_transform.basis_xform(Vector2.UP).normalized()
	corps.souffler(axe * force * k_x * k_h * f)
