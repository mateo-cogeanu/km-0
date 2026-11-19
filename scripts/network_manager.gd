extends Node

signal lobby_list_changed
signal lobby_state_changed
signal connection_failed(message: String)
signal game_start_requested
signal player_disconnected(peer_id: int)

const GAME_PORT := 24680
const DISCOVERY_PORT := 24681
## Several copies of the game on one computer can't all listen on one port:
## each listens on the first free one of these, and hosts announce to all.
const DISCOVERY_PORT_COUNT := 8
const JOIN_TIMEOUT := 10.0
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
## Tells this lobby's announcements apart when they arrive by several routes.
var _lobby_token := ""
var _join_address := ""
var _join_clock := -1.0


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
	if _join_clock >= 0.0:
		_join_clock += delta
		if _join_clock > JOIN_TIMEOUT:
			var address := _join_address
			leave_lobby()
			connection_failed.emit("Couldn’t reach the lobby at %s. Check you’re both on the same network, and that the host’s firewall lets KM0 accept incoming connections." % address)
	if is_host and is_online() and not game_in_progress:
		_broadcast_elapsed += delta
		if _broadcast_elapsed >= BROADCAST_INTERVAL:
			_broadcast_elapsed = 0.0
			_broadcast_lobby()


func _setup_discovery() -> void:
	for offset in DISCOVERY_PORT_COUNT:
		if _discovery_listener.bind(DISCOVERY_PORT + offset) == OK:
			break
	if not _discovery_listener.is_bound():
		push_warning("LAN lobby discovery could not listen on ports %d-%d." % [DISCOVERY_PORT, DISCOVERY_PORT + DISCOVERY_PORT_COUNT - 1])
	_discovery_broadcaster.set_broadcast_enabled(true)


static func local_addresses() -> PackedStringArray:
	## This computer's addresses on its local networks (IPv4), for showing the
	## host's address and for announcing lobbies on each network.
	var found := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") != 3 or address.begins_with("127.") or address.begins_with("169.254."):
			continue
		found.append(address)
	return found


func create_lobby(new_lobby_name: String, player_name: String) -> Error:
	leave_lobby()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(GAME_PORT, MAX_PLAYERS - 1, 4)
	if error != OK:
		if error == ERR_CANT_CREATE or error == ERR_ALREADY_IN_USE:
			connection_failed.emit("Couldn’t host: another lobby is already running on this computer. Join it from the list instead.")
		else:
			connection_failed.emit("Couldn’t create the lobby (error %s)." % error)
		return error
	is_host = true
	_lobby_token = "%d-%d" % [Time.get_ticks_usec(), randi()]
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
	address = address.strip_edges()
	if address.is_empty():
		connection_failed.emit("Type the host’s address first.")
		return ERR_INVALID_PARAMETER
	if not address.is_valid_ip_address():
		var resolved := IP.resolve_hostname(address, IP.TYPE_IPV4)
		if resolved.is_empty():
			connection_failed.emit("Couldn’t find a computer called “%s”." % address)
			return ERR_CANT_RESOLVE
		address = resolved
	var error := peer.create_client(address, GAME_PORT, 4)
	if error != OK:
		connection_failed.emit("Couldn’t connect to that lobby (error %s)." % error)
		return error
	is_host = false
	_join_address = address
	_join_clock = 0.0
	local_player_name = _clean_name(player_name, "Player")
	multiplayer.multiplayer_peer = peer
	return OK


func leave_lobby() -> void:
	if is_online():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	_join_clock = -1.0
	game_in_progress = false
	trip_started = false
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
	arrived.clear()
	trip_started = false
	# A fresh shared trip: nothing carried over from earlier solo play on any
	# one machine, so everyone starts the story in the same place.
	var house_script: GDScript = load("res://scripts/road_end_house.gd")
	house_script.story = {}
	house_script.seen = false
	(load("res://scripts/story_notes.gd") as GDScript).read = {}
	story = story_name if STORY_SCENES.has(story_name) else "road"
	game_start_requested.emit()
	get_tree().change_scene_to_file(STORY_SCENES[story])


func salvage() -> bool:
	return story == "salvage"


# --- In the game: everyone loaded, and the story kept by the host ----------------

## Peers whose game scene is up (host only).
var arrived := {}
## The host has started the trip; anyone arriving after that is caught up.
var trip_started := false
signal everyone_arrived
signal arrived_late(peer_id: int)


func report_arrived() -> void:
	## Called by a guest's game scene once its players exist.
	if is_online() and not is_host:
		_arrived.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _arrived() -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	arrived[sender] = true
	if trip_started:
		arrived_late.emit(sender)
	elif all_arrived():
		everyone_arrived.emit()


func all_arrived() -> bool:
	for peer_id in players:
		if peer_id != 1 and not arrived.has(peer_id):
			return false
	return true


func report_heard(which: int) -> void:
	## A guest heard a broadcast on a radio: the host keeps the story.
	if is_online() and not is_host:
		_heard.rpc_id(1, which)


@rpc("any_peer", "call_remote", "reliable")
func _heard(which: int) -> void:
	if is_host:
		var story_data: Dictionary = (load("res://scripts/road_end_house.gd") as GDScript).story
		var heard: Dictionary = story_data.get("heard", {})
		heard[str(which)] = true
		story_data["heard"] = heard


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
	_join_clock = -1.0
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
		"token": _lobby_token,
		"story": lobby_story,
	}
	var bytes := JSON.stringify(packet).to_utf8_buffer()
	# Everywhere a player might be listening: the whole network, each local
	# network's own broadcast address (macOS often drops 255.255.255.255), and
	# this computer, on every discovery port.
	var targets := PackedStringArray(["255.255.255.255", "127.0.0.1"])
	for address in local_addresses():
		var parts := address.split(".")
		targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	for target in targets:
		for offset in DISCOVERY_PORT_COUNT:
			_discovery_broadcaster.set_dest_address(target, DISCOVERY_PORT + offset)
			_discovery_broadcaster.put_packet(bytes)


func _read_discovery_packets() -> void:
	while _discovery_listener.get_available_packet_count() > 0:
		var packet := _discovery_listener.get_packet()
		var sender_ip := _discovery_listener.get_packet_ip()
		var data = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(data) != TYPE_DICTIONARY or not data.get("km0_lobby", false):
			continue
		if is_host or data.get("version") != ProjectSettings.get_setting("application/config/version"):
			continue
		# The same lobby arrives by several routes: list it once, by the
		# address that reaches it most directly (this computer, if it's here).
		var token := str(data.get("token", sender_ip))
		var known: Dictionary = discovered_lobbies.get(token, {})
		var address := sender_ip
		if not known.is_empty() and str(known.get("address", "")).begins_with("127.") and not sender_ip.begins_with("127."):
			address = str(known["address"])
		var fresh: bool = known.is_empty() or known.get("address") != address or known.get("players") != data.get("players") \
			or known.get("name") != data.get("name") or known.get("story") != data.get("story")
		data["address"] = address
		data["last_seen"] = Time.get_ticks_msec() / 1000.0
		discovered_lobbies[token] = data
		if fresh:
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
