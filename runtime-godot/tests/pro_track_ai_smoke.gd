extends SceneTree

func _init() -> void:
	var world := Node3D.new()
	world.name = "ProTrackAIPhysicsTest"
	get_root().add_child(world)
	current_scene = world

	var track := TrackSpline.new()
	track.name = "RedBlueCircuitPRO"
	track.auto_build_layout = "red_blue_pro"
	world.add_child(track)
	await process_frame
	await physics_frame

	var styles := ["balanced", "drifter", "aggressive"]
	var drift_biases := [0.16, 0.78, 0.48]
	var racers: Array[AIRacer3D] = []
	var start_ratios := [0.020, 0.012, 0.004]

	for i in range(3):
		var ai := AIRacer3D.new()
		ai.name = "ProAI%d" % (i + 1)
		ai.track = track
		ai.progress_ratio = start_ratios[i]
		ai.speed_mps = 27.0 + float(i) * 1.2
		ai.driver_skill = 0.88 + float(i) * 0.03
		ai.aggression = 0.50 + float(i) * 0.15
		ai.braking_confidence = 0.90 + float(i) * 0.03
		ai.lane_offset = (float(i) - 1.0) * 0.70
		ai.driving_style = styles[i]
		ai.drift_bias = drift_biases[i]
		ai.line_variation = 0.20 + float(i) * 0.14
		ai.line_phase = float(i) * 1.37
		world.add_child(ai)

		var spawn := track.get_world_transform_at_ratio(ai.progress_ratio)
		spawn.origin += spawn.basis.x * ai.lane_offset + Vector3.UP * ai.ride_height
		ai.global_transform = spawn
		ai.reset_dynamics()
		racers.append(ai)

	var starts: Array[float] = []
	var max_speed := [0.0, 0.0, 0.0]
	var max_drift := [0.0, 0.0, 0.0]
	var offroad := [0, 0, 0]
	var samples := [0, 0, 0]
	var second_gear := [false, false, false]
	for ai in racers:
		starts.append(ai.total_progress())

	for frame in range(60 * 14):
		await physics_frame
		if frame % 6 != 0:
			continue
		for i in range(racers.size()):
			var ai := racers[i]
			samples[i] += 1
			max_speed[i] = maxf(max_speed[i], ai.speed_kmh)
			max_drift[i] = maxf(max_drift[i], ai.drift_intensity)
			if ai.current_gear >= 2:
				second_gear[i] = true
			if ai.is_offroad:
				offroad[i] += 1

	for i in range(racers.size()):
		var ai := racers[i]
		var progress := ai.total_progress() - starts[i]
		var offroad_ratio := float(offroad[i]) / maxf(1.0, float(samples[i]))
		assert(progress > 0.045, "PRO AI did not make meaningful physical progress")
		assert(max_speed[i] > 45.0, "PRO AI did not build racing speed")
		assert(second_gear[i], "PRO AI never reached second gear")
		assert(offroad_ratio < 0.22, "PRO AI spends too much time off-road")
		assert(ai.autopilot_recoveries <= 2, "PRO AI required too many recoveries")
		print(
			"HGE_PRO_AI racer=", i + 1,
			" style=", styles[i],
			" progress=", snappedf(progress, 0.001),
			" vmax=", snappedf(max_speed[i], 0.1),
			" drift=", snappedf(max_drift[i], 0.01),
			" offroad=", snappedf(offroad_ratio, 0.001),
			" recoveries=", ai.autopilot_recoveries
		)

	print("HGE_PRO_TRACK_AI_OK")
	world.queue_free()
	await process_frame
	await process_frame
	quit(0)
