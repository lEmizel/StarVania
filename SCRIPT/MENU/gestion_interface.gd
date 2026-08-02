extends CanvasLayer
## HUD du joueur : cœurs de vie, jauge de sang, compteur de blood.
##
## Circuit : l'autoload Player modifie les valeurs (hp / sang) puis notifie
## ce HUD via les groupes UI_Health / UI_Sang et les signaux ci-dessous.
## Personne ne modifie Player.hp ou Player.sang sans passer par l'autoload.

signal health_request(amount: float)
signal sang_request(amount: float)
signal bar_max_request(kind: String, new_max: float)

## Largeur de la jauge de sang : pixels par point de capacité
@export var SANG_PX_PER_POINT: float = 4.0
## Durée du tween de la barre fantôme (dépense de sang)
@export var BACK_TWEEN_DURATION: float = 1.0
## Durée de la montée de jauge lors d'un gain de sang (courte = nerveuse)
@export var SANG_GAIN_TWEEN_DURATION: float = 0.3

@onready var sang_bar: TextureProgressBar = $barre_de_sang
@onready var sang_back_bar: TextureProgressBar = $Under_sang
@onready var _blood_icon: Control = $TextureRect
@onready var _blood_label: Control = $Label

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

var _max_sang: float


func _ready() -> void:
	add_to_group("UI_Health")
	add_to_group("UI_Sang")

	_max_sang = Player.MAX_SANG
	for bar in [sang_bar, sang_back_bar]:
		bar.min_value = 0
		bar.max_value = _max_sang
		bar.value = float(Player.sang)

	_build_hearts()

	connect("health_request", Callable(self, "_on_health_request"))
	connect("sang_request", Callable(self, "_on_sang_request"))
	connect("bar_max_request", Callable(self, "_on_bar_max_request"))
	_apply_sang_bar_max(_max_sang, false)


# ==================================================
#  CŒURS DE VIE
# ==================================================

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


func _on_health_request(amount: float) -> void:
	# Player.hp est déjà à jour, on en déduit l'ancien total
	var new_hp := int(Player.hp)
	var old_hp := int(round(float(new_hp) - amount))
	_refresh_hearts(old_hp, new_hp)


# ==================================================
#  JAUGE DE SANG
#  (ne se régénère jamais toute seule : elle se remplit uniquement
#   via les récoltes de sang des ennemis tués)
# ==================================================

var _sang_gain_tween: Tween = null

func _on_sang_request(amount: float) -> void:
	# cible = la vérité du singleton (déjà mis à jour), robuste même si un
	# tween de gain précédent est encore en vol
	var new_val: float = clampf(float(Player.sang), 0.0, _max_sang)
	var old_val: float = sang_bar.value

	if amount >= 0.0:
		# GAIN : montée progressive et rapide, pas de "pop" instantané
		if _sang_gain_tween != null and _sang_gain_tween.is_valid():
			_sang_gain_tween.kill()
		_sang_gain_tween = create_tween() \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)
		_sang_gain_tween.tween_property(sang_bar, "value", new_val, SANG_GAIN_TWEEN_DURATION)
		_sang_gain_tween.parallel().tween_property(sang_back_bar, "value", new_val, SANG_GAIN_TWEEN_DURATION)
	else:
		# DÉPENSE : front instant, back suit en tween (effet fantôme)
		sang_bar.value = new_val
		sang_back_bar.value = old_val
		sang_back_bar.create_tween() \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT) \
			.tween_property(sang_back_bar, "value", new_val, BACK_TWEEN_DURATION)


## Redimensionne la jauge quand la capacité max change
## (largeur = marges fixes + SANG_PX_PER_POINT × capacité)
func _apply_sang_bar_max(new_max: float, tween: bool = true) -> void:
	_max_sang = new_max
	for b in [sang_bar, sang_back_bar]:
		b.max_value = new_max

	var cap_sum := float(sang_bar.stretch_margin_left + sang_bar.stretch_margin_right)
	var w: float = cap_sum + SANG_PX_PER_POINT * new_max
	for b in [sang_bar, sang_back_bar]:
		if tween:
			var t := create_tween()
			t.tween_property(b, "size", Vector2(w, b.size.y), 0.30)
		else:
			b.size.x = w

	sang_bar.value = float(Player.sang)
	sang_back_bar.value = float(Player.sang)


# ==================================================
#  FX de ramassage de cœur : gros plan en fondu au centre de l'écran, puis
#  envol vers la rangée de cœurs en étoile filante rouge sang
# ==================================================

## Hauteur du gros plan de cœur ramassé : fraction de l'écran (0 = bord
## haut, 0.5 = centre). À ajuster au feeling.
@export var FX_COEUR_HAUTEUR: float = 0.25

func heart_pickup_fx() -> void:
	var big := Vector2(220.0, 220.0)
	var fx := TextureRect.new()
	fx.texture = _heart_template_full.texture
	# TODO (asset) : la texture du cœur est à l'envers pour le moment —
	# Kaoru corrigera le PNG plus tard ; RETIRER ce flip_v à ce moment-là
	fx.flip_v = true
	fx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.size = big
	fx.pivot_offset = big * 0.5
	var ecran := get_viewport().get_visible_rect().size
	fx.position = Vector2((ecran.x - big.x) * 0.5,
		ecran.y * FX_COEUR_HAUTEUR - big.y * 0.5)
	fx.modulate = Color(1.0, 1.0, 1.0, 0.0)
	fx.scale = Vector2(0.6, 0.6)
	add_child(fx)

	# traînée de comète rouge sang
	var trail := CPUParticles2D.new()
	trail.emitting = false
	trail.amount = 60
	trail.lifetime = 0.55
	trail.local_coords = false
	trail.direction = Vector2(0.0, 1.0)
	trail.spread = 35.0
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 40.0
	trail.initial_velocity_max = 140.0
	trail.scale_amount_min = 3.0
	trail.scale_amount_max = 7.0
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.25, 0.3, 1.0))
	grad.set_color(1, Color(0.45, 0.0, 0.06, 0.0))
	trail.color_ramp = grad
	trail.position = big * 0.5
	fx.add_child(trail)

	# cible : le centre du dernier cœur de la rangée (le tout nouveau)
	var target_center: Vector2 = _hearts.back()["full"].get_global_rect().get_center()

	var t := create_tween()
	# 1) fondu rapide plein écran avec petit pop
	t.tween_property(fx, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(fx, "scale", Vector2.ONE, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.35)
	# 2) envol en comète vers la rangée de cœurs
	t.tween_callback(func() -> void: trail.emitting = true)
	t.tween_property(fx, "position", target_center - big * 0.5, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(fx, "scale", Vector2(0.18, 0.18), 0.5)
	# 3) impact : pulsation du nouveau cœur, extinction de la comète
	t.tween_callback(_heart_land_pulse)
	t.tween_callback(func() -> void: trail.emitting = false)
	t.tween_property(fx, "modulate:a", 0.0, 0.1)
	t.tween_interval(0.6)  # laisse la traînée finir de mourir
	t.tween_callback(fx.queue_free)


func _heart_land_pulse() -> void:
	if _hearts.is_empty():
		return
	var h: TextureRect = _hearts.back()["full"]
	var base: Vector2 = h.scale
	var pt := create_tween()
	pt.tween_property(h, "scale", base * 1.35, 0.08)
	pt.tween_property(h, "scale", base, 0.15)


func _on_bar_max_request(kind: String, new_max: float) -> void:
	if kind == "sang":
		_apply_sang_bar_max(new_max, true)
	elif kind == "hp":
		# le nombre de cœurs max a changé (cœur ramassé…) : on reconstruit
		# la rangée — _build_hearts lit Player.max_hearts et repeint selon hp
		_build_hearts()


# ==================================================
#  FEEDBACK UNIVERSEL "pas de quoi payer" : l'UI de la ressource concernée
#  tremble et clignote en rouge. Appelé par le player pour tout coût refusé :
#    insufficient_feedback("sang")  → la jauge de sang (sorts)
#    insufficient_feedback("blood") → le compteur de blood (soin, achats...)
# ==================================================

var _fb_shake: Tween = null
var _fb_flash: Tween = null
var _fb_nodes: Array = []           # nœuds actuellement animés
var _fb_base_x: Dictionary = {}     # node -> position x d'origine

func insufficient_feedback(kind: String) -> void:
	match kind:
		"sang":
			_play_insufficient_feedback([sang_bar, sang_back_bar])
		"blood":
			_play_insufficient_feedback([_blood_icon, _blood_label])


func _play_insufficient_feedback(nodes: Array) -> void:
	# stoppe un feedback en cours et remet ses nœuds en place
	if _fb_shake != null and _fb_shake.is_valid():
		_fb_shake.kill()
	if _fb_flash != null and _fb_flash.is_valid():
		_fb_flash.kill()
	for n in _fb_nodes:
		if is_instance_valid(n):
			n.position.x = _fb_base_x.get(n, n.position.x)
			n.modulate = Color.WHITE

	_fb_nodes = nodes
	for n in nodes:
		if not _fb_base_x.has(n):
			_fb_base_x[n] = n.position.x

	# tremblement : oscillations décroissantes de tous les nœuds ensemble
	_fb_shake = create_tween()
	var amp := 7.0
	for i in range(3):
		for offset in [amp, -amp]:
			for j in nodes.size():
				var n: Control = nodes[j]
				if j == 0:
					_fb_shake.tween_property(n, "position:x", _fb_base_x[n] + offset, 0.04)
				else:
					_fb_shake.parallel().tween_property(n, "position:x", _fb_base_x[n] + offset, 0.04)
		amp *= 0.55
	for j in nodes.size():
		var n: Control = nodes[j]
		if j == 0:
			_fb_shake.tween_property(n, "position:x", _fb_base_x[n], 0.04)
		else:
			_fb_shake.parallel().tween_property(n, "position:x", _fb_base_x[n], 0.04)

	# clignotement rouge vif, en parallèle du tremblement
	_fb_flash = create_tween()
	for i in range(2):
		for j in nodes.size():
			var n: Control = nodes[j]
			if j == 0:
				_fb_flash.tween_property(n, "modulate", Color(1.0, 0.15, 0.15), 0.07)
			else:
				_fb_flash.parallel().tween_property(n, "modulate", Color(1.0, 0.15, 0.15), 0.07)
		for j in nodes.size():
			var n: Control = nodes[j]
			if j == 0:
				_fb_flash.tween_property(n, "modulate", Color.WHITE, 0.10)
			else:
				_fb_flash.parallel().tween_property(n, "modulate", Color.WHITE, 0.10)


# NOTE : les anciens inputs de debug (up_menu/down_menu → ±1 cœur) ont été
# retirés : ces actions partagent les boutons de la croix directionnelle
# avec le gameplay, ce qui déclenchait des soins/dégâts fantômes en jeu.
