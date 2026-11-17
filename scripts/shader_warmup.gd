extends Node3D
## Rare effects (the creature, fire, smoke, flares) loaded once at the start,
## out of sight under the ground, so their shaders and pipelines are ready
## before they are first seen instead of hitching the frame they appear in.

const Creature := preload("res://scripts/road_creature.gd")
const HouseFire := preload("res://scripts/house_fire.gd")
const Supply := preload("res://scripts/supply_item.gd")

var frames := 0


func _ready() -> void:
	position = Vector3(0, -60, 0)
	var creature := Creature.new()
	add_child(creature)
	var fire := HouseFire.new()
	add_child(fire)
	fire.set_heat(1.0)
	fire.crackle.volume_db = -80.0
	var flare := Supply.new()
	flare.kind = "flare"
	flare.freeze = true
	add_child(flare)


func _process(_delta: float) -> void:
	frames += 1
	if frames == 1:
		var creature := get_child(0)
		if creature.has_method("set_eyes"):
			creature.set_eyes(5.0, 1.0)
	if frames > 20:
		queue_free()
