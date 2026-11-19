extends Node
## Every menu at several window sizes: main menu, name prompt, settings (both
## pages), multiplayer browser and lobby, pause menu, pause settings,
## inventory and the tutorial. Screenshots into KM0_CHECK_DIR.

const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1024, 640), Vector2i(2560, 1600)]
var dir := OS.get_environment("KM0_CHECK_DIR")


func _ready() -> void:
	var only := OS.get_environment("KM0_SIZES")
	for size: Vector2i in SIZES:
		if not only.is_empty() and not only.contains(str(size.x)):
			continue
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(size)
		await _frames(10)
		var tag := "%dx%d" % [size.x, size.y]
		# Main menu, and its settings.
		var menu: Control = load("res://scenes/menu.tscn").instantiate()
		get_tree().root.add_child(menu)
		await _frames(30)
		await _shot("main_" + tag)
		menu._prompt_for_name()
		await _frames(10)
		await _shot("name_" + tag)
		menu._save_first_name(GameSettings.player_name if not GameSettings.player_name.is_empty() else "Mateo")
		menu._open_settings()
		await _frames(10)
		await _shot("settings_video_" + tag)
		for page in ["Sound", "Game"]:
			menu.settings_panel._show_page(page)
			await _frames(10)
			await _shot("settings_%s_%s" % [page.to_lower(), tag])
		menu.queue_free()
		await _frames(5)
		# Multiplayer: browser, then a hosted lobby.
		var mp: Control = load("res://scenes/multiplayer_menu.tscn").instantiate()
		get_tree().root.add_child(mp)
		await _frames(30)
		await _shot("mp_browser_" + tag)
		NetworkManager.create_lobby("A rather long lobby name", "Mateo")
		await _frames(20)
		await _shot("mp_lobby_" + tag)
		NetworkManager.leave_lobby()
		mp.queue_free()
		await _frames(5)
		# In game: pause, pause settings, inventory, tutorial.
		var world: Node = load("res://scenes/main.tscn").instantiate()
		get_tree().root.add_child(world)
		get_tree().current_scene = world
		await _frames(60)
		var guide := world.get_node_or_null("TutorialGuide")
		if guide:
			await _shot("tutorial_" + tag)
			guide.queue_free()
		var pause := world.get_node_or_null("PauseMenu")
		if pause:
			pause._pause_game()
			await _frames(10)
			await _shot("pause_" + tag)
			pause._open_settings()
			await _frames(10)
			await _shot("pause_settings_" + tag)
			pause.settings_panel.close()
			pause._resume_game()
			await _frames(5)
		var player := get_tree().get_first_node_in_group("local_player")
		if player and player.has_method("open_inventory"):
			player.open_inventory()
			await _frames(10)
			await _shot("inventory_" + tag)
			player.close_inventory()
		await _frames(5)
		await _shot("hud_" + tag)
		world.queue_free()
		get_tree().current_scene = null
		await _frames(10)
	get_tree().quit()


func _shot(title: String) -> void:
	await _frames(3)
	if not dir.is_empty():
		get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
