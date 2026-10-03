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

	var track := world.get_node_or_null("RedBlueCircuitPRO") as TrackSpline
	var safe := world.get_node_or_null("SafeTrackside") as Node3D
	assert(track != null, "PRO track missing")
	assert(safe != null, "SafeTrackside root missing")
	assert(safe.get_node_or_null("StartFinishGantry") != null, "Start/finish gantry missing")
	assert(safe.get_node_or_null("ProPitComplex") != null, "Pit complex missing")

	var gantry := safe.get_node("StartFinishGantry") as Node3D
	var post_l := gantry.get_node("PostL") as MeshInstance3D
	var post_r := gantry.get_node("PostR") as MeshInstance3D
	assert(post_l.position.x < -track.get_barrier_offset(-1.0, 0.0), "Left gantry post occupies the safety envelope")
	assert(post_r.position.x > track.get_barrier_offset(1.0, 0.0), "Right gantry post occupies the safety envelope")
	assert(safe.get_node_or_null("BrakeMarkers") != null, "Brake markers missing")
	assert(safe.get_node_or_null("SponsorBoards") != null, "Sponsor boards missing")
	assert(safe.get_node_or_null("CornerSafety") != null, "Corner safety props missing")
	assert(safe.get_node_or_null("SectorLandmarks") != null, "Sector landmarks missing")
	assert(safe.get_node_or_null("DistantLandscape") != null, "Distant landscape missing")
	assert(safe.get_node_or_null("ShrubClusters") != null, "Shrub clusters missing")
	assert(safe.get_node_or_null("CrowdClusters") != null, "Crowd clusters missing")
	assert(safe.get_node_or_null("CrowdClusters/CrowdHeads") != null, "Crowd head layer missing")
	assert(safe.get_node_or_null("ProPitComplex/PitCrew/PitCrewBodies") != null, "Pit crew bodies missing")
	assert(safe.get_node_or_null("ProPitComplex/PitCrew/PitCrewHelmets") != null, "Pit crew helmets missing")
	assert(track.get_node_or_null("Guardrails/CornerPanelsRed") != null, "Red corner impact panels missing")
	assert(track.get_node_or_null("Guardrails/CornerPanelsWhite") != null, "White corner impact panels missing")

	var pit := safe.get_node("ProPitComplex")
	var brakes := safe.get_node("BrakeMarkers")
	var sponsors := safe.get_node("SponsorBoards")
	var corner_safety := safe.get_node("CornerSafety")
	var landmarks := safe.get_node("SectorLandmarks")
	var landscape := safe.get_node("DistantLandscape")

	var garage_count := 0
	for child in pit.get_children():
		if String(child.name).begins_with("Garage_"):
			garage_count += 1

	assert(garage_count >= 5, "Too few pit garages generated")
	var garage_01 := pit.get_node_or_null("Garage_01")
	assert(garage_01 != null and garage_01.get_node_or_null("WorkLight") != null, "Pit work lighting missing")
	assert(garage_01.get_node_or_null("ToolCabinet") != null, "Pit tool cabinet missing")
	assert(brakes.get_child_count() >= 10, "Too few braking reference boards generated")
	assert(sponsors.get_child_count() >= 5, "Too few sponsor boards generated")
	assert(corner_safety.get_child_count() >= 8, "Too few corner safety props generated")
	assert(landmarks.get_child_count() >= 6, "Too few sector landmarks generated")
	assert(landscape.get_child_count() >= 5, "Too few background hills generated")

	var safe_props := get_nodes_in_group("safe_trackside_prop")
	assert(safe_props.size() >= 90, "Trackside environment is unexpectedly sparse")

	var flood_count := 0
	for node in safe.get_children():
		flood_count += _count_named(node, "FloodLight")
	assert(flood_count >= 8, "Functional floodlights missing")

	var flag_count := _count_named(safe, "MarshalFlag")
	assert(flag_count >= 5, "Animated marshal flags missing")
	var pine_count := _count_prefix(safe, "tree_pine") + _count_prefix(safe, "Tree_Pine")
	var lush_count := _count_prefix(safe, "tree_lush") + _count_prefix(safe, "Tree_Lush")
	assert(pine_count >= 6, "Pine vegetation layer missing")
	assert(lush_count >= 20, "Broadleaf vegetation layer missing")

	print(
		"HGE_TRACKSIDE_ENV_OK props=", safe_props.size(),
		" garages=", garage_count,
		" brake_boards=", brakes.get_child_count(),
		" sponsors=", sponsors.get_child_count(),
		" corner_safety=", corner_safety.get_child_count(),
		" landmarks=", landmarks.get_child_count(),
		" hills=", landscape.get_child_count(),
		" floodlights=", flood_count,
		" flags=", flag_count,
		" pines=", pine_count,
		" lush=", lush_count
	)

	world.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _count_named(node: Node, wanted: String) -> int:
	var count := 1 if String(node.name) == wanted else 0
	for child in node.get_children():
		count += _count_named(child, wanted)
	return count

func _count_prefix(node: Node, prefix: String) -> int:
	var count := 1 if String(node.name).begins_with(prefix) else 0
	for child in node.get_children():
		count += _count_prefix(child, prefix)
	return count
