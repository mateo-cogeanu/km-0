extends Node
## Plays one ending cinematic on its own (KM0_CINE = replaced, house or free)
## and saves frames at the times in KM0_CINE_TIMES into KM0_CHECK_DIR.

const Cinematic := preload("res://scripts/ending_cinematic.gd")


func _ready() -> void:
	var kind := OS.get_environment("KM0_CINE")
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var cinematic: Control = Cinematic.create(kind if kind else "replaced")
	layer.add_child(cinematic)
	var button := Button.new()
	button.text = "Main menu"
	button.name = "EndButton"
	cinematic.set_card([["Somebody always comes.", 40], ["A line of text under it, for the layout.", 20], ["THE END", 30]], button)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var times: Array = []
	for value in OS.get_environment("KM0_CINE_TIMES").split(",", false):
		times.append(float(value))
	var dir := OS.get_environment("KM0_CHECK_DIR")
	while not times.is_empty():
		await get_tree().process_frame
		if cinematic.time >= times[0]:
			var inner: Image = cinematic.viewport.get_texture().get_image()
			inner.resize(16, 9)
			var total := 0.0
			for y in 9:
				for x in 16:
					total += inner.get_pixel(x, y).get_luminance()
			print("t=", times[0], " shot=", cinematic.last_shot, " inner=", snappedf(total / 144.0, 0.001), " cam=", cinematic.camera.global_position.snapped(Vector3.ONE * 0.01), " fade=", cinematic.fade.color.a)
			get_viewport().get_texture().get_image().save_png(dir.path_join("%s_%05.1f.png" % [kind, times[0]]))
			cinematic.viewport.get_texture().get_image().save_png(dir.path_join("%s_%05.1f_scene.png" % [kind, times[0]]))
			times.pop_front()
	get_tree().quit()
