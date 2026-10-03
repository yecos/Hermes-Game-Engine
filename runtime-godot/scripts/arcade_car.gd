class_name ArcadeCarController3D
extends CharacterBody3D

@export var input_enabled: bool = true
@export var body_color: Color = Color("#ef3f51")
@export var top_speed: float = 34.0
@export var reverse_speed: float = 10.0
@export var acceleration: float = 25.0
@export var brake_force: float = 38.0
@export var rolling_drag: float = 8.0
@export var lateral_grip: float = 14.0
@export var steering_rate: float = 2.35
@export var offroad_drag: float = 18.0
@export var turbo_force: float = 16.0
@export var ride_height: float = 0.48

@export var fuel_capacity_liters: float = 42.0
@export var fuel_burn_per_second: float = 0.035
@export var tire_wear_rate: float = 0.00032
@export var pit_service_rate: float = 0.55

var track: TrackSpline
var speed_kmh: float = 0.0
var is_offroad: bool = false
var slip_amount: float = 0.0

var fuel_liters: float = 42.0
var tire_health: float = 1.0
var damage: float = 0.0
var in_pit_lane: bool = false
var pit_servicing: bool = false

var _visual: Node3D
var _wheel_nodes: Array[Node3D] = []
var _rear_wheel_local_positions: Array[Vector3] = [
	Vector3(-0.82, 0.28, 0.88),
	Vector3(0.82, 0.28, 0.88)
]
var _skid_root: Node3D
var _skid_marks: Array[Node3D] = []
var _skid_timer: float = 0.0
var _smoke_timer: float = 0.0
var _engine_audio: EngineAudio3D
var _last_steer_input: float = 0.0
var _base_forward_speed: float = 0.0

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	fuel_liters = fuel_capacity_liters
	_build_collision()
	_build_visual()
	_build_effects()
	_build_audio()

func _physics_process(delta: float) -> void:
	if not input_enabled:
		return

	var throttle := Input.get_action_strength("accelerate")
	var reverse_input := Input.get_action_strength("brake_reverse")
	var steer_input := Input.get_axis("steer_left", "steer_right")
	var boost := Input.is_action_pressed("boost")
	var pit_requested := Input.is_action_pressed("pit_service")
	_last_steer_input = steer_input

	var forward := -global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()
	var forward_speed := velocity.dot(forward)
	var lateral_speed := velocity.dot(right)
	_base_forward_speed = forward_speed

	in_pit_lane = track != null and track.is_in_pit_zone(global_position)

	var fuel_factor := 1.0 if fuel_liters > 0.01 else 0.0
	var damage_factor := lerpf(1.0, 0.72, clampf(damage, 0.0, 1.0))
	var tire_grip_factor := lerpf(0.62, 1.0, clampf(tire_health, 0.0, 1.0))

	if throttle > 0.01 and fuel_factor > 0.0:
		var target_speed := top_speed * damage_factor * (1.14 if boost else 1.0)
		forward_speed = move_toward(forward_speed, target_speed, acceleration * throttle * damage_factor * delta)
	elif reverse_input > 0.01:
		if forward_speed > 1.0:
			forward_speed = move_toward(forward_speed, 0.0, brake_force * reverse_input * delta)
		else:
			forward_speed = move_toward(forward_speed, -reverse_speed, acceleration * 0.55 * reverse_input * delta)
	else:
		forward_speed = move_toward(forward_speed, 0.0, rolling_drag * delta)

	var steer_factor: float = clampf(absf(forward_speed) / maxf(1.0, top_speed), 0.12, 1.0)
	if absf(forward_speed) > 0.4 and absf(steer_input) > 0.01:
		rotate_y(-steer_input * steering_rate * tire_grip_factor * steer_factor * signf(forward_speed) * delta)

	forward = -global_transform.basis.z.normalized()
	right = global_transform.basis.x.normalized()
	lateral_speed = velocity.dot(right)

	slip_amount = clampf(absf(lateral_speed) / maxf(2.0, absf(forward_speed)), 0.0, 1.0)

	lateral_speed = move_toward(
		lateral_speed,
		0.0,
		lateral_grip * tire_grip_factor * delta * maxf(1.0, absf(forward_speed) * 0.35)
	)

	if boost and forward_speed > 2.0 and fuel_factor > 0.0:
		forward_speed += turbo_force * delta

	is_offroad = track != null and not track.is_on_track(global_position, -0.25)
	if is_offroad:
		forward_speed = move_toward(forward_speed, 0.0, offroad_drag * delta)
		forward_speed = clampf(forward_speed, -reverse_speed * 0.55, top_speed * 0.58)

	velocity = forward * forward_speed + right * lateral_speed
	velocity.y = 0.0

	move_and_slide()
	_apply_collision_damage()

	global_position.y = ride_height
	rotation.x = 0.0
	rotation.z = 0.0
	speed_kmh = absf(forward_speed) * 3.6

	_update_resources(delta, throttle, boost)
	_update_pit_service(delta, pit_requested)
	_update_visuals(delta, steer_input, forward_speed)
	_update_effects(delta, forward_speed)

func telemetry() -> Dictionary:
	return {
		"speed_kmh": snappedf(speed_kmh, 0.1),
		"slip": snappedf(slip_amount, 0.001),
		"fuel_liters": snappedf(fuel_liters, 0.01),
		"fuel_percent": snappedf((fuel_liters / maxf(0.001, fuel_capacity_liters)) * 100.0, 0.1),
		"tire_health": snappedf(tire_health, 0.001),
		"tire_percent": snappedf(tire_health * 100.0, 0.1),
		"damage": snappedf(damage, 0.001),
		"damage_percent": snappedf(damage * 100.0, 0.1),
		"offroad": is_offroad,
		"in_pit_lane": in_pit_lane,
		"pit_servicing": pit_servicing,
		"position": {
			"x": snappedf(global_position.x, 0.01),
			"y": snappedf(global_position.y, 0.01),
			"z": snappedf(global_position.z, 0.01)
		},
		"tuning": {
			"top_speed": top_speed,
			"acceleration": acceleration,
			"brake_force": brake_force,
			"lateral_grip": lateral_grip,
			"steering_rate": steering_rate,
			"turbo_force": turbo_force
		}
	}

func _update_resources(delta: float, throttle: float, boost: bool) -> void:
	if fuel_liters > 0.0 and throttle > 0.01:
		var burn := fuel_burn_per_second * throttle * (1.65 if boost else 1.0)
		fuel_liters = maxf(0.0, fuel_liters - burn * delta)

	if speed_kmh > 8.0:
		var wear_load := 0.12 + slip_amount * 3.5 + (1.5 if is_offroad else 0.0)
		tire_health = maxf(0.0, tire_health - tire_wear_rate * wear_load * delta * maxf(0.35, speed_kmh / 65.0))

func _update_pit_service(delta: float, pit_requested: bool) -> void:
	pit_servicing = in_pit_lane and pit_requested and speed_kmh < 12.0
	if not pit_servicing:
		return

	fuel_liters = minf(fuel_capacity_liters, fuel_liters + fuel_capacity_liters * pit_service_rate * delta)
	tire_health = minf(1.0, tire_health + pit_service_rate * delta)
	damage = maxf(0.0, damage - pit_service_rate * 0.45 * delta)

func _apply_collision_damage() -> void:
	var count := get_slide_collision_count()
	if count <= 0:
		return

	var impact_speed := absf(_base_forward_speed)
	if impact_speed < 4.0:
		return

	damage = clampf(damage + minf(0.08, impact_speed * 0.0018), 0.0, 1.0)
	velocity *= 0.72

func _update_visuals(delta: float, steer_input: float, forward_speed: float) -> void:
	if _visual == null:
		return

	var speed_ratio := clampf(absf(forward_speed) / maxf(1.0, top_speed), 0.0, 1.0)
	var target_roll := -steer_input * speed_ratio * 0.075
	var target_pitch := clampf((_base_forward_speed - forward_speed) * 0.01, -0.035, 0.035)

	_visual.rotation.z = lerpf(_visual.rotation.z, target_roll, 1.0 - exp(-8.0 * delta))
	_visual.rotation.x = lerpf(_visual.rotation.x, target_pitch, 1.0 - exp(-8.0 * delta))

	for i in range(_wheel_nodes.size()):
		var wheel := _wheel_nodes[i]
		var is_front := i < 2
		var steer_angle := -steer_input * 0.42 if is_front else 0.0
		wheel.rotation.y = lerpf(wheel.rotation.y, steer_angle, 1.0 - exp(-12.0 * delta))
		wheel.rotation.x += forward_speed * delta * 1.7

		var suspension := sin(Time.get_ticks_msec() * 0.013 + float(i)) * 0.018 * speed_ratio
		wheel.position.y = 0.28 + suspension

func _update_effects(delta: float, forward_speed: float) -> void:
	_skid_timer = maxf(0.0, _skid_timer - delta)
	_smoke_timer = maxf(0.0, _smoke_timer - delta)

	var should_skid := speed_kmh > 38.0 and (slip_amount > 0.16 or (Input.is_action_pressed("brake_reverse") and forward_speed > 6.0))
	if should_skid and _skid_timer <= 0.0:
		_spawn_skid_marks()
		_skid_timer = 0.065

	if should_skid and slip_amount > 0.22 and _smoke_timer <= 0.0:
		_spawn_smoke_puff()
		_smoke_timer = 0.085

func _spawn_skid_marks() -> void:
	if _skid_root == null:
		return

	for local_position in _rear_wheel_local_positions:
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.17, 0.018, 0.68)
		marker.mesh = mesh

		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.04, 0.04, 0.045, 0.54)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 1.0
		marker.material_override = material

		var world_position := to_global(local_position)
		marker.global_position = Vector3(world_position.x, 0.035, world_position.z)
		marker.global_rotation = Vector3(0.0, global_rotation.y, 0.0)
		_skid_root.add_child(marker)
		_skid_marks.append(marker)

	while _skid_marks.size() > 180:
		var oldest: Node3D = _skid_marks.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

func _spawn_smoke_puff() -> void:
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.23
	sphere.height = 0.46
	puff.mesh = sphere

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.82, 0.85, 0.86, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material_override = material

	var rear := to_global(Vector3(0.0, 0.25, 1.35))
	puff.global_position = rear
	get_tree().current_scene.add_child(puff)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "scale", Vector3.ONE * 2.8, 0.65)
	tween.tween_property(puff, "global_position:y", rear.y + 0.8, 0.65)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.65)
	tween.chain().tween_callback(puff.queue_free)

func _build_effects() -> void:
	_skid_root = Node3D.new()
	_skid_root.name = "SkidMarks"
	get_tree().current_scene.add_child.call_deferred(_skid_root)

func _build_audio() -> void:
	_engine_audio = EngineAudio3D.new()
	_engine_audio.name = "EngineAudio"
	_engine_audio.car = self
	add_child(_engine_audio)

func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.55, 0.7, 3.0)
	collision.shape = shape
	collision.position.y = 0.35
	add_child(collision)

func _make_material(color: Color, roughness: float = 0.35, metallic: float = 0.08) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _mesh_box(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	node.material_override = material
	return node

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "CarVisual"
	add_child(_visual)

	var paint := _make_material(body_color, 0.22, 0.34)
	var paint_dark := _make_material(body_color.darkened(0.18), 0.28, 0.28)
	var dark := _make_material(Color("#10141a"), 0.5, 0.05)
	var glass := _make_material(Color("#203345"), 0.12, 0.38)
	var white := _make_material(Color("#f6f4ed"), 0.3, 0.1)
	var light := _make_material(Color("#ffe8b8"), 0.16, 0.22)

	_visual.add_child(_mesh_box(Vector3(1.48, 0.40, 2.82), Vector3(0, 0.42, 0.02), paint))
	_visual.add_child(_mesh_box(Vector3(1.30, 0.18, 0.72), Vector3(0, 0.57, -1.00), paint_dark))
	_visual.add_child(_mesh_box(Vector3(1.16, 0.42, 1.08), Vector3(0, 0.78, -0.16), glass))
	_visual.add_child(_mesh_box(Vector3(0.28, 0.055, 2.42), Vector3(0, 0.69, -0.07), white))
	_visual.add_child(_mesh_box(Vector3(1.52, 0.11, 0.18), Vector3(0, 0.67, 1.27), dark))
	_visual.add_child(_mesh_box(Vector3(0.42, 0.09, 0.08), Vector3(-0.42, 0.51, -1.42), light))
	_visual.add_child(_mesh_box(Vector3(0.42, 0.09, 0.08), Vector3(0.42, 0.51, -1.42), light))

	var wheel_positions := [
		Vector3(-0.82, 0.28, -0.88),
		Vector3(0.82, 0.28, -0.88),
		Vector3(-0.82, 0.28, 0.88),
		Vector3(0.82, 0.28, 0.88)
	]

	for wheel_position in wheel_positions:
		var pivot := Node3D.new()
		pivot.position = wheel_position
		_visual.add_child(pivot)
		_wheel_nodes.append(pivot)

		var wheel := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.29
		cylinder.bottom_radius = 0.29
		cylinder.height = 0.24
		wheel.mesh = cylinder
		wheel.rotation_degrees.z = 90.0
		wheel.material_override = dark
		pivot.add_child(wheel)
