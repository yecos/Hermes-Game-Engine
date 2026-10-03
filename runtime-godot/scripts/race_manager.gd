class_name RaceManager3D
extends Node

@export var total_laps: int = 3

var track: TrackSpline
var player: ArcadeCarController3D
var ai_racers: Array[AIRacer3D] = []

var player_lap: int = 0
var current_position: int = 1
var current_sector: int = 1
var best_lap_time: float = 0.0
var current_lap_time: float = 0.0
var last_lap_time: float = 0.0
var last_sector_time: float = 0.0

var _last_ratio: float = 0.0
var _lap_started_at: int = 0
var _sector_started_at: int = 0
var _last_sector: int = 1

var _position_label: Label
var _lap_label: Label
var _speed_label: Label
var _gear_label: Label
var _rpm_label: Label
var _drift_label: Label
var _status_label: Label
var _timing_label: Label
var _resources_label: Label

func _ready() -> void:
	_build_hud()

	if player and track:
		_last_ratio = track.get_progress_ratio(player.global_position)
		current_sector = track.get_sector_index(player.global_position)
		_last_sector = current_sector

	_lap_started_at = Time.get_ticks_msec()
	_sector_started_at = _lap_started_at

func _process(_delta: float) -> void:
	if player == null or track == null:
		return
	if player.replay_mode:
		return

	var now := Time.get_ticks_msec()
	var ratio := track.get_progress_ratio(player.global_position)
	current_sector = track.get_sector_index(player.global_position)
	current_lap_time = float(now - _lap_started_at) / 1000.0

	if current_sector != _last_sector:
		last_sector_time = float(now - _sector_started_at) / 1000.0
		_sector_started_at = now
		_last_sector = current_sector

	if _last_ratio > 0.88 and ratio < 0.12:
		player_lap += 1
		last_lap_time = current_lap_time
		if best_lap_time <= 0.0 or last_lap_time < best_lap_time:
			best_lap_time = last_lap_time
		_lap_started_at = now
		_sector_started_at = now
		current_lap_time = 0.0

	_last_ratio = ratio
	var player_total := float(player_lap) + ratio

	current_position = 1
	for ai in ai_racers:
		if ai.total_progress() > player_total:
			current_position += 1

	_position_label.text = _ordinal(current_position)
	_lap_label.text = "LAP %d/%d · S%d" % [min(player_lap + 1, total_laps), total_laps, current_sector]
	_speed_label.text = "%03d km/h" % int(player.speed_kmh)
	_gear_label.text = player.gear_display()
	_rpm_label.text = "%04d RPM%s" % [
		int(player.engine_rpm),
		"  SHIFT" if player.is_shifting else ""
	]
	_drift_label.text = "SLIP %4.1f°  %3d%%" % [
		absf(player.vehicle_slip_angle_deg),
		int(player.drift_intensity * 100.0)
	]

	var best_text := "--:--.---"
	if best_lap_time > 0.0:
		best_text = _format_time(best_lap_time)

	_timing_label.text = "LAP %s
BEST %s
SECTOR %.3fs" % [
		_format_time(current_lap_time),
		best_text,
		last_sector_time
	]

	_resources_label.text = "FUEL %3d%%
TIRES %3d%%
DMG %3d%%" % [
		int((player.fuel_liters / maxf(0.001, player.fuel_capacity_liters)) * 100.0),
		int(player.tire_health * 100.0),
		int(player.damage * 100.0)
	]

	if player_lap >= total_laps:
		_status_label.text = "FINISH · " + _ordinal(current_position)
	elif player.pit_servicing:
		_status_label.text = "PIT SERVICE"
	elif player.in_pit_lane and player.speed_kmh < 18.0:
		_status_label.text = "HOLD E FOR PIT"
	elif player.is_offroad:
		_status_label.text = "OFF ROAD"
	else:
		_status_label.text = ""

func reset_session() -> void:
	player_lap = 0
	current_position = 1
	current_sector = 1
	best_lap_time = 0.0
	current_lap_time = 0.0
	last_lap_time = 0.0
	last_sector_time = 0.0
	_last_ratio = track.get_progress_ratio(player.global_position) if track and player else 0.0
	_last_sector = track.get_sector_index(player.global_position) if track and player else 1
	_lap_started_at = Time.get_ticks_msec()
	_sector_started_at = _lap_started_at

func snapshot() -> Dictionary:
	return {
		"lap": player_lap,
		"position": current_position,
		"sector": current_sector,
		"current_lap_time": snappedf(current_lap_time, 0.001),
		"last_lap_time": snappedf(last_lap_time, 0.001),
		"best_lap_time": snappedf(best_lap_time, 0.001),
		"last_sector_time": snappedf(last_sector_time, 0.001)
	}

func _format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	var remainder := fmod(seconds, 60.0)
	return "%d:%06.3f" % [minutes, remainder]

func _ordinal(value: int) -> String:
	var mod10 := value % 10
	var mod100 := value % 100

	if mod10 == 1 and mod100 != 11:
		return "%dst" % value
	if mod10 == 2 and mod100 != 12:
		return "%dnd" % value
	if mod10 == 3 and mod100 != 13:
		return "%drd" % value
	return "%dth" % value

func _make_label(text_value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.04, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	return label

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	_position_label = _make_label("1st", 48)
	_position_label.position = Vector2(28, 20)
	layer.add_child(_position_label)

	_lap_label = _make_label("LAP 1/%d · S1" % total_laps, 22)
	_lap_label.position = Vector2(32, 78)
	layer.add_child(_lap_label)

	_speed_label = _make_label("000 km/h", 28)
	_speed_label.position = Vector2(1050, 28)
	layer.add_child(_speed_label)

	var controls := _make_label("W ACCEL | S BRAKE/REVERSE | A/D STEER | SPACE BOOST | E PIT | R REPLAY", 13)
	controls.position = Vector2(720, 68)
	layer.add_child(controls)

	_gear_label = _make_label("1", 52)
	_gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear_label.position = Vector2(1160, 176)
	_gear_label.size = Vector2(80, 64)
	layer.add_child(_gear_label)

	_rpm_label = _make_label("1050 RPM", 14)
	_rpm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rpm_label.position = Vector2(1010, 236)
	_rpm_label.size = Vector2(230, 26)
	layer.add_child(_rpm_label)

	_drift_label = _make_label("SLIP 0.0°   0%", 13)
	_drift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_drift_label.position = Vector2(1000, 262)
	_drift_label.size = Vector2(240, 24)
	layer.add_child(_drift_label)

	_timing_label = _make_label("LAP 0:00.000
BEST --:--.---
SECTOR 0.000s", 16)
	_timing_label.position = Vector2(28, 112)
	layer.add_child(_timing_label)

	_resources_label = _make_label("FUEL 100%
TIRES 100%
DMG   0%", 16)
	_resources_label.position = Vector2(1080, 110)
	layer.add_child(_resources_label)

	_status_label = _make_label("", 34)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(440, 28)
	_status_label.size = Vector2(400, 50)
	layer.add_child(_status_label)
