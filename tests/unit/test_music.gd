extends GutTest
## The background music track is there, loops over its whole length, and plays at the
## settings volume.


func test_the_track_loops_over_its_whole_length() -> void:
	var track: AudioStreamWAV = Music._looping(Music.TRACK) as AudioStreamWAV
	assert_not_null(track, "the track is a WAV")
	assert_eq(track.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(track.loop_begin, 0)
	assert_almost_eq(float(track.loop_end) / track.mix_rate, track.get_length(), 0.01)
	assert_gt(track.get_length(), 60.0, "a full loop, not a jingle")


func test_volume_follows_the_setting() -> void:
	var saved: float = Settings.music_volume
	Settings.music_volume = 1.0
	assert_almost_eq(Music.target_db(), 0.0, 0.01)
	Settings.music_volume = 0.5
	assert_almost_eq(Music.target_db(), -6.02, 0.05)
	Settings.music_volume = saved
