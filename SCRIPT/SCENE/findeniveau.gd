extends Area2D
## FIN DE DÉMO : quand le joueur entre dans la zone → fondu au noir, message
## de félicitations centré, puis START ramène au menu principal.
## Écran construit en code (CanvasLayer : insensible à la caméra).

const MENU_PRINCIPAL_SCENE := "uid://dm012xrdmag4v"  # SCRIPT/MENU/menu.tscn

## Durée du fondu au noir (s)
@export var duree_fondu := 1.2
## Textes (modifiables dans l'inspecteur)
@export_multiline var titre := "Congratulations!\nYou have completed our little demo."
@export var sous_titre := "Press START to return to the main menu"
@export var taille_titre := 72
@export var taille_sous_titre := 32
## Police optionnelle (sinon police par défaut du thème)
@export_file("*.ttf", "*.otf") var police := ""

var _declenche := false
var _pret_pour_start := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _declenche or not body.is_in_group("Player"):
		return
	_declenche = true
	_lancer_fin(body)


func _lancer_fin(joueur: Node) -> void:
	# le joueur sort du jeu : figé, et RETIRÉ du groupe "Player" pour que
	# l'autoload PauseMenu n'intercepte pas START (c'est cet écran qui le gère)
	joueur.remove_from_group("Player")
	joueur.process_mode = Node.PROCESS_MODE_DISABLED

	var layer := CanvasLayer.new()
	layer.layer = 200
	add_child(layer)

	# fondu au noir
	var fond := ColorRect.new()
	fond.color = Color(0.0, 0.0, 0.0, 0.0)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fond)

	# message principal, centré plein écran
	var lbl_titre := _make_label(titre, taille_titre)
	lbl_titre.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(lbl_titre)

	# sous-titre, un peu plus bas
	var lbl_sous := _make_label(sous_titre, taille_sous_titre)
	lbl_sous.anchor_left = 0.0
	lbl_sous.anchor_right = 1.0
	lbl_sous.anchor_top = 0.64
	lbl_sous.anchor_bottom = 0.74
	lbl_sous.offset_left = 0.0
	lbl_sous.offset_right = 0.0
	lbl_sous.offset_top = 0.0
	lbl_sous.offset_bottom = 0.0
	layer.add_child(lbl_sous)

	# séquence : noir → titre → sous-titre → START armé
	var t := create_tween()
	t.tween_property(fond, "color:a", 1.0, duree_fondu)
	t.tween_interval(0.3)
	t.tween_property(lbl_titre, "modulate:a", 1.0, 0.7)
	t.tween_interval(0.4)
	t.tween_property(lbl_sous, "modulate:a", 1.0, 0.5)
	t.tween_callback(func() -> void: _pret_pour_start = true)


func _make_label(texte: String, taille: int) -> Label:
	var lbl := Label.new()
	lbl.text = texte
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", taille)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	if police != "":
		var f := load(police)
		if f is Font:
			lbl.add_theme_font_override("font", f)
	lbl.modulate.a = 0.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _process(_delta: float) -> void:
	if _pret_pour_start and Input.is_action_just_pressed("start"):
		_pret_pour_start = false
		Loader.load_scene_with_loading(MENU_PRINCIPAL_SCENE)
