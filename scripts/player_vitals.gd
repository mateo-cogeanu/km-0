extends Node
## Health, hunger and stamina for the local player, their bars, and the
## vignette that closes in after dark.

const Style := preload("res://scripts/menu_style.gd")
const VIGNETTE := preload("res://assets/ui/vignette.gdshader")

## A full stomach lasts about this many seconds of play.
const HUNGER_SECONDS := 1250.0
const STARVING_DAMAGE := 0.5
const HEAL_RATE := 0.25
const SPRINT_DRAIN := 17.0
const JUMP_COST := 9.0
const STAMINA_REGEN := 15.0
const REGEN_DELAY := 0.9
const RECOVER_AT := 25.0
## A full drink of water lasts about this long; staying awake this long makes
## you exhausted. A flashlight battery lasts this many seconds switched on.
const THIRST_SECONDS := 950.0
const THIRST_DAMAGE := 0.7
const AWAKE_SECONDS := 2400.0
const BATTERY_SECONDS := 480.0

var player: CharacterBody3D
var health := 100.0
var hunger := 100.0
var stamina := 100.0
var thirst := 100.0
var fatigue := 0.0
var battery := 100.0
var blink_wait := 20.0
var exhausted := false
var regen_wait := 0.0
var passing_out := false
var spawn_point := Vector3.ZERO
var panel: VBoxContainer
var bars := {}
var vignette: ColorRect
var vignette_material: ShaderMaterial
var hurt := 0.0
var blackout: ColorRect


func setup(owner_player: CharacterBody3D, layer: CanvasLayer) -> void:
	player = owner_player
	spawn_point = player.global_position
	vignette = ColorRect.new()
	vignette.name = "Vignette"
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_material = ShaderMaterial.new()
	vignette_material.shader = VIGNETTE
	vignette.material = vignette_material
	layer.add_child(vignette)
	layer.move_child(vignette, 0)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = VBoxContainer.new()
	panel.name = "Vitals"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	for stat: Array in [["health", "Health", Color("#a8473d")], ["hunger", "Hunger", Color("#b08a3c")], ["thirst", "Thirst", Color("#4f86b0")],
			["stamina", "Stamina", Color("#6f9a6a")], ["rest", "Rest", Color("#8a7fb0")], ["battery", "Torch", Color("#d8c27a")]]:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		var label := Style.label(stat[1], 13)
		label.custom_minimum_size.x = 64
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		row.add_child(label)
		var back := ColorRect.new()
		back.color = Color(0.05, 0.05, 0.05, 0.55)
		back.custom_minimum_size = Vector2(130, 8)
		back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(back)
		var fill := ColorRect.new()
		fill.color = stat[2]
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.add_child(fill)
		fill.size = Vector2(130, 8)
		bars[stat[0]] = [fill, label]
	blackout = ColorRect.new()
	blackout.color = Color(0, 0, 0, 0)
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(blackout)
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout()


var _laid_out_for := Vector4.ZERO


func layout() -> void:
	# Bottom right, clear of the driving and fuel readouts on the left. Only
	# redone when the screen, the UI scale or the panel's size changes.
	var screen := player.get_viewport().get_visible_rect().size
	# Scaled with the window like the menus, so it stays readable on big screens.
	var ui := preload("res://scripts/menu_style.gd").ui_scale(screen)
	var key := Vector4(screen.x, screen.y, ui, panel.size.y)
	if key == _laid_out_for:
		return
	_laid_out_for = key
	panel.scale = Vector2.ONE * ui
	panel.position = Vector2(screen.x - 220 * ui, screen.y - (panel.get_combined_minimum_size().y + 22) * ui)


func can_sprint() -> bool:
	return not exhausted and stamina > 0.0


func sprinting(delta: float) -> void:
	stamina = maxf(0.0, stamina - SPRINT_DRAIN * delta)
	hunger = maxf(0.0, hunger - 100.0 / HUNGER_SECONDS * delta)
	thirst = maxf(0.0, thirst - 100.0 / THIRST_SECONDS * delta)
	fatigue = minf(100.0, fatigue + 100.0 / AWAKE_SECONDS * delta)
	regen_wait = REGEN_DELAY
	if stamina <= 0.0:
		exhausted = true


func can_jump() -> bool:
	return stamina >= JUMP_COST * 0.5


func jumped() -> void:
	stamina = maxf(0.0, stamina - JUMP_COST)
	regen_wait = REGEN_DELAY


func eat(food: Node) -> void:
	hunger = minf(100.0, hunger + food.hunger_value())
	stamina = minf(100.0, stamina + food.stamina_value())
	health = minf(100.0, health + food.health_value())
	if stamina > RECOVER_AT:
		exhausted = false


func drink(amount: float) -> void:
	thirst = minf(100.0, thirst + amount)


func can_sleep() -> bool:
	return fatigue >= 30.0


func slept() -> void:
	fatigue = 0.0
	hunger = maxf(5.0, hunger - 25.0)
	thirst = maxf(5.0, thirst - 35.0)
	health = minf(100.0, health + 20.0)


func flashlight_running(delta: float) -> bool:
	## Drains the battery; false once it is flat.
	battery = maxf(0.0, battery - 100.0 / BATTERY_SECONDS * delta)
	return battery > 0.0


func damage(amount: float) -> void:
	if amount <= 0.0 or passing_out:
		return
	health = maxf(0.0, health - amount)
	hurt = minf(1.0, hurt + amount / 25.0)


func to_save() -> Dictionary:
	return {"health": health, "hunger": hunger, "stamina": stamina, "thirst": thirst, "fatigue": fatigue, "battery": battery}


func from_save(data: Dictionary) -> void:
	health = clampf(float(data.get("health", 100.0)), 1.0, 100.0)
	hunger = clampf(float(data.get("hunger", 100.0)), 0.0, 100.0)
	stamina = clampf(float(data.get("stamina", 100.0)), 0.0, 100.0)
	thirst = clampf(float(data.get("thirst", 100.0)), 0.0, 100.0)
	fatigue = clampf(float(data.get("fatigue", 0.0)), 0.0, 100.0)
	battery = clampf(float(data.get("battery", 100.0)), 0.0, 100.0)


func _process(delta: float) -> void:
	if player == null:
		return
	layout()
	var hidden: bool = player.ending_locked
	panel.visible = not hidden
	if hidden or passing_out:
		vignette.visible = not hidden
		return
	hunger = maxf(0.0, hunger - 100.0 / HUNGER_SECONDS * delta)
	thirst = maxf(0.0, thirst - 100.0 / THIRST_SECONDS * delta)
	fatigue = minf(100.0, fatigue + 100.0 / AWAKE_SECONDS * delta)
	if hunger <= 0.0:
		damage(STARVING_DAMAGE * delta)
		hurt = minf(hurt, 0.3)
	if thirst <= 0.0:
		damage(THIRST_DAMAGE * delta)
		hurt = minf(hurt, 0.3)
	elif hunger > 60.0 and thirst > 40.0 and health < 100.0:
		health = minf(100.0, health + HEAL_RATE * delta)
	regen_wait = maxf(0.0, regen_wait - delta)
	if regen_wait <= 0.0:
		stamina = minf(100.0, stamina + STAMINA_REGEN * delta * (0.6 if hunger <= 0.0 else 1.0) * (0.5 if fatigue > 75.0 else 1.0))
	if exhausted and stamina >= RECOVER_AT:
		exhausted = false
	for stat in bars:
		var value: float = 100.0 - fatigue if stat == "rest" else get(stat)
		bars[stat][0].size.x = 130.0 * value / 100.0
		var low: bool = value < 20.0 or (stat == "stamina" and exhausted)
		bars[stat][1].modulate = Color(1, 0.55, 0.5) if low else Color.WHITE
	# The torch bar only shows while it matters.
	bars["battery"][0].get_parent().get_parent().visible = player.flashlight_on or battery < 25.0
	_tired_blink(delta)
	# After dark the edges close in, slowly breathing, like something is watching.
	var cycle := player.get_tree().current_scene.get_node_or_null("DayNightCycle") if player.get_tree().current_scene else null
	var daylight: float = cycle.daylight if cycle and "daylight" in cycle else 1.0
	hurt = maxf(0.0, hurt - delta * 0.6)
	var night := 1.0 - daylight
	vignette.visible = true
	vignette_material.set_shader_parameter("strength", night * 0.62 + (1.0 - health / 100.0) * 0.35 + hurt * 0.5 + maxf(0.0, fatigue - 70.0) / 30.0 * 0.4)
	vignette_material.set_shader_parameter("pulse", night)
	if health <= 0.0:
		_pass_out()


func _pass_out() -> void:
	passing_out = true
	var fade := create_tween()
	fade.tween_property(blackout, "color:a", 1.0, 1.4)
	fade.tween_callback(func() -> void:
		if is_instance_valid(player.active_vehicle):
			player._exit_vehicle()
		if player.held_object:
			player._drop_held_object()
		player.global_position = spawn_point
		player.velocity = Vector3.ZERO
		health = 45.0
		hunger = maxf(hunger, 35.0)
		stamina = 60.0
		exhausted = false)
	fade.tween_interval(1.2)
	fade.tween_property(blackout, "color:a", 0.0, 1.6)
	fade.tween_callback(func() -> void: passing_out = false)


func _tired_blink(delta: float) -> void:
	## Worn out: now and then your eyes close on their own. Fully exhausted, you
	## nod off for a second, even behind the wheel.
	if fatigue < 75.0 or passing_out:
		return
	blink_wait -= delta
	if blink_wait > 0.0:
		return
	var asleep := fatigue >= 99.0
	blink_wait = randf_range(14.0, 26.0) if not asleep else randf_range(22.0, 34.0)
	var close := create_tween()
	close.tween_property(blackout, "color:a", 1.0, 0.18 if not asleep else 0.5)
	close.tween_interval(0.12 if not asleep else 1.1)
	close.tween_property(blackout, "color:a", 0.0, 0.25 if not asleep else 0.6)


func sleep_until_morning(where: String) -> void:
	## Fade out, skip the night when playing alone, wake up rested.
	passing_out = true
	var fade := create_tween()
	fade.tween_property(blackout, "color:a", 1.0, 1.3)
	fade.tween_callback(func() -> void:
		slept()
		var cycle := player.get_tree().current_scene.get_node_or_null("DayNightCycle")
		if cycle and not NetworkManager.is_online():
			var morning := 0.29
			# Slept through a night: it still counts for the story, unless the
			# road already counted the one you lay down in.
			var road := player.get_tree().current_scene.get_node_or_null("InfiniteRoad")
			var passes_night: bool = cycle.time_of_day > morning or cycle.time_of_day < 0.25
			var counted: bool = road != null and "was_night" in road and road.was_night
			if passes_night and not counted:
				var story: Dictionary = preload("res://scripts/road_end_house.gd").story
				story["nights"] = int(story.get("nights", 0)) + 1
			if road and "was_night" in road:
				road.was_night = false
			cycle.time_of_day = morning)
	fade.tween_interval(1.6)
	fade.tween_property(blackout, "color:a", 0.0, 1.5)
	fade.tween_callback(func() -> void:
		passing_out = false
		player._show_tip("You slept %s until morning" % where if not NetworkManager.is_online() else "You rested for a while"))
