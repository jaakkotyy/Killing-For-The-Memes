extends GutTest
## Guess mode in the 3D room: a preview room plays a local guess game through the real
## GuessPresenter, GuessHud, placards and the SearchTerminal on the CRT.

const ROOM_SCENE: PackedScene = preload("res://src/world/room/room.tscn")

var room: GameRoom
var preview: PreviewGuessGame


func before_each() -> void:
	# Portraits would come from the internet.
	TemplateImageCache.offline = true
	room = ROOM_SCENE.instantiate()
	room.preview_players = 3
	room.preview_mode = GameMode.GUESS
	room.demo_enabled = false
	add_child_autofree(room)
	await wait_physics_frames(2)
	preview = room.get_preview_game()


func after_each() -> void:
	TemplateImageCache.offline = false


func _presenter() -> GuessPresenter:
	for child: Node in room.get_children():
		if child is GuessPresenter:
			return child
	return null


func _game() -> GuessMatch:
	return preview.game


## Steps the clock until it is the local player's turn to ask.
func _until_my_turn() -> void:
	preview.advance(GameConfig.new().deal_duration + 0.1)
	var waited: float = 0.0
	while not (_game().phase == GuessMatch.Phase.ASK and _game().asker_id() == PreviewGuessGame.LOCAL_ID) and waited < 200.0:
		preview.advance(1.0)
		waited += 1.0
	assert_eq(_game().asker_id(), PreviewGuessGame.LOCAL_ID)


func test_guess_mode_gets_the_terminal_instead_of_the_meme_editor() -> void:
	assert_not_null(preview)
	assert_null(room.get_station())
	assert_not_null(room.get_search_station())
	assert_not_null(room.get_guess_hud())
	assert_null(room.get_match_hud())
	assert_eq(room.get_search_station().terminal.pack, preview.guess_pack())


func test_placards_hide_only_your_own_identity() -> void:
	var pack: IdentityPack = preview.guess_pack()
	assert_eq(room.get_seat(1).placard.get_label_text(), "???")
	for id: int in [2, 3]:
		var placard: IdentityPlacard = room.get_seat(id).placard
		assert_eq(placard.state, IdentityPlacard.State.KNOWN)
		assert_eq(placard.get_label_text(), pack.get_entry(_game().identity_of(id)).name)
	assert_true(room.get_search_station().terminal.query.is_struck(_game().identity_of(2)),
		"the terminal crosses out what the placards show")


func test_a_turn_through_the_terminal_reaches_the_tv_and_hud() -> void:
	_until_my_turn()
	var terminal: SearchTerminal = room.get_search_station().terminal
	assert_eq(terminal.get_pane(), SearchTerminal.Pane.ASK)
	assert_eq(room.get_tv().get_caption()[0], "YOUR TURN")
	terminal.ask_stock(0)
	assert_eq(_game().phase, GuessMatch.Phase.ANSWER)
	var question: String = preview.guess_pack().stock_question(0).text
	assert_eq(room.get_tv().get_caption()[0], question, "the question is on the TV")
	assert_string_contains(room.get_guess_hud().get_question_text(), question)
	var sounds: PackedStringArray = _presenter().get_sfx().history
	assert_true(sounds.has("deal"))
	assert_true(sounds.has("your_turn"))
	assert_eq(sounds[-1], "question")


func test_solving_turns_your_placard_green() -> void:
	preview.advance(GameConfig.new().deal_duration + 0.1)
	var terminal: SearchTerminal = room.get_search_station().terminal
	terminal.select_entry(_game().identity_of(1))
	terminal.guess_selected()
	assert_true(_game().is_solved(1))
	var placard: IdentityPlacard = room.get_seat(1).placard
	assert_eq(placard.state, IdentityPlacard.State.SOLVED)
	assert_eq(_presenter().get_sfx().history[-1], "solved")
	assert_eq(placard.get_label_text(), preview.guess_pack().get_entry(_game().identity_of(1)).name)


func test_the_terminal_opens_on_the_crt() -> void:
	var station: SearchStation = room.get_search_station()
	station.open(true)
	await wait_physics_frames(2)
	assert_true(station.zoom.is_zoomed_in())
	assert_not_null(station.terminal.find_child("GuessButton", true, false))
