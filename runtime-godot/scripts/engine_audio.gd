class_name EngineAudio3D
extends AudioStreamPlayer3D

var car: ArcadeCarController3D
var playback: AudioStreamGeneratorPlayback
var phase: float = 0.0
var sub_phase: float = 0.0
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

	var rpm_factor := clampf(
		(car.engine_rpm - car.idle_rpm) / maxf(1.0, car.redline_rpm - car.idle_rpm),
		0.0,
		1.08
	)
	var load := clampf(car.throttle_input, 0.0, 1.0)
	var shift_cut := 0.46 if car.is_shifting else 1.0
	var base_frequency := 72.0 + rpm_factor * 270.0
	var sub_frequency := 36.0 + rpm_factor * 96.0
	var amplitude := (0.025 + load * 0.050 + rpm_factor * 0.020) * shift_cut

	for _i in range(available):
		phase = fmod(phase + TAU * base_frequency / sample_rate, TAU)
		sub_phase = fmod(sub_phase + TAU * sub_frequency / sample_rate, TAU)
		var harmonic := (
			sin(phase) * 0.54
			+ sin(phase * 2.0) * 0.22
			+ sin(phase * 3.01) * 0.09
			+ sin(sub_phase) * 0.15
		)
		var sample := harmonic * amplitude
		playback.push_frame(Vector2(sample, sample))
