extends AnimatedSprite2D
## ============================================================================
## PIQUES RÉTRACTABLES — au repos, un chemin praticable (le StaticBody2D) dont
## on ne voit que les pointes. Dès qu'une entité compatible marche dessus
## (joueur, monstre : tout ce qui sait encaisser des dégâts), le piège s'ARME :
## il tremble pendant `delai_avant_sortie`, puis sort ses piques (anim "attack"),
## blesse ce qui se trouve dans `zone_Degat`, et se rétracte (la même anim
## jouée à l'envers). S'il y a encore quelqu'un dessus, il se réarme.
##
## Une fois armé, le piège part quoi qu'il arrive : s'enfuir à temps = sauf.
##
## DEUX ZONES INDÉPENDANTES. Dans la scène, l'Area2D porte deux formes (pratique
## à éditer), mais une Area2D ne dit pas LAQUELLE de ses formes est touchée. Au
## démarrage, `zone_Degat` est donc déménagée dans sa propre Area2D :
##   • la DÉTECTION (forme `detection`, au ras du bloc) reste active EN
##     PERMANENCE et rejoint le groupe "DEGATS" → les monstres au sol la voient
##     comme un trou et l'évitent (BASE_IA.danger_devant), même piques rentrées ;
##   • les DÉGÂTS (forme `zone_Degat`, toute la hauteur des piques) ne sont lus
##     que piques dehors.
##
## Dégâts : comme piques.gd. Le joueur perd `damage` cœur(s) et est repoussé
## dans le sens où POINTENT les piques (l'axe "haut" du nœud : une instance
## retournée au plafond repousse vers le bas, tournée de 90° sur le côté) ;
## les monstres prennent `degats_monstres` (mort sur le coup par défaut).
## ============================================================================

enum Etat { REPOS, ARME, SORTIE, DEHORS, RENTREE, PAUSE }

## Cœurs perdus par le joueur
@export var damage: int = 1
## Dégâts aux monstres (999999 = mort en un coup, comme les piques fixes)
@export var degats_monstres: int = 999999

@export_group("Rythme")
## temps entre la détection et la sortie des piques : le temps de réagir
@export var delai_avant_sortie := 0.3
## temps passé piques dehors. Libre : une même sortie ne touche un même corps
## qu'UNE fois (voir _blesser), donc le joueur projeté en l'air qui retombe
## dans les piques encore sorties ne reprend pas un 2e cœur
@export var duree_dehors := 0.4
## repos après la rentrée, avant de pouvoir détecter à nouveau
@export var pause_apres := 0.3
## image de l'anim "attack" à partir de laquelle ça blesse (2 = piques sorties :
## avant, elles ne remplissent pas encore zone_Degat → pas de pique invisible)
@export var frame_degats := 2

@export_group("Avertissement")
## tremblement du sprite pendant l'armement, en pixels (0 = aucun)
@export var tremblement_px := 2.0

@onready var _zone: Area2D = $Area2D                                  # détection
@onready var _forme_degats: CollisionShape2D = $Area2D/zone_Degat
var _zone_degats: Area2D = null                                       # fabriquée au ready

var _etat := Etat.REPOS
var _t := 0.0
var _offset_base := Vector2.ZERO
var _duree_attack := 0.15
var _deja_touches := {}     # corps déjà blessés par la sortie en cours


func _ready() -> void:
	# joueur (couche 1) ET monstres (couches 2 et 4), comme piques.gd
	_zone.collision_mask = 0b1011
	# visible des monstres : ils la traitent comme un trou (BASE_IA.danger_devant)
	_zone.add_to_group("DEGATS")
	# zone_Degat déménage dans sa propre Area2D, au même endroit
	_zone_degats = Area2D.new()
	_zone_degats.name = "ZoneDegats"
	_zone_degats.transform = _zone.transform
	_zone_degats.collision_layer = 0
	_zone_degats.collision_mask = 0b1011
	add_child(_zone_degats)
	_zone.remove_child(_forme_degats)
	_zone_degats.add_child(_forme_degats)
	_forme_degats.disabled = false

	# le bloc doit porter tout le monde. Convention du projet : les blocs solides
	# sont sur les couches 1 ET 2 (joueur = masque 1+2, monstres = masque 2+3).
	# Resté sur la couche 1 par défaut, le bloc laisserait les monstres passer au
	# travers. On ne corrige QUE la valeur par défaut : un réglage fait dans
	# l'éditeur garde le dernier mot.
	var bloc := get_node_or_null("StaticBody2D") as StaticBody2D
	if bloc != null and bloc.collision_layer == 1:
		bloc.collision_layer = 3

	_offset_base = offset
	_duree_attack = _duree_anim(&"attack")
	play(&"idle")


func _physics_process(delta: float) -> void:
	_t += delta
	match _etat:
		Etat.REPOS:
			if _quelqu_un_dessus():
				_passer(Etat.ARME)
		Etat.ARME:
			# l'avertissement : le piège tremble, de plus en plus fort
			var force := tremblement_px * clampf(_t / maxf(delai_avant_sortie, 0.001), 0.3, 1.0)
			offset = _offset_base + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * force
			if _t >= delai_avant_sortie:
				_passer(Etat.SORTIE)
		Etat.SORTIE:
			if frame >= frame_degats:
				_blesser()
			if _t >= _duree_attack:
				_passer(Etat.DEHORS)
		Etat.DEHORS:
			_blesser()
			if _t >= duree_dehors:
				_passer(Etat.RENTREE)
		Etat.RENTREE:
			if _t >= _duree_attack:
				_passer(Etat.PAUSE)
		Etat.PAUSE:
			if _t >= pause_apres:
				_passer(Etat.REPOS)


func _passer(etat: Etat) -> void:
	_etat = etat
	_t = 0.0
	match etat:
		Etat.SORTIE:
			offset = _offset_base
			_deja_touches.clear()
			play(&"attack")
		Etat.RENTREE:
			play_backwards(&"attack")
		Etat.PAUSE:
			play(&"idle")


## une entité compatible (qui sait encaisser des dégâts) est-elle sur le piège ?
func _quelqu_un_dessus() -> bool:
	for body in _zone.get_overlapping_bodies():
		if body.has_method("apply_environment_damage") or body.has_method("apply_damage"):
			return true
	return false


## Vérification CONTINUE tant que les piques sont dehors (comme piques.gd) : un
## joueur invulnérable (roulade/dash) est touché dès que ça retombe s'il est
## encore dedans ; ses gardes d'état rendent l'appel répété inoffensif.
## Une même sortie ne blesse un même corps qu'UNE fois : seul un coup qui a
## PORTÉ est retenu, donc un joueur en roulade reste « à toucher ».
func _blesser() -> void:
	var direction := _direction()
	for body in _zone_degats.get_overlapping_bodies():
		if _deja_touches.has(body):
			continue
		var porte = false
		if body.has_method("apply_environment_damage"):
			porte = body.apply_environment_damage(damage, direction)
		elif body.has_method("apply_damage"):
			porte = body.apply_damage(degats_monstres, global_position.x, "piques")
		if porte == true:
			_deja_touches[body] = true


## sens où pointent les piques : l'axe "haut" local, rotations et retournements compris
func _direction() -> Vector2:
	return (-global_transform.y).normalized()


func _duree_anim(nom: StringName) -> float:
	if sprite_frames == null or not sprite_frames.has_animation(nom):
		return 0.15
	var fps := maxf(sprite_frames.get_animation_speed(nom), 0.001)
	var total := 0.0
	for i in sprite_frames.get_frame_count(nom):
		total += sprite_frames.get_frame_duration(nom, i) / fps
	return maxf(total, 0.01)
