@tool
extends Node2D
## ============================================================================
## LAME À CHAÎNE (3 oct. 2026, IDÉE DE KAORU, d'après une photo : « une grande
## lame de ce style, accrochée à une chaîne elle-même accrochée à la base comme
## les boules de feu ») — la cousine de la BARRE DE FEU (barre_feu.gd : même
## bloc de pierre, même façon de se poser, en autant d'exemplaires qu'on veut) :
## une grande lame en croissant au bout d'une chaîne, qui tourne sans fin
## autour de son bloc.
##   • elle tourne D'UN SEUL TENANT, comme la barre de feu : chaîne tendue, lame
##     droite au bout, vitesse constante. (La v1 avait une physique : chaîne
##     avec du mou, lame lente en haut et rapide en bas, balancée sur son
##     anneau. Kaoru l'a retirée : « ça rend pas bien au visuel ».)
##   • seule la LAME blesse, pas la chaîne : le joueur, repoussé dans le sens où
##     elle passe (`damage`, pas plus d'une fois par `delai_entre_coups` ;
##     roulade et dash passent au travers) ; les monstres qui s'y prennent
##     meurent (`degats_monstres`), sauf si `monstres_l_evitent` est coché (comme
##     la barre de feu : ils font demi-tour au bord du cercle). Près du bloc, la
##     chaîne passe sans faire de mal : on peut s'abriter au centre, sur le bloc.
##   • la lame est LE DESSIN DE KAORU (MEDIA/INTERACTIBLE/lame_pendule.png,
##     « finalement pour la lame j'ai refait aussi un dessin ») : cornes vers la
##     chaîne, pointe vers l'extérieur. Le script le MESURE (voir _lire_dessin) :
##     le milieu de son dos, où il rivette la platine et l'anneau de la chaîne,
##     et son enveloppe, qui fait la zone qui blesse. Un dessin retouché est
##     donc repris tel quel, attache et zone comprises. En jeu, il en fait une
##     copie à mipmaps, une fois pour toutes les lames : réduit 7 fois, le
##     dessin brut scintillerait en tournant.
## RÉGLAGES : `longueur` (de l'axe à l'anneau de la lame), `taille_lame`,
## `vitesse`, `sens_horaire`, `angle_depart`, `socle`, `monstres_l_evitent`.
## @tool : dans l'ÉDITEUR, elle se montre à sa vraie taille, à son angle de
## départ, avec le cercle que balaie la lame et son sens de rotation (et, case
## `monstres_l_evitent` cochée, la zone évitée par les monstres, en bleu). Rien
## n'est enregistré dans la scène : bloc, chaîne et lame sont fabriqués par le
## script (enfants internes).
## Dessins : son dessin, posé par SCRIPT/SHADER/lame_croissant.gdshader (avec
## la platine et l'anneau), maillon_chaine.gdshader (les maillons et le capuchon
## de l'axe, en aplat, sans ombrage : Kaoru n'en voulait pas le « côté 3D »),
## barre_feu_socle.gdshader (le bloc, celui de la barre de feu).
## POUR LA JUGER : ouvrir la scène et faire F6.
## ============================================================================

const DESSIN := preload("res://MEDIA/INTERACTIBLE/lame_pendule.png")
const SHADER_LAME := preload("res://SCRIPT/SHADER/lame_croissant.gdshader")
const SHADER_MAILLON := preload("res://SCRIPT/SHADER/maillon_chaine.gdshader")
const SHADER_SOCLE := preload("res://SCRIPT/SHADER/barre_feu_socle.gdshader")
const LARGEUR_LAME := 180.0             # la largeur de son dessin en jeu, d'une corne à l'autre, à la taille 1 (px)
const ANNEAU_AU_DOS := 9.0              # l'anneau pend à … px au-dessus du milieu du dos, où la platine est rivetée
const ZONE_TOUCHE := 0.9                # la zone qui blesse, un peu resserrée sur le dessin (cornes fines)
const POINTS_CONTOUR := 14              # sommets gardés pour la zone qui blesse
# les mesures de son dessin du 3 oct., si l'image n'est pas lisible (serveur de rendu factice)
const RAPPORT_SECOURS := 0.4003         # hauteur / largeur de l'image
const DOS_SECOURS := 0.3237             # le milieu du dos, en fraction de la hauteur
const CONTOUR_SECOURS: Array[Vector2] = [Vector2(0.009, 0.023), Vector2(1.0, 0.023), Vector2(0.954, 0.233),
	Vector2(0.843, 0.535), Vector2(0.75, 0.698), Vector2(0.509, 1.0), Vector2(0.5, 1.0), Vector2(0.241, 0.674),
	Vector2(0.185, 0.581), Vector2(0.111, 0.419), Vector2(0.065, 0.279), Vector2(0.009, 0.07)]
const PAS_MAILLON := 23.0               # d'un maillon au suivant (px)
const TAILLE_MAILLON := Vector2(34.0, 18.0)   # ils se chevauchent, comme ceux d'une vraie chaîne
const DEMI_SOCLE := 24.0                # le bloc de pierre : 48 × 48 px, celui de la barre de feu
const HAUTEUR_MONSTRES := 200.0         # la zone évitée descend d'autant sous le cercle : un squelette fait 183 px
const MARGE_EVITEMENT := 20.0           # … et déborde d'autant tout autour
const META := "genere_par_lame_chaine"

## Cœurs perdus par le joueur touché
@export var damage: int = 1
## Dégâts aux monstres (999999 = mort en un coup, comme les pièges)
@export var degats_monstres: int = 999999

@export_group("Lame")
## de l'axe à l'anneau de la lame (px)
@export_range(60.0, 800.0, 1.0) var longueur := 260.0:
	set(v):
		longueur = clampf(v, 60.0, 800.0)
		_reconstruire()
## taille de la lame (1 = 180 px d'une corne à l'autre ; 1,3 = 234 px, à peu
## près la hauteur du héros et demie)
@export_range(0.4, 2.5, 0.01) var taille_lame := 1.3:
	set(v):
		taille_lame = clampf(v, 0.4, 2.5)
		_reconstruire()
## le bloc de pierre au centre, solide (décocher dans un mur ou un plafond)
@export var socle := true:
	set(v):
		socle = v
		_reconstruire()

@export_group("Rotation")
## vitesse de rotation, en degrés par seconde (0 = immobile)
@export_range(0.0, 720.0, 1.0) var vitesse := 90.0:
	set(v):
		vitesse = maxf(v, 0.0)
		_placer()
		queue_redraw()
## dans le sens des aiguilles d'une montre
@export var sens_horaire := true:
	set(v):
		sens_horaire = v
		_placer()
		queue_redraw()
## angle de départ en degrés (0 = vers la droite, 90 = vers le bas) : pour
## décaler plusieurs lames entre elles
@export_range(-180.0, 180.0, 1.0) var angle_depart := 0.0:
	set(v):
		angle_depart = v
		_placer()
		queue_redraw()

@export_group("Dégâts")
## délai avant de pouvoir re-blesser le même corps
@export var delai_entre_coups := 1.0
## coché : les monstres au sol ne s'en approchent pas — ils font demi-tour au
## bord de la zone où leur corps toucherait la lame (en bleu dans l'éditeur).
## Décoché : ils s'y jettent et meurent. Les volants s'y prennent dans les deux cas.
@export var monstres_l_evitent := false:
	set(v):
		monstres_l_evitent = v
		_reconstruire()

# son dessin lu une fois (voir _lire_dessin), commun à toutes les lames
static var _cache := {}

var _maillons: Array[ColorRect] = []    # de l'axe vers la lame
var _lame: ColorRect = null
var _corps_socle: StaticBody2D = null
var _dessin := {}                       # son dessin et ses mesures
var _h_image := LARGEUR_LAME * RAPPORT_SECOURS                    # la hauteur du dessin en jeu, à la taille 1 (px)
var _y_anneau := LARGEUR_LAME * RAPPORT_SECOURS * DOS_SECOURS - ANNEAU_AU_DOS   # l'anneau, depuis le haut du dessin (px)
var _contour := PackedVector2Array()    # la zone qui blesse, repère de la lame (anneau en 0, lame vers +y)
var _centre_touche := Vector2.ZERO      # son milieu
var _temps := 0.0
var _theta := 0.0                       # l'angle de la chaîne autour de l'axe
var _dernier_coup := {}                 # corps → instant de son dernier coup
var _forme := ConvexPolygonShape2D.new()
var _requete := PhysicsShapeQueryParameters2D.new()


func _ready() -> void:
	if not Engine.is_editor_hint() and get_parent() == get_tree().root:
		position = get_viewport_rect().size * 0.5        # F6 : au milieu de l'écran
	if Engine.is_editor_hint():
		set_notify_transform(true)        # la zone bleue se redessine quand on la tourne
		# il réenregistre son dessin : on le remesure (attache, zone)
		if not DESSIN.changed.is_connected(_dessin_change):
			DESSIN.changed.connect(_dessin_change)
	_requete.shape = _forme
	_requete.collision_mask = 0b1011     # joueur (1) et monstres (2 et 4), comme les flammes
	_requete.collide_with_areas = false
	_construire()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_temps += delta
	_placer()
	_blesser()


func _omega() -> float:
	return deg_to_rad(vitesse) * (1.0 if sens_horaire else -1.0)


## le rayon du cercle que balaie la pointe de la lame (repère du nœud)
func portee() -> float:
	return longueur + (_h_image - _y_anneau + 4.0) * taille_lame


## le rayon de la zone évitée par les monstres (repère du monde)
func _rayon_evite() -> float:
	return portee() * absf(global_transform.get_scale().x) + MARGE_EVITEMENT


func _reconstruire() -> void:
	if is_node_ready():
		_construire()


## ÉDITEUR : son dessin vient d'être réenregistré
func _dessin_change() -> void:
	_cache = {}
	_reconstruire()


# ---------------------------------------------------------------------------
# SON DESSIN
# ---------------------------------------------------------------------------

## SON DESSIN, lu une fois pour toutes les lames : {texture, premultiplie,
## rapport (hauteur / largeur), dos, contour}.
##   • `dos` : le milieu du dos (le bord du haut, au milieu de l'image), en
##     fraction de la hauteur : c'est là que pend l'anneau ;
##   • `contour` : l'enveloppe convexe de la lame, en fractions de l'image : la
##     zone qui blesse ;
##   • en JEU, `texture` est une copie réduite (1024 px au plus, par moitiés :
##     chaque pixel = la moyenne de quatre), aux couleurs prémultipliées (pas de
##     liseré sombre au bord), avec ses mipmaps. Dans l'ÉDITEUR, le dessin tel
##     quel : une retouche s'y voit aussitôt.
## Si l'image n'est pas lisible (serveur de rendu factice) : le dessin brut et
## les mesures de secours.
func _lire_dessin() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var d := {"texture": DESSIN, "premultiplie": false, "rapport": RAPPORT_SECOURS, "dos": DOS_SECOURS,
		"contour": PackedVector2Array(CONTOUR_SECOURS)}
	var img: Image = DESSIN.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		d["rapport"] = float(img.get_height()) / float(img.get_width())
		while img.get_width() > 1024 or img.get_height() > 1024:
			img.resize(maxi(img.get_width() / 2, 1), maxi(img.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
		d["dos"] = _mesurer_dos(img)
		var petit := img.duplicate() as Image
		while petit.get_width() > 160:
			petit.resize(maxi(petit.get_width() / 2, 1), maxi(petit.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
		var contour := _mesurer_contour(petit)
		if contour.size() >= 3:
			d["contour"] = contour
		if not Engine.is_editor_hint():
			img.premultiply_alpha()
			img.generate_mipmaps()
			d["texture"] = ImageTexture.create_from_image(img)
			d["premultiplie"] = true
	_cache = d
	return d


## le milieu du dos : où la colonne du milieu de l'image devient opaque, en
## fraction de la hauteur (au demi-pixel près, entre deux lignes)
static func _mesurer_dos(img: Image) -> float:
	var x := img.get_width() / 2
	var h := img.get_height()
	var avant := 0.0
	for y in h:
		var a := img.get_pixel(x, y).a
		if a >= 0.5:
			var entre := 0.5 if y == 0 else (0.5 - avant) / maxf(a - avant, 0.001)
			return clampf((float(y) - 0.5 + entre) / float(h), 0.0, 1.0)
		avant = a
	return DOS_SECOURS


## l'enveloppe convexe de ses pixels opaques, en fractions de l'image, réduite à
## POINTS_CONTOUR sommets (on retire tour à tour celui qui compte le moins)
static func _mesurer_contour(img: Image) -> PackedVector2Array:
	var w := img.get_width()
	var h := img.get_height()
	var bords := PackedVector2Array()
	for y in h:
		var gauche := -1
		var droite := -1
		for x in w:
			if img.get_pixel(x, y).a >= 0.5:
				if gauche < 0:
					gauche = x
				droite = x
		if gauche >= 0:
			for yy in [y, y + 1]:
				bords.append(Vector2(float(gauche) / w, float(yy) / h))
				bords.append(Vector2(float(droite + 1) / w, float(yy) / h))
	if bords.size() < 3:
		return PackedVector2Array()
	var enveloppe := Geometry2D.convex_hull(bords)
	if enveloppe.size() > 1 and enveloppe[0].is_equal_approx(enveloppe[enveloppe.size() - 1]):
		enveloppe.remove_at(enveloppe.size() - 1)
	while enveloppe.size() > POINTS_CONTOUR:
		var n := enveloppe.size()
		var moindre := 0
		var aire_min := INF
		for i in n:
			var aire := absf((enveloppe[i] - enveloppe[(i - 1 + n) % n]).cross(enveloppe[(i + 1) % n] - enveloppe[i]))
			if aire < aire_min:
				aire_min = aire
				moindre = i
		enveloppe.remove_at(moindre)
	return enveloppe


# ---------------------------------------------------------------------------
# LA PIÈCE
# ---------------------------------------------------------------------------

## fabrique le bloc, son corps, la chaîne et la lame (enfants internes : rien
## n'est enregistré dans la scène)
func _construire() -> void:
	for enfant in get_children(true):
		if enfant.has_meta(META):
			remove_child(enfant)
			enfant.queue_free()
	_maillons.clear()
	_lame = null
	_corps_socle = null
	_requete.exclude = []
	# son dessin : sa hauteur en jeu, et l'anneau au-dessus du milieu de son dos
	_dessin = _lire_dessin()
	_h_image = LARGEUR_LAME * float(_dessin["rapport"])
	_y_anneau = _h_image * float(_dessin["dos"]) - ANNEAU_AU_DOS
	if socle:
		var dessin := ColorRect.new()
		var mat := ShaderMaterial.new()
		mat.shader = SHADER_SOCLE
		dessin.material = mat
		dessin.size = Vector2.ONE * (DEMI_SOCLE * 2.0 + 16.0)
		dessin.position = -dessin.size * 0.5
		dessin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mat.set_shader_parameter("taille", dessin.size)
		mat.set_shader_parameter("demi_cote", DEMI_SOCLE)
		dessin.set_meta(META, true)
		add_child(dessin, false, Node.INTERNAL_MODE_FRONT)
		if not Engine.is_editor_hint():
			# solide, comme le bloc de la barre de feu : on peut se tenir dessus
			_corps_socle = StaticBody2D.new()
			_corps_socle.collision_layer = 3          # comme les blocs de grayboxing
			_corps_socle.collision_mask = 0
			var forme := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2.ONE * DEMI_SOCLE * 2.0
			forme.shape = rect
			_corps_socle.add_child(forme)
			_corps_socle.set_meta(META, true)
			add_child(_corps_socle, false, Node.INTERNAL_MODE_FRONT)
			_requete.exclude = [_corps_socle.get_rid()]
	if monstres_l_evitent and not Engine.is_editor_hint():
		_creer_zone_evitee()
	# la chaîne : les maillons de face d'abord, ceux de profil par-dessus
	var n := maxi(3, roundi(longueur / PAS_MAILLON))
	_maillons.resize(n)
	for passe in 2:
		for i in range(passe, n, 2):
			var m := ColorRect.new()
			var mat := ShaderMaterial.new()
			mat.shader = SHADER_MAILLON
			m.material = mat
			m.size = TAILLE_MAILLON
			m.pivot_offset = TAILLE_MAILLON * 0.5
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mat.set_shader_parameter("taille", TAILLE_MAILLON)
			mat.set_shader_parameter("profil", float(passe))
			m.set_meta(META, true)
			add_child(m, false, Node.INTERNAL_MODE_BACK)
			_maillons[i] = m
	# le capuchon de l'axe, sur le départ de la chaîne
	var capuchon := ColorRect.new()
	var mat_c := ShaderMaterial.new()
	mat_c.shader = SHADER_MAILLON
	capuchon.material = mat_c
	capuchon.size = Vector2(22.0, 22.0)
	capuchon.position = -capuchon.size * 0.5
	capuchon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat_c.set_shader_parameter("taille", capuchon.size)
	mat_c.set_shader_parameter("profil", 2.0)
	capuchon.set_meta(META, true)
	add_child(capuchon, false, Node.INTERNAL_MODE_BACK)
	# la lame, par-dessus tout : son anneau couvre le bout de la chaîne
	_lame = ColorRect.new()
	var mat_l := ShaderMaterial.new()
	mat_l.shader = SHADER_LAME
	_lame.material = mat_l
	var marge := 6.0
	var haut := maxf(_y_anneau, 11.0) + marge          # de l'anneau au haut du rectangle (cornes, ou l'anneau lui-même)
	_lame.size = Vector2(LARGEUR_LAME + 2.0 * marge, haut + maxf(_h_image - _y_anneau, ANNEAU_AU_DOS + 8.0) + marge)
	_lame.pivot_offset = Vector2(_lame.size.x * 0.5, haut)      # l'anneau : la lame tourne et grandit autour
	_lame.scale = Vector2.ONE * taille_lame
	_lame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat_l.set_shader_parameter("taille", _lame.size)
	mat_l.set_shader_parameter("anneau", _lame.pivot_offset)
	mat_l.set_shader_parameter("dessin", _dessin["texture"])
	mat_l.set_shader_parameter("dessin_premultiplie", _dessin["premultiplie"])
	mat_l.set_shader_parameter("largeur", LARGEUR_LAME)
	mat_l.set_shader_parameter("attache", Vector2(0.5, _y_anneau / maxf(_h_image, 1.0)))
	mat_l.set_shader_parameter("dos", ANNEAU_AU_DOS)
	_lame.set_meta(META, true)
	add_child(_lame, false, Node.INTERNAL_MODE_BACK)
	_calculer_contour()
	_placer()
	queue_redraw()


## la zone qui blesse : l'enveloppe de son dessin (la lame et l'espace entre ses
## cornes), un peu resserrée, dans le repère de la lame
func _calculer_contour() -> void:
	_contour.clear()
	var points := PackedVector2Array()
	var centre := Vector2.ZERO
	for f: Vector2 in _dessin["contour"]:
		var q := Vector2((f.x - 0.5) * LARGEUR_LAME, f.y * _h_image - _y_anneau)
		points.append(q)
		centre += q
	if points.is_empty():
		return
	centre /= points.size()
	_centre_touche = centre * taille_lame
	for q in points:
		_contour.append((centre + (q - centre) * ZONE_TOUCHE) * taille_lame)


## la zone que les monstres au sol voient comme un trou (groupe "DEGATS", lu par
## BASE_IA.danger_devant), comme la barre de feu : le cercle balayé, prolongé
## de HAUTEUR_MONSTRES vers le bas
func _creer_zone_evitee() -> void:
	var zone := Area2D.new()
	zone.top_level = true                 # repère monde : « vers le bas » reste le bas
	zone.collision_layer = 1 << 30        # une couche à elle seule : la sonde des monstres la voit, rien d'autre
	zone.collision_mask = 0
	zone.monitoring = false
	var forme := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	var r := _rayon_evite()
	capsule.radius = r
	capsule.height = HAUTEUR_MONSTRES + 2.0 * r
	forme.shape = capsule
	zone.add_child(forme)
	zone.add_to_group("DEGATS")
	zone.set_meta(META, true)
	add_child(zone, false, Node.INTERNAL_MODE_FRONT)
	zone.global_position = global_position + Vector2(0.0, HAUTEUR_MONSTRES * 0.5)
	zone.global_rotation = 0.0


## la chaîne tendue de l'axe à l'anneau, la lame droite au bout
func _placer() -> void:
	if not is_node_ready() or _lame == null:
		return
	_theta = deg_to_rad(angle_depart) + _omega() * _temps
	var dir := Vector2.from_angle(_theta)
	var n := _maillons.size()
	for i in n:
		var m := _maillons[i]
		if not is_instance_valid(m):
			continue
		m.position = dir * longueur * (i + 0.5) / n - m.pivot_offset
		m.rotation = _theta
	_lame.position = dir * longueur - _lame.pivot_offset
	_lame.rotation = _theta - PI * 0.5


## la lame seule blesse : son dessin, à sa place exacte
func _blesser() -> void:
	if _contour.size() < 3:
		return
	var xf := global_transform
	var bout := Vector2.from_angle(_theta) * longueur
	var rot := _theta - PI * 0.5
	var pts := PackedVector2Array()
	for q in _contour:
		pts.append(xf * (bout + q.rotated(rot)))
	_forme.set_point_cloud(pts)
	_requete.transform = Transform2D.IDENTITY
	# le sens où elle passe
	var v := xf.basis_xform(Vector2(-sin(_theta), cos(_theta)) * longueur * _omega())
	var centre_lame := xf * (bout + _centre_touche.rotated(rot))
	var espace := get_world_2d().direct_space_state
	for res in espace.intersect_shape(_requete, 32):
		var corps: Object = res["collider"]
		if corps == null:
			continue
		if _temps - float(_dernier_coup.get(corps, -INF)) < delai_entre_coups:
			continue
		var porte := false
		if corps.has_method("apply_environment_damage"):
			# repoussé dans le sens où passe la lame, un peu vers le haut ; quand
			# elle passe à la verticale (sur les côtés du cercle), vers l'extérieur
			# (en roulade ou en dash, « pas porté » : on retente tant qu'il est dedans)
			var c: Vector2 = corps.centre_corps() if corps.has_method("centre_corps") else (corps as Node2D).global_position
			var cote := signf(v.x) if absf(v.x) >= 0.35 * v.length() else signf(c.x - xf.origin.x)
			if cote == 0.0:
				cote = 1.0
			porte = corps.apply_environment_damage(damage, Vector2(cote, -0.6).normalized())
		elif corps is BaseAI and corps.hp > 0:
			porte = corps.apply_damage(degats_monstres, centre_lame.x - signf(v.x) * 50.0, "lame_chaine")
		if porte:
			_dernier_coup[corps] = _temps


## ÉDITEUR seulement : le cercle que balaie la pointe, le sens de rotation et
## la zone évitée
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var couleur := Color(1.0, 0.55, 0.15, 0.55)
	var r := portee()
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, couleur, 2.0)
	if vitesse > 0.0:
		# une flèche sur le cercle, un peu après la lame, dans son sens
		var s := 1.0 if sens_horaire else -1.0
		var a := deg_to_rad(angle_depart) + s * 0.55
		var pointe := Vector2.from_angle(a) * r
		var avance := Vector2.from_angle(a + s * PI * 0.5)
		var dehors := Vector2.from_angle(a)
		draw_line(pointe, pointe - avance * 14.0 + dehors * 8.0, couleur, 3.0)
		draw_line(pointe, pointe - avance * 14.0 - dehors * 8.0, couleur, 3.0)
	if monstres_l_evitent:
		# la zone évitée par les monstres au sol, tracée en repère MONDE (vers le bas)
		draw_set_transform_matrix(global_transform.affine_inverse())
		var bleu := Color(0.45, 0.7, 1.0, 0.6)
		var haut := global_position
		var bas := haut + Vector2(0.0, HAUTEUR_MONSTRES)
		var re := _rayon_evite()
		draw_arc(haut, re, PI, TAU, 48, bleu, 2.0)
		draw_arc(bas, re, 0.0, PI, 48, bleu, 2.0)
		draw_line(haut + Vector2(-re, 0.0), bas + Vector2(-re, 0.0), bleu, 2.0)
		draw_line(haut + Vector2(re, 0.0), bas + Vector2(re, 0.0), bleu, 2.0)
		draw_set_transform_matrix(Transform2D.IDENTITY)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		queue_redraw()
