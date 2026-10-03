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

var track: TrackSpline
var speed_kmh: float = 0.0
var is_offroad: bool = false

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_build_collision()
	_build_visual()

func _physics_process(delta: float) -> void:
	if not input_enabled:
		return

	var throttle := Input.get_action_strength("accelerate")
	var reverse_input := Input.get_action_strength("brake_reverse")
	var steer_input := Input.get_axis("steer_left", "steer_right")
	var boost := Input.is_action_pressed("boost")

	var forward := -global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()
	var forward_speed := velocity.dot(forward)
	var lateral_speed := velocity.dot(right)

	if throttle > 0.01:
		var target_speed := top_speed * (1.14 if boost else 1.0)
		forward_speed = move_toward(forward_speed, target_speed, acceleration * throttle * delta)
	elif reverse_input > 0.01:
		if forward_speed > 1.0:
			forward_speed = move_toward(forward_speed, 0.0, brake_force * reverse_input * delta)
		else:
			forward_speed = move_toward(forward_speed, -reverse_speed, acceleration * 0.55 * reverse_input * delta)
	else:
		forward_speed = move_toward(forward_speed, 0.0, rolling_drag * delta)

	var steer_factor: float = clampf(absf(forward_speed) / maxf(1.0, top_speed), 0.12, 1.0)
	if abs(forward_speed) > 0.4 and abs(steer_input) > 0.01:
		rotate_y(-steer_input * steering_rate * steer_factor * sign(forward_speed) * delta)

	forward = -global_transform.basis.z.normalized()
	right = global_transform.basis.x.normalized()

	lateral_speed = move_toward(
		lateral_speed,
		0.0,
		lateral_grip * delta * max(1.0, abs(forward_speed) * 0.35)
	)

	if boost and forward_speed > 2.0:
		forward_speed += turbo_force * delta

	is_offroad = track != null and not track.is_on_track(global_position, -0.25)
	if is_offroad:
		forward_speed = move_toward(forward_speed, 0.0, offroad_drag * delta)
		forward_speed = clamp(forward_speed, -reverse_speed * 0.55, top_speed * 0.58)

	velocity = forward * forward_speed + right * lateral_speed
	velocity.y = 0.0

	move_and_slide()

	global_position.y = ride_height
	rotation.x = 0.0
	rotation.z = 0.0
	speed_kmh = abs(forward_speed) * 3.6

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
	var visual := Node3D.new()
	visual.name = "CarVisual"
	add_child(visual)

	var paint := _make_material(body_color, 0.24, 0.28)
	var dark := _make_material(Color("#10141a"), 0.5, 0.05)
	var glass := _make_material(Color("#203345"), 0.15, 0.32)
	var white := _make_material(Color("#f6f4ed"), 0.3, 0.1)

	visual.add_child(_mesh_box(Vector3(1.45, 0.42, 2.75), Vector3(0, 0.42, 0), paint))
	visual.add_child(_mesh_box(Vector3(1.15, 0.38, 1.05), Vector3(0, 0.77, -0.18), glass))
	visual.add_child(_mesh_box(Vector3(0.28, 0.05, 2.35), Vector3(0, 0.68, -0.06), white))
	visual.add_child(_mesh_box(Vector3(1.5, 0.12, 0.18), Vector3(0, 0.65, 1.25), dark))

	var wheel_positions := [
		Vector3(-0.82, 0.28, -0.88),
		Vector3(0.82, 0.28, -0.88),
		Vector3(-0.82, 0.28, 0.88),
		Vector3(0.82, 0.28, 0.88)
	]

	for wheel_position in wheel_positions:
		var wheel := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.28
		cylinder.bottom_radius = 0.28
		cylinder.height = 0.22
		wheel.mesh = cylinder
		wheel.position = wheel_position
		wheel.rotation_degrees.z = 90.0
		wheel.material_override = dark
		visual.add_child(wheel)
