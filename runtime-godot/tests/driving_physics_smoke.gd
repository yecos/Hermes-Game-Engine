extends SceneTree

func _init() -> void:
	var dt := 1.0 / 120.0
	var car := ArcadeCarController3D.new()

	# Acceleration / gearbox test.
	car.throttle_input = 1.0
	car.brake_input = 0.0
	car.steering_input = 0.0

	var seen_gears: Array[int] = [car.current_gear]
	var shift_durations: Array[float] = []
	var shift_elapsed := 0.0
	var previous_shifting := false
	var zero_to_hundred := -1.0
	var elapsed := 0.0
	var max_speed := 0.0

	for _i in range(int(14.0 / dt)):
		car._update_transmission(dt, true)
		car._step_vehicle_dynamics(dt, false)
		elapsed += dt

		if not seen_gears.has(car.current_gear):
			seen_gears.append(car.current_gear)

		if car.is_shifting:
			shift_elapsed += dt
		elif previous_shifting:
			shift_durations.append(shift_elapsed)
			shift_elapsed = 0.0
		previous_shifting = car.is_shifting

		var kmh := car.longitudinal_speed * 3.6
		max_speed = maxf(max_speed, kmh)
		if zero_to_hundred < 0.0 and kmh >= 100.0:
			zero_to_hundred = elapsed

	assert(seen_gears.size() >= 4, "Automatic transmission did not use enough gears")
	assert(zero_to_hundred > 3.5 and zero_to_hundred < 9.0, "0-100 outside intended arcade-sport window")
	assert(max_speed > 125.0, "Car did not build enough speed")
	assert(not shift_durations.is_empty(), "No measured shift durations")
	for duration in shift_durations:
		assert(duration >= 0.14 and duration <= 0.30, "Shift duration out of range")

	# Braking into reverse.
	car.throttle_input = 0.0
	car.brake_input = 1.0
	car.steering_input = 0.0
	var reverse_ok := false
	for _i in range(int(8.0 / dt)):
		car._update_transmission(dt, true)
		car._step_vehicle_dynamics(dt, false)
		if car.current_gear == -1 and car.longitudinal_speed < -1.5:
			reverse_ok = true
			break
	assert(reverse_ok, "Brake/reverse control never engaged reverse motion")

	# Return from R to forward.
	car.brake_input = 0.0
	car.throttle_input = 1.0
	var forward_again := false
	for _i in range(int(5.0 / dt)):
		car._update_transmission(dt, true)
		car._step_vehicle_dynamics(dt, false)
		if car.current_gear >= 1 and car.longitudinal_speed > 2.0:
			forward_again = true
			break
	assert(forward_again, "Throttle did not recover from R to a forward gear")

	# Controlled drift test: enter a medium/high-speed corner on throttle.
	car.reset_dynamics()
	car.current_gear = 3
	car.pending_gear = 3
	car.longitudinal_speed = 24.0
	car.engine_rpm = car._rpm_for_speed(car.longitudinal_speed, 3)
	car.throttle_input = 0.82
	car.brake_input = 0.0
	car.steering_input = 0.68

	var max_drift := 0.0
	var max_slip_angle := 0.0
	var max_yaw_deg := 0.0
	var settled_drift := 0.0

	for i in range(int(3.0 / dt)):
		car._update_transmission(dt, false)
		car._step_vehicle_dynamics(dt, false)
		max_drift = maxf(max_drift, car.drift_intensity)
		max_slip_angle = maxf(max_slip_angle, absf(car.vehicle_slip_angle_deg))
		max_yaw_deg = maxf(max_yaw_deg, absf(rad_to_deg(car.yaw_rate)))
		if i > int(1.0 / dt):
			settled_drift += car.drift_intensity * dt

	print(
		"HGE_DRIFT_DIAG max_drift=", snappedf(max_drift, 0.01),
		" max_slip=", snappedf(max_slip_angle, 0.1),
		" max_yaw=", snappedf(max_yaw_deg, 0.1),
		" settled=", snappedf(settled_drift, 0.2)
	)
	assert(max_drift > 0.22, "Physics never entered a meaningful drift state")
	assert(max_slip_angle > 4.0, "Vehicle slip angle stayed too low for drift")
	assert(max_slip_angle < 42.0, "Vehicle spun too aggressively")
	assert(max_yaw_deg < 150.0, "Yaw rate indicates an uncontrolled spin")
	assert(settled_drift > 0.12, "Drift was only an instantaneous spike")

	# Lift throttle and countersteer: car should recover rather than keep rotating forever.
	car.throttle_input = 0.0
	car.steering_input = -0.40 if car.yaw_rate > 0.0 else 0.40
	var starting_slip := absf(car.vehicle_slip_angle_deg)
	for _i in range(int(2.0 / dt)):
		car._update_transmission(dt, false)
		car._step_vehicle_dynamics(dt, false)

	var recovered_slip := absf(car.vehicle_slip_angle_deg)
	assert(recovered_slip < maxf(8.0, starting_slip), "Countersteer/lift did not recover the drift")

	print(
		"HGE_DRIVING_PHYSICS_OK 0-100=", snappedf(zero_to_hundred, 0.01),
		"s gears=", seen_gears,
		" shifts=", shift_durations,
		" vmax=", snappedf(max_speed, 0.1),
		" drift=", snappedf(max_drift, 0.01),
		" slip=", snappedf(max_slip_angle, 0.1),
		" yaw=", snappedf(max_yaw_deg, 0.1),
		" recovered=", snappedf(recovered_slip, 0.1)
	)

	car.free()
	quit(0)
