class_name VehicleFxAudio3D
extends AudioStreamPlayer3D

var car: ArcadeCarController3D
var playback: AudioStreamGeneratorPlayback
var sample_rate: float = 22050.0
var phase: float = 0.0
var noise_state: int = 1337
var impact_envelope: float = 0.0

func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = 0.12
	stream = generator
	unit_size = 16.0
	max_distance = 48.0
	volume_db = -7.0
	play()
	playback = get_stream_playback() as AudioStreamGeneratorPlayback

func trigger_impact(strength: float) -> void:
	impact_envelope = maxf(impact_envelope, clampf(strength, 0.0, 1.0))

func _process(_delta: float) -> void:
	if car == null or playback == null:
		return

	var available := playback.get_frames_available()
	if available <= 0:
		return

	var drift_gain := clampf(car.drift_intensity, 0.0, 1.0)
	var brake_squeal := 0.28 if car.brake_input > 0.72 and car.speed_kmh > 45.0 else 0.0
	var tire_gain := maxf(drift_gain, brake_squeal)
	var offroad_gain := 0.18 if car.is_offroad and car.speed_kmh > 18.0 else 0.0

	for _i in range(available):
		noise_state = int((noise_state * 1103515245 + 12345) & 0x7fffffff)
		var noise := (float(noise_state) / 1073741824.0) - 1.0
		phase = fmod(phase + TAU * (470.0 + car.speed_kmh * 2.6) / sample_rate, TAU)
		var squeal := (
			sin(phase) * 0.62
			+ sin(phase * 1.91) * 0.38
		) * tire_gain * 0.070
		var gravel := noise * offroad_gain * 0.060
		var impact := noise * impact_envelope * 0.20
		var sample := squeal + gravel + impact
		playback.push_frame(Vector2(sample, sample))
		impact_envelope *= 0.9984
