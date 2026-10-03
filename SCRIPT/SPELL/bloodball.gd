extends Area2D
## Boule de sang : file tout droit à vitesse constante, explose au contact
## d'un ennemi (en le blessant) ou d'un mur. L'explosion est une scène
## indépendante instanciée au point d'impact.
## TALISMAN « BOULE CHERCHEUSE » (2 oct. 2026) : elle s'incurve vers l'ennemi le
## plus proche devant elle (`_virer`). TALISMAN « TROP-PLEIN » : le joueur peut
## la faire sortir grosse et forte (`grossir`).
##
## Le même script pilote la TORNADE DE SANG (tornade_de_sang.tscn, talisman du
## même nom) : même vol, même zone de touche, mais `recul` y est coché.

const EXPLOSION_SCENE := preload("res://SCRIPT/SPELL/bloodball_explosion.tscn")
## TALISMAN « MARQUE DE SANG » : l'ennemi touché (et resté en vie) est marqué ;
## le prochain coup d'épée sur lui compte double (voir animator.gd)
const MARQUE_SANG := preload("res://SCRIPT/SHADER/marque_sang.gd")
const TALISMAN_MARQUE := "marque"
## TALISMAN « SANG BOUILLANT » : l'ennemi touché (et resté en vie) bout un peu
## plus, comme sous l'épée ; à la 3e charge il explose (player.gd,
## `bouillant_charger`)
const TALISMAN_BOUILLANT := "bouillant"
## TALISMAN « SANG CRISTALLISÉ » : une chance (player.gd `cristal_chance`) de
## figer l'ennemi touché (BASE_IA.cristalliser)
const TALISMAN_CRISTAL := "cristal"
## TALISMAN « BOULE CHERCHEUSE » (2 oct. 2026, id "chercheuse" ; très
## efficace contre les volants) : la boule vise l'ennemi vivant
## le plus proche DEVANT elle (à `chercheuse_cone` degrés au plus de son sens de
## départ, à `chercheuse_rayon` px au plus, sans mur entre eux) et tourne vers
## lui d'au plus `chercheuse_virage` radians par seconde, sans jamais sortir de
## ce cône : elle ne fait pas demi-tour. Même portée (le chemin parcouru). La
## Tornade aussi (même script).
const TALISMAN_CHERCHEUSE := "chercheuse"
@export var chercheuse_virage := 6.0
@export var chercheuse_cone := 70.0
@export var chercheuse_rayon := 450.0
## la cible est revue toutes les… (s)
const RECHERCHE := 0.08
var _chercheuse := false
var _cible: Node2D = null
var _recherche_t := 0.0
## le sens de vol (unitaire) : (dir, 0) au départ ; seule la chercheuse le tourne
var _direction := Vector2.RIGHT
## TALISMAN « TROP-PLEIN » : sa taille (visuel ET zone de touche) et celle de son
## impact (`grossir`)
var _taille := 1.0
var _impact := 1.0
## TALISMAN « SANG CORROMPU » : posé par le joueur au lancer (`corrompre`) — la
## boule (ou la tornade) vire au violet, son impact aussi, et l'ennemi touché
## est empoisonné (player.gd, `empoisonner` ; SCRIPT/SHADER/poison_sang.gd)
var corrompu := false
var _palette: Array[Color] = []          # son cœur, sa couleur, son ombre

@export var speed := 800.0
@export var damage := 60  # sept. 2026 : un peu sous le coup léger au corps à corps (animator.gd : damage = 70)
## Portée maximale (px) avant auto-explosion : courte = outil de proximité,
## pas un sniper (avant sept. 2026 : ~1600 px via une durée de vie de 2 s)
@export var portee := 400.0
## true : l'ennemi touché est repoussé dans le sens du vol, comme par un coup
## d'épée (la boule de sang, elle, pique sans déplacer)
@export var recul := false

## Direction horizontale (+1 droite, -1 gauche) — posée par le player au spawn
var dir := 1

var _parcouru := 0.0
var _eclate := false     # a déjà explosé : un 2e contact dans la même frame ne compte pas


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# oriente la boule, la traînée part derrière (Trop-plein : grossie)
	scale = Vector2(float(dir) * _taille, _taille)
	_direction = Vector2(float(dir), 0.0)
	_chercheuse = Player.talisman_equipe(TALISMAN_CHERCHEUSE)


## TALISMAN « TROP-PLEIN » : cette boule sort `taille` fois plus grosse (le
## visuel ET la zone de touche) et fait `degats` fois ses dégâts ; son impact
## éclabousse plus large. Appelé par le joueur au lancer, avant son entrée en
## scène.
func grossir(taille: float, degats: float) -> void:
	_taille = maxf(taille, 0.1)
	damage = roundi(damage * degats)
	_impact = 1.0 + (_taille - 1.0) * 0.5


## TALISMAN « SANG CORROMPU » : la boule (ou la tornade) prend ces couleurs —
## son cœur, sa couleur, son ombre — et empoisonnera l'ennemi qu'elle touche.
## Appelé par le joueur au lancer, avant que la boule n'entre en scène.
func corrompre(coeur: Color, couleur: Color, ombre: Color) -> void:
	corrompu = true
	_teindre(coeur, couleur, ombre)


## TALISMAN « PACTE DE SANG » : payée sur la jauge de soin, cette boule fait
## `mult` fois ses dégâts (×3, player.gd `pacte_multiplicateur`) et prend le sang sombre du pacte — sauf corrompue :
## le violet du poison reste. Appelé par le joueur au lancer.
func pacte(mult: float, coeur: Color, couleur: Color, ombre: Color) -> void:
	damage = roundi(damage * mult)
	if not corrompu:
		_teindre(coeur, couleur, ombre)


## la boule (ou la tornade) et son impact prennent ces couleurs : son cœur, sa
## couleur, son ombre
func _teindre(coeur: Color, couleur: Color, ombre: Color) -> void:
	_palette = [coeur, couleur, ombre]
	var visuel := get_node_or_null("Visual") as CanvasItem
	if visuel != null and visuel.material is ShaderMaterial:
		# le matériau de la boule est PARTAGÉ par toutes les boules : on le copie
		var mat := (visuel.material as ShaderMaterial).duplicate() as ShaderMaterial
		mat.set_shader_parameter("core_color", coeur)
		mat.set_shader_parameter("blood_color", couleur)
		mat.set_shader_parameter("outer_color", ombre)
		visuel.material = mat


func _physics_process(delta: float) -> void:
	if _chercheuse:
		_virer(delta)
	var pas := speed * delta
	position += _direction * pas
	_parcouru += pas
	if _parcouru >= portee:
		_explode(PUISSANCE_A_VIDE)


## BOULE CHERCHEUSE : tourne vers sa cible, bornée au cône de son départ
func _virer(delta: float) -> void:
	_recherche_t -= delta
	if _recherche_t <= 0.0 or not _cible_valide(_cible):
		_recherche_t = RECHERCHE
		_cible = _chercher_cible()
	if _cible == null:
		return
	var vers := _centre(_cible) - global_position
	if vers.length_squared() < 1.0:
		return
	# les angles sont comptés depuis son sens de départ
	var depart := 0.0 if dir > 0 else PI
	var cone := deg_to_rad(chercheuse_cone)
	var voulu := clampf(wrapf(vers.angle() - depart, -PI, PI), -cone, cone)
	var actuel := wrapf(_direction.angle() - depart, -PI, PI)
	var pas_max := chercheuse_virage * delta
	var nouveau := actuel + clampf(voulu - actuel, -pas_max, pas_max)
	_direction = Vector2.from_angle(depart + nouveau)
	# elle regarde où elle va (retournée vers la gauche : un demi-tour de plus)
	rotation = _direction.angle() + (PI if dir < 0 else 0.0)


## l'ennemi vivant le plus proche devant elle, à portée, sans mur entre eux
func _chercher_cible() -> Node2D:
	var espace := get_world_2d().direct_space_state
	var cercle := CircleShape2D.new()
	cercle.radius = chercheuse_rayon
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = cercle
	requete.transform = Transform2D(0.0, global_position)
	requete.collision_mask = 8           # la couche des monstres
	requete.collide_with_areas = false
	var lanceur := get_tree().get_first_node_in_group("Player")
	var depart := Vector2(float(dir), 0.0)
	var cone := deg_to_rad(chercheuse_cone)
	var meilleure: Node2D = null
	var meilleure_distance := INF
	for resultat in espace.intersect_shape(requete, 32):
		var c = resultat["collider"]
		if not _cible_valide(c):
			continue
		var la := _centre(c)
		var vers := la - global_position
		if absf(depart.angle_to(vers)) > cone:
			continue                     # pas devant elle
		var distance := vers.length()
		if distance >= meilleure_distance:
			continue
		# un mur entre elle et lui ? (murs solides = couche 1, où est aussi le joueur)
		var rayon := PhysicsRayQueryParameters2D.create(global_position, la, 1)
		if lanceur != null:
			rayon.exclude = [lanceur.get_rid()]
		if not espace.intersect_ray(rayon).is_empty():
			continue
		meilleure = c
		meilleure_distance = distance
	return meilleure


func _cible_valide(c) -> bool:
	if not is_instance_valid(c) or not (c is BaseAI) or not c.is_inside_tree():
		return false
	if c.hp <= 0 or c.invulnerable:
		return false
	var lanceur := get_tree().get_first_node_in_group("Player")
	return lanceur == null or c.est_ennemi(lanceur)


## le milieu de son corps (sa zone de collision), pas ses pieds
func _centre(c: Node2D) -> Vector2:
	if c is BaseAI and c.collision != null:
		return c.collision.global_position
	return c.global_position


func _on_body_entered(body: Node) -> void:
	# ne jamais exploser sur le lanceur
	if _eclate or body.is_in_group("Player"):
		return
	if body.has_method("apply_damage"):
		# (le Canon de verre ne la double pas, pour qu'il ne
		# se cumule pas avec le Pacte de sang)
		var degats := damage
		# le joueur est l'attaquant : ses victimes sont les siennes (Essaim)
		var lanceur := get_tree().get_first_node_in_group("Player")
		var porte
		if recul:
			# source placée juste derrière l'ennemi : il part TOUJOURS dans le
			# sens du vol, même touché à bout portant
			porte = body.apply_damage(degats, (body as Node2D).global_position.x - dir, "tornade", true, lanceur)
		else:
			# knockback = false : la bloodball pique sans déplacer (l'ennemi
			# se retourne et aggro quand même via la réaction de BASE_IA)
			porte = body.apply_damage(degats, global_position.x, "bloodball", false, lanceur)
		if porte != false and body is BaseAI and Player.talisman_equipe(TALISMAN_MARQUE):
			MARQUE_SANG.poser(body)
		if porte != false and body is BaseAI and body.hp > 0 and lanceur != null \
				and Player.talisman_equipe(TALISMAN_BOUILLANT):
			lanceur.bouillant_charger(body)
		if corrompu and porte != false and body is BaseAI and body.hp > 0 and lanceur != null:
			lanceur.empoisonner(body)
		# SANG CRISTALLISÉ : une chance sur cinq de le figer dans le cristal
		if porte != false and body is BaseAI and body.hp > 0 and lanceur != null \
				and Player.talisman_equipe(TALISMAN_CRISTAL) and randf() < float(lanceur.cristal_chance):
			if body.cristalliser(float(lanceur.cristal_duree)):
				print("[CRISTAL] f=", Engine.get_physics_frames(), " figé ", lanceur.cristal_duree, " s")
	_explode()


## Force de l'éclaboussure quand la boule s'éteint toute seule en bout de
## course, sans rien toucher (1 = aussi grosse qu'un vrai impact).
const PUISSANCE_A_VIDE := 0.45


## `puissance` : 1 pour un vrai impact (ennemi ou mur). L'éclaboussure connaît
## le sens de vol de la boule : le sang rejaillit vers l'arrière.
func _explode(puissance := 1.0) -> void:
	if _eclate:
		return
	_eclate = true
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.demo_boucle = false
	explosion.direction = _direction
	explosion.puissance = puissance
	if not _palette.is_empty():
		# l'impact prend les couleurs de la boule, corrompue ou du pacte (sur une
		# copie : les réglages de la scène d'impact ne bougent pas)
		var mat := explosion.material as ShaderMaterial
		if mat != null:
			mat = mat.duplicate() as ShaderMaterial
			mat.set_shader_parameter("core_color", _palette[0])
			mat.set_shader_parameter("blood_color", _palette[1])
			mat.set_shader_parameter("dark_color", _palette[2])
			explosion.material = mat
	get_tree().current_scene.add_child(explosion)
	# TROP-PLEIN : la grosse boule éclabousse plus large
	explosion.scale = Vector2(_impact, _impact)
	# ColorRect : global_position = coin haut-gauche → on recentre le rect
	# sur le point d'impact en retirant la moitié de sa taille (agrandie)
	explosion.global_position = global_position - explosion.size * explosion.scale * 0.5
	# Un visuel qui sait se dissiper (la spirale de la tornade, avalée par
	# l'impact) finit de le faire avant que le projectile disparaisse : il ne
	# vole plus, ne touche plus rien, et c'est son visuel qui le supprime. La
	# boule de sang, elle, part tout de suite, comme avant.
	var visuel := get_node_or_null("Visual")
	if visuel != null and visuel.has_method("dissiper"):
		set_physics_process(false)
		set_deferred("monitoring", false)
		visuel.call("dissiper")
		return
	queue_free()
