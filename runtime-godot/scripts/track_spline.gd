class_name TrackSpline
extends Node3D

@export var road_half_width: float = 7.2
@export var curb_width: float = 0.75
@export var runoff_width: float = 3.2
@export var pit_half_width: float = 3.0
@export var pit_offset: float = 11.5
@export var sample_count: int = 260
@export var terrain_blend_width: float = 8.0
@export var pro_centerline_clearance: float = 1.45
@export var editor_bounds: float = 360.0
@export var max_control_points: int = 96
@export var max_segment_length: float = 120.0
@export var auto_build_layout: String = "default"

var active_layout: String = "default"

var curve: Curve3D = Curve3D.new()
var path_node: Path3D

signal track_rebuilt

var control_points: Array[Vector3] = []
var bank_degrees: Array[float] = []
var _pit_centers: Array[Vector3] = []
var last_validation_errors: Array[String] = []

func _ready() -> void:
	if control_points.is_empty():
		reset_active_layout()

func reset_active_layout() -> void:
	if auto_build_layout == "red_blue_pro":
		build_red_blue_pro_circuit()
	else:
		build_default_circuit()

func build_default_circuit() -> void:
	active_layout = "default"
	road_half_width = 7.2
	curb_width = 0.75
	runoff_width = 3.2
	pit_half_width = 3.0
	pit_offset = 11.5
	sample_count = 260
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

func build_red_blue_pro_circuit() -> void:
	active_layout = "red_blue_pro"
	road_half_width = 5.5
	curb_width = 0.75
	runoff_width = 4.5
	pit_half_width = 3.0
	pit_offset = 12.0
	terrain_blend_width = 8.0
	sample_count = 1100
	editor_bounds = 360.0
	max_control_points = 96
	max_segment_length = 120.0

	var pro_points: Array[Vector3] = [
		Vector3(-245.602, 0.0, 25.929),
		Vector3(-234.433, 0.0, -17.662),
		Vector3(-222.797, 0.0, -61.130),
		Vector3(-212.319, 0.0, -104.870),
		Vector3(-178.903, 0.0, -128.499),
		Vector3(-157.293, 0.0, -94.941),
		Vector3(-139.766, 0.0, -56.588),
		Vector3(-111.000, 0.0, -75.000),
		Vector3(-143.357, 0.0, -122.985),
		Vector3(-181.252, 0.0, -146.441),
		Vector3(-220.225, 0.0, -128.179),
		Vector3(-252.917, 0.0, -97.278),
		Vector3(-276.159, 0.0, -59.046),
		Vector3(-288.858, 0.0, -15.980),
		Vector3(-294.845, 0.0, 28.578),
		Vector3(-296.359, 0.0, 73.538),
		Vector3(-296.271, 0.0, 118.537),
		Vector3(-294.830, 0.0, 163.508),
		Vector3(-277.705, 0.0, 201.803),
		Vector3(-233.340, 0.0, 206.659),
		Vector3(-188.741, 0.0, 203.103),
		Vector3(-148.112, 0.0, 184.148),
		Vector3(-112.385, 0.0, 156.857),
		Vector3(-79.919, 0.0, 125.716),
		Vector3(-48.474, 0.0, 93.528),
		Vector3(-18.303, 0.0, 60.159),
		Vector3(-7.119, 0.0, 17.615),
		Vector3(-0.116, 0.0, -26.382),
		Vector3(29.194, 0.0, -60.170),
		Vector3(69.183, 0.0, -64.571),
		Vector3(70.412, 0.0, -23.844),
		Vector3(53.231, 0.0, 17.737),
		Vector3(70.183, 0.0, 53.680),
		Vector3(113.985, 0.0, 48.008),
		Vector3(157.083, 0.0, 35.177),
		Vector3(200.669, 0.0, 24.016),
		Vector3(243.898, 0.0, 11.524),
		Vector3(287.133, 0.0, -0.726),
		Vector3(285.963, 0.0, -39.204),
		Vector3(260.313, 0.0, -76.160),
		Vector3(236.134, 0.0, -114.104),
		Vector3(210.473, 0.0, -151.062),
		Vector3(187.138, 0.0, -189.488),
		Vector3(147.812, 0.0, -206.168),
		Vector3(116.137, 0.0, -175.672),
		Vector3(82.563, 0.0, -145.929),
		Vector3(42.254, 0.0, -126.211),
		Vector3(-1.714, 0.0, -117.211),
		Vector3(-45.435, 0.0, -110.367),
		Vector3(-52.745, 0.0, -69.018),
		Vector3(-39.414, 0.0, -26.039),
		Vector3(-27.279, 0.0, 17.266),
		Vector3(-39.636, 0.0, 57.355),
		Vector3(-82.345, 0.0, 58.217),
		Vector3(-105.943, 0.0, 20.463),
		Vector3(-147.576, 0.0, 9.896),
		Vector3(-180.454, 0.0, 38.216),
		Vector3(-195.996, 0.0, 80.423),
		Vector3(-214.498, 0.0, 121.440),
		Vector3(-229.582, 0.0, 163.818),
		Vector3(-263.419, 0.0, 186.896),
		Vector3(-277.448, 0.0, 150.924),
		Vector3(-266.574, 0.0, 107.266),
		Vector3(-255.050, 0.0, 63.768)
	]
	var pro_banks: Array[float] = [
		0.009, 0.018, -0.033, 1.139, 1.977, 0.167, -1.946, -1.187,
		-1.111, -1.613, -0.525, -0.438, -0.434, -0.259, -0.163, -0.059,
		-0.054, -0.606, -1.617, -0.319, -0.605, -0.351, -0.192, -0.053,
		-0.077, -0.804, -0.141, 0.953, 1.335, 1.972, 0.618, -1.236,
		-1.798, -0.279, 0.059, -0.050, -0.028, -1.601, -0.830, 0.058,
		-0.064, 0.092, -1.048, -1.807, 0.073, 0.449, 0.421, 0.071,
		-1.780, -0.769, 0.044, 0.928, 1.947, 1.624, -1.263, -1.587,
		-0.851, 0.103, -0.124, 0.996, 1.980, 0.883, 0.030, -0.022
	]

	control_points.clear()
	bank_degrees.clear()
	for i in range(pro_points.size()):
		var p := pro_points[i]
		var elevation := TerrainBuilder3D.height_at(p.x, p.z) + pro_centerline_clearance
		control_points.append(Vector3(p.x, elevation, p.z))
		bank_degrees.append(pro_banks[i])

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
	_build_grass_shoulder_mesh()
	_build_pit_lane()
	_build_guardrails()
	_build_start_line()
	track_rebuilt.emit()

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
		"layout": active_layout,
		"point_count": control_points.size(),
		"length": snappedf(get_length(), 0.1),
		"road_width": road_half_width * 2.0,
		"runoff_width": runoff_width,
		"pit_offset": pit_offset,
		"points": points
	}

func set_control_point(index: int, x: float, z: float, bank: float) -> bool:
	if index < 0 or index >= control_points.size():
		last_validation_errors = ["invalid_index"]
		return false

	x = clampf(x, -editor_bounds, editor_bounds)
	z = clampf(z, -editor_bounds, editor_bounds)
	var candidate: Array[Vector3] = []
	for point in control_points:
		candidate.append(point)
	var clearance := pro_centerline_clearance if active_layout == "red_blue_pro" else 0.16
	candidate[index] = Vector3(x, TerrainBuilder3D.height_at(x, z) + clearance, z)

	var errors := _validate_candidate(candidate)
	if not errors.is_empty():
		last_validation_errors = errors
		return false

	control_points = candidate
	bank_degrees[index] = clampf(bank, -16.0, 16.0)
	last_validation_errors.clear()
	rebuild()
	return true

func set_bank(index: int, bank: float) -> bool:
	if index < 0 or index >= bank_degrees.size():
		last_validation_errors = ["invalid_index"]
		return false
	bank_degrees[index] = clampf(bank, -16.0, 16.0)
	last_validation_errors.clear()
	rebuild()
	return true

func replace_control_points(points: Array) -> bool:
	if points.size() < 6 or points.size() > max_control_points:
		last_validation_errors = ["point_count_must_be_6_to_%d" % max_control_points]
		return false

	var new_points: Array[Vector3] = []
	var new_banks: Array[float] = []

	for entry in points:
		if typeof(entry) != TYPE_DICTIONARY:
			last_validation_errors = ["point_payload_must_be_dictionary"]
			return false
		var x := clampf(float(entry.get("x", 0.0)), -editor_bounds, editor_bounds)
		var z := clampf(float(entry.get("z", 0.0)), -editor_bounds, editor_bounds)
		var bank := clampf(float(entry.get("bank", 0.0)), -16.0, 16.0)
		var clearance := pro_centerline_clearance if active_layout == "red_blue_pro" else 0.16
		new_points.append(Vector3(x, TerrainBuilder3D.height_at(x, z) + clearance, z))
		new_banks.append(bank)

	var errors := _validate_candidate(new_points)
	if not errors.is_empty():
		last_validation_errors = errors
		return false

	control_points = new_points
	bank_degrees = new_banks
	last_validation_errors.clear()
	rebuild()
	return true

func track_analysis() -> Dictionary:
	var count := control_points.size()
	if count < 3:
		return {"valid": false, "errors": ["not_enough_points"]}

	var min_segment := INF
	var max_segment := 0.0
	var total_segment := 0.0
	var max_bank := 0.0
	var sharp_turns := 0
	var hairpins := 0
	var elevation_gain := 0.0
	var elevation_loss := 0.0
	var min_elevation := INF
	var max_elevation := -INF
	var self_intersections := 0
	var longest_straight := 0.0
	var current_straight := 0.0

	for i in range(count):
		var current := control_points[i]
		var next := control_points[(i + 1) % count]
		var previous := control_points[(i - 1 + count) % count]
		var segment := current.distance_to(next)
		min_segment = minf(min_segment, segment)
		max_segment = maxf(max_segment, segment)
		total_segment += segment
		min_elevation = minf(min_elevation, current.y)
		max_elevation = maxf(max_elevation, current.y)

		var elevation_delta := next.y - current.y
		if elevation_delta > 0.0:
			elevation_gain += elevation_delta
		else:
			elevation_loss += absf(elevation_delta)

		var in_vector := Vector2(previous.x - current.x, previous.z - current.z).normalized()
		var out_vector := Vector2(next.x - current.x, next.z - current.z).normalized()
		var angle := rad_to_deg(acos(clampf(in_vector.dot(out_vector), -1.0, 1.0)))
		var deflection := 180.0 - angle
		if deflection > 55.0:
			sharp_turns += 1
		if deflection > 105.0:
			hairpins += 1

		if deflection < 14.0:
			current_straight += segment
			longest_straight = maxf(longest_straight, current_straight)
		else:
			current_straight = segment

		if i < bank_degrees.size():
			max_bank = maxf(max_bank, absf(bank_degrees[i]))

	for i in range(count):
		var a1 := Vector2(control_points[i].x, control_points[i].z)
		var a2 := Vector2(control_points[(i + 1) % count].x, control_points[(i + 1) % count].z)
		for j in range(i + 1, count):
			if j == i or j == (i + 1) % count or (j + 1) % count == i:
				continue
			if i == 0 and j == count - 1:
				continue
			var b1 := Vector2(control_points[j].x, control_points[j].z)
			var b2 := Vector2(control_points[(j + 1) % count].x, control_points[(j + 1) % count].z)
			if _segments_intersect(a1, a2, b1, b2):
				self_intersections += 1

	var area := absf(_polygon_area(control_points))
	var errors := _validate_candidate(control_points)
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"point_count": count,
		"curve_length": snappedf(get_length(), 0.1),
		"control_polygon_length": snappedf(total_segment, 0.1),
		"min_segment": snappedf(min_segment, 0.1),
		"max_segment": snappedf(max_segment, 0.1),
		"area": snappedf(area, 0.1),
		"sharp_turns": sharp_turns,
		"hairpins": hairpins,
		"longest_straight_estimate": snappedf(longest_straight, 0.1),
		"elevation_gain": snappedf(elevation_gain, 0.1),
		"elevation_loss": snappedf(elevation_loss, 0.1),
		"elevation_range": snappedf(max_elevation - min_elevation, 0.1),
		"max_bank": snappedf(max_bank, 0.1),
		"self_intersections": self_intersections
	}

func _validate_candidate(points: Array[Vector3]) -> Array[String]:
	var errors: Array[String] = []
	var count := points.size()
	if count < 6 or count > max_control_points:
		errors.append("point_count_must_be_6_to_%d" % max_control_points)
		return errors

	for i in range(count):
		var segment := points[i].distance_to(points[(i + 1) % count])
		if segment < 8.0:
			errors.append("segment_too_short_%d" % i)
		if segment > max_segment_length:
			errors.append("segment_too_long_%d" % i)

	if absf(_polygon_area(points)) < 700.0:
		errors.append("track_area_too_small")

	for i in range(count):
		var a1 := Vector2(points[i].x, points[i].z)
		var a2 := Vector2(points[(i + 1) % count].x, points[(i + 1) % count].z)
		for j in range(i + 1, count):
			if j == i or j == (i + 1) % count or (j + 1) % count == i:
				continue
			if i == 0 and j == count - 1:
				continue
			var b1 := Vector2(points[j].x, points[j].z)
			var b2 := Vector2(points[(j + 1) % count].x, points[(j + 1) % count].z)
			if _segments_intersect(a1, a2, b1, b2):
				errors.append("self_intersection_%d_%d" % [i, j])

	return errors

func _polygon_area(points: Array[Vector3]) -> float:
	var area := 0.0
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += a.x * b.z - b.x * a.z
	return area * 0.5

func _segments_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var epsilon := 0.001
	var ab := b - a
	var cd := d - c
	var c1 := ab.cross(c - a)
	var c2 := ab.cross(d - a)
	var c3 := cd.cross(a - c)
	var c4 := cd.cross(b - c)
	return (
		((c1 > epsilon and c2 < -epsilon) or (c1 < -epsilon and c2 > epsilon))
		and
		((c3 > epsilon and c4 < -epsilon) or (c3 < -epsilon and c4 > epsilon))
	)

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

func _signed_curvature_at_distance(distance: float) -> float:
	var length := get_length()
	if length <= 0.0:
		return 0.0
	var window := 7.5
	var before := curve.sample_baked(fposmod(distance - window, length), true)
	var center := curve.sample_baked(fposmod(distance, length), true)
	var after := curve.sample_baked(fposmod(distance + window, length), true)
	var incoming := Vector2(center.x - before.x, center.z - before.z).normalized()
	var outgoing := Vector2(after.x - center.x, after.z - center.z).normalized()
	var angle := atan2(incoming.cross(outgoing), clampf(incoming.dot(outgoing), -1.0, 1.0))
	return angle / maxf(0.001, window * 2.0)

func _curve_strength_at_distance(distance: float) -> float:
	return smoothstep(0.0025, 0.0140, absf(_signed_curvature_at_distance(distance)))

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
	var line_surface := SurfaceTool.new()
	line_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
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

		var midpoint := (d0 + d1) * 0.5
		var curve_strength := _curve_strength_at_distance(midpoint)
		var curb_active := curve_strength > 0.18
		var stripe_index := int(floor(midpoint / 3.6))
		var curb_color := Color("#f3f1e9") if stripe_index % 2 == 0 else Color("#cf343b")
		if not curb_active:
			curb_color = Color("#454b4c")
		var outer_l0 := p0 - r0 * (road_half_width + curb_width)
		var outer_l1 := p1 - r1 * (road_half_width + curb_width)
		var outer_r0 := p0 + r0 * (road_half_width + curb_width)
		var outer_r1 := p1 + r1 * (road_half_width + curb_width)
		var lift := normal * (0.035 if curb_active else 0.008)
		_add_quad(curb_surface, outer_l0+lift, left0+lift, left1+lift, outer_l1+lift, curb_color, Vector2(0,v0),Vector2(1,v0),Vector2(1,v1),Vector2(0,v1),normal)
		_add_quad(curb_surface, right0+lift, outer_r0+lift, outer_r1+lift, right1+lift, curb_color, Vector2(0,v0),Vector2(1,v0),Vector2(1,v1),Vector2(0,v1),normal)

		# Crisp white edge lines make the racing surface readable at speed without
		# turning the circuit into a road with center markings.
		var line_width := 0.12
		var line_offset := road_half_width - 0.15
		var line_l_outer0 := p0 - r0 * (line_offset + line_width * 0.5)
		var line_l_inner0 := p0 - r0 * (line_offset - line_width * 0.5)
		var line_l_outer1 := p1 - r1 * (line_offset + line_width * 0.5)
		var line_l_inner1 := p1 - r1 * (line_offset - line_width * 0.5)
		var line_r_inner0 := p0 + r0 * (line_offset - line_width * 0.5)
		var line_r_outer0 := p0 + r0 * (line_offset + line_width * 0.5)
		var line_r_inner1 := p1 + r1 * (line_offset - line_width * 0.5)
		var line_r_outer1 := p1 + r1 * (line_offset + line_width * 0.5)
		var line_lift := normal * 0.018
		_add_quad(line_surface, line_l_outer0+line_lift, line_l_inner0+line_lift, line_l_inner1+line_lift, line_l_outer1+line_lift, Color.WHITE, Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN,normal)
		_add_quad(line_surface, line_r_inner0+line_lift, line_r_outer0+line_lift, line_r_outer1+line_lift, line_r_inner1+line_lift, Color.WHITE, Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN,normal)

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

	var edge_lines := MeshInstance3D.new()
	edge_lines.name = "EdgeLines"
	edge_lines.mesh = line_surface.commit()
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color("#f3f4ef")
	line_material.roughness = 0.72
	line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	edge_lines.material_override = line_material
	root.add_child(edge_lines)

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
		var midpoint := (d0 + d1) * 0.5
		var curve_strength := _curve_strength_at_distance(midpoint)
		var signed_curve := _signed_curvature_at_distance(midpoint)
		var outside_side := 1.0 if signed_curve >= 0.0 else -1.0

		var straight_shoulder := Color("#465449")
		var inside_asphalt := Color("#4c5352")
		var gravel := Color("#8b8068")
		var gravel_light := Color("#9b9075")
		var band := 0.5 + 0.5 * sin(midpoint * 0.10)
		var outside_color := gravel.lerp(gravel_light, band * 0.30)
		var inside_color := straight_shoulder.lerp(inside_asphalt, curve_strength * 0.72)
		var left_color := inside_color
		var right_color := inside_color

		if curve_strength > 0.22:
			if outside_side < 0.0:
				left_color = inside_color.lerp(outside_color, curve_strength)
			else:
				right_color = inside_color.lerp(outside_color, curve_strength)

		_add_quad(surface, p0-r0*outer, p0-r0*edge, p1-r1*edge, p1-r1*outer, left_color, Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN,normal)
		_add_quad(surface, p0+r0*edge, p0+r0*outer, p1+r1*outer, p1+r1*edge, right_color, Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN,normal)

	var mesh := MeshInstance3D.new()
	mesh.name = "Runoff"
	mesh.mesh = surface.commit()
	mesh.material_override = WorldMaterials3D.runoff_material()
	add_child(mesh)


func contains_surface_corridor(world_position: Vector3, extra_margin: float = 0.0) -> bool:
	if is_in_pit_zone(world_position):
		return true
	if get_length() <= 0.0:
		return false
	var local_position := to_local(world_position)
	var offset := curve.get_closest_offset(local_position)
	var frame := _sample_frame(offset)
	var lateral := absf((local_position - (frame.point as Vector3)).dot(frame.right as Vector3))
	var outer := road_half_width + curb_width + runoff_width + terrain_blend_width + extra_margin
	return lateral <= outer

func get_drivable_surface_height(world_position: Vector3) -> float:
	if is_in_pit_zone(world_position):
		return _closest_pit_point(world_position).y
	if get_length() <= 0.0:
		return TerrainBuilder3D.height_at(world_position.x, world_position.z)

	var local_position := to_local(world_position)
	var offset := curve.get_closest_offset(local_position)
	var frame := _sample_frame(offset)
	var lateral := (local_position - (frame.point as Vector3)).dot(frame.right as Vector3)
	var track_height := (frame.point as Vector3).y + (frame.right as Vector3).y * lateral
	var runoff_outer := road_half_width + curb_width + runoff_width
	var lateral_abs := absf(lateral)

	if lateral_abs <= runoff_outer:
		return track_height

	var terrain_height := TerrainBuilder3D.height_at(world_position.x, world_position.z)
	var blend := smoothstep(runoff_outer, runoff_outer + terrain_blend_width, lateral_abs)
	return lerpf(track_height, terrain_height, blend)

func _build_grass_shoulder_mesh() -> void:
	var old := get_node_or_null("GrassShoulders")
	if old:
		old.free()

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := get_length()
	var inner_offset := road_half_width + curb_width + runoff_width
	var outer_offset := inner_offset + terrain_blend_width

	for i in range(sample_count):
		var d0 := length * float(i) / float(sample_count)
		var d1 := length * float(i + 1) / float(sample_count)
		var f0 := _sample_frame(d0)
		var f1 := _sample_frame(d1)
		var p0: Vector3 = f0.point
		var p1: Vector3 = f1.point
		var r0: Vector3 = f0.right
		var r1: Vector3 = f1.right

		var left_inner0 := p0 - r0 * inner_offset
		var left_inner1 := p1 - r1 * inner_offset
		var left_outer0 := p0 - r0 * outer_offset
		var left_outer1 := p1 - r1 * outer_offset
		left_outer0.y = TerrainBuilder3D.height_at(left_outer0.x, left_outer0.z) + 0.01
		left_outer1.y = TerrainBuilder3D.height_at(left_outer1.x, left_outer1.z) + 0.01

		var right_inner0 := p0 + r0 * inner_offset
		var right_inner1 := p1 + r1 * inner_offset
		var right_outer0 := p0 + r0 * outer_offset
		var right_outer1 := p1 + r1 * outer_offset
		right_outer0.y = TerrainBuilder3D.height_at(right_outer0.x, right_outer0.z) + 0.01
		right_outer1.y = TerrainBuilder3D.height_at(right_outer1.x, right_outer1.z) + 0.01

		var left_normal := (left_inner1 - left_inner0).cross(left_outer0 - left_inner0).normalized()
		if left_normal.y < 0.0:
			left_normal = -left_normal
		var right_normal := (right_outer0 - right_inner0).cross(right_inner1 - right_inner0).normalized()
		if right_normal.y < 0.0:
			right_normal = -right_normal

		_add_quad(
			surface,
			left_outer0, left_inner0, left_inner1, left_outer1,
			Color.WHITE, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN, left_normal
		)
		_add_quad(
			surface,
			right_inner0, right_outer0, right_outer1, right_inner1,
			Color.WHITE, Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN, right_normal
		)

	var mesh := MeshInstance3D.new()
	mesh.name = "GrassShoulders"
	mesh.mesh = surface.commit()
	mesh.material_override = WorldMaterials3D.grass_material()
	add_child(mesh)

func _pit_merge_at_ratio(ratio: float) -> float:
	var wrapped := fposmod(ratio, 1.0)
	var t := 0.0
	if wrapped >= 0.90:
		t = (wrapped - 0.90) / 0.10
	elif wrapped <= 0.10:
		t = (wrapped + 0.10) / 0.20
	else:
		return 0.0
	return smoothstep(0.0, 0.22, t) * (1.0 - smoothstep(0.78, 1.0, t))

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
		var merge0 := _pit_merge_at_ratio(fposmod(ratio0, 1.0))
		var merge1 := _pit_merge_at_ratio(fposmod(ratio1, 1.0))
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

func _pit_active_ratio(ratio: float) -> bool:
	var wrapped := fposmod(ratio, 1.0)
	return wrapped >= 0.90 or wrapped <= 0.10

func _pit_gate_ratio(ratio: float) -> bool:
	var wrapped := fposmod(ratio, 1.0)
	return (wrapped >= 0.90 and wrapped <= 0.925) or (wrapped >= 0.075 and wrapped <= 0.10)

func _base_barrier_offset_at_ratio(ratio: float) -> float:
	var base_offset := road_half_width + curb_width + runoff_width + 0.85
	if active_layout != "red_blue_pro":
		return base_offset

	var distance := fposmod(ratio, 1.0) * get_length()
	var curve_strength := _curve_strength_at_distance(distance)
	# Give straights and flowing corners breathing room. The guardrail closes in
	# only where a compact safety envelope is useful in the technical sections.
	var safety_extra := lerpf(4.2, 1.35, curve_strength)
	return base_offset + safety_extra

func get_barrier_offset(side: float, ratio: float) -> float:
	var base_offset := _base_barrier_offset_at_ratio(ratio)
	if side <= 0.0:
		return base_offset
	if not _pit_active_ratio(ratio):
		return base_offset
	var pit_merge := _pit_merge_at_ratio(ratio)
	return base_offset + pit_merge * (pit_offset + pit_half_width)

func _main_barrier_offset() -> float:
	return _base_barrier_offset_at_ratio(0.0)

func _barrier_transform(frame: Dictionary, side: float, offset: float, height: float) -> Transform3D:
	var basis := Basis(frame.right, frame.normal, -frame.forward).orthonormalized()
	var origin: Vector3 = frame.point + frame.right * side * offset + frame.normal * height
	return Transform3D(basis, origin)

func trackside_offset_conflicts(ratio: float, side: float, offset: float) -> bool:
	var length := get_length()
	if length <= 0.0:
		return false
	var wrapped := fposmod(ratio, 1.0)
	var distance := wrapped * length
	return _barrier_conflicts_with_other_track(_sample_frame(distance), side, offset, distance)

func _barrier_conflicts_with_other_track(
	frame: Dictionary,
	side: float,
	offset: float,
	source_distance: float
) -> bool:
	if active_layout != "red_blue_pro":
		return false

	var length := get_length()
	if length <= 0.0:
		return false

	var candidate: Vector3 = frame.point + frame.right * side * offset
	var other_offset := curve.get_closest_offset(candidate)
	var source := fposmod(source_distance, length)
	var along_delta := absf(other_offset - source)
	along_delta = minf(along_delta, length - along_delta)

	# Nearby samples from the same bend are expected. Only treat it as a conflict
	# when the closest centerline belongs to a remote part of the lap.
	if along_delta < 42.0:
		return false

	var other_center := curve.sample_baked(other_offset, true)
	var flat_distance := Vector2(
		candidate.x - other_center.x,
		candidate.z - other_center.z
	).length()

	# Never let a guardrail from one section occupy another section's racing
	# surface or curb envelope. This matters where the PRO layout folds back
	# alongside itself near the late-lap hairpin.
	return flat_distance < road_half_width + curb_width + 1.25

func _build_guardrails() -> void:
	var old := get_node_or_null("Guardrails")
	if old:
		old.free()

	var root := Node3D.new()
	root.name = "Guardrails"
	add_child(root)

	var length := get_length()

	# Main circuit rails remain visible on both sides. The right side has only two
	# controlled openings where the pit lane physically joins/leaves the circuit.
	var visual_spacing := 4.0 if active_layout == "red_blue_pro" else 2.4
	var visual_segments := int(ceil(length / visual_spacing))
	var visual_transforms: Array[Transform3D] = []
	var panel_red_transforms: Array[Transform3D] = []
	var panel_white_transforms: Array[Transform3D] = []

	for i in range(visual_segments):
		var distance := minf((float(i) + 0.5) * visual_spacing, length - 0.01)
		var ratio := distance / maxf(length, 0.001)
		var frame := _sample_frame(distance)
		var base_offset := _base_barrier_offset_at_ratio(ratio)

		if not _barrier_conflicts_with_other_track(frame, -1.0, base_offset, distance):
			visual_transforms.append(_barrier_transform(frame, -1.0, base_offset, 0.42))

		if not _pit_gate_ratio(ratio) and not _barrier_conflicts_with_other_track(frame, 1.0, base_offset, distance):
			visual_transforms.append(_barrier_transform(frame, 1.0, base_offset, 0.42))

		if _pit_active_ratio(ratio):
			var outer_offset := get_barrier_offset(1.0, ratio)
			if outer_offset > base_offset + 0.6 and not _barrier_conflicts_with_other_track(frame, 1.0, outer_offset, distance):
				visual_transforms.append(_barrier_transform(frame, 1.0, outer_offset, 0.42))

		# High-load corner exteriors get red/white impact panels in front of the
		# metallic rail. This breaks the visual repetition and makes braking zones
		# readable from the chase camera without changing collision geometry.
		var curve_strength := _curve_strength_at_distance(distance)
		if curve_strength > 0.62:
			var signed_curve := _signed_curvature_at_distance(distance)
			var outside_side := 1.0 if signed_curve >= 0.0 else -1.0
			if not _barrier_conflicts_with_other_track(frame, outside_side, base_offset - 0.16, distance):
				var panel_transform := _barrier_transform(frame, outside_side, base_offset - 0.16, 0.50)
				if int(floor(distance / 4.0)) % 2 == 0:
					panel_red_transforms.append(panel_transform)
				else:
					panel_white_transforms.append(panel_transform)

	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.20, 0.86, visual_spacing + 0.45)
	var rail_material := StandardMaterial3D.new()
	rail_material.albedo_color = Color("#69757c")
	rail_material.metallic = 0.52
	rail_material.roughness = 0.36
	rail_mesh.material = rail_material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = rail_mesh
	multimesh.instance_count = visual_transforms.size()
	for i in range(visual_transforms.size()):
		multimesh.set_instance_transform(i, visual_transforms[i])

	var visual_instance := MultiMeshInstance3D.new()
	visual_instance.name = "GuardrailVisual"
	visual_instance.multimesh = multimesh
	root.add_child(visual_instance)

	_add_corner_panel_multimesh(root, "CornerPanelsRed", panel_red_transforms, Color("#c9353f"), visual_spacing)
	_add_corner_panel_multimesh(root, "CornerPanelsWhite", panel_white_transforms, Color("#ece9df"), visual_spacing)

	# Physical enclosure uses overlapping short boxes. This prevents collision gaps
	# even through high-curvature sections and banking transitions.
	var body := StaticBody3D.new()
	body.name = "GuardrailCollision"
	root.add_child(body)

	var collision_spacing := 3.0 if active_layout == "red_blue_pro" else 1.65
	var collision_segments := int(ceil(length / collision_spacing))
	for i in range(collision_segments):
		var distance := minf((float(i) + 0.5) * collision_spacing, length - 0.01)
		var ratio := distance / maxf(length, 0.001)
		var frame := _sample_frame(distance)
		var base_offset := _base_barrier_offset_at_ratio(ratio)

		if not _barrier_conflicts_with_other_track(frame, -1.0, base_offset, distance):
			_add_barrier_collision(body, frame, -1.0, base_offset, collision_spacing, "L", i)

		if not _pit_gate_ratio(ratio) and not _barrier_conflicts_with_other_track(frame, 1.0, base_offset, distance):
			_add_barrier_collision(body, frame, 1.0, base_offset, collision_spacing, "R", i)

		if _pit_active_ratio(ratio):
			var outer_offset := get_barrier_offset(1.0, ratio)
			if outer_offset > base_offset + 0.6 and not _barrier_conflicts_with_other_track(frame, 1.0, outer_offset, distance):
				_add_barrier_collision(body, frame, 1.0, outer_offset, collision_spacing, "PIT_R", i)

func _add_corner_panel_multimesh(
	root: Node3D,
	name_value: String,
	transforms: Array[Transform3D],
	color: Color,
	spacing: float
) -> void:
	if transforms.is_empty():
		return
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(0.28, 1.02, spacing + 0.32)
	var panel_material := StandardMaterial3D.new()
	panel_material.albedo_color = color
	panel_material.roughness = 0.58
	panel_material.metallic = 0.06
	panel_mesh.material = panel_material

	var panel_multi := MultiMesh.new()
	panel_multi.transform_format = MultiMesh.TRANSFORM_3D
	panel_multi.mesh = panel_mesh
	panel_multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		panel_multi.set_instance_transform(i, transforms[i])

	var instance := MultiMeshInstance3D.new()
	instance.name = name_value
	instance.multimesh = panel_multi
	root.add_child(instance)

func _add_barrier_collision(
	body: StaticBody3D,
	frame: Dictionary,
	side: float,
	offset: float,
	spacing: float,
	label: String,
	index: int
) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "Barrier_%s_%04d" % [label, index]
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.48, 1.30, spacing + 0.72)
	shape_node.shape = shape
	shape_node.transform = _barrier_transform(frame, side, offset, 0.64)
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
