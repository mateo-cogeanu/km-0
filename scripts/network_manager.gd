extends Node

signal lobby_list_changed
signal lobby_state_changed
signal connection_failed(message: String)
signal game_start_requested
signal player_disconnected(peer_id: int)

const GAME_PORT := 24680
const DISCOVERY_PORT := 24681
const BROADCAST_INTERVAL := 1.0
const LOBBY_TIMEOUT := 3.5
const MAX_PLAYERS := 8

var is_host := false
var lobby_name := ""
var local_player_name := "Player"
var players: Dictionary = {}
var discovered_lobbies: Dictionary = {}
var game_in_progress := false
var kicked_peers: Dictionary = {}
## Which story the session plays: "road" (KM0) or "salvage" (the co-op
## Salvage Run in the flooded town).
var story := "road"
## The story the host has picked in the lobby, shown to everyone there.
var lobby_story := "road"
const STORY_NAMES := {"road": "The Drive", "salvage": "The Salvage Run"}
const STORY_SCENES := {"road": "res://scenes/main.tscn", "salvage": "res://scenes/salvage.tscn"}

var _discovery_listener := PacketPeerUDP.new()
var _discovery_broadcaster := PacketPeerUDP.new()
var _broadcast_elapsed := 0.0


func _ready() -> void:
	_setup_discovery()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	_read_discovery_packets()
	_expire_lobbies()
	if is_host and is_online() and not game_in_progress:
		_broadcast_elapsed += delta
		if _broadcast_elapsed >= BROADCAST_INTERVAL:
			_broadcast_elapsed = 0.0
			_broadcast_lobby()


func _setup_discovery() -> void:
	var error := _discovery_listener.bind(DISCOVERY_PORT)
	if error != OK:
		push_warning("LAN lobby discovery could not listen on port %d." % DISCOVERY_PORT)
	_discovery_broadcaster.set_broadcast_enabled(true)
	_discovery_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)


func create_lobby(new_lobby_name: String, player_name: String) -> Error:
	leave_lobby()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(GAME_PORT, MAX_PLAYERS - 1, 4)
	if error != OK:
		connection_failed.emit("Could not create lobby (error %s)." % error)
		return error
	is_host = true
	lobby_name = _clean_name(new_lobby_name, "Lobby")
	local_player_name = _clean_name(player_name, "Host")
	players = {1: {"name": local_player_name, "ready": false}}
	multiplayer.multiplayer_peer = peer
	_broadcast_lobby()
	lobby_state_changed.emit()
	return OK


func join_lobby(address: String, player_name: String) -> Error:
	leave_lobby()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, GAME_PORT, 4)
	if error != OK:
		connection_failed.emit("Could not connect to that lobby (error %s)." % error)
		return error
	is_host = false
	local_player_name = _clean_name(player_name, "Player")
	multiplayer.multiplayer_peer = peer
	return OK


func leave_lobby() -> void:
	if is_online():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	game_in_progress = false
	story = "road"
	lobby_story = "road"
	kicked_peers.clear()
	lobby_name = ""
	players.clear()
	lobby_state_changed.emit()


func is_online() -> bool:
	# Godot uses an OfflineMultiplayerPeer in single-player, so a null check
	# incorrectly reports that an offline game is connected to multiplayer.
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


func set_local_ready(ready: bool) -> void:
	var peer_id := multiplayer.get_unique_id()
	if is_host:
		_set_player_ready(peer_id, ready)
	else:
		set_ready_on_server.rpc_id(1, ready)


func can_host_start() -> bool:
	if not is_host or game_in_progress or players.is_empty():
		return false
	for peer_id in multiplayer.get_peers():
		if not players.has(peer_id):
			return false
	for data in players.values():
		if not bool(data.get("ready", false)):
			return false
	return true


func set_lobby_story(story_name: String) -> void:
	## The host picks what the lobby will play. Everyone else has to ready up
	## again, so nobody is started into a story they didn't see chosen.
	if not is_host or game_in_progress or not STORY_SCENES.has(story_name) or story_name == lobby_story:
		return
	lobby_story = story_name
	for peer_id in players:
		if peer_id != 1:
			players[peer_id]["ready"] = false
	_sync_lobby_state()


func start_game(story_name := "") -> void:
	if not can_host_start():
		return
	if story_name.is_empty():
		story_name = lobby_story
	multiplayer.multiplayer_peer.refuse_new_connections = true
	begin_game.rpc(players.duplicate(true), story_name)


@rpc("authority", "call_local", "reliable")
func begin_game(roster: Dictionary, story_name := "road") -> void:
	players = roster
	game_in_progress = true
	story = story_name if STORY_SCENES.has(story_name) else "road"
	game_start_requested.emit()
	get_tree().change_scene_to_file(STORY_SCENES[story])


func salvage() -> bool:
	return story == "salvage"


@rpc("any_peer", "call_remote", "reliable")
func register_player(player_name: String) -> void:
	if not is_host or game_in_progress:
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender) or kicked_peers.has(sender):
		return
	players[sender] = {"name": _clean_name(player_name, "Player"), "ready": false}
	_sync_lobby_state()


@rpc("any_peer", "call_remote", "reliable")
func set_ready_on_server(ready: bool) -> void:
	if not is_host:
		return
	_set_player_ready(multiplayer.get_remote_sender_id(), ready)


@rpc("authority", "call_remote", "reliable")
func receive_lobby_state(server_lobby_name: String, server_players: Dictionary, server_story: String) -> void:
	lobby_name = server_lobby_name
	players = server_players
	lobby_story = server_story if STORY_SCENES.has(server_story) else "road"
	lobby_state_changed.emit()


func _set_player_ready(peer_id: int, ready: bool) -> void:
	if game_in_progress or not players.has(peer_id):
		return
	players[peer_id]["ready"] = ready
	_sync_lobby_state()


func _sync_lobby_state() -> void:
	lobby_state_changed.emit()
	if is_host:
		for peer_id in multiplayer.get_peers():
			if not kicked_peers.has(peer_id):
				receive_lobby_state.rpc_id(peer_id, lobby_name, players, lobby_story)
		_broadcast_lobby()


func _on_peer_connected(_peer_id: int) -> void:
	if is_host and not game_in_progress:
		_sync_lobby_state()


func _on_connected_to_server() -> void:
	register_player.rpc_id(1, local_player_name)


func _on_peer_disconnected(peer_id: int) -> void:
	kicked_peers.erase(peer_id)
	if not players.erase(peer_id):
		return
	if game_in_progress:
		player_disconnected.emit(peer_id)
	elif is_host:
		_sync_lobby_state()


func _on_connection_failed() -> void:
	connection_failed.emit("Connection to the lobby failed.")
	leave_lobby()


func _on_server_disconnected() -> void:
	var was_playing := game_in_progress
	connection_failed.emit("The lobby host disconnected.")
	leave_lobby()
	if was_playing:
		get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _broadcast_lobby() -> void:
	var packet := {
		"km0_lobby": true,
		"version": ProjectSettings.get_setting("application/config/version"),
		"name": lobby_name,
		"players": players.size(),
		"max_players": MAX_PLAYERS,
	}
	_discovery_broadcaster.put_packet(JSON.stringify(packet).to_utf8_buffer())


func _read_discovery_packets() -> void:
	while _discovery_listener.get_available_packet_count() > 0:
		var packet := _discovery_listener.get_packet()
		var sender_ip := _discovery_listener.get_packet_ip()
		var data = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY or not data.get("km0_lobby", false):
			continue
		if is_host or data.get("version") != ProjectSettings.get_setting("application/config/version"):
			continue
		data["address"] = sender_ip
		data["last_seen"] = Time.get_ticks_msec() / 1000.0
		discovered_lobbies[sender_ip] = data
		lobby_list_changed.emit()


func _expire_lobbies() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var changed := false
	for address in discovered_lobbies.keys():
		if now - float(discovered_lobbies[address].get("last_seen", 0.0)) > LOBBY_TIMEOUT:
			discovered_lobbies.erase(address)
			changed = true
	if changed:
		lobby_list_changed.emit()


func _clean_name(value: String, fallback: String) -> String:
	var cleaned := value.strip_edges().substr(0, 24)
	return fallback if cleaned.is_empty() else cleaned


func kick_player(peer_id: int) -> void:
	if not is_host or game_in_progress or peer_id == 1 or not players.has(peer_id):
		return
	kicked_peers[peer_id] = true
	players.erase(peer_id)
	var connection := multiplayer.multiplayer_peer
	removed_from_lobby.rpc_id(peer_id)
	_sync_lobby_state()
	# Give the reliable reason a chance to leave before enforcing the disconnect.
	await get_tree().create_timer(0.25).timeout
	if multiplayer.multiplayer_peer == connection and multiplayer.get_peers().has(peer_id):
		connection.disconnect_peer(peer_id)


@rpc("authority", "call_remote", "reliable")
func removed_from_lobby() -> void:
	leave_lobby()
	connection_failed.emit("The host removed you from the lobby.")
