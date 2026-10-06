# premier_boss.gd
extends BaseAI
## ============================================================================
## PREMIER BOSS — VERSION PROVISOIRE, pour essayer l'enchaînement de ses
## attaques avant que ses images existent. Son corps est dessiné par un shader
## (premier_boss_corps.gd, premier_boss.gdshader).
##
## ELLE VOLE TOUT LE TEMPS : au repos elle flotte à `hauteur_repos` du sol, à
## hauteur d'épée ; elle ne le touche qu'à sa mort. La toucher NE BLESSE PAS
## (`contact_damage` 0 sur sa scène : à cette hauteur son corps serait un mur
## de 450 px) — seules ses attaques blessent. Si le héros est juste sous elle,
## elle reste assez haut pour ne pas se poser sur lui.
## Le combat commence quand elle voit le héros (ou qu'il la frappe). Ensuite
## elle enchaîne ses attaques, tirées AU HASARD (jamais deux fois la même de
## suite ; `attaque_seule` n'en garde qu'une, pour la régler) :
##   • LA PLUIE DE PÉTALES — elle monte à `hauteur_pluie` et vient se placer
##     au-dessus du héros (c'est elle qui prévient, en se mettant en place),
##     lève les ailes pendant `annonce_pluie`, puis les abat : la pluie tombe
##     sous toute son envergure. La réponse : ne pas rester sous elle.
##   • LES LANCES — sa main quitte la cloche et se lève pendant
##     `annonce_lances`, puis elle claque des doigts : les lances sortent du sol
##     de toute l'arène, en rythme, une vague par claquement. La réponse : se
##     placer dans les trous.
##   • LE VENT ET LA CLOCHE — elle descend à la hauteur du héros, à
##     `distance_vent` de lui du côté du mur le plus proche (il fuit donc vers
##     le milieu de l'arène ; du côté où elle était déjà, le combat finissait
##     toujours contre un mur), ses ailes vrombissent, une brise prévient
##     (`annonce_vent`), puis un vent très fort le TIRE vers elle pendant
##     `duree_vent`. La réponse : courir à l'opposé. S'il arrive à moins de
##     `declenche_cloche` d'elle, elle SONNE SA CLOCHE : ses ronds blessent
##     (une fois) et le repoussent — et LE VENT TIRE TOUJOURS pendant qu'elle
##     sonne : pris dedans, on ne s'en sort plus en courant, la roulade passe
##     les ronds. Une seule sonnerie par vent (`cloches_max` : à 3, on mourait
##     d'office), puis elle revient.
##   • LA RAFALE DE PÉTALES — chaque battement d'ailes envoie une rafale de
##     pétales des deux côtés jusqu'aux murs, BASSE ou HAUTE. C'EST ELLE QUI
##     MONTRE LA HAUTEUR : pour une basse elle descend au ras du sol
##     (`hauteur_rafale_basse`), pour une haute elle remonte
##     (`hauteur_rafale_haute`) — la rafale part de là où sont ses ailes. La
##     réponse : sauter la basse, rester au sol sous la haute. Tant que ça dure,
##     la toucher ne blesse pas (on saute à travers elle).
## Après le vent et la pluie, qui l'éloignent, elle REVIENT SE POSER PRÈS DU
## HÉROS (`recul_repos`), du côté du milieu de l'arène : on la frappe sans
## courir, et le combat ne dérive pas vers un mur.
## Entre deux attaques, `repos` s où elle flotte près du sol : le moment de la
## frapper.
##
## LA PHASE 2, à `p2_seuil` de sa vie : l'ÉVEIL — elle monte, sa cloche sonne,
## ses yeux s'ouvrent, intouchable `p2_eveil_duree` s — puis tout se resserre,
## EN FACTEURS des réglages de la phase 1 : repos ×`p2_repos`, `p2_rafales_en_plus`
## rafales de plus par salve, les vagues de lances ×`p2_lances_rythme` plus
## rapprochées, et des LANCES SOUS LA PLUIE (`p2_lances_pendant_la_pluie` : le
## nœud `LancesPluie`, quelques lances au hasard sous les pétales — on sort de
## dessous elle en slalomant). Ses ailes battent plus vite, sa cloche tremble
## sans arrêt. Et une attaque à elle, LE REGARD (`Regard`) : ses yeux ouverts
## visent le héros, un fil de lumière le suit puis se fige, et un rayon part
## le long du fil ; `tirs` fois de suite — et à chaque rayon, un coup d'aile
## envoie une RAFALE BASSE (`p2_regard_rafale`). La réponse : quand le fil se
## fige, sortir de la ligne (un pas de côté en s'éloignant d'elle, ou un saut
## si elle est couchée), puis sauter la rafale qui suit le rayon.
## C'est un VRAI BOSS (`vrai_boss`) : inébranlable, ni Coup de grâce ni cristal.
##
## L'ARÈNE est mesurée au début du combat : le sol sous elle, les murs de
## chaque côté (couche 2, les décors). Les lances couvrent tout l'espace entre
## les deux murs ; sans murs, `largeur_arene` la fixe à la main.
## La pluie, les lances et la rafale sont ses nœuds `Petales`, `Lances` et
## `Rafale` : leurs réglages (durée, rythme, dégâts…) se font sur eux. Le vent (vent_aspire.gdshader) et
## les ronds de la cloche (SCRIPT/SHADER/cri_rond.tscn, ceux du cri du
## loup-garou) sont fabriqués ici, à son départ.
##
## POUR LA JUGER SANS HÉROS : ouvrir la scène et faire F6 — elle enchaîne ses
## attaques au-dessus d'un sol d'essai, en suivant une cible qui va et vient.
## ============================================================================

enum States { IDLE, SURVOL, PLUIE, LANCES, VENT, RAFALE, REGARD, RETOUR, EVEIL, DEAD }

signal combat_commence
signal vaincue
## la phase 2 commence (son éveil)
signal phase_2

## 1 = sa taille normale : 445 px de la tête aux pieds (un peu moins de 1,75
## fois son dessin de référence), 1190 px d'un bout d'aile à l'autre
@export_range(0.4, 2.5, 0.05) var taille := 1.0
@export var points_de_vie := 1500
## pour régler une attaque : elle ne fait plus que celle-là
@export_enum("Au hasard", "Pluie de pétales", "Lances", "Vent et cloche", "Rafale de pétales", "Regard (phase 2)") var attaque_seule := 0

@export_group("Vol")
## au repos, ses pieds flottent à … px du sol : à 60, l'épée du héros (qui
## monte à 230 px) la prend sur 170 px de haut sans sauter. Le héros ne passe
## plus sous elle : la toucher blesse, comme un autre monstre
@export var hauteur_repos := 60.0
## pour la pluie, elle monte à … px du sol (plus haut, sa tête sort de l'écran)
@export var hauteur_pluie := 250.0
## sa vitesse en vol (px/s) ; en dessous de celle du héros : en courant, il lui
## échappe
@export var vitesse_vol := 520.0
## elle se balance de … px en flottant
@export var flottement := 8.0

@export_group("Combat")
## le répit entre deux attaques (s) : le moment de la frapper
@export var repos := 2.5
## quand elle voit le héros, elle attend … s avant sa première attaque
@export var eveil := 1.5
## après le vent ou la pluie, elle revient se poser à … px du héros, du côté du
## milieu de l'arène (0 : elle reste où elle est)
@export var recul_repos := 220.0
## elle y revient à … px/s
@export var vitesse_retour := 900.0

@export_group("Pluie de pétales")
## elle suit le héros au plus … s avant de s'arrêter au-dessus de lui
@export var survol_max := 2.6
## ailes levées pendant … s, puis elle les abat et la pluie part (à 0,9, le
## héros sorti de dessous elle en réagissant en 0,5 s n'est pas touché)
@export var annonce_pluie := 0.9
## demi-largeur de la pluie (px) ; 0 : celle de ses ailes
@export var envergure_pluie := 0.0
## les pétales partent pendant … s (0 : la durée réglée sur le nœud Petales,
## 4,2 s — deux fois trop long dans un combat, ça casse le rythme). L'attaque
## dure cette durée plus l'annonce, la chute et la braise : environ 2 s de plus
@export var duree_pluie := 1.2

@export_group("Lances")
## main levée pendant … s avant que la première vague s'annonce
@export var annonce_lances := 0.6
## largeur de la zone des lances (px), centrée sur sa place de départ ; 0 : tout
## l'espace entre les deux murs qui l'entourent
@export var largeur_arene := 0.0
## pendant les lances, ses pieds montent à … px du sol : une lance qui touche le
## héros le fait sauter de 44 px, il ne doit pas en plus heurter son corps
@export var hauteur_lances := 230.0

@export_group("Vent et cloche")
## elle se pose à … px du héros, d'un côté ou de l'autre
@export var distance_vent := 800.0
## elle descend alors à … px du sol : à la hauteur du héros
@export var hauteur_vent := 30.0
## une brise prévient pendant … s (elle ne tire pas encore)
@export var annonce_vent := 0.6
## puis le vent tire le héros vers elle pendant … s
@export var duree_vent := 3.0
## la vitesse du vent (px/s). Le héros court à 700 : en dessous il s'éloigne en
## courant à l'opposé, à 700 il tient sur place, au-dessus le vent est plus fort
## que lui — à 760, en courant sans s'arrêter il perd 60 px par seconde : il
## tient jusqu'au bout s'il part à temps
@export var force_vent := 760.0
## le vent porte jusqu'à … px d'elle
@export var portee_vent := 1700.0
## s'il arrive à moins de … px d'elle, elle sonne sa cloche
@export var declenche_cloche := 260.0
## la cloche blesse jusqu'à … px d'elle ; ses ronds se règlent dessus
@export var portee_cloche := 420.0
## cœurs enlevés par la cloche (une seule fois par sonnerie)
@export var degats_cloche := 1
## la vitesse de ses ronds (px/s) : vite, on ne les distance pas en courant
@export var vitesse_cloche := 1100.0
## sonneries par vent, au plus : UNE (à 3, pris dans le vent, on mourait
## d'office) ; au-delà, elle sonne encore tant que le héros reste contre elle
@export var cloches_max := 1
@export var couleur_cloche := Color(1.0, 0.84, 0.92)

@export_group("Phase 2")
## elle s'éveille quand il lui reste … de sa vie (0 : pas de phase 2)
@export_range(0.0, 0.95) var p2_seuil := 0.5
## l'éveil : intouchable pendant … s, sa cloche sonne, ses yeux s'ouvrent
@export var p2_eveil_duree := 1.5
## en phase 2, son repos vaut … fois celui de la phase 1
@export_range(0.2, 1.0) var p2_repos := 0.7
## … rafales de plus par salve
@export var p2_rafales_en_plus := 2
## les vagues de lances sont … fois plus rapprochées
@export_range(0.3, 1.0) var p2_lances_rythme := 0.7
## pendant la pluie, elle claque aussi des doigts : les lances du nœud
## `LancesPluie` sortent sous la pluie, … s après le premier pétale
@export var p2_lances_pendant_la_pluie := true
@export var p2_lances_delai := 0.5
## pendant le regard, chaque rayon est suivi d'une rafale basse
@export var p2_regard_rafale := true

@export_group("Rafale de pétales")
## pour une rafale HAUTE, ses pieds montent à … px du sol ; pour une BASSE, ils
## descendent à … px : sa place montre la hauteur de la rafale qui vient
@export var hauteur_rafale_haute := 250.0
@export var hauteur_rafale_basse := 20.0
## elle change de hauteur à … px/s (vite : l'annonce est courte)
@export var vitesse_rafale := 1500.0
## ailes levées pendant … s avant que la première rafale s'annonce
@export var annonce_rafale := 0.25
@export_group("")
## lancée seule (F6) : elle enchaîne ses attaques au-dessus d'un sol d'essai
@export var demo_boucle := true

## son accélération en vol (px/s²)
const ACCELERATION := 2600.0
## elle arrive en douceur : sa vitesse vaut … fois ce qui lui reste à parcourir
const DOUCEUR := 4.0
## elle se tient à … px des murs de l'arène, au moins (pour une taille de 1)
const MARGE_MUR := 150.0
## les murs de l'arène sont cherchés jusqu'à … px de chaque côté
const PORTEE_MURS := 6000.0
## sans murs trouvés ni `largeur_arene` : une zone de lances de … px
const LARGEUR_PAR_DEFAUT := 1600.0
## même déjà au-dessus du héros, sa mise en place dure au moins … s
const SURVOL_MINI := 0.7
## morte, elle ne tombe pas plus vite que … px/s
const CHUTE_MAX := 1400.0
## ses attaques, dans l'ordre de la liste `attaque_seule` ; la dernière, le
## regard, n'est tirée qu'en phase 2
const ATTAQUES := [States.SURVOL, States.LANCES, States.VENT, States.RAFALE, States.REGARD]
## sa mise en place à côté du héros dure au plus … s
const PLACEMENT_VENT_MAX := 2.2
## la brise qui prévient : la force du dessin du vent (1 : le vent qui tire)
const BRISE := 0.35
## le vent arrive à sa pleine force en … s
const MONTEE_DU_VENT := 0.3
## pour le vent, elle ne descend à la hauteur du héros qu'à plus de … px de lui
## en largeur ; au repos, à plus de … px (son corps plus le sien) ; tant qu'il
## est sous elle, ses pieds restent à … px du sol au moins (il fait 126 px)
const ECART_POUR_DESCENDRE := 300.0
const ECART_SOUS_ELLE := 115.0
const HAUTEUR_SUR_LE_HEROS := 160.0
## son retour près du héros dure au plus … s
const RETOUR_MAX := 2.5
## la bande de vent : du sol jusqu'à … px de haut
const HAUT_VENT := 540.0
## la cloche sonne pendant … s, puis elle reste … s sur place
const DUREE_SON := 0.5
const APRES_LE_SON := 0.7
## le rayon des ronds de la cloche pour une portée de 1 : encore pleins à la portée
const RAYON_PAR_PORTEE := 1.4
const CRI_SCENE := preload("res://SCRIPT/SHADER/cri_rond.tscn")
const VENT_SHADER := preload("res://SCRIPT/BOSS/vent_aspire.gdshader")

@onready var petales: Node2D = $Petales
@onready var lances: Node2D = $Lances
@onready var rafale: Node2D = $Rafale
@onready var lances_pluie: Node2D = $LancesPluie
@onready var regard: Node2D = $Regard

var _combat := false
var _mesuree := false
var _age := 0.0
var _t := 0.0
var _attente := 0.0           # le repos à tenir avant la prochaine attaque
var _phase := 0
var _derniere := -1           # sa dernière attaque : elle n'est pas rejouée aussitôt
var _p2 := false              # la phase 2 est en cours
var _eveillee := false        # l'éveil a eu lieu (il n'a lieu qu'une fois)
var _lances_sous_la_pluie := false
var _contact_d_avant := 1     # ses dégâts de contact, mis de côté pendant les rafales
var _contact_coupe := false   # … et tant qu'elle n'est pas remontée après
var _poste := Vector2.ZERO    # où elle se tient pendant une attaque
var _cote := 1.0              # le vent : de quel côté du héros elle se pose
var _regard := 1.0            # le vent : le côté qu'il couvre (celui où elle regarde)
var _cloche: Node2D           # les ronds de sa cloche
var _cloche_a_porte := false  # cette sonnerie a déjà pris son cœur
var _sonneries := 0           # les sonneries de ce vent
var _vent_rect: ColorRect
var _vent_mat: ShaderMaterial
var _vent_force := 0.0        # la force du dessin du vent, et celle qu'on lui demande
var _vent_voulu := 0.0
var _vent_t := 0.0
var _sol_y := 0.0
var _centre_x := 0.0
var _demi_arene := LARGEUR_PAR_DEFAUT * 0.5
var _bob := 0.0
var _scrute := 0.0
var _au_sol := false
var _demo := false
var _demo_t := 0.0
var _demo_tire := 0.0         # la démo : de combien le vent a tiré la cible
var _cible_demo: Node2D


func _ready() -> void:
	# AVANT BASE_IA : sa zone de contact copie la forme de collision
	_appliquer_taille()
	super._ready()
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		_preparer_la_demo()


## Sa taille règle sa forme de collision, son dessin et la place de sa barre de vie
func _appliquer_taille() -> void:
	var forme: CollisionShape2D = $Collision
	if forme.shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = forme.shape.duplicate()
		capsule.radius *= taille
		capsule.height *= taille
		forme.shape = capsule
		forme.position *= taille
	animator.taille = taille
	animator._poser_rectangle()
	var barre: Node2D = $bare_de_vie
	barre.position = Vector2(-243.0 * barre.scale.x, -animator.hauteur_tete() - 60.0)
	$POINT/vision.position = forme.position


func _setup_states() -> void:
	_register_states(States)


func _start() -> void:
	volant = true
	vrai_boss = true
	inebranlable = true
	oubli_hors_vue = 0.0              # elle n'oublie pas sa cible faute de la voir
	max_tracking_distance = 1.0e6
	max_hp = points_de_vie
	hp = points_de_vie
	_flash_material = animator.materiau()
	petales.automatique = false
	lances.automatique = false
	lances.vague_annoncee.connect(_on_vague_annoncee)
	lances.vague_sortie.connect(_on_vague_sortie)
	lances_pluie.automatique = false
	lances_pluie.vague_sortie.connect(_on_vague_sortie)
	regard.automatique = false
	regard.vise.connect(_on_regard_vise)
	regard.tir.connect(_on_regard_tir)
	rafale.automatique = false
	rafale.rafale_annoncee.connect(_on_rafale_annoncee)
	rafale.rafale_partie.connect(_on_rafale_partie)
	_poser_vent_et_cloche()
	_sol_y = global_position.y + hauteur_repos
	_centre_x = global_position.x
	change_state(States.IDLE)


func _physics_process(delta: float) -> void:
	if _demo:
		_animer_la_demo(delta)
	super(delta)
	animator.suivre(velocity)
	# à `p2_seuil` de sa vie : l'éveil, une fois
	if _combat and not _eveillee and p2_seuil > 0.0 and hp <= int(points_de_vie * p2_seuil) \
			and current_state != States.DEAD and current_state != States.EVEIL:
		goto_state(States.EVEIL)


## le dessin du vent : il monte et retombe en douceur
func _process(delta: float) -> void:
	if _vent_rect == null:
		return
	_vent_force = move_toward(_vent_force, _vent_voulu, delta * 3.0)
	_vent_rect.visible = _vent_force > 0.01
	if _vent_rect.visible:
		_vent_t += delta
		_vent_mat.set_shader_parameter("temps", _vent_t)
		_vent_mat.set_shader_parameter("force", _vent_force)


# ============================================================
#  DÉGÂTS (overrides)
# ============================================================
func _is_dead() -> bool:
	return current_state == States.DEAD

func _on_dead() -> void:
	change_state(States.DEAD)


# ============================================================
#  DÉCISION
# ============================================================

## La prochaine attaque, une fois son repos tenu. BASE_IA l'appelle aussi quand
## on la frappe ou qu'elle reprend ses esprits : elle ne quitte jamais une
## attaque en cours, et n'écourte pas son repos.
func decide() -> void:
	if current_state != States.IDLE or not _combat or est_etourdi():
		return
	if not check_tracking() or _t < _attente:
		return
	_attente = INF                    # (jusqu'à son prochain repos)
	goto_state(_choisir_attaque())


## Sa prochaine attaque : au hasard, mais pas celle qu'elle vient de faire
## (`attaque_seule` : toujours celle-là)
func _choisir_attaque() -> int:
	if attaque_seule > 0:
		return ATTAQUES[mini(attaque_seule, ATTAQUES.size()) - 1]
	var possibles: Array = ATTAQUES.filter(func(a: int) -> bool: return a != _derniere and (a != States.REGARD or _p2))
	_derniere = possibles[randi() % possibles.size()]
	return _derniere


func _commencer_le_combat() -> void:
	_combat = true
	_t = 0.0
	_attente = eveil
	_mesurer_arene()
	combat_commence.emit()


# ============================================================
#  L'ARÈNE, LE VOL
# ============================================================

## Le sol sous elle et les murs de chaque côté (couche 2 : les décors — ni le
## héros ni les monstres n'y sont)
func _mesurer_arene() -> void:
	_mesuree = true
	var espace := get_world_2d().direct_space_state
	var ici := global_position
	var bas := espace.intersect_ray(PhysicsRayQueryParameters2D.create(
			ici + Vector2(0.0, -40.0), ici + Vector2(0.0, 4000.0), 2))
	_sol_y = (bas["position"] as Vector2).y if not bas.is_empty() else ici.y + hauteur_repos
	if largeur_arene > 0.0:
		_centre_x = initial_position.x
		_demi_arene = largeur_arene * 0.5
		return
	var depuis := Vector2(ici.x, _sol_y - 90.0)
	var gauche := espace.intersect_ray(PhysicsRayQueryParameters2D.create(
			depuis, depuis + Vector2(-PORTEE_MURS, 0.0), 2))
	var droite := espace.intersect_ray(PhysicsRayQueryParameters2D.create(
			depuis, depuis + Vector2(PORTEE_MURS, 0.0), 2))
	if gauche.is_empty() or droite.is_empty():
		_centre_x = initial_position.x
		_demi_arene = LARGEUR_PAR_DEFAUT * 0.5
		return
	var x_gauche: float = (gauche["position"] as Vector2).x
	var x_droite: float = (droite["position"] as Vector2).x
	_centre_x = (x_gauche + x_droite) * 0.5
	_demi_arene = (x_droite - x_gauche) * 0.5


## `x`, ramené entre les murs de l'arène (à MARGE_MUR près)
func _dans_l_arene(x: float) -> float:
	var demi := maxf(_demi_arene - MARGE_MUR * taille, 0.0)
	return clampf(x, _centre_x - demi, _centre_x + demi)


## Elle vole vers `but` : vite quand elle est loin, en douceur à l'arrivée
## (`vitesse` : sa vitesse au plus ; 0 : `vitesse_vol`)
func _voler_vers(but: Vector2, delta: float, vitesse := 0.0) -> void:
	var limite := vitesse if vitesse > 0.0 else vitesse_vol
	var voulue := ((but - global_position) * DOUCEUR * maxf(limite / vitesse_vol, 1.0)).limit_length(limite)
	velocity = velocity.move_toward(voulue, ACCELERATION * maxf(limite / vitesse_vol, 1.0) * delta)


## Là où elle flotte au repos : à `_poste.x`, à `hauteur_repos` du sol, en se
## balançant — sauf si le héros est juste sous elle
func _point_de_repos() -> Vector2:
	return Vector2(_poste.x, _sans_ecraser(_sol_y - hauteur_repos + sin(_bob * 2.2) * flottement, ECART_SOUS_ELLE))


## Sa place de repos : près du héros, du côté du milieu de l'arène ; sans héros
## (ou `recul_repos` 0) : là où elle est
func _place_de_repos() -> float:
	if recul_repos <= 0.0 or not check_tracking():
		return global_position.x
	var vers_milieu := signf(_centre_x - target.global_position.x)
	if vers_milieu == 0.0:
		vers_milieu = signf(global_position.x - target.global_position.x)
	if vers_milieu == 0.0:
		vers_milieu = 1.0
	return _dans_l_arene(target.global_position.x + vers_milieu * recul_repos)


# ============================================================
#  ÉTATS
# ============================================================

# --- IDLE : elle flotte près du sol (avant le combat, et entre deux attaques) ---
func idle_enter() -> void:
	animator.play("idle")
	animator.voler(0.35 if _p2 else 0.0)
	animator.armer_ailes(false)
	animator.lever_bras(false)
	_t = 0.0
	_poste = Vector2(global_position.x, _sol_y - hauteur_repos)
	if _combat:
		_attente = repos * (p2_repos if _p2 else 1.0)

func idle_execute(delta: float) -> void:
	_age += delta
	if not _mesuree:
		# (les décors du niveau viennent d'arriver : on les laisse se poser)
		velocity = Vector2.ZERO
		if _age > 0.15:
			_mesurer_arene()
		return
	_bob += delta
	_voler_vers(_point_de_repos(), delta, vitesse_retour)
	# (après des rafales : la toucher blesse de nouveau une fois qu'elle est remontée)
	if _contact_coupe and _sol_y - global_position.y >= hauteur_repos - 25.0:
		_contact_coupe = false
		contact_damage = _contact_d_avant
	if not check_tracking():
		# un héros DÉJÀ dans son champ n'y « entre » jamais : elle regarde encore
		_scrute -= delta
		if _scrute <= 0.0:
			_scrute = 0.25
			_rescan_vision()
		return
	if not _combat:
		_commencer_le_combat()
	flip_toward(target.global_position.x)
	_t += delta
	if _t >= _attente:
		decide()


# --- SURVOL : elle monte et vient se placer au-dessus du héros, puis lève les ailes ---
func survol_enter() -> void:
	animator.play("vol")
	animator.voler(1.0)
	_t = 0.0
	_phase = 0

func survol_execute(delta: float) -> void:
	_t += delta
	var haut := _sol_y - hauteur_pluie
	if _phase == 0:
		var x := global_position.x
		if check_tracking():
			x = _dans_l_arene(target.global_position.x)
			flip_toward(target.global_position.x)
		_voler_vers(Vector2(x, haut), delta)
		var en_place := absf(global_position.x - x) < 60.0 and absf(global_position.y - haut) < 50.0
		if (en_place and _t >= SURVOL_MINI) or _t >= survol_max:
			# ailes levées : elle ne le suit plus
			_phase = 1
			_t = 0.0
			_poste = Vector2(global_position.x, haut)
			animator.armer_ailes(true)
	else:
		_voler_vers(_poste, delta)
		if _t >= annonce_pluie:
			goto_state(States.PLUIE)


# --- PLUIE : elle abat ses ailes, et tient sa place tant que ses pétales tombent ---
func pluie_enter() -> void:
	animator.play("pluie")
	animator.coup_d_aile()
	petales.envergure = envergure_pluie if envergure_pluie > 0.0 else animator.demi_envergure_px()
	if duree_pluie > 0.0:
		petales.duree = duree_pluie
	petales.position = Vector2(0.0, -animator.hauteur_poitrine())
	petales.lancer()
	_lances_sous_la_pluie = false

func pluie_execute(delta: float) -> void:
	_bob += delta
	_voler_vers(_poste + Vector2(0.0, sin(_bob * 2.2) * flottement), delta)
	# phase 2 : sous la pluie, elle claque des doigts
	if _p2 and p2_lances_pendant_la_pluie and not _lances_sous_la_pluie \
			and petales._t >= petales.delai_avertissement + p2_lances_delai:
		_lances_sous_la_pluie = true
		animator.lever_bras(true)
		lances_pluie.largeur = 2.0 * _demi_arene
		lances_pluie.global_position = Vector2(_centre_x, _sol_y - 60.0)
		lances_pluie.lancer()
	if not petales.en_cours() and not lances_pluie.en_cours():
		goto_state(States.RETOUR)

func pluie_exit() -> void:
	animator.lever_bras(false)


# --- LANCES : la main levée, puis un claquement de doigts par vague ---
func lances_enter() -> void:
	_poste = Vector2(global_position.x, _sol_y - hauteur_lances)
	animator.play("lances")
	animator.voler(0.35)
	animator.lever_bras(true)
	_t = 0.0
	_phase = 0

func lances_execute(delta: float) -> void:
	_t += delta
	_bob += delta
	_voler_vers(Vector2(_poste.x, _sol_y - hauteur_lances + sin(_bob * 2.2) * flottement), delta)
	if check_tracking():
		flip_toward(target.global_position.x)
	if _phase == 0:
		if _t >= annonce_lances:
			# toute l'arène, d'un mur à l'autre
			_phase = 1
			lances.largeur = 2.0 * _demi_arene
			lances.global_position = Vector2(_centre_x, _sol_y - 60.0)
			lances.lancer()
	elif not lances.en_cours():
		goto_state(States.IDLE)

func lances_exit() -> void:
	animator.lever_bras(false)


func _on_vague_annoncee(_numero: int) -> void:
	if current_state == States.LANCES or current_state == States.PLUIE:
		animator.lever_bras(true)


## les lances sortent : c'est son claquement de doigts
func _on_vague_sortie(_numero: int) -> void:
	if current_state == States.LANCES or current_state == States.PLUIE:
		animator.claquer()


# --- VENT : à la hauteur du héros, d'un côté, un vent le tire vers elle ; s'il
# arrive trop près, elle sonne sa cloche ---
func vent_enter() -> void:
	animator.play("vent")
	animator.voler(0.6)
	_t = 0.0
	_phase = 0
	_cloche_a_porte = false
	_sonneries = 0
	# de quel côté du héros : celui du mur le plus proche de lui, s'il y a la
	# place — il fuit alors vers le milieu de l'arène ; sinon l'autre
	var x_heros := global_position.x
	if check_tracking():
		x_heros = target.global_position.x
	var vers_mur := signf(x_heros - _centre_x)
	if vers_mur == 0.0:
		vers_mur = 1.0 if randf() < 0.5 else -1.0
	var place := _demi_arene - MARGE_MUR * taille - absf(x_heros - _centre_x)
	_cote = vers_mur if place >= distance_vent else -vers_mur
	_regler_le_vent()

func vent_execute(delta: float) -> void:
	_t += delta
	_bob += delta
	var bas := _sol_y - hauteur_vent
	if _phase == 0:
		# elle se met en place, à côté de lui
		var x := global_position.x
		if check_tracking():
			x = _dans_l_arene(target.global_position.x + _cote * distance_vent)
			flip_toward(target.global_position.x)
		_voler_vers(Vector2(x, _sans_ecraser(bas)), delta)
		var en_place := absf(global_position.x - x) < 70.0 and absf(global_position.y - bas) < 40.0
		if en_place or _t >= PLACEMENT_VENT_MAX:
			# elle ne se retourne plus : le vent couvre le côté où elle regarde
			_phase = 1
			_t = 0.0
			_poste = Vector2(global_position.x, bas)
			_regard = float(last_direction)
			animator.vrombir(true)
			_vent_voulu = BRISE
		return
	_voler_vers(Vector2(_poste.x, _sans_ecraser(_poste.y + sin(_bob * 2.2) * flottement * 0.5)), delta)
	if _phase == 1:
		# la brise prévient
		if _t >= annonce_vent:
			_phase = 2
			_t = 0.0
			_vent_voulu = 1.0
	elif _phase == 2:
		# le vent tire
		_tirer(minf(_t / MONTEE_DU_VENT, 1.0))
		if _trop_pres():
			_phase = 3
			_t = 0.0
			_sonneries = 1
			animator.sonner()
			attack_power = degats_cloche
			_cloche.crier(DUREE_SON)
		elif _t >= duree_vent:
			goto_state(States.RETOUR)
	else:
		# la cloche sonne, et le vent tire toujours
		_tirer(1.0)
		if not _cloche_a_porte:
			_cloche_frapper()
		if _t >= DUREE_SON + APRES_LE_SON:
			if _sonneries < cloches_max and _trop_pres():
				# toujours contre elle : elle sonne encore
				_t = 0.0
				_sonneries += 1
				_cloche_a_porte = false
				animator.sonner()
				_cloche.crier(DUREE_SON)
			else:
				goto_state(States.RETOUR)

func vent_exit() -> void:
	# fini, ou coupé (sonnée, tuée…) : le vent tombe, la cloche se tait
	_vent_voulu = 0.0
	animator.vrombir(false)
	_cloche.arreter()


## La hauteur où elle a le droit d'aller : `voulue`, sauf si le héros est à
## moins de `ecart` px d'elle en largeur — alors pas plus bas que
## HAUTEUR_SUR_LE_HEROS, elle ne se pose pas sur sa tête
func _sans_ecraser(voulue: float, ecart := ECART_POUR_DESCENDRE) -> float:
	if check_tracking() and absf(target.global_position.x - global_position.x) < ecart:
		return minf(voulue, _sol_y - maxf(hauteur_repos, HAUTEUR_SUR_LE_HEROS))
	return voulue


## Le dessin du vent et les ronds de la cloche, posés sur elle (dans POINT : ils
## suivent son retournement)
func _poser_vent_et_cloche() -> void:
	_cloche = CRI_SCENE.instantiate()
	_cloche.name = "Cloche"
	_cloche.apercu = false
	_cloche.demo_boucle = false
	_cloche.rayon = portee_cloche * RAYON_PAR_PORTEE
	_cloche.vitesse = vitesse_cloche
	_cloche.couleur = couleur_cloche
	_cloche.position = animator.place_cloche()
	point.add_child(_cloche)
	_vent_rect = ColorRect.new()
	_vent_mat = ShaderMaterial.new()
	_vent_mat.shader = VENT_SHADER
	_vent_rect.material = _vent_mat
	_vent_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vent_rect.visible = false
	point.add_child(_vent_rect)


## Le rectangle du vent : il part d'elle, du côté où elle regarde, son bas au sol
func _regler_le_vent() -> void:
	_vent_rect.size = Vector2(portee_vent, HAUT_VENT)
	_vent_rect.position = Vector2(0.0, hauteur_vent + 8.0 - HAUT_VENT)
	_vent_mat.set_shader_parameter("taille", _vent_rect.size)
	_vent_mat.set_shader_parameter("bouche", Vector2(0.0, _cloche.position.y - _vent_rect.position.y))
	_vent_mat.set_shader_parameter("graine", float(randi_range(1, 900)))
	_vent_t = 0.0


## Le vent tire vers elle tout ce qui se laisse souffler, du côté qu'il couvre
## (`montee` : de 0 à 1, sa force qui arrive)
func _tirer(montee: float) -> void:
	for corps in get_tree().get_nodes_in_group("Player"):
		if not (corps is Node2D) or not corps.has_method("souffler"):
			continue
		var ecart: float = (corps.global_position.x - global_position.x) * _regard
		var haut: float = _sol_y - corps.global_position.y
		if ecart <= 0.0 or ecart > portee_vent or haut < -60.0 or haut > HAUT_VENT:
			continue
		corps.souffler(Vector2(-_regard * force_vent * montee, 0.0))


## Sa cible est-elle arrivée contre elle ?
func _trop_pres() -> bool:
	if not check_tracking():
		return false
	var ecart := absf(target.global_position.x - global_position.x)
	return ecart < declenche_cloche and _sol_y - target.global_position.y < HAUT_VENT


## La cloche sonne : ses ronds blessent le héros dès qu'ils l'atteignent (jusqu'à
## `portee_cloche`), sans mur entre eux. Une seule fois par sonnerie : tant que le
## coup n'a pas PORTÉ (une roulade, un bouclier…), il n'est pas compté.
func _cloche_frapper() -> void:
	var ronds: Vector2 = _cloche.couronne()
	var front: float = minf(ronds.y, portee_cloche)
	if front <= 0.0:
		return
	var j := get_tree().get_first_node_in_group("Player") as PhysicsBody2D
	if j == null or not est_ennemi(j):
		return
	var depuis: Vector2 = _cloche.global_position
	var c: Vector2 = j.centre_corps()
	var d := c.distance_to(depuis)
	if d > front or d < ronds.x or not _a_vue(depuis, c):
		return
	var vie_avant: int = Player.hp
	var etat_avant: int = j.current_state
	infliger(j, global_position.x, "cloche:" + name)
	if Player.hp < vie_avant or (j.current_state == j.States.HIT and etat_avant != j.States.HIT):
		_cloche_a_porte = true


## les ronds ne passent pas les murs (couche 2 : les décors)
func _a_vue(de: Vector2, vers: Vector2) -> bool:
	var requete := PhysicsRayQueryParameters2D.create(de, vers, 2)
	return get_world_2d().direct_space_state.intersect_ray(requete).is_empty()


# --- REGARD (phase 2) : ses yeux visent le héros, le fil se fige, le rayon part ---
func regard_enter() -> void:
	animator.play("regard")
	animator.voler(0.5)
	animator.eveiller(true)
	_t = 0.0
	_poste = Vector2(global_position.x, _sol_y - hauteur_repos)
	if check_tracking():
		flip_toward(target.global_position.x)
	regard.global_position = point.to_global(animator.place_yeux())
	regard.lancer()

func regard_execute(delta: float) -> void:
	_t += delta
	_bob += delta
	# elle se tient immobile : le fil part de ses yeux, qui ne bougent pas
	_voler_vers(_poste, delta)
	if not regard.en_cours() and not rafale.en_cours():
		goto_state(States.IDLE)

func regard_exit() -> void:
	regard.arreter()
	animator.eveiller(_p2)


## un nouveau regard : elle se tourne vers le héros
func _on_regard_vise(_numero: int) -> void:
	if current_state == States.REGARD and check_tracking():
		flip_toward(target.global_position.x)


## le rayon part : un coup d'aile, et une rafale basse part de ses ailes
func _on_regard_tir(_numero: int) -> void:
	if current_state == States.REGARD and p2_regard_rafale:
		animator.coup_d_aile()
		rafale.position = Vector2(0.0, -animator.hauteur_poitrine())
		rafale.lancer_seule(false)


# --- RETOUR : après une attaque qui l'a éloignée, elle revient se poser près du
# héros, du côté du milieu de l'arène ---
func retour_enter() -> void:
	animator.play("idle")
	animator.voler(0.6 if _p2 else 0.4)
	animator.armer_ailes(false)
	animator.lever_bras(false)
	_t = 0.0
	_poste = Vector2(_place_de_repos(), _sol_y - hauteur_repos)

func retour_execute(delta: float) -> void:
	_t += delta
	_bob += delta
	_voler_vers(Vector2(_poste.x, _sans_ecraser(_poste.y, ECART_SOUS_ELLE)), delta, vitesse_retour)
	if check_tracking():
		flip_toward(target.global_position.x)
	if absf(global_position.x - _poste.x) < 60.0 or _t >= RETOUR_MAX:
		goto_state(States.IDLE)


# --- RAFALE : elle prend un peu de hauteur, lève les ailes, et chaque battement
# envoie une rafale de pétales des deux côtés, basse ou haute ---
func rafale_enter() -> void:
	animator.play("rafale")
	animator.voler(0.5)
	animator.armer_ailes(true)
	_t = 0.0
	_phase = 0
	_poste = Vector2(_dans_l_arene(global_position.x), global_position.y)
	# pendant les rafales, la toucher ne blesse pas : une rafale basse oblige à
	# sauter, et elle-même descend au ras du sol
	if not _contact_coupe:
		_contact_d_avant = contact_damage
		_contact_coupe = true
	contact_damage = 0

func rafale_execute(delta: float) -> void:
	_t += delta
	_bob += delta
	_voler_vers(_poste + Vector2(0.0, sin(_bob * 2.2) * flottement * 0.3), delta, vitesse_rafale)
	if check_tracking():
		flip_toward(target.global_position.x)
	if _phase == 0:
		if _t >= annonce_rafale:
			# les rafales partent d'elle, des deux côtés
			_phase = 1
			rafale.position = Vector2(0.0, -animator.hauteur_poitrine())
			rafale.lancer()
	elif not rafale.en_cours():
		goto_state(States.IDLE)

func rafale_exit() -> void:
	animator.armer_ailes(false)


## une rafale s'annonce : elle va se mettre à sa hauteur, les ailes levées
func _on_rafale_annoncee(_numero: int, haute: bool) -> void:
	if current_state == States.RAFALE:
		_poste.y = _sol_y - (hauteur_rafale_haute if haute else hauteur_rafale_basse)
		animator.armer_ailes(true)


## la rafale part : c'est son battement d'ailes
func _on_rafale_partie(_numero: int, _haute: bool) -> void:
	if current_state == States.RAFALE:
		animator.coup_d_aile()


# --- EVEIL : la phase 2 commence — ses attaques s'arrêtent, elle monte,
# intouchable, sa cloche sonne, ses yeux s'ouvrent ; puis tout se resserre ---
func eveil_enter() -> void:
	_eveillee = true
	petales.arreter()
	lances.arreter()
	lances_pluie.arreter()
	rafale.arreter()
	regard.arreter()
	invulnerable = true
	_t = 0.0
	_poste = Vector2(_dans_l_arene(global_position.x), _sol_y - hauteur_pluie)
	animator.play("eveil")
	animator.voler(1.0)
	animator.armer_ailes(true)
	animator.lever_bras(false)
	animator.sonner()
	animator.eveiller(true)
	_cloche.crier(DUREE_SON)        # (ses ronds, sans dégât : un glas)
	phase_2.emit()

func eveil_execute(delta: float) -> void:
	_t += delta
	_bob += delta
	_voler_vers(_poste + Vector2(0.0, sin(_bob * 2.2) * flottement * 0.5), delta)
	if check_tracking():
		flip_toward(target.global_position.x)
	if _t >= p2_eveil_duree:
		goto_state(States.IDLE)

func eveil_exit() -> void:
	# la phase 2 : les réglages se resserrent, sur ceux de la phase 1
	invulnerable = false
	_p2 = true
	animator.armer_ailes(false)
	animator.agiter(true)
	rafale.rafales += p2_rafales_en_plus
	lances.rythme *= p2_lances_rythme


# --- DEAD : ses attaques s'arrêtent, elle tombe, et s'affaisse en touchant le sol ---
func dead_enter() -> void:
	invulnerable = false
	petales.arreter()
	lances.arreter()
	lances_pluie.arreter()
	rafale.arreter()
	regard.arreter()
	animator.mourir()
	volant = false
	velocity = Vector2.ZERO
	vaincue.emit()

func dead_execute(delta: float) -> void:
	velocity.x = 0.0
	if is_on_floor():
		velocity.y = 0.0
		if not _au_sol:
			_au_sol = true
			animator.toucher_le_sol()
	else:
		velocity.y = minf(velocity.y + gravity * delta, CHUTE_MAX)


# ============================================================
#  LA DÉMO (F6) : un sol, deux murs, une cible qui va et vient
# ============================================================

func _preparer_la_demo() -> void:
	var ecran := get_viewport_rect().size
	var sol := ecran.y * 0.86
	var fond := ColorRect.new()
	fond.color = Color(0.27, 0.36, 0.58)
	fond.size = ecran
	fond.z_index = -10
	get_parent().add_child.call_deferred(fond)
	for r: Rect2 in [Rect2(0.0, sol, ecran.x, ecran.y - sol), Rect2(0.0, 0.0, 40.0, sol),
			Rect2(ecran.x - 40.0, 0.0, 40.0, sol)]:
		var mur := StaticBody2D.new()
		mur.collision_layer = 3
		mur.position = r.get_center()
		var forme := CollisionShape2D.new()
		var boite := RectangleShape2D.new()
		boite.size = r.size
		forme.shape = boite
		mur.add_child(forme)
		var vue := ColorRect.new()
		vue.color = Color(0.17, 0.22, 0.38)
		vue.size = r.size
		vue.position = -r.size * 0.5
		mur.add_child(vue)
		get_parent().add_child.call_deferred(mur)
	global_position = Vector2(ecran.x * 0.5, sol - hauteur_repos)
	initial_position = global_position
	hauteur_pluie = minf(hauteur_pluie, sol * 0.42)
	distance_vent = minf(distance_vent, ecran.x * 0.3)      # (qu'elle reste à l'écran)
	# la cible : de la taille du héros, elle marche d'un mur à l'autre
	_cible_demo = Node2D.new()
	var corps := ColorRect.new()
	corps.color = Color(0.9, 0.9, 0.95)
	corps.size = Vector2(46.0, 126.0)
	corps.position = Vector2(-23.0, -126.0)
	_cible_demo.add_child(corps)
	_cible_demo.position = Vector2(ecran.x * 0.5, sol)
	get_parent().add_child.call_deferred(_cible_demo)


func _animer_la_demo(delta: float) -> void:
	if _cible_demo == null or not _cible_demo.is_inside_tree():
		return
	_demo_t += delta
	var ecran := get_viewport_rect().size
	# (elle reste au milieu : ses ailes sont larges, l'écran ne l'est guère plus)
	var x := ecran.x * (0.5 + 0.17 * sin(_demo_t * 0.6))
	# son vent tire la cible vers elle (elle ne sait pas courir)
	if current_state == States.VENT and _phase == 2:
		_demo_tire = move_toward(_demo_tire, global_position.x - x, force_vent * 0.7 * delta)
	else:
		_demo_tire = move_toward(_demo_tire, 0.0, 600.0 * delta)
	_cible_demo.position.x = x + _demo_tire
	if target == null and _mesuree:
		target = _cible_demo
