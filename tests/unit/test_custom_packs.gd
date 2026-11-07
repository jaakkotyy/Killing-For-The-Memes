extends GutTest
## Custom identity packs ("Our friends"): found in user://identities/ on the host, sent to
## everyone with the game start, validated like any pack on arrival.

const PACK_ID: String = "zz_test_custom_pack"
const EXAMPLE: String = "res://data/identity_examples/friends.json"

var path: String = IdentityPack.USER_DIR + PACK_ID + ".json"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(IdentityPack.USER_DIR)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(EXAMPLE))
	file.close()


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	IdentityPack.forget_received()


func test_the_example_pack_is_a_valid_pack() -> void:
	var pack: IdentityPack = IdentityPack.load_file(EXAMPLE)
	assert_not_null(pack)
	assert_eq(pack.size(), 8)
	assert_eq(pack.stock_questions().size(), 5, "every stock question's filter fits its field")
	assert_eq(pack.fields().size(), 5)


func test_custom_packs_are_listed_after_the_shipped_ones() -> void:
	var ids: PackedStringArray = IdentityPack.available_ids()
	assert_true(ids.has(PACK_ID))
	assert_gt(ids.find(PACK_ID), ids.find("musicians"))
	assert_false(IdentityPack.is_shipped(PACK_ID))
	assert_true(IdentityPack.is_shipped("movies"))
	assert_true(IdentityPack.exists(PACK_ID))


func test_a_custom_pack_takes_its_id_from_the_file_name() -> void:
	var pack: IdentityPack = IdentityPack.load_pack(PACK_ID)
	assert_not_null(pack)
	assert_eq(pack.id, PACK_ID, "not the example_friends id written inside")
	assert_eq(IdentityPack.display_name(PACK_ID), "Our friends (example)")


func test_only_custom_packs_are_sent() -> void:
	assert_false(IdentityPack.custom_pack_text(PACK_ID).is_empty())
	assert_eq(IdentityPack.custom_pack_text("movies"), "", "everyone has the shipped ones")
	assert_eq(IdentityPack.custom_pack_text("../secrets"), "")
	assert_eq(IdentityPack.custom_pack_text("nope"), "")


func test_a_received_pack_is_validated_and_wins_until_forgotten() -> void:
	assert_null(IdentityPack.receive("friends_of_host", "not json"))
	assert_null(IdentityPack.receive("friends_of_host", 42))
	assert_null(IdentityPack.receive("../x", FileAccess.get_file_as_string(EXAMPLE)))
	assert_null(IdentityPack.receive("friends_of_host", JSON.stringify({"entries": []})), "an empty pack is no pack")
	assert_false(IdentityPack.exists("friends_of_host"))
	var pack: IdentityPack = IdentityPack.receive("friends_of_host", FileAccess.get_file_as_string(EXAMPLE))
	assert_not_null(pack)
	assert_eq(pack.id, "friends_of_host")
	assert_true(IdentityPack.exists("friends_of_host"))
	assert_same(IdentityPack.load_pack("friends_of_host"), pack)
	IdentityPack.forget_received()
	assert_false(IdentityPack.exists("friends_of_host"))


func test_the_host_can_pick_a_custom_pack_and_play_it() -> void:
	var server := ServerController.new(3, 4)
	for id: int in [1, 2, 3]:
		server.handle_peer_connected(id, 0.0)
		server.handle_join_request(id, "P%d" % id, Protocol.VERSION)
	server.handle_set_ready(2, true)
	server.handle_set_ready(3, true)
	server.handle_set_mode(1, GameMode.GUESS, PACK_ID)
	assert_eq(server.lobby.pack, PACK_ID)
	server.handle_start_request(1, 0.0)
	assert_not_null(server.guess_match)
	assert_eq(server.guess_match.pack.id, PACK_ID)
	assert_eq((server.snapshot_for(2, 0.0) as Dictionary)["pack"], PACK_ID)
