extends Node2D
class_name HealthBar

signal health_request(amount: float)

@onready var barre_de_vie:       TextureProgressBar = $barre_de_vie
@onready var under_barre_de_vie: TextureProgressBar = $Under_barre_de_vie

var max_health = 10
var health     = max_health
var _hide_timer: Timer

func _ready() -> void:
	modulate.a = 0.0   # rend le Node2D (self) entièrement invisible


	SignalUtils.connect_signal(self, "health_request", self, "_on_health_request")

func init_vie() -> void:
	health     = max_health
	# barre avant
	barre_de_vie.min_value  = 0
	barre_de_vie.max_value  = max_health
	barre_de_vie.value      = health

	# barre arrière
	under_barre_de_vie.min_value  = 0
	under_barre_de_vie.max_value  = max_health
	under_barre_de_vie.value      = health


func _on_health_request(amount: float) -> void:
	# 1) Update health et bar_front
	var old_health = health
	health = clamp(health + amount, 0, max_health)
	barre_de_vie.value = health

	# 2) Tween barre arrière
	under_barre_de_vie.value = old_health
	under_barre_de_vie.create_tween() \
		.tween_property(under_barre_de_vie, "value", health, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 3) FADE IN des deux barres sur 0.5s
	for bar in [barre_de_vie, under_barre_de_vie]:
		# Annule tout tween alpha en cours pour ne pas confondre
		bar.create_tween().kill()
		bar.create_tween() \
			.tween_property(bar, "modulate:a", 1.0, 0.5)

	# 4) (Re)lance le timer de 4s pour le fade out
	if not is_instance_valid(_hide_timer):
		_hide_timer = Timer.new()
		_hide_timer.wait_time = 4.0
		_hide_timer.one_shot  = true
		_hide_timer.connect("timeout", Callable(self, "_on_hide_timer_timeout"))
		add_child(_hide_timer)
	else:
		_hide_timer.stop()
	_hide_timer.start()


func _on_hide_timer_timeout() -> void:
	# FADE OUT des deux barres sur 1s
	for bar in [barre_de_vie, under_barre_de_vie]:
		# kill ancien tween alpha pour être sûr
		bar.create_tween().kill()
		bar.create_tween() \
			.tween_property(bar, "modulate:a", 0.0, 1.0) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("down_menu"):
		emit_signal("health_request", -25)
	elif event.is_action_pressed("up_menu"):
		emit_signal("health_request", 15)

func apparition_temp(fade_time := 0.1, hold_time := 3.0) -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, fade_time)  # fade-in
	t.tween_interval(hold_time)                           # attente
	t.tween_property(self, "modulate:a", 0.0, fade_time)  # fade-out
