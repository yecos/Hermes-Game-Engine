extends Node3D

var track: TrackSpline
var player: ArcadeCarController3D
var camera: RaceCamera3D
var ai_racers: Array[AIRacer3D] = []
var race_manager: RaceManager3D
var runtime_bridge: HermesRuntimeBridge
var replay_manager: ReplayManager3D

func _ready() -> void:
	_register_input_actions()
	_build_environment()
	_build_track()
	_rebuild_safe_trackside()
	_spawn_player()
	_spawn_ai()
	_spawn_camera()
	_spawn_race_manager()
	_spawn_replay_manager()
	_spawn_runtime_bridge()
	print("HGE_GODOT_RUNTIME_READY")

func _register_input_actions() -> void:
	_add_key("accelerate", KEY_W)
	_add_key("accelerate", KEY_UP)
	_add_key("brake_reverse", KEY_S)
	_add_key("brake_reverse", KEY_DOWN)
	_add_key("steer_left", KEY_A)
	_add_key("steer_left", KEY_LEFT)
	_add_key("steer_right", KEY_D)
	_add_key("steer_right", KEY_RIGHT)
	_add_key("boost", KEY_SPACE)
	_add_key("pit_service", KEY_E)
	_add_key("replay", KEY_R)

func _add_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return

	var key_event := InputEventKey.new()
	key_event.physical_keycode = keycode
	InputMap.action_add_event(action, key_event)

func _build_environment() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "PremiumEnvironment"

	var environment := Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#4b9fe8")
	sky_material.sky_horizon_color = Color("#b9e4ff")
	sky_material.ground_horizon_color = Color("#c8d6ad")
	sky_material.ground_bottom_color = Color("#526a42")
	sky_material.sun_angle_max = 22.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material

	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color("#d9e9f2")
	environment.ambient_light_energy = 0.72
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.08
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.03
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.08

	_set_env_if_exists(environment, "ssao_enabled", true)
	_set_env_if_exists(environment, "ssao_radius", 1.6)
	_set_env_if_exists(environment, "ssao_intensity", 2.0)
	_set_env_if_exists(environment, "ssil_enabled", true)
	_set_env_if_exists(environment, "glow_enabled", true)
	_set_env_if_exists(environment, "glow_intensity", 0.42)
	_set_env_if_exists(environment, "glow_bloom", 0.045)
	_set_env_if_exists(environment, "fog_enabled", true)
	_set_env_if_exists(environment, "fog_light_color", Color("#d7e9f5"))
	_set_env_if_exists(environment, "fog_density", 0.0012)
	_set_env_if_exists(environment, "fog_sky_affect", 0.08)

	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46.0, -34.0, 0.0)
	sun.light_color = Color("#fff2d3")
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	add_child(sun)

	var terrain := TerrainBuilder3D.new()
	terrain.name = "RollingTerrain"
	terrain.world_size = 760.0
	terrain.resolution = 160
	add_child(terrain)

func _set_env_if_exists(environment: Environment, property_name: String, value: Variant) -> void:
	for info in environment.get_property_list():
		if String(info.name) == property_name:
			environment.set(property_name, value)
			return

func _spawn_asset(
	asset_name: String,
	position_value: Vector3,
	scale_value: float = 1.0,
	rotation_degrees_y: float = 0.0
) -> Node3D:
	var asset := AssetLibrary3D.instantiate_asset(asset_name)
	if asset == null:
		return null

	asset.position = Vector3(
		position_value.x,
		TerrainBuilder3D.height_at(position_value.x, position_value.z) + position_value.y,
		position_value.z
	)
	asset.scale = Vector3.ONE * scale_value
	asset.rotation.y = deg_to_rad(rotation_degrees_y)
	var lod_distance := 115.0 if asset_name == "grandstand" or asset_name == "light_mast" else 85.0
	AssetLibrary3D.apply_lod(asset, lod_distance, 14.0)
	add_child(asset)
	return asset

func _spawn_safe_trackside_asset(
	root: Node3D,
	asset_name: String,
	ratio: float,
	side: float,
	extra_clearance: float,
	scale_value: float = 1.0,
	yaw_offset_degrees: float = 0.0
) -> Node3D:
	if track == null:
		return null

	var asset := AssetLibrary3D.instantiate_asset(asset_name)
	if asset == null:
		return null

	var frame := track.get_world_transform_at_ratio(ratio)
	var barrier_offset := track.get_barrier_offset(side, ratio)
	var target := frame.origin + frame.basis.x * side * (barrier_offset + extra_clearance)
	target.y = TerrainBuilder3D.height_at(target.x, target.z)

	var forward := -frame.basis.z.normalized()
	var yaw := atan2(forward.x, forward.z) + deg_to_rad(yaw_offset_degrees)

	root.add_child(asset)
	asset.global_position = target
	asset.rotation.y = yaw
	asset.scale = Vector3.ONE * scale_value

	var lod_distance := 120.0 if asset_name == "grandstand" or asset_name == "light_mast" else 88.0
	AssetLibrary3D.apply_lod(asset, lod_distance, 14.0)
	return asset

func _rebuild_safe_trackside() -> void:
	if track == null:
		return

	var old := get_node_or_null("SafeTrackside")
	if old:
		old.free()

	var root := Node3D.new()
	root.name = "SafeTrackside"
	add_child(root)

	# Only large objects well outside the physical barrier envelope.
	_spawn_safe_trackside_asset(root, "grandstand", 0.035, -1.0, 9.0, 1.08, 180.0)
	_spawn_safe_trackside_asset(root, "service_van", 0.965, -1.0, 7.0, 0.88, 90.0)
	_spawn_safe_trackside_asset(root, "paddock_tent", 0.12, 1.0, 8.0, 0.95, 90.0)
	_spawn_safe_trackside_asset(root, "paddock_tent", 0.66, -1.0, 8.5, 0.92, -90.0)

	for data in [
		[0.04, -1.0],
		[0.27, 1.0],
		[0.51, -1.0],
		[0.76, 1.0]
	]:
		_spawn_safe_trackside_asset(root, "light_mast", float(data[0]), float(data[1]), 5.0, 0.92, 0.0)

	# Trees are distributed relative to the current Curve3D, never by fixed world coordinates.
	for i in range(20):
		var ratio := fposmod(0.015 + float(i) / 20.0, 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var extra := 7.0 + float(i % 4) * 2.4
		_spawn_safe_trackside_asset(root, "tree_lush", ratio, side, extra, 0.82 + float(i % 3) * 0.12, float(i * 31))

	# Small safety props remain outside the barrier, never on the racing surface.
	_spawn_safe_trackside_asset(root, "tire_stack", 0.34, 1.0, 2.6, 0.9, 0.0)
	_spawn_safe_trackside_asset(root, "tire_stack", 0.79, -1.0, 2.6, 0.9, 0.0)

func _build_scenery() -> void:
	var tree_positions := [
		Vector3(-54, 0, -34), Vector3(-49, 0, -42), Vector3(-34, 0, -52),
		Vector3(18, 0, -52), Vector3(44, 0, -40), Vector3(55, 0, -18),
		Vector3(57, 0, 26), Vector3(43, 0, 45), Vector3(19, 0, 51),
		Vector3(-18, 0, 52), Vector3(-46, 0, 40), Vector3(-56, 0, 18),
		Vector3(-13, 0, -3), Vector3(3, 0, 5), Vector3(16, 0, -7),
		Vector3(-5, 0, 15), Vector3(9, 0, 17)
	]

	for i in range(tree_positions.size()):
		_create_tree(tree_positions[i], 0.9 + float(i % 4) * 0.12)

func _create_tree(position_value: Vector3, scale_value: float) -> void:
	var tree := AssetLibrary3D.instantiate_asset("tree_lush")
	if tree:
		tree.position = Vector3(
			position_value.x,
			TerrainBuilder3D.height_at(position_value.x, position_value.z),
			position_value.z
		)
		tree.scale = Vector3.ONE * scale_value
		tree.rotation.y = deg_to_rad(fmod(absf(position_value.x * 13.0 + position_value.z * 7.0), 360.0))
		add_child(tree)
		return

	var root := Node3D.new()
	root.position = Vector3(
		position_value.x,
		TerrainBuilder3D.height_at(position_value.x, position_value.z),
		position_value.z
	)
	root.scale = Vector3.ONE * scale_value
	add_child(root)

	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.32
	trunk_mesh.height = 2.4
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.2

	var trunk_material := StandardMaterial3D.new()
	trunk_material.albedo_color = Color("#765238")
	trunk.material_override = trunk_material
	root.add_child(trunk)

	var crown := MeshInstance3D.new()
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.35
	crown_mesh.height = 2.7
	crown.mesh = crown_mesh
	crown.position.y = 3.0

	var crown_material := StandardMaterial3D.new()
	crown_material.albedo_color = Color("#3f8d46")
	crown_material.roughness = 0.95
	crown.material_override = crown_material
	root.add_child(crown)

func _build_pit_complex() -> void:
	var pit_root := Node3D.new()
	pit_root.name = "PitComplex"
	add_child(pit_root)

	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color("#d8d8d2")
	concrete.roughness = 0.9

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#252a31")
	dark.roughness = 0.82

	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color("#e34b4b")
	accent.roughness = 0.6

	for i in range(6):
		var garage := MeshInstance3D.new()
		var garage_mesh := BoxMesh.new()
		garage_mesh.size = Vector3(4.2, 2.4, 5.0)
		garage.mesh = garage_mesh
		garage.position = Vector3(-30.0 + float(i) * 5.0, 1.2, 47.0)
		garage.material_override = concrete
		pit_root.add_child(garage)

		var opening := MeshInstance3D.new()
		var opening_mesh := BoxMesh.new()
		opening_mesh.size = Vector3(3.2, 1.7, 0.12)
		opening.mesh = opening_mesh
		opening.position = garage.position + Vector3(0.0, -0.18, -2.56)
		opening.material_override = dark
		pit_root.add_child(opening)

		var banner := MeshInstance3D.new()
		var banner_mesh := BoxMesh.new()
		banner_mesh.size = Vector3(3.5, 0.38, 0.16)
		banner.mesh = banner_mesh
		banner.position = garage.position + Vector3(0.0, 1.28, -2.62)
		banner.material_override = accent
		pit_root.add_child(banner)

	var stand := MeshInstance3D.new()
	var stand_mesh := BoxMesh.new()
	stand_mesh.size = Vector3(22.0, 3.8, 7.0)
	stand.mesh = stand_mesh
	stand.position = Vector3(23.0, 1.9, 48.0)
	stand.material_override = dark
	pit_root.add_child(stand)

	for row in range(3):
		for column in range(10):
			var seat := MeshInstance3D.new()
			var seat_mesh := BoxMesh.new()
			seat_mesh.size = Vector3(1.5, 0.45, 0.8)
			seat.mesh = seat_mesh
			seat.position = stand.position + Vector3(-8.0 + float(column) * 1.75, 0.2 + float(row) * 0.65, -2.2 + float(row) * 1.2)
			var seat_material := StandardMaterial3D.new()
			seat_material.albedo_color = Color("#2f7fff") if (column + row) % 2 == 0 else Color("#f0d44b")
			seat.material_override = seat_material
			pit_root.add_child(seat)

	_spawn_asset("grandstand", Vector3(19.0, 0.15, 54.0), 1.18, 180.0)
	_spawn_asset("service_van", Vector3(-7.0, 0.10, 51.5), 0.92, 92.0)
	_spawn_asset("light_mast", Vector3(-38.0, 0.0, 46.0), 1.0, 0.0)
	_spawn_asset("light_mast", Vector3(41.0, 0.0, 44.0), 1.0, 180.0)
	_spawn_asset("light_mast", Vector3(53.0, 0.0, -21.0), 0.92, -90.0)
	_spawn_asset("light_mast", Vector3(-54.0, 0.0, -24.0), 0.92, 90.0)

func _build_trackside_festival() -> void:
	var root := Node3D.new()
	root.name = "TracksideFestival"
	add_child(root)

	var banner_colors: Array[Color] = [
		Color("#2f7fff"),
		Color("#ef4052"),
		Color("#ffd33f"),
		Color("#35c977"),
		Color("#a858e8")
	]

	var banner_positions: Array[Vector3] = [
		Vector3(-48, 1.7, -18),
		Vector3(48, 1.7, -8),
		Vector3(34, 1.7, 37),
		Vector3(-38, 1.7, 38)
	]

	for i in range(banner_positions.size()):
		var pole_left := RaceCarVisual3D.box(Vector3(0.12, 3.2, 0.12), banner_positions[i] + Vector3(-1.9, 0.0, 0.0), RaceCarVisual3D.material(Color("#c9cdd2"), 0.4, 0.55))
		var pole_right := RaceCarVisual3D.box(Vector3(0.12, 3.2, 0.12), banner_positions[i] + Vector3(1.9, 0.0, 0.0), RaceCarVisual3D.material(Color("#c9cdd2"), 0.4, 0.55))
		var banner := RaceCarVisual3D.box(Vector3(3.9, 1.0, 0.12), banner_positions[i] + Vector3(0.0, 0.55, 0.0), RaceCarVisual3D.material(banner_colors[i], 0.5, 0.05))
		root.add_child(pole_left)
		root.add_child(pole_right)
		root.add_child(banner)

	var tent_positions: Array[Vector3] = [
		Vector3(-51, 0.0, 8),
		Vector3(50, 0.0, 17),
		Vector3(9, 0.0, 52)
	]
	for i in range(tent_positions.size()):
		var tent := Node3D.new()
		tent.position = tent_positions[i]
		root.add_child(tent)

		var base_color: Color = banner_colors[(i + 1) % banner_colors.size()]
		var roof := RaceCarVisual3D.box(Vector3(4.8, 0.35, 3.4), Vector3(0.0, 2.4, 0.0), RaceCarVisual3D.material(base_color, 0.65, 0.02), Vector3(0.0, 0.0, deg_to_rad(6.0)))
		tent.add_child(roof)
		for corner in [
			Vector3(-2.0, 1.2, -1.3),
			Vector3(2.0, 1.2, -1.3),
			Vector3(-2.0, 1.2, 1.3),
			Vector3(2.0, 1.2, 1.3)
		]:
			tent.add_child(RaceCarVisual3D.box(Vector3(0.10, 2.4, 0.10), corner, RaceCarVisual3D.material(Color("#e2e2df"), 0.5, 0.4)))

	var crowd_origins: Array[Vector3] = [
		Vector3(-24, 0.0, 48),
		Vector3(18, 0.0, 48),
		Vector3(47, 0.0, -24)
	]
	for group_index in range(crowd_origins.size()):
		for row in range(3):
			for column in range(12):
				var person := Node3D.new()
				person.position = crowd_origins[group_index] + Vector3(float(column) * 0.72, float(row) * 0.30, float(row) * 0.72)
				root.add_child(person)

				var body_color: Color = banner_colors[(group_index + row + column) % banner_colors.size()]
				var torso := RaceCarVisual3D.box(Vector3(0.28, 0.48, 0.22), Vector3(0.0, 0.56, 0.0), RaceCarVisual3D.material(body_color, 0.7, 0.0))
				person.add_child(torso)

				var head := MeshInstance3D.new()
				var head_mesh := SphereMesh.new()
				head_mesh.radius = 0.13
				head_mesh.height = 0.26
				head.mesh = head_mesh
				head.position = Vector3(0.0, 0.92, 0.0)
				head.material_override = RaceCarVisual3D.material(Color("#d8a77f"), 0.8, 0.0)
				person.add_child(head)

	for i in range(10):
		var stack := Node3D.new()
		stack.position = Vector3(-52.0 + float(i) * 2.1, 0.0, -32.0)
		root.add_child(stack)
		for tire_index in range(3):
			var tire := RaceCarVisual3D.cylinder(0.36, 0.24, Vector3(0.0, 0.18 + float(tire_index) * 0.23, 0.0), RaceCarVisual3D.material(Color("#16191e"), 0.9, 0.0))
			stack.add_child(tire)

	for i in range(12):
		var cone := Node3D.new()
		cone.position = Vector3(-12.0 + float(i) * 2.0, 0.0, 44.0)
		root.add_child(cone)
		var cone_body := CylinderMesh.new()
		cone_body.top_radius = 0.08
		cone_body.bottom_radius = 0.22
		cone_body.height = 0.55
		cone_body.radial_segments = 12
		var cone_mesh := MeshInstance3D.new()
		cone_mesh.mesh = cone_body
		cone_mesh.position.y = 0.28
		cone_mesh.material_override = RaceCarVisual3D.material(Color("#ff7a2f"), 0.7, 0.0)
		cone.add_child(cone_mesh)

	# Imported GLB props from the Blender asset pipeline.
	for tent_data in [
		[Vector3(-53.0, 0.0, 10.0), 1.0, 72.0],
		[Vector3(51.0, 0.0, 19.0), 0.95, -78.0],
		[Vector3(12.0, 0.0, 54.0), 0.90, 176.0]
	]:
		_spawn_asset("paddock_tent", tent_data[0], float(tent_data[1]), float(tent_data[2]))

	for stack_data in [
		[Vector3(-49.0, 0.0, -31.0), 1.0],
		[Vector3(-45.0, 0.0, -34.0), 1.0],
		[Vector3(49.0, 0.0, 31.0), 0.95],
		[Vector3(44.0, 0.0, 35.0), 0.95]
	]:
		_spawn_asset("tire_stack", stack_data[0], float(stack_data[1]), 0.0)

	for cone_index in range(10):
		_spawn_asset(
			"track_cone",
			Vector3(-14.0 + float(cone_index) * 2.1, 0.03, 46.5),
			0.85,
			0.0
		)

func _build_track() -> void:
	track = TrackSpline.new()
	track.name = "RedBlueCircuitPRO"
	track.auto_build_layout = "red_blue_pro"
	add_child(track)
	if not track.track_rebuilt.is_connected(_rebuild_safe_trackside):
		track.track_rebuilt.connect(_rebuild_safe_trackside)

func _spawn_player() -> void:
	player = ArcadeCarController3D.new()
	player.name = "PlayerCar"
	player.body_color = Color("#ef4052")
	player.track = track
	player.add_to_group("race_cars")
	add_child(player)

	var spawn := track.get_world_transform_at_ratio(0.018)
	spawn.origin += spawn.basis.x * -1.4 + Vector3.UP * 0.48
	player.global_transform = spawn

func _spawn_ai() -> void:
	var colors := [
		Color("#2f7fff"),
		Color("#ffd33f"),
		Color("#a858e8"),
		Color("#35c977"),
		Color("#f5f5f2")
	]

	for i in range(5):
		var ai := AIRacer3D.new()
		ai.name = "Rival%d" % (i + 1)
		ai.track = track
		ai.body_color = colors[i]
		ai.progress_ratio = fposmod(0.985 - float(i) * 0.012, 1.0)

		# Same physics for every car. Only the driver's decisions change.
		var styles := ["smooth", "balanced", "late_braker", "drifter", "aggressive"]
		var drift_biases := [0.04, 0.16, 0.24, 0.78, 0.48]
		var late_brake_biases := [0.00, 0.10, 0.55, 0.24, 0.48]
		var throttle_commitments := [0.42, 0.58, 0.68, 0.90, 0.78]
		var countersteer_skills := [0.92, 0.90, 0.84, 0.94, 0.86]
		var line_variations := [0.12, 0.22, 0.34, 0.46, 0.58]

		ai.speed_mps = 25.0 + float(i) * 0.80
		ai.driver_skill = clampf(0.82 + float(i) * 0.03, 0.0, 1.0)
		ai.aggression = clampf(0.38 + float(i) * 0.12, 0.0, 1.0)
		ai.braking_confidence = clampf(0.86 + float(i) * 0.025, 0.0, 1.0)
		ai.lane_offset = (float(i % 3) - 1.0) * 0.92

		ai.driving_style = styles[i]
		ai.drift_bias = drift_biases[i]
		ai.late_brake_bias = late_brake_biases[i]
		ai.throttle_commitment = throttle_commitments[i]
		ai.countersteer_skill = countersteer_skills[i]
		ai.line_variation = line_variations[i]
		ai.line_phase = float(i) * 1.37
		add_child(ai)

		var spawn := track.get_world_transform_at_ratio(ai.progress_ratio)
		spawn.origin += spawn.basis.x * ai.lane_offset + Vector3.UP * 0.48
		ai.global_transform = spawn
		ai.reset_dynamics()
		ai_racers.append(ai)

func _spawn_camera() -> void:
	camera = RaceCamera3D.new()
	camera.name = "RaceCamera"
	camera.target = player
	add_child(camera)

	var forward := -player.global_transform.basis.z.normalized()
	camera.global_position = player.global_position + Vector3.UP * camera.height - forward * camera.follow_distance
	camera.look_at(player.global_position + forward * camera.look_ahead, Vector3.UP)

func _spawn_race_manager() -> void:
	race_manager = RaceManager3D.new()
	race_manager.name = "RaceManager"
	race_manager.track = track
	race_manager.player = player
	race_manager.ai_racers = ai_racers
	race_manager.total_laps = 3
	add_child(race_manager)

func _spawn_replay_manager() -> void:
	replay_manager = ReplayManager3D.new()
	replay_manager.name = "ReplayManager"
	replay_manager.player = player
	replay_manager.track = track
	replay_manager.live_camera = camera
	add_child(replay_manager)

func _spawn_runtime_bridge() -> void:
	runtime_bridge = HermesRuntimeBridge.new()
	runtime_bridge.name = "HermesRuntimeBridge"
	runtime_bridge.player = player
	runtime_bridge.track = track
	runtime_bridge.ai_racers = ai_racers
	runtime_bridge.race_manager = race_manager
	runtime_bridge.replay_manager = replay_manager
	add_child(runtime_bridge)
