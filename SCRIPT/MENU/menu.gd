extends Control

@onready var btn_play : Button = $"CenterContainer/BoxContainer/PLAY"
@onready var btn_load : Button = $"CenterContainer/BoxContainer/LOAD"
@onready var btn_quit : Button = $"CenterContainer/BoxContainer/QUIT"

# ordre logique pour le focus
@onready var _buttons : Array[Button] = [btn_play, btn_load, btn_quit]
const TARGET_SCENE := "uid://q73v1b80lt2r"

func _ready() -> void:
	# signaux
	SignalUtils.connect_signal(btn_play, "pressed", self, "_on_play_pressed")
	SignalUtils.connect_signal(btn_load, "pressed", self, "_on_load_pressed")
	SignalUtils.connect_signal(btn_quit, "pressed", self, "_on_quit_pressed")

	btn_play.grab_focus()
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
	Loader.load_scene_with_loading(TARGET_SCENE)
#const LOADING_SCENE := preload("uid://dm012xrdmag4v")
func _on_load_pressed() -> void:
	print("[MENU] _on_load_pressed")

func _on_quit_pressed() -> void:
	print("[MENU] _on_quit_pressed → on ferme le jeu")
	get_tree().quit()
