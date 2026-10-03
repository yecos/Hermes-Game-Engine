class_name EngineAudio3D
extends AudioStreamPlayer3D

var car: ArcadeCarController3D
var playback: AudioStreamGeneratorPlayback
var phase: float = 0.0
var sub_phase: float = 0.0
var intake_phase: float = 0.0
var whine_phase: float = 0.0
var sample_rate: float = 22050.0
var _smooth_rpm: float = 0.0
var _smooth_load: float = 0.0
var _shift_pop_envelope: float = 0.0
var _was_shifting: bool = false

func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = 0.12
	stream = generator
	unit_size = 18.0
	max_distance = 58.0
	volume_db = -7.5
	play()
	playback = get_stream_playback() as AudioStreamGeneratorPlayback

func _process(delta: float) -> void:
	if car == null or playback == null:
		return

	var raw_rpm := clampf(
		(car.engine_rpm - car.idle_rpm) / maxf(1.0, car.redline_rpm - car.idle_rpm),
		0.0,
		1.08
	)
	_smooth_rpm = lerpf(_smooth_rpm, raw_rpm, 1.0 - exp(-14.0 * delta))
	_smooth_load = lerpf(_smooth_load, clampf(car.throttle_input, 0.0, 1.0), 1.0 - exp(-10.0 * delta))

	if car.is_shifting and not _was_shifting:
		_shift_pop_envelope = 1.0
	_was_shifting = car.is_shifting

	var available := playback.get_frames_available()
	if available <= 0:
		return

	var shift_cut := 0.40 if car.is_shifting else 1.0
	var firing_frequency := 58.0 + _smooth_rpm * 265.0
	var sub_frequency := 29.0 + _smooth_rpm * 91.0
	var intake_frequency := 116.0 + _smooth_rpm * 410.0
	var gear_whine_frequency := 245.0 + car.speed_kmh * 4.2 + float(maxi(car.current_gear, 1)) * 48.0
	var amplitude := (0.024 + _smooth_load * 0.052 + _smooth_rpm * 0.022) * shift_cut
	var whine_gain := clampf(car.speed_kmh / 170.0, 0.0, 1.0) * 0.014

	for _i in range(available):
		phase = fmod(phase + TAU * firing_frequency / sample_rate, TAU)
		sub_phase = fmod(sub_phase + TAU * sub_frequency / sample_rate, TAU)
		intake_phase = fmod(intake_phase + TAU * intake_frequency / sample_rate, TAU)
		whine_phase = fmod(whine_phase + TAU * gear_whine_frequency / sample_rate, TAU)

		var exhaust := (
			sin(phase) * 0.47
			+ sin(phase * 2.0) * 0.21
			+ sin(phase * 3.02) * 0.095
			+ sin(sub_phase) * 0.19
		)
		var intake := (
			sin(intake_phase) * 0.055
			+ sin(intake_phase * 0.51) * 0.035
		) * (0.35 + _smooth_load * 0.65)
		var whine := sin(whine_phase) * whine_gain
		var shift_pop := sin(sub_phase * 0.47) * _shift_pop_envelope * 0.065

		var sample := tanh((exhaust * amplitude + intake + whine + shift_pop) * 1.55) * 0.78
		playback.push_frame(Vector2(sample, sample))
		_shift_pop_envelope *= 0.9981
