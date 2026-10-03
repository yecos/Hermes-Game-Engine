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

	var camera := world.get_node_or_null("RaceCamera") as RaceCamera3D
	var player := world.get_node_or_null("PlayerCar") as ArcadeCarController3D
	var manager := world.get_node_or_null("RaceManager") as RaceManager3D
	assert(camera != null, "Race camera missing")
	assert(player != null, "Player car missing")
	assert(manager != null, "Race manager missing")

	assert(camera.base_fov >= 45.0, "Camera FOV regressed to a flat/telephoto feel")
	assert(camera.height <= 8.5, "Race camera is too high for the intended speed sensation")
	assert(camera.speed_fov_gain >= 8.0, "Dynamic speed FOV missing")

	var detail_rig := player.get_node_or_null("VehicleDetailRig")
	assert(detail_rig != null, "Vehicle visual detail rig missing")
	assert(detail_rig.get_child_count() >= 6, "Vehicle lights/aero details incomplete")
	assert(player.get_node_or_null("EngineAudio") != null, "Engine audio missing")
	assert(player.get_node_or_null("TiresAndImpactAudio") != null, "Vehicle FX audio missing")
	assert(player.get_node_or_null("TireSmokeGPU") is GPUParticles3D, "GPU tire smoke missing")
	assert(player.get_node_or_null("OffroadDustGPU") is GPUParticles3D, "GPU offroad dust missing")
	assert(player.get_node_or_null("GravelDebrisGPU") is GPUParticles3D, "GPU gravel debris missing")
	assert(world.get_node_or_null("PremiumEnvironment") != null, "Premium environment missing")
	assert(world.get_node_or_null("Sun") != null, "Cinematic sun missing")
	assert(world.get_node_or_null("SkyFill") != null, "Cool sky fill missing")

	var canvas: CanvasLayer = null
	for child in manager.get_children():
		if child is CanvasLayer:
			canvas = child as CanvasLayer
			break
	assert(canvas != null, "HUD canvas missing")
	assert(canvas.get_node_or_null("RaceInfoPanel") != null, "Race info HUD panel missing")
	assert(canvas.get_node_or_null("VehicleInfoPanel") != null, "Vehicle info HUD panel missing")
	assert(canvas.get_node_or_null("DriftPanel") != null, "Drift HUD panel missing")
	assert(canvas.get_node_or_null("ControlsPanel") != null, "Controls HUD panel missing")
	assert(canvas.get_node_or_null("RPMBar") != null, "RPM bar missing")

	await process_frame
	var before_children := world.get_child_count()
	player._spawn_smoke_puff(0.8)
	player._spawn_dust_puff(0.7)
	await process_frame
	assert(world.get_child_count() > before_children, "Tire smoke/dust feedback failed to spawn")

	player._spawn_skid_marks(0.75)
	await process_frame
	var skid_root := world.get_node_or_null("SkidMarks")
	assert(skid_root != null and skid_root.get_child_count() >= 2, "Skid marks failed to spawn")

	player._spawn_sparks(0.8)
	await process_frame
	assert(world.get_node_or_null("ImpactSparksGPU") is GPUParticles3D, "GPU impact sparks failed to spawn")

	print(
		"HGE_PRESENTATION_OK fov=", camera.base_fov,
		" height=", camera.height,
		" detail_nodes=", detail_rig.get_child_count(),
		" hud=4panels",
		" effects=smoke+dust+skid"
	)

	world.queue_free()
	await process_frame
	await process_frame
	quit(0)
