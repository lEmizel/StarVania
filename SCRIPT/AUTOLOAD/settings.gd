extends Node
## Réglages persistants (user://settings.cfg) : applique fenêtre + volumes
## au DÉMARRAGE du jeu, et sert de source unique d'application pour le
## panneau Options (SCRIPT/MENU/options.gd).
##
## Jeu 2D + stretch "viewport" : en plein écran / borderless le stretch du
## projet gère l'image, la "résolution" ne pilote que la taille de la
## fenêtre en mode FENÊTRÉ. (Pas de scaling 3D ici — il n'affecterait rien.)

const SETTINGS_PATH := "user://settings.cfg"

enum WindowMode { WINDOWED, BORDERLESS, FULLSCREEN }

# [nom de bus AudioServer, clé dans le cfg]
const AUDIO_BUSES := [["Master", "master"], ["Music", "music"], ["SFX", "sfx"]]


func _ready() -> void:
	apply_saved()


## Applique tout ce que le fichier de settings contient (appelé au boot)
func apply_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return  # premier lancement : on garde les réglages du projet
	apply_window_mode(cfg.get_value("display", "window_mode", WindowMode.FULLSCREEN) as int)
	for bus in AUDIO_BUSES:
		apply_bus_volume(bus[0], cfg.get_value("audio", bus[1], 1.0) as float)


func apply_window_mode(idx: int) -> void:
	var win := get_window()
	match idx:
		WindowMode.WINDOWED:
			# fenêtré = fenêtre MAXIMISÉE (barre de titre + barre des tâches
			# visibles), redimensionnable à la souris — le stretch "viewport"
			# du projet rend le jeu correct à n'importe quelle taille
			win.borderless = false
			win.mode = Window.MODE_MAXIMIZED
		WindowMode.BORDERLESS:
			# borderless plein écran sur L'ÉCRAN COURANT — position réelle de
			# l'écran, pas (0,0) qui téléporterait sur le moniteur principal
			var screen := win.current_screen
			win.mode = Window.MODE_WINDOWED
			win.borderless = true
			win.size = DisplayServer.screen_get_size(screen)
			win.position = DisplayServer.screen_get_position(screen)
		WindowMode.FULLSCREEN:
			win.mode = Window.MODE_FULLSCREEN
			win.borderless = false


func apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return  # bus pas encore créé (l'audio arrivera avec les sound designers)
	var db: float = linear_to_db(linear) if linear > 0.001 else -80.0
	AudioServer.set_bus_volume_db(idx, db)
