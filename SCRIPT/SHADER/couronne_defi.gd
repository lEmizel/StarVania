extends Node2D
## ============================================================================
## COURONNE DU DÉFI (1er oct. 2026) — talisman « Couronne du défi » (id "defi") :
## tant qu'il est porté, une COURONNE D'OR tourne
## au-dessus de la tête du héros (couronne_defi.gdshader : fleurons et perles,
## rubis, reflet qui la balaie, étincelles). Visuel seul : le défi lui-même
## (un seul cœur, les autres talismans verrouillés) est dans l'autoload Player
## (`equiper_talisman`, `add_max_hp`). Elle se POSE quand on la met, s'EFFACE
## quand on l'ôte, et flotte doucement.
## Enfant du joueur (player.gd, `_couronne_defi_preparer`), créée une fois.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (elle se pose au milieu de
## l'écran, tourne, puis s'efface et revient, en boucle). Son allure : sur le
## matériau du nœud Couronne.
## ============================================================================

## lancée seule (F6) : posée, tenue, effacée, en boucle
@export var demo_boucle := true
## où elle flotte (repère du joueur : ses pieds à 0) — son bas reste vers −172,
## juste au-dessus des cheveux à leur plus haut (−170, coups d'épée compris ;
## au repos ils sont vers −148)
@export var hauteur := -188.0
## sa taille (1 = celle du dessin du shader ; à 1, elle est trop grosse)
@export var echelle := 0.65

const TALISMAN := "defi"
const DUREE_POSE := 0.12
const DUREE_EFFACE := 0.3

@onready var _couronne: ColorRect = $Couronne

var _t := 0.0                  # depuis qu'elle est posée (s)
var _efface_t := -1.0          # >= 0 : elle s'efface
var _portee := false
var _demo := false


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
	else:
		position = Vector2(0.0, hauteur)
	scale = Vector2(echelle, echelle)
	visible = false
	_appliquer()


func _process(delta: float) -> void:
	var porte := _porte_maintenant()
	if porte and not _portee:
		# on la met : elle se pose
		_portee = true
		_t = 0.0
		_efface_t = -1.0
		visible = true
	elif not porte and _portee:
		# on l'ôte : elle s'efface
		_portee = false
		_efface_t = 0.0
	if not visible:
		return
	_t += delta
	if _efface_t >= 0.0:
		_efface_t += delta
		if _efface_t >= DUREE_EFFACE:
			_efface_t = -1.0
			visible = false
			return
	# elle flotte doucement
	var base := get_viewport_rect().size * 0.5 if _demo else Vector2(0.0, hauteur)
	position = base + Vector2(0.0, sin(_t * 2.6) * 3.0)
	rotation = sin(_t * 1.7) * 0.04
	_appliquer()


func _porte_maintenant() -> bool:
	if _demo:
		return not _portee or _t < 5.0     # F6 : 5 s portée, puis ôtée, en boucle
	return Player.talisman_equipe(TALISMAN)


func _appliquer() -> void:
	var mat := _couronne.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _couronne.size)
	mat.set_shader_parameter("apparition", clampf(_t / DUREE_POSE, 0.0, 1.0))
	mat.set_shader_parameter("efface", clampf(_efface_t / DUREE_EFFACE, 0.0, 1.0) if _efface_t >= 0.0 else 0.0)
	mat.set_shader_parameter("temps", _t)
