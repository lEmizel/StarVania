extends CharacterBody2D


enum States { IDLE, RUN, CHUTE, JUMP, WALL_GRIFFE, WALL_JUMP, CLIMB, ROLL, CHUTE_GRIFFE, GRAB, ATTACK_LIGHT_1, ATTACK_LIGHT_2, ATTACK_LIGHT_3, ATTACK_AIR, ATTACK_LOURDE, DEAD, HIT, HEAL, DROP, BLOODBALL, ECHELLE, DASH, CORDE, GRAPPIN }



@export_group("Base")
# CAMP (23 sept. 2026) : même système que les monstres (`faction` de BASE_IA).
# Un monstre du même camp ne nous attaque pas. 1 par défaut, les monstres à 0.
@export_range(0, 10) var faction: int = 1

@onready var wall_right: RayCast2D = $POINT/wall_right
@onready var wall_left: RayCast2D = $POINT/wall_left
@onready var climbcast_up: RayCast2D = $POINT/climbcast_up
@onready var climbcast_down: RayCast2D = $POINT/climbcast_down
@onready var climbcast_left: RayCast2D = $POINT/climbcast_left
@onready var climbcast_right: RayCast2D = $POINT/climbcast_right
@onready var grab: RayCast2D = $POINT/GRAB
@onready var ancre_grab: Node2D = $POINT/ANCRE_GRAB
@onready var slash_attack: AnimatedSprite2D = $POINT/slash_attack

@onready var ANCRE_SOL_BACK: Node2D = $POINT/ANCRE_SOL_BACK
@onready var ANCRE_SOL: Node2D = $POINT/ANCRE_SOL
@onready var ANCRE_WALL: Node2D = $POINT/ANCRE_WALL

@onready var point: Node2D = $POINT # le node 2d qui sert a flip le personnage
@onready var animator = $POINT/animator
@onready var spellcast: Marker2D = $POINT/SPELLCAST
@onready var collision_normale: CollisionShape2D = $CollisionShape2D
@onready var collision_roulade: CollisionShape2D = $CollisionShaperoulage
var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var current_state : States = States.IDLE
var previous_state : States = States.IDLE
var state_functions: Dictionary = {}

const GROUND_SPEED = 700            # FIX: renommé pour clarté
## Vitesse horizontale en l'air (sept. 2026 : 400 → 480, garde la portée du
## saut ≈ 440 px malgré le vol raccourci — et rend l'air moins pataud)
@export var AIR_SPEED: float = 610.0
@export var GROUND_SPEED_ATTACK: float = 550.0  # vitesse de course pendant les attaques
## Nombre de cœurs de vie max — synchronisé vers le singleton Player au spawn
@export var MAX_HEARTS: int = 5
var last_direction := 1  # 1 = droite, -1 = gauche

## vitesse de déplacement en escalade (surfaces CLIMB)
@export var CLIMB_SPEED: float = 200.0
const ROLL_SPEED := 760.0

const COYOTE_TIME := 0.08
## Coyote élargi pour les chutes SUBIES depuis une accroche (griffe qui
## expire, échelle, grab…) : la chute n'étant pas choisie, la pression de
## saut du joueur arrive naturellement plus tard
@export var GRIP_COYOTE_TIME: float = 0.3
var _coyote_timer := 0.0
const JUMP_BUFFER_TIME := 0.12  # très court — juste un filet de sécurité
var _jump_buffer_timer := 0.0

const GRAB_COOLDOWN := 0.2  # secondes avant de pouvoir re-grab
var _grab_cooldown_timer := 0.0
var current_grab_area: Area2D = null

const FOOTSTEP_SCENE = preload("uid://bc2iigjdyudgm")
const CHUTE_SCENE = preload("uid://bfwic6xtfgc4p")
const WALL_JUMP_SCENE = preload("uid://c5a6or75xrx3o")
## l'éclat rouge sang qui marque un coup REÇU (30 sept. 2026) — le jumeau de
## l'éclat blanc de l'épée (animator.gd) : même shader, sa propre scène
const IMPACT_SANG := preload("res://SCRIPT/SHADER/impact_sang.tscn")

## TALISMAN « BOUCLIER DE SANG » (30 sept. 2026, id "bouclier" dans
## SCRIPT/TALISMAN/talismans.gd) : porté, ENCAISSER un coup dresse une bulle de
## sang à facettes autour du joueur pendant `bouclier_duree` secondes, et elle
## PARE tout autre coup (ni dégât, ni recul, ni stun) — voir `_bouclier_pare`.
## L'allure de la bulle se règle dans SCRIPT/SHADER/bouclier_sang.tscn.
const BOUCLIER_SCENE := preload("res://SCRIPT/SHADER/bouclier_sang.tscn")
const TALISMAN_BOUCLIER := "bouclier"
@export_group("Talismans")
@export_subgroup("Bouclier de sang")
## combien de temps le bouclier tient (s)
@export var bouclier_duree := 2.0
## temps mort après sa chute avant qu'un coup puisse le relever (s, 0 = aucun)
@export var bouclier_recharge := 0.0
var _bouclier: Node2D
var _bouclier_recharge_reste := 0.0

## TALISMAN « ÉPINES DE SANG » (1er oct. 2026, id "epines") : porté, ENCAISSER
## un coup (d'un ennemi ou du décor) fait jaillir de tout le corps des pics de
## sang cristallisé : chaque ennemi dont le corps est à moins de `epines_rayon`
## px du milieu du nôtre, sans mur entre nous, prend `epines_part` × les dégâts
## d'un coup d'épée (bonus en pourcentage compris) et est repoussé — voir
## `_epines_jaillir`. Un coup paré (bouclier) ou esquivé ne compte pas.
## L'allure des pics se règle dans SCRIPT/SHADER/epines_sang.tscn.
const EPINES_SCENE := preload("res://SCRIPT/SHADER/epines_sang.tscn")
const TALISMAN_EPINES := "epines"
@export_subgroup("Épines de sang")
## portée des pics depuis le milieu du corps (px) — le dessin la suit
@export var epines_rayon := 200.0
## dégâts : part d'un coup d'épée (1 = autant qu'un coup, bonus compris)
@export var epines_part := 1.0

## TALISMAN « SECOND SOUFFLE » (1er oct. 2026, id "souffle") : porté, un coup
## qui devrait nous tuer nous laisse à UN cœur, puis plus aucun coup ne passe
## pendant `second_souffle_grace` s (le temps de fuir ou de se soigner). Il se
## recharge en `second_souffle_recharge` s, au respawn, et à chaque checkpoint
## touché.
## Le cœur qui reste se fêle dans le HUD (gestion_interface.gd, `souffle_fx`).
## L'attente vit dans l'autoload (`Player.second_souffle_attente`) : le joueur
## est recréé à chaque respawn.
const TALISMAN_SOUFFLE := "souffle"
@export_subgroup("Second souffle")
@export var second_souffle_recharge := 120.0
@export var second_souffle_grace := 1.0
var _souffle_grace_reste := 0.0

@export_subgroup("Marque de sang")
## TALISMAN « MARQUE DE SANG » (1er oct. 2026, id "marque") : la boule de sang
## (et la tornade) marque l'ennemi qu'elle touche (SCRIPT/SPELL/bloodball.gd) ;
## le prochain coup d'épée qui PORTE sur lui fait `marque_multiplicateur` fois
## ses dégâts et efface la marque (animator.gd). La rune et sa durée :
## SCRIPT/SHADER/marque_sang.tscn.
@export var marque_multiplicateur := 1.5     # +50 % (×2 était trop fort)

## TALISMAN « CANON DE VERRE » (1er oct. 2026, id "canon") :
## les coups d'épée (avec l'éclair de la Lame de foudre) et ceux de l'Ombre de
## sang ×2 — SEULEMENT eux depuis le 2 oct. (plus la boule, pour ne pas
## cumuler avec le Pacte de sang ; la description ne parle que de l'épée) —
## et tous les dégâts reçus ×2 (clés du catalogue lues par
## `Player.multiplicateur_infliges()` / `Player.multiplicateur_recus()`, cette
## dernière appliquée dans `_degats_recus`). Tant qu'il est porté, un petit ŒIL DE FEU
## (l'œil de Sauron) flotte au-dessus de la tête — au-dessus de
## la couronne de la Vengeance quand elle est levée : SCRIPT/SHADER/oeil_canon.tscn,
## posé une fois par `_oeil_preparer`.
const OEIL_CANON := preload("res://SCRIPT/SHADER/oeil_canon.tscn")
var _oeil: Node2D

## TALISMAN « ALLONGE » (1er oct. 2026, id "allonge") : la lame porte plus loin
## — clé `allonge_pourcent` du catalogue (20 = +20 %), appliquée par animator.gd
## à chaque coup (`_play_slash`) : la zone de touche ET le slash grandissent
## ensemble autour du centre du coup.

## TALISMAN « VENGEANCE » (1er oct. 2026, id "vengeance") : porté, ENCAISSER un
## coup la charge pour `vengeance_duree` s ; tant qu'elle dure, TOUS les coups
## d'épée qui portent font `vengeance_multiplicateur` fois leurs dégâts
## (animator.gd) — elle ne s'use pas au premier coup (la première
## version ne donnait que le prochain coup, dans les 3 s). Un nouveau coup
## encaissé la relance pour toute sa durée. Tant qu'elle est chargée, une
## COURONNE de sang flotte au-dessus du perso (l'épée ne se voit pas hors
## des coups) : SCRIPT/SHADER/couronne_vengeance.tscn ; ses
## pointes rentrent avec le temps qui reste, elle bat à chaque coup vengeur,
## s'efface quand le temps est écoulé.
const TALISMAN_VENGEANCE := "vengeance"
const COURONNE_SCENE := preload("res://SCRIPT/SHADER/couronne_vengeance.tscn")
@export_subgroup("Vengeance")
@export var vengeance_duree := 5.0
@export var vengeance_multiplicateur := 1.5
## où flotte la couronne (repère du joueur : ses pieds sont à 0) : son bas
## reste à ~177 au-dessus des pieds, comme la première (le haut des cheveux
## est vers 170, coups d'épée compris)
@export var couronne_position := Vector2(0.0, -192.0)
var vengeance_reste := 0.0
var _couronne: Node2D

## TALISMAN « COUP DANS LE DOS » (1er oct. 2026, id "dos") : un coup d'épée qui
## frappe un ennemi DE DOS (nous sommes du côté opposé à son regard, au moment
## du coup) fait `dos_multiplicateur` fois ses dégâts — +50 %
## (plutôt que +75 %) ; un grand éclat rouge et blanc le signale.
## Voir animator.gd (`_on_body_entered`, `_de_dos`). Le héros traverse les
## ennemis : passer de l'autre côté et frapper avant qu'il se retourne.
const TALISMAN_DOS := "dos"
@export_subgroup("Coup dans le dos")
@export var dos_multiplicateur := 1.5

## TALISMAN « CRESCENDO » (1er oct. 2026, id "crescendo") : chaque coup d'épée
## qui porte sans qu'on soit touché fait monter la série ; le n-ième coup de la
## série fait `CRESCENDO_PALIERS[n]` % de dégâts en plus — 5, 10, 20, 40 puis
## 50 % pour tous les suivants (plutôt que +5 % par
## coup jusqu'à 50). Un coup ENCAISSÉ remet la série à zéro ; elle s'éteint
## aussi après `crescendo_delai` s sans coup qui porte (0 = jamais). Un coup qui
## touche plusieurs ennemis ne compte qu'une fois. Le slash rougit et
## s'épaissit avec la série (animator.gd, `_crescendo_habiller`).
const TALISMAN_CRESCENDO := "crescendo"
const CRESCENDO_PALIERS := [5.0, 10.0, 20.0, 40.0, 50.0]
@export_subgroup("Crescendo")
@export var crescendo_delai := 4.0
## le slash au plus fort de la série : sa couleur, son épaisseur (× celle des
## dessins)
@export var crescendo_couleur := Color(0.86, 0.06, 0.14)
@export var crescendo_epaisseur := 1.3
var crescendo_serie := 0          # coups d'épée qui ont porté d'affilée
var _crescendo_coup := -1         # le dernier coup compté (animator `_coup_id`)
var _crescendo_reste := 0.0       # avant que la série s'éteigne (s)

## TALISMAN « PARADE » (1er oct. 2026, id "parade") : un coup d'ennemi au corps à corps (l'étiquette "attaque:" de
## BASE_IA.infliger) qui nous arrive DE FACE pendant que notre lame est sortie
## — ou sur le point de sortir, l'image d'avant — est PARÉ : aucun dégât, et
## l'ennemi reste sonné `parade_etourdi` s (BASE_IA.etourdir : son coup s'arrête
## net, des étoiles tournent au-dessus de sa tête), le
## skeleton_boss autant que les autres (une version le sonnait deux fois moins
## longtemps : inutile). Passe avant le Bouclier et le Pas de
## côté ; le coup n'est pas
## encaissé (la Vengeance ne se charge pas, le Crescendo ne casse pas). Voir
## `_parade_tente` ; la lame en garde : animator.gd `lame_en_garde` ; le choc :
## SCRIPT/SHADER/parade_choc.tscn.
const TALISMAN_PARADE := "parade"
const PARADE_CHOC_SCENE := preload("res://SCRIPT/SHADER/parade_choc.tscn")
@export_subgroup("Parade")
@export var parade_etourdi := 1.0
## la caméra tremble au choc (0 = pas du tout)
@export var parade_secousse := 3.0

## TALISMAN « LAME CORROMPUE » (1er oct. 2026, id "lame_corrompue") :
## chaque coup d'épée qui porte EMPOISONNE l'ennemi — le même poison
## que le Sang corrompu (`empoisonner`, `poison_degats`…, prolongé à chaque
## coup, sans cumul) — et le slash vire au violet ; avec la Lame de foudre, sa
## foudre et l'éclair qui bondit virent au violet aussi, et l'ennemi que
## l'éclair touche est empoisonné à son tour. Voir animator.gd
## (`_on_body_entered`, `_foudre_bondir`, `_habiller_slash`).
const TALISMAN_LAME_CORROMPUE := "lame_corrompue"
@export_subgroup("Lame corrompue")
## le slash corrompu (la couleur de sa lame) ; sa foudre avec la Lame de
## foudre : le trait, le halo ; le cœur de l'éclair qui bondit
@export var lame_corrompue_couleur := Color(0.7, 0.38, 1.0)
@export var lame_corrompue_foudre := Color(0.78, 0.5, 1.0)
@export var lame_corrompue_halo := Color(0.52, 0.12, 0.9)
@export var lame_corrompue_coeur_foudre := Color(0.95, 0.86, 1.0)

## TALISMAN « PRISE FERME » (1er oct. 2026, id "prise") :
## accroché à un mur (état WALL_JUMP), on ne glisse plus — on reste où on s'est
## accroché ; bas maintenu, on glisse comme avant pour descendre. Voir
## `wall_jump_execute`.
const TALISMAN_PRISE := "prise"

## TALISMAN « VENIN » (1er oct. 2026, id "venin") : un ennemi EMPOISONNÉ (Sang
## corrompu, Lame corrompue) prend `venin_multiplicateur` fois TOUS nos coups,
## le poison compris — appliqué dans BASE_IA.apply_damage (`_venin`) ; l'éclat
## d'un coup d'épée renforcé se cerne de violet (animator.gd `_eclat_impact`).
const TALISMAN_VENIN := "venin"
@export_subgroup("Venin")
@export var venin_multiplicateur := 1.3

## TALISMAN « COUP DE GRÂCE » (1er oct. 2026, id "grace") : un ennemi à moins
## d'un quart de sa vie (BASE_IA.SEUIL_GRACE ; pas les vrais boss, `vrai_boss` —
## le skeleton_boss est un élite, il y passe)
## se fissure de rouge, et notre prochain coup d'épée l'ACHÈVE : il vole en
## éclats (SCRIPT/SHADER/grace_eclats.tscn), la jauge reprend
## `grace_bloodheal` (50 = une demi-barre), la caméra tremble. Voir
## animator.gd (`_on_body_entered`) et `grace_executer`.
const TALISMAN_GRACE := "grace"
const GRACE_SCENE := preload("res://SCRIPT/SHADER/grace_eclats.tscn")
@export_subgroup("Coup de grâce")
@export var grace_bloodheal := 50
@export var grace_secousse := 5.0

## TALISMAN « SANG CRISTALLISÉ » (1er oct. 2026, id "cristal") : une boule de
## sang (ou la Tornade) qui touche a `cristal_chance` (une sur cinq :
## à chaque boule c'était trop fort) de FIGER l'ennemi `cristal_duree` s
## dans le cristal (BASE_IA.cristalliser : une statue rouge, sobre — pas de
## bulle comme le Bouclier, trop gros) ; notre coup d'épée suivant le BRISE pour
## `cristal_bonus` fois ses dégâts. Voir bloodball.gd et animator.gd.
const TALISMAN_CRISTAL := "cristal"
@export_subgroup("Sang cristallisé")
@export_range(0.0, 1.0) var cristal_chance := 0.2
@export var cristal_duree := 1.5
@export var cristal_bonus := 1.5

## TALISMAN « PLUMES ACÉRÉES » (1er oct. 2026, id "plumes") — IL FAUT LE
## DOUBLE SAUT (sans lui, rien : précisé dans la description) :
## à chaque double saut, l'aile lâche `plumes_nombre` plumes acérées qui fondent
## vers le sol en éventail (`plumes_eventail` degrés de part et d'autre de la
## verticale) ; chacune blesse le premier ennemi qu'elle touche pour
## `plumes_part` d'un coup d'épée (bonus compris), sans recul, puis se plante
## (dans le sol aussi) et s'efface — SCRIPT/SHADER/plume_aceree.tscn, aux
## couleurs de l'aile. Voir `_plumes_lancer` (appelé par `_try_double_jump`).
const TALISMAN_PLUMES := "plumes"
const PLUME_ACEREE := preload("res://SCRIPT/SHADER/plume_aceree.tscn")
@export_subgroup("Plumes acérées")
@export var plumes_nombre := 5
## chaque plume vaut un coup d'épée entier (70 sans bonus) — à 0,35 (25) c'était
## trop faible
@export var plumes_part := 1.0
@export var plumes_vitesse := 950.0
@export var plumes_eventail := 36.0

## TALISMAN « SANG VERSÉ » (1er oct. 2026, id "sang_verse") :
## chaque cœur perdu remplit la jauge de soin de `sang_verse_par_coeur` (50 = une
## demi-barre ; un soin coûte `HEAL_COST`, 100) — voir `_sang_verse`, appelé
## quand un coup est VRAIMENT encaissé (`apply_damage`, `apply_environment_damage` :
## pas s'il est paré, esquivé, ou si on en meurt).
const TALISMAN_SANG_VERSE := "sang_verse"
@export_subgroup("Sang versé")
@export var sang_verse_par_coeur := 50

@export_subgroup("Reliquaire et âmes perdues")
## LE SANG PERDU À LA MORT (1er oct. 2026) : en mourant, on perd
## `blood_perdu_a_la_mort` du sang récolté (le compteur `Player.blood`, les
## « âmes ») — 1 = tout, 0 = rien. JUSQUE-LÀ ON NE PERDAIT RIEN : ajouté avec le
## talisman « RELIQUAIRE » (id "reliquaire"), qui en GARDE
## `reliquaire_part` (50 %) sur nous. Voir `_perdre_blood`, dans `dead_enter`.
## CE QU'ON PERD N'EST PAS PERDU TOUT DE SUITE (1er oct. 2026, comme
## dans les Souls) : il attend en ESPRIT DE SANG (SCRIPT/SHADER/esprit_sang.tscn)
## à `ames_hauteur` px au-dessus du dernier sol sûr (`_dernier_sol_sur` : au
## sol, ni mort ni sonné, depuis `SOL_SUR_IMAGES` images — jamais au fond d'un
## trou ni dans des piques) ; le toucher le rend. Mourir de nouveau avant : il
## est perdu pour de bon. Avec le Reliquaire, l'esprit ne porte que la moitié
## qu'on n'a pas gardée. Voir `_ames_poser` et l'autoload (`laisser_ames`,
## `reprendre_ames`).
@export_range(0.0, 1.0) var blood_perdu_a_la_mort := 1.0
const TALISMAN_RELIQUAIRE := "reliquaire"
@export_range(0.0, 1.0) var reliquaire_part := 0.5
const ESPRIT_SANG_SCENE := preload("res://SCRIPT/SHADER/esprit_sang.tscn")
const SOL_SUR_IMAGES := 6
@export var ames_hauteur := 64.0
var _dernier_sol_sur := Vector2.INF
var _au_sol_depuis := 0

@export_subgroup("Croissant de sang")
## TALISMAN « CROISSANT DE SANG » (1er oct. 2026, id "croissant") : le DERNIER
## coup du combo (le 2e : le combo n'en a que deux) projette son slash vers
## l'avant (animator.gd, `_croissant`) ; ses
## dégâts = cette part d'un coup d'épée (bonus compris). Sa vitesse et sa
## portée : SCRIPT/SHADER/croissant_sang.tscn.
@export var croissant_part := 1.0
## à quel moment du slash il s'en détache (0 = au départ du coup, 1 = à la
## fin ; 0,5 = quand la lame passe droit devant le perso)
@export_range(0.0, 1.0, 0.01) var croissant_depart := 0.5
## combien de temps avant ce départ il « prend » sur la lame, attaché à elle (s)
@export var croissant_amorce := 0.05

## TALISMAN « ESSAIM » (1er oct. 2026, id "essaim") : chaque ennemi que NOUS
## tuons (épée, boule, épines, brume, croissant… et les chauves-souris
## elles-mêmes : la chaîne est voulue) lâche `essaim_nombre` chauves-souris de
## sang de son cadavre ; elles SUIVENT le joueur tant qu'elles n'ont pas de
## proie, puis fondent sur les ennemis proches et les mordent pour
## `essaim_part` d'un coup d'épée (bonus compris), sans recul — voir
## `_on_monstre_tue`. Jamais plus de `essaim_max` en vol (0 = sans limite) :
## elles s'accumulent entre deux combats. Elles nous suivent D'UN TABLEAU À
## L'AUTRE (`_essaim_reprendre`, d'après `Player.essaim_en_vol`) ; la mort les
## disperse. Leur vol et leur allure : SCRIPT/SHADER/chauve_souris_sang.tscn.
const TALISMAN_ESSAIM := "essaim"
const CHAUVE_SOURIS_SCENE := preload("res://SCRIPT/SHADER/chauve_souris_sang.tscn")
@export_subgroup("Essaim")
@export var essaim_nombre := 2
@export var essaim_part := 0.5
@export var essaim_max := 10

## TALISMAN « OFFRANDE » (1er oct. 2026, id "offrande") : se soigner fait
## naître un SCEAU de sang sous nos pieds (au début du soin) ; à peine dessiné,
## il lâche une ONDE qui court au sol jusqu'à `offrande_rayon` px et blesse
## (`offrande_part` d'un coup d'épée, bonus compris) et repousse les ennemis
## qu'elle atteint, sans passer les murs — de quoi finir son soin tranquille.
## Le sceau brille tant que dure le soin et s'éteint avec lui (fini ou
## interrompu) — voir `_offrande_lancer`. L'allure :
## SCRIPT/SHADER/sceau_sang.tscn.
const TALISMAN_OFFRANDE := "offrande"
const SCEAU_SCENE := preload("res://SCRIPT/SHADER/sceau_sang.tscn")
@export_subgroup("Offrande")
@export var offrande_rayon := 280.0
@export var offrande_part := 1.0
var _sceau: Node2D

## TALISMAN « SANG BOUILLANT » — ÉBULLITION (1er oct. 2026, id "bouillant") :
## chaque coup d'épée ou de boule de sang qui touche un ennemi fait bouillir son
## sang (une charge, des bulles) ; à la troisième charge il EXPLOSE : lui et ses
## voisins à moins de `bouillant_rayon` px (sans mur entre eux) prennent
## `bouillant_part` d'un coup d'épée (bonus compris), sans recul. Sans coup
## pendant `bouillant_duree_charge` s, les charges retombent. Voir
## `bouillant_charger` (appelé par animator.gd, bloodball.gd et ombre_sang.gd :
## le coup du double de l'Ombre de sang charge aussi) ; l'allure (les bulles,
## l'explosion) :
## SCRIPT/SHADER/bouillon_sang.tscn. (v1 : les ennemis TUÉS explosaient en
## cascade — inutile sans groupes, et la Lame de foudre faisait mieux.)
const TALISMAN_BOUILLANT := "bouillant"
const BOUILLON_SCENE := preload("res://SCRIPT/SHADER/bouillon_sang.tscn")
@export_subgroup("Sang bouillant")
@export var bouillant_rayon := 180.0
@export var bouillant_part := 1.0
@export var bouillant_duree_charge := 3.0
## la caméra tremble à chaque explosion (0 = pas du tout)
@export var bouillant_secousse := 6.0

## TALISMAN « OMBRE DE SANG » (1er oct. 2026, id "ombre") : quand notre épée
## touche, un double de sang surgit DERRIÈRE l'ennemi, refait notre coup en
## miroir et le frappe à son tour pour `ombre_part` des dégâts d'un coup
## (bonus compris), sans recul (il nous renverrait l'ennemi dessus) —
## `ombre_surgir`, appelé par
## animator.gd ; le double : SCRIPT/SHADER/ombre_sang.gd. (v1 : un double qui
## nous suivait avec du retard ; il ne touchait jamais, le recul de notre coup
## avait déjà emporté l'ennemi.)
const OMBRE_SCENE := preload("res://SCRIPT/SHADER/ombre_sang.tscn")
@export_subgroup("Ombre de sang")
@export var ombre_part := 0.5

## TALISMAN « SANG CORROMPU » (1er oct. 2026, id "corrompu") :
## la boule de sang — et la Tornade si elle est portée — vire au violet et
## EMPOISONNE l'ennemi qu'elle touche : il perd `poison_degats` PV toutes les
## `poison_intervalle` s pendant `poison_duree` s (Canon de verre compris, sans
## recul) ; une nouvelle boule relance le compte, sans cumul. Voir
## `bloodball_enter` (les couleurs) et `empoisonner` ; le poison :
## SCRIPT/SHADER/poison_sang.gd.
const TALISMAN_CORROMPU := "corrompu"
const POISON_SCENE := preload("res://SCRIPT/SHADER/poison_sang.tscn")
@export_subgroup("Sang corrompu")
@export var poison_degats := 15
@export var poison_intervalle := 0.5
@export var poison_duree := 3.0
## les couleurs de la boule corrompue (de la tornade et de leur impact aussi) :
## son cœur, sa couleur, son ombre
@export var corrompu_coeur := Color(0.93, 0.72, 1.0)
@export var corrompu_couleur := Color(0.58, 0.14, 0.84)
@export var corrompu_ombre := Color(0.19, 0.02, 0.31)

## TALISMAN « GARDIENNES » (1er oct. 2026, id "gardiennes") : tant qu'il est porté,
## deux gouttes de sang tournent autour de nous — elles blessent les ennemis
## qu'elles touchent pour `gardiennes_part` d'un coup d'épée (bonus compris),
## sans recul, et fondent sur les tirs ennemis qui nous visent pour éclater avec
## eux, puis se reforment. Leur ronde, leur garde et leur allure :
## SCRIPT/SHADER/gardiennes_sang.tscn, posé une fois par `_gardiennes_preparer`.
const GARDIENNES_SCENE := preload("res://SCRIPT/SHADER/gardiennes_sang.tscn")
@export_subgroup("Gardiennes")
@export var gardiennes_part := 0.5
var _gardiennes: Node2D

## TALISMAN « SOIN ÉCLAIR » (1er oct. 2026, id "soin_eclair") :
## l'animation de soin — le temps où l'on reste planté, à la merci d'un coup qui
## l'interrompt — joue `soin_eclair_vitesse` fois plus vite (0,73 s → 0,37 s).
## Même coût, mêmes cœurs. Voir `heal_enter`.
const TALISMAN_SOIN_ECLAIR := "soin_eclair"
@export_subgroup("Soin éclair")
@export var soin_eclair_vitesse := 2.0

## TALISMAN « CŒUR NOIR » (1er oct. 2026, id "coeur_noir") : un
## cœur NOIR s'ajoute aux nôtres — un seul, jamais plus — `coeur_noir_recharge` s
## après l'avoir perdu, et à chaque checkpoint touché (et au respawn, qui se fait
## à un checkpoint). Il prend le PREMIER point de dégât d'un coup (Canon de
## verre : un coup de 2 brise le cœur noir puis un rouge) ; le coup est encaissé
## quand même (recul, Vengeance, Épines…). En se BRISANT, il frappe tous les
## monstres VISIBLES À L'ÉCRAN pour `coeur_noir_part` d'un coup d'épée (bonus compris),
## avec recul : une onde noire part de nous et les frappe quand elle les atteint
## (SCRIPT/SHADER/coeur_noir_onde.tscn). Il vit dans l'autoload
## (`Player.coeur_noir`, `coeur_noir_attente`) ; le HUD le montre après les
## cœurs rouges (gestion_interface.gd, `coeur_noir_fx`). Voir `_coeur_noir_tick`,
## `_coeur_noir_absorbe`, `_coeur_noir_eclater`.
## TALISMAN « COURONNE DU DÉFI » (1er oct. 2026, id "defi") :
## un seul cœur, tous les autres talismans retirés et verrouillés (tout cela vit
## dans l'autoload : `equiper_talisman`, `retirer_talisman`, `add_max_hp`) — et
## une magnifique couronne d'or qui tourne au-dessus de la tête :
## SCRIPT/SHADER/couronne_defi.tscn, posée une fois par `_couronne_defi_preparer`
## (elle se montre et se cache seule).
const COURONNE_DEFI_SCENE := preload("res://SCRIPT/SHADER/couronne_defi.tscn")

const TALISMAN_COEUR_NOIR := "coeur_noir"
const COEUR_NOIR_ONDE := preload("res://SCRIPT/SHADER/coeur_noir_onde.tscn")
@export_subgroup("Cœur noir")
@export var coeur_noir_recharge := 120.0
@export var coeur_noir_part := 2.0
## la caméra tremble quand il éclate (0 = pas du tout)
@export var coeur_noir_secousse := 7.0

@export_subgroup("Entraves")
## TALISMAN « ENTRAVES » (1er oct. 2026, id "entraves") : chaque
## coup d'épée qui porte ENTRAVE l'ennemi — il vit à `entraves_facteur` de sa
## vitesse pendant `entraves_duree` s (marche, vol, chute, coups, animation), au
## sol comme en vol ; un nouveau coup relance le temps, sans cumul. Un anneau de
## sang l'enserre. Voir animator.gd (`_on_body_entered`) et BASE_IA.gd
## (`entraver`) ; l'anneau : SCRIPT/SHADER/entrave_sang.tscn.
@export var entraves_duree := 2.0
@export var entraves_facteur := 0.6

## TALISMAN « TROP-PLEIN » (2 oct. 2026, id "trop_plein") : le
## miroir de la Marque — `trop_plein_coups_requis` coups d'épée qui portent (un
## par coup, même s'il touche plusieurs ennemis) remplissent la boule : la
## suivante sort `trop_plein_taille` fois plus grosse et fait
## `trop_plein_degats` fois ses dégâts (la Tornade aussi). Pour le voir venir :
## une ROUE de sang au-dessus de l'épaule, comme la jauge d'endurance de Zelda,
## qui se remplit en tournant d'un tiers à chaque coup ; pleine, son
## cœur se remplit et bat ; elle crève au lancer
## (SCRIPT/SHADER/trop_plein_jauge.tscn). Voir animator.gd (`_on_body_entered`)
## et `bloodball_enter`.
const TALISMAN_TROP_PLEIN := "trop_plein"
const TROP_PLEIN_JAUGE := preload("res://SCRIPT/SHADER/trop_plein_jauge.tscn")
@export_subgroup("Trop-plein")
@export var trop_plein_coups_requis := 3
@export var trop_plein_taille := 2.0
@export var trop_plein_degats := 2.0
var trop_plein_coups := 0
var _trop_plein: Node2D

## TALISMAN « INÉBRANLABLE » (2 oct. 2026, id "inebranlable") :
## un coup d'ENNEMI encaissé ne fait plus reculer ni vaciller — pas d'état HIT,
## pas de recul : on garde la main (un coup d'épée en cours continue). Le cœur
## est perdu quand même, et tout ce qu'un coup encaissé déclenche part
## (Vengeance, Épines, Bouclier…). À la place du vacillement, l'effet du PAS
## DE CÔTÉ (plutôt qu'un clignotement) : un fantôme reste sur place et
## glisse vers le coup, le corps blêmit un instant (`_fantome_esquive`) ; et
## pendant `inebranlable_repit` s — la grâce du pas de côté — le même coup ne
## repasse pas (sauf ceux qui percent le vacillement, comme les explosions).
## Les PIÈGES gardent leur renvoi (il nous sort des piques), et un coup
## interrompt toujours le SOIN. Voir `apply_damage`.
const TALISMAN_INEBRANLABLE := "inebranlable"
@export_subgroup("Inébranlable")
@export var inebranlable_repit := 0.35
var _inebranlable_reste := 0.0

## TALISMAN « SIXIÈME COUP » (2 oct. 2026, id "sixieme") : un
## coup d'épée qui porte sur `sixieme_tous_les` est CRITIQUE — il fait
## `sixieme_multiplicateur` fois ses dégâts ; son étoile d'impact grandit et se
## cerne de sang, la caméra tremble un peu. Compté une fois par coup d'épée,
## même s'il touche plusieurs ennemis (tous prennent le critique). Voir
## animator.gd (`_on_body_entered`), `sixieme_critique`, `sixieme_porte`.
const TALISMAN_SIXIEME := "sixieme"
@export_subgroup("Sixième coup")
@export var sixieme_tous_les := 6
@export var sixieme_multiplicateur := 2.0
## la caméra tremble au coup critique (0 = pas du tout)
@export var sixieme_secousse := 4.0
## la taille de son étoile d'impact (celle d'un coup dans le dos : 1,3 ; une
## étoile ×2,2 couvrait le héros ET l'ennemi)
@export var sixieme_eclat_taille := 1.6
var sixieme_compte := 0
var _sixieme_coup_compte := -1      # le coup d'épée déjà compté
var _sixieme_coup_critique := -1    # le coup d'épée critique

## TALISMAN « PACTE DE SANG » (2 oct. 2026, id "pacte") :
## chaque boule de sang boit `pacte_cout` de la jauge de soin (un tiers de soin)
## et fait `pacte_multiplicateur` fois ses dégâts, dans le sang sombre du pacte
## (corrompue, elle reste violette) ; jauge trop basse : elle part normale,
## gratuite. ×3 (essayé à ×2 le même jour : le coût n'en valait plus la
## peine). Voir `bloodball_enter`
## et bloodball.gd (`pacte`).
const TALISMAN_PACTE := "pacte"
@export_subgroup("Pacte de sang")
@export var pacte_cout := 34
@export var pacte_multiplicateur := 3.0
@export var pacte_coeur := Color(1.0, 0.7, 0.58)
@export var pacte_couleur := Color(0.52, 0.0, 0.07)
@export var pacte_ombre := Color(0.15, 0.0, 0.03)

## TALISMAN « SANG NEUF » (2 oct. 2026, id "sang_neuf") : au respawn, la jauge
## de soin se remplit jusqu'en haut (au lieu d'un seul soin) — le HUD la montre
## monter `sang_neuf_delai` s après la réapparition. `dead_input` note la mort
## dans l'autoload (`Player.vient_de_mourir`) ; voir `_sang_neuf`.
const TALISMAN_SANG_NEUF := "sang_neuf"
@export_subgroup("Sang neuf")
@export var sang_neuf_delai := 0.6

# AMÉLIORATION: combo_count remplace le bool "combo" — plus clair et extensible
var combo_buffered := false   # true si le joueur a appuyé pendant l'anim en cours





func _enter_tree() -> void:
	# Synchro AVANT le _ready des enfants : le HUD (enfant de cette scène)
	# lit ces valeurs pour construire sa rangée de cœurs.
	# L'export n'est que la valeur de DÉPART : au premier spawn seulement —
	# ensuite l'autoload fait foi, les cœurs ramassés survivent au respawn
	if not Player.hearts_initialized:
		Player.hearts_initialized = true
		Player.max_hearts = MAX_HEARTS
		Player.MAX_HP = MAX_HEARTS
		# début de partie : la jauge de sang offre exactement un soin,
		# comme au respawn
		Player.bloodheal = HEAL_COST
	Player.hp = mini(Player.hp, Player.MAX_HP)


func _ready() -> void:
	# Les raycasts de mur ne détectent QUE les corps solides : une Area2D
	# (checkpoint, grab, porte...) qui chevauche un mur arrêterait le rayon
	# avant le mur et ferait clignoter l'accroche du wall jump
	wall_right.collide_with_areas = false
	wall_left.collide_with_areas = false
	wall_right.collide_with_bodies = true
	wall_left.collide_with_bodies = true

	animator.connect("animation_finished", Callable(self, "_on_animation_finished"))
	set_floor_max_angle(deg_to_rad(60))
	set_floor_snap_length(6.0)
	print(Player.hp,"hp")
	_griffe_preparer()
	_aile_preparer()
	_bouclier_preparer()
	_couronne_preparer()
	_oeil_preparer()
	_gardiennes_preparer()
	_couronne_defi_preparer()
	_trop_plein_preparer()
	# un talisman ôté : le Trop-plein se vide (la connexion meurt avec ce joueur)
	Player.talismans_changes.connect(_trop_plein_verifier)
	# nos victimes (talisman « Essaim ») ; le signal vit dans l'autoload, la
	# connexion meurt avec ce joueur
	Player.monstre_tue.connect(_on_monstre_tue)
	# celles qui nous suivaient au tableau d'avant : relâchées une fois que le
	# spawn nous a posés (il nous déplace juste après nous avoir ajoutés)
	_essaim_reprendre.call_deferred()
	# nos âmes perdues, si c'est ici qu'on est tombé
	_ames_poser.call_deferred()
	# on revient d'une mort ? (talisman « Sang neuf » : la jauge se remplit)
	_sang_neuf.call_deferred()
	initialize_states()
	change_state(States.IDLE)


var _facing_prev := 1.0

func _physics_process(delta: float) -> void:
	state_functions[current_state]["execute"].call(delta)
	# le plané ne vit que dans les états qui l'entretiennent (chute, coup ou
	# sort en l'air) : sol, mur, dash, coup reçu, double saut… replient l'aile
	if _plane and _plane_frame != Engine.get_physics_frames():
		_planer_arreter()
	# Le slash FX est enfant de POINT : si le perso se retourne pendant que
	# la traînée joue, elle partirait en miroir avec lui → on la coupe.
	# Détection centralisée ici pour couvrir tous les flips (run, jump, chute...)
	if signf(point.scale.x) != signf(_facing_prev):
		_cut_slash_fx()
	_facing_prev = point.scale.x
	# Recharge du double saut + référence des dégâts de chute : au sol elle
	# suit le perso ; en l'air elle garde le point le PLUS HAUT du vol —
	# un double saut ne peut donc jamais effacer une chute accumulée
	if _au_sol():
		_double_jump_used = false
		_air_dash_used = false
		FALL_POINT = global_position.y
	else:
		FALL_POINT = minf(FALL_POINT, global_position.y)
	# Knockback absolu — même principe que les monstres (BASE_IA) : tant qu'il
	# est actif, il remplace le déplacement horizontal, via velocity pour que
	# move_and_slide glisse le long du sol
	if _knock != Vector2.ZERO:
		velocity.x = _knock.x
	_trainee_tick()          # la traînée du dash / de la roulade (avant de bouger)
	_sillage_tick()          # le talisman « sillage de sang » (même moment)
	_coeur_noir_tick(delta)  # le talisman « cœur noir » : il revient
	var v_etat := _poussees_appliquer(delta)
	move_and_slide()
	_faux_sol_tick()              # le moteur a-t-il pris un mur pour sol ?
	_poussees_rendre(v_etat)      # trou noir, vent : notre vitesse nous revient
	# le câble du grappin se trace APRÈS le déplacement (sinon il part de la
	# main du pas précédent et dépasse du bras, voir _grappin_tracer_cable)
	if current_state == States.GRAPPIN:
		_grappin_tracer_cable()
	# la trace de la griffe aussi, pour la même raison
	if current_state == States.WALL_GRIFFE:
		_griffe_tracer()
	_decay_knockback(delta)
	# le dernier sol sûr : nos âmes y attendront si on meurt
	if _au_sol() and current_state != States.DEAD and current_state != States.HIT:
		_au_sol_depuis += 1
		if _au_sol_depuis >= SOL_SUR_IMAGES:
			_dernier_sol_sur = global_position
	else:
		_au_sol_depuis = 0
	_corde_cooldown = maxf(_corde_cooldown - delta, 0.0)
	_grappin_cooldown = maxf(_grappin_cooldown - delta, 0.0)
	_bouclier_recharge_reste = maxf(_bouclier_recharge_reste - delta, 0.0)
	_esquive_grace_reste = maxf(_esquive_grace_reste - delta, 0.0)
	if vengeance_reste > 0.0:
		vengeance_reste = maxf(vengeance_reste - delta, 0.0)
		if vengeance_reste == 0.0 and _couronne != null:
			_couronne.effacer()      # le temps a passé : la vengeance retombe
	# la série du crescendo s'éteint sans coup qui porte
	if crescendo_serie > 0 and crescendo_delai > 0.0:
		_crescendo_reste -= delta
		if _crescendo_reste <= 0.0:
			crescendo_casser()
	_souffle_grace_reste = maxf(_souffle_grace_reste - delta, 0.0)
	Player.second_souffle_attente = maxf(Player.second_souffle_attente - delta, 0.0)
	# INÉBRANLABLE : la grâce qui suit un coup encaissé sans vaciller
	_inebranlable_reste = maxf(_inebranlable_reste - delta, 0.0)
	_grappin_scanner()


# ---------------------------------------------------------------------------
# LES FORCES DES PIÈGES (2 oct. 2026) : le TROU NOIR nous aspire (`aspirer`),
# le VENT nous pousse (`souffler`). Chacun redonne À CHAQUE IMAGE la vitesse
# qu'il nous impose là où on est (px/s) :
#   • le trou noir : en largeur, sa vitesse s'AJOUTE à la nôtre le temps du
#     pas, puis elle est retirée (notre course la combat : le héros court à
#     700 px/s) ; en hauteur, c'est une ACCÉLÉRATION comme la gravité (×4) :
#     debout dessous, on ne décolle que s'il tire plus fort qu'elle ;
#   • le vent nous donne de l'ÉLAN : il nous entraîne vers sa vitesse (×6, en
#     un rien de temps), et cet élan CONTINUE après le courant — en l'air on
#     file loin, au sol on glisse un peu ; un mur l'arrête net.
# Agrippé (échelle, corde, rebord, mur, grappin), on tient bon ; mort, plus rien.
const POUSSEE_RAIDEUR := 4.0        # le trou noir en hauteur : sa vitesse ×4, en px/s²
const VENT_RAIDEUR := 6.0           # le vent : sa vitesse ×6, en px/s²
const ELAN_AMORTI_AIR := 1.2        # l'élan du vent retombe de tant par seconde, en l'air…
const ELAN_AMORTI_SOL := 6.0        # … et au sol
var _aspiration := Vector2.ZERO
var _vent := Vector2.ZERO
var _elan_x := 0.0                  # l'élan du vent en largeur (en hauteur, il vit dans velocity)
var _pousse_ce_pas := false

func aspirer(v: Vector2) -> void:
	_aspiration += v


func souffler(v: Vector2) -> void:
	_vent += v


## avant move_and_slide : les poussées s'ajoutent ; rend la vitesse d'avant elles
func _poussees_appliquer(delta: float) -> Vector2:
	var a := _aspiration
	var w := _vent
	_aspiration = Vector2.ZERO
	_vent = Vector2.ZERO
	_pousse_ce_pas = false
	if current_state in [States.DEAD, States.ECHELLE, States.CORDE, States.GRAB, States.CLIMB,
			States.GRAPPIN, States.WALL_GRIFFE]:
		_elan_x = 0.0
		return velocity
	if absf(w.x) > 1.0:
		_elan_x = _vers_le_vent(_elan_x, w.x, delta)
	elif _elan_x != 0.0:
		_elan_x = _elan_amortir(_elan_x, is_on_floor(), delta)
	if a == Vector2.ZERO and w == Vector2.ZERO and _elan_x == 0.0:
		return velocity
	velocity.y += a.y * POUSSEE_RAIDEUR * delta       # le trou noir : une accélération, elle reste
	velocity.y = _vers_le_vent(velocity.y, w.y, delta)
	var v_etat := velocity
	velocity.x += a.x + _elan_x
	_pousse_ce_pas = true
	return v_etat


## vers la vitesse du vent `vent` (sur un axe) : on y est entraîné d'autant
## plus vite qu'il est fort (un souffle faible ne vainc pas la gravité), mais il
## ne freine jamais ce qui file déjà plus vite que lui dans son sens
func _vers_le_vent(v: float, vent: float, delta: float) -> float:
	if absf(vent) < 1.0:
		return v
	var n := v + vent * VENT_RAIDEUR * delta
	if vent < 0.0:
		return maxf(n, minf(v, vent))
	return minf(n, maxf(v, vent))


## l'élan du vent, hors du courant : il retombe vite au sol, lentement en l'air
func _elan_amortir(e: float, au_sol: bool, delta: float) -> float:
	var amorti := ELAN_AMORTI_SOL if au_sol else ELAN_AMORTI_AIR
	e = move_toward(e, 0.0, (absf(e) * amorti + 20.0) * delta)
	return e if absf(e) > 5.0 else 0.0


## après move_and_slide : la vitesse d'avant les poussées revient, moins ce que
## le sol, un mur ou le plafond a arrêté pendant le pas
func _poussees_rendre(v_etat: Vector2) -> void:
	if not _pousse_ce_pas:
		return
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		var d := v_etat.dot(n)
		if d < 0.0:
			v_etat -= n * d
		# l'élan du vent s'écrase sur un MUR (pas sur le sol : sa normale garde
		# une poussière de largeur, ~1e-8, qui le remettait à zéro à chaque image)
		if n.x * signf(_elan_x) < -0.5:
			_elan_x = 0.0
	velocity = v_etat


var _knock := Vector2.ZERO

func _decay_knockback(delta: float) -> void:
	if _knock == Vector2.ZERO:
		return
	_knock = _knock.lerp(Vector2.ZERO, clamp(HIT_X_DAMP * delta, 0.0, 1.0))
	# Seuil de coupure haut (150 px/s) : dès que la poussée devient faible,
	# le joueur reprend IMMÉDIATEMENT le contrôle — pas de queue de knockback
	# qui écrase sa vitesse de course et donne une sensation de ralenti
	if _knock.length_squared() < 22500.0:
		_knock = Vector2.ZERO
		velocity.x = 0.0


## Contrecoup quand le joueur frappe un ennemi inébranlable (sans knockback) :
## si le joueur est en mouvement, une contre-poussée inverse annule son élan
func cancel_movement_recoil() -> void:
	if absf(velocity.x) < 1.0:
		return
	_knock.x = -velocity.x * 1.56  # contrecoup amplifié : 1.2 × 1.3 (+30%)
	velocity.x = 0.0


func _cut_slash_fx() -> void:
	animator.couper_slash()      # le slash dessiné ET le slash en shader


### GESTION DES INPUTS ###
func _input(event):
	# DEBUG spell : l'événement arrive-t-il jusqu'au player, et dans quel état ?
	if event.is_action_pressed("spell"):
		print("[SPELL] événement reçu — état=", States.keys()[current_state])
	# GRAPPIN : touche dédiée, valable dans les états listés (sol et air)
	if event.is_action_pressed("grapin") and _try_grappin():
		return
	if state_functions[current_state].has("input"):
		state_functions[current_state]["input"].call(event)

# Dispatcher animation_finished (sans argument)
func _on_animation_finished() -> void:
	var funcs = state_functions[current_state]
	if funcs.has("animation_finished"):
		funcs["animation_finished"].call()


# ---------------------------------------------------------
#  UTILITAIRES
# ---------------------------------------------------------

## goto_state : transition DIFFÉRÉE (call_deferred) — à utiliser depuis execute/physics
## pour éviter de changer d'état pendant qu'on est encore dans le callback.
## change_state : transition IMMÉDIATE — à utiliser depuis input/animation_finished.
# AMÉLIORATION: documentation claire de la distinction



func _handle_landing() -> void:
	calcule_falling_damage()
	if current_state == States.DEAD or current_state == States.HIT:
		return
	var land_fx = instantiate_scene(CHUTE_SCENE)
	land_fx.global_position = ANCRE_SOL.global_position
	if land_fx is AnimatedSprite2D:
		land_fx.play()
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer = 0.0
		goto_state(States.JUMP)
		return
	if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
		goto_state(States.RUN)
	else:
		goto_state(States.IDLE)

## `perce_stun` : réservé aux sources qui ne frappent QU'UNE FOIS (le souffle
## d'un kamikaze). Les sources continues — contact d'un monstre, piques, jet de
## flammes — sont relues à chaque frame et ont besoin du stun pour ne pas vider
## la barre en une seconde ; un souffle, lui, ne part qu'un coup par bombe, et
## sans ça quatre kamikazes qui explosent ensemble ne coûtent qu'un seul cœur
## (vécu le 18 sept. 2026). La roulade et le dash restent des parades absolues.
func apply_damage(amount: int, source_x, source_tag := "?", perce_stun := false, attaquant: Node = null) -> void:
	if current_state in [States.ROLL, States.DASH, States.DEAD]:
		return
	if current_state == States.HIT and not perce_stun:
		# DEBUG dégâts : coup ignoré pendant le stun
		# (AVANT le bouclier et le pas de côté : un coup déjà encaissé ne doit
		#  plus rien déclencher. Le contact d'une larve rappelle apply_damage à
		#  chaque image pendant le stun ; le dé du pas de côté tombait alors
		#  APRÈS le dégât et on voyait le fantôme d'un coup pourtant pris.)
		print("[DMG bloqué/stun] f=", Engine.get_physics_frames(),
			" src=", source_tag, " amount=", amount)
		return
	# INÉBRANLABLE : le répit qui suit un coup encaissé sans vaciller tient le
	# rôle du vacillement : aucun coup ne passe (sauf ceux qui le percent)
	if _inebranlable_reste > 0.0 and not perce_stun:
		return
	# le répit qui suit un second souffle : aucun coup ne passe
	if _souffle_grace_reste > 0.0:
		return
	# la parade d'abord : un coup paré n'est pas encaissé, rien d'autre ne part
	if _parade_tente(source_x, source_tag, attaquant):
		return
	if _bouclier_pare(source_x, source_tag):
		return
	if _esquive_tente(source_x, source_tag):
		return
	# canon de verre (dégâts reçus multipliés), puis le cœur noir (il prend le
	# premier point), puis second souffle (un coup mortel nous laisse à un cœur)
	amount = _second_souffle(_coeur_noir_absorbe(_degats_recus(amount), source_tag), source_tag)
	print("[DMG] f=", Engine.get_physics_frames(),
		" src=", source_tag, " amount=", amount,
		" état=", States.keys()[current_state],
		" hp ", Player.hp, " -> ", Player.hp - amount)
	Player.changement_de_vie(-amount)
	_sang_verse(amount)
	# l'éclat de sang part dans le sens où le coup nous envoie ; source
	# inconnue (une chute) : vers le haut
	var sens_coup := Vector2.UP
	if source_x != null:
		sens_coup = Vector2(1.0 if global_position.x > float(source_x) else -1.0, 0.0)
	_eclat_sang(sens_coup)
	if Player.hp <= 0:
		_knock = Vector2.ZERO
		change_state(States.DEAD)
		return
	if Player.talisman_equipe(TALISMAN_INEBRANLABLE) and current_state != States.HEAL:
		# INÉBRANLABLE : ni recul ni vacillement, on garde la main ; à la place,
		# l'effet du pas de côté : un fantôme reste sur place et glisse vers le
		# coup, le corps blêmit — et sa grâce : le même coup ne repasse pas
		_inebranlable_reste = inebranlable_repit
		var dir_coup := 0
		if source_x != null:
			dir_coup = 1 if (global_position.x - float(source_x)) > 0.0 else -1
		elif last_direction != 0:
			dir_coup = -last_direction
		_fantome_esquive(Vector2(-dir_coup, 0.0))
		print("[INÉBRANLABLE] f=", Engine.get_physics_frames(), " coup encaissé sans vaciller (",
			States.keys()[current_state], ") ; répit ", inebranlable_repit, " s")
	else:
		# Knockback horizontal absolu, l'état HIT gère stun + anim
		var dir := 0
		if source_x != null:
			dir = 1 if (global_position.x - source_x) > 0 else -1
		_knock = Vector2(dir * HIT_KNOCK_X, 0.0)
		change_state(States.HIT)
		# Soulèvement : impulsion verticale one-shot, appliquée APRÈS hit_enter
		# (qui remet velocity à zéro) — la gravité gère la retombée
		velocity.y = HIT_KNOCK_Y
	# le coup est encaissé : le bouclier de sang se dresse du côté d'où il vient
	_bouclier_lever(-sens_coup)
	_epines_jaillir()
	_vengeance_charger()
	crescendo_casser()          # un coup encaissé : la série retombe


## --- le cœur noir ---

## porté, il revient s'il manque (au bout de son attente) ; ôté, il disparaît
func _coeur_noir_tick(delta: float) -> void:
	if not Player.talisman_equipe(TALISMAN_COEUR_NOIR):
		if Player.coeur_noir:
			Player.coeur_noir = false
			_coeur_noir_hud("ote")
		return
	if Player.coeur_noir or Player.hp <= 0:
		return
	Player.coeur_noir_attente = maxf(Player.coeur_noir_attente - delta, 0.0)
	if Player.coeur_noir_attente <= 0.0:
		Player.coeur_noir = true
		_coeur_noir_hud("gagne")
		print("[CŒUR NOIR] f=", Engine.get_physics_frames(), " un cœur noir s'ajoute")


## un coup de `amount` arrive : le cœur noir en prend le premier point et se
## brise (il éclate : l'onde) ; renvoie ce qu'il reste pour les cœurs rouges
func _coeur_noir_absorbe(amount: int, source_tag: String) -> int:
	if amount <= 0 or not Player.coeur_noir or not Player.talisman_equipe(TALISMAN_COEUR_NOIR):
		return amount
	Player.coeur_noir = false
	Player.coeur_noir_attente = coeur_noir_recharge
	_coeur_noir_hud("perdu")
	_sang_verse(1)                 # un cœur perdu, tout noir qu'il est
	print("[CŒUR NOIR] f=", Engine.get_physics_frames(), " brisé par un coup (", source_tag, ", ", amount,
		") : il en prend 1 ; de retour dans ", coeur_noir_recharge, " s ou au prochain checkpoint")
	_coeur_noir_eclater()
	return amount - 1


## il éclate : tous les monstres visibles à l'écran seront frappés par l'onde
func _coeur_noir_eclater() -> void:
	var vp := get_viewport()
	var vue: Rect2 = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	var c := centre_corps()
	var rect := RectangleShape2D.new()
	rect.size = vue.size
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = rect
	requete.transform = Transform2D(0.0, vue.get_center())
	requete.collision_mask = 8           # la couche des monstres
	requete.collide_with_areas = false
	var cibles := []
	var vus := {}
	for resultat in get_world_2d().direct_space_state.intersect_shape(requete, 64):
		var m = resultat["collider"]
		if not (m is BaseAI) or m.hp <= 0 or not m.est_ennemi(self) or vus.has(m.get_instance_id()):
			continue
		vus[m.get_instance_id()] = true
		var milieu: Vector2 = m.collision.global_position if m.collision != null else m.global_position
		cibles.append({"noeud": m, "id": m.get_instance_id(), "distance": milieu.distance_to(c)})
	# l'onde court jusqu'au coin de l'écran le plus loin de nous
	var loin := 0.0
	for coin in [vue.position, vue.position + Vector2(vue.size.x, 0.0), vue.end, vue.position + Vector2(0.0, vue.size.y)]:
		loin = maxf(loin, c.distance_to(coin))
	var onde := COEUR_NOIR_ONDE.instantiate()
	onde.demo_boucle = false
	onde.joueur = self
	onde.degats = maxi(roundi(animator.degats_du_coup() * coeur_noir_part), 1)
	onde.rayon_max = loin + 40.0
	onde.cibles = cibles
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = get_parent()
	hote.add_child(onde)
	onde.global_position = c
	var cam := get_tree().get_first_node_in_group("Camera")
	if coeur_noir_secousse > 0.0 and cam != null and cam.has_method("shake"):
		cam.shake(coeur_noir_secousse, 9.0)
	print("[CŒUR NOIR] il éclate : ", cibles.size(), " monstre(s) à l'écran, ", onde.degats, " dégâts chacun")


## le HUD montre le cœur noir : « gagne », « perdu » (il se brise), « ote »
func _coeur_noir_hud(quoi: String) -> void:
	var huds := get_tree().get_nodes_in_group("UI_Health")
	if not huds.is_empty() and huds[0].has_method("coeur_noir_fx"):
		huds[0].call_deferred("coeur_noir_fx", quoi)


## --- le canon de verre et le second souffle ---

## les dégâts d'un coup reçu, multipliés par les talismans (Canon de verre : ×2)
func _degats_recus(amount: int) -> int:
	return roundi(amount * Player.multiplicateur_recus())


## Un coup de `amount` arrive : s'il est MORTEL et que le Second souffle est
## porté et prêt, il ne nous laisse qu'à un cœur, et le souffle repart pour
## `second_souffle_recharge` s. Renvoie les dégâts à appliquer vraiment.
func _second_souffle(amount: int, source_tag: String) -> int:
	if Player.hp - amount > 0 or not Player.talisman_equipe(TALISMAN_SOUFFLE):
		return amount
	if Player.second_souffle_attente > 0.0:
		return amount
	Player.second_souffle_attente = second_souffle_recharge
	_souffle_grace_reste = second_souffle_grace
	# le cœur qui se brise et se reforme, en FIN d'image : le HUD repeint ses
	# cœurs à chaque changement de vie (même nul) et effacerait l'effet
	var huds := get_tree().get_nodes_in_group("UI_Health")
	if not huds.is_empty() and huds[0].has_method("souffle_fx"):
		huds[0].call_deferred("souffle_fx")
	print("[SOUFFLE] f=", Engine.get_physics_frames(), " coup mortel (", source_tag,
		", ", amount, ") : il reste un cœur ; de nouveau prêt dans ",
		second_souffle_recharge, " s")
	return maxi(Player.hp - 1, 0)


## --- la vengeance ---

## l'œil du Canon de verre : il se montre et se cache seul selon le talisman
func _oeil_preparer() -> void:
	_oeil = OEIL_CANON.instantiate()
	_oeil.demo_boucle = false
	_oeil.joueur = self
	add_child(_oeil)


## la couronne d'or du défi : elle se montre et se cache seule selon le talisman
func _couronne_defi_preparer() -> void:
	var c := COURONNE_DEFI_SCENE.instantiate()
	c.demo_boucle = false
	add_child(c)


## la roue du Trop-plein : elle se montre et se cache seule selon le compte
func _trop_plein_preparer() -> void:
	_trop_plein = TROP_PLEIN_JAUGE.instantiate()
	_trop_plein.demo_boucle = false
	_trop_plein.joueur = self
	add_child(_trop_plein)


## TROP-PLEIN : un coup d'épée qui porte (animator.gd, une fois par coup) remplit
## la boule d'un cran
func trop_plein_charger() -> void:
	if not Player.talisman_equipe(TALISMAN_TROP_PLEIN) \
			or trop_plein_coups >= trop_plein_coups_requis:
		return
	trop_plein_coups += 1
	print("[TROP-PLEIN] f=", Engine.get_physics_frames(), " coup ", trop_plein_coups,
		"/", trop_plein_coups_requis)


## TROP-PLEIN : la prochaine boule sortira grosse
func trop_plein_pret() -> bool:
	return Player.talisman_equipe(TALISMAN_TROP_PLEIN) \
		and trop_plein_coups >= trop_plein_coups_requis


## le talisman ôté : la boule se vide
func _trop_plein_verifier() -> void:
	if not Player.talisman_equipe(TALISMAN_TROP_PLEIN):
		trop_plein_coups = 0


## SIXIÈME COUP : ce coup d'épée (son numéro) sera-t-il critique ? Demandé AVANT
## de frapper : c'est le cas s'il est le `sixieme_tous_les`-ième à porter (un
## coup déjà compté garde sa réponse : tous ses ennemis prennent le critique)
func sixieme_critique(coup_id: int) -> bool:
	if not Player.talisman_equipe(TALISMAN_SIXIEME):
		return false
	if coup_id == _sixieme_coup_compte:
		return coup_id == _sixieme_coup_critique
	return sixieme_compte + 1 >= sixieme_tous_les


## SIXIÈME COUP : ce coup d'épée a porté — il compte, une fois ; le sixième
## remet le compte à zéro et fait trembler la caméra
func sixieme_porte(coup_id: int) -> void:
	if coup_id == _sixieme_coup_compte:
		return
	_sixieme_coup_compte = coup_id
	sixieme_compte += 1
	if sixieme_compte >= sixieme_tous_les:
		sixieme_compte = 0
		_sixieme_coup_critique = coup_id
		var camera := get_tree().get_first_node_in_group("Camera")
		if camera != null and camera.has_method("shake") and sixieme_secousse > 0.0:
			camera.shake(sixieme_secousse, 8.0)


## SANG NEUF : on vient de réapparaître après une mort : la jauge de soin se
## remplit, un instant après (pour qu'on la voie monter)
func _sang_neuf() -> void:
	if not Player.vient_de_mourir:
		return
	Player.vient_de_mourir = false
	if not Player.talisman_equipe(TALISMAN_SANG_NEUF):
		return
	# une minuterie liée à ce joueur : s'il disparaît avant, elle ne fait rien
	get_tree().create_timer(sang_neuf_delai).timeout.connect(_sang_neuf_remplir)


func _sang_neuf_remplir() -> void:
	if Player.hp <= 0:
		return
	var manque := Player.MAX_BLOODHEAL - Player.bloodheal
	if manque > 0:
		Player.changement_de_bloodheal(manque)
	print("[SANG NEUF] f=", Engine.get_physics_frames(), " réapparition : la jauge de soin se remplit (+",
		manque, " → ", Player.bloodheal, "/", Player.MAX_BLOODHEAL, ")")


## les gouttes des Gardiennes : elles se montrent et se cachent seules selon le
## talisman
func _gardiennes_preparer() -> void:
	_gardiennes = GARDIENNES_SCENE.instantiate()
	_gardiennes.demo_boucle = false
	_gardiennes.joueur = self
	add_child(_gardiennes)


## ce que fait une goutte des Gardiennes qui touche (lu à chaque coup : les
## bonus du moment comptent)
func gardiennes_degats() -> int:
	return maxi(roundi(animator.degats_du_coup() * gardiennes_part), 1)


func _couronne_preparer() -> void:
	_couronne = COURONNE_SCENE.instantiate()
	_couronne.demo_boucle = false
	_couronne.position = couronne_position
	_couronne.z_index = 2       # devant le sprite du perso
	add_child(_couronne)


## un coup vient d'être ENCAISSÉ (et on y a survécu) : la vengeance se charge
## (ou repart pour toute sa durée)
func _vengeance_charger() -> void:
	if not Player.talisman_equipe(TALISMAN_VENGEANCE):
		return
	vengeance_reste = vengeance_duree
	if _couronne != null:
		_couronne.position = couronne_position
		_couronne.lever(vengeance_duree)
	print("[VENGEANCE] chargée pour ", vengeance_duree, " s")


## la vengeance est-elle chargée ? Tant qu'elle l'est, TOUS les coups d'épée
## en profitent
func vengeance_active() -> bool:
	return vengeance_reste > 0.0


## un coup d'épée vient de porter avec la vengeance : la couronne bat (la
## vengeance, elle, ne s'use pas : seul le temps l'éteint)
func vengeance_frapper() -> void:
	if _couronne != null:
		_couronne.battre()


## --- le bouclier de sang ---

func _bouclier_preparer() -> void:
	_bouclier = BOUCLIER_SCENE.instantiate()
	_bouclier.demo_boucle = false
	_bouclier.position = collision_normale.position      # au milieu du corps
	_bouclier.tombe.connect(_on_bouclier_tombe)
	add_child(_bouclier)


## Un coup vient d'être ENCAISSÉ : si le talisman est porté (et son temps mort
## passé), le bouclier se dresse depuis `cote`, le côté d'où le coup est venu
## (vecteur unitaire, (-1, 0) = la gauche).
func _bouclier_lever(cote: Vector2) -> void:
	if _bouclier == null or not Player.talisman_equipe(TALISMAN_BOUCLIER):
		return
	if _bouclier_recharge_reste > 0.0:
		return
	_bouclier.lever(bouclier_duree, cote)


## true si le bouclier est levé : le coup est PARÉ, rien ne passe (ni dégât,
## ni recul, ni stun) ; l'onde de la parade part du côté d'où il venait.
func _bouclier_pare(source_x, source_tag: String) -> bool:
	if _bouclier == null or not _bouclier.actif():
		return false
	var cote := Vector2.UP
	if source_x != null:
		cote = Vector2(-1.0 if global_position.x > float(source_x) else 1.0, 0.0)
	_bouclier.bloquer(cote)
	print("[DMG paré] f=", Engine.get_physics_frames(), " src=", source_tag,
		" bouclier encore ", snappedf(_bouclier.restant(), 0.01), " s")
	return true


func _on_bouclier_tombe() -> void:
	_bouclier_recharge_reste = bouclier_recharge


## --- les épines de sang ---

## Un coup vient d'être ENCAISSÉ (et on y a survécu) : si le talisman est
## porté, les pics jaillissent et mordent TOUT DE SUITE (ils sortent en moins
## de 0,1 s) les ennemis proches, sans mur entre eux et nous.
func _epines_jaillir() -> void:
	if not Player.talisman_equipe(TALISMAN_EPINES):
		return
	var centre := centre_corps()
	var fx := EPINES_SCENE.instantiate()
	fx.demo_boucle = false
	fx.rayon = epines_rayon
	# au sol, les pics ne partent que vers le haut et les côtés (l'origine du
	# joueur est à ses pieds)
	fx.sol_monde = global_position.y if is_on_floor() else INF
	fx.z_index = 0          # derrière le sprite du perso (z 1) : il reste lisible au milieu
	add_child(fx)
	fx.global_position = centre
	var espace := get_world_2d().direct_space_state
	var cercle := CircleShape2D.new()
	cercle.radius = epines_rayon
	var requete := PhysicsShapeQueryParameters2D.new()
	requete.shape = cercle
	requete.transform = Transform2D(0.0, centre)
	requete.collision_mask = 8               # la couche des monstres
	requete.collide_with_areas = false
	var degats := roundi(animator.degats_du_coup() * epines_part)
	var touches: Array[Node] = []
	for resultat in espace.intersect_shape(requete, 32):
		var c: Node = resultat["collider"]
		if not (c is BaseAI) or touches.has(c):
			continue
		if c.hp <= 0 or c.invulnerable or not c.est_ennemi(self):
			continue
		# un mur entre nous ? (murs solides = couche 1, où est aussi le joueur)
		var la: Vector2 = c.collision.global_position if c.collision != null else (c as Node2D).global_position
		var rayon := PhysicsRayQueryParameters2D.create(centre, la, 1)
		rayon.exclude = [get_rid()]
		if not espace.intersect_ray(rayon).is_empty():
			continue
		touches.append(c)
		c.apply_damage(degats, global_position.x, "epines", true, self)
	print("[EPINES] f=", Engine.get_physics_frames(), " ", touches.size(),
		" ennemi(s) touché(s), ", degats, " dégâts chacun")


## --- le sang versé, le sang perdu à la mort ---

## SANG VERSÉ : `coeurs` cœurs viennent d'être perdus — la jauge de soin s'en
## remplit (pas si on en meurt : on ne se soigne plus)
func _sang_verse(coeurs: int) -> void:
	if coeurs <= 0 or Player.hp <= 0 or not Player.talisman_equipe(TALISMAN_SANG_VERSE):
		return
	Player.changement_de_bloodheal(sang_verse_par_coeur * coeurs)
	print("[SANG VERSÉ] +", sang_verse_par_coeur * coeurs, " de jauge (", coeurs, " cœur(s) perdu(s))")


## à la mort : on perd `blood_perdu_a_la_mort` du sang récolté — le Reliquaire
## en garde `reliquaire_part` — et ce qu'on perd attend en esprit de sang
## au-dessus du dernier sol sûr (un esprit qui attendait encore est perdu)
func _perdre_blood() -> void:
	var part := blood_perdu_a_la_mort
	if Player.talisman_equipe(TALISMAN_RELIQUAIRE):
		part *= 1.0 - reliquaire_part
	var perte := int(floor(float(Player.blood) * part))
	if perte > 0:
		Player.changement_de_blood(-perte)
	var lieu := _dernier_sol_sur if _dernier_sol_sur.is_finite() else global_position
	# le TABLEAU où l'on tombe (pas la scène courante : en jeu c'est le conteneur
	# du Loader, le même pour tous les tableaux — l'esprit reparaissait alors dans
	# n'importe lequel, aux coordonnées d'un autre)
	Player.laisser_ames(perte, Player.niveau_courant(), lieu + Vector2(0.0, -ames_hauteur))
	print("[MORT] sang perdu : ", perte, " (il en reste ", Player.blood, ")",
		" — il attend en esprit de sang à ", Player.ames_position if perte > 0 else "nulle part")


## à notre arrivée dans un tableau : si nos âmes perdues attendent ici, leur
## esprit de sang y flotte (une seule fois : pas s'il y est déjà)
func _ames_poser() -> void:
	var scene := get_tree().current_scene
	if Player.ames_perdues <= 0 or scene == null or Player.niveau_courant() != Player.ames_scene:
		return
	if not get_tree().get_nodes_in_group("esprit_sang").is_empty():
		return
	var e := ESPRIT_SANG_SCENE.instantiate()
	e.demo_boucle = false
	e.position = Player.ames_position          # le tableau est à l'origine
	scene.add_child(e)
	print("[ÂMES] ", Player.ames_perdues, " âmes attendent ici, en esprit de sang, à ", Player.ames_position)


## --- le coup de grâce ---

## notre épée vient d'ACHEVER `cible`, fissuré : il vole en éclats, la jauge se
## remplit de `grace_bloodheal`, la caméra tremble
func grace_executer(cible: Node2D) -> void:
	var fx := GRACE_SCENE.instantiate()
	fx.demo_boucle = false
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = get_parent()
	hote.add_child(fx)
	var c := cible.global_position
	if cible is BaseAI and cible.collision != null:
		c = cible.collision.global_position
	fx.global_position = c
	Player.changement_de_bloodheal(grace_bloodheal)
	var cam := get_tree().get_first_node_in_group("Camera")
	if grace_secousse > 0.0 and cam != null and cam.has_method("shake"):
		cam.shake(grace_secousse, 10.0)
	print("[GRÂCE] f=", Engine.get_physics_frames(), " exécuté : +", grace_bloodheal, " de jauge")


## --- la parade ---

## Un coup d'ennemi arrive : est-il PARÉ ? (le talisman porté, un coup au corps
## à corps, notre lame en garde, et il vient de devant)
func _parade_tente(source_x, source_tag: String, attaquant: Node) -> bool:
	if not Player.talisman_equipe(TALISMAN_PARADE) or not source_tag.begins_with("attaque:"):
		return false
	if not animator.lame_en_garde():
		return false
	var x_attaquant = source_x
	if attaquant is Node2D:
		x_attaquant = (attaquant as Node2D).global_position.x
	if x_attaquant == null:
		return false
	# il frappe DEVANT nous : du côté où part la lame
	var cote := signf(float(x_attaquant) - global_position.x)
	if cote != 0.0 and cote != signf(point.scale.x):
		return false
	var duree := parade_etourdi
	print("[PARADE] f=", Engine.get_physics_frames(), " coup paré (", source_tag,
		") : sonné ", duree, " s")
	if attaquant != null and attaquant.has_method("etourdir"):
		attaquant.etourdir(duree)
	_parade_choc(float(x_attaquant))
	return true


## le « clang » : entre nous et l'attaquant (au bout de la lame au plus), à
## hauteur de poitrine ; la caméra tremble un peu
func _parade_choc(x_attaquant: float) -> void:
	var fx := PARADE_CHOC_SCENE.instantiate()
	fx.demo_boucle = false
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = get_parent()
	hote.add_child(fx)
	var c := centre_corps()
	fx.global_position = Vector2(c.x + clampf(x_attaquant - c.x, -180.0, 180.0) * 0.5, c.y - 12.0)
	var cam := get_tree().get_first_node_in_group("Camera")
	if parade_secousse > 0.0 and cam != null and cam.has_method("shake"):
		cam.shake(parade_secousse, 12.0)


## --- le crescendo ---

## le bonus (en %) que fera le coup d'épée `coup_id` s'il porte, 0 sans le
## talisman : son rang dans la série (un coup déjà compté — il touche un
## deuxième ennemi — garde le sien)
func crescendo_pourcent(coup_id: int) -> float:
	if not Player.talisman_equipe(TALISMAN_CRESCENDO):
		return 0.0
	var rang := crescendo_serie + (0 if coup_id == _crescendo_coup else 1)
	return CRESCENDO_PALIERS[clampi(rang, 1, CRESCENDO_PALIERS.size()) - 1]


## le coup d'épée `coup_id` a porté : la série monte (une fois par coup) et
## repart pour `crescendo_delai` s
func crescendo_porte(coup_id: int) -> void:
	if not Player.talisman_equipe(TALISMAN_CRESCENDO):
		return
	if coup_id != _crescendo_coup:
		_crescendo_coup = coup_id
		crescendo_serie += 1
	_crescendo_reste = crescendo_delai


## un coup encaissé, ou le temps sans frapper : la série retombe à zéro
func crescendo_casser() -> void:
	if crescendo_serie > 0:
		print("[CRESCENDO] série cassée après ", crescendo_serie, " coup(s)")
	crescendo_serie = 0
	_crescendo_coup = -1


## --- l'essaim ---

## Un monstre vient de mourir : si c'est NOUS qui l'avons tué et que le
## talisman « Essaim » est porté, son cadavre lâche l'essaim.
func _on_monstre_tue(monstre: Node, attaquant: Node) -> void:
	if attaquant != self or not (monstre is Node2D) or not Player.talisman_equipe(TALISMAN_ESSAIM):
		return
	var centre: Vector2 = (monstre as Node2D).global_position
	if monstre is BaseAI and monstre.collision != null:
		centre = monstre.collision.global_position       # le milieu du corps
	# on peut être en plein rappel de physique (le coup d'épée tue dans son
	# `body_entered`) : l'essaim sort juste après
	_essaim_lacher.call_deferred(centre)


## --- l'ombre de sang ---

## notre épée vient de toucher `cible` (vivant) : le double surgit derrière lui
## et refait ce coup-là
func ombre_surgir(cible: Node2D) -> void:
	var o := OMBRE_SCENE.instantiate()
	o.joueur = self
	o.cible = cible
	o.cote = 1.0 if cible.global_position.x >= global_position.x else -1.0
	o.part = ombre_part
	o.animation = String(animator.animation)
	o.image_coup = animator.frame
	o.slash_nom = animator.dernier_slash
	o.slash_position = animator.slash_attack.position
	o.echelle = animator.slash_attack.scale.x
	o.zone = animator.zone_active()
	o.xf_attaque = animator.collision.transform
	# on est dans le rappel de physique du coup d'épée : posé juste après
	_essaim_hote().add_child.call_deferred(o)


## --- le sang bouillant (ébullition) ---

## notre épée ou notre boule de sang vient de toucher `cible` (vivant) : son
## sang bout un peu plus ; à la troisième charge il explose (bouillon_sang.gd)
func bouillant_charger(cible: Node2D) -> void:
	# (non typé : une méta peut garder un nœud déjà libéré)
	var deja = cible.get_meta("bouillon") if cible.has_meta("bouillon") else null
	if is_instance_valid(deja) and not deja.is_queued_for_deletion():
		deja.ajouter_charge()
		return
	var b := BOUILLON_SCENE.instantiate()
	b.demo_boucle = false
	b.joueur = self
	b.cible = cible
	b.rayon = bouillant_rayon
	b.part = bouillant_part
	b.duree_charge = bouillant_duree_charge
	b.secousse = bouillant_secousse
	b.charges = 1
	# rien de physique dedans : on peut l'ajouter pendant le rappel du coup
	_essaim_hote().add_child(b)


## --- le sang corrompu (poison) ---

## une boule corrompue vient de toucher `cible` (vivant) : il est empoisonné ;
## déjà empoisonné, son poison repart pour `poison_duree` s (poison_sang.gd)
func empoisonner(cible: Node2D) -> void:
	# (non typé : une méta peut garder un nœud déjà libéré)
	var deja = cible.get_meta("poison") if cible.has_meta("poison") else null
	if is_instance_valid(deja) and not deja.is_queued_for_deletion():
		deja.relancer()
		return
	var p := POISON_SCENE.instantiate()
	p.demo_boucle = false
	p.joueur = self
	p.cible = cible
	p.degats = poison_degats
	p.intervalle = poison_intervalle
	p.duree = poison_duree
	# rien de physique dedans : on peut l'ajouter pendant le rappel du coup
	_essaim_hote().add_child(p)


func _essaim_lacher(centre: Vector2) -> void:
	var nombre := essaim_nombre
	if essaim_max > 0:
		var en_vol := get_tree().get_nodes_in_group("chauve_souris_sang").size()
		nombre = mini(essaim_nombre, essaim_max - en_vol)
		if nombre <= 0:
			print("[ESSAIM] f=", Engine.get_physics_frames(), " déjà ", en_vol, " en vol : aucune de plus")
			return
	var hote := _essaim_hote()
	for i in nombre:
		var cs := _essaim_creer()
		# en éventail vers le haut : la première part à gauche, la dernière à droite
		var s := float(i) / maxf(nombre - 1, 1) * 2.0 - 1.0
		var angle := -PI * 0.5 + s * 0.6 + randf_range(-0.15, 0.15)
		cs.vitesse_depart = Vector2.from_angle(angle) * randf_range(420.0, 520.0)
		hote.add_child(cs)
		cs.global_position = centre
	print("[ESSAIM] f=", Engine.get_physics_frames(), " ", nombre,
		" chauve(s)-souris lâchée(s), ", essaim_degats(), " dégâts chacune")


## Celles qui nous suivaient au tableau d'avant. Le changement de tableau a
## tout détruit (le niveau, l'ancien joueur, elles) ; `Player.essaim_en_vol`
## se souvient de leur nombre : on les relâche à leur place autour de nous,
## déjà en vol. (La mort remet ce compte à zéro : `dead_input`.)
func _essaim_reprendre() -> void:
	var nombre := Player.essaim_en_vol
	Player.essaim_en_vol = 0          # chacune se recompte en naissant
	if nombre <= 0 or not Player.talisman_equipe(TALISMAN_ESSAIM):
		return
	if essaim_max > 0:
		nombre = mini(nombre, essaim_max)
	var hote := _essaim_hote()
	for i in nombre:
		var cs := _essaim_creer()
		cs.deja_la = true
		hote.add_child(cs)
		cs.se_placer()
	print("[ESSAIM] f=", Engine.get_physics_frames(), " ", nombre,
		" chauve(s)-souris nous ont suivis dans ce tableau")


## une chauve-souris prête à être posée dans la scène
func _essaim_creer() -> Node2D:
	var cs := CHAUVE_SOURIS_SCENE.instantiate()
	cs.demo_boucle = false
	cs.joueur = self
	cs.degats = essaim_degats()
	cs.graine = randf() * TAU
	return cs


func essaim_degats() -> int:
	return maxi(roundi(animator.degats_du_coup() * essaim_part), 1)


## où vivent les chauves-souris : dans la scène, pas sous le joueur (elles
## volent dans le monde)
func _essaim_hote() -> Node:
	var hote: Node = get_tree().current_scene
	return hote if hote != null else get_parent()


## --- le pas de côté ---

@export_subgroup("Pas de côté")
## TALISMAN « PAS DE CÔTÉ » (30 sept. 2026, id "esquive") : à chaque coup
## d'ENNEMI (pas les pièges : leur renvoi doit rester), une chance
## (`Player.chance_esquive()`, 20 %) que le coup soit ignoré — ni dégât, ni
## stun. Le corps fait un VRAI pas de côté : il est repoussé hors du coup (le
## recul d'un coup encaissé, réduit à `esquive_recul`), et laisse derrière lui
## un FANTÔME à sa pose exacte, qui encaisse à sa place et s'efface. Sans ce
## déplacement (première version), on restait DANS la source — les piques
## d'une larve, un monstre au contact — et le coup revenait à la fin de la
## grâce : on voyait le fantôme et on prenait quand même le dégât.
## part du recul d'un coup encaissé (HIT_KNOCK_X / HIT_KNOCK_Y) que fait le
## pas de côté (1 = autant qu'un coup pris)
@export var esquive_recul := 0.6
## durée du fantôme (s) et distance dont il glisse vers le coup (px)
@export var esquive_fantome_duree := 0.28
@export var esquive_fantome_distance := 14.0
@export var esquive_fantome_couleur := Color(1.0, 0.72, 0.78, 0.7)
## GRÂCE après un pas de côté (s) : le temps pendant lequel le même coup ne
## peut pas revenir. Sans elle, une source CONTINUE (le contact d'un monstre
## est relu à CHAQUE image de physique, un jet de flammes aussi) retirait un
## nouveau dé l'image d'après et touchait à 80 % — on voyait le fantôme et
## on prenait quand même le dégât (30 sept. 2026). Un coup encaissé, lui, a le
## stun de l'état HIT (0,25 s) pour ça ; le pas de côté n'a pas de stun, il a
## cette grâce. Pas de recul non plus : si on reste dans le monstre, le coup
## suivant se rejoue normalement à la fin de la grâce.
@export var esquive_grace := 0.35
var _esquive_grace_reste := 0.0

func _esquive_tente(source_x, source_tag: String) -> bool:
	if _esquive_grace_reste > 0.0:
		return true                       # le même coup qui revient : toujours au travers
	var chance := Player.chance_esquive()
	if chance <= 0.0 or randf() >= chance:
		return false
	_esquive_grace_reste = esquive_grace
	# d'où vient le coup : le pas de côté part de l'autre côté
	var dir := 0
	if source_x != null:
		dir = 1 if (global_position.x - float(source_x)) > 0.0 else -1
	elif last_direction != 0:
		dir = -last_direction
	# le fantôme reste sur place et glisse VERS le coup ; le corps, lui, s'écarte
	_fantome_esquive(Vector2(-dir, 0.0))
	_knock = Vector2(dir * HIT_KNOCK_X * esquive_recul, 0.0)
	velocity.y = minf(velocity.y, HIT_KNOCK_Y * esquive_recul)   # petit bond, pour décoller d'une larve
	print("[DMG esquivé] f=", Engine.get_physics_frames(), " src=", source_tag, " chance ", chance)
	return true


## le fantôme du pas de côté : la pose du perso, DEVANT lui, qui glisse un peu
## dans `sens` et s'efface pendant que le vrai corps s'écarte
func _fantome_esquive(sens: Vector2) -> void:
	_poser_fantome(esquive_fantome_couleur, esquive_fantome_duree, sens * esquive_fantome_distance, true)
	# et le vrai corps blêmit une fraction de seconde
	var tv := animator.create_tween()
	animator.modulate.a = 0.35
	tv.tween_property(animator, "modulate:a", 1.0, esquive_fantome_duree * 0.7)


## UN FANTÔME : une copie de la pose EXACTE du perso à cet instant (même image
## de l'animation, même sens, miroir de POINT compris), hébergée par la scène —
## elle reste où elle a été posée pendant que le perso s'en va — qui glisse de
## `glisse` px et s'efface en `duree` s, puis se supprime. `devant` : au-dessus
## du perso (le pas de côté) ou juste derrière lui (la traînée). Pas de shader :
## un Sprite2D teinté par `couleur`, rien à préchauffer.
func _poser_fantome(couleur: Color, duree: float, glisse: Vector2, devant: bool) -> void:
	var tex: Texture2D = animator.sprite_frames.get_frame_texture(animator.animation, animator.frame)
	if tex == null:
		return
	var fantome := Sprite2D.new()
	fantome.texture = tex
	fantome.texture_filter = animator.texture_filter
	fantome.light_mask = animator.light_mask          # pas plus éclairé par les lumières que le perso
	fantome.offset = animator.offset
	fantome.centered = animator.centered
	fantome.flip_h = animator.flip_h
	fantome.flip_v = animator.flip_v
	# rang absolu : juste au-dessus du perso, ou juste en dessous
	fantome.z_as_relative = false
	fantome.z_index = _z_absolu(animator) + (2 if devant else -1)
	fantome.modulate = couleur
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = get_parent()
	hote.add_child(fantome)
	fantome.global_transform = animator.global_transform
	var tw := fantome.create_tween().set_parallel(true)
	if glisse != Vector2.ZERO:
		tw.tween_property(fantome, "global_position", fantome.global_position + glisse, duree) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(fantome, "modulate:a", 0.0, duree)
	tw.chain().tween_callback(fantome.queue_free)


## le rang d'affichage (z) réel d'un nœud : le sien plus ceux de ses parents,
## tant qu'ils sont relatifs
func _z_absolu(ci: CanvasItem) -> int:
	var z := 0
	var n: Node = ci
	while n is CanvasItem:
		z += (n as CanvasItem).z_index
		if not (n as CanvasItem).z_as_relative:
			break
		n = n.get_parent()
	return z


## --- la traînée fantomatique (dash aérien, roulade) ---

@export_group("Traînée fantôme")
## TRAÎNÉE (30 sept. 2026) : pendant le dash aérien et la
## roulade, le perso sème derrière lui des fantômes de sa pose — la même famille
## que le pas de côté, en traînée. Une copie tous les `trainee_espacement` px
## parcourus (donc la même densité au dash, 1400 px/s, qu'à la roulade,
## 760 px/s), la première au point de départ ; chacune reste où elle a été
## posée, derrière le perso, et s'efface en `trainee_duree` s : les plus
## anciennes sont les plus pâles.
@export var trainee_dash := true
@export var trainee_roulade := true
## une copie tous les tant de px parcourus (60 : des images bien distinctes ;
## 42 faisait une bouillie, 75 une traînée trop clairsemée — essais du 30 sept.)
@export var trainee_espacement := 60.0
## durée de vie d'une copie (s) : la longueur de la traînée = vitesse × durée
@export var trainee_duree := 0.22
@export var trainee_couleur := Color(1.0, 0.72, 0.78, 0.5)
var _trainee_derniere := Vector2.INF     # où a été posée la dernière copie (INF = pas en traînée)

## --- le sillage de sang (talisman) ---

## TALISMAN « SILLAGE DE SANG » (1er oct. 2026, id "sillage") : porté, la
## roulade et le dash laissent derrière le perso une BRUME DE SANG qui reste
## `sillage_duree` s et ronge à petit feu les ennemis pris dedans (toutes les
## `sillage_intervalle` s : `sillage_degats` PV, sans recul). Le visuel ET les
## dégâts sont dans SCRIPT/SHADER/sillage_sang.gd ; ici on ne fait que semer
## les points du trajet.
const SILLAGE_SCENE := preload("res://SCRIPT/SHADER/sillage_sang.tscn")
const TALISMAN_SILLAGE := "sillage"
@export_group("Talismans")
@export_subgroup("Sillage de sang")
## combien de temps la brume vit en chaque endroit (s)
@export var sillage_duree := 3.0
## dégâts d'un tick de brume (le coup d'épée fait 70 ; 12 au départ, ×3 le
## 1er oct. 2026 : trop faible sinon), et temps entre deux ticks (s)
@export var sillage_degats := 36
@export var sillage_intervalle := 0.5
## tolérance (px) au-delà de la brume visible : un ennemi dont le corps
## l'effleure est « dedans » (la zone de dégâts suit la brume dessinée)
@export var sillage_marge := 16.0
## un point de brume tous les tant de px parcourus
@export var sillage_espacement := 36.0
## hauteur de la brume au-dessus des pieds (px) : à mi-corps
const SILLAGE_HAUTEUR := 48.0
var _sillage: Node2D = null
var _sillage_dernier := Vector2.INF

func _sillage_tick() -> void:
	var actif := (current_state == States.ROLL or current_state == States.DASH) \
			and Player.talisman_equipe(TALISMAN_SILLAGE)
	if _sillage != null and not is_instance_valid(_sillage):
		_sillage = null
	if not actif:
		if _sillage != null:
			# un dernier point À L'ARRIVÉE : sans lui, la brume s'arrêtait jusqu'à
			# un espacement avant la fin réelle du mouvement, et l'ennemi posé
			# là n'était jamais dedans
			_sillage.ajouter(global_position + Vector2(0.0, -SILLAGE_HAUTEUR))
			_sillage.fermer()            # la brume semée vit sa vie
			_sillage = null
		return
	var ici := global_position + Vector2(0.0, -SILLAGE_HAUTEUR)
	if _sillage != null:
		_sillage.suivre(ici)         # le bout du sillage avance en continu avec nous
	if _sillage != null and ici.distance_to(_sillage_dernier) < sillage_espacement:
		return
	if _sillage == null or not _sillage.ajouter(ici):
		# un nouveau sillage (le premier du mouvement, ou le précédent est plein)
		if _sillage != null:
			_sillage.fermer()
		_sillage = SILLAGE_SCENE.instantiate()
		_sillage.demo_boucle = false
		_sillage.joueur = self
		_sillage.duree = sillage_duree
		_sillage.degats = sillage_degats
		_sillage.intervalle = sillage_intervalle
		_sillage.marge = sillage_marge
		var hote: Node = get_tree().current_scene
		if hote == null:
			hote = get_parent()
		hote.add_child(_sillage)
		_sillage.ajouter(ici)
	_sillage_dernier = ici


## appelé à chaque pas de physique, AVANT le déplacement : la première copie
## tombe pile au point de départ
func _trainee_tick() -> void:
	var active := (current_state == States.DASH and trainee_dash) \
			or (current_state == States.ROLL and trainee_roulade)
	if not active:
		_trainee_derniere = Vector2.INF
		return
	if _trainee_derniere != Vector2.INF and global_position.distance_to(_trainee_derniere) < trainee_espacement:
		return
	_trainee_derniere = global_position
	_poser_fantome(trainee_couleur, trainee_duree, Vector2.ZERO, false)


@export_group("Coups reçus")
@export_subgroup("Pièges")
## Renvoi des dégâts d'environnement (piques, scie). Le danger fournit une
## DIRECTION de repoussée et chaque axe a sa force (sept. 2026 : avant, le renvoi
## était toujours vers le haut : une pique de plafond nous renvoyait DANS elle).
@export var ENV_KNOCK_Y: float = -1100.0           ## vers le HAUT (piques au sol), inchangé
@export var ENV_KNOCK_BAS: float = 500.0           ## vers le BAS (piques de plafond) : on décroche, la gravité fait le reste
@export var ENV_KNOCK_X: float = 1300.0            ## sur le CÔTÉ (piques murales, flanc d'une scie), comme un coup de monstre
@export var ENV_KNOCK_SOULEVEMENT: float = 450.0   ## petit saut ajouté à une poussée latérale, pour décoller du sol


## centre du corps (milieu de la hitbox debout), pour les dangers à repoussée
## radiale (scie) : les pieds sont trop bas pour donner une bonne direction
func centre_corps() -> Vector2:
	return collision_normale.global_position


## L'éclat de sang d'un coup REÇU : posé au milieu du corps, du côté d'où vient
## le coup, et tourné dans le `sens` où il nous envoie. Hébergé par la scène,
## pas par le joueur — il reste où le coup est tombé pendant qu'on recule.
func _eclat_sang(sens: Vector2) -> void:
	var d := sens.normalized() if sens.length_squared() > 0.0001 else Vector2.UP
	var fx := IMPACT_SANG.instantiate()
	fx.demo_boucle = false
	fx.z_index = 5                                    # devant le joueur
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = get_parent()
	hote.add_child(fx)
	# jamais deux fois au même endroit ni sous le même angle
	fx.global_position = centre_corps() - d * 14.0 \
			+ Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	fx.rotation = d.angle() + randf_range(-0.3, 0.3)


## Dégâts d'environnement (piques & co) : perte de cœur(s), renvoi fort dans la
## `direction` fournie par le danger (le sens où pointent les piques, ou du
## centre de la scie vers nous), et recharge du double saut + dash pour pouvoir
## se rattraper. Roulade et dash rendent invulnérable, comme contre les
## ennemis. Sans direction : vers le haut, comme avant.
## Retourne true si le coup a PORTÉ (false : mort, déjà sonné, en roulade ou en dash)
## — les pièges qui ne doivent toucher qu'une fois par sortie s'en servent.
func apply_environment_damage(amount: int, direction: Vector2 = Vector2.UP) -> bool:
	if current_state in [States.DEAD, States.HIT, States.ROLL, States.DASH]:
		return false
	if _souffle_grace_reste > 0.0:
		return false               # le répit qui suit un second souffle
	var d := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.UP
	if _bouclier != null and _bouclier.actif():
		# PARÉ par le bouclier de sang : ni dégât ni stun, mais le renvoi reste
		# (sans lui on resterait planté dans les piques jusqu'à sa chute)
		_bouclier.bloquer(-d)
		print("[DMG paré] f=", Engine.get_physics_frames(), " src=environnement",
			" bouclier encore ", snappedf(_bouclier.restant(), 0.01), " s")
		_renvoi_environnement(d)
		return true
	amount = _second_souffle(_coeur_noir_absorbe(_degats_recus(amount), "environnement"), "environnement")
	print("[DMG] f=", Engine.get_physics_frames(),
		" src=environnement amount=", amount,
		" état=", States.keys()[current_state],
		" hp ", Player.hp, " -> ", Player.hp - amount)
	Player.changement_de_vie(-amount)
	_sang_verse(amount)
	_eclat_sang(direction)
	if Player.hp <= 0:
		_knock = Vector2.ZERO
		change_state(States.DEAD)
		return true
	change_state(States.HIT)
	_renvoi_environnement(d)
	# le coup est encaissé : le bouclier de sang se dresse du côté d'où il vient
	_bouclier_lever(-d)
	_epines_jaillir()
	_vengeance_charger()
	crescendo_casser()          # un coup encaissé : la série retombe
	return true


## Le renvoi d'un danger d'environnement dans la direction `d` (unitaire) :
## latéral = poussée absolue amortie, le même mécanisme que les coups de
## monstres ; vertical = impulsion one-shot — à appeler APRÈS hit_enter (qui
## remet velocity à zéro). Recharge le double saut + dash pour se rattraper.
func _renvoi_environnement(d: Vector2) -> void:
	_knock = Vector2(d.x * ENV_KNOCK_X, 0.0)
	# haut, bas et soulèvement se raccordent SANS seuil : une pique murale donne
	# d.y = ±0,00000004 (flottants) et un joueur qui tombe est vite quelques
	# pixels sous le centre d'une scie ; un test « d.y <= 0 » sautait dans ces cas
	var haut := maxf(-d.y, 0.0) * absf(ENV_KNOCK_Y)
	var bas := maxf(d.y, 0.0) * ENV_KNOCK_BAS
	# poussée latérale : petit soulèvement pour décoller du sol, qui s'efface à
	# mesure que le danger pousse vers le bas
	var soulevement := ENV_KNOCK_SOULEVEMENT * absf(d.x) * (1.0 - maxf(d.y, 0.0))
	velocity.y = bas - maxf(haut, soulevement)
	_recharge_air_moves()


func goto_state(s: States) -> void:
	if current_state == s:
		return
	call_deferred("_goto_differe", s, current_state)


## La transition DIFFÉRÉE est abandonnée si, entre la demande et la fin de
## l'image, un coup a IMPOSÉ HIT ou DEAD (2 oct. 2026, roue à pointes : un
## atterrissage demandait IDLE pour la fin de l'image, la roue piquait dans la
## même image, et l'IDLE différé effaçait le HIT — plus de stun ni de répit,
## piqué de nouveau à l'image suivante ; après un coup mortel, il aurait même
## relevé le mort). Même famille que le garde-fou des monstres (BASE_IA).
func _goto_differe(s: States, depuis: States) -> void:
	if current_state != depuis and current_state in [States.HIT, States.DEAD]:
		return
	change_state(s)

## Détection de mur pour le wall jump : uniquement les StaticBody2D
## explicitement marqués (groupe "wall_jump") — l'opt-in permet au level
## design de décider quels murs sont grimpables
func _raycast_hits_wall(rc: RayCast2D) -> bool:
	rc.force_raycast_update()
	if not rc.is_colliding():
		return false
	var col := rc.get_collider()
	# wall jump universel (pour le moment) : tout mur StaticBody2D est valide
	return col is StaticBody2D


## FAUX SOL (3 oct. 2026) : avec le bon timing on pouvait « courir contre les
## murs » — depuis un coin de plateforme, on descendait le long de la paroi en
## gardant l'état course. Arrivé PILE sur le coin d'une
## plateforme en allant vers elle (le bas arrondi du corps posé sur l'arête, les
## pieds une douzaine de pixels sous le dessus), Godot le dit « au sol » une
## image (l'arête fait une pente de moins de 60°), puis le contact devient celui
## d'un mur… et le moteur le GARDE au sol : quand un corps qui était au sol
## bute contre un mur (`floor_block_on_wall`), il le recolle au sol en acceptant
## le MUR comme sol, vitesse remise à zéro, un peu plus bas à chaque image. Le
## héros restait en COURSE en descendant tout le flanc (mesuré : 51 images).
## On reconnaît ce faux sol à sa normale, qui est celle d'un mur (au-delà de
## `floor_max_angle`), sans vrai sol sous les pieds (contre un mur, debout sur
## un vrai sol, le moteur peut aussi rendre la normale du mur : ce n'est pas un
## faux sol). Le temps qu'il dure, on coupe `floor_block_on_wall` : à l'image
## suivante le moteur le lâche, et il tombe normalement.
var _faux_sol := false

func _faux_sol_tick() -> void:
	var faux := false
	var limite := floor_max_angle + 0.02
	if is_on_floor() and absf(get_floor_normal().angle_to(Vector2.UP)) > limite:
		var dessous := move_and_collide(Vector2.DOWN * (floor_snap_length + 2.0), true)
		faux = dessous == null or absf(dessous.get_normal().angle_to(Vector2.UP)) > limite
	if faux != _faux_sol:
		floor_block_on_wall = not faux
	_faux_sol = faux


## au sol POUR DE BON : pas sur le faux sol d'un mur (voir _faux_sol_tick)
func _au_sol() -> bool:
	return is_on_floor() and not _faux_sol


## Y a-t-il du mur à hauteur de la MAIN et du PIED, du côté `cote` (+1 droite,
## −1 gauche) ? L'accroche murale l'exige (3 oct. 2026) : plus
## d'accroche « dans le vide » en haut d'un mur, ni sur une plateforme trop
## petite pour un wall jump. Le rayon de mur (`wall_right`) ne regarde qu'à MI-CORPS : on
## s'accrochait la tête et la main au-dessus du haut d'un mur, ou sur le flanc
## d'une plateforme plus petite que le héros. Dans la pose d'accroche, la main
## est posée au mur vers `WALL_HAUTEUR_MAIN` et le pied vers `WALL_HAUTEUR_PIED` :
## s'il manque du mur à l'une des deux, pas d'accroche.
func _mur_couvre_le_corps(cote: float) -> bool:
	if cote == 0.0:
		return false
	var espace := get_world_2d().direct_space_state
	for hauteur in [WALL_HAUTEUR_MAIN, WALL_HAUTEUR_PIED]:
		var depart := global_position + Vector2(0.0, -hauteur)
		var rayon := PhysicsRayQueryParameters2D.create(
			depart, depart + Vector2(signf(cote) * WALL_PORTEE_CORPS, 0.0), wall_right.collision_mask)
		rayon.exclude = [get_rid()]
		var touche := espace.intersect_ray(rayon)
		if touche.is_empty() or not (touche["collider"] is StaticBody2D):
			return false
	return true


func _raycast_hits_group(rc: RayCast2D, group_name: String, body_only := false) -> bool:
	# AMÉLIORATION: note — cette fonction peut faire plusieurs force_raycast_update
	# par appel si des colliders sont empilés. Surveiller les perfs si besoin.
	var ignored: Array[RID] = []
	rc.clear_exceptions()

	while rc.is_colliding():
		var col := rc.get_collider()
		var ok := false
		if body_only:
			ok = col is PhysicsBody2D and col.is_in_group(group_name)
		else:
			ok = col is Area2D and col.is_in_group(group_name)

		if ok:
			for rid in ignored:
				rc.remove_exception_rid(rid)
			rc.force_raycast_update()
			return true

		var rid := rc.get_collider_rid()
		rc.add_exception_rid(rid)
		ignored.append(rid)
		rc.force_raycast_update()

	for rid in ignored:
		rc.remove_exception_rid(rid)
	rc.force_raycast_update()
	return false


## Comme `_raycast_hits_group` pour une Area2D, mais renvoie la ZONE touchée
## (null si aucune) : le wall run a besoin de savoir SUR QUEL mur il court.
func _raycast_zone_du_groupe(rc: RayCast2D, group_name: String) -> Area2D:
	var ignored: Array[RID] = []
	var trouvee: Area2D = null
	rc.clear_exceptions()
	while rc.is_colliding():
		var zone := rc.get_collider() as Area2D
		if zone != null and zone.is_in_group(group_name):
			trouvee = zone
			break
		var rid := rc.get_collider_rid()
		rc.add_exception_rid(rid)
		ignored.append(rid)
		rc.force_raycast_update()
	for rid in ignored:
		rc.remove_exception_rid(rid)
	rc.force_raycast_update()
	return trouvee



@export_subgroup("Chute")
## Dégâts de chute activables/désactivables depuis l'inspecteur
## (désactivés pour le moment — la logique reste calculée et loguée)
@export var FALL_DAMAGE_ENABLED := false

## Dégâts de chute, à l'échelle CŒURS :
## - en dessous de SAFE_HEIGHT : rien
## - au-delà : 1 cœur, +1 par tranche de STEP_PX supplémentaire
## - plafonné à LETHAL_DAMAGE (10) : une très grande chute reste mortelle
##   quel que soit le nombre de cœurs du joueur
func calcule_falling_damage() -> int:
	const SAFE_HEIGHT: float   = 850.0
	const STEP_PX: float       = 250.0
	const LETHAL_DAMAGE: int   = 10

	# Sentinelle : aucun départ de chute enregistré → pas de dégâts possibles
	if FALL_POINT <= -1e8:
		return 0

	var impact_point: float  = global_position.y
	var fall_distance: float = max(0.0, impact_point - FALL_POINT)

	if fall_distance <= SAFE_HEIGHT:
		return 0

	var excess: float = fall_distance - SAFE_HEIGHT
	var damage: int = clampi(1 + int(excess / STEP_PX), 1, LETHAL_DAMAGE)
	if FALL_DAMAGE_ENABLED:
		apply_damage(damage, null, "chute")
	print("Dégâts de chute : ", damage, " cœur(s) | hauteur : ", int(fall_distance), " px")
	return damage


func instantiate_scene(scene_ref, parent_node: Node = null) -> Node:
	var packed: PackedScene
	if scene_ref is PackedScene:
		packed = scene_ref
	elif scene_ref is String:
		packed = load(scene_ref)
	else:
		push_error("instantiate_scene: scene_ref doit être PackedScene ou String")
		return null

	var instance = packed.instantiate()
	var target_parent: Node = parent_node if parent_node != null else get_tree().get_current_scene()
	target_parent.add_child(instance)
	return instance

func _flip_facing_on_wall() -> void:
	point.scale.x *= -1
	last_direction = -last_direction


func _flip_from_input() -> void:
	var dir := Input.get_axis("left_move", "right_move")
	if dir != 0:
		last_direction = sign(dir)
		point.scale.x  = last_direction

# ----------- Initialisation des états -------------------
func _register_states(states_enum: Dictionary) -> void:
	for state_name in states_enum:
		var key: int = states_enum[state_name]
		var name_lower: String = state_name.to_lower()
		var dict := {}
		for suffix in ["enter", "execute", "input", "exit", "animation_finished", "animation_looped"]:
			var func_name: String = name_lower + "_" + suffix
			if has_method(func_name):
				dict[suffix] = Callable(self, func_name)
		state_functions[key] = dict

func initialize_states() -> void:
	_register_states(States)

# ----------- Gestion du changement d'état ---------------

var _changing_now := false

func change_state(new_state: States) -> void:
	#print("[", Engine.get_physics_frames(), "] ",
		#"STATE: ", current_state, " -> ", new_state,
		#" | on_floor=", is_on_floor(), " | vel=", velocity)

	if _changing_now or new_state == current_state:
		return

	_changing_now = true
	state_functions[current_state]["exit"].call()
	previous_state = current_state
	current_state  = new_state
	_state_enter_frame = Engine.get_process_frames()
	state_functions[current_state]["enter"].call()
	_changing_now = false


# Frame d'entrée dans l'état courant : sert à ignorer les pressions "fantômes"
# quand deux actions partagent un bouton (ex. jump et griffe sur le bouton 0 :
# la pression qui fait ENTRER dans wall_griffe ne doit pas aussi déclencher
# le saut de sortie dans la même frame)
var _state_enter_frame := 0

## Comme is_action_just_pressed, mais ignore la pression qui a déclenché
## l'entrée dans l'état courant (même frame)
func _fresh_press(action: String) -> bool:
	return Input.is_action_just_pressed(action) \
		and Engine.get_process_frames() != _state_enter_frame

# =====================  IDLE  ===========================
#region IDLE

func idle_enter() -> void:
	animator.play("idle")
	velocity = Vector2.ZERO


func idle_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not _au_sol():
		change_state(States.CHUTE)


func idle_input(event: InputEvent) -> void:
	if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
		change_state(States.RUN)
	elif Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	elif Input.is_action_just_pressed("heal"):
		_try_heal()
		return
	elif Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_1)
		return
	elif Input.is_action_just_pressed("spell"):
		_try_cast_bloodball()
		return
	elif (Input.is_action_just_pressed("up_move") or Input.is_action_just_pressed("down_move")) \
		and _try_echelle():
		return
	elif Input.is_action_just_pressed("down_move") and is_on_floor() \
		and _standing_on_oneway():
		change_state(States.DROP)
		return

func idle_exit() -> void:
	pass
#endregion

# =====================  RUN  ===========================

var run_frame_counter : int = 0



func run_enter() -> void:
	animator.play("run")


func run_execute(delta: float) -> void:
	run_frame_counter += 1
	_flip_from_input()

	velocity.y += gravity * delta

	if not _au_sol():
		goto_state(States.CHUTE)
		return

	var direction := Input.get_axis("left_move", "right_move")

	if direction == 0:
		goto_state(States.IDLE)
		return

	if animator.animation == "run" and run_frame_counter % 10 == 0:
		var foot = instantiate_scene(FOOTSTEP_SCENE)
		foot.global_position = ANCRE_SOL_BACK.global_position
		foot.scale.x        *= point.scale.x
		foot.play("run_to_ground")

	# FIX: utilise GROUND_SPEED au lieu de SPEED
	var target_speed: float = float(direction) * GROUND_SPEED
	velocity.x = lerp(velocity.x, target_speed, 0.15)


func run_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	elif Input.is_action_just_pressed("heal"):
		_try_heal()
		return
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	elif Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_LIGHT_1)
		return
	elif Input.is_action_just_pressed("spell"):
		_try_cast_bloodball()
		return
	elif (Input.is_action_just_pressed("up_move") or Input.is_action_just_pressed("down_move")) \
		and _try_echelle():
		return
	elif Input.is_action_just_pressed("down_move") and is_on_floor() \
		and _standing_on_oneway():
		change_state(States.DROP)
		return

func run_exit() -> void:
	pass


#region JUMP

@export_group("Saut et chute")
## Impulsion de saut (négatif = vers le haut). Plus la valeur est grande
## en absolu, plus le saut monte haut.
## Réglage "nerveux" (sept. 2026 : les sauts et les chutes étaient mollassons ;
## préféré à un réglage intermédiaire) : montée 0,35 s et chute
## 0,38 s au lieu de 0,47 / 0,63, HAUTEURS INCHANGÉES (saut ≈ 232 px, petit
## saut ≈ 80 px, comme l'ancien −750 forcé par la scène) et portée conservée
## (≈ 445 px).
@export var JUMP_VELOCITY: float = -1062.0   # −15 % (16 sept.) avec la gravité −15 % : mêmes durées, hauteur ≈ 257 px
const MIN_JUMP_TIME   := 0.01
const MAX_JUMP_HOLD   := 0.25
## multiplicateurs de la gravité projet (2500 depuis le 16 sept. 2026 : gravité
## UNIFIÉE, la chute du joueur = la gravité de tout le monde)
@export var GRAVITY_RISE: float = 0.6       # bouton maintenu → monte haut (gravité projet 2500 : 1 = chute normale)
@export var GRAVITY_CUTOFF: float = 2.5     # relâché tôt → coupe net
@export var GRAVITY_FALL: float = 1.0       # chute, attaque aérienne, drop = la gravité du projet telle quelle
@export var MAX_FALL_SPEED: float = 1360.0  # vitesse de chute plafond (px/s) (1600 × 0,85)
## Gravité de montée des LANCERS (grappin, corde, sortie d'escalade) : c'est
## l'ancienne coupure, gardée pour ne pas changer les hauteurs déjà réglées
@export var GRAVITY_LANCEMENT: float = 1.37  # = l'ancien 3,5 × 980 ramené à 2500 : hauteurs de lancer inchangées
var _saut_lance := false   # saut issu d'un lancer → GRAVITY_LANCEMENT à la montée

const AIR_CONTROL = 0.2
const DECELERATION_RATE = 0.95
var _jump_timer := 0.0
# vrai quand la phase aérienne a commencé SANS saut (marche dans le vide,
# lâcher d'accroche…) : le saut simple reste dû, sans limite de temps
var _walkoff_jump := false
var _climb_auto_exit := false
const CLIMB_EXIT_VELOCITY := -1000.0  # plus fort que JUMP_VELOCITY (-700)

@export_subgroup("Double saut")
# --- DOUBLE SAUT ---
## Capacité metroidvania : désactivable tant qu'elle n'est pas débloquée
@export var double_jump_enabled := true
## Impulsion du second saut (souvent un peu plus faible que le premier)
@export var DOUBLE_JUMP_VELOCITY: float = -944.0   # −15 % aussi (≈ 214 px)
var _double_jump_used := false
var _dj_pending := false  # signal pour jump_enter : c'est un double saut


## Tente le double saut (appelé depuis JUMP et CHUTE sur appui de saut en l'air)
func _try_double_jump() -> bool:
	if not double_jump_enabled or _double_jump_used or is_on_floor():
		print("[DJ] refusé  deja_utilise=", _double_jump_used,
			" au_sol=", is_on_floor(), " état=", States.keys()[current_state])
		return false
	# grâce anti-spam post-saut mural : pression ignorée, double saut intact
	if _wj_lock_timer > WALL_JUMP_LOCK_TIME - WALL_JUMP_DJ_GRACE:
		print("[WJ] pression saut ignorée (grâce anti-spam)")
		return false
	print("[DJ] double saut  depuis=", States.keys()[current_state])
	_double_jump_used = true
	_aile_battre()
	# PLUMES ACÉRÉES : l'aile lâche ses plumes-lames vers le sol
	if Player.talisman_equipe(TALISMAN_PLUMES):
		_plumes_lancer()
	if _wj_lock_timer > 0.0:
		print("[WJ] verrou coupé par DOUBLE SAUT")
	_wj_lock_timer = 0.0  # le double saut interrompt le verrou du saut mural
	if current_state == States.JUMP:
		# déjà dans l'état JUMP : on ré-applique l'impulsion directement
		velocity.y = DOUBLE_JUMP_VELOCITY
		_jump_timer = 0.0            # ré-arme la fenêtre de hold du saut
		animator.play("jump")
	else:
		_dj_pending = true
		change_state(States.JUMP)
	return true


# --- L'aile blanche du double saut (30 sept. 2026) ---
const AILE_DOUBLE_SAUT := preload("res://SCRIPT/SHADER/aile_double_saut.tscn")
## Où l'aile s'attache dans le dos, dans le repère de POINT (perso tourné vers
## la droite).
@export var AILE_ATTACHE := Vector2(-16.0, -90.0)
var _aile: Node2D = null   # une seule, créée à l'apparition du joueur
var _aile_plane: Node2D = null   # la même aile, tenue ouverte quand on plane


## Enfant de POINT : l'aile suit le joueur et se retourne avec lui. Le sprite
## du perso a un z_index de 1 : l'aile, restée à 0, se dessine derrière lui.
## Une seconde instance, en mode plané, sert d'aile tenue ouverte (PLANER).
func _aile_preparer() -> void:
	var aile := AILE_DOUBLE_SAUT.instantiate() as Node2D
	aile.demo_boucle = false
	aile.auto_detruire = false
	point.add_child(aile)
	_aile = aile
	var plane := AILE_DOUBLE_SAUT.instantiate() as Node2D
	plane.demo_boucle = false
	plane.auto_detruire = false
	plane.mode_plane = true
	point.add_child(plane)
	_aile_plane = plane


func _aile_battre() -> void:
	if _aile == null:
		return
	_aile.position = AILE_ATTACHE
	_aile.jouer()


## PLUMES ACÉRÉES : au double saut, l'aile lâche ses plumes-lames, de son
## attache dans le dos, vers le bas en éventail, à ses couleurs
func _plumes_lancer() -> void:
	var origine: Vector2 = point.to_global(AILE_ATTACHE)
	var degats := maxi(roundi(animator.degats_du_coup() * plumes_part), 1)
	var couleur = null
	var contour = null
	if _aile != null:
		var rect := _aile.get_node_or_null("Aile") as CanvasItem
		if rect != null and rect.material is ShaderMaterial:
			couleur = (rect.material as ShaderMaterial).get_shader_parameter("couleur")
			contour = (rect.material as ShaderMaterial).get_shader_parameter("couleur_contour")
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = get_parent()
	for i in plumes_nombre:
		var t := 0.0 if plumes_nombre <= 1 else float(i) / float(plumes_nombre - 1) * 2.0 - 1.0
		var ang := deg_to_rad(90.0 + t * plumes_eventail + randf_range(-4.0, 4.0))
		var plume := PLUME_ACEREE.instantiate()
		plume.demo_boucle = false
		plume.joueur = self
		plume.degats = degats
		plume.vitesse = Vector2.from_angle(ang) * plumes_vitesse * randf_range(0.9, 1.1)
		hote.add_child(plume)
		plume.global_position = origine + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
		plume.teindre(couleur, contour)
	print("[PLUMES] f=", Engine.get_physics_frames(), " double saut : ", plumes_nombre,
		" plumes de ", degats, " dégâts")


@export_subgroup("Plané")
# --- PLANER (1er oct. 2026) ---
## Capacité metroidvania : MAINTENIR le saut pendant qu'on retombe — après un
## saut simple comme après un double saut — ouvre l'aile de sang et fait
## PLANER : la chute est freinée jusqu'à `PLANER_VITESSE` et le reste tant que
## le bouton est tenu. Lâcher : l'aile se replie, la chute normale reprend.
## Tient aussi pendant un coup ou un sort en l'air. Désactivable tant qu'elle
## n'est pas débloquée, comme le double saut et le dash aérien.
@export var planer_enabled := true
## vitesse de chute en planant (px/s ; la chute libre plafonne à MAX_FALL_SPEED)
@export var PLANER_VITESSE: float = 150.0
## freinage quand l'aile s'ouvre sur une chute plus rapide (px/s², en plus de
## la gravité : 8000 ramène une chute à pleine vitesse au plané en ~0,2 s)
@export var PLANER_FREIN: float = 8000.0
## l'animation du perso en plané, si elle existe (sinon, celle de chute)
const ANIM_PLANE := "plane"
var _plane := false
var _plane_frame := -1   # dernière image de physique où un état a entretenu le plané


## Appelé par les états aériens qui permettent de planer (chute, coup en l'air,
## sort en l'air), APRÈS leur gravité : saut tenu en descendant → la chute est
## freinée jusqu'à PLANER_VITESSE et l'aile reste ouverte. Tout autre état
## replie l'aile (voir _physics_process).
func _planer_tick(delta: float) -> void:
	_plane_frame = Engine.get_physics_frames()
	var veut := planer_enabled and Input.is_action_pressed("jump") \
		and velocity.y > 0.0 and not is_on_floor()
	if veut:
		if velocity.y > PLANER_VITESSE:
			velocity.y = maxf(velocity.y - PLANER_FREIN * delta, PLANER_VITESSE)
		# une descente en plané n'est pas une chute : les dégâts de chute ne
		# comptent qu'à partir de l'endroit où l'on cesse de planer
		FALL_POINT = global_position.y
	if veut and not _plane:
		_planer_ouvrir()
	elif _plane and not veut:
		_planer_arreter()


func _planer_ouvrir() -> void:
	_plane = true
	if _aile_plane != null:
		_aile_plane.position = AILE_ATTACHE
		_aile_plane.ouvrir()
	if current_state == States.CHUTE and _anim_existe(ANIM_PLANE):
		animator.play(ANIM_PLANE)
	print("[PLANE] ouverte  état=", States.keys()[current_state], " vy=", int(velocity.y))


func _planer_arreter() -> void:
	if not _plane:
		return
	_plane = false
	if _aile_plane != null:
		_aile_plane.fermer()
	if current_state == States.CHUTE and animator.animation == ANIM_PLANE:
		animator.play("chute")
	print("[PLANE] repliée  état=", States.keys()[current_state])

func jump_enter():
	animator.play("jump")
	_jump_timer = 0.0
	_saut_lance = false
	_walkoff_jump = false  # tout saut solde le saut de chute libre
	# (FALL_POINT est géré en continu dans _physics_process : suivi au sol,
	# point le plus haut conservé en vol)

	if _climb_auto_exit:
		velocity.y = CLIMB_EXIT_VELOCITY
		velocity.x = 0.0
		_climb_auto_exit = false
		_jump_timer = MAX_JUMP_HOLD  # ← désactive le hold
		_saut_lance = true
	elif _propulsion_pending:
		# propulsion d'un passage vertical : vitesse imposée, pas de hold
		_propulsion_pending = false
		velocity = _propulsion_velocite
		_jump_timer = MAX_JUMP_HOLD
		_saut_lance = true
	elif _grappin_pending:
		# catapulte du grappin : vitesse imposée, gravité normale, pas de hold
		_grappin_pending = false
		velocity = _grappin_velocite
		_jump_timer = MAX_JUMP_HOLD
		_saut_lance = true
	elif _corde_pending:
		# lâcher de corde : l'élan du balancier + une impulsion, gravité normale
		_corde_pending = false
		velocity = _corde_velocite_sortie
		_jump_timer = MAX_JUMP_HOLD
		_saut_lance = true
	elif _dj_pending:
		_dj_pending = false
		velocity.y = DOUBLE_JUMP_VELOCITY
	elif _wj_pending:
		# saut mural : impulsion verticale normale + diagonale imposée
		_wj_pending = false
		velocity.y = JUMP_VELOCITY
		_wj_lock_dir = last_direction
		_wj_lock_timer = WALL_JUMP_LOCK_TIME
		velocity.x = WALL_JUMP_PUSH_X * _wj_lock_dir
		print("[WJ] saut mural  dir_verrou=", _wj_lock_dir,
			" vx=", velocity.x, " verrou=", WALL_JUMP_LOCK_TIME, "s")
	else:
		velocity.y = JUMP_VELOCITY
		_poser_impulsion_saut()


## l'impulsion d'air sous les pieds au départ du saut SIMPLE (30 sept. 2026) :
## ni le double saut, ni le saut mural, ni les sauts lancés (grappin, corde…)
const IMPULSION_SAUT := preload("res://SCRIPT/SHADER/impulsion_saut.tscn")

## Posée aux pieds et hébergée par la scène, derrière le joueur : elle reste au
## point d'appel. Son sillage part dans le sens du saut — droit pour un saut sur
## place, penché pour un saut en courant.
func _poser_impulsion_saut() -> void:
	var fx := IMPULSION_SAUT.instantiate()
	fx.demo_boucle = false
	fx.direction = velocity.normalized()
	fx.vitesse = velocity.length()
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = get_parent()
	hote.add_child(fx)
	fx.global_position = global_position


func jump_execute(delta):
	_jump_timer += delta
	_grab_cooldown_timer = max(_grab_cooldown_timer - delta, 0.0)

	var direction = Input.get_axis("left_move", "right_move")
	if _wj_lock_timer > 0.0:
		# verrou du saut mural : diagonale imposée, stick ignoré.
		# Interruptible : toute action qui quitte JUMP (dash, coup, griffe,
		# échelle…) passe par jump_exit qui coupe le verrou, et le double
		# saut le coupe dans _try_double_jump.
		_wj_lock_timer = maxf(_wj_lock_timer - delta, 0.0)
		velocity.x = WALL_JUMP_PUSH_X * _wj_lock_dir
		if _wj_lock_timer == 0.0:
			print("[WJ] verrou expiré naturellement (", WALL_JUMP_LOCK_TIME, "s)")
	else:
		_flip_from_input()
		if direction != 0:
			velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
		else:
			velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	if is_on_ceiling():
		velocity.y = 0.0

	var g_mul := 1.0
	if velocity.y < 0.0:
		var holding := Input.is_action_pressed("jump")
		var force_min := _jump_timer < MIN_JUMP_TIME
		var within_hold := _jump_timer < MAX_JUMP_HOLD

		if _saut_lance:
			g_mul = GRAVITY_LANCEMENT   # lancer : montée comme avant le réglage nerveux
		elif force_min or (holding and within_hold):
			g_mul = GRAVITY_RISE
		else:
			g_mul = GRAVITY_CUTOFF
	else:
		g_mul = GRAVITY_FALL

	velocity.y = minf(velocity.y + gravity * g_mul * delta, MAX_FALL_SPEED)

	if _grab_cooldown_timer <= 0.0 and _raycast_hits_group(grab, "GRAB"):
		current_grab_area = grab.get_collider()
		change_state(States.GRAB)
		return

	if velocity.y > 0.0:
		change_state(States.CHUTE)

func jump_input(event: InputEvent) -> void:
	# PRIORITÉ griffe : jump et griffe partagent le bouton — près d'une
	# surface accrochable, la pression accroche au lieu de double-sauter
	if Input.is_action_just_pressed("griffe"):
		var hit_r := _raycast_hits_group(climbcast_right, "CLIMB")
		var hit_l := _raycast_hits_group(climbcast_left,  "CLIMB")
		if hit_r and hit_l:
			change_state(States.CLIMB)
			return
		if _raycast_hits_group(climbcast_right, "GRIFFE") and absf(velocity.x) > 0.0:
			change_state(States.WALL_GRIFFE)
			return
	# _fresh_press et pas is_action_just_pressed : la pression qui vient de nous
	# faire ENTRER dans JUMP reste « juste pressée » toute la frame. Un 2e événement
	# dans cette frame (le stick tenu sur une échelle en envoie sans arrêt) repassait
	# ici et consommait le double saut aussitôt. Invisible depuis le sol (le double
	# saut y est refusé), mais pas depuis une échelle, une corde ou un saut de grâce.
	if _fresh_press("jump"):
		if _try_double_jump():
			return
	if _fresh_press("esquive") and _try_air_dash():
		return
	if (Input.is_action_just_pressed("up_move") or Input.is_action_just_pressed("down_move")) \
		and _try_echelle():
		return
	if Input.is_action_just_pressed("spell"):
		_try_cast_bloodball()
		return
	if Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_AIR)
		return

func jump_exit():
	# quitter JUMP (dash, coup, griffe, échelle, chute…) libère toujours
	# la trajectoire imposée du saut mural
	if _wj_lock_timer > 0.0:
		print("[WJ] verrou coupé par SORTIE de JUMP (reste ",
			snappedf(_wj_lock_timer, 0.01), "s)")
	_wj_lock_timer = 0.0
#endregion




#region CHUTE

# =====================  CHUTE  ===========================
var FALL_POINT: float = -1e9

func chute_enter() -> void:
	# coyote accordé en quittant le sol OU une surface d'accroche : sans ça,
	# tomber d'une griffe/échelle/mur faisait de la 1re pression un DOUBLE
	# saut ("la griffe ne recharge pas" — si, mais le saut normal sautait).
	# Les chutes SUBIES (griffe qui expire…) ont une fenêtre élargie :
	# le joueur n'a pas choisi de tomber, sa pression arrive plus tard.
	# ET dans tous ces cas : tomber sans avoir sauté ne coûte jamais le
	# saut simple — il reste disponible toute la chute (_walkoff_jump)
	if previous_state in [States.WALL_GRIFFE, States.CHUTE_GRIFFE,
		States.CLIMB, States.GRAB, States.ECHELLE, States.WALL_JUMP, States.CORDE]:
		_coyote_timer = GRIP_COYOTE_TIME
		_walkoff_jump = true
	elif previous_state in [States.RUN, States.IDLE]:
		_coyote_timer = COYOTE_TIME
		_walkoff_jump = true
	else:
		_coyote_timer = 0.0
	# (retour d'un coup en l'air pendant qu'on plane : l'anim de plané)
	animator.play(ANIM_PLANE if _plane and _anim_existe(ANIM_PLANE) else "chute")


func chute_execute(delta: float) -> void:
	var direction := Input.get_axis("left_move", "right_move")
	_grab_cooldown_timer = max(_grab_cooldown_timer - delta, 0.0)
	_coyote_timer = max(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = max(_jump_buffer_timer - delta, 0.0)

	if direction != 0:
		if previous_state != States.WALL_JUMP or absf(velocity.x) < 100.0:
			last_direction = sign(direction)
			point.scale.x = last_direction

	velocity.y = minf(velocity.y + gravity * GRAVITY_FALL * delta, MAX_FALL_SPEED)
	_planer_tick(delta)

	if direction != 0:
		velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	if _grab_cooldown_timer <= 0.0 and _raycast_hits_group(grab, "GRAB"):
		current_grab_area = grab.get_collider()
		change_state(States.GRAB)
		return

	if _raycast_hits_wall(wall_right) and _mur_couvre_le_corps(point.scale.x):
		change_state(States.WALL_JUMP)
		return

	if _au_sol():
		_handle_landing()


func chute_input(event: InputEvent) -> void:
	# PRIORITÉ griffe : jump et griffe partagent le bouton — près d'une
	# surface accrochable, la pression accroche au lieu de (double-)sauter
	if Input.is_action_just_pressed("griffe"):
		if _raycast_hits_group(climbcast_up, "CHUTE"):
			change_state(States.CHUTE_GRIFFE)
			return
		var hit_r := _raycast_hits_group(climbcast_right, "CLIMB")
		var hit_l := _raycast_hits_group(climbcast_left,  "CLIMB")
		if hit_r and hit_l:
			change_state(States.CLIMB)
			return
		if _raycast_hits_group(climbcast_right, "GRIFFE") and absf(velocity.x) > 0.0:
			change_state(States.WALL_GRIFFE)
			return

	if Input.is_action_just_pressed("jump"):
		if _coyote_timer > 0.0:
			_coyote_timer = 0.0
			change_state(States.JUMP)
			return
		elif _walkoff_jump:
			# la chute a commencé sans saut : le saut simple est toujours dû
			change_state(States.JUMP)
			return
		elif _try_double_jump():
			return
		else:
			_jump_buffer_timer = JUMP_BUFFER_TIME

	if _fresh_press("esquive") and _try_air_dash():
		return

	if (Input.is_action_just_pressed("up_move") or Input.is_action_just_pressed("down_move")) \
		and _try_echelle():
		return

	if Input.is_action_just_pressed("spell"):
		_try_cast_bloodball()
		return

	if Input.is_action_just_pressed("light_attack"):
		change_state(States.ATTACK_AIR)
		return


func chute_exit() -> void:
	pass
#endregion



#region WALL_GRIFFE
## S'accrocher à quelque chose (mur, griffe, échelle, point de grab…)
## recharge le double saut et le dash aérien
func _recharge_air_moves() -> void:
	if _double_jump_used or _air_dash_used:
		print("[DJ] recharge par accroche  état=", States.keys()[current_state])
	_double_jump_used = false
	_air_dash_used = false


func wall_griffe_enter():
	animator.play("wall_griffe")
	velocity.y = 0
	_recharge_air_moves()

	# On détermine la direction selon la vélocité d'arrivée
	if velocity.x > 0:
		last_direction = 1
	elif velocity.x < 0:
		last_direction = -1

	point.scale.x = last_direction

	# On pousse le perso DANS le mur pour maintenir le contact raycast
	# Le mur bloque le déplacement réel, mais la vélocité garde le contact
	velocity.x = 700.0 * last_direction   # 500 → 700 (sept. 2026) : c'est la "vitesse du wall run"

@export_group("Mur")
@export_subgroup("Course au mur (griffe)")
## Le wall run se cale sur le MILIEU du mur (30 sept. 2026) : où qu'on
## l'accroche, trop haut ou trop bas, le perso glisse vers la ligne médiane du
## mur de griffe pendant qu'il court, et y reste.
## Hauteur, depuis ses pieds, du point du perso qu'on amène sur ce milieu
## (le milieu de sa silhouette en course murale).
@export var WALL_GRIFFE_MILIEU_PERSO: float = -78.0
## Vivacité du recentrage (par seconde) : 22 = l'écart est rattrapé en un
## dixième de seconde environ. 0 = pas de recentrage, comme avant.
@export var WALL_GRIFFE_RECENTRAGE: float = 22.0
## vitesse verticale plafond pendant le recentrage (px/s)
@export var WALL_GRIFFE_RECENTRAGE_MAX: float = 1600.0

func wall_griffe_execute(_delta: float) -> void:
	FALL_POINT = global_position.y  # appui légitime : accroché au mur
	var mur := _raycast_zone_du_groupe(climbcast_right, "GRIFFE")
	if mur == null:
		change_state(States.CHUTE)
		return
	# recentrage : la vitesse verticale est proportionnelle à l'écart restant,
	# donc on arrive en douceur, sans dépasser
	var ecart := _milieu_vertical(mur) - (global_position.y + WALL_GRIFFE_MILIEU_PERSO)
	velocity.y = clampf(ecart * WALL_GRIFFE_RECENTRAGE,
			-WALL_GRIFFE_RECENTRAGE_MAX, WALL_GRIFFE_RECENTRAGE_MAX)


## Milieu vertical (coordonnées du monde) d'une zone : le milieu de ses formes
## de collision, quelles que soient leur position et leur échelle.
func _milieu_vertical(zone: Area2D) -> float:
	var haut := INF
	var bas := -INF
	for enfant in zone.get_children():
		var forme := enfant as CollisionShape2D
		if forme == null or forme.shape == null:
			continue
		var boite: Rect2 = forme.global_transform * forme.shape.get_rect()
		haut = minf(haut, boite.position.y)
		bas = maxf(bas, boite.end.y)
	if haut > bas:
		return zone.global_position.y   # aucune forme lisible : l'origine de la zone
	return (haut + bas) * 0.5

func wall_griffe_input(event: InputEvent):
	# _fresh_press : jump partage le bouton de griffe — la pression qui a
	# accroché le mur ne doit pas faire sauter dans la foulée
	if _fresh_press("jump"):
		change_state(States.JUMP)

func wall_griffe_animation_finished():
	change_state(States.CHUTE)

func wall_griffe_exit():
	_griffe_lacher()


# --- La trace que la griffe laisse sur le mur (30 sept. 2026) ---
const TRACE_GRIFFE := preload("res://SCRIPT/SHADER/trace_de_griffe.tscn")
## Bout des doigts de la griffe pendant le wall run, dans le repère de POINT
## (perso tourné vers la droite). Mesuré sur l'animation `wall_griffe`.
@export var GRIFFE_BOUT := Vector2(-62.0, -112.0)
## La griffe n'est tendue contre le mur que sur ces images de l'animation
## (la première et la dernière la montrent ramenée contre le corps).
const GRIFFE_IMAGE_DEBUT := 1
const GRIFFE_IMAGE_FIN := 9
var _traces_griffe: Array[Node] = []   # deux, créées une fois pour toutes
var _trace_griffe: Node = null         # celle du trait en cours


## Deux traces suffisent : un trait s'éteint en moins d'une demi-seconde, bien
## avant que la griffe ait refait un tour d'animation. Créées ici, à
## l'apparition du joueur, jamais en plein jeu. Elles vivent dans le repère du
## monde (top_level) et se dessinent juste sous le joueur.
func _griffe_preparer() -> void:
	for i in 2:
		var trace := TRACE_GRIFFE.instantiate()
		trace.demo_boucle = false
		trace.top_level = true
		trace.z_index = -1
		add_child(trace)
		_traces_griffe.append(trace)


## Appelée à chaque pas de physique du wall run, APRÈS le déplacement.
func _griffe_tracer() -> void:
	# pas de trait tant que le perso glisse encore vers le milieu du mur : la
	# trace suppose une course horizontale
	var racle: bool = animator.frame >= GRIFFE_IMAGE_DEBUT and animator.frame <= GRIFFE_IMAGE_FIN \
			and absf(velocity.y) < 120.0
	if not racle:
		_griffe_lacher()
		return
	var bout: Vector2 = point.to_global(GRIFFE_BOUT)
	if _trace_griffe != null:
		_trace_griffe.suivre(bout)
		return
	for trace in _traces_griffe:
		if trace.libre():
			_trace_griffe = trace
			trace.vitesse = maxf(absf(velocity.x), 1.0)
			trace.poser(bout, last_direction)
			return


func _griffe_lacher() -> void:
	if _trace_griffe != null:
		_trace_griffe.lacher()
		_trace_griffe = null
#endregion





#region WALL_JUMP
@export_subgroup("Accroche et saut mural")
## vitesse de glisse le long du mur en état WALL_JUMP
@export var WALL_GLIDE_SPEED: float = 300.0

# --- Saut mural façon Hollow Knight : LÉGÈRE impulsion diagonale imposée,
# purement cosmétique (éviter de "baver" le long du mur en remontant) —
# on peut re-spammer le même mur juste après ---
## Poussée horizontale d'éloignement du mur pendant le verrou du saut mural
@export var WALL_JUMP_PUSH_X: float = 300.0
## Durée (s) du verrou : trajectoire diagonale incontrôlable au stick,
## mais interruptible par toute action aérienne (dash, coup, double saut…)
@export var WALL_JUMP_LOCK_TIME: float = 0.2
## Fenêtre (s) après un saut mural où une pression de saut est IGNORÉE (sans
## consommer le double saut) : évite que le spam du bouton transforme chaque
## saut mural en double saut vertical collé au mur
@export var WALL_JUMP_DJ_GRACE: float = 0.15
## Hauteur de la MAIN posée au mur dans la pose d'accroche (px au-dessus des
## pieds, mesurée sur l'image wall_jump). Le mur doit monter au moins
## jusque-là : pas d'accroche la main au-dessus du haut d'un mur.
@export var WALL_HAUTEUR_MAIN: float = 142.0
## Hauteur du PIED posé au mur (px au-dessus des pieds). Le mur doit descendre
## au moins jusque-là. Avec la main, ça fait 134 px de mur au minimum : le
## flanc d'une plateforme plus petite n'accroche pas.
@export var WALL_HAUTEUR_PIED: float = 8.0
## Jusqu'où on cherche le mur depuis l'axe du corps (px ; le corps fait 23 px
## de demi-largeur)
@export var WALL_PORTEE_CORPS: float = 46.0


## De quel côté est le mur ? +1 droite, -1 gauche, 0 aucun.
## Rayons lancés au niveau du torse, en coordonnées MONDE — contrairement à
## une inversion aveugle du regard, le résultat est toujours fiable
func _wall_side() -> int:
	var space := get_world_2d().direct_space_state
	var origin := global_position + Vector2(0.0, -60.0)
	for side in [1, -1]:
		var q := PhysicsRayQueryParameters2D.create(
			origin, origin + Vector2(side * 45.0, 0.0), 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit and hit.collider is StaticBody2D:
			return side
	return 0
var _wj_pending := false     # signal pour jump_enter : saut depuis un mur
var _wj_lock_timer := 0.0
var _wj_lock_dir := 0.0

func wall_jump_enter():
	# regard DOS AU MUR déduit de la position réelle du mur — l'inversion
	# aveugle (_flip_facing_on_wall) se trompait quand on re-accrochait un
	# mur sans s'être retourné, et le saut opposé partait DANS le mur
	var side := _wall_side()
	if side != 0:
		last_direction = -side
		point.scale.x = last_direction
	else:
		_flip_facing_on_wall()  # secours si aucun rayon ne confirme le mur
	print("[WJ] accroche  mur_cote=", side, " regard=", last_direction,
		" depuis=", States.keys()[previous_state])
	velocity = Vector2.ZERO
	_recharge_air_moves()
	animator.play("wall_jump")

func wall_jump_execute(_delta: float) -> void:
	# Vérif mur des DEUX côtés : les deux raycasts ne sont pas des
	# jumeaux parfaits (hauteur/longueur), et selon le point d'accroche
	# l'un peut rater là où l'autre touche → clignotement CHUTE↔WALL_JUMP.
	# Le test symétrique est insensible au flip et à leurs différences.
	var on_wall := _raycast_hits_wall(wall_left) or _raycast_hits_wall(wall_right)
	# … et il faut du mur sous la main et sous le pied (le mur est dans son dos) :
	# arrivé au bas d'un mur, il le lâche au lieu de pendre dans le vide
	if not on_wall or not _mur_couvre_le_corps(-last_direction):
		change_state(States.CHUTE)
		return
	# Plaque le perso contre le mur (même technique que wall_griffe) :
	# le mur bloque le déplacement réel, mais le contact physique et
	# les raycasts restent stables — sans ça, il flotte à quelques px
	# du mur et l'accroche peut osciller frame à frame
	velocity.x = -last_direction * 150.0
	# Appui légitime : la glissade murale remet la chute à zéro
	FALL_POINT = global_position.y
	# Glissement — TALISMAN « PRISE FERME » : on reste où on s'est accroché
	# (bas maintenu : on glisse quand même, pour descendre)
	if Player.talisman_equipe(TALISMAN_PRISE) and not Input.is_action_pressed("down_move"):
		velocity.y = 0.0
	else:
		velocity.y = lerp(velocity.y, WALL_GLIDE_SPEED, 0.05)
	if is_on_floor():
		change_state(States.IDLE)

func wall_jump_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		# saut mural = un VRAI saut via l'état JUMP normal, mais avec un
		# verrou diagonal façon Hollow Knight (voir jump_enter/_execute)
		var land_fx = instantiate_scene(WALL_JUMP_SCENE)
		land_fx.global_position = ANCRE_WALL.global_position
		land_fx.scale.x *= point.scale.x
		if land_fx is AnimatedSprite2D:
			land_fx.play()
		_wj_pending = true
		change_state(States.JUMP)
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)

func wall_jump_exit():
	velocity.x = 0.0  # annule la pression plaquée contre le mur
#endregion



func climb_enter() -> void:
	velocity = Vector2.ZERO
	_recharge_air_moves()
	animator.play("climbidle")

func climb_execute(delta: float) -> void:
	FALL_POINT = global_position.y  # appui légitime : en escalade
	var dir := Input.get_vector("left_move", "right_move",
		"up_move",   "down_move")

	const DEAD_ZONE := 0.3
	if abs(dir.x) < DEAD_ZONE:
		dir.x = 0

	var can_climb_forward := _raycast_hits_group(climbcast_right, "CLIMB")

	if not can_climb_forward and animator.animation != "climbquit":
		animator.play("climbquit")

	if can_climb_forward and animator.animation == "climbquit":
		animator.play("climbidle")

	if not can_climb_forward:
		if sign(point.scale.x) > 0:
			dir.x = min(dir.x, 0)
		else:
			dir.x = max(dir.x, 0)
		dir.y = 0

	if animator.animation != "climbquit":
		if dir == Vector2.ZERO:
			animator.play("climbidle")
		else:
			if abs(dir.x) > abs(dir.y):
				animator.play("climb_move_up")
			elif dir.y < 0:
				animator.play("climb_move_up")
			else:
				animator.play("climb_move_down")

	velocity = dir * CLIMB_SPEED
	_flip_from_input()

	var hit_left  := _raycast_hits_group(climbcast_left,  "CLIMB")
	var hit_right := _raycast_hits_group(climbcast_right, "CLIMB")
	if not (hit_left or hit_right):
		change_state(States.CHUTE)
		return

	var hit_up := _raycast_hits_group(climbcast_up, "CLIMB")
	if not hit_up:
		_climb_auto_exit = true
		change_state(States.JUMP)
		return

func climb_input(event: InputEvent) -> void:
	# FIX: déplacé depuis climb_execute — just_pressed appartient à _input
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)
		return
	elif _fresh_press("jump"):  # même bouton que griffe → filtre la pression d'entrée
		change_state(States.JUMP)
		return

func climb_exit() -> void:
	pass


# =====================  ECHELLE  ===========================
#region ECHELLE
## État parallèle à CLIMB, dédié aux échelles (zones Area2D du groupe
## "ECHELLE") : on ne peut QUE monter et descendre. Seule échappatoire : sauter.

@export_group("Échelle")
@export var ECHELLE_SPEED: float = 250.0
## Butée haute de grimpe : distance (px) entre le sommet de la ZONE de
## l'échelle et l'origine du perso au maximum de la montée. Plus grand =
## le perso s'arrête plus bas. À régler à l'œil dans l'inspecteur.
@export var ECHELLE_TOP_OFFSET: float = 150.0
## Portée de raccord entre échelles empilées : distance (px) au-dessus de la
## sonde torse où l'on cherche l'échelle suivante une fois la butée atteinte
@export var ECHELLE_CHAIN_REACH: float = 300.0
## Distance (px) sondée sous les pieds pour le raccord descendant entre
## deux échelles empilées
@export var ECHELLE_BELOW_REACH: float = 120.0
## Enfoncement immédiat (px) à l'accroche depuis une plateforme : sans lui,
## le perso reste en pose de grimpe flottant au-dessus de la planche
@export var ECHELLE_GRAB_SINK: float = 70.0
var _current_echelle: Area2D = null
var _echelle_enter_pframe := 0  # frame physique d'accroche (garde anti-éjection)


## Bord haut (y global) de la zone d'une échelle, lu depuis son CollisionShape2D
func _echelle_zone_top(ladder: Area2D) -> float:
	for child in ladder.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			return child.global_position.y - child.shape.size.y * 0.5 * absf(child.global_scale.y)
	return ladder.global_position.y


## Sortie haute d'échelle : pose le perso DEBOUT sur le sol au-dessus du
## sommet (l'échelle vit toujours sous une plateforme one-way dédiée).
## On restaure d'abord le masque one-way (coupé pendant l'état), on cherche
## la surface par rayon autour du sommet de la zone, puis on pose les pieds
## dessus avec une micro-poussée vers le bas pour valider le contact au sol
## dès le premier frame — ni chute parasite, ni particules d'atterrissage.
func _echelle_pose_au_sommet() -> void:
	set_collision_mask_value(ONEWAY_LAYER, true)
	var top := _echelle_zone_top(_current_echelle) if _current_echelle != null \
		else global_position.y
	# cherche la surface du sol depuis au-dessus du sommet de zone jusqu'au
	# niveau des pieds : couvre aussi bien une zone collée à la planche
	# qu'une zone volontairement étirée bien au-dessus (réglage d'émergence)
	var q := PhysicsRayQueryParameters2D.create(
		Vector2(global_position.x, top - 80.0),
		Vector2(global_position.x, global_position.y + 20.0),
		collision_mask)
	q.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit:
		global_position.y = hit.position.y
	else:
		global_position.y = top
	velocity = Vector2(0.0, 50.0)  # micro-poussée : contact sol immédiat
	print("[ECH] sortie HAUT (pose au sommet)  perso_y=",
		snappedf(global_position.y, 0.1), " sol_trouve=", not hit.is_empty())
	goto_state(States.IDLE)


## Bord bas (y global) de la zone d'une échelle
func _echelle_zone_bottom(ladder: Area2D) -> float:
	for child in ladder.get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			return child.global_position.y + child.shape.size.y * 0.5 * absf(child.global_scale.y)
	return ladder.global_position.y


## Cherche une zone du groupe "ECHELLE" en un point donné.
## En cas de chevauchement, privilégie l'échelle qui monte le plus haut.
func _find_echelle_at(point: Vector2) -> Area2D:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = point
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var best: Area2D = null
	for hit in get_world_2d().direct_space_state.intersect_point(params, 8):
		var col = hit.get("collider")
		if col is Area2D and col.is_in_group("ECHELLE"):
			if best == null or _echelle_zone_top(col) < _echelle_zone_top(best):
				best = col
	return best


## Cherche une zone du groupe "ECHELLE" au niveau du torse du perso
func _find_echelle() -> Area2D:
	return _find_echelle_at(global_position + Vector2(0.0, -60.0))


## Tente d'accrocher une échelle (appui haut/bas dans les états qui le permettent)
func _try_echelle() -> bool:
	var ladder := _find_echelle()
	if ladder == null:
		# secours au niveau des pieds : accroche depuis une plateforme dont
		# la zone ne dépasse que peu au-dessus de la surface — l'échelle
		# garde ainsi la priorité sur le DROP
		ladder = _find_echelle_at(global_position + Vector2(0.0, -8.0))
	if ladder == null:
		return false
	_current_echelle = ladder
	change_state(States.ECHELLE)
	return true


func echelle_enter() -> void:
	velocity = Vector2.ZERO
	_recharge_air_moves()
	_echelle_enter_pframe = Engine.get_physics_frames()
	# sur l'échelle, les plateformes traversables (one-way) ne bloquent plus :
	# indispensable pour descendre depuis un rebord ou croiser une plateforme
	set_collision_mask_value(ONEWAY_LAYER, false)
	# aimante le perso sur l'axe central de l'échelle
	if _current_echelle != null:
		global_position.x = _current_echelle.global_position.x
		var top := _echelle_zone_top(_current_echelle)
		# accroche au-dessus de la butée (depuis une plateforme) : petit
		# enfoncement immédiat pour empoigner l'échelle au lieu de flotter
		var limite := top + ECHELLE_TOP_OFFSET
		if global_position.y < limite:
			global_position.y = minf(global_position.y + ECHELLE_GRAB_SINK, limite)
		print("[ECH] enter  perso_y=", snappedf(global_position.y, 0.1),
			" haut_zone=", snappedf(top, 0.1),
			" ecart(perso-haut)=", snappedf(global_position.y - top, 0.1),
			" au_sol=", is_on_floor())
	animator.play("climbidle")


func echelle_execute(_delta: float) -> void:
	# ancre légitime : pas de chute accumulée tant qu'on est sur l'échelle
	FALL_POINT = global_position.y

	# uniquement monter / descendre — aucun déplacement horizontal
	var dir := Input.get_axis("up_move", "down_move")
	var vy_prec := velocity.y  # conservé pour la vraie gravité pendant la glisse
	velocity.x = 0.0
	velocity.y = dir * ECHELLE_SPEED

	# échelles empilées : la sonde passe d'une échelle à l'autre en grimpant.
	# On ne monte jamais en grade vers le bas ici (sinon ping-pong avec le
	# raccord) : la descente vers une échelle plus basse passe uniquement
	# par le raccord descendant explicite plus bas.
	var ladder := _find_echelle()
	if ladder != null and (_current_echelle == null
		or _echelle_zone_top(ladder) <= _echelle_zone_top(_current_echelle)):
		_current_echelle = ladder

	# BUTÉE HAUTE géométrique : quoi que dise la sonde, l'origine du perso ne
	# reste jamais au-dessus du sommet de la zone + ECHELLE_TOP_OFFSET.
	# `au_dessus_butee` = accroché depuis un rebord ou re-grab trop haut :
	# au lieu de téléporter, on GLISSE vers la butée à vitesse d'échelle.
	var au_dessus_butee := false
	if _current_echelle != null:
		var limite := _echelle_zone_top(_current_echelle) + ECHELLE_TOP_OFFSET
		au_dessus_butee = global_position.y < limite - 4.0
		if global_position.y <= limite:
			if dir < 0.0:
				# une échelle continue-t-elle au-dessus ? raccord sans saut
				var next := _find_echelle_at(global_position
					+ Vector2(0.0, -60.0 - ECHELLE_CHAIN_REACH))
				if next != null and _echelle_zone_top(next) < _echelle_zone_top(_current_echelle):
					print("[ECH] raccord vers l'échelle du dessus")
					_current_echelle = next
					global_position.x = next.global_position.x  # ré-aimante en x
				else:
					# butée atteinte en montant, rien au-dessus : pose debout
					# sur le sol au-dessus du sommet (plus de saut)
					_echelle_pose_au_sommet()
					return
			elif ladder != null:
				# (si ladder == null on est en transit de raccord descendant :
				#  on garde la vitesse d'échelle, ni glisse ni téléport)
				if au_dessus_butee:
					# chute libre (vraie gravité) jusqu'à la butée
					velocity.y = maxf(vy_prec, 0.0) + gravity * _delta
				else:
					global_position.y = limite
					velocity.y = maxf(velocity.y, 0.0)

	# animations : toujours celles de l'échelle, même pendant la glisse
	# vers la butée (plus d'anim de chute parasite à l'accroche haute)
	if dir < 0.0:
		if animator.animation != "climb_move_up":
			animator.play("climb_move_up")
	elif dir > 0.0:
		if animator.animation != "climb_move_down":
			animator.play("climb_move_down")
	else:
		if animator.animation != "climbidle":
			animator.play("climbidle")

	# plus d'échelle sous la main (au torse) → sortie selon la situation
	if ladder == null:
		# en glisse depuis un rebord vers la butée : on ne sort pas encore
		if au_dessus_butee:
			return
		# transit entre deux échelles raccordées : la sonde est encore sous la
		# zone de l'échelle adoptée au-dessus → on continue de grimper
		if dir < 0.0 and _current_echelle != null \
			and global_position.y - 60.0 > _echelle_zone_bottom(_current_echelle):
			return
		# raccord DESCENDANT échelle→échelle : une échelle continue en
		# dessous → on descend vers elle sans lâcher prise
		if dir > 0.0:
			var next_bas := _find_echelle_at(global_position + Vector2(0.0, ECHELLE_BELOW_REACH))
			if next_bas != null:
				if next_bas != _current_echelle:
					print("[ECH] raccord vers l'échelle du dessous")
					_current_echelle = next_bas
					global_position.x = next_bas.global_position.x  # ré-aimante en x
				return
		if dir < 0.0:
			# raccord MONTANT : même si la sonde a décroché, une échelle
			# continue peut-être au-dessus → on l'adopte au lieu de sauter
			var next_haut := _find_echelle_at(global_position
				+ Vector2(0.0, -60.0 - ECHELLE_CHAIN_REACH))
			if next_haut != null and (_current_echelle == null
				or _echelle_zone_top(next_haut) < _echelle_zone_top(_current_echelle)):
				print("[ECH] raccord vers l'échelle du dessus (sonde)")
				_current_echelle = next_haut
				global_position.x = next_haut.global_position.x  # ré-aimante en x
				return
			# sortie par le HAUT en montant : pose debout sur le sol au-dessus
			_echelle_pose_au_sommet()
		elif is_on_floor():
			print("[ECH] sortie SOL  perso_y=", snappedf(global_position.y, 0.1))
			goto_state(States.IDLE)
		else:
			print("[ECH] sortie CHUTE  perso_y=", snappedf(global_position.y, 0.1))
			goto_state(States.CHUTE)
		return

	# pieds au sol en descendant → arrivé en bas.
	# Garde de 3 frames après l'accroche : en s'accrochant depuis une
	# plateforme (appui bas au-dessus de l'échelle), is_on_floor est encore
	# "vrai" au premier frame et éjectait l'état avant la descente
	if is_on_floor() and dir > 0.0 and not au_dessus_butee \
		and Engine.get_physics_frames() > _echelle_enter_pframe + 3:
		goto_state(States.IDLE)


func echelle_input(_event: InputEvent) -> void:
	# sauter depuis n'importe quel point de l'échelle
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	# esquive (rond) : lâcher prise et se laisser tomber
	if Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)


func echelle_exit() -> void:
	_current_echelle = null
	velocity = Vector2.ZERO
	set_collision_mask_value(ONEWAY_LAYER, true)
#endregion



var _roll_forced := false  # roulade relancée faute de place pour se relever

func roll_enter() -> void:
	_roll_forced = false
	var dir := Input.get_axis("left_move", "right_move")

	if dir != 0.0:
		dir = sign(dir)
		last_direction = dir
		point.scale.x  = dir
		velocity.x     = dir * ROLL_SPEED
		animator.play("roll")
		# Hitbox compacte pendant la roulade (la normale est restaurée par roll_exit)
		collision_normale.set_deferred("disabled", true)
		collision_roulade.set_deferred("disabled", false)
	else:
		# Pas de direction → on ne roll pas, retour IDLE (différé, avec le garde-fou
		# de goto_state : un coup encaissé entre-temps garde son HIT)
		call_deferred("_goto_differe", States.IDLE, States.ROLL)

func roll_execute(delta: float) -> void:
	velocity.y += gravity * delta
	# Réaffirme la vitesse à chaque frame : move_and_slide l'annule sur une
	# collision frontale (ex. obstacle à hauteur de tête percuté à la frame 1,
	# quand l'ancienne hitbox est encore active) — sans ça, roulade sur place.
	# Les roulades forcées (sous un plafond bas) avancent 2× moins vite.
	velocity.x = last_direction * ROLL_SPEED * (0.5 if _roll_forced else 1.0)

	# percuter un mur stoppe la roulade — sauf si pas la place de se relever
	# (tunnel bas : on reste en roulade, quitte à pousser contre le mur)
	if _raycast_hits_wall(wall_right) and _can_stand_up():
		goto_state(States.IDLE)
		return

## Y a-t-il la place de se relever ici ? Teste la capsule debout contre les
## murs solides (layer 1 uniquement : les one-way ne bloquent pas le relevé)
func _can_stand_up() -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision_normale.shape
	var xf := collision_normale.global_transform
	xf.origin.y -= 4.0  # léger décalage vers le haut pour ignorer le contact au sol
	params.transform = xf
	params.collision_mask = 1
	params.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()


func roll_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump") and _can_stand_up():
		change_state(States.JUMP)

func roll_exit() -> void:
	collision_normale.set_deferred("disabled", false)
	collision_roulade.set_deferred("disabled", true)

# =====================  DASH AÉRIEN  ===========================
#region DASH
## Version aérienne de l'esquive (même touche) : mêmes vitesse et distance
## que la roulade (700 px/s pendant 0.727 s ≈ 509 px), horizontal pur.
## Un seul dash par phase aérienne, rechargé au sol / mur / grab.

@export_group("Dash aérien")
## Capacité metroidvania : désactivable tant qu'elle n'est pas débloquée
@export var air_dash_enabled := true
## Vitesse du dash (2× la roulade — la distance reste identique grâce à
## la durée divisée par deux : ~509 px au total)
@export var DASH_SPEED: float = 1400.0
@export var DASH_DURATION: float = 0.2363
var _air_dash_used := false
var _dash_timer := 0.0
## le souffle d'air laissé au point de départ du dash (30 sept. 2026)
const SOUFFLE_DASH := preload("res://SCRIPT/SHADER/souffle_dash.tscn")
var _souffle_dash: Node = null
var _dash_depart_x := 0.0


## Tente le dash aérien (touche esquive en l'air, depuis JUMP ou CHUTE)
func _try_air_dash() -> bool:
	if not air_dash_enabled or _air_dash_used or is_on_floor():
		return false
	_air_dash_used = true
	change_state(States.DASH)
	return true


func dash_enter() -> void:
	# direction : l'input s'il est tenu, sinon le regard
	var dir := Input.get_axis("left_move", "right_move")
	if dir != 0.0:
		last_direction = sign(dir)
		point.scale.x = last_direction
	_dash_timer = 0.0
	velocity = Vector2(last_direction * DASH_SPEED, 0.0)
	animator.play("dash")
	_poser_souffle_dash()


## Le souffle reste AU POINT DE DÉPART (hébergé par la scène, derrière le
## joueur) : on s'en éloigne. Il connaît la vitesse et la portée du dash pour
## que son sillage ne nous dépasse jamais.
func _poser_souffle_dash() -> void:
	var fx := SOUFFLE_DASH.instantiate()
	fx.demo_boucle = false
	fx.vitesse = DASH_SPEED
	fx.distance = DASH_SPEED * DASH_DURATION
	var hote: Node = get_tree().current_scene
	if hote == null:
		hote = get_parent()
	hote.add_child(fx)
	fx.global_position = centre_corps()
	fx.scale = Vector2(last_direction, 1.0)
	_souffle_dash = fx
	_dash_depart_x = global_position.x


func dash_execute(delta: float) -> void:
	_dash_timer += delta
	# trajectoire figée : horizontal pur, la gravité est suspendue
	velocity.x = last_direction * DASH_SPEED
	velocity.y = 0.0

	# percuter un mur interrompt le dash : accroche immédiate en glissade
	# (raycast avant uniquement — l'arrière raccrocherait le mur qu'on quitte)
	if _raycast_hits_wall(wall_right) and _mur_couvre_le_corps(last_direction):
		change_state(States.WALL_JUMP)
		return
	if is_on_floor():
		_handle_landing()
		return
	if _dash_timer >= DASH_DURATION:
		goto_state(States.CHUTE)


func dash_exit() -> void:
	velocity.x = 0.0
	# dash coupé court (mur, sol) : le sillage s'arrête où l'on s'est arrêté
	if is_instance_valid(_souffle_dash):
		_souffle_dash.arreter_a(absf(global_position.x - _dash_depart_x))
	_souffle_dash = null
#endregion


func roll_animation_finished() -> void:
	# Pas la place de se relever (fin de roulade sous un passage bas) :
	# on repart pour une roulade, en laissant le joueur choisir la direction
	# (maintenir la direction opposée permet de faire demi-tour)
	if not _can_stand_up():
		_roll_forced = true  # les relances avancent à demi-vitesse
		var dir := Input.get_axis("left_move", "right_move")
		if dir != 0.0:
			last_direction = sign(dir)
			point.scale.x = last_direction
		animator.play("roll")
		return

	var horiz := Input.get_action_strength("right_move") - Input.get_action_strength("left_move")

	if horiz != 0.0:
		goto_state(States.RUN)
	elif Input.is_action_pressed("jump"):
		goto_state(States.JUMP)
	elif not is_on_floor():
		goto_state(States.CHUTE)
	else:
		goto_state(States.IDLE)



func chute_griffe_enter() -> void:
	_recharge_air_moves()
	animator.play("chute_griffe")
	velocity.y = 250.0

func chute_griffe_execute(delta: float) -> void:
	FALL_POINT = global_position.y  # descente contrôlée : pas de chute accumulée
	const GLIDE_Y   := 250.0
	const GLIDE_X   := 150.0
	const DECELRATE := 0.50

	var dir := Input.get_axis("left_move", "right_move")
	if dir != 0:
		velocity.x = dir * GLIDE_X
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELRATE * delta)

	velocity.y = GLIDE_Y

	# is_action_pressed (pas just_pressed) → OK dans execute
	var still_holding := _raycast_hits_group(climbcast_up, "CHUTE") \
		and Input.is_action_pressed("griffe")

	if not still_holding:
		change_state(States.CHUTE)

func chute_griffe_input(event: InputEvent) -> void:
	pass

func chute_griffe_exit() -> void:
	pass



#region GRAB
const GRAB_LERP_SPEED := 600.0   # vitesse d'approche en pixels/sec
var _grab_locked := false          # true quand le perso a atteint le point

func grab_enter() -> void:
	velocity = Vector2.ZERO
	_grab_locked = false
	_recharge_air_moves()
	animator.play("chute")  # on garde l'anim de chute pendant l'approche

func grab_execute(delta: float) -> void:
	FALL_POINT = global_position.y  # appui légitime : accroché à un point
	if not current_grab_area:
		change_state(States.CHUTE)
		return

	var grab_pos = current_grab_area.global_position
	var offset = ancre_grab.global_position - global_position
	var target_pos = grab_pos - offset

	if not _grab_locked:
		# Phase d'approche — le perso glisse vers le point
		global_position = global_position.move_toward(target_pos, GRAB_LERP_SPEED * delta)
		if global_position.distance_to(target_pos) < 2.0:
			global_position = target_pos
			_grab_locked = true
			animator.play("suspendu")  # anim seulement quand on est accroché
	else:
		# Phase accrochée — on reste collé
		global_position = target_pos

func grab_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
	elif Input.is_action_just_pressed("esquive"):
		change_state(States.CHUTE)

func grab_exit() -> void:
	_grab_locked = false
	current_grab_area = null
	_grab_cooldown_timer = GRAB_COOLDOWN
#endregion


# =====================  ATTAQUES  ===========================
# AMÉLIORATION: combo_buffered remplace le bool "combo"
# Chaque état d'attaque l'utilise de la même façon :
# - enter: reset combo_buffered = false
# - input: si le joueur appuie pendant l'anim principale → combo_buffered = true
# - animation_finished: si combo_buffered → chaîne, sinon → recovery (anim _r)

@export_group("Attaques")
## Le slash des attaques est joué EN SHADER (SCRIPT/SHADER/slash_heros.tscn :
## le même croissant que les dessins, mais à chaque image d'écran). Décoché :
## retour aux dessins d'origine. Visuel seulement, la hitbox ne change pas.
@export var slash_en_shader := true

@export_group("Talismans")
@export_subgroup("Lame de foudre")
## TALISMAN « LAME DE FOUDRE » (30 sept. 2026, id "foudre" dans
## SCRIPT/TALISMAN/talismans.gd) : porté, le slash est fait de foudre (réglages
## sur le matériau de SCRIPT/SHADER/slash_heros.tscn), les coups font +10 %
## (`degats_pourcent` du catalogue, un pourcentage des dégâts de base) et
## chaque coup qui PORTE bondit sur l'ennemi le plus proche (animator.gd,
## `_foudre_bondir`).
## portée du bond, depuis le corps de l'ennemi touché (px) — 280 au départ,
## +50 % après essai en jeu (30 sept. 2026)
@export var foudre_portee := 420.0
## dégâts du premier bond, en PART des dégâts du coup qui l'a lancé (0.5 = la
## moitié : 39 pour un coup de 77) ; chaque bond suivant en fait la moitié
@export_range(0.05, 1.0, 0.05) var foudre_part := 0.5
## nombre de bonds : 1 = l'éclair saute sur un seul voisin
@export_range(1, 3) var foudre_sauts := 1

## Déplacement type RUN pendant les attaques : contrôle au stick, même vitesse
## et même inertie que run_execute. Pas de flip — le perso garde la direction
## de son attaque (il peut donc reculer en marche arrière pendant le coup).
func _attack_run_movement(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)
		return
	var direction := Input.get_axis("left_move", "right_move")
	var target_speed := float(direction) * GROUND_SPEED_ATTACK
	velocity.x = lerp(velocity.x, target_speed, 0.15)


## Le perso est-il en mouvement pendant une attaque ? (direction maintenue)
## Détermine si le combo peut sauter l'animation de retour (recovery) :
## en mouvement → enchaînement direct ; immobile → recovery obligatoire.
func _attack_is_moving() -> bool:
	return Input.get_axis("left_move", "right_move") != 0.0


func attack_light_1_enter() -> void:
	slash_attack.position = Vector2(-4, -70)
	_flip_from_input()
	combo_buffered = false
	animator.play("attack")

func attack_light_1_execute(delta: float) -> void:
	_attack_run_movement(delta)

func attack_light_1_input(event: InputEvent) -> void:
	# CANCEL DÉFENSIF : sauter ou rouler interrompt l'attaque à tout moment
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	# Buffer pendant l'anim principale
	if event.is_action("light_attack") \
		and event.is_pressed() \
		and not event.is_echo() \
		and animator.animation == "attack":
		combo_buffered = true
	# Pendant la recovery
	if animator.animation == "attack_r":
		if Input.is_action_just_pressed("light_attack"):
			if _attack_is_moving():
				change_state(States.ATTACK_LIGHT_2)  # en mouvement : cancel direct
			else:
				combo_buffered = true  # immobile : partira à la fin de la recovery
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)

func attack_light_1_animation_finished() -> void:
	match animator.animation:
		"attack":
			# Skip de la recovery uniquement si le perso est en mouvement
			if combo_buffered and _attack_is_moving():
				change_state(States.ATTACK_LIGHT_2)
				return
			# Immobile : recovery obligatoire (le combo bufferisé reste en attente)
			animator.play("attack_r")
		"attack_r":
			if combo_buffered:
				change_state(States.ATTACK_LIGHT_2)
				return
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)

func attack_light_1_exit() -> void:
	combo_buffered = false




func attack_light_2_enter() -> void:
	_flip_from_input()
	combo_buffered = false
	animator.play("attack_02")


func attack_light_2_execute(delta: float) -> void:
	_attack_run_movement(delta)

func attack_light_2_input(event: InputEvent) -> void:
	# CANCEL DÉFENSIF : sauter ou rouler interrompt l'attaque à tout moment
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	if event.is_action("light_attack") \
		and event.is_pressed() \
		and not event.is_echo() \
		and animator.animation == "attack_02":
		combo_buffered = true
	if animator.animation == "attack_02_r":
		if Input.is_action_just_pressed("light_attack"):
			if _attack_is_moving():
				change_state(States.ATTACK_LIGHT_1)  # en mouvement : cancel direct
			else:
				combo_buffered = true  # immobile : partira à la fin de la recovery
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)

func attack_light_2_animation_finished() -> void:
	match animator.animation:
		"attack_02":
			# Skip de la recovery uniquement si le perso est en mouvement
			if combo_buffered and _attack_is_moving():
				change_state(States.ATTACK_LIGHT_1)
				return
			# Immobile : recovery obligatoire (le combo bufferisé reste en attente)
			animator.play("attack_02_r")
		"attack_02_r":
			if combo_buffered:
				change_state(States.ATTACK_LIGHT_1)
				return
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)

func attack_light_2_exit() -> void:
	combo_buffered = false




func attack_light_3_enter() -> void:
	_flip_from_input()
	combo_buffered = false
	animator.play("attack_03")

func attack_light_3_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)

func attack_light_3_input(event: InputEvent) -> void:
	# CANCEL DÉFENSIF : sauter ou rouler interrompt l'attaque à tout moment
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)
		return
	if animator.animation == "attack_03_r":
		if Input.is_action_just_pressed("light_attack"):
			change_state(States.ATTACK_LIGHT_1)
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			change_state(States.RUN)
		elif Input.is_action_just_pressed("jump"):
			change_state(States.JUMP)

func attack_light_3_animation_finished() -> void:
	match animator.animation:
		"attack_03":
			animator.play("attack_03_r")
		"attack_03_r":
			if Input.is_action_just_pressed("light_attack"):
				change_state(States.ATTACK_LIGHT_1)
			elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
				return
			else:
				change_state(States.IDLE)
				return

func attack_light_3_exit() -> void:
	combo_buffered = false



func attack_lourde_enter() -> void:
	slash_attack.position = Vector2(-32, -92)
	animator.play("attack_lourde")

func attack_lourde_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)

func attack_lourde_input(event: InputEvent) -> void:
	# CANCEL DÉFENSIF : même la lourde s'interrompt pour esquiver
	if Input.is_action_just_pressed("esquive"):
		change_state(States.ROLL)
		return
	if Input.is_action_just_pressed("jump"):
		change_state(States.JUMP)

func attack_lourde_animation_finished() -> void:
	match animator.animation:
		"attack_lourde":
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
			else:
				change_state(States.IDLE)

func attack_lourde_exit() -> void:
	pass



func attack_air_enter() -> void:
	slash_attack.position = Vector2(-4, -73)
	animator.play("attack_air")
	if velocity.y < 0.0:
		velocity.y = 0.0  # stoppe la montée, la gravité prend le relais

func attack_air_execute(delta: float) -> void:
	velocity.y = minf(velocity.y + gravity * GRAVITY_FALL * delta, MAX_FALL_SPEED)
	_planer_tick(delta)   # on peut frapper en planant : l'aile reste ouverte

	if is_on_floor():
		_handle_landing()

func attack_air_input(event: InputEvent) -> void:
	# CANCEL DÉFENSIF aérien : dash ou double saut interrompent l'attaque
	if _fresh_press("esquive") and _try_air_dash():
		return
	if _fresh_press("jump") and _try_double_jump():
		return

func attack_air_animation_finished() -> void:
	match animator.animation:
		"attack_air":
			change_state(States.CHUTE)

func attack_air_exit() -> void:
	pass



@export_group("Soin et boule de sang")
@export_subgroup("Soin")
## Coût du soin, en SANG (la jauge remplie par les récoltes)
@export var HEAL_COST: int = 100
## Cœurs rendus par un soin complet
@export var HEAL_AMOUNT: int = 2

## Tente de lancer le soin : refuse si pas assez de sang ou déjà plein PV.
## Le coût n'est débité qu'à la FIN de l'animation (soin interrompu = gratuit)
func _try_heal() -> void:
	if Player.hp >= Player.MAX_HP:
		return
	if Player.bloodheal < HEAL_COST:
		_notify_insufficient("bloodheal")
		return
	change_state(States.HEAL)


func heal_enter() -> void:
	# se soigner exige l'immobilité : on coupe tout élan résiduel
	velocity.x = 0.0
	# SOIN ÉCLAIR : la même animation, plus vite (elle seule : le coût et les
	# cœurs rendus ne changent pas)
	var vitesse_soin := soin_eclair_vitesse if Player.talisman_equipe(TALISMAN_SOIN_ECLAIR) else 1.0
	animator.play("heal", vitesse_soin)
	_offrande_lancer()

func heal_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		change_state(States.CHUTE)

func heal_input(event: InputEvent) -> void:
	pass

func heal_animation_finished() -> void:
	match animator.animation:
		"heal":
			Player.changement_de_bloodheal(-HEAL_COST)
			Player.changement_de_vie(HEAL_AMOUNT)
			if Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
				change_state(States.RUN)
			else:
				change_state(States.IDLE)

func heal_exit() -> void:
	velocity.x = 0
	_offrande_eteindre()


## TALISMAN « OFFRANDE » : le soin commence, le sceau naît à nos pieds (au sol
## seulement : en l'air il n'aurait rien sur quoi se poser)
func _offrande_lancer() -> void:
	if not Player.talisman_equipe(TALISMAN_OFFRANDE) or not is_on_floor():
		return
	_offrande_eteindre()
	var s := SCEAU_SCENE.instantiate()
	s.demo_boucle = false
	s.joueur = self
	s.rayon = offrande_rayon
	s.degats = maxi(roundi(animator.degats_du_coup() * offrande_part), 1)
	get_tree().current_scene.add_child(s)
	s.global_position = global_position          # sous nos pieds
	_sceau = s
	print("[OFFRANDE] f=", Engine.get_physics_frames(), " sceau posé, onde de ",
		offrande_rayon, " px, ", s.degats, " dégâts")


## le soin est fini (ou interrompu) : le sceau s'éteint (son onde finit sa course)
func _offrande_eteindre() -> void:
	if _sceau != null and is_instance_valid(_sceau):
		_sceau.eteindre()
	_sceau = null


# =====================  BLOODBALL (sort de boule de sang)  ==================
#region BLOODBALL

const BLOODBALL_SCENE := preload("res://SCRIPT/SPELL/bloodball.tscn")
## TALISMAN « Tornade de sang » : tant qu'il est équipé, le sort lance ce
## projectile-là à la place de la boule (même coût, même geste)
const TORNADE_SCENE := preload("res://SCRIPT/SPELL/tornade_de_sang.tscn")
const TALISMAN_TORNADE := "tornade_bloodball"
@export_subgroup("Boule de sang")
## Durée du lancer avant de rendre la main (en attendant une anim de cast dédiée)
@export var BLOODBALL_CAST_TIME: float = 0.25
## Coût en sang d'une boule
## Coût en sang d'une boule — 0 pour le moment : tir ILLIMITÉ (rééquilibrage
## sept. 2026, remettre un coût ici le jour où le sort redevient payant)
@export var BLOODBALL_COST: int = 0
var _cast_timer := 0.0


## Tente de lancer le sort : vérifie la jauge de sang ; si insuffisante,
## déclenche le feedback UI (jauge qui tremble + clignote rouge) sans caster
func _try_cast_bloodball() -> void:
	if Player.bloodheal < BLOODBALL_COST:
		_notify_insufficient("bloodheal")
		return
	change_state(States.BLOODBALL)


## Feedback universel de coût refusé : fait trembler/clignoter l'UI de la
## ressource concernée ("sang" = jauge, "blood" = compteur)
func _notify_insufficient(kind: String) -> void:
	var huds := get_tree().get_nodes_in_group("UI_Bloodheal")
	if not huds.is_empty() and huds[0].has_method("insufficient_feedback"):
		huds[0].insufficient_feedback(kind)

func bloodball_enter() -> void:
	print("[SPELL] cast ! spawn de la boule au marker ", spellcast.global_position)
	Player.changement_de_bloodheal(-BLOODBALL_COST)  # le sort boit son sang
	# Au sol : le perso se plante pour lancer. En l'air : comme l'attaque
	# aérienne, le cast ne touche pas à l'élan du saut
	if is_on_floor():
		animator.play("cast")
		velocity.x = 0.0
	else:
		animator.play("cast_air")
	_cast_timer = 0.0

	var scene := TORNADE_SCENE if Player.talisman_equipe(TALISMAN_TORNADE) else BLOODBALL_SCENE
	var ball := scene.instantiate()
	ball.dir = int(signf(point.scale.x))
	# TROP-PLEIN : remplie par trois coups d'épée, elle sort grosse et forte ;
	# la roue de l'épaule crève
	if trop_plein_pret():
		ball.grossir(trop_plein_taille, trop_plein_degats)
		trop_plein_coups = 0
		if _trop_plein != null:
			_trop_plein.crever()
		print("[TROP-PLEIN] f=", Engine.get_physics_frames(), " boule pleine : ×",
			trop_plein_taille, " de taille, ×", trop_plein_degats, " de dégâts")
	# SANG CORROMPU : violette, elle empoisonne (la Tornade aussi)
	if Player.talisman_equipe(TALISMAN_CORROMPU):
		ball.corrompre(corrompu_coeur, corrompu_couleur, corrompu_ombre)
	# PACTE DE SANG : payée sur la jauge de soin, elle frappe trois fois plus
	# fort ; jauge trop basse : elle part normale
	if Player.talisman_equipe(TALISMAN_PACTE) and Player.bloodheal >= pacte_cout:
		Player.changement_de_bloodheal(-pacte_cout)
		ball.pacte(pacte_multiplicateur, pacte_coeur, pacte_couleur, pacte_ombre)
		print("[PACTE] f=", Engine.get_physics_frames(), " boule payée ", pacte_cout,
			" de jauge (reste ", Player.bloodheal, ") : ", ball.damage, " de dégâts")
	get_tree().current_scene.add_child(ball)
	ball.global_position = spellcast.global_position

func bloodball_execute(delta: float) -> void:
	velocity.y += gravity * delta
	if not is_on_floor():
		_planer_tick(delta)   # un sort en planant : l'aile reste ouverte
	_cast_timer += delta
	if _cast_timer >= BLOODBALL_CAST_TIME:
		if not is_on_floor():
			goto_state(States.CHUTE)
		elif Input.is_action_pressed("right_move") or Input.is_action_pressed("left_move"):
			goto_state(States.RUN)
		else:
			goto_state(States.IDLE)

func bloodball_exit() -> void:
	pass
#endregion



# -------------------------------------------------
# HIT
# -------------------------------------------------




@export_group("Coups reçus")
@export_subgroup("Monstres")
@export var HIT_STUN_TIME: float = 0.25
@export var HIT_KNOCK_X:  float = 1300.0
@export var HIT_KNOCK_Y:  float = -287.0   # × 1,6 avec la gravité projet à 2500 : même soulèvement qu'à −180 sous 980
@export var HIT_X_DAMP:   float = 8.0

var _hit_elapsed := 0.0

func hit_enter() -> void:
	# Le déplacement est géré par le knockback superposé (_knock) ;
	# l'état HIT ne s'occupe que du stun et de l'animation
	velocity = Vector2.ZERO
	animator.play("hit")
	_hit_elapsed = 0.0


func hit_execute(delta: float) -> void:
	_hit_elapsed += delta
	velocity.y += gravity * delta

	if _hit_elapsed >= HIT_STUN_TIME:
		if is_on_floor():
			goto_state(States.IDLE)
		else:
			goto_state(States.CHUTE)

func hit_exit() -> void:
	velocity = Vector2.ZERO
	_knock = Vector2.ZERO  # fin du stun = contrôle rendu, aucune poussée résiduelle


# -------------------------------------------------
# DEAD — FIX: ajout de la gravité + blocage propre
# -------------------------------------------------
# ---- DÉMO : écran de mort (voile sombre + "Press X to revive") -----------
# À SUPPRIMER après la démo : cette constante, la ligne marquée DÉMO dans
# dead_enter, et le fichier SCRIPT/UTILITAIRE/ecran_mort_demo.gd.
const ECRAN_MORT_DEMO := preload("res://SCRIPT/UTILITAIRE/ecran_mort_demo.gd")
# --------------------------------------------------------------------------
func dead_enter() -> void:
	animator.play("death")
	_perdre_blood()
	Player.sauvegarder()        # la mort est écrite : quitter ne l'efface pas
	velocity.x = 0.0            # FIX: stoppe le mouvement horizontal
	if _bouclier != null:
		_bouclier.tomber()      # le bouclier de sang meurt avec nous
	add_child(ECRAN_MORT_DEMO.new())   # DÉMO — écran de mort (se retire seul)



func dead_execute(delta: float) -> void:
	# FIX: gravité active pour que le corps tombe au sol
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
	# Le joueur est mort — aucun mouvement horizontal
	velocity.x = 0.0
	# TODO: ici tu pourras ajouter un timer pour afficher un écran de game over
	# ou relancer au checkpoint après X secondes / appui sur un bouton


func dead_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("jump"):
		print("okkkkkkkje suis mort")
		Player.hp = Player.MAX_HP
		Player.second_souffle_attente = 0.0     # nouvelle vie : le souffle est prêt
		Player.coeur_noir_attente = 0.0         # … et le cœur noir revient
		Player.essaim_en_vol = 0                # … et l'essaim est dispersé
		Player.vient_de_mourir = true           # … et le Sang neuf remplira la jauge
		Player.roues_brisees.clear()            # … et les roues à pointes brisées reviennent
		# au respawn, la jauge de sang offre EXACTEMENT un soin : le joker
		# du joueur, à dépenser au bon moment
		Player.bloodheal = HEAL_COST
		# respawn dans la scène du dernier checkpoint croisé (peut être une
		# autre scène que celle où on est mort)
		var scene_path: String = Loader._target_scene_path
		if Player.has_checkpoint and Player.last_checkpoint_scene != "":
			scene_path = Player.last_checkpoint_scene
		Loader.load_scene_with_loading(scene_path)

func dead_exit() -> void:
	velocity = Vector2.ZERO

# =====================  DROP (passer à travers one-way)  ===========================
#region DROP
const ONEWAY_LAYER := 2
const DROP_THROUGH_TIME := 0.25
var _drop_timer := 0.0
var _drop_airborne := false  # vrai dès qu'on a réellement quitté le sol

## Le sol sous les pieds est-il RÉELLEMENT traversable ? Un DROP n'a de sens
## que si, une fois la couche one-way ignorée, plus rien ne retient le perso.
## Un bloc qui a coché couche 1 ET couche 2 reste solide → pas de DROP
## (sinon : anim de chute sur place + particules d'atterrissage fantômes).
func _standing_on_oneway() -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = collision_normale.shape
	var xf := collision_normale.global_transform
	xf.origin.y += 6.0  # léger décalage vers le bas : ce qu'il y a sous les pieds
	params.transform = xf
	params.collision_mask = 1 << (ONEWAY_LAYER - 1)
	params.exclude = [get_rid()]
	# masque restant pendant le DROP : ce qui colle encore n'est pas traversable
	var mask_apres_drop: int = collision_mask & ~(1 << (ONEWAY_LAYER - 1))
	for hit in get_world_2d().direct_space_state.intersect_shape(params, 8):
		var body = hit.get("collider")
		if body is StaticBody2D and (body.collision_layer & mask_apres_drop) == 0:
			return true
	return false


func drop_enter() -> void:
	_drop_timer = DROP_THROUGH_TIME
	_drop_airborne = false
	set_collision_mask_value(ONEWAY_LAYER, false)
	animator.play("chute")
	velocity.y = 50.0

func drop_execute(delta: float) -> void:
	_drop_timer -= delta
	velocity.y = minf(velocity.y + gravity * GRAVITY_FALL * delta, MAX_FALL_SPEED)

	var direction := Input.get_axis("left_move", "right_move")
	if direction != 0:
		velocity.x = lerp(velocity.x, direction * AIR_SPEED, AIR_CONTROL)
		_flip_from_input()
	else:
		velocity.x = lerp(velocity.x, 0.0, DECELERATION_RATE * delta)

	if not is_on_floor():
		_drop_airborne = true

	if _drop_timer <= 0.0:
		change_state(States.CHUTE)
		return

	# n'atterrit (particules, sortie d'état) qu'après avoir vraiment décollé :
	# au 1er frame is_on_floor() date encore du tick où on était posé
	if is_on_floor() and _drop_airborne:
		_handle_landing()

func drop_exit() -> void:
	set_collision_mask_value(ONEWAY_LAYER, true)
#endregion


# =====================  CORDE (balancier)  ===========================
#region CORDE
## Corde suspendue (SCRIPT/INTERACTIBLE/corde.tscn). Quand le joueur la
## touche en l'air, la corde appelle saisir_corde() ; c'est le joueur qui
## accepte selon son état. Le balancier est un pendule rigide simulé par la
## corde, le joueur y pend par ANCRE_GRAB. Stick = on pompe en rythme,
## haut/bas = on grimpe/descend, saut = on se lâche avec l'élan (+ impulsion),
## esquive = on se laisse tomber. Toute accroche recharge double saut et dash.

const CORDE_COOLDOWN := 0.35             # s avant de pouvoir reprendre une corde
@export_group("Corde et grappin")
@export_subgroup("Corde")
## impulsion verticale ajoutée à l'élan quand on saute de la corde
@export var CORDE_SAUT_IMPULSION: float = -450.0
var _corde: Node2D = null
var _corde_cooldown := 0.0
var _corde_pending := false
var _corde_velocite_sortie := Vector2.ZERO
var _corde_est_pendule := false   # la « corde » est une accroche pendulaire (câble de grappin)


## Appelé par la corde qui touche le joueur. Retourne true s'il s'y accroche.
func saisir_corde(corde: Node2D) -> bool:
	if corde == null or _corde_cooldown > 0.0:
		return false
	if not (current_state in [States.JUMP, States.CHUTE, States.DASH, States.ATTACK_AIR]):
		return false
	_corde = corde
	change_state(States.CORDE)
	return true


## la main qui tient : ANCRE_GRAB sur une corde, l'ancre du grappin sur une
## accroche pendulaire (c'est de là que part le câble)
func _corde_ancre_main() -> Node2D:
	if _corde_est_pendule and ancre_grappin != null:
		return ancre_grappin
	return ancre_grab


func corde_enter() -> void:
	_recharge_air_moves()
	_corde_est_pendule = _corde.has_method("signaler_blocage")
	_corde.saisir(self, _corde_ancre_main().global_position, velocity)
	velocity = Vector2.ZERO
	if _corde_est_pendule and _anim_existe(ANIM_GRAPPIN_GRAB):
		animator.play(ANIM_GRAPPIN_GRAB)   # on tient le câble du grappin, pas une corde
	else:
		animator.play("suspendu")


func corde_execute(delta: float) -> void:
	if _corde == null or not is_instance_valid(_corde):
		change_state(States.CHUTE)
		return
	FALL_POINT = global_position.y   # appui légitime : suspendu
	var axe := Input.get_axis("left_move", "right_move")
	var grimpe := Input.get_axis("down_move", "up_move")
	var main: Vector2 = _corde.simuler_balancier(delta, axe, grimpe)
	# le perso pend par la main : le corps se place pour que ANCRE_GRAB soit sur la corde
	var ancre := _corde_ancre_main()
	var cible := main - (ancre.global_position - global_position)
	if _corde_est_pendule:
		# une accroche pendulaire se prend aussi depuis le sol ou près d'un mur :
		# déplacement AVEC collisions ; bloqué, le pendule repart de la position réelle
		var col := move_and_collide(cible - global_position)
		if col != null:
			_corde.signaler_blocage(ancre.global_position, col.get_normal(), delta)
		# câble tracé APRÈS le déplacement (sinon il part de la main du pas précédent)
		_corde.cable_montrer(ancre.global_position, _corde.point())
	else:
		global_position = cible   # corde classique : inchangé
	velocity = Vector2.ZERO
	# pas de retournement au gré du balancier (trop étrange) : le perso garde
	# le regard qu'il avait en attrapant la corde


func corde_input(_event: InputEvent) -> void:
	if _fresh_press("jump"):
		_corde_velocite_sortie = _corde.vitesse_main()
		_corde_velocite_sortie.y = minf(_corde_velocite_sortie.y, 0.0) + CORDE_SAUT_IMPULSION
		_corde_pending = true
		change_state(States.JUMP)
		return
	if Input.is_action_just_pressed("esquive"):
		velocity = _corde.vitesse_main()   # on se laisse tomber avec l'élan
		change_state(States.CHUTE)


func corde_exit() -> void:
	if _corde != null and is_instance_valid(_corde):
		_corde.lacher()
	if _corde_est_pendule:
		_grappin_cooldown = maxf(_grappin_cooldown, CORDE_COOLDOWN)
	_corde_est_pendule = false
	_corde = null
	_corde_cooldown = CORDE_COOLDOWN
#endregion


# =====================  GRAPPIN  ===========================
#region GRAPPIN
## Grappin (touche "grapin") vers une accroche (SCRIPT/INTERACTIBLE/
## accroche_grappin.tscn, groupe GRAPPIN). Pas de zone : comme Batman, Sekiro
## ou Ori, le joueur scanne chaque pas de physique les accroches à portée
## (GRAPPIN_PORTEE), au-dessus de lui (GRAPPIN_ANGLE_MAX depuis la verticale)
## et sans mur entre sa main et le point (rayon sur la couche 1) ; la plus
## proche prenable s'allume, R1 y envoie le grappin :
##   1) LANCER : le câble file de la main au point, le joueur est figé ;
##   2) TIRER  : le joueur est hissé d'un trait jusqu'au point (main dessus) ;
##   3) arrivé : catapulte au-dessus du point, grappin détaché, double saut
##      et dash rechargés. Aucune suspension. Un coup reçu interrompt tout
##      (le câble est caché par grappin_exit).

@export_subgroup("Grappin")
@export var GRAPPIN_ACCEL: float = 6520.0        ## force de traction MAX du câble (px/s²), la gravité (2500) tire contre — même traction nette qu'à 5000 sous 980
@export var GRAPPIN_VITESSE_MAX: float = 1600.0  ## vitesse plafond de la traction (px/s)
## durée minimale d'une traction (s) : une accroche toute proche est hissée
## aussi lentement qu'une lointaine — l'accélération est calculée pour ça
@export var GRAPPIN_DUREE_MIN: float = 0.4
## amortissement par seconde de l'élan perpendiculaire au câble (anti-orbite)
@export var GRAPPIN_AMORT_DERIVE: float = 10.0
var _grappin_accel := 0.0   # accélération effective de la traction en cours
@export var GRAPPIN_CABLE_DUREE: float = 0.08    ## temps de vol du câble (s)
@export var GRAPPIN_ELAN_Y: float = -1500.0      ## catapulte verticale à l'arrivée (saut normal = -700)
@export var GRAPPIN_ELAN_X: float = 250.0        ## élan horizontal, dans le sens de l'approche
@export var GRAPPIN_PORTEE: float = 520.0        ## distance max main → accroche (px) — +15 % le 16 sept.
@export var GRAPPIN_ANGLE_MAX: float = 75.0      ## écart max à la verticale, en degrés (l'accroche doit être au-dessus)
const GRAPPIN_COOLDOWN := 0.3
## animations (SpriteFrames du joueur), jouées si elles existent :
##   lancer   : "grappin_sol" les pieds au sol, "grappin_air" sinon
##   traction : "grappin_grab", la même au sol et en l'air
## Une anim de lancer de PLUSIEURS frames donne sa durée au vol du câble ;
## une pose d'une seule frame n'a pas de durée propre → GRAPPIN_CABLE_DUREE.
## Repli si l'anim manque : "jump".
const ANIM_GRAPPIN_SOL := "grappin_sol"
const ANIM_GRAPPIN_AIR := "grappin_air"
const ANIM_GRAPPIN_GRAB := "grappin_grab"
var _grappin_candidat: Node2D = null   # accroche prenable ce pas-ci (allumée)
var _grappin_duree_cable := 0.08       # durée effective du vol du câble (anim ou export)
## d'où part le câble : un Marker2D "ANCRE_GRAPPIN" sous POINT, à placer sur la
## main de l'anim de lancer (déplaçable dans l'éditeur) ; à défaut, l'ancre de grab
@onready var ancre_grappin: Node2D = get_node_or_null("POINT/ANCRE_GRAPPIN")


func _main_grappin() -> Vector2:
	if ancre_grappin != null:
		return ancre_grappin.global_position
	return ancre_grab.global_position
const ETATS_GRAPPIN_OK := [States.IDLE, States.RUN, States.JUMP, States.CHUTE, States.DASH, States.ATTACK_AIR]
var _grappin_cible: Node2D = null
var _grappin_cooldown := 0.0
var _grappin_t := 0.0
var _grappin_tire := false
var _grappin_dir := 1
var _grappin_pending := false
var _grappin_velocite := Vector2.ZERO

# PROPULSION IMPOSÉE (28 sept. 2026) : un passage vertical projette le joueur
# vers le haut quand il ARRIVE par le bas d'un tableau. Même mécanisme que la
# catapulte du grappin : vitesse donnée, gravité de lancer, et le bouton de
# saut n'y change rien — sinon un bouton relâché couperait la montée net.
var _propulsion_pending := false
var _propulsion_velocite := Vector2.ZERO


func propulser(vitesse: Vector2) -> void:
	if current_state == States.DEAD:
		return
	_propulsion_velocite = vitesse
	_propulsion_pending = true
	_recharge_air_moves()
	if current_state == States.JUMP:
		jump_enter()      # change_state refuse l'état courant : on rejoue l'entrée
	else:
		change_state(States.JUMP)


## Chaque pas de physique : quelle accroche est prenable ? À portée, au-dessus,
## et rien entre la main et le point. La plus proche s'allume, les autres
## s'éteignent. Quelques rayons par frame au plus : les accroches d'un niveau
## se comptent sur les doigts d'une main.
func _grappin_scanner() -> void:
	var meilleure: Node2D = null
	if current_state in ETATS_GRAPPIN_OK and _grappin_cooldown <= 0.0:
		var main := _main_grappin()
		var d_min := INF
		var espace := get_world_2d().direct_space_state
		var lim := deg_to_rad(GRAPPIN_ANGLE_MAX)
		for a in get_tree().get_nodes_in_group("GRAPPIN"):
			if not (a is Node2D and a.has_method("point")):
				continue
			var cible: Vector2 = a.point()
			var v := cible - main
			var d := v.length()
			if d > GRAPPIN_PORTEE or d < 20.0 or v.y > -10.0:
				continue                       # trop loin, trop près, ou pas au-dessus
			if absf(atan2(v.x, -v.y)) > lim:
				continue                       # trop sur le côté
			if d >= d_min:
				continue
			# rien entre la main et le point ? (murs solides seulement)
			var q := PhysicsRayQueryParameters2D.create(main, cible, 1)
			q.exclude = [get_rid()]
			if espace.intersect_ray(q).is_empty():
				d_min = d
				meilleure = a
	if meilleure != _grappin_candidat:
		if _grappin_candidat != null and is_instance_valid(_grappin_candidat):
			_grappin_candidat.surligner(false)
		_grappin_candidat = meilleure
		if _grappin_candidat != null:
			_grappin_candidat.surligner(true)


## Touche "grapin" : part vers l'accroche allumée. Retourne true si le grappin part.
func _try_grappin() -> bool:
	if _grappin_candidat == null or not is_instance_valid(_grappin_candidat):
		return false
	_grappin_cible = _grappin_candidat
	_grappin_candidat.surligner(false)
	_grappin_candidat = null
	change_state(States.GRAPPIN)
	return true


func grappin_enter() -> void:
	velocity.x = 0.0                 # on garde (un peu de) la chute en cours : le poids
	velocity.y = clampf(velocity.y, 0.0, 300.0)
	_recharge_air_moves()
	_grappin_t = 0.0
	_grappin_tire = false
	# on regarde vers le point ; l'élan final partira de ce côté
	var dx: float = _grappin_cible.point().x - global_position.x
	if absf(dx) > 8.0:
		_grappin_dir = 1 if dx > 0.0 else -1
	else:
		_grappin_dir = last_direction
	last_direction = _grappin_dir
	point.scale.x = _grappin_dir
	_grappin_duree_cable = maxf(GRAPPIN_CABLE_DUREE, 0.001)
	# lancer : l'anim "sol" les pieds par terre, l'anim "air" sinon
	var anim_lancer := ANIM_GRAPPIN_SOL if is_on_floor() else ANIM_GRAPPIN_AIR
	if _anim_existe(anim_lancer):
		animator.play(anim_lancer)
		# une vraie animation (plusieurs frames) donne sa durée au vol du câble ;
		# une pose d'une frame n'a pas de durée propre → l'export fait foi
		if animator.sprite_frames.get_frame_count(anim_lancer) > 1:
			_grappin_duree_cable = maxf(_anim_duree(anim_lancer), 0.001)
	else:
		animator.play("jump")


## l'animation existe-t-elle dans les SpriteFrames du joueur ?
func _anim_existe(nom: String) -> bool:
	return animator.sprite_frames != null and animator.sprite_frames.has_animation(nom)


## durée totale d'une animation (s), frames à durées variables comprises
func _anim_duree(nom: String) -> float:
	var sf = animator.sprite_frames
	if sf == null or not sf.has_animation(nom):
		return 0.0
	var fps := maxf(sf.get_animation_speed(nom), 0.001)
	var total := 0.0
	for i in sf.get_frame_count(nom):
		total += sf.get_frame_duration(nom, i) / fps
	return total


func grappin_execute(delta: float) -> void:
	if _grappin_cible == null or not is_instance_valid(_grappin_cible):
		change_state(States.CHUTE)
		return
	FALL_POINT = global_position.y
	var cible: Vector2 = _grappin_cible.point()
	var main := _main_grappin()
	if not _grappin_tire:
		# 1) le câble file vers le point ; le joueur, lui, continue de tomber :
		#    c'est son poids qu'on sent pendant ce court instant
		velocity.x = 0.0
		velocity.y += gravity * delta
		_grappin_t += delta
		var t := clampf(_grappin_t / _grappin_duree_cable, 0.0, 1.0)
		if t >= 1.0:
			if _grappin_cible.has_method("saisir"):
				# ACCROCHE PENDULAIRE (accroche_pendule.tscn, la bleue) : pas de traction,
				# on reste suspendu au câble et on joue comme à la corde — l'accroche
				# fournit l'API d'une corde, l'état CORDE fait le reste
				_corde = _grappin_cible
				change_state(States.CORDE)
				return
			_grappin_tire = true
			if _anim_existe(ANIM_GRAPPIN_GRAB):
				animator.play(ANIM_GRAPPIN_GRAB)
			# accélération taillée sur la distance : une traction courte doit
			# durer GRAPPIN_DUREE_MIN elle aussi (d = ½·a·t² → a = 2d/t²),
			# la gravité étant compensée, et jamais plus que GRAPPIN_ACCEL
			var d0 := (cible - main).length()
			var t_min := maxf(GRAPPIN_DUREE_MIN, 0.05)
			# + de quoi annuler la chute en cours dans le même temps
			var chute := maxf(velocity.y, 0.0)
			_grappin_accel = clampf(2.0 * d0 / (t_min * t_min) + gravity + chute / t_min,
				gravity * 1.5, GRAPPIN_ACCEL)
		return
	# 2) traction PHYSIQUE : le câble accélère la main vers le point pendant
	#    que la gravité tire vers le bas → léger affaissement au départ, puis
	#    montée qui prend de la vitesse (treuil qui hisse un corps). Le
	#    déplacement passe par move_and_slide : un mur arrête net.
	var dest := cible - (main - global_position)
	var vers := dest - global_position
	var dist := vers.length()
	if dist > 0.001:
		var u := vers / dist
		# l'élan HORS de l'axe du câble est amorti : sans ça, un élan latéral
		# fait rater le point de peu et on tourne autour comme un satellite
		var v_axe := velocity.dot(u)
		var v_perp := velocity - u * v_axe
		v_perp *= maxf(0.0, 1.0 - GRAPPIN_AMORT_DERIVE * delta)
		velocity = u * v_axe + v_perp
		velocity += u * _grappin_accel * delta
	velocity.y += gravity * delta
	velocity = velocity.limit_length(GRAPPIN_VITESSE_MAX)
	# arrivée : à portée d'un pas, main au niveau du point ou au-dessus (point
	# dépassé, on ne tourne JAMAIS autour), ou point dépassé de peu à l'approche
	# — jamais au départ : en l'air on tombe encore quelques frames
	var pas := velocity.length() * delta
	var a_portee := dist <= maxf(20.0, pas * 1.1)
	var depasse := main.y <= cible.y + 6.0 or (dist < pas * 2.0 and vers.dot(velocity) < 0.0)
	if a_portee or depasse:
		if a_portee:
			global_position = dest
		# 3) catapulte au-dessus du point ; jump_enter applique la vitesse
		_grappin_velocite = Vector2(_grappin_dir * GRAPPIN_ELAN_X, GRAPPIN_ELAN_Y)
		_grappin_pending = true
		change_state(States.JUMP)


## Trace le câble ; appelé par _physics_process APRÈS move_and_slide. Tracé dans
## grappin_execute, donc AVANT le déplacement du pas, il partait de la main du
## pas précédent : écart = vitesse / 60, mesuré 21 px à 1283 px/s → le bout du
## câble sortait du bras, de plus en plus à mesure que la traction accélère.
func _grappin_tracer_cable() -> void:
	if _grappin_cible == null or not is_instance_valid(_grappin_cible):
		return
	var main := _main_grappin()
	var cible: Vector2 = _grappin_cible.point()
	if _grappin_tire:
		_grappin_cible.cable_montrer(main, cible)
	else:
		# le câble file : sa pointe avance de la main vers le point
		var t := clampf(_grappin_t / _grappin_duree_cable, 0.0, 1.0)
		_grappin_cible.cable_montrer(main, main.lerp(cible, t))


func grappin_exit() -> void:
	if _grappin_cible != null and is_instance_valid(_grappin_cible):
		_grappin_cible.cable_cacher()
	_grappin_cible = null
	_grappin_cooldown = GRAPPIN_COOLDOWN
#endregion
