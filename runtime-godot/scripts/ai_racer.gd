class_name AIRacer3D
extends ArcadeCarController3D

@export var progress_ratio: float = 0.0
@export var speed_mps: float = 27.0
@export var lane_offset: float = 0.0
@export var driver_skill: float = 0.88
@export var aggression: float = 0.56
@export var braking_confidence: float = 0.90
@export var avoidance_strength: float = 0.72
@export var driving_style: String = "balanced"
@export var drift_bias: float = 0.12
@export var late_brake_bias: float = 0.0
@export var countersteer_skill: float = 0.88
@export var throttle_commitment: float = 0.62
@export var line_variation: float = 0.0
@export var line_phase: float = 0.0

var lap_count: int = 0
var peak_drift_intensity: float = 0.0
var peak_slip_angle_deg: float = 0.0
var drift_time_seconds: float = 0.0
var _drift_entry_until_msec: int = 0
var _drift_cooldown_until_msec: int = 0
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

func _process(delta: float) -> void:
	peak_drift_intensity = maxf(peak_drift_intensity, drift_intensity)
	peak_slip_angle_deg = maxf(peak_slip_angle_deg, absf(vehicle_slip_angle_deg))
	if drift_intensity > 0.16 and speed_kmh > 35.0:
		drift_time_seconds += delta

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
	var far_distance := lerpf(38.0, 66.0, speed_ratio) * lerpf(1.0, 0.88, late_brake_bias)

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
	var natural_line_variation := (
		sin(ratio * TAU * 2.0 + line_phase)
		* line_variation
		* lerpf(1.0, 0.35, curvature)
	)
	var desired_lane := clampf(
		lane_offset * corner_lane_scale
		+ natural_line_variation
		+ float(traffic.offset),
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

	var current_speed := maxf(0.0, longitudinal_speed)
	var drift_opportunity := (
		drift_bias
		* smoothstep(0.16, 0.72, curvature)
		* smoothstep(11.0, 22.0, current_speed)
	)

	# Drivers with drift intent turn in a little harder. Once the rear starts
	# rotating, they countersteer from actual yaw/slip instead of following a spline.
	steer *= 1.0 + drift_opportunity * 0.46

	var slide_amount := smoothstep(5.0, 20.0, absf(vehicle_slip_angle_deg))
	var countersteer_signal := clampf(
		yaw_rate * 0.50 + deg_to_rad(vehicle_slip_angle_deg) * 0.68,
		-0.58,
		0.58
	)
	steer -= countersteer_signal * countersteer_skill * slide_amount
	steer = clampf(steer, -1.0, 1.0)

	var pace_scale := lerpf(0.88, 1.06, driver_skill)
	var aggression_scale := lerpf(0.92, 1.08, aggression)
	var straight_speed := speed_mps * pace_scale * aggression_scale
	var corner_floor := lerpf(8.0, 11.5, driver_skill) + drift_bias * 4.8
	var desired_speed := lerpf(straight_speed, corner_floor, pow(curvature, 0.72))
	desired_speed *= 1.0 + late_brake_bias * curvature * 0.08
	desired_speed *= 1.0 + drift_opportunity * 0.12
	desired_speed *= float(traffic.speed_scale)

	# Tire state and current slide influence the target exactly as they would for
	# a human driver lifting or braking to save a slide.
	if drift_intensity > 0.18 or absf(vehicle_slip_angle_deg) > 9.0:
		desired_speed *= lerpf(0.78, 0.88, driver_skill)
	if rear_tire_saturation > 1.12:
		desired_speed *= 0.90
	if is_offroad:
		desired_speed = minf(desired_speed, 7.5)

	var speed_error := desired_speed - current_speed

	var throttle := clampf(speed_error / lerpf(4.8, 3.2, driver_skill), 0.0, 1.0)
	var brake := clampf((-speed_error) / lerpf(3.8, 2.6, braking_confidence), 0.0, 1.0)
	brake *= 1.0 - late_brake_bias * 0.22
	brake = maxf(brake, float(traffic.brake))

	var now_msec := Time.get_ticks_msec()
	var can_start_drift := (
		drift_bias > 0.55
		and drift_opportunity > 0.16
		and current_speed > 14.0
		and absf(vehicle_slip_angle_deg) < 3.0
		and now_msec >= _drift_cooldown_until_msec
	)
	if can_start_drift:
		_drift_entry_until_msec = now_msec + 230
		_drift_cooldown_until_msec = now_msec + 1550

	if now_msec < _drift_entry_until_msec:
		# Real weight-transfer initiation: brief trail brake while turning in.
		brake = maxf(brake, lerpf(0.16, 0.30, drift_bias))
		throttle *= 0.12
		steer = clampf(steer * 1.10, -1.0, 1.0)
	elif drift_opportunity > 0.08 and brake < 0.18:
		var drift_throttle_floor := (
			lerpf(0.44, 0.88, throttle_commitment)
			* lerpf(0.55, 1.0, drift_opportunity)
		)
		if drift_bias > 0.55 and absf(vehicle_slip_angle_deg) > 3.0:
			drift_throttle_floor = maxf(drift_throttle_floor, 0.58)
		throttle = maxf(throttle, drift_throttle_floor)

	# Different drivers tolerate different slip angles before lifting.
	var save_threshold := lerpf(12.0, 23.0, drift_bias)
	var critical_threshold := lerpf(20.0, 31.0, drift_bias)
	var slip_abs := absf(vehicle_slip_angle_deg)

	if slip_abs > save_threshold:
		throttle *= lerpf(0.32, 0.72, drift_bias)
	if slip_abs > critical_threshold:
		throttle *= 0.20
		brake = maxf(brake, lerpf(0.18, 0.08, drift_bias))

	if brake > 0.08:
		throttle *= 0.15

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

		if longitudinal <= 0.0 or longitudinal >= 12.0 or absf(lateral) >= 3.4:
			continue

		var urgency := 1.0 - longitudinal / 12.0
		var pass_side := -1.0 if lateral >= 0.0 else 1.0
		correction += pass_side * urgency * avoidance_strength * 1.10

		var other_forward_speed := 0.0
		if other is ArcadeCarController3D:
			var other_physics := other as ArcadeCarController3D
			other_forward_speed = other_physics._world_planar_velocity().dot(forward)

		var own_forward_speed := _world_planar_velocity().dot(forward)
		var closing_speed := maxf(0.0, own_forward_speed - other_forward_speed)

		if absf(lateral) < 1.70:
			var follow_pressure := clampf(
				closing_speed / 8.0 + maxf(0.0, 5.0 - longitudinal) / 5.0,
				0.0,
				1.0
			)
			speed_scale = minf(speed_scale, lerpf(1.0, 0.70, follow_pressure))
			brake = maxf(brake, follow_pressure * 0.58)

		# Emergency braking only when we are actually closing fast on a short gap.
		if longitudinal < 2.8 and absf(lateral) < 1.20 and closing_speed > 2.0:
			brake = maxf(brake, 0.88)
			speed_scale = minf(speed_scale, 0.58)

		# At low relative speed prefer changing line instead of deadlocking.
		if longitudinal < 4.0 and closing_speed < 1.0:
			correction += pass_side * 0.40
			brake = minf(brake, 0.24)

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
	data["driving_style"] = driving_style
	data["drift_bias"] = drift_bias
	data["peak_drift_intensity"] = snappedf(peak_drift_intensity, 0.001)
	data["peak_slip_angle_deg"] = snappedf(peak_slip_angle_deg, 0.1)
	data["drift_time_seconds"] = snappedf(drift_time_seconds, 0.01)
	return data
