extends Node

const RoadAudio := preload("res://scripts/road_audio.gd")

var exposed: AudioStreamPlayer
var cabin: AudioStreamPlayer
var player: CharacterBody3D


func _ready() -> void:
	player = get_parent() as CharacterBody3D
	exposed = _add_loop(RoadAudio.WIND_EXPOSED)
	cabin = _add_loop(RoadAudio.WIND_CABIN)


func _add_loop(source: AudioStreamWAV) -> AudioStreamPlayer:
	var sound := AudioStreamPlayer.new()
	sound.stream = RoadAudio.loop(source)
	sound.volume_db = -80.0
	add_child(sound)
	sound.play()
	return sound


func _process(delta: float) -> void:
	var shell := 0.0
	var speed_gain := 0.0
	var vehicle: RigidBody3D = player.active_vehicle
	if is_instance_valid(vehicle):
		var v := vehicle.linear_velocity
		speed_gain = smoothstep(3.0, 33.0, Vector2(v.x, v.z).length())
		shell = vehicle.get_cabin_enclosure()
	# The loop carries the gusts. Speed only lifts them slightly above the road sound.
	var air_gain := lerpf(0.082, 0.18, speed_gain)
	var response := 1.0 - exp(-delta * 5.0)
	RoadAudio.smooth_gain(exposed, air_gain * (1.0 - shell), response)
	RoadAudio.smooth_gain(cabin, air_gain * 0.23 * shell, response)


func _exit_tree() -> void:
	exposed.stop()
	cabin.stop()
