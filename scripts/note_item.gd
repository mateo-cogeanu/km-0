extends Node3D
## A note, notebook, postcard, photo or sheet you can read with E. Its text
## lives in story_notes.gd under note_id.

const Shapes := preload("res://scripts/prop_shapes.gd")
const Notes := preload("res://scripts/story_notes.gd")

@export var note_id := "len_shift"


func _ready() -> void:
	var entry: Dictionary = Notes.NOTES.get(note_id, {})
	var style: String = entry.get("style", "paper")
	var size := Vector3(0.21, 0.004, 0.28)
	match style:
		"notebook":
			Shapes.box(self, "Cover", Vector3(0.15, 0.022, 0.21), Vector3(0, 0.011, 0), Shapes.material(Color("#3d4a3a")))
			Shapes.box(self, "Pages", Vector3(0.14, 0.018, 0.2), Vector3(0.004, 0.012, 0), Shapes.material(Color("#d8cfb5")))
			Shapes.box(self, "Band", Vector3(0.152, 0.024, 0.012), Vector3(0, 0.012, 0.06), Shapes.material(Color("#1e1c1a")))
			size = Vector3(0.15, 0.024, 0.21)
		"postcard":
			Shapes.box(self, "Card", Vector3(0.15, 0.003, 0.1), Vector3(0, 0.0015, 0), Shapes.material(Color("#e2d6b8")))
			Shapes.box(self, "Picture", Vector3(0.07, 0.0035, 0.085), Vector3(-0.035, 0.0018, 0), Shapes.material(Color("#7d8f9a")))
			size = Vector3(0.15, 0.004, 0.1)
		"photo":
			Shapes.box(self, "Frame", Vector3(0.09, 0.003, 0.105), Vector3(0, 0.0015, 0), Shapes.material(Color("#e8e4d8")))
			Shapes.box(self, "Image", Vector3(0.076, 0.0035, 0.076), Vector3(0, 0.0018, -0.008), Shapes.material(Color("#2a2622")))
			size = Vector3(0.09, 0.004, 0.105)
		"sheet":
			Shapes.box(self, "Clipboard", Vector3(0.23, 0.01, 0.32), Vector3(0, 0.005, 0), Shapes.material(Color("#6a5236")))
			Shapes.box(self, "Sheet", Vector3(0.21, 0.003, 0.28), Vector3(0, 0.011, 0.01), Shapes.material(Color("#d9d2bd")))
			Shapes.box(self, "Clip", Vector3(0.08, 0.012, 0.03), Vector3(0, 0.014, -0.14), Shapes.material(Color("#8a8a86"), 0.6, 0.4))
			size = Vector3(0.23, 0.02, 0.32)
		_:
			var paper := Shapes.box(self, "Paper", Vector3(0.21, 0.003, 0.28), Vector3(0, 0.0015, 0), Shapes.material(Color("#d4cab0")))
			paper.rotation.y = 0.08
			for i in 6:
				Shapes.box(self, "Writing", Vector3(0.15 - (i % 3) * 0.02, 0.0034, 0.004), Vector3(-0.01, 0.0017, -0.09 + i * 0.03), Shapes.material(Color("#3a3530")))
	var target := Area3D.new()
	target.name = "ReadTarget"
	target.collision_layer = 8
	target.collision_mask = 0
	target.add_to_group("note")
	add_child(target)
	var hitbox := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size + Vector3(0.06, 0.06, 0.06)
	hitbox.shape = shape
	hitbox.position.y = size.y * 0.5
	target.add_child(hitbox)


func title() -> String:
	return Notes.NOTES.get(note_id, {}).get("title", "note")


func text() -> String:
	return Notes.NOTES.get(note_id, {}).get("text", "")


func mark_read() -> void:
	Notes.read[note_id] = true
