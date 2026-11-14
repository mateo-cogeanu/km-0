extends Control

const Style := preload("res://scripts/menu_style.gd")

var speed_label: Label
var gear_label: Label
var fuel_label: Label
var lights_label: Label
var fuel_bar: ProgressBar
var rev_bar: ProgressBar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.055, 0.065, 0.07, 0.90), Color(0.72, 0.68, 0.54, 0.35), 10))
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := Style.vbox(5)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	speed_label = Style.label("0", 34)
	top.add_child(speed_label)
	var units := Style.label("km/h", 13, Style.MUTED)
	units.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	top.add_child(units)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	gear_label = Style.label("N", 24, Style.AMBER)
	gear_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(gear_label)

	rev_bar = _add_bar(column, 4, Style.MUTED)
	var status := HBoxContainer.new()
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(status)
	fuel_label = Style.label("", 14)
	fuel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(fuel_label)
	lights_label = Style.label("Lights", 12, Style.MUTED)
	status.add_child(lights_label)
	fuel_bar = _add_bar(column, 6, Style.AMBER)


func _add_bar(parent: Control, height: int, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size.y = height
	bar.add_theme_stylebox_override("background", Style.box(Color(1, 1, 1, 0.10), Color.TRANSPARENT))
	bar.add_theme_stylebox_override("fill", Style.box(color, Color.TRANSPARENT))
	parent.add_child(bar)
	return bar


func show_vehicle(vehicle: Node3D) -> void:
	visible = is_instance_valid(vehicle)
	if not visible:
		return
	var ignition: float = vehicle.ignition_progress()
	var planar_speed := Vector2(vehicle.linear_velocity.x, vehicle.linear_velocity.z).length()
	speed_label.text = "%d" % roundi(planar_speed * 3.6)
	var gear: int = vehicle.current_gear
	gear_label.text = "R" if gear == -1 else ("N" if gear == 0 else str(gear))
	var fuel: float = vehicle.get_fuel_fraction()
	var pedal: bool = vehicle.get_fuel_text() == "Pedal power"
	fuel_label.text = "Pedal power" if pedal else vehicle.get_fuel_text()
	fuel_label.modulate = Color("#ef956e") if not pedal and fuel < 0.15 else Color.WHITE
	fuel_bar.visible = not pedal
	fuel_bar.value = fuel
	rev_bar.visible = not pedal
	rev_bar.value = (vehicle.motor_rpm / maxf(vehicle.max_rpm, 1.0)) * smoothstep(0.2, 1.0, ignition)
	fuel_bar.modulate.a = lerpf(0.28, 1.0, ignition)
	if ignition < 1.0:
		fuel_label.text = "Powering on…" if vehicle.current_engine_variant == "Electric" else "Starting…"
	lights_label.visible = not pedal and vehicle.headlights_enabled
	lights_label.modulate = Color("#d2ecb9")
