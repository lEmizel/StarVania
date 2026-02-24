## sprite_scaler.gd
## Script @tool — Scale automatiquement tous les Sprite2D enfants en ×2
## Les sprites déjà scalés ne sont pas re-scalés.
##
## UTILISATION :
## 1. Attache ce script à ton Node2D parent "Decors"
## 2. Place tes sprites dessous
## 3. Coche "Appliquer Scale" dans l'inspecteur
##
## Le script vérifie chaque sprite : si son scale est déjà à (2,2) il ne touche pas.

@tool
extends Node2D

## Le facteur de scale à appliquer
@export var target_scale: float = 2.0

## ▶ Coche pour appliquer le scale sur tous les sprites enfants
@export var appliquer_scale: bool = false : set = _on_apply

## ▶ Coche pour remettre tous les sprites enfants à scale (1,1)
@export var reset_scale: bool = false : set = _on_reset


func _on_apply(value: bool) -> void:
	if not value:
		return
	appliquer_scale = false
	
	if not Engine.is_editor_hint():
		return
	
	var count := 0
	var skipped := 0
	_apply_to_children(self, count, skipped)
	print("[SpriteScaler] ✅ %d sprites scalés en ×%.1f — %d déjà au bon scale (ignorés)" % [count, target_scale, skipped])


func _on_reset(value: bool) -> void:
	if not value:
		return
	reset_scale = false
	
	if not Engine.is_editor_hint():
		return
	
	var count := 0
	_reset_children(self, count)
	print("[SpriteScaler] ✅ %d sprites remis à scale (1, 1)" % count)


func _apply_to_children(node: Node, count: int, skipped: int) -> Array:
	for child in node.get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			var current: Vector2 = child.scale
			var target := Vector2(target_scale, target_scale)
			# Tolérance pour éviter les erreurs de float
			if current.is_equal_approx(target):
				skipped += 1
			else:
				child.scale = target
				count += 1
		# Récursif dans les sous-enfants
		var result := _apply_to_children(child, count, skipped)
		count = result[0]
		skipped = result[1]
	return [count, skipped]


func _reset_children(node: Node, count: int) -> int:
	for child in node.get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			if not child.scale.is_equal_approx(Vector2.ONE):
				child.scale = Vector2.ONE
				count += 1
		count = _reset_children(child, count)
	return count
