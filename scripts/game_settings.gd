extends Node

signal settings_changed
signal player_name_changed(value: String)

const CONFIG_PATH := "user://settings.cfg"
const SECTION := "settings"
const FPS_OPTIONS: Array[int] = [30, 45, 60, 90, 120, 144]
const RENDER_SCALE_OPTIONS: Array[float] = [0.5, 0.67, 0.75, 1.0]
const SHADOW_OPTIONS: Array[String] = ["Off", "Medium", "High", "Ultra"]
const LIGHTING_OPTIONS: Array[String] = ["Performance", "Balanced", "Cinematic"]

var camera_motion := 0.65
var player_name := ""
var fps_cap: int = 90
var vsync_enabled: bool = true
var fullscreen_enabled: bool = false
var master_volume: float = 1.0
var mouse_sensitivity_scale: float = 1.0
var show_fps: bool = false
var render_scale: float = 1.0
var shadow_quality: int = 3
var lighting_quality: int = 2
var headlight_shadows: bool = true
var ui_scale: float = 1.35
var subtitles := true
var voice_volume := 1.0
var fov := 75.0
## Softer stings, no camera shake or red flash in the scariest moments.
var reduce_scares := false
## For older computers: no screen-space effects, no lamp shadows, less dust.
var low_end := false
## 0 near, 1 medium, 2 far: how much road and desert is kept around you.
var draw_distance := 1
## The first trip's job-sheet tutorial has been finished or skipped.
var tutorial_done := false
const DRAW_OPTIONS: Array[String] = ["Near", "Medium", "Far"]
const PRESETS: Array[String] = ["Potato", "Low", "Medium", "High", "Ultra"]


func _ready() -> void:
	load_settings()
	apply_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return

	camera_motion = clampf(float(config.get_value(SECTION, "camera_motion", camera_motion)), 0.0, 1.0)
	player_name = str(config.get_value(SECTION, "player_name", "")).strip_edges().substr(0, 24)
	fps_cap = int(config.get_value(SECTION, "fps_cap", fps_cap))
	if not FPS_OPTIONS.has(fps_cap):
		fps_cap = 90
	vsync_enabled = bool(config.get_value(SECTION, "vsync_enabled", vsync_enabled))
	fullscreen_enabled = bool(config.get_value(SECTION, "fullscreen_enabled", fullscreen_enabled))
	master_volume = clampf(float(config.get_value(SECTION, "master_volume", master_volume)), 0.0, 1.0)
	mouse_sensitivity_scale = clampf(float(config.get_value(SECTION, "mouse_sensitivity_scale", mouse_sensitivity_scale)), 0.35, 2.0)
	show_fps = bool(config.get_value(SECTION, "show_fps", show_fps))
	render_scale = _nearest_render_scale(float(config.get_value(SECTION, "render_scale", render_scale)))
	shadow_quality = clampi(int(config.get_value(SECTION, "shadow_quality", shadow_quality)), 0, SHADOW_OPTIONS.size() - 1)
	lighting_quality = clampi(int(config.get_value(SECTION, "lighting_quality", lighting_quality)), 0, LIGHTING_OPTIONS.size() - 1)
	headlight_shadows = bool(config.get_value(SECTION, "headlight_shadows", headlight_shadows))
	ui_scale = clampf(float(config.get_value(SECTION, "ui_scale", ui_scale)), 1.0, 1.8)
	subtitles = bool(config.get_value(SECTION, "subtitles", subtitles))
	voice_volume = clampf(float(config.get_value(SECTION, "voice_volume", voice_volume)), 0.0, 1.0)
	fov = clampf(float(config.get_value(SECTION, "fov", fov)), 60.0, 100.0)
	reduce_scares = bool(config.get_value(SECTION, "reduce_scares", reduce_scares))
	low_end = bool(config.get_value(SECTION, "low_end", low_end))
	draw_distance = clampi(int(config.get_value(SECTION, "draw_distance", draw_distance)), 0, 2)
	tutorial_done = bool(config.get_value(SECTION, "tutorial_done", tutorial_done))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(SECTION, "camera_motion", camera_motion)
	config.set_value(SECTION, "player_name", player_name)
	config.set_value(SECTION, "fps_cap", fps_cap)
	config.set_value(SECTION, "vsync_enabled", vsync_enabled)
	config.set_value(SECTION, "fullscreen_enabled", fullscreen_enabled)
	config.set_value(SECTION, "master_volume", master_volume)
	config.set_value(SECTION, "mouse_sensitivity_scale", mouse_sensitivity_scale)
	config.set_value(SECTION, "show_fps", show_fps)
	config.set_value(SECTION, "render_scale", render_scale)
	config.set_value(SECTION, "shadow_quality", shadow_quality)
	config.set_value(SECTION, "lighting_quality", lighting_quality)
	config.set_value(SECTION, "headlight_shadows", headlight_shadows)
	config.set_value(SECTION, "ui_scale", ui_scale)
	config.set_value(SECTION, "subtitles", subtitles)
	config.set_value(SECTION, "voice_volume", voice_volume)
	config.set_value(SECTION, "fov", fov)
	config.set_value(SECTION, "reduce_scares", reduce_scares)
	config.set_value(SECTION, "low_end", low_end)
	config.set_value(SECTION, "draw_distance", draw_distance)
	config.set_value(SECTION, "tutorial_done", tutorial_done)
	config.save(CONFIG_PATH)


func apply_settings() -> void:
	Engine.max_fps = fps_cap
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen_enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)
	var voices := voice_bus()
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(voices), linear_to_db(maxf(voice_volume, 0.001)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index(voices), voice_volume <= 0.001)
	_apply_viewport_settings()
	settings_changed.emit()


func _apply_viewport_settings() -> void:
	if not is_inside_tree():
		return

	var viewport := get_tree().root
	# Avoid sharpening noise from low-resolution lighting and shadows.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = render_scale
	viewport.set("msaa_3d", Viewport.MSAA_DISABLED if low_end else (Viewport.MSAA_4X if shadow_quality >= 2 else Viewport.MSAA_2X))
	viewport.set("screen_space_aa", Viewport.SCREEN_SPACE_AA_FXAA)


func set_fps_cap(value: int) -> void:
	fps_cap = value
	apply_settings()
	save_settings()


func set_vsync_enabled(value: bool) -> void:
	vsync_enabled = value
	apply_settings()
	save_settings()


func set_fullscreen_enabled(value: bool) -> void:
	fullscreen_enabled = value
	apply_settings()
	save_settings()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_settings()
	save_settings()


func set_mouse_sensitivity_scale(value: float) -> void:
	mouse_sensitivity_scale = clampf(value, 0.35, 2.0)
	save_settings()


func set_show_fps(value: bool) -> void:
	show_fps = value
	save_settings()
	settings_changed.emit()


func set_render_scale(value: float) -> void:
	render_scale = _nearest_render_scale(value)
	apply_settings()
	save_settings()


func set_shadow_quality(value: int) -> void:
	shadow_quality = clampi(value, 0, SHADOW_OPTIONS.size() - 1)
	apply_settings()
	save_settings()


func set_lighting_quality(value: int) -> void:
	lighting_quality = clampi(value, 0, LIGHTING_OPTIONS.size() - 1)
	apply_settings()
	save_settings()


func set_headlight_shadows(value: bool) -> void:
	headlight_shadows = value
	apply_settings()
	save_settings()


func set_ui_scale(value: float) -> void:
	ui_scale = clampf(value, 1.0, 1.8)
	save_settings()
	settings_changed.emit()


func get_fps_label(value: int) -> String:
	return "%d FPS" % value


func get_render_scale_label(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


func _nearest_render_scale(value: float) -> float:
	var best_value := RENDER_SCALE_OPTIONS[0]
	var best_distance := absf(value - best_value)
	for option in RENDER_SCALE_OPTIONS:
		var distance := absf(value - option)
		if distance < best_distance:
			best_distance = distance
			best_value = option

	return best_value


func set_player_name(value: String) -> void:
	var cleaned := value.strip_edges().substr(0, 24)
	if cleaned.is_empty() or cleaned == player_name:
		return
	player_name = cleaned
	save_settings()
	player_name_changed.emit(player_name)


func voice_bus() -> StringName:
	## Every spoken line goes through this bus, so it has its own volume.
	if AudioServer.get_bus_index(&"Voice") < 0:
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, &"Voice")
		AudioServer.set_bus_send(index, AudioServer.get_bus_name(0))
	return &"Voice"


func lamp_shadows() -> bool:
	## Whether small lights (lamps, bulbs, flashlights) should cast shadows.
	return not low_end and shadow_quality >= 1


func set_option(key: String, value: Variant) -> void:
	set(key, value)
	save_settings()
	apply_settings()


func apply_preset(index: int) -> void:
	## One click for a whole graphics level, from the oldest laptop up.
	match index:
		0:
			render_scale = 0.5; shadow_quality = 0; lighting_quality = 0; low_end = true; draw_distance = 0; headlight_shadows = false
		1:
			render_scale = 0.67; shadow_quality = 1; lighting_quality = 0; low_end = true; draw_distance = 0; headlight_shadows = false
		2:
			render_scale = 0.75; shadow_quality = 1; lighting_quality = 1; low_end = false; draw_distance = 1; headlight_shadows = true
		3:
			render_scale = 1.0; shadow_quality = 2; lighting_quality = 2; low_end = false; draw_distance = 1; headlight_shadows = true
		_:
			render_scale = 1.0; shadow_quality = 3; lighting_quality = 2; low_end = false; draw_distance = 2; headlight_shadows = true
	save_settings()
	apply_settings()
