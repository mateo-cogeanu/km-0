extends Node
## What the player carries. Q puts the held item away, or opens this list when
## your hands are empty. The flashlight is always with you (F).

signal take_requested(index: int)
signal eat_requested(index: int)

const Style := preload("res://scripts/menu_style.gd")

const CAPACITY := 8
## Anything longer than this on its longest side is too big to pocket.
const MAX_SIZE := 0.95

var items: Array[RigidBody3D] = []
var screen: Control
var list: VBoxContainer
var title_for := Callable()


func setup(layer: CanvasLayer, titles: Callable) -> void:
	title_for = titles
	screen = ColorRect.new()
	screen.name = "Inventory"
	(screen as ColorRect).color = Color(0, 0, 0, 0.45)
	screen.theme = Style.make_theme()
	layer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	screen.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(380, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var heading := Style.label("Inventory", 24)
	box.add_child(heading)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	box.add_child(list)
	var hint := Style.label("Q or Esc to close", 13)
	hint.modulate = Color(1, 1, 1, 0.6)
	box.add_child(hint)
	screen.hide()


func is_open() -> bool:
	return screen != null and screen.visible


func refusal(body: RigidBody3D) -> String:
	## Why this can't be put away, or an empty string when it can.
	if items.size() >= CAPACITY:
		return "Inventory full"
	if _longest_side(body) > MAX_SIZE:
		return "Too big to carry"
	return ""


func add(body: RigidBody3D) -> void:
	items.append(body)
	_refresh()


func remove_at(index: int) -> RigidBody3D:
	var body := items[index]
	items.remove_at(index)
	_refresh()
	return body


func open() -> void:
	_refresh()
	var card := screen.get_child(0) as Control
	card.scale = Vector2.ONE * GameSettings.ui_scale * 1.25
	screen.show()
	card.size = Vector2.ZERO
	_center.call_deferred(card)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _center(card: Control) -> void:
	card.size = card.get_combined_minimum_size()
	card.pivot_offset = card.size * 0.5
	card.position = (screen.size - card.size) * 0.5


func close() -> void:
	screen.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()
	var torch := Style.label("Flashlight  (F to switch on and off)", 16)
	list.add_child(torch)
	if items.is_empty():
		var empty := Style.label("Nothing else. Hold something and press Q to put it away.", 14)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.modulate = Color(1, 1, 1, 0.7)
		list.add_child(empty)
	for i in items.size():
		var body := items[i]
		if not is_instance_valid(body):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		list.add_child(row)
		var title := String(title_for.call(body))
		var name_label := Style.label(title.left(1).to_upper() + title.substr(1), 16)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		if body.is_in_group("food"):
			var eat := Style.button("Eat", 15)
			eat.pressed.connect(func() -> void: eat_requested.emit(i))
			row.add_child(eat)
		var take := Style.button("Take", 15)
		take.pressed.connect(func() -> void: take_requested.emit(i))
		row.add_child(take)
	var count := Style.label("%d / %d" % [items.size(), CAPACITY], 13)
	count.modulate = Color(1, 1, 1, 0.6)
	list.add_child(count)


static func _longest_side(body: Node3D) -> float:
	var bounds := AABB()
	var first := true
	for visual: VisualInstance3D in body.find_children("*", "VisualInstance3D", true, false):
		var box: AABB = (body.global_transform.affine_inverse() * visual.global_transform) * visual.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
