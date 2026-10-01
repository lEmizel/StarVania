extends Node2D
## ============================================================================
## ROUE DU TROP-PLEIN (2 oct. 2026) — le signal du talisman « Trop-plein » (id
## "trop_plein", choisi par Kaoru), faite comme la JAUGE D'ENDURANCE de Zelda
## (sa demande) : un anneau de sang flotte au-dessus de l'épaule, côté dos, et se
## REMPLIT EN TOURNANT d'un tiers à chaque coup d'épée qui porte (« plop », le
## tiers gagné s'éclaire) ; PLEINE, son cœur se remplit d'une boule de sang qui
## bat : la prochaine boule de sang sortira grosse et forte. Au lancer de cette
## boule, elle CRÈVE (player.gd, `bloodball_enter` → `crever`).
## Visuel seul : le compte des coups est sur le joueur (`trop_plein_coups`,
## `trop_plein_charger`). Enfant du joueur (`_trop_plein_preparer`), créée une
## fois ; elle se montre et se cache seule.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (elle se remplit coup par coup,
## bat pleine, puis crève, en boucle). Son allure : sur le matériau du nœud
## Roue.
## ============================================================================

## lancée seule (F6) : remplie, pleine, crevée, en boucle
@export var demo_boucle := true
## où elle flotte (repère du joueur : ses pieds à 0 ; x pour un héros tourné
## vers la DROITE, retourné avec lui) : un peu au-dessus de l'épaule, côté dos,
## à l'écart de la tête (le haut des cheveux est vers −148 au repos)
@export var position_dos := Vector2(-58.0, -150.0)
## vivacité de sa glissade d'un côté à l'autre quand il se retourne (par s)
@export var glissade := 12.0
## durée de la crevaison (s)
@export var duree_eclat := 0.28

const TALISMAN := "trop_plein"

var joueur: Node2D

@onready var _roue: ColorRect = $Roue

var _t := 0.0
var _coups := 0                 # le compte vu à l'image d'avant
var _requis := 3
var _rempli := 0.0              # la part affichée (0 → 1), qui rattrape le compte
var _plein := 0.0
var _flash := 0.0
var _gonfle := 1.0              # ressort du « plop »
var _gonfle_v := 0.0
var _eclat_t := -1.0            # >= 0 : elle crève
var _demo := false
var _demo_t := 0.0


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
		scale = Vector2(3.0, 3.0)
	visible = false
	_appliquer()


func _process(delta: float) -> void:
	_t += delta
	var n := 0
	if _demo:
		_requis = 3
		n = _demo_compte(delta)
	elif joueur != null and is_instance_valid(joueur):
		_requis = maxi(int(joueur.trop_plein_coups_requis), 1)
		if Player.talisman_equipe(TALISMAN):
			n = int(joueur.trop_plein_coups)
	if n > _coups:
		# un coup qui porte : elle (ré)apparaît, ou gagne un tiers
		if _coups == 0 and _eclat_t < 0.0:
			_gonfle = 0.25
			_gonfle_v = 0.0
			_rempli = 0.0
		_gonfle_v += 3.2
		_flash = 1.0
	_coups = n
	var cible := clampf(float(n) / float(_requis), 0.0, 1.0)

	if _eclat_t >= 0.0:
		_eclat_t += delta
		if _eclat_t >= duree_eclat:
			_eclat_t = -1.0
	var montre := n > 0 or _eclat_t >= 0.0
	visible = montre
	if not montre:
		_rempli = 0.0
		_plein = 0.0
		return

	if _eclat_t < 0.0:
		_rempli = lerpf(_rempli, cible, 1.0 - exp(-12.0 * delta))
	_flash = maxf(_flash - delta * 3.0, 0.0)
	_plein = move_toward(_plein, 1.0 if (n >= _requis and _eclat_t < 0.0) else 0.0, delta * 6.0)
	# le « plop » : un ressort amorti
	var acc := (1.0 - _gonfle) * 260.0 - _gonfle_v * 18.0
	_gonfle_v += acc * delta
	_gonfle += _gonfle_v * delta

	if not _demo and joueur != null and is_instance_valid(joueur):
		# au-dessus de l'épaule, côté dos ; elle glisse quand il se retourne
		var f := signf(joueur.point.scale.x) if joueur.point != null else 1.0
		var cible_pos := Vector2(position_dos.x * f, position_dos.y)
		position = position.lerp(cible_pos, 1.0 - exp(-glissade * delta))
		position.y = position_dos.y + sin(_t * 2.4) * 2.0
	_appliquer()


## la grosse boule part : la roue crève
func crever() -> void:
	_eclat_t = 0.0
	visible = true
	_appliquer()


## F6 : un coup toutes les 0,7 s, 2,6 s pleine, puis elle crève
func _demo_compte(delta: float) -> int:
	_demo_t += delta
	var cycle := 0.7 * 3.0 + 2.6 + duree_eclat + 0.5
	if _demo_t >= cycle:
		_demo_t -= cycle
	if _demo_t < 0.4:
		return 0
	if _demo_t >= 0.4 + 0.7 * 2.0 + 2.6:
		if _eclat_t < 0.0 and _coups >= 3:
			crever()
		return 0
	return mini(int((_demo_t - 0.4) / 0.7) + 1, 3)


func _appliquer() -> void:
	var mat := _roue.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _roue.size)
	mat.set_shader_parameter("centre", -_roue.position)
	mat.set_shader_parameter("rempli", clampf(_rempli, 0.0, 1.0))
	mat.set_shader_parameter("crans", float(_requis))
	mat.set_shader_parameter("plein", _plein)
	mat.set_shader_parameter("flash", _flash)
	mat.set_shader_parameter("gonfle", maxf(_gonfle, 0.05))
	mat.set_shader_parameter("eclat", clampf(_eclat_t / duree_eclat, 0.0, 1.0) if _eclat_t >= 0.0 else 0.0)
	mat.set_shader_parameter("temps", _t)
