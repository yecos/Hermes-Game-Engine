extends SceneTree

func _init() -> void:
	var host := Node3D.new()
	get_root().add_child(host)

	var track := TrackSpline.new()
	track.name = "SafetyTrack"
	host.add_child(track)

	await process_frame
	await physics_frame
	await physics_frame

	var collision_body := track.get_node_or_null("Guardrails/GuardrailCollision") as StaticBody3D
	assert(collision_body != null, "Guardrail collision body missing")

	var expected_min := int(ceil(track.get_length() / 1.65)) * 2
	var shapes := collision_body.get_children()
	assert(shapes.size() >= expected_min, "Not enough guardrail collision segments")

	var left_count := 0
	var right_count := 0
	var pit_right_count := 0
	for child in shapes:
		if not (child is CollisionShape3D):
			continue
		var shape_node := child as CollisionShape3D
		var box := shape_node.shape as BoxShape3D
		assert(box != null, "Barrier collision must use BoxShape3D")
		assert(box.size.x <= 0.6, "Barrier thickness axis is wrong")
		assert(box.size.z >= 2.2, "Barrier length axis is wrong")
		var shape_name := String(shape_node.name)
		if shape_name.begins_with("Barrier_L"):
			left_count += 1
		elif shape_name.begins_with("Barrier_R"):
			right_count += 1
		elif shape_name.begins_with("Barrier_PIT_R"):
			pit_right_count += 1

	assert(left_count > 150, "Left barrier must cover the full lap")
	assert(right_count > 140, "Main right barrier must cover almost the full lap except pit gates")
	assert(pit_right_count > 10, "Pit lane requires its own outer right barrier")

	var space := get_root().get_world_3d().direct_space_state
	var misses: Array[String] = []

	for i in range(36):
		var ratio := (float(i) + 0.5) / 36.0
		var frame := track.get_world_transform_at_ratio(ratio)
		var up := frame.basis.y.normalized()
		var right := frame.basis.x.normalized()
		var start := frame.origin + up * 0.62

		for side_value in [-1.0, 1.0]:
			var side: float = float(side_value)
			var barrier_offset: float = track.get_barrier_offset(side, ratio)
			var finish: Vector3 = start + right * side * (barrier_offset + 2.0)
			var query := PhysicsRayQueryParameters3D.create(start, finish)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				misses.append("ratio=%.3f side=%s" % [ratio, "L" if side < 0.0 else "R"])

	assert(misses.is_empty(), "Barrier ray misses: " + ", ".join(misses))

	print(
		"HGE_TRACK_SAFETY_OK length=", snappedf(track.get_length(), 0.1),
		" left=", left_count,
		" right=", right_count,
		" pit_right=", pit_right_count,
		" rays=", 72
	)

	host.free()
	quit(0)
