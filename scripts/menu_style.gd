extends RefCounted

const INK := Color("#17130c")
const SURFACE := Color(0.055, 0.065, 0.07, 0.94)
const FIELD := Color(0.036, 0.044, 0.048, 0.9)
const LINE := Color(1, 1, 1, 0.26)
const TEXT := Color("#fff0d1")
const MUTED := Color("#d0ccc3")
const AMBER := Color("#eb9e1f")
const GREEN := Color("#b2e4a2")
const ALERT := Color("#ffb5a5")


static func box(fill: Color, edge: Color, inset: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = inset
	style.content_margin_right = inset
	style.content_margin_top = inset
	style.content_margin_bottom = inset
	return style


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", TEXT)
	theme.set_stylebox("panel", "PanelContainer", box(SURFACE, LINE, 18))
	for kind in ["Button", "OptionButton"]:
		var normal := box(Color(0.055, 0.065, 0.07, 0.86), LINE, 5)
		normal.content_margin_left = 14
		theme.set_stylebox("normal", kind, normal)
		var hover := box(AMBER, Color("#ffdc8f"), 5)
		hover.content_margin_left = 14
		theme.set_stylebox("hover", kind, hover)
		var pressed := box(Color("#b8660f"), Color("#ffc251"), 5)
		pressed.content_margin_left = 14
		theme.set_stylebox("pressed", kind, pressed)
		theme.set_stylebox("hover_pressed", kind, pressed)
		theme.set_stylebox("disabled", kind, box(Color(0.055, 0.065, 0.07, 0.68), Color(1, 1, 1, 0.12), 5))
		var focus := box(Color.TRANSPARENT, Color("#ffd58b"))
		focus.draw_center = false
		theme.set_stylebox("focus", kind, focus)
		theme.set_color("font_color", kind, TEXT)
		theme.set_color("font_hover_color", kind, INK)
		theme.set_color("font_pressed_color", kind, Color.WHITE)
		theme.set_color("font_hover_pressed_color", kind, Color.WHITE)
		theme.set_color("font_disabled_color", kind, Color("#a69f92"))

	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_hover_color", "CheckBox", Color("#ffd58b"))
	theme.set_color("font_pressed_color", "CheckBox", TEXT)

	var input := box(FIELD, LINE, 6)
	var outline := box(Color.TRANSPARENT, Color("#ffd58b"))
	outline.draw_center = false
	theme.set_stylebox("normal", "LineEdit", input)
	theme.set_stylebox("focus", "LineEdit", outline)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", AMBER)
	theme.set_color("selection_color", "LineEdit", Color("#70501f"))

	theme.set_stylebox("panel", "ItemList", input)
	theme.set_stylebox("focus", "ItemList", outline)
	theme.set_stylebox("hovered", "ItemList", box(Color("#3c3221"), LINE))
	theme.set_stylebox("selected", "ItemList", box(Color("#5f411c"), AMBER))
	theme.set_stylebox("selected_focus", "ItemList", box(Color("#5f411c"), Color("#ffd58b")))
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", TEXT)
	theme.set_constant("v_separation", "ItemList", 7)
	theme.set_stylebox("slider", "HSlider", box(FIELD, LINE, 3))
	theme.set_stylebox("grabber_area", "HSlider", box(Color("#9b610f"), AMBER, 3))
	theme.set_stylebox("grabber_area_highlight", "HSlider", box(AMBER, Color("#ffd58b"), 3))
	theme.set_stylebox("panel", "PopupMenu", box(SURFACE, LINE, 6))
	theme.set_stylebox("hover", "PopupMenu", box(Color("#5f411c"), AMBER, 4))
	theme.set_color("font_color", "PopupMenu", TEXT)
	return theme


static func label(value: String, font_size: int = 16, tint: Color = TEXT) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", tint)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func heading(value: String, font_size: int) -> Label:
	var result := label(value, font_size)
	result.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	result.add_theme_constant_override("shadow_offset_x", 2)
	result.add_theme_constant_override("shadow_offset_y", 2)
	return result


static func caption(value: String) -> Label:
	var result := label(value, 15, MUTED)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


static func button(value: String, font_size: int = 20) -> Button:
	var result := Button.new()
	result.text = value
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.add_theme_font_size_override("font_size", font_size)
	result.custom_minimum_size.y = 44
	return result


static func vbox(gap: int) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation", gap)
	return result


static func fit_panel(panel: Control, viewport_size: Vector2, align_left: bool) -> void:
	var bounds := panel.get_combined_minimum_size()
	var available := (viewport_size - Vector2(32, 32)).max(Vector2.ONE)
	var fit := minf(GameSettings.ui_scale, minf(available.x / bounds.x, available.y / bounds.y))
	panel.size = bounds
	panel.scale = Vector2.ONE * fit
	var centered := (viewport_size - bounds * fit) * 0.5
	panel.position = Vector2(minf(72.0, centered.x) if align_left else centered.x, centered.y)
