extends SceneTree
## Saves the bike engine's mesh (from assets/desert/props/bike_engine.glb) as a
## mesh file, because assets/vehicles/parts/bike_engine.tscn has to be a
## MeshInstance3D at its root (drivable_vehicle.gd and two_wheeler.gd use it so).

func _init() -> void:
	var scene: Node = load("res://assets/desert/props/bike_engine.glb").instantiate()
	var mesh := (scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	print("bike engine mesh saved: ", ResourceSaver.save(mesh, "res://assets/desert/props/bike_engine_mesh.res") == OK)
	scene.free()
	quit()
