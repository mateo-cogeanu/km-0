extends Node
## The lobby as the host sees it, with each story picked. Screenshots into KM0_CHECK_DIR.

func _ready() -> void:
	var dir := OS.get_environment("KM0_CHECK_DIR")
	var menu: Control = load("res://scenes/multiplayer_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	for i in 20:
		await get_tree().process_frame
	NetworkManager.create_lobby("Friday night", "Mateo")
	for story in ["road", "salvage"]:
		NetworkManager.set_lobby_story(story)
		for i in 20:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/lobby_%s.png" % [dir, story])
	NetworkManager.leave_lobby()
	get_tree().quit()
