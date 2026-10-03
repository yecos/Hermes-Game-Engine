class_name VehicleFxAudio3D
extends AudioStreamPlayer3D

var car: ArcadeCarController3D
var playback: AudioStreamGeneratorPlayback
var sample_rate: float = 22050.0
var phase: float = 0.0
var wind_phase: float = 0.0
var noise_state: int = 1337
var impact_envelope: float = 0.0
var shift_envelope: float = 0.0
var _was_shifting: bool = false

func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = 0.12
	stream = generator
	unit_size = 16.0
	max_distance = 50.0
	volume_db = -6.5
	play()
	playback = get_stream_playback() as AudioStreamGeneratorPlayback

func trigger_impact(strength: float) -> void:
	impact_envelope = maxf(impact_envelope, clampf(strength, 0.0, 1.0))

func _process(_delta: float) -> void:
	if car == null or playback == null:
		return

	if car.is_shifting and not _was_shifting:
		shift_envelope = 1.0
	_was_shifting = car.is_shifting

	var available := playback.get_frames_available()
	if available <= 0:
		return

	var drift_gain := clampf(car.drift_intensity, 0.0, 1.0)
	var brake_squeal := 0.30 if car.brake_input > 0.70 and car.speed_kmh > 42.0 else 0.0
	var tire_gain := maxf(drift_gain, brake_squeal)
	var offroad_gain := clampf(car.speed_kmh / 100.0, 0.0, 1.0) if car.is_offroad else 0.0
	var road_gain := clampf(car.speed_kmh / 165.0, 0.0, 1.0)
	var wind_gain := pow(road_gain, 1.55)

	for _i in range(available):
		noise_state = int((noise_state * 1103515245 + 12345) & 0x7fffffff)
		var noise := (float(noise_state) / 1073741824.0) - 1.0
		phase = fmod(phase + TAU * (455.0 + car.speed_kmh * 2.8) / sample_rate, TAU)
		wind_phase = fmod(wind_phase + TAU * (82.0 + car.speed_kmh * 0.65) / sample_rate, TAU)

		var squeal := (
			sin(phase) * 0.58
			+ sin(phase * 1.87) * 0.30
			+ sin(phase * 2.43) * 0.12
		) * tire_gain * 0.068
		var road := noise * road_gain * 0.014
		var gravel := noise * offroad_gain * 0.082
		var wind := (noise * 0.55 + sin(wind_phase) * 0.18) * wind_gain * 0.020
		var shift_clunk := noise * shift_envelope * 0.095
		var impact := noise * impact_envelope * 0.21

		var sample := squeal + road + gravel + wind + shift_clunk + impact
		playback.push_frame(Vector2(sample, sample))
		impact_envelope *= 0.9984
		shift_envelope *= 0.9968
