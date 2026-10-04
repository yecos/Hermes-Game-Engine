class_name ReplayManager3D
extends Node

@export var record_seconds: float = 14.0
@export var record_rate: float = 24.0
@export var playback_speed: float = 0.78
@export var shot_seconds: float = 2.4

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
var _saved_input_enabled: bool = true
var _saved_autopilot_enabled: bool = false
var _tv_camera: Camera3D
var _label: Label
var _shot_label: Label
var _speed_label: Label
var _shot_index: int = -1
var _shot_elapsed: float = 0.0
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _smoothed_camera_position: Vector3
var _hidden_race_layers: Array[CanvasLayer] = []
var _shot_modes := ["TRACKSIDE", "LOW KERB", "HELICOPTER", "LONG LENS", "CHASE"]

func _ready() -> void:
	_build_camera()
	_build_overlay()

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
		"speed": player.speed_kmh,
		"drift": player.drift_intensity,
		"brake": player.brake_input
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
	_shot_elapsed = shot_seconds
	_saved_transform = player.global_transform
	_saved_velocity = player.velocity
	_saved_input_enabled = player.input_enabled
	_saved_autopilot_enabled = player.autopilot_enabled
	player.replay_mode = true
	player.input_enabled = false
	player.autopilot_enabled = false
	_tv_camera.current = true
	_hide_race_hud()
	_set_overlay_visible(true)
	_smoothed_camera_position = _tv_camera.global_position
	_advance_shot()

func stop_replay() -> void:
	if not replay_active:
		return

	replay_active = false
	player.global_transform = _saved_transform
	player.velocity = _saved_velocity
	player.replay_mode = false
	player.input_enabled = _saved_input_enabled
	player.autopilot_enabled = _saved_autopilot_enabled
	if live_camera:
		live_camera.current = true
	_restore_race_hud()
	_set_overlay_visible(false)

func _update_replay(delta: float) -> void:
	var speed_scale := maxf(0.2, playback_speed)
	_play_timer += delta * speed_scale
	_shot_elapsed += delta

	if _shot_elapsed >= shot_seconds:
		_advance_shot()

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

	_update_tv_camera(delta)

	if _speed_label:
		_speed_label.text = "%03d km/h" % int(float(frame.speed))

func _advance_shot() -> void:
	_shot_elapsed = 0.0
	_shot_index = (_shot_index + 1) % _shot_modes.size()
	if _shot_label:
		_shot_label.text = String(_shot_modes[_shot_index])

func _update_tv_camera(delta: float) -> void:
	var mode := String(_shot_modes[maxi(0, _shot_index)])
	var ratio := track.get_progress_ratio(player.global_position)
	var frame := track.get_world_transform_at_ratio(ratio)
	var forward := -player.global_transform.basis.z.normalized()
	var right := player.global_transform.basis.x.normalized()
	var desired_position := player.global_position - forward * 8.0 + Vector3.UP * 4.0
	var target := player.global_position + Vector3.UP * 0.55
	var desired_fov := 42.0

	match mode:
		"TRACKSIDE":
			var anchor := track.get_world_transform_at_ratio(ratio + 0.010)
			var side := -1.0 if int(_play_index / maxi(1, int(record_rate))) % 2 == 0 else 1.0
			desired_position = anchor.origin + anchor.basis.x * side * 13.0 + Vector3.UP * 5.0
			target = player.global_position + Vector3.UP * 0.62
			desired_fov = 38.0
		"LOW KERB":
			var anchor := track.get_world_transform_at_ratio(ratio + 0.004)
			var side := 1.0 if _shot_index % 2 == 0 else -1.0
			desired_position = anchor.origin + anchor.basis.x * side * 7.7 + Vector3.UP * 1.15
			target = player.global_position + forward * 1.7 + Vector3.UP * 0.38
			desired_fov = 34.0
		"HELICOPTER":
			desired_position = player.global_position - forward * 13.0 + right * 10.0 + Vector3.UP * 23.0
			target = player.global_position + forward * 4.0
			desired_fov = 46.0
		"LONG LENS":
			var anchor := track.get_world_transform_at_ratio(ratio + 0.032)
			desired_position = anchor.origin + anchor.basis.x * -16.0 + Vector3.UP * 6.8
			target = player.global_position + Vector3.UP * 0.55
			desired_fov = 24.0
		"CHASE":
			desired_position = player.global_position - forward * 9.2 + right * 1.8 + Vector3.UP * 3.2
			target = player.global_position + forward * 6.5 + Vector3.UP * 0.50
			desired_fov = 51.0

	var smooth_rate := 5.2 if mode != "LOW KERB" else 8.5
	var weight := 1.0 - exp(-smooth_rate * delta)
	_smoothed_camera_position = _smoothed_camera_position.lerp(desired_position, weight)
	_tv_camera.global_position = _smoothed_camera_position
	_tv_camera.fov = lerpf(_tv_camera.fov, desired_fov, 1.0 - exp(-4.5 * delta))
	_tv_camera.look_at(target, Vector3.UP)

func _build_camera() -> void:
	_tv_camera = Camera3D.new()
	_tv_camera.name = "ReplayTVCamera"
	_tv_camera.fov = 42.0
	add_child(_tv_camera)

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	_top_bar = ColorRect.new()
	_top_bar.name = "ReplayTopBar"
	_top_bar.position = Vector2(0, 0)
	_top_bar.size = Vector2(1280, 48)
	_top_bar.color = Color(0.0, 0.0, 0.0, 0.86)
	layer.add_child(_top_bar)

	_bottom_bar = ColorRect.new()
	_bottom_bar.name = "ReplayBottomBar"
	_bottom_bar.position = Vector2(0, 672)
	_bottom_bar.size = Vector2(1280, 48)
	_bottom_bar.color = Color(0.0, 0.0, 0.0, 0.86)
	layer.add_child(_bottom_bar)

	_label = Label.new()
	_label.name = "ReplayLabel"
	_label.text = "REPLAY"
	_label.position = Vector2(36, 10)
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color("#ffffff"))
	layer.add_child(_label)

	_shot_label = Label.new()
	_shot_label.name = "ReplayShotLabel"
	_shot_label.text = "TRACKSIDE"
	_shot_label.position = Vector2(540, 13)
	_shot_label.size = Vector2(200, 28)
	_shot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shot_label.add_theme_font_size_override("font_size", 15)
	_shot_label.add_theme_color_override("font_color", Color("#d9e1e7"))
	layer.add_child(_shot_label)

	_speed_label = Label.new()
	_speed_label.name = "ReplaySpeedLabel"
	_speed_label.text = "000 km/h"
	_speed_label.position = Vector2(1080, 11)
	_speed_label.size = Vector2(160, 28)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.add_theme_font_size_override("font_size", 18)
	_speed_label.add_theme_color_override("font_color", Color("#ffffff"))
	layer.add_child(_speed_label)

	_set_overlay_visible(false)

func _set_overlay_visible(value: bool) -> void:
	if _label:
		_label.visible = value
	if _shot_label:
		_shot_label.visible = value
	if _speed_label:
		_speed_label.visible = value
	if _top_bar:
		_top_bar.visible = value
	if _bottom_bar:
		_bottom_bar.visible = value

func _hide_race_hud() -> void:
	_hidden_race_layers.clear()
	var world := get_tree().current_scene
	if world == null:
		return
	var race_manager := world.get_node_or_null("RaceManager")
	if race_manager == null:
		return
	for child in race_manager.get_children():
		if child is CanvasLayer and child.visible:
			var layer := child as CanvasLayer
			_hidden_race_layers.append(layer)
			layer.visible = false

func _restore_race_hud() -> void:
	for layer in _hidden_race_layers:
		if is_instance_valid(layer):
			layer.visible = true
	_hidden_race_layers.clear()

func replay_snapshot() -> Dictionary:
	return {
		"active": replay_active,
		"frames": _frames.size(),
		"shot": String(_shot_modes[maxi(0, _shot_index)]) if _shot_index >= 0 else "NONE",
		"playback_speed": playback_speed
	}
