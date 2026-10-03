@tool
extends Node2D
## ============================================================================
## CRI EN ROND — le cri continu d'un monstre (le loup-garou) : des ronds qui
## partent de sa gueule aussi longtemps qu'il crie. Visuel seul : l'effet ne
## blesse pas et ne repousse pas, c'est le monstre qui s'en charge.
##
## USAGE : poser cette scène dans le monstre, SON ORIGINE SUR LA GUEULE, sous
## son nœud POINT (elle suit son retournement). Puis, depuis son script :
##     cri.crier()         # il crie… aussi longtemps qu'on veut
##     cri.arreter()       # il se tait : les dernières ondes finissent leur course
##     cri.crier(2.0)      # ou : un cri de 2 secondes, qui s'arrête tout seul
## `en_cours()` dit s'il crie ; le signal `fini` part quand la dernière onde
## s'est éteinte. Rappeler `crier()` pendant un cri le prolonge sans à-coup.
## `couronne()` dit où sont les ronds en ce moment : le monstre s'en sert pour
## que son cri blesse là où on le voit (loup_garou.gd).
##
## CE QU'ON VOIT (SCRIPT/SHADER/cri_rond_traits.gdshader et
## cri_rond_lentille.gdshader, fabriqués ici : la scène ne contient que ce nœud) :
##   • le cri ÉCLATE : une grosse onde d'un seul tenant file devant les autres ;
##   • puis des RONDS sortent de la gueule l'un après l'autre tant que le cri
##     dure — une onde forte, une faible — tracés au pinceau, qui maigrissent et
##     se défont en arcs en s'éloignant. Ils passent DERRIÈRE les personnages :
##     le monstre se détache devant son propre cri, le héros reste lisible
##     (case `devant` pour l'inverse) ;
##   • le DÉCOR ONDULE au passage de chaque onde (une lentille, comme le trou
##     noir : dessinée au niveau du décor, le monstre et le héros restent nets) ;
##   • la CAMÉRA tremble tant qu'il crie (plus fort à l'éclat du départ).
##
## POUR LE JUGER : ouvrir la scène, le cri s'y rejoue en boucle (case `apercu`) ;
## ou F6 : il crie en boucle au milieu de l'écran, sur le loup-garou, devant un
## décor de barres pour voir l'ondulation. Posé dans la scène du monstre,
## l'aperçu tourne aussi (pour le placer sur la gueule) ; dans un niveau, non.
## ============================================================================

signal fini

## jusqu'où portent les ondes (px, depuis la gueule)
@export var rayon := 560.0
## ondes par seconde
@export var cadence := 8.0
## leur vitesse (px/s)
@export var vitesse := 640.0
## l'épaisseur des ronds les plus forts (px)
@export var epaisseur := 16.0
## de combien le décor ondule au passage d'une onde (px ; 0 = pas du tout)
@export var deformation := 12.0
## la caméra tremble tant que le cri dure (0 = pas du tout)
@export var secousse := 3.0
## les ronds passent DEVANT les personnages (décoché : derrière eux, juste
## au-dessus du décor — le monstre se détache devant son cri)
@export var devant := false
@export var couleur := Color(1.0, 1.0, 1.0, 1.0)

@export_group("Aperçu")
## dans l'éditeur : le cri se rejoue en boucle (ici, ou posé dans la scène du monstre)
@export var apercu := true
## lancé seul (F6) : il se rejoue en boucle au milieu de l'écran
@export var demo_boucle := true
## l'aperçu et la démo crient pendant… (s)
@export var demo_duree := 2.4
## … puis se taisent pendant… (s)
@export var demo_pause := 1.4

const LENTILLE := preload("res://SCRIPT/SHADER/cri_rond_lentille.gdshader")
const TRAITS := preload("res://SCRIPT/SHADER/cri_rond_traits.gdshader")
const META := "genere_par_cri_rond"
const SANS_FIN := 100000.0
## l'éclat du départ file à tant de fois la vitesse des autres ondes
const VITESSE_ECLAT := 1.5
## le rectangle dépasse la portée de… (px)
const MARGE := 24.0
## au-delà de cette distance de la caméra, le cri ne la secoue plus (px)
const SECOUSSE_PRES := 1000.0
const SECOUSSE_LOIN := 1600.0
## la démo F6 pose le loup-garou qui crie : son image, et sa gueule ouverte
## dedans, depuis le milieu de l'image (mesurée sur ses images 4 à 6 du cri)
const LOUP_DEMO := "res://MEDIA/MONSTER/LOUP_GAROU/Cri/Werewolf_cri-5.png"
const GUEULE_LOUP := Vector2(0.0, -120.0)

var _copie: BackBufferCopy
var _lentille: ColorRect
var _traits: ColorRect

var _temps := 0.0
var _fin := SANS_FIN
var _duree := 0.0
var _emet := false        # il crie
var _vivant := false      # des ondes sont encore en route
var _graine := 1.0
var _demo := false
var _pause := 0.0


func _ready() -> void:
	_construire()
	if Engine.is_editor_hint():
		return
	# lancé seul (F6) : au milieu de l'écran, sur le loup, devant un décor
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
		_poser_decor_de_demo()


## Le monstre crie. `duree` > 0 : il se tait tout seul après tant de secondes ;
## sinon il crie jusqu'à `arreter()`.
func crier(duree: float = 0.0) -> void:
	if _emet:
		# il crie déjà : on ne fait que prolonger
		_duree = _temps + duree if duree > 0.0 else 0.0
		return
	_temps = 0.0
	_fin = SANS_FIN
	_duree = duree
	_emet = true
	_vivant = true
	_graine = float(randi_range(1, 400))      # deux cris ne se ressemblent pas
	_appliquer()
	_montrer(true)


## Il se tait : plus aucune onde ne part, les dernières finissent leur course.
func arreter() -> void:
	if not _emet:
		return
	_emet = false
	_fin = _temps


## Vrai tant qu'il crie (pas pendant que les dernières ondes s'éloignent).
func en_cours() -> bool:
	return _emet


## Où sont les ronds en ce moment, en px depuis la gueule : de `x` (le dedans :
## 0 tant qu'il crie, puis le vide qui s'élargit derrière la dernière onde) à
## `y` (le front : l'éclat du départ, puis la portée). (0, 0) : aucun rond.
func couronne() -> Vector2:
	if not _vivant:
		return Vector2.ZERO
	var dedans := 0.0 if _emet else minf(vitesse * (_temps - _fin), rayon)
	return Vector2(dedans, minf(vitesse * VITESSE_ECLAT * _temps, rayon))


func _process(delta: float) -> void:
	if _traits == null:
		_construire()                         # le script vient d'être rechargé dans l'éditeur
	var boucle := _demo or _apercu_editeur()
	if Engine.is_editor_hint() and not boucle:
		if _vivant:
			_eteindre()
		return
	if not _vivant:
		if boucle:
			_pause -= delta
			if _pause <= 0.0:
				crier(demo_duree)
		return
	_temps += delta
	if _emet and _duree > 0.0 and _temps >= _duree:
		arreter()
	# la dernière onde est au bout de sa portée
	if not _emet and _temps >= _fin + maxf(rayon / maxf(vitesse, 1.0), 0.45):
		_eteindre()
		_pause = demo_pause
		return
	_appliquer()
	_montrer(true)
	_secouer()


## dans l'éditeur, l'aperçu tourne dans cette scène ou dans celle où elle est
## posée directement (le monstre) — pas dans les niveaux où le monstre est posé
func _apercu_editeur() -> bool:
	if not Engine.is_editor_hint() or not apercu or not is_inside_tree():
		return false
	var racine := get_tree().edited_scene_root
	return racine != null and (racine == self or owner == racine)


func _eteindre() -> void:
	_emet = false
	_vivant = false
	_montrer(false)
	fini.emit()


func _montrer(oui: bool) -> void:
	if _traits == null:
		return
	# sans déformation, pas de lentille : pas de copie d'écran à faire
	var lentille := oui and deformation > 0.0
	_copie.visible = lentille
	_lentille.visible = lentille
	_traits.visible = oui
	_traits.z_index = 3 if devant else -1


## la caméra tremble tant qu'il crie : plus fort à l'éclat du départ, et moins
## quand le cri est loin d'elle
func _secouer() -> void:
	if secousse <= 0.0 or not _emet or _demo or Engine.is_editor_hint():
		return
	var cam := get_tree().get_first_node_in_group("Camera") as Node2D
	if cam == null or not cam.has_method("shake"):
		return
	var loin := cam.global_position.distance_to(global_position)
	var proche := 1.0 - smoothstep(SECOUSSE_PRES, SECOUSSE_LOIN, loin)
	var eclat := 1.0 + 1.5 * clampf(1.0 - _temps / 0.25, 0.0, 1.0)
	var voulu := secousse * eclat * proche
	# on ne coupe jamais une secousse plus forte déjà en route (un coup reçu…)
	var deja = cam.get("_shake_intensity")
	if voulu > 0.0 and (deja == null or float(deja) < voulu):
		cam.shake(voulu, 8.0)


func _appliquer() -> void:
	if _traits == null:
		return
	var demi := maxf(rayon, 60.0) + MARGE
	for rect: ColorRect in [_lentille, _traits]:
		rect.position = Vector2(-demi, -demi)
		rect.size = Vector2(2.0 * demi, 2.0 * demi)
		var mat := rect.material as ShaderMaterial
		mat.set_shader_parameter("taille", rect.size)
		mat.set_shader_parameter("centre", Vector2(demi, demi))
		mat.set_shader_parameter("rayon", maxf(rayon, 60.0))
		mat.set_shader_parameter("vitesse", vitesse)
		mat.set_shader_parameter("cadence", cadence)
		mat.set_shader_parameter("temps", _temps)
		mat.set_shader_parameter("fin", _fin)
		mat.set_shader_parameter("graine", _graine)
		mat.set_shader_parameter("vitesse_eclat", VITESSE_ECLAT)
	(_lentille.material as ShaderMaterial).set_shader_parameter("deformation", deformation)
	var mat_traits := _traits.material as ShaderMaterial
	mat_traits.set_shader_parameter("epaisseur", epaisseur)
	mat_traits.set_shader_parameter("couleur", couleur)


## Les trois nœuds du cri, fabriqués ici (ils ne sont pas enregistrés dans la
## scène) : la copie d'écran et la lentille au niveau du décor, les ronds
## par-dessus. La copie est FRAÎCHE, en mode écran entier : sans elle, un autre
## shader qui lit l'écran plus tôt (le flou du fond de sc_10) laisse une copie
## sans le décor — vécu avec le trou noir.
func _construire() -> void:
	for enfant in get_children(true):
		if enfant.has_meta(META):
			remove_child(enfant)
			enfant.queue_free()
	_copie = BackBufferCopy.new()
	_copie.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_copie.z_index = -1
	_ajouter(_copie)
	_lentille = _rectangle(LENTILLE)
	_lentille.z_index = -1
	_traits = _rectangle(TRAITS)
	_appliquer()
	_montrer(_vivant)


func _rectangle(shader: Shader) -> ColorRect:
	var rect := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ajouter(rect)
	return rect


func _ajouter(noeud: Node) -> void:
	noeud.set_meta(META, true)
	add_child(noeud, false, Node.INTERNAL_MODE_BACK)


## F6 : des barres de couleur derrière lui, pour voir le décor onduler, et le
## loup-garou qui crie, sa gueule sur l'origine
func _poser_decor_de_demo() -> void:
	var taille := get_viewport_rect().size * 2.0
	var fond := ColorRect.new()
	fond.color = Color(0.08, 0.09, 0.14)
	fond.size = taille
	fond.position = -taille * 0.5
	fond.z_index = -2
	add_child(fond)
	for i in 20:
		var barre := ColorRect.new()
		barre.color = Color(0.2, 0.26, 0.38) if i % 2 == 0 else Color(0.32, 0.18, 0.24)
		barre.size = Vector2(18.0, taille.y)
		barre.position = Vector2(-taille.x * 0.5 + (i + 0.5) * taille.x / 20.0, -taille.y * 0.5)
		barre.z_index = -2
		add_child(barre)
	for i in 12:
		var barre := ColorRect.new()
		barre.color = Color(0.22, 0.3, 0.26)
		barre.size = Vector2(taille.x, 10.0)
		barre.position = Vector2(-taille.x * 0.5, -taille.y * 0.5 + (i + 0.5) * taille.y / 12.0)
		barre.z_index = -2
		add_child(barre)
	if ResourceLoader.exists(LOUP_DEMO):
		var loup := Sprite2D.new()
		loup.texture = load(LOUP_DEMO)
		loup.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		loup.position = -GUEULE_LOUP
		add_child(loup)
