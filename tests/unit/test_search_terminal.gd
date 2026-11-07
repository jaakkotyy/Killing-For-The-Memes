extends GutTest
## Guess mode's CRT terminal (SearchTerminal), fed by views of a real GuessMatch: filters,
## crossing out, clues as filters, asking, answering and guessing only when allowed.

const Phase := GuessMatch.Phase
const YES: int = GuessMatch.Answer.YES
const NO: int = GuessMatch.Answer.NO

var pack: IdentityPack
var game: GuessMatch
var terminal: SearchTerminal
var now: float = 0.0


func before_each() -> void:
	var entries: Array = []
	for i: int in range(12):
		entries.append({"id": "E%d" % i, "name": "Entry %d" % i, "fame": 100 - i,
			"fields": {"kind": "band" if i % 2 == 0 else "solo artist", "born": 1950 + i * 5,
				"alive": i < 6, "genres": ["rock"] if i % 3 == 0 else ["pop"]}})
	pack = IdentityPack.from_dict({
		"id": "test", "name": "Test",
		"fields": [{"id": "kind", "type": "enum"}, {"id": "born", "type": "year"},
			{"id": "alive", "type": "bool"}, {"id": "genres", "type": "tags"}],
		"questions": [{"text": "Am I a band?", "filter": {"field": "kind", "op": "is", "value": "band"}}],
		"entries": entries,
	})
	var players: Array[LobbyPlayer] = []
	for i: int in range(3):
		players.append(LobbyPlayer.new(i + 1, "P%d" % (i + 1), i))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	game = GuessMatch.new(GameConfig.new(), players, pack, rng)
	now = 0.0
	game.start(now)
	terminal = SearchTerminal.new()
	terminal.set_pack(pack)
	add_child_autofree(terminal)


func _view(viewer: int) -> GuessView:
	return GuessView.from_snapshot(game.to_snapshot(now, viewer), now)


func _to_turns() -> void:
	now += GameConfig.new().deal_duration + 0.1
	game.update(now)
	assert_eq(game.phase, Phase.ASK)


func test_results_start_best_known_first() -> void:
	assert_eq(terminal.open_count(), 12)
	assert_eq(terminal.result_ids()[0], "E0")
	assert_eq(terminal.result_ids()[11], "E11")


func test_filters_from_the_field_builder() -> void:
	terminal.select_field("kind")
	# Values are listed most common first; both kinds have six.
	terminal.add_built_filter(0, "is")
	assert_eq(terminal.open_count(), 6)
	terminal.remove_filter(0)
	terminal.select_field("born")
	terminal.add_built_filter(0, "decade")  # the 1950s: 1950 and 1955
	assert_eq(terminal.open_count(), 2)
	terminal.add_built_filter(0, "decade")
	assert_eq(terminal.query.filters.size(), 1, "the same filter twice is one filter")
	terminal.remove_filter(0)
	terminal.add_built_filter(0, "not_decade")
	assert_eq(terminal.open_count(), 10)
	terminal.remove_filter(0)
	terminal.select_field("alive")
	terminal.add_built_filter(0, "is")  # "yes" comes first
	assert_eq(terminal.open_count(), 6)
	terminal.remove_filter(0)
	terminal.select_field("genres")
	terminal.add_built_filter(1, "has")  # rock (4) after pop (8)
	assert_eq(terminal.open_count(), 4)
	terminal.add_built_filter(99, "has")
	assert_eq(terminal.query.filters.size(), 1, "rows that don't exist are ignored")


func test_name_search_and_crossing_out() -> void:
	terminal.set_search_text("entry 1")
	assert_eq(terminal.open_count(), 3, "Entry 1, 10 and 11")
	terminal.set_search_text("")
	terminal.toggle_struck("E0")
	assert_eq(terminal.open_count(), 11)
	assert_eq(terminal.result_ids()[-1], "E0", "crossed out ones sink to the bottom")
	terminal.toggle_struck("E0")
	assert_eq(terminal.result_ids()[0], "E0")


func test_other_players_identities_are_crossed_out() -> void:
	terminal.apply_view(_view(1), 1)
	assert_true(terminal.query.is_struck(game.identity_of(2)))
	assert_true(terminal.query.is_struck(game.identity_of(3)))
	assert_false(terminal.query.is_struck(game.identity_of(1)), "the terminal can't know your own")
	assert_eq(terminal.open_count(), 10)


func test_asking_only_on_your_turn() -> void:
	_to_turns()
	var asker: int = game.asker_id()
	var other: int = 1 if asker != 1 else 2
	watch_signals(terminal)
	terminal.apply_view(_view(other), other)
	terminal.ask_own("Am I tall?")
	terminal.ask_stock(0)
	assert_signal_not_emitted(terminal, "ask_requested")
	assert_signal_not_emitted(terminal, "stock_requested")

	terminal = SearchTerminal.new()
	terminal.set_pack(pack)
	add_child_autofree(terminal)
	watch_signals(terminal)
	terminal.apply_view(_view(asker), asker)
	assert_eq(terminal.get_pane(), SearchTerminal.Pane.ASK, "your turn opens the ASK pane")
	terminal.ask_own("   ")
	assert_signal_not_emitted(terminal, "ask_requested", "blank questions aren't sent")
	terminal.ask_own("Am I tall?")
	assert_signal_emitted_with_parameters(terminal, "ask_requested", ["Am I tall?"])
	terminal.ask_stock(7)
	assert_signal_not_emitted(terminal, "stock_requested", "no such stock question")
	terminal.ask_stock(0)
	assert_signal_emitted_with_parameters(terminal, "stock_requested", [0])


func test_answer_bar_while_someone_elses_question_is_up() -> void:
	_to_turns()
	var asker: int = game.asker_id()
	var other: int = 1 if asker != 1 else 2
	game.ask(asker, {"stock": 0}, now)
	watch_signals(terminal)
	terminal.apply_view(_view(asker), asker)
	terminal.answer(YES)
	assert_signal_not_emitted(terminal, "answer_requested", "the asker doesn't answer")
	terminal.apply_view(_view(other), other)
	var bar: Button = _find_button(terminal, "YES")
	assert_true(bar.is_visible_in_tree(), "the answer bar shows")
	terminal.answer(NO)
	assert_signal_emitted_with_parameters(terminal, "answer_requested", [NO])


func test_clear_stock_answers_become_filters_on_request() -> void:
	_to_turns()
	var asker: int = game.asker_id()
	game.ask(asker, {"stock": 0}, now)
	for id: int in [1, 2, 3]:
		if id != asker:
			game.answer(id, YES, now)
	assert_eq(game.phase, Phase.RESULT)
	terminal.apply_view(_view(asker), asker)
	assert_eq(terminal.query.filters.size(), 0, "never applied by itself")
	terminal.apply_clue(0)
	assert_eq(terminal.query.filters.size(), 1)
	assert_eq(terminal.query.filters[0].describe(), "kind is band")
	terminal.apply_clue(5)
	assert_eq(terminal.query.filters.size(), 1)


func test_guessing_and_a_wrong_guess_crosses_it_out() -> void:
	watch_signals(terminal)
	terminal.apply_view(_view(1), 1)
	var wrong: String = "E0" if game.identity_of(1) != "E0" else "E1"
	terminal.select_entry(wrong)
	terminal.guess_selected()
	assert_signal_not_emitted(terminal, "guess_requested", "not during the deal")
	_to_turns()
	terminal.apply_view(_view(1), 1)
	terminal.guess_selected()
	assert_signal_emitted_with_parameters(terminal, "guess_requested", [wrong])
	game.guess(1, wrong, now)
	terminal.apply_view(_view(1), 1)
	assert_true(terminal.query.is_struck(wrong))


func test_a_new_round_starts_a_new_search() -> void:
	terminal.apply_view(_view(1), 1)
	terminal.select_field("kind")
	terminal.add_built_filter(0, "is")
	while game.round_number < 2 and now < 2000.0:
		now += 1.0
		game.update(now)
	terminal.apply_view(_view(1), 1)
	assert_eq(terminal.query.filters.size(), 0)


func _find_button(root: Node, text: String) -> Button:
	for node: Node in root.find_children("*", "Button", true, false):
		if (node as Button).text == text:
			return node
	return null
