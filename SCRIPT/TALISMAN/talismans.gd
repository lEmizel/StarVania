extends RefCounted
## ============================================================================
## CATALOGUE DES TALISMANS — la liste de tous les talismans du jeu.
##
## Ce que le joueur a DÉCOUVERT et ce qu'il PORTE est dans l'autoload Player
## (talismans_decouverts / talismans_equipes). Le menu START, onglet Talismans,
## affiche les deux.
##
## AJOUTER UN TALISMAN = ajouter UNE ligne dans LISTE. Sa place dans la liste
## est sa place dans la grille du menu (de gauche à droite, puis la rangée
## suivante) :
##   "id"          le nom utilisé dans le code, à ne plus changer une fois posé
##                 (Player.talisman_equipe("mon_id") pour brancher son effet)
##   "nom"         le nom affiché
##   "description" le texte affiché sous la grille
##   "couleur"     la couleur du rond, tant qu'il n'a ni dessin ni icône
##   "dessin"      (facultatif) un SHADER qui dessine le talisman et peut
##                 l'animer : "res://SCRIPT/TALISMAN/dessin_….gdshader"
##                 (modèle : dessin_tornade_de_sang.gdshader)
##   "icone"       (facultatif) une IMAGE : "res://MEDIA/…/mon_talisman.png"
##   "degats_pourcent" (facultatif) bonus de dégâts des COUPS D'ÉPÉE, en pour
##                 cent (10 = +10 %) — un pourcentage des dégâts de base, pas
##                 un ajout fixe ; plusieurs talismans portés s'additionnent
##                 (Player.multiplicateur_degats())
## Le dessin passe avant l'icône, qui passe avant le rond de couleur ; les deux
## sont posés dans l'emplacement, à sa taille.
## ============================================================================

## Nombre d'emplacements RONDS de la collection dans le menu. Ceux qui n'ont pas
## encore de talisman dans LISTE restent des emplacements vides « à découvrir ».
## S'il y a plus de talismans que d'emplacements, la grille s'agrandit seule.
const NB_EMPLACEMENTS := 18

## Les trois premiers sont de VRAIS talismans : la tornade est branchée dans
## SCRIPT/CHARACHTER/player.gd (région BLOODBALL), la lame de foudre dans
## SCRIPT/CHARACHTER/animator.gd (le slash et l'arc qui bondit), le bouclier
## de sang dans player.gd (`apply_damage` / `apply_environment_damage`). Les
## « Talisman 2 » à « Talisman 6 » sont des EXEMPLES sans effet, pour faire
## tourner le menu : à remplacer par les vrais au fur et à mesure.
const LISTE := [
	{"id": "tornade_bloodball", "nom": "Tornade de sang", "description": "La boule de sang file en spirale et repousse les ennemis qu'elle touche.", "couleur": Color(0.72, 0.13, 0.17), "dessin": "res://SCRIPT/TALISMAN/dessin_tornade_de_sang.gdshader"},
	{"id": "foudre", "nom": "Lame de foudre", "description": "Le coup d'épée devient foudre : +10 % de dégâts, et quand il porte, l'éclair bondit sur l'ennemi le plus proche.", "couleur": Color(0.45, 0.72, 1.0), "dessin": "res://SCRIPT/TALISMAN/dessin_foudre.gdshader", "degats_pourcent": 10},
	{"id": "bouclier", "nom": "Bouclier de sang", "description": "Encaisser un coup dresse un bouclier de sang qui pare tous les suivants pendant deux secondes.", "couleur": Color(0.72, 0.13, 0.17), "dessin": "res://SCRIPT/TALISMAN/dessin_bouclier.gdshader"},
	{"id": "talisman_2", "nom": "Talisman 2", "description": "Effet à définir.", "couleur": Color(0.85, 0.55, 0.16)},
	{"id": "talisman_3", "nom": "Talisman 3", "description": "Effet à définir.", "couleur": Color(0.84, 0.79, 0.66)},
	{"id": "talisman_4", "nom": "Talisman 4", "description": "Effet à définir.", "couleur": Color(0.2, 0.55, 0.55)},
	{"id": "talisman_5", "nom": "Talisman 5", "description": "Effet à définir.", "couleur": Color(0.47, 0.28, 0.62)},
	{"id": "talisman_6", "nom": "Talisman 6", "description": "Effet à définir.", "couleur": Color(0.38, 0.55, 0.25)},
]

## POUR TESTER LE MENU : les talismans déjà découverts au début d'une partie.
## À vider ([]) quand ils se trouveront dans les niveaux.
const DECOUVERTS_AU_DEPART := ["tornade_bloodball", "foudre", "bouclier", "talisman_2", "talisman_3", "talisman_4"]


## la ligne du catalogue qui porte cet id ({} si aucune)
static func trouver(id: String) -> Dictionary:
	for t in LISTE:
		if t["id"] == id:
			return t
	return {}


## le numéro d'un talisman = sa place dans la grille, à partir de 1 (0 si l'id
## n'existe pas)
static func numero(id: String) -> int:
	for i in LISTE.size():
		if LISTE[i]["id"] == id:
			return i + 1
	return 0


## nombre d'emplacements de la grille : jamais moins que de talismans
static func nb_emplacements() -> int:
	return maxi(NB_EMPLACEMENTS, LISTE.size())


## le shader qui dessine un talisman, ou null s'il n'en a pas
static func dessin(talisman: Dictionary) -> Shader:
	var chemin := String(talisman.get("dessin", ""))
	if chemin == "" or not ResourceLoader.exists(chemin):
		return null
	return load(chemin) as Shader


## l'image d'un talisman, ou null s'il n'en a pas (encore) : on dessine alors
## le rond de couleur
static func icone(talisman: Dictionary) -> Texture2D:
	var chemin := String(talisman.get("icone", ""))
	if chemin == "" or not ResourceLoader.exists(chemin):
		return null
	return load(chemin) as Texture2D
