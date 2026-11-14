extends Control

const Style := preload("res://scripts/menu_style.gd")
const SettingsPanel := preload("res://scripts/settings_panel.gd")

var settings_panel: PanelContainer


func _ready() -> void:
	get_tree().paused = false
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
