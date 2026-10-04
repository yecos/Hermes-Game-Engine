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
	var track := world.get_node_or_null("RedBlueCircuitPRO") as TrackSpline
	assert(manager != null, "Race manager missing")
	assert(player != null, "Player missing")
	assert(track != null, "Track missing")
	assert(manager.ai_racers.size() == 5, "Expected five rivals")

	# Return everyone to the stored race grid and launch immediately.
	manager._restore_grid()
	manager._enter_race()

	var player_ratio := track.get_progress_ratio(player.global_position)
	assert(player_ratio < 0.10, "Player is expected just after start/finish")

	for ai in manager.ai_racers:
		var ai_ratio := track.get_progress_ratio(ai.global_position)
		assert(ai_ratio > 0.90, "Rival is expected just before start/finish")
		assert(ai.lap_count == -1, "Rival behind the line must begin on relative lap -1")
		assert(ai.total_progress() < player_ratio, "Rival behind player was scored ahead")

	manager._update_race_progress()
	assert(manager.current_position == 1, "Player starts physically first but ranking is not 1st")

	# A rival crosses start/finish: -1 -> 0, but remains behind player at 0.018.
	var rival := manager.ai_racers[0]
	rival.reset_race_progress(0.990, -1)
	# One stationary frame arms the crossing detector, matching the real grid hold.
	rival._process(0.016)
	var just_crossed := track.get_world_transform_at_ratio(0.005)
	just_crossed.origin += Vector3.UP * rival.ride_height
	rival.global_transform = just_crossed
	rival._process(0.016)
	assert(rival.lap_count == 0, "Rival crossing start line did not normalize lap -1 -> 0")
	manager._update_race_progress()
	assert(manager.current_position == 1, "Rival just behind after crossing incorrectly took 1st")

	# A real overtake beyond the player's 0.018 progress must change position.
	var ahead := track.get_world_transform_at_ratio(0.030)
	ahead.origin += Vector3.UP * rival.ride_height
	rival.global_transform = ahead
	rival._process(0.016)
	manager._update_race_progress()
	assert(manager.current_position == 2, "Real overtake was not reflected in ranking")

	print(
		"HGE_RACE_POSITION_OK player_ratio=", snappedf(player_ratio, 0.001),
		" initial=1st",
		" crossing_lap=", rival.lap_count,
		" overtake=2nd"
	)

	world.queue_free()
	await process_frame
	await process_frame
	quit(0)
