extends Node3D

const CarModel := preload("res://scripts/compact_car_model.gd")
const Shapes := preload("res://scripts/prop_shapes.gd")
const Terrain := preload("res://scripts/roadside_terrain.gd")
const ROAD_X := 2.1

var camera_base_transform: Transform3D
var camera_parallax := Vector2.ZERO

@export var camera_parallax_degrees: float = 1.1
@export var camera_parallax_distance: float = 0.12
@export var camera_parallax_smoothing: float = 2.4

@onready var menu_camera: Camera3D = $Camera3D


func _ready() -> void:
	camera_base_transform = menu_camera.transform
	CarModel.new(Color("#7e3830")).build($Car, CarModel.WAGON, false)
	$Workshop.build()
	_add_landscape()


func _add_landscape() -> void:
	var terrain := Terrain.new()
	for index in range(-6, 1):
		var terrain_section := Node3D.new()
		add_child(terrain_section)
		terrain_section.position.z = index * 80.0
		terrain.populate(terrain_section, terrain_section.position.z, 80.0, index, index == 0, 0.0, func(_z: float) -> float: return ROAD_X)

	var faded_white := Shapes.material(Color("#b6ad92"))
	var faded_yellow := Shapes.material(Color("#a28348"))
	for side in [-1.0, 1.0]:
		Shapes.box(self, "RoadEdge", Vector3(0.08, 0.004, 440), Vector3(ROAD_X + side * 3.24, 0.006, -204), faded_white)
	for index in range(55):
		Shapes.box(self, "CenterDash", Vector3(0.11, 0.004, 3.1), Vector3(ROAD_X, 0.006, 13.0 - index * 8.0), faded_yellow)

	var gravel := Shapes.material(Color("#87745d"))
	Shapes.box(self, "WorkshopPullOff", Vector3(8.5, 0.015, 5.2), Vector3(8.3, -0.024, -8.8), gravel)
	for at in [Vector3(-3.7, 0.0, 2.5), Vector3(7.1, 0.0, -1.7), Vector3(-5.3, 0.0, -13.0)]:
		var shrub := MeshInstance3D.new()
		shrub.mesh = preload("res://scripts/desert_models.gd").mesh_of("scrub")
		add_child(shrub)
		shrub.position = at
		shrub.rotation.y = at.x


func _process(delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var normalized_mouse := (get_viewport().get_mouse_position() / viewport_size) * 2.0 - Vector2.ONE
	normalized_mouse.x = clampf(normalized_mouse.x, -1.0, 1.0)
	normalized_mouse.y = clampf(normalized_mouse.y, -1.0, 1.0)
	var blend := 1.0 - exp(-camera_parallax_smoothing * delta)
	camera_parallax = camera_parallax.lerp(normalized_mouse, blend)

	var target := camera_base_transform
	target.origin += Vector3(
		camera_parallax.x * camera_parallax_distance,
		-camera_parallax.y * camera_parallax_distance * 0.55,
		0.0
	)
	var rotation_offset := Basis.from_euler(Vector3(
		deg_to_rad(-camera_parallax.y * camera_parallax_degrees * 0.65),
		deg_to_rad(-camera_parallax.x * camera_parallax_degrees),
		0.0
	))
	target.basis = camera_base_transform.basis * rotation_offset
	menu_camera.transform = target
