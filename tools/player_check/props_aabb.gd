extends SceneTree
## Prints the visual bounds of each prop scene and part model (in its own space).

func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var xf := Transform3D()
		var n: Node = mesh
		while n != root and n != null:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b := xf * mesh.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _init() -> void:
	for path in ["res://scenes/fuel_canister.tscn", "res://scenes/spray_can.tscn", "res://assets/vehicles/parts/stockengine.glb",
			"res://assets/vehicles/parts/v8engine.glb", "res://assets/vehicles/parts/electricmotor.glb", "res://assets/vehicles/parts/radiatorassembly.glb",
			"res://assets/vehicles/parts/batterypack.glb", "res://assets/vehicles/parts/airfilter.glb", "res://assets/vehicles/parts/coolantreservoir.glb",
			"res://assets/vehicles/parts/bike_engine.tscn"]:
		var node: Node3D = load(path).instantiate()
		var b := _bounds(node)
		var surfaces := 0
		var tris := 0
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh:
				for s in mesh.mesh.get_surface_count():
					surfaces += 1
					var arr := mesh.mesh.surface_get_arrays(s)
					var idx = arr[Mesh.ARRAY_INDEX]
					tris += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
		print(path.get_file(), " pos ", b.position, " size ", b.size, " surfaces ", surfaces, " tris ", tris, " children ", node.get_children().map(func(c: Node) -> String: return c.name))
		node.free()
	quit()
