extends Node3D

const Shapes := preload("res://scripts/prop_shapes.gd")
const Stop := preload("res://scripts/roadside_stop.gd")
const Terrain := preload("res://scripts/roadside_terrain.gd")
const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const Dread := preload("res://scripts/road_dread.gd")
const Weather := preload("res://scripts/weather.gd")
const StrangerHouse := preload("res://scripts/stranger_house.gd")
const CarModel := preload("res://scripts/compact_car_model.gd")
const FUEL := preload("res://scenes/fuel_canister.tscn")
const NoteItem := preload("res://scripts/note_item.gd")
const Desert := preload("res://scripts/desert_models.gd")
const GROUND := preload("res://assets/desert/desert_ground.gdshader")
const ROAD_END := 9.0
## The road only ends once it has had a good listen to you, and you to it: the
## broadcasts at HEARD_NEEDED different places, and NIGHTS_NEEDED nights out
## here. Then the house is HOUSE_AHEAD metres on, but never nearer than
## HOUSE_NEAREST. Until then the road goes on.
const HOUSE_NEAREST := -5200.0
const HOUSE_AHEAD := 1600.0
const HEARD_NEEDED := 4
const NIGHTS_NEEDED := 2
const NO_HOUSE := -1.0e9
const STOP_BLOCK := 12
const GROUND_TILE_SIZE := 160.0
const GROUND_DEPTH := 8.0
const GROUND_OVERLAP := 0.12
const ASPHALT := preload("res://assets/buildings/asphalt.gdshader")
## Telephone poles down the left of the road, every POLE_SPACING metres, from a
## little past the workshop to just before the house.
const POLE_SPACING := 42.0
const POLE_FIRST_Z := -48.0
const POLE_SIDE := -7.4
const POLE_HEIGHT := 7.2
const WIRE_SAG := 0.9

@export var target: Node3D
@export var segment_length := 80.0
@export var road_width := 6.8
@export var shoulder_width := 2.6
@export var keep_segments_ahead := 6
@export var keep_segments_behind := 3

var segments: Dictionary = {}
var wrecks: Node
var stops: Dictionary = {}
var ground_tiles: Dictionary[Vector2i, StaticBody3D] = {}
var ground_shape := BoxShape3D.new()
var update_timer := 0.0

var road_material := ShaderMaterial.new()
var gravel := ShaderMaterial.new()
var sand := ShaderMaterial.new()
var white := Shapes.material(Color("#dfdbbf"))
var yellow := Shapes.material(Color("#cfa247"))
var desert_ground: MeshInstance3D
var terrain := Terrain.new()
var stream_stops := false
var furthest := 0.0
var was_night := false
var night_noted := false
var pole_mesh: Mesh
var wire_mesh := CylinderMesh.new()
var pole_shape := CylinderShape3D.new()
var pole_wood := Shapes.material(Color("#4a3a2c"))
var wire_black := Shapes.material(Color("#191817"), 0.3, 0.6)
var marker_white := Shapes.material(Color("#e6e1d2"))
var marker_green := Shapes.material(Color("#2f5a3c"))
var sign_wood := Shapes.material(Color("#6b5a45"))


func _ready() -> void:
	road_material.shader = ASPHALT
	for desert_material in [road_material, sand, gravel]:
		desert_material.set_shader_parameter("noise_tex", Desert.noise_texture())
	pole_mesh = Desert.mesh_of("pole")
	sand.shader = GROUND
	sand.set_shader_parameter("use_vertex_color", 0.0)
	sand.set_shader_parameter("flat_color", Terrain.SAND)
	gravel.shader = GROUND
	gravel.set_shader_parameter("use_vertex_color", 0.0)
	gravel.set_shader_parameter("flat_color", Color("#8a7a62"))
	gravel.set_shader_parameter("pebbles", 3.0)
	gravel.set_shader_parameter("ripples", 0.0)
	gravel.set_shader_parameter("cracks", 0.0)
	wire_mesh.top_radius = 0.012
	wire_mesh.bottom_radius = 0.012
	wire_mesh.height = 1.0
	wire_mesh.radial_segments = 4
	wire_mesh.rings = 0
	wire_mesh.material = wire_black
	pole_shape.radius = 0.13
	pole_shape.height = POLE_HEIGHT
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
	var desk: Node = preload("res://scripts/county_desk.gd").new()
	desk.name = "CountyDesk"
	add_child(desk)
	wrecks = preload("res://scripts/roadside_wrecks.gd").new()
	wrecks.name = "Wrecks"
	wrecks.road = self
	add_child(wrecks)
	var warmup: Node3D = preload("res://scripts/shader_warmup.gd").new()
	warmup.name = "ShaderWarmup"
	add_child(warmup)
	_update_segments(1000)


func begin_streaming() -> void:
	stream_stops = true
	_update_segments(1000)


static func house_approach() -> float:
	## Where the pavement runs out before the house, or NO_HOUSE while the road
	## still goes on.
	return RoadEndHouse.story.get("house_z", NO_HOUSE)


func _watch_for_the_house() -> void:
	var story := RoadEndHouse.story
	if story.has("house_z"):
		return
	# In co-op the host keeps the story and tells everyone where the road ends.
	if NetworkManager.is_online() and not multiplayer.is_server():
		return
	# Trips from before this came in, and anyone who has been there already.
	if RoadEndHouse.seen:
		story["house_z"] = HOUSE_NEAREST
		return
	var cycle := get_tree().current_scene.get_node_or_null("DayNightCycle") if get_tree().current_scene else null
	if cycle and "daylight" in cycle:
		var night: bool = cycle.daylight < 0.12
		# The first look only notes whether it is night (a trip continued at
		# night has already counted this one).
		if not night_noted:
			night_noted = true
			was_night = night
		if night and not was_night:
			story["nights"] = int(story.get("nights", 0)) + 1
		was_night = night
	var heard: Dictionary = story.get("heard", {})
	if heard.size() < HEARD_NEEDED or int(story.get("nights", 0)) < NIGHTS_NEEDED:
		return
	var at_z := minf(HOUSE_NEAREST, furthest - HOUSE_AHEAD)
	if NetworkManager.is_online():
		_house_at.rpc(at_z)
	else:
		_house_at(at_z)


@rpc("authority", "call_local", "reliable")
func _house_at(z: float) -> void:
	var story := RoadEndHouse.story
	if story.has("house_z"):
		return
	story["house_z"] = z
	# Any stretch of road already built where the house now goes is rebuilt.
	var at := floori(float(story["house_z"]) / segment_length)
	for index in range(at - 2, at + 2):
		if segments.has(index):
			(segments[index] as Node3D).queue_free()
			segments.erase(index)
	_update_segments(1000)
	var player := get_tree().get_first_node_in_group("local_player")
	if player:
		player.tip_override = "[Every radio, at once, very faint] ...the kettle's on. Not far now."
		player.tip_time = 7.0


func _process(delta: float) -> void:
	update_timer -= delta
	if update_timer > 0.0:
		return
	update_timer = 0.18
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	if player:
		furthest = minf(furthest, player.global_position.z)
	# The host counts how far anyone has got, not just itself.
	if NetworkManager.is_online() and multiplayer.is_server():
		for other: Node3D in get_tree().get_nodes_in_group("road_stream_player"):
			furthest = minf(furthest, other.global_position.z)
	_watch_for_the_house()
	_update_segments()


## A vehicle further than this from everyone sleeps; it wakes inside PARK_WAKE.
const PARK_SLEEP := 300.0
const PARK_WAKE := 220.0


func _can_park(vehicle: Node) -> bool:
	if vehicle.get("driver") != null:
		return false
	if vehicle is RigidBody3D and (vehicle as RigidBody3D).linear_velocity.length() > 0.5:
		return false
	return true


func _park(vehicle: Node, sleep: bool) -> void:
	if sleep:
		vehicle.set_meta("parked_far", true)
	else:
		vehicle.remove_meta("parked_far")
	vehicle.set_process(not sleep)
	vehicle.set_physics_process(not sleep)
	# Only whoever simulates it changes its physics; elsewhere it already
	# follows them as a frozen body.
	if vehicle is RigidBody3D and (not NetworkManager.is_online() or vehicle.is_multiplayer_authority()):
		var body := vehicle as RigidBody3D
		if sleep:
			body.set_meta("parked_freeze", [body.freeze, body.freeze_mode])
			body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			body.freeze = true
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
		elif body.has_meta("parked_freeze"):
			var was: Array = body.get_meta("parked_freeze")
			body.remove_meta("parked_freeze")
			body.freeze_mode = was[1]
			body.freeze = was[0]


func _update_segments(budget := 1) -> void:
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
	# Road right under someone is built at once; the rest, nearest first, one
	# stretch a frame, so driving fast never builds several in the same frame.
	var urgent: Dictionary = {}
	var center := floori(tracking.z / segment_length)
	for index in range(center - 1, center + 2):
		urgent[index] = true
	for player: Node3D in players:
		urgent[floori(player.global_position.z / segment_length)] = true
	var waking: Array = []
	for vehicle in get_tree().get_nodes_in_group("drivable"):
		# A vehicle left far behind is put to sleep where it stands: it stops
		# being simulated and stops holding road built under it, which would
		# otherwise pile up with every car you pass. It wakes as you come back.
		var nearest := absf(vehicle.global_position.z - tracking.z)
		for player: Node3D in players:
			nearest = minf(nearest, absf(vehicle.global_position.z - player.global_position.z))
		var parked: bool = vehicle.get_meta("parked_far", false)
		if parked and nearest < PARK_WAKE:
			waking.append(vehicle)
		elif not parked and nearest > PARK_SLEEP and _can_park(vehicle):
			_park(vehicle, true)
			parked = true
		if parked and not waking.has(vehicle):
			continue
		# Parked vehicles still need the same road height after a player leaves the area.
		var vehicle_index := floori(vehicle.global_position.z / segment_length)
		for index in range(vehicle_index - 1, vehicle_index + 2):
			wanted[index] = true
			urgent[index] = true

	var missing: Array = wanted.keys().filter(func(index: int) -> bool: return not segments.has(index))
	missing.sort_custom(func(a: int, b: int) -> bool: return absi(a - center) < absi(b - center))
	for index: int in missing:
		if urgent.has(index) or budget > 0:
			if not urgent.has(index):
				budget -= 1
			segments[index] = _create_segment(index)
		else:
			# More to build: come back next frame.
			update_timer = 0.0
	# The road under a waking vehicle is built now (it was urgent): let it go.
	for vehicle: Node3D in waking:
		if segments.has(floori(vehicle.global_position.z / segment_length)):
			_park(vehicle, false)
	for index in wanted:
		if segments.has(index):
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
	var approach := house_approach()
	var start := maxf(segment_start, approach)
	var stop_side := _stop_side(index) if index < -1 else 0.0
	terrain.populate(segment, segment_start, segment_length, index, absi(index) <= 1, stop_side, _road_x)
	_add_power_line(segment, segment_start, segment_start + segment_length)
	_add_markers(segment, index, segment_start, segment_start + segment_length)
	wrecks.populate(segment, index)
	if start >= end:
		return segment
	if start == approach:
		_build_house_turnoff(segment)
	var half := road_width * 0.5
	_add_strip(segment, "Asphalt", start, end, -half, half, 0.0, road_material, "Road")
	_add_strip(segment, "GravelLeft", start, end, -half - shoulder_width, -half, -0.009, gravel, "Dirt")
	_add_strip(segment, "GravelRight", start, end, half, half + shoulder_width, -0.009, gravel, "Dirt")
	var marking_end := end - 3.0 if end == ROAD_END else end
	if start == approach:
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


static func station_number(index: int) -> int:
	## Stations counted from the workshop: the first garage is 1, then one per block.
	return 1 if index == -5 else -floori(float(index) / STOP_BLOCK)


func _add_markers(segment: Node3D, index: int, from_z: float, to_z: float) -> void:
	## Kilometre posts, and a sign before each station telling you it is coming.
	var approach := house_approach()
	var first := ceili(-to_z / 1000.0)
	var last := floori(-from_z / 1000.0)
	for km in range(maxi(first, 1), last + 1):
		var z := -km * 1000.0
		if z < approach + 20.0:
			continue
		var post := _roadside(segment, z, 5.3)
		post.add_child(_prop("km_post"))
		_label(post, "KM\n%d" % km, Vector3(0, 0.88, 0.05), 46)
	for stop in range(index - 8, index + 2):
		if not _has_stop(stop):
			continue
		var stop_z := (stop + 0.5) * segment_length
		var sign_z := stop_z + 300.0
		if sign_z < from_z or sign_z >= to_z or sign_z > -20.0 or stop_z < approach:
			continue
		var board := _roadside(segment, sign_z, 5.6)
		board.add_child(_prop("station_sign"))
		_label(board, "STATION %d\nRADIO  ·  300 m" % station_number(stop), Vector3(0, 1.75, 0.075), 52)


func _prop(title: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = title.to_pascal_case()
	mesh.mesh = Desert.mesh_of(title)
	mesh.visibility_range_end = 160.0
	return mesh


func _roadside(segment: Node3D, z: float, lateral: float) -> Node3D:
	var holder := Node3D.new()
	segment.add_child(holder)
	var slope := _road_x(z + 0.5) - _road_x(z - 0.5)
	holder.position = _sample(z, lateral) - segment.position
	holder.rotation.y = atan2(slope, 1.0)
	return holder


func _label(parent: Node3D, text: String, at: Vector3, size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.004
	label.modulate = Color(0.95, 0.95, 0.9)
	label.outline_size = 0
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	label.position = at


func _has_pole(z: float) -> bool:
	if z > POLE_FIRST_Z or z < house_approach() + 30.0:
		return false
	# Leave room for any stop on the poles' side of the road.
	var near := floori(z / segment_length)
	for index in range(near - 1, near + 2):
		if _has_stop(index) and _stop_side(index) < 0.0 and absf(z - (index + 0.5) * segment_length) < 24.0:
			return false
	return true


func _pole_top(z: float, across: float) -> Vector3:
	## Where a wire hangs off the cross-arm of the pole at z.
	var slope := _road_x(z + 0.5) - _road_x(z - 0.5)
	var right := Vector3(1, 0, -slope).normalized()
	return _sample(z, POLE_SIDE) + Vector3.UP * (POLE_HEIGHT - 0.42) + right * across


func _add_power_line(segment: Node3D, from_z: float, to_z: float) -> void:
	var first := ceili(from_z / POLE_SPACING)
	var last := floori((to_z - 0.001) / POLE_SPACING)
	for k in range(first, last + 1):
		var z := k * POLE_SPACING
		if not _has_pole(z):
			continue
		var base := _sample(z, POLE_SIDE)
		var slope := _road_x(z + 0.5) - _road_x(z - 0.5)
		var facing := Basis(Vector3.UP, atan2(-slope, 1.0))
		var lean := Basis(Vector3.FORWARD, (posmod(hash("pole:%d" % k), 7) - 3) * 0.006)
		var pole := MeshInstance3D.new()
		pole.name = "Pole"
		pole.mesh = pole_mesh
		segment.add_child(pole)
		pole.transform = Transform3D(facing * lean, base - segment.position)
		var body := StaticBody3D.new()
		pole.add_child(body)
		body.position.y = POLE_HEIGHT * 0.5
		var hitbox := CollisionShape3D.new()
		hitbox.shape = pole_shape
		body.add_child(hitbox)
		# Two wires back to the previous pole, sagging in the middle.
		var previous := z + POLE_SPACING
		if not _has_pole(previous):
			continue
		for across in [-0.6, 0.6]:
			var a := _pole_top(z, across) - segment.position
			var b := _pole_top(previous, across) - segment.position
			var points: Array[Vector3] = []
			for step in range(7):
				var t := step / 6.0
				points.append(a.lerp(b, t) + Vector3.DOWN * WIRE_SAG * 4.0 * t * (1.0 - t))
			for step in range(6):
				_wire_piece(segment, points[step], points[step + 1])


func _wire_piece(segment: Node3D, from: Vector3, to: Vector3) -> void:
	var span := to - from
	var wire := MeshInstance3D.new()
	wire.name = "Wire"
	wire.mesh = wire_mesh
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	segment.add_child(wire)
	var up := span.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	wire.transform = Transform3D(Basis(side, up * span.length(), side.cross(up)), (from + to) * 0.5)


func _build_house_turnoff(segment: Node3D) -> void:
	var house := RoadEndHouse.new()
	house.name = "RoadEndHouse"
	segment.add_child(house)
	var at := _sample(house_approach() + 5.0, 13.0) - segment.position
	house.position = Vector3(at.x, 0.0, at.z)
	house.rotation.y = -PI * 0.5
	var entry := house.position + Vector3.LEFT * 6.1
	var drive_start := _sample(house_approach() + 8.0, road_width * 0.5 + 0.6) - segment.position
	var drive := Shapes.box(segment, "HouseTurnoff", Vector3(3.1, 0.04, drive_start.distance_to(entry) + 2.0),
		(drive_start + entry) * 0.5, gravel, true)
	drive.position.y = -0.04
	drive.rotation.y = atan2(entry.x - drive_start.x, entry.z - drive_start.z)
	_add_county_car(segment, drive_start, entry)


func _add_county_car(segment: Node3D, drive_start: Vector3, entry: Vector3) -> void:
	## The County dispatcher drove out here, parked at the turnoff and went in.
	## Her note is on the seat and there is petrol by the boot.
	var county := Node3D.new()
	county.name = "CountyCar"
	segment.add_child(county)
	CarModel.new(Color("#d8d5cb"), 0.35).build(county, CarModel.SEDAN, false)
	# A light bar on the roof, amber, long since switched off.
	var bar := Shapes.box(county, "LightBar", Vector3(1.1, 0.07, 0.24), Vector3(0, 1.545, 0.2), Shapes.material(Color("#2a2c2c"), 0.3, 0.5))
	for side in [-1.0, 1.0]:
		var lens := Shapes.box(bar, "BarLens", Vector3(0.42, 0.09, 0.2), Vector3(side * 0.26, 0.06, 0), Shapes.material(Color("#c98a2e"), 0.1, 0.25))
		CarModel.Looks.reshape(lens, "lens")
	var heading := entry - drive_start
	county.position = drive_start.lerp(entry, 0.35) + heading.normalized().cross(Vector3.UP) * 3.2
	county.position.y = -0.02
	county.rotation.y = atan2(-heading.x, -heading.z) + 0.25
	var door := county.get_node_or_null("FL_Door") as Node3D
	if door:
		door.rotation.y = -1.0
	for side in [-1.0, 1.0]:
		var tag := Label3D.new()
		tag.text = "COUNTY ROADS"
		tag.font_size = 40
		tag.pixel_size = 0.004
		tag.modulate = Color(0.12, 0.2, 0.42)
		tag.outline_size = 0
		county.add_child(tag)
		tag.position = Vector3(side * 0.835, 0.72, 0.5)
		tag.rotation.y = side * PI * 0.5
	var body := StaticBody3D.new()
	county.add_child(body)
	var hitbox := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.7, 1.35, 4.3)
	hitbox.shape = box
	body.add_child(hitbox)
	body.position = Vector3(0, 0.7, 0)
	var note := NoteItem.new()
	note.note_id = "county_car"
	county.add_child(note)
	note.position = Vector3(0.4, 0.62, 0.15)
	note.rotation.y = 0.4
	# Only the first time she is found: the can stays wherever you take it.
	if not RoadEndHouse.story.get("county_can", false):
		RoadEndHouse.story["county_can"] = true
		var can := FUEL.instantiate() as RigidBody3D
		can.name = "CountyCan"
		can.fuel_amount = 16.0
		# Kept on the road itself, not this stretch of it, so it is still there
		# after you drive off and come back.
		add_child(can)
		can.global_transform = county.global_transform * Transform3D(Basis(), Vector3(0.9, 0.3, 2.6))


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
	if (index + 0.5) * segment_length <= house_approach() or not _has_stop(index):
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


func replay_stops_to(peer_id: int) -> void:
	## A guest who arrived late gets every station already out on the road.
	for index in stops:
		spawn_stop.rpc_id(peer_id, index)


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
