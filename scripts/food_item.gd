extends RigidBody3D
## Something to eat, found lying around. Pick it up, put it away with Q, or eat
## it while holding it with R.


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
	# The models (Sources/make_road_props.py) stand on the origin at these sizes.
	var size: Vector3 = {
		"beans": Vector3(0.084, 0.11, 0.084), "soup": Vector3(0.084, 0.11, 0.084), "soda": Vector3(0.066, 0.12, 0.066),
		"chocolate": Vector3(0.16, 0.02, 0.06), "crackers": Vector3(0.15, 0.2, 0.05), "apple": Vector3(0.08, 0.08, 0.08),
		"jerky": Vector3(0.12, 0.17, 0.03),
	}.get(kind, Vector3(0.08, 0.11, 0.08))
	var model := (load("res://assets/desert/props/food_%s.glb" % (kind if KINDS.has(kind) else "beans")) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	var hitbox := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	hitbox.shape = shape
	hitbox.position.y = size.y * 0.5
	add_child(hitbox)
