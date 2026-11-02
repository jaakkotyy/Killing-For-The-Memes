extends GutTest

var server: ServerController


func before_each() -> void:
	server = ServerController.new(3, 4)
	watch_signals(server)


func _join(peer_id: int, player_name: String) -> void:
	server.handle_peer_connected(peer_id, 0.0)
	server.handle_join_request(peer_id, player_name, Protocol.VERSION)


func _fill_ready_lobby() -> void:
	_join(1, "Host")
	_join(2, "B")
	_join(3, "C")
	server.handle_set_ready(2, true)
	server.handle_set_ready(3, true)


func test_join_is_accepted_and_broadcast() -> void:
	_join(1, "Host")
	assert_signal_emitted(server, "join_accepted")
	assert_signal_emitted(server, "lobby_changed")
	assert_true(server.lobby.has_player(1))
	var snapshot: Dictionary = get_signal_parameters(server, "lobby_changed")[0]
	assert_eq(snapshot["players"][0]["name"], "Host")


func test_wrong_version_is_rejected() -> void:
	server.handle_join_request(2, "B", Protocol.VERSION + 1)
	assert_signal_emitted_with_parameters(server, "join_rejected", [2, Protocol.REJECT_VERSION_MISMATCH])
	assert_false(server.lobby.has_player(2))


func test_non_int_version_is_rejected() -> void:
	server.handle_join_request(2, "B", "1")
	assert_signal_emitted_with_parameters(server, "join_rejected", [2, Protocol.REJECT_VERSION_MISMATCH])


func test_non_string_name_falls_back_to_default() -> void:
	server.handle_join_request(2, {"evil": true}, Protocol.VERSION)
	assert_eq(server.lobby.get_player(2).name, LobbyState.DEFAULT_NAME)


func test_full_lobby_rejects() -> void:
	for id: int in range(1, 5):
		_join(id, "P")
	_join(9, "Late")
	assert_signal_emitted_with_parameters(server, "join_rejected", [9, Protocol.REJECT_LOBBY_FULL])


func test_started_game_rejects_new_players() -> void:
	_fill_ready_lobby()
	server.handle_start_request(1)
	_join(4, "Late")
	assert_signal_emitted_with_parameters(server, "join_rejected", [4, Protocol.REJECT_GAME_IN_PROGRESS])


func test_duplicate_join_request_is_ignored() -> void:
	_join(2, "B")
	server.handle_join_request(2, "B again", Protocol.VERSION)
	assert_signal_emit_count(server, "join_accepted", 1)
	assert_eq(server.lobby.get_player(2).name, "B")


func test_set_ready_validates_input() -> void:
	_join(2, "B")
	server.handle_set_ready(2, "yes")
	server.handle_set_ready(99, true)
	assert_false(server.lobby.get_player(2).ready)
	server.handle_set_ready(2, true)
	assert_true(server.lobby.get_player(2).ready)


func test_set_ready_without_change_does_not_broadcast() -> void:
	_join(2, "B")
	server.handle_set_ready(2, false)
	assert_signal_emit_count(server, "lobby_changed", 1, "only the join broadcast")


func test_only_host_can_start() -> void:
	_fill_ready_lobby()
	server.handle_start_request(2)
	assert_signal_not_emitted(server, "game_started")
	server.handle_start_request(1)
	assert_signal_emitted(server, "game_started")
	assert_true(server.lobby.started)


func test_cannot_start_until_guests_ready() -> void:
	_join(1, "Host")
	_join(2, "B")
	_join(3, "C")
	server.handle_set_ready(2, true)
	server.handle_start_request(1)
	assert_signal_not_emitted(server, "game_started")


func test_ready_changes_ignored_after_start() -> void:
	_fill_ready_lobby()
	server.handle_start_request(1)
	server.handle_set_ready(2, false)
	assert_true(server.lobby.get_player(2).ready)


func test_disconnect_removes_player_and_broadcasts() -> void:
	_join(2, "B")
	server.handle_peer_disconnected(2)
	assert_false(server.lobby.has_player(2))
	assert_signal_emit_count(server, "lobby_changed", 2)


func test_pending_peers_time_out() -> void:
	server.handle_peer_connected(5, 10.0)
	server.handle_peer_connected(6, 12.0)
	assert_eq(server.collect_timed_out_peers(10.0 + Protocol.JOIN_REQUEST_TIMEOUT), [5] as Array[int])
	assert_eq(server.collect_timed_out_peers(10.0 + Protocol.JOIN_REQUEST_TIMEOUT), [] as Array[int], "reported once")


func test_joined_peers_do_not_time_out() -> void:
	_join(5, "E")
	assert_eq(server.collect_timed_out_peers(1000.0), [] as Array[int])
