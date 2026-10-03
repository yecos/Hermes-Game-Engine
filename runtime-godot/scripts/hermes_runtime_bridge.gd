class_name HermesRuntimeBridge
extends Node

@export var port: int = 8650

var player: ArcadeCarController3D
var track: TrackSpline
var race_manager: RaceManager3D
var replay_manager: ReplayManager3D

var _server := TCPServer.new()
var _clients: Array[StreamPeerTCP] = []
var _buffers: Dictionary = {}

var _test_running: bool = false
var _test_target_laps: int = 0
var _test_started_at: int = 0
var _test_start_fuel: float = 0.0
var _test_sample_timer: float = 0.0
var _test_samples: Array[Dictionary] = []
var _last_test_summary: Dictionary = {}

const RUNTIME_ASSETS: Array[String] = [
	"grandstand",
	"light_mast",
	"paddock_tent",
	"service_van",
	"tire_stack",
	"track_cone",
	"tree_lush"
]

var _runtime_assets: Array[Node3D] = []

func _ready() -> void:
	var error := _server.listen(port, "127.0.0.1")
	if error == OK:
		print("HGE_GODOT_BRIDGE_READY port=", port)
	else:
		push_error("Hermes runtime bridge failed to listen on %d: %s" % [port, error_string(error)])

func _process(delta: float) -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer:
			_clients.append(peer)
			_buffers[peer] = ""

	for peer in _clients.duplicate():
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(peer)
			_buffers.erase(peer)
			continue

		var available: int = peer.get_available_bytes()
		if available <= 0:
			continue

		var result: Array = peer.get_data(available)
		if result[0] != OK:
			continue

		var chunk := (result[1] as PackedByteArray).get_string_from_utf8()
		var buffer := String(_buffers.get(peer, "")) + chunk

		while buffer.contains("\n"):
			var newline := buffer.find("\n")
			var line := buffer.substr(0, newline).strip_edges()
			buffer = buffer.substr(newline + 1)
			if not line.is_empty():
				_handle_line(peer, line)

		_buffers[peer] = buffer

	_update_test_run(delta)

func _handle_line(peer: StreamPeerTCP, line: String) -> void:
	var payload = JSON.parse_string(line)
	if typeof(payload) != TYPE_DICTIONARY:
		_send(peer, {"ok": false, "error": "invalid_json"})
		return

	var command := String(payload.get("command", "telemetry"))
	match command:
		"telemetry":
			_send(peer, {"ok": true, "telemetry": _telemetry()})
		"set_tuning":
			var values: Dictionary = payload.get("values", {})
			_apply_tuning(values)
			_send(peer, {"ok": true, "telemetry": _telemetry()})
		"reset_car":
			_reset_player()
			_send(peer, {"ok": true, "telemetry": _telemetry()})
		"service_car":
			_service_player()
			_send(peer, {"ok": true, "telemetry": _telemetry()})
		"start_test_run":
			var laps := clampi(int(payload.get("laps", 1)), 1, 3)
			_start_test_run(laps)
			_send(peer, {"ok": true, "test": _test_status()})
		"stop_test_run":
			_finish_test_run(false, "stopped")
			_send(peer, {"ok": true, "test": _test_status()})
		"test_summary":
			_send(peer, {"ok": true, "test": _test_status()})
		"start_replay":
			if replay_manager:
				replay_manager.start_replay()
			_send(peer, {"ok": true})
		"asset_inventory":
			_send(peer, {"ok": true, "assets": RUNTIME_ASSETS, "spawned": _runtime_assets.size()})
		"spawn_asset":
			_send(peer, _spawn_runtime_asset(payload))
		"clear_runtime_assets":
			_clear_runtime_assets()
			_send(peer, {"ok": true, "spawned": 0})
		"track_snapshot":
			_send(peer, {"ok": true, "track": track.track_snapshot() if track else {}})
		"set_track_point":
			_send(peer, _set_track_point(payload))
		"set_track_bank":
			_send(peer, _set_track_bank(payload))
		"replace_track":
			_send(peer, _replace_track(payload))
		"reset_track":
			if track:
				track.build_default_circuit()
				_after_track_edit()
			_send(peer, {"ok": true, "track": track.track_snapshot() if track else {}})
		_:
			_send(peer, {"ok": false, "error": "unknown_command", "command": command})

func _set_track_point(payload: Dictionary) -> Dictionary:
	if track == null:
		return {"ok": false, "error": "track_unavailable"}
	var index := int(payload.get("index", -1))
	var snapshot := track.track_snapshot()
	var points: Array = snapshot.get("points", [])
	if index < 0 or index >= points.size():
		return {"ok": false, "error": "invalid_track_index", "index": index}
	var current: Dictionary = points[index]
	var x := float(payload.get("x", current.get("x", 0.0)))
	var z := float(payload.get("z", current.get("z", 0.0)))
	var bank := float(payload.get("bank", current.get("bank", 0.0)))
	var ok := track.set_control_point(index, x, z, bank)
	if ok:
		_after_track_edit()
	return {"ok": ok, "track": track.track_snapshot()}

func _set_track_bank(payload: Dictionary) -> Dictionary:
	if track == null:
		return {"ok": false, "error": "track_unavailable"}
	var index := int(payload.get("index", -1))
	var bank := float(payload.get("bank", 0.0))
	var ok := track.set_bank(index, bank)
	if ok:
		_after_track_edit()
	return {"ok": ok, "track": track.track_snapshot()}

func _replace_track(payload: Dictionary) -> Dictionary:
	if track == null:
		return {"ok": false, "error": "track_unavailable"}
	var points: Array = payload.get("points", [])
	var ok := track.replace_control_points(points)
	if ok:
		_after_track_edit()
	return {"ok": ok, "track": track.track_snapshot()}

func _after_track_edit() -> void:
	_reset_player()
	if race_manager:
		race_manager.reset_session()

func _spawn_runtime_asset(payload: Dictionary) -> Dictionary:
	var asset_name := String(payload.get("asset", ""))
	if not RUNTIME_ASSETS.has(asset_name):
		return {"ok": false, "error": "asset_not_allowed", "asset": asset_name}

	var instance := AssetLibrary3D.instantiate_asset(asset_name)
	if instance == null:
		return {"ok": false, "error": "asset_missing", "asset": asset_name}

	var x := clampf(float(payload.get("x", 0.0)), -70.0, 70.0)
	var z := clampf(float(payload.get("z", 0.0)), -70.0, 70.0)
	var scale_value := clampf(float(payload.get("scale", 1.0)), 0.35, 2.5)
	var rotation_value := clampf(float(payload.get("rotation", 0.0)), -360.0, 360.0)
	var surface_y := TerrainBuilder3D.height_at(x, z)

	instance.name = "HermesAsset_%s_%d" % [asset_name, _runtime_assets.size() + 1]
	instance.position = Vector3(x, surface_y, z)
	instance.scale = Vector3.ONE * scale_value
	instance.rotation.y = deg_to_rad(rotation_value)
	var lod_distance := 115.0 if asset_name == "grandstand" or asset_name == "light_mast" else 85.0
	AssetLibrary3D.apply_lod(instance, lod_distance, 14.0)

	var scene := get_tree().current_scene
	if scene == null:
		instance.free()
		return {"ok": false, "error": "scene_unavailable"}

	scene.add_child(instance)
	_runtime_assets.append(instance)

	return {
		"ok": true,
		"asset": asset_name,
		"x": snappedf(x, 0.01),
		"y": snappedf(surface_y, 0.01),
		"z": snappedf(z, 0.01),
		"scale": snappedf(scale_value, 0.01),
		"rotation": snappedf(rotation_value, 0.1),
		"spawned": _runtime_assets.size()
	}

func _clear_runtime_assets() -> void:
	for asset in _runtime_assets:
		if is_instance_valid(asset):
			asset.queue_free()
	_runtime_assets.clear()

func _apply_tuning(values: Dictionary) -> void:
	if player == null:
		return

	var allowed := {
		"top_speed": Vector2(18.0, 55.0),
		"acceleration": Vector2(8.0, 55.0),
		"brake_force": Vector2(12.0, 75.0),
		"lateral_grip": Vector2(5.0, 32.0),
		"steering_rate": Vector2(0.8, 4.6),
		"turbo_force": Vector2(0.0, 35.0)
	}

	for key in values.keys():
		var key_string := String(key)
		if not allowed.has(key_string):
			continue
		var limits: Vector2 = allowed[key_string]
		var value := clampf(float(values[key]), limits.x, limits.y)
		player.set(key_string, value)

func _reset_player() -> void:
	if player == null or track == null:
		return

	if replay_manager and replay_manager.replay_active:
		replay_manager.stop_replay()

	player.autopilot_enabled = false
	player.replay_mode = false
	player.input_enabled = true
	var spawn := track.get_world_transform_at_ratio(0.018)
	spawn.origin += spawn.basis.x * -1.4 + Vector3.UP * player.ride_height
	player.global_transform = spawn
	player.reset_dynamics()

	if race_manager:
		race_manager.reset_session()

func _service_player() -> void:
	if player == null:
		return
	player.fuel_liters = player.fuel_capacity_liters
	player.tire_health = 1.0
	player.damage = 0.0

func _start_test_run(laps: int) -> void:
	if player == null or track == null or race_manager == null:
		return

	_reset_player()
	_service_player()
	race_manager.reset_session()

	_test_running = true
	_test_target_laps = laps
	_test_started_at = Time.get_ticks_msec()
	_test_start_fuel = player.fuel_liters
	_test_sample_timer = 0.0
	_test_samples.clear()
	_last_test_summary = {}

	player.input_enabled = false
	player.autopilot_enabled = true

func _update_test_run(delta: float) -> void:
	if not _test_running or player == null or race_manager == null:
		return

	_test_sample_timer += delta
	if _test_sample_timer >= 0.10:
		_test_sample_timer -= 0.10
		_test_samples.append({
			"speed": player.speed_kmh,
			"slip": player.slip_amount,
			"offroad": player.is_offroad,
			"damage": player.damage,
			"fuel": player.fuel_liters,
			"tire": player.tire_health
		})

	var elapsed := float(Time.get_ticks_msec() - _test_started_at) / 1000.0
	if race_manager.player_lap >= _test_target_laps:
		_finish_test_run(true, "completed")
	elif elapsed > 75.0:
		_finish_test_run(false, "timeout")

func _finish_test_run(completed: bool, reason: String) -> void:
	if not _test_running:
		return

	_test_running = false
	if player:
		player.autopilot_enabled = false
		player.input_enabled = true
		player.reset_dynamics()

	var count := _test_samples.size()
	var speed_sum := 0.0
	var slip_sum := 0.0
	var max_speed := 0.0
	var offroad_samples := 0

	for sample in _test_samples:
		var speed := float(sample.get("speed", 0.0))
		var slip := float(sample.get("slip", 0.0))
		speed_sum += speed
		slip_sum += slip
		max_speed = maxf(max_speed, speed)
		if bool(sample.get("offroad", false)):
			offroad_samples += 1

	var elapsed := float(Time.get_ticks_msec() - _test_started_at) / 1000.0
	_last_test_summary = {
		"completed": completed,
		"reason": reason,
		"target_laps": _test_target_laps,
		"laps_completed": race_manager.player_lap if race_manager else 0,
		"elapsed_seconds": snappedf(elapsed, 0.01),
		"samples": count,
		"average_speed_kmh": snappedf(speed_sum / maxf(1.0, float(count)), 0.1),
		"max_speed_kmh": snappedf(max_speed, 0.1),
		"average_slip": snappedf(slip_sum / maxf(1.0, float(count)), 0.001),
		"offroad_ratio": snappedf(float(offroad_samples) / maxf(1.0, float(count)), 0.001),
		"best_lap_seconds": snappedf(race_manager.best_lap_time if race_manager else 0.0, 0.001),
		"fuel_used_liters": snappedf(_test_start_fuel - (player.fuel_liters if player else _test_start_fuel), 0.01),
		"tire_remaining": snappedf(player.tire_health if player else 1.0, 0.001),
		"damage": snappedf(player.damage if player else 0.0, 0.001)
	}

func _test_status() -> Dictionary:
	return {
		"running": _test_running,
		"target_laps": _test_target_laps,
		"current_lap": race_manager.player_lap if race_manager else 0,
		"summary": _last_test_summary
	}

func _telemetry() -> Dictionary:
	if player == null:
		return {}

	var payload := player.telemetry()
	if race_manager:
		payload["lap"] = race_manager.player_lap
		payload["position"] = race_manager.current_position
		payload["sector"] = race_manager.current_sector
		payload["best_lap"] = race_manager.best_lap_time
	payload["test_run"] = _test_status()
	payload["replay_active"] = replay_manager.replay_active if replay_manager else false
	payload["asset_pipeline"] = {
		"format": "GLB/GLTF",
		"available": RUNTIME_ASSETS,
		"runtime_spawned": _runtime_assets.size()
	}
	payload["track_editor"] = {
		"point_count": track.control_points.size() if track else 0,
		"length": snappedf(track.get_length(), 0.1) if track else 0.0,
		"banking": true,
		"runoff": true,
		"pit_lane": true
	}
	return payload

func _send(peer: StreamPeerTCP, payload: Dictionary) -> void:
	var encoded := JSON.stringify(payload) + "\n"
	peer.put_data(encoded.to_utf8_buffer())
