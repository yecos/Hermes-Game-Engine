class_name HermesRuntimeBridge
extends Node

@export var port: int = 8650

var player: ArcadeCarController3D
var track: TrackSpline
var race_manager: RaceManager3D

var _server := TCPServer.new()
var _clients: Array[StreamPeerTCP] = []
var _buffers: Dictionary = {}

func _ready() -> void:
	var error := _server.listen(port, "127.0.0.1")
	if error == OK:
		print("HGE_GODOT_BRIDGE_READY port=", port)
	else:
		push_error("Hermes runtime bridge failed to listen on %d: %s" % [port, error_string(error)])

func _process(_delta: float) -> void:
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
			if player and track:
				var spawn := track.get_world_transform_at_ratio(0.018)
				spawn.origin += spawn.basis.x * -1.4 + Vector3.UP * player.ride_height
				player.global_transform = spawn
				player.velocity = Vector3.ZERO
			_send(peer, {"ok": true})
		"service_car":
			if player:
				player.fuel_liters = player.fuel_capacity_liters
				player.tire_health = 1.0
				player.damage = 0.0
			_send(peer, {"ok": true, "telemetry": _telemetry()})
		_:
			_send(peer, {"ok": false, "error": "unknown_command", "command": command})

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

func _telemetry() -> Dictionary:
	if player == null:
		return {}

	var payload := player.telemetry()
	if race_manager:
		payload["lap"] = race_manager.player_lap
		payload["position"] = race_manager.current_position
		payload["sector"] = race_manager.current_sector
		payload["best_lap"] = race_manager.best_lap_time
	return payload

func _send(peer: StreamPeerTCP, payload: Dictionary) -> void:
	var encoded := JSON.stringify(payload) + "\n"
	peer.put_data(encoded.to_utf8_buffer())
