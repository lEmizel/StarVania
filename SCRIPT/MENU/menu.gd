extends Control

@onready var btn_play : Button = $"CenterContainer/BoxContainer/PLAY"
@onready var btn_load : Button = $"CenterContainer/BoxContainer/LOAD"
@onready var btn_options : Button = $"CenterContainer/BoxContainer/OPTIONS"
@onready var btn_quit : Button = $"CenterContainer/BoxContainer/QUIT"
@onready var _boite_principale : BoxContainer = $"CenterContainer/BoxContainer"

# ordre logique pour le focus
@onready var _buttons : Array[Button] = [btn_play, btn_load, btn_options, btn_quit]

## ---------------------------------------------------------------------------
## LES DÉMOS proposées par le bouton PLAY, dans l'ordre d'affichage.
## Ajouter une démo = ajouter UNE ligne ici : le nom du bouton + la première
## scène à charger (chemin res:// ou uid://). Une démo dont la scène n'existe
## pas encore apparaît grisée au lieu de planter.
## ---------------------------------------------------------------------------
const DEMOS := [
	{"nom": "DEMO 1", "scene": "uid://gq88m0garham"},                 # la démo d'origine, démarre sur scene_7
	{"nom": "DEMO 2", "scene": "res://SCRIPT/SCENE/scene_08.tscn"},
]
const OPTIONS_SCENE := preload("res://SCRIPT/MENU/options.tscn")

var _boite_demos : BoxContainer = null     # liste DEMO 1, DEMO 2, …, BACK (construite au ready, cachée)
var _boutons_demos : Array[Button] = []
var _btn_retour : Button = null
var _frame_ouverture := -1                 # frame où la liste s'est ouverte (anti double validation)

func _ready() -> void:
	# signaux
	SignalUtils.connect_signal(btn_play, "pressed", self, "_on_play_pressed")
	SignalUtils.connect_signal(btn_load, "pressed", self, "_on_load_pressed")
	SignalUtils.connect_signal(btn_options, "pressed", self, "_on_options_pressed")
	SignalUtils.connect_signal(btn_quit, "pressed", self, "_on_quit_pressed")
	_construire_liste_demos()

	btn_play.grab_focus()


func _on_options_pressed() -> void:
	var panel := OPTIONS_SCENE.instantiate()
	# à la RACINE, pas en enfant du MENU : le nœud MENU a des offsets de
	# mise en page (-690 px…) que le panneau héritait → il s'ouvrait hors
	# écran. À la racine, ses ancres plein-écran couvrent la vraie fenêtre.
	get_tree().root.add_child(panel)
	# MODAL : boutons du menu cachés tant que les options sont ouvertes,
	# sinon la navigation manette "fuite" vers eux derrière le panneau
	$CenterContainer.visible = false
	panel.tree_exited.connect(func() -> void:
		if not is_inside_tree():
			return
		$CenterContainer.visible = true
		if is_instance_valid(btn_options):
			btn_options.grab_focus())
# -----------------------------------------------------------------
# -----------------------------------------------------------------
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("valid_menu"):
		var btn = get_viewport().gui_get_focus_owner()
		if btn and btn is Button: btn.emit_signal("pressed")
	# Rond / Échap : la liste des démos se referme, retour aux boutons principaux
	if Input.is_action_just_pressed("ui_cancel") and _boite_demos.is_visible_in_tree():
		_fermer_demos()
# -----------------------------------------------------------------
var _current := 0
func _move_focus(step: int) -> void:
	_current = (_current + step) % _buttons.size()
	_buttons[_current].grab_focus()

# -----------------------------------------------------------------
# PLAY → choix de la démo
# -----------------------------------------------------------------
func _on_play_pressed() -> void:
	_ouvrir_demos()


## construit la liste des démos (cachée) à la place des boutons principaux
func _construire_liste_demos() -> void:
	_boite_demos = BoxContainer.new()
	_boite_demos.name = "DEMOS"
	_boite_demos.vertical = true
	_boite_demos.visible = false
	$CenterContainer.add_child(_boite_demos)
	for i in DEMOS.size():
		var b := _nouveau_bouton(String(DEMOS[i]["nom"]))
		if not ResourceLoader.exists(String(DEMOS[i]["scene"])):
			# démo pas encore faite : grisée, et la manette saute par-dessus
			b.disabled = true
			b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_demo_pressed.bind(i))
		_boutons_demos.append(b)
	_btn_retour = _nouveau_bouton("BACK")
	_btn_retour.pressed.connect(_fermer_demos)


## un bouton au look du bouton PLAY (copie sans ses signaux), ajouté à la liste
func _nouveau_bouton(texte: String) -> Button:
	var b: Button = btn_play.duplicate(0)
	b.name = texte.replace(" ", "_")
	b.text = texte
	_boite_demos.add_child(b)
	return b


func _ouvrir_demos() -> void:
	if _boite_demos.visible:
		return
	_boite_principale.visible = false
	_boite_demos.visible = true
	_frame_ouverture = Engine.get_process_frames()
	for b in _boutons_demos:
		if not b.disabled:
			b.grab_focus()
			return
	_btn_retour.grab_focus()


func _fermer_demos() -> void:
	if not _boite_demos.visible or Engine.get_process_frames() == _frame_ouverture:
		return
	_boite_demos.visible = false
	_boite_principale.visible = true
	btn_play.grab_focus()


func _on_demo_pressed(i: int) -> void:
	# une validation arrivée dans la frame même où la liste s'est ouverte, c'est
	# encore l'appui sur PLAY (le focus vient de passer sur DEMO 1), pas un choix
	if Engine.get_process_frames() == _frame_ouverture:
		return
	print("[MENU] ", DEMOS[i]["nom"], " → ", DEMOS[i]["scene"])
	# nouvelle partie = page blanche (cœurs ramassés, sang, checkpoints…)
	Player.reset_partie()
	Loader.load_scene_with_loading(String(DEMOS[i]["scene"]))

#const LOADING_SCENE := preload("uid://dm012xrdmag4v")
func _on_load_pressed() -> void:
	print("[MENU] _on_load_pressed")

func _on_quit_pressed() -> void:
	print("[MENU] _on_quit_pressed → on ferme le jeu")
	get_tree().quit()
