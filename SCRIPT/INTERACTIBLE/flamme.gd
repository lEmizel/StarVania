extends Node2D
## ============================================================================
## FLAMME DE TORCHE — la flamme posée sur les torches peintes des
## décors (flamme_cartoon, aux réglages de la scène), et depuis le 3 oct. 2026 son HALO
## (SCRIPT/SHADER/halo_torche.gdshader, d'après une image de référence) : une
## lueur ronde cernée d'un liseré, des braises qui montent.
## Ce script la fait VACILLER : la lueur du halo et l'intensité de sa lumière
## (PointLight2D, autour du réglage d'énergie de la scène) suivent le même souffle,
## irrégulier comme un feu — un bruit lent et un bruit vif mêlés. Chaque torche
## a le sien : elles ne battent pas ensemble.
## Seulement en jeu : dans l'éditeur, le halo reste à mi-souffle et rien n'est
## modifié dans la scène.
## ============================================================================

@onready var _halo: ColorRect = get_node_or_null("Halo")
@onready var _lumiere: PointLight2D = get_node_or_null("PointLight2D")

var _energie := 0.0                     # l'énergie réglée sur la lumière : la moyenne du vacillement
var _lent := 0.5
var _vise_lent := 0.5
var _attente_lent := 0.0
var _vif := 0.5
var _vise_vif := 0.5
var _attente_vif := 0.0


func _ready() -> void:
	if _lumiere != null:
		_energie = _lumiere.energy


func _process(delta: float) -> void:
	# deux souffles : un lent (la flamme monte et baisse) et un vif (elle frémit)
	_attente_lent -= delta
	if _attente_lent <= 0.0:
		_attente_lent = randf_range(0.35, 0.8)
		_vise_lent = randf()
	_attente_vif -= delta
	if _attente_vif <= 0.0:
		_attente_vif = randf_range(0.05, 0.12)
		_vise_vif = randf()
	_lent = lerpf(_lent, _vise_lent, 1.0 - exp(-delta * 3.0))
	_vif = lerpf(_vif, _vise_vif, 1.0 - exp(-delta * 18.0))
	var v := clampf(0.6 * _lent + 0.4 * _vif, 0.0, 1.0)
	if _halo != null and _halo.material is ShaderMaterial:
		(_halo.material as ShaderMaterial).set_shader_parameter("vacille", v)
	if _lumiere != null:
		_lumiere.energy = _energie * (0.8 + 0.4 * v)
