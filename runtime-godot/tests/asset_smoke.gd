extends SceneTree

func _init() -> void:
	var names := [
		"gt_car",
		"gt_car_v2",
		"tree_lush",
		"tree_pine",
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

	var car := AssetLibrary3D.instantiate_asset("gt_car_v2")
	assert(car != null, "GT v2 asset missing")
	var wheels := AssetLibrary3D.car_wheels(car)
	assert(wheels.size() == 4, "Expected 4 named wheel pivots, got %d" % wheels.size())
	var material_names: Array[String] = []
	_collect_material_names(car, material_names)
	assert(material_names.any(func(value: String) -> bool: return value.begins_with("BodyPaint")), "BodyPaint material missing")
	assert(material_names.any(func(value: String) -> bool: return value.begins_with("Accent")), "Accent material missing")
	assert(AssetLibrary3D.find_node_recursive(car, "FrontGrille") != null, "GT v2 front grille missing")
	assert(AssetLibrary3D.find_node_recursive(car, "Wheel_FL_Spoke_0") != null, "GT v2 racing spokes missing")

	var road_material := WorldMaterials3D.road_material()
	assert(road_material.shader != null, "Road shader missing")
	assert(road_material.shader.code.contains("left_lane"), "Road racing-line layer missing")
	assert(road_material.shader.code.contains("repair"), "Road repair/seam layer missing")

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
