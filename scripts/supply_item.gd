extends RigidBody3D
## Small supplies found on the road: a water bottle (drink it: R), flashlight
## batteries (R to load them) and a road flare.

const Shapes := preload("res://scripts/prop_shapes.gd")

@export_enum("water", "batteries", "flare") var kind := "water"
## For water: how much is left, 0 to 1. Each drink takes a third.
@export var amount := 1.0

var water_mesh: MeshInstance3D


func _ready() -> void:
	add_to_group({"water": "water", "batteries": "battery_pack", "flare": "flare"}[kind])
	collision_layer = 16
	collision_mask = 17
	mass = 0.5
	contact_monitor = true
	max_contacts_reported = 4
	var size := Vector3(0.07, 0.24, 0.07)
	var model := (load("res://assets/desert/props/supply_%s.glb" % kind) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	match kind:
		"water":
			# The water inside, drawn here so it can go down as you drink.
			var water := Shapes.material(Color(0.45, 0.62, 0.78, 0.55), 0.0, 0.05)
			water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water_mesh = Shapes.cylinder(self, "Water", Vector3(0, 0.1, 0), Vector3.UP, 0.031, 0.19, water, 12)
			size = Vector3(0.07, 0.25, 0.07)
		"batteries":
			size = Vector3(0.09, 0.12, 0.03)
		"flare":
			size = Vector3(0.042, 0.33, 0.042)
	var hitbox := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	hitbox.shape = shape
	hitbox.position.y = size.y * 0.5
	add_child(hitbox)
	set_amount(amount)


func title() -> String:
	match kind:
		"water":
			return "water bottle" if amount > 0.05 else "empty bottle"
		"batteries":
			return "flashlight batteries"
		_:
			return "road flare"


func set_amount(value: float) -> void:
	amount = clampf(value, 0.0, 1.0)
	if water_mesh:
		water_mesh.visible = amount > 0.02
		water_mesh.scale.y = maxf(amount, 0.02)
		water_mesh.position.y = 0.005 + 0.095 * maxf(amount, 0.02)
