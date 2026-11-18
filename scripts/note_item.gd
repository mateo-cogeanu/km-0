extends Node3D
## A note, notebook, postcard, photo or sheet you can read with E. Its text
## lives in story_notes.gd under note_id.

const Notes := preload("res://scripts/story_notes.gd")

@export var note_id := "len_shift"


func _ready() -> void:
	var entry: Dictionary = Notes.NOTES.get(note_id, {})
	var style: String = entry.get("style", "paper")
	var size := Vector3(0.21, 0.004, 0.28)
	size = {"notebook": Vector3(0.15, 0.024, 0.21), "postcard": Vector3(0.15, 0.004, 0.1), "photo": Vector3(0.09, 0.004, 0.105),
		"sheet": Vector3(0.23, 0.02, 0.32)}.get(style, size)
	var model := (load("res://assets/desert/props/note_%s.glb" % (style if style in ["notebook", "postcard", "photo", "sheet"] else "paper")) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	add_child(model)
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
