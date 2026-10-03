extends SceneTree

func _init() -> void:
	var world := Node3D.new()
	world.name = "AISharedPhysicsTest"
	get_root().add_child(world)
	current_scene = world

	var track := TrackSpline.new()
	track.name = "AITestTrack"
	world.add_child(track)
	await process_frame
	await physics_frame

	var racers: Array[AIRacer3D] = []
	var start_ratios := [0.10, 0.075, 0.05]
	var lane_offsets := [-0.9, 0.0, 0.9]

	for i in range(3):
		var ai := AIRacer3D.new()
		ai.name = "PhysicsAI%d" % (i + 1)
		ai.track = track
		ai.progress_ratio = start_ratios[i]
		ai.speed_mps = 24.5 + float(i) * 1.2
		ai.driver_skill = 0.82 + float(i) * 0.07
		ai.aggression = 0.46 + float(i) * 0.12
		ai.braking_confidence = 0.84 + float(i) * 0.06
		ai.lane_offset = lane_offsets[i]
		world.add_child(ai)

		var spawn := track.get_world_transform_at_ratio(ai.progress_ratio)
		spawn.origin += spawn.basis.x * ai.lane_offset + Vector3.UP * ai.ride_height
		ai.global_transform = spawn
		ai.reset_dynamics()
		racers.append(ai)

	var seen_gears: Array[Dictionary] = []
	var start_totals: Array[float] = []
	var offroad_samples := [0, 0, 0]
	var total_samples := [0, 0, 0]
	var max_drift := [0.0, 0.0, 0.0]
	var max_speed := [0.0, 0.0, 0.0]

	for ai in racers:
		assert(ai is ArcadeCarController3D, "AI must inherit the player's physics controller")
		assert(absf(ai.vehicle_mass - 1160.0) < 0.01)
		assert(absf(ai.final_drive - 4.10) < 0.001)
		assert(ai.gear_ratios.size() == 5)
		seen_gears.append({})
		start_totals.append(ai.total_progress())

	for frame in range(60 * 28):
		await physics_frame
		if frame % 6 != 0:
			continue

		for i in range(racers.size()):
			var ai := racers[i]
			total_samples[i] += 1
			if ai.is_offroad:
				offroad_samples[i] += 1
			max_drift[i] = maxf(max_drift[i], ai.drift_intensity)
			max_speed[i] = maxf(max_speed[i], ai.speed_kmh)
			seen_gears[i][ai.current_gear] = true

	for i in range(racers.size()):
		var ai := racers[i]
		var progress_gain := ai.total_progress() - start_totals[i]
		var offroad_ratio := float(offroad_samples[i]) / maxf(1.0, float(total_samples[i]))

		assert(progress_gain > 0.35, "AI did not physically progress around the circuit")
		assert(seen_gears[i].has(2), "AI never shifted into second gear")
		assert(max_speed[i] > 45.0, "AI never built racing speed")
		assert(offroad_ratio < 0.18, "AI spends too much time off track")
		assert(ai.autopilot_recoveries <= 3, "AI required too many teleport recoveries")

		print(
			"HGE_AI_PHYSICS racer=", i + 1,
			" progress=", snappedf(progress_gain, 0.01),
			" gears=", seen_gears[i].keys(),
			" vmax=", snappedf(max_speed[i], 0.1),
			" drift=", snappedf(max_drift[i], 0.01),
			" offroad=", snappedf(offroad_ratio, 0.001),
			" damage=", snappedf(ai.damage, 0.01),
			" recoveries=", ai.autopilot_recoveries
		)

	print("HGE_AI_SHARED_PHYSICS_OK")
	world.queue_free()
	await process_frame
	await process_frame
	quit(0)
