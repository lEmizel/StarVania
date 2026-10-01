@tool
extends Node2D
## ============================================================================
## SLASH DU HÉROS — le croissant blanc des attaques, en shader (visuel seul : la
## hitbox reste dans PLAYER.tscn, pilotée par animator.gd). Il remplace les
## dessins `new_slash_1` (coups 1 et 2 au sol) et `slash_air` (attaque
## aérienne) : le même mouvement, mais à chaque image d'écran au lieu de six
## dessins.
##
## USAGE EN JEU : animator.gd en garde un, enfant de POINT (il se retourne avec
## le perso), et appelle `jouer("new_slash_1")` ou `jouer("slash_air")` à
## l'image où le coup part, `couper()` quand le coup est interrompu. Il se
## cache tout seul à la fin. Les SQUELETTES (classique et bleu) en gardent un
## aussi et jouent `"slash_squelette"` (1er oct. 2026) : le nom du fichier est
## resté « héros », mais c'est LE slash en shader du jeu, tous les slashs
## mesurés sont dans MESURES.
##
## D'OÙ VIENNENT LES CHIFFRES : de tes dessins, mesurés un par un (MESURES, plus
## bas). Le trajet de la lame est le bord extérieur de tous les croissants mis
## ensemble ; pour chaque dessin j'ai relevé de quel angle à quel angle va le
## croissant sur ce trajet, puis, en douze points de sa queue à sa tête, de
## combien son bord sort du trajet, son épaisseur et son opacité. Le dessin n°k
## sert de repère au MILIEU de son temps d'affichage ; entre deux repères, tout
## glisse. Ces tableaux ne sont pas faits pour être retouchés à la main : pour
## grossir ou affiner la lame, `epaisseur_facteur`.
##
## POUR LE JUGER : ouvrir la scène et faire F6, `demo_boucle` rejoue les deux
## slashs en boucle au milieu de l'écran (`demo_ralenti` pour les voir au
## ralenti). Dans l'éditeur, `apercu` choisit le slash et le curseur
## `progression` montre n'importe quel instant. La force des filets, le flou de
## la queue et la couleur se règlent sur le matériau du nœud Lame.
##
## EFFETS : `effet` habille le slash — "foudre" en fait un croissant DE foudre
## (chair de plasma bleu pâle, brins de foudre qui se tressent dedans, halo,
## étincelles ; tous les réglages sont sur le matériau du nœud Lame, section
## « la foudre »). En jeu c'est animator.gd qui choisit l'effet à chaque coup
## (`slash_effet` sur le joueur, puis le talisman équipé).
## ============================================================================

## Un repère par DESSIN, dans l'ordre. `centre` = centre du trajet depuis le
## centre de l'image ; `forme` = la courbe du trajet (voir slash_heros.gdshader) ;
## `queue` et `tete` = d'où à où va le croissant (degrés autour du centre, 0 =
## droit devant, 90 = vers le bas) ; `dehors`, `large`, `voile` = douze relevés
## de la queue à la tête (px hors du trajet, px d'épaisseur, opacité) ;
## `filets` = les petits traits dessinés autour du croissant, quatre au plus par
## dessin, six nombres chacun : de où à où le long de la lame (0 = queue, 1 =
## tête), à quelle distance du trajet à ses deux bouts (px, positif vers le
## centre), sa demi-épaisseur (px), son opacité.
const MESURES := {
	"new_slash_1": {
		"images_par_seconde": 25.0,
		"centre": Vector2(48.4, -36.1),
		"forme": [127.59, -10.00, -2.59, 17.62, 4.23],
		"queue": [-143.3, -118.6, -94.2, -17.1, 16.0, 88.5],
		"tete": [-90.7, -51.0, 41.3, 107.2, 147.2, 156.4],
		"dehors": [
			[-8.0, -7.1, -6.0, -4.9, -3.6, -2.3, -1.2, -0.3, 0.5, 1.2, 1.4, 1.3],
			[0.4, 1.4, 2.5, 3.2, 3.8, 4.0, 4.1, 3.8, 3.1, 2.3, 1.0, -0.2],
			[4.3, 4.0, 2.7, 0.8, -1.1, -2.4, -2.4, -1.6, -0.4, 1.3, 3.2, 4.2],
			[-3.5, -0.9, 0.7, 1.4, 2.2, 2.7, 2.5, 1.8, 0.8, -0.5, -2.4, -4.3],
			[0.2, 2.5, 2.9, 1.6, 0.5, -0.4, -1.1, -1.8, -2.4, -2.4, 0.3, 4.3],
			[-3.0, -2.3, -1.5, -0.6, 0.3, 1.1, 1.9, 3.2, 4.8, 6.8, 9.0, 10.9],
		],
		"large": [
			[6.4, 7.7, 8.8, 9.3, 9.3, 8.9, 8.4, 7.5, 6.5, 5.9, 5.2, 4.4],
			[7.7, 8.8, 9.4, 9.5, 9.5, 9.1, 8.9, 8.7, 8.3, 7.8, 6.8, 5.6],
			[13.3, 15.6, 18.1, 20.4, 23.2, 26.2, 28.6, 29.3, 27.7, 23.8, 18.0, 12.9],
			[22.6, 26.3, 28.1, 27.5, 26.5, 24.9, 21.7, 17.6, 13.3, 9.5, 6.5, 4.9],
			[12.9, 17.0, 18.9, 17.8, 15.6, 13.2, 10.9, 8.5, 6.6, 5.6, 6.1, 7.4],
			[6.3, 6.9, 7.5, 8.1, 8.6, 8.9, 8.8, 8.3, 7.5, 6.8, 6.2, 5.8],
		],
		"voile": [
			[0.32, 0.42, 0.55, 0.69, 0.82, 0.92, 0.97, 1.00, 1.00, 1.00, 0.94, 0.82],
			[0.39, 0.57, 0.77, 0.89, 0.96, 0.99, 1.00, 1.00, 1.00, 1.00, 1.00, 0.99],
			[0.38, 0.58, 0.80, 0.94, 0.99, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
			[0.32, 0.45, 0.66, 0.86, 0.97, 1.00, 1.00, 1.00, 1.00, 0.99, 0.92, 0.82],
			[0.37, 0.55, 0.79, 0.94, 0.99, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
			[0.28, 0.38, 0.53, 0.67, 0.79, 0.88, 0.93, 0.95, 0.95, 0.92, 0.80, 0.63],
		],
		"filets": [
			[0.11, 0.42, 26.1, 23.2, 2.8, 0.96,  0.53, 0.73, -11.3, -11.5, 2.9, 0.97,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[-0.08, 0.33, 24.3, 14.8, 3.5, 0.77,  0.20, 0.52, -13.7, -10.7, 3.1, 0.87,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.45, 0.70, 39.9, 42.2, 3.2, 0.78,  0.75, 0.84, -6.5, -7.2, 2.1, 0.68,  0.90, 0.94, 15.7, 10.8, 2.0, 0.64,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.37, 0.62, -7.5, -10.8, 2.7, 0.81,  0.25, 0.55, 39.1, 28.9, 2.7, 0.80,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.27, 0.57, 27.8, 20.6, 2.2, 0.80,  0.23, 0.37, -13.1, -7.0, 2.0, 0.64,  0.68, 0.82, 19.8, 20.7, 1.9, 0.95,  0.85, 0.92, -3.6, -9.8, 2.2, 0.87],
			[0.74, 0.90, 9.2, 2.2, 2.3, 0.55,  0.78, 0.88, -12.1, -15.9, 1.9, 0.48,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
		],
	},
	"slash_air": {
		"images_par_seconde": 23.0,
		"centre": Vector2(67.3, -35.8),
		"forme": [163.31, 1.73, 3.47, 23.01, -4.53],
		"queue": [-154.4, -154.4, -127.9, -66.8, 39.0, 100.4],
		"tete": [-132.6, -132.6, -69.4, 119.8, 159.5, 171.9],
		"dehors": [
			[-4.8, -3.4, -1.7, -0.2, 0.9, 1.7, 2.4, 2.8, 2.9, 2.4, 1.4, 0.5],
			[-4.5, -3.3, -1.7, -0.3, 1.0, 2.0, 2.7, 3.1, 3.1, 2.6, 1.7, 0.9],
			[-3.7, -0.9, 2.1, 4.1, 5.1, 5.4, 4.6, 2.9, 0.8, -1.5, -4.0, -6.1],
			[-3.3, -1.6, 1.1, 2.8, 2.0, -0.4, -1.9, -1.7, -0.8, -0.0, 0.5, 0.5],
			[-3.3, -0.9, 0.8, 1.1, 0.8, 0.6, 0.4, 0.1, -0.2, -0.7, -1.5, -2.4],
			[5.7, 4.6, 3.0, 1.4, -0.1, -1.1, -1.5, -1.1, 0.0, 1.2, 1.9, 1.7],
		],
		"large": [
			[2.9, 3.6, 4.6, 5.3, 5.8, 6.0, 6.0, 5.9, 5.4, 4.3, 2.8, 1.6],
			[3.2, 3.9, 4.8, 5.6, 6.0, 6.3, 6.5, 6.3, 5.7, 4.6, 3.2, 2.0],
			[9.3, 10.7, 11.5, 11.6, 11.5, 10.9, 9.5, 7.7, 6.7, 6.2, 5.3, 4.4],
			[15.5, 21.6, 30.2, 37.2, 39.5, 37.1, 32.2, 26.6, 21.2, 16.2, 11.2, 7.5],
			[25.1, 25.7, 24.1, 21.5, 19.8, 19.1, 19.0, 18.9, 18.0, 15.9, 12.4, 9.0],
			[19.9, 19.4, 19.1, 19.1, 19.1, 18.9, 18.2, 17.1, 15.4, 13.1, 10.0, 7.2],
		],
		"voile": [
			[0.37, 0.37, 0.37, 0.37, 0.37, 0.37, 0.37, 0.37, 0.37, 0.37, 0.37, 0.36],
			[1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 0.99, 0.97],
			[0.32, 0.44, 0.62, 0.78, 0.89, 0.94, 0.98, 1.00, 1.00, 1.00, 1.00, 1.00],
			[0.68, 0.88, 0.99, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 0.96, 0.90],
			[0.41, 0.59, 0.80, 0.93, 0.99, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
			[0.37, 0.50, 0.67, 0.81, 0.90, 0.96, 0.99, 1.00, 1.00, 1.00, 1.00, 1.00],
		],
		"filets": [
			[0.23, 0.49, 15.1, 12.6, 1.4, 0.37,  0.45, 0.61, -7.1, -8.6, 1.2, 0.37,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.23, 0.49, 15.1, 12.7, 1.5, 1.00,  0.45, 0.61, -7.1, -8.6, 1.2, 1.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.42, 0.60, -14.2, -12.1, 1.6, 1.00,  0.70, 0.77, 11.3, 12.0, 1.3, 1.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.24, 0.48, -16.8, -11.3, 3.3, 0.98,  0.50, 0.73, 49.9, 26.3, 4.1, 0.90,  0.16, 0.29, 32.3, 46.7, 3.4, 0.86,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.25, 0.62, -21.9, -17.1, 5.2, 0.82,  0.25, 0.74, 32.7, 32.5, 4.8, 0.89,  0.88, 1.12, -20.7, -8.6, 5.6, 0.98,  0.85, 1.03, 26.0, 19.4, 4.6, 0.97],
			[0.29, 0.61, -16.1, -7.9, 3.3, 0.96,  0.92, 1.08, 22.9, 22.7, 3.6, 0.96,  0.50, 0.73, 33.6, 34.4, 2.6, 0.97,  1.05, 1.19, -5.6, 3.5, 3.0, 1.00],
		],
	},
	"slash_squelette": {
		# le slash des SQUELETTES (classique et bleu : les mêmes dessins), mesuré
		# sur ses dessins retournés en miroir (il tourne dans l'autre sens)
		"images_par_seconde": 35.0,
		"miroir": true,
		"rectangle": Vector2(340, 340),
		"centre": Vector2(-9.5, 5.0),
		"forme": [112.98, 4.73, 0.90, 4.61, 3.09],
		"queue": [49.0, 87.7, 104.2, 120.0, 204.6, 262.8],
		"tete": [76.4, 152.4, 222.6, 301.4, 329.3, 329.3],
		"dehors": [
			[7.8, 7.2, 6.3, 5.4, 4.3, 2.9, 1.5, 0.2, -1.4, -2.7, -3.8, -4.9],
			[-4.2, -3.4, -2.3, -1.5, -1.0, -0.8, -0.7, -0.7, -0.8, -1.2, -2.3, -3.5],
			[-1.9, -1.0, -0.1, 0.4, 0.6, 0.6, 0.2, -0.6, -1.6, -2.6, -3.1, -3.1],
			[3.2, 3.2, 3.2, 3.4, 2.8, 1.1, -0.6, -1.5, -1.1, 0.0, 1.1, 1.5],
			[-0.7, -0.4, -0.1, 0.6, 1.7, 2.3, 2.5, 2.1, 1.3, 0.0, -1.4, -2.4],
			[1.3, 1.9, 2.3, 2.2, 1.8, 1.1, 0.3, -0.3, -1.1, -1.9, -2.6, -3.0],
		],
		"large": [
			[3.8, 4.1, 4.5, 5.0, 5.5, 5.2, 4.7, 4.4, 3.7, 2.9, 2.3, 1.7],
			[5.4, 6.8, 8.6, 10.0, 10.8, 10.7, 10.3, 9.8, 9.2, 8.1, 6.3, 4.6],
			[9.6, 11.4, 13.0, 13.7, 14.1, 14.4, 14.3, 13.1, 10.9, 8.1, 5.2, 3.4],
			[15.2, 16.4, 17.9, 18.9, 18.4, 16.8, 14.6, 12.1, 9.7, 7.4, 5.2, 3.6],
			[12.9, 14.1, 14.6, 14.1, 12.8, 11.0, 9.4, 7.8, 6.2, 5.0, 3.8, 2.9],
			[8.3, 8.8, 8.7, 8.0, 6.9, 5.9, 5.1, 4.6, 4.2, 3.7, 2.8, 2.0],
		],
		"voile": [
			[1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 0.99, 0.98],
			[0.23, 0.30, 0.41, 0.54, 0.70, 0.87, 0.97, 1.00, 1.00, 1.00, 1.00, 1.00],
			[0.35, 0.53, 0.74, 0.89, 0.97, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
			[0.50, 0.72, 0.91, 0.98, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
			[0.53, 0.74, 0.91, 0.97, 0.99, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
			[0.47, 0.67, 0.87, 0.97, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 1.00],
		],
		"filets": [
			[0.41, 0.64, 10.4, 14.7, 1.2, 1.00,  0.38, 0.66, -10.3, -3.8, 1.2, 1.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.69, 0.82, -4.6, -5.0, 1.2, 1.00,  0.59, 0.76, 15.9, 15.9, 1.2, 1.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.46, 0.75, -9.5, -5.2, 1.8, 1.00,  0.58, 0.92, 27.2, 15.1, 1.5, 1.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.52, 0.67, -6.5, -7.8, 1.2, 1.00,  0.50, 0.67, 22.4, 17.3, 1.2, 1.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.48, 0.65, -9.9, -11.2, 1.4, 1.00,  0.46, 0.55, 15.3, 15.4, 1.2, 1.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
			[0.55, 0.69, 14.8, 15.7, 1.2, 1.00,  0.70, 0.82, -7.0, -5.9, 1.2, 1.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00,  0.00, 0.00, 0.0, 0.0, 0.0, 0.00],
		],
	},
}

## le slash montré dans l'éditeur et par la démo
@export_enum("new_slash_1", "slash_air", "slash_squelette") var apercu := "new_slash_1":
	set(v):
		apercu = v
		_nom = v
		_appliquer()
## l'habillage du slash : "aucun" = le croissant blanc des dessins,
## "foudre" = le même croissant, fait de foudre ; "feu" = fait de feu
@export_enum("aucun", "foudre", "feu") var effet := "aucun":
	set(v):
		effet = v
		_appliquer()
## instant affiché, 0 → 1 (aperçu dans l'éditeur ; en jeu c'est le script)
@export_range(0.0, 1.0, 0.005) var progression := 0.45:
	set(v):
		progression = clampf(v, 0.0, 1.0)
		_appliquer()
## lancé seul (F6) : rejoue les slashs en boucle au milieu de l'écran
@export var demo_boucle := true
@export var demo_pause := 0.5
## la démo tourne tant de fois plus lentement que le jeu (1 = vitesse réelle)
@export_range(1.0, 20.0, 0.5) var demo_ralenti := 1.0
## grossit ou affine la lame (1 = l'épaisseur des dessins)
@export_range(0.3, 3.0, 0.05) var epaisseur_facteur := 1.0:
	set(v):
		epaisseur_facteur = v
		_appliquer()

@onready var _lame: ColorRect = $Lame

## le rectangle de dessin d'un slash qui n'en précise pas (celui des dessins du
## héros) ; un slash plus petit en donne un à sa taille (`"rectangle"`) : moins
## de pixels à calculer
const RECTANGLE_DEFAUT := Vector2(650.0, 650.0)
## un effet (foudre, feu) déborde de la lame : le rectangle réduit d'un slash
## s'agrandit d'autant quand il en porte un
const MARGE_EFFET := 80.0

var _nom := "new_slash_1"
var _t := 0.0
var _joue := false
var _demo := false
var _graine := 0.0    # un nombre par coup : deux slashs n'ont jamais les mêmes éclairs


func _ready() -> void:
	_nom = apercu
	if Engine.is_editor_hint():
		_appliquer()
		return
	# lancé seul (F6) : au milieu de l'écran, en boucle
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		position = get_viewport_rect().size * 0.5
		jouer(apercu)
	else:
		visible = false


## true si ce slash est refait en shader (sinon animator.gd garde le dessin)
func connait(nom: String) -> bool:
	return MESURES.has(nom)


## Joue un slash depuis le début. Retourne false si ce nom n'est pas refait en
## shader : rien n'est joué.
func jouer(nom: String) -> bool:
	if not MESURES.has(nom):
		return false
	_nom = nom
	_t = 0.0
	_joue = true
	_graine = randf() * 100.0
	visible = true
	progression = 0.0
	return true


## le coup est interrompu : le slash disparaît aussitôt
func couper() -> void:
	_joue = false
	visible = false


## durée du slash : celle de son animation dessinée
func duree() -> float:
	var m: Dictionary = MESURES[_nom]
	return float(m["queue"].size()) / float(m["images_par_seconde"])


## La géométrie d'un slash à l'instant `prog` (0 → 1 de son animation), pour
## qui veut se caler dessus (le croissant de sang, lâché sur la lame) : le
## centre du trajet (px, repère de ce nœud), sa courbe (`forme` : a0, a1, b1,
## a2, b2), les angles de la queue et de la tête de la lame (rad), et la durée
## du slash (s).
func geometrie(nom: String, prog: float) -> Dictionary:
	var m: Dictionary = MESURES[nom]
	var n: int = m["queue"].size()
	var x := clampf(prog, 0.0, 1.0) * float(n)
	var debut: float = m["queue"][0]
	var fin: float = m["tete"][n - 1]
	return {
		"centre": m["centre"],
		"forme": m["forme"],
		"queue": deg_to_rad(_angle(m["queue"], x, debut, fin)),
		"tete": deg_to_rad(_angle(m["tete"], x, debut, fin)),
		"duree": float(n) / float(m["images_par_seconde"]),
	}


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _joue:
		return
	_t += delta / (demo_ralenti if _demo else 1.0)
	var d := duree()
	if _t < d:
		progression = _t / d
		return
	progression = 1.0
	if not _demo:
		couper()
	elif _t >= d + demo_pause:
		# la démo alterne les slashs
		var noms := MESURES.keys()
		jouer(noms[(noms.find(_nom) + 1) % noms.size()])


func _appliquer() -> void:
	if not is_node_ready() or not MESURES.has(_nom):
		return
	var mat := _lame.material as ShaderMaterial
	if mat == null:
		return
	var m: Dictionary = MESURES[_nom]
	var n: int = m["queue"].size()
	# le temps compté en dessins : le dessin n°k est le repère de l'instant k + 0,5
	var x := progression * float(n)
	var debut: float = m["queue"][0]
	var fin: float = m["tete"][n - 1]
	var q := deg_to_rad(_angle(m["queue"], x, debut, fin))
	var t := deg_to_rad(_angle(m["tete"], x, debut, fin))
	# entre quels dessins on est, et où entre les deux
	var u := clampf(x - 0.5, 0.0, float(n - 1))
	var k0 := int(floor(u))
	var k1 := mini(k0 + 1, n - 1)
	var w := u - float(k0)
	# la lame apparaît d'un coup, comme le premier dessin (c'est sa longueur qui
	# part de zéro), et meurt en s'amincissant sur le dernier demi-dessin
	var vie := clampf((float(n) - x) / 0.5, 0.0, 1.0)
	# l'effet : la foudre a besoin du temps qui passe, de l'angle de naissance
	# de la lame (l'électricité ne traîne pas avant), de sa vie, d'une graine
	mat.set_shader_parameter("foudre", 1.0 if effet == "foudre" else 0.0)
	mat.set_shader_parameter("feu", 1.0 if effet == "feu" else 0.0)
	mat.set_shader_parameter("temps", progression * duree() if Engine.is_editor_hint() else _t)
	mat.set_shader_parameter("origine", deg_to_rad(debut))
	mat.set_shader_parameter("vie", vie)
	mat.set_shader_parameter("graine", _graine)
	# le rectangle à la taille de CE slash, centré sur le nœud
	var rect: Vector2 = m.get("rectangle", RECTANGLE_DEFAUT)
	if m.has("rectangle") and effet != "aucun":
		rect += Vector2(MARGE_EFFET, MARGE_EFFET)
	if _lame.size != rect:
		_lame.size = rect
		_lame.position = -rect * 0.5
	mat.set_shader_parameter("taille", rect)
	# mesuré sur les dessins retournés : le shader les retourne au rendu
	mat.set_shader_parameter("miroir", -1.0 if m.get("miroir", false) else 1.0)
	mat.set_shader_parameter("centre", m["centre"])
	var f: Array = m["forme"]
	mat.set_shader_parameter("forme", Vector4(f[0], f[1], f[2], f[3]))
	mat.set_shader_parameter("forme_b2", f[4])
	mat.set_shader_parameter("queue", q)
	mat.set_shader_parameter("tete", maxf(t, q + 0.001))
	mat.set_shader_parameter("dehors", _releves(m["dehors"][k0], m["dehors"][k1], w, 1.0))
	mat.set_shader_parameter("large", _releves(m["large"][k0], m["large"][k1], w, vie * epaisseur_facteur))
	mat.set_shader_parameter("voile", _releves(m["voile"][k0], m["voile"][k1], w, 1.0))
	# les filets du dessin qu'on quitte s'effacent pendant que ceux du suivant
	# apparaissent ; tous suivent la lame (ils sont repérés par rapport à elle)
	var filets := PackedFloat32Array()
	for paire in [[k0, (1.0 - w) * vie], [k1, w * vie if k1 != k0 else 0.0]]:
		var releve: Array = m["filets"][paire[0]]
		for i in releve.size():
			# le 6e nombre de chaque filet est son opacité : c'est elle qui fond
			filets.append(releve[i] * (paire[1] if i % 6 == 5 else 1.0))
	mat.set_shader_parameter("filets", filets)


## les douze relevés à mi-chemin entre deux dessins, multipliés par `facteur`
func _releves(a: Array, b: Array, w: float, facteur: float) -> PackedFloat32Array:
	var r := PackedFloat32Array()
	r.resize(a.size())
	for i in a.size():
		r[i] = lerpf(a[i], b[i], w) * facteur
	return r


## Un angle (queue ou tête) à l'instant `x`, compté en dessins de 0 à n. Les
## repères sont aux instants 0,5 ; 1,5 ; … ; la lame part de l'angle `debut` (à
## l'instant 0) et finit à l'angle `fin` (à l'instant n). Entre deux repères la
## courbe est lisse (Catmull-Rom) : pas d'à-coup quand la lame passe d'un dessin
## au suivant.
func _angle(reperes: Array, x: float, debut: float, fin: float) -> float:
	var n := reperes.size()
	var pts: Array[float] = [debut]
	for v in reperes:
		pts.append(float(v))
	pts.append(fin)
	# instants des points : 0 ; 0,5 ; 1,5 ; … ; n - 0,5 ; n
	var u := clampf(x, 0.0, float(n))
	var i := 0            # on est entre pts[i] et pts[i + 1]
	var t := 0.0
	if u < 0.5:
		t = u / 0.5
	elif u >= float(n) - 0.5:
		i = n
		t = (u - (float(n) - 0.5)) / 0.5
	else:
		i = int(floor(u - 0.5)) + 1
		t = (u - 0.5) - floor(u - 0.5)
	var p0: float = pts[maxi(i - 1, 0)]
	var p1: float = pts[i]
	var p2: float = pts[i + 1]
	var p3: float = pts[mini(i + 2, n + 1)]
	var v := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
	# pas de dépassement : l'angle reste entre ses deux repères
	return clampf(v, minf(p1, p2), maxf(p1, p2))
