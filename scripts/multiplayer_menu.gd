extends Control
## Multiplayer: find or host a game on the local network, then the lobby,
## where the host picks the story and everyone readies up.

const Style := preload("res://scripts/menu_style.gd")
const WIDTH := 520.0
const STORY_BLURBS := {
	"road": "KM0’s desert road, together: a car for every four of you, the workshop, the stations and the radio. Engines take two to lift; alone you can only drag one along the ground.",
	"salvage": "A separate co-op story: strip cars in a flooded town for a scrap buyer before the water rises. Something in the water hunts by sound.",
}

var screen: Dictionary
var content: VBoxContainer
var setup_panel: VBoxContainer
var room_panel: VBoxContainer
var lobby_list: ItemList
var empty_label: Label
var lobby_count: Label
var join_button: Button
var address_edit: LineEdit
var address_join: Button
var lobby_name_edit: LineEdit
var create_button: Button
var room_title: Label
var room_caption: Label
var room_count: Label
var player_list: VBoxContainer
var story_buttons := {}
var story_blurb: Label
var launch_hint: Label
var ready_button: Button
var play_button: Button
var status_label: Label
var back_button: Button
var selected_address := ""
var visible_lobbies: Dictionary = {}
var searching_dots := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = Style.make_theme()
	_build_ui()
	NetworkManager.lobby_list_changed.connect(_refresh_lobbies)
	NetworkManager.lobby_state_changed.connect(_refresh_room)
	NetworkManager.connection_failed.connect(_show_error)
	resized.connect(_fit_layout)
	GameSettings.settings_changed.connect(_fit_layout)
	_fit_layout()
	_refresh_lobbies(true)
	_refresh_room()
	_focus_default.call_deferred()


func _exit_tree() -> void:
	if NetworkManager.is_online() and not NetworkManager.game_in_progress:
		NetworkManager.leave_lobby()


func _process(delta: float) -> void:
	# A sign of life while the list is empty: it is still looking.
	if setup_panel.visible and visible_lobbies.is_empty():
		searching_dots = fmod(searching_dots + delta * 2.0, 4.0)
		empty_label.text = "Looking for games on your network" + ".".repeat(int(searching_dots))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.35)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen = Style.screen(self, WIDTH)
	content = screen["content"]
	content.add_child(Style.heading("Multiplayer", Style.H1))
	_build_browser()
	_build_room()
	content.add_child(Style.divider())
	status_label = Style.caption("")
	status_label.hide()
	content.add_child(status_label)
	back_button = Style.quiet("Back")
	back_button.pressed.connect(_back)
	content.add_child(back_button)


func _build_browser() -> void:
	setup_panel = Style.vbox(Style.GAP_M)
	content.add_child(setup_panel)
	setup_panel.add_child(Style.caption("Playing as %s. You can change your name in Settings." % GameSettings.player_name))

	var header := Style.hbox(Style.GAP_S)
	setup_panel.add_child(header)
	var join_title := Style.section("Join a game")
	join_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(join_title)
	lobby_count = Style.label("", Style.SMALL, Style.FAINT)
	header.add_child(lobby_count)

	var list_area := Control.new()
	list_area.custom_minimum_size.y = 150
	setup_panel.add_child(list_area)
	lobby_list = ItemList.new()
	lobby_list.item_selected.connect(_select_lobby)
	lobby_list.item_activated.connect(_activate_lobby)
	lobby_list.accessibility_name = "Games on your network"
	list_area.add_child(lobby_list)
	lobby_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_label = Style.caption("")
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	list_area.add_child(empty_label)
	empty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty_label.offset_left = 12.0
	empty_label.offset_right = -12.0

	join_button = Style.primary("Join game")
	join_button.disabled = true
	join_button.pressed.connect(_join_lobby)
	setup_panel.add_child(join_button)

	# Not listed (another network, or broadcasts blocked): type the address
	# the host's lobby shows.
	setup_panel.add_child(Style.caption("Not listed? Type the address shown in the host’s lobby."))
	var address_row := Style.hbox(Style.GAP_S)
	setup_panel.add_child(address_row)
	address_edit = _field("Host address, e.g. 192.168.1.20", 64)
	address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_edit.text_submitted.connect(func(_value: String) -> void: _join_address())
	address_edit.text_changed.connect(func(value: String) -> void: address_join.disabled = value.strip_edges().is_empty())
	address_row.add_child(address_edit)
	address_join = Style.button("Join")
	address_join.alignment = HORIZONTAL_ALIGNMENT_CENTER
	address_join.custom_minimum_size.x = 96
	address_join.disabled = true
	address_join.pressed.connect(_join_address)
	address_row.add_child(address_join)

	setup_panel.add_child(Style.spacer(Style.GAP_S))
	setup_panel.add_child(Style.section("Host a game"))
	var host_row := Style.hbox(Style.GAP_S)
	setup_panel.add_child(host_row)
	lobby_name_edit = _field("Lobby name, e.g. Road Trip", 24)
	lobby_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_name_edit.text_submitted.connect(func(_value: String) -> void: _create_lobby())
	host_row.add_child(lobby_name_edit)
	create_button = Style.button("Create")
	create_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	create_button.custom_minimum_size.x = 96
	create_button.pressed.connect(_create_lobby)
	host_row.add_child(create_button)


func _build_room() -> void:
	room_panel = Style.vbox(Style.GAP_M)
	room_panel.hide()
	content.add_child(room_panel)
	room_title = Style.label("", Style.H2 + 4)
	room_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	room_panel.add_child(room_title)
	room_caption = Style.caption("")
	room_panel.add_child(room_caption)

	var players_header := Style.hbox(Style.GAP_S)
	room_panel.add_child(players_header)
	var players_title := Style.section("Players")
	players_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_header.add_child(players_title)
	room_count = Style.label("", Style.SMALL, Style.FAINT)
	players_header.add_child(room_count)
	player_list = Style.vbox(Style.GAP_XS)
	room_panel.add_child(player_list)

	room_panel.add_child(Style.spacer(Style.GAP_XS))
	room_panel.add_child(Style.section("Story"))
	var story_row := Style.hbox(Style.GAP_S)
	room_panel.add_child(story_row)
	var group := ButtonGroup.new()
	for story_name in ["road", "salvage"]:
		var pick := Style.button(NetworkManager.STORY_NAMES[story_name])
		pick.toggle_mode = true
		pick.button_group = group
		pick.alignment = HORIZONTAL_ALIGNMENT_CENTER
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.pressed.connect(NetworkManager.set_lobby_story.bind(story_name))
		story_row.add_child(pick)
		story_buttons[story_name] = pick
	story_blurb = Style.caption("")
	room_panel.add_child(story_blurb)

	room_panel.add_child(Style.spacer(Style.GAP_XS))
	launch_hint = Style.caption("")
	room_panel.add_child(launch_hint)
	ready_button = Style.button("Ready up")
	ready_button.toggle_mode = true
	ready_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_button.toggled.connect(func(on: bool) -> void:
		ready_button.text = "I’m ready" if on else "Ready up"
		NetworkManager.set_local_ready(on))
	room_panel.add_child(ready_button)
	play_button = Style.primary("Start")
	play_button.pressed.connect(func() -> void: NetworkManager.start_game())
	room_panel.add_child(play_button)


func _field(placeholder: String, length: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.accessibility_name = placeholder
	edit.max_length = length
	edit.custom_minimum_size.y = Style.BUTTON_HEIGHT
	return edit


func _fit_layout() -> void:
	Style.fit_screen(screen, size, true)


func _focus_default() -> void:
	if room_panel.visible:
		(play_button if play_button.visible and not play_button.disabled else ready_button).grab_focus()
	elif lobby_list.item_count > 0:
		join_button.grab_focus()
	else:
		lobby_name_edit.grab_focus()
	# The screen opens at its top, title and all.
	await get_tree().process_frame
	(screen["scroll"] as ScrollContainer).scroll_vertical = 0


func _create_lobby() -> void:
	if NetworkManager.is_online():
		return
	if NetworkManager.create_lobby(lobby_name_edit.text, GameSettings.player_name) == OK:
		_set_status("Lobby created. Friends on your network will see it in their list.", Style.GREEN)
		_focus_default.call_deferred()


func _join_lobby() -> void:
	if NetworkManager.is_online() or not NetworkManager.discovered_lobbies.has(selected_address):
		return
	_connect_to(str(NetworkManager.discovered_lobbies[selected_address].get("address", "")))


func _join_address() -> void:
	if NetworkManager.is_online():
		return
	_connect_to(address_edit.text)


func _connect_to(address: String) -> void:
	if NetworkManager.join_lobby(address, GameSettings.player_name) == OK:
		_set_status("Connecting to %s…" % address.strip_edges())
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
	var keys := NetworkManager.discovered_lobbies.keys()
	keys.sort()
	for key in keys:
		var lobby: Dictionary = NetworkManager.discovered_lobbies[key]
		current[key] = "%s   ·   %s   ·   %d/%d" % [
			str(lobby.get("name", "Lobby")).substr(0, 24),
			NetworkManager.STORY_NAMES.get(str(lobby.get("story", "road")), "The Drive"),
			lobby.get("players", 0),
			lobby.get("max_players", NetworkManager.MAX_PLAYERS),
		]
	if not force and current == visible_lobbies:
		return
	var had_none := visible_lobbies.is_empty()
	visible_lobbies = current
	lobby_list.clear()
	var listed_index := -1
	for key in keys:
		var index := lobby_list.add_item(current[key])
		lobby_list.set_item_metadata(index, key)
		if key == selected_address:
			listed_index = index
	# The first game to turn up is picked for you.
	if listed_index < 0 and lobby_list.item_count > 0:
		listed_index = 0
		selected_address = str(lobby_list.get_item_metadata(0))
	if listed_index >= 0:
		lobby_list.select(listed_index)
		lobby_list.ensure_current_is_visible()
	else:
		selected_address = ""
	join_button.disabled = listed_index < 0
	empty_label.visible = current.is_empty()
	lobby_list.focus_mode = Control.FOCUS_NONE if current.is_empty() else Control.FOCUS_ALL
	lobby_count.text = "" if current.is_empty() else ("1 game" if current.size() == 1 else "%d games" % current.size())
	if had_none and not current.is_empty() and setup_panel.visible and not (lobby_name_edit.has_focus() or address_edit.has_focus()):
		join_button.grab_focus()


func _refresh_room() -> void:
	var connected := NetworkManager.is_online()
	var changing_view := room_panel.visible != connected
	setup_panel.visible = not connected
	room_panel.visible = connected
	if changing_view:
		(screen["scroll"] as ScrollContainer).scroll_vertical = 0
	back_button.text = "Leave lobby" if connected else "Back"
	if not connected:
		if changing_view:
			_focus_default.call_deferred()
		return

	var pending := NetworkManager.lobby_name.is_empty()
	var host := NetworkManager.is_host
	room_title.text = "Joining…" if pending else NetworkManager.lobby_name
	var addresses := NetworkManager.local_addresses()
	if pending:
		room_caption.text = "Waiting for the host to answer."
	elif host:
		room_caption.text = ("You’re hosting. Friends on another network can join at %s." % ", ".join(addresses)) if not addresses.is_empty() else "You’re hosting."
	else:
		room_caption.text = "You’ve joined this lobby."
	room_count.text = "%d of %d" % [NetworkManager.players.size(), NetworkManager.MAX_PLAYERS]
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()
	var local_id := NetworkManager.multiplayer.get_unique_id() if not pending else 0
	for peer_id in NetworkManager.players:
		_add_player_row(peer_id, NetworkManager.players[peer_id], peer_id == local_id)

	var can_ready := NetworkManager.players.has(local_id)
	var is_ready := can_ready and bool(NetworkManager.players[local_id].get("ready", false))
	ready_button.disabled = not can_ready
	ready_button.set_pressed_no_signal(is_ready)
	ready_button.text = "I’m ready" if is_ready else "Ready up"
	var chosen := NetworkManager.lobby_story
	for story_name in story_buttons:
		var pick: Button = story_buttons[story_name]
		pick.set_pressed_no_signal(story_name == chosen)
		# Only the host chooses; everyone else sees the choice.
		pick.disabled = not host or pending
		pick.focus_mode = Control.FOCUS_ALL if host else Control.FOCUS_NONE
	story_blurb.text = STORY_BLURBS.get(chosen, "") + ("" if host else "  The host picks the story.")
	play_button.visible = host
	play_button.disabled = not NetworkManager.can_host_start()
	play_button.text = "Start %s" % NetworkManager.STORY_NAMES.get(chosen, "the game")
	if pending:
		launch_hint.text = "You can ready up once you’re in."
	elif host:
		launch_hint.text = "Everyone, you included, must be ready before you can start." if play_button.disabled else "Everyone is ready."
	else:
		launch_hint.text = "The host starts once everyone is ready."
		_set_status("")
	if changing_view:
		_focus_default.call_deferred()


func _add_player_row(peer_id: int, data: Dictionary, is_local: bool) -> void:
	var is_ready := bool(data.get("ready", false))
	var line := PanelContainer.new()
	line.add_theme_stylebox_override("panel", Style.box(Style.RAISED, Style.LINE, 10, 1, 6))
	player_list.add_child(line)
	var row := Style.hbox(Style.GAP_S)
	line.add_child(row)
	var player := Style.label(str(data.get("name", "Player")) + ("  (you)" if is_local else ""))
	player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(player)
	if peer_id == 1:
		row.add_child(_chip("Host", Style.AMBER))
	row.add_child(_chip("Ready" if is_ready else "Not ready", Style.GREEN if is_ready else Style.FAINT))
	if NetworkManager.is_host and peer_id != 1:
		var kick := Style.quiet("Remove")
		kick.custom_minimum_size = Vector2(0, 34)
		kick.add_theme_font_size_override("font_size", Style.SMALL)
		kick.pressed.connect(NetworkManager.kick_player.bind(peer_id))
		row.add_child(kick)


func _chip(text: String, tint: Color) -> Label:
	var chip := Style.label(text, Style.SMALL, tint)
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.custom_minimum_size.y = 34
	return chip


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
