extends CanvasLayer

const SettingsPanel := preload("res://scripts/settings_panel.gd")
const Style := preload("res://scripts/menu_style.gd")

var overlay: Control
var card: PanelContainer
var resume_button: Button
var settings_button: Button
var settings_panel: Control
var tutorial: Control
var tutorial_card: PanelContainer
var tutorial_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Above every other overlay (captions, the job sheet, ending overlays).
	layer = 40
	_build_ui()
	_build_tutorial()
	get_viewport().size_changed.connect(_fit_layout)
	GameSettings.settings_changed.connect(_fit_layout)
	_fit_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var player := get_tree().get_first_node_in_group("local_player")
		if player and player.ending_locked:
			return
		if player and player.has_method("reading") and player.reading():
			player.close_note()
			get_viewport().set_input_as_handled()
			return
		if player and player.has_method("inventory_open") and player.inventory_open():
			player.close_inventory()
			get_viewport().set_input_as_handled()
			return
		if tutorial.visible:
			_close_tutorial()
		elif settings_panel.visible:
			settings_panel.close()
		elif overlay.visible:
			_resume_game()
		else:
			_pause_game()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	overlay = Control.new()
	overlay.theme = Style.make_theme()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.hide()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	card = PanelContainer.new()
	card.custom_minimum_size.x = 360
	overlay.add_child(card)

	var items := Style.vbox(Style.GAP_M)
	card.add_child(items)
	items.add_child(Style.heading("Paused", Style.H1))
	if NetworkManager.is_online():
		items.add_child(Style.caption("The game keeps going for everyone else."))
	resume_button = Style.primary("Resume")
	resume_button.pressed.connect(_resume_game)
	items.add_child(resume_button)
	settings_button = Style.button("Settings")
	settings_button.pressed.connect(_open_settings)
	items.add_child(settings_button)
	tutorial_button = Style.button("Show tutorial again")
	tutorial_button.pressed.connect(_toggle_tutorial)
	tutorial_button.visible = not NetworkManager.salvage()
	items.add_child(tutorial_button)
	items.add_child(Style.divider())
	var main_menu := Style.quiet("Leave to main menu" if NetworkManager.is_online() else "Save and go to main menu")
	main_menu.pressed.connect(_return_to_menu)
	items.add_child(main_menu)
	var quit := Style.quiet("Quit game" if NetworkManager.is_online() else "Save and quit")
	quit.pressed.connect(_quit_game)
	items.add_child(quit)

	settings_panel = SettingsPanel.new()
	settings_panel.closed.connect(_close_settings)
	overlay.add_child(settings_panel)


func _fit_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	Style.fit_panel(card, viewport_size, false)



func _pause_game() -> void:
	_refresh_tutorial_button()
	get_tree().paused = not NetworkManager.is_online()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay.show()
	resume_button.grab_focus()


func _resume_game() -> void:
	get_tree().paused = false
	overlay.hide()
	# Back to whatever was on screen: a conversation, a note or the pack
	# still needs the mouse; otherwise the camera has it.
	var player := get_tree().get_first_node_in_group("local_player")
	var busy: bool = player != null and player.has_method("gameplay_ui_open") and (player.gameplay_ui_open() or is_instance_valid(player.get("talking_to")))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if busy else Input.MOUSE_MODE_CAPTURED


func _return_to_menu() -> void:
	if not TripSave.save_trip():
		show_save_error()
		return
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkManager.is_online():
		NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _quit_game() -> void:
	if TripSave.save_trip():
		get_tree().quit()
	else:
		show_save_error()


func show_save_error() -> void:
	if not get_tree().paused:
		_pause_game()
	Style.confirm(overlay, "Couldn’t save your trip", "Check there is free disk space, then try again. If you quit now, progress since the last save is lost.",
		"Quit without saving", "Back to the game", func() -> void: TripSave.quit_without_saving(), func() -> void: resume_button.grab_focus())


func _open_settings() -> void:
	card.hide()
	settings_panel.open()


func _close_settings() -> void:
	card.show()
	settings_button.grab_focus()


func gameplay_ui_open() -> bool:
	return (overlay != null and overlay.visible) or (tutorial != null and tutorial.visible)


func _build_tutorial() -> void:
	## The old card is gone; the tutorial is now a live job sheet on screen
	## (tutorial_guide.gd), shown on your first trip only.
	tutorial = Control.new()
	tutorial.hide()
	add_child(tutorial)
	if not GameSettings.tutorial_done and not NetworkManager.salvage():
		_start_guide.call_deferred()


func _start_guide() -> void:
	var world := get_parent()
	if world == null or world.get_node_or_null("TutorialGuide"):
		return
	var guide: CanvasLayer = preload("res://scripts/tutorial_guide.gd").new()
	guide.name = "TutorialGuide"
	world.add_child(guide)
	_refresh_tutorial_button()


func _guide() -> Node:
	return get_parent().get_node_or_null("TutorialGuide") if get_parent() else null


func _toggle_tutorial() -> void:
	var guide := _guide()
	if guide:
		guide.finish()
	else:
		GameSettings.tutorial_done = false
		GameSettings.save_settings()
		_start_guide()
	_refresh_tutorial_button.call_deferred()


func _refresh_tutorial_button() -> void:
	if tutorial_button:
		var guide := _guide()
		tutorial_button.text = "Skip tutorial" if guide and not guide.is_queued_for_deletion() else "Show tutorial again"


func _close_tutorial() -> void:
	## Kept for the check scenes; there is no card to close any more.
	tutorial.hide()
