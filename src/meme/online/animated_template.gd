class_name AnimatedTemplate
extends RefCounted
## A decoded GIF template: one texture per frame and how long each is shown. It loops.

var textures: Array[Texture2D] = []
var delays: PackedFloat32Array = []
var duration: float = 0.0


static func from_frames(frames: Array[Image], frame_delays: PackedFloat32Array) -> AnimatedTemplate:
	var animation := AnimatedTemplate.new()
	for i: int in range(mini(frames.size(), frame_delays.size())):
		animation.textures.append(ImageTexture.create_from_image(frames[i]))
		animation.delays.append(frame_delays[i])
		animation.duration += frame_delays[i]
	return animation


func frame_count() -> int:
	return textures.size()


## The frame index shown [param seconds] after the animation started.
func frame_index_at(seconds: float) -> int:
	if textures.size() <= 1 or duration <= 0.0:
		return 0
	var t: float = fposmod(seconds, duration)
	for i: int in range(delays.size()):
		t -= delays[i]
		if t < 0.0:
			return i
	return delays.size() - 1


func frame_at(seconds: float) -> Texture2D:
	return textures[frame_index_at(seconds)] if not textures.is_empty() else null
