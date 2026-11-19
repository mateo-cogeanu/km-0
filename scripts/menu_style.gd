extends RefCounted
## KM0's menu design system. Every menu builds from these pieces so they look
## and behave the same:
##   - one type scale (TITLE/H1/H2/BODY/SMALL) and one spacing grid (GAP_*),
##     all in "design pixels" for a 900-pixel-tall window;
##   - screens scale with the window height and the UI scale setting, and
##     scroll when they are taller than the window instead of shrinking to
##     unreadable sizes (see screen() / fit_screen());
##   - three button weights (primary, secondary, quiet), one toggle, one
##     dropdown, one slider row, and a clear, high-contrast focus ring so the
##     menus work the same with a mouse, a keyboard or a controller;
##   - themed confirm dialogs instead of the engine's default grey ones.

const INK := Color("#17130c")
const SURFACE := Color(0.045, 0.052, 0.056, 0.95)
const RAISED := Color(0.075, 0.085, 0.09, 0.96)
const FIELD := Color(0.03, 0.036, 0.04, 0.95)
const LINE := Color(1, 1, 1, 0.18)
const LINE_STRONG := Color(1, 1, 1, 0.34)
const TEXT := Color("#fff0d1")
const MUTED := Color("#cfc8bb")
const FAINT := Color("#9a9286")
const AMBER := Color("#eb9e1f")
const AMBER_LIGHT := Color("#ffd58b")
const AMBER_DARK := Color("#9c5a0c")
const GREEN := Color("#b2e4a2")
const ALERT := Color("#ffb5a5")

# Type scale.
const TITLE := 88
const H1 := 40
const H2 := 22
const BODY := 18
const SMALL := 15
# Spacing grid.
const GAP_XS := 4
const GAP_S := 8
const GAP_M := 12
const GAP_L := 20
const GAP_XL := 32
# Control sizes.
const BUTTON_HEIGHT := 48
const ROW_HEIGHT := 40
const CONTROL_WIDTH := 200
## Boxed menus (settings, multiplayer, pause, the pack, notes, dialogs) are
## dense with rows, so they are drawn smaller than the open title screen.
const PANEL_SCALE := 0.74
const MIN_FACTOR := 0.72
const PANEL_PADDING := 28
## Window height at which one design pixel is one screen pixel.
const DESIGN_HEIGHT := 820.0
## The UI scale setting that means "normal size" (it was the old default).
## The title screen's open column is drawn larger than the boxed menus.
const TITLE_SCALE := 1.33


static func box(fill: Color, edge: Color, inset: int = 0, width: int = 2, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = inset
	style.content_margin_right = inset
	style.content_margin_top = inset
	style.content_margin_bottom = inset
	style.anti_aliasing = true
	return style


static func _button_box(fill: Color, edge: Color, width := 2) -> StyleBoxFlat:
	var style := box(fill, edge, 0, width)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = BODY
	theme.set_color("font_color", "Label", TEXT)
	theme.set_stylebox("panel", "PanelContainer", box(SURFACE, LINE, PANEL_PADDING, 1, 10))

	# Buttons: secondary by default. Hover and keyboard focus look the same,
	# so whichever way you move through a menu, you see where you are.
	for kind in ["Button", "OptionButton", "CheckButton"]:
		theme.set_stylebox("normal", kind, _button_box(RAISED, LINE_STRONG))
		theme.set_stylebox("hover", kind, _button_box(Color("#2a2418"), AMBER))
		theme.set_stylebox("pressed", kind, _button_box(AMBER, AMBER_LIGHT))
		theme.set_stylebox("hover_pressed", kind, _button_box(Color("#f4b041"), AMBER_LIGHT))
		theme.set_stylebox("disabled", kind, _button_box(Color(0, 0, 0, 0.18), Color(1, 1, 1, 0.07)))
		var focus := box(Color.TRANSPARENT, AMBER_LIGHT, 0, 3, 7)
		focus.draw_center = false
		focus.expand_margin_left = 2
		focus.expand_margin_right = 2
		focus.expand_margin_top = 2
		focus.expand_margin_bottom = 2
		theme.set_stylebox("focus", kind, focus)
		theme.set_color("font_color", kind, TEXT)
		theme.set_color("font_hover_color", kind, AMBER_LIGHT)
		theme.set_color("font_focus_color", kind, AMBER_LIGHT)
		theme.set_color("font_pressed_color", kind, INK)
		theme.set_color("font_hover_pressed_color", kind, INK)
		theme.set_color("font_disabled_color", kind, Color(1, 1, 1, 0.3))
		theme.set_font_size("font_size", kind, BODY)
	theme.set_constant("h_separation", "Button", GAP_S)

	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_hover_color", "CheckBox", AMBER_LIGHT)
	theme.set_color("font_pressed_color", "CheckBox", TEXT)

	var input := box(FIELD, LINE_STRONG, 10, 2)
	input.content_margin_top = 6
	input.content_margin_bottom = 6
	var input_focus := box(FIELD, AMBER_LIGHT, 10, 3)
	input_focus.content_margin_top = 6
	input_focus.content_margin_bottom = 6
	theme.set_stylebox("normal", "LineEdit", input)
	theme.set_stylebox("focus", "LineEdit", input_focus)
	theme.set_stylebox("read_only", "LineEdit", box(Color(0, 0, 0, 0.2), LINE, 10))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", FAINT)
	theme.set_color("caret_color", "LineEdit", AMBER)
	theme.set_color("selection_color", "LineEdit", Color("#70501f"))
	theme.set_font_size("font_size", "LineEdit", BODY)

	var list := box(FIELD, LINE_STRONG, 8, 2)
	var list_focus := box(FIELD, AMBER_LIGHT, 8, 3)
	theme.set_stylebox("panel", "ItemList", list)
	theme.set_stylebox("focus", "ItemList", list_focus)
	theme.set_stylebox("hovered", "ItemList", box(Color("#2a2418"), Color.TRANSPARENT, 0, 0, 4))
	theme.set_stylebox("selected", "ItemList", box(Color("#5f411c"), AMBER, 0, 2, 4))
	theme.set_stylebox("selected_focus", "ItemList", box(Color("#5f411c"), AMBER_LIGHT, 0, 2, 4))
	theme.set_stylebox("cursor", "ItemList", box(Color.TRANSPARENT, AMBER_LIGHT, 0, 2, 4))
	theme.set_stylebox("cursor_unfocused", "ItemList", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", TEXT)
	theme.set_constant("v_separation", "ItemList", GAP_M)
	theme.set_constant("h_separation", "ItemList", GAP_M)
	theme.set_font_size("font_size", "ItemList", BODY)

	theme.set_stylebox("slider", "HSlider", box(FIELD, LINE_STRONG, 3, 1, 4))
	theme.set_stylebox("grabber_area", "HSlider", box(AMBER_DARK, AMBER, 3, 1, 4))
	theme.set_stylebox("grabber_area_highlight", "HSlider", box(AMBER, AMBER_LIGHT, 3, 1, 4))
	var slider_focus := box(Color.TRANSPARENT, AMBER_LIGHT, 0, 2, 6)
	slider_focus.draw_center = false
	slider_focus.expand_margin_top = 6
	slider_focus.expand_margin_bottom = 6
	slider_focus.expand_margin_left = 6
	slider_focus.expand_margin_right = 6
	theme.set_stylebox("focus", "HSlider", slider_focus)

	theme.set_stylebox("panel", "PopupMenu", box(SURFACE, LINE_STRONG, 6, 1, 6))
	theme.set_stylebox("hover", "PopupMenu", box(Color("#5f411c"), AMBER, 4, 1, 4))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_font_size("font_size", "PopupMenu", BODY)
	theme.set_constant("v_separation", "PopupMenu", GAP_M)

	var bar := box(Color(1, 1, 1, 0.06), Color.TRANSPARENT, 0, 0, 3)
	bar.content_margin_left = 2
	bar.content_margin_right = 2
	theme.set_stylebox("scroll", "VScrollBar", bar)
	theme.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.35), Color.TRANSPARENT, 0, 0, 4))
	theme.set_stylebox("grabber_highlight", "VScrollBar", box(AMBER, Color.TRANSPARENT, 0, 0, 4))
	theme.set_stylebox("grabber_pressed", "VScrollBar", box(AMBER_LIGHT, Color.TRANSPARENT, 0, 0, 4))
	theme.set_stylebox("panel", "TooltipPanel", box(SURFACE, LINE_STRONG, 10, 1, 6))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", SMALL)
	return theme


# --- Text ------------------------------------------------------------------------

static func label(value: String, font_size: int = BODY, tint: Color = TEXT) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", tint)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func heading(value: String, font_size: int = H1) -> Label:
	var result := label(value, font_size)
	result.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	result.add_theme_constant_override("shadow_offset_x", 2)
	result.add_theme_constant_override("shadow_offset_y", 2)
	return result


static func section(value: String) -> Label:
	## A small heading over a group of rows.
	var result := label(value.to_upper(), SMALL, AMBER)
	result.add_theme_constant_override("line_spacing", 0)
	return result


static func caption(value: String) -> Label:
	var result := label(value, SMALL, MUTED)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


static func body(value: String) -> Label:
	var result := label(value, BODY, MUTED)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


# --- Buttons and controls ---------------------------------------------------------

static func button(value: String, font_size: int = BODY) -> Button:
	## A secondary button.
	var result := Button.new()
	result.text = value
	result.alignment = HORIZONTAL_ALIGNMENT_LEFT
	result.add_theme_font_size_override("font_size", font_size)
	result.custom_minimum_size.y = BUTTON_HEIGHT
	result.focus_mode = Control.FOCUS_ALL
	return result


static func primary(value: String) -> Button:
	## The one thing this screen is for: filled amber.
	var result := button(value, BODY + 2)
	result.add_theme_stylebox_override("normal", _button_box(AMBER, AMBER_LIGHT))
	result.add_theme_stylebox_override("hover", _button_box(Color("#f6b445"), Color.WHITE))
	result.add_theme_stylebox_override("pressed", _button_box(AMBER_DARK, AMBER_LIGHT))
	result.add_theme_color_override("font_color", INK)
	result.add_theme_color_override("font_hover_color", INK)
	result.add_theme_color_override("font_focus_color", INK)
	result.add_theme_color_override("font_pressed_color", TEXT)
	return result


static func quiet(value: String) -> Button:
	## Back, Quit, Cancel: present but not shouting.
	var result := button(value)
	var flat := _button_box(Color.TRANSPARENT, Color.TRANSPARENT)
	result.add_theme_stylebox_override("normal", flat)
	result.add_theme_color_override("font_color", MUTED)
	return result


static func toggle(on: bool, changed: Callable) -> Button:
	## One On/Off switch for every yes-or-no setting: the label always says
	## what it is now, and it is amber when on.
	var result := button("On" if on else "Off")
	result.toggle_mode = true
	result.alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.set_pressed_no_signal(on)
	result.custom_minimum_size = Vector2(CONTROL_WIDTH, ROW_HEIGHT - 4)
	result.toggled.connect(func(value: bool) -> void:
		result.text = "On" if value else "Off"
		changed.call(value))
	return result


static func set_toggle(target: Button, on: bool) -> void:
	target.set_pressed_no_signal(on)
	target.text = "On" if on else "Off"


static func dropdown(items: Array) -> OptionButton:
	var result := OptionButton.new()
	for item in items:
		result.add_item(str(item))
	result.custom_minimum_size = Vector2(CONTROL_WIDTH, ROW_HEIGHT - 4)
	result.fit_to_longest_item = false
	result.focus_mode = Control.FOCUS_ALL
	return result


static func slider(minimum: float, maximum: float, step: float) -> HSlider:
	var result := HSlider.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = step
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.focus_mode = Control.FOCUS_ALL
	return result


static func row(parent: Control, title: String, control: Control, hint := "") -> HBoxContainer:
	## A setting: its name on the left, its control on the right, every row
	## the same height and the controls lined up in one column.
	var line := HBoxContainer.new()
	line.custom_minimum_size.y = ROW_HEIGHT
	line.add_theme_constant_override("separation", GAP_M)
	parent.add_child(line)
	var name_label := label(title, BODY, TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if not hint.is_empty():
		name_label.tooltip_text = hint
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		control.tooltip_text = hint
	line.add_child(name_label)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if control.custom_minimum_size.x < CONTROL_WIDTH:
		control.custom_minimum_size.x = CONTROL_WIDTH
	line.add_child(control)
	return line


static func slider_row(parent: Control, title: String, control: HSlider, value_label: Label, hint := "") -> HBoxContainer:
	var holder := HBoxContainer.new()
	holder.custom_minimum_size.x = CONTROL_WIDTH
	holder.add_theme_constant_override("separation", GAP_S)
	holder.add_child(control)
	value_label.custom_minimum_size.x = 58
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", SMALL)
	value_label.add_theme_color_override("font_color", MUTED)
	holder.add_child(value_label)
	return row(parent, title, holder, hint)


static func value_label() -> Label:
	return label("", SMALL, MUTED)


static func vbox(gap: int) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation", gap)
	return result


static func hbox(gap: int) -> HBoxContainer:
	var result := HBoxContainer.new()
	result.add_theme_constant_override("separation", gap)
	return result


static func spacer(height: int) -> Control:
	var result := Control.new()
	result.custom_minimum_size.y = height
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result


static func divider() -> HSeparator:
	var result := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = LINE
	line.thickness = 1
	result.add_theme_stylebox_override("separator", line)
	result.add_theme_constant_override("separation", GAP_M)
	return result


# --- Screens ----------------------------------------------------------------------

static func ui_scale(viewport_size: Vector2) -> float:
	## How big one design pixel is: by window height, times the player's UI
	## scale, never smaller than readable.
	return clampf(viewport_size.y / DESIGN_HEIGHT, 0.75, 3.0) * GameSettings.ui_size


static func screen(host: Control, width: float) -> Dictionary:
	## A full-window, scrollable column holding one panel. Returns
	## {scroll, panel, content}; call fit_screen() whenever the window or the
	## UI scale changes.
	var scroll := ScrollContainer.new()
	scroll.name = "Screen"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	host.add_child(scroll)
	var column := MarginContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["top", "bottom"]:
		column.add_theme_constant_override("margin_" + side, GAP_XL)
	scroll.add_child(column)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.custom_minimum_size.x = width
	column.add_child(panel)
	var content := vbox(GAP_M)
	panel.add_child(content)
	return {"scroll": scroll, "panel": panel, "content": content, "width": width}


static func fit_screen(parts: Dictionary, viewport_size: Vector2, align_left: bool, open_layout := false) -> void:
	## open_layout: the title screen's bare column, drawn at full size. Boxed
	## screens get PANEL_SCALE.
	var scroll: ScrollContainer = parts["scroll"]
	var width: float = parts["width"]
	# Never so small that body text drops below about 13 pixels.
	var factor := maxf(ui_scale(viewport_size) * (TITLE_SCALE if open_layout else PANEL_SCALE), MIN_FACTOR)
	# Never wider than the window, with a margin either side.
	factor = minf(factor, (viewport_size.x - 32.0) / (width + 2.0 * GAP_XL))
	factor = maxf(factor, 0.5)
	var scaled_width := (width + GAP_XL + GAP_S + 6.0) * factor
	var left := minf(viewport_size.x * 0.06, (viewport_size.x - scaled_width) * 0.5) if align_left else (viewport_size.x - scaled_width) * 0.5
	scroll.scale = Vector2.ONE * factor
	scroll.position = Vector2(maxf(left, 16.0), 0)
	scroll.size = Vector2(width + GAP_XL + GAP_S + 6.0, viewport_size.y / factor)
	var column: MarginContainer = scroll.get_child(0)
	column.add_theme_constant_override("margin_left", GAP_XL)
	# The scroll bar, when there is one, sits just beside the panel.
	column.add_theme_constant_override("margin_right", GAP_S + 6)


static func fit_panel(panel: Control, viewport_size: Vector2, align_left: bool) -> void:
	## For small fixed cards (pause card, dialogs): scaled like screens and
	## kept inside the window.
	var bounds := panel.get_combined_minimum_size()
	var available := (viewport_size - Vector2(32, 32)).max(Vector2.ONE)
	var fit := minf(maxf(ui_scale(viewport_size) * PANEL_SCALE, MIN_FACTOR), minf(available.x / bounds.x, available.y / bounds.y))
	panel.size = bounds
	panel.scale = Vector2.ONE * fit
	var centered := (viewport_size - bounds * fit) * 0.5
	panel.position = Vector2(minf(viewport_size.x * 0.06, centered.x) if align_left else centered.x, centered.y)


static func confirm(host: Control, title: String, message: String, yes: String, no: String, on_yes: Callable, on_no := Callable()) -> Control:
	## A themed modal question. Focus starts on the safe choice (no), Escape
	## answers no.
	var veil := ColorRect.new()
	veil.name = "Confirm"
	veil.color = Color(0, 0, 0, 0.6)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.theme = make_theme()
	host.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 440
	veil.add_child(card)
	var content := vbox(GAP_M)
	card.add_child(content)
	content.add_child(heading(title, H2 + 6))
	content.add_child(body(message))
	content.add_child(spacer(GAP_S))
	var buttons := hbox(GAP_M)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	content.add_child(buttons)
	var no_button := button(no)
	no_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_button.custom_minimum_size.x = 130
	var yes_button := primary(yes)
	yes_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	yes_button.custom_minimum_size.x = 160
	if no.is_empty():
		no_button.hide()
	buttons.add_child(no_button)
	buttons.add_child(yes_button)
	var close := func(answer: bool) -> void:
		veil.queue_free()
		if answer:
			on_yes.call()
		elif on_no.is_valid():
			on_no.call()
	yes_button.pressed.connect(close.bind(true))
	no_button.pressed.connect(close.bind(false))
	# Escape answers the safe way.
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	var escape := Shortcut.new()
	escape.events = [cancel]
	(no_button if not no.is_empty() else yes_button).shortcut = escape
	(no_button if not no.is_empty() else yes_button).shortcut_in_tooltip = false
	var place := func() -> void:
		if is_instance_valid(card):
			fit_panel(card, veil.size, false)
	veil.resized.connect(place)
	card.minimum_size_changed.connect(place)
	place.call_deferred()
	(no_button if not no.is_empty() else yes_button).grab_focus.call_deferred()
	return veil
