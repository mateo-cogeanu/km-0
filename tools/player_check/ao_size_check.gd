extends Node
## Ambient occlusion switches to half size only on tall enough screens.

func _ready() -> void:
	await get_tree().process_frame
	print("start: ", get_tree().root.size, " half=", GameSettings.ao_half)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	await _frames(20)
	get_tree().root.size = Vector2i(1920, 1080)
	await _frames(20)
	print("1080p window: ", get_tree().root.size, " half=", GameSettings.ao_half)
	get_tree().root.size = Vector2i(2560, 1440)
	await _frames(20)
	print("1440p window: ", get_tree().root.size, " half=", GameSettings.ao_half)
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
