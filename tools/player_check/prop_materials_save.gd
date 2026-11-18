extends SceneTree
## Writes the prop materials (scripts/prop_materials.gd) to assets/desert/props/materials/.
## Run: Godot --headless --script res://tools/player_check/prop_materials_save.gd

func _init() -> void:
	preload("res://scripts/prop_materials.gd").save_all()
	print("prop materials saved")
	quit()
