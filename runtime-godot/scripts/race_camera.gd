class_name RaceCamera3D
extends Camera3D

@export var height: float = 6.8
@export var follow_distance: float = 10.6
@export var look_ahead: float = 9.8
@export var position_smoothing: float = 6.4
@export var target_smoothing: float = 8.2
@export var base_fov: float = 46.5
@export var speed_fov_gain: float = 9.0
@export var drift_look_gain: float = 0.26
@export var drift_follow_gain: float = 0.075
@export var drift_fov_gain: float = 2.4
@export var brake_push_gain: float = 0.85
@export var acceleration_pull_gain: float = 0.52
@export var max_camera_roll_deg: float = 2.4
@export var speed_shake_strength: float = 0.055
@export var offroad_shake_strength: float = 0.13

var target: ArcadeCarController3D
var _smoothed_target: Vector3
var _smoothed_roll: float = 0.0

func _ready() -> void:
	current = true
	fov = base_fov

	if target:
		_smoothed_target = target.global_position

func _process(delta: float) -> void:
	if target == null:
		return

	var forward := -target.global_transform.basis.z.normalized()
	var right := target.global_transform.basis.x.normalized()
	var lateral_velocity := target.lateral_speed_body
	var drift_target_offset := clampf(lateral_velocity * drift_look_gain, -3.0, 3.0)
	var drift_camera_offset := clampf(lateral_velocity * drift_follow_gain, -1.05, 1.05)

	var speed_ratio: float = clampf(target.speed_kmh / 170.0, 0.0, 1.0)
	var accel_pull := clampf(target.longitudinal_accel_g, -1.2, 1.2)
	var dynamic_distance := follow_distance
	dynamic_distance += maxf(0.0, accel_pull) * acceleration_pull_gain
	dynamic_distance -= maxf(0.0, -accel_pull) * brake_push_gain

	var shake_strength := speed_shake_strength * pow(speed_ratio, 2.0)
	if target.is_offroad:
		shake_strength += offroad_shake_strength * clampf(target.speed_kmh / 90.0, 0.0, 1.0)
	var clock := Time.get_ticks_msec() * 0.001
	var shake_x := sin(clock * 24.0 + target.speed_kmh * 0.017) * shake_strength
	var shake_y := sin(clock * 31.0 + 1.7) * shake_strength * 0.65

	var desired_position := (
		target.global_position
		+ Vector3.UP * (height + shake_y)
		- forward * dynamic_distance
		+ right * (drift_camera_offset + shake_x)
	)
	var desired_target := (
		target.global_position
		+ forward * (look_ahead + speed_ratio * 2.8)
		+ right * drift_target_offset
		+ Vector3.UP * 0.40
	)

	var position_weight := 1.0 - exp(-position_smoothing * delta)
	var target_weight := 1.0 - exp(-target_smoothing * delta)

	global_position = global_position.lerp(desired_position, position_weight)
	_smoothed_target = _smoothed_target.lerp(desired_target, target_weight)
	look_at(_smoothed_target, Vector3.UP)

	var roll_target := clampf(
		-target.lateral_accel_g * deg_to_rad(0.95)
		- target.steering_input * deg_to_rad(0.55),
		-deg_to_rad(max_camera_roll_deg),
		deg_to_rad(max_camera_roll_deg)
	)
	_smoothed_roll = lerp_angle(_smoothed_roll, roll_target, 1.0 - exp(-5.5 * delta))
	rotate_object_local(Vector3.FORWARD, _smoothed_roll)

	var target_fov := (
		base_fov
		+ pow(speed_ratio, 0.82) * speed_fov_gain
		+ target.drift_intensity * drift_fov_gain
	)
	if target.is_shifting:
		target_fov += 0.45
	fov = lerp(fov, target_fov, 1.0 - exp(-5.2 * delta))
