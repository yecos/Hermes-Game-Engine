class_name TrackSpline
extends Node3D

@export var road_half_width: float = 7.2
@export var curb_width: float = 0.75
@export var sample_count: int = 240

var curve: Curve3D = Curve3D.new()
var path_node: Path3D

func _ready() -> void:
	if curve.point_count == 0:
		build_default_circuit()

func build_default_circuit() -> void:
	curve = Curve3D.new()
	curve.bake_interval = 0.5

	var points: Array[Vector3] = [
		Vector3(-42.0, 0.0, -8.0),
		Vector3(-35.0, 0.0, -28.0),
		Vector3(-18.0, 0.0, -37.0),
		Vector3(7.0, 0.0, -39.0),
		Vector3(30.0, 0.0, -32.0),
		Vector3(43.0, 0.0, -17.0),
		Vector3(47.0, 0.0, 4.0),
		Vector3(39.0, 0.0, 25.0),
		Vector3(21.0, 0.0, 36.0),
		Vector3(-3.0, 0.0, 39.0),
		Vector3(-27.0, 0.0, 33.0),
		Vector3(-43.0, 0.0, 17.0)
	]

	for i in range(points.size() + 1):
		var index := i % points.size()
		var previous := points[(index - 1 + points.size()) % points.size()]
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		var tangent := (next - previous) * 0.18
		curve.add_point(current, -tangent, tangent)

	if is_instance_valid(path_node):
		path_node.queue_free()

	path_node = Path3D.new()
	path_node.name = "RacingPath"
	path_node.curve = curve
	add_child(path_node)

	_build_road_mesh()
	_build_guardrails()
	_build_start_line()

func get_length() -> float:
	return curve.get_baked_length()

func get_progress_ratio(world_position: Vector3) -> float:
	var local_position := to_local(world_position)
	var offset := curve.get_closest_offset(local_position)
	return offset / max(0.001, get_length())

func get_closest_world_point(world_position: Vector3) -> Vector3:
	return to_global(curve.get_closest_point(to_local(world_position)))

func is_on_track(world_position: Vector3, extra_margin: float = 0.0) -> bool:
	var closest := get_closest_world_point(world_position)
	var flat_delta := Vector2(world_position.x - closest.x, world_position.z - closest.z)
	return flat_delta.length() <= road_half_width + extra_margin

func get_sector_index(world_position: Vector3) -> int:
	var ratio := get_progress_ratio(world_position)
	if ratio < 0.333333:
		return 1
	if ratio < 0.666666:
		return 2
	return 3

func is_in_pit_zone(world_position: Vector3) -> bool:
	var ratio := get_progress_ratio(world_position)
	var near_start := ratio < 0.07 or ratio > 0.93
	if not near_start:
		return false
	var closest := get_closest_world_point(world_position)
	var distance := Vector2(world_position.x - closest.x, world_position.z - closest.z).length()
	return distance <= road_half_width + 1.6

func get_world_transform_at_ratio(ratio: float) -> Transform3D:
	var length := get_length()
	var distance := fposmod(ratio, 1.0) * length
	var local_position := curve.sample_baked(distance, true)
	var next_distance := distance + 0.8
	var next_position: Vector3

	if next_distance >= length:
		next_position = curve.sample_baked(next_distance - length, true)
	else:
		next_position = curve.sample_baked(next_distance, true)

	var forward := (next_position - local_position).normalized()
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD

	var basis := Basis.looking_at(forward, Vector3.UP)
	return global_transform * Transform3D(basis, local_position)

func _sample_frame(distance: float) -> Dictionary:
	var length := get_length()
	var d: float = clampf(distance, 0.0, length)
	var p := curve.sample_baked(d, true)
	var before := curve.sample_baked(max(0.0, d - 0.45), true)
	var after := curve.sample_baked(min(length, d + 0.45), true)
	var forward := (after - before).normalized()

	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD

	var right := Vector3(-forward.z, 0.0, forward.x).normalized()
	return {"point": p, "forward": forward, "right": right}

func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color = Color.WHITE) -> void:
	surface.set_color(color)
	surface.set_normal(Vector3.UP)
	surface.add_vertex(a)
	surface.set_color(color)
	surface.set_normal(Vector3.UP)
	surface.add_vertex(b)
	surface.set_color(color)
	surface.set_normal(Vector3.UP)
	surface.add_vertex(c)

	surface.set_color(color)
	surface.set_normal(Vector3.UP)
	surface.add_vertex(a)
	surface.set_color(color)
	surface.set_normal(Vector3.UP)
	surface.add_vertex(c)
	surface.set_color(color)
	surface.set_normal(Vector3.UP)
	surface.add_vertex(d)

func _build_road_mesh() -> void:
	var old := get_node_or_null("RoadMesh")
	if old:
		old.queue_free()

	var road_surface := SurfaceTool.new()
	road_surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var curb_surface := SurfaceTool.new()
	curb_surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var length := get_length()

	for i in range(sample_count):
		var d0 := length * float(i) / float(sample_count)
		var d1 := length * float(i + 1) / float(sample_count)
		var f0 := _sample_frame(d0)
		var f1 := _sample_frame(d1)
		var p0: Vector3 = f0.point
		var p1: Vector3 = f1.point
		var r0: Vector3 = f0.right
		var r1: Vector3 = f1.right

		var left0 := p0 - r0 * road_half_width
		var right0 := p0 + r0 * road_half_width
		var left1 := p1 - r1 * road_half_width
		var right1 := p1 + r1 * road_half_width

		_add_quad(road_surface, left0, right0, right1, left1)

		var curb_color := Color("#f4f3ef") if (i / 4) % 2 == 0 else Color("#e34b4b")
		var y_offset := Vector3.UP * 0.035

		var outer_left0 := p0 - r0 * (road_half_width + curb_width)
		var outer_left1 := p1 - r1 * (road_half_width + curb_width)
		_add_quad(curb_surface, outer_left0 + y_offset, left0 + y_offset, left1 + y_offset, outer_left1 + y_offset, curb_color)

		var outer_right0 := p0 + r0 * (road_half_width + curb_width)
		var outer_right1 := p1 + r1 * (road_half_width + curb_width)
		_add_quad(curb_surface, right0 + y_offset, outer_right0 + y_offset, outer_right1 + y_offset, right1 + y_offset, curb_color)

	var road_material := StandardMaterial3D.new()
	road_material.albedo_color = Color("#444a50")
	road_material.roughness = 0.93
	road_material.metallic = 0.0
	road_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "Road"
	road_mesh.mesh = road_surface.commit()
	road_mesh.material_override = road_material

	var curb_material := StandardMaterial3D.new()
	curb_material.vertex_color_use_as_albedo = true
	curb_material.roughness = 0.82
	curb_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var curb_mesh := MeshInstance3D.new()
	curb_mesh.name = "Curbs"
	curb_mesh.mesh = curb_surface.commit()
	curb_mesh.material_override = curb_material

	var root := Node3D.new()
	root.name = "RoadMesh"
	root.add_child(road_mesh)
	root.add_child(curb_mesh)
	add_child(root)

func _build_guardrails() -> void:
	var old := get_node_or_null("Guardrails")
	if old:
		old.queue_free()

	var root := Node3D.new()
	root.name = "Guardrails"
	add_child(root)

	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(2.4, 0.8, 0.18)

	var rail_material := StandardMaterial3D.new()
	rail_material.albedo_color = Color("#2674c8")
	rail_material.metallic = 0.15
	rail_material.roughness = 0.5
	rail_mesh.material = rail_material

	var length := get_length()
	var spacing := 3.0
	var count := int(length / spacing) * 2

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = rail_mesh
	multimesh.instance_count = count

	var instance := 0
	for i in range(int(length / spacing)):
		var distance := float(i) * spacing
		var frame := _sample_frame(distance)
		var p: Vector3 = frame.point
		var right: Vector3 = frame.right
		var forward: Vector3 = frame.forward
		var yaw := atan2(forward.x, forward.z)

		for side in [-1.0, 1.0]:
			var origin: Vector3 = p + right * float(side) * (road_half_width + curb_width + 1.15) + Vector3.UP * 0.43
			var basis := Basis(Vector3.UP, yaw)
			multimesh.set_instance_transform(instance, Transform3D(basis, origin))
			instance += 1

	var mm_instance := MultiMeshInstance3D.new()
	mm_instance.multimesh = multimesh
	root.add_child(mm_instance)

	var barrier_body := StaticBody3D.new()
	barrier_body.name = "GuardrailCollision"
	root.add_child(barrier_body)

	var collision_spacing := 5.5
	var collision_count := int(length / collision_spacing)
	for i in range(collision_count):
		var distance := float(i) * collision_spacing
		var frame := _sample_frame(distance)
		var p: Vector3 = frame.point
		var right: Vector3 = frame.right
		var forward: Vector3 = frame.forward
		var yaw := atan2(forward.x, forward.z)

		for side in [-1.0, 1.0]:
			var shape_node := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(collision_spacing + 0.8, 1.0, 0.35)
			shape_node.shape = shape
			var origin: Vector3 = p + right * float(side) * (road_half_width + curb_width + 1.15) + Vector3.UP * 0.5
			shape_node.transform = Transform3D(Basis(Vector3.UP, yaw), origin)
			barrier_body.add_child(shape_node)

func _build_start_line() -> void:
	var old := get_node_or_null("StartLine")
	if old:
		old.queue_free()

	var transform := get_world_transform_at_ratio(0.0)
	var root := Node3D.new()
	root.name = "StartLine"
	root.global_transform = transform
	add_child(root)

	var cell_size := 0.75
	var columns := int((road_half_width * 2.0) / cell_size)

	for row in range(2):
		for column in range(columns):
			var tile := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(cell_size, 0.04, cell_size)
			tile.mesh = mesh

			var material := StandardMaterial3D.new()
			material.albedo_color = Color.WHITE if (row + column) % 2 == 0 else Color("#121212")
			material.roughness = 0.8
			tile.material_override = material
			tile.position = Vector3(
				-road_half_width + cell_size * 0.5 + float(column) * cell_size,
				0.08,
				(float(row) - 0.5) * cell_size
			)
			root.add_child(tile)
