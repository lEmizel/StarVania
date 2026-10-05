@tool
extends Node2D
## ============================================================================
## SILLAGE DE SANG — la brume laissée par la roulade et le dash quand le
## talisman « Sillage de sang » est porté (1er oct. 2026). Visuel ET dégâts :
## elle ronge à petit feu les ennemis pris dedans.
##
## USAGE EN JEU : player.gd en crée un au début de chaque roulade / dash
## (hébergé par la scène : la brume reste où elle a été semée pendant que le
## perso s'en va), lui passe `joueur` et ses réglages, puis `ajouter(point)`
## tous les quelques px du trajet, et `fermer()` à la fin du mouvement. Chaque
## endroit vit `duree` s après le passage du perso ; le nœud se supprime quand
## tout est éteint.
##
## LES DÉGÂTS : toutes les `intervalle` s, chaque ennemi (BaseAI du camp d'en
## face, vivant, vulnérable) dont le CORPS touche la brume VISIBLE perd `degats`
## points de vie — une seule fois par tick, même s'il est dans plusieurs bouts.
## « Touche » : le haut, le milieu ou le bas de sa forme de collision est dans
## l'enveloppe que dessine le shader (base posée sur le trajet, haut qui monte
## avec l'âge, mêmes `epaisseur` et `montee` que le matériau), à `marge` px
## près. Avant (1er oct. 2026), c'était le seul milieu du corps à moins de
## 56 px du trajet : la brume, qui monte jusqu'à ~200 px, mordait bien moins
## loin qu'elle ne se voyait (la zone de dégâts semblait plus petite).
## Pendant son dernier cinquième la brume se déchire : elle ne mord plus. Sans
## recul ; l'ennemi se retourne contre le joueur. Ne recharge pas le bloodheal
## (seul le coup d'épée le fait).
##
## POUR LE JUGER : ouvrir la scène et faire F6 : un sillage est semé en boucle
## au milieu de l'écran. L'allure (épaisseur, volutes, couleurs) se règle sur
## le matériau du nœud Brume ; le rendu, fumée douce ou marbré, sur ce nœud
## (`douceur`).
## ============================================================================

## nombre de points d'un sillage (le shader en prend autant) : au-delà, le
## joueur en commence un nouveau
const MAX_POINTS := 24

## combien de temps la brume vit en chaque endroit (s)
@export var duree := 3.0
## dégâts d'un tick, et temps entre deux ticks (s)
@export var degats := 36
@export var intervalle := 0.5
## tolérance (px) au-delà de la brume visible : un corps qui l'effleure
## compte comme dedans
@export var marge := 16.0
## EFFILÉE AUX DEUX BOUTS (1er oct. 2026, pour éviter le côté
## rectangulaire) : sur cette
## longueur (px) depuis chaque bout du trajet, la brume rapetisse — épaisseur ET
## montée — jusqu'à `bout_min` de sa taille ; un sillage plus court que deux
## fois cette longueur devient une lentille. Réglé ici et pas sur le matériau :
## c'est ce script qui le donne au shader, et la zone de dégâts suit la même
## forme.
@export var effilage := 110.0
@export_range(0.0, 1.0) var bout_min := 0.3
## 1 = une fumée faite comme un nuage : un bord en bosses qui fond, un cœur
## plein, un relief doux, plus de veines claires. 0 = le rendu marbré d'avant,
## très enroulé. Entre les deux, les deux rendus se fondent l'un dans l'autre.
## Sans effet si `toon` vaut 1 sur le matériau. Réglé ici et pas sur le
## matériau, comme l'effilage : c'est ce script qui le donne au shader.
@export_range(0.0, 1.0) var douceur := 1.0
## lancé seul (F6) : un sillage est semé en boucle
@export var demo_boucle := true

## posé par le joueur : l'attaquant (camp, riposte). Sans lui : aucun dégât.
var joueur: Node2D = null

@onready var _brume: ColorRect = $Brume

var _points: Array[Vector2] = []          # dans le repère du nœud
var _naissances := PackedFloat32Array()
# le BOUT VIVANT du sillage tant qu'il se trace : là où est le perso, entre deux
# points (repère du nœud ; INF = fermé ou inconnu). Sans lui, la longueur ne
# grandirait que par sauts de 36 px à chaque point posé, et l'effilage du bout
# sauterait avec elle.
var _bout_vivant := Vector2.INF
var _t := 0.0
var _ferme := false
var _tick := 0.2
var _demo := false
var _graine := 0.0


func _ready() -> void:
	_graine = randf() * 100.0
	if Engine.is_editor_hint():
		return
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5


## un point de plus sur le trajet (coordonnées MONDE) ; false si le sillage
## est fermé ou plein (le joueur en commence alors un autre)
func ajouter(point_monde: Vector2) -> bool:
	if _ferme or _points.size() >= MAX_POINTS:
		return false
	_points.append(to_local(point_monde))
	_naissances.append(_t)
	_cadrer()
	return true


## le perso est ICI (coordonnées MONDE), entre deux points : le bout du sillage
## avance en continu avec lui (à appeler à chaque image tant qu'il se trace)
func suivre(point_monde: Vector2) -> void:
	if not _ferme:
		_bout_vivant = to_local(point_monde)


## le mouvement est fini : plus de nouveaux points, la brume vit sa vie
func fermer() -> void:
	_ferme = true
	_bout_vivant = Vector2.INF


## la longueur du trajet (px), bout vivant compris
func _longueur() -> float:
	var l := 0.0
	for i in _points.size() - 1:
		l += _points[i].distance_to(_points[i + 1])
	if not _ferme and is_finite(_bout_vivant.x) and not _points.is_empty():
		l += _points[_points.size() - 1].distance_to(_bout_vivant)
	return l


## la taille de la brume à `s` px du début du trajet (1 au milieu, `bout_min`
## aux deux bouts) — la MÊME formule que le shader
func _effile(s: float, longueur: float) -> float:
	var lt := maxf(minf(effilage, longueur * 0.5), 1.0)
	return lerpf(bout_min, 1.0, smoothstep(0.0, lt, minf(s, longueur - s)))


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_t += delta
	if _demo:
		_demo_semer()
	_appliquer()
	var fini := (_ferme or _points.size() >= MAX_POINTS) and not _points.is_empty() \
			and _t > _naissances[_naissances.size() - 1] + duree
	if fini:
		if _demo:
			_demo_relancer()
		else:
			queue_free()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or joueur == null or not is_instance_valid(joueur) or _points.is_empty():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = intervalle
	_ronger()


## un tick de dégâts : les ennemis dont le corps touche la brume encore
## dense (le dernier cinquième de sa vie, la brume se déchire : elle ne mord
## plus)
func _ronger() -> void:
	var limite := duree * 0.8
	var zone := Rect2()
	var vide := true
	for i in _points.size():
		if _t - _naissances[i] < limite:
			var g := to_global(_points[i])
			if vide:
				zone = Rect2(g, Vector2.ZERO)
				vide = false
			else:
				zone = zone.expand(g)
	if vide:
		return
	# la brume monte au-dessus du trajet : la boîte de recherche aussi
	zone = zone.grow(_reglage("epaisseur", 56.0) * 1.4 + _reglage("montee", 120.0) + marge + 80.0)
	var forme := RectangleShape2D.new()
	forme.size = zone.size
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.transform = Transform2D(0.0, zone.get_center())
	requete.collision_mask = 8               # la couche des monstres
	requete.collide_with_areas = false
	var touches: Array[Node] = []
	for resultat in get_world_2d().direct_space_state.intersect_shape(requete, 32):
		var c: Node = resultat["collider"]
		if not (c is BaseAI) or touches.has(c):
			continue
		if c.hp <= 0 or c.invulnerable or not c.est_ennemi(joueur):
			continue
		for g in _points_du_corps(c):
			if dans_la_brume(to_local(g), limite):
				touches.append(c)
				# (le Canon de verre ne double que l'épée et l'Ombre)
				c.apply_damage(degats, joueur.global_position.x, "sillage", false, joueur)
				break


## le haut, le milieu et le bas de la forme de collision d'un ennemi (monde)
func _points_du_corps(c: BaseAI) -> Array[Vector2]:
	var col: CollisionShape2D = c.collision
	if col == null or col.shape == null:
		return [c.global_position]
	var r := col.shape.get_rect()
	var xf := col.global_transform
	var cx := r.get_center().x
	return [xf * Vector2(cx, r.position.y), xf * r.get_center(), xf * Vector2(cx, r.end.y)]


## un point (repère du nœud) est-il dans la brume VISIBLE et encore dense ?
## La même enveloppe que le shader (sillage_sang.gdshader, « L'ENVELOPPE,
## ANCRÉE COMME UNE FLAMME ») : autour du point du trajet le plus proche, base
## posée à 0,55 × R dessous, haut qui monte avec l'âge de R + montée ; les
## renflements et les colonnes du bruit sont pris à leur valeur moyenne, les
## volutes qui débordent sont couvertes par `marge`. La fumée douce (`douceur`)
## a une enveloppe un peu plus grande dont le bord fond : sa partie visible
## couvre la même zone.
func dans_la_brume(p: Vector2, limite: float) -> bool:
	if _points.is_empty():
		return false
	var proche := _points[0]
	var naissance := _naissances[0]
	var dmin := p.distance_to(proche)
	var cumul := 0.0
	var s_proche := 0.0            # px depuis le début du trajet
	for i in _points.size() - 1:
		var a := _points[i]
		var ab := _points[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var c := a + ab * t
		var d := p.distance_to(c)
		if d < dmin:
			dmin = d
			proche = c
			naissance = lerpf(_naissances[i], _naissances[i + 1], t)
			s_proche = cumul + ab.length() * t
		cumul += ab.length()
	var age := _t - naissance
	if age < 0.0 or age >= limite:
		return false
	var vie := age / maxf(duree, 0.001)
	var effile := _effile(s_proche, maxf(_longueur(), cumul))
	var rayon := _reglage("epaisseur", 56.0) * lerpf(0.5, 1.0, smoothstep(0.0, 0.2, age)) * effile
	var h_haut := rayon + _reglage("montee", 120.0) * (1.0 - (1.0 - vie) * (1.0 - vie)) * effile
	var h_bas := rayon * 0.55
	var rel := p - proche
	# on se ramène à un cercle de rayon `rayon`, comme le shader ; la marge,
	# elle, compte en px vrais au-dessus comme au-dessous
	var echelle := (rayon / h_haut) if rel.y < 0.0 else (rayon / h_bas)
	rel.y *= echelle
	return rel.length() <= rayon * 0.9 + marge * echelle


## un réglage du matériau de la brume (le même que celui du shader)
func _reglage(nom: String, defaut: float) -> float:
	if _brume == null:
		return defaut
	var mat := _brume.material as ShaderMaterial
	if mat == null:
		return defaut
	var v = mat.get_shader_parameter(nom)
	return float(v) if v != null else defaut


## le rectangle de dessin : la boîte des points, plus la place de la brume
func _cadrer() -> void:
	if _brume == null or _points.is_empty():
		return
	var mat := _brume.material as ShaderMaterial
	var ep := 56.0
	if mat != null and mat.get_shader_parameter("epaisseur") != null:
		ep = float(mat.get_shader_parameter("epaisseur"))
	var boite := Rect2(_points[0], Vector2.ZERO)
	for p in _points:
		boite = boite.expand(p)
	boite = boite.grow(ep * 3.2)
	boite.position.y -= 150.0         # la place de la montée de la fumée
	boite.size.y += 150.0
	_brume.position = boite.position
	_brume.size = boite.size


func _appliquer() -> void:
	if _brume == null:
		return
	var mat := _brume.material as ShaderMaterial
	if mat == null:
		return
	var pts := PackedVector2Array()
	var nes := PackedFloat32Array()
	pts.resize(MAX_POINTS)
	nes.resize(MAX_POINTS)
	# les points dans le repère FIXE du nœud (pas celui du rectangle, qui bouge
	# quand le sillage part vers la gauche) : le shader y fait tous ses calculs
	for i in _points.size():
		pts[i] = _points[i]
		nes[i] = _naissances[i]
	mat.set_shader_parameter("taille", _brume.size)
	mat.set_shader_parameter("origine_rect", _brume.position)
	mat.set_shader_parameter("points", pts)
	mat.set_shader_parameter("naissances", nes)
	mat.set_shader_parameter("nb_points", _points.size())
	mat.set_shader_parameter("temps", _t)
	mat.set_shader_parameter("duree", duree)
	mat.set_shader_parameter("graine", _graine)
	mat.set_shader_parameter("longueur", _longueur())
	mat.set_shader_parameter("effilage", effilage)
	mat.set_shader_parameter("bout_min", bout_min)
	mat.set_shader_parameter("douceur", douceur)


# --- la démo (F6) : une roulade vers la droite, semée en boucle ---

var _demo_x := -210.0

func _demo_semer() -> void:
	if _ferme:
		return
	var x := -210.0 + _t * 760.0
	if x >= 210.0:
		# un dernier point à l'arrivée, comme le joueur
		ajouter(to_global(Vector2(210.0, 0.0)))
		fermer()
		return
	suivre(to_global(Vector2(x, 0.0)))
	if _points.is_empty() or x - _demo_x >= 36.0:
		_demo_x = x
		ajouter(to_global(Vector2(x, 0.0)))


func _demo_relancer() -> void:
	_bout_vivant = Vector2.INF
	_points.clear()
	_naissances = PackedFloat32Array()
	_t = 0.0
	_ferme = false
	_demo_x = -210.0
	_graine = randf() * 100.0
