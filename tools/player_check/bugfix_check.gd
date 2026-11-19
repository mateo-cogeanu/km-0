extends Node
## Proves the gameplay fixes from the bug audit, in one run (prints PASS/FAIL
## per line, quits with 1 if any failed):
##   New trip clears story state left from an earlier trip.
##   An item taken out of a cooler is visible and solid after Continue.
##   The County car's can survives Continue.
##   Endings don't replay: escaped closes the way out, burned keeps the house
##   shut, replaced stops the radio answering.
##   H in the car sounds the horn without touching the headlights.
##   Sleeping twice in a row only sleeps once.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const StoryNotes := preload("res://scripts/story_notes.gd")
const RoadDread := preload("res://scripts/road_dread.gd")

var failed := 0


func _ready() -> void:
	# Live outside the current scene, which New trip / Continue replace.
	if not has_meta("driver"):
		var driver := Node.new()
		driver.set_meta("driver", true)
		driver.set_script(get_script())
		get_tree().root.add_child.call_deferred(driver)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	TripSave.save_path = "user://bugfix_check.save"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TripSave.save_path))
	# 1. Stale story from "an earlier trip", then New trip.
	RoadEndHouse.story = {"house_z": -5200.0, "heard": {"0": true}, "escaped": true}
	RoadEndHouse.seen = true
	StoryNotes.read["len_1"] = true
	TripSave.start_trip(false)
	var world := await _main()
	_check("new trip clears story", RoadEndHouse.story.is_empty() and not RoadEndHouse.seen and StoryNotes.read.is_empty())
	var road: Node3D = world.get_node("InfiniteRoad")
	var player: CharacterBody3D = world.get_node("Player")
	player.set_physics_process(false)

	# 2. A cooler opened, an item taken out and set down; plus a County can.
	var box: Node3D
	for index in range(-2, -300, -1):
		if not road._has_stop(index):
			continue
		road.spawn_stop(index)
		await _frames(2)
		box = world.get_node_or_null("Finds_%d/Cooler" % index)
		if box:
			break
	box.open(true)
	await _frames(5)
	var item: RigidBody3D = box.items[0]
	var spot := box.global_position + Vector3(1.5, 0.6, 0)
	item.global_position = spot
	var can := road.FUEL.instantiate() as RigidBody3D
	can.name = "CountyCan"
	road.add_child(can)
	can.global_position = spot + Vector3(0, 0, 1.5)
	await _frames(5)
	var item_path := world.get_path_to(item)
	_check("save written", TripSave.save_trip())
	TripSave.start_trip(true)
	world = await _main()
	var restored := world.get_node_or_null(item_path) as RigidBody3D
	_check("looted item visible after Continue", restored != null and restored.visible)
	_check("looted item solid after Continue", restored != null and restored.collision_layer != 0 and not restored.has_meta("loot_layers"))
	road = world.get_node("InfiniteRoad")
	_check("County can kept after Continue", road.get_node_or_null("CountyCan") != null)
	player = world.get_node("Player")

	# 3. Endings stay done.
	var dread: Node = world.get_node_or_null("InfiniteRoad/RoadDread")
	_check("road dread found", dread != null)
	for page in RoadDread.PAGES:
		StoryNotes.read[page] = true
	RoadEndHouse.seen = false
	RoadEndHouse.story.erase("caught")
	RoadEndHouse.story.erase("escaped")
	var open_before: bool = dread != null and dread.way_out_open()
	RoadEndHouse.story["escaped"] = true
	_check("escaped closes the way out (open before: %s)" % open_before, open_before and not dread.way_out_open())
	RoadEndHouse.story["burned"] = true
	var house := RoadEndHouse.new()
	world.add_child(house)
	house.global_position = Vector3(500, 0, -500)
	await _frames(3)
	_check("burned house stands shut and charred", not house.entry_trigger.monitoring and not house.handle_r(player))
	house.queue_free()
	RoadEndHouse.seen = true
	RoadEndHouse.story["replaced"] = true
	_check("replaced: the radio can't be answered again", player.has_method("can_answer_radio") and not player.can_answer_radio())
	RoadEndHouse.seen = false
	RoadEndHouse.story.erase("replaced")

	# 4. H in the car: horn, not headlights.
	var car: Node3D = world.get_node("Car")
	player._enter_vehicle(car, true)
	await _frames(5)
	var lights_before: bool = car.headlights_enabled
	var press := InputEventKey.new()
	press.keycode = KEY_H
	press.pressed = true
	player._unhandled_input(press)
	var release := InputEventKey.new()
	release.keycode = KEY_H
	release.pressed = false
	player._unhandled_input(release)
	_check("H leaves the headlights alone", car.headlights_enabled == lights_before)
	player._exit_vehicle()
	await _frames(5)

	# 5. Sleep twice in a row.
	player.vitals.fatigue = 95.0
	player.vitals.hunger = 80.0
	player._try_sleep("here")
	player._try_sleep("here")
	await get_tree().create_timer(5.0).timeout
	_check("sleeping twice sleeps once (hunger %.0f)" % player.vitals.hunger, player.vitals.hunger > 50.0)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TripSave.save_path))
	print("bugfix_check: %d failed" % failed)
	get_tree().quit(1 if failed > 0 else 0)


func _main() -> Node:
	while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != TripSave.MAIN or get_tree().current_scene.get_node_or_null("Player") == null:
		await get_tree().process_frame
	await _frames(40)
	var world := get_tree().current_scene
	var guide := world.get_node_or_null("TutorialGuide")
	if guide:
		guide.queue_free()
	return world


func _check(what: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		failed += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
