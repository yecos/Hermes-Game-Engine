class_name StormAudio
extends AudioStreamPlayer

var playback: AudioStreamGeneratorPlayback
var sample_rate: float = 22050.0
var thunder_envelope: float = 0.0
var thunder_strength: float = 0.0
var phase_low: float = 0.0
var phase_rumble: float = 0.0
var noise_state: int = 421337

func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = 0.22
	stream = generator
	volume_db = -8.0
	play()
	playback = get_stream_playback() as AudioStreamGeneratorPlayback

func trigger_thunder(strength: float = 1.0) -> void:
	thunder_strength = clampf(strength, 0.15, 1.0)
	thunder_envelope = 1.0

func _process(_delta: float) -> void:
	if playback == null:
		return

	var available := playback.get_frames_available()
	if available <= 0:
		return

	for _i in range(available):
		noise_state = int((noise_state * 1664525 + 1013904223) & 0x7fffffff)
		var noise := (float(noise_state % 65536) / 32768.0) - 1.0

		phase_low = fmod(phase_low + TAU * 38.0 / sample_rate, TAU)
		phase_rumble = fmod(phase_rumble + TAU * 71.0 / sample_rate, TAU)

		var body := sin(phase_low) * 0.58 + sin(phase_rumble) * 0.22
		var crack := noise * minf(1.0, thunder_envelope * 3.2)
		var sample := (body * 0.72 + crack * 0.38) * thunder_envelope * thunder_strength
		sample = tanh(sample * 1.4) * 0.82
		playback.push_frame(Vector2(sample, sample))

		thunder_envelope *= 0.99942
		if thunder_envelope < 0.0008:
			thunder_envelope = 0.0
