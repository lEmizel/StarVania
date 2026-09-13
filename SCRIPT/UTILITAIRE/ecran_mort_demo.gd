extends CanvasLayer
## ============================================================================
## DÉMO UNIQUEMENT — écran de mort : voile sombre progressif + "Press X to
## revive". Construit en code, aucune scène à maintenir.
##
## Ajouté en ENFANT du joueur par player.gd (dead_enter) : un CanvasLayer
## ignore la position de son parent et de la caméra. Il se retire TOUT SEUL
## dès que le joueur quitte l'état DEAD (respawn), et part avec lui s'il est
## libéré. Rien à nettoyer côté player.
##
## POUR LE RETIRER APRÈS LA DÉMO :
##   1. supprimer ce fichier ;
##   2. dans SCRIPT/CHARACHTER/player.gd, effacer le bloc "DÉMO : écran de mort"
##      (la constante ECRAN_MORT_DEMO et la ligne marquée DÉMO de dead_enter).
## ============================================================================

const LAYER := 90                 # sous le menu pause (couche 100)
const OPACITE_VOILE := 0.65       # 1.0 = noir complet
const DUREE_VOILE := 1.0          # s — assombrissement progressif
const DELAI_MESSAGE := 0.4        # s — pause avant l'apparition du texte
const DUREE_MESSAGE := 0.5        # s — fondu d'entrée du texte
const TEXTE := "Press X to revive"
const TAILLE_TEXTE := 40


func _ready() -> void:
	layer = LAYER

	# voile sombre plein écran
	var voile := ColorRect.new()
	voile.color = Color(0.0, 0.0, 0.0, 0.0)
	voile.set_anchors_preset(Control.PRESET_FULL_RECT)
	voile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(voile)

	# message, sous le centre de l'écran (le corps du joueur reste lisible)
	var lbl := Label.new()
	lbl.text = TEXTE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", TAILLE_TEXTE)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.62
	lbl.anchor_bottom = 0.72
	lbl.offset_left = 0.0
	lbl.offset_right = 0.0
	lbl.offset_top = 0.0
	lbl.offset_bottom = 0.0
	lbl.modulate.a = 0.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)

	# séquence : voile → pause → texte → pulsation douce en boucle
	var t := create_tween()
	t.tween_property(voile, "color:a", OPACITE_VOILE, DUREE_VOILE)
	t.tween_interval(DELAI_MESSAGE)
	t.tween_property(lbl, "modulate:a", 1.0, DUREE_MESSAGE)
	t.tween_callback(_pulser.bind(lbl))


func _process(_delta: float) -> void:
	# auto-nettoyage : le joueur (parent) n'est plus mort → l'écran disparaît
	var joueur := get_parent()
	if joueur == null or joueur.current_state != joueur.States.DEAD:
		queue_free()


func _pulser(lbl: Label) -> void:
	var p := create_tween().set_loops()
	p.tween_property(lbl, "modulate:a", 0.55, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	p.tween_property(lbl, "modulate:a", 1.0, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
