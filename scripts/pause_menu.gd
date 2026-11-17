extends CanvasLayer

const SettingsPanel := preload("res://scripts/settings_panel.gd")
const Style := preload("res://scripts/menu_style.gd")

var overlay: Control
var card: PanelContainer
var resume_button: Button
var settings_button: Button
var settings_panel: PanelContainer
var tutorial: Control
var tutorial_card: PanelContainer
var tutorial_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	dim.color = Color(0, 0, 0, 0.48)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	card = PanelContainer.new()
	card.custom_minimum_size.x = 300
	overlay.add_child(card)

	var items := Style.vbox(10)
	card.add_child(items)
	items.add_child(Style.heading("Paused", 46))
	resume_button = Style.button("Resume", 24)
	resume_button.pressed.connect(_resume_game)
	items.add_child(resume_button)
	settings_button = Style.button("Settings", 24)
	settings_button.pressed.connect(_open_settings)
	items.add_child(settings_button)
	tutorial_button = Style.button("Show tutorial again", 24)
	tutorial_button.pressed.connect(_toggle_tutorial)
	items.add_child(tutorial_button)
	var main_menu := Style.button("Main menu" if NetworkManager.is_online() else "Save & main menu", 24)
	main_menu.pressed.connect(_return_to_menu)
	items.add_child(main_menu)
	var quit := Style.button("Quit game" if NetworkManager.is_online() else "Save & quit", 24)
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	var dialog := AcceptDialog.new()
	dialog.dialog_text = "Could not save your trip. Check available disk space and try again."
	overlay.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


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
	if not GameSettings.tutorial_done:
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
