class_name ArcadeCarController3D
extends CharacterBody3D

# ---------------------------------------------------------------------------
# Driver / legacy tuning surface
# ---------------------------------------------------------------------------

@export var input_enabled: bool = true
@export var body_color: Color = Color("#ef3f51")
@export var top_speed: float = 48.0
@export var reverse_speed: float = 11.0
@export var acceleration: float = 25.0
@export var brake_force: float = 38.0
@export var rolling_drag: float = 8.0
@export var lateral_grip: float = 14.0
@export var steering_rate: float = 2.35
@export var offroad_drag: float = 18.0
@export var turbo_force: float = 16.0
@export var ride_height: float = 0.48

# ---------------------------------------------------------------------------
# Chassis / tire model
# ---------------------------------------------------------------------------

@export_group("Vehicle Dynamics")
@export var vehicle_mass: float = 1160.0
@export var yaw_inertia: float = 2050.0
@export var wheelbase: float = 2.62
@export var cg_to_front: float = 1.18
@export var cg_height: float = 0.48
@export var tire_mu: float = 1.18
@export var front_cornering_stiffness: float = 82000.0
@export var rear_cornering_stiffness: float = 80000.0
@export var max_steer_low_speed_deg: float = 29.0
@export var max_steer_high_speed_deg: float = 8.5
@export var aero_drag_coefficient_area: float = 0.72
@export var rolling_resistance_coefficient: float = 0.016
@export var stability_assist: float = 0.24
@export var max_controlled_slip_deg: float = 30.0
@export var spin_recovery_strength: float = 12.0
@export var surface_grip_offroad: float = 0.58

@export_group("Collision Physics")
@export var car_restitution: float = 0.18
@export var static_restitution: float = 0.10
@export var collision_friction: float = 0.24
@export var collision_yaw_transfer: float = 0.28
@export var impact_damage_threshold_mps: float = 4.0
@export var impact_damage_scale: float = 0.010

@export_group("Driver Feel")
@export var throttle_rise_rate: float = 3.8
@export var throttle_release_rate: float = 7.5
@export var brake_rise_rate: float = 9.0
@export var brake_release_rate: float = 11.0
@export var steering_input_rate: float = 4.8
@export var steering_return_rate: float = 7.0
@export var countersteer_input_rate: float = 8.5
@export var input_deadzone: float = 0.015

# ---------------------------------------------------------------------------
# Engine / transmission
# ---------------------------------------------------------------------------

@export_group("Powertrain")
@export var idle_rpm: float = 1050.0
@export var redline_rpm: float = 7600.0
@export var upshift_rpm_full_throttle: float = 7050.0
@export var upshift_rpm_light_throttle: float = 6250.0
@export var downshift_rpm: float = 2850.0
@export var max_engine_torque_nm: float = 335.0
@export var final_drive: float = 4.10
@export var driveline_efficiency: float = 0.90
@export var wheel_radius: float = 0.31
@export var reverse_ratio: float = 3.20
@export var gear_ratios: Array[float] = [3.20, 2.25, 1.70, 1.35, 1.10]
@export var upshift_times: Array[float] = [0.24, 0.20, 0.18, 0.17]
@export var downshift_time: float = 0.18
@export var shift_lockout_time: float = 0.14
@export var downshift_blip_rpm: float = 260.0

# ---------------------------------------------------------------------------
# Consumables
# ---------------------------------------------------------------------------

@export_group("Race Systems")
@export var fuel_capacity_liters: float = 42.0
@export var fuel_burn_per_second: float = 0.035
@export var tire_wear_rate: float = 0.00032
@export var pit_service_rate: float = 0.55

# ---------------------------------------------------------------------------
# Public runtime state
# ---------------------------------------------------------------------------

var track: TrackSpline

var speed_kmh: float = 0.0
var signed_speed_kmh: float = 0.0
var is_offroad: bool = false
var slip_amount: float = 0.0
var drift_intensity: float = 0.0
var vehicle_slip_angle_deg: float = 0.0
var front_slip_angle_deg: float = 0.0
var rear_slip_angle_deg: float = 0.0
var lateral_accel_g: float = 0.0
var longitudinal_accel_g: float = 0.0
var front_tire_saturation: float = 0.0
var rear_tire_saturation: float = 0.0

var last_impact_speed_mps: float = 0.0
var last_impact_impulse_ns: float = 0.0
var impact_count: int = 0

var engine_rpm: float = 1050.0
var current_gear: int = 1
var pending_gear: int = 1
var is_shifting: bool = false
var throttle_input: float = 0.0
var brake_input: float = 0.0
var steering_input: float = 0.0
var steering_angle_deg: float = 0.0

var fuel_liters: float = 42.0
var tire_health: float = 1.0
var damage: float = 0.0
var in_pit_lane: bool = false
var pit_servicing: bool = false
var replay_mode: bool = false

var autopilot_enabled: bool = false
var autopilot_target_speed: float = 27.0
var autopilot_lookahead: float = 0.018
var autopilot_recoveries: int = 0

# ---------------------------------------------------------------------------
# Dynamic state in the car body frame
# longitudinal_speed: +forward, lateral_speed_body: +right, yaw_rate: +right turn
# ---------------------------------------------------------------------------

var longitudinal_speed: float = 0.0
var lateral_speed_body: float = 0.0
var yaw_rate: float = 0.0
var longitudinal_accel: float = 0.0
var lateral_accel: float = 0.0

var _previous_longitudinal_speed: float = 0.0
var _shift_timer: float = 0.0
var _shift_total_time: float = 0.0
var _shift_lockout_timer: float = 0.0
var _shift_from_gear: int = 1
var _shift_committed: bool = false
var _shift_kick: float = 0.0
var _stationary_reverse_hold: float = 0.0
var _steering_reversal_target: float = 0.0
var _autopilot_stuck_time: float = 0.0
var _pre_move_velocity: Vector3 = Vector3.ZERO
var _resolved_vehicle_collision_frames: Dictionary = {}
var _contact_event_frames: Dictionary = {}

var _visual: Node3D
var _visual_detail_rig: Node3D
var _wheel_nodes: Array[Node3D] = []
var _rear_wheel_local_positions: Array[Vector3] = [
	Vector3(-0.82, 0.28, 0.88),
	Vector3(0.82, 0.28, 0.88)
]
var _skid_root: Node3D
var _skid_marks: Array[Node3D] = []
var _skid_timer: float = 0.0
var _smoke_timer: float = 0.0
var _dust_timer: float = 0.0
var _tire_smoke_gpu: GPUParticles3D
var _offroad_dust_gpu: GPUParticles3D
var _gravel_debris_gpu: GPUParticles3D
var _wet_spray_gpu: GPUParticles3D
var _weather_wetness: float = 0.0
var _night_factor: float = 0.0
var _headlight_lights: Array[SpotLight3D] = []
var _engine_audio: EngineAudio3D
var _fx_audio: VehicleFxAudio3D
var _brake_light_material: StandardMaterial3D
var _headlight_material: StandardMaterial3D

const AIR_DENSITY := 1.225
const GRAVITY_ACCEL := 9.81

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	fuel_liters = fuel_capacity_liters
	engine_rpm = idle_rpm
	_build_collision()
	_build_visual()
	_build_visual_details()
	_build_effects()
	_build_audio()

func _physics_process(delta: float) -> void:
	if replay_mode:
		velocity = Vector3.ZERO
		return
	if not input_enabled and not autopilot_enabled:
		return

	var throttle := 0.0
	var brake_reverse := 0.0
	var steer := 0.0
	var boost := false
	var pit_requested := false

	if autopilot_enabled:
		var controls := _autopilot_controls()
		throttle = float(controls.throttle)
		brake_reverse = float(controls.brake)
		steer = float(controls.steer)
		boost = bool(controls.boost)
	else:
		throttle = Input.get_action_strength("accelerate")
		brake_reverse = Input.get_action_strength("brake_reverse")
		steer = Input.get_axis("steer_left", "steer_right")
		boost = Input.is_action_pressed("boost")
		pit_requested = Input.is_action_pressed("pit_service")

	# Human and AI drivers pass through the same pedal/steering response model.
	_update_driver_inputs(delta, throttle, brake_reverse, steer)

	in_pit_lane = track != null and track.is_in_pit_zone(global_position)
	is_offroad = track != null and not track.is_on_track(global_position, -0.20)

	_update_transmission(delta, not autopilot_enabled)
	_step_vehicle_dynamics(delta, boost)
	_apply_world_motion(delta)
	_update_surface_height()
	_update_race_state(delta, pit_requested, boost)

	if autopilot_enabled and _update_autopilot_recovery(delta):
		return

func _update_driver_inputs(
	delta: float,
	throttle_target: float,
	brake_target: float,
	steer_target: float
) -> void:
	throttle_target = clampf(throttle_target, 0.0, 1.0)
	brake_target = clampf(brake_target, 0.0, 1.0)
	steer_target = clampf(steer_target, -1.0, 1.0)

	var throttle_rate := throttle_rise_rate if throttle_target > throttle_input else throttle_release_rate
	var brake_rate := brake_rise_rate if brake_target > brake_input else brake_release_rate
	throttle_input = move_toward(throttle_input, throttle_target, throttle_rate * delta)
	brake_input = move_toward(brake_input, brake_target, brake_rate * delta)

	if absf(steer_target) < input_deadzone:
		steer_target = 0.0

	# Analog inputs get a little extra precision around center. Keyboard input still
	# reaches full lock, but the temporal ramp prevents A/D from behaving like switches.
	if absf(steer_target) > 0.0:
		steer_target = signf(steer_target) * pow(absf(steer_target), 1.08)

	if (
		absf(steer_target) > 0.10
		and absf(steering_input) > 0.10
		and signf(steer_target) != signf(steering_input)
	):
		_steering_reversal_target = signf(steer_target)

	if (
		_steering_reversal_target != 0.0
		and (
			absf(steer_target) < 0.10
			or signf(steer_target) != signf(_steering_reversal_target)
		)
	):
		_steering_reversal_target = 0.0

	var steering_rate := steering_input_rate
	if is_zero_approx(steer_target):
		steering_rate = steering_return_rate
	elif _steering_reversal_target != 0.0:
		steering_rate = countersteer_input_rate

	steering_input = move_toward(steering_input, steer_target, steering_rate * delta)

	if (
		_steering_reversal_target != 0.0
		and absf(steering_input - steer_target) < 0.06
	):
		_steering_reversal_target = 0.0

func _step_vehicle_dynamics(delta: float, boost: bool) -> void:
	var speed_abs := absf(longitudinal_speed)
	var direction_sign := 1.0 if longitudinal_speed >= -0.05 else -1.0

	var damage_factor := lerpf(1.0, 0.72, clampf(damage, 0.0, 1.0))
	var wear_grip := lerpf(0.66, 1.0, clampf(tire_health, 0.0, 1.0))
	var grip_scale := pow(maxf(0.25, lateral_grip / 14.0), 0.34)
	var surface_mu := tire_mu * wear_grip * grip_scale
	if is_offroad:
		surface_mu *= surface_grip_offroad

	var normalized_speed := clampf(speed_abs / maxf(1.0, top_speed), 0.0, 1.0)
	var max_steer := deg_to_rad(lerpf(max_steer_low_speed_deg, max_steer_high_speed_deg, pow(normalized_speed, 0.55)))
	var steer_target := steering_input * max_steer
	var steering_response := steering_rate * 3.25
	var steering_angle := deg_to_rad(steering_angle_deg)
	steering_angle = move_toward(steering_angle, steer_target, steering_response * delta)
	steering_angle_deg = rad_to_deg(steering_angle)

	# Reverse is intentionally more stable and kinematic at low speed.
	# It also handles the launch from standstill after R is engaged.
	if current_gear == -1 and brake_input > 0.01 and longitudinal_speed <= 0.25:
		_step_reverse_dynamics(delta, steering_angle, surface_mu)
		return
	if longitudinal_speed < -0.15:
		_step_reverse_dynamics(delta, steering_angle, surface_mu)
		return

	var rear_distance := maxf(0.1, wheelbase - cg_to_front)
	var speed_for_slip := maxf(2.2, speed_abs)

	var front_slip := atan2(
		lateral_speed_body + cg_to_front * yaw_rate,
		speed_for_slip
	) - steering_angle
	var rear_slip := atan2(
		lateral_speed_body - rear_distance * yaw_rate,
		speed_for_slip
	)

	front_slip_angle_deg = rad_to_deg(front_slip)
	rear_slip_angle_deg = rad_to_deg(rear_slip)
	vehicle_slip_angle_deg = rad_to_deg(atan2(lateral_speed_body, maxf(1.0, speed_abs)))

	var static_front_load := vehicle_mass * GRAVITY_ACCEL * rear_distance / wheelbase
	var static_rear_load := vehicle_mass * GRAVITY_ACCEL * cg_to_front / wheelbase

	var transfer := vehicle_mass * longitudinal_accel * cg_height / wheelbase
	var front_normal := clampf(static_front_load - transfer, vehicle_mass * GRAVITY_ACCEL * 0.25, vehicle_mass * GRAVITY_ACCEL * 0.72)
	var rear_normal := vehicle_mass * GRAVITY_ACCEL - front_normal

	var max_front_force := surface_mu * front_normal
	var max_rear_force := surface_mu * rear_normal

	var raw_front_lateral := -front_cornering_stiffness * front_slip
	var raw_rear_lateral := -rear_cornering_stiffness * rear_slip

	var drive_force := _drivetrain_force(boost) * damage_factor
	var brake_force_total := _braking_force()
	var brake_front := brake_force_total * 0.64
	var brake_rear := brake_force_total * 0.36

	var longitudinal_front := -signf(maxf(0.01, longitudinal_speed)) * brake_front
	var longitudinal_rear := drive_force - signf(maxf(0.01, longitudinal_speed)) * brake_rear

	# Friction circle: longitudinal demand consumes part of the available tire force.
	# RWD drive is limited below 100% utilization so power-oversteer is progressive,
	# rather than instantly deleting every bit of rear lateral grip.
	longitudinal_front = clampf(longitudinal_front, -max_front_force * 0.96, max_front_force * 0.96)
	if drive_force > 0.0 and brake_force_total <= 0.01:
		longitudinal_rear = clampf(longitudinal_rear, 0.0, max_rear_force * 0.72)
	else:
		longitudinal_rear = clampf(longitudinal_rear, -max_rear_force * 0.96, max_rear_force * 0.96)

	var front_lat_limit := sqrt(maxf(0.0, max_front_force * max_front_force - longitudinal_front * longitudinal_front))
	var rear_lat_limit := sqrt(maxf(0.0, max_rear_force * max_rear_force - longitudinal_rear * longitudinal_rear))

	var front_lateral := 0.0
	var rear_lateral := 0.0
	if front_lat_limit > 1.0:
		front_lateral = -front_lat_limit * tanh(
			front_cornering_stiffness * front_slip / front_lat_limit
		)
	if rear_lat_limit > 1.0:
		rear_lateral = -rear_lat_limit * tanh(
			rear_cornering_stiffness * rear_slip / rear_lat_limit
		)

	# Gentle stability assist keeps sustained drifts controllable without cancelling them.
	if speed_abs > 9.0 and absf(vehicle_slip_angle_deg) > 5.0:
		var assist := clampf(stability_assist, 0.0, 0.55)
		rear_lateral = clampf(
			rear_lateral - lateral_speed_body * vehicle_mass * assist,
			-rear_lat_limit,
			rear_lat_limit
		)

	var aero_drag := 0.5 * AIR_DENSITY * aero_drag_coefficient_area * longitudinal_speed * absf(longitudinal_speed)
	var rolling_force := rolling_resistance_coefficient * vehicle_mass * GRAVITY_ACCEL
	if speed_abs < 0.20:
		rolling_force *= clampf(speed_abs / 0.20, 0.0, 1.0)
	var rolling_drag_force := signf(longitudinal_speed) * rolling_force

	if is_offroad:
		rolling_drag_force += signf(longitudinal_speed) * offroad_drag * 95.0

	var force_x := longitudinal_rear + longitudinal_front - aero_drag - rolling_drag_force - front_lateral * sin(steering_angle)
	var force_y := rear_lateral + front_lateral * cos(steering_angle)

	var accel_x := force_x / vehicle_mass + lateral_speed_body * yaw_rate
	var accel_y := force_y / vehicle_mass - longitudinal_speed * yaw_rate
	var yaw_moment := cg_to_front * front_lateral * cos(steering_angle) - rear_distance * rear_lateral
	var yaw_accel := yaw_moment / maxf(100.0, yaw_inertia)

	# Mild electronic stability control. The requested bicycle-model yaw is
	# limited by the lateral acceleration the tires can physically generate.
	if speed_abs > 8.0:
		var kinematic_yaw := longitudinal_speed / maxf(0.5, wheelbase) * tan(steering_angle)
		var grip_yaw_limit := surface_mu * GRAVITY_ACCEL / maxf(5.0, speed_abs) * 0.94
		var desired_yaw_rate := clampf(kinematic_yaw, -grip_yaw_limit, grip_yaw_limit)
		var countersteering := (
			absf(steering_angle) > deg_to_rad(1.0)
			and absf(yaw_rate) > deg_to_rad(3.0)
			and signf(steering_angle) != signf(yaw_rate)
		)
		var esc_strength := stability_assist * smoothstep(3.0, 16.0, absf(vehicle_slip_angle_deg))
		if countersteering:
			esc_strength *= 1.42
		yaw_accel += (desired_yaw_rate - yaw_rate) * esc_strength * 5.5

		# When yaw exceeds what the current grip can sustain, individual-wheel
		# braking in a real ESC would create a correcting moment. This models that
		# moment without adding lateral tire force beyond the friction circle.
		var drift_yaw_limit := grip_yaw_limit * 1.34 + 0.08
		if absf(yaw_rate) > drift_yaw_limit:
			var bounded_yaw := clampf(yaw_rate, -drift_yaw_limit, drift_yaw_limit)
			var yaw_recovery := 6.2 if countersteering else 5.2
			yaw_accel += (bounded_yaw - yaw_rate) * yaw_recovery

	_previous_longitudinal_speed = longitudinal_speed
	longitudinal_speed += accel_x * delta
	lateral_speed_body += accel_y * delta
	yaw_rate += yaw_accel * delta

	# Final ESC envelope. It still allows a large drift angle, but prevents the
	# car from rotating faster than the available lateral grip can support.
	if speed_abs > 5.0:
		var planar_speed := maxf(
			5.0,
			sqrt(longitudinal_speed * longitudinal_speed + lateral_speed_body * lateral_speed_body)
		)
		var physical_yaw_cap := surface_mu * GRAVITY_ACCEL / planar_speed * 1.48 + 0.10
		physical_yaw_cap = minf(physical_yaw_cap, deg_to_rad(65.0))
		yaw_rate = clampf(yaw_rate, -physical_yaw_cap, physical_yaw_cap)

		var max_lateral_speed := tan(deg_to_rad(max_controlled_slip_deg)) * maxf(5.0, absf(longitudinal_speed))
		if absf(lateral_speed_body) > max_lateral_speed:
			var target_lateral := signf(lateral_speed_body) * max_lateral_speed
			var countersteer_recovery := (
				absf(steering_angle) > deg_to_rad(1.0)
				and absf(yaw_rate) > deg_to_rad(3.0)
				and signf(steering_angle) != signf(yaw_rate)
			)
			var recovery_strength := spin_recovery_strength * (1.30 if countersteer_recovery else 1.0)
			lateral_speed_body = lerpf(
				lateral_speed_body,
				target_lateral,
				1.0 - exp(-recovery_strength * delta)
			)

	# Aerodynamic / chassis yaw damping grows with speed.
	var physical_slip_damping := smoothstep(4.0, 20.0, absf(vehicle_slip_angle_deg))
	var yaw_damping := 0.48 + speed_abs * 0.014 + physical_slip_damping * 0.30
	yaw_rate = move_toward(yaw_rate, 0.0, yaw_damping * delta)

	if throttle_input <= 0.01 and brake_input <= 0.01 and speed_abs < 1.1:
		longitudinal_speed = move_toward(longitudinal_speed, 0.0, 1.4 * delta)
		lateral_speed_body = move_toward(lateral_speed_body, 0.0, 2.8 * delta)
		yaw_rate = move_toward(yaw_rate, 0.0, 1.2 * delta)

	longitudinal_speed = clampf(longitudinal_speed, -reverse_speed, top_speed * (1.08 if boost else 1.0))
	lateral_speed_body = clampf(lateral_speed_body, -18.0, 18.0)
	yaw_rate = clampf(yaw_rate, -2.8, 2.8)

	longitudinal_accel = accel_x
	lateral_accel = accel_y
	longitudinal_accel_g = accel_x / GRAVITY_ACCEL
	lateral_accel_g = accel_y / GRAVITY_ACCEL
	vehicle_slip_angle_deg = rad_to_deg(
		atan2(lateral_speed_body, maxf(1.0, absf(longitudinal_speed)))
	)

	front_tire_saturation = absf(raw_front_lateral) / maxf(1.0, max_front_force)
	rear_tire_saturation = absf(raw_rear_lateral) / maxf(1.0, max_rear_force)

	var slip_angle_rad := absf(atan2(lateral_speed_body, maxf(1.0, absf(longitudinal_speed))))
	var slip_component := smoothstep(0.060, 0.30, slip_angle_rad)
	var rear_breakaway := smoothstep(0.90, 1.45, rear_tire_saturation)
	var speed_component := smoothstep(7.0, 19.0, speed_abs)
	drift_intensity = clampf(maxf(slip_component, rear_breakaway * 0.68) * speed_component, 0.0, 1.0)
	slip_amount = clampf(absf(vehicle_slip_angle_deg) / 28.0, 0.0, 1.0)

func _step_reverse_dynamics(delta: float, steering_angle: float, surface_mu: float) -> void:
	var fuel_factor := 1.0 if fuel_liters > 0.01 else 0.0
	var reverse_throttle := brake_input if current_gear == -1 else 0.0

	var reverse_drive := max_engine_torque_nm * reverse_ratio * final_drive * driveline_efficiency / wheel_radius
	reverse_drive *= reverse_throttle * fuel_factor * (acceleration / 25.0)
	if is_shifting:
		reverse_drive *= _shift_torque_factor()

	var braking := 0.0
	if throttle_input > 0.01:
		braking = throttle_input * _max_brake_force_newtons()

	var rolling := rolling_resistance_coefficient * vehicle_mass * GRAVITY_ACCEL
	var net_force := -reverse_drive + braking + rolling
	var accel_x := net_force / vehicle_mass
	longitudinal_speed += accel_x * delta
	longitudinal_speed = clampf(longitudinal_speed, -reverse_speed, 0.0)

	var target_yaw := -longitudinal_speed / maxf(0.5, wheelbase) * tan(steering_angle)
	yaw_rate = lerpf(yaw_rate, target_yaw, 1.0 - exp(-5.5 * surface_mu * delta))
	lateral_speed_body = move_toward(lateral_speed_body, 0.0, 8.0 * surface_mu * delta)

	longitudinal_accel = accel_x
	lateral_accel = 0.0
	longitudinal_accel_g = accel_x / GRAVITY_ACCEL
	lateral_accel_g = 0.0
	drift_intensity = 0.0
	slip_amount = 0.0
	front_slip_angle_deg = 0.0
	rear_slip_angle_deg = 0.0
	vehicle_slip_angle_deg = 0.0

func _drivetrain_force(boost: bool) -> float:
	if current_gear <= 0 or is_shifting and not _shift_committed:
		return 0.0
	if fuel_liters <= 0.01:
		return 0.0

	var ratio := _gear_ratio(current_gear)
	if ratio <= 0.0:
		return 0.0

	var torque := _engine_torque_nm(engine_rpm)
	torque *= throttle_input
	torque *= acceleration / 25.0
	torque *= _shift_torque_factor()

	if boost and longitudinal_speed > 4.0:
		torque *= 1.0 + clampf(turbo_force / 100.0, 0.0, 0.25)

	return torque * ratio * final_drive * driveline_efficiency / maxf(0.05, wheel_radius)

func _engine_torque_nm(rpm: float) -> float:
	var normalized := clampf((rpm - idle_rpm) / maxf(1.0, redline_rpm - idle_rpm), 0.0, 1.0)
	# Broad naturally-aspirated style curve: builds through midrange, softens near redline.
	var curve := 0.64 + 0.42 * sin(pow(normalized, 0.82) * PI * 0.92)
	curve -= smoothstep(0.88, 1.0, normalized) * 0.18
	return max_engine_torque_nm * clampf(curve, 0.48, 1.02)

func _braking_force() -> float:
	if brake_input <= 0.01:
		return 0.0
	if longitudinal_speed <= 0.65:
		return 0.0
	return brake_input * _max_brake_force_newtons()

func _max_brake_force_newtons() -> float:
	return 14500.0 * clampf(brake_force / 38.0, 0.45, 1.65)

func _update_transmission(delta: float, allow_reverse: bool) -> void:
	_shift_kick = move_toward(_shift_kick, 0.0, delta * 5.0)
	_shift_lockout_timer = maxf(0.0, _shift_lockout_timer - delta)

	if is_shifting:
		_shift_timer = maxf(0.0, _shift_timer - delta)

		var shift_target_rpm := _rpm_for_speed(longitudinal_speed, pending_gear)
		var is_downshift := pending_gear > 0 and _shift_from_gear > pending_gear
		if is_downshift:
			var blip_shape := sin(clampf(1.0 - _shift_timer / maxf(0.001, _shift_total_time), 0.0, 1.0) * PI)
			shift_target_rpm += downshift_blip_rpm * blip_shape

		var shift_rpm_response := 14.0 if is_downshift else 9.0
		engine_rpm = lerpf(
			engine_rpm,
			clampf(shift_target_rpm, idle_rpm, redline_rpm + 150.0),
			1.0 - exp(-shift_rpm_response * delta)
		)

		var commit_at := _shift_total_time * 0.48
		if not _shift_committed and _shift_timer <= commit_at:
			current_gear = pending_gear
			_shift_committed = true

		if _shift_timer <= 0.0:
			is_shifting = false
			_shift_committed = true
			_shift_lockout_timer = shift_lockout_time
		return

	_update_engine_rpm(delta)

	if allow_reverse and brake_input > 0.08 and absf(longitudinal_speed) < 0.45:
		_stationary_reverse_hold += delta
	else:
		_stationary_reverse_hold = 0.0

	if allow_reverse and _stationary_reverse_hold >= 0.10 and current_gear != -1 and not is_shifting:
		_begin_shift(-1)
		return

	if throttle_input > 0.08 and longitudinal_speed >= -0.45 and current_gear <= 0 and not is_shifting:
		_begin_shift(1)
		return

	if current_gear <= 0 or is_shifting:
		return
	if _shift_lockout_timer > 0.0:
		return

	var throttle_shift_target := lerpf(upshift_rpm_light_throttle, upshift_rpm_full_throttle, throttle_input)
	if engine_rpm >= throttle_shift_target and current_gear < gear_ratios.size():
		_begin_shift(current_gear + 1)
		return

	if current_gear > 1 and engine_rpm <= downshift_rpm:
		var lower_rpm := _rpm_for_speed(longitudinal_speed, current_gear - 1)
		if lower_rpm < redline_rpm * 0.91:
			_begin_shift(current_gear - 1)

func _begin_shift(new_gear: int) -> void:
	if is_shifting or new_gear == current_gear:
		return
	_shift_from_gear = current_gear
	pending_gear = clampi(new_gear, -1, gear_ratios.size())

	if current_gear > 0 and pending_gear > current_gear:
		var index := clampi(current_gear - 1, 0, upshift_times.size() - 1)
		_shift_total_time = upshift_times[index] if not upshift_times.is_empty() else 0.20
	else:
		_shift_total_time = downshift_time

	if pending_gear == -1 or current_gear == -1:
		_shift_total_time = maxf(_shift_total_time, 0.22)

	_shift_timer = _shift_total_time
	_shift_committed = false
	is_shifting = true
	_shift_kick = 1.0

func _shift_torque_factor() -> float:
	if not is_shifting:
		return 1.0
	if _shift_total_time <= 0.001:
		return 1.0
	var progress := 1.0 - _shift_timer / _shift_total_time
	if progress < 0.42:
		return lerpf(1.0, 0.06, progress / 0.42)
	if progress < 0.68:
		return 0.06
	return lerpf(0.06, 1.0, (progress - 0.68) / 0.32)

func _update_engine_rpm(delta: float) -> void:
	var target := _rpm_for_speed(longitudinal_speed, current_gear)
	if absf(longitudinal_speed) < 1.0 and throttle_input > 0.02 and current_gear > 0:
		target = maxf(target, idle_rpm + throttle_input * 1200.0)

	var response := 13.0 if not is_shifting else 8.0
	engine_rpm = lerpf(engine_rpm, target, 1.0 - exp(-response * delta))
	engine_rpm = clampf(engine_rpm, idle_rpm, redline_rpm + 150.0)

func _rpm_for_speed(speed_mps: float, gear: int) -> float:
	if gear == 0:
		return idle_rpm
	var ratio := _gear_ratio(gear)
	if ratio <= 0.0:
		return idle_rpm
	var wheel_rpm := absf(speed_mps) / maxf(0.05, TAU * wheel_radius) * 60.0
	return maxf(idle_rpm, wheel_rpm * ratio * final_drive)

func _gear_ratio(gear: int) -> float:
	if gear == -1:
		return reverse_ratio
	if gear <= 0 or gear > gear_ratios.size():
		return 0.0
	return gear_ratios[gear - 1]

func gear_display() -> String:
	if current_gear < 0:
		return "R"
	if current_gear == 0:
		return "N"
	return str(current_gear)

func reset_transmission() -> void:
	current_gear = 1
	pending_gear = 1
	engine_rpm = idle_rpm
	is_shifting = false
	_shift_timer = 0.0
	_shift_total_time = 0.0
	_shift_lockout_timer = 0.0
	_shift_from_gear = 1
	_shift_committed = true
	_shift_kick = 0.0
	_stationary_reverse_hold = 0.0

func reset_dynamics() -> void:
	velocity = Vector3.ZERO
	longitudinal_speed = 0.0
	lateral_speed_body = 0.0
	yaw_rate = 0.0
	longitudinal_accel = 0.0
	lateral_accel = 0.0
	longitudinal_accel_g = 0.0
	lateral_accel_g = 0.0
	speed_kmh = 0.0
	signed_speed_kmh = 0.0
	slip_amount = 0.0
	drift_intensity = 0.0
	vehicle_slip_angle_deg = 0.0
	front_slip_angle_deg = 0.0
	rear_slip_angle_deg = 0.0
	front_tire_saturation = 0.0
	rear_tire_saturation = 0.0
	last_impact_speed_mps = 0.0
	last_impact_impulse_ns = 0.0
	impact_count = 0
	throttle_input = 0.0
	brake_input = 0.0
	steering_input = 0.0
	steering_angle_deg = 0.0
	_steering_reversal_target = 0.0
	_autopilot_stuck_time = 0.0
	_resolved_vehicle_collision_frames.clear()
	_contact_event_frames.clear()
	reset_transmission()

func _apply_world_motion(delta: float) -> void:
	var forward := -global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()

	rotate_y(-yaw_rate * delta)
	forward = -global_transform.basis.z.normalized()
	right = global_transform.basis.x.normalized()

	velocity = forward * longitudinal_speed + right * lateral_speed_body
	velocity.y = 0.0
	_pre_move_velocity = velocity
	move_and_slide()
	_apply_collision_response()

	# Recover body-frame state after collision response.
	forward = -global_transform.basis.z.normalized()
	right = global_transform.basis.x.normalized()
	longitudinal_speed = velocity.dot(forward)
	lateral_speed_body = velocity.dot(right)

	signed_speed_kmh = longitudinal_speed * 3.6
	speed_kmh = absf(signed_speed_kmh)

func _update_surface_height() -> void:
	var surface_height := TerrainBuilder3D.height_at(global_position.x, global_position.z)
	if track != null and track.contains_surface_corridor(global_position, 0.6):
		surface_height = track.get_drivable_surface_height(global_position)
	global_position.y = surface_height + ride_height
	rotation.x = 0.0
	rotation.z = 0.0

func _update_race_state(delta: float, pit_requested: bool, boost: bool) -> void:
	_update_resources(delta, throttle_input, boost)
	_update_pit_service(delta, pit_requested)
	_update_visuals(delta)
	_update_effects(delta)

func _update_resources(delta: float, throttle: float, boost: bool) -> void:
	if fuel_liters > 0.0 and throttle > 0.01:
		var rpm_load := clampf(engine_rpm / maxf(1.0, redline_rpm), 0.2, 1.1)
		var burn := fuel_burn_per_second * throttle * lerpf(0.75, 1.35, rpm_load)
		burn *= 1.35 if boost else 1.0
		fuel_liters = maxf(0.0, fuel_liters - burn * delta)

	if speed_kmh > 8.0:
		var wear_load := 0.10 + drift_intensity * 4.0 + (1.8 if is_offroad else 0.0)
		tire_health = maxf(
			0.0,
			tire_health - tire_wear_rate * wear_load * delta * maxf(0.35, speed_kmh / 80.0)
		)

func _update_pit_service(delta: float, pit_requested: bool) -> void:
	pit_servicing = in_pit_lane and pit_requested and speed_kmh < 12.0
	if not pit_servicing:
		return
	fuel_liters = minf(fuel_capacity_liters, fuel_liters + fuel_capacity_liters * pit_service_rate * delta)
	tire_health = minf(1.0, tire_health + pit_service_rate * delta)
	damage = maxf(0.0, damage - pit_service_rate * 0.45 * delta)

func _apply_collision_response() -> void:
	var count := get_slide_collision_count()
	if count <= 0:
		return

	for i in range(count):
		var collision := get_slide_collision(i)
		if collision == null:
			continue

		var normal: Vector3 = collision.get_normal()
		normal.y = 0.0
		if normal.length_squared() < 0.0001:
			continue
		normal = normal.normalized()

		var contact: Vector3 = collision.get_position()
		var collider := collision.get_collider()
		var collider_id := collision.get_collider_id()

		if collider is ArcadeCarController3D:
			_resolve_vehicle_impact(collider as ArcadeCarController3D, normal, contact)
		elif collider is RigidBody3D:
			_resolve_rigidbody_impact(collider as RigidBody3D, normal, contact, collider_id)
		else:
			_resolve_static_impact(normal, contact, collider_id)

func _world_planar_velocity() -> Vector3:
	var forward := -global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()
	var result := forward * longitudinal_speed + right * lateral_speed_body
	result.y = 0.0
	return result

func _set_world_planar_velocity(world_velocity: Vector3) -> void:
	var planar := world_velocity
	planar.y = 0.0
	velocity = planar

	var forward := -global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()
	longitudinal_speed = planar.dot(forward)
	lateral_speed_body = planar.dot(right)
	signed_speed_kmh = longitudinal_speed * 3.6
	speed_kmh = absf(signed_speed_kmh)

func _resolve_vehicle_impact(
	other: ArcadeCarController3D,
	normal: Vector3,
	contact: Vector3
) -> void:
	if other == null or not is_instance_valid(other):
		return

	var physics_frame := Engine.get_physics_frames()
	var other_id := other.get_instance_id()
	if int(_resolved_vehicle_collision_frames.get(other_id, -1)) == physics_frame:
		return

	_resolved_vehicle_collision_frames[other_id] = physics_frame
	other._resolved_vehicle_collision_frames[get_instance_id()] = physics_frame

	var separation := global_position - other.global_position
	separation.y = 0.0
	if separation.length_squared() > 0.0001 and separation.dot(normal) < 0.0:
		normal = -normal

	var velocity_a := _pre_move_velocity
	velocity_a.y = 0.0
	var velocity_b := other._world_planar_velocity()
	var relative_velocity := velocity_a - velocity_b
	var relative_normal_speed := relative_velocity.dot(normal)

	if relative_normal_speed >= -0.05:
		return

	var inv_mass_a := 1.0 / maxf(1.0, vehicle_mass)
	var inv_mass_b := 1.0 / maxf(1.0, other.vehicle_mass)
	var inv_mass_sum := inv_mass_a + inv_mass_b

	var previous_contact_frame := int(_contact_event_frames.get(other_id, -100000))
	var is_new_impact := physics_frame - previous_contact_frame > 10
	_contact_event_frames[other_id] = physics_frame
	other._contact_event_frames[get_instance_id()] = physics_frame

	var restitution := clampf(
		(car_restitution + other.car_restitution) * 0.5,
		0.0,
		0.42
	)
	if not is_new_impact:
		restitution *= 0.12
	var normal_impulse_magnitude := (
		-(1.0 + restitution) * relative_normal_speed / maxf(0.000001, inv_mass_sum)
	)
	var normal_impulse := normal * normal_impulse_magnitude

	var tangent_velocity := relative_velocity - normal * relative_normal_speed
	var tangent_impulse := Vector3.ZERO
	if tangent_velocity.length_squared() > 0.0001:
		var tangent := tangent_velocity.normalized()
		var tangent_impulse_magnitude := (
			-relative_velocity.dot(tangent) / maxf(0.000001, inv_mass_sum)
		)
		var friction_limit := normal_impulse_magnitude * minf(
			collision_friction,
			other.collision_friction
		)
		tangent_impulse_magnitude = clampf(
			tangent_impulse_magnitude,
			-friction_limit,
			friction_limit
		)
		tangent_impulse = tangent * tangent_impulse_magnitude

	var impulse := normal_impulse + tangent_impulse
	var new_velocity_a := velocity_a + impulse * inv_mass_a
	var new_velocity_b := velocity_b - impulse * inv_mass_b

	_set_world_planar_velocity(new_velocity_a)
	other._set_world_planar_velocity(new_velocity_b)
	_pre_move_velocity = new_velocity_a
	other._pre_move_velocity = new_velocity_b

	_apply_contact_yaw_impulse(contact, impulse)
	other._apply_contact_yaw_impulse(contact, -impulse)

	var closing_speed := absf(relative_normal_speed)
	if is_new_impact and closing_speed > 1.0:
		_register_impact(closing_speed, impulse.length())
		other._register_impact(closing_speed, impulse.length())

func _resolve_rigidbody_impact(
	other: RigidBody3D,
	normal: Vector3,
	contact: Vector3,
	collider_id: int
) -> void:
	if other == null or not is_instance_valid(other):
		return

	var velocity_a := _pre_move_velocity
	velocity_a.y = 0.0
	var velocity_b := other.linear_velocity
	velocity_b.y = 0.0

	var relative_velocity := velocity_a - velocity_b
	var relative_normal_speed := relative_velocity.dot(normal)
	if relative_normal_speed >= -0.05:
		return

	var physics_frame := Engine.get_physics_frames()
	var previous_contact_frame := int(_contact_event_frames.get(collider_id, -100000))
	var is_new_impact := physics_frame - previous_contact_frame > 10
	_contact_event_frames[collider_id] = physics_frame

	var inv_mass_a := 1.0 / maxf(1.0, vehicle_mass)
	var inv_mass_b := 1.0 / maxf(0.01, other.mass)
	var inv_mass_sum := inv_mass_a + inv_mass_b
	var restitution := clampf(car_restitution, 0.0, 0.36)
	if not is_new_impact:
		restitution *= 0.12

	var normal_impulse_magnitude := (
		-(1.0 + restitution) * relative_normal_speed / maxf(0.000001, inv_mass_sum)
	)
	var normal_impulse := normal * normal_impulse_magnitude

	var tangent_velocity := relative_velocity - normal * relative_normal_speed
	var tangent_impulse := Vector3.ZERO
	if tangent_velocity.length_squared() > 0.0001:
		var tangent := tangent_velocity.normalized()
		var tangent_impulse_magnitude := (
			-relative_velocity.dot(tangent) / maxf(0.000001, inv_mass_sum)
		)
		var friction_limit := normal_impulse_magnitude * collision_friction
		tangent_impulse_magnitude = clampf(
			tangent_impulse_magnitude,
			-friction_limit,
			friction_limit
		)
		tangent_impulse = tangent * tangent_impulse_magnitude

	var impulse := normal_impulse + tangent_impulse
	var new_velocity_a := velocity_a + impulse * inv_mass_a
	_set_world_planar_velocity(new_velocity_a)
	_pre_move_velocity = new_velocity_a

	var local_contact := contact - other.global_position
	other.apply_impulse(-impulse, local_contact)
	_apply_contact_yaw_impulse(contact, impulse)
	if is_new_impact and absf(relative_normal_speed) > 1.0:
		_register_impact(absf(relative_normal_speed), impulse.length())

func _resolve_static_impact(
	normal: Vector3,
	contact: Vector3,
	collider_id: int
) -> void:
	var incoming_velocity := _pre_move_velocity
	incoming_velocity.y = 0.0
	var normal_speed := incoming_velocity.dot(normal)

	if normal_speed >= -0.05:
		return

	var physics_frame := Engine.get_physics_frames()
	var previous_contact_frame := int(_contact_event_frames.get(collider_id, -100000))
	var is_new_impact := physics_frame - previous_contact_frame > 10
	_contact_event_frames[collider_id] = physics_frame

	var restitution := static_restitution if is_new_impact else static_restitution * 0.08
	var mass := maxf(1.0, vehicle_mass)
	var normal_impulse_magnitude := -(1.0 + restitution) * normal_speed * mass
	var normal_impulse := normal * normal_impulse_magnitude

	var tangent_velocity := incoming_velocity - normal * normal_speed
	var tangent_impulse := Vector3.ZERO
	if tangent_velocity.length_squared() > 0.0001:
		var tangent := tangent_velocity.normalized()
		var tangent_impulse_magnitude := -incoming_velocity.dot(tangent) * mass
		var friction_limit := normal_impulse_magnitude * collision_friction
		tangent_impulse_magnitude = clampf(
			tangent_impulse_magnitude,
			-friction_limit,
			friction_limit
		)
		tangent_impulse = tangent * tangent_impulse_magnitude

	var impulse := normal_impulse + tangent_impulse
	var outgoing_velocity := incoming_velocity + impulse / mass
	_set_world_planar_velocity(outgoing_velocity)
	_pre_move_velocity = outgoing_velocity
	_apply_contact_yaw_impulse(contact, impulse)
	if is_new_impact and absf(normal_speed) > 1.0:
		_register_impact(absf(normal_speed), impulse.length())

func _apply_contact_yaw_impulse(contact: Vector3, impulse: Vector3) -> void:
	var lever := contact - global_position
	lever.y = 0.0
	var planar_impulse := impulse
	planar_impulse.y = 0.0

	var torque_impulse_y := (
		lever.z * planar_impulse.x
		- lever.x * planar_impulse.z
	)
	yaw_rate += (
		-torque_impulse_y
		/ maxf(100.0, yaw_inertia)
		* collision_yaw_transfer
	)
	yaw_rate = clampf(yaw_rate, -1.8, 1.8)

func _register_impact(impact_speed: float, impulse_ns: float) -> void:
	last_impact_speed_mps = impact_speed
	last_impact_impulse_ns = impulse_ns
	impact_count += 1

	if impact_speed > impact_damage_threshold_mps:
		var excess_speed := impact_speed - impact_damage_threshold_mps
		var impulse_scale := clampf(
			impulse_ns / maxf(1.0, vehicle_mass * 8.0),
			0.35,
			1.65
		)
		var damage_delta := excess_speed * impact_damage_scale * impulse_scale
		damage = clampf(damage + minf(0.18, damage_delta), 0.0, 1.0)

	var feedback_strength := clampf(impact_speed / 24.0, 0.08, 1.0)
	if _fx_audio:
		_fx_audio.trigger_impact(feedback_strength)
	if impact_speed > 2.0:
		_spawn_sparks(clampf(feedback_strength, 0.18, 1.0))

func _update_visuals(delta: float) -> void:
	if _visual == null:
		return

	var bank_roll := deg_to_rad(track.get_bank_degrees_at_world(global_position)) if track != null else 0.0
	var body_roll := clampf(-lateral_accel_g * 0.045, -0.10, 0.10)
	var shift_pitch := -_shift_kick * 0.035
	var accel_pitch := clampf(-longitudinal_accel_g * 0.025, -0.055, 0.055)
	var target_roll := bank_roll + body_roll
	var target_pitch := accel_pitch + shift_pitch

	_visual.rotation.z = lerpf(_visual.rotation.z, target_roll, 1.0 - exp(-8.0 * delta))
	_visual.rotation.x = lerpf(_visual.rotation.x, target_pitch, 1.0 - exp(-9.5 * delta))
	if _visual_detail_rig:
		_visual_detail_rig.rotation.z = _visual.rotation.z
		_visual_detail_rig.rotation.x = _visual.rotation.x

	if _brake_light_material:
		var rain_visibility := _weather_wetness * 0.34
		var brake_glow := clampf(
			maxf(
				brake_input + (0.35 if is_shifting and longitudinal_accel_g < -0.05 else 0.0),
				rain_visibility
			),
			0.0,
			1.0
		)
		_brake_light_material.emission_energy_multiplier = lerpf(0.75, 5.2, brake_glow)
		_brake_light_material.albedo_color = Color("#8f101d").lerp(Color("#ff3042"), brake_glow)
	if _headlight_material:
		_headlight_material.emission_energy_multiplier = (
			lerpf(1.7, 2.6, clampf(speed_kmh / 160.0, 0.0, 1.0))
			+ _night_factor * 2.8
		)

	var steer_angle := deg_to_rad(steering_angle_deg)
	for i in range(_wheel_nodes.size()):
		var wheel := _wheel_nodes[i]
		var is_front := i < 2
		var wheel_steer := -steer_angle if is_front else 0.0
		wheel.rotation.y = lerpf(wheel.rotation.y, wheel_steer, 1.0 - exp(-14.0 * delta))
		wheel.rotation.x += longitudinal_speed * delta / maxf(0.05, wheel_radius)

		var suspension_load := absf(lateral_accel_g) * 0.014 + absf(longitudinal_accel_g) * 0.010
		var suspension_wave := sin(Time.get_ticks_msec() * 0.013 + float(i)) * 0.010
		wheel.position.y = 0.28 + suspension_wave - suspension_load * (1.0 if i % 2 == 0 else -1.0)

func _update_effects(delta: float) -> void:
	_skid_timer = maxf(0.0, _skid_timer - delta)
	_smoke_timer = maxf(0.0, _smoke_timer - delta)
	_dust_timer = maxf(0.0, _dust_timer - delta)

	var braking_skid := brake_input > 0.78 and speed_kmh > 55.0
	var should_skid := speed_kmh > 28.0 and (drift_intensity > 0.16 or braking_skid)
	var smoke_active := speed_kmh > 34.0 and (drift_intensity > 0.22 or braking_skid)
	var offroad_active := is_offroad and speed_kmh > 16.0
	var speed_fx := clampf(speed_kmh / 120.0, 0.0, 1.0)

	if _tire_smoke_gpu:
		_tire_smoke_gpu.emitting = smoke_active
		_tire_smoke_gpu.amount_ratio = clampf(
			maxf(drift_intensity, 0.48 if braking_skid else 0.0),
			0.18 if smoke_active else 0.0,
			1.0
		) if smoke_active else 0.0

	if _offroad_dust_gpu:
		_offroad_dust_gpu.emitting = offroad_active
		_offroad_dust_gpu.amount_ratio = clampf(0.28 + speed_fx * 0.72, 0.0, 1.0) if offroad_active else 0.0

	if _gravel_debris_gpu:
		var debris_active := offroad_active and speed_kmh > 34.0
		_gravel_debris_gpu.emitting = debris_active
		_gravel_debris_gpu.amount_ratio = clampf(0.20 + speed_fx * 0.70, 0.0, 0.90) if debris_active else 0.0

	if _wet_spray_gpu:
		var spray_active := _weather_wetness > 0.04 and speed_kmh > 18.0
		_wet_spray_gpu.emitting = spray_active
		_wet_spray_gpu.amount_ratio = (
			clampf(_weather_wetness * (0.18 + speed_fx * 0.82), 0.0, 1.0)
			if spray_active else 0.0
		)

	if _tire_smoke_gpu and _weather_wetness > 0.0:
		_tire_smoke_gpu.amount_ratio *= 1.0 - _weather_wetness * 0.72
	if _offroad_dust_gpu and _weather_wetness > 0.0:
		_offroad_dust_gpu.amount_ratio *= 1.0 - _weather_wetness * 0.82

	if should_skid and _skid_timer <= 0.0:
		_spawn_skid_marks(clampf(maxf(drift_intensity, 0.42 if braking_skid else 0.0), 0.18, 1.0))
		_skid_timer = lerpf(0.075, 0.035, drift_intensity)

	# CPU puffs remain only as occasional larger volume accents; the continuous
	# trail now comes from the GPU emitters above.
	if drift_intensity > 0.58 and speed_kmh > 42.0 and _smoke_timer <= 0.0:
		_spawn_smoke_puff(drift_intensity)
		_smoke_timer = lerpf(0.22, 0.12, drift_intensity)

	if offroad_active and speed_kmh > 42.0 and _dust_timer <= 0.0:
		_spawn_dust_puff(clampf(speed_kmh / 105.0, 0.28, 1.0))
		_dust_timer = lerpf(0.20, 0.10, speed_fx)

func _spawn_skid_marks(intensity: float) -> void:
	if _skid_root == null or not _skid_root.is_inside_tree():
		return

	for local_position in _rear_wheel_local_positions:
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var mark_length := clampf(absf(longitudinal_speed) * 0.045, 0.30, 1.15)
		mesh.size = Vector3(0.18, 0.014, mark_length)
		marker.mesh = mesh

		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.025, 0.025, 0.028, lerpf(0.32, 0.78, intensity))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 1.0
		marker.material_override = material

		var world_position := to_global(local_position)
		var mark_height := TerrainBuilder3D.height_at(world_position.x, world_position.z)
		if track != null and track.contains_surface_corridor(world_position, 0.2):
			mark_height = track.get_drivable_surface_height(world_position)

		_skid_root.add_child(marker)
		marker.global_position = Vector3(world_position.x, mark_height + 0.025, world_position.z)
		var planar_velocity := _world_planar_velocity()
		var mark_yaw := global_rotation.y
		if planar_velocity.length_squared() > 0.5:
			mark_yaw = atan2(-planar_velocity.x, -planar_velocity.z)
		marker.global_rotation = Vector3(0.0, mark_yaw, 0.0)
		_skid_marks.append(marker)

	while _skid_marks.size() > 260:
		var oldest: Node3D = _skid_marks.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

func _spawn_smoke_puff(intensity: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	for local_position in _rear_wheel_local_positions:
		var world_position := to_global(local_position + Vector3(0.0, 0.04, 0.12))
		var lateral_bias := clampf(lateral_speed_body * 0.035, -0.55, 0.55)
		world_position += global_transform.basis.x.normalized() * lateral_bias
		_spawn_transient_puff(
			scene,
			world_position,
			Color(0.82, 0.84, 0.85, 0.15 + intensity * 0.22),
			0.16 + intensity * 0.12,
			lerpf(0.72, 1.05, intensity),
			lerpf(2.0, 3.3, intensity),
			0.78
		)

func _spawn_dust_puff(intensity: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	for local_position in _rear_wheel_local_positions:
		var world_position := to_global(local_position + Vector3(0.0, 0.02, 0.15))
		var dust_color := Color(0.49, 0.40, 0.28, 0.18 + intensity * 0.24)
		_spawn_transient_puff(
			scene,
			world_position,
			dust_color,
			0.20 + intensity * 0.15,
			lerpf(0.38, 0.72, intensity),
			lerpf(2.3, 4.0, intensity),
			0.92
		)

func _spawn_transient_puff(
	scene: Node,
	world_position: Vector3,
	color: Color,
	base_radius: float,
	rise: float,
	end_scale: float,
	lifetime: float
) -> void:
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = base_radius
	sphere.height = base_radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 5
	puff.mesh = sphere

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	puff.material_override = material

	scene.add_child(puff)
	puff.global_position = world_position
	var phase := float(Time.get_ticks_msec() % 1000) * 0.001
	var side_drift := Vector3(
		sin(phase * 7.0) * 0.32,
		rise,
		cos(phase * 5.0) * 0.24
	)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "scale", Vector3.ONE * end_scale, lifetime)
	tween.tween_property(puff, "global_position", world_position + side_drift, lifetime)
	tween.tween_property(material, "albedo_color:a", 0.0, lifetime)
	tween.chain().tween_callback(puff.queue_free)

func _build_visual_details() -> void:
	_visual_detail_rig = Node3D.new()
	_visual_detail_rig.name = "VehicleDetailRig"
	add_child(_visual_detail_rig)

	_headlight_material = StandardMaterial3D.new()
	_headlight_material.albedo_color = Color("#fff4d8")
	_headlight_material.roughness = 0.12
	_headlight_material.metallic = 0.08
	_headlight_material.emission_enabled = true
	_headlight_material.emission = Color("#fff0bd")
	_headlight_material.emission_energy_multiplier = 1.8

	_brake_light_material = StandardMaterial3D.new()
	_brake_light_material.albedo_color = Color("#8f101d")
	_brake_light_material.roughness = 0.18
	_brake_light_material.metallic = 0.06
	_brake_light_material.emission_enabled = true
	_brake_light_material.emission = Color("#ff2438")
	_brake_light_material.emission_energy_multiplier = 0.75

	var carbon := RaceCarVisual3D.material(Color("#0d1116"), 0.42, 0.22)
	for side in [-1.0, 1.0]:
		_visual_detail_rig.add_child(
			RaceCarVisual3D.box(
				Vector3(0.42, 0.095, 0.055),
				Vector3(0.43 * side, 0.54, -1.49),
				_headlight_material
			)
		)
		var headlight := SpotLight3D.new()
		headlight.name = "HeadlightL" if side < 0.0 else "HeadlightR"
		headlight.position = Vector3(0.43 * side, 0.54, -1.54)
		headlight.rotation_degrees = Vector3(-5.0, 0.0, 0.0)
		headlight.light_color = Color("#fff0c8")
		headlight.light_energy = 0.0
		headlight.spot_range = 42.0
		headlight.spot_angle = 31.0
		headlight.spot_attenuation = 1.35
		headlight.shadow_enabled = false
		_visual_detail_rig.add_child(headlight)
		_headlight_lights.append(headlight)

		_visual_detail_rig.add_child(
			RaceCarVisual3D.box(
				Vector3(0.38, 0.085, 0.055),
				Vector3(0.45 * side, 0.52, 1.49),
				_brake_light_material
			)
		)

	# A compact center rain/brake light and a low diffuser edge make the rear
	# silhouette readable during braking and drift without replacing the GT mesh.
	_visual_detail_rig.add_child(
		RaceCarVisual3D.box(
			Vector3(0.18, 0.07, 0.045),
			Vector3(0.0, 0.45, 1.51),
			_brake_light_material
		)
	)
	_visual_detail_rig.add_child(
		RaceCarVisual3D.box(
			Vector3(1.44, 0.055, 0.12),
			Vector3(0.0, 0.19, 1.47),
			carbon
		)
	)

func set_environment_visuals(wetness: float, night_factor: float) -> void:
	_weather_wetness = clampf(wetness, 0.0, 1.0)
	_night_factor = clampf(night_factor, 0.0, 1.0)
	for headlight in _headlight_lights:
		if not is_instance_valid(headlight):
			continue
		headlight.visible = _night_factor > 0.04
		headlight.light_energy = lerpf(0.0, 11.5, _night_factor)
		headlight.spot_range = lerpf(30.0, 62.0, _night_factor)

func _build_effects() -> void:
	_skid_root = Node3D.new()
	_skid_root.name = "SkidMarks"
	call_deferred("_attach_skid_root")

	_tire_smoke_gpu = _create_gpu_billboard_emitter(
		"TireSmokeGPU",
		Color(0.78, 0.81, 0.83, 0.34),
		72,
		0.88,
		Vector3(0.70, 0.03, 0.12),
		Vector3(0.0, 0.88, 0.28),
		46.0,
		0.55,
		1.55,
		0.34,
		0.92,
		Vector3(0.0, 0.48, 0.0),
		0.28
	)
	_tire_smoke_gpu.position = Vector3(0.0, 0.18, 1.12)

	_offroad_dust_gpu = _create_gpu_billboard_emitter(
		"OffroadDustGPU",
		Color(0.48, 0.39, 0.26, 0.42),
		84,
		0.78,
		Vector3(0.74, 0.04, 0.14),
		Vector3(0.0, 0.60, 0.62),
		58.0,
		1.10,
		3.20,
		0.32,
		0.88,
		Vector3(0.0, -0.30, 0.0),
		0.30
	)
	_offroad_dust_gpu.position = Vector3(0.0, 0.12, 1.08)

	_gravel_debris_gpu = _create_gpu_debris_emitter()
	_gravel_debris_gpu.position = Vector3(0.0, 0.10, 1.05)

	_wet_spray_gpu = _create_gpu_billboard_emitter(
		"WetSprayGPU",
		Color(0.72, 0.82, 0.88, 0.20),
		154,
		0.68,
		Vector3(0.76, 0.030, 0.12),
		Vector3(0.0, 0.26, 0.97),
		34.0,
		1.0,
		4.6,
		0.12,
		0.40,
		Vector3(0.0, -0.22, 0.0),
		0.14
	)
	_wet_spray_gpu.position = Vector3(0.0, 0.10, 1.10)

func _create_gpu_billboard_emitter(
	name_value: String,
	base_color: Color,
	amount_value: int,
	lifetime_value: float,
	box_extents: Vector3,
	direction_value: Vector3,
	spread_value: float,
	velocity_min: float,
	velocity_max: float,
	scale_min_value: float,
	scale_max_value: float,
	gravity_value: Vector3,
	quad_size: float
) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = name_value
	particles.amount = amount_value
	particles.lifetime = lifetime_value
	particles.randomness = 0.42
	particles.emitting = false
	particles.local_coords = false
	particles.fixed_fps = 30
	particles.visibility_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 10.0, 16.0))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = box_extents
	process.direction = direction_value.normalized()
	process.spread = spread_value
	process.initial_velocity_min = velocity_min
	process.initial_velocity_max = velocity_max
	process.gravity = gravity_value
	process.scale_min = scale_min_value
	process.scale_max = scale_max_value

	var gradient := Gradient.new()
	gradient.set_color(0, Color(base_color.r, base_color.g, base_color.b, 0.0))
	gradient.add_point(0.10, base_color)
	gradient.add_point(0.56, Color(base_color.r, base_color.g, base_color.b, base_color.a * 0.68))
	gradient.set_color(1, Color(base_color.r, base_color.g, base_color.b, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	process.color_ramp = gradient_texture
	particles.process_material = process

	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = quad_size * 0.50
	puff_mesh.height = quad_size
	puff_mesh.radial_segments = 8
	puff_mesh.rings = 4
	var draw_material := StandardMaterial3D.new()
	draw_material.albedo_color = Color(1.0, 1.0, 1.0, clampf(base_color.a * 0.45, 0.08, 0.22))
	draw_material.vertex_color_use_as_albedo = true
	draw_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	puff_mesh.material = draw_material
	particles.draw_pass_1 = puff_mesh
	add_child(particles)
	return particles

func _create_gpu_debris_emitter() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "GravelDebrisGPU"
	particles.amount = 54
	particles.lifetime = 0.58
	particles.randomness = 0.55
	particles.emitting = false
	particles.local_coords = false
	particles.fixed_fps = 30
	particles.visibility_aabb = AABB(Vector3(-7.0, -2.0, -7.0), Vector3(14.0, 8.0, 14.0))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.72, 0.025, 0.12)
	process.direction = Vector3(0.0, 0.72, 0.68).normalized()
	process.spread = 72.0
	process.initial_velocity_min = 2.2
	process.initial_velocity_max = 5.8
	process.gravity = Vector3(0.0, -7.2, 0.0)
	process.scale_min = 0.55
	process.scale_max = 1.35
	process.color = Color("#9c8766")
	particles.process_material = process

	var stone_mesh := BoxMesh.new()
	stone_mesh.size = Vector3(0.035, 0.025, 0.055)
	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color("#9c8766")
	stone_material.roughness = 0.98
	stone_mesh.material = stone_material
	particles.draw_pass_1 = stone_mesh
	add_child(particles)
	return particles

func _attach_skid_root() -> void:
	if _skid_root == null or _skid_root.is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(_skid_root)
	else:
		get_tree().root.add_child(_skid_root)

func _build_audio() -> void:
	_engine_audio = EngineAudio3D.new()
	_engine_audio.name = "EngineAudio"
	_engine_audio.car = self
	add_child(_engine_audio)

	_fx_audio = VehicleFxAudio3D.new()
	_fx_audio.name = "TiresAndImpactAudio"
	_fx_audio.car = self
	add_child(_fx_audio)

func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.55, 0.72, 3.0)
	collision.shape = shape
	collision.position.y = 0.36
	add_child(collision)

func _autopilot_controls() -> Dictionary:
	if track == null or track.get_length() <= 0.0:
		return {"throttle": 0.0, "brake": 1.0, "steer": 0.0, "boost": false}

	var length := track.get_length()
	var ratio := track.get_progress_ratio(global_position)
	var speed_ratio := clampf(speed_kmh / maxf(1.0, top_speed * 3.6), 0.0, 1.0)
	var near_distance := lerpf(10.0, 22.0, speed_ratio)
	var far_distance := lerpf(30.0, 58.0, speed_ratio)

	var target := track.get_world_transform_at_ratio(ratio + near_distance / length)
	var local_target := to_local(target.origin)
	var steer := clampf(
		local_target.x / maxf(2.2, absf(local_target.z) * 0.82),
		-1.0,
		1.0
	)

	var current_track := track.get_world_transform_at_ratio(ratio)
	var far_target := track.get_world_transform_at_ratio(ratio + far_distance / length)
	var current_forward := -current_track.basis.z.normalized()
	var far_forward := -far_target.basis.z.normalized()
	var heading_change := acos(clampf(current_forward.dot(far_forward), -1.0, 1.0))
	var turn_severity := clampf(heading_change / deg_to_rad(78.0), 0.0, 1.0)

	var desired_speed := lerpf(autopilot_target_speed, 7.5, pow(turn_severity, 0.72))
	if drift_intensity > 0.20 or absf(vehicle_slip_angle_deg) > 10.0:
		desired_speed *= 0.82
	if is_offroad:
		desired_speed = minf(desired_speed, 8.0)

	var current_speed := speed_kmh / 3.6
	var throttle := 1.0 if current_speed < desired_speed - 0.55 else 0.0
	var brake := 1.0 if current_speed > desired_speed + 0.45 else 0.0

	if absf(vehicle_slip_angle_deg) > 14.0:
		throttle = 0.0
	if brake > 0.0:
		throttle = 0.0

	return {
		"throttle": throttle,
		"brake": brake,
		"steer": steer,
		"boost": false
	}

func _update_autopilot_recovery(delta: float) -> bool:
	if track == null:
		return false

	var stuck := speed_kmh < 7.0 and throttle_input > 0.6
	if stuck or damage > 0.62:
		_autopilot_stuck_time += delta
	else:
		_autopilot_stuck_time = maxf(0.0, _autopilot_stuck_time - delta * 1.5)

	if _autopilot_stuck_time < 1.2:
		return false

	var ratio := track.get_progress_ratio(global_position)
	var recovery := track.get_world_transform_at_ratio(ratio + 0.012)
	recovery.origin += recovery.basis.y.normalized() * ride_height
	global_transform = recovery

	reset_dynamics()
	is_offroad = false
	damage = 0.0

	_autopilot_stuck_time = 0.0
	autopilot_recoveries += 1
	return true

func telemetry() -> Dictionary:
	return {
		"speed_kmh": snappedf(speed_kmh, 0.1),
		"signed_speed_kmh": snappedf(signed_speed_kmh, 0.1),
		"gear": gear_display(),
		"gear_index": current_gear,
		"pending_gear": pending_gear,
		"engine_rpm": snappedf(engine_rpm, 1.0),
		"shifting": is_shifting,
		"shift_time_remaining": snappedf(_shift_timer, 0.001),
		"steering_angle_deg": snappedf(steering_angle_deg, 0.1),
		"slip": snappedf(slip_amount, 0.001),
		"drift_intensity": snappedf(drift_intensity, 0.001),
		"vehicle_slip_angle_deg": snappedf(vehicle_slip_angle_deg, 0.1),
		"front_slip_angle_deg": snappedf(front_slip_angle_deg, 0.1),
		"rear_slip_angle_deg": snappedf(rear_slip_angle_deg, 0.1),
		"front_tire_saturation": snappedf(front_tire_saturation, 0.01),
		"rear_tire_saturation": snappedf(rear_tire_saturation, 0.01),
		"last_impact_speed_mps": snappedf(last_impact_speed_mps, 0.01),
		"last_impact_impulse_ns": snappedf(last_impact_impulse_ns, 1.0),
		"impact_count": impact_count,
		"vehicle_mass": snappedf(vehicle_mass, 1.0),
		"lateral_accel_g": snappedf(lateral_accel_g, 0.01),
		"longitudinal_accel_g": snappedf(longitudinal_accel_g, 0.01),
		"yaw_rate_deg_s": snappedf(rad_to_deg(yaw_rate), 0.1),
		"fuel_liters": snappedf(fuel_liters, 0.01),
		"fuel_percent": snappedf((fuel_liters / maxf(0.001, fuel_capacity_liters)) * 100.0, 0.1),
		"tire_health": snappedf(tire_health, 0.001),
		"tire_percent": snappedf(tire_health * 100.0, 0.1),
		"damage": snappedf(damage, 0.001),
		"damage_percent": snappedf(damage * 100.0, 0.1),
		"offroad": is_offroad,
		"in_pit_lane": in_pit_lane,
		"pit_servicing": pit_servicing,
		"autopilot_recoveries": autopilot_recoveries,
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

func _spawn_sparks(strength: float) -> void:
	var world := get_tree().current_scene
	if world == null:
		return

	var particles := GPUParticles3D.new()
	particles.name = "ImpactSparksGPU"
	particles.amount = int(lerpf(14.0, 34.0, strength))
	particles.lifetime = lerpf(0.28, 0.48, strength)
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.randomness = 0.65
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-5.0, -2.0, -5.0), Vector3(10.0, 8.0, 10.0))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.15
	process.direction = Vector3(0.0, 0.72, 0.18).normalized()
	process.spread = 82.0
	process.initial_velocity_min = lerpf(2.8, 5.0, strength)
	process.initial_velocity_max = lerpf(5.5, 9.0, strength)
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.65
	process.scale_max = 1.35

	var gradient := Gradient.new()
	gradient.set_color(0, Color("#fff3a3"))
	gradient.add_point(0.34, Color("#ffb13b"))
	gradient.set_color(1, Color(1.0, 0.22, 0.02, 0.0))
	var color_texture := GradientTexture1D.new()
	color_texture.gradient = gradient
	process.color_ramp = color_texture
	particles.process_material = process

	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.026, 0.026, 0.16 + strength * 0.12)
	var spark_material := StandardMaterial3D.new()
	spark_material.albedo_color = Color.WHITE
	spark_material.vertex_color_use_as_albedo = true
	spark_material.emission_enabled = true
	spark_material.emission = Color("#ff9d32")
	spark_material.emission_energy_multiplier = 3.8
	spark_material.roughness = 0.24
	spark_mesh.material = spark_material
	particles.draw_pass_1 = spark_mesh

	world.add_child(particles)
	particles.global_position = global_position + Vector3.UP * 0.30
	particles.finished.connect(particles.queue_free)
	particles.emitting = true
	particles.restart()

func _build_visual() -> void:
	var built: Dictionary = RaceCarVisual3D.build(self, body_color, Color("#f6f4ed"))
	_visual = built.root as Node3D
	_wheel_nodes.clear()
	for wheel in built.wheels:
		_wheel_nodes.append(wheel as Node3D)
