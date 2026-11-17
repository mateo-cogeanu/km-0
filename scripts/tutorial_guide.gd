extends CanvasLayer
## The first trip's tutorial: County's job sheet in the corner of the screen.
## Each step ticks itself off when you actually do it, with a short hint for
## the one you are on. Shown once (GameSettings.tutorial_done); skip it or
## bring it back from the pause menu.

const Style := preload("res://scripts/menu_style.gd")
const RoadEndHouse := preload("res://scripts/road_end_house.gd")
const RoadRadio := preload("res://scripts/road_radio.gd")
const PARTS := ["engine", "radiator", "battery"]

const STEPS := [
	["Listen to the radio", "County is calling on the workshop radio, on the bench."],
	["Look the car over", "Walk up to the car in the workshop and see what is missing."],
	["Fit the missing parts", "The parts are around the shack. Pick one up (E), carry it to its empty mount, and press E when the tip says Install. Open the hood (E) for the engine bay."],
	["Fill the tank", "Carry the fuel can to the car, open the fuel cap (E), aim at the filler and press E to refuel."],
	["Open the shutter and get in", "Open the garage shutter (E), then get in at the driver's door (E)."],
	["Drive east", "Follow the road away from the workshop. The posts count the kilometres."],
	["Check in at station 1", "Pull in where the sign says STATION 1, find its radio and check in (E)."],
]
const DONE := "That's the job. Keep driving east and check in at every station.\nLook after yourself: R eats or drinks what you hold, Z sleeps in a parked car, F is the flashlight, Q is your pack."

var step := 0
var car: Node3D
var panel: PanelContainer
var rows: Array[Label] = []
var hint: Label
var parts: Label
var finished_at := -1.0
var clock := 0.0
var started_radio_at := -1.0


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_PAUSABLE
	panel = PanelContainer.new()
	panel.theme = Style.make_theme()
	panel.add_theme_stylebox_override("panel", Style.box(Color(0.06, 0.06, 0.05, 0.82), Style.LINE, 10))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var column := Style.vbox(6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var heading := Style.label("COUNTY JOB SHEET", 15, Style.AMBER)
	column.add_child(heading)
	for entry: Array in STEPS:
		var row := Style.label("", 16)
		column.add_child(row)
		rows.append(row)
	parts = Style.label("", 14)
	parts.add_theme_color_override("font_color", Color("#cfc6b4"))
	column.add_child(parts)
	hint = Style.label("", 14)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 360
	hint.add_theme_color_override("font_color", Color("#d9cfba"))
	column.add_child(hint)
	var skip := Style.label("Esc  ·  Skip tutorial in the pause menu", 12)
	skip.add_theme_color_override("font_color", Color("#8d8576"))
	column.add_child(skip)
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	panel.scale = Vector2.ONE * GameSettings.ui_scale * 0.85
	panel.position = Vector2(18, 18)


func _process(delta: float) -> void:
	clock += delta
	var player := get_tree().get_first_node_in_group("local_player") as Node3D
	if player == null:
		return
	if car == null or not is_instance_valid(car):
		car = _find_car(player)
	if finished_at >= 0.0:
		if clock - finished_at > 14.0:
			finish()
		return
	# Steps already done (a continued trip, or done out of order) tick at once.
	while step < STEPS.size() and _done(step, player):
		step += 1
	if step >= STEPS.size():
		finished_at = clock
	_draw(player)


func _done(index: int, player: Node3D) -> bool:
	match index:
		0:
			var radio := get_tree().current_scene.find_child("WorkshopRadio", true, false) if get_tree().current_scene else null
			if radio and radio.replying:
				started_radio_at = clock
				return false
			return RoadEndHouse.story.get("intro_played", false) and clock > 6.0
		1:
			if car == null:
				return false
			var camera: Camera3D = player.camera if "camera" in player else null
			var to := car.global_position - player.global_position
			var looking := camera == null or to.normalized().dot(-camera.global_basis.z) > 0.6
			return to.length() < 5.0 and looking
		2:
			return car != null and _missing().is_empty()
		3:
			return car != null and "fuel_amount" in car and car.fuel_amount >= 12.0
		4:
			return car != null and player.active_vehicle == car
		5:
			return player.global_position.z < -150.0
		6:
			var checked: Dictionary = RoadEndHouse.story.get("checked_in", {})
			for key: String in checked:
				if int(key) != RoadRadio.Broadcast.WORKSHOP:
					return true
			return false
	return false


func _missing() -> Array:
	var missing := []
	if car == null or not "removable_parts" in car:
		return missing
	for part: String in PARTS:
		var data: Dictionary = car.removable_parts.get(part, {})
		if not data.get("installed", false):
			missing.append(part)
	var wheels := 0
	for slot in ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]:
		if car.removable_parts.get(slot, {}).get("installed", false):
			wheels += 1
	if wheels < 4:
		missing.append("wheels (%d of 4 on)" % wheels)
	return missing


func _draw(_player: Node3D) -> void:
	for i in rows.size():
		var mark := "✔ " if i < step else ("▸ " if i == step else "   ")
		rows[i].text = mark + STEPS[i][0]
		rows[i].add_theme_color_override("font_color", Color("#7f9b74") if i < step else (Color("#f2e6c9") if i == step else Color("#8d8576")))
	if finished_at >= 0.0:
		hint.text = DONE
		parts.text = ""
		return
	hint.text = STEPS[step][1]
	parts.text = ""
	if step == 2:
		var missing := _missing()
		parts.text = "Still missing: " + ", ".join(missing) if not missing.is_empty() else ""


func _find_car(player: Node3D) -> Node3D:
	var best: Node3D = null
	for candidate: Node3D in get_tree().get_nodes_in_group("drivable"):
		if "removable_parts" in candidate and (best == null or candidate.global_position.distance_to(player.global_position) < best.global_position.distance_to(player.global_position)):
			best = candidate
	return best


func finish() -> void:
	## Done or skipped: it will not come back on its own.
	GameSettings.tutorial_done = true
	GameSettings.save_settings()
	queue_free()
