extends Control
## Menu pause in-game (ouvert par l'autoload PauseMenu sur "start").
## Le jeu est figé (get_tree().paused) tant qu'il est affiché — la scène
## est en PROCESS_MODE_ALWAYS pour rester interactive.

const OPTIONS_SCENE := preload("res://SCRIPT/MENU/options.tscn")
const MENU_PRINCIPAL_SCENE := "uid://dm012xrdmag4v"  # SCRIPT/MENU/menu.tscn

@onready var btn_reprendre: Button = $Panel/VBoxContainer/Reprendre
@onready var btn_options: Button = $Panel/VBoxContainer/Options
@onready var btn_menu: Button = $Panel/VBoxContainer/MenuPrincipal
@onready var btn_quitter: Button = $Panel/VBoxContainer/Quitter


func _ready() -> void:
	btn_reprendre.pressed.connect(fermer)
	btn_options.pressed.connect(_on_options_pressed)
	btn_menu.pressed.connect(_on_menu_principal_pressed)
	btn_quitter.pressed.connect(func() -> void: get_tree().quit())
	btn_reprendre.grab_focus()


# même mécanique manette que le menu principal : valid_menu déclenche le
# bouton qui a le focus
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("valid_menu"):
		var btn := get_viewport().gui_get_focus_owner()
		if btn and btn is Button:
			btn.emit_signal("pressed")


func fermer() -> void:
	get_tree().paused = false
	queue_free()


func _on_options_pressed() -> void:
	var panel := OPTIONS_SCENE.instantiate()
	add_child(panel)  # enfant du menu pause : hérite du PROCESS_MODE_ALWAYS
	# MODAL : on cache le panneau de pause tant que les options sont
	# ouvertes — un contrôle caché est infocusable, la navigation manette
	# ne peut plus "fuiter" vers les boutons de derrière
	$Panel.visible = false
	panel.tree_exited.connect(func() -> void:
		if not is_inside_tree():
			return
		$Panel.visible = true
		if is_instance_valid(btn_options):
			btn_options.grab_focus())


func _on_menu_principal_pressed() -> void:
	get_tree().paused = false
	Loader.load_scene_with_loading(MENU_PRINCIPAL_SCENE)
	queue_free()
