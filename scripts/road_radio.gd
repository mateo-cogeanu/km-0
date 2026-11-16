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
		[3.213, ""],
		[3.833, "Ruth: Yeah, just locking up. Has Len called?"],
		[5.942, ""],
		[6.512, "Garage operator: He said five minutes. I’ve just put the kettle on."],
		[9.635, ""],
	],
	[
		[0.47, "Garage operator: Ruth? Did Len come your way?"],
		[2.554, ""],
		[3.324, "Ruth: No. Why?"],
		[5.499, ""],
		[6.049, "Garage operator: His van’s out front. Driver’s door’s open."],
		[8.805, ""],
		[9.075, "Garage operator: Hang on. The keys are still in it."],
		[11.112, ""],
	],
	[
		[0.55, "Ruth: County, I can see the relay light from the yard. You getting me?"],
		[3.944, "County: Loud and clear, Ruth."],
		[5.855, ""],
		[6.335, "Mick: County, it’s Mick. Six o’clock. All clear at the east sheds."],
		[10.211, ""],
		[10.486, "Mick: [Coughs]"],
		[12.086, ""],
		[12.921, "Ruth: Oh. I thought he’d gone home."],
		[14.693, ""],
	],
	[
		[0.469, "Garage operator: Sorry, County. You’re coming through now."],
		[2.781, ""],
		[2.901, "County: Mick, if you’re still on, where’d you leave the gate key?"],
		[6.026, ""],
		[8.636, "Mick: County, it’s Mick. Six o’clock. All clear at the east sheds."],
		[12.513, ""],
		[12.788, "Mick: [Coughs]"],
		[14.388, ""],
	],
	[
		[0.48, "County: County desk, for anyone still on the east road."],
		[3.28, ""],
		[3.71, "County: We’re at the house where the pavement runs out. The one on the right."],
		[7.108, ""],
		[7.553, "County: There’s a light on. Kettle’s on if you’re out that way."],
		[10.587, ""],
	],
	[
		[0.5, "County: County desk, evening roll call. Len?"],
		[3.172, ""],
		[5.172, "County: Ruth?"],
		[5.943, ""],
		[7.543, "County: Ruth, are you there? Please."],
		[10.174, ""],
		[11.374, "Ruth: Yeah, just locking up. Has Len called?"],
		[13.483, ""],
		[14.483, "County: Ruth. You said that two days ago."],
		[16.346, ""],
		[17.746, "Ruth: Yeah, just locking up. Has Len called?"],
		[19.856, ""],
	],
	[
		[0.5, "You: County, it’s me."],
		[2.843, ""],
		[3.443, "You: I’m at the house. Everything’s fine."],
		[5.359, ""],
		[5.959, "You: The kettle’s on. You should come out."],
		[9.335, ""],
		[10.535, "Mick: [Coughs]"],
		[12.135, ""],
	],
]

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
	voice.finished.connect(stop_listening)
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
	if not is_instance_valid(listener) or not listener.can_listen_to_radio(global_position):
		stop_listening()
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
	echo_at = randf_range(9.0, maxf(10.0, RECORDINGS[broadcast].get_length() - 6.0)) if randf() < 0.3 else -1.0
	caption = "Carrier signal…"
	listener.show_radio_caption(self, caption)
	dial.emission_enabled = true
	voice.play()
	carrier.play()
	set_process(true)


func stop_listening() -> void:
	set_process(false)
	if is_instance_valid(listener):
		listener.clear_radio_caption(self)
	listener = null
	caption = ""
	voice.stop()
	carrier.stop()
	echo.stop()
	dial.emission_enabled = false


func _exit_tree() -> void:
	if is_instance_valid(listener):
		listener.clear_radio_caption(self)


func _carrier_sound() -> AudioStreamWAV:
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
