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

	var available: int = playback.get_frames_available()
	if available <= 0:
		return

	var slip_gain := clampf((car.slip_amount - 0.08) * 2.3, 0.0, 0.8)
	var offroad_gain := 0.16 if car.is_offroad and car.speed_kmh > 18.0 else 0.0

	for _i in range(available):
		noise_state = int((noise_state * 1103515245 + 12345) & 0x7fffffff)
		var noise := (float(noise_state) / 1073741824.0) - 1.0

		phase = fmod(phase + TAU * (520.0 + car.speed_kmh * 2.1) / sample_rate, TAU)
		var squeal := (sin(phase) * 0.66 + sin(phase * 1.93) * 0.34) * slip_gain * 0.06
		var gravel := noise * offroad_gain * 0.055
		var impact := noise * impact_envelope * 0.20
		var sample := squeal + gravel + impact
		playback.push_frame(Vector2(sample, sample))
		impact_envelope *= 0.9984
