extends RefCounted

const ASPHALT := preload("res://assets/audio/road/asphalt.wav")
const GRAVEL := preload("res://assets/audio/road/gravel.wav")
const SOIL := preload("res://assets/audio/road/soil.wav")
const WIND_EXPOSED := preload("res://assets/audio/road/wind_exposed.wav")
const WIND_CABIN := preload("res://assets/audio/road/wind_cabin.wav")


static func loop(source: AudioStreamWAV) -> AudioStreamWAV:
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	return stream


static func smooth_gain(player: Node, target: float, response: float) -> void:
	var gain := lerpf(db_to_linear(player.volume_db), target, response)
	player.volume_db = linear_to_db(maxf(gain, 0.0001))
