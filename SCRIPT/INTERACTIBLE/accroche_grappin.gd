@tool
extends Node2D
## ============================================================================
## ACCROCHE DE GRAPPIN — un simple point, sans physique ni zone. C'est le
## JOUEUR qui décide si elle est prenable : à portée (GRAPPIN_PORTEE), au-dessus
## de lui, et aucun mur entre sa main et le point (rayon) — comme Batman, Sekiro
## ou Ori. L'accroche prenable s'allume ; R1 y envoie le grappin, qui hisse le
## joueur d'un trait puis le catapulte au-dessus (état GRAPPIN, player.gd).
##
## Ce nœud ne fait que : se déclarer dans le groupe "GRAPPIN", donner son
## point, s'allumer, et dessiner le câble pendant la traction.
## Son visuel : la PINCE (2 oct. 2026, d'après un croquis), posée au
## démarrage — fermée, OUVERTE avec une lumière bleue quand on peut s'y
## accrocher, refermée sur le câble pendant la traction
## (SCRIPT/SHADER/pince_grappin.tscn). Sans pince (l'accroche pendulaire),
## l'anneau d'avant.
## Dans l'éditeur : la pince (fermée, ou ouverte avec `apercu_pince_ouverte`)
## plus un cercle de portée indicatif pour placer.
## ============================================================================

@export var couleur_anneau := Color(1.0, 0.9, 0.3)
@export var couleur_active := Color(0.4, 1.0, 0.5)
## robe du câble : pilote la couleur de corps du shader cable_de_sang
@export var couleur_cable := Color(0.62, 0.04, 0.08)   # rouge sang
## épaisseur VISIBLE du câble, en pixels (le shader fait le reste)
@export var epaisseur_cable := 10.0
## rayon indicatif dessiné dans l'éditeur (la vraie portée est celle du joueur,
## GRAPPIN_PORTEE dans player.gd) : à garder égal pour placer juste
@export var portee_indicative := 520.0:
	set(v):
		portee_indicative = v
		queue_redraw()

## Marge laissée AUTOUR du câble dans le ruban : c'est la place des gouttes,
## des grumeaux et de la lueur. Le ruban de la Line2D est donc volontairement
## bien plus large que le câble qu'on y voit.
const CABLE_MARGE := 40.0

const CABLE_SHADER := preload("res://SCRIPT/SHADER/cable_de_sang.gdshader")
const PINCE_SCENE := preload("res://SCRIPT/SHADER/pince_grappin.tscn")

## la pince dessine le point (sinon : l'anneau) — l'accroche pendulaire la coupe
@export var pince_visible := true
## sa taille (1 = celle du dessin : ~42 px fermée, ~66 px ouverte) ; 1,82 :
## agrandie de 40 % puis de 30 % → ~76 et ~120 px
@export var echelle_pince := 1.82
## dans l'éditeur seulement : voir la pince ouverte
@export var apercu_pince_ouverte := false

@onready var _cable: Line2D = $Cable
var _actif := false
var _pince: Node2D = null


func _ready() -> void:
	add_to_group("GRAPPIN")
	# Le ruban est fabriqué ICI et pas dans la scène : l'accroche pendulaire
	# hérite de ce script sans avoir le matériau, elle aurait affiché une bande
	# blanche de 50 px. Les valeurs posées dans une scène restent prioritaires.
	if _cable.material == null:
		var m := ShaderMaterial.new()
		m.shader = CABLE_SHADER
		_cable.material = m
	# bouts CARRÉS : arrondis, un ruban de 50 px déborderait de 25 px au-delà
	# de la main et de l'anneau
	_cable.begin_cap_mode = Line2D.LINE_CAP_NONE
	_cable.end_cap_mode = Line2D.LINE_CAP_NONE
	_cable.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	_cable.width = epaisseur_cable + CABLE_MARGE
	_cable.default_color = Color.WHITE       # la couleur vient du shader
	# Une Line2D ne fabrique ses UV que si elle porte une texture : sans elle le
	# shader n'aurait aucune coordonnée le long du câble. Quatre pixels blancs
	# suffisent, c'est le shader qui peint.
	if _cable.texture == null:
		var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_cable.texture = ImageTexture.create_from_image(img)
	var mat := _cable.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("epaisseur", epaisseur_cable)
		mat.set_shader_parameter("largeur", _cable.width)
		mat.set_shader_parameter("middle_color", couleur_cable)
		# une graine par accroche : deux câbles ne grumellent pas pareil
		mat.set_shader_parameter("graine", randf_range(1.0, 100.0))
	_cable.visible = false
	if pince_visible:
		_poser_pince()
	queue_redraw()


## la pince : posée une fois (dans l'éditeur aussi, sans être enregistrée).
## `_process` la rattrape aussi : une accroche déjà chargée dans l'éditeur quand
## ce script a changé ne refait pas son `_ready` — elle gardait l'ancien anneau
## jusqu'à ce qu'on rouvre la scène
func _poser_pince() -> void:
	_pince = get_node_or_null("PinceGrappin") as Node2D
	if _pince == null:
		_pince = PINCE_SCENE.instantiate()
		_pince.name = "PinceGrappin"
		_pince.demo_boucle = false
		add_child(_pince)
	queue_redraw()


## la pince suit l'état de l'accroche : ouverte quand on peut s'y accrocher,
## refermée (et allumée) tant que le câble y tient
func _process(_delta: float) -> void:
	if pince_visible and _pince == null:
		_poser_pince()
	if _pince == null:
		return
	_pince.scale = Vector2(echelle_pince, echelle_pince)
	if Engine.is_editor_hint():
		_pince.ouvert = apercu_pince_ouverte
		_pince.tenue = false
		return
	_pince.ouvert = _actif
	_pince.tenue = _cable.visible


# ---------------------------------------------------------------------------
# API pour le joueur
# ---------------------------------------------------------------------------

## position globale du point d'accroche
func point() -> Vector2:
	return global_position


## allumée = prenable maintenant (le joueur le décide chaque frame)
func surligner(actif: bool) -> void:
	if actif == _actif:
		return
	_actif = actif
	queue_redraw()


## câble visible entre deux positions globales (main du joueur → pointe)
func cable_montrer(depuis: Vector2, jusqua: Vector2) -> void:
	_cable.visible = true
	_cable.points = PackedVector2Array([to_local(depuis), to_local(jusqua)])
	var mat := _cable.material as ShaderMaterial
	if mat == null:
		return
	var v := jusqua - depuis
	var l := v.length()
	# la longueur change à CHAQUE image pendant le lancer : sans elle, grumeaux
	# et gouttes s'étireraient avec le câble au lieu de garder leur taille
	mat.set_shader_parameter("longueur", l)
	if l < 0.001:
		return
	# "vers le bas" du monde, exprimé dans le repère du ruban (le long, en
	# travers) : sinon les gouttes tomberaient perpendiculairement au câble,
	# donc de côté dès qu'il est en diagonale
	var tangente := v / l
	var normale := Vector2(-tangente.y, tangente.x)
	mat.set_shader_parameter("bas_local",
		Vector2(Vector2.DOWN.dot(tangente), Vector2.DOWN.dot(normale)))


func cable_cacher() -> void:
	_cable.visible = false


# ---------------------------------------------------------------------------

func _draw() -> void:
	# sans pince (l'accroche pendulaire) : l'anneau, vif quand on peut s'y accrocher
	if _pince == null:
		var c := couleur_active if _actif else couleur_anneau
		draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 28, c, 4.0 if _actif else 3.0)
		draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 16, c, 2.0)
	if Engine.is_editor_hint():
		draw_arc(Vector2.ZERO, portee_indicative, 0.0, TAU, 64, Color(couleur_anneau, 0.25), 1.5)
