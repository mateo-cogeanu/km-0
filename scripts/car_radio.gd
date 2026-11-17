extends Area3D
## The radio in whatever you are driving (T to switch it on and off). It picks
## up the broadcast for the stretch of road you have reached; after the house,
## it is you reporting in. An Area3D only so it can share the radio captions.

const RoadRadio := preload("res://scripts/road_radio.gd")
const RoadEndHouse := preload("res://scripts/road_end_house.gd")

var player: Node3D
var voice: AudioStreamPlayer
var carrier: AudioStreamPlayer
var on := false
var playing := 0
var caption := ""
var wait := 0.0
var furthest := 0.0


func setup(owner_player: Node3D) -> void:
	player = owner_player
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false
	voice = AudioStreamPlayer.new()
	voice.bus = RoadRadio._radio_bus()
	voice.volume_db = RoadRadio.VOICE_VOLUME - 1.0
	add_child(voice)
	carrier = AudioStreamPlayer.new()
	var tuner := RoadRadio.new()
	carrier.stream = tuner._carrier_sound()
	tuner.free()
	carrier.volume_db = -20.0
	add_child(carrier)
	voice.finished.connect(func() -> void:
		wait = randf_range(14.0, 26.0)
		_show(""))


func toggle() -> void:
	on = not on
	if on:
		carrier.play()
		wait = 1.2
		_show("Carrier signal…")
	else:
		voice.stop()
		carrier.stop()
		player.clear_radio_caption(self)


## The same calls the player makes on a station radio, so either can be the one
## you are listening to.
func stop_listening() -> void:
	if on:
		toggle()


func toggle_listening(_player: Node3D) -> void:
	toggle()


func _pick() -> int:
	## The broadcast for how far down the road you have got.
	if RoadEndHouse.seen:
		return RoadRadio.Broadcast.YOU
	var behind_start := player.global_position.z > 400.0
	if behind_start:
		# Out past the workshop the only thing still coming through is Ruth.
		return RoadRadio.Broadcast.QUIET
	var travelled := furthest
	if travelled < 1300.0:
		return RoadRadio.Broadcast.FIRST_GARAGE
	if travelled < 2400.0:
		return RoadRadio.Broadcast.WAYSIDE
	if travelled < 3300.0:
		return RoadRadio.Broadcast.TOWER
	if travelled < 4300.0:
		return RoadRadio.Broadcast.QUIET
	return RoadRadio.Broadcast.LAST_STOP


func _process(delta: float) -> void:
	if player == null:
		return
	furthest = maxf(furthest, -player.global_position.z)
	if on and not is_instance_valid(player.active_vehicle):
		toggle()
	if not on:
		return
	if not voice.playing:
		wait -= delta
		if wait <= 0.0:
			playing = _pick()
			voice.stream = RoadRadio.RECORDINGS[playing]
			voice.play()
		return
	var at := voice.get_playback_position()
	if at > RoadRadio.RECORDINGS[playing].get_length() * 0.6:
		RoadRadio.mark_heard(playing)
	var line := "Carrier signal…"
	for entry: Array in RoadRadio.LINES[playing]:
		if at >= entry[0]:
			line = entry[1]
	_show(line)


func _show(line: String) -> void:
	if line != caption:
		caption = line
		player.show_radio_caption(self, line)
