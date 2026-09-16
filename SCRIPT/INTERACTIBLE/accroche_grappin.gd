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
## Dans l'éditeur : l'anneau plus un cercle de portée indicatif pour placer.
## ============================================================================

@export var couleur_anneau := Color(1.0, 0.9, 0.3)
@export var couleur_active := Color(0.4, 1.0, 0.5)
@export var couleur_cable := Color(0.62, 0.04, 0.08)   # rouge sang
@export var epaisseur_cable := 4.0
## rayon indicatif dessiné dans l'éditeur (la vraie portée est celle du joueur,
## GRAPPIN_PORTEE dans player.gd) : à garder égal pour placer juste
@export var portee_indicative := 520.0:
	set(v):
		portee_indicative = v
		queue_redraw()

@onready var _cable: Line2D = $Cable
var _actif := false


func _ready() -> void:
	add_to_group("GRAPPIN")
	_cable.width = epaisseur_cable
	_cable.default_color = couleur_cable
	_cable.visible = false
	queue_redraw()


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


func cable_cacher() -> void:
	_cable.visible = false


# ---------------------------------------------------------------------------

func _draw() -> void:
	var c := couleur_active if _actif else couleur_anneau
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 28, c, 4.0 if _actif else 3.0)
	draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 16, c, 2.0)
	if Engine.is_editor_hint():
		draw_arc(Vector2.ZERO, portee_indicative, 0.0, TAU, 64, Color(couleur_anneau, 0.25), 1.5)
