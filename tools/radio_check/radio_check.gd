extends Node
## Records a few seconds of a radio voice, clean and through the radio bus.

const Radio := preload("res://scripts/road_radio.gd")


func _ready() -> void:
	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, record)
	for pass_name in ["clean", "radio"]:
		var speaker := AudioStreamPlayer.new()
		speaker.stream = load("res://assets/audio/radio/workshop.wav")
		speaker.volume_db = -4.0 if pass_name == "clean" else Radio.VOICE_VOLUME
		if pass_name == "radio":
			speaker.bus = Radio._radio_bus()
		add_child(speaker)
		record.set_recording_active(true)
		speaker.play(3.0)
		await get_tree().create_timer(6.0).timeout
		record.set_recording_active(false)
		speaker.stop()
		record.get_recording().save_to_wav("/private/tmp/claude-501/-Users-mateocogeanu-km-0/e3451267-ae12-4e01-ab91-404095614e3d/scratchpad/radio_%s.wav" % pass_name)
	get_tree().quit()
