extends Node

# Dernier checkpoint croisé : position + scène — un NodePath ne survivrait
# pas au rechargement de la scène après la mort (ancien bug de respawn)
var last_checkpoint_pos := Vector2.ZERO
var last_checkpoint_scene := ""
var has_checkpoint := false
var last_door_id: int = -1
# Élan à conserver en traversant un passage en courant : capturé par
# passage.gd, restitué par spawnplayer de l'autre côté (une seule fois)
var transition_velocity := Vector2.ZERO
var transition_direction: int = 1
var has_transition_momentum := false

var blood := 0
# La vie est comptée en CŒURS : 1 dégât = 1 cœur perdu.
# (garder hp/MAX_HP synchronisés avec max_hearts)
var hp := 5
var MAX_HP := 5
var max_hearts := 5  # nombre de cœurs affichés
# vrai après le premier spawn : l'export MAX_HEARTS du player n'est que la
# valeur de DÉPART, ensuite l'autoload fait foi (cœurs ramassés compris)
var hearts_initialized := false
# Registre des cœurs déjà ramassés (clé = scène niveau + position) : un
# pickup présent ici se détruit à son chargement — sinon il renaîtrait à
# chaque respawn (cœurs infinis). Vit le temps de la session ; à brancher
# sur la vraie sauvegarde disque quand elle existera.
var coeurs_ramasses := {}
# --- Réserve de soin BLOODHEAL : N barres côte à côte, chacune = un soin ---
## capacité d'UNE barre = le coût d'un soin (HEAL_COST côté player : les deux doivent rester égaux)
const BARRE_BLOODHEAL := 100
## plafond de barres possibles (règle-le ici)
const MAX_BARRES_BLOODHEAL := 4
## barres possédées au départ d'une partie (1..MAX_BARRES_BLOODHEAL)
const BARRES_BLOODHEAL_DEPART := 2
var nb_barres_bloodheal := BARRES_BLOODHEAL_DEPART
var bloodheal := 0  # réserve courante, remplie COUP PAR COUP, de gauche à droite
## bloodheal rendu par coup au corps à corps qui porte : 15 % d'une barre
const BLOODHEAL_PAR_COUP := 15
var MAX_BLOODHEAL := BARRES_BLOODHEAL_DEPART * BARRE_BLOODHEAL  # dérivé : nb_barres × BARRE, ne pas régler à la main

# --- TALISMANS : ce que le joueur a découvert, et ce qu'il porte ---
# Le catalogue (la liste de tous les talismans du jeu) est dans
# SCRIPT/TALISMAN/talismans.gd ; le menu START, onglet Talismans, montre et
# modifie ce qui suit. Vit le temps de la session, comme les cœurs ramassés : à
# brancher sur la vraie sauvegarde disque quand elle existera.
const Talismans := preload("res://SCRIPT/TALISMAN/talismans.gd")
## émis à chaque découverte, équipement ou retrait : le menu se redessine, et le
## gameplay pourra s'y brancher pour appliquer les effets
signal talismans_changes
## un monstre vient de mourir, et qui l'a tué (null : un piège, une source
## anonyme) — émis par BASE_IA ; le joueur y branche ses talismans (Essaim)
signal monstre_tue(monstre: Node, attaquant: Node)
## TALISMAN « ESSAIM » : combien de chauves-souris de sang suivent le joueur.
## Tenu par elles-mêmes (SCRIPT/SHADER/chauve_souris_sang.gd : une de plus à la
## naissance, une de moins quand elle mord ou s'en va). Un changement de
## tableau les détruit SANS les décompter : le joueur du tableau suivant relâche
## ce compte autour de lui (player.gd, `_essaim_reprendre`). Remis à zéro à la
## mort et en nouvelle partie.
var essaim_en_vol := 0
## nombre d'emplacements où l'on équipe un talisman (règle-le ici)
const EMPLACEMENTS_TALISMAN := 3
var talismans_decouverts := {}             # id → true
var talismans_equipes: Array[String] = []  # un id par emplacement, "" = libre


func _ready() -> void:
	_talismans_page_blanche()


## Réinitialise TOUT l'état de partie — appelé par PLAY au menu principal.
## Nouvelle partie = page blanche : cœurs ramassés compris.
func reset_partie() -> void:
	hearts_initialized = false  # le prochain spawn relira l'export du player
	coeurs_ramasses.clear()
	_talismans_page_blanche()
	hp = 999999  # clampé au max par le _enter_tree du player
	blood = 0
	bloodheal = 0
	nb_barres_bloodheal = BARRES_BLOODHEAL_DEPART
	MAX_BLOODHEAL = nb_barres_bloodheal * BARRE_BLOODHEAL
	has_checkpoint = false
	last_checkpoint_scene = ""
	last_checkpoint_pos = Vector2.ZERO
	last_door_id = -1
	has_transition_momentum = false
	second_souffle_attente = 0.0
	essaim_en_vol = 0


func changement_de_vie(amount: int) -> void:
	var old := hp
	hp = clamp(hp + amount, 0, MAX_HP)
	var delta := hp - old
	var bars := get_tree().get_nodes_in_group("UI_Health")
	if !bars.is_empty():
		bars[0].emit_signal("health_request", float(delta))

func changement_de_bloodheal(amount: int) -> void:
	var old := bloodheal
	bloodheal = clamp(bloodheal + amount, 0, MAX_BLOODHEAL)
	var delta := bloodheal - old
	var bars := get_tree().get_nodes_in_group("UI_Bloodheal")
	if !bars.is_empty():
		bars[0].emit_signal("bloodheal_request", float(delta))

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


# --- MAX HP ---
func set_max_hp(new_max: int) -> void:
	new_max = max(1, new_max)
	if new_max == MAX_HP:
		return
	var old_hp := hp
	MAX_HP = new_max
	max_hearts = MAX_HP  # la rangée de cœurs affichée suit toujours le max
	# Ne PAS rééchelonner : on garde la valeur et on clamp si besoin
	hp = min(old_hp, MAX_HP)

	var ui := get_tree().get_nodes_in_group("UI_Health")
	if not ui.is_empty():
		ui[0].emit_signal("bar_max_request", "hp", float(MAX_HP))  # pas de health_request

func add_max_hp(delta: int) -> void:
	set_max_hp(MAX_HP + delta)  # <-- aucune mise à l’échelle

# --- BARRES DE BLOODHEAL (capacité max = nombre de barres × un soin) ---
## Fixe le nombre de barres (1..MAX_BARRES_BLOODHEAL) ; la capacité suit et
## le HUD reconstruit la rangée. La réserve courante est conservée (clampée).
func set_nb_barres_bloodheal(n: int) -> void:
	n = clampi(n, 1, MAX_BARRES_BLOODHEAL)
	var new_max := n * BARRE_BLOODHEAL
	if n == nb_barres_bloodheal and new_max == MAX_BLOODHEAL:
		return
	nb_barres_bloodheal = n
	MAX_BLOODHEAL = new_max
	bloodheal = min(bloodheal, MAX_BLOODHEAL)

	var ui := get_tree().get_nodes_in_group("UI_Bloodheal")
	if not ui.is_empty():
		ui[0].emit_signal("bar_max_request", "bloodheal", float(MAX_BLOODHEAL))

## +1 barre (pickup, récompense…)
func add_barre_bloodheal(delta: int = 1) -> void:
	set_nb_barres_bloodheal(nb_barres_bloodheal + delta)

## compatibilité : une capacité brute est arrondie au nombre de barres entier
func set_max_bloodheal(new_max: int) -> void:
	set_nb_barres_bloodheal(int(round(float(new_max) / float(BARRE_BLOODHEAL))))

func add_max_bloodheal(delta: int) -> void:
	set_max_bloodheal(MAX_BLOODHEAL + delta)


# ---------- TALISMANS ----------

## état de départ : rien d'équipé, seuls les talismans « de départ » du
## catalogue sont découverts
func _talismans_page_blanche() -> void:
	talismans_decouverts.clear()
	for id in Talismans.DECOUVERTS_AU_DEPART:
		if not Talismans.trouver(id).is_empty():
			talismans_decouverts[id] = true
	talismans_equipes.resize(EMPLACEMENTS_TALISMAN)
	talismans_equipes.fill("")
	talismans_changes.emit()


## Le joueur trouve un talisman : il apparaît dans la collection du menu.
## Retourne true si c'est une découverte (false : id inconnu ou déjà trouvé).
func decouvrir_talisman(id: String) -> bool:
	if Talismans.trouver(id).is_empty() or talismans_decouverts.has(id):
		return false
	talismans_decouverts[id] = true
	talismans_changes.emit()
	return true


func talisman_decouvert(id: String) -> bool:
	return talismans_decouverts.has(id)


## true si ce talisman est porté : c'est LA question à poser dans le gameplay
## pour appliquer son effet
func talisman_equipe(id: String) -> bool:
	return id != "" and talismans_equipes.has(id)


## Équipe un talisman découvert dans le premier emplacement libre. Retourne le
## numéro de l'emplacement (0 = le premier), ou -1 si c'est refusé : pas
## découvert, déjà porté, ou plus d'emplacement libre.
func equiper_talisman(id: String) -> int:
	if not talisman_decouvert(id) or talisman_equipe(id):
		return -1
	var libre := talismans_equipes.find("")
	if libre == -1:
		return -1
	talismans_equipes[libre] = id
	talismans_changes.emit()
	return libre


## Retire un talisman porté : son emplacement redevient libre (les autres ne
## bougent pas). Retourne false s'il n'était pas porté.
func retirer_talisman(id: String) -> bool:
	if not talisman_equipe(id):
		return false
	talismans_equipes[talismans_equipes.find(id)] = ""
	talismans_changes.emit()
	return true


## La somme, sur les talismans PORTÉS, d'une clé chiffrée du catalogue
## (`degats_pourcent`, `esquive_pourcent`, `blood_pourcent`…) : c'est ainsi que
## tout bonus chiffré d'un talisman arrive dans le jeu, et que deux talismans
## qui portent la même clé s'additionnent.
func bonus_talismans(cle: String) -> float:
	var total := 0.0
	for id in talismans_equipes:
		if id == "":
			continue
		total += float(Talismans.trouver(id).get(cle, 0))
	return total


## Le bonus de dégâts des COUPS D'ÉPÉE apporté par les talismans portés, en
## pour cent : la somme des `degats_pourcent` du catalogue (10 = +10 %). Un
## POURCENTAGE, jamais un ajout fixe (Kaoru, 30 sept. 2026) : quand les dégâts
## de base du joueur monteront, le bonus suivra.
## Plus, AU DERNIER CŒUR seulement, la somme des `degats_pourcent_dernier_coeur`
## (talisman « Frénésie » : +50 %, 1er oct. 2026) — les deux s'additionnent.
func bonus_degats_pourcent() -> float:
	var total := bonus_talismans("degats_pourcent")
	if frenesie_active():
		total += bonus_talismans("degats_pourcent_dernier_coeur")
	if sang_plein_actif():
		total += bonus_talismans("degats_pourcent_jauge_pleine")
	return total


## SANG PLEIN (talisman « Sang plein », 1er oct. 2026) : vrai quand un bonus
## « jauge pleine » est porté ET que la jauge de sang (bloodheal) est pleine —
## se soigner la vide et coupe le bonus : le dilemme est voulu. Des STATS
## seulement, comme la Frénésie (pas d'effet à l'écran).
func sang_plein_actif() -> bool:
	return bloodheal >= MAX_BLOODHEAL and bonus_talismans("degats_pourcent_jauge_pleine") > 0.0


## Vrai quand un bonus « dernier cœur » est porté ET qu'il ne reste qu'un cœur.
## Des STATS seulement, sans effet à l'écran : des veines au bord de l'écran et
## un liseré rouge ont été essayés puis retirés (Kaoru, 1er oct. 2026 : « pas
## nécessaire, pas beau, plus stressant pour le joueur »).
func frenesie_active() -> bool:
	return hp == 1 and bonus_talismans("degats_pourcent_dernier_coeur") > 0.0


## Ce par quoi multiplier les dégâts de base d'un coup d'épée (1.1 = +10 %),
## multiplicateur de TOUS les dégâts infligés compris (Canon de verre).
## À appliquer au moment du coup : `roundi(base * Player.multiplicateur_degats())`.
func multiplicateur_degats() -> float:
	return (1.0 + bonus_degats_pourcent() / 100.0) * multiplicateur_infliges()


## Le PRODUIT, sur les talismans portés, d'une clé multiplicative du catalogue
## (1 si aucun ne la porte) : deux talismans qui doublent font ×4.
func produit_talismans(cle: String) -> float:
	var total := 1.0
	for id in talismans_equipes:
		if id == "":
			continue
		var v = Talismans.trouver(id).get(cle, null)
		if v != null:
			total *= float(v)
	return total


## Ce par quoi multiplier TOUS les dégâts que le joueur INFLIGE — épée (via
## `multiplicateur_degats`, donc aussi les épines et l'éclair qui en découlent),
## boule et tornade de sang, brume du sillage (talisman « Canon de verre » : ×2)
func multiplicateur_infliges() -> float:
	return produit_talismans("degats_infliges_multiplicateur")


## Ce par quoi multiplier TOUS les dégâts que le joueur REÇOIT, d'un ennemi
## comme du décor (Canon de verre : ×2 → un coup coûte deux cœurs)
func multiplicateur_recus() -> float:
	return produit_talismans("degats_recus_multiplicateur")


## SECOND SOUFFLE (talisman « souffle », 1er oct. 2026) : secondes avant qu'il
## puisse resservir (0 = prêt). Il vit ICI et pas dans le joueur, qui est recréé
## à chaque respawn ; remis à 0 au respawn, à chaque checkpoint touché et en
## nouvelle partie. Le joueur le décompte (player.gd, `_second_souffle`).
var second_souffle_attente := 0.0


## La chance qu'un coup d'ennemi soit ignoré, de 0 à 1 (talisman « Pas de
## côté » : 0.2). Tirée au moment du coup par le joueur (`_esquive_tente`).
func chance_esquive() -> float:
	return clampf(bonus_talismans("esquive_pourcent") / 100.0, 0.0, 1.0)


## Ce par quoi multiplier une RÉCOLTE de sang (talisman « Soif de sang » :
## 1.1 = +10 %). Un pourcentage de la récolte, pas un ajout fixe.
func multiplicateur_blood() -> float:
	return 1.0 + bonus_talismans("blood_pourcent") / 100.0


## Une RÉCOLTE de sang arrive au joueur (la particule de sang d'un monstre
## mort) : créditée avec le bonus des talismans. Les autres mouvements du
## compteur (dépenses à venir) passent par `changement_de_blood`, sans bonus.
func recolter_blood(montant: int) -> void:
	changement_de_blood(roundi(montant * multiplicateur_blood()))


#Player.add_max_sang(50)        # +50 de capacité de jauge de sang (la barre s'allonge)
