extends SceneTree

func _init() -> void:
	var world := Node3D.new()
	world.name = "ProTrackSpeedTest"
	get_root().add_child(world)
	current_scene = world

	var track := TrackSpline.new()
	track.name = "RedBlueCircuitPRO"
	track.auto_build_layout = "red_blue_pro"
	world.add_child(track)
	await process_frame
	await physics_frame

	var ai := AIRacer3D.new()
	ai.name = "QualifyingDriver"
	ai.track = track
	ai.progress_ratio = 0.145
	ai.speed_mps = 42.0
	ai.driver_skill = 0.98
	ai.aggression = 0.86
	ai.braking_confidence = 0.98
	ai.late_brake_bias = 0.24
	ai.drift_bias = 0.20
	ai.throttle_commitment = 0.84
	ai.countersteer_skill = 0.96
	world.add_child(ai)

	var spawn := track.get_world_transform_at_ratio(ai.progress_ratio)
	spawn.origin += Vector3.UP * ai.ride_height
	ai.global_transform = spawn
	ai.reset_dynamics()

	var max_speed := 0.0
	var max_gear := 1
	var offroad_samples := 0
	var samples := 0

	for frame in range(60 * 14):
		await physics_frame
		max_speed = maxf(max_speed, ai.speed_kmh)
		max_gear = maxi(max_gear, ai.current_gear)
		if frame % 6 == 0:
			samples += 1
			if ai.is_offroad:
				offroad_samples += 1

	var offroad_ratio := float(offroad_samples) / maxf(1.0, float(samples))
	assert(max_gear >= 5, "PRO main straight must allow fifth gear")
	assert(max_speed >= 130.0, "PRO main straight must allow 130+ km/h qualifying pace")
	assert(offroad_ratio < 0.08, "Qualifying line leaves the circuit too often")

	print(
		"HGE_PRO_SPEED_OK vmax=", snappedf(max_speed, 0.1),
		" gear=", max_gear,
		" offroad=", snappedf(offroad_ratio, 0.001),
		" recoveries=", ai.autopilot_recoveries
	)

	world.queue_free()
	await process_frame
	quit(0)
