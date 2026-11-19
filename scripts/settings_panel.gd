extends Control
## Settings, shared by the title screen and the pause menu: three pages
## (Video, Sound, Game), settings grouped under small headings, one row style,
## and every yes-or-no setting the same On/Off switch that says what it is now.

signal closed

const Style := preload("res://scripts/menu_style.gd")
const WIDTH := 560.0

var align_left := false
var screen: Dictionary
var pages := {}
var tabs := {}
var first_controls := {}
var page := "Video"

var player_name_edit: LineEdit
var preset_option: OptionButton
var fps_option: OptionButton
var render_scale_option: OptionButton
var shadow_option: OptionButton
var lighting_option: OptionButton
var draw_option: OptionButton
var vsync_check: Button
var fullscreen_check: Button
var headlight_shadows_check: Button
var show_fps_check: Button
var low_end_check: Button
var subtitles_check: Button
var scares_check: Button
var volume_slider: HSlider
var volume_value: Label
var voice_slider: HSlider
var voice_value: Label
var sensitivity_slider: HSlider
var sensitivity_value: Label
var camera_motion_slider: HSlider
var camera_motion_value: Label
var ui_scale_slider: HSlider
var ui_scale_value: Label
var fov_slider: HSlider
var fov_value: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Style.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_sync_from_settings()
	get_viewport().size_changed.connect(_fit_layout)
	GameSettings.settings_changed.connect(_fit_layout)


func open() -> void:
	_sync_from_settings()
	visible = true
	_fit_layout()
	_show_page(page)


func close() -> void:
	_save_player_name()
	visible = false
	closed.emit()


func _fit_layout() -> void:
	if visible:
		Style.fit_screen(screen, get_viewport().get_visible_rect().size, align_left)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode == KEY_TAB:
		# Ctrl+Tab moves between the pages.
		var names := pages.keys()
		_show_page(names[(names.find(page) + (names.size() - 1 if event.shift_pressed else 1)) % names.size()])
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	screen = Style.screen(self, WIDTH)
	var root: VBoxContainer = screen["content"]
	root.add_child(Style.heading("Settings", Style.H1))

	var tab_row := Style.hbox(Style.GAP_S)
	root.add_child(tab_row)
	var group := ButtonGroup.new()
	for title in ["Video", "Sound", "Game"]:
		var tab := Style.button(title)
		tab.toggle_mode = true
		tab.button_group = group
		tab.alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_show_page.bind(title))
		tab_row.add_child(tab)
		tabs[title] = tab
		var holder := Style.vbox(Style.GAP_XS)
		root.add_child(holder)
		pages[title] = holder
	root.add_child(Style.divider())

	_build_video(pages["Video"])
	_build_sound(pages["Sound"])
	_build_game(pages["Game"])
	# Every page as tall as the tallest, so the tabs and Back never jump.
	var tallest := 0.0
	for holder: Control in pages.values():
		tallest = maxf(tallest, holder.get_combined_minimum_size().y)
	for holder: Control in pages.values():
		holder.custom_minimum_size.y = tallest

	var back := Style.quiet("Back")
	back.pressed.connect(close)
	root.add_child(back)


func _show_page(title: String) -> void:
	page = title
	for name in pages:
		(pages[name] as Control).visible = name == title
		(tabs[name] as Button).set_pressed_no_signal(name == title)
	if visible and first_controls.has(title):
		(first_controls[title] as Control).grab_focus()


func _build_video(holder: VBoxContainer) -> void:
	holder.add_child(Style.section("Quality"))
	preset_option = Style.dropdown(["Custom"] + Array(GameSettings.PRESETS))
	preset_option.item_selected.connect(func(index: int) -> void:
		if index > 0:
			GameSettings.apply_preset(index - 1)
			_sync_from_settings())
	Style.row(holder, "Preset", preset_option, "Sets resolution, shadows, lighting and draw distance in one go.")
	first_controls["Video"] = preset_option
	low_end_check = Style.toggle(false, func(on: bool) -> void:
		GameSettings.set_option("low_end", on)
		_sync_preset())
	Style.row(holder, "Older computer mode", low_end_check, "Simpler effects for old or integrated graphics.")
	render_scale_option = Style.dropdown(GameSettings.RENDER_SCALE_OPTIONS.map(func(value: float) -> String: return GameSettings.get_render_scale_label(value)))
	render_scale_option.item_selected.connect(func(index: int) -> void:
		GameSettings.set_render_scale(GameSettings.RENDER_SCALE_OPTIONS[index])
		_sync_preset())
	Style.row(holder, "3D resolution", render_scale_option)
	shadow_option = Style.dropdown(GameSettings.SHADOW_OPTIONS)
	shadow_option.item_selected.connect(func(index: int) -> void:
		GameSettings.set_shadow_quality(index)
		_sync_preset())
	Style.row(holder, "Shadows", shadow_option)
	lighting_option = Style.dropdown(GameSettings.LIGHTING_OPTIONS)
	lighting_option.item_selected.connect(func(index: int) -> void:
		GameSettings.set_lighting_quality(index)
		_sync_preset())
	Style.row(holder, "Lighting", lighting_option)
	draw_option = Style.dropdown(GameSettings.DRAW_OPTIONS)
	draw_option.item_selected.connect(func(index: int) -> void:
		GameSettings.set_option("draw_distance", index)
		_sync_preset())
	Style.row(holder, "Draw distance", draw_option)
	headlight_shadows_check = Style.toggle(false, func(on: bool) -> void:
		GameSettings.set_headlight_shadows(on)
		_sync_preset())
	Style.row(holder, "Headlight shadows", headlight_shadows_check)

	holder.add_child(Style.spacer(Style.GAP_S))
	holder.add_child(Style.section("Display"))
	fullscreen_check = Style.toggle(false, func(on: bool) -> void: GameSettings.set_fullscreen_enabled(on))
	Style.row(holder, "Fullscreen", fullscreen_check)
	vsync_check = Style.toggle(false, func(on: bool) -> void: GameSettings.set_vsync_enabled(on))
	Style.row(holder, "VSync", vsync_check, "Stops tearing; caps the frame rate to your screen.")
	fps_option = Style.dropdown(GameSettings.FPS_OPTIONS.map(func(value: int) -> String: return GameSettings.get_fps_label(value)))
	fps_option.item_selected.connect(func(index: int) -> void: GameSettings.set_fps_cap(GameSettings.FPS_OPTIONS[index]))
	Style.row(holder, "Frame rate limit", fps_option)
	show_fps_check = Style.toggle(false, func(on: bool) -> void: GameSettings.set_show_fps(on))
	Style.row(holder, "Show frame rate", show_fps_check)


func _build_sound(holder: VBoxContainer) -> void:
	holder.add_child(Style.section("Volume"))
	volume_slider = Style.slider(0.0, 1.0, 0.01)
	volume_value = Style.value_label()
	volume_slider.value_changed.connect(func(value: float) -> void:
		GameSettings.set_master_volume(value)
		volume_value.text = "%d%%" % roundi(value * 100.0))
	Style.slider_row(holder, "Master", volume_slider, volume_value)
	first_controls["Sound"] = volume_slider
	voice_slider = Style.slider(0.0, 1.0, 0.01)
	voice_value = Style.value_label()
	voice_slider.value_changed.connect(func(value: float) -> void:
		voice_value.text = "%d%%" % roundi(value * 100.0)
		GameSettings.set_option("voice_volume", value))
	Style.slider_row(holder, "Voices", voice_slider, voice_value)
	holder.add_child(Style.spacer(Style.GAP_S))
	holder.add_child(Style.section("Text"))
	subtitles_check = Style.toggle(true, func(on: bool) -> void: GameSettings.set_option("subtitles", on))
	Style.row(holder, "Subtitles", subtitles_check, "Show what is said on radios and by people.")


func _build_game(holder: VBoxContainer) -> void:
	holder.add_child(Style.section("You"))
	player_name_edit = LineEdit.new()
	player_name_edit.max_length = 24
	player_name_edit.placeholder_text = "Player name"
	player_name_edit.custom_minimum_size = Vector2(Style.CONTROL_WIDTH, Style.ROW_HEIGHT - 4)
	player_name_edit.text_submitted.connect(func(_value: String) -> void: _save_player_name())
	player_name_edit.focus_exited.connect(_save_player_name)
	Style.row(holder, "Player name", player_name_edit, "The name other players see in multiplayer.")
	first_controls["Game"] = player_name_edit

	holder.add_child(Style.spacer(Style.GAP_S))
	holder.add_child(Style.section("Controls"))
	sensitivity_slider = Style.slider(0.35, 2.0, 0.05)
	sensitivity_value = Style.value_label()
	sensitivity_slider.value_changed.connect(func(value: float) -> void:
		GameSettings.set_mouse_sensitivity_scale(value)
		sensitivity_value.text = "%.2f×" % value)
	Style.slider_row(holder, "Mouse sensitivity", sensitivity_slider, sensitivity_value)
	fov_slider = Style.slider(60.0, 100.0, 1.0)
	fov_value = Style.value_label()
	fov_slider.value_changed.connect(func(value: float) -> void:
		fov_value.text = "%d°" % roundi(value)
		GameSettings.set_option("fov", value))
	Style.slider_row(holder, "Field of view", fov_slider, fov_value)

	holder.add_child(Style.spacer(Style.GAP_S))
	holder.add_child(Style.section("Comfort"))
	camera_motion_slider = Style.slider(0.0, 1.0, 0.05)
	camera_motion_value = Style.value_label()
	camera_motion_slider.value_changed.connect(func(value: float) -> void:
		GameSettings.camera_motion = value
		GameSettings.save_settings()
		_show_camera_motion_value(value))
	Style.slider_row(holder, "Camera motion", camera_motion_slider, camera_motion_value, "Head bob and sway while walking and driving.")
	ui_scale_slider = Style.slider(1.0, 1.8, 0.05)
	ui_scale_value = Style.value_label()
	# Applied when let go, so the menu doesn't resize under the mouse.
	ui_scale_slider.value_changed.connect(func(value: float) -> void: ui_scale_value.text = _percent_size(value))
	ui_scale_slider.drag_ended.connect(func(_changed: bool) -> void: GameSettings.set_ui_scale(ui_scale_slider.value))
	ui_scale_slider.focus_exited.connect(func() -> void:
		if not is_equal_approx(GameSettings.ui_scale, ui_scale_slider.value):
			GameSettings.set_ui_scale(ui_scale_slider.value))
	Style.slider_row(holder, "Interface size", ui_scale_slider, ui_scale_value)
	scares_check = Style.toggle(false, func(on: bool) -> void: GameSettings.set_option("reduce_scares", on))
	Style.row(holder, "Reduce scares", scares_check, "Fewer sudden loud sounds and jump scares.")


func _sync_preset() -> void:
	## Shows which preset the current settings match, or Custom.
	var current := [GameSettings.render_scale, GameSettings.shadow_quality, GameSettings.lighting_quality,
		GameSettings.low_end, GameSettings.draw_distance, GameSettings.headlight_shadows]
	var presets := [
		[0.5, 0, 0, true, 0, false], [0.67, 1, 0, true, 0, false], [0.75, 1, 1, false, 1, true],
		[1.0, 2, 2, false, 1, true], [1.0, 3, 2, false, 2, true],
	]
	var match_index := 0
	for index in presets.size():
		var preset: Array = presets[index]
		if is_equal_approx(preset[0], current[0]) and preset.slice(1) == current.slice(1):
			match_index = index + 1
	preset_option.select(match_index)


func _sync_from_settings() -> void:
	if fps_option == null:
		return
	player_name_edit.text = GameSettings.player_name
	fps_option.select(maxi(GameSettings.FPS_OPTIONS.find(GameSettings.fps_cap), 0))
	render_scale_option.select(maxi(GameSettings.RENDER_SCALE_OPTIONS.find(GameSettings.render_scale), 0))
	shadow_option.select(GameSettings.shadow_quality)
	lighting_option.select(GameSettings.lighting_quality)
	draw_option.select(GameSettings.draw_distance)
	Style.set_toggle(vsync_check, GameSettings.vsync_enabled)
	Style.set_toggle(fullscreen_check, GameSettings.fullscreen_enabled)
	Style.set_toggle(headlight_shadows_check, GameSettings.headlight_shadows)
	Style.set_toggle(show_fps_check, GameSettings.show_fps)
	Style.set_toggle(low_end_check, GameSettings.low_end)
	Style.set_toggle(subtitles_check, GameSettings.subtitles)
	Style.set_toggle(scares_check, GameSettings.reduce_scares)
	volume_slider.set_value_no_signal(GameSettings.master_volume)
	volume_value.text = "%d%%" % roundi(GameSettings.master_volume * 100.0)
	voice_slider.set_value_no_signal(GameSettings.voice_volume)
	voice_value.text = "%d%%" % roundi(GameSettings.voice_volume * 100.0)
	sensitivity_slider.set_value_no_signal(GameSettings.mouse_sensitivity_scale)
	sensitivity_value.text = "%.2f×" % GameSettings.mouse_sensitivity_scale
	fov_slider.set_value_no_signal(GameSettings.fov)
	fov_value.text = "%d°" % roundi(GameSettings.fov)
	camera_motion_slider.set_value_no_signal(GameSettings.camera_motion)
	_show_camera_motion_value(GameSettings.camera_motion)
	ui_scale_slider.set_value_no_signal(GameSettings.ui_scale)
	ui_scale_value.text = _percent_size(GameSettings.ui_scale)
	_sync_preset()


func _save_player_name() -> void:
	if player_name_edit == null:
		return
	GameSettings.set_player_name(player_name_edit.text)
	player_name_edit.text = GameSettings.player_name


func _percent_size(value: float) -> String:
	return "%d%%" % roundi(value / Style.UI_SCALE_NORMAL * 100.0)


func _show_camera_motion_value(value: float) -> void:
	camera_motion_value.text = "Off" if value == 0.0 else "%d%%" % roundi(value * 100.0)
