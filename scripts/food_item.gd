extends RigidBody3D
## Something to eat, found lying around. Pick it up, put it away with Q, or eat
## it while holding it with R.

const Shapes := preload("res://scripts/prop_shapes.gd")

## name: [title, hunger restored, stamina restored, health restored]
const KINDS := {
	"beans": ["can of beans", 38.0, 0.0, 4.0],
	"soup": ["can of soup", 32.0, 10.0, 6.0],
	"chocolate": ["chocolate bar", 14.0, 35.0, 0.0],
	"crackers": ["box of crackers", 22.0, 0.0, 2.0],
	"apple": ["apple", 11.0, 8.0, 2.0],
	"jerky": ["bag of jerky", 26.0, 6.0, 3.0],
	"soda": ["can of soda", 6.0, 45.0, 0.0],
}

@export var kind := "beans"


func _ready() -> void:
	add_to_group("food")
	collision_layer = 16
	collision_mask = 17
	mass = 0.4
	contact_monitor = true
	max_contacts_reported = 4
	_build()


func title() -> String:
	return KINDS.get(kind, KINDS["beans"])[0]


func hunger_value() -> float:
	return KINDS.get(kind, KINDS["beans"])[1]


func stamina_value() -> float:
	return KINDS.get(kind, KINDS["beans"])[2]


func health_value() -> float:
	return KINDS.get(kind, KINDS["beans"])[3]


func _build() -> void:
	var size := Vector3(0.08, 0.11, 0.08)
	match kind:
		"beans", "soup", "soda":
			var tin := Shapes.material(Color("#9c9a94"), 0.75, 0.35)
			var label_color: Color = {"beans": Color("#a8492f"), "soup": Color("#c9a63d"), "soda": Color("#2f6a9c")}[kind]
			var height := 0.12 if kind == "soda" else 0.11
			var radius := 0.033 if kind == "soda" else 0.042
			Shapes.cylinder(self, "Tin", Vector3(0, height * 0.5, 0), Vector3.UP, radius, height, tin, 14)
			Shapes.cylinder(self, "Label", Vector3(0, height * 0.5, 0), Vector3.UP, radius + 0.002, height * 0.62, Shapes.material(label_color), 14)
			size = Vector3(radius * 2.0, height, radius * 2.0)
		"chocolate":
			Shapes.box(self, "Wrapper", Vector3(0.16, 0.018, 0.06), Vector3(0, 0.009, 0), Shapes.material(Color("#5a2a1e")))
			Shapes.box(self, "Band", Vector3(0.06, 0.02, 0.062), Vector3(0, 0.009, 0), Shapes.material(Color("#c8b27a")))
			size = Vector3(0.16, 0.02, 0.06)
		"crackers":
			Shapes.box(self, "Box", Vector3(0.15, 0.2, 0.05), Vector3(0, 0.1, 0), Shapes.material(Color("#c98a2e")))
			Shapes.box(self, "Front", Vector3(0.11, 0.08, 0.052), Vector3(0, 0.12, 0), Shapes.material(Color("#e8dcc0")))
			size = Vector3(0.15, 0.2, 0.05)
		"apple":
			Shapes.cylinder(self, "Apple", Vector3(0, 0.04, 0), Vector3.UP, 0.04, 0.075, Shapes.material(Color("#8e2a22"), 0.0, 0.45), 10)
			Shapes.cylinder(self, "Stem", Vector3(0, 0.085, 0), Vector3.UP, 0.004, 0.02, Shapes.material(Color("#4a3a22")), 5)
			size = Vector3(0.08, 0.08, 0.08)
		"jerky":
			Shapes.box(self, "Bag", Vector3(0.12, 0.17, 0.03), Vector3(0, 0.085, 0), Shapes.material(Color("#3b4a35"), 0.2, 0.5))
			Shapes.box(self, "Window", Vector3(0.07, 0.07, 0.032), Vector3(0, 0.08, 0), Shapes.material(Color("#6b3a22")))
			size = Vector3(0.12, 0.17, 0.03)
	var hitbox := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	hitbox.shape = shape
	hitbox.position.y = size.y * 0.5
	add_child(hitbox)
