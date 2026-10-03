extends SceneTree

func _init() -> void:
	var car := ArcadeCarController3D.new()
	var dt := 1.0 / 120.0

	# Throttle should feel progressive but reach full quickly.
	for _i in range(int(0.10 / dt)):
		car._update_driver_inputs(dt, 1.0, 0.0, 0.0)
	var throttle_100ms := car.throttle_input
	assert(throttle_100ms > 0.30 and throttle_100ms < 0.48)

	for _i in range(int(0.20 / dt)):
		car._update_driver_inputs(dt, 1.0, 0.0, 0.0)
	assert(car.throttle_input > 0.98)

	# Brake must come in faster than throttle.
	car.throttle_input = 0.0
	for _i in range(int(0.12 / dt)):
		car._update_driver_inputs(dt, 0.0, 1.0, 0.0)
	assert(car.brake_input > 0.95)

	# Steering builds progressively with keyboard.
	car.brake_input = 0.0
	for _i in range(int(0.10 / dt)):
		car._update_driver_inputs(dt, 0.0, 0.0, 1.0)
	var steer_100ms := car.steering_input
	assert(steer_100ms > 0.40 and steer_100ms < 0.60)

	for _i in range(int(0.13 / dt)):
		car._update_driver_inputs(dt, 0.0, 0.0, 1.0)
	assert(car.steering_input > 0.98)

	# Countersteer must be faster than initial steering.
	var counter_time := 0.0
	while car.steering_input > -0.98 and counter_time < 0.5:
		car._update_driver_inputs(dt, 0.0, 0.0, -1.0)
		counter_time += dt
	assert(counter_time < 0.27)

	# Return to center should be crisp but not instant.
	var center_time := 0.0
	while absf(car.steering_input) > 0.02 and center_time < 0.5:
		car._update_driver_inputs(dt, 0.0, 0.0, 0.0)
		center_time += dt
	assert(center_time > 0.10 and center_time < 0.20)

	print(
		"HGE_DRIVER_INPUT_OK throttle100ms=", snappedf(throttle_100ms, 0.01),
		" steer100ms=", snappedf(steer_100ms, 0.01),
		" counter=", snappedf(counter_time, 0.01),
		"s center=", snappedf(center_time, 0.01),
		"s"
	)
	car.free()
	quit(0)
