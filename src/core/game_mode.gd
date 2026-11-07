class_name GameMode
extends RefCounted
## The game modes a host can pick in the lobby. The lobby carries the mode (and, for
## guess mode, the identity pack) so everyone sees what the next game will be.

## The meme game: make memes, the worst one dies (docs/GAME_DESIGN.md).
const MEMES: String = "memes"
## "Who Am I?": guess your hidden identity with the search terminal (docs/GUESS_MODE.md).
const GUESS: String = "guess"
const ALL: PackedStringArray = [MEMES, GUESS]


static func is_valid(mode: Variant) -> bool:
	return typeof(mode) == TYPE_STRING and ALL.has(mode)


static func label(mode: String) -> String:
	match mode:
		GUESS:
			return "Who Am I?"
	return "Killing for the Memes"
