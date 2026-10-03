class_name TrackSpline
extends Node3D

@export var road_half_width: float = 7.2
@export var curb_width: float = 0.75
@export var runoff_width: float = 3.2
@export var pit_half_width: float = 3.0
@export var pit_offset: float = 11.5
@export var sample_count: int = 260

var curve: Curve3D = Curve3D.new()
var path_node: Path3D

var control_points: Array[Vector3] = []
var bank_degrees: Array[float] = []
var _pit_centers: Array[Vector3] = []

func _ready() -> void:
	if control_points.is_empty():
		build_default_circuit()

func build_default_circuit() -> void:
	var flat_points: Array[Vector2] = [
		Vector2(-42.0, -8.0),
		Vector2(-35.0, -28.0),
		Vector2(-18.0, -37.0),
		Vector2(7.0, -39.0),
		Vector2(30.0, -32.0),
		Vector2(43.0, -17.0),
		Vector2(47.0, 4.0),
		Vector2(39.0, 25.0),
		Vector2(21.0, 36.0),
		Vector2(-3.0, 39.0),
		Vector2(-27.0, 33.0),
		Vector2(-43.0, 17.0)
	]
	var default_banks: Array[float] = [0.0, 4.0, 7.0, 2.0, -5.0, -8.0, -4.0, 6.0, 8.0, 3.0, -5.0, -2.0]

	control_points.clear()
	bank_degrees.clear()
	for i in range(flat_points.size()):
		var p := flat_points[i]
		control_points.append(Vector3(p.x, TerrainBuilder3D.height_at(p.x, p.y) + 0.16, p.y))
		bank_degrees.append(default_banks[i])

	rebuild()

func rebuild() -> void:
	if control_points.size() < 6:
		return

	curve = Curve3D.new()
	curve.bake_interval = 0.45

	for i in range(control_points.size() + 1):
		var index := i % control_points.size()
		var previous := control_points[(index - 1 + control_points.size()) % control_points.size()]
		var current := control_points[index]
		var next := control_points[(index + 1) % control_points.size()]
		var tangent := (next - previous) * 0.18
		curve.add_point(current, -tangent, tangent)

	if is_instance_valid(path_node):
		path_node.queue_free()

	path_node = Path3D.new()
	path_node.name = "RacingPath"
	path_node.curve = curve
	add_child(path_node)

	_build_road_mesh()
	_build_runoff_mesh()
	_build_pit_lane()
	_build_guardrails()
	_build_start_line()

func track_snapshot() -> Dictionary:
	var points: Array[Dictionary] = []
	for i in range(control_points.size()):
		var p := control_points[i]
		points.append({
			"index": i,
			"x": snappedf(p.x, 0.01),
			"z": snappedf(p.z, 0.01),
			"y": snappedf(p.y, 0.01),
			"bank": snappedf(bank_degrees[i] if i < bank_degrees.size() else 0.0, 0.1)
		})
	return {
		"point_count": control_points.size(),
		"length": snappedf(get_length(), 0.1),
		"road_width": road_half_width * 2.0,
		"runoff_width": runoff_width,
		"pit_offset": pit_offset,
		"points": points
	}

func set_control_point(index: int, x: float, z: float, bank: float) -> bool:
	if index < 0 or index >= control_points.size():
		return false
	x = clampf(x, -65.0, 65.0)
	z = clampf(z, -65.0, 65.0)
	var y := TerrainBuilder3D.height_at(x, z) + 0.16
	control_points[index] = Vector3(x, y, z)
	bank_degrees[index] = clampf(bank, -16.0, 16.0)
	rebuild()
	return true

func set_bank(index: int, bank: float) -> bool:
	if index < 0 or index >= bank_degrees.size():
		return false
	bank_degrees[index] = clampf(bank, -16.0, 16.0)
	rebuild()
	return true

func replace_control_points(points: Array) -> bool:
	if points.size() < 6 or points.size() > 24:
		return false

	var new_points: Array[Vector3] = []
	var new_banks: Array[float] = []

	for entry in points:
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var x := clampf(float(entry.get("x", 0.0)), -65.0, 65.0)
		var z := clampf(float(entry.get("z", 0.0)), -65.0, 65.0)
		var bank := clampf(float(entry.get("bank", 0.0)), -16.0, 16.0)
		new_points.append(Vector3(x, TerrainBuilder3D.height_at(x, z) + 0.16, z))
		new_banks.append(bank)

	for i in range(new_points.size()):
		var next := new_points[(i + 1) % new_points.size()]
		if new_points[i].distance_to(next) < 7.0:
			return false

	control_points = new_points
	bank_degrees = new_banks
	rebuild()
	return true

func get_length() -> float:
	return curve.get_baked_length()

func get_progress_ratio(world_position: Vector3) -> float:
	var local_position := to_local(world_position)
	var offset := curve.get_closest_offset(local_position)
	return offset / maxf(0.001, get_length())

func get_closest_world_point(world_position: Vector3) -> Vector3:
	return to_global(curve.get_closest_point(to_local(world_position)))

func get_surface_height(world_position: Vector3) -> float:
	if is_in_pit_zone(world_position):
		var closest := _closest_pit_point(world_position)
		return closest.y
	var local_position := to_local(world_position)
	var offset := curve.get_closest_offset(local_position)
	var frame := _sample_frame(offset)
	var lateral := (local_position - (frame.point as Vector3)).dot(frame.right as Vector3)
	return (frame.point as Vector3).y + (frame.right as Vector3).y * lateral

func get_bank_degrees_at_world(world_position: Vector3) -> float:
	return _bank_at_ratio(get_progress_ratio(world_position))

func is_on_track(world_position: Vector3, extra_margin: float = 0.0) -> bool:
	if is_in_pit_zone(world_position):
		return true
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
	if _pit_centers.is_empty():
		return false
	var world_flat := Vector2(world_position.x, world_position.z)
	for point in _pit_centers:
		if world_flat.distance_to(Vector2(point.x, point.z)) <= pit_half_width + 0.8:
			return true
	return false

func get_world_transform_at_ratio(ratio: float) -> Transform3D:
	var frame := _sample_frame(fposmod(ratio, 1.0) * get_length())
	var basis := Basis(frame.right, frame.normal, -frame.forward).orthonormalized()
	return global_transform * Transform3D(basis, frame.point)

func _bank_at_ratio(ratio: float) -> float:
	if bank_degrees.is_empty():
		return 0.0
	var scaled := fposmod(ratio, 1.0) * float(bank_degrees.size())
	var index_a := int(floor(scaled)) % bank_degrees.size()
	var index_b := (index_a + 1) % bank_degrees.size()
	var t: float = scaled - floor(scaled)
	return lerpf(bank_degrees[index_a], bank_degrees[index_b], t)

func _sample_frame(distance: float) -> Dictionary:
	var length := get_length()
	var d := fposmod(distance, length)
	var p := curve.sample_baked(d, true)
	var before := curve.sample_baked(fposmod(d - 0.5, length), true)
	var after := curve.sample_baked(fposmod(d + 0.5, length), true)
	var forward := (after - before).normalized()
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD

	var right := Vector3(-forward.z, 0.0, forward.x).normalized()
	var normal := right.cross(forward).normalized()
	if normal.y < 0.0:
		normal = -normal

	var bank := deg_to_rad(_bank_at_ratio(d / length))
	var bank_basis := Basis(forward, bank)
	right = (bank_basis * right).normalized()
	normal = (bank_basis * normal).normalized()

	return {"point": p, "forward": forward, "right": right, "normal": normal}

func _add_quad(
	surface: SurfaceTool,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	color: Color = Color.WHITE,
	uv_a: Vector2 = Vector2.ZERO,
	uv_b: Vector2 = Vector2.RIGHT,
	uv_c: Vector2 = Vector2.ONE,
	uv_d: Vector2 = Vector2.DOWN,
	normal: Vector3 = Vector3.UP
) -> void:
	for item in [[a, uv_a], [b, uv_b], [c, uv_c], [a, uv_a], [c, uv_c], [d, uv_d]]:
		surface.set_color(color)
		surface.set_normal(normal)
		surface.set_uv(item[1])
		surface.add_vertex(item[0])

func _build_road_mesh() -> void:
	var old := get_node_or_null("RoadMesh")
	if old:
		old.free()

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
		var n0: Vector3 = f0.normal
		var n1: Vector3 = f1.normal
		var normal := (n0 + n1).normalized()

		var left0 := p0 - r0 * road_half_width
		var right0 := p0 + r0 * road_half_width
		var left1 := p1 - r1 * road_half_width
		var right1 := p1 + r1 * road_half_width
		var v0 := d0 / 5.0
		var v1 := d1 / 5.0
		_add_quad(road_surface, left0, right0, right1, left1, Color.WHITE, Vector2(0,v0), Vector2(1,v0), Vector2(1,v1), Vector2(0,v1), normal)

		var curb_color := Color("#f4f3ef") if (i / 4) % 2 == 0 else Color("#e34b4b")
		var outer_l0 := p0 - r0 * (road_half_width + curb_width)
		var outer_l1 := p1 - r1 * (road_half_width + curb_width)
		var outer_r0 := p0 + r0 * (road_half_width + curb_width)
		var outer_r1 := p1 + r1 * (road_half_width + curb_width)
		var lift := normal * 0.035
		_add_quad(curb_surface, outer_l0+lift, left0+lift, left1+lift, outer_l1+lift, curb_color, Vector2(0,v0),Vector2(1,v0),Vector2(1,v1),Vector2(0,v1),normal)
		_add_quad(curb_surface, right0+lift, outer_r0+lift, outer_r1+lift, right1+lift, curb_color, Vector2(0,v0),Vector2(1,v0),Vector2(1,v1),Vector2(0,v1),normal)

	var root := Node3D.new()
	root.name = "RoadMesh"
	add_child(root)

	var road := MeshInstance3D.new()
	road.name = "Road"
	road.mesh = road_surface.commit()
	road.material_override = WorldMaterials3D.road_material()
	root.add_child(road)

	var curbs := MeshInstance3D.new()
	curbs.name = "Curbs"
	curbs.mesh = curb_surface.commit()
	curbs.material_override = WorldMaterials3D.curb_material()
	root.add_child(curbs)

func _build_runoff_mesh() -> void:
	var old := get_node_or_null("Runoff")
	if old:
		old.free()

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
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
		var normal: Vector3 = (f0.normal + f1.normal).normalized()
		var edge := road_half_width + curb_width
		var outer := edge + runoff_width
		var color := Color("#c9a66b") if i % 7 < 5 else Color("#b99861")

		_add_quad(surface, p0-r0*outer, p0-r0*edge, p1-r1*edge, p1-r1*outer, color, Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN,normal)
		_add_quad(surface, p0+r0*edge, p0+r0*outer, p1+r1*outer, p1+r1*edge, color, Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN,normal)

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := MeshInstance3D.new()
	mesh.name = "Runoff"
	mesh.mesh = surface.commit()
	mesh.material_override = material
	add_child(mesh)

func _build_pit_lane() -> void:
	var old := get_node_or_null("PitLane")
	if old:
		old.free()
	_pit_centers.clear()

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 34

	for i in range(segments):
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var ratio0 := lerpf(0.90, 1.10, t0)
		var ratio1 := lerpf(0.90, 1.10, t1)
		var f0 := _sample_frame(fposmod(ratio0,1.0) * get_length())
		var f1 := _sample_frame(fposmod(ratio1,1.0) * get_length())
		var merge0 := smoothstep(0.0, 0.22, t0) * (1.0 - smoothstep(0.78, 1.0, t0))
		var merge1 := smoothstep(0.0, 0.22, t1) * (1.0 - smoothstep(0.78, 1.0, t1))
		var center0: Vector3 = f0.point + f0.right * (road_half_width + pit_offset * merge0)
		var center1: Vector3 = f1.point + f1.right * (road_half_width + pit_offset * merge1)
		_pit_centers.append(center0)

		var left0: Vector3 = center0 - (f0.right as Vector3) * pit_half_width
		var right0: Vector3 = center0 + (f0.right as Vector3) * pit_half_width
		var left1: Vector3 = center1 - (f1.right as Vector3) * pit_half_width
		var right1: Vector3 = center1 + (f1.right as Vector3) * pit_half_width
		var normal: Vector3 = (f0.normal + f1.normal).normalized()
		_add_quad(surface, left0, right0, right1, left1, Color.WHITE, Vector2(0,t0*8),Vector2(1,t0*8),Vector2(1,t1*8),Vector2(0,t1*8),normal)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#555b60")
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := MeshInstance3D.new()
	mesh.name = "PitLane"
	mesh.mesh = surface.commit()
	mesh.material_override = material
	add_child(mesh)

func _closest_pit_point(world_position: Vector3) -> Vector3:
	var closest := world_position
	var best := INF
	for p in _pit_centers:
		var distance := Vector2(world_position.x-p.x, world_position.z-p.z).length_squared()
		if distance < best:
			best = distance
			closest = p
	return closest

func _build_guardrails() -> void:
	var old := get_node_or_null("Guardrails")
	if old:
		old.free()

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
		var frame := _sample_frame(float(i) * spacing)
		for side in [-1.0, 1.0]:
			var offset := road_half_width + curb_width + runoff_width + 0.85
			var origin: Vector3 = frame.point + frame.right * float(side) * offset + frame.normal * 0.43
			var basis := Basis(frame.right, frame.normal, -frame.forward).orthonormalized()
			multimesh.set_instance_transform(instance, Transform3D(basis, origin))
			instance += 1

	var mm := MultiMeshInstance3D.new()
	mm.multimesh = multimesh
	root.add_child(mm)

	var body := StaticBody3D.new()
	body.name = "GuardrailCollision"
	root.add_child(body)
	var collision_spacing := 5.5
	for i in range(int(length / collision_spacing)):
		var frame := _sample_frame(float(i) * collision_spacing)
		for side in [-1.0, 1.0]:
			var shape_node := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(collision_spacing + 0.8, 1.0, 0.35)
			shape_node.shape = shape
			var offset := road_half_width + curb_width + runoff_width + 0.85
			var origin: Vector3 = frame.point + frame.right * float(side) * offset + frame.normal * 0.5
			shape_node.transform = Transform3D(Basis(frame.right, frame.normal, -frame.forward).orthonormalized(), origin)
			body.add_child(shape_node)

func _build_start_line() -> void:
	var old := get_node_or_null("StartLine")
	if old:
		old.free()

	var transform := get_world_transform_at_ratio(0.0)
	var root := Node3D.new()
	root.name = "StartLine"
	root.global_transform = transform
	add_child(root)

	var cell := 0.75
	var columns := int((road_half_width * 2.0) / cell)
	for row in range(2):
		for column in range(columns):
			var tile := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(cell, 0.04, cell)
			tile.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = Color.WHITE if (row + column) % 2 == 0 else Color("#121212")
			material.roughness = 0.8
			tile.material_override = material
			tile.position = Vector3(-road_half_width + cell*0.5 + float(column)*cell, 0.08, (float(row)-0.5)*cell)
			root.add_child(tile)
