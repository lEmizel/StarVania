## level_exporter.gd
## Script @tool pour Godot 4 — Exporte les collision shapes d'un niveau en PNG
##
## UTILISATION :
## 1. Attache ce script à un Node vide dans ta scène de niveau
## 2. Dans l'inspecteur, configure le chemin d'export et le scale si besoin
## 3. Coche "Exporter Niveau" → le PNG est généré
## 4. Ouvre le PNG dans Procreate comme calque de référence
##
## export_scale = 1.0 → taille réelle (1 pixel jeu = 1 pixel image)
## export_scale = 0.5 → moitié résolution (image 4× plus légère)

@tool
extends Node

## Chemin de sauvegarde du PNG exporté
@export var export_path: String = "res://level_export.png"
## Facteur d'échelle (0.5 = moitié résolution, 1.0 = taille réelle)
@export var export_scale: float = 1.0
## Couleur de remplissage des collision shapes
@export var fill_color: Color = Color(0.8, 0.2, 0.2, 1.0)
## Couleur du contour des shapes
@export var outline_color: Color = Color(1, 1, 1, 1)
## Couleur de fond
@export var bg_color: Color = Color(0.1, 0.1, 0.1, 1.0)
## Marge en pixels autour du niveau (en unités jeu, sera scalée)
@export var margin: int = 200
## Épaisseur du contour en pixels image
@export var outline_thickness: int = 2
## Nombre de segments pour approximer les cercles/capsules
@export var circle_segments: int = 32

## ▶ Coche cette case pour lancer l'export !
@export var exporter_niveau: bool = false : set = _on_export_pressed


# ============================================================
#  POINT D'ENTRÉE
# ============================================================

func _on_export_pressed(value: bool) -> void:
	if not value:
		return
	exporter_niveau = false
	
	if not Engine.is_editor_hint():
		push_warning("Ce script fonctionne uniquement dans l'éditeur.")
		return
	
	_export_level()


func _export_level() -> void:
	var root = get_tree().edited_scene_root
	if root == null:
		push_error("Aucune scène ouverte dans l'éditeur.")
		return
	
	# 1. Collecter toutes les collision shapes
	var shape_data_list: Array = []
	_collect_shapes(root, shape_data_list)
	
	if shape_data_list.is_empty():
		push_warning("Aucune CollisionShape2D ou CollisionPolygon2D trouvée dans la scène.")
		return
	
	# 2. Convertir chaque shape en polygone (points globaux)
	var polygons: Array = []
	for sd in shape_data_list:
		var poly: PackedVector2Array = _shape_data_to_polygon(sd)
		if not poly.is_empty():
			polygons.append(poly)
	
	if polygons.is_empty():
		push_warning("Aucune shape convertible trouvée.")
		return
	
	# 3. Calculer le bounding rect global
	var bounds := _compute_bounds(polygons)
	bounds = bounds.grow(margin)
	
	# 4. Appliquer le scale à la taille de l'image
	var img_w: int = int(ceil(bounds.size.x * export_scale))
	var img_h: int = int(ceil(bounds.size.y * export_scale))
	
	# Sécurité
	var megapixels := (img_w * img_h) / 1_000_000.0
	print("[LevelExporter] Taille image : %d × %d px (%.1f MP) — scale: %.2f" % [img_w, img_h, megapixels, export_scale])
	if megapixels > 300:
		push_warning("Attention : image très grande (%.0f MP). Ça peut prendre du temps." % megapixels)
	
	# 5. Créer l'image
	var img := Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	img.fill(bg_color)
	
	var offset := bounds.position
	
	# 6. Dessiner chaque polygone (avec scale appliqué aux points)
	for poly in polygons:
		var adjusted := PackedVector2Array()
		for p in poly:
			adjusted.append((p - offset) * export_scale)
		_fill_polygon_scanline(img, adjusted, fill_color)
		_draw_polygon_outline(img, adjusted, outline_color, outline_thickness)
	
	# 7. Sauvegarder
	var err := img.save_png(export_path)
	if err == OK:
		print("[LevelExporter] ✅ Niveau exporté : %s" % export_path)
		print("[LevelExporter] Dimensions : %d × %d px" % [img_w, img_h])
		if export_scale != 1.0:
			print("[LevelExporter] Scale %.2f — dans Godot, importe tes sprites avec un scale de %.1f et filtre nearest." % [export_scale, 1.0 / export_scale])
	else:
		push_error("Erreur lors de la sauvegarde : %s" % str(err))


# ============================================================
#  COLLECTE DES SHAPES
# ============================================================

func _collect_shapes(node: Node, result: Array) -> void:
	if node is CollisionShape2D:
		var cs: CollisionShape2D = node
		if cs.shape != null and not cs.disabled:
			result.append({
				"type": "collision_shape",
				"shape": cs.shape,
				"transform": cs.global_transform,
			})
	
	elif node is CollisionPolygon2D:
		var cp: CollisionPolygon2D = node
		if not cp.disabled and cp.polygon.size() >= 3:
			result.append({
				"type": "collision_polygon",
				"polygon": cp.polygon,
				"transform": cp.global_transform,
			})
	
	for child in node.get_children():
		_collect_shapes(child, result)


# ============================================================
#  CONVERSION SHAPE → POLYGONE (points globaux)
# ============================================================

func _shape_data_to_polygon(sd: Dictionary) -> PackedVector2Array:
	if sd.type == "collision_polygon":
		return _transform_points(sd.polygon, sd.transform)
	
	var shape: Shape2D = sd.shape
	var xform: Transform2D = sd.transform
	var local_points := PackedVector2Array()
	
	if shape is RectangleShape2D:
		var half: Vector2 = shape.size / 2.0
		local_points = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])
	
	elif shape is CircleShape2D:
		var r: float = shape.radius
		for i in circle_segments:
			var angle: float = (float(i) / circle_segments) * TAU
			local_points.append(Vector2(cos(angle), sin(angle)) * r)
	
	elif shape is CapsuleShape2D:
		var r: float = shape.radius
		var h: float = shape.height / 2.0 - r
		var half_segs: int = circle_segments / 2
		for i in range(half_segs + 1):
			var angle: float = PI + (float(i) / half_segs) * PI
			local_points.append(Vector2(cos(angle) * r, sin(angle) * r - h))
		for i in range(half_segs + 1):
			var angle: float = (float(i) / half_segs) * PI
			local_points.append(Vector2(cos(angle) * r, sin(angle) * r + h))
	
	elif shape is ConvexPolygonShape2D:
		local_points = shape.points
	
	elif shape is ConcavePolygonShape2D:
		local_points = shape.segments
	
	elif shape is SegmentShape2D:
		var a: Vector2 = shape.a
		var b: Vector2 = shape.b
		var normal: Vector2 = (b - a).normalized().orthogonal() * 2.0
		local_points = PackedVector2Array([
			a + normal, b + normal, b - normal, a - normal,
		])
	
	elif shape is WorldBoundaryShape2D:
		return PackedVector2Array()
	
	else:
		push_warning("Shape type non supporté : %s" % shape.get_class())
		return PackedVector2Array()
	
	if local_points.is_empty():
		return PackedVector2Array()
	
	return _transform_points(local_points, xform)


func _transform_points(points: PackedVector2Array, xform: Transform2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in points:
		result.append(xform * p)
	return result


# ============================================================
#  CALCUL DU BOUNDING RECT
# ============================================================

func _compute_bounds(polygons: Array) -> Rect2:
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	
	for poly in polygons:
		for p in poly:
			min_pos.x = min(min_pos.x, p.x)
			min_pos.y = min(min_pos.y, p.y)
			max_pos.x = max(max_pos.x, p.x)
			max_pos.y = max(max_pos.y, p.y)
	
	return Rect2(min_pos, max_pos - min_pos)


# ============================================================
#  DESSIN : REMPLISSAGE POLYGONE (Scanline)
# ============================================================

func _fill_polygon_scanline(img: Image, polygon: PackedVector2Array, color: Color) -> void:
	if polygon.size() < 3:
		return
	
	var min_y: int = int(floor(polygon[0].y))
	var max_y: int = int(ceil(polygon[0].y))
	for p in polygon:
		min_y = mini(min_y, int(floor(p.y)))
		max_y = maxi(max_y, int(ceil(p.y)))
	
	min_y = clampi(min_y, 0, img.get_height() - 1)
	max_y = clampi(max_y, 0, img.get_height() - 1)
	
	var n: int = polygon.size()
	
	for y in range(min_y, max_y + 1):
		var intersections: Array[float] = []
		var fy: float = float(y) + 0.5
		
		for i in n:
			var j: int = (i + 1) % n
			var yi: float = polygon[i].y
			var yj: float = polygon[j].y
			
			if (yi <= fy and yj > fy) or (yj <= fy and yi > fy):
				var t: float = (fy - yi) / (yj - yi)
				var x_intersect: float = polygon[i].x + t * (polygon[j].x - polygon[i].x)
				intersections.append(x_intersect)
		
		intersections.sort()
		
		for k in range(0, intersections.size() - 1, 2):
			var x_start: int = maxi(int(floor(intersections[k])), 0)
			var x_end: int = mini(int(ceil(intersections[k + 1])), img.get_width() - 1)
			for x in range(x_start, x_end + 1):
				if color.a < 1.0:
					var existing := img.get_pixel(x, y)
					img.set_pixel(x, y, existing.blend(color))
				else:
					img.set_pixel(x, y, color)


# ============================================================
#  DESSIN : CONTOUR POLYGONE (Bresenham)
# ============================================================

func _draw_polygon_outline(img: Image, polygon: PackedVector2Array, color: Color, thickness: int = 1) -> void:
	if polygon.size() < 2:
		return
	
	var n: int = polygon.size()
	for i in n:
		var j: int = (i + 1) % n
		_draw_thick_line(img, polygon[i], polygon[j], color, thickness)


func _draw_thick_line(img: Image, from: Vector2, to: Vector2, color: Color, thickness: int) -> void:
	if thickness <= 1:
		_draw_line_bresenham(img, int(from.x), int(from.y), int(to.x), int(to.y), color)
		return
	
	var dir := (to - from).normalized()
	var normal := dir.orthogonal()
	var half_t := thickness / 2.0
	
	for t in thickness:
		var offset_val: float = float(t) - half_t + 0.5
		var offset_vec: Vector2 = normal * offset_val
		_draw_line_bresenham(img, 
			int(from.x + offset_vec.x), int(from.y + offset_vec.y),
			int(to.x + offset_vec.x), int(to.y + offset_vec.y),
			color)


func _draw_line_bresenham(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	
	var w: int = img.get_width()
	var h: int = img.get_height()
	
	while true:
		if x0 >= 0 and x0 < w and y0 >= 0 and y0 < h:
			img.set_pixel(x0, y0, color)
		
		if x0 == x1 and y0 == y1:
			break
		
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
