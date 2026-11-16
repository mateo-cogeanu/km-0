extends PanelContainer

signal closed

const Style := preload("res://scripts/menu_style.gd")

var align_left := false
var player_name_edit: LineEdit
var fps_option: OptionButton
var render_scale_option: OptionButton
var shadow_option: OptionButton
var lighting_option: OptionButton
var vsync_check: CheckBox
var fullscreen_check: CheckBox
var headlight_shadows_check: CheckBox
var volume_slider: HSlider
var volume_value: Label
var sensitivity_slider: HSlider
var sensitivity_value: Label
var camera_motion_slider: HSlider
var camera_motion_value: Label
var ui_scale_slider: HSlider
var ui_scale_value: Label
var show_fps_check: CheckBox
var low_end_check: CheckBox
var draw_option: OptionButton
var voice_slider: HSlider
var voice_value: Label
var subtitles_check: CheckBox
var fov_slider: HSlider
var fov_value: Label
var scares_check: CheckBox


func _ready() -> void:
	visible = false
	theme = Style.make_theme()
	custom_minimum_size = Vector2(420, 0)
	_build_ui()
	_sync_from_settings()
	get_viewport().size_changed.connect(_fit_layout)
	minimum_size_changed.connect(_fit_layout)
	GameSettings.settings_changed.connect(_fit_layout)


func open() -> void:
	_sync_from_settings()
	visible = true
	_fit_layout()
	var first_control: Control = fps_option if fps_option.is_visible_in_tree() else volume_slider
	first_control.grab_focus()


func close() -> void:
	_save_player_name()
	visible = false
	closed.emit()


func _fit_layout() -> void:
	if visible:
		Style.fit_panel(self, get_viewport().get_visible_rect().size, align_left)


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build_ui() -> void:
	var root := Style.vbox(10)
	add_child(root)
	root.add_child(Style.heading("Settings", 38))

	var tabs := HBoxContainer.new()
	root.add_child(tabs)
	var group := ButtonGroup.new()
	var graphics := _add_tab(tabs, group, "Graphics")
	var gameplay := _add_tab(tabs, group, "Gameplay")
	var pages := PanelContainer.new()
	pages.add_theme_stylebox_override("panel", Style.box(Style.FIELD, Style.LINE, 12))
	root.add_child(pages)
	var display_controls := Style.vbox(4)
	pages.add_child(display_controls)
	var game_controls := Style.vbox(4)
	pages.add_child(game_controls)
	game_controls.hide()
	graphics.set_pressed_no_signal(true)
	graphics.pressed.connect(func() -> void:
		game_controls.hide()
		display_controls.show()
	)
	gameplay.pressed.connect(func() -> void:
		display_controls.hide()
		game_controls.show()
	)

	var preset_option := OptionButton.new()
	preset_option.add_item("Choose…")
	for value in GameSettings.PRESETS:
		preset_option.add_item(value)
	preset_option.item_selected.connect(func(index: int) -> void:
		if index > 0:
			GameSettings.apply_preset(index - 1)
			_sync_from_settings()
			preset_option.select(0))
	_add_row(display_controls, "Quality preset", preset_option)

	low_end_check = CheckBox.new()
	low_end_check.text = "On"
	low_end_check.toggled.connect(func(on: bool) -> void: GameSettings.set_option("low_end", on))
	_add_row(display_controls, "Older computer mode", low_end_check)

	draw_option = OptionButton.new()
	for value in GameSettings.DRAW_OPTIONS:
		draw_option.add_item(value)
	draw_option.item_selected.connect(func(index: int) -> void: GameSettings.set_option("draw_distance", index))
	_add_row(display_controls, "Draw distance", draw_option)

	fps_option = OptionButton.new()
	for value in GameSettings.FPS_OPTIONS:
		fps_option.add_item(GameSettings.get_fps_label(value))
	fps_option.item_selected.connect(_on_fps_selected)
	_add_row(display_controls, "FPS cap", fps_option)

	render_scale_option = OptionButton.new()
	for value in GameSettings.RENDER_SCALE_OPTIONS:
		render_scale_option.add_item(GameSettings.get_render_scale_label(value))
	render_scale_option.item_selected.connect(_on_render_scale_selected)
	_add_row(display_controls, "3D resolution", render_scale_option)

	shadow_option = OptionButton.new()
	for value in GameSettings.SHADOW_OPTIONS:
		shadow_option.add_item(value)
	shadow_option.item_selected.connect(_on_shadow_selected)
	_add_row(display_controls, "Shadows", shadow_option)

	lighting_option = OptionButton.new()
	for value in GameSettings.LIGHTING_OPTIONS:
		lighting_option.add_item(value)
	lighting_option.item_selected.connect(_on_lighting_selected)
	_add_row(display_controls, "Lighting", lighting_option)

	vsync_check = CheckBox.new()
	vsync_check.text = "On"
	vsync_check.toggled.connect(_on_vsync_toggled)
	_add_row(display_controls, "VSync", vsync_check)

	headlight_shadows_check = CheckBox.new()
	headlight_shadows_check.text = "On"
	headlight_shadows_check.toggled.connect(_on_headlight_shadows_toggled)
	_add_row(display_controls, "Headlight shadows", headlight_shadows_check)

	fullscreen_check = CheckBox.new()
	fullscreen_check.text = "On"
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_add_row(display_controls, "Fullscreen", fullscreen_check)

	player_name_edit = LineEdit.new()
	player_name_edit.max_length = 24
	player_name_edit.placeholder_text = "Player name"
	player_name_edit.text_submitted.connect(func(_value: String) -> void: _save_player_name())
	_add_row(game_controls, "Player name", player_name_edit)

	volume_slider = _create_slider(0.0, 1.0, 0.01)
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_value = Label.new()
	volume_value.custom_minimum_size = Vector2(52.0, 0.0)
	_add_slider_row(game_controls, "Master volume", volume_slider, volume_value)

	voice_slider = _create_slider(0.0, 1.0, 0.01)
	voice_value = Label.new()
	voice_value.custom_minimum_size = Vector2(52.0, 0.0)
	voice_slider.value_changed.connect(func(value: float) -> void:
		voice_value.text = "%d%%" % roundi(value * 100.0)
		GameSettings.set_option("voice_volume", value))
	_add_slider_row(game_controls, "Voice volume", voice_slider, voice_value)

	subtitles_check = CheckBox.new()
	subtitles_check.text = "On"
	subtitles_check.toggled.connect(func(on: bool) -> void: GameSettings.set_option("subtitles", on))
	_add_row(game_controls, "Subtitles", subtitles_check)

	fov_slider = _create_slider(60.0, 100.0, 1.0)
	fov_value = Label.new()
	fov_value.custom_minimum_size = Vector2(52.0, 0.0)
	fov_slider.value_changed.connect(func(value: float) -> void:
		fov_value.text = "%d°" % roundi(value)
		GameSettings.set_option("fov", value))
	_add_slider_row(game_controls, "Field of view", fov_slider, fov_value)

	scares_check = CheckBox.new()
	scares_check.text = "On"
	scares_check.toggled.connect(func(on: bool) -> void: GameSettings.set_option("reduce_scares", on))
	_add_row(game_controls, "Reduce scares", scares_check)

	sensitivity_slider = _create_slider(0.35, 2.0, 0.05)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	sensitivity_value = Label.new()
	sensitivity_value.custom_minimum_size = Vector2(52.0, 0.0)
	_add_slider_row(game_controls, "Mouse sensitivity", sensitivity_slider, sensitivity_value)

	camera_motion_slider = _create_slider(0.0, 1.0, 0.05)
	camera_motion_value = Label.new()
	camera_motion_value.custom_minimum_size.x = 72
	camera_motion_slider.value_changed.connect(_on_camera_motion_changed)
	_add_slider_row(game_controls, "Camera motion", camera_motion_slider, camera_motion_value)

	ui_scale_slider = _create_slider(1.0, 1.8, 0.05)
	ui_scale_slider.value_changed.connect(_on_ui_scale_changed)
	ui_scale_value = Label.new()
	ui_scale_value.custom_minimum_size = Vector2(72.0, 0.0)
	_add_slider_row(game_controls, "UI scale", ui_scale_slider, ui_scale_value)

	show_fps_check = CheckBox.new()
	show_fps_check.text = "On"
	show_fps_check.toggled.connect(_on_show_fps_toggled)
	_add_row(display_controls, "FPS counter", show_fps_check)
	# Keep the tabs in place when switching to the shorter Gameplay page.
	pages.custom_minimum_size.y = pages.get_combined_minimum_size().y

	var close_button := Style.button("Back")
	close_button.pressed.connect(close)
	root.add_child(close_button)


func _add_tab(row: HBoxContainer, group: ButtonGroup, text: String) -> Button:
	var button := Style.button(text, 17)
	button.toggle_mode = true
	button.button_group = group
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	return button


func _add_row(root: VBoxContainer, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	root.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)

	control.custom_minimum_size = Vector2(145, 32)
	if control is Button:
		(control as Button).add_theme_font_size_override("font_size", 15)
	row.add_child(control)


func _add_slider_row(root: VBoxContainer, label_text: String, slider: HSlider, value_label: Label) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	root.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	row.add_child(label)

	slider.custom_minimum_size = Vector2(105, 32)
	row.add_child(slider)
	value_label.add_theme_font_size_override("font_size", 15)
	row.add_child(value_label)


func _create_slider(minimum: float, maximum: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	return slider


func _sync_from_settings() -> void:
	if fps_option == null:
		return

	player_name_edit.text = GameSettings.player_name
	var fps_index := maxi(GameSettings.FPS_OPTIONS.find(GameSettings.fps_cap), 0)
	fps_option.select(fps_index)
	var render_index := maxi(GameSettings.RENDER_SCALE_OPTIONS.find(GameSettings.render_scale), 0)
	render_scale_option.select(render_index)
	shadow_option.select(GameSettings.shadow_quality)
	lighting_option.select(GameSettings.lighting_quality)
	vsync_check.button_pressed = GameSettings.vsync_enabled
	fullscreen_check.button_pressed = GameSettings.fullscreen_enabled
	headlight_shadows_check.button_pressed = GameSettings.headlight_shadows
	volume_slider.value = GameSettings.master_volume
	_update_volume_label()
	sensitivity_slider.value = GameSettings.mouse_sensitivity_scale
	_update_sensitivity_label()
	camera_motion_slider.set_value_no_signal(GameSettings.camera_motion)
	_show_camera_motion_value(GameSettings.camera_motion)
	ui_scale_slider.set_value_no_signal(GameSettings.ui_scale)
	_update_ui_scale_label()
	show_fps_check.button_pressed = GameSettings.show_fps
	low_end_check.set_pressed_no_signal(GameSettings.low_end)
	draw_option.select(GameSettings.draw_distance)
	voice_slider.set_value_no_signal(GameSettings.voice_volume)
	voice_value.text = "%d%%" % roundi(GameSettings.voice_volume * 100.0)
	subtitles_check.set_pressed_no_signal(GameSettings.subtitles)
	fov_slider.set_value_no_signal(GameSettings.fov)
	fov_value.text = "%d°" % roundi(GameSettings.fov)
	scares_check.set_pressed_no_signal(GameSettings.reduce_scares)


func _on_fps_selected(index: int) -> void:
	GameSettings.set_fps_cap(GameSettings.FPS_OPTIONS[index])


func _on_render_scale_selected(index: int) -> void:
	GameSettings.set_render_scale(GameSettings.RENDER_SCALE_OPTIONS[index])


func _on_shadow_selected(index: int) -> void:
	GameSettings.set_shadow_quality(index)


func _on_lighting_selected(index: int) -> void:
	GameSettings.set_lighting_quality(index)


func _on_vsync_toggled(enabled: bool) -> void:
	GameSettings.set_vsync_enabled(enabled)


func _on_fullscreen_toggled(enabled: bool) -> void:
	GameSettings.set_fullscreen_enabled(enabled)


func _on_headlight_shadows_toggled(enabled: bool) -> void:
	GameSettings.set_headlight_shadows(enabled)


func _on_volume_changed(value: float) -> void:
	GameSettings.set_master_volume(value)
	_update_volume_label()


func _on_sensitivity_changed(value: float) -> void:
	GameSettings.set_mouse_sensitivity_scale(value)
	_update_sensitivity_label()


func _on_ui_scale_changed(value: float) -> void:
	GameSettings.set_ui_scale(value)
	_update_ui_scale_label()


func _on_show_fps_toggled(enabled: bool) -> void:
	GameSettings.set_show_fps(enabled)


func _update_volume_label() -> void:
	volume_value.text = "%d%%" % roundi(GameSettings.master_volume * 100.0)


func _update_sensitivity_label() -> void:
	sensitivity_value.text = "%.2fx" % GameSettings.mouse_sensitivity_scale


func _update_ui_scale_label() -> void:
	ui_scale_value.text = "%.2fx" % GameSettings.ui_scale


func _save_player_name() -> void:
	GameSettings.set_player_name(player_name_edit.text)
	player_name_edit.text = GameSettings.player_name


func _on_camera_motion_changed(value: float) -> void:
	GameSettings.camera_motion = value
	GameSettings.save_settings()
	_show_camera_motion_value(value)


func _show_camera_motion_value(value: float) -> void:
	camera_motion_value.text = "Off" if value == 0.0 else "%d%%" % roundi(value * 100.0)
