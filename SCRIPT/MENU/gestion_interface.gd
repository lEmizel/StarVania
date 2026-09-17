extends CanvasLayer
## HUD du joueur : cœurs de vie, jauge de sang, compteur de blood.
##
## Circuit : l'autoload Player modifie les valeurs (hp / sang) puis notifie
## ce HUD via les groupes UI_Health / UI_Sang et les signaux ci-dessous.
## Personne ne modifie Player.hp ou Player.bloodheal sans passer par l'autoload.

signal health_request(amount: float)
signal bloodheal_request(amount: float)
signal bar_max_request(kind: String, new_max: float)

## Largeur de la jauge de sang : pixels par point de capacité
@export var BLOODHEAL_PX_PER_POINT: float = 2.2   # 16 sept. : une barre de 100 ≈ 100 px à l'écran (−35 %)
## Durée du tween de la barre fantôme (dépense de sang)
@export var BACK_TWEEN_DURATION: float = 1.0
## Durée de la montée de jauge lors d'un gain de sang (courte = nerveuse)
@export var BLOODHEAL_GAIN_TWEEN_DURATION: float = 0.3
## Soin : durée pendant laquelle la pastille pleine consommée se vide (son fantôme)
@export var BLOODHEAL_CONSO_DUREE: float = 0.35
## Soin : durée du report, le reste entamé glisse dans la pastille libérée
@export var BLOODHEAL_REPORT_DUREE: float = 0.25

## Espace horizontal (px écran) entre deux barres de bloodheal
@export var BLOODHEAL_ESPACEMENT: float = 2.0
## Pixels TRANSPARENTS gauche + droite dans la texture du cadre (mesurés :
## 21 + 23 sur barre de vie_1.png) : compensés pour que BLOODHEAL_ESPACEMENT
## soit l'écart réellement visible entre deux barres
@export var BLOODHEAL_MARGE_TEXTURE: float = 44.0

# gabarits (barre n°1) : les suivantes sont des copies décalées vers la droite,
# comme les cœurs. Chaque barre vaut exactement un soin (Player.BARRE_BLOODHEAL).
@onready var bloodheal_bar: TextureProgressBar = $barre_de_bloodheal
@onready var bloodheal_back_bar: TextureProgressBar = $Under_bloodheal
var _bh_bars: Array[TextureProgressBar] = []        # fronts, de gauche à droite
var _bh_back_bars: Array[TextureProgressBar] = []   # fantômes, même ordre
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

var _max_bloodheal: float


func _ready() -> void:
	add_to_group("UI_Health")
	add_to_group("UI_Bloodheal")

	_max_bloodheal = Player.MAX_BLOODHEAL
	_build_bloodheal_bars()
	print("[UI] ready  Player.bloodheal=", Player.bloodheal, " MAX_BLOODHEAL=", Player.MAX_BLOODHEAL,
		" barres=", _bh_bars.size())

	_build_hearts()

	connect("health_request", Callable(self, "_on_health_request"))
	connect("bloodheal_request", Callable(self, "_on_bloodheal_request"))
	connect("bar_max_request", Callable(self, "_on_bar_max_request"))


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

var _bloodheal_gain_tween: Tween = null
var _bloodheal_depense_tween: Tween = null      # dépense « par pastilles » en vol
var _bh_tweens_fantomes: Array[Tween] = []      # fantômes du vidage continu en vol

## valeur affichée par la barre n°i pour une réserve totale `total`
## (les barres se remplissent de gauche à droite, chacune jusqu'à un soin)
func _bh_valeur_barre(i: int, total: float) -> float:
	var barre := float(Player.BARRE_BLOODHEAL)
	return clampf(total - barre * float(i), 0.0, barre)


func _on_bloodheal_request(amount: float) -> void:
	# cible = la vérité du singleton (déjà mis à jour), robuste même si un
	# tween de gain précédent est encore en vol
	var total: float = clampf(float(Player.bloodheal), 0.0, _max_bloodheal)
	print("[UI] bloodheal_request amount=", amount, " Player.bloodheal=", Player.bloodheal,
		" barres=", _bh_bars.size())
	# On TUE d'abord un éventuel tween de gain en vol : sinon il réécrivait
	# les barres vers le haut après une dépense (bug de la jauge affichée
	# pleine après un soin post-récolte)
	if _bh_couper_animations():
		# une DÉPENSE animée a été coupée (coup porté juste après un soin) : on
		# repart de l'état VRAI d'avant cette requête, tassé à gauche
		_bh_caler(clampf(total - amount, 0.0, _max_bloodheal))

	if amount >= 0.0:
		# GAIN : montée progressive et rapide, barre après barre
		_bloodheal_gain_tween = create_tween() \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT) \
			.set_parallel(true)
		for i in _bh_bars.size():
			var cible := _bh_valeur_barre(i, total)
			if is_equal_approx(_bh_bars[i].value, cible):
				continue
			_bloodheal_gain_tween.tween_property(_bh_bars[i], "value", cible, BLOODHEAL_GAIN_TWEEN_DURATION)
			_bloodheal_gain_tween.tween_property(_bh_back_bars[i], "value", cible, BLOODHEAL_GAIN_TWEEN_DURATION)
	elif _bh_depense_par_pastilles(clampf(total - amount, 0.0, _max_bloodheal), total):
		pass  # un soin : pastille pleine consommée, puis report du reste (voir la fonction)
	else:
		# DÉPENSE partielle (pas un nombre entier de pastilles) : vidage continu,
		# front instant, fantôme qui suit en tween, barre par barre
		for i in _bh_bars.size():
			var cible := _bh_valeur_barre(i, total)
			var avant: float = _bh_bars[i].value
			if is_equal_approx(avant, cible):
				continue
			_bh_bars[i].value = cible
			_bh_back_bars[i].value = avant
			var tf := _bh_back_bars[i].create_tween() \
				.set_trans(Tween.TRANS_QUAD) \
				.set_ease(Tween.EASE_OUT)
			tf.tween_property(_bh_back_bars[i], "value", cible, BACK_TWEEN_DURATION)
			_bh_tweens_fantomes.append(tf)


## cale fronts ET fantômes sur l'état « tassé à gauche » d'une réserve `total`
func _bh_caler(total: float) -> void:
	for i in _bh_bars.size():
		var v := _bh_valeur_barre(i, total)
		_bh_bars[i].value = v
		_bh_back_bars[i].value = v


## coupe les animations de jauge en vol ; true si une DÉPENSE animée a été coupée
func _bh_couper_animations() -> bool:
	if _bloodheal_gain_tween != null and _bloodheal_gain_tween.is_valid():
		_bloodheal_gain_tween.kill()
	var depense_coupee := false
	if _bloodheal_depense_tween != null and _bloodheal_depense_tween.is_valid():
		_bloodheal_depense_tween.kill()
		depense_coupee = true
	_bloodheal_depense_tween = null
	for t in _bh_tweens_fantomes:
		if t != null and t.is_valid():
			t.kill()
			depense_coupee = true
	_bh_tweens_fantomes.clear()
	return depense_coupee


## Dépense d'un nombre ENTIER de pastilles (un soin = une pastille). La jauge ne
## se vide PAS comme une barre continue : la pastille PLEINE la plus à droite est
## consommée d'un bloc (son fantôme se vide vite, on la voit partir), puis le
## reste entamé glisse à gauche dans la place libérée. L'état final est le même
## que tassé à gauche. Retourne false si la dépense n'est pas un nombre entier
## de pastilles : l'appelant fait alors le vidage continu classique.
func _bh_depense_par_pastilles(avant: float, apres: float) -> bool:
	var barre := float(Player.BARRE_BLOODHEAL)
	var nb_conso := int(round((avant - apres) / barre))
	if nb_conso < 1 or not is_equal_approx(avant - apres, barre * float(nb_conso)):
		return false
	var pleines := int(floor(avant / barre + 0.0001))   # pastilles pleines avant la dépense
	if pleines < nb_conso or pleines > _bh_bars.size():
		return false
	_bh_caler(avant)                       # base vraie : l'état d'avant, tassé à gauche
	var premiere := pleines - nb_conso     # première pastille consommée
	var tw := create_tween().set_parallel(true)
	_bloodheal_depense_tween = tw
	# 1) consommation : le front tombe à zéro tout de suite, le fantôme se vide vite
	for i in range(premiere, pleines):
		_bh_bars[i].value = 0.0
		tw.tween_property(_bh_back_bars[i], "value", 0.0, BLOODHEAL_CONSO_DUREE) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2) report : tout se retasse à gauche, fronts et fantômes ensemble (c'est un
	#    déplacement, pas une perte : aucun fantôme à la traîne)
	var premier := true
	for i in range(premiere, _bh_bars.size()):
		var cible := _bh_valeur_barre(i, apres)
		var depart := 0.0 if i < pleines else _bh_valeur_barre(i, avant)
		if is_equal_approx(depart, cible):
			continue
		for b in [_bh_bars[i], _bh_back_bars[i]]:
			var t := tw.chain() if premier else tw
			premier = false
			t.tween_property(b, "value", cible, BLOODHEAL_REPORT_DUREE) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return true


## La capacité max a changé (barre gagnée…) : on reconstruit la rangée
func _apply_bloodheal_bar_max(new_max: float, _tween: bool = true) -> void:
	_max_bloodheal = new_max
	_build_bloodheal_bars()


## Construit la rangée de barres : le gabarit + autant de copies que
## Player.nb_barres_bloodheal − 1, décalées vers la droite. Chaque barre a la
## largeur d'un soin (marges fixes + BLOODHEAL_PX_PER_POINT × BARRE_BLOODHEAL).
func _build_bloodheal_bars() -> void:
	_bh_couper_animations()
	# purge les copies d'une construction précédente (on garde les gabarits)
	for b in _bh_bars:
		if b != bloodheal_bar:
			b.queue_free()
	for b in _bh_back_bars:
		if b != bloodheal_back_bar:
			b.queue_free()
	_bh_bars.clear()
	_bh_back_bars.clear()

	var barre := float(Player.BARRE_BLOODHEAL)
	var nb: int = clampi(int(round(_max_bloodheal / barre)), 1, Player.MAX_BARRES_BLOODHEAL)
	var cap_sum := float(bloodheal_bar.stretch_margin_left + bloodheal_bar.stretch_margin_right)
	var w: float = cap_sum + BLOODHEAL_PX_PER_POINT * barre          # largeur non mise à l'échelle
	# décalage écran entre deux barres : largeur VISIBLE (marges transparentes
	# de la texture déduites) + espacement voulu
	var pas: float = (w - BLOODHEAL_MARGE_TEXTURE) * bloodheal_bar.scale.x + BLOODHEAL_ESPACEMENT

	for i in nb:
		var front: TextureProgressBar = bloodheal_bar if i == 0 else bloodheal_bar.duplicate()
		var back: TextureProgressBar = bloodheal_back_bar if i == 0 else bloodheal_back_bar.duplicate()
		if i > 0:
			add_child(back)   # le fantôme d'abord : il reste dessous (z_index -1 copié)
			add_child(front)
			front.position.x = bloodheal_bar.position.x + pas * float(i)
			back.position.x = bloodheal_back_bar.position.x + pas * float(i)
		for b in [front, back]:
			b.min_value = 0
			b.max_value = barre
			b.size.x = w
			b.value = _bh_valeur_barre(i, float(Player.bloodheal))
		_bh_bars.append(front)
		_bh_back_bars.append(back)


# ==================================================
#  FX de ramassage de cœur : gros plan en fondu au centre de l'écran, puis
#  envol vers la rangée de cœurs en étoile filante rouge sang
# ==================================================

## Hauteur du gros plan de cœur ramassé : fraction de l'écran (0 = bord
## haut, 0.5 = centre). À ajuster au feeling.
@export var FX_COEUR_HAUTEUR: float = 0.25

# traînée de la cérémonie du cœur, fabriquée une seule fois (voir heart_pickup_fx)
@onready var _trail_coeur: CPUParticles2D = _creer_trail_coeur()


func _creer_trail_coeur() -> CPUParticles2D:
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
	trail.position = Vector2(-4000.0, -4000.0)   # hors écran en attendant
	add_child(trail)
	# chauffe : une émission hors écran à l'arrivée dans le niveau, pour que
	# ses tampons GPU existent avant le premier ramassage
	trail.emitting = true
	get_tree().create_timer(0.4).timeout.connect(func() -> void: trail.emitting = false)
	return trail


func heart_pickup_fx() -> void:
	# le nouveau cœur (déjà ajouté aux stats et à la rangée) reste invisible
	# jusqu'à l'impact de la comète — c'est elle qui le "dépose"
	if not _hearts.is_empty():
		var nouveau: Dictionary = _hearts.back()
		for k in ["full", "broken", "empty"]:
			nouveau[k].modulate.a = 0.0

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

	# traînée de comète rouge sang — instance UNIQUE créée au ready du HUD et
	# réutilisée : créer un CPUParticles2D en jeu freeze 100 à 250 ms sur Mac
	var trail := _trail_coeur
	trail.reparent(fx)
	trail.position = big * 0.5

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
	t.tween_callback(func() -> void:
		trail.reparent(self)   # la traînée survit au gros cœur, pour la prochaine fois
		fx.queue_free())


func _heart_land_pulse() -> void:
	if _hearts.is_empty():
		return
	# impact de la comète : le nouveau cœur se révèle et pulse
	var trio: Dictionary = _hearts.back()
	for k in ["full", "broken", "empty"]:
		trio[k].modulate.a = 1.0
	var h: TextureRect = trio["full"]
	var base: Vector2 = h.scale
	var pt := create_tween()
	pt.tween_property(h, "scale", base * 1.35, 0.08)
	pt.tween_property(h, "scale", base, 0.15)


func _on_bar_max_request(kind: String, new_max: float) -> void:
	if kind == "bloodheal":
		_apply_bloodheal_bar_max(new_max, true)
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
		"bloodheal":
			var noeuds: Array = []
			noeuds.append_array(_bh_bars)
			noeuds.append_array(_bh_back_bars)
			_play_insufficient_feedback(noeuds)
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
