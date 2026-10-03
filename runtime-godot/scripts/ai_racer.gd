class_name AIRacer3D
extends Node3D

@export var body_color: Color = Color("#2f7fff")
@export var progress_ratio: float = 0.0
@export var speed_mps: float = 27.0
@export var lane_offset: float = 0.0

var track: TrackSpline
var lap_count: int = 0
var _visual: Node3D
var _wheel_nodes: Array[Node3D] = []

func _ready() -> void:
	var built: Dictionary = RaceCarVisual3D.build(self, body_color, Color("#f6f4ed"))
	_visual = built.root as Node3D
	for wheel in built.wheels:
		_wheel_nodes.append(wheel as Node3D)

func _process(delta: float) -> void:
	if track == null or track.get_length() <= 0.0:
		return

	var previous := progress_ratio
	progress_ratio = fposmod(progress_ratio + (speed_mps / track.get_length()) * delta, 1.0)

	if previous > 0.88 and progress_ratio < 0.12:
		lap_count += 1

	var target_transform := track.get_world_transform_at_ratio(progress_ratio)
	target_transform.origin += target_transform.basis.x * lane_offset
	target_transform.origin += Vector3.UP * 0.48

	global_transform = global_transform.interpolate_with(target_transform, clampf(delta * 9.0, 0.0, 1.0))

	for wheel in _wheel_nodes:
		wheel.rotation.x += speed_mps * delta * 1.7

	if _visual:
		var corner_roll := sin(progress_ratio * TAU * 2.0 + lane_offset) * 0.025
		_visual.rotation.z = lerpf(_visual.rotation.z, corner_roll, 1.0 - exp(-5.0 * delta))

func total_progress() -> float:
	return float(lap_count) + progress_ratio
