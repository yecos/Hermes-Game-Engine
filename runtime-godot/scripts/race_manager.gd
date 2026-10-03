class_name RaceManager3D
extends Node

@export var total_laps: int = 3

var track: TrackSpline
var player: ArcadeCarController3D
var ai_racers: Array[AIRacer3D] = []

var player_lap: int = 0
var _last_ratio: float = 0.0
var _position_label: Label
var _lap_label: Label
var _speed_label: Label
var _status_label: Label

func _ready() -> void:
	_build_hud()

	if player and track:
		_last_ratio = track.get_progress_ratio(player.global_position)

func _process(_delta: float) -> void:
	if player == null or track == null:
		return

	var ratio := track.get_progress_ratio(player.global_position)

	if _last_ratio > 0.88 and ratio < 0.12:
		player_lap += 1

	_last_ratio = ratio
	var player_total := float(player_lap) + ratio

	var place := 1
	for ai in ai_racers:
		if ai.total_progress() > player_total:
			place += 1

	_position_label.text = _ordinal(place)
	_lap_label.text = "LAP %d/%d" % [min(player_lap + 1, total_laps), total_laps]
	_speed_label.text = "%03d km/h" % int(player.speed_kmh)

	if player_lap >= total_laps:
		_status_label.text = "FINISH · " + _ordinal(place)
	elif player.is_offroad:
		_status_label.text = "OFF ROAD"
	else:
		_status_label.text = ""

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

	_lap_label = _make_label("LAP 1/%d" % total_laps, 22)
	_lap_label.position = Vector2(32, 78)
	layer.add_child(_lap_label)

	_speed_label = _make_label("000 km/h", 28)
	_speed_label.position = Vector2(1060, 28)
	layer.add_child(_speed_label)

	var controls := _make_label("WASD / ARROWS · SPACE TURBO", 14)
	controls.position = Vector2(955, 68)
	layer.add_child(controls)

	_status_label = _make_label("", 34)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(440, 28)
	_status_label.size = Vector2(400, 50)
	layer.add_child(_status_label)
