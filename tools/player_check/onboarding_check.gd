extends Node
## A first trip: County's call at the workshop, the job sheet ticking along,
## kilometre posts and station signs, and checking in at station 1.
## Screenshots into KM0_CHECK_DIR. Leaves the real tutorial setting alone.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")

var world: Node
var dir := OS.get_environment("KM0_CHECK_DIR")
var saved_done := false


func _ready() -> void:
	saved_done = GameSettings.tutorial_done
	GameSettings.tutorial_done = false
	RoadEndHouse.seen = false
	RoadEndHouse.story = {}
	world = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _frames(2)
	get_tree().current_scene = world
	await _frames(150)
	var player: CharacterBody3D = get_tree().get_first_node_in_group("local_player")
	var guide := world.get_node_or_null("TutorialGuide")
	print("guide shown: ", guide != null, " step: ", guide.step if guide else -1)
	var workshop := world.find_child("WorkshopRadio", true, false)
	print("county calling: ", workshop.replying, " caption: ", workshop.caption)
	_shot("onboard_call")
	for i in 900:
		await get_tree().process_frame
		if not workshop.replying:
			break
	await _frames(120)
	print("after the call, step: ", guide.step if is_instance_valid(guide) else -1)
	# Look the car over.
	var car: Node3D = guide.car
	player.global_position = car.global_position + Vector3(0, 1.0, 3.2)
	player.look_at(car.global_position, Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	await _frames(30)
	print("by the car, step: ", guide.step, " missing: ", guide.parts.text)
	_shot("onboard_sheet")
	# Out on the road: posts and signs.
	var road: Node3D = world.get_node("InfiniteRoad")
	player.global_position = road._sample(-80.0, 1.6, 1.1)
	player.look_at(road._sample(-160.0, 4.0, 1.2), Vector3.UP)
	player.rotation.x = 0.0
	player.rotation.z = 0.0
	await _frames(60)
	_shot("onboard_sign")
	var labels := world.find_children("*", "Label3D", true, false)
	var texts := []
	for label: Label3D in labels:
		if label.text.begins_with("KM") or label.text.begins_with("STATION"):
			texts.append(label.text.replace("\n", " "))
	print("markers near: ", texts)
	for label: Label3D in labels:
		if label.text.begins_with("KM") or label.text.begins_with("STATION"):
			print("  ", label.text.replace("\n", " "), " at ", label.global_position.snapped(Vector3.ONE * 0.1), " visible ", label.is_visible_in_tree())
	# Check in at station 1.
	await _frames(30)
	var station: Node3D = null
	for radio: Node3D in get_tree().get_nodes_in_group("road_radio"):
		if radio.name != "WorkshopRadio" and radio.broadcast == 1:
			station = radio
	if station == null:
		player.global_position = road._sample(-400.0, 6.0, 1.1)
		await _frames(120)
		for radio: Node3D in get_tree().get_nodes_in_group("road_radio"):
			if radio.name != "WorkshopRadio" and radio.broadcast == 1:
				station = radio
	print("station 1 radio found: ", station != null)
	if station:
		player.global_position = station.to_global(Vector3(0, 0, 1.0))
		await _frames(10)
		station.toggle_listening(player)
		station.voice.seek(station.voice.stream.get_length() - 0.3)
		var seen_captions := []
		for i in 2400:
			await get_tree().process_frame
			if not seen_captions.has(station.caption):
				seen_captions.append(station.caption)
			if station.replying and station.caption.begins_with("County"):
				print("reply: ", station.caption)
				break
		print("captions seen: ", seen_captions, " replying: ", station.replying, " you playing: ", station.you_speaker.playing, " county playing: ", station.reply_speaker.playing)
		print("checked in: ", RoadEndHouse.story.get("checked_in", {}), " step: ", guide.step if is_instance_valid(guide) else "done")
	GameSettings.tutorial_done = saved_done
	GameSettings.save_settings()
	get_tree().quit()


func _shot(title: String) -> void:
	get_viewport().get_texture().get_image().save_png(dir.path_join(title + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
