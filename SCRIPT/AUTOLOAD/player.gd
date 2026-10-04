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
# chaque respawn (cœurs infinis). Gardé dans la sauvegarde.
var coeurs_ramasses := {}
# Registre des ROUES À POINTES brisées (même clé que les cœurs) : une roue
# brisée ne revient QUE SI ON MEURT — vidé à la réapparition après la
# mort (player.gd, dead_input), pas en changeant de tableau.
var roues_brisees := {}
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
# modifie ce qui suit. Gardé dans la sauvegarde, comme les cœurs ramassés.
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
## LES ÂMES PERDUES À LA MORT (1er oct. 2026, comme dans les Souls) :
## le sang perdu en mourant attend en ESPRIT DE SANG dans le tableau où l'on est
## tombé (`ames_scene`), au-dessus du dernier sol où l'on a posé le pied
## (`ames_position`) — posé par le joueur à son arrivée dans ce tableau
## (player.gd, `_ames_poser`) ; le toucher les rend (`reprendre_ames`). Une
## nouvelle mort avant : l'ancien esprit est perdu pour de bon, le nouveau prend
## sa place (`ames_id` change : l'ancien s'éteint). Gardé dans la sauvegarde,
## comme les cœurs ramassés.
var ames_perdues := 0
## TALISMAN « CŒUR NOIR » (1er oct. 2026) : le joueur a-t-il son
## cœur noir (un seul, jamais plus), et dans combien de secondes il revient s'il
## l'a perdu (0 : dès que le talisman est porté). Les checkpoints et le respawn
## remettent l'attente à 0. Ici : le joueur est recréé à chaque tableau.
var coeur_noir := false
var coeur_noir_attente := 0.0
## TALISMAN « SANG NEUF » (2 oct. 2026) : vrai entre une mort et
## la réapparition qui la suit — le joueur qui naît alors sait qu'il revient
## d'une mort (player.gd, `_sang_neuf` : la jauge de soin se remplit).
var vient_de_mourir := false
## TALISMAN « COURONNE DU DÉFI » (1er oct. 2026) : un défi — tant
## qu'elle est portée on n'a plus qu'UN cœur, et tous les autres talismans sont
## retirés et VERROUILLÉS (`talisman_verrouille`). `defi_max_hp` garde le vrai
## nombre de cœurs pendant ce temps (0 : pas de défi) ; un cœur ramassé pendant
## le défi s'y ajoute (`add_max_hp`) : on le retrouve en ôtant la couronne. Les
## cœurs rendus en l'ôtant sont vides (pas de soin gratuit).
const TALISMAN_DEFI := "defi"
var defi_max_hp := 0
var ames_scene := ""
var ames_position := Vector2.ZERO
var ames_id := 0
## nombre d'emplacements où l'on équipe un talisman (règle-le ici)
const EMPLACEMENTS_TALISMAN := 3
var talismans_decouverts := {}             # id → true
var talismans_equipes: Array[String] = []  # un id par emplacement, "" = libre


func _ready() -> void:
	_talismans_page_blanche()
	# trouver, équiper ou retirer un talisman : la partie est écrite aussitôt
	# (branché APRÈS la page blanche : au démarrage il n'y a rien à écrire)
	talismans_changes.connect(sauvegarder)


func _notification(what: int) -> void:
	# la fenêtre se ferme (croix, Alt+F4) : la partie est écrite avant
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		sauvegarder()


## Réinitialise TOUT l'état de partie — appelé par PLAY au menu principal.
## Nouvelle partie = page blanche : cœurs ramassés compris.
func reset_partie() -> void:
	hearts_initialized = false  # le prochain spawn relira l'export du player
	coeurs_ramasses.clear()
	roues_brisees.clear()
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
	ames_perdues = 0
	ames_scene = ""
	ames_id += 1
	coeur_noir = false
	coeur_noir_attente = 0.0
	vient_de_mourir = false
	defi_max_hp = 0


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

## une mort : `montant` âmes attendront là, dans `scene`, à `position` ; un
## esprit qui attendait encore est perdu pour de bon
func laisser_ames(montant: int, scene: String, position: Vector2) -> void:
	if ames_perdues > 0:
		print("[ÂMES] l'esprit de sang d'avant (", ames_perdues, " âmes) est perdu pour de bon")
	ames_id += 1
	ames_perdues = maxi(montant, 0)
	ames_scene = scene if ames_perdues > 0 else ""
	ames_position = position


## l'esprit de sang est repris : ses âmes reviennent au compteur (sans bonus :
## ce n'est pas une récolte) ; renvoie combien
func reprendre_ames() -> int:
	var n := ames_perdues
	ames_perdues = 0
	ames_scene = ""
	ames_id += 1
	changement_de_blood(n)
	sauvegarder()          # les âmes reprises sont écrites tout de suite
	return n


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
	# la Couronne du défi tient le max à UN cœur : le cœur ramassé compte pour
	# après (on le retrouve en ôtant la couronne)
	if defi_max_hp > 0:
		defi_max_hp += delta
		return
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
## découvert, déjà porté, verrouillé par la Couronne du défi, ou plus
## d'emplacement libre. La Couronne du défi, elle, RETIRE tous les autres
## talismans portés avant de se poser — et on n'a plus qu'un cœur.
func equiper_talisman(id: String) -> int:
	if not talisman_decouvert(id) or talisman_equipe(id) or talisman_verrouille(id):
		return -1
	if id == TALISMAN_DEFI:
		talismans_equipes.fill("")
		defi_max_hp = MAX_HP
		set_max_hp(1)
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
	if id == TALISMAN_DEFI and defi_max_hp > 0:
		# le défi s'achève : les cœurs reviennent… vides
		var vrai_max := defi_max_hp
		defi_max_hp = 0
		set_max_hp(vrai_max)
	talismans_changes.emit()
	return true


## verrouillé : la Couronne du défi est portée, et ce n'est pas elle
func talisman_verrouille(id: String) -> bool:
	return id != TALISMAN_DEFI and talismans_equipes.has(TALISMAN_DEFI)


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
## POURCENTAGE, jamais un ajout fixe : quand les dégâts
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
## un liseré rouge ont été essayés puis retirés (1er oct. 2026 : pas beaux, et
## plus stressants pour le joueur).
func frenesie_active() -> bool:
	return hp == 1 and bonus_talismans("degats_pourcent_dernier_coeur") > 0.0


## Ce par quoi multiplier les dégâts de base d'un coup d'épée (1.1 = +10 %).
## À appliquer au moment du coup : `roundi(base * Player.multiplicateur_degats())`.
## Le Canon de verre n'y est PAS (depuis le 2 oct. 2026) : tout ce qui part d'un
## « coup d'épée, bonus compris » (épines, gardiennes, croissant, onde du cœur
## noir…) l'aurait doublé aussi — voir `multiplicateur_infliges`.
func multiplicateur_degats() -> float:
	return 1.0 + bonus_degats_pourcent() / 100.0


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


## Ce par quoi multiplier le COUP D'ÉPÉE LUI-MÊME (avec l'éclair qui en bondit,
## Lame de foudre) et celui de l'OMBRE DE SANG, et rien d'autre (talisman
## « Canon de verre » : ×2). Depuis le 2 oct. 2026 : plus la boule ni la Tornade,
## pour qu'il ne se cumule pas avec le Pacte de sang ; ni le reste de ce qui
## découle d'un coup d'épée (épines, gardiennes, croissant, essaim,
## plumes, offrande, sang bouillant, onde du cœur noir), ni
## le poison, ni le sillage. Appliqué dans animator.gd (`_on_body_entered`) et
## ombre_sang.gd.
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


# ---------- SAUVEGARDE ----------
# La partie est gardée sur le disque, UNE SEULE (user://sauvegarde.cfg). Elle
# est écrite EN CONTINU : à chaque checkpoint touché, à l'arrivée dans un
# tableau, quand on ramasse un cœur, qu'on trouve, équipe ou retire un
# talisman, qu'on meurt, qu'on reprend ses âmes, et en quittant (menu de pause,
# fermeture de la fenêtre). Rien de ce qu'on a gagné n'est perdu en quittant.
#   • LOAD (menu principal) la reprend AU DERNIER CHECKPOINT TOUCHÉ, cœurs
#     pleins — sans checkpoint, au début du tableau où l'on était ;
#   • PLAY commence une partie neuve, qui la remplace à sa première écriture.
# Ce qui est gardé : le checkpoint, le sang, les cœurs (et les gouttes déjà
# ramassées), la jauge de soin, les talismans trouvés et portés, le cœur noir,
# les âmes perdues qui attendent. Ce qui ne l'est pas, comme à une
# réapparition : la vie courante, les temps de recharge, les roues à pointes
# brisées, l'essaim.
# On n'écrit qu'EN PARTIE (un tableau posé par le Loader) : jamais au menu, ni
# quand un tableau est lancé seul depuis l'éditeur.
# L'écriture passe par un fichier provisoire, et la sauvegarde d'avant reste en
# copie de secours (.bak) : une écriture interrompue ne casse rien. Une
# sauvegarde illisible, d'une version inconnue ou dont le tableau n'existe plus
# est ignorée (LOAD reste grisé) — elle ne fait jamais planter le jeu.
const SAUVEGARDE := "user://sauvegarde.cfg"
const SAUVEGARDE_SECOURS := "user://sauvegarde.cfg.bak"
const SAUVEGARDE_VERSION := 1
## le plus grand nombre de cœurs qu'une sauvegarde peut rendre
const SAUVEGARDE_COEURS_MAX := 99
var _sauvegarde_gelee := false       # pendant une lecture : on n'écrit pas par-dessus


## Le tableau où l'on joue (chemin res://) : celui que le Loader a posé ; lancé
## seul depuis l'éditeur, la scène courante.
func niveau_courant() -> String:
	var loader := get_node_or_null("/root/Loader")
	if loader != null and loader.niveau_courant != "":
		return loader.niveau_courant
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


## Une partie est-elle en cours (un tableau posé par le Loader) ?
func en_partie() -> bool:
	var loader := get_node_or_null("/root/Loader")
	return loader != null and loader.niveau_courant != ""


## Écrit la partie sur le disque. Sans effet hors partie. Renvoie true si elle
## est écrite.
func sauvegarder() -> bool:
	if _sauvegarde_gelee or not en_partie():
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("sauvegarde", "version", SAUVEGARDE_VERSION)
	cfg.set_value("sauvegarde", "date", Time.get_datetime_string_from_system())
	cfg.set_value("sauvegarde", "niveau", niveau_courant())
	cfg.set_value("partie", "checkpoint", has_checkpoint)
	cfg.set_value("partie", "checkpoint_scene", last_checkpoint_scene)
	cfg.set_value("partie", "checkpoint_position", last_checkpoint_pos)
	cfg.set_value("partie", "sang", blood)
	cfg.set_value("partie", "coeurs", MAX_HP)
	cfg.set_value("partie", "coeurs_initialises", hearts_initialized)
	cfg.set_value("partie", "defi_coeurs", defi_max_hp)
	cfg.set_value("partie", "coeurs_ramasses", coeurs_ramasses.keys())
	cfg.set_value("partie", "barres_soin", nb_barres_bloodheal)
	cfg.set_value("partie", "soin", bloodheal)
	cfg.set_value("partie", "coeur_noir", coeur_noir)
	cfg.set_value("partie", "talismans_trouves", talismans_decouverts.keys())
	cfg.set_value("partie", "talismans_portes", Array(talismans_equipes))
	cfg.set_value("partie", "ames", ames_perdues)
	cfg.set_value("partie", "ames_scene", ames_scene)
	cfg.set_value("partie", "ames_position", ames_position)
	# écrite à côté, puis mise en place : l'ancienne devient la copie de secours
	var provisoire := SAUVEGARDE + ".tmp"
	var err := cfg.save(provisoire)
	if err != OK:
		push_warning("[SAUVEGARDE] écriture impossible (erreur %d)" % err)
		return false
	if FileAccess.file_exists(SAUVEGARDE):
		if FileAccess.file_exists(SAUVEGARDE_SECOURS):
			DirAccess.remove_absolute(SAUVEGARDE_SECOURS)
		DirAccess.rename_absolute(SAUVEGARDE, SAUVEGARDE_SECOURS)
	err = DirAccess.rename_absolute(provisoire, SAUVEGARDE)
	if err != OK:
		push_warning("[SAUVEGARDE] mise en place impossible (erreur %d)" % err)
		return false
	return true


## Y a-t-il une partie à reprendre (lisible, et dont le tableau existe) ?
func sauvegarde_existe() -> bool:
	return _lire_sauvegarde() != null


## Reprend la partie sauvegardée : tout l'état de partie est remplacé par le
## sien. Renvoie le tableau à charger (celui du dernier checkpoint touché ;
## sans checkpoint, celui où l'on était), ou "" s'il n'y a rien à reprendre —
## dans ce cas rien n'est touché.
func charger() -> String:
	var cfg := _lire_sauvegarde()
	if cfg == null:
		return ""
	_sauvegarde_gelee = true
	reset_partie()
	var p := "partie"
	blood = maxi(_sauv_entier(cfg, p, "sang", 0), 0)
	for cle in _sauv_liste(cfg, p, "coeurs_ramasses"):
		if cle is String:
			coeurs_ramasses[cle] = true
	nb_barres_bloodheal = clampi(_sauv_entier(cfg, p, "barres_soin", BARRES_BLOODHEAL_DEPART), 1, MAX_BARRES_BLOODHEAL)
	MAX_BLOODHEAL = nb_barres_bloodheal * BARRE_BLOODHEAL
	bloodheal = clampi(_sauv_entier(cfg, p, "soin", 0), 0, MAX_BLOODHEAL)
	coeur_noir = cfg.get_value(p, "coeur_noir", false) == true
	# les talismans : ceux du départ, plus ceux de la sauvegarde que le catalogue
	# connaît encore ; portés seulement s'ils sont trouvés, jamais en double
	for id in _sauv_liste(cfg, p, "talismans_trouves"):
		if id is String and not Talismans.trouver(id).is_empty():
			talismans_decouverts[id] = true
	var portes := _sauv_liste(cfg, p, "talismans_portes")
	for i in mini(portes.size(), EMPLACEMENTS_TALISMAN):
		var id = portes[i]
		if id is String and id != "" and talisman_decouvert(id) and not talismans_equipes.has(id):
			talismans_equipes[i] = id
	# les cœurs ; avec la Couronne du défi : elle seule est portée, un seul
	# cœur, et les vrais cœurs sont mis de côté
	var coeurs := clampi(_sauv_entier(cfg, p, "coeurs", MAX_HP), 1, SAUVEGARDE_COEURS_MAX)
	if talismans_equipes.has(TALISMAN_DEFI):
		for i in talismans_equipes.size():
			if talismans_equipes[i] != TALISMAN_DEFI:
				talismans_equipes[i] = ""
		defi_max_hp = clampi(maxi(_sauv_entier(cfg, p, "defi_coeurs", 0), coeurs), 1, SAUVEGARDE_COEURS_MAX)
		coeurs = 1
	# (une partie écrite avant la première apparition du héros n'a pas encore
	# ses cœurs : il les lira à son arrivée, comme en partie neuve)
	if cfg.get_value(p, "coeurs_initialises", true) == true:
		hearts_initialized = true
		MAX_HP = coeurs
		max_hearts = coeurs
		hp = coeurs                       # on reprend cœurs pleins
	# le point de retour
	var scene = cfg.get_value(p, "checkpoint_scene", "")
	var position = cfg.get_value(p, "checkpoint_position", Vector2.ZERO)
	if cfg.get_value(p, "checkpoint", false) == true and scene is String \
			and scene != "" and ResourceLoader.exists(scene) and position is Vector2:
		has_checkpoint = true
		last_checkpoint_scene = scene
		last_checkpoint_pos = position
	# les âmes perdues qui attendent encore
	var ames := maxi(_sauv_entier(cfg, p, "ames", 0), 0)
	scene = cfg.get_value(p, "ames_scene", "")
	position = cfg.get_value(p, "ames_position", Vector2.ZERO)
	if ames > 0 and scene is String and scene != "" and position is Vector2:
		ames_perdues = ames
		ames_scene = scene
		ames_position = position
	ames_id += 1
	talismans_changes.emit()
	_sauvegarde_gelee = false
	return _sauv_scene_de_reprise(cfg)


## la sauvegarde si elle est utilisable, sinon sa copie de secours, sinon null
func _lire_sauvegarde() -> ConfigFile:
	for chemin in [SAUVEGARDE, SAUVEGARDE_SECOURS]:
		if not FileAccess.file_exists(chemin):
			continue
		var cfg := ConfigFile.new()
		if cfg.load(chemin) != OK:
			push_warning("[SAUVEGARDE] fichier illisible : " + chemin)
			continue
		var version = cfg.get_value("sauvegarde", "version", 0)
		if typeof(version) != TYPE_INT or version < 1 or version > SAUVEGARDE_VERSION:
			continue
		if _sauv_scene_de_reprise(cfg) == "":
			continue
		return cfg
	return null


## le tableau où reprendre : celui du dernier checkpoint touché ; sans
## checkpoint, celui où l'on était ; "" si aucun des deux n'existe
func _sauv_scene_de_reprise(cfg: ConfigFile) -> String:
	var scene = cfg.get_value("partie", "checkpoint_scene", "")
	if cfg.get_value("partie", "checkpoint", false) == true and scene is String \
			and scene != "" and ResourceLoader.exists(scene):
		return scene
	scene = cfg.get_value("sauvegarde", "niveau", "")
	if scene is String and scene != "" and ResourceLoader.exists(scene):
		return scene
	return ""


func _sauv_entier(cfg: ConfigFile, section: String, cle: String, defaut: int) -> int:
	var v = cfg.get_value(section, cle, defaut)
	return int(v) if (v is int or v is float) else defaut


func _sauv_liste(cfg: ConfigFile, section: String, cle: String) -> Array:
	var v = cfg.get_value(section, cle, [])
	return v if v is Array else []


#Player.add_max_sang(50)        # +50 de capacité de jauge de sang (la barre s'allonge)
