extends Control
## The title screen: the road behind, the menu down the left over a dark
## gradient so it reads against the sky and the sand.

const Style := preload("res://scripts/menu_style.gd")
const SettingsPanel := preload("res://scripts/settings_panel.gd")
const WIDTH := 400.0

var settings_panel: Control
var name_panel: Control
var screen: Dictionary
var menu: VBoxContainer
var version_label: Label
var first_button: Button
var settings_button: Button


func _ready() -> void:
	get_tree().paused = false
	NetworkManager.story = "road"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettings.apply_settings()
	theme = Style.make_theme()
	_build()
	_create_settings_panel()
	resized.connect(_fit)
	GameSettings.settings_changed.connect(_fit)
	_fit()
	if GameSettings.player_name.is_empty():
		_prompt_for_name.call_deferred()
	else:
		first_button.grab_focus.call_deferred()


func _build() -> void:
	# A dark band down the left: the menu stays readable whatever the sky does.
	var scrim := TextureRect.new()
	scrim.name = "Scrim"
	var fade := Gradient.new()
	fade.set_color(0, Color(0, 0, 0, 0.78))
	fade.set_color(1, Color(0, 0, 0, 0.0))
	fade.add_point(0.45, Color(0, 0, 0, 0.55))
	var ramp := GradientTexture2D.new()
	ramp.gradient = fade
	ramp.fill_from = Vector2(0, 0)
	ramp.fill_to = Vector2(1, 0)
	scrim.texture = ramp
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)

	screen = Style.screen(self, WIDTH)
	(screen["panel"] as PanelContainer).add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	menu = screen["content"]
	menu.add_theme_constant_override("separation", Style.GAP_M)
	var title := Style.heading("KM 0", Style.TITLE)
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	menu.add_child(title)
	menu.add_child(Style.spacer(Style.GAP_L))

	var can_continue := TripSave.has_trip()
	if can_continue:
		var continue_button := Style.primary("Continue")
		continue_button.name = "ContinueButton"
		continue_button.pressed.connect(func() -> void: TripSave.start_trip(true))
		menu.add_child(continue_button)
		first_button = continue_button
	var start := Style.button("New trip") if can_continue else Style.primary("Start")
	start.name = "StartButton"
	start.pressed.connect(_start_game)
	menu.add_child(start)
	if first_button == null:
		first_button = start
	var multiplayer_button := Style.button("Multiplayer")
	multiplayer_button.name = "MultiplayerButton"
	multiplayer_button.pressed.connect(_open_multiplayer)
	menu.add_child(multiplayer_button)
	settings_button = Style.button("Settings")
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(_open_settings)
	menu.add_child(settings_button)
	menu.add_child(Style.spacer(Style.GAP_S))
	var quit := Style.quiet("Quit")
	quit.name = "QuitButton"
	quit.pressed.connect(_quit_game)
	menu.add_child(quit)

	version_label = Style.label("Version %s" % ProjectSettings.get_setting("application/config/version"), Style.SMALL, Style.FAINT)
	version_label.name = "Version"
	add_child(version_label)


func _fit() -> void:
	Style.fit_screen(screen, size, true, true)
	var factor := Style.ui_scale(size)
	var scrim: Control = get_node("Scrim")
	scrim.size = Vector2(minf(size.x, (WIDTH + 260.0) * factor), size.y)
	version_label.scale = Vector2.ONE * factor
	version_label.position = Vector2(size.x - (version_label.size.x + 24.0) * factor, size.y - (version_label.size.y + 16.0) * factor)
	if is_instance_valid(name_panel):
		Style.fit_panel(name_panel, size, true)


func _start_game() -> void:
	if not TripSave.has_trip():
		TripSave.start_trip(false)
		return
	Style.confirm(self, "Start a new trip?", "Your saved trip will be replaced the next time the game saves.",
		"Start new trip", "Keep my trip", func() -> void: TripSave.start_trip(false))


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
	(screen["scroll"] as Control).hide()
	settings_panel.open()


func _close_settings() -> void:
	(screen["scroll"] as Control).show()
	settings_button.grab_focus()


func _prompt_for_name() -> void:
	(screen["scroll"] as Control).hide()
	name_panel = PanelContainer.new()
	name_panel.name = "NamePrompt"
	name_panel.custom_minimum_size.x = WIDTH + 40.0
	add_child(name_panel)

	var content := Style.vbox(Style.GAP_M)
	name_panel.add_child(content)
	content.add_child(Style.heading("Your name", Style.H1))
	content.add_child(Style.body("This is the name other players see in multiplayer. You can change it later in Settings."))

	var field := LineEdit.new()
	field.name = "PlayerName"
	field.max_length = 24
	field.placeholder_text = "Player name"
	field.custom_minimum_size.y = Style.BUTTON_HEIGHT
	content.add_child(field)

	var next := Style.primary("Continue")
	next.disabled = true
	content.add_child(next)
	field.text_changed.connect(func(value: String) -> void:
		next.disabled = value.strip_edges().is_empty()
	)
	field.text_submitted.connect(_save_first_name)
	next.pressed.connect(func() -> void:
		_save_first_name(field.text)
	)
	name_panel.minimum_size_changed.connect(_fit)
	_fit()
	field.grab_focus()


func _save_first_name(value: String) -> void:
	if value.strip_edges().is_empty() or not is_instance_valid(name_panel):
		return
	GameSettings.set_player_name(value)
	name_panel.queue_free()
	name_panel = null
	(screen["scroll"] as Control).show()
	first_button.grab_focus()
