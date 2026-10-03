class_name AIRacer3D
extends ArcadeCarController3D

@export var progress_ratio: float = 0.0
@export var speed_mps: float = 27.0
@export var lane_offset: float = 0.0
@export var driver_skill: float = 0.88
@export var aggression: float = 0.56
@export var braking_confidence: float = 0.90
@export var avoidance_strength: float = 0.72

var lap_count: int = 0
var _last_progress_ratio: float = 0.0
var _race_started: bool = false

func _ready() -> void:
	input_enabled = false
	autopilot_enabled = true
	autopilot_target_speed = speed_mps
	throttle_rise_rate = lerpf(3.3, 4.4, driver_skill)
	brake_rise_rate = lerpf(7.5, 10.5, braking_confidence)
	steering_input_rate = lerpf(4.1, 5.4, driver_skill)
	countersteer_input_rate = lerpf(7.3, 9.4, driver_skill)
	add_to_group("race_cars")
	super._ready()
	_last_progress_ratio = progress_ratio

func _process(_delta: float) -> void:
	if track == null or track.get_length() <= 0.0:
		return

	var actual_ratio := track.get_progress_ratio(global_position)

	if _race_started and _last_progress_ratio > 0.88 and actual_ratio < 0.12:
		lap_count += 1

	progress_ratio = actual_ratio
	_last_progress_ratio = actual_ratio
	_race_started = true

func _autopilot_controls() -> Dictionary:
	if track == null or track.get_length() <= 0.0:
		return {
			"throttle": 0.0,
			"brake": 1.0,
			"steer": 0.0,
			"boost": false
		}

	var length := track.get_length()
	var ratio := track.get_progress_ratio(global_position)
	var speed_ratio := clampf(speed_kmh / maxf(1.0, top_speed * 3.6), 0.0, 1.0)

	# Skilled drivers look further through a corner as speed rises.
	var near_distance := lerpf(10.0, 23.0, speed_ratio) * lerpf(0.92, 1.08, driver_skill)
	var medium_distance := lerpf(23.0, 42.0, speed_ratio)
	var far_distance := lerpf(38.0, 66.0, speed_ratio)

	var near_frame := track.get_world_transform_at_ratio(ratio + near_distance / length)
	var medium_frame := track.get_world_transform_at_ratio(ratio + medium_distance / length)
	var far_frame := track.get_world_transform_at_ratio(ratio + far_distance / length)

	var traffic := _traffic_response()

	# Measure upcoming curvature at two horizons so braking starts before the car
	# has already entered the corner.
	var current_frame := track.get_world_transform_at_ratio(ratio)
	var current_forward := -current_frame.basis.z.normalized()
	var medium_forward := -medium_frame.basis.z.normalized()
	var far_forward := -far_frame.basis.z.normalized()

	var medium_change := acos(clampf(current_forward.dot(medium_forward), -1.0, 1.0))
	var far_change := acos(clampf(current_forward.dot(far_forward), -1.0, 1.0))
	var curvature := maxf(
		medium_change / deg_to_rad(72.0),
		far_change / deg_to_rad(108.0)
	)
	curvature = clampf(curvature, 0.0, 1.0)

	# Pull the racing line closer to the center in sharp corners; this leaves
	# physical margin for slip and prevents a fixed lane offset touching barriers.
	var corner_lane_scale := lerpf(1.0, 0.42, pow(curvature, 0.8))
	var desired_lane := clampf(
		lane_offset * corner_lane_scale + float(traffic.offset),
		-1.75,
		1.75
	)
	var target_point := near_frame.origin + near_frame.basis.x * desired_lane
	var local_target := to_local(target_point)

	var steer := clampf(
		local_target.x / maxf(2.0, absf(local_target.z) * lerpf(0.88, 0.72, driver_skill)),
		-1.0,
		1.0
	)

	var pace_scale := lerpf(0.88, 1.06, driver_skill)
	var aggression_scale := lerpf(0.92, 1.08, aggression)
	var straight_speed := speed_mps * pace_scale * aggression_scale
	var corner_floor := lerpf(8.0, 11.5, driver_skill)
	var desired_speed := lerpf(straight_speed, corner_floor, pow(curvature, 0.72))
	desired_speed *= float(traffic.speed_scale)

	# Tire state and current slide influence the target exactly as they would for
	# a human driver lifting or braking to save a slide.
	if drift_intensity > 0.18 or absf(vehicle_slip_angle_deg) > 9.0:
		desired_speed *= lerpf(0.78, 0.88, driver_skill)
	if rear_tire_saturation > 1.12:
		desired_speed *= 0.90
	if is_offroad:
		desired_speed = minf(desired_speed, 7.5)

	var current_speed := maxf(0.0, longitudinal_speed)
	var speed_error := desired_speed - current_speed

	var throttle := clampf(speed_error / lerpf(4.8, 3.2, driver_skill), 0.0, 1.0)
	var brake := clampf((-speed_error) / lerpf(3.8, 2.6, braking_confidence), 0.0, 1.0)
	brake = maxf(brake, float(traffic.brake))

	# Do not keep adding throttle while the rear axle is already rotating away.
	if absf(vehicle_slip_angle_deg) > 14.0:
		throttle *= 0.35
	if absf(vehicle_slip_angle_deg) > 20.0:
		throttle = 0.0
		brake = maxf(brake, 0.16)

	if brake > 0.04:
		throttle = 0.0

	return {
		"throttle": throttle,
		"brake": brake,
		"steer": steer,
		"boost": false
	}

func _traffic_response() -> Dictionary:
	if not is_inside_tree():
		return {"offset": 0.0, "speed_scale": 1.0, "brake": 0.0}

	var correction := 0.0
	var speed_scale := 1.0
	var brake := 0.0
	var forward := -global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()

	for other in get_tree().get_nodes_in_group("race_cars"):
		if other == self or not (other is Node3D):
			continue

		var other_car := other as Node3D
		var delta := other_car.global_position - global_position
		var longitudinal := delta.dot(forward)
		var lateral := delta.dot(right)

		if longitudinal <= 0.0 or longitudinal >= 11.0 or absf(lateral) >= 3.2:
			continue

		var urgency := 1.0 - longitudinal / 11.0
		var pass_side := -1.0 if lateral >= 0.0 else 1.0
		correction += pass_side * urgency * avoidance_strength * 0.95

		if absf(lateral) < 1.65:
			speed_scale = minf(speed_scale, lerpf(0.64, 0.96, longitudinal / 11.0))
			brake = maxf(brake, pow(urgency, 1.35) * 0.72)

		if longitudinal < 3.2 and absf(lateral) < 1.25:
			brake = maxf(brake, 0.92)
			speed_scale = minf(speed_scale, 0.56)

	return {
		"offset": clampf(correction, -1.05, 1.05),
		"speed_scale": clampf(speed_scale, 0.50, 1.0),
		"brake": clampf(brake, 0.0, 1.0)
	}

func total_progress() -> float:
	return float(lap_count) + progress_ratio

func ai_telemetry() -> Dictionary:
	var data := telemetry()
	data["lap"] = lap_count
	data["progress_ratio"] = snappedf(progress_ratio, 0.0001)
	data["lane_offset"] = lane_offset
	data["driver_skill"] = driver_skill
	data["aggression"] = aggression
	return data
