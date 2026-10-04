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
	var player := world.get_node_or_null("PlayerCar") as ArcadeCarController3D
	var rain := world.get_node_or_null("RainField") as GPUParticles3D
	var safe := world.get_node_or_null("SafeTrackside") as Node3D
	assert(track != null, "Track missing")
	assert(player != null, "Player missing")
	assert(rain != null, "Rain field missing")
	assert(safe != null, "Safe trackside missing")

	var original_accel := player.acceleration
	var original_grip := player.lateral_grip
	var original_top_speed := player.top_speed

	var initial: Dictionary = world.weather_snapshot()
	assert(String(initial.time_preset) == "golden_hour", "Golden-hour default missing")
	assert(float(initial.rain_intensity) == 0.0, "Unexpected rain at startup")

	assert(world.set_time_of_day("night"), "Night preset rejected")
	await process_frame
	var headlight_l := player.get_node_or_null("VehicleDetailRig/HeadlightL") as SpotLight3D
	var headlight_r := player.get_node_or_null("VehicleDetailRig/HeadlightR") as SpotLight3D
	assert(headlight_l != null and headlight_r != null, "Headlights missing")
	assert(headlight_l.light_energy >= 10.0 and headlight_r.light_energy >= 10.0, "Night headlights too weak")

	var flood := _find_named_light(safe, "FloodLight")
	assert(flood != null, "Circuit floodlight missing")
	assert(flood.light_energy >= 5.0, "Night floodlights not activated")
	assert(not world.set_time_of_day("invalid_preset"), "Invalid time preset accepted")

	world.set_rain_intensity(1.0)
	await process_frame
	var wet: Dictionary = world.weather_snapshot()
	assert(float(wet.surface_wetness) >= 0.99, "Track wetness did not follow rain")
	assert(rain.emitting and rain.amount_ratio >= 0.99, "Rain particles not active")

	var road := track.get_node_or_null("RoadMesh/Road") as MeshInstance3D
	assert(road != null and road.material_override is ShaderMaterial, "Road shader material missing")
	var wet_shader := road.material_override as ShaderMaterial
	assert(float(wet_shader.get_shader_parameter("wetness")) >= 0.99, "Road wetness shader parameter missing")

	var spray := player.get_node_or_null("WetSprayGPU") as GPUParticles3D
	assert(spray != null, "Wet spray emitter missing")
	player.longitudinal_speed = 30.0
	player.speed_kmh = 108.0
	player._update_effects(0.016)
	assert(spray.emitting, "Wet spray did not activate at speed")

	assert(is_equal_approx(player.acceleration, original_accel), "Weather changed acceleration physics")
	assert(is_equal_approx(player.lateral_grip, original_grip), "Weather changed grip physics")
	assert(is_equal_approx(player.top_speed, original_top_speed), "Weather changed top-speed physics")

	world.set_rain_intensity(0.0)
	assert(world.set_time_of_day("day"), "Day preset rejected")
	await process_frame
	assert(not rain.emitting, "Rain did not stop")
	assert(track.surface_wetness <= 0.001, "Track did not dry visually")
	assert(headlight_l.light_energy <= 0.01, "Day headlights stayed powered")

	print(
		"HGE_WEATHER_VISUAL_OK time=", world.current_time_preset,
		" rain=", world.rain_intensity,
		" flood=", snappedf(flood.light_energy, 0.01),
		" headlight=", snappedf(headlight_l.light_energy, 0.01),
		" wetness=", snappedf(track.surface_wetness, 0.01)
	)

	world.queue_free()
	await process_frame
	await process_frame
	quit(0)

func _find_named_light(node: Node, wanted: String) -> Light3D:
	if node is Light3D and String(node.name) == wanted:
		return node as Light3D
	for child in node.get_children():
		var found := _find_named_light(child, wanted)
		if found != null:
			return found
	return null
