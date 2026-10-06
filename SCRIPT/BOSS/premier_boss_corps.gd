@tool
extends Node2D
## ============================================================================
## LE CORPS DU PREMIER BOSS — FIGURE PROVISOIRE. Il tient la place de
## l'`animator` des autres monstres (`POINT/animator`), mais il n'a pas
## d'images : il est DESSINÉ par premier_boss.gdshader (une grande phalène vue
## de face, en vol, d'après son dessin de référence), et c'est ce script qui le
## fait vivre à chaque image.
##
## CE QU'IL FAIT TOUT SEUL : battre des ailes (doucement au repos, plus fort
## quand on le lui demande), laisser ses oreilles suivre ses montées et ses
## descentes.
## CE QUE LE CERVEAU LUI DIT (premier_boss.gd) :
##     suivre(vitesse)          à chaque pas : où elle va
##     voler(force)             la vigueur du battement, de 0 (repos) à 1
##     armer_ailes(true/false)  elle lève les ailes et les tient : l'annonce
##     coup_d_aile()            elle les abat d'un trait (elle lance ses pétales)
##     vrombir(true/false)      ses ailes battent très vite, à petits coups (son vent)
##     sonner()                 sa cloche se balance : elle sonne
##     agiter(true/false)       sa cloche tremble sans arrêt (la phase 2)
##     eveiller(true/false)     ses yeux s'ouvrent
##     lever_bras(true/false)   sa main quitte la cloche, le bras se lève / y revient
##     claquer()                le claquement de doigts : un éclat au bout de la main
##     mourir()                 ses ailes se replient, sa tête tombe
##     toucher_le_sol()         elle s'affaisse ; `animation_finished` part à la fin
##
## POUR BASE_IA, c'est un animator : son `material` n'est pas utilisé (le vrai
## matériau est celui du rectangle fabriqué ici, rendu par `materiau()` : le
## cerveau le donne à BASE_IA, qui y pilote l'éclair de coup et la teinte) ;
## `pause()` le fige, `play()` le relance, `speed_scale` le ralentit (les
## entraves).
##
## Le rectangle du dessin est fabriqué ici, il n'est pas enregistré dans la
## scène. Dans l'éditeur, elle vit aussi (au repos), à la taille réglée sur le
## monstre.
##
## LE JOUR OÙ SES IMAGES ARRIVENT : `POINT/animator` redevient un
## AnimatedSprite2D, et les appels ci-dessus se branchent sur ses animations.
## ============================================================================

signal animation_finished
signal animation_looped

@export_group("Dessin")
## du milieu du corps au bout d'une aile ouverte, pour une taille de 1 (px) :
## à 595, elle fait 445 px de la tête aux pieds — un peu moins de 1,75 fois
## son dessin de référence (266 px)
@export var demi_envergure := 595.0
## le côté d'un pixel du dessin, en px d'écran (1,75 : ceux de son dessin de
## référence, agrandi d'autant)
@export var pixel := 1.75

@export_group("Ailes")
## battements par seconde : au repos, et quand elle bat fort
@export var cadence := 0.8
@export var cadence_forte := 1.6
## de combien les ailes montent et descendent (degrés) : au repos, et fort
@export var battement := 7.0
@export var battement_fort := 15.0
@export_group("")

const SHADER := preload("res://SCRIPT/BOSS/premier_boss.gdshader")
const META := "genere_par_premier_boss"
## les mesures du dessin (les mêmes que dans le shader), en unités du dessin :
## du milieu au bout d'une aile, de la poitrine au point le plus bas, et la
## place qu'il lui faut autour d'elle
const DEMI_DESSIN := 96.0
const BAS := 42.0
const DEMI_CADRE := 104.0
const HAUT_CADRE := 66.0
const HAUT_TETE := 30.0
## la hauteur du milieu de sa cloche au-dessus de son point le plus bas, et son
## écart du milieu du corps, du côté où elle regarde
const HAUT_CLOCHE := 32.5
## la hauteur de ses yeux au-dessus de la poitrine (unités)
const HAUT_YEUX := 11.6
const ECART_CLOCHE := 3.4
## les ailes ARMÉES (levées et tenues) puis ABATTUES, en degrés : (haut, bas)
const AILES_ARMEES := Vector2(30.0, 14.0)
const AILES_ABATTUES := Vector2(-24.0, -12.0)
## le coup d'aile : la descente, puis le retour au battement (s)
const COUP_DESCENTE := 0.12
const COUP_RETOUR := 0.5
## les ailes qui VROMBISSENT : battements par seconde, et leur angle (degrés)
const VROMBIT_CADENCE := 5.0
const VROMBIT_ANGLE := 8.0
## la cloche qui sonne : elle se balance de … degrés, … fois par seconde, pendant … s
const CLOCHE_ANGLE := 24.0
const CLOCHE_CADENCE := 5.5
const CLOCHE_DUREE := 0.8
## le bras se lève ou retombe en … s ; l'éclat du claquement dure … s
const DUREE_BRAS := 0.22
const DUREE_CLAQUE := 0.18
## la mort : les ailes se replient en … s ; au sol, elle s'affaisse en … s
const MORT_REPLI := 0.55
const MORT_AFFAISSE := 0.4

## pour BASE_IA (les entraves la ralentissent)
var speed_scale := 1.0
var animation: StringName = &"idle"
var frame := 0

## la taille du monstre (1 = la taille normale), donnée par le cerveau
var taille := 1.0

var _rect: ColorRect
var _mat: ShaderMaterial
var _fige := false
var _temps := 0.0
var _phase := 0.0             # le battement des ailes (radians)
var _vigueur := 0.0           # du repos (0) au battement fort (1)
var _vigueur_voulue := 0.0
var _arme := 0.0              # ailes levées et tenues (0 à 1)
var _arme_voulu := false
var _coup := -1.0             # le temps depuis le coup d'aile (< 0 : aucun)
var _vrombit := 0.0           # ses ailes vrombissent (0 à 1)
var _vrombit_voulu := false
var _sonne := -1.0            # le temps depuis que la cloche sonne (< 0 : elle se tait)
var _agitee := false          # sa cloche tremble sans arrêt
var _yeux := false            # ses yeux sont ouverts
var _bras := 0.0
var _bras_voulu := false
var _claque := -1.0           # le temps depuis le claquement (< 0 : aucun)
var _oreilles := 0.0
var _vitesse := Vector2.ZERO
var _mort := -1.0             # le temps depuis sa mort (< 0 : vivante)
var _pose := -1.0             # le temps depuis qu'elle a touché le sol (< 0 : pas encore)
var _fini := false


func _ready() -> void:
	_construire()


## le matériau du dessin : c'est lui que BASE_IA doit piloter
func materiau() -> ShaderMaterial:
	if _mat == null:
		_construire()
	return _mat


# ---------- ce qu'attend BASE_IA d'un animator ----------

func play(nom: StringName = &"", _vitesse_anim := 1.0, _a_l_envers := false) -> void:
	_fige = false
	if nom != &"":
		animation = nom


func pause() -> void:
	_fige = true


func stop() -> void:
	_fige = true


func is_playing() -> bool:
	return not _fige


# ---------- ses mesures, en px, dans le repère de POINT ----------

## une unité du dessin, en px d'écran
func unite_px() -> float:
	return demi_envergure * maxf(taille, 0.05) / DEMI_DESSIN


## du milieu du corps au bout d'une aile ouverte
func demi_envergure_px() -> float:
	return demi_envergure * maxf(taille, 0.05)


## la hauteur de sa poitrine (l'attache des ailes) et celle du sommet de sa
## tête, au-dessus de son point le plus bas
func hauteur_poitrine() -> float:
	return BAS * unite_px()


func hauteur_tete() -> float:
	return (BAS + HAUT_TETE) * unite_px()


## le milieu de sa cloche, dans POINT
func place_cloche() -> Vector2:
	return Vector2(ECART_CLOCHE, -HAUT_CLOCHE) * unite_px()


## ses yeux (le milieu des deux), dans POINT
func place_yeux() -> Vector2:
	return Vector2(0.0, -(BAS + HAUT_YEUX) * unite_px())


# ---------- ce que lui dit le cerveau ----------

## à chaque pas : sa vitesse (dans le monde)
func suivre(vitesse: Vector2) -> void:
	_vitesse = vitesse


## la vigueur de son battement d'ailes : 0 = au repos, 1 = fort
func voler(force: float) -> void:
	_vigueur_voulue = clampf(force, 0.0, 1.0)


## elle lève les ailes et les tient (l'annonce de la pluie) — ou elle les relâche
func armer_ailes(oui: bool) -> void:
	_arme_voulu = oui


## elle abat ses ailes d'un trait, puis reprend son battement
func coup_d_aile() -> void:
	_arme_voulu = false
	_arme = 0.0
	_coup = 0.0


## ses ailes vrombissent (elles battent très vite, à petits coups) — ou reprennent
## leur battement
func vrombir(oui: bool) -> void:
	_vrombit_voulu = oui


## sa cloche se balance : elle sonne
func sonner() -> void:
	_sonne = 0.0


## sa cloche tremble sans arrêt — ou se calme
func agiter(oui: bool) -> void:
	_agitee = oui


## ses yeux s'ouvrent — ou se ferment
func eveiller(oui: bool) -> void:
	_yeux = oui


## son bras libre se lève (elle va claquer des doigts) — ou retombe
func lever_bras(oui: bool) -> void:
	_bras_voulu = oui


## le claquement de doigts : un éclat au bout de sa main
func claquer() -> void:
	_claque = 0.0


## elle meurt : ses ailes se replient, sa tête tombe
func mourir() -> void:
	if _mort >= 0.0:
		return
	_mort = 0.0
	_fini = false
	_fige = false
	_arme_voulu = false
	_bras_voulu = false
	_vrombit_voulu = false
	_coup = -1.0
	_claque = -1.0
	_sonne = -1.0
	animation = &"dead"


## morte, elle touche le sol : elle s'affaisse ; `animation_finished` part à la fin
func toucher_le_sol() -> void:
	if _pose < 0.0:
		_pose = 0.0


# ---------- sa vie ----------

func _process(delta: float) -> void:
	if _rect == null or _mat == null:
		_construire()          # le script vient d'être rechargé dans l'éditeur
	if Engine.is_editor_hint():
		_lire_le_monstre()
	var d := 0.0 if _fige else delta * speed_scale
	if d > 0.0:
		_vivre(d)
	_appliquer()


## dans l'éditeur : la taille réglée sur le monstre (le nœud qui porte POINT)
func _lire_le_monstre() -> void:
	var monstre := get_parent().get_parent() if get_parent() != null else null
	if monstre == null:
		return
	var t = monstre.get("taille")
	if (t is float or t is int) and not is_equal_approx(float(t), taille):
		taille = clampf(float(t), 0.2, 4.0)
		_poser_rectangle()


func _vivre(d: float) -> void:
	_temps += d
	_vigueur = move_toward(_vigueur, _vigueur_voulue, d * 2.5)
	_vrombit = move_toward(_vrombit, 1.0 if _vrombit_voulu else 0.0, d * 4.0)
	_phase = fposmod(_phase + TAU * lerpf(lerpf(cadence, cadence_forte, _vigueur), VROMBIT_CADENCE, _vrombit) * d, TAU)
	if _sonne >= 0.0:
		_sonne += d
		if _sonne > CLOCHE_DUREE:
			_sonne = -1.0
	_arme = move_toward(_arme, 1.0 if _arme_voulu else 0.0, d / 0.3)
	_bras = move_toward(_bras, 1.0 if _bras_voulu else 0.0, d / DUREE_BRAS)
	if _coup >= 0.0:
		_coup += d
		if _coup > COUP_DESCENTE + COUP_RETOUR:
			_coup = -1.0
	if _claque >= 0.0:
		_claque += d
		if _claque > DUREE_CLAQUE:
			_claque = -1.0
	# ses oreilles traînent : elles se lèvent quand elle descend, tombent quand elle monte
	var voulu := clampf(_vitesse.y / 45.0, -14.0, 10.0)
	if _mort >= 0.0:
		voulu = -30.0
		_mort += d
	_oreilles = lerpf(_oreilles, voulu, clampf(d * 6.0, 0.0, 1.0))
	if _pose >= 0.0:
		_pose += d
		if not _fini and _pose >= MORT_AFFAISSE + 0.3:
			_fini = true
			animation_finished.emit()


## l'angle de ses ailes du moment : (celles du haut, celles du bas), en degrés
func _angle_ailes() -> Vector2:
	var ampleur := lerpf(lerpf(battement, battement_fort, _vigueur), VROMBIT_ANGLE, _vrombit)
	var ailes := Vector2(ampleur * sin(_phase), 0.6 * ampleur * sin(_phase - 0.8))
	# elles vrombissent : un peu levées, comme une voile qui prend le vent
	ailes += Vector2(10.0, 4.0) * _vrombit
	# armées : elles se lèvent et tiennent
	var lisse := _arme * _arme * (3.0 - 2.0 * _arme)
	ailes = ailes.lerp(AILES_ARMEES, lisse)
	# le coup d'aile : abattues d'un trait, puis le battement reprend
	if _coup >= 0.0:
		if _coup < COUP_DESCENTE:
			var k := _coup / COUP_DESCENTE
			ailes = AILES_ARMEES.lerp(AILES_ABATTUES, k * k)
		else:
			var k := clampf((_coup - COUP_DESCENTE) / COUP_RETOUR, 0.0, 1.0)
			ailes = AILES_ABATTUES.lerp(ailes, k * k * (3.0 - 2.0 * k))
	return ailes


func _appliquer() -> void:
	if _mat == null:
		return
	var ailes := _angle_ailes()
	var repli := 0.0
	var affaisse := 0.0
	var tete := 0.0
	if _mort >= 0.0:
		var k := clampf(_mort / MORT_REPLI, 0.0, 1.0)
		repli = k * k * (3.0 - 2.0 * k)
		tete = -2.4 * repli
	if _pose >= 0.0:
		var k := clampf(_pose / MORT_AFFAISSE, 0.0, 1.0)
		affaisse = 1.0 - (1.0 - k) * (1.0 - k)
	var claque := 0.0
	if _claque >= 0.0:
		var k := _claque / DUREE_CLAQUE
		claque = minf(k / 0.18, 1.0) * (1.0 - k)
	_mat.set_shader_parameter("pixel", pixel)
	_mat.set_shader_parameter("unite", unite_px() / maxf(pixel, 0.1))
	_mat.set_shader_parameter("aile_haut", ailes.x)
	_mat.set_shader_parameter("aile_bas", ailes.y)
	_mat.set_shader_parameter("repli", repli)
	_mat.set_shader_parameter("bras", _bras * _bras * (3.0 - 2.0 * _bras))
	_mat.set_shader_parameter("claque", claque)
	_mat.set_shader_parameter("tete", tete)
	_mat.set_shader_parameter("oreilles", _oreilles)
	_mat.set_shader_parameter("queue", _temps * 1.7)
	var cloche := 0.0
	if _sonne >= 0.0:
		cloche = CLOCHE_ANGLE * sin(TAU * CLOCHE_CADENCE * _sonne) * (1.0 - _sonne / CLOCHE_DUREE)
	elif _agitee:
		cloche = 4.0 * sin(TAU * 2.3 * _temps)
	_mat.set_shader_parameter("cloche", cloche)
	_mat.set_shader_parameter("yeux", 1.0 if _yeux else 0.0)
	_mat.set_shader_parameter("affaisse", affaisse)


## le rectangle du dessin, fabriqué ici (il n'est pas enregistré dans la scène)
func _construire() -> void:
	for enfant in get_children(true):
		if enfant.has_meta(META):
			remove_child(enfant)
			enfant.queue_free()
	_rect = ColorRect.new()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_meta(META, true)
	add_child(_rect, false, Node.INTERNAL_MODE_BACK)
	_poser_rectangle()
	_appliquer()


## le rectangle autour d'elle, calé sur la grille des pixels du dessin : son
## point le plus bas à l'origine du nœud, la place de ses ailes levées autour
func _poser_rectangle() -> void:
	if _rect == null:
		return
	var cases := unite_px() / maxf(pixel, 0.1)
	var demi := ceilf(DEMI_CADRE * cases)
	var haut := ceilf((HAUT_CADRE + BAS) * cases)
	var bas := 3.0
	_rect.size = Vector2(2.0 * demi, haut + bas) * pixel
	_rect.position = Vector2(-demi, -haut) * pixel
	_mat.set_shader_parameter("pieds", Vector2(demi, haut) * pixel)
