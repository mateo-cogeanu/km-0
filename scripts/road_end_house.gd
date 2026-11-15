extends Node3D

const Shapes := preload("res://scripts/prop_shapes.gd")
const Creature := preload("res://scripts/road_creature.gd")
const Style := preload("res://scripts/menu_style.gd")
const HELLO := preload("res://assets/audio/ending/hello.wav")
const ANYBODY := preload("res://assets/audio/ending/anybody.wav")
const TRICKED := preload("res://assets/audio/ending/tricked.wav")
const STEP := preload("res://assets/audio/ending/step.wav")
const DRY_TICKS := preload("res://assets/audio/ending/dry_ticks.wav")
const RAPID_CLICKS := preload("res://assets/audio/ending/rapid_clicks.wav")
const THROAT_RATTLE := preload("res://assets/audio/ending/throat_rattle.wav")
const CLOCK_TICK := preload("res://assets/audio/ending/clock_tick.wav")
const HOUSE_HUM := preload("res://assets/audio/ending/house_hum.wav")
const FLICKER := preload("res://assets/audio/ending/flicker.wav")
const CRACK := preload("res://assets/audio/ending/crack.wav")
const HIT := preload("res://assets/audio/ending/hit.wav")
const DOOR_CREAK := preload("res://assets/audio/ending/door_creak.wav")
const DOOR_OPEN := preload("res://assets/audio/ending/door_open.wav")
const DOOR_LATCH := preload("res://assets/audio/ending/door_latch.wav")
const BREATH_CLOSE := preload("res://assets/audio/ending/breath_close.wav")

var boards := Shapes.material(Color("#675545"))
var floorboards := Shapes.material(Color("#504236"))
var plaster := Shapes.material(Color("#7c7162"))
var dark := Shapes.material(Color("#292524"))
var player: Node3D
var creature: Node3D
var voice: AudioStreamPlayer3D
var footfall: AudioStreamPlayer3D
var creature_sound: AudioStreamPlayer3D
var sequence: Tween
var overlay: CanvasLayer
var caption: Label
var looked := false
var door_open := false
var door_hinge: Node3D
var door_target: Area3D
var previous_step := -1
var walk_start := Vector3.ZERO
var last_palms: Array[Vector3] = []
var last_feet: Array[Vector3] = []
var last_shoulders := Vector3.ZERO
var last_pelvis := Vector3.ZERO
var last_normals: Array[Vector3] = []
var last_foot_normals: Array[Vector3] = []
var stair_palms: Array[Vector3] = []
var stair_feet: Array[Vector3] = []
var stair_shoulders := Vector3.ZERO
var stair_pelvis := Vector3.ZERO
var stair_foot_normals: Array[Vector3] = []
var stair_normals: Array[Vector3] = []
var walls: Array[AABB] = []
var lamps: Array[OmniLight3D] = []
var lamp_energy: Array[float] = []
## The bare bulbs you can see, which dim and flicker with the lamps.
var bulbs: Array[StandardMaterial3D] = []
## Scales every light in the house, for the flickers.
var light_level := 1.0
var interior: Environment
var ambience: Array[AudioStreamPlayer3D] = []
var sting: AudioStreamPlayer
var elbow_cracked := false
var twist_cracked := false
# Hiding and moving between the walls once the lights come back.
var stalking := false
var stalk_spots: Array[Dictionary] = []
var stalk_index := -1
var stalk_seen := 0.0
var stalk_unseen := 0.0
var stalk_found := false
var stalk_wait := 0.0
var stalk_clock := 0.0
## Whether posing the creature also turns your head toward it.
var camera_follow := true
## Which way you face it at the end, and which way its back faced before.
var face_basis := Basis()
var face_back := Vector3.UP
var face_close := 0.0
var shake := 0.0
var fake_end: Control
var fake_tilt: Control
var fake_black: ColorRect
var fake_card: Control
var fake_twisted := false
var roaming := false
var roam_time := 0.0
var roam_inside := false
var breather: AudioStreamPlayer3D
## How open its pupils are in the light; they narrow to slits when it is close.
var eye_open := 0.35
# Shutting the door behind you.
var gaze_target := Vector3.ZERO
var gaze_mix := 0.0
var camera_bias := Vector3.ZERO
var skit_shoulders := Vector3.ZERO
var skit_pelvis := Vector3.ZERO
var skit_palms: Array[Vector3] = []
var skit_feet: Array[Vector3] = []
var skit_normals: Array[Vector3] = []
var skit_start := Vector3.ZERO
var door_reach := Vector3.ZERO
var door_angle := DOOR_OPEN_ANGLE

const STAIR_TIME := 7.7
## How long you can look around inside before it starts, and how close to the
## door counts as trying to leave.
const ROAM_TIME := 10.0
const LEAVE_Z := 3.05
const HOUSE_LAYER := 1 << 19
const DOOR_OPEN_ANGLE := 103.0
## Where it stops beside the open door to shut it, and where you end up standing,
## clear of the door's swing.
const DOOR_SPOT := Vector3(-0.85, 0, 1.72)
const STAND_AT := Vector3(0.15, 0, 2.15)
const SKITTER_TIME := 1.15
const REACH_TIME := 2.4
const DOOR_SWING_TIME := 2.1
## A point on the door's inner face near its free edge, in hinge space.
const DOOR_GRIP := Vector3(1.36, 1.2, -0.06)
## How far into the crawl it freezes before the lights go.
const VANISH_AT := 0.53
const FREEZE_AT := 0.44
const RUSH_TIME := 0.3
# Looking straight at it keeps it still; it moves only while unwatched.
const WATCHED_ANGLE := 0.82
const MOVE_AFTER_LOOK_AWAY := 0.55
const LOST_TIMEOUT := 6.5
const STARE_TIMEOUT := 4.0
const CRAWL_TIME := 7.0
const CRAWL_STRIDES := 6.0
# The tall stairwell wall the creature climbs down, from the landing to where
# the wall ends at the foot of the stairs.
const WALL_X := 2.55
# The stairs' footprint across the room.
const STAIR_LEFT := 1.095
const STAIR_RIGHT := 2.505
const WALL_NORMAL := Vector3.LEFT
const WALL_STANDOFF := 0.27
const WALL_START_Z := -3.1
const WALL_END_Z := -0.85
# Palms stop this far back so the long fingers stay on the plaster too.
const WALL_EDGE_Z := -0.36
const WALL_STRIDES := 7.0
# Feet stay this far in front of the back wall at the top of the climb.
const BACK_WALL_Z := -3.25
# Hands and feet keep this far from the stairwell walls while between them.
const WALL_MARGIN := 0.13
# Room kept between an elbow or knee and a wall.
const JOINT_CLEARANCE := 0.09
## Fraction of the crawl covered before it stops with a hand in the air.
const CRAWL_PAUSE_AT := 0.47
const LEAN_TIME := 2.25
const CLOSE_HOLD := 3.1
const INTRO_QUESTION_CUE := 1.07
const FINAL_WORDS_CUE := 1.27
# Level of the final take, sampled every 50 ms, including the breath and pause.
const FINAL_JAW := [
	0, 84, 126, 121, 100, 71, 46, 29, 16, 7,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	52, 108, 128, 198, 85, 0, 75, 186, 214, 184, 82, 108,
	193, 214, 202, 213, 195, 182, 1, 0, 0, 0, 0, 0,
]


func _ready() -> void:
	_build_house()
	# The house gets its own light layer, so outdoor light that has no shadows
	# can be kept off its insides once you are in.
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mesh.layers = HOUSE_LAYER
	var trigger := Area3D.new()
	trigger.name = "EntryTrigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 4
	add_child(trigger)
	trigger.position = Vector3(0, 1.0, 2.04)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.32, 2.1, 1.15)
	shape.shape = box
	trigger.add_child(shape)
	trigger.body_entered.connect(_on_entry)


func _build_house() -> void:
	Shapes.box(self, "Floor", Vector3(7.2, 0.18, 7.5), Vector3(0, -0.09, 0), floorboards, true)
	for plank in range(22):
		Shapes.box(self, "FloorSeam", Vector3(0.012, 0.003, 7.38), Vector3(-3.45 + plank * 0.32, 0.002, 0), dark)
	_wall(Vector3(0, 2.62, -3.66), Vector3(7.25, 5.24, 0.23))
	for side in [-1.0, 1.0]:
		_wall(Vector3(side * 3.53, 2.62, 0), Vector3(0.24, 5.24, 7.4))
		_wall(Vector3(side * 2.18, 1.34, 3.65), Vector3(2.78, 2.68, 0.26))
		for y in [1.28, 3.56]:
			Shapes.box(self, "WindowFrame", Vector3(1.02, 0.91, 0.14), Vector3(side * 2.04, y, 3.8), floorboards)
			Shapes.box(self, "DarkWindow", Vector3(0.82, 0.70, 0.034), Vector3(side * 2.04, y, 3.89), dark)
			Shapes.box(self, "Mullion", Vector3(0.027, 0.71, 0.034), Vector3(side * 2.04, y, 3.915), boards)
		var roof := Shapes.box(self, "Roof", Vector3(4.07, 0.18, 7.94), Vector3(side * 1.94, 5.51, 0), dark)
		roof.rotation.z = -side * 0.23
	_wall(Vector3(0, 3.79, 3.65), Vector3(7.20, 2.90, 0.26))
	Shapes.box(self, "Ceiling", Vector3(7.14, 0.16, 7.4), Vector3(0, 5.22, 0), dark)
	Shapes.box(self, "Porch", Vector3(3.15, 0.13, 1.54), Vector3(0, -0.071, 4.35), floorboards, true)
	for x in [-0.805, 0.805]:
		Shapes.box(self, "DoorJamb", Vector3(0.12, 2.58, 0.27), Vector3(x, 1.27, 3.65), floorboards)
	for y in [2.78, 5.04]:
		Shapes.box(self, "FrontSidingTrim", Vector3(7.27, 0.072, 0.060),
			Vector3(0, y, 3.802), boards)
	for side in [-1.0, 1.0]:
		for i in range(18):
			Shapes.box(self, "ClapboardSeam", Vector3(2.73, 0.011, 0.028),
				Vector3(side * 2.18, 0.28 * (i + 1), 3.785), boards)
		Shapes.box(self, "PorchPost", Vector3(0.145, 2.50, 0.145), Vector3(side * 1.47, 1.25, 4.99), boards)
	Shapes.box(self, "PorchRoof", Vector3(3.22, 0.14, 1.56), Vector3(0, 2.51, 4.43), dark)
	_build_front_door()
	_build_exterior()
	var stair_mat := Shapes.material(Color("#665346"))
	for i in range(13):
		var height := 0.207 * (i + 1)
		Shapes.box(self, "Stair", Vector3(1.41, height, 0.282), Vector3(1.80, height * 0.5, -0.10 - i * 0.27), stair_mat, true)
	Shapes.box(self, "Landing", Vector3(2.04, 0.18, 0.42), Vector3(1.67, 2.61, -3.43), floorboards, true)
	Shapes.box(self, "UpperFloor", Vector3(4.13, 0.16, 7.27), Vector3(-1.42, 2.61, 0), floorboards, true)
	_wall(Vector3(0.97, 1.5, -1.81), Vector3(0.14, 3.0, 3.55))
	_wall(Vector3(2.62, 2.4, -1.81), Vector3(0.14, 4.8, 3.55))
	Shapes.box(self, "StairTrim", Vector3(0.16, 0.14, 3.57), Vector3(0.97, 3.04, -1.81), boards)
	Shapes.box(self, "BareTable", Vector3(1.24, 0.078, 0.72), Vector3(-2.23, 0.79, -1.35), floorboards, true)
	for x in [-2.75, -1.71]:
		for z in [-1.61, -1.09]:
			Shapes.box(self, "TableLeg", Vector3(0.068, 0.74, 0.066), Vector3(x, 0.371, z), floorboards)
	_build_interior()
	_lamp(Vector3(-1.7, 2.29, 1.31), 0.72, 4.9)
	_lamp(Vector3(2.45, 2.82, -1.94), 0.46, 4.7)
	# Washes the tall stairwell wall so what climbs down it can be seen against it.
	_lamp(Vector3(1.25, 2.9, -1.5), 0.42, 3.4)


func _build_exterior() -> void:
	## Siding, trim, windows, gables, chimney and porch details on the outside.
	var trim := Shapes.material(Color("#8f806b"))
	var stone := Shapes.material(Color("#4a463f"), 0.0, 0.95)
	var brick := Shapes.material(Color("#5c3b31"), 0.0, 0.9)
	var shutter := Shapes.material(Color("#2f3a34"))
	# Clapboards down the sides and across the back, like the front.
	for i in range(18):
		var y := 0.28 * (i + 1)
		for side in [-1.0, 1.0]:
			Shapes.box(self, "ClapboardSeam", Vector3(0.028, 0.011, 7.36), Vector3(side * 3.672, y, 0), boards)
		Shapes.box(self, "ClapboardSeam", Vector3(7.2, 0.011, 0.028), Vector3(0, y, -3.797), boards)
	# Corner boards and a stone foundation.
	for x in [-3.66, 3.66]:
		for z in [-3.8, 3.8]:
			Shapes.box(self, "CornerBoard", Vector3(0.17, 5.3, 0.17), Vector3(x, 2.6, z), trim)
	for side in [-1.0, 1.0]:
		Shapes.box(self, "Foundation", Vector3(0.12, 0.44, 7.72), Vector3(side * 3.71, 0.12, 0), stone)
		Shapes.box(self, "Foundation", Vector3(2.9, 0.44, 0.12), Vector3(side * 2.3, 0.12, 3.85), stone)
	Shapes.box(self, "Foundation", Vector3(7.54, 0.44, 0.12), Vector3(0, 0.12, -3.84), stone)
	# Windows all round, with sills; shutters on the front.
	for y in [1.28, 3.56]:
		for offset in [-1.65, 1.65]:
			for side in [-1.0, 1.0]:
				_window(Vector3(side * 3.72, y, offset), Vector3(side, 0, 0), trim)
			_window(Vector3(offset * 1.24, y, -3.85), Vector3.FORWARD, trim)
		for side in [-1.0, 1.0]:
			Shapes.box(self, "Sill", Vector3(1.14, 0.05, 0.13), Vector3(side * 2.04, y - 0.48, 3.88), trim)
			for edge in [-1.0, 1.0]:
				var leaf := Shapes.box(self, "Shutter", Vector3(0.3, 0.97, 0.04), Vector3(side * 2.04 + edge * 0.69, y, 3.83), shutter)
				for slat in range(6):
					Shapes.box(leaf, "Slat", Vector3(0.26, 0.012, 0.012), Vector3(0, -0.4 + slat * 0.16, 0.024), boards)
	# Close the gables under the roof, with a vent in each.
	for z in [3.785, -3.785]:
		_gable(z)
		Shapes.box(self, "GableVent", Vector3(0.56, 0.26, 0.03), Vector3(0, 5.48, z + signf(z) * 0.02), trim)
		Shapes.box(self, "GableVentSlots", Vector3(0.46, 0.18, 0.03), Vector3(0, 5.48, z + signf(z) * 0.035), dark)
	# Ridge cap, boards along the eaves and a brick chimney.
	Shapes.box(self, "RidgeCap", Vector3(0.26, 0.09, 8.0), Vector3(0, 6.02, 0), dark)
	for side in [-1.0, 1.0]:
		var fascia := Shapes.box(self, "Fascia", Vector3(0.05, 0.22, 7.98), Vector3(side * 3.95, 5.0, 0), trim)
		fascia.rotation.z = -side * 0.23
	Shapes.box(self, "Chimney", Vector3(0.62, 1.75, 0.62), Vector3(2.3, 6.18, -1.9), brick)
	Shapes.box(self, "ChimneyCap", Vector3(0.76, 0.09, 0.76), Vector3(2.3, 7.08, -1.9), stone)
	Shapes.box(self, "ChimneyFlue", Vector3(0.36, 0.05, 0.36), Vector3(2.3, 7.14, -1.9), dark)
	# Porch railings and a lamp by the door.
	for side in [-1.0, 1.0]:
		Shapes.box(self, "PorchRail", Vector3(0.07, 0.06, 1.16), Vector3(side * 1.47, 0.9, 4.39), boards, true)
		Shapes.box(self, "PorchRail", Vector3(0.06, 0.05, 1.16), Vector3(side * 1.47, 0.16, 4.39), boards)
		for i in range(7):
			Shapes.box(self, "Baluster", Vector3(0.035, 0.7, 0.035), Vector3(side * 1.47, 0.53, 3.93 + i * 0.15), boards)
	Shapes.box(self, "PorchLampBase", Vector3(0.13, 0.2, 0.05), Vector3(1.06, 2.05, 3.81), dark)
	var glow := Shapes.material(Color("#f2d29a"))
	glow.emission_enabled = true
	glow.emission = Color("#f0c27a")
	glow.emission_energy_multiplier = 1.6
	Shapes.cylinder(self, "PorchLampGlass", Vector3(1.06, 2.0, 3.89), Vector3.UP, 0.05, 0.16, glow)
	var porch_light := OmniLight3D.new()
	porch_light.name = "PorchLamp"
	porch_light.light_color = Color("#f0c890")
	porch_light.light_energy = 0.55
	porch_light.omni_range = 4.0
	porch_light.shadow_enabled = true
	add_child(porch_light)
	porch_light.position = Vector3(1.06, 2.0, 4.02)


func _build_interior() -> void:
	## Lived-in, and then left: trim, dark windows, a few things where the
	## sounds come from.
	var wood := Shapes.material(Color("#4a3b2f"))
	var glass := Shapes.material(Color("#0b0e14"), 0.35, 0.12)
	# Faint night outside, so the panes read as windows and not holes.
	glass.emission_enabled = true
	glass.emission = Color("#1c2638")
	glass.emission_energy_multiplier = 0.45
	var enamel := Shapes.material(Color("#b3ab9b"), 0.1, 0.45)
	var brass := Shapes.material(Color("#7a6646"), 0.6, 0.4)
	var cloth := Shapes.material(Color("#2b2a2c"), 0.0, 0.95)
	# Baseboards.
	for side in [-1.0, 1.0]:
		Shapes.box(self, "Baseboard", Vector3(0.03, 0.13, 7.0), Vector3(side * 3.395, 0.065, 0), wood)
		Shapes.box(self, "Baseboard", Vector3(2.6, 0.13, 0.03), Vector3(side * 2.11, 0.065, 3.505), wood)
	Shapes.box(self, "Baseboard", Vector3(6.8, 0.13, 0.03), Vector3(0, 0.065, -3.53), wood)
	# The windows from inside: dark glass, nothing beyond it.
	for spot: Array in [
			[Vector3(-2.04, 1.28, 3.52), Vector3.FORWARD], [Vector3(2.04, 1.28, 3.52), Vector3.FORWARD],
			[Vector3(2.04, 3.56, 3.52), Vector3.FORWARD],
			[Vector3(-3.41, 1.28, -1.65), Vector3.RIGHT], [Vector3(-3.41, 1.28, 1.65), Vector3.RIGHT],
			[Vector3(3.41, 1.28, -1.65), Vector3.LEFT], [Vector3(3.41, 1.28, 1.65), Vector3.LEFT],
			[Vector3(3.41, 3.56, -1.65), Vector3.LEFT], [Vector3(3.41, 3.56, 1.65), Vector3.LEFT],
			[Vector3(-2.05, 1.28, -3.545), Vector3.BACK], [Vector3(2.05, 3.56, -3.545), Vector3.BACK]]:
		var at: Vector3 = spot[0]
		var facing: Vector3 = spot[1]
		var across := Vector3.UP.cross(facing).abs()
		var flat := facing.abs()
		Shapes.box(self, "InnerWindowFrame", across * 1.0 + Vector3.UP * 0.9 + flat * 0.02, at + facing * 0.01, wood)
		Shapes.box(self, "InnerWindowGlass", across * 0.84 + Vector3.UP * 0.74 + flat * 0.01, at + facing * 0.02, glass)
		Shapes.box(self, "InnerMullion", across * 0.025 + Vector3.UP * 0.74 + flat * 0.012, at + facing * 0.026, wood)
		Shapes.box(self, "InnerMullion", across * 0.84 + Vector3.UP * 0.025 + flat * 0.012, at + facing * 0.026, wood)
		Shapes.box(self, "InnerSill", across * 1.08 + Vector3.UP * 0.035 + flat * 0.09, at + facing * 0.045 + Vector3.DOWN * 0.465, wood)
	# A worn rug.
	Shapes.box(self, "Rug", Vector3(2.1, 0.008, 1.45), Vector3(0.25, 0.004, 0.55), Shapes.material(Color("#3e2522"), 0.0, 1.0))
	Shapes.box(self, "RugField", Vector3(1.8, 0.009, 1.15), Vector3(0.25, 0.0045, 0.55), Shapes.material(Color("#523430"), 0.0, 1.0))
	# Chairs at the table: one pulled out, one knocked over.
	_chair(Vector3(-2.2, 0, -0.62), PI, wood)
	var fallen := _chair(Vector3(-1.25, 0.22, -1.75), -0.6, wood)
	fallen.rotate_object_local(Vector3.BACK, PI * 0.5)
	# The fridge that hums, and the clock that ticks.
	Shapes.box(self, "Fridge", Vector3(0.74, 1.68, 0.66), Vector3(-3.0, 0.84, -3.16), enamel, true)
	Shapes.box(self, "FridgeSeam", Vector3(0.75, 0.012, 0.67), Vector3(-3.0, 1.18, -3.16), dark)
	Shapes.box(self, "FridgeHandle", Vector3(0.03, 0.36, 0.04), Vector3(-2.72, 1.42, -2.81), brass)
	Shapes.cylinder(self, "ClockFace", Vector3(-3.385, 2.05, -1.3), Vector3.RIGHT, 0.2, 0.04, Shapes.material(Color("#cfc5ad")), 24)
	Shapes.cylinder(self, "ClockRim", Vector3(-3.395, 2.05, -1.3), Vector3.RIGHT, 0.225, 0.03, brass, 24)
	var hour := Shapes.box(self, "ClockHand", Vector3(0.006, 0.11, 0.014), Vector3(-3.36, 2.09, -1.31), dark)
	hour.rotation.x = 0.9
	var minute := Shapes.box(self, "ClockHand", Vector3(0.006, 0.16, 0.01), Vector3(-3.358, 2.1, -1.27), dark)
	minute.rotation.x = -2.6
	# A picture hung crooked, too dark to make out.
	var picture := Shapes.box(self, "PictureFrame", Vector3(0.035, 0.62, 0.48), Vector3(-3.39, 1.55, 0.15), wood)
	picture.rotation.x = 0.06
	Shapes.box(picture, "Picture", Vector3(0.01, 0.5, 0.36), Vector3(0.02, 0, 0), Shapes.material(Color("#1d1a19")))
	# A long coat on a rack by the door.
	Shapes.cylinder(self, "CoatRack", Vector3(-1.5, 0.88, 3.22), Vector3.UP, 0.025, 1.76, wood)
	Shapes.cylinder(self, "CoatRackFoot", Vector3(-1.5, 0.02, 3.22), Vector3.UP, 0.2, 0.04, wood)
	Shapes.box(self, "Coat", Vector3(0.4, 1.0, 0.2), Vector3(-1.5, 1.18, 3.1), cloth)
	Shapes.box(self, "CoatShoulders", Vector3(0.46, 0.08, 0.22), Vector3(-1.5, 1.68, 3.1), cloth)
	# Bare bulbs on cords for the room lamp and the one over the stairs.
	for hang: Array in [[Vector3(-1.7, 2.33, 1.31), 2.53], [Vector3(1.25, 2.95, -1.5), 5.14]]:
		var bulb_at: Vector3 = hang[0]
		var top: float = hang[1]
		Shapes.box(self, "LampCord", Vector3(0.008, top - bulb_at.y, 0.008), Vector3(bulb_at.x, (top + bulb_at.y) * 0.5, bulb_at.z), dark)
		Shapes.cylinder(self, "LampSocket", bulb_at + Vector3.UP * 0.05, Vector3.UP, 0.022, 0.05, dark)
		var glow := Shapes.material(Color("#f4dfb6"))
		glow.emission_enabled = true
		glow.emission = Color("#f3cf8e")
		glow.emission_energy_multiplier = 2.2
		bulbs.append(glow)
		Shapes.cylinder(self, "Bulb", bulb_at - Vector3.UP * 0.02, Vector3.UP, 0.035, 0.07, glow, 10)


func _chair(at: Vector3, turn: float, wood: Material) -> Node3D:
	var chair := Node3D.new()
	chair.name = "Chair"
	add_child(chair)
	chair.position = at
	chair.rotation.y = turn
	Shapes.box(chair, "Seat", Vector3(0.42, 0.04, 0.42), Vector3(0, 0.45, 0), wood)
	for x in [-0.18, 0.18]:
		for z in [-0.18, 0.18]:
			Shapes.box(chair, "ChairLeg", Vector3(0.035, 0.45, 0.035), Vector3(x, 0.225, z), wood)
		Shapes.box(chair, "ChairPost", Vector3(0.035, 0.5, 0.035), Vector3(x, 0.72, 0.19), wood)
	for y in [0.62, 0.82]:
		Shapes.box(chair, "ChairRail", Vector3(0.36, 0.05, 0.025), Vector3(0, y, 0.19), wood)
	return chair


func _window(at: Vector3, facing: Vector3, trim: Material) -> void:
	## A dark window in a frame with a sill, on an outside wall facing outward.
	var across := Vector3.UP.cross(facing).abs()
	var frame_size := across * 1.02 + Vector3.UP * 0.91 + facing.abs() * 0.12
	Shapes.box(self, "WindowFrame", frame_size, at, floorboards)
	Shapes.box(self, "DarkWindow", across * 0.82 + Vector3.UP * 0.7 + facing.abs() * 0.03, at + facing * 0.05, dark)
	Shapes.box(self, "Mullion", across * 0.027 + Vector3.UP * 0.71 + facing.abs() * 0.03, at + facing * 0.07, boards)
	Shapes.box(self, "Sill", across * 1.14 + Vector3.UP * 0.05 + facing.abs() * 0.13, at + facing * 0.05 + Vector3.DOWN * 0.48, trim)


func _gable(z: float) -> void:
	## The triangle of wall between the top of the front or back wall and the roof.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outward := signf(z)
	for corner in ([Vector3(-2.72, 5.24, z), Vector3(2.72, 5.24, z), Vector3(0, 5.9, z)] if outward < 0 else [Vector3(2.72, 5.24, z), Vector3(-2.72, 5.24, z), Vector3(0, 5.9, z)]):
		surface.set_normal(Vector3(0, 0, outward))
		surface.add_vertex(corner)
	var gable := MeshInstance3D.new()
	gable.name = "Gable"
	gable.mesh = surface.commit()
	gable.material_override = plaster
	add_child(gable)
	for i in range(2):
		var y := 5.24 + 0.28 * (i + 1)
		var half := 2.72 * (1.0 - (y - 5.24) / 0.66)
		Shapes.box(self, "ClapboardSeam", Vector3(half * 2.0, 0.011, 0.028), Vector3(0, y, z + outward * 0.01), boards)


func _build_front_door() -> void:
	door_hinge = Node3D.new()
	door_hinge.name = "FrontDoorHinge"
	door_hinge.position = Vector3(-0.737, 0, 3.65)
	add_child(door_hinge)
	Shapes.box(door_hinge, "FrontDoor", Vector3(1.47, 2.49, 0.105), Vector3(0.737, 1.25, 0), boards, true)
	for height in [0.58, 1.79]:
		Shapes.box(door_hinge, "RecessedPanel", Vector3(1.13, 0.83, 0.022), Vector3(0.737, height, 0.054), floorboards)
	var brass := Shapes.material(Color("#867050"), 0.57)
	Shapes.cylinder(door_hinge, "Knob", Vector3(1.31, 1.03, 0.084), Vector3.BACK, 0.045, 0.065, brass)

	door_target = Area3D.new()
	door_target.name = "FrontDoorTarget"
	door_target.collision_layer = 8
	door_target.collision_mask = 0
	door_target.position = Vector3(0.0, 1.25, 3.728)
	door_target.add_to_group("house_front_door")
	add_child(door_target)
	var hitbox := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.46, 2.48, 0.12)
	hitbox.shape = box
	door_target.add_child(hitbox)


func request_open_door() -> void:
	if not NetworkManager.is_online():
		_open_door()
	elif multiplayer.is_server():
		_open_door.rpc()
	else:
		_request_open_door.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_open_door() -> void:
	if not multiplayer.is_server() or door_open:
		return
	var sender := get_tree().current_scene.get_node_or_null(str(multiplayer.get_remote_sender_id())) as Node3D
	if sender and sender.global_position.distance_to(door_target.global_position) < 4.0:
		_open_door.rpc()


@rpc("authority", "call_local", "reliable")
func _open_door() -> void:
	if door_open:
		return
	door_open = true
	door_target.collision_layer = 0
	var swing := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	swing.tween_property(door_hinge, "rotation:y", deg_to_rad(DOOR_OPEN_ANGLE), 1.05).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var hinge := AudioStreamPlayer3D.new()
	hinge.stream = DOOR_OPEN
	hinge.unit_size = 3.0
	hinge.volume_db = -6.0
	add_child(hinge)
	hinge.position = Vector3(0.0, 1.3, 3.65)
	hinge.play()
	hinge.finished.connect(hinge.queue_free)


func _wall(at: Vector3, size: Vector3) -> void:
	Shapes.box(self, "Wall", size, at, plaster, true)
	walls.append(AABB(at - size * 0.5, size))


func _clear_of_walls(point: Vector3, root: Vector3) -> Vector3:
	## Push a creature joint (in the creature's space) out of the walls, back
	## toward the side its limb root is on, with room for the flesh around it.
	var at := point + creature.position
	var from := root + creature.position
	for box: AABB in walls:
		var grown := box.grow(JOINT_CLEARANCE)
		# Out through the wall's face, never around its end; a joint that went
		# right through to the far side is pulled back too.
		var axis := 0 if box.size.x < box.size.z else 2
		var across := 2 - axis
		if at.y < grown.position.y or at.y > grown.end.y or at[across] < grown.position[across] or at[across] > grown.end[across]:
			continue
		if from[axis] < box.get_center()[axis]:
			at[axis] = minf(at[axis], grown.position[axis])
		else:
			at[axis] = maxf(at[axis], grown.end[axis])
	return at - creature.position


func wall_depth(point: Vector3) -> float:
	## How far a point is inside the nearest wall, or 0 when it is clear of them.
	var depth := 0.0
	for box: AABB in walls:
		if box.has_point(point):
			var inside := (point - box.position).min(box.end - point)
			depth = maxf(depth, minf(inside.x, minf(inside.y, inside.z)))
	return depth


func _lamp(at: Vector3, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color("#eed8b9")
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = true
	light.light_cull_mask &= ~Creature.LIGHT_LAYER
	add_child(light)
	light.position = at
	lamps.append(light)
	lamp_energy.append(energy)


func _on_entry(body: Node3D) -> void:
	## Inside, and free to look around. It begins after a while, or as soon as
	## you head back out or start up the stairs.
	if not door_open or looked or roaming or not body.is_in_group("local_player") or body.active_vehicle:
		return
	roaming = true
	roam_time = 0.0
	player = body
	var world_environment := get_tree().current_scene.get_node("WorldEnvironment") as WorldEnvironment
	interior = world_environment.environment.duplicate() as Environment
	interior.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	interior.ambient_light_color = Color("#a6a7b4")
	interior.ambient_light_energy = 0.19
	interior.ambient_light_sky_contribution = 0.0
	player.camera.environment = interior
	var sun := get_tree().current_scene.get_node("Sun") as DirectionalLight3D
	sun.light_cull_mask &= ~(Creature.LIGHT_LAYER | HOUSE_LAYER)
	var sky_fill := get_tree().current_scene.get_node_or_null("DayNightCycle/SkyFillLight") as DirectionalLight3D
	if sky_fill:
		sky_fill.light_cull_mask &= ~(Creature.LIGHT_LAYER | HOUSE_LAYER)
	# An ordinary, quiet house first: a clock and the hum of the wiring.
	ambience.append(_loop(CLOCK_TICK, Vector3(-3.3, 2.05, -1.3), -15.0))
	ambience.append(_loop(HOUSE_HUM, Vector3(-2.4, 1.0, -3.2), -21.0))


func _roam(delta: float) -> void:
	if not is_instance_valid(player):
		roaming = false
		return
	roam_time += delta
	var at := to_local(player.global_position)
	# Only once you are properly in does turning back count as leaving.
	if at.z < LEAVE_Z - 0.45:
		roam_inside = true
	var leaving := roam_inside and at.z > LEAVE_Z
	var climbing := at.x > STAIR_LEFT - 0.2 and at.x < STAIR_RIGHT + 0.2 and at.z < 0.15
	if roam_time >= ROAM_TIME or leaving or climbing:
		_begin_ending()


func _begin_ending() -> void:
	roaming = false
	looked = true
	player.lock_for_ending(to_global(Vector3(0, 1.03, 5.62)))
	# Back to just inside the door, out of the door's way, wherever you were.
	var inside := to_local(player.global_position)
	var target := Vector3(STAND_AT.x, 1.03, STAND_AT.z)
	var step_in := create_tween()
	step_in.tween_property(player, "global_position", to_global(target), clampf(inside.distance_to(target) / 1.5, 1.3, 3.2)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_build_overlay()
	creature = Creature.new()
	add_child(creature)
	creature.keep_clear = _clear_of_walls
	creature.position = Vector3(1.80, 2.70, -3.36)
	creature.hide()
	# Lit low, so it reads mostly as an outline until its face is close.
	_creature_light("StairLight", Vector3(2.0, 3.41, -0.65), Color("#dfb99a"), 0.95, 4.8)
	_creature_light("StairRim", Vector3(2.33, 2.45, -3.27), Color("#8b9fc8"), 0.86, 4.2)
	voice = _speaker(2.4)
	footfall = _speaker(4.5)
	creature_sound = _speaker(2.8)
	creature_sound.volume_db = -7.0
	sting = AudioStreamPlayer.new()
	sting.volume_db = -3.0
	add_child(sting)
	sequence = create_tween()
	sequence.tween_interval(0.95)
	sequence.tween_callback(_speak.bind(HELLO, "You: Hello?", player.camera.global_position + player.camera.global_basis.z * 0.15))
	sequence.tween_interval(INTRO_QUESTION_CUE)
	sequence.tween_callback(caption.set_text.bind("You: Anybody there?"))
	sequence.tween_interval(HELLO.get_length() - INTRO_QUESTION_CUE)
	sequence.tween_callback(caption.set_text.bind(""))
	sequence.tween_interval(1.25)
	sequence.tween_callback(_play_creature_sound.bind(DRY_TICKS))
	sequence.tween_interval(1.92)
	sequence.tween_callback(_begin_descent)


func _begin_descent() -> void:
	_speak(ANYBODY, "[Your voice, upstairs] Anybody there?", creature.global_position + Vector3.UP * 1.15)
	sequence = create_tween()
	var reply_duration := ANYBODY.get_length()
	var listen_duration := maxf(1.5, reply_duration + 0.25)
	var look_at_reply_end := 0.61 * reply_duration / listen_duration
	sequence.tween_method(_listen_toward_stairs, 0.0, look_at_reply_end, reply_duration)
	sequence.tween_callback(caption.set_text.bind(""))
	sequence.tween_method(_listen_toward_stairs, look_at_reply_end, 0.61, listen_duration - reply_duration)
	sequence.tween_callback(_play_creature_sound.bind(THROAT_RATTLE))
	sequence.tween_method(_listen_toward_stairs, 0.61, 1.0, 0.95)
	sequence.tween_callback(creature.show)
	sequence.tween_method(_descend, 0.0, 1.0, STAIR_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_callback(_start_crawl)
	sequence.tween_method(_stair_hold, 0.0, 0.48, 0.48)
	sequence.tween_callback(_play_creature_sound.bind(RAPID_CLICKS))
	sequence.tween_method(_stair_hold, 0.48, 1.9, 1.42)
	sequence.tween_method(_crawl, 0.0, FREEZE_AT, FREEZE_AT * CRAWL_TIME)
	# Everything goes quiet the moment it stops.
	sequence.tween_callback(_stop_ambience)
	sequence.tween_method(_crawl, FREEZE_AT, VANISH_AT, (VANISH_AT - FREEZE_AT) * CRAWL_TIME)
	sequence.tween_interval(0.7)
	# Its eyes slide off you to the open door behind you. Then it goes for it.
	sequence.tween_callback(_start_skitter)
	sequence.tween_method(_look_at_door, 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	sequence.tween_interval(0.35)
	sequence.tween_method(_skitter, 0.0, 1.0, SKITTER_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	sequence.tween_callback(_start_reach)
	sequence.tween_method(_shut_door, 0.0, 1.0, REACH_TIME)
	sequence.tween_method(_door_swings_shut, 0.0, 1.0, DOOR_SWING_TIME)
	sequence.tween_callback(_play_at.bind(DOOR_LATCH, to_global(Vector3(0.6, 1.1, 3.6)), 1.0))
	sequence.tween_method(_after_door, 0.0, 1.0, 1.25)
	sequence.tween_callback(_play_flicker)
	for beat: Array in [[0.0, 0.07], [1.0, 0.12], [0.0, 0.05], [1.0, 0.34]]:
		sequence.tween_callback(_set_lights.bind(beat[0]))
		sequence.tween_interval(beat[1])
	sequence.tween_callback(_play_flicker)
	sequence.tween_callback(_set_lights.bind(0.0))
	# Only its eyes in the dark, still on you. Then they go out.
	sequence.tween_interval(0.75)
	sequence.tween_callback(creature.hide)
	# In the dark, something fast skitters off toward the far wall.
	sequence.tween_interval(0.4)
	for step: Array in [[Vector3(1.9, 0.1, 1.2), 1.05, 0.16], [Vector3(2.6, 0.4, 1.4), 1.12, 0.13], [Vector3(3.2, 1.2, 1.1), 1.2, 0.12], [Vector3(3.4, 2.3, 0.8), 1.3, 0.85]]:
		sequence.tween_callback(func() -> void: _play_at(STEP, to_global(step[0]), step[1]))
		sequence.tween_interval(step[2])
	sequence.tween_callback(_set_lights.bind(1.0))
	sequence.tween_interval(1.35)
	sequence.tween_callback(_begin_stalk)


func _final_approach() -> void:
	## The last flicker: in the dark it gets onto the wall right beside you.
	stalking = false
	camera_follow = false
	player.end_ending_look()
	for speaker: Node in [creature_sound, footfall, voice]:
		speaker.stop()
	sequence = create_tween()
	sequence.tween_callback(_set_lights.bind(0.0))
	sequence.tween_callback(creature.hide)
	sequence.tween_interval(1.25)
	# Two eyes open in the dark, right beside you, before the lights come back.
	sequence.tween_callback(_place_at.bind(stalk_spots.size() - 1))
	sequence.tween_interval(1.15)
	sequence.tween_callback(_set_lights.bind(1.0))
	sequence.tween_method(_turn_to_creature, 0.0, 1.0, 0.42)
	sequence.tween_method(_turn_to_creature, 1.0, 1.0, 0.55)
	sequence.tween_callback(_start_rush)
	sequence.tween_method(_lean, 0.0, 1.0, RUSH_TIME).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	sequence.tween_method(_hold_face.bind(false), 0.0, 0.76, 0.76)
	sequence.tween_callback(_play_creature_sound.bind(RAPID_CLICKS))
	sequence.tween_method(_hold_face.bind(false), 0.76, CLOSE_HOLD, CLOSE_HOLD - 0.76)
	sequence.tween_callback(_deliver_line)
	var line_end := TRICKED.get_length() + 0.35
	sequence.tween_method(_hold_face.bind(true), 0.0, FINAL_WORDS_CUE, FINAL_WORDS_CUE)
	sequence.tween_callback(caption.set_text.bind("Creature: Tricked you too."))
	sequence.tween_method(_hold_face.bind(true), FINAL_WORDS_CUE, line_end, line_end - FINAL_WORDS_CUE)
	sequence.tween_callback(caption.set_text.bind(""))
	sequence.tween_method(_hold_face.bind(true), line_end, line_end + 0.65, 0.65)
	sequence.tween_callback(_show_fake_end)


func _start_skitter() -> void:
	creature.jitter = 0.0
	skit_shoulders = last_shoulders
	skit_pelvis = last_pelvis
	skit_palms = last_palms.duplicate()
	skit_feet = last_feet.duplicate()
	skit_normals = last_normals.duplicate()
	skit_start = creature.position
	gaze_target = to_local(door_hinge.to_global(Vector3(0.7, 1.3, 0)))
	_creature_light("DoorLight", Vector3(-0.15, 2.2, 2.75), Color("#d9b394"), 0.9, 3.2)


func _look_at_door(amount: float) -> void:
	gaze_mix = amount
	creature.tilt = lerpf(0.38, -0.2, amount)
	_pose(skit_shoulders, skit_pelvis, skit_palms, skit_normals, skit_feet, 5.03, 0.0, [Vector3.UP, Vector3.UP])


func _skitter(t: float) -> void:
	## Fast and low, wide around you, to the open door.
	var bend := Vector3(0.4, 0, 0.78)
	var strides := t * 3.5
	var at := _crawl_path(skit_start, bend, DOOR_SPOT, t)
	var forward := (bend - skit_start).lerp(DOOR_SPOT - bend, t).normalized()
	creature.position = at
	var blend := smoothstep(0.0, 0.2, t)
	var palms: Array[Vector3] = []
	var feet: Array[Vector3] = []
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var phase := strides + i * 0.5
		var hand_t := clampf((_contact(phase) - 0.05) / 3.5, 0, 1)
		var hand_forward := (bend - skit_start).lerp(DOOR_SPOT - bend, hand_t).normalized()
		var palm := _crawl_path(skit_start, bend, DOOR_SPOT, hand_t) + hand_forward * 0.28 + Vector3.UP.cross(hand_forward) * side * 0.4
		palm.y = _swing(phase) * 0.16
		palm = _between_walls(skit_palms[i].lerp(palm, blend))
		palm.y = maxf(palm.y, _ground_under(palm, 0.14) + 0.02)
		palms.append(palm)
		var foot_t := clampf((_contact(phase + 0.5) - 0.42) / 3.5, 0, 1)
		var foot_forward := (bend - skit_start).lerp(DOOR_SPOT - bend, foot_t).normalized()
		var foot := _crawl_path(skit_start, bend, DOOR_SPOT, foot_t) - foot_forward * 0.5 + Vector3.UP.cross(foot_forward) * side * 0.3
		foot.y = _swing(phase + 0.5) * 0.1
		foot = _between_walls(skit_feet[i].lerp(foot, blend))
		foot.y = maxf(foot.y, _ground_under(foot, 0.14))
		feet.append(foot)
	var shoulders := at + forward * 0.16 + Vector3.UP * (0.62 - absf(sin(strides * TAU)) * 0.04)
	var pelvis := at - forward * 0.58 + Vector3.UP * 0.58
	var normals: Array[Vector3] = [skit_normals[0].lerp(Vector3.UP, blend).normalized(), skit_normals[1].lerp(Vector3.UP, blend).normalized()]
	_pose(skit_shoulders.lerp(shoulders, blend), skit_pelvis.lerp(pelvis, blend), palms, normals, feet, 5.03, 0.0, [Vector3.UP, Vector3.UP])
	_play_contact(strides * 2.0, palms[floori(strides * 2.0) % 2], 1.18)
	# Its gaze swings back to you as it arrives.
	gaze_mix = 1.0 - smoothstep(0.6, 1.0, t)
	creature.tilt = lerpf(-0.2, 0.25, t)


func _start_reach() -> void:
	skit_shoulders = last_shoulders
	skit_pelvis = last_pelvis
	skit_palms = last_palms.duplicate()
	skit_feet = last_feet.duplicate()
	door_reach = DOOR_SPOT + Vector3(-0.08, 1.02, 0.26)
	var creak := _speaker(3.0)
	creak.volume_db = -3.0
	creak.stream = DOOR_CREAK
	creak.position = Vector3(-0.6, 1.3, 3.0)
	var start := create_tween()
	start.tween_interval(REACH_TIME * 0.32)
	start.tween_callback(creak.play)
	creak.finished.connect(creak.queue_free)


func _door_grip() -> Vector3:
	return door_hinge.transform * DOOR_GRIP


func _shut_door(t: float) -> void:
	## Rears up, curls its long fingers around the edge of the door and pushes
	## it shut, slowly, watching you the whole time.
	var rise := smoothstep(0.0, 0.32, t)
	var push := smoothstep(0.32, 1.0, t)
	door_angle = lerpf(DOOR_OPEN_ANGLE, 52.0, push)
	door_hinge.rotation.y = deg_to_rad(door_angle)
	var grip := _door_grip()
	var face := door_hinge.basis * Vector3.FORWARD
	var reach := skit_palms[0].lerp(grip, rise) + Vector3.UP * sin(rise * PI) * 0.18
	var palms: Array[Vector3] = [reach if push == 0.0 else grip, skit_palms[1]]
	var normals: Array[Vector3] = [Vector3.UP.lerp(face, rise).normalized(), Vector3.UP]
	var shoulders := skit_shoulders.lerp(door_reach, rise)
	shoulders += (grip - shoulders) * Vector3(1, 0, 1) * 0.12 * push
	camera_bias = (to_global(grip) - creature.head.global_position) * 0.55 * rise
	_pose(shoulders, skit_pelvis, palms, normals, skit_feet, 5.03, 0.0, [Vector3.UP, Vector3.UP])


func _door_swings_shut(t: float) -> void:
	## It lets go. The door creaks the rest of the way by itself, and the hand
	## that pushed it sinks back to the floor.
	if t == 0.0 or skit_palms.size() < 3:
		skit_palms = [last_palms[0], skit_palms[1], last_palms[0]]
		skit_normals = [last_normals[0], Vector3.UP]
		skit_shoulders = last_shoulders
	door_angle = lerpf(52.0, 0.0, smoothstep(0.0, 1.0, t))
	door_hinge.rotation.y = deg_to_rad(door_angle)
	var drop := smoothstep(0.35, 1.0, t)
	var rest := Vector3(-1.05, 0.0, 2.05)
	var palms: Array[Vector3] = [skit_palms[2].lerp(rest, drop) + Vector3.UP * sin(drop * PI) * 0.1, skit_palms[1]]
	var normals: Array[Vector3] = [skit_normals[0].lerp(Vector3.UP, drop).normalized(), Vector3.UP]
	camera_bias = camera_bias * (1.0 - drop)
	creature.tilt = lerpf(0.25, 0.55, t)
	_pose(skit_shoulders, skit_pelvis, palms, normals, skit_feet, 5.03, 0.0, [Vector3.UP, Vector3.UP])


func _after_door(t: float) -> void:
	## Shut in. It holds still and stares, twitching.
	creature.jitter = 0.6
	camera_bias = Vector3.ZERO
	creature.tilt = 0.55 + _twitch_at(t * 0.2, 0.1) * 0.2
	_pose(skit_shoulders, skit_pelvis, last_palms, last_normals, skit_feet, 5.03, 0.0, [Vector3.UP, Vector3.UP])


func _listen_toward_stairs(progress: float) -> void:
	var focus := to_global(Vector3(1.88, 2.55, -2.86))
	player.aim_ending_camera(focus, _camera_response(1.2) * smoothstep(0.33, 0.90, progress))


func _descend(progress: float) -> void:
	# Head first down the tall stairwell wall, belly to the plaster and all four
	# limbs on it, well above the steps.
	var stride := progress * WALL_STRIDES
	var step := (WALL_END_Z - WALL_START_Z) / WALL_STRIDES
	var center_z := lerpf(WALL_START_Z, WALL_END_Z, progress)
	var center := _wall_point(center_z) + Vector3(-WALL_STANDOFF + sin(stride * TAU) * 0.02, 0, 0)
	var spine := _wall_heading(center_z)
	creature.position = Vector3(WALL_X - 0.4, _stair_line(center_z), center_z)
	var palms: Array[Vector3] = []
	var feet: Array[Vector3] = []
	var normals: Array[Vector3] = [WALL_NORMAL, WALL_NORMAL]
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var phase := stride + i * 0.5
		var lift := _swing(phase)
		var palm_z := minf(WALL_START_Z + (_contact(phase) + 1.15) * step, WALL_EDGE_Z)
		palms.append(_on_wall(_wall_point(palm_z) + _wall_side(palm_z) * side * 0.4) + WALL_NORMAL * lift * 0.14)
		var foot_phase := phase + 0.5
		var foot_lift := _swing(foot_phase)
		var foot_z := clampf(WALL_START_Z + (_contact(foot_phase) - 0.95) * step, BACK_WALL_Z, WALL_EDGE_Z)
		feet.append(_on_wall(_wall_point(foot_z) + _wall_side(foot_z) * side * 0.32) + WALL_NORMAL * foot_lift * 0.12)
	_pose(center + spine * 0.372, center - spine * 0.372, palms, normals, feet, progress * 3.65, 0.0, normals, WALL_NORMAL)
	_play_contact(stride * 2.0, palms[mini(1, floori(stride * 2.0) % 2)], 0.76)


func _wall_point(z: float) -> Vector3:
	## The line the creature's belly follows down the wall: high above the
	## steps at first, closer to them near the bottom.
	var height := lerpf(1.55, 1.12, smoothstep(-1.4, WALL_END_Z, z))
	return Vector3(WALL_X, _stair_line(z) + height, z)


func _on_wall(point: Vector3) -> Vector3:
	## Keep a hand or foot on the plaster, short of where the wall ends.
	return Vector3(point.x, point.y, minf(point.z, WALL_EDGE_Z))


func _wall_heading(z: float) -> Vector3:
	return (_wall_point(z + 0.05) - _wall_point(z)).normalized()


func _wall_side(z: float) -> Vector3:
	## Across the wall: the creature's right, pointing up the wall.
	var heading := _wall_heading(z)
	return Vector3(0, heading.z, -heading.y)


func ground_height(x: float, z: float) -> float:
	## Height of whatever is underfoot inside the house: a stair tread or the floor.
	if x < STAIR_LEFT or x > STAIR_RIGHT:
		return 0.0
	return _stair_height(z)


func _ground_under(point: Vector3, reach: float) -> float:
	## Highest surface under a hand or foot, so it rests on a step rather than
	## sinking into its edge.
	var top := 0.0
	for dx in [-reach, 0.0, reach]:
		for dz in [-reach, 0.0, reach]:
			top = maxf(top, ground_height(point.x + dx, point.z + dz))
	return top


func _ground_smooth(point: Vector3) -> float:
	## Ground under the body, eased across step edges so it glides down them.
	var total := 0.0
	for dz in [-0.3, -0.15, 0.0, 0.15, 0.3]:
		total += _ground_under(point + Vector3(0, 0, dz), 0.22)
	return total / 5.0


func _stair_line(z: float) -> float:
	## Height of a smooth line along the stair nosings.
	return maxf(0.0, (0.042 - z) / 0.27 * 0.207)


func _stair_height(z: float) -> float:
	return 0.0 if z > 0.042 else clampf(floorf((0.041 - z) / 0.27) + 1.0, 1.0, 13.0) * 0.207


func _start_crawl() -> void:
	walk_start = creature.position
	stair_palms = last_palms
	stair_feet = last_feet
	stair_shoulders = last_shoulders
	stair_pelvis = last_pelvis
	stair_foot_normals = last_foot_normals
	stair_normals = last_normals
	previous_step = -1


func _stair_hold(seconds: float) -> void:
	creature.jitter = 0.4
	var breath := sin(seconds * 2.5) * 0.012
	# Hangs on the wall at the foot of the stairs, head lowering toward you.
	var lean := Vector3(0, -0.14, 0.1) * smoothstep(0.4, 1.6, seconds)
	# The head keeps turning, much further than a neck should let it, then
	# snaps back.
	creature.tilt = smoothstep(0.5, 1.45, seconds) * 1.95 if seconds < 1.6 else 0.0
	if seconds >= 1.6 and not twist_cracked:
		twist_cracked = true
		_play_at(CRACK, creature.head.global_position, 0.9)
	_pose(stair_shoulders + lean + WALL_NORMAL * breath, stair_pelvis + lean * 0.3, stair_palms, stair_normals, stair_feet,
		3.65 + seconds * 0.35, 0.0, stair_foot_normals, WALL_NORMAL)


func _crawl(phase_progress: float) -> void:
	# Approach, freeze with a hand raised and the head cocked, then scuttle.
	var progress := _crawl_distance(phase_progress)
	var freeze := smoothstep(0.4, 0.46, phase_progress) * (1.0 - smoothstep(0.58, 0.62, phase_progress))
	creature.jitter = freeze * 0.55
	creature.tilt = freeze * 0.38 + _twitch_at(phase_progress, 0.5) * 0.12
	# For one stride the right elbow bends the wrong way, then pops back.
	creature.elbow_flip[1] = smoothstep(0.27, 0.33, phase_progress) if phase_progress < 0.37 else 0.0
	if phase_progress >= 0.37 and not elbow_cracked:
		elbow_cracked = true
		_play_at(CRACK, to_global(last_palms[1]) if last_palms.size() > 1 else creature.global_position, 1.08)
	var eye := to_local(player.camera.global_position)
	var end := Vector3(eye.x, 0, eye.z - 1.03)
	var bend := Vector3(1.72, 0, 0.82)
	var start := Vector3(walk_start.x, 0, walk_start.z)
	var strides := progress * CRAWL_STRIDES
	var at := _crawl_path(start, bend, end, progress)
	var forward := (bend - start).lerp(end - bend, progress).normalized()
	var right := Vector3.UP.cross(forward)
	creature.position = at
	var palms: Array[Vector3] = []
	var normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
	var foot_normals: Array[Vector3] = [Vector3.UP, Vector3.UP]
	var feet: Array[Vector3] = []
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var phase := strides + i * 0.5
		var hand_progress := clampf((_contact(phase) - 0.05) / CRAWL_STRIDES, 0, 1)
		var hand_path := _crawl_path(start, bend, end, hand_progress)
		var foot_progress := clampf((_contact(phase + 0.5) - 0.42) / CRAWL_STRIDES, 0, 1)
		var foot_path := _crawl_path(start, bend, end, foot_progress)
		var hand_forward := ((bend - start).lerp(end - bend, hand_progress)).normalized()
		var hand_right := Vector3.UP.cross(hand_forward)
		# Hands reach high and slap down; the swing arc overshoots forward.
		var lift := _swing(phase)
		var palm := hand_path + hand_forward * (0.24 + lift * 0.06) + hand_right * side * (0.38 + lift * 0.05)
		palm = _between_walls(palm)
		palm.y = _ground_under(palm, 0.1) + lift * 0.2
		var settle := smoothstep(float(i) * 0.085, 0.24 + float(i) * 0.085, phase_progress)
		var drop_arc := sin(settle * PI) * 0.16
		var reach_down := stair_palms[i].lerp(palm, settle) + stair_normals[i] * drop_arc + Vector3.UP * drop_arc * 0.4
		# On the way from the wall to a tread, pass over the step edges, not through them.
		reach_down = _between_walls(reach_down)
		reach_down.y = maxf(reach_down.y, _ground_under(reach_down, 0.14) + 0.02 + (1.0 - settle) * 0.08)
		palms.append(reach_down)
		normals[i] = stair_normals[i].lerp(Vector3.UP, settle).normalized()
		var foot_forward := ((bend - start).lerp(end - bend, foot_progress)).normalized()
		var foot := foot_path - foot_forward * 0.5 + Vector3.UP.cross(foot_forward) * side * 0.3
		foot = _between_walls(foot)
		foot.y = _ground_under(foot, 0.1) + _swing(phase + 0.5) * 0.13
		var foot_settle := smoothstep(0.04 + float(i) * 0.05, 0.22 + float(i) * 0.05, phase_progress)
		var step_down := stair_feet[i].lerp(foot, foot_settle) + stair_foot_normals[i] * sin(foot_settle * PI) * 0.12
		step_down = _between_walls(step_down)
		step_down.y = maxf(step_down.y, _ground_under(step_down, 0.14) + (1.0 - foot_settle) * 0.08)
		feet.append(step_down)
		foot_normals[i] = stair_foot_normals[i].lerp(Vector3.UP, foot_settle).normalized()
	# The chest drops onto each planted hand and rolls toward it.
	var plant := absf(sin(strides * TAU))
	var sway := sin(strides * TAU) * 0.04
	var shoulders := at + forward * 0.16 + right * sway
	shoulders.y = _ground_smooth(shoulders) + 0.70 - plant * 0.035 + freeze * 0.05
	var pelvis := at - forward * 0.58 - right * sway * 0.6
	pelvis.y = _ground_smooth(pelvis) + 0.62 + plant * 0.012
	# Climbs down off the wall, hands first, and turns belly-down on the floor.
	var transfer := smoothstep(0.0, 0.24, phase_progress)
	var held := Vector3(0, -0.14, 0.1)
	shoulders = (stair_shoulders + held).lerp(shoulders, transfer)
	pelvis = (stair_pelvis + held * 0.3).lerp(pelvis, smoothstep(0.04, 0.3, phase_progress))
	var back := WALL_NORMAL.slerp(Vector3.UP, transfer)
	_pose(shoulders, pelvis, palms, normals, feet, lerpf(4.2275, 5.75, phase_progress), 0.0, foot_normals, back)
	if phase_progress >= 0.26:
		_play_contact(strides * 2.0, palms[floori(strides * 2.0) % 2], 0.96 + (0.08 if phase_progress > 0.6 else 0.0))


func _between_walls(point: Vector3) -> Vector3:
	## Keep a hand or foot off the stairwell walls until it is past their end.
	var inside := 1.0 - smoothstep(-0.2, 0.1, point.z)
	var clamped := point
	clamped.x = clampf(point.x, STAIR_LEFT + WALL_MARGIN, WALL_X - WALL_MARGIN)
	return point.lerp(clamped, inside)


func _crawl_path(start: Vector3, bend: Vector3, end: Vector3, t: float) -> Vector3:
	return start.lerp(bend, t).lerp(bend.lerp(end, t), t)


func _crawl_distance(t: float) -> float:
	## Time to distance: a measured approach, a dead stop, then a fast rush.
	return smoothstep(0.15, 0.46, t) * CRAWL_PAUSE_AT + smoothstep(0.58, 1.0, t) * (1.0 - CRAWL_PAUSE_AT)


func _twitch_at(t: float, at: float) -> float:
	var local := (t - at) * CRAWL_TIME
	return smoothstep(0.0, 0.04, local) * (1.0 - smoothstep(0.06, 0.22, local))


func _contact(phase: float) -> float:
	return floorf(phase) + smoothstep(0.58, 1.0, fposmod(phase, 1.0))


func _swing(phase: float) -> float:
	return sin(clampf((fposmod(phase, 1.0) - 0.58) / 0.42, 0.0, 1.0) * PI)


func _play_contact(phase: float, point: Vector3, pitch: float) -> void:
	var index := floori(phase)
	if index == previous_step:
		return
	previous_step = index
	footfall.global_position = to_global(point)
	footfall.pitch_scale = pitch + index % 4 * 0.055
	footfall.stream = STEP
	footfall.play()


func _pose(shoulders: Vector3, pelvis: Vector3, palms: Array[Vector3], normals: Array[Vector3], feet: Array[Vector3],
		elapsed: float, reveal: float = 0.0, foot_normals: Array[Vector3] = [Vector3.UP, Vector3.UP],
		back: Vector3 = Vector3.UP) -> void:
	if reveal == 0.0 and elapsed <= 5.75:
		last_palms = palms
		last_feet = feet
		last_shoulders = shoulders
		last_pelvis = pelvis
		last_normals = normals
		last_foot_normals = foot_normals
	var eye := to_local(player.camera.global_position).lerp(gaze_target, gaze_mix)
	var local_palms: Array[Vector3] = [palms[0] - creature.position, palms[1] - creature.position]
	var local_feet: Array[Vector3] = [feet[0] - creature.position, feet[1] - creature.position]
	creature.pose_contacts(shoulders - creature.position, pelvis - creature.position, eye - creature.position,
		local_palms, normals, local_feet, elapsed, reveal, foot_normals, back)
	if camera_follow:
		player.aim_ending_camera(creature.head.global_position + Vector3.UP * 0.22 + camera_bias, _camera_response(5.5))
	if shake > 0.0:
		player.camera.rotate_object_local(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.4, 0.4)).normalized(), shake)


func _camera_response(rate: float) -> float:
	return 1.0 - exp(-rate * get_process_delta_time())


func _lean(amount: float) -> void:
	_final_pose(amount, amount * 0.52)
	creature.set_jaw_offset(-0.006 * amount)
	if not has_node("FaceFill"):
		var eye := to_local(player.camera.global_position)
		_creature_light("FaceFill", eye + face_basis * Vector3(-0.83, 0.51, -0.08), Color("#f0c9ac"), 0.0, 3.0)
		_creature_light("FaceRim", eye + face_basis * Vector3(0.65, 0.66, -1.48), Color("#8b9ecb"), 0.0, 3.0)
	# Its face is only properly lit once it is right in front of you.
	var reveal := smoothstep(0.16, 0.92, amount)
	$FaceFill.light_energy = 1.48 * reveal * light_level
	$FaceRim.light_energy = 0.82 * reveal * light_level


func _creature_light(title: String, at: Vector3, tint: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.name = title
	light.position = at
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = reach
	light.light_cull_mask = Creature.LIGHT_LAYER
	light.set_meta("energy", energy)
	add_child(light)


func _final_pose(amount: float, elapsed: float) -> void:
	var eye := to_local(player.camera.global_position)
	var shoulders := last_shoulders.lerp(eye + face_basis * Vector3(0, -0.46 + 0.07 * face_close, -0.90 + 0.4 * face_close), amount)
	# The body follows the shoulders up; the hands leave the floor and creep up
	# either side of your view instead of the arms being dragged.
	var pelvis := last_pelvis.lerp(shoulders + face_basis * Vector3(0, -0.42, -0.6), amount)
	var rise := smoothstep(0.25, 1.0, amount)
	var palms: Array[Vector3] = []
	var normals: Array[Vector3] = []
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		var grip := eye + face_basis * Vector3(side * (0.42 + 0.02 * sin(elapsed * 1.7 + i)), -0.6 + 0.1 * face_close, -0.66 + 0.25 * face_close)
		palms.append(last_palms[i].lerp(grip, rise) + Vector3.UP * sin(rise * PI) * 0.12)
		normals.append(last_normals[i].lerp(face_basis * Vector3(0, 0.25, -1).normalized(), rise).normalized())
	_pose(shoulders, pelvis, palms, normals, last_feet, 5.75 + elapsed, amount, last_foot_normals,
		face_back.slerp(Vector3.UP, smoothstep(0.0, 0.7, amount)))


func _hold_face(elapsed: float, speaking: bool) -> void:
	_final_pose(1.0, (1.58 + elapsed * 0.42) if speaking else (0.52 + elapsed / CLOSE_HOLD * 1.06))
	var sample := minf(elapsed * 20.0, FINAL_JAW.size() - 1)
	var index := floori(sample)
	var opening := lerpf(FINAL_JAW[index], FINAL_JAW[mini(index + 1, FINAL_JAW.size() - 1)], sample - index) / 255.0
	# Teeth chattering along with the clicks.
	var chatter := 0.0
	if not speaking and elapsed > 0.76 and elapsed < 1.85:
		chatter = 0.0028 if sin(elapsed * 92.0) > 0.0 else 0.0
	creature.set_jaw_offset(-0.003 - 0.007 * opening if speaking else -0.006 - chatter)
	shake = maxf(0.0, shake - get_process_delta_time() * 0.05)
	if is_instance_valid(breather):
		breather.global_position = creature.jaw.global_position


func _deliver_line() -> void:
	if is_instance_valid(breather):
		breather.queue_free()
	_speak(TRICKED, "", creature.jaw.global_position)


func _play_creature_sound(stream: AudioStream) -> void:
	creature_sound.global_position = creature.jaw.global_position if creature.visible else creature.global_position + Vector3.UP * 1.15
	creature_sound.stream = stream
	creature_sound.play()


func _speaker(distance: float) -> AudioStreamPlayer3D:
	var speaker := AudioStreamPlayer3D.new()
	speaker.unit_size = distance
	speaker.max_distance = 14.0
	speaker.volume_db = 1.0
	add_child(speaker)
	return speaker


func _speak(stream: AudioStream, line: String, at: Vector3, pitch: float = 1.0) -> void:
	voice.global_position = at
	voice.pitch_scale = pitch
	voice.stream = stream
	voice.play()
	caption.text = line


func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.layer = 8
	add_child(overlay)
	caption = Style.label("", roundi(22 * GameSettings.ui_scale))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_constant_override("outline_size", 6)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	overlay.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_left = 16
	caption.offset_right = -16
	caption.offset_top = -100
	caption.offset_bottom = -30


func _show_end() -> void:
	var black := ColorRect.new()
	black.color = Color.BLACK
	overlay.add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.hide()
	var button := Style.button("Main menu", roundi(23 * GameSettings.ui_scale))
	button.name = "EndButton"
	button.theme = Style.make_theme()
	black.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	button.offset_left = -98 * GameSettings.ui_scale
	button.offset_right = 98 * GameSettings.ui_scale
	button.offset_top = -25 * GameSettings.ui_scale
	button.offset_bottom = 25 * GameSettings.ui_scale
	button.pressed.connect(_return_to_menu)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	button.grab_focus()


func _return_to_menu() -> void:
	if not TripSave.save_trip():
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "Could not save your trip. Check available disk space and try again."
		overlay.add_child(dialog)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered()
		return
	get_tree().paused = false
	if NetworkManager.is_online():
		NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _process(delta: float) -> void:
	if not interior:
		return
	for i in lamps.size():
		lamps[i].light_energy = lamp_energy[i] * light_level
	for bulb in bulbs:
		bulb.emission_energy_multiplier = 2.2 * light_level
		bulb.albedo_color = Color("#f4dfb6") if light_level > 0.5 else Color("#3a3631")
	for title in ["StairLight", "StairRim", "StalkLight", "DoorLight"]:
		var light := get_node_or_null(title) as OmniLight3D
		if light:
			light.light_energy = light.get_meta("energy", light.light_energy) * light_level
	interior.ambient_light_energy = 0.19 * lerpf(0.06, 1.0, light_level)
	if roaming:
		_roam(delta)
	if stalking:
		_stalk(delta)
	if creature:
		creature.set_eyes(lerpf(7.0, 1.0, light_level), lerpf(1.0, eye_open, light_level))


func _set_lights(level: float) -> void:
	light_level = level


func _play_flicker() -> void:
	_play_at(FLICKER, to_global(Vector3(1.25, 2.9, -1.5)), randf_range(0.95, 1.05))


func _loop(stream: AudioStreamWAV, at: Vector3, volume: float) -> AudioStreamPlayer3D:
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	var speaker := _speaker(3.0)
	speaker.volume_db = volume
	speaker.stream = stream
	speaker.position = at
	speaker.play()
	return speaker


func _stop_ambience() -> void:
	for speaker in ambience:
		speaker.stop()


func _play_at(stream: AudioStream, at: Vector3, pitch: float = 1.0) -> void:
	## A one-off sound at a spot, without cutting off whatever else is playing.
	var speaker := _speaker(2.6)
	speaker.global_position = at
	speaker.pitch_scale = pitch
	speaker.stream = stream
	speaker.play()
	speaker.finished.connect(speaker.queue_free)


func _begin_stalk() -> void:
	creature.jitter = 0.0
	## The room is empty. You can look around now; it is somewhere in here.
	creature.tilt = 0.0
	creature.elbow_flip[0] = 0.0
	creature.elbow_flip[1] = 0.0
	camera_follow = false
	player.begin_ending_look()
	var eye := to_local(player.camera.global_position)
	var front := Vector3(0, 0, -1)
	# Down the side wall toward the front of the house, then onto the front
	# wall, and finally right beside you.
	stalk_spots = [
		{"center": Vector3(3.41, 2.75, 0.2), "normal": Vector3.LEFT, "heading": Vector3(0, -1, 0.5).normalized()},
		{"center": Vector3(3.41, 2.05, 2.35), "normal": Vector3.LEFT, "heading": Vector3(0, -0.55, 1).normalized()},
		{"center": Vector3(2.35, 2.3, 3.52), "normal": front, "heading": Vector3(-1, -0.4, 0).normalized()},
		{"center": Vector3(maxf(eye.x + 1.3, 1.6), eye.y - 0.3, 3.52), "normal": front, "heading": Vector3(-1, 0.12, 0).normalized()},
	]
	var light := OmniLight3D.new()
	light.name = "StalkLight"
	light.light_color = Color("#9fb0d6")
	light.omni_range = 3.2
	light.light_cull_mask = Creature.LIGHT_LAYER
	light.set_meta("energy", 0.55)
	add_child(light)
	var ceiling := create_tween()
	var clicks := _speaker(2.8)
	clicks.volume_db = -5.0
	clicks.stream = RAPID_CLICKS
	clicks.position = Vector3(1.6, 4.9, -1.6)
	ceiling.tween_callback(clicks.play)
	ceiling.tween_callback(caption.set_text.bind("[Clicking, across the ceiling]"))
	ceiling.tween_property(clicks, "position", Vector3(2.9, 4.6, 2.6), 1.6).set_trans(Tween.TRANS_SINE)
	ceiling.tween_callback(caption.set_text.bind(""))
	ceiling.tween_interval(1.1)
	# Your own voice again, from behind you, a little too low.
	var behind := to_global(stalk_spots[2]["center"] + Vector3(0, -0.6, -0.3))
	ceiling.tween_callback(_speak.bind(HELLO, "[Your voice, behind you] Hello?", behind, 0.93))
	ceiling.tween_interval(INTRO_QUESTION_CUE / 0.93)
	ceiling.tween_callback(caption.set_text.bind("[Your voice, behind you] Anybody there?"))
	ceiling.tween_interval((HELLO.get_length() - INTRO_QUESTION_CUE) / 0.93)
	ceiling.tween_callback(caption.set_text.bind(""))
	ceiling.tween_callback(clicks.queue_free)
	ceiling.tween_callback(func() -> void:
		stalk_index = -1
		stalk_clock = 0.0
		stalking = true)


func _stalk(delta: float) -> void:
	## It never moves while you look straight at it. Look away and it is
	## somewhere else, closer. Stare too long and the lights go instead.
	stalk_clock += delta
	if stalk_index < 0:
		# Show up first wherever you are not looking.
		if not _watching(stalk_spots[0]["center"]) or stalk_clock > 3.0:
			_place_at(0)
			_play_at(STEP, to_global(stalk_spots[0]["center"]), 0.7)
		return
	if _watching(creature.head.global_position, true):
		stalk_seen += delta
		stalk_unseen = 0.0
		stalk_found = true
	else:
		stalk_unseen += delta
		# Breathing, only while nobody is looking.
		_wall_pose(stalk_spots[stalk_index], stalk_clock)
	var last := stalk_index >= stalk_spots.size() - 2
	if stalk_seen > STARE_TIMEOUT:
		if last:
			_final_approach()
		else:
			_flicker_move()
	elif (stalk_found and stalk_unseen > MOVE_AFTER_LOOK_AWAY) or stalk_unseen > LOST_TIMEOUT:
		if last:
			_final_approach()
		elif not _watching(stalk_spots[stalk_index + 1]["center"]) or stalk_unseen > LOST_TIMEOUT + 2.5:
			_place_at(stalk_index + 1)
			_play_at(STEP, to_global(stalk_spots[stalk_index]["center"]), 0.66 + stalk_index * 0.04)


func _flicker_move() -> void:
	stalking = false
	var blink := create_tween()
	blink.tween_callback(_play_flicker)
	blink.tween_callback(_set_lights.bind(0.0))
	blink.tween_interval(0.45)
	blink.tween_callback(creature.hide)
	blink.tween_interval(0.55)
	blink.tween_callback(_place_at.bind(stalk_index + 1))
	blink.tween_callback(_set_lights.bind(1.0))
	blink.tween_callback(func() -> void: stalking = true)


func _watching(point: Vector3, global: bool = false) -> bool:
	## Whether you are looking more or less straight at a point.
	var at := point if global else to_global(point)
	var camera: Camera3D = player.camera
	var toward := (at - camera.global_position).normalized()
	return camera.is_position_in_frustum(at) and toward.dot(-camera.global_basis.z) > WATCHED_ANGLE


func _place_at(index: int) -> void:
	stalk_index = index
	stalk_seen = 0.0
	stalk_unseen = 0.0
	stalk_found = false
	var spot := stalk_spots[index]
	var light := get_node_or_null("StalkLight") as OmniLight3D
	if light:
		var eye := to_local(player.camera.global_position)
		light.position = spot["center"].lerp(eye, 0.45) + Vector3.UP * 0.6
		light.set_meta("energy", 0.75 if index == stalk_spots.size() - 1 else 0.55)
	_wall_pose(spot, stalk_clock)
	creature.show()


func _wall_pose(spot: Dictionary, seconds: float) -> void:
	## Flat against a wall, limbs splayed, head toward heading, face toward you.
	var normal: Vector3 = spot["normal"]
	var heading: Vector3 = spot["heading"]
	var across := normal.cross(heading).normalized()
	var wall: Vector3 = spot["center"]
	var center := wall + normal * (WALL_STANDOFF + 0.06 + sin(seconds * 2.3) * 0.012)
	creature.position = wall + normal * 0.4 - Vector3.UP * 1.0
	var palms: Array[Vector3] = []
	var feet: Array[Vector3] = []
	var normals: Array[Vector3] = [normal, normal]
	for i in range(2):
		var side := -1.0 if i == 0 else 1.0
		# One hand reaches further than the other.
		palms.append(wall + heading * (0.78 if i == 0 else 0.5) + across * side * 0.44)
		feet.append(wall - heading * 0.62 + across * side * 0.34)
	_pose(center + heading * 0.372, center - heading * 0.372, palms, normals, feet, 4.3 + sin(seconds) * 0.05, 0.0, normals, normal)


func _turn_to_creature(amount: float) -> void:
	player.aim_ending_camera(creature.head.global_position, lerpf(_camera_response(9.0), 1.0, amount * amount))


func _start_rush() -> void:
	## Off the wall and straight into your face.
	var eye := to_local(player.camera.global_position)
	var toward := (to_local(creature.head.global_position) - eye) * Vector3(1, 0, 1)
	face_basis = Basis.looking_at(toward.normalized(), Vector3.UP)
	face_back = stalk_spots[-1]["normal"]
	camera_follow = true
	shake = 0.035
	sting.stream = HIT
	sting.play()
	creature.jitter = 0.85
	var narrow := create_tween()
	narrow.tween_property(self, "eye_open", 0.0, 0.25)
	narrow.tween_interval(RUSH_TIME)
	narrow.tween_callback(func() -> void:
		breather = _loop(BREATH_CLOSE, to_local(creature.jaw.global_position), -9.0))


func _show_fake_end() -> void:
	## A calm, ordinary end card. It is not over.
	camera_follow = false
	caption.hide()
	fake_end = Control.new()
	fake_end.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(fake_end)
	fake_end.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fake_black = ColorRect.new()
	fake_black.color = Color(0, 0, 0, 0)
	fake_end.add_child(fake_black)
	fake_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fake_tilt = Control.new()
	fake_tilt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fake_end.add_child(fake_tilt)
	fake_tilt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fake_tilt.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	var card := VBoxContainer.new()
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", roundi(18 * GameSettings.ui_scale))
	fake_tilt.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for line: Array in [["KM0", 64], ["Thank you for playing.", 25], ["You made it to the end of the road.", 19]]:
		var label := Style.label(line[0], roundi(line[1] * GameSettings.ui_scale))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(label)
	var gap := Control.new()
	gap.custom_minimum_size.y = 24 * GameSettings.ui_scale
	card.add_child(gap)
	var button := Style.button("Main menu", roundi(23 * GameSettings.ui_scale))
	button.name = "ThanksButton"
	button.theme = Style.make_theme()
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(196, 50) * GameSettings.ui_scale
	card.add_child(button)
	button.pressed.connect(_fake_twist)
	fake_card = card
	card.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(fake_black, "color:a", 1.0, 0.7)
	fade.tween_property(card, "modulate:a", 1.0, 0.9)
	fade.tween_callback(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		button.grab_focus())
	fade.tween_interval(4.6)
	fade.tween_callback(_fake_twist)


func _fake_twist() -> void:
	## The card tips, the dark thins, and it was there behind it all along.
	if fake_twisted:
		return
	fake_twisted = true
	var button := fake_card.get_node_or_null("ThanksButton") as Button
	if button:
		button.disabled = true
		button.release_focus()
	face_close = 0.0
	var face_light := get_node_or_null("FaceFill") as OmniLight3D
	if face_light:
		face_light.light_color = Color("#d98a78")
	var face_rim := get_node_or_null("FaceRim") as OmniLight3D
	if face_rim:
		face_rim.light_energy = 0.0
	_play_creature_sound(THROAT_RATTLE)
	var twist := create_tween()
	twist.tween_property(fake_tilt, "rotation", deg_to_rad(2.6), 1.7).set_trans(Tween.TRANS_SINE)
	twist.parallel().tween_property(fake_black, "color:a", 0.6, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	twist.parallel().tween_property(fake_card, "modulate", Color(0.55, 0.5, 0.5, 0.85), 1.7)
	twist.parallel().tween_method(_behind_card, 0.0, 1.0, 1.7)
	twist.tween_interval(0.4)
	twist.tween_callback(func() -> void:
		fake_black.color.a = 0.0
		fake_card.hide()
		sting.stream = HIT
		sting.play()
		shake = 0.04)
	twist.tween_method(_lunge, 0.0, 1.0, 0.16).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	twist.tween_method(_lunge, 1.0, 1.0, 0.22)
	twist.tween_callback(func() -> void:
		fake_black.color.a = 1.0
		creature.hide()
		_set_lights(0.0))
	twist.tween_interval(1.8)
	twist.tween_callback(func() -> void:
		fake_end.hide()
		_show_end())


func _behind_card(amount: float) -> void:
	face_close = 0.0
	_final_pose(1.0, 2.2 + amount * 0.3)
	creature.set_jaw_offset(-0.006 - 0.002 * amount)
	var face_light := get_node_or_null("FaceFill") as OmniLight3D
	if face_light:
		face_light.light_energy = 0.9 * amount


func _lunge(amount: float) -> void:
	face_close = amount
	_final_pose(1.0, 2.5)
	creature.set_jaw_offset(-0.008 - 0.004 * amount)
	shake = maxf(0.0, shake - get_process_delta_time() * 0.06)
	var face_light := get_node_or_null("FaceFill") as OmniLight3D
	if face_light:
		face_light.light_energy = 1.6
