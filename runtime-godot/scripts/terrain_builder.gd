class_name TerrainBuilder3D
extends Node3D

@export var world_size: float = 150.0
@export var resolution: int = 72

static func height_at(x: float, z: float) -> float:
	var rolling := sin(x * 0.048) * 0.72 + cos(z * 0.052) * 0.52
	var crossing := sin((x + z) * 0.027) * 0.46
	var hill_a := exp(-((x - 30.0) * (x - 30.0) + (z + 22.0) * (z + 22.0)) / 1050.0) * 1.8
	var hill_b := exp(-((x + 35.0) * (x + 35.0) + (z - 27.0) * (z - 27.0)) / 860.0) * 1.35
	return rolling + crossing + hill_a + hill_b - 0.45

func _ready() -> void:
	build()

func build() -> void:
	var existing := get_node_or_null("TerrainMesh")
	if existing:
		existing.queue_free()

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half := world_size * 0.5
	var step := world_size / float(resolution)

	for z_index in range(resolution):
		for x_index in range(resolution):
			var x0 := -half + float(x_index) * step
			var x1 := x0 + step
			var z0 := -half + float(z_index) * step
			var z1 := z0 + step

			var a := Vector3(x0, height_at(x0, z0), z0)
			var b := Vector3(x1, height_at(x1, z0), z0)
			var c := Vector3(x1, height_at(x1, z1), z1)
			var d := Vector3(x0, height_at(x0, z1), z1)

			var uv_a := Vector2(float(x_index) / resolution, float(z_index) / resolution)
			var uv_b := Vector2(float(x_index + 1) / resolution, float(z_index) / resolution)
			var uv_c := Vector2(float(x_index + 1) / resolution, float(z_index + 1) / resolution)
			var uv_d := Vector2(float(x_index) / resolution, float(z_index + 1) / resolution)

			_add_triangle(surface, a, b, c, uv_a, uv_b, uv_c)
			_add_triangle(surface, a, c, d, uv_a, uv_c, uv_d)

	surface.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = surface.commit()
	mesh_instance.material_override = WorldMaterials3D.grass_material()
	add_child(mesh_instance)

func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2) -> void:
	surface.set_uv(uv_a)
	surface.add_vertex(a)
	surface.set_uv(uv_b)
	surface.add_vertex(b)
	surface.set_uv(uv_c)
	surface.add_vertex(c)
