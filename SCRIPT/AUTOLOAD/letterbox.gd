# res://letterbox.gd
extends Node           # autoload global, pas besoin d’être dans la scène

# --- bornes de rapport ---------------------------------------
const AR_4_3        : float = 4.0 / 3.0          # 1.333…
const AR_16_9       : float = 21.0 / 9.0         # 1.778…
const VIRTUAL_WIDTH : int   = 1920               # largeur fixe logiquement

var  use_normal_range := true                    # toggle « ui_accept »

@onready var window  : Window   = get_window()   # fenêtre physique
var       _last_phys : Vector2i = Vector2i.ZERO  # mémo taille physique
var       _last_virt : Vector2i = Vector2i.ZERO  # mémo taille virtuelle

# -------------------------------------------------------------
func _ready() -> void:
	_last_phys = DisplayServer.window_get_size()
	_apply_letterbox()

func _process(_delta: float) -> void:
	var phys := DisplayServer.window_get_size()
	if phys != _last_phys:                       # la fenêtre a bougé
		_last_phys = phys
		_apply_letterbox()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):     # ↔ inverse la plage 4:3/16:9
		use_normal_range = !use_normal_range
		_apply_letterbox()

# -------------------------------------------------------------
func _apply_letterbox() -> void:
	# 1) rapport physique actuel
	var phys      : Vector2i = _last_phys
	var ar_phys   : float = phys.x / float(phys.y)

	# 2) bornes dynamiques
	var low  : float = AR_4_3  if use_normal_range else AR_16_9
	var high : float = AR_16_9 if use_normal_range else AR_4_3

	# 3) clamp + résolution virtuelle
	var ar_clamped : float = clampf(ar_phys, low, high)
	var virt_h     : int   = int(round(VIRTUAL_WIDTH / ar_clamped))
	var virt_sz    : Vector2i = Vector2i(VIRTUAL_WIDTH, virt_h)

	# 4) stop si rien ne change
	if virt_sz == _last_virt:
		return
	_last_virt = virt_sz

	# 5) applique le letter-box : le moteur ajoute les bandes noires
	window.content_scale_mode   = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size   = virt_sz

	# --- debug facultatif ------------------------------------
	print("Fenêtre:", phys,
		"→ virtuelle:", virt_sz,
		"ratio phys %.3f, clamp %.3f" % [ar_phys, ar_clamped])
