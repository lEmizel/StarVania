extends CanvasLayer
## --------------------------------------------------
## Signal déjà utilisé par l’autoload Player (pour la vie)
## --------------------------------------------------
signal health_request(amount: float)
signal endurance_request(amount: float)
signal bar_max_request(kind: String, new_max: float)
signal rally_heal_request(amount: float)

# Mapping largeur ↔ points (pour la VIE)
@export var HP_BASE_POINTS: float   = 100.0   # points de vie de référence
@export var HP_BASE_WIDTH:  float   = 1300.0  # largeur à 100 PV (ta valeur)
@export var HP_PX_PER_POINT: float  = 4.5     # +5 px par point de vie
@export var HP_BACK_START_DELAY: float = 2.5  # délai avant que la barre orange HP commence à descendre
# (Optionnel, si tu veux des coefficients différents pour l’endurance)
@export var EN_BASE_POINTS: float   = 100.0
@export var EN_BASE_WIDTH:  float   = 1300.0
@export var EN_PX_PER_POINT: float  = 4.5

@onready var front_bar : TextureProgressBar       = $barre_de_vie
@onready var back_bar  : TextureProgressBar       = $Under_barre_de_vie
@onready var front_bar_endu: TextureProgressBar   = $barre_de_sang
@onready var back_bar_endu : TextureProgressBar   = $Under_sang

# --- Système de cœurs ---
@onready var _vie_container: Node = $VIE
@onready var _heart_template_full: TextureRect = $VIE/coeur_1
@onready var _heart_template_broken: TextureRect = $VIE/coeur_1_broken
@onready var _heart_template_empty: TextureRect = $VIE/coeur_1_noir
## Décalage horizontal entre deux cœurs
@export var HEART_SPACING: float = 45.0
## Temps d'affichage du cœur brisé avant son fondu
@export var BROKEN_LINGER_TIME: float = 0.33
## Durée du fondu de disparition du cœur brisé
@export var BROKEN_FADE_DURATION: float = 0.5
# chaque entrée : { "full", "broken", "empty" : TextureRect, "tw" : Tween }
var _hearts: Array = []

## ---------------- Réglages (éditables) ----------------
@export var BACK_TWEEN_DURATION: float = 1.0    # durée du tween (vie & endu)


## ---------------- State interne ----------------
var _max_hp: float
var _max_en: float
var _cur_en: float


func _ready() -> void:
	# Groupes utilisés par Player (pour la vie)
	add_to_group("UI_Health")
	add_to_group("UI_Endu")

	# --- VIE : on garde ton autoload Player tel quel ---
	_max_hp = Player.MAX_HP
	var cur_hp = Player.hp
	for bar in [front_bar, back_bar]:
		bar.min_value = 0
		bar.max_value = _max_hp
		bar.value     = cur_hp


	_max_en = Player.MAX_en
	_cur_en = float(Player.en)
	for bar in [front_bar_endu, back_bar_endu]:
		bar.min_value = 0
		bar.max_value = _max_en
		bar.value     = _cur_en

	# Connexions
	_build_hearts()

	connect("health_request", Callable(self, "_on_health_request"))
	connect("endurance_request", Callable(self, "_on_endurance_request"))
	connect("bar_max_request", Callable(self, "_on_bar_max_request"))
	connect("rally_heal_request", Callable(self, "_on_rally_heal_request"))
	_apply_bar_max_generic("hp", _max_hp, false)
	_apply_bar_max_generic("en", _max_en, false)  # si tu veux aussi pour l’endurance

## Construit la rangée de cœurs en dupliquant le trio template (noir / brisé /
## rouge) selon Player.max_hearts, avec un décalage horizontal par cœur.
## Ré-appelable si le nombre de cœurs max change en cours de partie.
func _build_hearts() -> void:
	# purge les duplicats d'une construction précédente (on garde les templates)
	for h in _hearts:
		if h["full"] != _heart_template_full:
			h["full"].queue_free()
			h["broken"].queue_free()
			h["empty"].queue_free()
	_hearts.clear()

	_hearts.append({
		"full": _heart_template_full,
		"broken": _heart_template_broken,
		"empty": _heart_template_empty,
	})
	for i in range(1, Player.max_hearts):
		var empty: TextureRect = _heart_template_empty.duplicate()
		var broken: TextureRect = _heart_template_broken.duplicate()
		var full: TextureRect = _heart_template_full.duplicate()
		for node in [empty, broken, full]:
			node.position.x += HEART_SPACING * float(i)
		# même ordre que les templates : noir, puis brisé, puis rouge par-dessus
		_vie_container.add_child(empty)
		_vie_container.add_child(broken)
		_vie_container.add_child(full)
		_hearts.append({"full": full, "broken": broken, "empty": empty})

	# état initial : rouges selon les PV, brisés cachés
	for i in _hearts.size():
		_hearts[i]["full"].visible = i < int(Player.hp)
		_hearts[i]["broken"].visible = false


## Met à jour l'affichage des cœurs après un changement de PV.
## Dégât : le rouge disparaît instantanément, le brisé apparaît instantanément,
## puis (après BROKEN_LINGER_TIME) le brisé se fond en douceur.
func _refresh_hearts(old_hp: int, new_hp: int) -> void:
	for i in _hearts.size():
		_hearts[i]["full"].visible = i < new_hp

	if new_hp < old_hp:
		for i in range(maxi(new_hp, 0), mini(old_hp, _hearts.size())):
			_show_broken(i)
	elif new_hp > old_hp:
		# soin : les brisés des cœurs récupérés disparaissent immédiatement
		for i in range(maxi(old_hp, 0), mini(new_hp, _hearts.size())):
			_hide_broken_now(i)


func _show_broken(i: int) -> void:
	var h: Dictionary = _hearts[i]
	var broken: TextureRect = h["broken"]
	if h.has("tw") and h["tw"] != null and h["tw"].is_valid():
		h["tw"].kill()
	broken.modulate.a = 1.0
	broken.visible = true
	var tw := create_tween()
	tw.tween_interval(BROKEN_LINGER_TIME)
	tw.tween_property(broken, "modulate:a", 0.0, BROKEN_FADE_DURATION)
	tw.tween_callback(func () -> void: broken.visible = false)
	h["tw"] = tw


func _hide_broken_now(i: int) -> void:
	var h: Dictionary = _hearts[i]
	if h.has("tw") and h["tw"] != null and h["tw"].is_valid():
		h["tw"].kill()
	h["broken"].visible = false


func _bar_width_from_points(points: float, base_points: float, base_width: float, px_per_point: float) -> float:
	return base_width + (points - base_points) * px_per_point

func _set_bar_pair_width(front: Control, back: Control, w: float, tween_time: float = 0.0) -> void:
	for bar in [front, back]:
		if tween_time > 0.0:
			var t = create_tween()
			# Si le parent est un Container, anime custom_minimum_size ; sinon size
			if bar.get_parent() is Container:
				t.tween_property(bar, "custom_minimum_size", Vector2(w, bar.custom_minimum_size.y), tween_time)
			else:
				t.tween_property(bar, "size", Vector2(w, bar.size.y), tween_time)
		else:
			if bar.get_parent() is Container:
				bar.custom_minimum_size.x = w
			else:
				bar.size.x = w

func _apply_bar_max_generic(kind: String, new_max: float, tween: bool = true) -> void:
	var front: TextureProgressBar = null
	var back:  TextureProgressBar = null
	var pphp: float
	var cur_value: float

	match kind:
		"hp":
			front = front_bar
			back  = back_bar
			_max_hp = new_max
			pphp = HP_PX_PER_POINT
			cur_value = float(Player.hp)
		"en":
			front = front_bar_endu
			back  = back_bar_endu
			_max_en = new_max
			pphp = EN_PX_PER_POINT
			cur_value = float(Player.en)
		_:
			return

	for b in [front, back]:
		b.max_value = new_max

	# --- largeur = caps fixes + (pixels_par_point * MAX) ---
	var cap_sum := float(front.stretch_margin_left + front.stretch_margin_right)
	var w: float = cap_sum + pphp * new_max
	var tw: float = 0.30 if tween else 0.0
	_set_bar_pair_width(front, back, w, tw)

	# Sync des values
	front.value = cur_value
	back.value  = cur_value

func _on_bar_max_request(kind: String, new_max: float) -> void:
	_apply_bar_max_generic(kind, new_max, true)
## --------------------------------------------------
## VIE (inchangé : front instant, back en tween)
## --------------------------------------------------

var _hp_back_anchor: float = 0.0
var _hp_back_target: float = 0.0
var _hp_back_tween: Tween = null


func _on_health_request(amount: float) -> void:
	# --- Cœurs : Player.hp est déjà à jour, on en déduit l'ancien total ---
	var new_hp := int(Player.hp)
	var old_hp := int(round(float(new_hp) - amount))
	_refresh_hearts(old_hp, new_hp)

	# --- Ancien système de barres (masqué mais conservé) ---
	var before: float = front_bar.value
	var after:  float = clamp(before + amount, 0, _max_hp)

	front_bar.value = after

	if amount < 0.0:
		var had_running := is_instance_valid(_hp_back_tween) and _hp_back_tween.is_running()

		if is_instance_valid(_hp_back_tween):
			_hp_back_tween.kill()
			_hp_back_tween = null

		_hp_back_anchor = before
		_hp_back_target = after

		# ⬅️ Assure la présence de l’orange : jamais en dessous de l’ancre
		if back_bar.value < _hp_back_anchor:
			back_bar.value = _hp_back_anchor

		_hp_back_tween = back_bar.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		# 1er hit → délai ; hits suivants → direct
		if not had_running:
			_hp_back_tween.tween_interval(HP_BACK_START_DELAY)

		# Si la back est AU-DESSUS de l’ancre, on la descend d’abord jusqu’à l’ancre
		const EPS := 0.001
		if back_bar.value > _hp_back_anchor + EPS:
			_hp_back_tween.tween_property(back_bar, "value", _hp_back_anchor, BACK_TWEEN_DURATION)

		# Puis on fige à l’ancre, et on descend vers la cible
		_hp_back_tween.tween_interval(HP_BACK_START_DELAY)
		_hp_back_tween.tween_property(back_bar, "value", _hp_back_target, BACK_TWEEN_DURATION)
	else:
		# Soin : ne pas perturber la back bar si un tween est en cours
		var tween_active := is_instance_valid(_hp_back_tween) and _hp_back_tween.is_running()
		if not tween_active:
			back_bar.value = after


func _on_rally_heal_request(amount: float) -> void:
	if amount <= 0.0:
		return

	# Max récupérable via la barre orange (back - front)
	var rally_pool: float = max(0.0, back_bar.value - front_bar.value)
	if rally_pool <= 0.0:
		return

	var missing: float = _max_hp - front_bar.value
	if missing <= 0.0:
		return

	var gain: float = min(float(amount), rally_pool, missing)

	# Applique uniquement à la barre avant (HP visibles)
	var new_front = clamp(front_bar.value + gain, 0.0, _max_hp)
	front_bar.value = new_front

	# ⬇️ Sync côté Player (pas de signal → pas de boucle)
	Player.hp = int(new_front)
	# NOTE: on ne modifie PAS back_bar (elle continue sa vie et son tween)
	
## --------------------------------------------------
## ENDURANCE (même logique que la vie, sans regen)
## --------------------------------------------------
## Durée de la montée de jauge lors d'un gain de sang (courte = nerveuse)
@export var EN_GAIN_TWEEN_DURATION: float = 0.3
var _endu_gain_tween: Tween = null

func _on_endurance_request(amount: float) -> void:
	# cible = la vérité du singleton (déjà mis à jour), robuste même si un
	# tween de gain précédent est encore en vol
	var new_val: float = clampf(float(Player.en), 0.0, _max_en)
	var old_val: float = front_bar_endu.value

	if amount >= 0.0:
		# GAIN : montée progressive et rapide, pas de "pop" instantané
		if _endu_gain_tween != null and _endu_gain_tween.is_valid():
			_endu_gain_tween.kill()
		_endu_gain_tween = create_tween() \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)
		_endu_gain_tween.tween_property(front_bar_endu, "value", new_val, EN_GAIN_TWEEN_DURATION)
		_endu_gain_tween.parallel().tween_property(back_bar_endu, "value", new_val, EN_GAIN_TWEEN_DURATION)
	else:
		# DÉPENSE : front instant, back suit en tween (effet fantôme, comme la vie)
		front_bar_endu.value = new_val
		back_bar_endu.value  = old_val
		back_bar_endu.create_tween() \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT) \
			.tween_property(back_bar_endu, "value", new_val, BACK_TWEEN_DURATION)

	_cur_en = new_val


# NOTE : la jauge de sang ne se régénère PAS toute seule (contrairement à
# l'ancienne endurance) — elle se remplit uniquement via les récoltes de sang


## --------------------------------------------------
## FEEDBACK "pas assez de sang" : la jauge tremble et clignote en rouge
## (appelé par le player quand un sort est refusé faute de réserve)
## --------------------------------------------------
var _blood_fb_shake: Tween = null
var _blood_fb_flash: Tween = null
var _endu_front_base_x := 0.0
var _endu_back_base_x := 0.0
var _endu_base_captured := false

func blood_insufficient_feedback() -> void:
	# capture des positions d'origine au premier appel (layout déjà posé)
	if not _endu_base_captured:
		_endu_front_base_x = front_bar_endu.position.x
		_endu_back_base_x = back_bar_endu.position.x
		_endu_base_captured = true

	# feedback déjà en cours : on remet tout en place avant de relancer
	if _blood_fb_shake != null and _blood_fb_shake.is_valid():
		_blood_fb_shake.kill()
	if _blood_fb_flash != null and _blood_fb_flash.is_valid():
		_blood_fb_flash.kill()
	front_bar_endu.position.x = _endu_front_base_x
	back_bar_endu.position.x = _endu_back_base_x
	front_bar_endu.modulate = Color.WHITE
	back_bar_endu.modulate = Color.WHITE

	# tremblement : oscillations décroissantes des deux barres ensemble
	_blood_fb_shake = create_tween()
	var amp := 7.0
	for i in range(3):
		_blood_fb_shake.tween_property(front_bar_endu, "position:x", _endu_front_base_x + amp, 0.04)
		_blood_fb_shake.parallel().tween_property(back_bar_endu, "position:x", _endu_back_base_x + amp, 0.04)
		_blood_fb_shake.tween_property(front_bar_endu, "position:x", _endu_front_base_x - amp, 0.04)
		_blood_fb_shake.parallel().tween_property(back_bar_endu, "position:x", _endu_back_base_x - amp, 0.04)
		amp *= 0.55
	_blood_fb_shake.tween_property(front_bar_endu, "position:x", _endu_front_base_x, 0.04)
	_blood_fb_shake.parallel().tween_property(back_bar_endu, "position:x", _endu_back_base_x, 0.04)

	# clignotement rouge vif, en parallèle du tremblement
	_blood_fb_flash = create_tween()
	for i in range(2):
		_blood_fb_flash.tween_property(front_bar_endu, "modulate", Color(1.0, 0.15, 0.15), 0.07)
		_blood_fb_flash.parallel().tween_property(back_bar_endu, "modulate", Color(1.0, 0.15, 0.15), 0.07)
		_blood_fb_flash.tween_property(front_bar_endu, "modulate", Color.WHITE, 0.10)
		_blood_fb_flash.parallel().tween_property(back_bar_endu, "modulate", Color.WHITE, 0.10)


## --------------------------------------------------
## DEBUG INPUTS (modifient l’ENDURANCE uniquement)
## down_menu : -25 endu  |  up_menu : +15 endu
## --------------------------------------------------
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("down_menu"):
		emit_signal("health_request", -205)
		#Player.add_max_hp(-50) 
		#print(Player.hp,"hp", Player.MAX_HP)
		#print(front_bar.value, "value texture",front_bar.max_value)
	elif event.is_action_pressed("up_menu"):
		emit_signal("rally_heal_request", 100.0)  # soigne via la jauge orange (30 PV pour le test)
		#emit_signal("health_request", 15)
		#Player.add_max_hp(50) 
		#print(Player.hp,"hp", Player.MAX_HP)
		#
		#print(front_bar.value, "value texture",front_bar.max_value)
