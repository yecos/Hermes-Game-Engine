class_name ReplayManager3D
extends Node

@export var record_seconds: float = 12.0
@export var record_rate: float = 20.0

var player: ArcadeCarController3D
var track: TrackSpline
var live_camera: RaceCamera3D

var replay_active: bool = false
var _frames: Array[Dictionary] = []
var _record_timer: float = 0.0
var _play_index: int = 0
var _play_timer: float = 0.0
var _saved_transform: Transform3D
var _saved_velocity: Vector3
var _tv_camera: Camera3D
var _label: Label
var _shot_index: int = -1

func _ready() -> void:
	_build_camera()
	_build_label()

func _process(delta: float) -> void:
	if player == null or track == null:
		return

	if replay_active:
		_update_replay(delta)
	else:
		_record_timer += delta
		var interval := 1.0 / maxf(1.0, record_rate)
		if _record_timer >= interval:
			_record_timer -= interval
			_record_frame()

	if Input.is_action_just_pressed("replay"):
		if replay_active:
			stop_replay()
		else:
			start_replay()

func _record_frame() -> void:
	_frames.append({
		"transform": player.global_transform,
		"speed": player.speed_kmh
	})
	var max_frames := int(record_seconds * record_rate)
	while _frames.size() > max_frames:
		_frames.pop_front()

func start_replay() -> void:
	if _frames.size() < int(record_rate * 2.0):
		return

	replay_active = true
	_play_index = 0
	_play_timer = 0.0
	_shot_index = -1
	_saved_transform = player.global_transform
	_saved_velocity = player.velocity
	player.replay_mode = true
	player.input_enabled = false
	_tv_camera.current = true
	_label.visible = true

func stop_replay() -> void:
	if not replay_active:
		return

	replay_active = false
	player.global_transform = _saved_transform
	player.velocity = _saved_velocity
	player.replay_mode = false
	player.input_enabled = true
	if live_camera:
		live_camera.current = true
	_label.visible = false

func _update_replay(delta: float) -> void:
	_play_timer += delta
	var interval := 1.0 / maxf(1.0, record_rate)

	while _play_timer >= interval:
		_play_timer -= interval
		_play_index += 1
		if _play_index >= _frames.size():
			stop_replay()
			return

	var frame: Dictionary = _frames[_play_index]
	var next_index := mini(_play_index + 1, _frames.size() - 1)
	var next_frame: Dictionary = _frames[next_index]
	var alpha := clampf(_play_timer / interval, 0.0, 1.0)
	player.global_transform = (frame.transform as Transform3D).interpolate_with(next_frame.transform as Transform3D, alpha)
	player.velocity = Vector3.ZERO

	_update_tv_camera()

func _update_tv_camera() -> void:
	var ratio := float(_play_index) / maxf(1.0, float(_frames.size() - 1))
	var shot := int(ratio * 4.0) % 4
	if shot != _shot_index:
		_shot_index = shot

	var track_ratios := [0.08, 0.31, 0.57, 0.82]
	var base := track.get_world_transform_at_ratio(track_ratios[shot])
	var side := -1.0 if shot % 2 == 0 else 1.0
	_tv_camera.global_position = base.origin + base.basis.x * side * 10.0 + Vector3.UP * (7.5 + float(shot % 2) * 2.0)
	_tv_camera.look_at(player.global_position + Vector3.UP * 0.5, Vector3.UP)

func _build_camera() -> void:
	_tv_camera = Camera3D.new()
	_tv_camera.name = "ReplayTVCamera"
	_tv_camera.fov = 42.0
	add_child(_tv_camera)

func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_label = Label.new()
	_label.text = "REPLAY"
	_label.position = Vector2(590, 34)
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color("#ffffff"))
	_label.add_theme_color_override("font_shadow_color", Color("#000000"))
	_label.add_theme_constant_override("shadow_offset_x", 3)
	_label.add_theme_constant_override("shadow_offset_y", 3)
	_label.visible = false
	layer.add_child(_label)
