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


## Le bonus de dégâts des COUPS D'ÉPÉE apporté par les talismans portés, en
## pour cent : la somme des `degats_pourcent` du catalogue (10 = +10 %). Un
## POURCENTAGE, jamais un ajout fixe (Kaoru, 30 sept. 2026) : quand les dégâts
## de base du joueur monteront, le bonus suivra.
func bonus_degats_pourcent() -> float:
	var total := 0.0
	for id in talismans_equipes:
		if id == "":
			continue
		total += float(Talismans.trouver(id).get("degats_pourcent", 0))
	return total


## Ce par quoi multiplier les dégâts de base d'un coup d'épée (1.1 = +10 %).
## À appliquer au moment du coup : `roundi(base * Player.multiplicateur_degats())`.
func multiplicateur_degats() -> float:
	return 1.0 + bonus_degats_pourcent() / 100.0


#Player.add_max_sang(50)        # +50 de capacité de jauge de sang (la barre s'allonge)
