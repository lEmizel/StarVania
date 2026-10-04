@tool
extends Node2D
## ============================================================================
## LE CORPS DU SLIME — il tient la place de l'`animator` des autres monstres
## (`POINT/animator`), mais il n'a pas d'images : il est DESSINÉ par
## slime.gdshader, d'après un dessin de référence, et c'est ce script qui le
## fait vivre à chaque image.
##
## CE QU'IL FAIT TOUT SEUL : respirer, et se comporter en GELÉE — il s'étire en
## l'air, s'écrase à l'atterrissage puis tremblote (un ressort), se penche dans
## son élan ; son liquide se balance et son noyau traîne quand il change d'allure.
## IL RAMPE EN SE DÉFORMANT, en deux temps, sans pencher ni se balancer : il
## S'ÉTIRE vers l'avant (son arrière reste planté), puis son ARRIÈRE RATTRAPE
## son avant (qui reste planté à son tour), et ainsi de suite. Sa longueur
## change exactement deux fois plus vite qu'il n'avance : c'est ce qui tient
## immobile le bord qui attend.
## CE QUE LE CERVEAU LUI DIT (slime.gd) :
##     suivre(vitesse, au_sol)   à chaque pas : où il va, s'il touche le sol
##     ramper(vitesse)           il rampe à cette allure (0 : il ne rampe pas)
##     annoncer(true / false)    il se ramasse et tremble : il va bondir
##     atterrir(force)           il s'écrase ; au-delà de 0.6, des gouttes giclent
##     secouer(force)            un coup reçu : il tremblote
##     mourir()                  il éclate, laisse une flaque qui se résorbe ;
##                               `animation_finished` part à la fin
##
## POUR BASE_IA, c'est un animator : son `material` n'est pas utilisé (le vrai
## matériau est celui du rectangle fabriqué ici, rendu par `materiau()` : le
## cerveau le donne à BASE_IA, qui y pilote l'éclair de coup, la teinte, les
## fissures et le cristal) ; `pause()` le fige (la statue de cristal), `play()`
## le relance, `speed_scale` le ralentit (les entraves).
##
## Le rectangle du dessin est fabriqué ici, il n'est pas enregistré dans la
## scène : les réglages sont les valeurs exportées ci-dessous. Dans l'éditeur, il
## vit aussi (au repos), à la taille réglée sur le monstre.
## ============================================================================

signal animation_finished
signal animation_looped

@export_group("Dessin")
## sa largeur et sa hauteur au repos, sans le trait, en pixels du dessin, pour
## une taille de 1 (71,6 × 56 : deux fois le dessin de référence, qu'on
## retrouve tel quel à la taille 0.5)
@export var largeur := 71.6
@export var hauteur := 56.0
## le côté d'un pixel du dessin, en px d'écran (1,22 : le grain des autres monstres)
@export var pixel := 1.22
## le haut, clair
@export var couleur := Color(0.647, 0.125, 0.204)
## le bas, sombre — et le noyau
@export var couleur_ombre := Color(0.463, 0.086, 0.204)
@export var couleur_reflet := Color(0.973, 0.6, 0.655)
@export var couleur_trait := Color(0.275, 0.0, 0.0)
## la couleur de ses fissures (talisman « Coup de grâce ») : claires, celles des
## autres monstres sont rouges et ne se verraient pas sur lui
@export var couleur_fissures := Color(1.0, 0.85, 0.8)

@export_group("Reptation")
## de combien il s'étire à chaque fois (0.5 = de la moitié de sa longueur) : au
## moins (à petite allure) et au plus (à grande allure)
@export var reptation_min := 0.5
@export var reptation_max := 0.8
## pas plus de… étirements par seconde : au-delà, il s'étire plus loin à chaque fois
@export var reptation_cadence := 1.3

@export_group("Gelée")
## la raideur du ressort : plus grand = il tremblote plus vite
@export var raideur := 230.0
## l'amorti : plus grand = il se calme plus tôt
@export var amorti := 9.0
## de combien il respire au repos (0.035 = 3,5 % de sa hauteur ; 0 = immobile)
@export var respiration := 0.035
## de combien il s'étire en l'air, au plus (0.25 = un quart de sa hauteur)
@export var etirement_en_vol := 0.25
## de combien il se ramasse avant de bondir (0.36 = d'un bon tiers)
@export var tassement_annonce := 0.36
## de combien son liquide se balance sous un à-coup (0 = pas du tout)
@export var balancement := 1.0

const SHADER := preload("res://SCRIPT/MONSTER/slime.gdshader")
const META := "genere_par_slime"
## les gouttes d'un gros atterrissage (la même durée que dans le shader)
const ECLABOUSSURE := 0.45
## la mort : il s'aplatit, la flaque reste, puis elle se résorbe (s)
## le changement de vitesse, d'une image à l'autre, qui fait balancer son liquide (px/s)
const A_COUP := 220.0
## en rampant, sa longueur va de celle-ci (ramassé) à celle-ci plus sa course
const REPTATION_COURT := 0.92
const MORT_APLATI := 0.14
const MORT_FLAQUE := 2.2
const MORT_FONTE := 0.5
## la place laissée autour de lui pour ses gouttes, vivant et mort (pixels du dessin)
const MARGE_VIVANT := 42.0
const MARGE_MORT := 135.0

## pour BASE_IA (les entraves le ralentissent)
var speed_scale := 1.0
var animation: StringName = &"idle"
var frame := 0

## la taille du monstre (1 = le slime normal), donnée par le cerveau
var taille := 1.0

var _rect: ColorRect
var _mat: ShaderMaterial
var _fige := false
var _temps := 0.0
var _vitesse := Vector2.ZERO
var _vitesse_avant := Vector2.ZERO
var _au_sol := true
var _etire := 0.0             # sa hauteur en plus ou en moins (0 = au repos)
var _etire_v := 0.0
var _houle := 0.0             # le balancement de son liquide
var _houle_v := 0.0
var _sol := 1.0
var _penche := 0.0
var _annonce := false
var _rampe := 0.0             # l'allure à laquelle il rampe (px/s ; 0 : il ne rampe pas)
var _rampe_x := 1.0           # sa longueur du moment (1 = au repos)
var _rampe_etire := true      # il s'étire (sinon : son arrière rattrape)
var _eclab := -1.0
var _mort := -1.0
var _fini := false
var _graine := 1.0
var _echelle_mort := Vector2.ONE


func _ready() -> void:
	_graine = float(randi_range(1, 4000))
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


# ---------- ce que lui dit le cerveau ----------

## à chaque pas : sa vitesse (dans le monde) et s'il touche le sol
func suivre(vitesse: Vector2, au_sol: bool) -> void:
	var sens := signf(global_transform.x.x)
	if sens == 0.0:
		sens = 1.0
	_vitesse = Vector2(vitesse.x * sens, vitesse.y)
	_au_sol = au_sol


## il rampe à cette allure (px/s, dans le monde) ; 0 : il ne rampe pas
func ramper(vitesse: float) -> void:
	_rampe = absf(vitesse)


## il se ramasse et tremble (l'annonce du bond) — ou il arrête
func annoncer(oui: bool) -> void:
	_annonce = oui


## il touche le sol : il s'écrase (`force` de 0 à 1) ; fort, des gouttes giclent
func atterrir(force: float) -> void:
	_etire_v -= 7.0 * clampf(force, 0.0, 1.0)
	if force >= 0.6:
		_eclab = 0.0


## un coup reçu : il tremblote
func secouer(force := 1.0) -> void:
	_etire_v += 5.0 * force


## il éclate ; `animation_finished` part quand la flaque a disparu
func mourir() -> void:
	if _mort >= 0.0:
		return
	_mort = 0.0
	_fini = false
	_fige = false
	_annonce = false
	_eclab = -1.0
	animation = &"dead"
	_echelle_mort = _echelle_vivant()
	_poser_rectangle()


func duree_mort() -> float:
	return MORT_APLATI + MORT_FLAQUE + MORT_FONTE


# ---------- sa vie ----------

func _process(delta: float) -> void:
	if _rect == null or _mat == null:
		_construire()          # le script vient d'être rechargé dans l'éditeur
	if Engine.is_editor_hint():
		_lire_le_monstre()
	var d := 0.0 if _fige else delta * speed_scale
	if d > 0.0:
		_temps += d
		if _mort >= 0.0:
			_mort += d
			if not _fini and _mort >= duree_mort():
				_fini = true
				animation_finished.emit()
		else:
			_vivre(d)
	_appliquer()


## dans l'éditeur : la taille réglée sur le monstre (le nœud qui porte POINT)
func _lire_le_monstre() -> void:
	var monstre := get_parent().get_parent() if get_parent() != null else null
	if monstre == null:
		return
	var t = monstre.get("taille")
	if (t is float or t is int) and not is_equal_approx(float(t), taille):
		taille = clampf(float(t), 0.2, 8.0)
		_poser_rectangle()


func _vivre(d: float) -> void:
	# LA GELÉE : un ressort tire sa hauteur vers celle du moment
	var cible := respiration * sin(_temps * 2.4) if _rampe <= 1.0 else 0.0
	if _annonce:
		cible = -tassement_annonce
	elif not _au_sol:
		cible = minf(0.08 + absf(_vitesse.y) * 0.0002, etirement_en_vol)
	# SON LIQUIDE se balance quand sa vitesse change BRUTALEMENT (un bond, un
	# atterrissage, un coup) — pas quand il se met à ramper ou s'arrête
	var a_coup := _vitesse.x - _vitesse_avant.x
	if absf(a_coup) > A_COUP:
		_houle_v -= a_coup * 0.012 * balancement
	_vitesse_avant = _vitesse
	var reste := d
	while reste > 0.0:
		var pas := minf(reste, 1.0 / 120.0)
		_etire_v += (-raideur * (_etire - cible) - amorti * _etire_v) * pas
		_etire += _etire_v * pas
		_houle_v += (-90.0 * _houle - 5.0 * _houle_v) * pas
		_houle += _houle_v * pas
		reste -= pas
	_etire = clampf(_etire, -0.6, 0.5)
	_houle = clampf(_houle, -1.0, 1.0)
	# LA REPTATION, en deux temps : il s'étire, puis son arrière rattrape. Sa
	# longueur change deux fois plus vite qu'il n'avance : ses bords sont à
	# (milieu ± demi-longueur), donc l'un des deux reste où il est — l'arrière
	# quand il s'étire, l'avant quand il se ramasse.
	if _rampe > 1.0 and _au_sol and not _annonce:
		var longueur := maxf(largeur * maxf(taille, 0.05) * pixel * absf(global_transform.get_scale().x), 1.0)
		var course := clampf(_rampe / (longueur * maxf(reptation_cadence, 0.1)), reptation_min, reptation_max)
		var pas := 2.0 * _rampe * d / longueur
		if _rampe_etire:
			_rampe_x += pas
			if _rampe_x >= REPTATION_COURT + course:
				_rampe_etire = false
		else:
			_rampe_x -= pas
			if _rampe_x <= REPTATION_COURT:
				_rampe_etire = true
	else:
		# il s'arrête : il reprend sa forme
		_rampe_x = move_toward(_rampe_x, 1.0, d * 2.5)
		_rampe_etire = true
	_sol = move_toward(_sol, 1.0 if _au_sol else 0.0, d * 10.0)
	var penche_voulu := 0.0 if _au_sol else clampf(_vitesse.x / 1100.0, -0.3, 0.3)
	_penche = lerpf(_penche, penche_voulu, clampf(d * 12.0, 0.0, 1.0))
	if _eclab >= 0.0:
		_eclab += d
		if _eclab > ECLABOUSSURE:
			_eclab = -1.0


## son écrasement vivant : (largeur, hauteur) ; il garde à peu près son volume
func _echelle_vivant() -> Vector2:
	var y := clampf(1.0 + _etire, 0.4, 1.5)
	var e := Vector2(pow(y, -0.7), y)
	# en rampant : plus long, à peine plus bas
	e.x *= _rampe_x
	e.y *= pow(_rampe_x, -0.3)
	return e


func _echelle() -> Vector2:
	if _mort < 0.0:
		return _echelle_vivant()
	# mort : il s'aplatit en flaque, qui reste, puis se résorbe
	var a := clampf(_mort / MORT_APLATI, 0.0, 1.0)
	a = 1.0 - (1.0 - a) * (1.0 - a)
	var e := _echelle_mort.lerp(Vector2(1.5, 0.12), a)
	var fonte := clampf((_mort - MORT_APLATI - MORT_FLAQUE) / MORT_FONTE, 0.0, 1.0)
	e.x *= 1.0 - fonte
	return e


func _appliquer() -> void:
	if _mat == null:
		return
	var k := maxf(taille, 0.05)
	_mat.set_shader_parameter("pixel", pixel)
	_mat.set_shader_parameter("demi_largeur", largeur * 0.5 * k)
	_mat.set_shader_parameter("hauteur", hauteur * k)
	_mat.set_shader_parameter("echelle", _echelle())
	_mat.set_shader_parameter("penche", _penche)
	_mat.set_shader_parameter("sol", _sol)
	# l'annonce : il tremble d'une case, de gauche à droite
	var tremble := 0.0
	if _annonce and _mort < 0.0:
		tremble = 1.0 if int(_temps * 30.0) % 2 == 0 else -1.0
	_mat.set_shader_parameter("decalage", tremble)
	_mat.set_shader_parameter("houle", _houle)
	# le noyau traîne : il recule quand le liquide se balance, s'enfonce quand le corps s'écrase
	_mat.set_shader_parameter("noyau_decale", Vector2(-_houle * 4.0, _etire * 8.0) * k)
	_mat.set_shader_parameter("eclabousse", _eclab)
	_mat.set_shader_parameter("mort", _mort)
	_mat.set_shader_parameter("graine", _graine)
	_mat.set_shader_parameter("couleur", couleur)
	_mat.set_shader_parameter("couleur_ombre", couleur_ombre)
	_mat.set_shader_parameter("couleur_reflet", couleur_reflet)
	_mat.set_shader_parameter("couleur_trait", couleur_trait)
	_mat.set_shader_parameter("fissure_couleur", couleur_fissures)


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


## le rectangle autour de lui, calé sur la grille des pixels du dessin : sa
## base sur le sol, la place de ses gouttes autour (plus grande quand il éclate)
func _poser_rectangle() -> void:
	if _rect == null:
		return
	var k := maxf(taille, 0.05)
	var marge := (MARGE_MORT if _mort >= 0.0 else MARGE_VIVANT) * sqrt(k)
	var demi := ceilf(largeur * 0.5 * k * 1.75 + marge)
	var haut := ceilf(hauteur * k * 1.5 + marge)
	var bas := 3.0
	_rect.size = Vector2(2.0 * demi, haut + bas) * pixel
	_rect.position = Vector2(-demi, -haut) * pixel
	_mat.set_shader_parameter("pieds", Vector2(demi, haut) * pixel)
