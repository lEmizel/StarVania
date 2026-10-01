@tool
extends Node2D
## ============================================================================
## ÉPINES DE SANG (1er oct. 2026) — le talisman : quand le joueur encaisse un
## coup, des pics de sang cristallisé jaillissent de tout son corps jusqu'à la
## portée des dégâts, puis se brisent.
##
## VISUEL SEUL : les dégâts et le recul sont faits par le joueur au même
## instant, sur le même rayon (player.gd, `_epines_jaillir`, réglages
## `epines_*`). Posé au milieu de son corps, enfant du joueur : les pics sortent
## de LUI et le suivent pendant qu'il recule ; derrière son sprite, pour qu'il
## reste lisible au milieu. Au sol (`sol_monde` fourni par le joueur), les pics
## ne partent que vers le haut et les côtés, et rien ne passe sous le sol ; en
## l'air, étoile complète. Se supprime à la fin.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (en boucle au milieu de l'écran,
## seulement lancée seule). Dans l'éditeur, le curseur `progression` la
## parcourt. L'allure se règle sur le matériau du nœud Pics ; la portée, c'est
## `rayon` (en jeu, celle du joueur).
## ============================================================================

## durée de l'effet entier (s)
@export var duree := 0.5
## portée des pics depuis le milieu du corps (px) — en jeu, `epines_rayon` du
## joueur (la portée des dégâts)
@export var rayon := 200.0:
	set(v):
		rayon = maxf(v, 10.0)
		_cadrer()
		_appliquer()
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.01) var progression := 0.0:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## lancée seule (F6) : rejoue en boucle au lieu de se supprimer
@export var demo_boucle := true
@export var demo_pause := 0.5
## graine : 0 = tirée au hasard à chaque éruption
@export var graine := 0.0
## aperçu (éditeur, F6) : comme au sol, le sol à `apercu_sol` px sous le milieu
## du corps ; sinon comme en l'air
@export var apercu_au_sol := true:
	set(v):
		apercu_au_sol = v
		_appliquer()
@export var apercu_sol := 63.0

## en jeu : la hauteur du SOL dans le monde, fournie par le joueur quand il est
## au sol (INF = en l'air). Recalculée à chaque image par rapport au nœud : le
## joueur bouge (recul, soulèvement), le sol, lui, reste où il est.
var sol_monde := INF

@onready var _pics: ColorRect = $Pics

var _t := 0.0
var _demo := false
var _graine_effective := 0.0


func _ready() -> void:
	_graine_effective = graine if graine != 0.0 else randf_range(1.0, 100.0)
	_cadrer()
	if Engine.is_editor_hint():
		_appliquer()
		return
	# la boucle de démo n'existe que lancée seule, jamais posée dans un jeu
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
	_appliquer()


## le rectangle couvre la portée, plus ce que la casse envoie au-delà
func _cadrer() -> void:
	if not is_node_ready():
		return
	var cote := 2.0 * (rayon + 160.0)
	_pics.size = Vector2(cote, cote)
	_pics.position = -_pics.size * 0.5


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	if _t < duree:
		progression = _t / maxf(duree, 0.001)
		return
	if _demo:
		progression = 1.0
		if _t >= duree + demo_pause:
			_t = 0.0
			if graine == 0.0:
				_graine_effective = randf_range(1.0, 100.0)
		return
	queue_free()


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _pics.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("progress", progression)
	mat.set_shader_parameter("taille", _pics.size)
	mat.set_shader_parameter("rayon", rayon)
	mat.set_shader_parameter("graine", _graine_effective)
	mat.set_shader_parameter("duree", duree)
	var sol := 100000.0
	if is_finite(sol_monde) and not Engine.is_editor_hint():
		sol = sol_monde - global_position.y
	elif (Engine.is_editor_hint() or _demo) and apercu_au_sol:
		sol = apercu_sol
	mat.set_shader_parameter("sol", sol)
