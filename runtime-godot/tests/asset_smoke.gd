extends SceneTree

func _init() -> void:
	var names := [
		"gt_car",
		"tree_lush",
		"grandstand",
		"paddock_tent",
		"light_mast",
		"service_van",
		"tire_stack",
		"track_cone"
	]
	var instances: Array[Node3D] = []

	for asset_name in names:
		var instance := AssetLibrary3D.instantiate_asset(asset_name)
		assert(instance != null, "Missing asset: " + asset_name)
		instances.append(instance)

	var car := AssetLibrary3D.instantiate_asset("gt_car")
	assert(car != null)
	var wheels := AssetLibrary3D.car_wheels(car)
	assert(wheels.size() == 4, "Expected 4 named wheel pivots, got %d" % wheels.size())
	var material_names: Array[String] = []
	_collect_material_names(car, material_names)
	assert(material_names.any(func(value: String) -> bool: return value.begins_with("BodyPaint")), "BodyPaint material missing")
	assert(material_names.any(func(value: String) -> bool: return value.begins_with("Accent")), "Accent material missing")

	car.free()
	for instance in instances:
		instance.free()

	print("HGE_GLTF_ASSET_SMOKE_OK assets=", names.size(), " wheels=", wheels.size())
	quit(0)

func _collect_material_names(node: Node, output: Array[String]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var material := mesh_instance.mesh.surface_get_material(surface_index)
				if material and not output.has(material.resource_name):
					output.append(material.resource_name)

	for child in node.get_children():
		_collect_material_names(child, output)
