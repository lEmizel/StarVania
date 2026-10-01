extends AnimatedSprite2D

@onready var player: CharacterBody2D = $"../.."
@onready var slash_attack: AnimatedSprite2D = $"../slash_attack"
@onready var collision: Area2D = $"../collision_attack"

@onready var hitbox_1: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D"
@onready var hitbox_2: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D2"
@onready var hitbox_3: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D3"
@onready var hitbox_4: CollisionPolygon2D = $"../collision_attack/CollisionPolygon2D4"


## dégâts DE BASE d'un coup d'épée ; le coup réel les multiplie par les bonus
## des talismans portés (`Player.multiplicateur_degats()`, un pourcentage),
## voir `degats_du_coup()`
var damage = 70

## l'éclat blanc qui marque un coup qui porte (30 sept. 2026)
const IMPACT := preload("res://SCRIPT/SHADER/impact_blanc.tscn")
## l'éclat reste à cette distance du bord de la zone balayée par la lame
const MARGE_ZONE := 24.0

## LE SLASH EN SHADER (30 sept. 2026) : le même croissant que les dessins, mais
## à chaque image d'écran. Il remplace les dessins qu'il sait refaire
## (`new_slash_1`, `slash_air`) tant que `slash_en_shader` est coché sur le
## joueur ; les autres slashs, et tous si la case est décochée, restent dessinés.
const SLASH_SHADER := preload("res://SCRIPT/SHADER/slash_heros.tscn")
var _slash_shader: Node2D

## TALISMAN « LAME DE FOUDRE » (30 sept. 2026) : porté, le slash est fait de
## foudre et, quand le coup PORTE, l'éclair bondit de l'ennemi touché sur
## l'ennemi le plus proche (`player.foudre_portee`), sans recul, pour
## `player.foudre_degats` — et ainsi de suite `player.foudre_sauts` fois, en
## divisant les dégâts par deux à chaque bond. Le bond ne recharge pas le
## bloodheal (seul le coup d'épée le fait). Un même ennemi n'est frappé qu'une
## fois par coup, directement ou par l'éclair.
const TALISMAN_FOUDRE := "foudre"
const ARC_FOUDRE := preload("res://SCRIPT/SHADER/arc_foudre.tscn")
var _foudre_touches: Array[Node] = []

func _ready() -> void:
	# 1) on connecte une fois les deux signaux
	SignalUtils.connect_signal(self, "frame_changed",    self, "_on_frame_changed")
	SignalUtils.connect_signal(self, "animation_changed", self, "_on_animation_changed")

	SignalUtils.connect_signal(collision, "body_entered", self, "_on_body_entered")
	# le FX de slash ne vit que le temps de son animation : caché au repos
	SignalUtils.connect_signal(slash_attack, "animation_finished", self, "_on_slash_finished")
	slash_attack.visible = false
	# le slash en shader : frère du slash dessiné, sous POINT (il se retourne
	# avec le perso), posé après lui pour se dessiner au même rang
	_slash_shader = SLASH_SHADER.instantiate()
	_slash_shader.demo_boucle = false
	slash_attack.add_sibling.call_deferred(_slash_shader)


func _on_slash_finished() -> void:
	slash_attack.visible = false

	
func _process(delta):
	# le croissant de sang armé par le coup en cours (voir `_croissant`)
	if _croissant_reste < 0.0:
		return
	# le coup a été interrompu, ou un autre a commencé : il ne part pas
	if _croissant_coup != _coup_id or not _slash_a_l_ecran():
		_croissant_annuler()
		return
	_croissant_reste -= delta
	if _croissant_reste > player.croissant_amorce:
		return
	# il « prend » sur la lame : posé sur le trajet du slash, il la suit…
	var reste := maxf(_croissant_reste, 0.0)
	var prog := clampf(player.croissant_depart - reste / maxf(_croissant_duree, 0.001), 0.0, 1.0)
	var g: Dictionary = _slash_shader.geometrie(SLASH_DU_CROISSANT, prog)
	if _croissant_noeud == null:
		_croissant_noeud = _croissant_creer(g)
	_croissant_noeud.suivre_lame(slash_attack.to_global(g["centre"]), g["queue"], g["tete"],
		1.0 - reste / maxf(player.croissant_amorce, 0.001))
	# … et s'en détache quand elle passe devant le perso
	if _croissant_reste <= 0.0:
		_croissant_noeud.lacher()
		print("[CROISSANT] lancé : ", _croissant_noeud.degats, " dégâts")
		_croissant_noeud = null
		_croissant_reste = -1.0
# 2) Ce handler est appelé à chaque fois qu'on change d'animation    

## les dégâts d'un coup d'épée, bonus des talismans compris (70 → 77 avec la
## lame de foudre, +10 %)
func degats_du_coup() -> int:
	return roundi(damage * Player.multiplicateur_degats())


## la rune du talisman « Marque de sang » (posée par la boule de sang)
const MARQUE_SANG := preload("res://SCRIPT/SHADER/marque_sang.gd")
## le numéro du coup d'épée en cours (un par `_play_slash`) : le croissant de
## sang armé par un coup ne part pas si un autre coup a commencé
var _coup_id := 0

## TALISMAN « CROISSANT DE SANG » (1er oct. 2026) : le DERNIER coup du combo
## projette son slash vers l'avant (SCRIPT/SHADER/croissant_sang.gd). Le combo
## n'a que DEUX coups en jeu (1 → 2 → 1…, ATTACK_LIGHT_3 n'est jamais atteint) :
## c'est donc le 2e (« attack_02 ») ; si le 3e revient, déplacer l'appel. Il vaut
## `player.croissant_part` d'un coup d'épée, bonus compris, et ignore les
## ennemis que ce coup vient de toucher au corps à corps.
## Il NAÎT SUR LE SLASH (Kaoru : « qu'il commence pile sur le slash FX du
## joueur ») : `_croissant()` l'ARME au départ du coup. `_process` le crée
## `player.croissant_amorce` s avant le départ, ATTACHÉ à la lame : posé sur le
## centre du trajet du slash (le slash vit sous POINT : retourné avec le
## perso, agrandi par l'Allonge), il suit la lame image après image et
## « prend » dessus ; puis il est LÂCHÉ quand la lame passe devant le perso (à
## `player.croissant_depart` de la durée du slash). Si le coup est interrompu
## avant (plus de slash à l'écran, ou un autre coup a commencé), il ne part
## pas.
const TALISMAN_CROISSANT := "croissant"
## TALISMAN « OMBRE DE SANG » : quand le coup porte, un double surgit derrière
## l'ennemi et le refait (player.gd, `ombre_surgir`) — un double par coup
const TALISMAN_OMBRE := "ombre"
## TALISMAN « SANG BOUILLANT » : chaque coup qui porte charge l'ennemi
## (player.gd, `bouillant_charger`)
const TALISMAN_BOUILLANT := "bouillant"
## TALISMAN « COUP DANS LE DOS » : un coup qui frappe un ennemi de dos fait
## `player.dos_multiplicateur` fois ses dégâts (`_de_dos`) ; son éclat est plus
## grand et cerné de sang (`_eclat_impact`)
const TALISMAN_DOS := "dos"
const DOS_ECLAT_TAILLE := 1.3
const DOS_ECLAT_CONTOUR := Color(0.78, 0.04, 0.12)
## où regardaient les ennemis proches quand le coup a COMMENCÉ (instance → ±1)
var _dos_regards := {}
## TALISMAN « CRESCENDO » : chaque coup qui porte fait monter la série
## (player.gd, `crescendo_pourcent` / `crescendo_porte`) ; le slash rougit et
## s'épaissit avec elle (`_crescendo_habiller`)
const TALISMAN_CRESCENDO := "crescendo"
## TALISMAN « LAME CORROMPUE » : chaque coup qui porte empoisonne (player.gd,
## `empoisonner`), le slash vire au violet, la foudre aussi (`_habiller_slash`,
## `_foudre_bondir`)
const TALISMAN_LAME_CORROMPUE := "lame_corrompue"
## TALISMAN « VENIN » : l'éclat d'un coup sur un ennemi empoisonné se cerne de
## violet (les dégâts en plus : BASE_IA `_venin`)
const TALISMAN_VENIN := "venin"
const VENIN_ECLAT_CONTOUR := Color(0.6, 0.18, 0.9)
## les couleurs du slash en shader telles que réglées (lues une fois) : sa
## lame, sa foudre, le halo de sa foudre
var _slash_couleur_base := Color.WHITE
var _slash_foudre_base := Color(0.45, 0.72, 1.0)
var _slash_halo_base := Color(0.30, 0.42, 1.0)
var _slash_couleur_lue := false
var _ombre_coup := -1            # le coup d'épée qui a déjà fait surgir son double
## le dernier slash lancé (l'ombre de sang le refait)
var dernier_slash := "new_slash_1"
const CROISSANT := preload("res://SCRIPT/SHADER/croissant_sang.tscn")
## le slash dont il se détache (celui des coups au sol)
const SLASH_DU_CROISSANT := "new_slash_1"
var _croissant_reste := -1.0     # temps avant de le lâcher (s) ; < 0 : rien d'armé
var _croissant_duree := 0.24     # durée du slash qui le porte (s)
var _croissant_coup := -1        # le coup d'épée qui l'a armé
var _croissant_noeud: Node2D = null   # celui qui est en train de prendre sur la lame


func _croissant() -> void:
	if not Player.talisman_equipe(TALISMAN_CROISSANT) or _slash_shader == null:
		return
	_croissant_annuler()
	_croissant_duree = float(_slash_shader.geometrie(SLASH_DU_CROISSANT, 0.0)["duree"])
	_croissant_reste = _croissant_duree * player.croissant_depart
	_croissant_coup = _coup_id


## le slash du coup en cours est-il à l'écran (dessiné ou en shader) ?
func _slash_a_l_ecran() -> bool:
	return slash_attack.visible or (_slash_shader != null and _slash_shader.visible)


## le croissant, attaché à la lame (géométrie `g` du slash à cet instant)
func _croissant_creer(g: Dictionary) -> Node2D:
	var c := CROISSANT.instantiate()
	c.demo_boucle = false
	c.attache = true
	c.dir = -1 if player.point.scale.x < 0.0 else 1
	c.degats = roundi(degats_du_coup() * player.croissant_part)
	c.joueur = player
	c.touches_du_coup = _foudre_touches
	c.forme = g["forme"]
	c.echelle = slash_attack.scale.x      # le talisman Allonge agrandit le slash
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = player.get_parent()
	hote.add_child(c)
	return c


## rien ne part : le croissant armé (ou déjà attaché à la lame) est retiré
func _croissant_annuler() -> void:
	_croissant_reste = -1.0
	if _croissant_noeud != null and is_instance_valid(_croissant_noeud):
		_croissant_noeud.queue_free()
	_croissant_noeud = null


func _on_body_entered(body):
	# on passe en paramètre amount ET la position X du joueur
	if body.has_method("apply_damage"):
		var coup := degats_du_coup()
		# MARQUE DE SANG : un ennemi marqué par la boule de sang prend
		# `marque_multiplicateur` fois le coup ; la marque éclate s'il porte
		var marque := MARQUE_SANG.est_marque(body)
		if marque:
			coup = roundi(coup * player.marque_multiplicateur)
		# VENGEANCE : chargée par un coup encaissé, elle renforce TOUS les
		# coups d'épée tant qu'elle dure
		var venge: bool = player.vengeance_active()
		if venge:
			coup = roundi(coup * player.vengeance_multiplicateur)
		# COUP DANS LE DOS : regardé AVANT le coup (touché, il se retourne
		# vers nous)
		var dos := Player.talisman_equipe(TALISMAN_DOS) and _de_dos(body)
		if dos:
			coup = roundi(coup * player.dos_multiplicateur)
		# CRESCENDO : ce coup vaut son rang dans la série (5, 10, 20, 40, 50 %)
		var serie: float = player.crescendo_pourcent(_coup_id)
		if serie > 0.0:
			coup = roundi(coup * (1.0 + serie / 100.0))
		# SANG CRISTALLISÉ : figé, ce coup brise le cristal et compte plus
		var cristal: bool = body is BaseAI and body.est_cristallise()
		if cristal:
			coup = roundi(coup * player.cristal_bonus)
		# COUP DE GRÂCE : fissuré (à portée d'exécution), ce coup l'achève
		var grace: bool = body is BaseAI and body.executable()
		if grace:
			coup = maxi(coup, body.hp)
		# (le joueur se déclare comme attaquant : ses victimes sont les siennes)
		var porte = body.apply_damage(coup, player.global_position.x, "epee", true, player)
		# coup au corps à corps qui PORTE (pas sur un mort ni un blindé) :
		# la jauge bloodheal se recharge de 20 % d'une barre (sept. 2026 :
		# c'est le coup qui recharge, plus le kill)
		if porte != false:
			if marque:
				MARQUE_SANG.consommer(body)
				print("[MARQUE] coup d'épée marqué : ", coup, " dégâts")
			if venge:
				player.vengeance_frapper()
				print("[VENGEANCE] coup vengeur : ", coup, " dégâts (encore ",
					snappedf(player.vengeance_reste, 0.01), " s)")
			if dos:
				print("[DOS] coup dans le dos : ", coup, " dégâts")
			if serie > 0.0:
				player.crescendo_porte(_coup_id)
				print("[CRESCENDO] coup n°", player.crescendo_serie, " de la série : +",
					serie, " % → ", coup, " dégâts")
			Player.changement_de_bloodheal(Player.BLOODHEAL_PAR_COUP)
			_eclat_impact(body, dos)
			# l'ombre de sang surgit derrière le premier ennemi que ce coup touche
			if Player.talisman_equipe(TALISMAN_OMBRE) and _ombre_coup != _coup_id \
					and body is BaseAI and body.hp > 0:
				_ombre_coup = _coup_id
				player.ombre_surgir(body)
			# SANG BOUILLANT : son sang bout un peu plus (boum à la 3e charge)
			if Player.talisman_equipe(TALISMAN_BOUILLANT) and body is BaseAI and body.hp > 0:
				player.bouillant_charger(body)
			# LAME CORROMPUE : le coup empoisonne (ou prolonge le poison)
			if Player.talisman_equipe(TALISMAN_LAME_CORROMPUE) and body is BaseAI and body.hp > 0:
				player.empoisonner(body)
			# COUP DE GRÂCE : il vole en éclats, la jauge se remplit
			if grace:
				player.grace_executer(body)
			# SANG CRISTALLISÉ : le cristal vole en éclats, il repart
			if cristal:
				body.briser_cristal()
				print("[CRISTAL] brisé par l'épée : ", coup, " dégâts")
			_foudre_touches.append(body)
			if Player.talisman_equipe(TALISMAN_FOUDRE):
				_foudre_bondir(body, coup)
		# Ennemi inébranlable : le contrecoup annule l'élan du joueur
		# au lieu de faire reculer l'ennemi
		if body is BaseAI and body.inebranlable:
			player.cancel_movement_recoil()


## Le bond de la lame de foudre : depuis l'ennemi touché par un coup de `coup`
## dégâts, l'éclair saute sur le voisin le plus proche encore indemne (pour
## `foudre_part` du coup), puis du voisin au suivant (moitié à chaque bond).
## L'arc est posé dans la scène (comme l'éclat d'impact) : il finit de jouer
## même si l'ennemi meurt du coup.
func _foudre_bondir(depuis: Node, coup: int) -> void:
	var source: Node = depuis
	var degats: int = maxi(roundi(coup * player.foudre_part), 1)
	for _saut in player.foudre_sauts:
		var cible := _foudre_cible(source)
		if cible == null:
			return
		_foudre_touches.append(cible)
		var arc := ARC_FOUDRE.instantiate()
		arc.demo_boucle = false
		var hote: Node = get_tree().current_scene
		if hote == null:
			hote = player.get_parent()
		hote.add_child(arc)
		# LAME CORROMPUE : l'éclair vire au violet (sur son propre matériau)
		var corrompue := Player.talisman_equipe(TALISMAN_LAME_CORROMPUE)
		if corrompue:
			var trait_arc := arc.get_node_or_null("Trait") as CanvasItem
			if trait_arc != null and trait_arc.material is ShaderMaterial:
				var m := trait_arc.material as ShaderMaterial
				m.set_shader_parameter("couleur", player.lame_corrompue_coeur_foudre)
				m.set_shader_parameter("couleur_foudre", player.lame_corrompue_foudre)
		arc.tendre(_centre_du_corps(source), _centre_du_corps(cible))
		# la foudre se retourne contre le joueur, pas contre l'ennemi d'où elle
		# a sauté : c'est lui l'attaquant (pas de recul : l'éclair pique)
		var porte = cible.apply_damage(degats, player.global_position.x, "foudre", false, player)
		if porte == false:
			return
		# … et l'ennemi que l'éclair touche est empoisonné à son tour
		if corrompue and cible is BaseAI and cible.hp > 0:
			player.empoisonner(cible)
		source = cible
		degats = maxi(roundi(degats * 0.5), 1)


## L'ennemi le plus proche de `depuis` à portée de l'éclair, vivant, vulnérable,
## du camp d'en face, pas encore frappé par ce coup, et sans mur entre les deux.
func _foudre_cible(depuis: Node) -> Node:
	var espace := player.get_world_2d().direct_space_state
	var origine := _centre_du_corps(depuis)
	var cercle := CircleShape2D.new()
	cercle.radius = player.foudre_portee
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = cercle
	requete.transform = Transform2D(0.0, origine)
	requete.collision_mask = 8           # la couche des monstres
	requete.collide_with_areas = false
	var meilleur: Node = null
	var meilleure_distance := INF
	for resultat in espace.intersect_shape(requete, 16):
		var c: Node = resultat["collider"]
		if c == depuis or not (c is BaseAI) or _foudre_touches.has(c):
			continue
		if c.hp <= 0 or c.invulnerable or not c.est_ennemi(player):
			continue
		var la := _centre_du_corps(c)
		var distance := origine.distance_to(la)
		if distance >= meilleure_distance:
			continue
		# un mur entre les deux ? (murs solides = couche 1, comme le rayon du
		# grappin ; le JOUEUR est aussi sur la couche 1 : on l'exclut, sinon
		# l'éclair refuse tout voisin de l'autre côté de lui — les volants qui
		# tournent autour de lui en faisaient les frais)
		var rayon := PhysicsRayQueryParameters2D.create(origine, la, 1)
		rayon.exclude = [player.get_rid()]
		if not espace.intersect_ray(rayon).is_empty():
			continue
		meilleur = c
		meilleure_distance = distance
	return meilleur


## le milieu du corps d'un monstre (pas ses pieds)
func _centre_du_corps(n: Node) -> Vector2:
	if n is BaseAI and n.collision != null:
		return n.collision.global_position
	return (n as Node2D).global_position


## L'éclat d'impact : posé là où la lame rencontre le corps, tourné dans le sens
## du coup. Seulement quand le coup PORTE (ni sur un mort, ni sur un blindé) :
## c'est la confirmation visuelle que l'épée a mordu. Hébergé par la scène, pas
## par le monstre — il doit finir de jouer même si le monstre meurt du coup, et
## il reste où le coup est tombé pendant que le monstre recule.
func _eclat_impact(body: Node, dans_le_dos := false) -> void:
	if not (body is Node2D):
		return
	var centre: Vector2 = body.global_position
	if body is BaseAI and body.collision != null:
		centre = body.collision.global_position      # le milieu du corps, pas ses pieds
	var sens := signf(centre.x - player.global_position.x)
	if sens == 0.0:
		sens = float(player.last_direction)
	# un gros monstre a son milieu hors de portée de l'épée : l'éclat ne sort
	# jamais de la zone que la lame balaie vraiment
	var zone := _zone_du_coup()
	if zone.has_area():
		centre = centre.clamp(zone.position, zone.end)
	var fx := IMPACT.instantiate()
	fx.demo_boucle = false
	fx.z_index = 5                                    # devant le monstre et son flash
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = player.get_parent()
	hote.add_child(fx)
	# jamais deux fois au même endroit ni sous le même angle
	fx.global_position = centre + Vector2(-sens * 8.0, randf_range(-16.0, 16.0))
	fx.scale = Vector2(sens, 1.0)
	fx.rotation = randf_range(-0.3, 0.3)
	# COUP DANS LE DOS : l'étoile blanche (« tu as frappé ») grandit un peu et
	# se cerne de sang. (Un 2e éclat, rouge, posé dessous et agrandi ×2,2
	# couvrait le héros ET l'ennemi : beaucoup trop ; et une étoile rouge, c'est
	# déjà « le héros encaisse ».)
	# VENIN : un ennemi empoisonné prend plus — l'étoile se cerne de violet
	var venin := not dans_le_dos and Player.talisman_equipe(TALISMAN_VENIN) \
			and body.has_meta("poison") and is_instance_valid(body.get_meta("poison"))
	if dans_le_dos:
		fx.scale *= DOS_ECLAT_TAILLE
	if dans_le_dos or venin:
		# le matériau est sur l'enfant « Eclat » (propre à chaque éclat)
		var eclat := fx.get_node_or_null("Eclat") as CanvasItem
		if eclat != null and eclat.material is ShaderMaterial:
			var mat := eclat.material as ShaderMaterial
			mat.set_shader_parameter("couleur_contour", DOS_ECLAT_CONTOUR if dans_le_dos else VENIN_ECLAT_CONTOUR)
			mat.set_shader_parameter("contour", 0.85)


## l'ennemi nous tourne-t-il le dos ? Nous sommes du côté opposé à son regard
## (`last_direction`), à plus de quelques pixels de son milieu — son regard
## d'AU DÉPART du coup compte aussi : la lame met ~0,2 s à arriver, et un
## squelette qui nous voit passer derrière lui a le temps de se retourner (en
## test, une fois sur deux le bonus sautait alors qu'on avait frappé son dos)
func _de_dos(body: Node) -> bool:
	if not (body is BaseAI):
		return false
	var centre: Vector2 = body.global_position
	if body.collision != null:
		centre = body.collision.global_position
	var dx: float = player.global_position.x - centre.x
	if absf(dx) <= 4.0:
		return false
	var cote := signf(dx)
	var au_depart: int = _dos_regards.get(body.get_instance_id(), body.last_direction)
	return cote != float(body.last_direction) or cote != float(au_depart)


## au départ d'un coup : où regardent les ennemis à moins de 400 px
func _dos_noter_regards() -> void:
	_dos_regards.clear()
	if not Player.talisman_equipe(TALISMAN_DOS):
		return
	var cercle := CircleShape2D.new()
	cercle.radius = 400.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = cercle
	q.transform = Transform2D(0.0, player.global_position)
	q.collision_mask = 8                     # la couche des monstres
	q.collide_with_areas = false
	for r in get_world_2d().direct_space_state.intersect_shape(q, 32):
		var c: Object = r["collider"]
		if c is BaseAI:
			_dos_regards[c.get_instance_id()] = c.last_direction


## LE SLASH DU COUP QUI PART, habillé par les talismans :
## - LAME CORROMPUE : sa lame vire au violet (`player.lame_corrompue_couleur`),
##   et, avec la Lame de foudre, sa foudre et son halo aussi ;
## - CRESCENDO : il rougit (vers `player.crescendo_couleur`) et s'épaissit
##   (jusqu'à `player.crescendo_epaisseur` fois) selon le rang de ce coup dans la
##   série (+5 % : à peine teinté ; +50 % : rouge).
## Sans ces talismans : tel quel (les couleurs réglées, lues une fois).
func _habiller_slash() -> void:
	var corrompue := Player.talisman_equipe(TALISMAN_LAME_CORROMPUE)
	var t := 0.0
	if Player.talisman_equipe(TALISMAN_CRESCENDO):
		t = player.crescendo_pourcent(_coup_id) / float(player.CRESCENDO_PALIERS[-1])
	var lame: ColorRect = null
	if _slash_shader != null:
		lame = _slash_shader.get_node_or_null("Lame") as ColorRect
	if lame != null and lame.material is ShaderMaterial:
		var mat := lame.material as ShaderMaterial
		if not _slash_couleur_lue:
			_slash_couleur_base = _parametre(mat, "couleur", _slash_couleur_base)
			_slash_foudre_base = _parametre(mat, "couleur_foudre", _slash_foudre_base)
			_slash_halo_base = _parametre(mat, "couleur_halo", _slash_halo_base)
			_slash_couleur_lue = true
		var base: Color = player.lame_corrompue_couleur if corrompue else _slash_couleur_base
		mat.set_shader_parameter("couleur", base.lerp(player.crescendo_couleur, t))
		mat.set_shader_parameter("couleur_foudre", player.lame_corrompue_foudre if corrompue else _slash_foudre_base)
		mat.set_shader_parameter("couleur_halo", player.lame_corrompue_halo if corrompue else _slash_halo_base)
		_slash_shader.epaisseur_facteur = lerpf(1.0, player.crescendo_epaisseur, t)
	# le slash dessiné (si le shader est décoché) : teinté de même
	var dessin: Color = player.lame_corrompue_couleur if corrompue else Color.WHITE
	slash_attack.self_modulate = dessin.lerp(player.crescendo_couleur, t)


## un paramètre d'un matériau, ou la valeur par défaut de son shader s'il ne
## le règle pas, ou `sinon`
func _parametre(mat: ShaderMaterial, nom: String, sinon: Color) -> Color:
	var v = mat.get_shader_parameter(nom)
	if v == null and mat.shader != null:
		v = RenderingServer.shader_get_parameter_default(mat.shader.get_rid(), nom)
	return v if v is Color else sinon


## Le rectangle (en coordonnées du monde) que couvrent les hitbox d'attaque
## actives, un peu rentré. Vide si aucune n'est active.
func _zone_du_coup() -> Rect2:
	var zone := Rect2()
	var vide := true
	for hb: CollisionPolygon2D in [hitbox_1, hitbox_2, hitbox_3, hitbox_4]:
		if hb.disabled:
			continue
		for pt in hb.polygon:
			var g: Vector2 = hb.global_transform * pt
			if vide:
				zone = Rect2(g, Vector2.ZERO)
				vide = false
			else:
				zone = zone.expand(g)
	return zone.grow(-MARGE_ZONE) if not vide else zone

# play() ne redémarre pas une anim déjà en cours de lecture —
# on force le stop pour que le slash reparte toujours de la frame 0
func _play_slash(anim_name: String) -> void:
	couper_slash()
	_foudre_touches.clear()      # un nouveau coup : tout le monde est de nouveau frappable
	_coup_id += 1
	# TALISMAN « ALLONGE » : la lame porte plus loin — la zone de touche ET le
	# slash (dessiné ou en shader) grandissent ensemble autour du centre du
	# coup (là où player.gd vient de poser le slash), pour que ce qu'on voit
	# reste ce qui touche
	var f := 1.0 + Player.bonus_talismans("allonge_pourcent") / 100.0
	var c := slash_attack.position
	collision.transform = Transform2D(0.0, Vector2(f, f), 0.0, c * (1.0 - f))
	slash_attack.scale = Vector2(f, f)
	if _slash_shader != null:
		_slash_shader.scale = Vector2(f, f)
	dernier_slash = anim_name
	_habiller_slash()
	# en shader si on sait le refaire : à la place exacte du dessin (player.gd
	# la pose sur slash_attack à chaque attaque)
	if player.slash_en_shader and _slash_shader.is_inside_tree() and _slash_shader.connait(anim_name):
		_slash_shader.position = slash_attack.position
		_slash_shader.effet = "foudre" if Player.talisman_equipe(TALISMAN_FOUDRE) else "aucun"
		_slash_shader.jouer(anim_name)
		return
	slash_attack.visible = true  # peut avoir été masqué par un retournement du perso
	slash_attack.play(anim_name)


## Le coup en cours est terminé ou interrompu : son slash disparaît, qu'il soit
## dessiné ou en shader.
func couper_slash() -> void:
	slash_attack.stop()
	slash_attack.visible = false
	if _slash_shader != null:
		_slash_shader.couper()

## TALISMAN « PARADE » : la lame est-elle EN GARDE — sortie (une zone de touche
## active pendant un coup) ou sur le point de sortir (l'image juste avant le
## slash) ? Un coup d'ennemi qui arrive à ce moment-là est paré (player.gd,
## `_parade_tente`). Pas pendant les retours (« _r »).
const PARADE_IMAGE_AVANT := {"attack": 1, "attack_02": 0, "attack_air": 2, "attack_03": 0, "attack_lourde": 2}
func lame_en_garde() -> bool:
	var nom := String(animation)
	if not nom.begins_with("attack") or nom.ends_with("_r"):
		return false
	for hb in [hitbox_1, hitbox_2, hitbox_3, hitbox_4]:
		if not (hb as CollisionPolygon2D).disabled:
			return true
	return PARADE_IMAGE_AVANT.has(nom) and frame == PARADE_IMAGE_AVANT[nom]


## la zone de touche de l'épée active en ce moment (0 à 3), 0 si aucune
func zone_active() -> int:
	var hbs := [hitbox_1, hitbox_2, hitbox_3, hitbox_4]
	for i in hbs.size():
		if not (hbs[i] as CollisionPolygon2D).disabled:
			return i
	return 0


func _disable_all_hitboxes() -> void:
	hitbox_1.set_deferred("disabled", true)
	hitbox_2.set_deferred("disabled", true)
	hitbox_3.set_deferred("disabled", true)
	hitbox_4.set_deferred("disabled", true)

	
func _on_animation_changed() -> void:
	_disable_all_hitboxes()
	# le perso change d'animation = le coup en cours est terminé ou
	# interrompu : son FX de slash disparaît avec lui (un éventuel coup
	# suivant relancera le sien via _play_slash)
	couper_slash()
	# COUP DANS LE DOS : un coup commence → on note où regardent les ennemis
	var nom_anim := String(animation)
	if nom_anim.begins_with("attack") and not nom_anim.ends_with("_r"):
		_dos_noter_regards()
	# frame_changed n'est pas émis quand on passe d'une anim en frame 0
	# à une nouvelle anim en frame 0 (la valeur ne change pas) —
	# on rattrape donc la frame 0 ici, au changement d'animation
	_process_frame_logic()

func _on_frame_changed():
	_process_frame_logic()

# garde-fou pour ne pas traiter deux fois la même frame de la même anim
var _last_frame_key := ""

func _process_frame_logic() -> void:
	var key := str(animation) + ":" + str(frame)
	if key == _last_frame_key:
		return
	_last_frame_key = key
	var current_animation = animation
	match current_animation:
		"attack":
			match frame:
				0:
					_disable_all_hitboxes()
				1:
					pass
				2:
					_disable_all_hitboxes()
					_play_slash("new_slash_1")
					hitbox_1.set_deferred("disabled", false)
		"attack_02":
			match frame:
				1:
					_play_slash("new_slash_1")
					hitbox_2.set_deferred("disabled", false)
					_croissant()      # le DERNIER coup du combo (il n'en a que deux)
				3:
					_disable_all_hitboxes()

	
		"attack_03":
			match frame:
				0:
					player.velocity.x = player.point.scale.x * 250
				1:
					hitbox_3.set_deferred("disabled", false)
					_play_slash("slash_3")
				2:
					pass
				3:
					_disable_all_hitboxes()
					pass

		"attack_03_r":
			match frame:
				0:
					pass
				1:
					player.velocity.x = 0
		"attack_lourde":
			match frame:
				0:
					pass
				1:
					pass
				2:
					player.velocity.x = player.point.scale.x * 250
				3:
					_play_slash("slash_h")
				4:
					pass
				5:
					player.velocity.x = 0
				6:
					pass
				7:
					pass
		"attack_air":
			match frame:
				3:
					_play_slash("slash_air")
					hitbox_4.set_deferred("disabled", false)
				6:
					_disable_all_hitboxes()
