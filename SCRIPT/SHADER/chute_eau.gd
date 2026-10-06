@tool
extends Node2D
## ============================================================================
## CHUTE D'EAU (6 oct. 2026) — décor. Une nappe d'eau translucide qui tombe,
## dessinée à plat (SCRIPT/SHADER/chute_eau.gdshader), d'après des images de
## référence : liserés clairs, bandes de brillance qui restent en place, longs
## trous en aiguille et plis qui tombent vite, éclaboussure au pied.
## Sans effet sur le jeu : ni collision, ni dégât.
##
## À POSER : le nœud est le SOMMET de la chute (là d'où l'eau sort) ; elle tombe
## de `hauteur` px. On la voit dans l'éditeur et elle y suit ses réglages en
## direct. Son ordre d'affichage est celui du nœud (sa place dans l'arbre, son
## z_index) : derrière un pilier, devant un mur…
## UN FILET (l'eau d'une cruche, d'une gouttière) : `largeur` 12 à 30,
## `ondulation` 2 à 4, `ecume` 20 à 40, `opacite` 0,8.
## Son rectangle est fabriqué par le script (enfant interne) : rien n'est
## enregistré dans les scènes.
##
## POUR LA JUGER : ouvrir la scène et faire F6 — trois chutes sur un fond
## d'essai : celle des réglages, une verte et large, un filet.
## ============================================================================

const SHADER := preload("res://SCRIPT/SHADER/chute_eau.gdshader")
const META := "genere_par_chute_eau"
const MAX_NAPPES := 8
## quand `nappes` vaut 0 : un pan tous les … px de largeur (à l'échelle 1)
const LARGEUR_D_UN_PAN := 50.0

## largeur de la nappe (px)
@export var largeur := 140.0
## hauteur de chute, du nœud (le sommet) jusqu'au pied (px)
@export var hauteur := 600.0
## la couleur de l'eau, et celle de son écume (liserés, bandes, éclaboussure)
@export var couleur := Color(0.42, 0.72, 1.0)
@export var couleur_ecume := Color(0.88, 0.96, 1.0)
## ce que la nappe cache du décor : 0,2 = un voile, 1 = pleine
@export_range(0.0, 1.0) var opacite := 0.5
## hauteur de l'éclaboussure au pied (px) ; 0 : aucune
@export var ecume := 120.0
@export_group("Réglages fins")
## vitesse de chute de ce qui tombe : les trous, les plis (px/s)
@export var vitesse := 4000.0
## nombre de pans de la nappe ; 0 : selon sa largeur
@export_range(0, 8) var nappes := 0
## l'abondance des trous : 0 = nappe pleine, 0,5 = de longues fentes fines un
## peu partout, 1 = en lanières
@export_range(0.0, 1.0) var dechirure := 0.5
## la grosseur des trous : 0,5 = moitié moins larges, 2 = deux fois plus
@export var taille_trous := 1.0
## taille du dessin (bandes, plis, liserés) : plus petit pour une chute lointaine
@export var echelle := 1.0
## la lumière que l'eau ajoute à ce qu'il y a derrière elle
@export_range(0.0, 1.0) var lueur := 0.5
## un filet : de combien son axe ondule (px) ; 0 : une nappe droite
@export var ondulation := 0.0
## fondus du sommet et du pied (px) ; 0 : coupe nette
@export var fondu_haut := 0.0
@export var fondu_bas := 0.0
## l'éclaboussure bouge par à-coups : … images par seconde (0 : en continu)
@export var cadence_ecume := 12.0
## le tirage du dessin (place des coutures…) ; 0 : tiré du nom du nœud, deux
## chutes d'un même tableau diffèrent donc d'elles-mêmes
@export var graine := 0
@export_group("")
## lancée seule (F6) : le fond d'essai et ses deux autres chutes
@export var demo_boucle := true

var _signature := ""
var _demo := false


func _ready() -> void:
	_demo = not Engine.is_editor_hint() and demo_boucle and get_parent() == get_tree().root
	if _demo:
		_preparer_la_demo()
	set_process(Engine.is_editor_hint())     # en jeu, rien à suivre : le shader s'anime seul
	_construire()


## ÉDITEUR : on suit les réglages en direct
func _process(_delta: float) -> void:
	if _calculer_signature() != _signature:
		_construire()


func _calculer_signature() -> String:
	return str([largeur, hauteur, couleur, couleur_ecume, opacite, ecume, vitesse, nappes, dechirure,
		taille_trous, echelle, lueur, ondulation, fondu_haut, fondu_bas, cadence_ecume, graine, name])


## le tirage du dessin : `graine`, ou un nombre tiré du nom du nœud
func _tirage() -> float:
	if graine != 0:
		return float(graine)
	return float(absi(hash(String(name))) % 997 + 1)


## le nombre de pans : `nappes`, ou selon la largeur
func _nombre_de_pans() -> int:
	if nappes > 0:
		return mini(nappes, MAX_NAPPES)
	return clampi(roundi(largeur / (LARGEUR_D_UN_PAN * maxf(echelle, 0.05))), 1, MAX_NAPPES)


func _construire() -> void:
	_signature = _calculer_signature()
	for enfant in get_children(true):
		if enfant.has_meta(META):
			remove_child(enfant)
			enfant.queue_free()
	var rect := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_meta(META, true)
	# le rectangle : la nappe, plus la place de l'éclaboussure de chaque côté et
	# un peu sous le pied (les mêmes mesures que le shader)
	var a_une_ecume := ecume > 0.5
	var marge := absf(ondulation) * 1.3 + largeur * 0.15 + 6.0
	var dessous := 2.0
	if a_une_ecume:
		marge = maxf(marge, 2.6 * (0.55 * ecume + 0.12 * largeur) + 4.0)
		dessous = 0.1 * ecume + 8.0
	rect.position = Vector2(-largeur * 0.5 - marge, -2.0)
	rect.size = Vector2(maxf(largeur, 1.0) + 2.0 * marge, maxf(hauteur, 1.0) + 2.0 + dessous)
	add_child(rect, false, Node.INTERNAL_MODE_FRONT)
	mat.set_shader_parameter("taille", rect.size)
	mat.set_shader_parameter("origine", rect.position)
	mat.set_shader_parameter("largeur", largeur)
	mat.set_shader_parameter("hauteur", hauteur)
	mat.set_shader_parameter("couleur", couleur)
	mat.set_shader_parameter("couleur_ecume", couleur_ecume)
	mat.set_shader_parameter("opacite", opacite)
	mat.set_shader_parameter("lueur", lueur)
	mat.set_shader_parameter("vitesse", vitesse)
	mat.set_shader_parameter("nappes", _nombre_de_pans())
	mat.set_shader_parameter("dechirure", dechirure)
	mat.set_shader_parameter("taille_trous", maxf(taille_trous, 0.0))
	mat.set_shader_parameter("echelle", maxf(echelle, 0.05))
	mat.set_shader_parameter("ondulation", ondulation)
	mat.set_shader_parameter("ecume", ecume if a_une_ecume else 0.0)
	mat.set_shader_parameter("cadence", cadence_ecume)
	mat.set_shader_parameter("fondu_haut", fondu_haut)
	mat.set_shader_parameter("fondu_bas", fondu_bas)
	mat.set_shader_parameter("graine", _tirage())


# --- la démo (F6) : un fond d'essai et deux autres chutes ---

func _preparer_la_demo() -> void:
	var ecran := get_viewport_rect().size
	position = Vector2(ecran.x * 0.22, ecran.y * 0.05)
	hauteur = ecran.y * 0.81
	var scene := load(scene_file_path) as PackedScene
	if scene == null:
		return
	var verte: Node2D = scene.instantiate()
	verte.name = "ChuteVerte"
	verte.demo_boucle = false
	verte.largeur = 240.0
	verte.hauteur = hauteur
	verte.couleur = Color(0.55, 0.63, 0.31)
	verte.couleur_ecume = Color(0.78, 0.91, 0.58)
	verte.opacite = 0.25
	verte.ecume = 180.0
	verte.position = Vector2(ecran.x * 0.55, position.y)
	var filet: Node2D = scene.instantiate()
	filet.name = "Filet"
	filet.demo_boucle = false
	filet.largeur = 16.0
	filet.hauteur = ecran.y * 0.5
	filet.opacite = 0.8
	filet.ondulation = 3.0
	filet.ecume = 28.0
	filet.position = Vector2(ecran.x * 0.86, ecran.y * 0.36)
	get_parent().add_child.call_deferred(verte)
	get_parent().add_child.call_deferred(filet)


## le fond d'essai : un mur, des piliers, une poutre sombre en travers (pour
## juger la transparence), un sol
func _draw() -> void:
	if not _demo:
		return
	var ecran := get_viewport_rect().size
	var o := -position
	draw_rect(Rect2(o, ecran), Color(0.06, 0.09, 0.17))
	draw_rect(Rect2(o + Vector2(0.0, ecran.y * 0.18), Vector2(ecran.x, ecran.y * 0.68)), Color(0.13, 0.18, 0.3))
	for part: float in [0.08, 0.3, 0.47, 0.64, 0.92]:
		draw_rect(Rect2(o + Vector2(ecran.x * part, 0.0), Vector2(70.0, ecran.y * 0.86)), Color(0.22, 0.29, 0.43))
	draw_rect(Rect2(o + Vector2(0.0, ecran.y * 0.4), Vector2(ecran.x, 46.0)), Color(0.04, 0.06, 0.11))
	draw_rect(Rect2(o + Vector2(0.0, ecran.y * 0.86), Vector2(ecran.x, ecran.y * 0.14)), Color(0.1, 0.14, 0.24))
	draw_rect(Rect2(o + Vector2(0.0, ecran.y * 0.86), Vector2(ecran.x, 5.0)), Color(0.3, 0.38, 0.54))
