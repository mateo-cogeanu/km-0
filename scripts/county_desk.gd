extends Node
## At the start of a new trip, County comes over the workshop radio: Len is
## missing, get the car going, drive east, check in at every station. Once per
## trip, so a continued trip does not hear it again.

const RoadEndHouse := preload("res://scripts/road_end_house.gd")

var wait := 3.5


func _process(delta: float) -> void:
	if RoadEndHouse.story.get("intro_played", false):
		set_process(false)
		return
	wait -= delta
	if wait > 0.0:
		return
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	var radio := get_tree().current_scene.find_child("WorkshopRadio", true, false) if get_tree().current_scene else null
	if player == null or radio == null or not radio.has_method("county_call"):
		return
	# Only on a fresh trip, at the workshop.
	if player.global_position.distance_to(radio.global_position) > 40.0:
		RoadEndHouse.story["intro_played"] = true
		return
	RoadEndHouse.story["intro_played"] = true
	radio.county_call("county_intro", player)
	set_process(false)
