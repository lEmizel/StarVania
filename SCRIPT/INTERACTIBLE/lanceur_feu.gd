@tool
extends Node2D
## ============================================================================
## LANCEUR DE BOULES DE FEU — un canon scellé dans le mur, qui tire LA boule de
## feu du squelette bleu (SCRIPT/SPELL/projectile_feu.tscn) à intervalle
## régulier, droit devant lui.
##   • AVERTI : `duree_charge` avant le tir, la boule enfle dans sa bouche et le
##     bout du canon rougit (le même geste que la main du squelette bleu) ;
##   • la boule file droit, explose sur le premier mur, blesse le joueur
##     (`damage`, comme un coup de monstre : esquive, bouclier… comptent ; les
##     Gardiennes l'arrêtent) et tue les monstres (`degats_monstres`) : elle n'a
##     pas de camp ;
##   • il ne tire QUE S'IL EST À L'ÉCRAN : on voit toujours d'où ça vient.
## RÉGLAGES : `intervalle`, `decale` (coché : il tire une demi-période après les
## autres, comme les flammes et le vent), `duree_charge`, `vitesse_boule`,
## `portee_boule`. Tous les lanceurs d'un niveau partent ensemble au
## chargement : leurs rythmes restent calés entre eux.
## Il tire vers sa DROITE : le TOURNER (rotation) pour tirer vers le haut, le bas
## ou en biais, `scale.x = -1` pour tirer vers la gauche. Son ORIGINE se pose SUR
## LA SURFACE DU MUR ; la boule naît devant sa bouche, à 70 px du mur.
## Dessin : deux pièces, pour que le canon recule dans son socle au tir :
## MEDIA/INTERACTIBLE/base canon.png et
## canon.png, posés et animés par SCRIPT/SHADER/lanceur_feu.gdshader (nœud
## Lanceur ; la scène lui donne les deux images). Sa bouche est à 62 px du mur.
## @tool : dans l'éditeur, des pointillés montrent où il tire.
## POUR LA JUGER : ouvrir la scène et faire F6 (il tire sur un mur de démo).
## ============================================================================

const PROJECTILE := preload("res://SCRIPT/SPELL/projectile_feu.tscn")
const VISUEL_CHARGE := preload("res://SCRIPT/SHADER/boule_de_feu.tscn")
const BOUCHE := Vector2(70.0, 0.0)      # où naît la boule (repère du lanceur)
const CENTRE := Vector2(32.0, 0.0)      # le milieu du lanceur (pour savoir s'il est à l'écran)
const TAILLE_BOULE := 0.77              # l'échelle du visuel du projectile
const TRAINEE_CHARGE := 0.15            # elle ne vole pas encore : traînée courte, comme dans la main du squelette

## Cœurs perdus par le joueur touché
@export var damage: int = 1
## Dégâts aux monstres (999999 = mort en un coup, comme les pièges)
@export var degats_monstres: int = 999999

@export_group("Cadence")
## temps entre deux tirs (s)
@export var intervalle := 2.5
## coché : il tire une demi-période après les autres (deux groupes qui alternent)
@export var decale := false
## la boule enfle dans la bouche pendant… avant de partir (s) : le temps de réagir
@export var duree_charge := 0.65

@export_group("Boule")
## sa vitesse (px/s) — celle du squelette bleu : 800
@export var vitesse_boule := 800.0
## au-delà, elle s'éteint sans exploser (px)
@export var portee_boule := 2200.0

@onready var _dessin: ColorRect = $Lanceur

var _temps := 0.0
var _prochain_tir := 0.0
var _charge := -1.0                     # >= 0 : la boule enfle (s écoulées)
var _tir := 0.0                         # 1 → 0 après un tir : recul, fumée
var _chaleur := 0.0
var _visuel: Node2D = null
var _demo := false


func _ready() -> void:
	_demo = not Engine.is_editor_hint() and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * Vector2(0.12, 0.5)
		_poser_decor_de_demo.call_deferred()
	_prochain_tir = _periode() * (1.5 if decale else 1.0)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_temps += delta
	_tir = maxf(_tir - delta / 0.5, 0.0)
	var charge := _duree_charge()
	if _charge < 0.0:
		_chaleur = maxf(_chaleur - delta / 0.35, 0.0)
		if _temps >= _prochain_tir - charge:
			if _a_l_ecran():
				_commencer_charge()
			else:
				_prochain_tir += _periode()      # hors de l'écran : ce tir n'a pas lieu
	else:
		_charge += delta
		var k := clampf(_charge / maxf(charge, 0.001), 0.0, 1.0)
		_chaleur = k
		_grossir(k)
		if _temps >= _prochain_tir:
			_tirer()
			_prochain_tir += _periode()
	_appliquer()


func _periode() -> float:
	return maxf(intervalle, 0.3)


func _duree_charge() -> float:
	return clampf(duree_charge, 0.0, _periode() * 0.9)


## entièrement à l'écran (son milieu, avec une marge) : on voit d'où ça vient
func _a_l_ecran() -> bool:
	if _demo:
		return true
	var vp := get_viewport()
	var ecran := vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	return ecran.grow(-20.0).has_point(global_transform * CENTRE)


func _commencer_charge() -> void:
	_charge = 0.0
	_eteindre_visuel()
	_visuel = VISUEL_CHARGE.instantiate() as Node2D
	_visuel.demo_vol = false              # elle enfle sur place, elle ne vole pas
	_visuel.puissance = 0.25
	_visuel.z_index = 1                   # devant le canon
	add_child(_visuel, false, Node.INTERNAL_MODE_BACK)
	_visuel.position = BOUCHE
	_visuel.regler_trainee(TRAINEE_CHARGE)
	_grossir(0.0)


## la boule qui enfle : le compte à rebours rendu visible (comme le squelette)
func _grossir(k: float) -> void:
	if _visuel == null or not is_instance_valid(_visuel):
		return
	# à la fin, exactement la boule qui part, quelle que soit l'échelle du lanceur
	var compense := 1.0 / maxf(absf(global_transform.get_scale().x), 0.01)
	_visuel.scale = Vector2.ONE * TAILLE_BOULE * (0.12 + 0.88 * k) * compense
	_visuel.puissance = 0.25 + 0.75 * k


func _eteindre_visuel() -> void:
	if _visuel != null and is_instance_valid(_visuel):
		_visuel.queue_free()
	_visuel = null


func _tirer() -> void:
	_charge = -1.0
	_eteindre_visuel()
	_tir = 1.0
	var b := PROJECTILE.instantiate()
	b.direction = global_transform.x.normalized()
	b.damage = damage
	b.faction = -1                        # sans camp : il blesse le joueur ET les monstres
	b.degats_monstres = degats_monstres
	b.tireur = null
	b.speed = vitesse_boule
	b.portee = portee_boule
	var hote: Node = get_tree().current_scene
	if hote == null or _demo:
		hote = get_parent()
	hote.add_child(b)
	b.global_position = global_transform * BOUCHE
	# sa traînée = le chemin parcouru en 0,1 s : elle POUSSE en sortant de la
	# bouche (pleine dès le départ, elle traversait le canon jusqu'au mur)
	var visuel := b.get_node_or_null("Visuel")
	var dessin := visuel.get_node_or_null("Boule") as ColorRect if visuel != null else null
	if dessin != null and dessin.material is ShaderMaterial and visuel.has_method("regler_trainee"):
		var pleine := float((dessin.material as ShaderMaterial).get_shader_parameter("longueur_trainee"))
		visuel.regler_trainee(TRAINEE_CHARGE)
		b.create_tween().tween_method(visuel.regler_trainee, TRAINEE_CHARGE, pleine, 0.12)


func _appliquer() -> void:
	var mat := _dessin.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("chaleur", _chaleur)
	mat.set_shader_parameter("tir", _tir)
	mat.set_shader_parameter("temps", _temps)


## ÉDITEUR seulement : des pointillés, là où il tire
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var couleur := Color(1.0, 0.5, 0.12, 0.6)
	draw_arc(BOUCHE, 22.4, 0.0, TAU, 32, couleur, 2.0)
	var x := BOUCHE.x + 30.0
	while x < BOUCHE.x + 430.0:
		draw_line(Vector2(x, 0.0), Vector2(x + 14.0, 0.0), couleur, 3.0)
		x += 26.0


## F6 : un mur derrière lui (il y est scellé) et un mur en face, où ses boules explosent
func _poser_decor_de_demo() -> void:
	var taille := get_viewport_rect().size
	var mur_fond := ColorRect.new()
	mur_fond.color = Color(0.2, 0.25, 0.33)
	mur_fond.position = Vector2(position.x - 200.0, 0.0)
	mur_fond.size = Vector2(200.0, taille.y)
	mur_fond.z_index = -1
	get_parent().add_child(mur_fond)
	var corps := StaticBody2D.new()
	corps.collision_layer = 1 | 2 | 4
	var forme := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(60.0, taille.y)
	forme.shape = r
	corps.add_child(forme)
	corps.position = Vector2(taille.x * 0.88, taille.y * 0.5)
	get_parent().add_child(corps)
	var mur := ColorRect.new()
	mur.color = Color(0.2, 0.25, 0.33)
	mur.position = corps.position - r.size * 0.5
	mur.size = r.size
	mur.z_index = -1
	get_parent().add_child(mur)
