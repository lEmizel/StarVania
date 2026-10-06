@tool
extends Node2D
## ============================================================================
## LANCES ROSES (5 oct. 2026) — attaque de boss. À son claquement de doigts,
## des lances de lumière sortent du sol dans toute une zone, EN RYTHME
## (lances_roses.gdshader). La zone est découpée en emplacements réguliers ; à
## chaque vague, une `part` d'entre eux tirée au hasard pousse une lance. LA
## RÉPONSE : se placer là où il n'y en a pas, et recommencer à chaque vague.
## Elle ne blesse que le héros.
##
## SANS BOSS (`automatique`, coché) : posée dans un niveau au milieu de la
## zone, sur le sol de la salle ou au-dessus, elle enchaîne ses salves toute
## seule tant que le héros est à portée (à peu près : à l'écran). Dans
## l'éditeur, un trait rose montre la largeur de la zone et des traits pâles
## les emplacements, sur toute la hauteur où le sol est cherché.
## AVEC UN BOSS : il met `automatique` à faux et appelle `lancer()` (`arreter()`
## coupe la salve net, s'il meurt). Les signaux
## `vague_annoncee(n)` et `vague_sortie(n)` donnent le rythme (le claquement de
## doigts tombe sur `vague_sortie`).
##
## Une salve = `vagues` vagues, une toutes les `rythme` s. Une vague :
##   • `annonce` s : chaque emplacement visé s'allume (étoile et trait de
##     lumière au sol, filet là où montera la lance) ; les autres restent
##     sombres — le temps d'aller se mettre dans un trou ;
##   • les lances jaillissent d'un trait et restent `tenue` s : qui en touche
##     une perd `damage` cœur(s) et il est repoussé de côté — une seule fois par
##     vague ;
##   • elles rentrent dans le sol, et ne blessent plus dès qu'elles rentrent.
## LE TIRAGE d'une vague, fait à son annonce : une lance EXACTEMENT SOUS LE
## HÉROS, là où il est à ce moment-là (`vise_le_heros` : tous les emplacements
## de la vague se décalent pour qu'un d'eux tombe sous ses pieds ; il doit
## bouger à chaque vague), une autre juste à côté de lui d'un côté au hasard
## (`ferme_un_cote` : il doit lire de quel côté partir), puis
## une `part` des emplacements en tout, au hasard, jamais plus
## de `suite_max` lances côte à côte (un mur trop large ne se quitterait pas à
## temps) — les deux bords de la zone comptent comme une lance, ce sont les
## murs de la salle : on ne reste pas coincé dans un coin — et jamais le même
## tirage deux fois de suite.
## Chaque lance sort du premier sol de son emplacement (couches 1 et 2), cherché
## de RECHERCHE_AU_DESSUS px au-dessus du nœud (il peut être posé à même le sol)
## jusqu'à `chute` px dessous ; sans sol, l'emplacement reste vide.
## La salve reste OÙ ELLE A ÉTÉ LANCÉE : le temps qu'elle dure, le nœud ne suit
## plus les déplacements de son parent ; à la fin il reprend sa place chez lui.
##
## POUR LA JUGER : ouvrir la scène et faire F6 (les salves s'enchaînent).
## L'allure (fer, hampe, couleurs, paillettes, halo) se règle sur le matériau du
## nœud Lances.
## ============================================================================

signal finie
## une vague s'annonce (ses emplacements s'allument) ; puis ses lances sortent
signal vague_annoncee(numero: int)
signal vague_sortie(numero: int)

## nombre d'emplacements au plus (le shader en prend autant) : une zone de
## 4800 px à 100 px d'écart
const MAX_CASES := 48
## la sortie et le retrait d'une lance (s)
const SORTIE := 0.08
const RETRAIT := 0.16
## les dernières paillettes s'éteignent en … s après la dernière vague
const DUREE_TRACE := 0.4
## en automatique, le héros est « à portée » jusqu'à … px au-delà de la zone
const PORTEE_MARGE := 500.0
## le sol est cherché à partir de … px au-dessus du nœud
const RECHERCHE_AU_DESSUS := 200.0

## sans boss pour la commander : les salves s'enchaînent toutes seules tant que
## le héros est à portée
@export var automatique := true
## en automatique : le silence entre deux salves (s)
@export var pause := 1.5
@export_group("La zone")
## largeur de la zone, centrée sur le nœud (px) : la salle
@export var largeur := 1600.0
## un emplacement de lance tous les … px (ils sont répartis pour remplir juste
## la largeur) ; assez serrés pour qu'on ne tienne pas entre deux lances voisines
@export var espacement := 100.0
## la part des emplacements d'où sort une lance, à chaque vague
@export_range(0.1, 0.9) var part := 0.5
## chaque vague vise le héros : ses emplacements se calent sur lui et une lance
## sort exactement sous ses pieds, il doit bouger à chaque fois ; décoché : tout
## est tiré au hasard, il peut se trouver dans un trou sans avoir bougé
@export var vise_le_heros := true
## … et une autre sort juste à côté de lui, d'un côté au hasard : il doit LIRE
## de quel côté partir (décoché : les deux côtés peuvent être libres)
@export var ferme_un_cote := true
@export_group("Le rythme")
## nombre de vagues d'une salve
@export var vagues := 4
## une vague toutes les … s
@export var rythme := 1.2
## les emplacements visés s'allument … s avant que les lances sortent
@export var annonce := 0.7
## les lances restent sorties … s
@export var tenue := 0.3
@export_group("Réglages fins")
## hauteur des lances (px)
@export var hauteur := 460.0
## jamais plus de … lances côte à côte (à 3, on ne sort plus du milieu du mur
## à temps sans réagir très vite)
@export var suite_max := 2
## jusqu'où l'on cherche le sol sous le nœud (px)
@export var chute := 1600.0
## secousse de la caméra à chaque sortie (0 : aucune)
@export var secousse := 3.0
@export_group("Dégâts")
@export var damage := 1
## demi-largeur de ce qui blesse dans une lance (px)
@export var demi_largeur := 24.0
@export_group("")
## lancée seule (F6) : les salves s'enchaînent
@export var demo_boucle := true

@onready var _rect: ColorRect = $Lances

var _t := 0.0
var _active := false
var _graine := 0
var _sols := PackedFloat32Array()         # hauteur du sol sous chaque emplacement (> chute : aucun)
var _base_x := 0.0                        # abscisse du premier emplacement
var _pas := 100.0                         # l'écart réel entre deux emplacements
var _motifs: Array[PackedByteArray] = []  # par vague ANNONCÉE : 1 = une lance sort de cet emplacement
var _nb_vagues := 4                       # le nombre de vagues de cette salve
var _decals := PackedFloat32Array()       # par vague annoncée : le décalage de ses emplacements (px)
var _decal_tire := 0.0                    # celui du dernier tirage
var _annoncees := PackedByteArray()       # par vague : son signal d'annonce est parti
var _sorties := PackedByteArray()         # par vague : ses lances sont sorties
var _touche := PackedByteArray()          # par vague : elle a déjà pris son cœur
var _ancre := Vector2.ZERO                # sa place chez son parent, le temps d'une salve
var _detache := false                     # il ne suit plus son parent (salve en cours)
var _demo := false
var _attente := 0.0                       # seule : le silence depuis la dernière salve


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_rect.visible = false
	_demo = demo_boucle and get_parent() == get_tree().root
	if _demo:
		var ecran := get_viewport_rect().size
		position = Vector2(ecran.x * 0.5, ecran.y * 0.3)
		largeur = minf(largeur, ecran.x - 240.0)
		lancer()


## une salve, là où est le nœud
func lancer() -> void:
	_graine = randi() % 1000
	_t = 0.0
	# la salve reste où elle est lancée, même si le parent bouge ensuite
	_rattacher()
	if get_parent() is Node2D:
		var ici := global_position
		_ancre = position
		_detache = true
		top_level = true
		global_position = ici
	# les emplacements, et le sol sous chacun
	var n := _nb_cases()
	_pas = largeur / n
	_base_x = -largeur * 0.5 + _pas * 0.5
	_sols = PackedFloat32Array()
	var plus_haut := INF
	var plus_bas := -INF
	for i in n:
		var sol := _sol_sous(_base_x + i * _pas)
		_sols.append(sol)
		if sol <= chute:
			plus_haut = minf(plus_haut, sol)
			plus_bas = maxf(plus_bas, sol)
	if not is_finite(plus_haut):
		plus_haut = 0.0
		plus_bas = 0.0
	# le tirage de la 1re vague ; les suivantes sont tirées à leur annonce : elles
	# visent le héros là où il est à ce moment-là
	_nb_vagues = maxi(vagues, 1)
	_motifs = []
	_decals = PackedFloat32Array()
	_motifs.append(_tirer(PackedByteArray()))
	_decals.append(_decal_tire)
	_annoncees = PackedByteArray()
	_annoncees.resize(_nb_vagues)
	_sorties = PackedByteArray()
	_sorties.resize(_nb_vagues)
	_touche = PackedByteArray()
	_touche.resize(_nb_vagues)
	# le rectangle : toute la zone, du sol le plus bas au-dessus des plus hautes lances
	var dessus := plus_haut - hauteur * 1.08 - 100.0
	_rect.position = Vector2(-largeur * 0.5 - 140.0, dessus)
	_rect.size = Vector2(largeur + 280.0, plus_bas + 60.0 - dessus)
	_active = true
	_rect.visible = true
	_appliquer()


func en_cours() -> bool:
	return _active


## la salve s'arrête net (le boss meurt) : plus de lances, plus de dégâts, et le
## signal `finie` ne part pas
func arreter() -> void:
	if not _active:
		return
	_active = false
	_rect.visible = false
	_rattacher()


## le nombre d'emplacements : de quoi remplir juste la largeur, à l'espacement près
func _nb_cases() -> int:
	return clampi(roundi(largeur / maxf(espacement, 30.0)), 1, MAX_CASES)


## la vie d'une vague, de son annonce à la fin de son retrait (s)
func _vie() -> float:
	return annonce + SORTIE + tenue + RETRAIT


## l'heure de l'annonce de la vague n°`k` (s depuis le lancer)
func _heure(k: int) -> float:
	return k * rythme


## le tirage d'une vague : quels emplacements poussent une lance (1). Celui du
## héros d'abord (`vise_le_heros`), puis une `part` de ceux qui ont un sol en
## tout, au hasard, jamais plus de `suite_max` côte à côte (les lances sont
## posées une à une, celles qui allongeraient trop une suite sont écartées : il
## peut en manquer une ou deux), et pas le tirage de la vague d'avant.
func _tirer(precedent: PackedByteArray) -> PackedByteArray:
	var n := _sols.size()
	var avec_sol: Array[int] = []
	for i in n:
		if _sols[i] <= chute:
			avec_sol.append(i)
	var combien := clampi(roundi(avec_sol.size() * part), 0, avec_sol.size())
	_decal_tire = 0.0
	var vise := _case_du_heros() if vise_le_heros else -1
	var limite := maxi(suite_max, 1)
	var motif := PackedByteArray()
	for essai in 8:
		motif = PackedByteArray()
		motif.resize(n)
		avec_sol.shuffle()
		var reste := combien
		# sous le héros d'abord ; puis les autres un à un, au hasard, en écartant
		# ceux qui feraient une suite trop longue (tirer tout d'un coup puis
		# vérifier ne tient plus dans une grande zone : sur 40 emplacements,
		# presque aucun tirage ne passe)
		if vise >= 0 and reste > 0:
			motif[vise] = 1
			reste -= 1
			# sa voisine, d'un côté au hasard (de l'autre si le mur ou la règle des
			# suites l'interdit)
			if ferme_un_cote and reste > 0:
				var cote := 1 if randf() < 0.5 else -1
				for j: int in [vise + cote, vise - cote]:
					if j < 0 or j >= n or _sols[j] > chute:
						continue
					motif[j] = 1
					if _plus_longue_suite(motif) > limite:
						motif[j] = 0
						continue
					reste -= 1
					break
		for i in avec_sol:
			if reste <= 0:
				break
			if motif[i] == 1:
				continue
			motif[i] = 1
			if _plus_longue_suite(motif) > limite:
				motif[i] = 0
			else:
				reste -= 1
		if motif != precedent:
			break
	return motif


## l'emplacement du héros (−1 : hors de la zone, ou pas de sol à cet endroit) ;
## pose aussi `_decal_tire` : de combien décaler les emplacements de la vague
## pour que celui-là tombe exactement sous lui (d'un demi-écart au plus)
func _case_du_heros() -> int:
	if _demo:
		return -1
	var pas := maxf(_pas, 1.0)
	for joueur in get_tree().get_nodes_in_group("Player"):
		if joueur is Node2D:
			var p := to_local((joueur as Node2D).global_position)
			var i := roundi((p.x - _base_x) / pas)
			if i >= 0 and i < _sols.size() and _sols[i] <= chute:
				_decal_tire = p.x - (_base_x + i * pas)
				return i
	return -1


## le plus grand nombre de lances côte à côte d'un tirage ; chaque bord de la
## zone compte comme une lance de plus
func _plus_longue_suite(motif: PackedByteArray) -> int:
	var pire := 0
	var suite := 1
	for v in motif:
		suite = suite + 1 if v == 1 else 0
		pire = maxi(pire, suite)
	return maxi(pire, suite + 1) if suite > 0 else pire


## le nœud reprend sa place chez son parent
func _rattacher() -> void:
	if _detache:
		_detache = false
		top_level = false
		position = _ancre


## le héros est-il assez près pour que les lances sortent ?
func _heros_a_portee() -> bool:
	for joueur in get_tree().get_nodes_in_group("Player"):
		if joueur is Node2D:
			var p := to_local((joueur as Node2D).global_position)
			if absf(p.x) <= largeur * 0.5 + PORTEE_MARGE and p.y >= -PORTEE_MARGE - RECHERCHE_AU_DESSUS and p.y <= chute + PORTEE_MARGE:
				return true
	return false


## la hauteur du premier sol à l'abscisse `x` (repère du nœud ; négative : le
## sol est au-dessus du nœud) ; plus que `chute` : aucun
func _sol_sous(x: float) -> float:
	if _demo:
		return get_viewport_rect().size.y * 0.86 - position.y
	var depuis := global_position + Vector2(x, -RECHERCHE_AU_DESSUS)
	var jusque := global_position + Vector2(x, chute)
	var exclus: Array[RID] = []
	for essai in 6:
		var rayon := PhysicsRayQueryParameters2D.create(depuis, jusque, 0b11)
		rayon.exclude = exclus
		var touche := get_world_2d().direct_space_state.intersect_ray(rayon)
		if touche.is_empty():
			break
		if touche["collider"] is CharacterBody2D:
			exclus.append(touche["rid"])
			continue
		return (touche["position"] as Vector2).y - global_position.y
	return chute + 1000.0


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active:
		return
	_t += delta
	for k in _nb_vagues:
		var tau := _t - _heure(k)
		if tau < 0.0:
			break
		if k >= _motifs.size():
			_motifs.append(_tirer(_motifs[k - 1]))      # elle s'annonce : son tirage
			_decals.append(_decal_tire)
		if _annoncees[k] == 0:
			_annoncees[k] = 1
			vague_annoncee.emit(k)
		if tau < annonce:
			continue
		if _sorties[k] == 0:
			_sorties[k] = 1
			vague_sortie.emit(k)
			_secouer()
		# sorties, elles blessent ; dès qu'elles rentrent, plus
		if not _demo and _touche[k] == 0 and tau < annonce + SORTIE + tenue:
			_blesser(k, tau)
	if _t >= _heure(_nb_vagues - 1) + _vie() + DUREE_TRACE:
		_active = false
		_rect.visible = false
		_rattacher()
		finie.emit()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()       # le repère suit les réglages
		return
	if _active:
		_appliquer()
	elif _demo or (automatique and _heros_a_portee()):
		# seule : une salve, un silence, la suivante
		_attente += delta
		if _attente >= pause:
			_attente = 0.0
			lancer()


## dans l'éditeur seulement, et en automatique (commandée par un boss, c'est lui
## qui la place) : la largeur de la zone, ses bords, et les emplacements des
## lances jusqu'où le sol est cherché
func _draw() -> void:
	if not Engine.is_editor_hint() or not automatique:
		return
	var rose := Color(1.0, 0.5, 0.8)
	var demi := largeur * 0.5
	draw_line(Vector2(-demi, 0.0), Vector2(demi, 0.0), Color(rose, 0.9), 3.0)
	draw_line(Vector2(-demi, -RECHERCHE_AU_DESSUS), Vector2(-demi, chute), Color(rose, 0.8), 3.0)
	draw_line(Vector2(demi, -RECHERCHE_AU_DESSUS), Vector2(demi, chute), Color(rose, 0.8), 3.0)
	var n := _nb_cases()
	var pas := largeur / n
	for i in n:
		var x := -demi + (i + 0.5) * pas
		draw_line(Vector2(x, -RECHERCHE_AU_DESSUS), Vector2(x, chute), Color(rose, 0.25), 2.0)


func _secouer() -> void:
	if secousse <= 0.0 or _demo:
		return
	var cam := get_tree().get_first_node_in_group("Camera")
	if cam != null and cam.has_method("shake"):
		cam.shake(secousse, 10.0)


## la hauteur d'une lance qui blesse, `tau` s après l'annonce de sa vague (un
## peu moins que la plus courte des lances dessinées : la pointe pardonne)
func _longueur(tau: float) -> float:
	var am := clampf((tau - annonce) / SORTIE, 0.0, 1.0)
	return hauteur * 0.82 * (1.0 - pow(1.0 - am, 3.0))


## qui touche une lance de la vague n°`k` perd un cœur et il est repoussé de
## côté ; une seule fois par vague
func _blesser(k: int, tau: float) -> void:
	var haut := _longueur(tau)
	if haut < 30.0:
		return
	var motif := _motifs[k]
	for joueur in get_tree().get_nodes_in_group("Player"):
		if not (joueur is Node2D) or not joueur.has_method("apply_environment_damage"):
			continue
		var p := to_local((joueur as Node2D).global_position)
		var depart := _base_x + _decals[k]
		var proche := roundi((p.x - depart) / maxf(_pas, 1.0))
		for i: int in [proche, proche - 1, proche + 1]:
			if i < 0 or i >= motif.size() or motif[i] == 0 or _sols[i] > chute:
				continue
			var x := depart + i * _pas
			if not _corps_dans(joueur, x, _sols[i], haut):
				continue
			var cote := signf(p.x - x)
			if cote == 0.0:
				cote = 1.0 if randf() < 0.5 else -1.0
			if joueur.apply_environment_damage(damage, Vector2(cote, -0.5).normalized()):
				_touche[k] = 1
			return


## le corps de `joueur` touche-t-il la lance d'abscisse `x`, sortie de `haut`
## px au-dessus du sol `sol` ?
func _corps_dans(joueur: Node, x: float, sol: float, haut: float) -> bool:
	var forme := RectangleShape2D.new()
	forme.size = Vector2(demi_largeur * 2.0, haut)
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = forme
	requete.transform = Transform2D(0.0, global_position + Vector2(x, sol - haut * 0.5))
	requete.collision_mask = 0b1011          # joueur et monstres, comme les pièges
	requete.collide_with_areas = false
	for resultat in get_world_2d().direct_space_state.intersect_shape(requete, 16):
		if resultat["collider"] == joueur:
			return true
	return false


func _appliquer() -> void:
	var mat := _rect.material as ShaderMaterial
	if mat == null:
		return
	# les vagues visibles (trois au plus : à un rythme serré, deux vagues et la
	# traîne de la précédente se chevauchent)
	var visibles: Array[int] = []
	for k in _motifs.size():
		var tau := _t - _heure(k)
		if tau >= 0.0 and tau < _vie() + DUREE_TRACE:
			visibles.append(k)
	while visibles.size() > 3:
		visibles.pop_front()
	var sols := PackedFloat32Array()
	sols.resize(MAX_CASES)
	for i in _sols.size():
		sols[i] = _sols[i]
	mat.set_shader_parameter("taille", _rect.size)
	mat.set_shader_parameter("origine", _rect.position)
	mat.set_shader_parameter("nb_cases", _sols.size())
	mat.set_shader_parameter("base_x", _base_x)
	mat.set_shader_parameter("pas", maxf(_pas, 1.0))
	mat.set_shader_parameter("sols", sols)
	mat.set_shader_parameter("chute", chute)
	for rang in 3:
		var lettre: String = ["a", "b", "c"][rang]
		var motif := PackedFloat32Array()
		motif.resize(MAX_CASES)
		var tau := -1.0
		var graine := 0.0
		if rang < visibles.size():
			var k := visibles[rang]
			for i in _motifs[k].size():
				motif[i] = float(_motifs[k][i])
			tau = _t - _heure(k)
			graine = float(_graine + k * 17)
			mat.set_shader_parameter("decal_" + lettre, _decals[k])
		mat.set_shader_parameter("motif_" + lettre, motif)
		mat.set_shader_parameter("temps_" + lettre, tau)
		mat.set_shader_parameter("graine_" + lettre, graine)
	mat.set_shader_parameter("annonce", annonce)
	mat.set_shader_parameter("sortie", SORTIE)
	mat.set_shader_parameter("tenue", tenue)
	mat.set_shader_parameter("retrait", RETRAIT)
	mat.set_shader_parameter("hauteur", hauteur)
