extends Node2D
## ============================================================================
## SANG CORROMPU — le POISON (1er oct. 2026) — talisman « Sang corrompu » (id
## "corrompu", idée de Kaoru : « une bloodball qui empoisonne, violette/mauve,
## qui change aussi la tornade, et fait des dégâts sur la durée ») : l'ennemi
## touché par la boule corrompue perd `degats` PV toutes les `intervalle` s
## pendant `duree` s (Canon de verre compris), sans recul ni éclair blanc
## (BASE_IA : l'étiquette "poison"). Un nouveau coup corrompu (une boule, ou
## l'épée avec la Lame corrompue) le PROLONGE : il dure `duree` s après le
## dernier (pas de cumul) ; ses morsures gardent leur rythme — remises à zéro à
## chaque coup, une épée qui frappe toutes les 0,4 s les repoussait sans fin.
## Le poison peut tuer : le joueur est l'attaquant (les chauves-souris de
## l'Essaim sortent).
##
## À l'écran : le monstre vire au violet (BASE_IA.teinter → hit_flash.gdshader,
## la teinte est MULTIPLIÉE : l'encre reste noire), plus fort à chaque morsure,
## et des volutes violettes montent de son corps (nœud Volutes,
## poison_sang.gdshader). Le nœud suit l'ennemi ; il est rangé sur lui (méta
## "poison"). Posé par player.gd (`empoisonner`), appelé par bloodball.gd
## quand une boule corrompue touche, et par animator.gd quand une lame
## corrompue porte (le coup, et l'éclair de la Lame de foudre).
##
## POUR LE JUGER : ouvrir la scène et faire F6 (les volutes seules, une
## morsure toutes les `intervalle` s, en boucle — seulement lancé seul).
## ============================================================================

## lancé seul (F6) : les volutes en boucle
@export var demo_boucle := true
## la teinte du monstre empoisonné (multipliée) ; sa force au repos et au
## moment d'une morsure (elle y retombe en `duree_pulse` s)
@export var teinte := Color(0.72, 0.45, 1.0)
@export_range(0.0, 1.0) var teinte_repos := 0.55
@export_range(0.0, 1.0) var teinte_morsure := 1.0
@export var duree_pulse := 0.3
## le poison apparaît, et s'éteint, en… (s)
@export var duree_fondu := 0.2

## posés par le joueur (player.gd, `empoisonner`)
var joueur: CharacterBody2D = null
var cible: Node2D = null
var degats := 15
var intervalle := 0.5
var duree := 3.0

const META := "poison"

@onready var _volutes: ColorRect = $Volutes

var _t := 0.0             # depuis la pose du poison (s) : le rythme des morsures
var _fin_prevue := 0.0    # quand il s'éteint (s, sur `_t`)
var _prochaine := 0.0     # la prochaine morsure (s, sur `_t`)
var _vie := 0.0           # depuis l'apparition (s) : le fondu d'entrée
var _pulse := 10.0        # depuis la dernière morsure (s)
var _fin := -1.0          # le poison s'éteint (s ; < 0 : non)
var _temps := 0.0         # l'horloge des volutes
var _demo := false
var _graine := 0.0


func _ready() -> void:
	_graine = randf() * 10.0
	_prochaine = intervalle
	_fin_prevue = duree
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
	elif is_instance_valid(cible):
		cible.set_meta(META, self)
		global_position = _centre(cible)
	else:
		queue_free()
		return
	_appliquer()


## un nouveau coup corrompu l'a touché : le poison dure encore `duree` s à
## partir de maintenant (ses morsures gardent leur rythme)
func relancer() -> void:
	if _fin >= 0.0:
		_fin = -1.0
		_vie = duree_fondu
	_fin_prevue = _t + duree


func _physics_process(delta: float) -> void:
	_temps += delta
	_vie += delta
	_pulse += delta
	if _demo:
		_t += delta
		if _t >= _prochaine:
			_prochaine += intervalle
			_pulse = 0.0
		_appliquer()
		return
	if _fin >= 0.0:
		_fin += delta
		if _fin >= duree_fondu:
			_finir()
			return
	elif not is_instance_valid(cible) or cible.hp <= 0:
		_fin = 0.0
	else:
		global_position = _centre(cible)
		_t += delta
		if _t >= _prochaine:
			_prochaine += intervalle
			_mordre()
		if _t >= _fin_prevue:
			_fin = 0.0
	_appliquer()


## une morsure du poison
func _mordre() -> void:
	_pulse = 0.0
	var qui: Node = joueur if is_instance_valid(joueur) else null
	var d := maxi(degats, 1)          # (le Canon de verre ne double que l'épée et l'Ombre)
	cible.apply_damage(d, cible.global_position.x, "poison", false, qui)
	print("[POISON] f=", Engine.get_physics_frames(), " morsure : ", d, " dégâts (",
		snappedf(_t, 0.01), " s)")


func _finir() -> void:
	if is_instance_valid(cible):
		if cible.has_method("teinter"):
			cible.teinter(teinte, 0.0)
		if cible.has_meta(META) and cible.get_meta(META) == self:
			cible.remove_meta(META)
	queue_free()


func _centre(c: Node2D) -> Vector2:
	if c is BaseAI and c.collision != null:
		return c.collision.global_position     # le milieu du corps, pas ses pieds
	return c.global_position


func _appliquer() -> void:
	var fondu := clampf(_vie / maxf(duree_fondu, 0.001), 0.0, 1.0)
	if _fin >= 0.0:
		fondu *= 1.0 - clampf(_fin / maxf(duree_fondu, 0.001), 0.0, 1.0)
	var morsure := 1.0 - clampf(_pulse / maxf(duree_pulse, 0.001), 0.0, 1.0)
	# le monstre vire au violet, plus fort à chaque morsure
	if not _demo and is_instance_valid(cible) and cible.has_method("teinter"):
		cible.teinter(teinte, fondu * lerpf(teinte_repos, teinte_morsure, morsure))
	var m := _volutes.material as ShaderMaterial
	if m != null:
		m.set_shader_parameter("taille", _volutes.size)
		m.set_shader_parameter("origine", -_volutes.position)
		m.set_shader_parameter("force", fondu)
		m.set_shader_parameter("morsure", morsure)
		m.set_shader_parameter("temps", _temps)
		m.set_shader_parameter("graine", _graine)
