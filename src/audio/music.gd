class_name Music
extends AudioStreamPlayer
## The background music: one original loop (assets/music/forgotten_rooms.wav, composed by
## tools/make_music.py) that plays from the main menu on, across every scene change,
## because App owns it. Volume comes from Settings.music_volume; 0 keeps it silent.

const TRACK: AudioStream = preload("res://assets/music/forgotten_rooms.wav")
## Seconds to fade in from silence, so the game doesn't open with a jolt.
const FADE_IN_SECONDS: float = 3.0
const SILENT_DB: float = -60.0


func _ready() -> void:
	stream = _looping(TRACK)
	if Settings.music_volume <= 0.0:
		return
	volume_db = SILENT_DB
	play()
	print("[Music] Playing %s (%.0f s loop) at %.1f dB." % [TRACK.resource_path.get_file(), TRACK.get_length(), target_db()])
	create_tween().tween_property(self, "volume_db", target_db(), FADE_IN_SECONDS)


## The player volume for Settings.music_volume (0..1).
static func target_db() -> float:
	return linear_to_db(maxf(Settings.music_volume, 0.001))


## The track set to loop over its whole length (the file has no loop points of its own).
static func _looping(track: AudioStream) -> AudioStream:
	var wav: AudioStreamWAV = track as AudioStreamWAV
	if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(round(wav.get_length() * wav.mix_rate))
	return track
