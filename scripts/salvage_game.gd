extends Node3D
## The Salvage Run, first night: the ridge camp above the drowned town of
## Marrow, the road down, and one flooded street of abandoned cars. Strip
## what the buyer wants, get it onto the pallet at the camp, and get everyone
## back up the hill before the water rises. Something in the water hunts by
## sound (salvage_listener.gd); salvage_noise.gd works out how loud you are.
## The host runs the creature and decides how the night ends.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CAR_SCENE := preload("res://scenes/car.tscn")
const Shapes := preload("res://scripts/prop_shapes.gd")
const Style := preload("res://scripts/menu_style.gd")
const NoiseField := preload("res://scripts/salvage_noise.gd")
const Listener := preload("res://scripts/salvage_listener.gd")
const WATER_BED := preload("res://assets/audio/salvage/water_bed.wav")
const SPLASHES := [
	preload("res://assets/audio/salvage/splash_1.wav"), preload("res://assets/audio/salvage/splash_2.wav"),
	preload("res://assets/audio/salvage/splash_3.wav"), preload("res://assets/audio/salvage/splash_4.wav"),
]

## The ground: the ridge is at 0, the street floor six metres below, and the
## road between them runs from RAMP_TOP down to RAMP_BOTTOM.
const FLOOR_Y := -6.0
const RAMP_TOP := 8.0
const RAMP_BOTTOM := -40.0
const STREET_END := -150.0
const STREET_HALF := 9.0
const KERB_TOP := -4.75
## The water starts knee deep and rises through the night.
const WATER_START := -5.2
const WATER_END := -4.55
const NIGHT_SECONDS := 900.0
const RIDGE_Z := 6.0
const PALLET := Vector3(7.5, 0.0, 17.0)
const CONTRACT := {"battery": 2, "radiator": 1, "engine": 1}
const TITLES := {"battery": "Batteries", "radiator": "Radiator", "engine": "Engine (any)"}

var clock := 0.0
var water_level := WATER_START
var water: MeshInstance3D
var water_material: StandardMaterial3D
var noise: Node
var listener: Node3D
var hud: CanvasLayer
var contract_label: Label
var timer_label: Label
var message_label: Label
var noise_bar: ProgressBar
var message_time := 0.0
var ended := false
var delivered := {}
var pallet_area: Area3D
var lap: AudioStreamPlayer3D


func _ready() -> void:
	_build_ground()
	_build_town()
	_build_camp()
	noise = NoiseField.new()
	noise.name = "Noise"
	noise.game = self
	add_child(noise)
	listener = Listener.new()
	listener.name = "Listener"
	listener.game = self
	add_child(listener)
	_build_hud()
	await get_tree().process_frame
	_spawn_cars()
	_spawn_players()


static func is_host() -> bool:
	return not NetworkManager.is_online() or NetworkManager.multiplayer.is_server()


# --- The ground ------------------------------------------------------------------

func ground_height(x: float, z: float) -> float:
	if z >= RAMP_TOP:
		return 0.0
	if z > RAMP_BOTTOM and absf(x) < 6.0:
		return lerpf(FLOOR_Y, 0.0, (z - RAMP_BOTTOM) / (RAMP_TOP - RAMP_BOTTOM))
	if absf(x) > STREET_HALF and absf(x) < 14.0 and z < -44.0 and z > STREET_END:
		return KERB_TOP
	return FLOOR_Y


func in_water(point: Vector3) -> bool:
	## Standing (or lying) in the flood: the ground here is under the water.
	return ground_height(point.x, point.z) < water_level - 0.05 and point.y < water_level + 1.2


func water_depth(point: Vector3) -> float:
	return maxf(water_level - ground_height(point.x, point.z), 0.0)


func _build_ground() -> void:
	var mud := Shapes.material(Color("#3d3428"), 0.0, 0.95)
	var asphalt := Shapes.material(Color("#2b2a28"), 0.0, 0.9)
	var concrete := Shapes.material(Color("#5b574f"), 0.0, 0.92)
	var grass := Shapes.material(Color("#4d5034"), 0.0, 1.0)
	# The ridge, and the hillside below it.
	var ridge := Shapes.box(self, "Ridge", Vector3(70, 2, 40), Vector3(0, -1, 28), grass, true)
	ridge.get_child(0).add_to_group("Dirt")
	for side in [-1.0, 1.0]:
		var bank := Shapes.box(self, "Bank", Vector3(28, 2, 52), Vector3(side * 20.0, -3.2, -16), mud, true)
		bank.rotation.x = deg_to_rad(-7.1)
		bank.get_child(0).add_to_group("Dirt")
	# The road down: one long slope from the ridge to the street.
	var length := RAMP_TOP - RAMP_BOTTOM
	var ramp := Shapes.box(self, "RoadDown", Vector3(12, 0.6, sqrt(length * length + 36.0)),
		Vector3(0, FLOOR_Y * 0.5 - 0.3, (RAMP_TOP + RAMP_BOTTOM) * 0.5), asphalt, true)
	ramp.rotation.x = -atan2(-FLOOR_Y, length)
	ramp.get_child(0).add_to_group("Road")
	# The drowned street and everything around it.
	var street := Shapes.box(self, "Street", Vector3(90, 2, 140), Vector3(0, FLOOR_Y - 1.0, -100), asphalt, true)
	street.get_child(0).add_to_group("Road")
	Shapes.box(self, "Below", Vector3(90, 2, 50), Vector3(0, FLOOR_Y - 1.02, -15), mud, true)
	for side in [-1.0, 1.0]:
		var kerb := Shapes.box(self, "Pavement", Vector3(5, KERB_TOP - FLOOR_Y, -STREET_END - 44.0),
			Vector3(side * (STREET_HALF + 2.5), (KERB_TOP + FLOOR_Y) * 0.5, (STREET_END - 44.0) * 0.5), concrete, true)
		kerb.get_child(0).add_to_group("Road")
	water_material = StandardMaterial3D.new()
	water_material.albedo_color = Color(0.07, 0.075, 0.05, 0.95)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.roughness = 0.06
	water_material.metallic_specular = 0.55
	water_material.normal_enabled = true
	var ripples := NoiseTexture2D.new()
	ripples.seamless = true
	ripples.as_normal_map = true
	ripples.bump_strength = 2.5
	ripples.width = 256
	ripples.height = 256
	var pattern := FastNoiseLite.new()
	pattern.frequency = 0.03
	ripples.noise = pattern
	water_material.normal_texture = ripples
	water_material.normal_scale = 0.35
	water_material.uv1_scale = Vector3(18, 18, 1)
	water = MeshInstance3D.new()
	water.name = "Floodwater"
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 190)
	water.mesh = plane
	water.material_override = water_material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	water.position = Vector3(0, water_level, -85)
	lap = AudioStreamPlayer3D.new()
	lap.stream = _looped(WATER_BED)
	lap.unit_size = 30.0
	lap.max_distance = 160.0
	lap.volume_db = -6.0
	add_child(lap)
	lap.position = Vector3(0, -4.5, -80)
	lap.play()


func _build_town() -> void:
	## Houses along both sides, flooded to the window sills, porches and
	## pavement just above the water; a dead street light here and there.
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var walls := [Color("#6d6658"), Color("#5c6560"), Color("#76695a"), Color("#4f5458"), Color("#6a5f55")]
	var dark := Shapes.material(Color("#0b0b0c"))
	var trim := Shapes.material(Color("#8d877a"))
	var roof := Shapes.material(Color("#2a2522"), 0.0, 0.85)
	for side in [-1.0, 1.0]:
		var z := -48.0
		while z > STREET_END + 8.0:
			var width := rng.randf_range(9.0, 13.0)
			var depth := rng.randf_range(9.0, 12.0)
			var height := rng.randf_range(4.5, 7.0)
			var house := Node3D.new()
			house.name = "House"
			add_child(house)
			house.position = Vector3(side * (14.0 + depth * 0.5), FLOOR_Y, z - width * 0.5)
			house.rotation.y = -side * PI * 0.5
			var paint := Shapes.material(walls[rng.randi_range(0, walls.size() - 1)], 0.0, 0.9)
			Shapes.box(house, "Walls", Vector3(width, height, depth), Vector3(0, height * 0.5, 0), paint, true)
			var top := Shapes.box(house, "Roof", Vector3(width + 0.6, 0.4, depth * 0.62), Vector3(0, height + 0.9, -depth * 0.2), roof)
			top.rotation.x = 0.5
			var back := Shapes.box(house, "Roof", Vector3(width + 0.6, 0.4, depth * 0.62), Vector3(0, height + 0.9, depth * 0.2), roof)
			back.rotation.x = -0.5
			# The front faces the street (+Z here): a door, black windows.
			var front := depth * 0.5 + 0.02
			Shapes.box(house, "Door", Vector3(1.1, 2.1, 0.06), Vector3(rng.randf_range(-1.5, 1.5), 1.25 + 1.0, front), dark)
			for w in [-width * 0.3, width * 0.3]:
				Shapes.box(house, "Window", Vector3(1.4, 1.2, 0.05), Vector3(w, 2.6, front), dark)
				Shapes.box(house, "Sill", Vector3(1.6, 0.08, 0.14), Vector3(w, 1.98, front + 0.05), trim)
				if height > 5.5:
					Shapes.box(house, "Window", Vector3(1.2, 1.0, 0.05), Vector3(w, height - 1.6, front), dark)
			# A tide line where the water stood for years.
			Shapes.box(house, "TideLine", Vector3(width + 0.02, 0.5, depth + 0.02), Vector3(0, 1.55, 0), Shapes.material(Color(0.2, 0.18, 0.13)))
			z -= width + rng.randf_range(1.5, 4.0)
		for k in 4:
			var post := Shapes.cylinder(self, "StreetLight", Vector3(side * (STREET_HALF + 0.6), KERB_TOP + 2.6, -60.0 - k * 26.0), Vector3.UP, 0.08, 5.2, trim, 8)
			post.rotation.z = side * rng.randf_range(0.0, 0.12)
	# Rubbish caught in the flood: drums, planks and a fallen fence.
	var rust := Shapes.material(Color("#5a3a26"), 0.3, 0.7)
	var wood := Shapes.material(Color("#4a3c2e"))
	for i in 14:
		var at := Vector3(rng.randf_range(-8.0, 8.0), FLOOR_Y, rng.randf_range(-48.0, STREET_END + 6.0))
		if rng.randf() < 0.5:
			var drum := Shapes.cylinder(self, "Drum", at + Vector3(0, 0.3, 0), Vector3(rng.randf_range(-1, 1), 0.3, rng.randf_range(-1, 1)).normalized(), 0.3, 0.85, rust, 12)
			drum.rotation.y = rng.randf_range(0, TAU)
		else:
			var plank := Shapes.box(self, "Plank", Vector3(0.25, 0.05, rng.randf_range(1.5, 3.0)), at + Vector3(0, water_level - FLOOR_Y + 0.01, 0), wood)
			plank.rotation.y = rng.randf_range(0, TAU)
	# The way the water came: a storm drain at the far end, black and open.
	Shapes.box(self, "DrainMouth", Vector3(6.0, 2.4, 0.4), Vector3(0, FLOOR_Y + 1.0, STREET_END + 0.5), dark)
	Shapes.box(self, "EndWall", Vector3(30, 9, 1.0), Vector3(0, FLOOR_Y + 4.5, STREET_END - 0.2), Shapes.material(Color("#3a3833")), true)


func _build_camp() -> void:
	## The ridge camp: the buyer's pallet under a work lamp, a tent and the
	## contract nailed to a post.
	var wood := Shapes.material(Color("#7a6447"))
	for i in 5:
		Shapes.box(self, "PalletSlat", Vector3(2.4, 0.04, 0.32), PALLET + Vector3(0, 0.14, -1.0 + i * 0.5), wood)
	for x in [-1.0, 0.0, 1.0]:
		Shapes.box(self, "PalletBlock", Vector3(0.18, 0.12, 2.4), PALLET + Vector3(x * 1.1, 0.06, 0), wood)
	var base := Shapes.box(self, "PalletBase", Vector3(2.4, 0.1, 2.4), PALLET + Vector3(0, 0.05, 0), wood, true)
	base.visible = false
	pallet_area = Area3D.new()
	pallet_area.name = "Pallet"
	pallet_area.collision_layer = 0
	pallet_area.collision_mask = 16
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 2.4, 3.2)
	shape.shape = box
	pallet_area.add_child(shape)
	add_child(pallet_area)
	pallet_area.position = PALLET + Vector3(0, 1.2, 0)
	var steel := Shapes.material(Color("#3c3c3a"), 0.6, 0.5)
	Shapes.cylinder(self, "LampPost", PALLET + Vector3(-1.8, 1.6, -1.6), Vector3.UP, 0.05, 3.2, steel, 8)
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 6.0
	lamp.spot_range = 14.0
	lamp.spot_angle = 55.0
	lamp.shadow_enabled = true
	add_child(lamp)
	lamp.position = PALLET + Vector3(-1.6, 3.3, -1.4)
	lamp.look_at(PALLET, Vector3.FORWARD)
	var board := Label3D.new()
	board.text = "MARROW SALVAGE\nBUYER'S PALLET"
	board.font_size = 64
	board.pixel_size = 0.006
	board.modulate = Color(0.95, 0.88, 0.7)
	board.outline_size = 8
	add_child(board)
	board.position = PALLET + Vector3(0, 2.3, -1.9)
	# A tent and a crate to sit on.
	var canvas := Shapes.material(Color("#4f5a3c"))
	for side in [-1.0, 1.0]:
		var sheet := Shapes.box(self, "Tent", Vector3(0.04, 2.0, 3.2), Vector3(-8.0 + side * 0.7, 0.9, 20.0), canvas)
		sheet.rotation.z = side * 0.62
	Shapes.box(self, "Crate", Vector3(0.7, 0.5, 0.7), Vector3(-6.0, 0.25, 17.5), wood, true)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.3)
	glow.light_energy = 1.2
	glow.omni_range = 7.0
	add_child(glow)
	glow.position = Vector3(-7.5, 0.6, 18.5)


# --- Cars and players -----------------------------------------------------------

func _spawn_cars() -> void:
	## The truck at the camp, and the cars left in the street when the water
	## came: one electric, one V8, the rest ordinary. None of them will start.
	var truck := CAR_SCENE.instantiate()
	truck.name = "Truck"
	truck.start_with_removed_panels = false
	truck.start_with_random_body_color = false
	add_child(truck)
	truck.global_transform = Transform3D(Basis(Vector3.UP, 0.0), Vector3(0, 0.45, 26))
	truck.fuel_amount = 45.0
	truck.reset_physics_interpolation()
	var spots := [[-5.4, -56.0, 0.08, "Stock"], [5.2, -72.0, PI - 0.1, "Stock"], [-5.0, -90.0, -0.15, "Stock"],
		[5.5, -104.0, PI + 0.06, "Electric"], [-5.6, -121.0, 0.2, "Stock"], [4.8, -137.0, PI - 0.25, "V8"]]
	for i in spots.size():
		var spot: Array = spots[i]
		var car := CAR_SCENE.instantiate()
		car.name = "Flooded_%d" % (i + 1)
		car.start_with_removed_panels = false
		car.starting_engine_variant = spot[3]
		car.body_style = i % 3
		add_child(car)
		car.global_transform = Transform3D(Basis(Vector3.UP, spot[2]), Vector3(spot[0], FLOOR_Y + 0.45, spot[1]))
		car.fuel_amount = 0.0
		car.electric_charge = 0.0
		car.reset_physics_interpolation()


func _spawn_players() -> void:
	var ids: Array = NetworkManager.players.keys() if NetworkManager.is_online() else [1]
	ids.sort()
	for index in ids.size():
		var peer_id := int(ids[index])
		var player := PLAYER_SCENE.instantiate()
		player.name = str(peer_id)
		player.player_name = str(NetworkManager.players.get(peer_id, {}).get("name", GameSettings.player_name))
		player.position = Vector3(-3.0 + index * 1.2, 1.05, 20.0)
		if NetworkManager.is_online():
			player.set_multiplayer_authority(peer_id)
		add_child(player)
		player.rotation.y = 0.0
		player.last_safe_position = player.global_position
	if NetworkManager.is_online():
		NetworkManager.player_disconnected.connect(_remove_player)
	var me := local_player()
	if me:
		me.camera.make_current()
	show_message("The buyer wants: two batteries, a radiator and an engine, on the pallet by morning.\nGo quietly. Sound carries over water.", 9.0)


func local_player() -> CharacterBody3D:
	return get_tree().get_first_node_in_group("local_player") as CharacterBody3D


func players() -> Array:
	return get_tree().get_nodes_in_group("road_stream_player")


func _remove_player(peer_id: int) -> void:
	var player := get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
	for vehicle in get_tree().get_nodes_in_group("drivable"):
		vehicle.remove_disconnected_rider(peer_id)


# --- The night -----------------------------------------------------------------

func _process(delta: float) -> void:
	if not ended:
		clock += delta
	water_level = lerpf(WATER_START, WATER_END, clampf(clock / NIGHT_SECONDS, 0.0, 1.0))
	water.position.y = water_level
	water_material.uv1_offset += Vector3(0.004, 0.0025, 0) * delta
	var me := local_player()
	if me:
		var wet := in_water(me.global_position + Vector3.DOWN * 0.9) and not is_instance_valid(me.active_vehicle)
		me.terrain_speed_scale = lerpf(1.0, 0.62, clampf(water_depth(me.global_position) / 0.8, 0.0, 1.0)) if wet else 1.0
	for player: Node in players():
		player.step_sounds = SPLASHES if in_water(player.global_position + Vector3.DOWN * 0.9) else []
	_count_pallet()
	_update_hud(delta)
	if is_host() and not ended:
		_check_end()


func _count_pallet() -> void:
	delivered = {}
	for body in pallet_area.get_overlapping_bodies():
		var kind := String(body.get_meta("vehicle_part_type", ""))
		if body.has_meta("held_by"):
			continue
		if kind == "aux_battery":
			kind = "battery"
		if CONTRACT.has(kind):
			delivered[kind] = int(delivered.get(kind, 0)) + 1


func contract_met() -> bool:
	for kind: String in CONTRACT:
		if int(delivered.get(kind, 0)) < CONTRACT[kind]:
			return false
	return true


func _check_end() -> void:
	if clock >= NIGHT_SECONDS:
		_end_everywhere("flooded")
		return
	if not contract_met():
		return
	for player: Node3D in players():
		if player.global_position.z < RIDGE_Z and not listener.is_taken(player):
			return
	_end_everywhere("filled")


func _end_everywhere(how: String) -> void:
	if NetworkManager.is_online():
		end_night.rpc(how)
	else:
		end_night(how)


@rpc("authority", "call_local", "reliable")
func end_night(how: String) -> void:
	if ended:
		return
	ended = true
	var me := local_player()
	if me:
		if is_instance_valid(me.active_vehicle):
			me._exit_vehicle()
		me.lock_for_ending(me.global_position)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var card := ColorRect.new()
	card.color = Color(0.03, 0.03, 0.025, 0.0)
	hud.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := Style.vbox(16)
	column.theme = Style.make_theme()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lines := {
		"filled": ["Contract filled.", "The buyer's truck came up the hill at first light, counted the parts twice and paid in cash.\nBelow, the water lay flat and still over Marrow, as if nothing lived in it at all."],
		"flooded": ["The water took the street.", "By first light there was nothing left of Marrow but rooftops.\nThe buyer doesn't pay for parts that aren't on the pallet."],
	}
	for i in 2:
		var label := Style.label(lines[how][i], 40 if i == 0 else 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 760
		label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(label)
	var button := Style.button("Back to the menu", 22)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func() -> void:
		NetworkManager.leave_lobby()
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	column.add_child(button)
	create_tween().tween_property(card, "color:a", 0.88, 2.5)


# --- The HUD -------------------------------------------------------------------

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "SalvageHUD"
	hud.layer = 5
	add_child(hud)
	var panel := PanelContainer.new()
	panel.theme = Style.make_theme()
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.05, 0.06, 0.05, 0.78), Style.LINE, 10))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(panel)
	panel.position = Vector2(18, 18)
	var column := Style.vbox(4)
	panel.add_child(column)
	column.add_child(Style.label("THE BUYER WANTS", 14, Style.AMBER))
	contract_label = Style.label("", 16)
	column.add_child(contract_label)
	timer_label = Style.label("", 14)
	timer_label.add_theme_color_override("font_color", Color("#9fb4c0"))
	column.add_child(timer_label)
	message_label = Style.label("", 20)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_constant_override("outline_size", 6)
	message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hud.add_child(message_label)
	var meter := Style.vbox(2)
	meter.name = "NoiseMeter"
	hud.add_child(meter)
	var caption := Style.label("NOISE", 12, Style.AMBER)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meter.add_child(caption)
	noise_bar = ProgressBar.new()
	noise_bar.show_percentage = false
	noise_bar.max_value = 1.0
	noise_bar.custom_minimum_size = Vector2(220, 8)
	meter.add_child(noise_bar)
	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud()


func _layout_hud() -> void:
	var size := get_viewport().get_visible_rect().size
	message_label.size = Vector2(minf(820.0, size.x - 40.0), 120)
	message_label.position = Vector2((size.x - message_label.size.x) * 0.5, size.y * 0.2)
	var meter := hud.get_node("NoiseMeter") as Control
	meter.position = Vector2(size.x * 0.5 - 110.0, size.y - 120.0)


func show_message(text: String, seconds := 4.0) -> void:
	message_label.text = text
	message_time = seconds


@rpc("authority", "call_local", "reliable")
func broadcast_message(text: String, seconds: float) -> void:
	show_message(text, seconds)


func _update_hud(delta: float) -> void:
	var lines := []
	for kind: String in CONTRACT:
		var have := mini(int(delivered.get(kind, 0)), CONTRACT[kind])
		var mark := "✔" if have >= CONTRACT[kind] else "·"
		lines.append("%s %s  %d/%d" % [mark, TITLES[kind], have, CONTRACT[kind]])
	contract_label.text = "\n".join(lines)
	var left := maxf(NIGHT_SECONDS - clock, 0.0)
	timer_label.text = "Water rising  ·  %d:%02d to first light" % [int(left) / 60, int(left) % 60]
	message_time -= delta
	message_label.modulate.a = clampf(message_time, 0.0, 1.0)
	noise_bar.value = lerpf(noise_bar.value, noise.local_level, 1.0 - exp(-10.0 * delta))
	noise_bar.modulate = Color(0.55, 0.75, 0.5).lerp(Color(0.95, 0.35, 0.25), clampf(noise_bar.value * 1.4, 0.0, 1.0))


func _looped(stream: AudioStreamWAV) -> AudioStreamWAV:
	var copy := stream.duplicate() as AudioStreamWAV
	copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
	copy.loop_begin = 0
	copy.loop_end = int(copy.get_length() * copy.mix_rate)
	return copy
