extends Node3D

const Shapes := preload("res://scripts/prop_shapes.gd")
const Stop := preload("res://scripts/roadside_stop.gd")
const Terrain := preload("res://scripts/roadside_terrain.gd")
const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const Dread := preload("res://scripts/road_dread.gd")
const Weather := preload("res://scripts/weather.gd")
const StrangerHouse := preload("res://scripts/stranger_house.gd")
const ROAD_END := 9.0
const HOUSE_APPROACH := -5200.0
const STOP_BLOCK := 12
const GROUND_TILE_SIZE := 160.0
const GROUND_DEPTH := 8.0
const GROUND_OVERLAP := 0.12
const ASPHALT := preload("res://assets/buildings/asphalt.gdshader")

@export var target: Node3D
@export var segment_length := 80.0
@export var road_width := 6.8
@export var shoulder_width := 2.6
@export var keep_segments_ahead := 6
@export var keep_segments_behind := 3

var segments: Dictionary = {}
var stops: Dictionary = {}
var ground_tiles: Dictionary[Vector2i, StaticBody3D] = {}
var ground_shape := BoxShape3D.new()
var update_timer := 0.0

var road_material := ShaderMaterial.new()
var gravel := Shapes.material(Color("#89775b"))
var sand := Shapes.material(Terrain.SAND, 0.0, 1.0)
var white := Shapes.material(Color("#dfdbbf"))
var yellow := Shapes.material(Color("#cfa247"))
var desert_ground: MeshInstance3D
var terrain := Terrain.new()
var stream_stops := false


func _ready() -> void:
	road_material.shader = ASPHALT
	sand.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Local boxes keep collision broad-phase bounds close to the bodies using them.
	ground_shape.size = Vector3(GROUND_TILE_SIZE + GROUND_OVERLAP, GROUND_DEPTH, GROUND_TILE_SIZE + GROUND_OVERLAP)
	desert_ground = Shapes.box(self, "DesertHorizon", Vector3(2000.0, 0.06, 2000.0), Vector3(0, -0.105, 0), sand)
	var weather := Weather.new()
	weather.name = "Weather"
	add_child(weather)
	var dread := Dread.new()
	dread.name = "RoadDread"
	dread.road = self
	add_child(dread)
	# Back the other way, past where the road begins, someone else is holed up.
	var cabin := StrangerHouse.new()
	cabin.name = "StrangerHouse"
	add_child(cabin)
	cabin.position = StrangerHouse.LOCATION
	cabin.rotation.y = StrangerHouse.TURN
	_update_segments()


func begin_streaming() -> void:
	stream_stops = true
	_update_segments()


func _process(delta: float) -> void:
	update_timer -= delta
	if update_timer > 0.0:
		return
	update_timer = 0.18
	_update_segments()


func _update_segments() -> void:
	var camera := get_viewport().get_camera_3d()
	var tracking := camera.global_position if camera else (target.global_position if is_instance_valid(target) else global_position)
	desert_ground.global_position = Vector3(tracking.x, -0.105, tracking.z)
	var wanted: Dictionary = {}
	var players := get_tree().get_nodes_in_group("road_stream_player")
	_update_ground_tiles(tracking, players)
	_collect_segments(tracking.z, wanted)
	# Keep road collisions under other drivers as well as the local camera.
	if NetworkManager.is_online():
		for player in players:
			_collect_segments(player.global_position.z, wanted)
	for vehicle in get_tree().get_nodes_in_group("drivable"):
		# Parked vehicles still need the same road height after a player leaves the area.
		var vehicle_index := floori(vehicle.global_position.z / segment_length)
		for index in range(vehicle_index - 1, vehicle_index + 2):
			wanted[index] = true

	for index in wanted:
		if not segments.has(index):
			segments[index] = _create_segment(index)
		_update_stop(index, tracking, segments[index], players)
	for index in segments.keys():
		if not wanted.has(index):
			(segments[index] as Node3D).queue_free()
			segments.erase(index)
	for index in stops:
		var stop := stops[index] as Node3D
		stop.visible = wanted.has(index)


func _update_ground_tiles(tracking: Vector3, players: Array[Node]) -> void:
	var wanted: Dictionary[Vector2i, bool] = {}
	_collect_ground_tiles(tracking, 1, wanted)
	for player: Node3D in players:
		_collect_ground_tiles(player.global_position, 1, wanted)
	for group in [&"drivable", &"vehicle_loose_part", &"fuel_canister", &"spray_can"]:
		for body: RigidBody3D in get_tree().get_nodes_in_group(group):
			if not body.is_queued_for_deletion():
				_collect_ground_tiles(body.global_position, 1 if group == &"drivable" else 0, wanted)

	# Add new tiles before releasing old ones. Neighboring boxes overlap at the seams.
	for index in wanted:
		if ground_tiles.has(index):
			continue
		var tile := StaticBody3D.new()
		tile.name = "Ground_%d_%d" % [index.x, index.y]
		tile.position = Vector3(
			(index.x + 0.5) * GROUND_TILE_SIZE,
			Terrain.LEVEL - GROUND_DEPTH * 0.5,
			(index.y + 0.5) * GROUND_TILE_SIZE
		)
		tile.add_to_group("Dirt")
		tile.add_to_group("roadside_soil")
		var collision := CollisionShape3D.new()
		collision.shape = ground_shape
		tile.add_child(collision)
		add_child(tile)
		ground_tiles[index] = tile
	for index in ground_tiles.keys():
		if not wanted.has(index):
			ground_tiles[index].queue_free()
			ground_tiles.erase(index)


func _collect_ground_tiles(at: Vector3, padding: int, wanted: Dictionary[Vector2i, bool]) -> void:
	var center := Vector2i(floori(at.x / GROUND_TILE_SIZE), floori(at.z / GROUND_TILE_SIZE))
	for z in range(-padding, padding + 1):
		for x in range(-padding, padding + 1):
			wanted[center + Vector2i(x, z)] = true


func _collect_segments(z: float, wanted: Dictionary) -> void:
	var center := floori(z / segment_length)
	var ahead: int = [4, keep_segments_ahead, keep_segments_ahead + 4][GameSettings.draw_distance]
	var behind: int = [2, keep_segments_behind, keep_segments_behind + 2][GameSettings.draw_distance]
	for index in range(center - ahead - 2, center + behind + 2):
		wanted[index] = true


func _road_x(z: float) -> float:
	var t := z / segment_length
	var departure_blend := smoothstep(15.0, 140.0, absf(z))
	return (sin(t * 0.34) * 14.0 + (sin(t * 0.15 + 1.9) - sin(1.9)) * 8.0) * departure_blend


func _road_height(z: float) -> float:
	return 0.006 + smoothstep(24.0, 125.0, absf(z)) * (0.027 + 0.018 * sin(z * 0.07) + 0.01 * sin(z * 0.22))


func _sample(z: float, lateral: float, height_offset: float = 0.0) -> Vector3:
	var slope := _road_x(z + 0.5) - _road_x(z - 0.5)
	var right := Vector3(1, 0, -slope).normalized()
	return Vector3(_road_x(z), _road_height(z) + height_offset, z) + right * lateral


func _create_segment(index: int) -> Node3D:
	var segment := Node3D.new()
	segment.name = "Road_%d" % index
	add_child(segment)
	var segment_start := index * segment_length
	segment.position.z = segment_start
	var end := minf(segment_start + segment_length, ROAD_END)
	var start := maxf(segment_start, HOUSE_APPROACH)
	var stop_side := _stop_side(index) if index < -1 else 0.0
	terrain.populate(segment, segment_start, segment_length, index, absi(index) <= 1, stop_side, _road_x)
	if start >= end:
		return segment
	if start == HOUSE_APPROACH:
		_build_house_turnoff(segment)
	var half := road_width * 0.5
	_add_strip(segment, "Asphalt", start, end, -half, half, 0.0, road_material, "Road")
	_add_strip(segment, "GravelLeft", start, end, -half - shoulder_width, -half, -0.009, gravel, "Dirt")
	_add_strip(segment, "GravelRight", start, end, half, half + shoulder_width, -0.009, gravel, "Dirt")
	var marking_end := end - 3.0 if end == ROAD_END else end
	if start == HOUSE_APPROACH:
		_add_strip(segment, "CrumbledFarEnd", start - 0.46, start + 0.10, -half, half, -0.012, gravel)
	for side in [-1.0, 1.0]:
		var edge: float = side * (half - 0.16)
		_add_strip(segment, "EdgeLine", start, marking_end, edge - 0.045, edge + 0.045, 0.002, white)
	for dash in range(ceili(segment_length / 8.0)):
		var z := start + dash * 8.0 + 0.7
		if z + 3.4 <= marking_end:
			_add_strip(segment, "CenterDash", z, z + 3.4, -0.06, 0.06, 0.002, yellow)
	if end == ROAD_END:
		_add_strip(segment, "CrumbledEnd", end - 0.10, end + 0.48, -half, half, -0.012, gravel)
	return segment


func _build_house_turnoff(segment: Node3D) -> void:
	var house := RoadEndHouse.new()
	house.name = "RoadEndHouse"
	segment.add_child(house)
	var at := _sample(HOUSE_APPROACH + 5.0, 13.0) - segment.position
	house.position = Vector3(at.x, 0.0, at.z)
	house.rotation.y = -PI * 0.5
	var entry := house.position + Vector3.LEFT * 6.1
	var drive_start := _sample(HOUSE_APPROACH + 8.0, road_width * 0.5 + 0.6) - segment.position
	var drive := Shapes.box(segment, "HouseTurnoff", Vector3(3.1, 0.04, drive_start.distance_to(entry) + 2.0),
		(drive_start + entry) * 0.5, gravel, true)
	drive.position.y = -0.04
	drive.rotation.y = atan2(entry.x - drive_start.x, entry.z - drive_start.z)


func _add_strip(segment: Node3D, title: String, from_z: float, to_z: float, left: float, right: float, lift: float, material: Material, surface_group: String = "") -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var divisions := maxi(1, ceili((to_z - from_z) / 3.0))
	for i in range(divisions):
		var z0 := lerpf(from_z, to_z, float(i) / divisions)
		var z1 := lerpf(from_z, to_z, float(i + 1) / divisions)
		var a := _sample(z0, left, lift) - segment.position
		var b := _sample(z0, right, lift) - segment.position
		var c := _sample(z1, left, lift) - segment.position
		var d := _sample(z1, right, lift) - segment.position
		var vertices := [a, b, c, b, d, c]
		var uvs := [Vector2(0, z0), Vector2(1, z0), Vector2(0, z1), Vector2(1, z0), Vector2(1, z1), Vector2(0, z1)]
		for vertex in range(6):
			surface.set_normal(Vector3.UP)
			surface.set_uv(uvs[vertex])
			surface.add_vertex(vertices[vertex])
	var visual := MeshInstance3D.new()
	visual.name = title
	visual.mesh = surface.commit()
	visual.material_override = material
	segment.add_child(visual)
	if not surface_group.is_empty():
		var body := StaticBody3D.new()
		body.add_to_group(surface_group)
		if surface_group == "Dirt":
			body.add_to_group("roadside_gravel")
		visual.add_child(body)
		var collision := CollisionShape3D.new()
		collision.shape = visual.mesh.create_trimesh_shape()
		body.add_child(collision)


func _has_stop(index: int) -> bool:
	if index == -5:
		return true
	if index > -15:
		return false
	var block := floori(float(index) / STOP_BLOCK)
	var offset := 3 + posmod(hash("stop:%d" % block), 5)
	return index == STOP_BLOCK * block + offset


func _stop_side(index: int) -> float:
	return 1.0 if posmod(hash("side:%d" % index), 2) == 0 else -1.0


func _update_stop(index: int, tracking: Vector3, segment: Node3D, players: Array[Node]) -> void:
	if (index + 0.5) * segment_length <= HOUSE_APPROACH or not _has_stop(index):
		return
	var z := (index + 0.5) * segment_length
	var side := _stop_side(index)
	var at := _sample(z, side * 14.0)
	if not segment.has_node("Turnoff"):
		var link_start := _sample(z, side * (road_width * 0.5 + 0.8)) - segment.position
		var link_end := at - Vector3(side * 5.0, 0, 0) - segment.position
		var heading := link_end - link_start
		var driveway := Shapes.box(segment, "Turnoff", Vector3(4.4, 0.018, heading.length()), (link_start + link_end) / 2.0, gravel, true)
		driveway.position.y = -0.039
		driveway.rotation.y = atan2(heading.x, heading.z)
		var surface := driveway.get_child(0)
		surface.remove_from_group("Road")
		surface.add_to_group("Dirt")
		surface.add_to_group("roadside_gravel")

	if not stream_stops or stops.has(index):
		return
	if not NetworkManager.is_online():
		if absf(tracking.z - z) <= segment_length * 3.0:
			spawn_stop(index)
	elif multiplayer.is_server():
		for player in players:
			if absf(player.global_position.z - z) <= segment_length * 3.0:
				spawn_stop.rpc(index)
				break


@rpc("authority", "call_local", "reliable")
func spawn_stop(index: int, vehicle_owner: int = 1, legacy_layout: bool = false, use_sedan_loadout: bool = true, restoring: bool = false, saved_body_style: int = -1, legacy_car_spares := false) -> void:
	if stops.has(index):
		return
	var z := (index + 0.5) * segment_length
	var side := _stop_side(index)
	var at := _sample(z, side * 14.0)
	var stop := Stop.new()
	stop.name = "Stop_%d" % index
	stop.stop_index = index
	stop.vehicle_owner = vehicle_owner
	stop.legacy_layout = legacy_layout
	stop.use_sedan_loadout = use_sedan_loadout
	stop.restoring = restoring
	stop.saved_body_style = saved_body_style
	stop.legacy_car_spares = legacy_car_spares
	stop.position = Vector3(at.x, 0, at.z)
	stop.rotation.y = -side * PI * 0.5
	add_child(stop)
	stops[index] = stop
