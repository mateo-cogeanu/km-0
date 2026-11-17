extends Control

const Style := preload("res://scripts/menu_style.gd")
const SettingsPanel := preload("res://scripts/settings_panel.gd")

var settings_panel: PanelContainer
var name_panel: PanelContainer


func _ready() -> void:
	get_tree().paused = false
	NetworkManager.story = "road"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.apply_settings()
	resized.connect(_apply_menu_scale)
	GameSettings.settings_changed.connect(_apply_menu_scale)
	$Menu/Version.text = "Version %s" % ProjectSettings.get_setting("application/config/version")
	var can_continue := TripSave.has_trip()
	$Menu/ContinueButton.visible = can_continue
	$Menu/ContinueButton.pressed.connect(func() -> void: TripSave.start_trip(true))
	$Menu/StartButton.text = "New trip" if can_continue else "Start"
	_apply_menu_scale()
	$Menu.minimum_size_changed.connect(_apply_menu_scale)
	_create_settings_panel()
	$Menu/StartButton.pressed.connect(_start_game)
	$Menu/MultiplayerButton.pressed.connect(_open_multiplayer)
	$Menu/SettingsButton.pressed.connect(_open_settings)
	$Menu/QuitButton.pressed.connect(_quit_game)
	if GameSettings.player_name.is_empty():
		_prompt_for_name.call_deferred()


func _start_game() -> void:
	if not TripSave.has_trip():
		TripSave.start_trip(false)
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Starting a new trip will replace your saved trip the next time the game saves."
	dialog.ok_button_text = "Start new trip"
	add_child(dialog)
	dialog.confirmed.connect(func() -> void: TripSave.start_trip(false))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func _open_multiplayer() -> void:
	get_tree().change_scene_to_file("res://scenes/multiplayer_menu.tscn")


func _quit_game() -> void:
	get_tree().quit()


func _create_settings_panel() -> void:
	settings_panel = SettingsPanel.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.align_left = true
	settings_panel.closed.connect(_close_settings)
	add_child(settings_panel)


func _open_settings() -> void:
	$Menu.hide()
	settings_panel.open()


func _close_settings() -> void:
	$Menu.show()
	$Menu/SettingsButton.grab_focus()


func _apply_menu_scale() -> void:
	Style.fit_panel($Menu, size, true)
	if is_instance_valid(name_panel):
		Style.fit_panel(name_panel, size, true)


func _prompt_for_name() -> void:
	$Menu.hide()
	name_panel = PanelContainer.new()
	name_panel.name = "NamePrompt"
	name_panel.theme = Style.make_theme()
	name_panel.custom_minimum_size.x = $Menu.custom_minimum_size.x
	add_child(name_panel)

	var content := Style.vbox(12)
	name_panel.add_child(content)
	content.add_child(Style.heading("Your name", 34))
	content.add_child(Style.label("This is the name other players will see."))

	var field := LineEdit.new()
	field.name = "PlayerName"
	field.max_length = 24
	field.placeholder_text = "Player name"
	field.custom_minimum_size.y = 42
	content.add_child(field)

	var next := Style.button("Continue")
	next.disabled = true
	content.add_child(next)
	field.text_changed.connect(func(value: String) -> void:
		next.disabled = value.strip_edges().is_empty()
	)
	field.text_submitted.connect(_save_first_name)
	next.pressed.connect(func() -> void:
		_save_first_name(field.text)
	)
	name_panel.minimum_size_changed.connect(_apply_menu_scale)
	_apply_menu_scale()
	field.grab_focus()


func _save_first_name(value: String) -> void:
	if value.strip_edges().is_empty() or not is_instance_valid(name_panel):
		return
	GameSettings.set_player_name(value)
	name_panel.queue_free()
	name_panel = null
	$Menu.show()
	if $Menu/ContinueButton.visible:
		$Menu/ContinueButton.grab_focus()
	else:
		$Menu/StartButton.grab_focus()
