extends Label

signal souls_request(amount: int)

@export var count_duration: float = 0.6    # <-- même durée quelle que soit la distance
@export var clamp_min_zero: bool = true

@export var popup_duration: float = 2.0
@export var popup_fade_duration: float = 0.0

@onready var add_number: Label = $postive_number

var _display_value: float = 0.0
var display_value: float:
	set(value):
		_display_value = value
		text = str(int(round(_display_value)))
	get:
		return _display_value

var target_value: int = 0
var _tw: Tween
var _popup_total: int = 0
var _popup_tw: Tween

func _ready() -> void:
	add_to_group("UI_Blood")
	display_value = 0.0
	target_value  = 0
	connect("souls_request", Callable(self, "_on_souls_request"))

	if add_number:
		add_number.text = ""
		add_number.visible = false
		add_number.self_modulate.a = 1.0

	request_set(Player.blood)

func _on_souls_request(amount: int) -> void:
	request_delta(amount)

func request_delta(delta: int) -> void:
	var t := target_value + delta
	if clamp_min_zero:
		t = max(0, t)
	_animate_to(t)
	if delta > 0:
		_show_popup(delta)

func request_set(value: int) -> void:
	var t = clamp(value, 0, 2_147_483_647)
	if clamp_min_zero:
		t = max(0, t)
	_animate_to(t)

func _animate_to(t: int) -> void:
	target_value = t
	if is_instance_valid(_tw):
		_tw.kill()
	if int(round(display_value)) == target_value:
		display_value = float(target_value)
		return
	var dur = max(count_duration, 0.01)  # durée constante
	_tw = create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_property(self, "display_value", float(target_value), dur)

func _show_popup(delta: int) -> void:
	if add_number == null:
		return
	_popup_total += delta
	add_number.text = "+" + str(_popup_total)
	add_number.visible = true
	add_number.self_modulate.a = 1.0
	if is_instance_valid(_popup_tw):
		_popup_tw.kill()
	_popup_tw = create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	_popup_tw.tween_interval(popup_duration)
	if popup_fade_duration > 0.0:
		_popup_tw.tween_property(add_number, "self_modulate:a", 0.0, popup_fade_duration)
	_popup_tw.tween_callback(Callable(self, "_clear_popup"))

func _clear_popup() -> void:
	_popup_total = 0
	if add_number:
		add_number.text = ""
		add_number.visible = false
		add_number.self_modulate.a = 1.0

# ----------------- Debug via touches -----------------
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("up_menu"):
		emit_signal("souls_request", 10000)   # +100 (déclenche aussi le popup)
	elif event.is_action_pressed("down_menu"):
		emit_signal("souls_request", -100)  # -100 (popup ignoré)
