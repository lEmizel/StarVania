extends Node2D
class_name HealthBar

signal health_request(amount: float)

@onready var barre_de_vie:       TextureProgressBar = $barre_de_vie
@onready var under_barre_de_vie: TextureProgressBar = $Under_barre_de_vie

var max_health = 10
var health     = max_health
var _hide_timer: Timer
# Un tween par propriété animée. Sans ces références on ne peut pas tuer le
# précédent : `bar.create_tween().kill()` fabriquait un tween NEUF et tuait
# celui-là, laissant l'ancien tourner. Deux fondus concurrents sur le même
# `modulate:a` et l'alpha finissait où le dernier tick le laissait.
var _tweens_alpha := {}
var _tween_valeur: Tween


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
	if _tween_valeur != null and _tween_valeur.is_valid():
		_tween_valeur.kill()
	_tween_valeur = under_barre_de_vie.create_tween()
	_tween_valeur.tween_property(under_barre_de_vie, "value", health, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 3) FADE IN des deux barres sur 0.5s
	for bar in [barre_de_vie, under_barre_de_vie]:
		_fondu(bar, 1.0, 0.5)

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
		_fondu(bar, 0.0, 1.0, Tween.TRANS_QUAD, Tween.EASE_IN)


## Fondu d'alpha sur UNE barre, en tuant proprement le fondu précédent de
## cette barre-là (et seulement celui-là).
func _fondu(bar: CanvasItem, cible: float, duree: float,
		trans := Tween.TRANS_LINEAR, aisance := Tween.EASE_IN_OUT) -> void:
	var ancien: Tween = _tweens_alpha.get(bar)
	if ancien != null and ancien.is_valid():
		ancien.kill()
	var t := bar.create_tween()
	t.tween_property(bar, "modulate:a", cible, duree).set_trans(trans).set_ease(aisance)
	_tweens_alpha[bar] = t


# NOTE : il y avait ici un `_input` de debug (down_menu → −25, up_menu → +15).
# Comme CHAQUE monstre porte cette barre, chaque appui vidait ou remplissait
# l'intérieur de TOUTES les barres de la scène à la fois, sans toucher aux vrais
# points de vie — et `down_menu` est la CROIX DU BAS de la manette. Retiré le
# 19 sept. 2026, comme ses jumeaux l'avaient été dans gestion_interface.gd.


func apparition_temp(fade_time := 0.1, hold_time := 3.0) -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, fade_time)  # fade-in
	t.tween_interval(hold_time)                           # attente
	t.tween_property(self, "modulate:a", 0.0, fade_time)  # fade-out
