@tool
extends AnimatedSprite2D
## LAME DE SCIE : blesse comme les piques (les dégâts sont gérés par
## piques.gd attaché à l'Area2D enfant) et fait la navette entre deux
## positions posées depuis l'éditeur.
##
## SETUP dans l'éditeur : place la scie au point de départ → clique
## "Capturer position A" dans l'inspecteur, déplace-la au point d'arrivée
## → "Capturer position B". Le trajet s'affiche en rouge dans l'éditeur.
## Positions LOCALES au parent : déplacer le conteneur déplace le trajet.

@export var position_a := Vector2.ZERO
@export var position_b := Vector2.ZERO
@export_tool_button("Capturer position A") var _btn_a: Callable = _capturer_a
@export_tool_button("Capturer position B") var _btn_b: Callable = _capturer_b
## Vitesse de déplacement (px/s)
@export var vitesse := 200.0

var _vers_b := true  # sens courant de la navette


func _ready() -> void:
	play("idle")
	if Engine.is_editor_hint():
		return
	# en jeu : départ sur A si un trajet est configuré
	if position_a != position_b:
		position = position_a


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if position_a == position_b:
		return  # pas de trajet : scie statique
	var cible := position_b if _vers_b else position_a
	position = position.move_toward(cible, vitesse * delta)
	if position == cible:
		_vers_b = not _vers_b


func _capturer_a() -> void:
	position_a = position
	queue_redraw()


func _capturer_b() -> void:
	position_b = position
	queue_redraw()


# --- Aperçu du trajet dans l'éditeur ---

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if position_a == position_b:
		return
	# les positions sont dans l'espace du PARENT → conversion en local
	var a := position_a - position
	var b := position_b - position
	draw_line(a, b, Color(1.0, 0.3, 0.2, 0.7), 5.0)
	draw_circle(a, 14.0, Color(1.0, 0.3, 0.2, 0.9))
	draw_circle(b, 14.0, Color(1.0, 0.6, 0.2, 0.9))
