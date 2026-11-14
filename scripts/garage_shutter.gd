extends Node3D

const Shapes := preload("res://scripts/prop_shapes.gd")
const HEIGHT := 2.29
const WIDTH := 4.53
const SLAT_COUNT := 15

var opening := 0.0
var slats: Array[MeshInstance3D] = []
var handle: MeshInstance3D
var door_collision: CollisionShape3D
var door_shape := BoxShape3D.new()
var target: Area3D


func build(steel: Material, dark: Material, trim: Material) -> void:
	var pitch := HEIGHT / SLAT_COUNT
	for index in range(SLAT_COUNT):
		_add_slat(index, pitch, steel if index % 2 == 0 else dark)
	handle = Shapes.box(self, "PullHandle", Vector3(0.26, 0.06, 0.07), Vector3(0, 0.14, 0.08), trim)
	for side in [-1, 1]:
		Shapes.box(self, "GuideRail", Vector3(0.075, HEIGHT, 0.18), Vector3(side * WIDTH * 0.5, HEIGHT * 0.5, 0), dark)
	Shapes.box(self, "DrumHousing", Vector3(WIDTH + 0.13, 0.30, 0.31), Vector3(0, HEIGHT + 0.16, 0.14), dark)

	var body := AnimatableBody3D.new()
	body.add_to_group("Road")
	add_child(body)
	door_collision = CollisionShape3D.new()
	door_collision.shape = door_shape
	body.add_child(door_collision)

	target = Area3D.new()
	target.name = "GarageDoorTarget"
	target.collision_layer = 8
	target.collision_mask = 0
	target.add_to_group("shack_interactable")
	add_child(target)
	var target_shape := CollisionShape3D.new()
	var target_box := BoxShape3D.new()
	target_box.size = Vector3(WIDTH, 0.30, 0.26)
	target_shape.shape = target_box
	target.add_child(target_shape)
	set_opening(0)


func _add_slat(index: int, pitch: float, finish: Material) -> void:
	var at := Vector3(0, (index + 0.5) * pitch, 0)
	slats.append(Shapes.box(self, "Slat", Vector3(WIDTH, pitch - 0.008, 0.105), at, finish))


func set_opening(value: float) -> void:
	opening = clampf(value, 0.0, 1.0)
	var bottom := HEIGHT * opening
	var pitch := HEIGHT / SLAT_COUNT
	for index in range(SLAT_COUNT):
		var slat := slats[index]
		var low := bottom + index * pitch
		var high := minf(low + pitch - 0.008, HEIGHT)
		slat.visible = high > low
		if slat.visible:
			slat.position.y = (low + high) * 0.5
			slat.scale.y = (high - low) / (pitch - 0.008)
	handle.visible = bottom + 0.18 < HEIGHT
	handle.position.y = bottom + 0.14
	target.position.y = minf(bottom + 0.14, HEIGHT + 0.14)

	var remaining := HEIGHT - bottom
	door_collision.set_deferred("disabled", remaining < 0.01)
	door_shape.size = Vector3(WIDTH, maxf(0.01, remaining), 0.105)
	door_collision.position.y = bottom + remaining * 0.5


func set_door_overlay(material: Material) -> void:
	for slat in slats:
		slat.material_overlay = material
	handle.material_overlay = material
