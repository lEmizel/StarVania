extends Node2D
## ============================================================================
## TROU NOIR (2 oct. 2026, piège choisi par Kaoru parmi des pièges « simples
## et spectaculaires », sur le modèle du pilier de foudre). Une seule règle :
## il t'ASPIRE, et son cœur blesse.
##
##   • À L'ÉCRAN (VisibleOnScreenNotifier2D « Ecran »), il s'ÉVEILLE : l'ombre
##     grandit, le disque s'embrase (`duree_eveil`). Hors de l'écran il se
##     rendort et n'aspire plus — rien ne se fait manger loin du joueur.
##   • Il ASPIRE le joueur et les monstres à moins de `portee` px (pas à travers
##     un mur), de plus en plus fort en approchant (`force` tout près). On s'en
##     sort en courant à contre-courant (le héros court à 700 px/s) ; agrippé
##     (échelle, corde, rebord, mur, grappin), on tient bon.
##   • Son CŒUR (`rayon_coeur`) : le joueur perd `damage` cœur(s) et il est
##     RECRACHÉ en arc, de son côté (`crachat_force` pendant `crachat_duree`,
##     puis plus aspiré du tout jusqu'à la fin du `repit`) ; un monstre
##     est DÉVORÉ (mort, il glisse dans l'ombre et s'éteint) — les vrais boss y
##     échappent. En roulade ou en dash, on traverse le cœur sans dégât, comme
##     les piques. Chaque fois qu'il mange : éclair, JETS aux pôles, onde dans
##     le décor, la caméra tremble.
##
## Le visuel : SCRIPT/SHADER/trou_noir.gdshader (nœud Trou). Il LIT L'ÉCRAN pour
## tordre ce qui est dessiné avant lui — une copie FRAÎCHE, faite par le nœud
## « Copie » (BackBufferCopy, mode écran entier) juste avant : sans elle, un autre
## shader qui lit l'écran plus tôt (le flou du fond de sc_10) laissait une copie
## SANS le décor, et la lentille tordait le vide. (En mode rectangle, la copie ne
## prenait pas : constaté, cause non élucidée.) Il est à z −1, comme le décor peint :
## placé APRÈS le nœud VISUAL dans la scène, il tord le décor et passe sous les
## monstres (z 0) et le joueur (z 1) — ce qui bouge reste net, là où on le voit.
## L'origine du nœud est son centre.
##
## POUR LE JUGER : ouvrir la scène et faire F6 (il s'éveille devant un décor de
## barres pour voir la lentille, et mange en boucle).
## ============================================================================

## Cœurs perdus par le joueur qui touche le cœur
@export var damage: int = 1
## Dégâts aux monstres dévorés (999999 = mort en un coup, comme les pièges)
@export var degats_monstres: int = 999999
## lancé seul (F6) : il s'éveille et mange en boucle
@export var demo_boucle := true

@export_group("Aspiration")
## jusqu'où il aspire (px, du centre au milieu du corps)
@export var portee := 560.0
## la vitesse d'aspiration tout près du cœur (px/s) ; elle tombe à 0 au bord
@export var force := 450.0
## comment elle monte en approchant (1 = régulièrement, plus = surtout tout près)
@export var courbe := 1.2
## part de l'aspiration en hauteur (1 = autant qu'en largeur ; sous lui, on
## décolle quand il tire plus fort que la gravité)
@export var part_verticale := 1.0

@export_group("Cœur")
## le cœur blesse (px, du centre au milieu du corps)
@export var rayon_coeur := 88.0
## recraché, le joueur n'est plus aspiré pendant… (s) — le temps de fuir
@export var repit := 1.2
## le crachat : il nous repousse encore, en arc, pendant… (s)
@export var crachat_duree := 0.35
## … à cette vitesse au départ (px/s), qui retombe à 0
@export var crachat_force := 900.0
## la caméra tremble quand il mange (0 = pas du tout)
@export var secousse := 6.0

@export_group("Dessin")
## le rayon de l'ombre (px)
@export var rayon := 72.0
## il s'éveille en… (s)
@export var duree_eveil := 0.8

@onready var _trou: ColorRect = $Trou
@onready var _ecran: VisibleOnScreenNotifier2D = $Ecran

var _eveil := 0.0
var _festin := 0.0
var _temps := 0.0
var _repit_joueur := 0.0
var _crachat_reste := 0.0
var _crachat_dir := Vector2.ZERO
var _zone := CircleShape2D.new()
var _demo := false
var _demo_t := 0.0


func _ready() -> void:
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
		_poser_decor_de_demo()
	# le rectangle couvre la zone d'aspiration (les poussières y tombent)
	var demi := maxf(portee, 470.0) + 30.0
	_trou.position = Vector2(-demi, -demi)
	_trou.size = Vector2(2.0 * demi, 2.0 * demi)
	_zone.radius = portee
	_appliquer()


func _physics_process(delta: float) -> void:
	var actif := _demo or _ecran.is_on_screen()
	_eveil = move_toward(_eveil, 1.0 if actif else 0.0, delta / (maxf(duree_eveil, 0.05) if actif else 1.2))
	_festin = maxf(_festin - delta / 0.9, 0.0)
	_repit_joueur = maxf(_repit_joueur - delta, 0.0)
	_crachat_reste = maxf(_crachat_reste - delta, 0.0)
	if _demo:
		_demo_t += delta
		if _eveil >= 1.0 and _demo_t > 2.4:
			_demo_t = 0.0
			_manger()
		return
	if _eveil <= 0.0:
		return
	# le joueur…
	var j := get_tree().get_first_node_in_group("Player") as Node2D
	if j != null and j.global_position.distance_to(global_position) < portee + 200.0:
		_attirer_joueur(j)
	# … et les monstres, sur LEUR couche seulement (8) : les blocs du décor, sur
	# la couche 1, rempliraient la requête avant eux
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _zone
	params.transform = Transform2D(0.0, global_position)
	params.collision_mask = 8
	params.collide_with_areas = false
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 32):
		var corps = hit.get("collider")
		if corps is BaseAI:
			_attirer_monstre(corps)


func _process(delta: float) -> void:
	_temps += delta
	_appliquer()


## la vitesse qui emporte vers le centre un corps dont le milieu est en `c`
## (nulle au bord de la zone, `force` tout près)
func _vitesse_vers(c: Vector2) -> Vector2:
	var d := global_position - c
	var r := d.length()
	if r >= portee or r < 0.5:
		return Vector2.ZERO
	var v := d / r * force * pow(1.0 - r / portee, courbe) * _eveil
	v.y *= part_verticale
	return v


## pas à travers un mur (couche 1) ; le joueur, lui aussi sur la couche 1, et
## les monstres ne cachent personne
func _a_vue(corps: PhysicsBody2D, c: Vector2) -> bool:
	var exclus: Array[RID] = [corps.get_rid()]
	for essai in 6:
		var rayon_vue := PhysicsRayQueryParameters2D.create(global_position, c, 1)
		rayon_vue.exclude = exclus
		var touche := get_world_2d().direct_space_state.intersect_ray(rayon_vue)
		if touche.is_empty():
			return true
		if not (touche["collider"] is CharacterBody2D):
			return false
		exclus.append(touche["rid"])
	return true


func _attirer_joueur(j: Node2D) -> void:
	if Player.hp <= 0:
		return
	var c: Vector2 = j.centre_corps()
	if _crachat_reste > 0.0:
		j.aspirer(_crachat_dir * crachat_force * (_crachat_reste / maxf(crachat_duree, 0.001)))
		return
	if c.distance_to(global_position) <= rayon_coeur * _eveil and _eveil > 0.5:
		# le cœur : un cœur perdu, recraché DE SON CÔTÉ, vers le haut (en roulade
		# ou en dash, on passe au travers : apply_environment_damage répond
		# « pas porté »). Pas « à l'opposé du centre » : sous lui, ça nous
		# plantait dans le sol à 130 px, repris une seconde plus tard
		var cote := signf(c.x - global_position.x)
		if cote == 0.0:
			cote = -float(j.last_direction)
		var dehors := Vector2(cote, -0.45).normalized()
		if j.apply_environment_damage(damage, dehors):
			_repit_joueur = repit
			_crachat_reste = crachat_duree
			_crachat_dir = dehors
			_manger()
			return
	if _repit_joueur > 0.0 or not _a_vue(j, c):
		return
	j.aspirer(_vitesse_vers(c))


func _attirer_monstre(m: BaseAI) -> void:
	if m.hp <= 0 or m.vrai_boss:
		return
	var c := m.collision.global_position if m.collision != null else m.global_position
	if c.distance_to(global_position) <= rayon_coeur * _eveil and _eveil > 0.5:
		_devorer(m, c)
		return
	if not _a_vue(m, c):
		return
	m.aspirer(_vitesse_vers(c))


## un monstre au cœur : il meurt, glisse dans l'ombre et s'éteint
func _devorer(m: BaseAI, c: Vector2) -> void:
	m.apply_damage(degats_monstres, global_position.x, "trou_noir")
	_manger()
	var tw := m.create_tween().set_parallel()
	tw.tween_property(m, "global_position", global_position + (m.global_position - c), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(m, "modulate", Color(0.0, 0.0, 0.0, 0.0), 0.35)


## il vient de manger : éclair, jets, onde — et la caméra tremble
func _manger() -> void:
	_festin = 1.0
	if secousse > 0.0 and not _demo:
		var cam := get_tree().get_first_node_in_group("Camera")
		if cam != null and cam.has_method("shake"):
			cam.shake(secousse, 10.0)


func _appliquer() -> void:
	var mat := _trou.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("taille", _trou.size)
	mat.set_shader_parameter("rayon", rayon)
	mat.set_shader_parameter("eveil", _eveil)
	mat.set_shader_parameter("festin", _festin)
	mat.set_shader_parameter("temps", _temps)
	mat.set_shader_parameter("portee", portee)


## F6 : des barres de couleur derrière lui, pour voir le décor se tordre
func _poser_decor_de_demo() -> void:
	var taille := get_viewport_rect().size * 2.0
	var fond := ColorRect.new()
	fond.color = Color(0.08, 0.09, 0.14)
	fond.size = taille
	fond.position = -taille * 0.5
	fond.z_index = -2
	add_child(fond)
	for i in 14:
		var barre := ColorRect.new()
		barre.color = Color(0.2, 0.26, 0.38) if i % 2 == 0 else Color(0.32, 0.18, 0.24)
		barre.size = Vector2(18.0, taille.y)
		barre.position = Vector2(-taille.x * 0.5 + (i + 0.5) * taille.x / 14.0, -taille.y * 0.5)
		barre.z_index = -2
		add_child(barre)
	for i in 8:
		var barre := ColorRect.new()
		barre.color = Color(0.22, 0.3, 0.26)
		barre.size = Vector2(taille.x, 10.0)
		barre.position = Vector2(-taille.x * 0.5, -taille.y * 0.5 + (i + 0.5) * taille.y / 8.0)
		barre.z_index = -2
		add_child(barre)
