class_name RaceManager3D
extends Node

@export var total_laps: int = 3
@export var ceremony_enabled: bool = true
@export var full_formation_lap: bool = false
@export var formation_duration: float = 4.8
@export var formation_speed_mps: float = 15.0
@export var full_formation_speed_mps: float = 22.0
@export var pre_grid_hold: float = 0.9
@export var start_light_interval: float = 0.62
@export var lights_out_hold: float = 0.95

signal race_phase_changed(phase: String)
signal race_flag_changed(flag: String)

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

var race_phase: String = "formation"
var flag_state: String = "yellow"
var start_lights_on: int = 0
var race_started: bool = false

var _last_ratio: float = 0.0
var _lap_started_at: int = 0
var _sector_started_at: int = 0
var _last_sector: int = 1

var _phase_elapsed: float = 0.0
var _grid_transforms: Dictionary = {}
var _ai_original_speed_mps: Dictionary = {}
var _ceremony_initialized: bool = false
var _formation_last_ratio: float = 0.0
var _formation_laps: int = 0

var _position_label: Label
var _lap_label: Label
var _speed_label: Label
var _gear_label: Label
var _rpm_label: Label
var _drift_label: Label
var _status_label: Label
var _timing_label: Label
var _resources_label: Label
var _rpm_bar: ProgressBar
var _flag_label: Label
var _start_panel: Panel
var _start_light_nodes: Array[ColorRect] = []

func _ready() -> void:
	_build_hud()

	if player and track:
		_last_ratio = track.get_progress_ratio(player.global_position)
		current_sector = track.get_sector_index(player.global_position)
		_last_sector = current_sector

	_lap_started_at = Time.get_ticks_msec()
	_sector_started_at = _lap_started_at

	if ceremony_enabled and player and track:
		begin_race_ceremony()
	else:
		_enter_race()

func _process(delta: float) -> void:
	if player == null or track == null:
		return
	if player.replay_mode:
		return

	if race_phase != "race" and race_phase != "finished":
		_update_ceremony(delta)
		_update_hud_static()
		return

	_update_race_progress()
	_update_hud_static()

func begin_race_ceremony() -> void:
	if player == null or track == null:
		return

	_grid_transforms.clear()
	_ai_original_speed_mps.clear()
	_grid_transforms[player.get_instance_id()] = player.global_transform

	for ai in ai_racers:
		_grid_transforms[ai.get_instance_id()] = ai.global_transform
		_ai_original_speed_mps[ai.get_instance_id()] = ai.speed_mps

	var formation_speed := full_formation_speed_mps if full_formation_lap else formation_speed_mps
	player.reset_dynamics()
	player.input_enabled = false
	player.autopilot_enabled = true
	player.autopilot_target_speed = formation_speed

	for ai in ai_racers:
		ai.reset_dynamics()
		ai.autopilot_enabled = true
		ai.speed_mps = formation_speed * 0.94
		ai.autopilot_target_speed = formation_speed * 0.94

	race_started = false
	player_lap = 0
	current_lap_time = 0.0
	start_lights_on = 0
	_phase_elapsed = 0.0
	_formation_laps = 0
	_formation_last_ratio = track.get_progress_ratio(player.global_position)
	_ceremony_initialized = true
	_set_phase("formation")
	set_flag_state("yellow")
	_set_world_start_lights(0, false)
	_update_start_light_hud()

func _update_ceremony(delta: float) -> void:
	if not _ceremony_initialized:
		return

	_phase_elapsed += delta

	match race_phase:
		"formation":
			var formation_ratio := track.get_progress_ratio(player.global_position)
			if _formation_last_ratio > 0.88 and formation_ratio < 0.12:
				_formation_laps += 1
			_formation_last_ratio = formation_ratio
			var formation_complete := (
				_formation_laps >= 1 if full_formation_lap
				else _phase_elapsed >= formation_duration
			)
			if formation_complete:
				_restore_grid()
				_phase_elapsed = 0.0
				_set_phase("grid")
				set_flag_state("yellow")
		"grid":
			if _phase_elapsed >= pre_grid_hold:
				_phase_elapsed = 0.0
				start_lights_on = 0
				_set_phase("lights")
				_set_world_start_lights(0, false)
				_update_start_light_hud()
		"lights":
			var target_count := mini(5, int(floor(_phase_elapsed / start_light_interval)) + 1)
			if target_count != start_lights_on:
				start_lights_on = target_count
				_set_world_start_lights(start_lights_on, false)
				_update_start_light_hud()

			var all_lights_time := start_light_interval * 5.0
			if start_lights_on >= 5 and _phase_elapsed >= all_lights_time + lights_out_hold:
				_enter_race()

func _restore_grid() -> void:
	if player and _grid_transforms.has(player.get_instance_id()):
		player.global_transform = _grid_transforms[player.get_instance_id()]
		player.reset_dynamics()
		player.autopilot_enabled = false
		player.input_enabled = false

	for ai in ai_racers:
		if _grid_transforms.has(ai.get_instance_id()):
			ai.global_transform = _grid_transforms[ai.get_instance_id()]
		ai.reset_dynamics()
		ai.autopilot_enabled = false

func _enter_race() -> void:
	_phase_elapsed = 0.0
	start_lights_on = 0
	_set_world_start_lights(0, false)
	_update_start_light_hud()

	if player:
		player.reset_dynamics()
		player.autopilot_enabled = false
		player.input_enabled = true

	for ai in ai_racers:
		if _ai_original_speed_mps.has(ai.get_instance_id()):
			ai.speed_mps = float(_ai_original_speed_mps[ai.get_instance_id()])
		ai.autopilot_enabled = true

	race_started = true
	_ceremony_initialized = true
	_set_phase("race")
	set_flag_state("green")
	_reset_timing_only()

func _update_race_progress() -> void:
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

	if player_lap >= total_laps and race_phase != "finished":
		_set_phase("finished")
		set_flag_state("checkered")

func _update_hud_static() -> void:
	if player == null:
		return

	_position_label.text = _ordinal(current_position)
	_lap_label.text = "LAP %d/%d · S%d" % [min(player_lap + 1, total_laps), total_laps, current_sector]
	_speed_label.text = "%03d km/h" % int(player.speed_kmh)
	_gear_label.text = player.gear_display()
	_rpm_label.text = "%04d RPM%s" % [
		int(player.engine_rpm),
		"  SHIFT" if player.is_shifting else ""
	]
	if _rpm_bar:
		_rpm_bar.max_value = player.redline_rpm
		_rpm_bar.value = player.engine_rpm
	_drift_label.text = "SLIP %4.1f°   DRIFT %3d%%" % [
		absf(player.vehicle_slip_angle_deg),
		int(player.drift_intensity * 100.0)
	]

	var best_text := "--:--.---"
	if best_lap_time > 0.0:
		best_text = _format_time(best_lap_time)

	_timing_label.text = "LAP %s\nBEST %s\nSECTOR %.3fs" % [
		_format_time(current_lap_time),
		best_text,
		last_sector_time
	]

	_resources_label.text = "FUEL %3d%%   TIRES %3d%%   DMG %3d%%" % [
		int((player.fuel_liters / maxf(0.001, player.fuel_capacity_liters)) * 100.0),
		int(player.tire_health * 100.0),
		int(player.damage * 100.0)
	]

	match race_phase:
		"formation":
			_status_label.text = "FORMATION LAP"
		"grid":
			_status_label.text = "GRID · HOLD"
		"lights":
			_status_label.text = "LIGHTS"
		"finished":
			_status_label.text = "FINISH · " + _ordinal(current_position)
		_:
			if player.pit_servicing:
				_status_label.text = "PIT SERVICE"
			elif player.in_pit_lane and player.speed_kmh < 18.0:
				_status_label.text = "HOLD E FOR PIT"
			elif player.is_offroad:
				_status_label.text = "OFF ROAD"
			else:
				_status_label.text = ""

	if _flag_label:
		_flag_label.text = flag_state.to_upper()
		_flag_label.modulate = _flag_color(flag_state)

func set_flag_state(state: String) -> bool:
	var normalized := state.to_lower()
	if not normalized in ["green", "yellow", "red", "checkered"]:
		return false
	flag_state = normalized
	_set_world_flag(flag_state)
	race_flag_changed.emit(flag_state)
	return true

func _set_phase(new_phase: String) -> void:
	if race_phase == new_phase:
		return
	race_phase = new_phase
	if _start_panel:
		_start_panel.visible = race_phase in ["formation", "grid", "lights"]
	race_phase_changed.emit(race_phase)

func _set_world_start_lights(count: int, green: bool) -> void:
	var world := get_tree().current_scene
	if world and world.has_method("set_start_lights"):
		world.call("set_start_lights", count, green)

func _set_world_flag(state: String) -> void:
	var world := get_tree().current_scene
	if world and world.has_method("set_race_flag"):
		world.call("set_race_flag", state)

func _flag_color(state: String) -> Color:
	match state:
		"green":
			return Color("#45e271")
		"yellow":
			return Color("#ffd84a")
		"red":
			return Color("#ff4252")
		"checkered":
			return Color.WHITE
	return Color.WHITE

func _update_start_light_hud() -> void:
	for i in range(_start_light_nodes.size()):
		var light := _start_light_nodes[i]
		light.color = Color("#f13b48") if i < start_lights_on else Color("#301216")

func reset_session() -> void:
	player_lap = 0
	current_position = 1
	current_sector = 1
	best_lap_time = 0.0
	current_lap_time = 0.0
	last_lap_time = 0.0
	last_sector_time = 0.0
	_reset_timing_only()

func restart_race_ceremony() -> void:
	reset_session()
	begin_race_ceremony()

func _reset_timing_only() -> void:
	_last_ratio = track.get_progress_ratio(player.global_position) if track and player else 0.0
	_last_sector = track.get_sector_index(player.global_position) if track and player else 1
	current_sector = _last_sector
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
		"last_sector_time": snappedf(last_sector_time, 0.001),
		"race_phase": race_phase,
		"flag_state": flag_state,
		"start_lights": start_lights_on
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
	label.add_theme_color_override("font_color", Color("#f5f4ef"))
	label.add_theme_color_override("font_shadow_color", Color(0.01, 0.015, 0.02, 0.82))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _make_hud_panel(position_value: Vector2, size_value: Vector2, accent: Color) -> Panel:
	var panel := Panel.new()
	panel.position = position_value
	panel.size = size_value
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.045, 0.76)
	style.border_color = Color(0.62, 0.68, 0.72, 0.24)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)

	var accent_bar := ColorRect.new()
	accent_bar.color = accent
	accent_bar.position = Vector2(0, 0)
	accent_bar.size = Vector2(4, size_value.y)
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(accent_bar)
	return panel

func _make_rpm_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 7600.0
	bar.value = 1050.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.12, 0.14, 0.95)
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#e83d48")
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	var left_panel := _make_hud_panel(Vector2(18, 18), Vector2(286, 184), Color("#e83d48"))
	left_panel.name = "RaceInfoPanel"
	layer.add_child(left_panel)
	var right_panel := _make_hud_panel(Vector2(1000, 18), Vector2(262, 210), Color("#2f7fff"))
	right_panel.name = "VehicleInfoPanel"
	layer.add_child(right_panel)
	var drift_panel := _make_hud_panel(Vector2(18, 650), Vector2(220, 46), Color("#f0c541"))
	drift_panel.name = "DriftPanel"
	layer.add_child(drift_panel)
	var controls_panel := _make_hud_panel(Vector2(265, 664), Vector2(750, 34), Color("#58636c"))
	controls_panel.name = "ControlsPanel"
	layer.add_child(controls_panel)

	var start_panel := _make_hud_panel(Vector2(493, 78), Vector2(294, 76), Color("#e83d48"))
	start_panel.name = "StartSequencePanel"
	layer.add_child(start_panel)
	_start_panel = start_panel
	for i in range(5):
		var light := ColorRect.new()
		light.name = "StartHUDLight%d" % i
		light.position = Vector2(24.0 + float(i) * 51.0, 20.0)
		light.size = Vector2(34.0, 34.0)
		light.color = Color("#301216")
		start_panel.add_child(light)
		_start_light_nodes.append(light)

	_flag_label = _make_label("YELLOW", 14)
	_flag_label.name = "RaceFlagLabel"
	_flag_label.position = Vector2(595, 158)
	_flag_label.size = Vector2(90, 24)
	_flag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_flag_label)

	_position_label = _make_label("1st", 44)
	_position_label.position = Vector2(34, 24)
	layer.add_child(_position_label)

	_lap_label = _make_label("LAP 1/%d · S1" % total_laps, 18)
	_lap_label.position = Vector2(38, 78)
	layer.add_child(_lap_label)

	_timing_label = _make_label("LAP 0:00.000\nBEST --:--.---\nSECTOR 0.000s", 14)
	_timing_label.position = Vector2(38, 108)
	layer.add_child(_timing_label)

	_speed_label = _make_label("000 km/h", 30)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.position = Vector2(1018, 26)
	_speed_label.size = Vector2(214, 40)
	layer.add_child(_speed_label)

	_gear_label = _make_label("1", 58)
	_gear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear_label.position = Vector2(1138, 64)
	_gear_label.size = Vector2(92, 70)
	layer.add_child(_gear_label)

	_rpm_label = _make_label("1050 RPM", 13)
	_rpm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rpm_label.position = Vector2(1020, 132)
	_rpm_label.size = Vector2(210, 22)
	layer.add_child(_rpm_label)

	_rpm_bar = _make_rpm_bar()
	_rpm_bar.name = "RPMBar"
	_rpm_bar.position = Vector2(1022, 158)
	_rpm_bar.size = Vector2(208, 10)
	layer.add_child(_rpm_bar)

	_resources_label = _make_label("FUEL 100%   TIRES 100%   DMG 0%", 13)
	_resources_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_resources_label.position = Vector2(1018, 182)
	_resources_label.size = Vector2(214, 28)
	layer.add_child(_resources_label)

	_drift_label = _make_label("SLIP 0.0°   DRIFT 0%", 14)
	_drift_label.position = Vector2(32, 661)
	_drift_label.size = Vector2(196, 24)
	layer.add_child(_drift_label)

	var controls := _make_label("W/S DRIVE  ·  A/D STEER  ·  SPACE BOOST  ·  E PIT  ·  R REPLAY  ·  T TIME  ·  Y RAIN", 12)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.position = Vector2(279, 671)
	controls.size = Vector2(722, 20)
	layer.add_child(controls)

	_status_label = _make_label("", 30)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(440, 24)
	_status_label.size = Vector2(400, 44)
	layer.add_child(_status_label)

	_update_start_light_hud()
