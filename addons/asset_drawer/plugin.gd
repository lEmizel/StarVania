@tool
extends EditorPlugin

const DrawerDock := preload("res://addons/asset_drawer/drawer_dock.gd")

## Distance (en pixels monde) en dessous de laquelle les bords s'aimantent
const MAGNET_THRESHOLD := 24.0

var dock: Control
var _magnet_btn: CheckButton

# suivi du drag en cours dans la vue 2D
var _was_pressed := false
var _drag_watch: Node2D = null
var _drag_start_pos := Vector2.INF


func _enter_tree() -> void:
	dock = DrawerDock.new()
	dock.name = "Tiroir"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_BR, dock)
	dock.connect("asset_dropped", _on_drawer_asset_dropped)
	dock.connect("asset_drag_begun", _on_drawer_drag_begun)

	# Barre d'outils en haut du dock Tiroir : aimantation + miroirs
	var toolbar := HBoxContainer.new()

	_magnet_btn = CheckButton.new()
	_magnet_btn.text = "Aimantation"
	_magnet_btn.button_pressed = true
	_magnet_btn.tooltip_text = "Au relâchement d'un déplacement, colle les bords du nœud\naux bords des nœuds voisins (collisions/sprites, seuil %d px)" % int(MAGNET_THRESHOLD)
	_magnet_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_magnet_btn)

	var base := EditorInterface.get_base_control()

	var flip_x := Button.new()
	flip_x.text = "X"
	flip_x.tooltip_text = "Miroir horizontal de la sélection (scale.x inversé)"
	if base.has_theme_icon("MirrorX", "EditorIcons"):
		flip_x.icon = base.get_theme_icon("MirrorX", "EditorIcons")
		flip_x.text = ""
	flip_x.pressed.connect(_flip_selection.bind(0))
	toolbar.add_child(flip_x)

	var flip_y := Button.new()
	flip_y.text = "Y"
	flip_y.tooltip_text = "Miroir vertical de la sélection (scale.y inversé)"
	if base.has_theme_icon("MirrorY", "EditorIcons"):
		flip_y.icon = base.get_theme_icon("MirrorY", "EditorIcons")
		flip_y.text = ""
	flip_y.pressed.connect(_flip_selection.bind(1))
	toolbar.add_child(flip_y)

	var new_scene_btn := Button.new()
	new_scene_btn.text = "+ Scène"
	new_scene_btn.tooltip_text = "Crée une scène de niveau pré-câblée :\nspawnplayer, interactible (+ checkpoint), grayboxing, VISUAL, enemi"
	new_scene_btn.pressed.connect(_on_new_level_scene_pressed)
	toolbar.add_child(new_scene_btn)

	dock.add_child(toolbar)
	dock.move_child(toolbar, 0)

	print("[Asset Drawer] plugin chargé — aimantation + miroirs disponibles dans le dock Tiroir")


func _exit_tree() -> void:
	remove_control_from_docks(dock)
	dock.free()  # l'interrupteur d'aimantation est un enfant du dock, libéré avec lui


# Sélection photographiée au DÉBUT du drag : seule une sélection qui a
# changé depuis correspond à un nœud fraîchement instancié par l'éditeur
var _pre_drag_selection: Array = []


func _on_drawer_drag_begun() -> void:
	_pre_drag_selection = EditorInterface.get_selection().get_selected_nodes()


## Un asset du tiroir vient d'être déposé : l'éditeur instancie le nœud et
## le sélectionne (parfois en plusieurs frames sur une grosse scène) → on
## attend de voir apparaître un nœud NOUVEAU dans la sélection, puis on le
## reparente sous la cible "Parent :" du tiroir et on l'aimante.
## Sans le test de fraîcheur, un dépôt raté (lâché hors zone valide)
## reparentait la sélection PRÉCÉDENTE — d'où les ratés aléatoires.
func _on_drawer_asset_dropped() -> void:
	for i in 15:
		await get_tree().process_frame
		var sel := EditorInterface.get_selection().get_selected_nodes()
		if sel.size() == 1 and sel[0] is Node2D \
			and not _pre_drag_selection.has(sel[0]):
			var node: Node2D = sel[0]
			_reparent_under_target(node, dock.get("target_parent"))
			if _magnet_btn != null and _magnet_btn.button_pressed:
				_apply_magnet(node)
			return


func _reparent_under_target(node: Node2D, target) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	# la case "Parent :" est la SEULE vérité : vide = "(racine)" → l'asset
	# va sous la racine, jamais sous la sélection du moment de l'éditeur
	if target == null or not is_instance_valid(target):
		target = root
	# cibles invalides : hors scène éditée, déjà parent, soi-même ou un ancêtre
	if target != root and not root.is_ancestor_of(target):
		return
	if node.get_parent() == target or node == target or node.is_ancestor_of(target):
		return

	var old_parent := node.get_parent()
	var ur := get_undo_redo()
	ur.create_action("Déposer sous « %s »" % target.name)
	ur.add_do_method(self, "_reparent_keep_position", node, target)
	ur.add_undo_method(self, "_reparent_keep_position", node, old_parent)
	ur.commit_action()


## Reparente en conservant la position globale (et l'ownership pour que
## le nœud soit bien sauvegardé dans la scène)
func _reparent_keep_position(node: Node2D, new_parent: Node) -> void:
	if not is_instance_valid(node) or not is_instance_valid(new_parent):
		return
	if node.get_parent() == new_parent:
		return
	var gpos := node.global_position
	node.get_parent().remove_child(node)
	new_parent.add_child(node, true)
	node.owner = EditorInterface.get_edited_scene_root()
	node.global_position = gpos
	# regarde à nouveau le nœud dans l'arbre de scène
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)


# ------------------------------------------------------------------
#  NOUVELLE SCÈNE DE NIVEAU — squelette pré-câblé prêt à construire
# ------------------------------------------------------------------

const SPAWNPLAYER_SCRIPT_PATH := "res://SCRIPT/UTILITAIRE/spawnplayer.gd"
const CHECKPOINT_SCENE_PATH := "res://SCRIPT/INTERACTIBLE/Checkpoint.tscn"

var _new_scene_dialog: EditorFileDialog = null

func _on_new_level_scene_pressed() -> void:
	if _new_scene_dialog == null:
		_new_scene_dialog = EditorFileDialog.new()
		_new_scene_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_new_scene_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_new_scene_dialog.add_filter("*.tscn", "Scène Godot")
		_new_scene_dialog.current_dir = "res://SCRIPT/SCENE"
		_new_scene_dialog.current_file = "nouveau_niveau.tscn"
		_new_scene_dialog.file_selected.connect(_create_level_scene)
		EditorInterface.get_base_control().add_child(_new_scene_dialog)
	_new_scene_dialog.popup_centered_ratio(0.6)


func _create_level_scene(path: String) -> void:
	var root := Node2D.new()
	root.name = path.get_file().get_basename()

	# spawnplayer : le nœud qui instancie player + caméra au chargement
	var spawn := Node.new()
	spawn.name = "spawnplayer"
	spawn.set_script(load(SPAWNPLAYER_SCRIPT_PATH))
	root.add_child(spawn)
	spawn.owner = root

	# conteneurs d'organisation
	var interactible: Node2D = null
	for container_name in ["interactible", "grayboxing", "VISUAL", "enemi"]:
		var container := Node2D.new()
		container.name = container_name
		root.add_child(container)
		container.owner = root
		if container_name == "interactible":
			interactible = container

	# checkpoint de départ, rangé sous interactible (groupe attendu par spawnplayer)
	var checkpoint_scene: PackedScene = load(CHECKPOINT_SCENE_PATH)
	if checkpoint_scene != null and interactible != null:
		var checkpoint := checkpoint_scene.instantiate()
		checkpoint.name = "checkpoint"
		checkpoint.add_to_group("Checkpoint", true)
		interactible.add_child(checkpoint)
		checkpoint.owner = root

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	root.free()
	if pack_err != OK:
		push_error("[Asset Drawer] échec du pack de la scène : %s" % pack_err)
		return

	var save_err := ResourceSaver.save(packed, path)
	if save_err != OK:
		push_error("[Asset Drawer] échec de la sauvegarde : %s" % save_err)
		return

	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)
	print("[Asset Drawer] scène de niveau créée : ", path)


# ------------------------------------------------------------------
#  MIROIRS — inverse la sélection en X (axis 0) ou en Y (axis 1)
# ------------------------------------------------------------------

func _flip_selection(axis: int) -> void:
	var targets: Array[Node2D] = []
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is Node2D:
			targets.append(n)
	if targets.is_empty():
		return
	var ur := get_undo_redo()
	ur.create_action("Miroir X" if axis == 0 else "Miroir Y")
	for n in targets:
		var new_scale: Vector2 = n.scale
		if axis == 0:
			new_scale.x = -new_scale.x
		else:
			new_scale.y = -new_scale.y
		ur.add_do_property(n, "scale", new_scale)
		ur.add_undo_property(n, "scale", n.scale)
	ur.commit_action()


# ------------------------------------------------------------------
#  AIMANTATION — détection du déplacement dans l'éditeur
# ------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _magnet_btn == null or not _magnet_btn.button_pressed:
		return

	var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	if pressed and not _was_pressed:
		# Début de drag potentiel : on mémorise le nœud sélectionné
		var sel := EditorInterface.get_selection().get_selected_nodes()
		if sel.size() == 1 and sel[0] is Node2D:
			_drag_watch = sel[0]
			_drag_start_pos = _drag_watch.global_position
		else:
			_drag_watch = null

	elif not pressed and _was_pressed:
		# Relâchement : si le nœud a réellement bougé → on aimante
		if _drag_watch != null and is_instance_valid(_drag_watch) \
			and _drag_watch.global_position != _drag_start_pos:
			_apply_magnet(_drag_watch)
		_drag_watch = null

	_was_pressed = pressed


func _apply_magnet(node: Node2D) -> void:
	var rect := _global_rect_of(node)
	if not rect.has_area():
		return

	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return

	# Rectangles candidats : tous les autres nœuds de la scène (hors sous-arbre
	# du nœud déplacé) qui ont une empreinte calculable
	var candidates: Array[Rect2] = []
	_collect_candidate_rects(root, node, candidates)

	# Zone de recherche : on ignore ce qui est loin
	var search := rect.grow(MAGNET_THRESHOLD * 4.0)

	var best_dx := INF
	var best_dy := INF
	for other in candidates:
		if not search.intersects(other, true):
			continue
		# X : collage bord à bord (droite↔gauche) et alignement (gauche↔gauche, droite↔droite)
		for pair in [
			[rect.end.x, other.position.x],       # ma droite contre sa gauche
			[rect.position.x, other.end.x],       # ma gauche contre sa droite
			[rect.position.x, other.position.x],  # alignement des gauches
			[rect.end.x, other.end.x],            # alignement des droites
		]:
			var d: float = pair[1] - pair[0]
			if absf(d) <= MAGNET_THRESHOLD and absf(d) < absf(best_dx):
				best_dx = d
		# Y : même logique (dessous↔dessus, alignements)
		for pair in [
			[rect.end.y, other.position.y],
			[rect.position.y, other.end.y],
			[rect.position.y, other.position.y],
			[rect.end.y, other.end.y],
		]:
			var d: float = pair[1] - pair[0]
			if absf(d) <= MAGNET_THRESHOLD and absf(d) < absf(best_dy):
				best_dy = d

	var offset := Vector2(
		best_dx if best_dx != INF else 0.0,
		best_dy if best_dy != INF else 0.0,
	)
	if offset == Vector2.ZERO:
		return

	var ur := get_undo_redo()
	ur.create_action("Aimantation")
	ur.add_do_property(node, "global_position", node.global_position + offset)
	ur.add_undo_property(node, "global_position", node.global_position)
	ur.commit_action()


# ------------------------------------------------------------------
#  EMPREINTES — rect global d'un nœud (collisions + sprites)
# ------------------------------------------------------------------

func _collect_candidate_rects(n: Node, exclude: Node, out: Array[Rect2]) -> void:
	# Parcourt tout l'arbre : les conteneurs d'organisation (Node2D "dossiers"
	# comme grayboxing/VISUAL) sont traversés, et chaque UNITÉ (instance de
	# scène, corps physique, sprite...) devient un candidat individuel
	for child in n.get_children():
		if child == exclude:
			continue  # on saute tout le sous-arbre du nœud déplacé
		if child is Node2D and _is_snap_unit(child):
			var r := _global_rect_of(child)
			if r.has_area():
				out.append(r)
		else:
			_collect_candidate_rects(child, exclude, out)


## Un nœud est une "unité" d'aimantation (un bloc, un objet) — par opposition
## à un conteneur d'organisation qu'il faut traverser
func _is_snap_unit(n: Node2D) -> bool:
	return n.scene_file_path != "" \
		or n is CollisionObject2D \
		or n is TileMap or n is TileMapLayer \
		or n is Sprite2D or n is AnimatedSprite2D \
		or n is Polygon2D


func _global_rect_of(n: Node) -> Rect2:
	var acc: Array[Rect2] = []
	_accumulate_rects(n, acc)
	if acc.is_empty():
		return Rect2()
	var result: Rect2 = acc[0]
	for i in range(1, acc.size()):
		result = result.merge(acc[i])
	return result


func _accumulate_rects(n: Node, acc: Array[Rect2]) -> void:
	if n is CollisionShape2D and n.shape != null:
		acc.append(_xform_rect(n.get_global_transform(), n.shape.get_rect()))
	elif n is CollisionPolygon2D and n.polygon.size() >= 3:
		var xf: Transform2D = n.get_global_transform()
		var r := Rect2(xf * n.polygon[0], Vector2.ZERO)
		for p in n.polygon:
			r = r.expand(xf * p)
		acc.append(r)
	elif n is Sprite2D and n.texture != null:
		acc.append(_xform_rect(n.get_global_transform(), n.get_rect()))
	for child in n.get_children():
		_accumulate_rects(child, acc)


## Transforme un Rect2 local en rect global englobant (gère rotation/scale)
func _xform_rect(xf: Transform2D, r: Rect2) -> Rect2:
	var result := Rect2(xf * r.position, Vector2.ZERO)
	result = result.expand(xf * Vector2(r.end.x, r.position.y))
	result = result.expand(xf * Vector2(r.position.x, r.end.y))
	result = result.expand(xf * r.end)
	return result
