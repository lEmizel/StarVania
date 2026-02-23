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
@onready var front_bar_endu: TextureProgressBar   = $barre_endurence
@onready var back_bar_endu : TextureProgressBar   = $Under_endurence

## ---------------- Réglages (éditables) ----------------
@export var BACK_TWEEN_DURATION: float = 1.0    # durée du tween (vie & endu)


## ---------------- State interne ----------------
var _max_hp: float
var _max_en: float
var _cur_en: float


func _physics_process(delta: float) -> void:
	endurance_recup()

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
	connect("health_request", Callable(self, "_on_health_request"))
	connect("endurance_request", Callable(self, "_on_endurance_request"))
	connect("bar_max_request", Callable(self, "_on_bar_max_request"))
	connect("rally_heal_request", Callable(self, "_on_rally_heal_request"))
	_apply_bar_max_generic("hp", _max_hp, false)
	_apply_bar_max_generic("en", _max_en, false)  # si tu veux aussi pour l’endurance

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
func _on_endurance_request(amount: float) -> void:
	if amount < 0.0:
		set_meta("dbg_delay", 0.0)
		set_meta("dbg_t", 0.0)
	var old_val = front_bar_endu.value
	var new_val = clamp(old_val + amount, 0, _max_en)

	# Comportement identique à la vie : front instant, back suit en tween
	front_bar_endu.value = new_val
	back_bar_endu.value  = old_val
	back_bar_endu.create_tween() \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT) \
		.tween_property(back_bar_endu, "value", new_val, BACK_TWEEN_DURATION)

	_cur_en = new_val


@export var ENDURANCE_REGEN_STEP: float = 1.0  # valeur configurable (1, 2, 3...)
@export var DBG_COUNT_INTERVAL: float = 0.5 # secondes entre deux incréments (augmente = plus lent)
@export var ENDURANCE_REGEN_DELAY: float = 1.0 # secondes à attendre avant de commencer la regen

func endurance_recup() -> void:
	# si déjà au max, on ne fait rien
	if front_bar_endu.value >= _max_en:
		return

	# récupérer ou init le timer de délai
	var delay: float = float(get_meta("dbg_delay")) if has_meta("dbg_delay") else 0.0
	if delay < ENDURANCE_REGEN_DELAY:
		delay += get_physics_process_delta_time()
		set_meta("dbg_delay", delay)
		return # on sort tant que le délai n’est pas fini

	# --- une fois le délai atteint, on fait la logique normale ---
	var t: float = float(get_meta("dbg_t")) if has_meta("dbg_t") else 0.0
	t += get_physics_process_delta_time()
	var interval: float = DBG_COUNT_INTERVAL

	if t >= interval:
		var count: int = int(get_meta("dbg_count")) if has_meta("dbg_count") else 0
		var steps: int = int(floor(t / interval))
		if steps > 0:
			count += steps
			set_meta("dbg_count", count)
			

			var add: float = float(steps) * ENDURANCE_REGEN_STEP
			var en_new: float = clamp(front_bar_endu.value + add, 0.0, _max_en)
			front_bar_endu.value = en_new
			back_bar_endu.value  = en_new
			_cur_en = en_new
			Player.en = int(en_new)

			t -= interval * steps

	set_meta("dbg_t", t)



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
