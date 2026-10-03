extends SceneTree

func _init() -> void:
	var host := Node3D.new()
	var built := RaceCarVisual3D.build(host, Color("#ef4052"), Color("#f6f4ed"))
	var visual := built.root as Node3D
	var headlight := AssetLibrary3D.find_node_recursive(visual, "Headlight_L") as Node3D
	var taillight := AssetLibrary3D.find_node_recursive(visual, "Taillight_L") as Node3D
	assert(headlight != null and taillight != null)

	var head_transform := visual.transform * _relative_transform(headlight, visual)
	var tail_transform := visual.transform * _relative_transform(taillight, visual)
	assert(head_transform.origin.z < tail_transform.origin.z, "Car visual must face Godot forward (-Z)")

	print("HGE_CAR_ORIENTATION_OK headlight_z=", head_transform.origin.z, " taillight_z=", tail_transform.origin.z)
	host.free()
	quit(0)

func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result := node.transform
	var current := node.get_parent()
	while current != null and current != ancestor:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result
