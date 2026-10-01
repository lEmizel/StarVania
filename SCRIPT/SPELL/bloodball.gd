extends Area2D
## Boule de sang : file tout droit à vitesse constante, explose au contact
## d'un ennemi (en le blessant) ou d'un mur. L'explosion est une scène
## indépendante instanciée au point d'impact.
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
	scale.x = dir  # oriente la boule, la traînée part derrière


## TALISMAN « SANG CORROMPU » : la boule (ou la tornade) prend ces couleurs —
## son cœur, sa couleur, son ombre — et empoisonnera l'ennemi qu'elle touche.
## Appelé par le joueur au lancer, avant que la boule n'entre en scène.
func corrompre(coeur: Color, couleur: Color, ombre: Color) -> void:
	corrompu = true
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
	var pas := speed * delta
	position.x += dir * pas
	_parcouru += pas
	if _parcouru >= portee:
		_explode(PUISSANCE_A_VIDE)


func _on_body_entered(body: Node) -> void:
	# ne jamais exploser sur le lanceur
	if _eclate or body.is_in_group("Player"):
		return
	if body.has_method("apply_damage"):
		# CANON DE VERRE : tous les dégâts infligés sont multipliés
		var degats := roundi(damage * Player.multiplicateur_infliges())
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
	explosion.direction = Vector2(float(dir), 0.0)
	explosion.puissance = puissance
	if corrompu:
		# l'impact prend les couleurs de la boule corrompue (sur une copie :
		# les réglages de la scène d'impact ne bougent pas)
		var mat := explosion.material as ShaderMaterial
		if mat != null:
			mat = mat.duplicate() as ShaderMaterial
			mat.set_shader_parameter("core_color", _palette[0])
			mat.set_shader_parameter("blood_color", _palette[1])
			mat.set_shader_parameter("dark_color", _palette[2])
			explosion.material = mat
	get_tree().current_scene.add_child(explosion)
	# ColorRect : global_position = coin haut-gauche → on recentre le rect
	# sur le point d'impact en retirant la moitié de sa taille
	explosion.global_position = global_position - explosion.size * 0.5
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
