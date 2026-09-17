extends Node2D
## ============================================================================
## PIÈGE DE FLAMMES — des jets (instances de SCRIPT/SHADER/jet_flamme.tscn,
## autant qu'on veut, posés en enfants) qui s'allument et s'éteignent en
## CYCLE, avec une zone de dégâts active seulement quand ça brûle.
##
## CYCLE À DEUX GROUPES qui alternent, avec un RÉPIT entre les deux :
##
##     groupe normal  : ████████░░░░░░░░░░░░████████░░░░░░░░░░░░
##     groupe décalé  : ░░░░░░░░░░████████░░░░░░░░░░████████░░░░
##                              ↑↑        ↑↑
##                           répit : TOUT LE MONDE est éteint
##
## `duree_allume` de brasier, puis `duree_repit` où personne ne brûle, puis
## c'est l'autre groupe, puis encore un répit. Cocher `decale` range le piège
## dans le second groupe. Le temps éteint et le décalage ne se règlent pas : ils
## se déduisent (éteint = duree_allume + 2 × duree_repit), ce qui GARANTIT le
## répit aux deux transitions. Tous les pièges d'un niveau partent ensemble au
## chargement, ils restent donc synchronisés ; le temps s'arrête avec la pause.
##
## AVERTISSEMENT : la veilleuse s'allume `duree_avertissement` avant le plein
## jet — pendant le répit, on voit donc QUEL groupe va partir. Elle ne blesse pas.
##
## ÉJECTION du joueur : par la face de la zone dont il est le plus près de
## sortir — gauche, droite, ou dessus — calculée dans le repère du piège (un
## piège tourné ou retourné marche donc aussi). Par le dessus, on ajoute un
## biais vers le côté d'où il vient, pour qu'il ne retombe pas dans le brasier.
##
## MONSTRES : la zone est dans le groupe "DEGATS" → les monstres au sol la
## traitent comme un trou et la contournent EN PERMANENCE, allumée ou non
## (BASE_IA.danger_devant). Pris dedans quand ça brûle : `degats_monstres`.
## ============================================================================

## Cœurs perdus par le joueur
@export var damage: int = 1
## Dégâts aux monstres (999999 = mort en un coup, comme les piques)
@export var degats_monstres: int = 999999

@export_group("Cycle")
## durée du brasier
@export var duree_allume := 2.0
## RÉPIT entre les deux groupes : pendant ce temps TOUT LE MONDE est éteint, c'est
## la fenêtre pour passer d'un piège normal à un piège décalé sans se faire brûler
@export var duree_repit := 1.0   # 0,5 s était trop court à la manette (18 sept. 2026)
## coché : ce piège est dans le SECOND groupe (il brûle quand les autres se reposent)
@export var decale := false

@export_group("Allumage")
## la veilleuse s'allume ce temps-là avant le plein jet
@export var duree_avertissement := 0.5
@export var duree_allumage := 0.15
## les flammes mettent ce temps à rétrécir — purement visuel : dès la fin de la
## phase allumée plus rien ne brûle, le répit est sûr du début à la fin
@export var duree_extinction := 0.25
@export_range(0.0, 1.0, 0.01) var puissance_max := 1.0
@export_range(0.0, 1.0, 0.01) var puissance_veilleuse := 0.12

@export_group("Dégâts")
## ça brûle à partir de cette puissance (la veilleuse ne blesse pas)
@export_range(0.0, 1.0, 0.01) var seuil_degats := 0.5
## délai avant de pouvoir re-blesser le MÊME corps : le joueur éjecté vers le haut
## retombe dans les flammes ~0,5 s plus tard, sans ça il perdrait 2 cœurs d'un coup.
## Rester dedans plus longtemps re-brûle : pas de passage gratuit.
@export var delai_entre_coups := 1.0

@onready var _zone: Area2D = $Area2D
@onready var _forme: CollisionShape2D = $Area2D/zonededegat

var _jets: Array[Node] = []
var _temps := 0.0
var _puissance := -1.0
var _dernier_coup := {}     # corps → instant (s) du dernier coup porté


func _ready() -> void:
	# joueur (couche 1) ET monstres (couches 2 et 4), comme piques.gd
	_zone.collision_mask = 0b1011
	# les monstres au sol la voient comme un trou, en permanence
	_zone.add_to_group("DEGATS")
	for c in get_children():
		if c.has_method("regler") and "puissance" in c:
			c.demo_cycle = false          # c'est le piège qui commande, plus la démo du jet
			_jets.append(c)
	if decale:
		_temps = -_demi_periode()         # second groupe : démarre une demi-période plus tard
	_appliquer(_puissance_a(_temps))


func _physics_process(delta: float) -> void:
	_temps += delta
	_appliquer(_puissance_a(_temps))
	if brule():
		_bruler()


## un brasier + un répit : le temps qui sépare l'allumage des deux groupes
func _demi_periode() -> float:
	return maxf(duree_allume + duree_repit, 0.01)


## est-on dans la phase ALLUMÉE du cycle à l'instant `t` ?
func _phase_allumee(t: float) -> bool:
	return t >= 0.0 and fposmod(t, 2.0 * _demi_periode()) < duree_allume


## la puissance des jets à l'instant `t` du cycle (t < 0 : pas encore démarré)
func _puissance_a(t: float) -> float:
	var periode := 2.0 * _demi_periode()
	var base := puissance_veilleuse if duree_avertissement > 0.0 else 0.0
	if t < 0.0:
		return base if -t <= duree_avertissement else 0.0
	var c := fposmod(t, periode)
	if c < duree_allume:
		return lerpf(base, puissance_max, clampf(c / maxf(duree_allumage, 0.001), 0.0, 1.0))
	if periode - c <= duree_avertissement:
		return base                                      # la veilleuse annonce le prochain jet
	var depuis := c - duree_allume
	if depuis < duree_extinction:
		return lerpf(puissance_max, 0.0, depuis / maxf(duree_extinction, 0.001))
	return 0.0


func _appliquer(p: float) -> void:
	if is_equal_approx(p, _puissance):
		return
	_puissance = p
	for j in _jets:
		j.puissance = p


## ça brûle-t-il en ce moment ? Seulement pendant la phase allumée : les flammes
## qui rétrécissent à l'extinction sont inoffensives, le répit est entièrement sûr
func brule() -> bool:
	return _phase_allumee(_temps) and _puissance >= seuil_degats


func _bruler() -> void:
	for body in _zone.get_overlapping_bodies():
		if _dernier_coup.has(body) and _temps - float(_dernier_coup[body]) < delai_entre_coups:
			continue
		var porte = false
		if body.has_method("apply_environment_damage"):
			porte = body.apply_environment_damage(damage, _direction_ejection(body))
		elif body.has_method("apply_damage"):
			porte = body.apply_damage(degats_monstres, global_position.x, "flammes")
		if porte == true:
			_dernier_coup[body] = _temps


## Par où éjecter `body` : la face de la zone (gauche, droite ou dessus — jamais
## le dessous, il y a le bloc) dont son centre est le plus près de sortir.
func _direction_ejection(body: Node2D) -> Vector2:
	var rect := _forme.shape as RectangleShape2D
	if rect == null:
		return (-global_transform.y).normalized()
	var centre: Vector2 = body.global_position
	if body.has_method("centre_corps"):
		centre = body.centre_corps()
	var demi := rect.size * 0.5
	var l := _forme.to_local(centre)                    # repère de la zone : les jets montent vers −y
	var vers_gauche := l.x + demi.x                     # distance à parcourir pour sortir par chaque face
	var vers_droite := demi.x - l.x
	var vers_dessus := l.y + demi.y
	var dir: Vector2
	if vers_dessus <= vers_gauche and vers_dessus <= vers_droite:
		# par le dessus : vers le haut, avec un biais vers le côté d'où il vient
		var vitesse_locale := Vector2.ZERO
		if "velocity" in body:
			vitesse_locale = _forme.global_transform.basis_xform_inv(body.velocity)
		var cote := 1.0
		if absf(vitesse_locale.x) > 30.0:
			cote = -signf(vitesse_locale.x)
		elif absf(l.x) > 4.0:
			cote = signf(l.x)
		dir = Vector2(cote * 0.6, -1.0)
	elif vers_gauche <= vers_droite:
		dir = Vector2.LEFT
	else:
		dir = Vector2.RIGHT
	return _forme.global_transform.basis_xform(dir).normalized()
