extends Area2D
## PASSAGE : comme une porte, mais la téléportation est AUTOMATIQUE au
## contact du joueur — aucun bouton. Reste dans le groupe "Porte" pour que
## le spawnplayer trouve le point d'arrivée (id + Marker2D) à destination.
##
## Anti-boucle : en arrivant par un passage, le joueur apparaît DANS sa
## zone — dans ce cas le passage ne s'arme qu'une fois le joueur sorti,
## sinon aller-retour infini entre les deux scènes.

@export var id: int = 0
@export_file("*.tscn") var target_scene: String

## PASSAGE VERTICAL (28 sept. 2026) — pour deux tableaux EMPILÉS.
## À cocher sur LES DEUX passages : celui du haut du tableau inférieur et celui
## du bas du tableau supérieur. Ce que ça change :
##   • le joueur arrive SUR le passage lui-même, et plus sur le Marker2D (qui
##     est décalé de côté, prévu pour un passage horizontal : dans un puits il
##     tomberait dans un mur) ;
##   • un passage du BAS d'un tableau (trou dans le sol) propulse vers le haut
##     le joueur qui ARRIVE : on n'y arrive que par-dessous. Un passage du HAUT
##     ne propulse jamais : on n'y arrive qu'en tombant.
##
## C'est le RÔLE du passage qui décide, pas la vitesse du joueur. (Premier jet :
## le signe de sa vitesse en traversant. Faux dès qu'on entre dans
## un passage du haut en retombant, ou du bas en sautant : on se retrouvait
## propulsé dans le tableau du bas et lâché au fond du trou dans celui du haut.)
@export_group("Passage vertical")
@export var vertical := false
enum Role { AUTO, HAUT_DU_TABLEAU, BAS_DU_TABLEAU }
## AUTO : déduit de la position du passage par rapport au décor solide du
## niveau (moitié haute = passage du haut). À forcer si la déduction se trompe.
@export var role: Role = Role.AUTO
## force vers le haut à l'arrivée par le bas, en px/s (saut normal ≈ 1060,
## catapulte du grappin 1500). Hauteur gagnée ≈ propulsion² ÷ 6850 :
##   1300 → 245 px   1600 → 375 px   1900 → 525 px   2200 → 705 px
## Il faut couvrir la profondeur du trou PLUS de quoi passer le rebord.
## (1300 au premier jet : trop mou, et ne sortait même pas d'un
## trou de 300 px.)
@export var propulsion := 1900.0
## poussée de côté ajoutée à l'élan d'arrivée, pour retomber sur le rebord et
## pas dans le trou (px/s, négatif = vers la gauche, 0 = aucune : au joueur
## de diriger sa retombée)
@export var propulsion_laterale := 0.0

## RAI DE LUMIÈRE (3 oct. 2026, d'après une image de référence) : la
## lumière qui entre par ce passage — l'ouverture blanche, la nappe de lumière,
## ses poussières, sa brume. Dessiné par l'enfant RaiDeLumiere (rai_lumiere.gd,
## visible dans l'éditeur), qui lit ces réglages.
##   • DE CÔTÉ (passage horizontal) : la nappe tombe en biais de l'ouverture
##     jusqu'au sol, vers la salle (le côté du Marker2D) ;
##   • TOMBE DU HAUT (trou au plafond) : une colonne de lumière droite qui
##     descend du trou ;
##   • MONTE DU BAS (trou dans le sol) : une colonne droite qui monte du trou.
##     En vertical, elle s'éteint en dégradé : nette au trou, plus rien au bout
##     de `rai_longueur` (elle se voit surtout sur la première moitié).
@export_group("Rai de lumière")
@export var rai_de_lumiere := true
enum ModeRai { AUTO, DE_COTE, TOMBE_DU_HAUT, MONTE_DU_BAS }
## AUTO : de côté pour un passage horizontal ; pour un passage vertical, tombe
## du haut s'il est en haut du tableau, monte du bas s'il est en bas (comme son
## rôle). Les autres : pour forcer.
@export var rai_mode: ModeRai = ModeRai.AUTO
## d'où part la lumière, décalée le long de son trajet (px ; + = vers la salle) :
## de côté, le bout du couloir ; en vertical, le bord du trou
@export var rai_depart := 0.0
## taille de l'ouverture (px) : sa HAUTEUR de côté, sa LARGEUR en vertical
@export var rai_hauteur := 300.0
## jusqu'où va la lumière (px) : de côté, là où elle touche le sol ; en
## vertical, là où la colonne s'est éteinte (dégradé)
@export var rai_longueur := 420.0
@export_range(0.0, 2.0, 0.01) var rai_intensite := 1.0
@export var rai_couleur := Color(1.0, 0.96, 0.88)
## l'ouverture elle-même, blanche de lumière (0 = invisible)
@export_range(0.0, 1.0, 0.01) var rai_ouverture := 0.8
## vitesse à laquelle l'ondulation des bords se transforme (0 = figée ;
## 0,6 = une forme nouvelle en 2 secondes environ)
@export_range(0.0, 2.0, 0.01) var rai_vitesse_ondulation := 0.6

# fenêtre (frames physique) après le chargement pendant laquelle une entrée
# est considérée comme une ARRIVÉE par ce passage, pas une traversée
const FENETRE_ARRIVEE := 30
# passage du BAS : le joueur doit être descendu d'autant sous le haut de la
# zone pour être considéré DANS le trou (la zone dépasse souvent sur le sol)
const MARGE_DANS_LE_TROU := 40.0

var _ready_frame := 0
var _bloque_jusqua_sortie := false
var _deja_utilise := false
var _role_effectif := Role.HAUT_DU_TABLEAU
var _dedans: Node2D = null       # le joueur, tant qu'il est dans la zone (passage vertical)
var _propulse: Node2D = null     # le joueur propulsé, tant qu'il n'est pas ressorti


func _ready() -> void:
	_ready_frame = Engine.get_physics_frames()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_physics_process(false)
	if vertical:
		_determiner_role()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("Player"):
		return
	_dedans = body
	# le joueur vient d'apparaître ici (arrivée par ce passage) :
	# on ne s'arme qu'à sa sortie de la zone
	if Engine.get_physics_frames() - _ready_frame < FENETRE_ARRIVEE:
		_bloque_jusqua_sortie = true
		if vertical:
			set_physics_process(true)
		return
	if vertical:
		set_physics_process(true)     # le guet décide (voir _physics_process)
		return
	if _bloque_jusqua_sortie or _deja_utilise:
		return
	_traverser(body)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		_bloque_jusqua_sortie = false
		_dedans = null
		_propulse = null
		set_physics_process(false)


func _traverser(body: Node2D) -> void:
	if target_scene.is_empty():
		push_warning("[PASSAGE] Aucune scène cible définie")
		return
	_deja_utilise = true  # une seule téléportation par vie de scène
	set_physics_process(false)
	Player.last_door_id = id
	# l'élan du joueur traverse avec lui : capturé ici, restitué au spawn
	Player.transition_velocity = body.velocity
	Player.transition_direction = body.last_direction
	Player.has_transition_momentum = true
	Loader.load_scene_with_loading(target_scene)


## Où le joueur apparaît quand il arrive par ce passage (lu par spawnplayer).
func point_arrivee() -> Vector2:
	if not vertical and has_node("Marker2D"):
		return get_node("Marker2D").global_position
	return global_position


## Appelé par spawnplayer quand le joueur ARRIVE par ce passage, une fois son
## élan et son état posés. Passage vertical du BAS d'un tableau = propulsion,
## toujours : on n'y arrive que par-dessous.
func joueur_arrive(body: Node2D) -> void:
	if not vertical or _role_effectif != Role.BAS_DU_TABLEAU:
		return
	if not body.has_method("propulser"):
		return
	body.propulser(Vector2(body.velocity.x + propulsion_laterale, -absf(propulsion)))
	_dedans = body
	_propulse = body
	set_physics_process(true)


## LE GUET d'un passage vertical : tourne tant que le joueur est dans la zone.
func _physics_process(_delta: float) -> void:
	var b := _dedans
	if b == null or not is_instance_valid(b):
		_dedans = null
		_propulse = null
		set_physics_process(false)
		return
	if _deja_utilise:
		return
	# 1) Il vient d'être propulsé et il RETOMBE sans être ressorti de la zone :
	#    le verrou d'arrivée l'aurait laissé traverser le passage sans être
	#    téléporté, droit dans le vide sous le tableau. C'est une descente.
	if _propulse == b:
		if b.velocity.y > 0.0 and b.global_position.y > point_arrivee().y + 24.0:
			_propulse = null
			_bloque_jusqua_sortie = false
			_traverser(b)
		return
	if _bloque_jusqua_sortie:
		return
	# 2) Trou dans le sol : MARCHER au bord ne téléporte pas (la zone déborde
	#    sur le sol), il faut être en l'air et descendu DANS le trou.
	if _role_effectif == Role.BAS_DU_TABLEAU:
		if b.is_on_floor():
			return
		if b.global_position.y < _haut_de_zone() + MARGE_DANS_LE_TROU:
			return
	_traverser(b)


# ---------------------------------------------------------------------------
#  RÔLE : haut ou bas du tableau
# ---------------------------------------------------------------------------

func _determiner_role() -> void:
	_role_effectif = role
	if role == Role.AUTO:
		var etendue := _etendue_du_decor()
		if etendue.x > etendue.y:
			push_warning("[PASSAGE] %s : aucun décor solide trouvé, rôle HAUT par défaut — à forcer dans l'inspecteur" % name)
			_role_effectif = Role.HAUT_DU_TABLEAU
		elif global_position.y < (etendue.x + etendue.y) * 0.5:
			_role_effectif = Role.HAUT_DU_TABLEAU
		else:
			_role_effectif = Role.BAS_DU_TABLEAU
	print("[PASSAGE] ", name, " (id ", id, ") vertical, rôle : ", Role.keys()[_role_effectif],
		"" if role != Role.AUTO else " (déduit)")


## (y le plus haut, y le plus bas) des corps solides du niveau
func _etendue_du_decor() -> Vector2:
	var racine: Node = owner if owner != null else get_parent()
	var haut := INF
	var bas := -INF
	if racine == null:
		return Vector2(haut, bas)
	for corps in racine.find_children("*", "StaticBody2D", true, false):
		for f in corps.get_children():
			var pts := PackedVector2Array()
			if f is CollisionShape2D and f.shape != null:
				var r: Rect2 = f.shape.get_rect()
				pts = PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0.0),
					r.position + r.size, r.position + Vector2(0.0, r.size.y)])
			elif f is CollisionPolygon2D:
				pts = f.polygon
			for p in pts:
				var y: float = (f.global_transform * p).y
				haut = minf(haut, y)
				bas = maxf(bas, y)
	return Vector2(haut, bas)


func _haut_de_zone() -> float:
	var forme := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if forme == null or forme.shape == null:
		return global_position.y
	var r: Rect2 = forme.shape.get_rect()
	var y1: float = (forme.global_transform * r.position).y
	var y2: float = (forme.global_transform * (r.position + r.size)).y
	return minf(y1, y2)
