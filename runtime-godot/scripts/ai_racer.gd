class_name AIRacer3D
extends Node3D

@export var body_color: Color = Color("#2f7fff")
@export var progress_ratio: float = 0.0
@export var speed_mps: float = 27.0
@export var lane_offset: float = 0.0

var track: TrackSpline
var lap_count: int = 0

func _ready() -> void:
	_build_visual()

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

	global_transform = global_transform.interpolate_with(target_transform, clamp(delta * 9.0, 0.0, 1.0))

func total_progress() -> float:
	return float(lap_count) + progress_ratio

func _material(color: Color, roughness: float = 0.32) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.18
	return material

func _box(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = position
	node.material_override = material
	return node

func _build_visual() -> void:
	var paint := _material(body_color, 0.24)
	var glass := _material(Color("#1a2a3a"), 0.14)
	var dark := _material(Color("#0c0f13"), 0.5)
	var stripe := _material(Color("#f6f2e9"), 0.28)

	add_child(_box(Vector3(1.45, 0.42, 2.75), Vector3(0, 0.42, 0), paint))
	add_child(_box(Vector3(1.15, 0.38, 1.05), Vector3(0, 0.77, -0.18), glass))
	add_child(_box(Vector3(0.25, 0.05, 2.25), Vector3(0, 0.68, -0.05), stripe))
	add_child(_box(Vector3(1.48, 0.12, 0.18), Vector3(0, 0.65, 1.23), dark))

	for wheel_position in [
		Vector3(-0.82, 0.28, -0.88),
		Vector3(0.82, 0.28, -0.88),
		Vector3(-0.82, 0.28, 0.88),
		Vector3(0.82, 0.28, 0.88)
	]:
		var wheel := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.28
		cylinder.bottom_radius = 0.28
		cylinder.height = 0.22
		wheel.mesh = cylinder
		wheel.position = wheel_position
		wheel.rotation_degrees.z = 90.0
		wheel.material_override = dark
		add_child(wheel)
