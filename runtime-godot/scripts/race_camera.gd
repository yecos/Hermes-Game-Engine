class_name RaceCamera3D
extends Camera3D

@export var height: float = 12.2
@export var follow_distance: float = 16.8
@export var look_ahead: float = 6.2
@export var position_smoothing: float = 5.5
@export var target_smoothing: float = 7.0
@export var base_fov: float = 34.0
@export var speed_fov_gain: float = 4.6
@export var drift_look_gain: float = 0.22
@export var drift_follow_gain: float = 0.065
@export var drift_fov_gain: float = 1.2

var target: ArcadeCarController3D
var _smoothed_target: Vector3

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
	var drift_target_offset := clampf(lateral_velocity * drift_look_gain, -2.4, 2.4)
	var drift_camera_offset := clampf(lateral_velocity * drift_follow_gain, -0.85, 0.85)

	var desired_position := (
		target.global_position
		+ Vector3.UP * height
		- forward * follow_distance
		+ right * drift_camera_offset
	)
	var desired_target := (
		target.global_position
		+ forward * look_ahead
		+ right * drift_target_offset
	)

	var position_weight := 1.0 - exp(-position_smoothing * delta)
	var target_weight := 1.0 - exp(-target_smoothing * delta)

	global_position = global_position.lerp(desired_position, position_weight)
	_smoothed_target = _smoothed_target.lerp(desired_target, target_weight)
	look_at(_smoothed_target, Vector3.UP)

	var speed_ratio: float = clampf(target.speed_kmh / 150.0, 0.0, 1.0)
	var target_fov := (
		base_fov
		+ speed_ratio * speed_fov_gain
		+ target.drift_intensity * drift_fov_gain
	)
	fov = lerp(fov, target_fov, 1.0 - exp(-4.0 * delta))
