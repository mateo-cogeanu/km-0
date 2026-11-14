extends Control

const Style := preload("res://scripts/menu_style.gd")

var lobby_list: ItemList
var lobby_name_edit: LineEdit
var player_name_edit: LineEdit
var status_label: Label
var lobby_count: Label
var empty_label: Label
var join_button: Button
var back_button: Button
var player_list: VBoxContainer
var ready_button: Button
var play_button: Button
var room_title: Label
var room_caption: Label
var room_count: Label
var launch_hint: Label
var setup_panel: VBoxContainer
var room_panel: VBoxContainer
var content: VBoxContainer
var panel: PanelContainer
var scroll: ScrollContainer
var selected_address := ""
var visible_lobbies: Dictionary = {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()
	NetworkManager.lobby_list_changed.connect(_refresh_lobbies)
	NetworkManager.lobby_state_changed.connect(_refresh_room)
	NetworkManager.connection_failed.connect(_show_error)
	resized.connect(_fit_layout)
	GameSettings.settings_changed.connect(_fit_layout)
	_fit_layout()
	_refresh_lobbies(true)
	_refresh_room()


func _exit_tree() -> void:
	if NetworkManager.is_online() and not NetworkManager.game_in_progress:
		NetworkManager.leave_lobby()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()


func _build_ui() -> void:
	theme = Style.make_theme()
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)

	var column := MarginContainer.new()
	column.add_theme_constant_override("margin_top", 16)
	column.add_theme_constant_override("margin_bottom", 16)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	panel = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)
	content = Style.vbox(8)
	panel.add_child(content)
	content.add_child(Style.heading("Multiplayer", 38))

	_build_browser()
	_build_room()
	status_label = Style.caption("")
	content.add_child(status_label)
	back_button = Style.button("Back")
	back_button.pressed.connect(_back)
	content.add_child(back_button)
	_set_status("")


func _build_browser() -> void:
	setup_panel = Style.vbox(8)
	content.add_child(setup_panel)
	player_name_edit = _add_field(setup_panel, "Your name", "Player")

	var browse_header := HBoxContainer.new()
	setup_panel.add_child(browse_header)
	var title := Style.label("LAN lobbies", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browse_header.add_child(title)
	lobby_count = Style.label("", 14, Style.MUTED)
	browse_header.add_child(lobby_count)

	var list_area := Control.new()
	list_area.custom_minimum_size.y = 104
	setup_panel.add_child(list_area)
	lobby_list = ItemList.new()
	lobby_list.item_selected.connect(_select_lobby)
	lobby_list.item_activated.connect(_activate_lobby)
	list_area.add_child(lobby_list)
	lobby_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	empty_label = Style.caption("No lobbies on your network yet.")
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	list_area.add_child(empty_label)
	empty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_label.offset_left = 8.0
	empty_label.offset_right = -8.0

	join_button = Style.button("Join lobby")
	join_button.disabled = true
	join_button.pressed.connect(_join_lobby)
	setup_panel.add_child(join_button)

	lobby_name_edit = _add_field(setup_panel, "Lobby name", "Road Trip")
	lobby_name_edit.text_submitted.connect(func(_value: String) -> void: _create_lobby())
	var create_button := Style.button("Create lobby")
	create_button.pressed.connect(_create_lobby)
	setup_panel.add_child(create_button)


func _build_room() -> void:
	room_panel = Style.vbox(8)
	room_panel.hide()
	content.add_child(room_panel)

	room_title = Style.label("", 23)
	room_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	room_panel.add_child(room_title)
	room_caption = Style.caption("")
	room_panel.add_child(room_caption)
	room_count = Style.label("", 16)
	room_panel.add_child(room_count)
	player_list = Style.vbox(5)
	room_panel.add_child(player_list)

	launch_hint = Style.caption("")
	room_panel.add_child(launch_hint)
	ready_button = Style.button("Ready")
	ready_button.toggle_mode = true
	ready_button.toggled.connect(NetworkManager.set_local_ready)
	room_panel.add_child(ready_button)
	play_button = Style.button("Start drive")
	play_button.pressed.connect(NetworkManager.start_game)
	room_panel.add_child(play_button)


func _add_field(parent: Control, field_name: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var field_label := Style.label(field_name, 15, Style.MUTED)
	field_label.custom_minimum_size.x = 88
	row.add_child(field_label)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.accessibility_name = field_name
	edit.max_length = 24
	edit.custom_minimum_size.y = 38
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _fit_layout() -> void:
	const BASE_WIDTH := 410.0
	var available_width := maxf(size.x - 32.0, 1.0)
	var scale_factor := minf(GameSettings.ui_scale, available_width / BASE_WIDTH)
	var left := minf(72.0, (size.x - BASE_WIDTH * scale_factor) * 0.5)
	scroll.scale = Vector2.ONE * scale_factor
	scroll.position = Vector2(left, 0)
	scroll.size = Vector2(BASE_WIDTH, size.y / scale_factor)


func _create_lobby() -> void:
	if NetworkManager.is_online():
		return
	if NetworkManager.create_lobby(lobby_name_edit.text, player_name_edit.text) == OK:
		_set_status("Lobby created.")
		ready_button.grab_focus()


func _join_lobby() -> void:
	if NetworkManager.is_online() or not NetworkManager.discovered_lobbies.has(selected_address):
		return
	if NetworkManager.join_lobby(selected_address, player_name_edit.text) == OK:
		_set_status("Connecting to lobby…")
		_refresh_room()
		back_button.grab_focus()


func _select_lobby(index: int) -> void:
	selected_address = str(lobby_list.get_item_metadata(index))
	join_button.disabled = false


func _activate_lobby(index: int) -> void:
	_select_lobby(index)
	_join_lobby()


func _refresh_lobbies(force: bool = false) -> void:
	var current: Dictionary = {}
	var addresses := NetworkManager.discovered_lobbies.keys()
	addresses.sort()
	for address in addresses:
		var lobby: Dictionary = NetworkManager.discovered_lobbies[address]
		current[address] = "%s    ·    %d/%d" % [
			str(lobby.get("name", "Lobby")).substr(0, 24),
			lobby.get("players", 0),
			lobby.get("max_players", NetworkManager.MAX_PLAYERS),
		]
	if not force and current == visible_lobbies:
		return
	visible_lobbies = current
	lobby_list.clear()
	var listed_index := -1
	for address in addresses:
		var index := lobby_list.add_item(current[address])
		lobby_list.set_item_metadata(index, address)
		if address == selected_address:
			listed_index = index
	if listed_index >= 0:
		lobby_list.select(listed_index)
		lobby_list.ensure_current_is_visible()
	else:
		selected_address = ""
	join_button.disabled = listed_index < 0
	empty_label.visible = current.is_empty()
	lobby_list.focus_mode = Control.FOCUS_NONE if current.is_empty() else Control.FOCUS_ALL
	lobby_count.text = "%d found" % current.size()


func _refresh_room() -> void:
	var connected := NetworkManager.is_online()
	var changing_view := room_panel.visible != connected
	setup_panel.visible = not connected
	room_panel.visible = connected
	if changing_view:
		scroll.scroll_vertical = 0
	back_button.text = "Leave lobby" if connected else "Back"
	if not connected:
		return

	var pending := NetworkManager.lobby_name.is_empty()
	var host := NetworkManager.is_host
	room_title.text = "Joining lobby…" if pending else NetworkManager.lobby_name
	room_caption.text = "Connecting…" if pending else ("You’re hosting" if host else "Joined via LAN")
	room_count.text = "Players  %d/%d" % [NetworkManager.players.size(), NetworkManager.MAX_PLAYERS]
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()
	var local_id := NetworkManager.multiplayer.get_unique_id() if not pending else 0
	for peer_id in NetworkManager.players:
		_add_player_row(peer_id, NetworkManager.players[peer_id], peer_id == local_id)
	if pending:
		player_list.add_child(Style.caption("Waiting for a response from the host…"))

	var can_ready := NetworkManager.players.has(local_id)
	var is_ready := can_ready and bool(NetworkManager.players[local_id].get("ready", false))
	ready_button.disabled = not can_ready
	ready_button.set_pressed_no_signal(is_ready)
	ready_button.text = "Unready" if is_ready else "Ready"
	play_button.visible = host
	play_button.disabled = not NetworkManager.can_host_start()
	if pending:
		launch_hint.text = "You can ready up when the lobby connects."
	elif host:
		launch_hint.text = "Everyone must be ready before you can start." if play_button.disabled else "Everyone is ready. Start the drive when you’re set."
	else:
		launch_hint.text = "The host can start once everyone is ready."
		_set_status("Connected to the lobby.")


func _add_player_row(peer_id: int, data: Dictionary, is_local: bool) -> void:
	var is_ready := bool(data.get("ready", false))
	var row := HBoxContainer.new()
	player_list.add_child(row)
	var name_text := str(data.get("name", "Player"))
	if is_local:
		name_text += "  (you)"
	var player := Style.label(name_text)
	player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(player)
	if peer_id == 1:
		row.add_child(Style.label("HOST", 12, Style.AMBER))
	row.add_child(Style.label("READY" if is_ready else "NOT READY", 12, Style.GREEN if is_ready else Style.MUTED))


func _set_status(message: String, tint: Color = Style.MUTED) -> void:
	status_label.visible = not message.is_empty()
	status_label.text = message
	status_label.add_theme_color_override("font_color", tint)


func _show_error(message: String) -> void:
	_set_status(message, Style.ALERT)


func _back() -> void:
	if NetworkManager.is_online():
		NetworkManager.leave_lobby()
		_set_status("You left the lobby.")
	else:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
