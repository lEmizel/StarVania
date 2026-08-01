@tool
extends VBoxContainer
## Tiroir d'assets : affiche les scènes/images d'un dossier sous forme de
## vignettes, glissables directement dans la scène (même mécanisme de drag
## que le dock FileSystem → déposer une .tscn l'instancie, une image crée
## un Sprite2D).
##
## Les vignettes de scènes sont rendues par le plugin lui-même : la scène est
## instanciée hors-écran dans un SubViewport, cadrée sur son contenu visuel,
## puis capturée — bien plus lisible que les aperçus par défaut de l'éditeur.

## Émis quand un asset du tiroir vient d'être déposé avec succès dans
## l'éditeur (le plugin s'en sert pour aimanter le nœud fraîchement créé)
signal asset_dropped

## Nœud parent cible : tout asset déposé depuis le tiroir devient son enfant.
## Défini en glissant un nœud de l'arbre de scène sur la case "Parent :",
## ou via le bouton sélection. Null = comportement par défaut (racine).
var target_parent: Node = null

const CONFIG_PATH := "res://addons/asset_drawer/folders.cfg"
const IMAGE_EXTENSIONS := ["png", "webp", "svg", "jpg", "jpeg"]
const SCENE_EXTENSIONS := ["tscn", "scn"]
const THUMB_RENDER_SIZE := 128  # résolution de rendu des vignettes de scènes

var _folders: PackedStringArray = []
var _thumb_size := 80.0
var _folder_select: OptionButton
var _filter: LineEdit
var _grid: HFlowContainer
var _empty_label: Label
var _add_dialog: EditorFileDialog
var _target_btn: Button

# rendu des vignettes de scènes
var _thumb_viewport: SubViewport
var _thumb_holder: Node2D
var _thumb_queue: Array = []            # paires [path, DrawerItem]
var _thumb_busy := false
var _thumb_cache: Dictionary = {}       # path -> Texture2D (par session)


func _init() -> void:
	custom_minimum_size = Vector2(220, 0)
	_load_config()  # avant _build_ui : la réglette de zoom lit _thumb_size
	_build_ui()
	_refresh_folder_options()
	call_deferred("_populate")


# ------------------------------------------------------------------
#  UI
# ------------------------------------------------------------------

func _build_ui() -> void:
	# --- Case "Parent cible" : les assets déposés deviennent ses enfants ---
	var target_row := HBoxContainer.new()
	add_child(target_row)

	var target_label := Label.new()
	target_label.text = "Parent :"
	target_row.add_child(target_label)

	_target_btn = TargetDropButton.new()
	_target_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target_btn.clip_text = true
	_target_btn.tooltip_text = "Glisse ici un nœud depuis l'arbre de scène :\nles assets déposés depuis le tiroir deviendront ses enfants.\nClic : re-sélectionne le nœud cible dans l'arbre."
	_target_btn.node_dropped.connect(set_target_parent)
	_target_btn.pressed.connect(_on_target_btn_pressed)
	target_row.add_child(_target_btn)

	var target_pick := Button.new()
	target_pick.text = "◎"
	target_pick.tooltip_text = "Utiliser le nœud actuellement sélectionné comme parent cible"
	target_pick.pressed.connect(_on_target_pick_pressed)
	target_row.add_child(target_pick)

	var target_clear := Button.new()
	target_clear.text = "✕"
	target_clear.tooltip_text = "Effacer la cible (dépôt à la racine, comportement par défaut)"
	target_clear.pressed.connect(func() -> void: set_target_parent(null))
	target_row.add_child(target_clear)

	_update_target_button()

	var top := HBoxContainer.new()
	add_child(top)

	_folder_select = OptionButton.new()
	_folder_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_folder_select.clip_text = true
	_folder_select.item_selected.connect(func(_i: int) -> void: _populate())
	top.add_child(_folder_select)

	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.tooltip_text = "Ajouter un dossier au tiroir"
	add_btn.pressed.connect(_on_add_folder_pressed)
	top.add_child(add_btn)

	var remove_btn := Button.new()
	remove_btn.text = "−"
	remove_btn.tooltip_text = "Retirer le dossier courant du tiroir"
	remove_btn.pressed.connect(_on_remove_folder_pressed)
	top.add_child(remove_btn)

	var refresh_btn := Button.new()
	refresh_btn.text = "↻"
	refresh_btn.tooltip_text = "Rafraîchir (re-rend aussi les vignettes)"
	refresh_btn.pressed.connect(func() -> void:
		_thumb_cache.clear()
		_populate())
	top.add_child(refresh_btn)

	_filter = LineEdit.new()
	_filter.placeholder_text = "Filtrer…"
	_filter.clear_button_enabled = true
	_filter.text_changed.connect(func(_t: String) -> void: _populate())
	add_child(_filter)

	# Réglette de zoom des vignettes
	var zoom := HSlider.new()
	zoom.min_value = 48.0
	zoom.max_value = 160.0
	zoom.step = 8.0
	zoom.value = _thumb_size
	zoom.tooltip_text = "Taille des vignettes"
	zoom.value_changed.connect(_on_thumb_size_changed)
	add_child(zoom)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_empty_label = Label.new()
	_empty_label.text = "Ajoute un dossier avec le bouton +"
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_empty_label)


# ------------------------------------------------------------------
#  PARENT CIBLE
# ------------------------------------------------------------------

func set_target_parent(n: Node) -> void:
	target_parent = n
	_update_target_button()


func _update_target_button() -> void:
	if target_parent != null and is_instance_valid(target_parent):
		_target_btn.text = target_parent.name
	else:
		target_parent = null
		_target_btn.text = "(racine)"


func _on_target_pick_pressed() -> void:
	var sel := EditorInterface.get_selection().get_selected_nodes()
	if sel.size() == 1:
		set_target_parent(sel[0])


func _on_target_btn_pressed() -> void:
	if target_parent != null and is_instance_valid(target_parent):
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(target_parent)


## Bouton qui accepte le drag de nœuds depuis l'arbre de scène de l'éditeur
class TargetDropButton extends Button:
	signal node_dropped(node: Node)

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("type", "") == "nodes"

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		var paths: Array = data.get("nodes", [])
		if paths.is_empty():
			return
		var n := get_node_or_null(paths[0])
		if n != null:
			node_dropped.emit(n)


func _on_add_folder_pressed() -> void:
	if _add_dialog == null:
		_add_dialog = EditorFileDialog.new()
		_add_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
		_add_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_add_dialog.dir_selected.connect(_on_folder_chosen)
		add_child(_add_dialog)
	_add_dialog.popup_centered_ratio(0.5)


func _on_folder_chosen(dir: String) -> void:
	if dir in _folders:
		return
	_folders.append(dir)
	_save_config()
	_refresh_folder_options()
	_folder_select.select(_folders.size() - 1)
	_populate()


func _on_remove_folder_pressed() -> void:
	var idx := _folder_select.selected
	if idx < 0 or idx >= _folders.size():
		return
	_folders.remove_at(idx)
	_save_config()
	_refresh_folder_options()
	_populate()


func _refresh_folder_options() -> void:
	_folder_select.clear()
	for f in _folders:
		_folder_select.add_item(f.trim_prefix("res://"))
	if _folders.size() > 0:
		_folder_select.select(0)


# ------------------------------------------------------------------
#  CONFIG (liste des dossiers, persistée dans l'addon)
# ------------------------------------------------------------------

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		_folders = cfg.get_value("drawer", "folders", PackedStringArray())
		_thumb_size = cfg.get_value("drawer", "thumb_size", 80.0)


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("drawer", "folders", _folders)
	cfg.set_value("drawer", "thumb_size", _thumb_size)
	cfg.save(CONFIG_PATH)


func _on_thumb_size_changed(value: float) -> void:
	_thumb_size = value
	_save_config()
	# redimensionne les vignettes existantes sans tout reconstruire
	for child in _grid.get_children():
		if child is DrawerItem:
			child.set_display_size(value)


# ------------------------------------------------------------------
#  CONTENU
# ------------------------------------------------------------------

func _populate() -> void:
	_thumb_queue.clear()
	for child in _grid.get_children():
		child.queue_free()

	var idx := _folder_select.selected
	var has_folder := idx >= 0 and idx < _folders.size()
	_empty_label.visible = not has_folder
	if not has_folder:
		return

	var paths: Array[String] = []
	_scan_dir(_folders[idx], paths)
	paths.sort()

	var filter_text := _filter.text.strip_edges().to_lower()

	for path in paths:
		if filter_text != "" and not path.get_file().to_lower().contains(filter_text):
			continue
		var item := DrawerItem.new(path)
		item.dropped.connect(func() -> void: asset_dropped.emit())
		item.set_display_size(_thumb_size)
		_grid.add_child(item)

		var ext := path.get_extension().to_lower()
		if ext in IMAGE_EXTENSIONS:
			# image : la texture elle-même est la meilleure vignette possible
			var tex: Texture2D = load(path)
			if tex != null:
				item.set_preview(tex)
		else:
			# scène : icône générique en attendant le rendu maison
			item.set_preview(get_theme_icon("PackedScene", "EditorIcons"))
			if _thumb_cache.has(path):
				item.set_preview(_thumb_cache[path])
			else:
				_thumb_queue.append([path, item])

	_process_thumb_queue()


func _scan_dir(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir():
			if not f.begins_with("."):
				_scan_dir(path.path_join(f), out)
		elif f.get_extension().to_lower() in IMAGE_EXTENSIONS + SCENE_EXTENSIONS:
			out.append(path.path_join(f))
		f = dir.get_next()
	dir.list_dir_end()


# ------------------------------------------------------------------
#  VIGNETTES DE SCÈNES — rendu hors-écran, cadré sur le contenu
# ------------------------------------------------------------------

func _ensure_thumb_viewport() -> void:
	if _thumb_viewport != null:
		return
	_thumb_viewport = SubViewport.new()
	_thumb_viewport.size = Vector2i(THUMB_RENDER_SIZE, THUMB_RENDER_SIZE)
	_thumb_viewport.transparent_bg = true
	_thumb_viewport.disable_3d = true
	_thumb_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_thumb_holder = Node2D.new()
	_thumb_viewport.add_child(_thumb_holder)
	add_child(_thumb_viewport)


func _process_thumb_queue() -> void:
	if _thumb_busy:
		return
	_thumb_busy = true
	while not _thumb_queue.is_empty():
		var entry: Array = _thumb_queue.pop_front()
		if is_instance_valid(entry[1]):
			await _render_scene_thumb(entry[0], entry[1])
	_thumb_busy = false


func _render_scene_thumb(path: String, item: DrawerItem) -> void:
	_ensure_thumb_viewport()
	var packed: PackedScene = load(path)
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	if not (inst is Node2D or inst is Control):
		inst.free()
		return

	_thumb_holder.scale = Vector2.ONE
	_thumb_holder.position = Vector2.ZERO
	_thumb_holder.add_child(inst)

	# cadre sur le contenu visuel réel (sprites, polygones, collisions)
	var rect := _visual_rect(inst)
	if not rect.has_area():
		rect = Rect2(-32, -32, 64, 64)
	var s: float = (THUMB_RENDER_SIZE - 8.0) / maxf(rect.size.x, rect.size.y)
	_thumb_holder.scale = Vector2(s, s)
	_thumb_holder.position = Vector2(THUMB_RENDER_SIZE, THUMB_RENDER_SIZE) * 0.5 - rect.get_center() * s

	_thumb_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	var img := _thumb_viewport.get_texture().get_image()
	inst.queue_free()
	if img == null:
		return
	var tex := ImageTexture.create_from_image(img)
	_thumb_cache[path] = tex
	if is_instance_valid(item):
		item.set_preview(tex)


## Rect englobant du contenu visible d'une scène instanciée dans le viewport
func _visual_rect(n: Node) -> Rect2:
	var acc: Array[Rect2] = []
	_accumulate_visual_rects(n, acc)
	if acc.is_empty():
		return Rect2()
	var result: Rect2 = acc[0]
	for i in range(1, acc.size()):
		result = result.merge(acc[i])
	return result


func _accumulate_visual_rects(n: Node, acc: Array[Rect2]) -> void:
	if n is CanvasItem and not n.visible:
		return
	if n is Sprite2D and n.texture != null:
		acc.append(_xform_rect(n.get_global_transform(), n.get_rect()))
	elif n is AnimatedSprite2D and n.sprite_frames != null:
		var anim: StringName = n.animation
		if n.sprite_frames.has_animation(anim) and n.sprite_frames.get_frame_count(anim) > 0:
			var tex: Texture2D = n.sprite_frames.get_frame_texture(anim, 0)
			if tex != null:
				var size := Vector2(tex.get_size())
				var pos := -size * 0.5 if n.centered else Vector2.ZERO
				acc.append(_xform_rect(n.get_global_transform(), Rect2(pos + n.offset, size)))
	elif n is Polygon2D and n.polygon.size() >= 3:
		acc.append(_polygon_rect(n.get_global_transform(), n.polygon))
	elif n is CollisionPolygon2D and n.polygon.size() >= 3:
		acc.append(_polygon_rect(n.get_global_transform(), n.polygon))
	elif n is CollisionShape2D and n.shape != null:
		acc.append(_xform_rect(n.get_global_transform(), n.shape.get_rect()))
	elif n is ColorRect:
		acc.append(_xform_rect(n.get_global_transform(), Rect2(Vector2.ZERO, n.size)))
	for child in n.get_children():
		_accumulate_visual_rects(child, acc)


func _polygon_rect(xf: Transform2D, points: PackedVector2Array) -> Rect2:
	var r := Rect2(xf * points[0], Vector2.ZERO)
	for p in points:
		r = r.expand(xf * p)
	return r


func _xform_rect(xf: Transform2D, r: Rect2) -> Rect2:
	var result := Rect2(xf * r.position, Vector2.ZERO)
	result = result.expand(xf * Vector2(r.end.x, r.position.y))
	result = result.expand(xf * Vector2(r.position.x, r.end.y))
	result = result.expand(xf * r.end)
	return result


# ------------------------------------------------------------------
#  ITEM : une vignette + un nom, draggable vers la scène
# ------------------------------------------------------------------

class DrawerItem extends VBoxContainer:
	## Émis quand le drag initié depuis cette vignette s'est terminé
	## par un dépôt réussi quelque part dans l'éditeur
	signal dropped

	var path: String
	var _icon: TextureRect
	var _label: Label
	var _dragging := false  # DRAG_END est diffusé à tous les contrôles :
							# seule la vignette source du drag doit émettre

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END and _dragging:
			_dragging = false
			if is_inside_tree() and get_viewport().gui_is_drag_successful():
				dropped.emit()

	func _init(p_path: String) -> void:
		path = p_path
		custom_minimum_size = Vector2(96, 112)
		tooltip_text = path + "\n(glisser dans la scène — double-clic pour ouvrir)"
		mouse_filter = Control.MOUSE_FILTER_STOP

		_icon = TextureRect.new()
		_icon.custom_minimum_size = Vector2(80, 80)
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)

		_label = Label.new()
		_label.text = path.get_file().get_basename()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		_label.custom_minimum_size = Vector2(96, 0)
		_label.add_theme_font_size_override("font_size", 20)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)

	func set_preview(tex: Texture2D) -> void:
		_icon.texture = tex

	## Ajuste la taille d'affichage de la vignette (réglette de zoom du tiroir)
	func set_display_size(s: float) -> void:
		custom_minimum_size = Vector2(s + 16.0, s + 32.0)
		_icon.custom_minimum_size = Vector2(s, s)
		_label.custom_minimum_size = Vector2(s + 16.0, 0)

	## Même format de drag que le dock FileSystem : l'éditeur sait déjà
	## instancier une .tscn ou créer un Sprite2D depuis une image
	func _get_drag_data(_pos: Vector2) -> Variant:
		_dragging = true
		var preview := TextureRect.new()
		preview.texture = _icon.texture
		preview.custom_minimum_size = Vector2(48, 48)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.modulate.a = 0.8
		set_drag_preview(preview)
		return {"type": "files", "files": [path], "from": self}

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton \
			and event.double_click \
			and event.button_index == MOUSE_BUTTON_LEFT:
			if path.get_extension().to_lower() in ["tscn", "scn"]:
				EditorInterface.open_scene_from_path(path)
			else:
				EditorInterface.edit_resource(load(path))
