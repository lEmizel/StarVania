extends Control
## ============================================================================
## ONGLET TALISMANS du menu START.
##   • en haut, les emplacements où l'on ÉQUIPE (Player.EMPLACEMENTS_TALISMAN) ;
##   • dessous, la COLLECTION : un emplacement rond par talisman à découvrir
##     (le catalogue est dans SCRIPT/TALISMAN/talismans.gd).
##
## MANETTE : croix ou stick pour se déplacer, Croix pour équiper un talisman de
## la collection dans le premier emplacement libre, ou pour le retirer (depuis
## la collection comme depuis la rangée du haut).
##
## Les emplacements sont fabriqués ici à partir de emplacement_talisman.tscn ;
## ce qu'ils montrent est l'état de l'autoload Player, relu à chaque signal
## `talismans_changes`.
## ============================================================================

const Talismans := preload("res://SCRIPT/TALISMAN/talismans.gd")
const EMPLACEMENT := preload("res://SCRIPT/MENU/emplacement_talisman.tscn")

## diamètre des emplacements d'équipement (rangée du haut)
@export var diametre_equipement := 112.0
## diamètre des emplacements de la collection
@export var diametre_collection := 92.0
## (s'il y a plus d'emplacements que la fenêtre n'en contient à ces tailles, les
## ronds rétrécissent tout seuls pour tenir : voir _tenir_dans_la_fenetre)
## couleur du message de refus (plus d'emplacement libre)
@export var couleur_refus := Color(0.95, 0.32, 0.32)
## durée d'affichage du message de refus (s)
@export var duree_refus := 1.8

@onready var _colonne: VBoxContainer = $Colonne
@onready var _rangee: HBoxContainer = $Colonne/Equipements
@onready var _grille: GridContainer = $Colonne/Collection
@onready var _titre_collection: Label = $Colonne/TitreCollection
@onready var _nom: Label = $Colonne/Nom
@onready var _description: Label = $Colonne/Description

var _equipements: Array[Control] = []
var _collection: Array[Control] = []
var _pointe: Control = null         # l'emplacement qui a le focus
var _message: Tween = null          # le message de refus en cours d'affichage


func _ready() -> void:
	for i in Player.EMPLACEMENTS_TALISMAN:
		var e := _nouvel_emplacement(_rangee, "Equipement%d" % (i + 1), diametre_equipement)
		e.est_equipement = true
		_equipements.append(e)
	for i in Talismans.nb_emplacements():
		_collection.append(_nouvel_emplacement(_grille, "Emplacement%d" % (i + 1), diametre_collection))
	_tenir_dans_la_fenetre()
	_cabler_focus()
	Player.talismans_changes.connect(_rafraichir)
	_rafraichir()


func _nouvel_emplacement(parent: Node, nom: String, diametre: float) -> Control:
	var e: Control = EMPLACEMENT.instantiate()
	e.name = nom
	e.diametre = diametre
	e.valide.connect(_on_valide)
	e.pointe.connect(_on_pointe)
	parent.add_child(e)
	return e


## Plus d'emplacements que la fenêtre n'en contient à cette taille (on a monté
## Player.EMPLACEMENTS_TALISMAN, le nombre d'emplacements du catalogue ou les
## colonnes de la grille) : les ronds rétrécissent juste assez pour tenir, rien
## ne sort du cadre.
func _tenir_dans_la_fenetre() -> void:
	var place := _colonne.size
	if place.x <= 0.0 or place.y <= 0.0:
		return
	var trop := _rangee.get_combined_minimum_size().x - place.x
	if trop > 0.0:
		_retrecir(_equipements, trop / float(_equipements.size()))
	trop = _grille.get_combined_minimum_size().x - place.x
	if trop > 0.0:
		_retrecir(_collection, trop / float(mini(_grille.columns, _collection.size())))
	trop = _colonne.get_combined_minimum_size().y - place.y
	if trop > 0.0:
		var rangees := ceili(float(_collection.size()) / float(_grille.columns))
		_retrecir(_collection, trop / float(rangees))


func _retrecir(emplacements: Array[Control], de: float) -> void:
	for e in emplacements:
		e.diametre = maxf(e.diametre - ceilf(de), 24.0)


## appelé par le menu quand l'onglet s'ouvre : le focus revient là où il était,
## sinon sur le premier talisman de la collection qu'on peut équiper
func prendre_le_focus() -> void:
	if _pointe != null:
		_pointe.grab_focus()
		return
	for e in _collection:
		if e.a_un_talisman() and not e.porte:
			e.grab_focus()
			return
	_collection[0].grab_focus()


## relit l'état du joueur et le montre
func _rafraichir() -> void:
	for i in _equipements.size():
		var id: String = Player.talismans_equipes[i] if i < Player.talismans_equipes.size() else ""
		_equipements[i].montrer(Talismans.trouver(id), Talismans.numero(id), id != "", false)
	var trouves := 0
	for i in _collection.size():
		var ligne: Dictionary = Talismans.LISTE[i] if i < Talismans.LISTE.size() else {}
		var id := String(ligne.get("id", ""))
		var decouvert := Player.talisman_decouvert(id)
		if decouvert:
			trouves += 1
		_collection[i].montrer(ligne, i + 1, decouvert, Player.talisman_equipe(id))
	_titre_collection.text = "COLLECTION   %d / %d" % [trouves, _collection.size()]
	_decrire(_pointe)


# --------------------------------------------------------------------------
#  Équiper / retirer
# --------------------------------------------------------------------------

func _on_valide(e: Control) -> void:
	if not e.a_un_talisman():
		e.refuser()     # emplacement libre, ou talisman pas encore découvert
		return
	var id := String(e.talisman["id"])
	if Player.talisman_equipe(id):
		var liberee := Player.talismans_equipes.find(id)
		Player.retirer_talisman(id)
		_equipements[liberee].sauter()
		_collection[Talismans.numero(id) - 1].sauter()
		return
	var place := Player.equiper_talisman(id)
	if place == -1:
		# plus d'emplacement libre : toute la rangée du haut tremble
		for equipement in _equipements:
			equipement.refuser()
		_dire_refus("Aucun emplacement libre", "Retire d'abord un talisman équipé.")
		return
	_equipements[place].sauter()
	e.sauter()


# --------------------------------------------------------------------------
#  Le texte sous la grille : nom et description de l'emplacement pointé
# --------------------------------------------------------------------------

func _on_pointe(e: Control) -> void:
	_pointe = e
	_decrire(e)


func _decrire(e: Control) -> void:
	if _message != null and _message.is_valid():
		_message.kill()
	_nom.remove_theme_color_override("font_color")
	if e == null:
		_nom.text = ""
		_description.text = ""
	elif e.a_un_talisman():
		_nom.text = String(e.talisman["nom"]) + ("   (équipé)" if e.porte else "")
		_description.text = String(e.talisman.get("description", ""))
	elif e.est_equipement:
		_nom.text = "Emplacement libre"
		_description.text = "Choisis un talisman dans la collection pour l'équiper."
	else:
		_nom.text = "???"
		_description.text = "Talisman pas encore découvert."


## message de refus, en rouge, qui laisse ensuite revenir la description
func _dire_refus(titre: String, texte: String) -> void:
	_decrire(null)
	_nom.add_theme_color_override("font_color", couleur_refus)
	_nom.text = titre
	_description.text = texte
	_message = create_tween()
	_message.tween_interval(duree_refus)
	_message.tween_callback(func() -> void: _decrire(_pointe))


# --------------------------------------------------------------------------
#  Navigation à la manette : chaque emplacement connaît ses quatre voisins.
#  (La recherche géométrique de Godot saute parfois une rangée ; ici un bord
#  est un bord : on n'en sort pas par le côté.)
# --------------------------------------------------------------------------

func _cabler_focus() -> void:
	var colonnes := _grille.columns
	var n := _collection.size()
	var ne := _equipements.size()
	# les deux rangées sont centrées l'une sous l'autre : pas entre deux ronds
	var pas_equipement: float = _rangee.get_theme_constant("separation")
	if ne > 0:
		pas_equipement += _equipements[0].diametre
	var pas_collection: float = _grille.get_theme_constant("h_separation") + _collection[0].diametre
	var premiere_rangee := mini(colonnes, n)
	for i in n:
		var colonne := i % colonnes
		var gauche := i - 1 if colonne > 0 else i
		var droite := i + 1 if colonne < colonnes - 1 and i + 1 < n else i
		var bas := i + colonnes if i + colonnes < n else i
		var haut: Control = _collection[i]      # pas de rangée au-dessus : on reste
		if i >= colonnes:
			haut = _collection[i - colonnes]
		elif ne > 0:
			haut = _equipements[_au_plus_pres(colonne, premiere_rangee, pas_collection, ne, pas_equipement)]
		_voisins(_collection[i], _collection[gauche], _collection[droite], haut, _collection[bas])
	for j in ne:
		var dessous := _au_plus_pres(j, ne, pas_equipement, premiere_rangee, pas_collection)
		_voisins(_equipements[j], _equipements[maxi(j - 1, 0)], _equipements[mini(j + 1, ne - 1)],
			_equipements[j], _collection[dessous])


## Deux rangées centrées l'une sous l'autre : le rond de la rangée d'arrivée
## (`n_vers` ronds espacés de `pas_vers`) le plus proche, à l'horizontale, du
## rond n°`i` de la rangée de départ (`n_depuis` ronds espacés de `pas_depuis`).
func _au_plus_pres(i: int, n_depuis: int, pas_depuis: float, n_vers: int, pas_vers: float) -> int:
	var x := (float(i) - float(n_depuis - 1) * 0.5) * pas_depuis
	var meilleur := 0
	var ecart := INF
	for k in n_vers:
		var e := absf((float(k) - float(n_vers - 1) * 0.5) * pas_vers - x)
		if e < ecart:
			ecart = e
			meilleur = k
	return meilleur


func _voisins(e: Control, gauche: Control, droite: Control, haut: Control, bas: Control) -> void:
	e.focus_neighbor_left = e.get_path_to(gauche)
	e.focus_neighbor_right = e.get_path_to(droite)
	e.focus_neighbor_top = e.get_path_to(haut)
	e.focus_neighbor_bottom = e.get_path_to(bas)
