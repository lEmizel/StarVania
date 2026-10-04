extends Control
## ============================================================================
## MENU START en jeu (ouvert par l'autoload PauseMenu sur "start") : une fenêtre
## CARRÉE avec des ONGLETS au-dessus.
##   • TALISMANS : les emplacements à découvrir et ceux qu'on équipe
##                 (page_talismans.gd) ;
##   • MENU      : reprendre, options, menu principal, quitter.
## Le jeu est figé (get_tree().paused) tant qu'il est affiché — la scène est en
## PROCESS_MODE_ALWAYS pour rester interactive.
##
## MANETTE : L1 / R1 changent d'onglet, la croix ou le stick déplacent le focus,
## Croix valide, Rond ou START ferment (Rond referme d'abord les options si
## elles sont ouvertes ; START, lui, ferme tout : c'est l'autoload qui l'écoute).
##
## AJOUTER UN ONGLET : un bouton de plus dans Cadre/Onglets/Boutons et une page
## de plus dans Cadre/Fenetre/Pages, À LA MÊME PLACE dans les deux listes. Une
## page qui a une méthode `prendre_le_focus()` choisit elle-même où poser le
## focus ; sinon il va sur son premier bouton.
## ============================================================================

const OPTIONS_SCENE := preload("res://SCRIPT/MENU/options.tscn")
const MENU_PRINCIPAL_SCENE := "uid://dm012xrdmag4v"  # SCRIPT/MENU/menu.tscn

## Les trois actions propres à ce menu. Si elles existent dans Projet →
## Paramètres du projet → Contrôles, ce sont LEURS touches qui comptent ; sinon
## elles sont créées à l'ouverture avec les touches ci-dessous.
const ACTION_ONGLET_PRECEDENT := "onglet_precedent"    # L1, ou A au clavier
const ACTION_ONGLET_SUIVANT := "onglet_suivant"        # R1, ou E au clavier
## (ui_cancel ne convient pas : dans ce projet il ne contient que Échap)
const ACTION_RETOUR := "retour_menu"                   # Rond, ou Retour arrière

## l'onglet montré à l'ouverture (0 = le premier)
@export var onglet_a_l_ouverture := 0
## espace gardé libre autour du menu quand l'écran est trop petit pour lui : il
## rétrécit pour tenir
@export var marge_ecran := 24.0
@export_group("Onglets")
@export var style_onglet_actif: StyleBox
@export var style_onglet_inactif: StyleBox
@export var couleur_texte_actif := Color(0.97, 0.93, 0.85)
@export var couleur_texte_inactif := Color(0.55, 0.5, 0.5)

@onready var _cadre: Control = $Cadre
@onready var _boutons_onglets: Array[Node] = $Cadre/Onglets/Boutons.get_children()
@onready var _pages: Array[Node] = $Cadre/Fenetre/Pages.get_children()
@onready var btn_reprendre: Button = $Cadre/Fenetre/Pages/Menu/Colonne/Reprendre
@onready var btn_options: Button = $Cadre/Fenetre/Pages/Menu/Colonne/Options
@onready var btn_menu: Button = $Cadre/Fenetre/Pages/Menu/Colonne/MenuPrincipal
@onready var btn_quitter: Button = $Cadre/Fenetre/Pages/Menu/Colonne/Quitter

var _onglet := 0
var _options: Control = null      # le panneau Options, tant qu'il est ouvert
var _frame_ouverture := -1


func _ready() -> void:
	_assurer_action(ACTION_ONGLET_PRECEDENT, JOY_BUTTON_LEFT_SHOULDER, KEY_Q)
	_assurer_action(ACTION_ONGLET_SUIVANT, JOY_BUTTON_RIGHT_SHOULDER, KEY_E)
	_assurer_action(ACTION_RETOUR, JOY_BUTTON_B, KEY_BACKSPACE)
	_frame_ouverture = Engine.get_process_frames()

	btn_reprendre.pressed.connect(fermer)
	btn_options.pressed.connect(_on_options_pressed)
	btn_menu.pressed.connect(_on_menu_principal_pressed)
	btn_quitter.pressed.connect(func() -> void:
		Player.sauvegarder()    # la partie est écrite avant de fermer le jeu
		get_tree().quit())
	_cabler_focus_menu()
	for i in _boutons_onglets.size():
		(_boutons_onglets[i] as Button).pressed.connect(_montrer_onglet.bind(i))

	get_viewport().size_changed.connect(_tenir_dans_l_ecran)
	_tenir_dans_l_ecran()
	_montrer_onglet(onglet_a_l_ouverture)


func _process(_delta: float) -> void:
	# la pression qui vient d'OUVRIR le menu (START, Échap) reste « juste
	# pressée » toute cette frame : on ne la relit pas ici
	if Engine.get_process_frames() == _frame_ouverture:
		return
	# même mécanique manette que le menu principal : valid_menu déclenche ce
	# qui a le focus (y compris les boutons du panneau Options)
	if Input.is_action_just_pressed("valid_menu"):
		_valider_le_focus()
	if _options != null:
		# MODAL : tant que les options sont ouvertes, Rond les referme et rien
		# d'autre ne passe (pas de changement d'onglet derrière le panneau)
		if Input.is_action_just_pressed(ACTION_RETOUR):
			_options.queue_free()
		return
	if Input.is_action_just_pressed(ACTION_ONGLET_SUIVANT):
		_montrer_onglet(_onglet + 1)
	elif Input.is_action_just_pressed(ACTION_ONGLET_PRECEDENT):
		_montrer_onglet(_onglet - 1)
	elif Input.is_action_just_pressed(ACTION_RETOUR):
		fermer()


func fermer() -> void:
	get_tree().paused = false
	queue_free()


# --------------------------------------------------------------------------
#  Onglets
# --------------------------------------------------------------------------

## montre l'onglet n°i (on boucle : après le dernier vient le premier)
func _montrer_onglet(i: int) -> void:
	_onglet = wrapi(i, 0, _pages.size())
	for k in _pages.size():
		var actif := k == _onglet
		(_pages[k] as Control).visible = actif
		var bouton := _boutons_onglets[k] as Button
		var style := style_onglet_actif if actif else style_onglet_inactif
		if style != null:
			for etat in ["normal", "hover", "pressed"]:
				bouton.add_theme_stylebox_override(etat, style)
		var couleur := couleur_texte_actif if actif else couleur_texte_inactif
		for etat in ["font_color", "font_hover_color", "font_pressed_color"]:
			bouton.add_theme_color_override(etat, couleur)
	_poser_le_focus()


## le focus va dans la page montrée : là où elle le décide, sinon sur son
## premier bouton
func _poser_le_focus() -> void:
	var page := _pages[_onglet]
	if page.has_method("prendre_le_focus"):
		page.prendre_le_focus()
		return
	var premier := _premier_focusable(page)
	if premier != null:
		premier.grab_focus()


func _premier_focusable(noeud: Node) -> Control:
	for enfant in noeud.get_children():
		var c := enfant as Control
		if c != null and c.visible and c.focus_mode != Control.FOCUS_NONE:
			return c
		var plus_bas := _premier_focusable(enfant)
		if plus_bas != null:
			return plus_bas
	return null


func _valider_le_focus() -> void:
	var c := get_viewport().gui_get_focus_owner()
	var bouton := c as Button
	if bouton != null:
		if not bouton.disabled:
			bouton.emit_signal("pressed")
	elif c != null and c.has_method("valider"):
		c.call("valider")      # un emplacement de talisman


## crée une action du menu si le projet ne la définit pas
func _assurer_action(nom: String, bouton: JoyButton, touche: Key) -> void:
	if InputMap.has_action(nom):
		return
	InputMap.add_action(nom)
	var manette := InputEventJoypadButton.new()
	manette.device = -1      # toutes les manettes
	manette.button_index = bouton
	InputMap.action_add_event(nom, manette)
	var clavier := InputEventKey.new()
	clavier.physical_keycode = touche    # la POSITION de la touche : Q et E d'un clavier QWERTY = A et E en AZERTY
	InputMap.action_add_event(nom, clavier)


# --------------------------------------------------------------------------
#  Onglet MENU
# --------------------------------------------------------------------------

## Chaîne de focus explicite des boutons, qui boucle de bas en haut ; gauche et
## droite ne font rien (ils ne doivent pas chercher un contrôle ailleurs)
func _cabler_focus_menu() -> void:
	var boutons: Array[Button] = [btn_reprendre, btn_options, btn_menu, btn_quitter]
	for i in boutons.size():
		var b := boutons[i]
		b.focus_neighbor_top = b.get_path_to(boutons[wrapi(i - 1, 0, boutons.size())])
		b.focus_neighbor_bottom = b.get_path_to(boutons[wrapi(i + 1, 0, boutons.size())])
		b.focus_neighbor_left = b.get_path_to(b)
		b.focus_neighbor_right = b.get_path_to(b)


func _on_options_pressed() -> void:
	if _options != null:
		return
	_options = OPTIONS_SCENE.instantiate()
	add_child(_options)  # enfant du menu pause : hérite du PROCESS_MODE_ALWAYS
	# MODAL : on cache la fenêtre tant que les options sont ouvertes — un
	# contrôle caché est infocusable, la navigation manette ne peut plus
	# "fuiter" vers les boutons de derrière
	_cadre.visible = false
	_options.tree_exited.connect(func() -> void:
		_options = null
		if not is_inside_tree() or is_queued_for_deletion():
			return
		_cadre.visible = true
		if is_instance_valid(btn_options):
			btn_options.grab_focus())


func _on_menu_principal_pressed() -> void:
	Player.sauvegarder()        # la partie est écrite avant de revenir au menu
	get_tree().paused = false
	Loader.load_scene_with_loading(MENU_PRINCIPAL_SCENE)
	queue_free()


# --------------------------------------------------------------------------
#  Écran trop petit (fenêtre très large ou très basse) : le menu rétrécit d'un
#  bloc pour tenir en entier, il n'est jamais coupé
# --------------------------------------------------------------------------

func _tenir_dans_l_ecran() -> void:
	var ecran := get_viewport_rect().size
	var libre := ecran - Vector2(marge_ecran, marge_ecran) * 2.0
	var echelle := minf(1.0, minf(libre.x / _cadre.size.x, libre.y / _cadre.size.y))
	_cadre.pivot_offset = _cadre.size * 0.5
	_cadre.scale = Vector2(echelle, echelle)
