extends Node2D
## ============================================================================
## ÉTOURDI (1er oct. 2026) — talisman « Parade » : le VISUEL d'un monstre
## sonné (BASE_IA.etourdir) — trois étoiles qui tournent au-dessus de sa tête
## (nœud Etoiles, etourdi.gdshader). Il suit sa tête et s'en va quand le monstre
## reprend ses esprits (ou meurt). Posé par BASE_IA.etourdir.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (les étoiles seules, en boucle).
## ============================================================================

## lancé seul (F6) : les étoiles en boucle au milieu de l'écran
@export var demo_boucle := true
## elles apparaissent en… ; elles s'en vont en… (s)
@export var duree_entree := 0.08
@export var duree_sortie := 0.15
## à quelle hauteur au-dessus du haut de sa forme de collision (px) : à 16,
## elles tournaient dans sa barre de vie
@export var au_dessus := 4.0

## posé par le monstre (BASE_IA.etourdir)
var monstre: Node2D = null

@onready var _etoiles: ColorRect = $Etoiles

var _t := 0.0
var _sortie := -1.0       # elles s'en vont (s ; < 0 : non)
var _demo := false


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
	elif is_instance_valid(monstre):
		global_position = _tete(monstre)
	else:
		queue_free()
		return
	_appliquer()


func _physics_process(delta: float) -> void:
	_t += delta
	if not _demo:
		var sonne: bool = is_instance_valid(monstre) and monstre.hp > 0 and monstre.est_etourdi()
		if sonne:
			global_position = _tete(monstre)
		elif _sortie < 0.0:
			_sortie = 0.0
		if _sortie >= 0.0:
			_sortie += delta
			if _sortie >= duree_sortie:
				queue_free()
				return
	_appliquer()


## le dessus de sa tête : le haut de sa forme de collision
func _tete(m: Node2D) -> Vector2:
	if m is BaseAI and m.collision != null:
		var c: CollisionShape2D = m.collision
		var demi := 40.0
		if c.shape is RectangleShape2D:
			demi = (c.shape as RectangleShape2D).size.y * 0.5
		elif c.shape is CapsuleShape2D:
			demi = (c.shape as CapsuleShape2D).height * 0.5
		elif c.shape is CircleShape2D:
			demi = (c.shape as CircleShape2D).radius
		demi *= absf(c.global_scale.y)
		return c.global_position - Vector2(0.0, demi + au_dessus)
	return m.global_position - Vector2(0.0, 100.0)


func _appliquer() -> void:
	var f := clampf(_t / maxf(duree_entree, 0.001), 0.0, 1.0)
	if _sortie >= 0.0:
		f *= 1.0 - clampf(_sortie / maxf(duree_sortie, 0.001), 0.0, 1.0)
	var m := _etoiles.material as ShaderMaterial
	if m != null:
		m.set_shader_parameter("taille", _etoiles.size)
		m.set_shader_parameter("temps", _t)
		m.set_shader_parameter("force", f)
