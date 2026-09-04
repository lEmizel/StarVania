extends Control
## Panneau Options : résolution (fenêtré), mode d'écran, volumes audio.
## L'application des réglages passe par l'autoload Settings — la même
## logique qui les ré-applique au démarrage du jeu.

const WINDOW_MODE_LABELS := [
	"Fenêtré",
	"Fenêtré sans bordure",
	"Plein écran",
]

@onready var fleche_gauche: Button = $Panel/VBoxContainer/WindowModeRow/FlecheGauche
@onready var mode_valeur: Button = $Panel/VBoxContainer/WindowModeRow/ModeValeur
@onready var fleche_droite: Button = $Panel/VBoxContainer/WindowModeRow/FlecheDroite
var _mode_idx: int = Settings.WindowMode.FULLSCREEN
@onready var master_slider: HSlider = $Panel/VBoxContainer/MasterVolumeRow/MasterVolumeSlider
@onready var master_value_label: Label = $Panel/VBoxContainer/MasterVolumeRow/MasterVolumeValue
@onready var music_slider: HSlider = $Panel/VBoxContainer/MusicVolumeRow/MusicVolumeSlider
@onready var music_value_label: Label = $Panel/VBoxContainer/MusicVolumeRow/MusicVolumeValue
@onready var sfx_slider: HSlider = $Panel/VBoxContainer/SFXVolumeRow/SFXVolumeSlider
@onready var sfx_value_label: Label = $Panel/VBoxContainer/SFXVolumeRow/SFXVolumeValue
@onready var apply_button: Button = $Panel/VBoxContainer/ButtonsRow/ApplyButton
@onready var close_button: Button = $Panel/VBoxContainer/ButtonsRow/CloseButton


func _ready() -> void:
	# sélecteur carrousel ❮ valeur ❯ : flèches à la souris, gauche/droite
	# à la manette, et A sur la valeur = cycler vers l'avant
	fleche_gauche.pressed.connect(func() -> void: _cycle_mode(-1))
	fleche_droite.pressed.connect(func() -> void: _cycle_mode(1))
	mode_valeur.pressed.connect(func() -> void: _cycle_mode(1))

	_load_into_widgets()

	apply_button.pressed.connect(_on_apply_pressed)
	close_button.pressed.connect(_on_close_pressed)
	# volumes : application LIVE + sauvegarde à chaque changement (fonctionne
	# aussi à la manette, où drag_ended n'est jamais émis)
	master_slider.value_changed.connect(_on_volume_changed.bind("Master", "master", 0))
	music_slider.value_changed.connect(_on_volume_changed.bind("Music", "music", 1))
	sfx_slider.value_changed.connect(_on_volume_changed.bind("SFX", "sfx", 2))

	_cabler_focus_manette()
	mode_valeur.grab_focus()


func _cycle_mode(d: int) -> void:
	_mode_idx = wrapi(_mode_idx + d, 0, WINDOW_MODE_LABELS.size())
	mode_valeur.text = WINDOW_MODE_LABELS[_mode_idx]


## Chaîne de focus explicite : la résolution géométrique de Godot se perd
## entre sliders et boutons (impossible d'atteindre Appliquer au pad)
func _cabler_focus_manette() -> void:
	var chaine: Array[Control] = [mode_valeur, master_slider,
		music_slider, sfx_slider, apply_button]
	for i in chaine.size() - 1:
		chaine[i].focus_neighbor_bottom = chaine[i].get_path_to(chaine[i + 1])
		chaine[i + 1].focus_neighbor_top = chaine[i + 1].get_path_to(chaine[i])
	# gauche/droite sur la valeur du mode NE quittent pas le contrôle
	# (c'est le cycle qui les consomme, voir _process)
	mode_valeur.focus_neighbor_left = mode_valeur.get_path_to(mode_valeur)
	mode_valeur.focus_neighbor_right = mode_valeur.get_path_to(mode_valeur)
	apply_button.focus_neighbor_right = apply_button.get_path_to(close_button)
	close_button.focus_neighbor_left = close_button.get_path_to(apply_button)
	close_button.focus_neighbor_top = close_button.get_path_to(sfx_slider)
	# bouclage haut/bas
	apply_button.focus_neighbor_bottom = apply_button.get_path_to(mode_valeur)
	close_button.focus_neighbor_bottom = close_button.get_path_to(mode_valeur)
	mode_valeur.focus_neighbor_top = mode_valeur.get_path_to(apply_button)


## Cycle du mode d'affichage à la manette : gauche/droite sur la valeur
func _process(_delta: float) -> void:
	if not mode_valeur.has_focus():
		return
	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("right_menu"):
		_cycle_mode(1)
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("left_menu"):
		_cycle_mode(-1)


func _on_apply_pressed() -> void:
	Settings.apply_window_mode(_mode_idx)
	var cfg := ConfigFile.new()
	cfg.load(Settings.SETTINGS_PATH)  # préserve les autres sections
	cfg.set_value("display", "window_mode", _mode_idx)
	cfg.save(Settings.SETTINGS_PATH)


func _on_close_pressed() -> void:
	queue_free()


func _on_volume_changed(value: float, bus_name: String, cfg_key: String, label_idx: int) -> void:
	Settings.apply_bus_volume(bus_name, value)
	var labels := [master_value_label, music_value_label, sfx_value_label]
	labels[label_idx].text = "%d%%" % roundi(value * 100.0)
	var cfg := ConfigFile.new()
	cfg.load(Settings.SETTINGS_PATH)
	cfg.set_value("audio", cfg_key, value)
	cfg.save(Settings.SETTINGS_PATH)


func _load_into_widgets() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(Settings.SETTINGS_PATH)
	var mode_idx: int = Settings.WindowMode.FULLSCREEN  # défaut sain pour une démo
	var volumes := [1.0, 1.0, 1.0]
	if err == OK:
		mode_idx = cfg.get_value("display", "window_mode", Settings.WindowMode.FULLSCREEN) as int
		for i in Settings.AUDIO_BUSES.size():
			volumes[i] = cfg.get_value("audio", Settings.AUDIO_BUSES[i][1], 1.0) as float
	_mode_idx = clampi(mode_idx, 0, WINDOW_MODE_LABELS.size() - 1)
	mode_valeur.text = WINDOW_MODE_LABELS[_mode_idx]
	# set_value_no_signal : ne pas re-sauvegarder ce qu'on vient de charger
	var sliders := [master_slider, music_slider, sfx_slider]
	var labels := [master_value_label, music_value_label, sfx_value_label]
	for i in 3:
		sliders[i].set_value_no_signal(volumes[i])
		labels[i].text = "%d%%" % roundi(volumes[i] * 100.0)
