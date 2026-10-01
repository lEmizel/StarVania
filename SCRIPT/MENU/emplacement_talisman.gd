extends Control
## ============================================================================
## EMPLACEMENT ROND DE TALISMAN (menu START, onglet Talismans).
## Le même rond sert deux fois :
##   • dans la COLLECTION : l'emplacement d'un talisman à découvrir ;
##   • dans la rangée du haut : un emplacement où l'on en ÉQUIPE un.
## C'est la page (page_talismans.gd) qui lui dit quoi montrer, avec `montrer()`.
##
## Le socle, le focus et les ronds de couleur sont DESSINÉS EN CODE (`_draw`) :
## couleurs et épaisseurs se règlent dans l'inspecteur, sur
## emplacement_talisman.tscn. Un talisman du catalogue peut avoir mieux qu'un
## rond de couleur :
##   • un "dessin" : un shader qui le dessine et peut l'animer. Il reçoit de
##     cet emplacement `opacite`, `eveil` (pointé ou porté) et `temps` ;
##   • sinon une "icone" : une image.
## ============================================================================

const Talismans := preload("res://SCRIPT/TALISMAN/talismans.gd")

signal valide(emplacement: Control)     # Croix, Entrée ou clic
signal pointe(emplacement: Control)     # vient de prendre le focus

@export var diametre := 92.0:
	set(v):
		diametre = v
		custom_minimum_size = Vector2(v, v)
		_placer_dessin()
		queue_redraw()

@export_group("Le socle")
@export var couleur_socle := Color(0.035, 0.028, 0.045)
@export var couleur_bord := Color(0.36, 0.31, 0.32)
## le bord d'un emplacement d'ÉQUIPEMENT (rangée du haut)
@export var couleur_bord_equipement := Color(0.56, 0.13, 0.17)
@export var epaisseur_bord := 3.0
## le « ? » d'un talisman pas encore découvert
@export var couleur_inconnu := Color(0.27, 0.24, 0.26)

@export_group("Le focus")
@export var couleur_focus := Color(0.97, 0.93, 0.85)
@export var epaisseur_focus := 4.0
## distance entre le bord du rond et l'anneau de focus
@export var ecart_focus := 7.0

@export_group("Le talisman")
## part du diamètre occupée par le talisman (1 = tout le rond : Kaoru ne veut
## pas d'anneau gris autour des icônes, 30 sept. 2026)
@export_range(0.4, 1.0, 0.01) var taille_talisman := 1.0
## opacité d'un talisman de la collection pendant qu'il est porté : il reste
## visible à sa place, éteint
@export_range(0.0, 1.0, 0.01) var opacite_porte := 0.28
## la pastille qui marque, dans la collection, un talisman porté
@export var couleur_pastille := Color(0.86, 0.17, 0.2)
## un talisman qui a un "dessin" vit : son temps passe tant de fois plus vite
## quand il est pointé ou porté
@export var acceleration_eveil := 4.0

var talisman := {}              # la ligne du catalogue, {} = rien ici
var numero := 0                 # écrit sur le rond tant qu'il n'a pas de dessin
var decouvert := false
var porte := false              # (collection) ce talisman est équipé
var est_equipement := false     # true = un emplacement de la rangée du haut
## (lu par la page) le focus vient d'arriver au survol de la souris
var pointe_a_la_souris := false

var _icone: Texture2D = null
var _dessin: ColorRect = null   # le rectangle qui porte le shader du talisman, s'il en a un
var _vie := 0.0                 # le temps propre de ce dessin
var _eveil := 0.0
var _t := 0.0
var _animation: Tween = null
# le dessin est animé, pas le nœud : un conteneur remet l'échelle et la position
# de ses enfants à zéro chaque fois qu'il les range
var echelle_dessin := 1.0:
	set(v):
		echelle_dessin = v
		_placer_dessin()
		queue_redraw()
var decalage_dessin := 0.0:
	set(v):
		decalage_dessin = v
		_placer_dessin()
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(diametre, diametre)
	focus_mode = Control.FOCUS_ALL
	# la molette passe à la liste qui défile (le clic, lui, est gardé ici)
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(false)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	mouse_entered.connect(_on_mouse_entered)
	resized.connect(_placer_dessin)


func _on_mouse_entered() -> void:
	pointe_a_la_souris = true
	grab_focus()
	pointe_a_la_souris = false


## Ce que l'emplacement montre. `ligne` = la ligne du catalogue ({} = aucun
## talisman), `num` = le numéro écrit sur le rond tant qu'il n'a pas de dessin.
func montrer(ligne: Dictionary, num: int, est_decouvert: bool, est_porte: bool) -> void:
	talisman = ligne
	numero = num
	decouvert = est_decouvert and not ligne.is_empty()
	porte = est_porte
	_icone = Talismans.icone(ligne) if decouvert else null
	_poser_dessin(Talismans.dessin(ligne) if decouvert else null)
	queue_redraw()


## true si l'emplacement montre un talisman qu'on peut prendre ou retirer
func a_un_talisman() -> bool:
	return decouvert and not talisman.is_empty()


func valider() -> void:
	valide.emit(self)


## petit rebond : quelque chose vient de se poser ici, ou d'en partir
func sauter() -> void:
	_couper_animation()
	echelle_dessin = 1.22
	_animation = create_tween()
	_animation.tween_property(self, "echelle_dessin", 1.0, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## refus : le rond tremble de gauche à droite
func refuser() -> void:
	_couper_animation()
	_animation = create_tween()
	var amplitude := 7.0
	for i in 3:
		_animation.tween_property(self, "decalage_dessin", amplitude, 0.04)
		_animation.tween_property(self, "decalage_dessin", -amplitude, 0.04)
		amplitude *= 0.55
	_animation.tween_property(self, "decalage_dessin", 0.0, 0.04)


func _couper_animation() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	echelle_dessin = 1.0
	decalage_dessin = 0.0


func _on_focus_entered() -> void:
	_t = 0.0
	_regler_process()
	queue_redraw()
	pointe.emit(self)


func _on_focus_exited() -> void:
	_regler_process()
	queue_redraw()


## l'emplacement ne tourne que s'il a quelque chose à animer : l'anneau de focus
## qui respire, ou un talisman dessiné par un shader
func _regler_process() -> void:
	set_process(has_focus() or _a_un_dessin())


func _process(delta: float) -> void:
	if has_focus():
		_t += delta
		queue_redraw()
	if _a_un_dessin():
		_animer_dessin(delta)


# --------------------------------------------------------------------------
#  Le talisman dessiné par un shader ("dessin" dans le catalogue)
# --------------------------------------------------------------------------

func _a_un_dessin() -> bool:
	return _dessin != null and _dessin.visible


## installe (ou retire) le shader du talisman montré
func _poser_dessin(shader: Shader) -> void:
	if shader == null:
		if _dessin != null:
			_dessin.visible = false
	else:
		if _dessin == null:
			_dessin = ColorRect.new()
			_dessin.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# derrière ce que dessine l'emplacement lui-même (pastille « porté »,
			# anneau de focus) : le dessin remplit le rond, tout le reste passe dessus
			_dessin.show_behind_parent = true
			_dessin.material = ShaderMaterial.new()
			add_child(_dessin)
		(_dessin.material as ShaderMaterial).shader = shader
		_dessin.visible = true
		_placer_dessin()
		_animer_dessin(0.0)
	_regler_process()


## le rectangle du dessin suit le rond : même centre, même rebond, même
## tremblement que ce qui est dessiné en code
func _placer_dessin() -> void:
	if _dessin == null:
		return
	var rt := diametre * 0.5 * taille_talisman
	_dessin.size = Vector2(rt, rt) * 2.0
	_dessin.pivot_offset = Vector2(rt, rt)
	_dessin.position = size * 0.5 - Vector2(rt, rt) + Vector2(decalage_dessin, 0.0)
	_dessin.scale = Vector2.ONE * echelle_dessin


## fait vivre le dessin : il s'éveille quand l'emplacement est pointé ou que
## c'est un emplacement d'équipement, et son temps s'accélère d'autant
func _animer_dessin(delta: float) -> void:
	var cible := 1.0 if (has_focus() or est_equipement) and not porte else 0.0
	_eveil = move_toward(_eveil, cible, delta * 5.0)
	_vie += delta * lerpf(1.0, acceleration_eveil, _eveil)
	var mat := _dessin.material as ShaderMaterial
	mat.set_shader_parameter("temps", _vie)
	mat.set_shader_parameter("eveil", _eveil)
	mat.set_shader_parameter("opacite", opacite_porte if porte else 1.0)


func _gui_input(event: InputEvent) -> void:
	var clic := event as InputEventMouseButton
	if clic != null and clic.pressed and clic.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		valider()
		accept_event()


func _draw() -> void:
	var r := diametre * 0.5
	# tout se dessine autour de (0, 0), posé au centre de l'emplacement
	draw_set_transform(size * 0.5 + Vector2(decalage_dessin, 0.0), 0.0, Vector2.ONE * echelle_dessin)

	# le socle et son bord : seulement si le talisman ne remplit pas déjà le
	# rond (un dessin ou une icône l'occupe en entier, sans anneau autour)
	var rempli := a_un_talisman() and (_a_un_dessin() or _icone != null) and taille_talisman >= 0.999
	if not rempli:
		draw_circle(Vector2.ZERO, r, couleur_socle, true, -1.0, true)
		var bord := couleur_bord_equipement if est_equipement else couleur_bord
		draw_arc(Vector2.ZERO, r - epaisseur_bord * 0.5, 0.0, TAU, 72, bord, epaisseur_bord, true)

	if a_un_talisman():
		if not _a_un_dessin():
			_dessiner_talisman(opacite_porte if porte else 1.0)
		if porte:
			var p := Vector2(r, -r) * 0.66
			draw_circle(p, 8.5, couleur_socle, true, -1.0, true)
			draw_circle(p, 6.0, couleur_pastille, true, -1.0, true)
	elif not est_equipement:
		_ecrire("?", int(r * 0.78), couleur_inconnu)

	if has_focus():
		var souffle := 0.8 + 0.2 * cos(_t * 5.0)
		draw_arc(Vector2.ZERO, r + ecart_focus, 0.0, TAU, 72,
			Color(couleur_focus, souffle), epaisseur_focus, true)


func _dessiner_talisman(opacite: float) -> void:
	var rt := diametre * 0.5 * taille_talisman
	if _icone != null:
		draw_texture_rect(_icone, Rect2(Vector2(-rt, -rt), Vector2(rt, rt) * 2.0), false,
			Color(1.0, 1.0, 1.0, opacite))
		return
	# pas encore de dessin : un médaillon de sa couleur, avec son numéro
	var teinte: Color = talisman.get("couleur", Color(0.5, 0.5, 0.5))
	draw_circle(Vector2.ZERO, rt, Color(teinte, opacite), true, -1.0, true)
	draw_arc(Vector2.ZERO, rt - 1.5, 0.0, TAU, 64, Color(teinte.darkened(0.5), opacite), 3.0, true)
	draw_arc(Vector2.ZERO, rt * 0.72, deg_to_rad(-165.0), deg_to_rad(-75.0), 24,
		Color(teinte.lightened(0.45), opacite * 0.9), 3.0, true)
	_ecrire(str(numero), int(rt * 0.95), Color(teinte.darkened(0.62), opacite))


## écrit un texte centré sur l'emplacement
func _ecrire(texte: String, taille: int, couleur: Color) -> void:
	var police := get_theme_default_font()
	var hauteur := police.get_ascent(taille) - police.get_descent(taille)
	draw_string(police, Vector2(-diametre * 0.5, hauteur * 0.5), texte,
		HORIZONTAL_ALIGNMENT_CENTER, diametre, taille, couleur)
