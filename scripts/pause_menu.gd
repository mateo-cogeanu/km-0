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
	# Wrapping changes the minimum height after the container gets its width.
	var bounds := tutorial_card.get_combined_minimum_size()
	var available := Vector2(viewport_size.x - 32.0, viewport_size.y * 0.68).max(Vector2.ONE)
	var fit := minf(GameSettings.ui_scale, minf(available.x / bounds.x, available.y / bounds.y))
	tutorial_card.size = bounds
	tutorial_card.scale = Vector2.ONE * fit
	tutorial_card.position = (viewport_size - bounds * fit) * 0.5


func _pause_game() -> void:
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
	tutorial = ColorRect.new()
	tutorial.color = Color(0.04, 0.04, 0.04, 0.58)
	tutorial.theme = Style.make_theme()
	add_child(tutorial)
	tutorial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial_card = PanelContainer.new()
	tutorial_card.custom_minimum_size.x = 470
	tutorial.add_child(tutorial_card)
	tutorial_card.minimum_size_changed.connect(_fit_layout, CONNECT_DEFERRED)
	var items := Style.vbox(10)
	tutorial_card.add_child(items)
	items.add_child(Style.heading("Get the car running", 32))
	_add_tutorial_step(items, "1. Find what’s missing",
		"Inspect the wheels and look under the hood for an engine, radiator, and battery. Search around the shack for the missing parts.")
	_add_tutorial_step(items, "2. Put the car back together",
		"Carry each part to its empty mount. Keep the hood open for engine bay parts. When the tooltip says Install, fit the part before moving on.")
	_add_tutorial_step(items, "3. Fuel up and head out",
		"Take the fuel can from the shack and open the car’s fuel cap. Aim at the filler to refuel. Open the shutter, get in, and follow the road. Check abandoned buildings for supplies along the way.")
	_add_tutorial_step(items, "4. Look after yourself",
		"Eat and drink what you find: hold it and press R. Search coolers and toolboxes for supplies. Sleep on the cot, or press Z in a parked car, when you get tired. Q puts away what you’re holding, or opens your pack when your hands are empty. F switches your flashlight on and off; batteries run down.")
	var actions := HBoxContainer.new()
	items.add_child(actions)
	var start := Style.button("Start repairs", 17)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(start)
	var skip := Style.button("Skip tutorial", 17)
	skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(skip)
	start.pressed.connect(_close_tutorial)
	skip.pressed.connect(_close_tutorial)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	start.grab_focus.call_deferred()


func _add_tutorial_step(items: VBoxContainer, title: String, text: String) -> void:
	items.add_child(Style.label(title, 17, Style.AMBER))
	items.add_child(Style.caption(text))


func _close_tutorial() -> void:
	tutorial.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
