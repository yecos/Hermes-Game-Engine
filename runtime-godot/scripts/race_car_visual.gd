class_name RaceCarVisual3D
extends RefCounted

static func material(color: Color, roughness: float = 0.3, metallic: float = 0.15, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	if emission != Color.BLACK:
		result.emission_enabled = true
		result.emission = emission
		result.emission_energy_multiplier = 1.6
	return result

static func box(size: Vector3, position: Vector3, mat: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	node.rotation = rotation
	node.material_override = mat
	return node

static func cylinder(radius: float, height: float, position: Vector3, mat: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	node.mesh = mesh
	node.position = position
	node.rotation = rotation
	node.material_override = mat
	return node

static func build(parent: Node3D, body_color: Color, accent_color: Color = Color("#f6f4ed")) -> Dictionary:
	var imported := AssetLibrary3D.instantiate_asset("gt_car")
	if imported:
		imported.name = "RaceCarVisual"
		imported.rotation.y = PI
		parent.add_child(imported)
		AssetLibrary3D.recolor_car(imported, body_color, accent_color)
		var imported_wheels := AssetLibrary3D.car_wheels(imported)
		if imported_wheels.size() == 4:
			return {
				"root": imported,
				"wheels": imported_wheels
			}
		imported.queue_free()

	var root := Node3D.new()
	root.name = "RaceCarVisual"
	parent.add_child(root)

	var paint := material(body_color, 0.2, 0.38)
	var paint_dark := material(body_color.darkened(0.22), 0.28, 0.28)
	var carbon := material(Color("#12161c"), 0.42, 0.18)
	var glass := material(Color("#203447"), 0.1, 0.48)
	var accent := material(accent_color, 0.28, 0.12)
	var tire := material(Color("#080a0d"), 0.86, 0.02)
	var rim := material(Color("#9aa3ad"), 0.22, 0.78)
	var headlight := material(Color("#fff4cf"), 0.12, 0.18, Color("#fff0b2"))
	var taillight := material(Color("#b71827"), 0.18, 0.12, Color("#ff2438"))

	# Main silhouette: wider GT stance with layered bodywork.
	root.add_child(box(Vector3(1.56, 0.34, 2.72), Vector3(0.0, 0.42, 0.04), paint))
	root.add_child(box(Vector3(1.42, 0.18, 0.78), Vector3(0.0, 0.55, -1.03), paint_dark, Vector3(deg_to_rad(-5.0), 0.0, 0.0)))
	root.add_child(box(Vector3(1.48, 0.16, 0.64), Vector3(0.0, 0.54, 1.02), paint_dark))
	root.add_child(box(Vector3(1.18, 0.40, 1.06), Vector3(0.0, 0.80, -0.13), glass))
	root.add_child(box(Vector3(1.05, 0.08, 0.78), Vector3(0.0, 1.03, -0.08), paint_dark))
	root.add_child(box(Vector3(0.24, 0.045, 2.44), Vector3(0.0, 0.70, -0.08), accent))

	# Front splitter and rear diffuser.
	root.add_child(box(Vector3(1.62, 0.08, 0.28), Vector3(0.0, 0.24, -1.44), carbon))
	root.add_child(box(Vector3(1.55, 0.08, 0.25), Vector3(0.0, 0.24, 1.42), carbon))
	root.add_child(box(Vector3(1.66, 0.09, 0.12), Vector3(0.0, 0.18, -1.52), carbon))

	# Side skirts and fender shoulders.
	root.add_child(box(Vector3(0.12, 0.17, 2.15), Vector3(-0.79, 0.29, 0.08), carbon))
	root.add_child(box(Vector3(0.12, 0.17, 2.15), Vector3(0.79, 0.29, 0.08), carbon))
	for side in [-1.0, 1.0]:
		root.add_child(box(Vector3(0.18, 0.25, 0.66), Vector3(0.75 * side, 0.48, -0.86), paint_dark))
		root.add_child(box(Vector3(0.18, 0.25, 0.66), Vector3(0.75 * side, 0.48, 0.86), paint_dark))

	# Aero wing with uprights.
	root.add_child(box(Vector3(1.62, 0.08, 0.28), Vector3(0.0, 1.02, 1.28), carbon))
	root.add_child(box(Vector3(0.08, 0.43, 0.08), Vector3(-0.55, 0.79, 1.22), carbon))
	root.add_child(box(Vector3(0.08, 0.43, 0.08), Vector3(0.55, 0.79, 1.22), carbon))

	# Lights.
	root.add_child(box(Vector3(0.46, 0.10, 0.06), Vector3(-0.43, 0.53, -1.43), headlight))
	root.add_child(box(Vector3(0.46, 0.10, 0.06), Vector3(0.43, 0.53, -1.43), headlight))
	root.add_child(box(Vector3(0.42, 0.09, 0.06), Vector3(-0.45, 0.52, 1.40), taillight))
	root.add_child(box(Vector3(0.42, 0.09, 0.06), Vector3(0.45, 0.52, 1.40), taillight))

	# Mirrors and exhaust.
	for side in [-1.0, 1.0]:
		root.add_child(box(Vector3(0.22, 0.12, 0.25), Vector3(0.79 * side, 0.74, -0.42), paint_dark))
	root.add_child(cylinder(0.085, 0.26, Vector3(-0.32, 0.31, 1.49), carbon, Vector3(deg_to_rad(90.0), 0.0, 0.0)))
	root.add_child(cylinder(0.085, 0.26, Vector3(0.32, 0.31, 1.49), carbon, Vector3(deg_to_rad(90.0), 0.0, 0.0)))

	var wheel_pivots: Array[Node3D] = []
	var wheel_positions := [
		Vector3(-0.84, 0.28, -0.90),
		Vector3(0.84, 0.28, -0.90),
		Vector3(-0.84, 0.28, 0.91),
		Vector3(0.84, 0.28, 0.91)
	]

	for wheel_position in wheel_positions:
		var pivot := Node3D.new()
		pivot.position = wheel_position
		root.add_child(pivot)
		wheel_pivots.append(pivot)

		var tire_mesh := cylinder(0.31, 0.25, Vector3.ZERO, tire, Vector3(0.0, 0.0, deg_to_rad(90.0)))
		pivot.add_child(tire_mesh)
		var rim_mesh := cylinder(0.18, 0.27, Vector3.ZERO, rim, Vector3(0.0, 0.0, deg_to_rad(90.0)))
		pivot.add_child(rim_mesh)
		var hub := cylinder(0.07, 0.29, Vector3.ZERO, carbon, Vector3(0.0, 0.0, deg_to_rad(90.0)))
		pivot.add_child(hub)

	return {
		"root": root,
		"wheels": wheel_pivots
	}
