extends SceneTree

func _init() -> void:
	var host := Node3D.new()
	get_root().add_child(host)

	var track := TrackSpline.new()
	track.name = "RedBlueCircuitPROTest"
	track.auto_build_layout = "red_blue_pro"
	host.add_child(track)

	await process_frame
	await physics_frame
	await physics_frame

	assert(track.active_layout == "red_blue_pro", "PRO layout was not activated")
	assert(track.control_points.size() == 64, "PRO layout must keep 64 editable control points")
	assert(track.road_half_width * 2.0 == 11.0, "PRO road width must be 11 m")
	assert(track.get_length() > 2700.0 and track.get_length() < 3000.0, "Unexpected PRO lap length")

	var analysis := track.track_analysis()
	assert(bool(analysis.get("valid", false)), "PRO track validation failed: %s" % [analysis])
	assert(int(analysis.get("self_intersections", -1)) == 0, "PRO track must not self-intersect")

	for i in range(32):
		var ratio := float(i) / 32.0
		var frame := track.get_world_transform_at_ratio(ratio)
		var center := frame.origin
		var right := frame.basis.x.normalized()
		for side_value in [-1.0, 1.0]:
			var side := float(side_value)
			var runoff_point := center + right * side * (track.road_half_width + track.curb_width + track.runoff_width - 0.2)
			var shoulder_point := center + right * side * (track.road_half_width + track.curb_width + track.runoff_width + track.terrain_blend_width * 0.65)
			assert(track.contains_surface_corridor(runoff_point), "Runoff left the continuous surface corridor")
			assert(track.contains_surface_corridor(shoulder_point), "Grass shoulder left the continuous surface corridor")
			var runoff_height := track.get_drivable_surface_height(runoff_point)
			var shoulder_height := track.get_drivable_surface_height(shoulder_point)
			assert(is_finite(runoff_height) and is_finite(shoulder_height), "Surface height became invalid")
			var terrain_height := TerrainBuilder3D.height_at(runoff_point.x, runoff_point.z)
			assert(runoff_height > terrain_height + 0.03, "Terrain can clip through the runoff surface")

	var collision_body := track.get_node_or_null("Guardrails/GuardrailCollision") as StaticBody3D
	assert(collision_body != null, "PRO guardrail collision body missing")
	assert(collision_body.get_child_count() > 1500, "PRO circuit needs continuous physical barriers")

	print(
		"HGE_PRO_TRACK_OK layout=", track.active_layout,
		" length=", snappedf(track.get_length(), 0.1),
		" width=", track.road_half_width * 2.0,
		" points=", track.control_points.size(),
		" barriers=", collision_body.get_child_count()
	)

	host.free()
	quit(0)
