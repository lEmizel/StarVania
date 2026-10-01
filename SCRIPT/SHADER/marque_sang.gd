@tool
extends Node2D
## ============================================================================
## MARQUE DE SANG (1er oct. 2026) — talisman « marque » : la rune que la boule
## de sang (et la tornade) pose au-dessus de l'ennemi qu'elle touche. Le
## prochain coup d'épée qui PORTE sur lui fait `marque_multiplicateur` (réglage
## du joueur) fois ses dégâts et la fait ÉCLATER ; sinon elle s'efface au bout
## de `duree` s, ou si l'ennemi meurt. Son anneau est un compte à rebours.
##
## API (statique), appelée par bloodball.gd et animator.gd :
##   poser(ennemi)       — le marque (déjà marqué : la durée repart)
##   est_marque(ennemi)  — la marque est-elle là, et vivante ?
##   consommer(ennemi)   — le coup a porté : elle éclate et s'en va
## La rune est un nœud enfant de l'ennemi nommé « MarqueSang », au-dessus du
## haut de sa forme de collision ; elle n'est pas retournée avec lui.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (posée, tenue, éclatée, en
## boucle ; seulement lancée seule). L'allure se règle sur le matériau du nœud
## Rune.
## ============================================================================

const NOM := "MarqueSang"
const CHEMIN_SCENE := "res://SCRIPT/SHADER/marque_sang.tscn"
const DUREE_POSE := 0.14
const DUREE_ECLAT := 0.28
const DUREE_EFFACE := 0.3

## combien de temps la marque attend le coup d'épée (s)
@export var duree := 6.0
## de combien elle flotte au-dessus du haut du corps (px)
@export var hauteur := 34.0
## lancée seule (F6) : posée, tenue, éclatée, en boucle
@export var demo_boucle := true

@onready var _rune: ColorRect = $Rune

var _t := 0.0
var _etat := 0          # 0 = elle vit ; 1 = elle éclate (coup porté) ; 2 = elle s'efface
var _t_fin := 0.0
var _demo := false
var _ennemi: Node = null
var _y_base := 0.0


# --- l'API ------------------------------------------------------------------

## l'ennemi porte-t-il une marque vivante ?
static func est_marque(n: Node) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	var m = n.get_node_or_null(NOM)
	return m != null and m.vivante()


## marque l'ennemi (ou fait repartir sa marque) ; jamais un mort
static func poser(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	if n.has_method("_is_dead") and n._is_dead():
		return
	var m = n.get_node_or_null(NOM)
	if m != null and m.vivante():
		m.rafraichir()
		return
	if m != null:
		m.name = NOM + "_fin"    # l'ancienne finit de partir sous un autre nom
	var nouvelle = load(CHEMIN_SCENE).instantiate()
	nouvelle.demo_boucle = false
	nouvelle.name = NOM
	n.add_child(nouvelle)
	nouvelle.placer_sur(n)
	print("[MARQUE] posée sur ", n.name)


## le coup d'épée a porté sur un ennemi marqué : la marque éclate
static func consommer(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	var m = n.get_node_or_null(NOM)
	if m != null:
		m.eclater()


# --- la rune ----------------------------------------------------------------

func _ready() -> void:
	z_index = 5             # devant l'ennemi
	if Engine.is_editor_hint():
		_appliquer()
		return
	# la boucle de démo n'existe que lancée seule, jamais posée dans un jeu
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
		_y_base = position.y
	_appliquer()


func vivante() -> bool:
	return _etat == 0


## remarquée : le compte à rebours repart, avec un nouveau coup de tampon
func rafraichir() -> void:
	_t = 0.0


func eclater() -> void:
	if _etat != 0:
		return
	_etat = 1
	_t_fin = 0.0
	name = NOM + "_fin"      # plus « la » marque : une boule peut en poser une neuve


func _effacer() -> void:
	if _etat != 0:
		return
	_etat = 2
	_t_fin = 0.0
	name = NOM + "_fin"


## au-dessus de la tête de l'ennemi : au-dessus de sa BARRE DE VIE s'il en a une
## (elle flotte au-dessus de sa tête, et la rune posée dessus la cachait),
## sinon au-dessus du haut de sa forme de collision
func placer_sur(n: Node) -> void:
	_ennemi = n
	var haut := -80.0
	var col = n.get("collision")
	if col is CollisionShape2D and col.shape != null:
		var r: Rect2 = col.shape.get_rect()
		haut = col.position.y + r.position.y
	var barre = n.get("vie")
	if barre is Node2D:
		haut = minf(haut, (barre as Node2D).position.y)
	position = Vector2(0.0, haut - hauteur)
	_y_base = position.y


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	if _etat == 0:
		var mort: bool = _ennemi != null and (not is_instance_valid(_ennemi) \
				or (_ennemi.has_method("_is_dead") and _ennemi._is_dead()))
		if _demo and _t >= 1.6:
			eclater()
		elif _t >= duree or mort:
			_effacer()
	else:
		_t_fin += delta
		if _t_fin >= (DUREE_ECLAT if _etat == 1 else DUREE_EFFACE):
			if _demo:
				_etat = 0
				_t = 0.0
				name = NOM
			else:
				queue_free()
				return
	# elle flotte doucement
	position.y = _y_base + sin(_t * 3.0) * 2.5
	_appliquer()


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _rune.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _rune.size)
	mat.set_shader_parameter("apparition", 1.0 if Engine.is_editor_hint() else clampf(_t / DUREE_POSE, 0.0, 1.0))
	mat.set_shader_parameter("restant", 1.0 if Engine.is_editor_hint() else clampf(1.0 - _t / maxf(duree, 0.001), 0.0, 1.0))
	mat.set_shader_parameter("eclat", clampf(_t_fin / DUREE_ECLAT, 0.0, 1.0) if _etat == 1 else 0.0)
	mat.set_shader_parameter("efface", clampf(_t_fin / DUREE_EFFACE, 0.0, 1.0) if _etat == 2 else 0.0)
