class_name EngineAudio3D
extends AudioStreamPlayer3D

var car: ArcadeCarController3D
var playback: AudioStreamGeneratorPlayback
var phase: float = 0.0
var sample_rate: float = 22050.0

func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = 0.12
	stream = generator
	unit_size = 18.0
	max_distance = 55.0
	volume_db = -8.0
	play()
	playback = get_stream_playback() as AudioStreamGeneratorPlayback

func _process(_delta: float) -> void:
	if car == null or playback == null:
		return

	var available := playback.get_frames_available()
	if available <= 0:
		return

	var normalized_speed := clampf(car.speed_kmh / 165.0, 0.0, 1.15)
	var rpm_factor := 0.16 + normalized_speed * 0.84
	var base_frequency := 78.0 + rpm_factor * 190.0
	var amplitude := 0.035 + normalized_speed * 0.045

	for _i in range(available):
		phase = fmod(phase + TAU * base_frequency / sample_rate, TAU)
		var harmonic := sin(phase) * 0.66 + sin(phase * 2.0) * 0.22 + sin(phase * 0.5) * 0.12
		var sample := harmonic * amplitude
		playback.push_frame(Vector2(sample, sample))
