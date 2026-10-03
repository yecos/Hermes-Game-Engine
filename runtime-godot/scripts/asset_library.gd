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
				standard.metallic = 0.60
				standard.roughness = 0.125
				standard.clearcoat_enabled = true
				standard.clearcoat = 0.88
				standard.clearcoat_roughness = 0.075
			elif material_name.begins_with("BodyDark"):
				standard.albedo_color = body_color.darkened(0.31)
				standard.metallic = 0.48
				standard.roughness = 0.18
				standard.clearcoat_enabled = true
				standard.clearcoat = 0.52
				standard.clearcoat_roughness = 0.12
			elif material_name.begins_with("Accent"):
				standard.albedo_color = accent_color
				standard.metallic = 0.34
				standard.roughness = 0.20
				standard.clearcoat_enabled = true
				standard.clearcoat = 0.55
				standard.clearcoat_roughness = 0.11
			elif material_name.begins_with("Carbon"):
				standard.albedo_color = Color("#0a0d11")
				standard.metallic = 0.20
				standard.roughness = 0.34
			elif material_name.begins_with("Glass"):
				standard.albedo_color = Color(0.055, 0.105, 0.145, 0.74)
				standard.metallic = 0.08
				standard.roughness = 0.07
				standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			elif material_name.begins_with("Rim"):
				standard.albedo_color = Color("#8e959d")
				standard.metallic = 0.88
				standard.roughness = 0.16
			elif material_name.begins_with("Tire"):
				standard.albedo_color = Color("#07090b")
				standard.metallic = 0.0
				standard.roughness = 0.96
			elif material_name.begins_with("Headlight"):
				standard.albedo_color = Color("#fff3d3")
				standard.roughness = 0.10
				standard.emission_enabled = true
				standard.emission = Color("#ffe6a9")
				standard.emission_energy_multiplier = 2.2
			elif material_name.begins_with("Taillight"):
				standard.albedo_color = Color("#9b1420")
				standard.roughness = 0.15
				standard.emission_enabled = true
				standard.emission = Color("#ff233b")
				standard.emission_energy_multiplier = 1.45
		mesh_instance.set_surface_override_material(surface_index, replacement)

static func style_tree(root: Node, variant: int = 0) -> void:
	var palettes := [
		[Color("#295f32"), Color("#3b7a3a"), Color("#5b3b24")],
		[Color("#1f5230"), Color("#337044"), Color("#503521")],
		[Color("#486b2d"), Color("#627f35"), Color("#654627")],
		[Color("#2d6738"), Color("#4a8648"), Color("#59402a")]
	]
	var palette: Array = palettes[posmod(variant, palettes.size())]

	for child in root.get_children():
		style_tree(child, variant)

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
			if material_name.begins_with("LeavesA"):
				standard.albedo_color = palette[0]
				standard.roughness = 0.92
			elif material_name.begins_with("LeavesB"):
				standard.albedo_color = palette[1]
				standard.roughness = 0.94
			elif material_name.begins_with("Bark"):
				standard.albedo_color = palette[2]
				standard.roughness = 0.98
			mesh_instance.set_surface_override_material(surface_index, replacement)

static func car_wheels(root: Node) -> Array[Node3D]:
	var wheels: Array[Node3D] = []
	for name in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var node := find_node_recursive(root, name)
		if node is Node3D:
			wheels.append(node as Node3D)
	return wheels

static func apply_lod(root: Node, end_distance: float = 90.0, margin: float = 12.0) -> void:
	if root is GeometryInstance3D:
		var geometry := root as GeometryInstance3D
		geometry.visibility_range_end = maxf(10.0, end_distance)
		geometry.visibility_range_end_margin = maxf(1.0, margin)
	for child in root.get_children():
		apply_lod(child, end_distance, margin)
