extends SceneTree

func _init() -> void:
	var host := Node3D.new()
	get_root().add_child(host)
	var track := TrackSpline.new()
	host.add_child(track)
	await process_frame

	var before := track.track_snapshot()
	assert(int(before.point_count) == 12)
	assert(track.get_node_or_null("RoadMesh") != null)
	assert(track.get_node_or_null("Runoff") != null)
	assert(track.get_node_or_null("PitLane") != null)
	assert(track.get_node_or_null("Guardrails") != null)

	var ok_bank := track.set_bank(2, 12.0)
	assert(ok_bank)
	var after_bank := track.track_snapshot()
	assert(absf(float(after_bank.points[2].bank) - 12.0) < 0.01)

	var ok_point := track.set_control_point(3, 10.0, -42.0, 8.0)
	assert(ok_point)
	var after_point := track.track_snapshot()
	assert(absf(float(after_point.points[3].x) - 10.0) < 0.01)
	assert(absf(float(after_point.points[3].z) + 42.0) < 0.01)

	var replacement := [
		{"x": -40.0, "z": -10.0, "bank": 0.0},
		{"x": -22.0, "z": -38.0, "bank": 8.0},
		{"x": 12.0, "z": -42.0, "bank": 4.0},
		{"x": 43.0, "z": -20.0, "bank": -7.0},
		{"x": 46.0, "z": 18.0, "bank": -4.0},
		{"x": 20.0, "z": 40.0, "bank": 8.0},
		{"x": -18.0, "z": 42.0, "bank": 4.0},
		{"x": -46.0, "z": 18.0, "bank": -6.0}
	]
	assert(track.replace_control_points(replacement))
	var final := track.track_snapshot()
	assert(int(final.point_count) == 8)
	assert(float(final.length) > 150.0)

	print("HGE_TRACK_EDITOR_SMOKE_OK points=", final.point_count, " length=", final.length)
	host.free()
	quit(0)
