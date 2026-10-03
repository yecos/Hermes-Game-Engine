extends SceneTree

const CarScript = preload("res://scripts/arcade_car.gd")

func _init() -> void:
	var dt: float = 1.0 / 120.0
	var car = CarScript.new()

	# 0-100 + shifts
	car.reset_dynamics()
	car.throttle_input = 1.0
	var t := 0.0
	var zero_to_hundred := -1.0
	var shifts: Array[float] = []
	var shift_elapsed := 0.0
	var was_shifting := false
	while t < 14.0:
		car._update_transmission(dt, true)
		car._step_vehicle_dynamics(dt, false)
		t += dt
		if car.is_shifting:
			shift_elapsed += dt
		elif was_shifting:
			shifts.append(shift_elapsed)
			shift_elapsed = 0.0
		was_shifting = car.is_shifting
		if zero_to_hundred < 0.0 and car.longitudinal_speed * 3.6 >= 100.0:
			zero_to_hundred = t

	# 100-0 braking
	car.reset_dynamics()
	car.current_gear = 3
	car.pending_gear = 3
	car.longitudinal_speed = 100.0 / 3.6
	car.engine_rpm = car._rpm_for_speed(car.longitudinal_speed, 3)
	car.brake_input = 1.0
	var brake_time := 0.0
	var brake_distance := 0.0
	while brake_time < 8.0 and car.longitudinal_speed > 0.4:
		var before: float = car.longitudinal_speed
		car._update_transmission(dt, false)
		car._step_vehicle_dynamics(dt, false)
		brake_distance += maxf(0.0, (before + car.longitudinal_speed) * 0.5) * dt
		brake_time += dt

	# Step steer stability at 80 km/h.
	car.reset_dynamics()
	car.current_gear = 3
	car.pending_gear = 3
	car.longitudinal_speed = 80.0 / 3.6
	car.engine_rpm = car._rpm_for_speed(car.longitudinal_speed, 3)
	car.throttle_input = 0.45
	car.steering_input = 0.75
	var max_step_slip := 0.0
	var max_step_yaw := 0.0
	for _i in range(int(2.0 / dt)):
		car._update_transmission(dt, false)
		car._step_vehicle_dynamics(dt, false)
		max_step_slip = maxf(max_step_slip, absf(car.vehicle_slip_angle_deg))
		max_step_yaw = maxf(max_step_yaw, absf(rad_to_deg(car.yaw_rate)))

	# Drift + recovery.
	car.reset_dynamics()
	car.current_gear = 3
	car.pending_gear = 3
	car.longitudinal_speed = 24.0
	car.engine_rpm = car._rpm_for_speed(24.0, 3)
	car.throttle_input = 0.82
	car.steering_input = 0.68
	var max_drift_slip := 0.0
	var max_drift_yaw := 0.0
	var drift_area := 0.0
	for _i in range(int(2.0 / dt)):
		car._update_transmission(dt, false)
		car._step_vehicle_dynamics(dt, false)
		max_drift_slip = maxf(max_drift_slip, absf(car.vehicle_slip_angle_deg))
		max_drift_yaw = maxf(max_drift_yaw, absf(rad_to_deg(car.yaw_rate)))
		drift_area += car.drift_intensity * dt

	var recovery_time := -1.0
	car.throttle_input = 0.0
	car.steering_input = -0.45 if car.yaw_rate > 0.0 else 0.45
	for i in range(int(3.0 / dt)):
		car._update_transmission(dt, false)
		car._step_vehicle_dynamics(dt, false)
		if recovery_time < 0.0 and absf(car.vehicle_slip_angle_deg) < 5.0:
			recovery_time = float(i) * dt
			break

	print(
		"HGE_V71_BASELINE ",
		"0-100=", snappedf(zero_to_hundred, 0.01),
		"s brake100-0=", snappedf(brake_time, 0.01),
		"s brake_dist=", snappedf(brake_distance, 0.1),
		"m step_slip=", snappedf(max_step_slip, 0.1),
		" step_yaw=", snappedf(max_step_yaw, 0.1),
		" drift_slip=", snappedf(max_drift_slip, 0.1),
		" drift_yaw=", snappedf(max_drift_yaw, 0.1),
		" drift_area=", snappedf(drift_area, 0.01),
		" recovery=", snappedf(recovery_time, 0.01),
		"s shifts=", shifts
	)

	car.free()
	quit(0)
