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
	(screen as ColorRect).color = Color(0, 0, 0, 0.55)
	screen.theme = Style.make_theme()
	layer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := PanelContainer.new()
	screen.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(420, 0)
	var box := Style.vbox(Style.GAP_M)
	card.add_child(box)
	box.add_child(Style.heading("Your pack", Style.H2 + 6))
	list = Style.vbox(Style.GAP_S)
	box.add_child(list)
	box.add_child(Style.divider())
	box.add_child(Style.caption("Q or Esc to close"))
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
	screen.show()
	card.size = Vector2.ZERO
	_center.call_deferred(card)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _center(card: Control) -> void:
	# Same size rules as every menu, and always inside the window.
	Style.fit_panel(card, screen.size, false)
	var first := _first_button()
	if first:
		first.grab_focus()


func _first_button() -> Button:
	for button: Button in list.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and not button.disabled:
			return button
	return null


func close() -> void:
	screen.hide()
	# Not while the pause card is up: it needs the pointer.
	var player := screen.get_tree().get_first_node_in_group("local_player")
	if player and player.has_method("capture_mouse_if_playing"):
		player.capture_mouse_if_playing()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh() -> void:
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var torch := Style.hbox(Style.GAP_S)
	list.add_child(torch)
	var torch_name := Style.label("Flashlight")
	torch_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	torch.add_child(torch_name)
	torch.add_child(Style.label("F  on / off", Style.SMALL, Style.FAINT))
	if items.is_empty():
		list.add_child(Style.caption("Nothing else yet. Hold something and press Q to put it in your pack."))
	for i in items.size():
		var body := items[i]
		if not is_instance_valid(body):
			continue
		var row := Style.hbox(Style.GAP_S)
		row.custom_minimum_size.y = Style.ROW_HEIGHT
		list.add_child(row)
		var title := String(title_for.call(body))
		var name_label := Style.label(title.left(1).to_upper() + title.substr(1))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_label)
		var use := ""
		if body.is_in_group("food"):
			use = "Eat"
		elif body.is_in_group("water") and body.amount > 0.05:
			use = "Drink"
		elif body.is_in_group("battery_pack"):
			use = "Load"
		if not use.is_empty():
			var eat := Style.button(use)
			eat.alignment = HORIZONTAL_ALIGNMENT_CENTER
			eat.custom_minimum_size = Vector2(90, Style.ROW_HEIGHT - 4)
			eat.pressed.connect(func() -> void: eat_requested.emit(i))
			row.add_child(eat)
		var take := Style.button("Take out")
		take.alignment = HORIZONTAL_ALIGNMENT_CENTER
		take.custom_minimum_size = Vector2(110, Style.ROW_HEIGHT - 4)
		take.pressed.connect(func() -> void: take_requested.emit(i))
		row.add_child(take)
	list.add_child(Style.label("%d of %d slots used" % [items.size(), CAPACITY], Style.SMALL, Style.FAINT))
	if screen != null and screen.visible:
		_center.call_deferred(screen.get_child(0) as Control)


static func _longest_side(body: Node3D) -> float:
	var bounds := AABB()
	var first := true
	for visual: VisualInstance3D in body.find_children("*", "VisualInstance3D", true, false):
		var box: AABB = (body.global_transform.affine_inverse() * visual.global_transform) * visual.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
