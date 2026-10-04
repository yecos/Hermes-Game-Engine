extends Node3D

var track: TrackSpline
var player: ArcadeCarController3D
var camera: RaceCamera3D
var ai_racers: Array[AIRacer3D] = []
var race_manager: RaceManager3D
var runtime_bridge: HermesRuntimeBridge
var replay_manager: ReplayManager3D
var _animated_flags: Array[Node3D] = []

var current_time_preset: String = "golden_hour"
var rain_intensity: float = 0.0
var _rain_target: float = 0.0
var _environment_resource: Environment
var _sky_material: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _sky_fill: DirectionalLight3D
var _rain_field: GPUParticles3D
const TIME_PRESETS := ["day", "golden_hour", "night"]

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
	_build_weather_system()
	_apply_visual_state()
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

	_update_weather_transition(_delta)
	if _rain_field and player and is_instance_valid(player):
		_rain_field.global_position = player.global_position + Vector3.UP * 6.5

	if Input.is_action_just_pressed("cycle_time_of_day"):
		cycle_time_of_day()
	if Input.is_action_just_pressed("toggle_rain"):
		set_rain_enabled(_rain_target < 0.5)

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
	_add_key("cycle_time_of_day", KEY_T)
	_add_key("toggle_rain", KEY_Y)

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
	sky_material.sky_top_color = Color("#245f92")
	sky_material.sky_horizon_color = Color("#b8d7df")
	sky_material.ground_horizon_color = Color("#b9c9a1")
	sky_material.ground_bottom_color = Color("#3d5237")
	sky_material.sun_angle_max = 18.0
	sky_material.sun_curve = 0.06
	sky.sky_material = sky_material

	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color("#c5d9e4")
	environment.ambient_light_energy = 0.50
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.03
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.13
	environment.adjustment_saturation = 1.04

	_set_env_if_exists(environment, "ssao_enabled", true)
	_set_env_if_exists(environment, "ssao_radius", 1.45)
	_set_env_if_exists(environment, "ssao_intensity", 2.20)
	_set_env_if_exists(environment, "ssil_enabled", true)
	_set_env_if_exists(environment, "ssr_enabled", true)
	_set_env_if_exists(environment, "ssr_max_steps", 96)
	_set_env_if_exists(environment, "ssr_fade_in", 0.12)
	_set_env_if_exists(environment, "ssr_fade_out", 2.4)
	_set_env_if_exists(environment, "glow_enabled", true)
	_set_env_if_exists(environment, "glow_intensity", 0.34)
	_set_env_if_exists(environment, "glow_bloom", 0.040)
	_set_env_if_exists(environment, "fog_enabled", true)
	_set_env_if_exists(environment, "fog_light_color", Color("#cbdde2"))
	_set_env_if_exists(environment, "fog_density", 0.00038)
	_set_env_if_exists(environment, "fog_sky_affect", 0.03)
	_set_env_if_exists(environment, "volumetric_fog_enabled", true)
	_set_env_if_exists(environment, "volumetric_fog_density", 0.0032)
	_set_env_if_exists(environment, "volumetric_fog_length", 125.0)
	_set_env_if_exists(environment, "volumetric_fog_ambient_inject", 0.22)
	_set_env_if_exists(environment, "volumetric_fog_sky_affect", 0.08)

	environment_node.environment = environment
	_environment_resource = environment
	_sky_material = sky_material
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, -42.0, 0.0)
	sun.light_color = Color("#ffdda9")
	sun.light_energy = 1.68
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 300.0
	sun.shadow_blur = 1.05
	sun.shadow_bias = 0.050
	sun.shadow_normal_bias = 1.20
	_sun = sun
	add_child(sun)

	# A low-energy cool fill keeps the shaded side of cars and pit buildings
	# readable while preserving a strong warm key-light direction.
	var sky_fill := DirectionalLight3D.new()
	sky_fill.name = "SkyFill"
	sky_fill.rotation_degrees = Vector3(-26.0, 136.0, 0.0)
	sky_fill.light_color = Color("#9fc6df")
	sky_fill.light_energy = 0.18
	sky_fill.shadow_enabled = false
	_sky_fill = sky_fill
	add_child(sky_fill)

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

func _build_weather_system() -> void:
	_rain_field = GPUParticles3D.new()
	_rain_field.name = "RainField"
	_rain_field.amount = 1150
	_rain_field.lifetime = 0.72
	_rain_field.randomness = 0.18
	_rain_field.emitting = false
	_rain_field.local_coords = false
	_rain_field.fixed_fps = 30
	_rain_field.visibility_aabb = AABB(Vector3(-30.0, -16.0, -34.0), Vector3(60.0, 34.0, 68.0))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(18.0, 7.5, 24.0)
	process.direction = Vector3(-0.13, -1.0, 0.08).normalized()
	process.spread = 3.5
	process.initial_velocity_min = 24.0
	process.initial_velocity_max = 34.0
	process.gravity = Vector3(0.0, -18.0, 0.0)

	var rain_gradient := Gradient.new()
	rain_gradient.set_color(0, Color(0.72, 0.84, 0.92, 0.0))
	rain_gradient.add_point(0.12, Color(0.72, 0.84, 0.92, 0.38))
	rain_gradient.add_point(0.80, Color(0.60, 0.76, 0.88, 0.30))
	rain_gradient.set_color(1, Color(0.60, 0.76, 0.88, 0.0))
	var rain_color := GradientTexture1D.new()
	rain_color.gradient = rain_gradient
	process.color_ramp = rain_color
	_rain_field.process_material = process

	var streak := BoxMesh.new()
	streak.size = Vector3(0.008, 0.38, 0.008)
	var streak_material := StandardMaterial3D.new()
	streak_material.albedo_color = Color(0.78, 0.88, 0.96, 0.30)
	streak_material.vertex_color_use_as_albedo = true
	streak_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	streak.material = streak_material
	_rain_field.draw_pass_1 = streak
	add_child(_rain_field)

func cycle_time_of_day() -> void:
	var index := TIME_PRESETS.find(current_time_preset)
	index = (index + 1) % TIME_PRESETS.size()
	set_time_of_day(String(TIME_PRESETS[index]))

func set_time_of_day(preset: String) -> bool:
	if not TIME_PRESETS.has(preset):
		return false
	current_time_preset = preset
	_apply_visual_state()
	print("HGE_TIME_PRESET ", current_time_preset)
	return true

func set_rain_enabled(enabled: bool) -> void:
	_rain_target = 1.0 if enabled else 0.0
	print("HGE_RAIN_TARGET ", _rain_target)

func set_rain_intensity(value: float, immediate: bool = true) -> void:
	_rain_target = clampf(value, 0.0, 1.0)
	if immediate:
		rain_intensity = _rain_target
		_apply_visual_state()

func _update_weather_transition(delta: float) -> void:
	if is_equal_approx(rain_intensity, _rain_target):
		return
	var previous := rain_intensity
	rain_intensity = move_toward(rain_intensity, _rain_target, delta * 0.24)
	if absf(rain_intensity - previous) > 0.0001:
		_apply_visual_state()

func _apply_visual_state() -> void:
	if _environment_resource == null or _sky_material == null or _sun == null or _sky_fill == null:
		return

	var sky_top := Color("#214d79")
	var sky_horizon := Color("#e1a06d")
	var ground_horizon := Color("#9e8a66")
	var ground_bottom := Color("#35452f")
	var ambient_color := Color("#c3b8aa")
	var ambient_energy := 0.36
	var exposure := 1.00
	var contrast := 1.16
	var saturation := 1.08
	var sun_rotation := Vector3(-18.0, -58.0, 0.0)
	var sun_color := Color("#ffb66d")
	var sun_energy := 2.05
	var fill_color := Color("#7fa4c8")
	var fill_energy := 0.14
	var night_factor := 0.0
	var base_fog_density := 0.00042
	var base_volumetric_density := 0.0035

	match current_time_preset:
		"day":
			sky_top = Color("#245f92")
			sky_horizon = Color("#b8d7df")
			ground_horizon = Color("#b9c9a1")
			ground_bottom = Color("#3d5237")
			ambient_color = Color("#c5d9e4")
			ambient_energy = 0.50
			exposure = 1.03
			contrast = 1.13
			saturation = 1.04
			sun_rotation = Vector3(-38.0, -42.0, 0.0)
			sun_color = Color("#ffdda9")
			sun_energy = 1.68
			fill_color = Color("#9fc6df")
			fill_energy = 0.18
			base_fog_density = 0.00038
			base_volumetric_density = 0.0032
		"night":
			sky_top = Color("#071124")
			sky_horizon = Color("#1b3150")
			ground_horizon = Color("#172431")
			ground_bottom = Color("#081014")
			ambient_color = Color("#607694")
			ambient_energy = 0.28
			exposure = 1.36
			contrast = 1.12
			saturation = 0.94
			sun_rotation = Vector3(-26.0, 34.0, 0.0)
			sun_color = Color("#b5cce3")
			sun_energy = 0.18
			fill_color = Color("#637fa8")
			fill_energy = 0.34
			night_factor = 1.0
			base_fog_density = 0.00055
			base_volumetric_density = 0.0042

	var rain := clampf(rain_intensity, 0.0, 1.0)
	var storm_top := Color("#101a26")
	var storm_horizon := Color("#536474")
	var storm_ground := Color("#303a36")
	sky_top = sky_top.lerp(storm_top, rain * 0.72)
	sky_horizon = sky_horizon.lerp(storm_horizon, rain * 0.74)
	ground_horizon = ground_horizon.lerp(storm_ground, rain * 0.66)
	ground_bottom = ground_bottom.lerp(Color("#18211f"), rain * 0.62)
	ambient_color = ambient_color.lerp(Color("#8798a8"), rain * 0.58)
	ambient_energy *= lerpf(1.0, 0.80, rain)
	sun_energy *= lerpf(1.0, 0.48, rain)
	fill_energy *= lerpf(1.0, 1.18, rain)
	saturation *= lerpf(1.0, 0.88, rain)

	_sky_material.sky_top_color = sky_top
	_sky_material.sky_horizon_color = sky_horizon
	_sky_material.ground_horizon_color = ground_horizon
	_sky_material.ground_bottom_color = ground_bottom
	_sky_material.sun_angle_max = 16.0 if current_time_preset == "golden_hour" else 18.0

	_environment_resource.ambient_light_color = ambient_color
	_environment_resource.ambient_light_energy = ambient_energy
	_environment_resource.tonemap_exposure = exposure
	_environment_resource.adjustment_contrast = contrast
	_environment_resource.adjustment_saturation = saturation

	_set_env_if_exists(_environment_resource, "fog_light_color", sky_horizon.lerp(Color("#aab8c2"), rain * 0.45))
	_set_env_if_exists(_environment_resource, "fog_density", lerpf(base_fog_density, 0.00125, rain))
	_set_env_if_exists(_environment_resource, "fog_sky_affect", lerpf(0.03, 0.16, rain))
	_set_env_if_exists(_environment_resource, "volumetric_fog_density", lerpf(base_volumetric_density, 0.0080, rain))
	_set_env_if_exists(_environment_resource, "volumetric_fog_ambient_inject", lerpf(0.22, 0.38, rain))
	_set_env_if_exists(_environment_resource, "volumetric_fog_sky_affect", lerpf(0.08, 0.24, rain))

	_sun.rotation_degrees = sun_rotation
	_sun.light_color = sun_color
	_sun.light_energy = sun_energy
	_sky_fill.light_color = fill_color
	_sky_fill.light_energy = fill_energy

	if track:
		track.set_surface_wetness(rain)

	if _rain_field:
		_rain_field.emitting = rain > 0.015
		_rain_field.amount_ratio = rain

	for node in get_tree().get_nodes_in_group("race_cars"):
		if node.has_method("set_environment_visuals"):
			node.call("set_environment_visuals", rain, night_factor)

	var circuit_light_factor := maxf(night_factor, rain * 0.34)
	_update_environment_lights(self, circuit_light_factor)

func _update_environment_lights(node: Node, factor: float) -> void:
	for child in node.get_children():
		if child is Light3D:
			var light := child as Light3D
			if String(light.name) == "FloodLight":
				light.light_energy = lerpf(0.03, 5.80, factor)
				if light is OmniLight3D:
					(light as OmniLight3D).omni_range = lerpf(28.0, 40.0, factor)
			elif String(light.name) == "GarageLight":
				light.light_energy = lerpf(0.12, 1.85, factor)
		_update_environment_lights(child, factor)

func weather_snapshot() -> Dictionary:
	return {
		"time_preset": current_time_preset,
		"rain_intensity": snappedf(rain_intensity, 0.01),
		"rain_target": snappedf(_rain_target, 0.01),
		"surface_wetness": snappedf(track.surface_wetness, 0.01) if track else 0.0
	}

func _spawn_asset(
	asset_name: String,
	position_value: Vector3,
	scale_value: float = 1.0,
	rotation_degrees_y: float = 0.0
) -> Node3D:
	var asset := AssetLibrary3D.instantiate_asset(asset_name)
	if asset == null:
		return null
	if asset_name.begins_with("tree_"):
		var tree_variant := int(absf(position_value.x * 0.17 + position_value.z * 0.11)) % 4
		AssetLibrary3D.style_tree(asset, tree_variant)

	asset.position = Vector3(
		position_value.x,
		TerrainBuilder3D.height_at(position_value.x, position_value.z) + position_value.y,
		position_value.z
	)
	if asset_name.begins_with("tree_"):
		var tree_variant_scale := int(absf(position_value.x * 0.13 + position_value.z * 0.19)) % 4
		var width_scale: float = float([0.84, 0.96, 1.08, 0.91][tree_variant_scale])
		var height_scale: float = float([1.16, 0.94, 1.08, 1.24][tree_variant_scale])
		asset.scale = Vector3(scale_value * width_scale, scale_value * height_scale, scale_value * width_scale)
	else:
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
	var visual_variant := int(floor(fposmod(ratio, 1.0) * 997.0 + absf(side) * 17.0)) % 4
	if asset_name.begins_with("tree_"):
		AssetLibrary3D.style_tree(asset, visual_variant)

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
	if asset_name.begins_with("tree_"):
		var width_scale: float = float([0.82, 0.95, 1.08, 0.90][visual_variant])
		var height_scale: float = float([1.22, 0.94, 1.08, 1.30][visual_variant])
		asset.scale = Vector3(scale_value * width_scale, scale_value * height_scale, scale_value * width_scale)
	else:
		asset.scale = Vector3.ONE * scale_value
	asset.add_to_group("safe_trackside_prop")

	var lod_distance := 120.0
	if asset_name == "grandstand":
		lod_distance = 230.0
	elif asset_name == "light_mast":
		lod_distance = 210.0
	elif asset_name.begins_with("tree_"):
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
		var tree_asset := "tree_pine" if i % 5 == 2 else "tree_lush"
		_spawn_safe_trackside_asset(root, tree_asset, ratio, side, extra, scale_value, float(i * 37))
		if i % 3 == 0:
			var back_tree_asset := "tree_pine" if i % 4 == 0 else "tree_lush"
			_spawn_safe_trackside_asset(root, back_tree_asset, fposmod(ratio + 0.0035, 1.0), side, extra + 7.0, scale_value * 1.12, float(i * 53 + 17))

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
	var work_light := _make_trackside_material(Color("#f6f0d8"), 0.28, 0.02, Color("#fff1bd"))
	var cabinet := _make_trackside_material(Color("#b72f36"), 0.56, 0.14)

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

		# Open-front garage shell: three walls + floor instead of a solid block.
		# The track-facing side stays open so equipment and crew are actually visible.
		_add_trackside_box(garage, "BackWall", Vector3(0.28, 3.4, 7.6), Vector3(3.46, 1.70, 0.0), concrete)
		_add_trackside_box(garage, "SideWallL", Vector3(7.0, 3.4, 0.24), Vector3(0.0, 1.70, -3.68), concrete)
		_add_trackside_box(garage, "SideWallR", Vector3(7.0, 3.4, 0.24), Vector3(0.0, 1.70, 3.68), concrete)
		_add_trackside_box(garage, "Floor", Vector3(7.0, 0.16, 7.35), Vector3(0.0, 0.08, 0.0), graphite)
		_add_trackside_box(garage, "DoorHeader", Vector3(0.24, 0.50, 7.10), Vector3(-3.54, 2.92, 0.0), graphite)
		_add_trackside_box(garage, "DoorJambL", Vector3(0.24, 2.70, 0.24), Vector3(-3.54, 1.35, -3.43), graphite)
		_add_trackside_box(garage, "DoorJambR", Vector3(0.24, 2.70, 0.24), Vector3(-3.54, 1.35, 3.43), graphite)
		_add_trackside_box(garage, "Fascia", Vector3(0.22, 0.62, 7.35), Vector3(-3.72, 3.18, 0.0), accent)
		_add_trackside_box(garage, "Roof", Vector3(7.55, 0.24, 7.95), Vector3(0.0, 3.52, 0.0), graphite)
		_add_trackside_box(garage, "WorkLight", Vector3(0.10, 0.10, 4.8), Vector3(-1.65, 3.02, 0.0), work_light)
		_add_trackside_box(garage, "ToolCabinet", Vector3(0.75, 1.25, 1.15), Vector3(2.85, 0.64, 2.65), cabinet)
		_add_trackside_box(garage, "Workbench", Vector3(0.72, 0.86, 2.15), Vector3(2.80, 0.45, -2.20), graphite)

		var garage_light := OmniLight3D.new()
		garage_light.name = "GarageLight"
		garage_light.position = Vector3(-1.45, 2.70, 0.0)
		garage_light.light_color = Color("#fff0bd")
		garage_light.light_energy = 0.72
		garage_light.omni_range = 6.5
		garage_light.shadow_enabled = false
		garage.add_child(garage_light)

		_create_dual_label(garage, "PIT %02d" % (i + 1), Vector3(-3.82, 3.18, 0.0), 36, 0.015, Color.WHITE, 90.0)

	_build_pit_crew(pit_root)

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

func _build_pit_crew(pit_root: Node3D) -> void:
	var crew_root := Node3D.new()
	crew_root.name = "PitCrew"
	pit_root.add_child(crew_root)

	var body_transforms: Array[Transform3D] = []
	var helmet_transforms: Array[Transform3D] = []
	for garage_index in range(7):
		var base_ratio := fposmod(0.962 + float(garage_index) * 0.0034, 1.0)
		for crew_index in range(2):
			var ratio := fposmod(base_ratio + (float(crew_index) - 0.5) * 0.00075, 1.0)
			var anchor := _trackside_anchor(ratio, 1.0, 4.35 + float(crew_index) * 0.55, true)
			if not bool(anchor.get("valid", false)):
				continue
			var base: Transform3D = anchor.transform

			var body := base
			body.origin += Vector3.UP * 0.60
			body.basis = base.basis.scaled(Vector3(0.95, 1.0, 0.95))
			body_transforms.append(body)

			var helmet := base
			helmet.origin += Vector3.UP * 1.28
			helmet.basis = base.basis.scaled(Vector3(1.0, 1.0, 1.0))
			helmet_transforms.append(helmet)

	if body_transforms.is_empty():
		return

	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.34, 1.04, 0.28)
	body_mesh.material = _make_trackside_material(Color("#20272d"), 0.80, 0.04)
	var body_multi := MultiMesh.new()
	body_multi.transform_format = MultiMesh.TRANSFORM_3D
	body_multi.mesh = body_mesh
	body_multi.instance_count = body_transforms.size()
	for i in range(body_transforms.size()):
		body_multi.set_instance_transform(i, body_transforms[i])
	var bodies := MultiMeshInstance3D.new()
	bodies.name = "PitCrewBodies"
	bodies.multimesh = body_multi
	bodies.visibility_range_end = 125.0
	bodies.visibility_range_end_margin = 18.0
	crew_root.add_child(bodies)

	var helmet_mesh := SphereMesh.new()
	helmet_mesh.radius = 0.15
	helmet_mesh.height = 0.27
	helmet_mesh.radial_segments = 10
	helmet_mesh.rings = 5
	helmet_mesh.material = _make_trackside_material(Color("#d83b43"), 0.42, 0.16)
	var helmet_multi := MultiMesh.new()
	helmet_multi.transform_format = MultiMesh.TRANSFORM_3D
	helmet_multi.mesh = helmet_mesh
	helmet_multi.instance_count = helmet_transforms.size()
	for i in range(helmet_transforms.size()):
		helmet_multi.set_instance_transform(i, helmet_transforms[i])
	var helmets := MultiMeshInstance3D.new()
	helmets.name = "PitCrewHelmets"
	helmets.multimesh = helmet_multi
	helmets.visibility_range_end = 125.0
	helmets.visibility_range_end_margin = 18.0
	crew_root.add_child(helmets)

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
	var head_transforms: Array[Transform3D] = []
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

				var head := base
				head.origin = person.origin + Vector3.UP * (0.50 * height_scale)
				head.basis = base.basis
				head_transforms.append(head)

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

	if not head_transforms.is_empty():
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 0.115
		head_mesh.height = 0.22
		head_mesh.radial_segments = 8
		head_mesh.rings = 4
		head_mesh.material = _make_trackside_material(Color("#c99a73"), 0.88, 0.0)

		var head_multi := MultiMesh.new()
		head_multi.transform_format = MultiMesh.TRANSFORM_3D
		head_multi.mesh = head_mesh
		head_multi.instance_count = head_transforms.size()
		for i in range(head_transforms.size()):
			head_multi.set_instance_transform(i, head_transforms[i])

		var heads := MultiMeshInstance3D.new()
		heads.name = "CrowdHeads"
		heads.multimesh = head_multi
		heads.visibility_range_end = 165.0
		heads.visibility_range_end_margin = 20.0
		crowd_root.add_child(heads)

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
	var tree_variant := int(absf(position_value.x * 0.17 + position_value.z * 0.11)) % 4
	var tree_name := "tree_pine" if tree_variant == 2 else "tree_lush"
	var tree := AssetLibrary3D.instantiate_asset(tree_name)
	if tree:
		AssetLibrary3D.style_tree(tree, tree_variant)
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
