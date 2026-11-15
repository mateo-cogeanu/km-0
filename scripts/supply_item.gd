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
	match kind:
		"water":
			var plastic := Shapes.material(Color(0.75, 0.85, 0.92, 0.35), 0.0, 0.08)
			plastic.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			Shapes.cylinder(self, "Bottle", Vector3(0, 0.1, 0), Vector3.UP, 0.034, 0.2, plastic, 14)
			Shapes.cylinder(self, "Shoulder", Vector3(0, 0.215, 0), Vector3.UP, 0.02, 0.03, plastic, 12)
			Shapes.cylinder(self, "Cap", Vector3(0, 0.237, 0), Vector3.UP, 0.014, 0.018, Shapes.material(Color("#2d5fa0")), 10)
			Shapes.cylinder(self, "Label", Vector3(0, 0.1, 0), Vector3.UP, 0.0345, 0.07, Shapes.material(Color("#d8e4ea")), 14)
			var water := Shapes.material(Color(0.45, 0.62, 0.78, 0.55), 0.0, 0.05)
			water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water_mesh = Shapes.cylinder(self, "Water", Vector3(0, 0.1, 0), Vector3.UP, 0.031, 0.19, water, 12)
			size = Vector3(0.07, 0.25, 0.07)
		"batteries":
			Shapes.box(self, "Card", Vector3(0.09, 0.12, 0.012), Vector3(0, 0.06, 0), Shapes.material(Color("#c43a2c")))
			for i in 4:
				Shapes.cylinder(self, "Cell", Vector3(-0.03 + i * 0.02, 0.06, 0.012), Vector3.UP, 0.007, 0.05, Shapes.material(Color("#2a2a2a"), 0.5, 0.4), 8)
			size = Vector3(0.09, 0.12, 0.03)
		"flare":
			Shapes.cylinder(self, "Tube", Vector3(0, 0.15, 0), Vector3.UP, 0.019, 0.3, Shapes.material(Color("#b0261c"), 0.0, 0.5), 12)
			Shapes.cylinder(self, "Cap", Vector3(0, 0.31, 0), Vector3.UP, 0.021, 0.03, Shapes.material(Color("#e8e2d0")), 12)
			Shapes.cylinder(self, "Band", Vector3(0, 0.2, 0), Vector3.UP, 0.0195, 0.04, Shapes.material(Color("#e8c848")), 12)
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
