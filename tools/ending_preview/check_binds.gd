extends SceneTree

func _init() -> void:
	var model: Node = load("res://assets/characters/road_creature.glb").instantiate()
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var skin_mesh := model.find_child("Continuous skin", true, false) as MeshInstance3D
	var skin := skin_mesh.skin
	for i in skin.get_bind_count():
		var bone := rig.find_bone(skin.get_bind_name(i)) if skin.get_bind_name(i) != "" else skin.get_bind_bone(i)
		var bind := skin.get_bind_pose(i).affine_inverse()
		var rest := rig.get_bone_global_rest(bone)
		var diff := bind.origin.distance_to(rest.origin) + (bind.basis.x - rest.basis.x).length() + (bind.basis.y - rest.basis.y).length()
		print(rig.get_bone_name(bone), " diff=", snappedf(diff, 0.0001), " bind=", bind.origin.snapped(Vector3.ONE * 0.001), " rest=", rest.origin.snapped(Vector3.ONE * 0.001))
	quit()
