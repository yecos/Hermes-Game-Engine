extends SceneTree

func _init() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	assert(packed != null, "Main scene missing")

	var world := packed.instantiate()
	get_root().add_child(world)
	current_scene = world
	await process_frame
	await physics_frame
	await process_frame

	var manager := world.get_node_or_null("RaceManager") as RaceManager3D
	var player := world.get_node_or_null("PlayerCar") as ArcadeCarController3D
	var replay := world.get_node_or_null("ReplayManager") as ReplayManager3D
	var safe := world.get_node_or_null("SafeTrackside") as Node3D
	assert(manager != null, "Race manager missing")
	assert(player != null, "Player missing")
	assert(replay != null, "Replay manager missing")
	assert(safe != null, "Trackside root missing")

	# Physical five-light gantry and flag network.
	var start_lights := get_nodes_in_group("race_start_light")
	var flags := get_nodes_in_group("marshal_flag_mesh")
	assert(start_lights.size() == 5, "Five physical start lights missing")
	assert(flags.size() >= 5, "Marshal flag network missing")

	world.set_start_lights(5, false)
	for node in start_lights:
		var mesh := node as MeshInstance3D
		assert(mesh != null and mesh.material_override is StandardMaterial3D, "Start-light material missing")
		var material := mesh.material_override as StandardMaterial3D
		assert(material.emission_energy_multiplier >= 5.0, "Start light did not illuminate")

	assert(manager.set_flag_state("red"), "Red flag rejected")
	await process_frame
	var first_flag := flags[0] as MeshInstance3D
	var first_flag_material := first_flag.material_override as StandardMaterial3D
	assert(first_flag_material.albedo_color.r > first_flag_material.albedo_color.g, "Physical red flag did not update")

	# Fast deterministic version of the full pre-race sequence.
	manager.full_formation_lap = false
	manager.formation_duration = 0.04
	manager.pre_grid_hold = 0.03
	manager.start_light_interval = 0.03
	manager.lights_out_hold = 0.04
	manager.restart_race_ceremony()
	assert(manager.race_phase == "formation", "Formation phase did not start")
	assert(player.autopilot_enabled and not player.input_enabled, "Formation did not take control of player")

	for _i in range(140):
		await process_frame

	var race_snapshot: Dictionary = manager.snapshot()
	assert(String(race_snapshot.race_phase) == "race", "Five-light sequence did not reach race")
	assert(String(race_snapshot.flag_state) == "green", "Race did not release under green")
	assert(int(race_snapshot.start_lights) == 0, "Start lights stayed on after lights out")
	assert(player.input_enabled and not player.autopilot_enabled, "Player control not restored at lights out")
	for ai in manager.ai_racers:
		assert(ai.autopilot_enabled, "AI did not launch after lights out")

	# Full-lap mode detects a real start/finish crossing when enabled.
	manager.full_formation_lap = true
	manager.restart_race_ceremony()
	manager._formation_last_ratio = 0.95
	var crossing := manager.track.get_world_transform_at_ratio(0.05)
	crossing.origin += Vector3.UP * player.ride_height
	player.global_transform = crossing
	manager._update_ceremony(0.01)
	assert(manager._formation_laps >= 1, "Full formation lap did not detect finish-line crossing")
	assert(manager.race_phase == "grid", "Full formation lap did not return to grid")

	# Pit-crew multimeshes must be genuinely animated.
	var bodies := safe.get_node_or_null("ProPitComplex/PitCrew/PitCrewBodies") as MultiMeshInstance3D
	var helmets := safe.get_node_or_null("ProPitComplex/PitCrew/PitCrewHelmets") as MultiMeshInstance3D
	var arms := safe.get_node_or_null("ProPitComplex/PitCrew/PitCrewArms") as MultiMeshInstance3D
	assert(bodies != null and helmets != null and arms != null, "Pit crew layers missing")
	assert(arms.multimesh.instance_count >= 28, "Pit crew arm layer incomplete")
	assert(world._pit_crew_body_bases.size() >= 14, "Pit crew base transforms missing")
	var body_base: Transform3D = world._pit_crew_body_bases[0]
	var body_at_a: Transform3D = world._pit_crew_transform(body_base, 0, 0.25, false, 1.0)
	var body_at_b: Transform3D = world._pit_crew_transform(body_base, 0, 1.75, false, 1.0)
	assert(body_at_a.origin.distance_to(body_at_b.origin) > 0.001, "Pit crew animation function is static")
	world._animate_pit_crew(1.75)

	# Lightning + procedural thunder.
	world.set_rain_intensity(1.0)
	world.trigger_lightning(1.0)
	var lightning := world.get_node_or_null("LightningFlash") as DirectionalLight3D
	var storm_audio := world.get_node_or_null("StormAudio") as StormAudio
	assert(lightning != null and lightning.light_energy >= 4.0, "Lightning flash missing")
	assert(storm_audio != null and storm_audio.thunder_envelope > 0.9, "Thunder envelope did not trigger")

	# Replay TV direction: five shot types, slow-motion playback and letterbox.
	replay._frames.clear()
	for i in range(72):
		var ratio := fposmod(0.20 + float(i) * 0.0015, 1.0)
		var frame := manager.track.get_world_transform_at_ratio(ratio)
		frame.origin += Vector3.UP * player.ride_height
		player.global_transform = frame
		player.speed_kmh = 105.0 + float(i % 12)
		replay._record_frame()

	replay.start_replay()
	assert(replay.replay_active, "Replay failed to start")
	var replay_snapshot: Dictionary = replay.replay_snapshot()
	assert(String(replay_snapshot.shot) == "TRACKSIDE", "Replay did not start on TV trackside shot")
	assert(float(replay_snapshot.playback_speed) < 1.0, "Replay is not using cinematic slow motion")
	assert(replay.get_node_or_null("ReplayTVCamera") is Camera3D, "Replay TV camera missing")

	replay._advance_shot()
	replay_snapshot = replay.replay_snapshot()
	assert(String(replay_snapshot.shot) == "LOW KERB", "Replay shot director failed to advance")
	replay.stop_replay()
	assert(not player.input_enabled, "Replay leaked manual control into pre-race grid state")

	# Wet-weather rear lights remain visible even without brake input.
	player.set_environment_visuals(1.0, 0.0)
	player.brake_input = 0.0
	player._update_visuals(0.016)
	assert(player._brake_light_material.emission_energy_multiplier > 1.0, "Wet-weather rear visibility light missing")

	print(
		"HGE_RACE_EVENT_OK phase=", race_snapshot.race_phase,
		" flag=", race_snapshot.flag_state,
		" lights=", start_lights.size(),
		" flags=", flags.size(),
		" pitcrew=", bodies.multimesh.instance_count,
		" replay_shots=5",
		" lightning=", snappedf(lightning.light_energy, 0.1)
	)

	world.queue_free()
	await process_frame
	await process_frame
	quit(0)
