extends Area3D

const Shapes := preload("res://scripts/prop_shapes.gd")
enum Broadcast { WORKSHOP, FIRST_GARAGE, WAYSIDE, TOWER, LAST_STOP, QUIET, YOU }

const RECORDINGS := [
	preload("res://assets/audio/radio/workshop.wav"),
	preload("res://assets/audio/radio/relay.wav"),
	preload("res://assets/audio/radio/wayside.wav"),
	preload("res://assets/audio/radio/tower.wav"),
	preload("res://assets/audio/radio/last_stop.wav"),
	preload("res://assets/audio/radio/quiet.wav"),
	preload("res://assets/audio/radio/you.wav"),
]
const LINES := [
	[
		[0.485, "County: County desk. Ruth, are you still at the sheds?"],
		[3.734, ""],
		[4.354, "Ruth: Yeah, just locking up. Has Len called?"],
		[6.388, ""],
		[6.958, "Garage operator: He said five minutes. I’ve just put the kettle on."],
		[10.082, ""],
	],
	[
		[0.47, "Garage operator: Ruth? Did Len come your way?"],
		[2.554, ""],
		[3.324, "Ruth: No. Why?"],
		[5.004, ""],
		[5.554, "Garage operator: His van’s out front. Driver’s door’s open."],
		[8.991, ""],
		[9.261, "Garage operator: Hang on. The keys are still in it."],
		[11.299, ""],
	],
	[
		[0.55, "Ruth: County, I can see the relay light from the yard. You getting me?"],
		[3.944, "County: Loud and clear, Ruth."],
		[5.855, ""],
		[6.335, "Mick: County, it’s Mick. Six o’clock. All clear at the east sheds."],
		[10.216, ""],
		[10.491, "Mick: [Coughs]"],
		[11.691, ""],
		[12.526, "Ruth: Oh. I thought he’d gone home."],
		[14.298, ""],
	],
	[
		[0.469, "Garage operator: Sorry, County. You’re coming through now."],
		[2.781, ""],
		[2.901, "County: Mick, if you’re still on, where’d you leave the gate key?"],
		[5.654, ""],
		[8.264, "Mick: County, it’s Mick. Six o’clock. All clear at the east sheds."],
		[12.145, ""],
		[12.42, "Mick: [Coughs]"],
		[13.62, ""],
	],
	[
		[0.48, "County: County desk, for anyone still on the east road."],
		[3.474, ""],
		[3.904, "County: We’re at the house where the pavement runs out. The one on the right."],
		[7.303, ""],
		[7.748, "County: There’s a light on. Kettle’s on if you’re out that way."],
		[10.432, ""],
	],
	[
		[0.5, "County: County desk, evening roll call. Len?"],
		[3.597, ""],
		[5.597, "County: Ruth?"],
		[6.368, ""],
		[7.968, "County: Ruth, are you there? Please."],
		[10.599, ""],
		[11.799, "Ruth: Yeah, just locking up. Has Len called?"],
		[13.833, ""],
		[14.833, "County: Ruth. You said that two days ago."],
		[16.696, ""],
		[18.096, "Ruth: Yeah, just locking up. Has Len called?"],
		[20.131, ""],
	],
	[
		[0.5, "You: County, it’s me."],
		[1.661, ""],
		[2.261, "You: I’m at the house. Everything’s fine."],
		[4.177, ""],
		[4.777, "You: The kettle’s on. You should come out."],
		[6.232, ""],
		[7.432, "Mick: [Coughs]"],
		[8.632, ""],
	],
]

## County's side of things: the call at the workshop, and her answer each time
## you check in from a station. Recorded by Sources/make_voices.py (county).
const COUNTY := {
	"county_intro": "Workshop, this is County desk. Workshop, do you read? Len hasn't checked in since Tuesday. If you can get that car going, drive the east road and check in at every station radio. Find him. County out.",
	"county_reply_1": "Copy, I hear you. That's one. Keep heading east. The next station's a kilometre or so on.",
	"county_reply_2": "Copy. That's two. Still nothing from Len. He always called in at night. Stay out there, find somewhere to sleep, and keep listening.",
	"county_reply_3": "Copy. Keep going. Check in at the next one.",
	"county_reply_4": "Copy. Still no word. Keep listening.",
}
const CHECK_IN_LINE := "County, this is the workshop car. Checking in."

const RADIO_BUS := &"Radio"
const VOICE_VOLUME := 0.0

var broadcast := Broadcast.WORKSHOP
var voice: AudioStreamPlayer3D
var carrier: AudioStreamPlayer3D
var dial: StandardMaterial3D
var listener: Node3D
var caption := ""
var echo: AudioStreamPlayer3D
var echo_at := -1.0
## After the house there is nothing on the radios but an open line, waiting.
var open_line := false
## Checking in: your report, then County's answer, after the broadcast.
var replying := false
var reply_speaker: AudioStreamPlayer3D
var you_speaker: AudioStreamPlayer
var reply_lines: Array = []
var reply_from: Node
const YOUR_VOICE := preload("res://assets/audio/ending/anybody.wav")


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	add_to_group("road_radio")
	var casing := Shapes.material(Color("#343a37"), 0.22)
	var face := Shapes.material(Color("#252726"), 0.03)
	var metal := Shapes.material(Color("#8a8979"), 0.45)
	dial = Shapes.material(Color("#524735"), 0.05)
	dial.emission = Color("#da9e55")
	dial.emission_energy_multiplier = 0.66
	Shapes.box(self, "Case", Vector3(0.38, 0.16, 0.23), Vector3.ZERO, casing)
	Shapes.box(self, "Faceplate", Vector3(0.345, 0.119, 0.018), Vector3(0, 0.002, 0.115), face)
	Shapes.box(self, "FrequencyWindow", Vector3(0.157, 0.027, 0.01), Vector3(-0.062, 0.032, 0.129), dial)
	for tick in range(10):
		Shapes.box(self, "ScaleMark", Vector3(0.003, 0.008 if tick % 3 == 0 else 0.004, 0.003),
			Vector3(-0.126 + tick * 0.014, 0.032, 0.135), metal)
	for line in range(5):
		Shapes.box(self, "SpeakerSlot", Vector3(0.134, 0.003, 0.008), Vector3(-0.073, -0.044 + line * 0.01, 0.128), metal)
	Shapes.cylinder(self, "TuningKnob", Vector3(0.102, 0.007, 0.139), Vector3.BACK, 0.032, 0.026, casing)
	Shapes.cylinder(self, "PowerKnob", Vector3(0.152, -0.029, 0.136), Vector3.BACK, 0.016, 0.025, metal, 12)
	Shapes.tube(self, "Antenna", Vector3(0.142, 0.067, -0.087), Vector3(0.161, 0.459, -0.205), 0.006, metal)
	if broadcast == Broadcast.TOWER:
		Shapes.box(self, "AntennaCoupler", Vector3(0.13, 0.065, 0.12), Vector3(-0.257, -0.035, 0), casing)
		Shapes.tube(self, "Coax", Vector3(-0.26, -0.026, -0.06), Vector3(-0.26, 0.56, -0.091), 0.006, face)
	var hitbox := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.41, 0.185, 0.265)
	hitbox.shape = box
	add_child(hitbox)
	voice = _make_player(RECORDINGS[broadcast], VOICE_VOLUME)
	voice.bus = _radio_bus()
	echo = _make_player(YOUR_VOICE, VOICE_VOLUME + 2.0)
	echo.bus = _radio_bus()
	echo.pitch_scale = 0.94
	carrier = _make_player(_carrier_sound(), -18.0 - broadcast * 0.9)
	voice.finished.connect(_broadcast_over)
	reply_speaker = _make_player(null, VOICE_VOLUME)
	reply_speaker.bus = _radio_bus()
	you_speaker = AudioStreamPlayer.new()
	you_speaker.bus = GameSettings.voice_bus()
	add_child(you_speaker)
	set_process(false)


static func _radio_bus() -> StringName:
	## A bus that makes clean recordings sound like a cheap speaker on a weak
	## signal: no lows or highs, overdriven, slightly honky.
	if AudioServer.get_bus_index(RADIO_BUS) >= 0:
		return RADIO_BUS
	var index := AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, RADIO_BUS)
	AudioServer.set_bus_send(index, AudioServer.get_bus_name(0))
	var low_cut := AudioEffectHighPassFilter.new()
	low_cut.cutoff_hz = 380.0
	low_cut.db = AudioEffectFilter.FILTER_24DB
	AudioServer.add_bus_effect(index, low_cut)
	var honk := AudioEffectEQ6.new()
	honk.set_band_gain_db(2, 5.0)
	honk.set_band_gain_db(3, 3.0)
	AudioServer.add_bus_effect(index, honk)
	var drive := AudioEffectDistortion.new()
	drive.mode = AudioEffectDistortion.MODE_OVERDRIVE
	drive.pre_gain = 6.0
	drive.drive = 0.5
	drive.keep_hf_hz = 2400.0
	drive.post_gain = -7.0
	AudioServer.add_bus_effect(index, drive)
	var high_cut := AudioEffectLowPassFilter.new()
	high_cut.cutoff_hz = 3100.0
	high_cut.resonance = 0.75
	high_cut.db = AudioEffectFilter.FILTER_24DB
	AudioServer.add_bus_effect(index, high_cut)
	var squash := AudioEffectCompressor.new()
	squash.threshold = -18.0
	squash.ratio = 6.0
	squash.gain = 3.0
	AudioServer.add_bus_effect(index, squash)
	return RADIO_BUS


func _make_player(stream: AudioStream, volume: float) -> AudioStreamPlayer3D:
	var speaker := AudioStreamPlayer3D.new()
	speaker.stream = stream
	speaker.volume_db = volume
	speaker.unit_size = 1.6
	speaker.max_distance = 8.0
	add_child(speaker)
	return speaker


func _process(_delta: float) -> void:
	if replying:
		_show_reply()
		return
	if not is_instance_valid(listener) or not listener.can_listen_to_radio(global_position):
		stop_listening()
		return
	if open_line:
		return
	# Reception drifts: now and then the voice sinks under the carrier.
	var elapsed := voice.get_playback_position()
	# Sometimes, under the broadcast, it is your own voice.
	if echo_at > 0.0 and elapsed >= echo_at:
		echo_at = -1.0
		echo.play()
		caption = "[Your voice, faint] ...Anybody there?"
		listener.show_radio_caption(self, caption)
	if echo.playing:
		voice.volume_db = VOICE_VOLUME - 22.0
		return
	var drift := pow(maxf(0.0, sin(elapsed * 0.83 + broadcast) * sin(elapsed * 0.31 + broadcast * 2.0)), 3.0)
	voice.volume_db = VOICE_VOLUME - drift * 9.0 + sin(elapsed * 23.0) * drift * 1.5
	var playback := voice.get_playback_position()
	if playback > RECORDINGS[broadcast].get_length() * 0.6:
		mark_heard(broadcast)
	var captions: Array = LINES[broadcast]
	var line := "Carrier signal…"
	for entry: Array in captions:
		if playback >= entry[0]:
			line = entry[1]
	if line != caption:
		caption = line
		listener.show_radio_caption(self, line)


func toggle_listening(player: Node3D) -> void:
	if listener == player:
		stop_listening()
		return
	listener = player
	dial.emission_enabled = true
	if preload("res://scripts/road_end_house.gd").seen:
		open_line = true
		caption = "[Static. The line is open.]"
		listener.show_radio_caption(self, caption)
		carrier.volume_db = -11.0
		carrier.play()
		set_process(true)
		return
	open_line = false
	carrier.volume_db = -18.0 - broadcast * 0.9
	echo_at = randf_range(9.0, maxf(10.0, RECORDINGS[broadcast].get_length() - 6.0)) if randf() < 0.3 else -1.0
	caption = "Carrier signal…"
	listener.show_radio_caption(self, caption)
	dial.emission_enabled = true
	voice.play()
	carrier.play()
	set_process(true)


static func county_captions(key: String, length: float) -> Array:
	## Sentence by sentence, timed by length across the recording.
	var text: String = COUNTY[key]
	var sentences := []
	for piece in text.replace("? ", "?|").replace(". ", ".|").split("|", false):
		sentences.append(piece)
	var total := 0.0
	for sentence: String in sentences:
		total += sentence.length() + 8.0
	var lines := []
	var at := 0.0
	for sentence: String in sentences:
		lines.append([at, "County: " + sentence])
		at += (sentence.length() + 8.0) / total * length
	return lines


func county_call(key: String, to: Node3D) -> void:
	## County comes over this radio on her own, e.g. the call at the workshop.
	var stream: AudioStream = load("res://assets/audio/radio/%s.wav" % key)
	listener = to
	replying = true
	dial.emission_enabled = true
	carrier.play()
	reply_speaker.stream = stream
	reply_lines = county_captions(key, stream.get_length())
	reply_from = reply_speaker
	reply_speaker.play()
	_after_reply()
	set_process(true)


func _broadcast_over() -> void:
	## After a broadcast you report in, and County answers, once per station.
	var story: Dictionary = preload("res://scripts/road_end_house.gd").story
	var checked: Dictionary = story.get("checked_in", {})
	if not is_instance_valid(listener) or preload("res://scripts/road_end_house.gd").seen or checked.has(str(broadcast)):
		stop_listening()
		return
	checked[str(broadcast)] = true
	story["checked_in"] = checked
	mark_heard(broadcast)
	replying = true
	you_speaker.stream = load("res://assets/audio/radio/you_checkin.wav")
	reply_lines = [[0.0, "You: " + CHECK_IN_LINE]]
	reply_from = you_speaker
	you_speaker.play()
	you_speaker.finished.connect(func() -> void:
		var key := "county_reply_%d" % clampi(checked.size(), 1, 4)
		var stream: AudioStream = load("res://assets/audio/radio/%s.wav" % key)
		reply_lines = county_captions(key, stream.get_length())
		reply_from = reply_speaker
		reply_speaker.stream = stream
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if replying:
				reply_speaker.play()
				_after_reply()), CONNECT_ONE_SHOT)


func _after_reply() -> void:
	if not reply_speaker.finished.is_connected(_reply_over):
		reply_speaker.finished.connect(_reply_over, CONNECT_ONE_SHOT)


func _show_reply() -> void:
	if not is_instance_valid(listener):
		return
	var line := "[Static]"
	if reply_from and reply_from.playing:
		var at: float = reply_from.get_playback_position()
		for entry: Array in reply_lines:
			if at >= entry[0]:
				line = entry[1]
	if line != caption:
		caption = line
		listener.show_radio_caption(self, line)


func _reply_over() -> void:
	replying = false
	stop_listening()


func answer(player: Node3D) -> void:
	## After the house: pick up the mic. See replaced_ending.gd.
	var ending: Node = preload("res://scripts/replaced_ending.gd").new()
	ending.name = "ReplacedEnding"
	get_tree().current_scene.add_child(ending)
	ending.start(player, self)


func stop_listening() -> void:
	set_process(false)
	if is_instance_valid(listener):
		listener.clear_radio_caption(self)
	listener = null
	caption = ""
	open_line = false
	replying = false
	reply_speaker.stop()
	you_speaker.stop()
	# Drop anything still waiting on a reply that will not come now.
	for connection: Dictionary in you_speaker.finished.get_connections():
		you_speaker.finished.disconnect(connection["callable"])
	if reply_speaker.finished.is_connected(_reply_over):
		reply_speaker.finished.disconnect(_reply_over)
	voice.stop()
	carrier.stop()
	echo.stop()
	dial.emission_enabled = false


func _exit_tree() -> void:
	if is_instance_valid(listener):
		listener.clear_radio_caption(self)


static func mark_heard(which: int) -> void:
	## Remembered with the trip: the road ends only after it has been listened to.
	var story: Dictionary = preload("res://scripts/road_end_house.gd").story
	var heard: Dictionary = story.get("heard", {})
	if heard.has(str(which)):
		return
	heard[str(which)] = true
	story["heard"] = heard
	# In co-op the host decides when the road ends (told once per broadcast).
	NetworkManager.report_heard(which)


static var carrier_cache: AudioStreamWAV


func _carrier_sound() -> AudioStreamWAV:
	## Made once and shared by every radio: building it is slow in script.
	if carrier_cache == null:
		carrier_cache = _make_carrier()
	return carrier_cache


static func _make_carrier() -> AudioStreamWAV:
	var samples := PackedByteArray()
	var rate := 12000
	samples.resize(rate * 3 * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6109
	var smooth_noise := 0.0
	for index in range(rate * 3):
		var elapsed := index / float(rate)
		smooth_noise = lerpf(smooth_noise, rng.randf_range(-1, 1), 0.14)
		var edge := minf(smoothstep(0, 0.16, elapsed), smoothstep(3.0, 2.84, elapsed))
		var flutter := 0.38 + 0.62 * pow(absf(sin(elapsed * TAU * 0.72)), 5)
		var sample := (smooth_noise * flutter + sin(elapsed * TAU * 137.0) * 0.035) * edge
		samples.encode_s16(index * 2, int(sample * 23000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = rate * 3
	stream.data = samples
	return stream
