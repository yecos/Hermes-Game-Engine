extends Node3D

var track: TrackSpline
var player: ArcadeCarController3D
var camera: RaceCamera3D
var ai_racers: Array[AIRacer3D] = []
var race_manager: RaceManager3D
var runtime_bridge: HermesRuntimeBridge
var replay_manager: ReplayManager3D
var _animated_flags: Array[Node3D] = []

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

func _process(_delta: float) -> void:
	var clock := Time.get_ticks_msec() * 0.001
	for i in range(_animated_flags.size()):
		var flag := _animated_flags[i]
		if not is_instance_valid(flag):
			continue
		var phase := clock * (2.8 + float(i % 3) * 0.22) + float(i) * 1.37
		flag.rotation.z = sin(phase) * 0.12
		flag.rotation.y = sin(phase * 0.71) * 0.08

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
	sky_material.sky_top_color = Color("#337fc1")
	sky_material.sky_horizon_color = Color("#acd8ee")
	sky_material.ground_horizon_color = Color("#c8d6ad")
	sky_material.ground_bottom_color = Color("#526a42")
	sky_material.sun_angle_max = 22.0
	sky_material.sun_curve = 0.08
	sky.sky_material = sky_material

	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color("#d9e9f2")
	environment.ambient_light_energy = 0.62
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.98
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.09
	environment.adjustment_saturation = 1.05

	_set_env_if_exists(environment, "ssao_enabled", true)
	_set_env_if_exists(environment, "ssao_radius", 1.6)
	_set_env_if_exists(environment, "ssao_intensity", 2.0)
	_set_env_if_exists(environment, "ssil_enabled", true)
	_set_env_if_exists(environment, "glow_enabled", true)
	_set_env_if_exists(environment, "glow_intensity", 0.42)
	_set_env_if_exists(environment, "glow_bloom", 0.045)
	_set_env_if_exists(environment, "fog_enabled", true)
	_set_env_if_exists(environment, "fog_light_color", Color("#d7e9f5"))
	_set_env_if_exists(environment, "fog_density", 0.00055)
	_set_env_if_exists(environment, "fog_sky_affect", 0.04)

	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46.0, -34.0, 0.0)
	sun.light_color = Color("#fff2d3")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.shadow_blur = 1.15
	sun.shadow_bias = 0.055
	sun.shadow_normal_bias = 1.35
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
	var prop_offset := barrier_offset + extra_clearance
	if track.trackside_offset_conflicts(ratio, side, prop_offset):
		return null
	var target := frame.origin + frame.basis.x * side * prop_offset
	target.y = TerrainBuilder3D.height_at(target.x, target.z)

	var forward := -frame.basis.z.normalized()
	var yaw := atan2(forward.x, forward.z) + deg_to_rad(yaw_offset_degrees)

	root.add_child(asset)
	asset.global_position = target
	asset.rotation.y = yaw
	asset.scale = Vector3.ONE * scale_value
	asset.add_to_group("safe_trackside_prop")

	var lod_distance := 120.0
	if asset_name == "grandstand":
		lod_distance = 230.0
	elif asset_name == "light_mast":
		lod_distance = 210.0
	elif asset_name == "tree_lush":
		lod_distance = 155.0
	elif asset_name == "paddock_tent" or asset_name == "service_van":
		lod_distance = 145.0
	AssetLibrary3D.apply_lod(asset, lod_distance, 18.0)
	return asset

func _rebuild_safe_trackside() -> void:
	if track == null:
		return

	_animated_flags.clear()
	var old := get_node_or_null("SafeTrackside")
	if old:
		old.free()

	var root := Node3D.new()
	root.name = "SafeTrackside"
	add_child(root)

	_build_start_finish_gantry(root)
	_build_pro_pit_complex(root)
	_build_braking_markers(root)
	_build_sponsor_boards(root)
	_build_corner_safety_props(root)
	_build_sector_landmarks(root)
	_build_distant_landscape(root)
	_build_shrub_clusters(root)
	_build_crowd_clusters(root)

	# Spectator zones sit at distinct parts of the lap instead of following the
	# road continuously. This gives the circuit recognizable visual sectors.
	for data in [
		[0.025, -1.0, 10.0, 1.12, 180.0],
		[0.175, 1.0, 12.5, 0.96, 0.0],
		[0.285, 1.0, 11.5, 1.05, 0.0],
		[0.515, -1.0, 12.0, 1.00, 180.0],
		[0.680, -1.0, 13.0, 0.96, 180.0],
		[0.805, 1.0, 10.5, 1.08, 0.0]
	]:
		_spawn_safe_trackside_asset(
			root, "grandstand", float(data[0]), float(data[1]),
			float(data[2]), float(data[3]), float(data[4])
		)

	# A denser but still LOD-controlled forest makes the 2.8 km environment feel
	# occupied without placing geometry close to the racing surface.
	for i in range(64):
		var ratio := fposmod(0.008 + float(i) / 64.0, 1.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var extra := 10.0 + float((i * 7) % 7) * 2.3
		var scale_value := 0.76 + float(i % 5) * 0.11
		_spawn_safe_trackside_asset(root, "tree_lush", ratio, side, extra, scale_value, float(i * 37))
		if i % 3 == 0:
			_spawn_safe_trackside_asset(root, "tree_lush", fposmod(ratio + 0.0035, 1.0), side, extra + 7.0, scale_value * 1.12, float(i * 53 + 17))

	# Lighting landmarks around the major braking and spectator zones.
	for data in [
		[0.015, -1.0], [0.085, 1.0], [0.185, -1.0], [0.285, 1.0],
		[0.445, 1.0], [0.515, -1.0], [0.585, -1.0], [0.685, 1.0],
		[0.745, -1.0], [0.805, 1.0], [0.925, 1.0], [0.975, -1.0]
	]:
		var mast := _spawn_safe_trackside_asset(root, "light_mast", float(data[0]), float(data[1]), 6.0, 0.95, 0.0)
		if mast:
			var flood := OmniLight3D.new()
			flood.name = "FloodLight"
			flood.position = Vector3(0.0, 7.5, 0.0)
			flood.light_color = Color("#fff1d0")
			flood.light_energy = 1.65
			flood.omni_range = 28.0
			flood.shadow_enabled = false
			mast.add_child(flood)

	# Paddock support area behind the pit buildings.
	for data in [
		[0.962, 1.0, 18.0, 1.0, 90.0],
		[0.978, 1.0, 19.5, 0.95, 90.0],
		[0.994, 1.0, 18.0, 1.0, 90.0]
	]:
		_spawn_safe_trackside_asset(
			root, "paddock_tent", float(data[0]), float(data[1]),
			float(data[2]), float(data[3]), float(data[4])
		)
	_spawn_safe_trackside_asset(root, "service_van", 0.972, 1.0, 23.0, 0.92, 90.0)
	_spawn_safe_trackside_asset(root, "service_van", 0.988, 1.0, 24.5, 0.92, 90.0)

func _trackside_anchor(ratio: float, side: float, clearance: float, use_track_height: bool = false) -> Dictionary:
	if track == null:
		return {"valid": false}

	var wrapped := fposmod(ratio, 1.0)
	var frame := track.get_world_transform_at_ratio(wrapped)
	var offset := track.get_barrier_offset(side, wrapped) + clearance
	if track.trackside_offset_conflicts(wrapped, side, offset):
		return {"valid": false}

	var origin := frame.origin + frame.basis.x * side * offset
	origin.y = frame.origin.y if use_track_height else TerrainBuilder3D.height_at(origin.x, origin.z)
	var forward := -frame.basis.z.normalized()
	var yaw := atan2(forward.x, forward.z)
	return {
		"valid": true,
		"transform": Transform3D(Basis(Vector3.UP, yaw), origin)
	}

func _make_trackside_material(
	color: Color,
	roughness: float = 0.72,
	metallic: float = 0.0,
	emission: Color = Color(0, 0, 0, 1)
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission.r + emission.g + emission.b > 0.001:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.6
	return material

func _add_trackside_box(
	parent: Node3D,
	name_value: String,
	size: Vector3,
	position_value: Vector3,
	material: Material
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name_value
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position_value
	node.material_override = material
	parent.add_child(node)
	return node

func _create_dual_label(
	parent: Node3D,
	text_value: String,
	position_value: Vector3,
	font_size_value: int,
	pixel_size_value: float,
	color: Color = Color.WHITE,
	local_yaw_degrees: float = 0.0
) -> void:
	for flip in [false, true]:
		var label := Label3D.new()
		label.text = text_value
		label.font_size = font_size_value
		label.outline_size = maxi(2, int(float(font_size_value) * 0.10))
		label.modulate = color
		label.pixel_size = pixel_size_value
		label.position = position_value + Vector3(0.0, 0.0, 0.07 if not flip else -0.07)
		label.rotation.y = deg_to_rad(local_yaw_degrees) + (PI if flip else 0.0)
		parent.add_child(label)

func _build_start_finish_gantry(root: Node3D) -> void:
	var frame := track.get_world_transform_at_ratio(0.0)
	var forward := -frame.basis.z.normalized()
	var yaw := atan2(forward.x, forward.z)

	var gantry := Node3D.new()
	gantry.name = "StartFinishGantry"
	gantry.global_transform = Transform3D(Basis(Vector3.UP, yaw), frame.origin)
	root.add_child(gantry)

	var steel := _make_trackside_material(Color("#d6dadd"), 0.34, 0.62)
	var dark := _make_trackside_material(Color("#171b20"), 0.48, 0.22)
	var red := _make_trackside_material(Color("#e33b45"), 0.40, 0.12, Color("#5a070a"))
	var left_post_x := -(track.get_barrier_offset(-1.0, 0.0) + 0.9)
	var right_post_x := track.get_barrier_offset(1.0, 0.0) + 0.9
	var center_x := (left_post_x + right_post_x) * 0.5
	var span := right_post_x - left_post_x

	_add_trackside_box(gantry, "PostL", Vector3(0.30, 5.8, 0.30), Vector3(left_post_x, 2.9, 0.0), steel)
	_add_trackside_box(gantry, "PostR", Vector3(0.30, 5.8, 0.30), Vector3(right_post_x, 2.9, 0.0), steel)
	_add_trackside_box(gantry, "Header", Vector3(span + 0.30, 1.15, 0.45), Vector3(center_x, 5.35, 0.0), dark)
	_create_dual_label(gantry, "RED BLUE CIRCUIT", Vector3(0.0, 5.36, 0.0), 54, 0.018)

	for i in range(5):
		_add_trackside_box(
			gantry, "StartLight%d" % i, Vector3(0.34, 0.34, 0.18),
			Vector3(-0.82 + float(i) * 0.41, 4.58, -0.24), red
		)

func _build_pro_pit_complex(root: Node3D) -> void:
	var pit_root := Node3D.new()
	pit_root.name = "ProPitComplex"
	root.add_child(pit_root)

	var concrete := _make_trackside_material(Color("#b9bbb6"), 0.82, 0.02)
	var graphite := _make_trackside_material(Color("#20252b"), 0.58, 0.18)
	var accent := _make_trackside_material(Color("#d73c42"), 0.46, 0.10)
	var glass := _make_trackside_material(Color("#243b49"), 0.18, 0.10)

	for i in range(7):
		var ratio := fposmod(0.962 + float(i) * 0.0034, 1.0)
		var anchor := _trackside_anchor(ratio, 1.0, 6.8, true)
		if not bool(anchor.get("valid", false)):
			continue

		var garage := Node3D.new()
		garage.name = "Garage_%02d" % (i + 1)
		garage.global_transform = anchor.transform
		garage.add_to_group("safe_trackside_prop")
		pit_root.add_child(garage)

		_add_trackside_box(garage, "Shell", Vector3(7.2, 3.4, 7.6), Vector3(0.0, 1.7, 0.0), concrete)
		_add_trackside_box(garage, "Door", Vector3(0.14, 2.35, 5.2), Vector3(-3.66, 1.30, 0.0), graphite)
		_add_trackside_box(garage, "Fascia", Vector3(0.22, 0.62, 7.35), Vector3(-3.72, 3.00, 0.0), accent)
		_add_trackside_box(garage, "Window", Vector3(0.12, 0.72, 2.1), Vector3(-3.75, 2.25, 2.1), glass)
		_add_trackside_box(garage, "Roof", Vector3(7.55, 0.24, 7.95), Vector3(0.0, 3.52, 0.0), graphite)
		_create_dual_label(garage, "PIT %02d" % (i + 1), Vector3(-3.82, 3.00, 0.0), 36, 0.015, Color.WHITE, 90.0)

	# Race-control tower anchors the start/finish complex.
	var tower_anchor := _trackside_anchor(0.992, -1.0, 14.0, true)
	if bool(tower_anchor.get("valid", false)):
		var tower := Node3D.new()
		tower.name = "RaceControl"
		tower.global_transform = tower_anchor.transform
		tower.add_to_group("safe_trackside_prop")
		pit_root.add_child(tower)
		_add_trackside_box(tower, "Base", Vector3(6.5, 5.6, 7.0), Vector3(0.0, 2.8, 0.0), graphite)
		_add_trackside_box(tower, "GlassBand", Vector3(6.7, 1.25, 7.2), Vector3(0.0, 4.35, 0.0), glass)
		_add_trackside_box(tower, "Roof", Vector3(7.4, 0.35, 7.8), Vector3(0.0, 5.78, 0.0), accent)
		_create_dual_label(tower, "RACE CONTROL", Vector3(0.0, 4.42, -3.68), 34, 0.015)

func _create_brake_marker(
	root: Node3D,
	ratio: float,
	side: float,
	text_value: String
) -> void:
	var anchor := _trackside_anchor(ratio, side, 1.8, false)
	if not bool(anchor.get("valid", false)):
		return

	var marker := Node3D.new()
	marker.name = "Brake_%s" % text_value
	marker.global_transform = anchor.transform
	marker.add_to_group("safe_trackside_prop")
	root.add_child(marker)

	var white := _make_trackside_material(Color("#f3f1ea"), 0.70, 0.02)
	var dark := _make_trackside_material(Color("#24272a"), 0.74, 0.0)
	_add_trackside_box(marker, "Post", Vector3(0.12, 1.25, 0.12), Vector3(0.0, 0.62, 0.0), dark)
	_add_trackside_box(marker, "Board", Vector3(1.20, 1.35, 0.10), Vector3(0.0, 1.55, 0.0), white)
	_create_dual_label(marker, text_value, Vector3(0.0, 1.56, 0.0), 46, 0.020, Color("#16191b"))

func _build_braking_markers(root: Node3D) -> void:
	var brake_root := Node3D.new()
	brake_root.name = "BrakeMarkers"
	root.add_child(brake_root)
	var length := track.get_length()
	var corners := [0.088, 0.449, 0.575, 0.747, 0.807, 0.933]

	for corner_ratio in corners:
		var signed_curve := track._signed_curvature_at_distance(float(corner_ratio) * length)
		var outside_side := 1.0 if signed_curve >= 0.0 else -1.0
		for distance_m in [150.0, 100.0, 50.0]:
			var ratio := fposmod(float(corner_ratio) - distance_m / length, 1.0)
			_create_brake_marker(brake_root, ratio, outside_side, str(int(distance_m)))

func _create_sponsor_board(
	root: Node3D,
	ratio: float,
	side: float,
	text_value: String,
	color: Color
) -> void:
	var anchor := _trackside_anchor(ratio, side, 3.0, false)
	if not bool(anchor.get("valid", false)):
		return
	var board := Node3D.new()
	board.name = "Sponsor_" + text_value.replace(" ", "_")
	board.global_transform = anchor.transform
	board.add_to_group("safe_trackside_prop")
	root.add_child(board)

	var panel := _make_trackside_material(color, 0.54, 0.05)
	var steel := _make_trackside_material(Color("#bfc5c8"), 0.42, 0.55)
	_add_trackside_box(board, "Panel", Vector3(5.6, 1.55, 0.12), Vector3(0.0, 1.75, 0.0), panel)
	_add_trackside_box(board, "PostL", Vector3(0.10, 1.55, 0.10), Vector3(-2.3, 0.78, 0.0), steel)
	_add_trackside_box(board, "PostR", Vector3(0.10, 1.55, 0.10), Vector3(2.3, 0.78, 0.0), steel)
	_create_dual_label(board, text_value, Vector3(0.0, 1.76, 0.0), 42, 0.015)

func _build_sponsor_boards(root: Node3D) -> void:
	var board_root := Node3D.new()
	board_root.name = "SponsorBoards"
	root.add_child(board_root)
	var entries := [
		[0.165, -1.0, "HERMES RACING", Color("#20252d")],
		[0.205, -1.0, "RED BLUE", Color("#c92f3b")],
		[0.305, 1.0, "APEX", Color("#245fa9")],
		[0.355, 1.0, "MOTORSPORT", Color("#20252d")],
		[0.525, -1.0, "RACE LAB", Color("#c92f3b")],
		[0.615, 1.0, "HERMES", Color("#245fa9")],
		[0.695, 1.0, "RED BLUE", Color("#20252d")],
		[0.825, -1.0, "APEX", Color("#c92f3b")]
	]
	for data in entries:
		_create_sponsor_board(
			board_root, float(data[0]), float(data[1]), String(data[2]), data[3]
		)

func _build_corner_safety_props(root: Node3D) -> void:
	var safety_root := Node3D.new()
	safety_root.name = "CornerSafety"
	root.add_child(safety_root)
	var length := track.get_length()
	var corners := [0.088, 0.449, 0.575, 0.747, 0.807, 0.933]

	for corner_index in range(corners.size()):
		var ratio := float(corners[corner_index])
		var signed_curve := track._signed_curvature_at_distance(ratio * length)
		var outside_side := 1.0 if signed_curve >= 0.0 else -1.0
		for j in range(3):
			var stack_ratio := fposmod(ratio + (float(j) - 1.0) * 0.0022, 1.0)
			_spawn_safe_trackside_asset(
				safety_root, "tire_stack", stack_ratio, outside_side,
				1.4 + float(j) * 0.25, 0.92 + float(j) * 0.04, float(j * 18)
		)
		# Cones mark the service-side edge near the highest-speed braking zones.
		if corner_index in [0, 1, 5]:
			for j in range(4):
				_spawn_safe_trackside_asset(
					safety_root, "track_cone",
					fposmod(ratio - 0.010 + float(j) * 0.0017, 1.0),
					-outside_side, 1.2, 0.82, 0.0
				)


func _build_sector_landmarks(root: Node3D) -> void:
	var landmark_root := Node3D.new()
	landmark_root.name = "SectorLandmarks"
	root.add_child(landmark_root)

	_create_sector_bridge(landmark_root, 0.335, "SECTOR 2", Color("#245fa9"))
	_create_sector_bridge(landmark_root, 0.665, "SECTOR 3", Color("#c93440"))

	var marshal_data := [
		[0.075, -1.0], [0.205, 1.0], [0.365, -1.0], [0.525, 1.0],
		[0.705, -1.0], [0.865, 1.0]
	]
	for i in range(marshal_data.size()):
		var ratio := float(marshal_data[i][0])
		var side := float(marshal_data[i][1])
		var anchor := _trackside_anchor(ratio, side, 3.4, false)
		if not bool(anchor.get("valid", false)):
			continue

		var hut := Node3D.new()
		hut.name = "MarshalPost_%02d" % (i + 1)
		hut.global_transform = anchor.transform
		hut.add_to_group("safe_trackside_prop")
		landmark_root.add_child(hut)

		var shell := _make_trackside_material(Color("#e8e1cf"), 0.82, 0.01)
		var dark := _make_trackside_material(Color("#252b30"), 0.55, 0.12)
		var safety := _make_trackside_material(Color("#f05a32"), 0.58, 0.02)
		var glass := _make_trackside_material(Color("#24434f"), 0.24, 0.10)
		_add_trackside_box(hut, "Cabin", Vector3(2.8, 2.2, 2.4), Vector3(0.0, 1.10, 0.0), shell)
		_add_trackside_box(hut, "Window", Vector3(2.0, 0.78, 0.10), Vector3(0.0, 1.45, -1.24), glass)
		_add_trackside_box(hut, "Roof", Vector3(3.15, 0.22, 2.75), Vector3(0.0, 2.30, 0.0), safety)
		_add_trackside_box(hut, "Rail", Vector3(3.3, 0.12, 0.12), Vector3(0.0, 0.85, -1.70), dark)
		_create_dual_label(hut, "M%d" % (i + 1), Vector3(0.0, 2.31, -1.40), 30, 0.014)

		var flag_pivot := Node3D.new()
		flag_pivot.name = "MarshalFlag"
		flag_pivot.position = Vector3(1.65, 2.15, -0.95)
		hut.add_child(flag_pivot)
		_animated_flags.append(flag_pivot)
		_add_trackside_box(flag_pivot, "Pole", Vector3(0.06, 1.45, 0.06), Vector3(0.0, -0.20, 0.0), dark)
		var flag_color := Color("#f4d447") if i % 3 != 1 else Color("#e33d49")
		var flag_material := _make_trackside_material(flag_color, 0.76, 0.0)
		_add_trackside_box(flag_pivot, "Flag", Vector3(0.88, 0.48, 0.035), Vector3(0.46, 0.28, 0.0), flag_material)

func _create_sector_bridge(
	root: Node3D,
	ratio: float,
	label_text: String,
	accent_color: Color
) -> void:
	var frame := track.get_world_transform_at_ratio(ratio)
	var forward := -frame.basis.z.normalized()
	var yaw := atan2(forward.x, forward.z)
	var left_x := -(track.get_barrier_offset(-1.0, ratio) + 0.9)
	var right_x := track.get_barrier_offset(1.0, ratio) + 0.9
	var center_x := (left_x + right_x) * 0.5
	var span := right_x - left_x

	var bridge := Node3D.new()
	bridge.name = label_text.replace(" ", "_")
	bridge.global_transform = Transform3D(Basis(Vector3.UP, yaw), frame.origin)
	root.add_child(bridge)

	var steel := _make_trackside_material(Color("#c8cdd0"), 0.34, 0.58)
	var panel := _make_trackside_material(accent_color, 0.48, 0.06)
	_add_trackside_box(bridge, "PostL", Vector3(0.24, 5.0, 0.24), Vector3(left_x, 2.5, 0.0), steel)
	_add_trackside_box(bridge, "PostR", Vector3(0.24, 5.0, 0.24), Vector3(right_x, 2.5, 0.0), steel)
	_add_trackside_box(bridge, "Header", Vector3(span + 0.25, 1.05, 0.34), Vector3(center_x, 4.55, 0.0), panel)
	_create_dual_label(bridge, label_text, Vector3(center_x, 4.56, 0.0), 44, 0.016)

func _build_distant_landscape(root: Node3D) -> void:
	var landscape := Node3D.new()
	landscape.name = "DistantLandscape"
	root.add_child(landscape)

	var hill_material_a := _make_trackside_material(Color("#355b37"), 0.98, 0.0)
	var hill_material_b := _make_trackside_material(Color("#476a3f"), 0.98, 0.0)
	var hill_data := [
		[0.07, -1.0, 54.0, Vector3(38.0, 9.0, 25.0)],
		[0.19, 1.0, 62.0, Vector3(46.0, 11.0, 28.0)],
		[0.31, -1.0, 58.0, Vector3(34.0, 8.0, 23.0)],
		[0.44, 1.0, 65.0, Vector3(52.0, 12.0, 31.0)],
		[0.58, -1.0, 57.0, Vector3(40.0, 10.0, 25.0)],
		[0.72, 1.0, 63.0, Vector3(47.0, 11.0, 29.0)],
		[0.84, -1.0, 55.0, Vector3(36.0, 8.5, 24.0)],
		[0.94, 1.0, 60.0, Vector3(44.0, 10.5, 27.0)]
	]

	for i in range(hill_data.size()):
		var ratio := float(hill_data[i][0])
		var side := float(hill_data[i][1])
		var clearance := float(hill_data[i][2])
		var scale_value: Vector3 = hill_data[i][3]
		var anchor := _trackside_anchor(ratio, side, clearance, false)
		if not bool(anchor.get("valid", false)):
			continue
		var hill := MeshInstance3D.new()
		hill.name = "Hill_%02d" % (i + 1)
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 16
		sphere.rings = 8
		hill.mesh = sphere
		hill.global_transform = anchor.transform
		hill.scale = scale_value
		hill.position.y -= scale_value.y * 0.70
		hill.material_override = hill_material_a if i % 2 == 0 else hill_material_b
		landscape.add_child(hill)


func _build_shrub_clusters(root: Node3D) -> void:
	var transforms: Array[Transform3D] = []
	for i in range(96):
		var ratio := fposmod(0.004 + float(i) / 96.0, 1.0)
		var side := -1.0 if (i % 4) < 2 else 1.0
		var clearance := 5.8 + float((i * 5) % 6) * 1.65
		if i % 5 == 0:
			clearance += 6.0
		var anchor := _trackside_anchor(ratio, side, clearance, false)
		if not bool(anchor.get("valid", false)):
			continue
		var transform: Transform3D = anchor.transform
		var scale_value := 0.55 + float((i * 7) % 8) * 0.085
		transform.basis = transform.basis.scaled(Vector3(scale_value * 1.35, scale_value * 0.72, scale_value))
		transform.origin.y += scale_value * 0.62
		transforms.append(transform)

	if transforms.is_empty():
		return

	var shrub_mesh := SphereMesh.new()
	shrub_mesh.radius = 1.0
	shrub_mesh.height = 2.0
	shrub_mesh.radial_segments = 8
	shrub_mesh.rings = 4
	var shrub_material := _make_trackside_material(Color("#244c2c"), 0.98, 0.0)
	shrub_mesh.material = shrub_material

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = shrub_mesh
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])

	var instance := MultiMeshInstance3D.new()
	instance.name = "ShrubClusters"
	instance.multimesh = multi
	instance.visibility_range_end = 150.0
	instance.visibility_range_end_margin = 20.0
	root.add_child(instance)

func _build_crowd_clusters(root: Node3D) -> void:
	var crowd_root := Node3D.new()
	crowd_root.name = "CrowdClusters"
	root.add_child(crowd_root)

	var palette := [
		Color("#d94a52"),
		Color("#3277c9"),
		Color("#e7c84b")
	]
	var transforms_by_color: Array[Array] = [[], [], []]
	var stands := [
		[0.025, -1.0, 10.0],
		[0.175, 1.0, 12.5],
		[0.285, 1.0, 11.5],
		[0.515, -1.0, 12.0],
		[0.680, -1.0, 13.0],
		[0.805, 1.0, 10.5]
	]

	for stand_index in range(stands.size()):
		var ratio := float(stands[stand_index][0])
		var side := float(stands[stand_index][1])
		var clearance := float(stands[stand_index][2])
		var anchor := _trackside_anchor(ratio, side, clearance + 0.8, false)
		if not bool(anchor.get("valid", false)):
			continue
		var base: Transform3D = anchor.transform

		for row in range(4):
			for column in range(8):
				var local_x := -3.2 + float(column) * 0.92
				var local_z := -1.1 + float(row) * 0.72
				var local_y := 0.55 + float(row) * 0.38
				var person := base
				person.origin = base * Vector3(local_x, local_y, local_z)
				var height_scale := 0.88 + float((column + row * 3) % 4) * 0.045
				person.basis = base.basis.scaled(Vector3(0.92, height_scale, 0.92))
				var color_index := (stand_index + row + column) % 3
				transforms_by_color[color_index].append(person)

	for color_index in range(3):
		var transforms: Array = transforms_by_color[color_index]
		if transforms.is_empty():
			continue
		var person_mesh := BoxMesh.new()
		person_mesh.size = Vector3(0.27, 0.72, 0.23)
		var person_material := _make_trackside_material(palette[color_index], 0.84, 0.0)
		person_mesh.material = person_material

		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = person_mesh
		multi.instance_count = transforms.size()
		for i in range(transforms.size()):
			multi.set_instance_transform(i, transforms[i])

		var crowd := MultiMeshInstance3D.new()
		crowd.name = "CrowdColor%d" % (color_index + 1)
		crowd.multimesh = multi
		crowd.visibility_range_end = 190.0
		crowd.visibility_range_end_margin = 24.0
		crowd_root.add_child(crowd)

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
