extends Control

@onready var btn_play : Button = $"CenterContainer/BoxContainer/PLAY"
@onready var btn_load : Button = $"CenterContainer/BoxContainer/LOAD"
@onready var btn_options : Button = $"CenterContainer/BoxContainer/OPTIONS"
@onready var btn_quit : Button = $"CenterContainer/BoxContainer/QUIT"

# ordre logique pour le focus
@onready var _buttons : Array[Button] = [btn_play, btn_load, btn_options, btn_quit]
const TARGET_SCENE := "uid://gq88m0garham"
const OPTIONS_SCENE := preload("res://SCRIPT/MENU/options.tscn")

func _ready() -> void:
	# signaux
	SignalUtils.connect_signal(btn_play, "pressed", self, "_on_play_pressed")
	SignalUtils.connect_signal(btn_load, "pressed", self, "_on_load_pressed")
	SignalUtils.connect_signal(btn_options, "pressed", self, "_on_options_pressed")
	SignalUtils.connect_signal(btn_quit, "pressed", self, "_on_quit_pressed")

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
# -----------------------------------------------------------------
var _current := 0
func _move_focus(step: int) -> void:
	_current = (_current + step) % _buttons.size()
	_buttons[_current].grab_focus()

# -----------------------------------------------------------------
func _on_play_pressed() -> void:
	# nouvelle partie = page blanche (cœurs ramassés, sang, checkpoints…)
	Player.reset_partie()
	Loader.load_scene_with_loading(TARGET_SCENE)
#const LOADING_SCENE := preload("uid://dm012xrdmag4v")
func _on_load_pressed() -> void:
	print("[MENU] _on_load_pressed")

func _on_quit_pressed() -> void:
	print("[MENU] _on_quit_pressed → on ferme le jeu")
	get_tree().quit()
