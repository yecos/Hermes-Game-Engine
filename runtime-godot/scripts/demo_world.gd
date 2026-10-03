extends Node3D

var track: TrackSpline
var player: ArcadeCarController3D
var camera: RaceCamera3D
var ai_racers: Array[AIRacer3D] = []

func _ready() -> void:
	_register_input_actions()
	_build_environment()
	_build_track()
	_spawn_player()
	_spawn_ai()
	_spawn_camera()
	_spawn_race_manager()
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
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#8ed4ff")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d9e9f2")
	environment.ambient_light_energy = 0.78
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	add_child(sun)

	var grass := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(125.0, 125.0)
	grass.mesh = plane
	grass.position.y = -0.04

	var grass_material := StandardMaterial3D.new()
	grass_material.albedo_color = Color("#65a94e")
	grass_material.roughness = 1.0
	grass.material_override = grass_material
	add_child(grass)

	_build_scenery()

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
	var root := Node3D.new()
	root.position = position_value
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
	crown_material.albedo_color = Color("#3f8d46") if int(position_value.x + position_value.z) % 2 == 0 else Color("#4e9d4d")
	crown_material.roughness = 0.95
	crown.material_override = crown_material
	root.add_child(crown)

func _build_track() -> void:
	track = TrackSpline.new()
	track.name = "GrandCircuit"
	add_child(track)

func _spawn_player() -> void:
	player = ArcadeCarController3D.new()
	player.name = "PlayerCar"
	player.body_color = Color("#ef4052")
	player.track = track
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
		ai.speed_mps = 25.5 + float(i) * 0.55
		ai.lane_offset = (float(i % 3) - 1.0) * 1.15
		add_child(ai)

		var spawn := track.get_world_transform_at_ratio(ai.progress_ratio)
		spawn.origin += spawn.basis.x * ai.lane_offset + Vector3.UP * 0.48
		ai.global_transform = spawn
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
	var manager := RaceManager3D.new()
	manager.name = "RaceManager"
	manager.track = track
	manager.player = player
	manager.ai_racers = ai_racers
	manager.total_laps = 3
	add_child(manager)
