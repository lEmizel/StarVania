@tool
extends Node2D
## ============================================================================
## BOUCLIER DE SANG — la bulle rouge à facettes hexagonales du talisman
## « Bouclier de sang » (30 sept. 2026). Visuel ET horloge : c'est ce nœud qui
## sait combien de temps le bouclier tient ; le joueur lui demande `actif()`.
##
## USAGE EN JEU : player.gd en garde un, enfant du joueur, posé au milieu du
## corps. `lever(duree, cote)` le dresse depuis le côté d'où le coup est venu
## (`cote` = vecteur unitaire, en coordonnées de bulle : (-1, 0) = la gauche),
## `bloquer(cote)` fait courir l'onde d'une parade, `tomber()` le fait se
## refermer avant l'heure (mort). Il se referme seul à la fin de `duree` et
## émet `tombe`.
##
## POUR LE JUGER : ouvrir la scène et faire F6, `demo_boucle` le rejoue en
## boucle (montée, une parade, clignotement, chute). Dans l'éditeur, le curseur
## `progression` montre n'importe quel instant : 0 → 0,15 la montée, 0,5 une
## parade, 0,85 → 1 la chute. L'allure (facettes, arêtes, couleurs, bombé) se
## règle sur le matériau du nœud Bulle.
## ============================================================================

signal tombe

## demi-axes de la bulle (px) : elle doit englober le perso avec de la marge.
## RONDE, pas ovale : les deux égaux
@export var rayons := Vector2(120.0, 120.0):
	set(v):
		rayons = v
		_placer()
## place laissée autour de la bulle pour sa lueur (px)
@export var marge := 24.0:
	set(v):
		marge = v
		_placer()
## durées de la montée et de la chute (s)
@export var duree_montee := 0.22
@export var duree_chute := 0.3
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.005) var progression := 0.3:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## lancé seul (F6) : rejoue en boucle
@export var demo_boucle := true
## le bouclier tient tant de secondes dans la démo
@export var demo_duree := 2.0

@onready var _bulle: ColorRect = $Bulle

enum { ABSENT, LEVE, TOMBE }
var _phase := ABSENT
var _t := 0.0            # depuis la montée
var _t_chute := 0.0      # depuis le début de la chute
var _reste := 0.0        # secondes avant la chute
var _origine := Vector2(-1.0, 0.0)
var _onde_t := 99.0      # depuis la dernière parade (grand = aucune)
var _onde_origine := Vector2(1.0, 0.0)
var _graine := 0.0
var _demo := false


func _ready() -> void:
	_placer()
	if Engine.is_editor_hint():
		_appliquer()
		return
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
		lever(demo_duree, Vector2(-1.0, 0.0))
	else:
		visible = false


## true tant que le bouclier pare les coups (dès la montée, jusqu'à la chute)
func actif() -> bool:
	return _phase == LEVE


## secondes avant qu'il tombe (0 s'il n'est pas levé)
func restant() -> float:
	return _reste if _phase == LEVE else 0.0


## Dresse le bouclier pour `duree` secondes, depuis le côté `cote` d'où le coup
## est venu. Relevé pendant qu'il tient : son temps repart de zéro.
func lever(duree: float, cote: Vector2) -> void:
	if _phase != LEVE:
		_t = 0.0
		_graine = randf() * 100.0
		_origine = cote.normalized() if cote.length_squared() > 0.0001 else Vector2(-1.0, 0.0)
	_phase = LEVE
	_reste = duree
	_onde_t = 99.0
	visible = true
	_appliquer()


## un coup vient d'être paré depuis le côté `cote` : l'onde court sur la bulle
func bloquer(cote: Vector2) -> void:
	if _phase != LEVE:
		return
	_onde_t = 0.0
	_onde_origine = cote.normalized() if cote.length_squared() > 0.0001 else Vector2(1.0, 0.0)
	_appliquer()


## le bouclier se referme (fin de sa durée, ou mort du joueur)
func tomber() -> void:
	if _phase != LEVE:
		return
	_phase = TOMBE
	_t_chute = 0.0
	_reste = 0.0
	tombe.emit()
	_appliquer()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _phase == ABSENT:
		return
	_t += delta
	_onde_t += delta
	if _phase == LEVE:
		_reste -= delta
		# la démo pare un coup au milieu de sa vie
		if _demo and _reste < demo_duree * 0.5 and _reste + delta >= demo_duree * 0.5:
			bloquer(Vector2(1.0, 0.0))
		if _reste <= 0.0:
			tomber()
	elif _phase == TOMBE:
		_t_chute += delta
		if _t_chute >= duree_chute:
			_phase = ABSENT
			visible = false
			if _demo:
				await get_tree().create_timer(0.6).timeout
				lever(demo_duree, Vector2(-1.0, 0.0))
			return
	_appliquer()


func _placer() -> void:
	if _bulle == null:
		return
	_bulle.size = (rayons + Vector2(marge, marge)) * 2.0
	_bulle.position = -_bulle.size * 0.5
	var mat := _bulle.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("taille", _bulle.size)
		mat.set_shader_parameter("rayons", rayons)


func _appliquer() -> void:
	if _bulle == null:
		return
	var mat := _bulle.material as ShaderMaterial
	if mat == null:
		return
	var montee: float
	var chute: float
	var restant_s: float
	var onde: float
	var temps: float
	if Engine.is_editor_hint():
		# aperçu : montée, tenue (avec une parade au milieu), chute
		montee = clampf(progression / 0.15, 0.0, 1.0)
		chute = clampf((progression - 0.85) / 0.15, 0.0, 1.0)
		restant_s = 2.0 * (1.0 - progression)
		onde = absf(progression - 0.5) * 2.0
		temps = progression * 2.0
	else:
		montee = clampf(_t / maxf(duree_montee, 0.001), 0.0, 1.0)
		chute = clampf(_t_chute / maxf(duree_chute, 0.001), 0.0, 1.0) if _phase == TOMBE else 0.0
		restant_s = _reste
		onde = _onde_t
		temps = _t
	mat.set_shader_parameter("temps", temps)
	mat.set_shader_parameter("montee", montee)
	mat.set_shader_parameter("chute", chute)
	mat.set_shader_parameter("restant", restant_s)
	mat.set_shader_parameter("origine", _origine)
	mat.set_shader_parameter("onde", onde)
	mat.set_shader_parameter("onde_origine", _onde_origine)
	mat.set_shader_parameter("graine", _graine)
