@tool
extends EditorScript

func _run():
	var vp := EditorInterface.get_editor_viewport_2d() # ou get_editor_viewport_3d(0)
	var img := vp.get_texture().get_image()
	img.save_png("res://preview.png")
