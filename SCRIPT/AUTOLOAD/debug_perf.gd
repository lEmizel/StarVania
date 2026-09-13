extends Node
## ============================================================================
## DEBUG PERF — overlay FPS / temps de frame + journal des pics en console.
##
## Toggle : F3 au clavier, bouton Share (bouton 4) à la manette. Caché au boot.
## Chaque frame plus longue que SEUIL_PIC_MS est journalisée avec sa
## répartition :
##   nœuds     = _process de tous les nœuds de la scène (scripts, tweens…)
##   physique  = pas de physique (_physics_process + moteur)
##   rendu CPU = préparation du rendu sur le CPU
##   GPU       = temps GPU réel de la frame précédente (0 si non mesurable)
##   attente   = le reste : attente du GPU / de l'écran / du pilote
##               (compilation de shader = gros pic ICI)
## plus la scène et l'état du joueur à cet instant. Le journal va aussi dans
## user://logs/godot.log (Mac : ~/Library/Application Support/Godot/
## app_userdata/SMILE_STAR/logs/).
##
## À RETIRER après la démo : supprimer ce fichier + la ligne DebugPerf dans
## les autoloads de project.godot.
## ============================================================================

const SEUIL_PIC_MS := 25.0          # 60 Hz = 16,7 ms par frame ; au-delà de 25 ms ça se voit
const INTERVALLE_AFFICHAGE := 0.5   # s entre deux rafraîchissements du texte

var _layer: CanvasLayer
var _label: Label
var _vp: RID
var _dernier_usec := 0
var _debut_noeuds_usec := 0
var _noeuds_ms := 0.0
var _cumul_ms := 0.0
var _nb_frames := 0
var _max_ms := 0.0
var _pics := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	get_tree().process_frame.connect(_fin_des_noeuds)

	_layer = CanvasLayer.new()
	_layer.layer = 150
	_layer.visible = false
	add_child(_layer)

	_label = Label.new()
	_label.position = Vector2(16.0, 16.0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_label)

	_dernier_usec = Time.get_ticks_usec()
	print("[PERF] écran %s | physique %d Hz | vsync %s | max_fps %d | fenêtre %s | %s" % [
		_hz(), Engine.physics_ticks_per_second, _vsync(), Engine.max_fps, _mode_fenetre(),
		RenderingServer.get_video_adapter_name()])


func _input(event: InputEvent) -> void:
	var toggle := false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		toggle = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK:
		toggle = true
	if toggle:
		_layer.visible = not _layer.visible
		if _layer.visible:
			_rafraichir()


# DebugPerf est le dernier autoload : son _process tourne juste avant ceux de la
# scène ; process_frame est émis quand tous les nœuds ont fini → durée "nœuds"
func _process(_delta: float) -> void:
	var maintenant := Time.get_ticks_usec()
	var ms := (maintenant - _dernier_usec) / 1000.0
	_dernier_usec = maintenant
	_debut_noeuds_usec = maintenant
	_cumul_ms += ms
	_nb_frames += 1
	_max_ms = maxf(_max_ms, ms)

	if ms > SEUIL_PIC_MS:
		_pics += 1
		var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var rendu_cpu := RenderingServer.viewport_get_measured_render_time_cpu(_vp)
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		print("[PERF] pic %.0f ms → nœuds %.1f | physique %.1f | rendu CPU %.1f | GPU %.1f | attente %.0f  (%s)" % [
			ms, _noeuds_ms, phys_ms, rendu_cpu, gpu,
			maxf(ms - _noeuds_ms - phys_ms - rendu_cpu, 0.0), _contexte()])

	if _cumul_ms >= INTERVALLE_AFFICHAGE * 1000.0:
		if _layer.visible:
			_rafraichir()
		_cumul_ms = 0.0
		_nb_frames = 0
		_max_ms = 0.0


func _fin_des_noeuds() -> void:
	_noeuds_ms = (Time.get_ticks_usec() - _debut_noeuds_usec) / 1000.0


func _rafraichir() -> void:
	var fps := 0.0
	if _cumul_ms > 0.0:
		fps = _nb_frames / (_cumul_ms / 1000.0)
	var moyenne := _cumul_ms / maxi(_nb_frames, 1)
	_label.text = "FPS %.0f  |  frame moy %.1f ms  max %.1f ms  |  pics > %d ms : %d\n" % [
			fps, moyenne, _max_ms, int(SEUIL_PIC_MS), _pics] \
		+ "nœuds %.1f ms  |  physique %.1f ms  |  rendu CPU %.1f ms  |  GPU %.1f ms\n" % [
			_noeuds_ms,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(_vp),
			RenderingServer.viewport_get_measured_render_time_gpu(_vp)] \
		+ "écran %s  |  physique %d Hz  |  vsync %s  |  fenêtre %s\n" % [
			_hz(), Engine.physics_ticks_per_second, _vsync(), _mode_fenetre()] \
		+ "VRAM %.0f Mo (textures %.0f Mo)  |  RAM statique %.0f Mo  |  draw calls %d  |  nœuds %d\n" % [
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6,
			OS.get_static_memory_usage() / 1e6,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))] \
		+ _contexte()


func _contexte() -> String:
	var scene := "?"
	var holder := get_tree().get_first_node_in_group("MAIN_SCENE")
	if holder != null and holder.get_child_count() > 0:
		scene = holder.get_child(holder.get_child_count() - 1).scene_file_path.get_file()
	var etat := "-"
	var joueur := get_tree().get_first_node_in_group("Player")
	if joueur != null and "current_state" in joueur:
		etat = str(joueur.States.keys()[joueur.current_state])
	return "scène %s | joueur %s" % [scene, etat]


func _hz() -> String:
	var hz := DisplayServer.screen_get_refresh_rate()
	return "%.0f Hz" % hz if hz > 0.0 else "? Hz"


func _vsync() -> String:
	match DisplayServer.window_get_vsync_mode():
		DisplayServer.VSYNC_DISABLED: return "désactivé"
		DisplayServer.VSYNC_ADAPTIVE: return "adaptatif"
		DisplayServer.VSYNC_MAILBOX: return "mailbox"
		_: return "activé"


func _mode_fenetre() -> String:
	match DisplayServer.window_get_mode():
		DisplayServer.WINDOW_MODE_FULLSCREEN: return "plein écran"
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: return "plein écran exclusif"
		DisplayServer.WINDOW_MODE_MAXIMIZED: return "maximisé"
		DisplayServer.WINDOW_MODE_MINIMIZED: return "minimisé"
		_: return "fenêtré"
