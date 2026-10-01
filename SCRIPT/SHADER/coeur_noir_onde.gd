extends Node2D
## ============================================================================
## L'ONDE DU CŒUR NOIR (1er oct. 2026) — talisman « Cœur noir » (id
## "coeur_noir", idée de Kaoru) : posée par le joueur quand son cœur noir se
## brise (player.gd, `_coeur_noir_eclater`), au milieu de son corps. Le cœur
## éclate (une tache noire, des éclats), une onde noire court jusqu'au bord de
## l'écran, et chaque monstre de `cibles` (ceux qui étaient VISIBLES À L'ÉCRAN,
## Kaoru : « autour de nous ou visibles à l'écran, c'est le mieux ») est frappé
## AU MOMENT OÙ L'ONDE L'ATTEINT : `degats`, avec recul. Elle reste là où elle
## est née (le héros peut bouger) et se supprime seule.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (elle éclate au milieu de
## l'écran, en boucle). Couleurs, épaisseur : sur le matériau.
## ============================================================================

## lancée seule (F6) : elle éclate en boucle
@export var demo_boucle := true
## le temps que met l'onde à atteindre `rayon_max` (s)
@export var duree := 0.55

## posés par le joueur
var joueur: Node2D = null
var degats := 0
var rayon_max := 560.0
## les monstres à frapper : [{"noeud": Node2D, "distance": float}]
var cibles: Array = []

@onready var _dessin: ColorRect = $Dessin
var _t := 0.0
var _demo := false
var _frappes := {}


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
		rayon_max = 500.0
	_appliquer()


func _physics_process(delta: float) -> void:
	_t += delta
	var progres := clampf(_t / maxf(duree, 0.001), 0.0, 1.0)
	var rayon := rayon_max * (1.0 - pow(1.0 - progres, 2.2))
	# chaque monstre est frappé quand l'onde l'atteint
	for c in cibles:
		var m = c["noeud"]
		var id: int = c["id"]
		if _frappes.has(id) or rayon < float(c["distance"]):
			continue
		_frappes[id] = true
		if is_instance_valid(m) and m.hp > 0:
			var porte = m.apply_damage(degats, global_position.x, "coeur_noir", true, joueur)
			print("[CŒUR NOIR] f=", Engine.get_physics_frames(), " ", m.name, " frappé par l'onde : ", degats,
				" dégâts", "" if porte != false else " (n'a pas porté)")
	if _t >= duree + 0.1:
		if _demo:
			_t = -0.5
		else:
			queue_free()
			return
	_appliquer()


func _appliquer() -> void:
	var mat := _dessin.material as ShaderMaterial
	if mat == null:
		return
	var cote := (rayon_max + 40.0) * 2.0
	_dessin.size = Vector2(cote, cote)
	_dessin.position = -_dessin.size * 0.5
	mat.set_shader_parameter("taille", _dessin.size)
	mat.set_shader_parameter("rayon_max", rayon_max)
	mat.set_shader_parameter("progres", clampf(_t / maxf(duree, 0.001), 0.0, 1.0))
	mat.set_shader_parameter("temps", maxf(_t, 0.0))
