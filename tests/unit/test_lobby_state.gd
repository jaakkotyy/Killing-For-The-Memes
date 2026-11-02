extends GutTest

var lobby: LobbyState


func before_each() -> void:
	lobby = LobbyState.new(4)


func test_add_player_assigns_lowest_free_seat() -> void:
	lobby.add_player(1, "Host")
	lobby.add_player(2, "B")
	lobby.add_player(3, "C")
	lobby.remove_player(2)
	var player: LobbyPlayer = lobby.add_player(4, "D")
	assert_eq(player.seat, 1, "seat freed by player 2 is reused")


func test_get_players_is_sorted_by_seat() -> void:
	lobby.add_player(1, "Host")
	lobby.add_player(7, "B")
	lobby.add_player(3, "C")
	lobby.remove_player(1)
	lobby.add_player(9, "D")
	var seats: Array[int] = []
	for player: LobbyPlayer in lobby.get_players():
		seats.append(player.seat)
	assert_eq(seats, [0, 1, 2] as Array[int])


func test_is_full() -> void:
	for id: int in range(1, 5):
		assert_false(lobby.is_full())
		lobby.add_player(id, "P")
	assert_true(lobby.is_full())


func test_sanitize_name() -> void:
	assert_eq(LobbyState.sanitize_name("  Alice  "), "Alice")
	assert_eq(LobbyState.sanitize_name("Bob\n\t\u0007"), "Bob")
	assert_eq(LobbyState.sanitize_name("Too    many   spaces"), "Too many spaces")
	assert_eq(LobbyState.sanitize_name("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), "ABCDEFGHIJKLMNOP")
	assert_eq(LobbyState.sanitize_name(""), LobbyState.DEFAULT_NAME)
	assert_eq(LobbyState.sanitize_name("\n\n"), LobbyState.DEFAULT_NAME)


func test_duplicate_names_get_numbered_case_insensitively() -> void:
	lobby.add_player(1, "Alice")
	assert_eq(lobby.add_player(2, "alice").name, "alice 2")
	assert_eq(lobby.add_player(3, "ALICE").name, "ALICE 3")


func test_numbered_name_stays_within_max_length() -> void:
	lobby.add_player(1, "ABCDEFGHIJKLMNOP")
	var second: LobbyPlayer = lobby.add_player(2, "ABCDEFGHIJKLMNOP")
	assert_eq(second.name, "ABCDEFGHIJKLMN 2")
	assert_lte(second.name.length(), LobbyState.NAME_MAX_LENGTH)


func test_can_start_requires_min_players_and_ready_guests() -> void:
	lobby.add_player(1, "Host")
	lobby.add_player(2, "B")
	assert_false(lobby.can_start(3), "not enough players")
	lobby.add_player(3, "C")
	assert_false(lobby.can_start(3), "guests not ready")
	lobby.set_ready(2, true)
	lobby.set_ready(3, true)
	assert_true(lobby.can_start(3), "host does not need to ready up")
	lobby.started = true
	assert_false(lobby.can_start(3), "cannot start twice")


func test_snapshot_roundtrip() -> void:
	lobby.add_player(1, "Host")
	lobby.add_player(5, "Guest")
	lobby.set_ready(5, true)
	lobby.started = true
	var copy: LobbyState = LobbyState.from_dict(lobby.to_dict())
	assert_eq(copy.to_dict(), lobby.to_dict())
	assert_eq(copy.get_player(5).name, "Guest")
	assert_true(copy.get_player(5).ready)
	assert_true(copy.started)
	assert_eq(copy.max_players, 4)
