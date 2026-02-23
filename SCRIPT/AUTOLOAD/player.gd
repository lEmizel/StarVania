extends Node

var blood := 0
var hp := 570
var MAX_HP := 570
var en := 95
var MAX_en := 195

# Soigne un pourcentage des PV max (par défaut 40%) et émet le signal via changement_de_vie
func heal_blood(pct: float = 0.40) -> void:
	var amount := int(round(MAX_HP * pct))
	if amount <= 0:
		return
	changement_de_vie(amount)

func changement_de_vie(amount: int) -> void:
	var old := hp
	hp = clamp(hp + amount, 0, MAX_HP)
	var delta := hp - old
	var bars := get_tree().get_nodes_in_group("UI_Health")
	if !bars.is_empty():
		bars[0].emit_signal("health_request", float(delta))

func changement_d_endurance(amount: int) -> void:
	var old := en
	en = clamp(en + amount, 0, MAX_en)
	var delta := en - old
	var bars := get_tree().get_nodes_in_group("UI_Endu")
	if !bars.is_empty():
		bars[0].emit_signal("endurance_request", float(delta))

func changement_de_blood(amount: int) -> void:
	if amount == 0:
		return
	var old := blood
	blood = max(0, old + amount)   # clamp à 0 (pas de max)
	var delta := blood - old
	if delta == 0:
		return
	for n in get_tree().get_nodes_in_group("UI_Blood"):
		n.emit_signal("souls_request", delta)

# ---------- MAX HP / EN ----------


# --- SOIN via la barre orange (rally) ---
func demande_rally_heal(amount: int) -> void:
	if amount <= 0:
		return
	var ui := get_tree().get_nodes_in_group("UI_Health")
	if not ui.is_empty():
		ui[0].emit_signal("rally_heal_request", float(amount))
		

# --- MAX HP ---
func set_max_hp(new_max: int) -> void:
	new_max = max(1, new_max)
	if new_max == MAX_HP:
		return
	var old_hp := hp
	MAX_HP = new_max
	# Ne PAS rééchelonner : on garde la valeur et on clamp si besoin
	hp = min(old_hp, MAX_HP)

	var ui := get_tree().get_nodes_in_group("UI_Health")
	if not ui.is_empty():
		ui[0].emit_signal("bar_max_request", "hp", float(MAX_HP))  # pas de health_request

func add_max_hp(delta: int) -> void:
	set_max_hp(MAX_HP + delta)  # <-- aucune mise à l’échelle

# --- MAX EN ---
func set_max_en(new_max: int) -> void:
	new_max = max(1, new_max)
	if new_max == MAX_en:
		return
	var old_en := en
	MAX_en = new_max
	en = min(old_en, MAX_en)

	var ui := get_tree().get_nodes_in_group("UI_Endu")
	if not ui.is_empty():
		ui[0].emit_signal("bar_max_request", "en", float(MAX_en))

func add_max_en(delta: int) -> void:
	set_max_en(MAX_en + delta)


#Player.set_max_hp(120)         # agrandit la barre HP + ajuste hp au même %
#Player.add_max_en(50)          # +50 max endu, conserve le pourcentage courant
