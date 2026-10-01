extends Node2D
const SP := "C:/Users/kaoru/AppData/Local/Temp/claude/C--Users-kaoru-StarVania/7c09354e-af63-4b86-9a95-845f685dcfaa/scratchpad/defi/"
const PLAYER := preload("res://SCRIPT/CHARACHTER/PLAYER.tscn")
func _ready() -> void:
	for action in InputMap.get_actions():
		for ev in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, ev)
	var fen := get_window()
	fen.borderless = false
	for i in 2:
		await get_tree().process_frame
	fen.mode = Window.MODE_WINDOWED
	for i in 2:
		await get_tree().process_frame
	fen.size = Vector2i(960, 540)
	var fond := ColorRect.new()
	fond.color = Color(0.2, 0.21, 0.25)
	fond.position = Vector2(-6000, -3000)
	fond.size = Vector2(30000, 8000)
	fond.z_index = -10
	add_child(fond)
	var sol := StaticBody2D.new()
	sol.collision_layer = 1 | 2 | 4
	var f := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(20000, 100)
	f.shape = r
	sol.add_child(f)
	sol.position = Vector2(0, 50)
	add_child(sol)
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	cam.zoom = Vector2(2.0, 2.0)
	var j = PLAYER.instantiate()
	add_child(j)
	j.global_position = Vector2(0, -10)
	for i in 40:
		await get_tree().physics_frame
	cam.global_position = j.global_position + Vector2(0, -120)
	Player.decouvrir_talisman("defi")
	Player.equiper_talisman("defi")
	for k in 3:
		for i in 25:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().get_region(Rect2i(960 - 200, 540 - 220, 400, 420)).save_png(SP + "petite_%d.png" % k)
	get_tree().quit()
