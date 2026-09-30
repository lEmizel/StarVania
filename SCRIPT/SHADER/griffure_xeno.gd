@tool
extends Node2D
## ============================================================================
## GRIFFURE DU XENO — le visuel de ses deux coups de griffes au corps à corps
## (visuel seul : les dégâts restent dans animator_xeno.gd et sa hitbox).
##
## USAGE EN JEU : chaque xeno en garde UNE, créée avec lui comme enfant de son
## POINT (animator_xeno.gd) : elle se retourne avec lui. L'animator appelle
## `jouer(1)` sur l'image où part le premier coup, `jouer(2)` pour le second ;
## à la fin elle se cache (`auto_detruire = false`). `arreter()` la coupe net
## (le xeno meurt en plein geste).
##
## LES DEUX ARCS sont réglés ci-dessous, un par coup. Ils partent des arcs
## MESURÉS sur les images de l'animation (Xeno_cac_attack-4 et -8), agrandis et
## avancés pour que le coup se détache du corps et couvre la zone de dégâts. Le nœud racine est aux PIEDS du xeno,
## qui regarde vers la droite ; angles : 0° = droit devant, -90° = au-dessus,
## 90° = dessous. Si l'animation change, ce sont ces huit valeurs qu'on retouche.
##
## POUR LA JUGER : ouvrir la scène et faire F6, `demo_boucle` enchaîne les deux
## coups au rythme du jeu, en boucle. Dans l'éditeur, `coup_apercu` choisit le
## coup et le curseur `progression` montre n'importe quel instant. Les formes se
## règlent sur le matériau du nœud Griffure.
## ============================================================================

## durée d'un coup
@export var duree := 0.22
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.01) var progression := 0.0:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## quel coup l'aperçu de l'éditeur montre
@export_range(1, 2) var coup_apercu := 1:
	set(v):
		coup_apercu = v
		if Engine.is_editor_hint():
			_coup = v
			_appliquer()
## en jeu : enchaîne les deux coups en boucle au lieu de s'arrêter
@export var demo_boucle := true
## temps entre les deux coups de la démo (celui du jeu : 0,31 s), puis pause
@export var demo_ecart := 0.31
@export var demo_pause := 0.7
## se supprime à la fin ; sinon elle se cache et attend le prochain `jouer()`
## (ignoré tant que `demo_boucle` est coché)
@export var auto_detruire := true

@export_group("Coup 1 (de haut en bas, devant lui)")
@export var centre_1 := Vector2(30.0, -146.0)
@export var rayon_1 := 136.0
@export var debut_1 := -95.0
@export var fin_1 := 120.0

@export_group("Coup 2 (par-dessus, plus loin devant)")
@export var centre_2 := Vector2(56.0, -152.0)
@export var rayon_2 := 128.0
@export var debut_2 := -115.0
@export var fin_2 := 115.0

@onready var _griffure: ColorRect = $Griffure

var _t := 0.0
var _joue := false
var _coup := 1
var _graine := 0.0
var _demo_t := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_coup = coup_apercu
		_appliquer()
		return
	if demo_boucle:
		# lancée seule (F6) : le xeno aurait les pieds un peu sous le milieu de l'écran
		if get_parent() == get_tree().root:
			position = get_viewport_rect().size * 0.5 + Vector2(-30.0, 130.0)
		jouer(1)
	else:
		visible = false


## lance la griffure du coup `n` (1 ou 2) depuis le début
func jouer(n: int) -> void:
	_coup = 2 if n == 2 else 1
	_graine = randf_range(1.0, 100.0)
	_t = 0.0
	_joue = true
	visible = true
	progression = 0.0


## coupe la griffure net
func arreter() -> void:
	_joue = false
	visible = false


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if demo_boucle:
		_demo_avancer(delta)
	if not _joue:
		return
	_t += delta
	if _t <= duree:
		progression = _t / duree
		return
	progression = 1.0
	_joue = false
	if demo_boucle:
		return
	if auto_detruire:
		queue_free()
	else:
		visible = false


## démo : coup 1, puis coup 2 au rythme du jeu, une pause, et on recommence
func _demo_avancer(delta: float) -> void:
	var avant := _demo_t
	_demo_t += delta
	if avant < demo_ecart and _demo_t >= demo_ecart:
		jouer(2)
	elif _demo_t >= demo_ecart + duree + demo_pause:
		_demo_t = 0.0
		jouer(1)


func _appliquer() -> void:
	if not is_node_ready():
		return
	var mat := _griffure.material as ShaderMaterial
	if mat == null:
		return
	var taille := Vector2(maxf(_griffure.size.x, 1.0), maxf(_griffure.size.y, 1.0))
	var second := _coup == 2
	mat.set_shader_parameter("progress", progression)
	mat.set_shader_parameter("graine", _graine)
	# le repère du shader : des pixels, comptés depuis ce nœud (les pieds du xeno)
	mat.set_shader_parameter("taille", taille)
	mat.set_shader_parameter("origine", -_griffure.position / taille)
	mat.set_shader_parameter("centre", centre_2 if second else centre_1)
	mat.set_shader_parameter("rayon", rayon_2 if second else rayon_1)
	mat.set_shader_parameter("angle_debut", debut_2 if second else debut_1)
	mat.set_shader_parameter("angle_fin", fin_2 if second else fin_1)
