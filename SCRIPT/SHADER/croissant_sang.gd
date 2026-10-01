@tool
extends Area2D
## ============================================================================
## CROISSANT DE SANG (v2, 1er oct. 2026) — talisman « croissant » : le dernier
## coup du combo (le 2e : le combo n'en a que deux) projette son slash vers
## l'avant.
##
## IL NAÎT SUR LE SLASH DU HÉROS : animator.gd (`_process`) le crée un peu
## avant que la lame passe devant le perso, ATTACHÉ (`attache`) : posé sur le
## CENTRE du trajet du slash, il SUIT la lame image après image
## (`suivre_lame` : le TRAJET `forme`, l'étendue de la lame `queue0`/`tete0`,
## l'échelle du slash `echelle` — le talisman Allonge) et « prend » dessus, de
## rien à l'épaisseur de la lame : son croissant recouvre la lame blanche au
## pixel. Quand la lame est devant, l'animator le LÂCHE (`lacher`) : il s'en
## détache — son ouverture se centre sur l'avant en `pose` s — et file à
## `vitesse`, sur `portee` px. Il blesse UNE fois chaque ennemi qu'il traverse
## (`degats`, recul), puis s'éteint en maigrissant ; un mur l'arrête net (il
## s'efface sur place).
##
## Le mur se cherche par un RAYON horizontal, à mi-hauteur, du joueur jusqu'à
## son bord d'attaque puis devant lui à chaque pas (sa zone toucherait le SOL
## et le prendrait pour un mur ; et il naît loin devant le joueur : sans le
## premier rayon il pouvait naître de l'autre côté d'un mur). La zone ne
## cherche que les monstres.
##
## Il ne blesse pas les ennemis que le coup d'épée lui-même vient de toucher :
## sa zone ne mord qu'après `armement` s, et il ignore la liste des touchés du
## coup (`touches_du_coup`, partagée par l'animator) — sinon l'ennemi au
## contact prenait le coup ET le croissant.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (il file en boucle au milieu de
## l'écran, seulement lancé seul). L'allure (épaisseur, langues, dégradé, fil,
## filets, couleurs) se règle sur le matériau du nœud Lame.
## ============================================================================

## vitesse (px/s) et distance parcourue avant de s'éteindre (px). Son bord
## d'attaque part de ~180 px devant le joueur (là où est le slash) : il va
## aussi loin que la première version, qui partait à 40 px pour 480 de course.
@export var vitesse := 1000.0
@export var portee := 380.0
## délai avant que sa zone morde (s) : le coup d'épée passe d'abord
@export var armement := 0.05
## son ouverture en vol (rad, de part et d'autre de l'avant) et le temps qu'il
## met à la prendre en quittant le slash (s)
@export var demi_arc := 1.08
@export var pose := 0.09
## lancé seul (F6) : file en boucle
@export var demo_boucle := true

## posés par l'animator
var dir := 1
var degats := 70
var joueur: Node2D = null
var touches_du_coup: Array = []
## le trajet du slash dont il se détache (a0, a1, b1, a2, b2), l'étendue de la
## lame à cet instant (rad), l'échelle du slash — par défaut : `new_slash_1` au
## milieu de sa course
var forme: Array = [127.59, -10.0, -2.59, 17.62, 4.23]
var queue0 := -0.98
var tete0 := 1.35
var echelle := 1.0
## true tant qu'il « prend » sur la lame : il la suit (`suivre_lame`), sans
## avancer ni mordre, jusqu'à `lacher()`
var attache := false

@onready var _lame: ColorRect = $Lame

var _parcouru := 0.0
var _t := 0.0
var _deja: Array[Node] = []
var _fin := false
var _t_fin := 0.0
var _prog_fin := 0.0
var _demo := false
var _depart := Vector2.ZERO
var _graine := 0.0
var _x_sonde := 0.0       # jusqu'où la voie est libre (x monde)
var _amorce := 1.0        # 0 → 1 tant qu'il prend sur la lame
const DUREE_FIN := 0.1
## de combien le rayon s'arrête avant le bord d'attaque (px) : la lame vient
## toucher le mur
const RETRAIT_SONDE := 10.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_appliquer(0.3)
		return
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * Vector2(0.3, 0.5)
	_depart = position
	scale = Vector2(float(dir) * echelle, echelle)
	_graine = randf() * 10.0
	_x_sonde = joueur.global_position.x if joueur != null else global_position.x
	body_entered.connect(_on_body_entered)
	_appliquer(0.0)


## Attaché : posé sur le centre du trajet du slash (`centre`, monde), à
## l'étendue qu'a la lame à cet instant ; `amorce` 0 → 1 = il prend sur elle.
func suivre_lame(centre: Vector2, queue: float, tete: float, amorce: float) -> void:
	global_position = centre
	queue0 = queue
	tete0 = tete
	_amorce = clampf(amorce, 0.0, 1.0)
	_appliquer(0.0)


## Il se détache de la lame et part.
func lacher() -> void:
	attache = false
	_amorce = 1.0
	_t = 0.0
	_parcouru = 0.0
	_depart = position
	_x_sonde = joueur.global_position.x if joueur != null else global_position.x
	_appliquer(0.0)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or attache:
		return
	_t += delta
	if _fin:
		# arrêté par un mur : il s'efface sur place
		_t_fin += delta
		if _t_fin >= DUREE_FIN:
			queue_free()
			return
		_appliquer(lerpf(_prog_fin, 1.0, _t_fin / DUREE_FIN))
		return
	var pas := vitesse * delta
	if not _demo and _mur_devant(pas):
		_fin = true
		_prog_fin = maxf(_parcouru / maxf(portee, 1.0), 0.7)
		return
	position.x += dir * pas
	_parcouru += pas
	# la zone s'arme : les corps déjà dedans comptent aussi
	if _t >= armement and _t - delta < armement:
		for b in get_overlapping_bodies():
			_on_body_entered(b)
	if _parcouru >= portee:
		if _demo:
			_parcouru = 0.0
			_t = 0.0
			_deja.clear()
			position = _depart
		else:
			queue_free()
			return
	_appliquer(_parcouru / maxf(portee, 1.0))


func _on_body_entered(body: Node) -> void:
	if _demo or attache or _t < armement or _fin:
		return
	if body.is_in_group("Player"):
		return
	if body is BaseAI:
		if _deja.has(body) or touches_du_coup.has(body):
			return
		if body.hp <= 0 or body.invulnerable or (joueur != null and not body.est_ennemi(joueur)):
			return
		_deja.append(body)
		var x: float = joueur.global_position.x if joueur != null else global_position.x - dir
		body.apply_damage(degats, x, "croissant", true, joueur)
		print("[CROISSANT] ", body.name, " : ", degats, " dégâts")


## le bord d'attaque du croissant, droit devant (x monde) : le trajet à 0 rad
func _avant() -> float:
	return global_position.x + dir * (float(forme[0]) + float(forme[1]) + float(forme[3])) * echelle


## un mur (corps solide, couche 1) entre le dernier point sûr et là où son
## bord d'attaque sera au prochain pas, à mi-hauteur ?
func _mur_devant(pas: float) -> bool:
	var jusqu_a := _avant() + dir * (pas - RETRAIT_SONDE)
	var q := PhysicsRayQueryParameters2D.create(Vector2(_x_sonde, global_position.y),
			Vector2(jusqu_a, global_position.y), 1)
	if joueur != null:
		q.exclude = [joueur.get_rid()]
	if not get_world_2d().direct_space_state.intersect_ray(q).is_empty():
		return true
	_x_sonde = jusqu_a
	return false


func _appliquer(progression: float) -> void:
	if not is_node_ready():
		return
	var mat := _lame.material as ShaderMaterial
	if mat == null:
		return
	# il quitte le slash : son ouverture glisse de celle de la lame à la sienne
	var ne := 1.0 if Engine.is_editor_hint() else clampf(_t / maxf(pose, 0.001), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, ne)
	mat.set_shader_parameter("taille", _lame.size)
	mat.set_shader_parameter("origine", -_lame.position)
	mat.set_shader_parameter("forme", Vector4(forme[0], forme[1], forme[2], forme[3]))
	mat.set_shader_parameter("forme_b2", float(forme[4]))
	mat.set_shader_parameter("queue", lerpf(queue0, -demi_arc, e))
	mat.set_shader_parameter("tete", lerpf(tete0, demi_arc, e))
	mat.set_shader_parameter("progress", clampf(progression, 0.0, 1.0))
	mat.set_shader_parameter("naissance", ne)
	mat.set_shader_parameter("amorce", _amorce)
	mat.set_shader_parameter("temps", _t)
	mat.set_shader_parameter("graine", _graine)
