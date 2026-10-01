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
##   "esquive_pourcent" (facultatif) chance, en pour cent, qu'un coup d'ennemi
##                 soit ignoré (Player.chance_esquive())
##   "blood_pourcent" (facultatif) bonus, en pour cent, sur chaque récolte de
##                 sang — le compteur chiffré (Player.multiplicateur_blood())
##   "degats_pourcent_dernier_coeur" (facultatif) bonus de dégâts des coups
##                 d'épée, en pour cent, compté SEULEMENT quand il ne reste
##                 qu'un cœur (Player.frenesie_active()) ; s'ajoute aux
##                 `degats_pourcent`
##   "degats_infliges_multiplicateur" / "degats_recus_multiplicateur"
##                 (facultatifs) multiplient TOUS les dégâts infligés / reçus
##                 (2 = ×2) ; plusieurs talismans se MULTIPLIENT entre eux
##                 (Player.produit_talismans)
##   "allonge_pourcent" (facultatif) portée de l'épée en plus, en pour cent
##                 (20 = +20 % : zone de touche et slash, animator.gd)
## Le dessin passe avant l'icône, qui passe avant le rond de couleur ; les deux
## sont posés dans l'emplacement, à sa taille.
## ============================================================================

## Nombre d'emplacements RONDS de la collection dans le menu. Ceux qui n'ont pas
## encore de talisman dans LISTE restent des emplacements vides « à découvrir ».
## S'il y a plus de talismans que d'emplacements, la grille s'agrandit seule.
## VINGT-SEPT pour le moment (5 le 30 sept. 2026 ; le sillage de sang, les
## épines, la frénésie, la marque, le second souffle, le canon de verre,
## l'allonge, la vengeance, le croissant de sang, l'essaim, l'offrande, le
## sang bouillant, l'ombre de sang, le sang corrompu, le coup dans le dos, le
## crescendo, la parade, la lame corrompue, la prise ferme, le venin, le coup
## de grâce et le sang cristallisé le 1er oct.) : monte ce nombre quand il y en
## aura d'autres à découvrir.
const NB_EMPLACEMENTS := 27

## Les VINGT-SEPT talismans du jeu (1er oct. 2026), tous branchés :
##   tornade  → SCRIPT/CHARACHTER/player.gd, région BLOODBALL
##   foudre   → SCRIPT/CHARACHTER/animator.gd (le slash, l'arc qui bondit, le +10 %)
##   bouclier → player.gd (`apply_damage` / `apply_environment_damage`)
##   esquive  → player.gd (`_esquive_tente`, dans `apply_damage`)
##   soif     → SCRIPT/AUTOLOAD/player.gd (`recolter_blood`)
##   sillage  → player.gd (`_sillage_tick`) + SCRIPT/SHADER/sillage_sang.gd
##   epines   → player.gd (`_epines_jaillir`, après un coup encaissé) +
##              SCRIPT/SHADER/epines_sang.gd
##   frenesie → SCRIPT/AUTOLOAD/player.gd (`bonus_degats_pourcent`,
##              `frenesie_active`) — des stats seules, voulu sans effet à l'écran
##   marque   → SCRIPT/SPELL/bloodball.gd (la pose) + SCRIPT/CHARACHTER/animator.gd
##              (le coup +50 %) + SCRIPT/SHADER/marque_sang.gd (la rune)
##   souffle  → player.gd (`_second_souffle`, `Player.second_souffle_attente`),
##              checkpoint.gd (recharge), gestion_interface.gd (`souffle_fx`)
##   canon    → SCRIPT/AUTOLOAD/player.gd (`multiplicateur_infliges` /
##              `multiplicateur_recus`) — des stats seules
##   allonge  → SCRIPT/CHARACHTER/animator.gd (`_play_slash`)
##   vengeance → player.gd (`_vengeance_charger`, `vengeance_active`) +
##              animator.gd (les coups ×1,5 tant qu'elle dure) +
##              SCRIPT/SHADER/couronne_vengeance.gd (la couronne)
##   croissant → animator.gd (`_croissant`, au dernier coup du combo) +
##              SCRIPT/SHADER/croissant_sang.gd (le projectile)
##   essaim   → player.gd (`_on_monstre_tue`, sur le signal
##              `Player.monstre_tue` émis par BASE_IA.gd) +
##              SCRIPT/SHADER/chauve_souris_sang.gd (les chauves-souris)
##   offrande → player.gd (`_offrande_lancer`, au début du soin) +
##              SCRIPT/SHADER/sceau_sang.gd (le sceau et son onde)
##   bouillant → animator.gd (`_on_body_entered`, quand le coup porte) +
##              SCRIPT/SPELL/bloodball.gd (quand la boule touche) +
##              SCRIPT/SHADER/ombre_sang.gd (le coup du double, synergie) +
##              player.gd (`bouillant_charger`) +
##              SCRIPT/SHADER/bouillon_sang.gd (les charges, les bulles, l'explosion)
##   ombre    → animator.gd (`_on_body_entered`, quand le coup porte) +
##              player.gd (`ombre_surgir`) + SCRIPT/SHADER/ombre_sang.gd (le double)
##   corrompu → player.gd (`bloodball_enter` : les couleurs ; `empoisonner`) +
##              SCRIPT/SPELL/bloodball.gd (`corrompre`, le poison à l'impact) +
##              SCRIPT/SHADER/poison_sang.gd (le poison) + BASE_IA.gd (`teinter`)
##   dos      → animator.gd (`_on_body_entered`, `_de_dos` ; l'éclat : `_eclat_impact`)
##   crescendo → player.gd (`crescendo_pourcent` / `_porte` / `_casser` : la série) +
##              animator.gd (`_on_body_entered` : les dégâts ; `_crescendo_habiller` : le slash)
##   parade   → player.gd (`apply_damage` → `_parade_tente`, `_parade_choc`) +
##              animator.gd (`lame_en_garde`) + BASE_IA.gd (`etourdir`, `infliger`) +
##              SCRIPT/SHADER/parade_choc.gd (le choc), etourdi.gd (les étoiles)
##   lame_corrompue → animator.gd (`_on_body_entered` : le poison ; `_foudre_bondir` :
##              l'éclair violet qui empoisonne ; `_habiller_slash` : le slash violet) +
##              player.gd (`empoisonner`) + SCRIPT/SHADER/poison_sang.gd
##   prise    → player.gd (`wall_jump_execute` : plus de glissade)
##   venin    → BASE_IA.gd (`_venin`, dans `apply_damage`) + animator.gd
##              (`_eclat_impact` : l'étoile cernée de violet)
##   grace    → BASE_IA.gd (`executable`, `_maj_fissures`) + hit_flash.gdshader
##              (les fissures) + animator.gd (`_on_body_entered`) + player.gd
##              (`grace_executer`) + SCRIPT/SHADER/grace_eclats.gd (les éclats)
##   cristal  → SCRIPT/SPELL/bloodball.gd (la chance de figer) + BASE_IA.gd
##              (`cristalliser`, `briser_cristal`) + hit_flash.gdshader (la statue) +
##              animator.gd (le coup d'épée qui le brise)
## Les clés chiffrées (`degats_pourcent`, `esquive_pourcent`, `blood_pourcent`,
## `degats_pourcent_dernier_coeur`)
## sont lues par `Player.bonus_talismans(cle)` : deux talismans qui portent la
## même clé s'additionnent.
const LISTE := [
	{"id": "tornade_bloodball", "nom": "Tornade de sang", "description": "La boule de sang file en spirale et repousse les ennemis qu'elle touche.", "couleur": Color(0.72, 0.13, 0.17), "dessin": "res://SCRIPT/TALISMAN/dessin_tornade_de_sang.gdshader"},
	{"id": "foudre", "nom": "Lame de foudre", "description": "Le coup d'épée devient foudre : +10 % de dégâts, et quand il porte, l'éclair bondit sur l'ennemi le plus proche.", "couleur": Color(0.45, 0.72, 1.0), "dessin": "res://SCRIPT/TALISMAN/dessin_foudre.gdshader", "degats_pourcent": 10},
	{"id": "bouclier", "nom": "Bouclier de sang", "description": "Encaisser un coup dresse un bouclier de sang qui pare tous les suivants pendant deux secondes.", "couleur": Color(0.72, 0.13, 0.17), "dessin": "res://SCRIPT/TALISMAN/dessin_bouclier.gdshader"},
	{"id": "esquive", "nom": "Pas de côté", "description": "Une chance sur cinq qu'un coup d'ennemi passe au travers de vous.", "couleur": Color(0.84, 0.79, 0.66), "dessin": "res://SCRIPT/TALISMAN/dessin_esquive.gdshader", "esquive_pourcent": 20},
	{"id": "soif", "nom": "Soif de sang", "description": "Chaque récolte de sang rapporte 10 % de plus.", "couleur": Color(0.55, 0.05, 0.08), "dessin": "res://SCRIPT/TALISMAN/dessin_soif.gdshader", "blood_pourcent": 10},
	{"id": "sillage", "nom": "Sillage de sang", "description": "La roulade et le dash laissent une brume de sang qui ronge à petit feu les ennemis pris dedans.", "couleur": Color(0.7, 0.05, 0.1), "dessin": "res://SCRIPT/TALISMAN/dessin_sillage.gdshader"},
	{"id": "epines", "nom": "Épines de sang", "description": "Encaisser un coup fait jaillir des pics de sang qui blessent et repoussent les ennemis proches.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_epines.gdshader"},
	{"id": "frenesie", "nom": "Frénésie", "description": "Au dernier cœur, les coups d'épée font 50 % de dégâts en plus.", "couleur": Color(0.85, 0.05, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_frenesie.gdshader", "degats_pourcent_dernier_coeur": 50},
	{"id": "marque", "nom": "Marque de sang", "description": "La boule de sang marque l'ennemi qu'elle touche : votre prochain coup d'épée sur lui fait 50 % de dégâts en plus.", "couleur": Color(0.76, 0.03, 0.11), "dessin": "res://SCRIPT/TALISMAN/dessin_marque.gdshader"},
	{"id": "souffle", "nom": "Second souffle", "description": "Un coup qui devrait vous tuer vous laisse à un cœur. Se recharge en 120 secondes, et à chaque checkpoint.", "couleur": Color(0.76, 0.03, 0.11), "dessin": "res://SCRIPT/TALISMAN/dessin_souffle.gdshader"},
	{"id": "canon", "nom": "Canon de verre", "description": "Tous les dégâts que vous infligez sont doublés… et tous ceux que vous recevez aussi.", "couleur": Color(0.76, 0.03, 0.11), "dessin": "res://SCRIPT/TALISMAN/dessin_canon.gdshader", "degats_infliges_multiplicateur": 2, "degats_recus_multiplicateur": 2},
	{"id": "allonge", "nom": "Allonge", "description": "La portée de l'épée augmente de 20 %.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_allonge.gdshader", "allonge_pourcent": 20},
	{"id": "croissant", "nom": "Croissant de sang", "description": "Le dernier coup du combo projette son slash vers l'avant : il traverse les ennemis sur une courte distance.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_croissant.gdshader"},
	{"id": "vengeance", "nom": "Vengeance", "description": "Après un coup encaissé, tous vos coups d'épée font 50 % de dégâts en plus pendant 5 secondes. Une couronne de sang le rappelle au-dessus de vous.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_vengeance.gdshader"},
	{"id": "essaim", "nom": "Essaim", "description": "Chaque ennemi que vous tuez lâche deux chauves-souris de sang qui fondent sur les ennemis proches et les mordent.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_essaim.gdshader"},
	{"id": "offrande", "nom": "Offrande", "description": "Se soigner dessine un sceau de sang sous vos pieds : son onde repousse et blesse les ennemis autour de vous.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_offrande.gdshader"},
	{"id": "bouillant", "nom": "Sang bouillant", "description": "Chaque coup d'épée ou de boule de sang fait bouillir le sang de l'ennemi ; au troisième, il explose et blesse aussi ses voisins.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_bouillant.gdshader"},
	{"id": "ombre", "nom": "Ombre de sang", "description": "Quand votre épée touche, un double de sang surgit derrière l'ennemi et le frappe à son tour, à moitié des dégâts.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_ombre.gdshader"},
	{"id": "corrompu", "nom": "Sang corrompu", "description": "La boule de sang se corrompt et vire au violet : l'ennemi qu'elle touche est empoisonné et perd de la vie pendant trois secondes.", "couleur": Color(0.58, 0.14, 0.84), "dessin": "res://SCRIPT/TALISMAN/dessin_corrompu.gdshader"},
	{"id": "dos", "nom": "Coup dans le dos", "description": "Un coup d'épée porté dans le dos d'un ennemi fait 50 % de dégâts en plus.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_dos.gdshader"},
	{"id": "crescendo", "nom": "Crescendo", "description": "Tant que vous n'êtes pas touché, chaque coup d'épée qui porte frappe plus fort : +5 %, +10 %, +20 %, +40 %, puis +50 %. Un coup encaissé, ou quelques secondes sans frapper, remet tout à zéro.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_crescendo.gdshader"},
	{"id": "parade", "nom": "Parade", "description": "Frappez au moment où un ennemi frappe : votre lame pare son coup, vous ne prenez rien et il reste sonné une seconde.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_parade.gdshader"},
	{"id": "lame_corrompue", "nom": "Lame corrompue", "description": "Le coup d'épée se corrompt et vire au violet : il empoisonne l'ennemi qu'il touche. Avec la Lame de foudre, la foudre devient violette et empoisonne aussi.", "couleur": Color(0.58, 0.14, 0.84), "dessin": "res://SCRIPT/TALISMAN/dessin_lame_corrompue.gdshader"},
	{"id": "prise", "nom": "Prise ferme", "description": "Accroché à un mur, vous ne glissez plus : vous restez où vous êtes. Maintenez bas pour descendre.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_prise.gdshader"},
	{"id": "venin", "nom": "Venin", "description": "Les ennemis empoisonnés prennent 30 % de dégâts en plus de toutes vos attaques.", "couleur": Color(0.58, 0.14, 0.84), "dessin": "res://SCRIPT/TALISMAN/dessin_venin.gdshader"},
	{"id": "grace", "nom": "Coup de grâce", "description": "Un ennemi à moins d'un quart de sa vie se fissure de rouge : votre prochain coup d'épée l'achève net et vous rend du sang. Les boss y échappent.", "couleur": Color(0.78, 0.04, 0.12), "dessin": "res://SCRIPT/TALISMAN/dessin_grace.gdshader"},
	{"id": "cristal", "nom": "Sang cristallisé", "description": "Une boule de sang sur cinq fige l'ennemi dans le cristal pendant un instant ; votre coup d'épée suivant le brise avec 50 % de dégâts en plus.", "couleur": Color(0.86, 0.12, 0.2), "dessin": "res://SCRIPT/TALISMAN/dessin_cristal.gdshader"},
]

## POUR TESTER LE MENU : les talismans déjà découverts au début d'une partie.
## À vider ([]) quand ils se trouveront dans les niveaux.
const DECOUVERTS_AU_DEPART := ["tornade_bloodball", "foudre", "bouclier", "esquive", "soif", "sillage", "epines", "frenesie", "marque", "souffle", "canon", "allonge", "vengeance", "croissant", "essaim", "offrande", "bouillant", "ombre", "corrompu", "dos", "crescendo", "parade", "lame_corrompue", "prise", "venin", "grace", "cristal"]


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
