class_name AssetLibrary3D
extends RefCounted

const ROOT := "res://assets/generated/"

static func path_for(name: String) -> String:
	return ROOT + name + ".glb"

static func instantiate_asset(name: String) -> Node3D:
	var path := path_for(name)
	if not ResourceLoader.exists(path):
		return null

	var resource := load(path)
	if resource is PackedScene:
		var instance := (resource as PackedScene).instantiate()
		if instance is Node3D:
			return instance as Node3D
	return null

static func find_node_recursive(root: Node, wanted_name: String) -> Node:
	if root.name == wanted_name:
		return root
	for child in root.get_children():
		var result := find_node_recursive(child, wanted_name)
		if result:
			return result
	return null

static func collect_nodes_prefix(root: Node, prefix: String, output: Array[Node3D]) -> void:
	if root is Node3D and String(root.name).begins_with(prefix):
		output.append(root as Node3D)
	for child in root.get_children():
		collect_nodes_prefix(child, prefix, output)

static func recolor_car(root: Node, body_color: Color, accent_color: Color) -> void:
	for child in root.get_children():
		recolor_car(child, body_color, accent_color)

	if not (root is MeshInstance3D):
		return

	var mesh_instance := root as MeshInstance3D
	if mesh_instance.mesh == null:
		return

	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var source := mesh_instance.mesh.surface_get_material(surface_index)
		if source == null:
			continue

		var material_name := source.resource_name
		var replacement := source.duplicate() as Material
		if replacement is StandardMaterial3D:
			var standard := replacement as StandardMaterial3D
			if material_name.begins_with("BodyPaint"):
				standard.albedo_color = body_color
				standard.metallic = 0.52
				standard.roughness = 0.16
				standard.clearcoat_enabled = true
				standard.clearcoat = 0.72
				standard.clearcoat_roughness = 0.12
			elif material_name.begins_with("BodyDark"):
				standard.albedo_color = body_color.darkened(0.25)
				standard.metallic = 0.42
				standard.roughness = 0.23
			elif material_name.begins_with("Accent"):
				standard.albedo_color = accent_color
		mesh_instance.set_surface_override_material(surface_index, replacement)

static func car_wheels(root: Node) -> Array[Node3D]:
	var wheels: Array[Node3D] = []
	for name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var node := find_node_recursive(root, name)
		if node is Node3D:
			wheels.append(node as Node3D)
	return wheels
