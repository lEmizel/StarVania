@tool
extends Node2D
## ============================================================================
## COURONNE DE VENGEANCE (1er oct. 2026) — talisman « Vengeance » : tant que la
## vengeance est chargée, cette couronne de sang flotte au-dessus du perso.
## Depuis la v2 du même jour elle est EN VOLUME : un anneau vu de trois quarts
## qui tourne lentement, des pointes devant et derrière, un dégradé, des
## gouttes (tout est dans couronne_vengeance.gdshader)
## (idée de Kaoru : on ne voit pas l'épée hors des coups). Visuel seul : le
## joueur la charge (player.gd, `_vengeance_charger`), elle ne fait que le
## montrer. Depuis que la vengeance renforce TOUS les coups d'épée pendant sa
## durée (elle ne s'use plus au premier), la couronne tient tout ce temps : ses
## pointes rentrent avec le temps qui reste, et elle BAT à chaque coup vengeur.
##
## API : `lever(duree)` (posée, ou reposée : le compte repart), `battre()` (un
## coup vengeur vient de porter), `effacer()` (le temps a passé). `eclater()`
## (la couronne éclate) n'est plus appelée par le jeu : gardée pour un usage à
## venir. Enfant du joueur, au-dessus de sa tête (`couronne_position` du
## joueur) ; elle oscille doucement.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (posée, elle bat de temps en
## temps, puis s'efface au bout de 5 s, en boucle ; seulement lancée seule). Le
## curseur `progression` de l'éditeur montre le temps qui passe. L'allure se
## règle sur le matériau du nœud Couronne.
## ============================================================================

const DUREE_POSE := 0.12
const DUREE_ECLAT := 0.26
const DUREE_EFFACE := 0.3
## le battement d'un coup vengeur : sa durée (s) et de combien elle grossit
const DUREE_POULS := 0.18
const AMPLEUR_POULS := 0.28

## lancée seule (F6) : posée, tenue, éclatée, en boucle
@export var demo_boucle := true
## aperçu dans l'éditeur : 1 = tout juste posée, 0 = son temps est écoulé
@export_range(0.0, 1.0, 0.01) var progression := 1.0:
	set(v):
		progression = v
		_appliquer()

@onready var _couronne: ColorRect = $Couronne

var _duree := 3.0
var _t := 0.0
var _etat := 0          # 0 = cachée ; 1 = elle tient ; 2 = elle éclate ; 3 = elle s'efface
var _t_fin := 0.0
var _demo := false
var _y_base := 0.0
var _pouls := 0.0       # temps restant du battement en cours


func _ready() -> void:
	if Engine.is_editor_hint():
		_appliquer()
		return
	visible = false
	# la boucle de démo n'existe que lancée seule, jamais posée dans un jeu
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
		lever(5.0)


## la vengeance se charge (ou repart) : la couronne se pose
func lever(duree: float) -> void:
	_duree = maxf(duree, 0.01)
	_t = 0.0
	_t_fin = 0.0
	_etat = 1
	_y_base = position.y
	_pouls = 0.0
	scale = Vector2.ONE
	visible = true
	_appliquer()


## un coup d'épée vengeur vient de porter : la couronne bat (elle ne s'use pas)
func battre() -> void:
	if _etat != 1:
		return
	_pouls = DUREE_POULS


## la vengeance s'abat : la couronne éclate
func eclater() -> void:
	if _etat != 1:
		return
	_etat = 2
	_t_fin = 0.0


## le temps a passé : la couronne s'efface
func effacer() -> void:
	if _etat != 1:
		return
	_etat = 3
	_t_fin = 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _etat == 0:
		return
	_t += delta
	if _etat == 1:
		if _demo:
			# la démo : elle bat de temps en temps, puis son temps s'écoule
			if int(_t / 1.2) != int((_t - delta) / 1.2):
				battre()
			if _t >= _duree:
				effacer()
	else:
		_t_fin += delta
		if _t_fin >= (DUREE_ECLAT if _etat == 2 else DUREE_EFFACE):
			_etat = 0
			visible = false
			if _demo:
				lever(_duree)
			return
	# elle flotte doucement
	position.y = _y_base + sin(_t * 3.2) * 3.0
	rotation = sin(_t * 2.1) * 0.05
	# elle bat : une bosse de taille, brève
	if _pouls > 0.0:
		_pouls = maxf(_pouls - delta, 0.0)
		scale = Vector2.ONE * (1.0 + AMPLEUR_POULS * sin(PI * (1.0 - _pouls / DUREE_POULS)))
	else:
		scale = Vector2.ONE
	_appliquer()


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _couronne.material as ShaderMaterial
	if mat == null:
		return
	var editeur := Engine.is_editor_hint()
	mat.set_shader_parameter("taille", _couronne.size)
	mat.set_shader_parameter("apparition", 1.0 if editeur else clampf(_t / DUREE_POSE, 0.0, 1.0))
	mat.set_shader_parameter("restant", progression if editeur else clampf(1.0 - _t / _duree, 0.0, 1.0))
	mat.set_shader_parameter("eclat", clampf(_t_fin / DUREE_ECLAT, 0.0, 1.0) if _etat == 2 else 0.0)
	mat.set_shader_parameter("efface", clampf(_t_fin / DUREE_EFFACE, 0.0, 1.0) if _etat == 3 else 0.0)
	# elle tourne, ses gouttes tombent ; elle s'éclaire quand elle bat
	mat.set_shader_parameter("temps", 0.0 if editeur else _t)
	mat.set_shader_parameter("pouls", sin(PI * (1.0 - _pouls / DUREE_POULS)) if _pouls > 0.0 else 0.0)
