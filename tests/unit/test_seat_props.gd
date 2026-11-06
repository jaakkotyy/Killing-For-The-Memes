extends GutTest
## The artist's drinks on the table: every seat gets one, the same on every client.


func test_drink_choice_is_deterministic_and_in_range() -> void:
	for look: int in range(-3, 20):
		var index: int = Seat.drink_index(look)
		assert_between(index, 0, Seat.DRINK_SCENES.size() - 1)
		assert_eq(index, Seat.drink_index(look), "same seat, same drink")


func test_neighbours_get_different_drinks() -> void:
	for look: int in 8:
		assert_ne(Seat.drink_index(look), Seat.drink_index(look + 1))


func test_every_seat_has_a_drink_standing_on_the_table() -> void:
	var seat := Seat.new()
	add_child_autofree(seat)
	seat.setup(1, "Tester", 2, 0.71, 0.05)
	assert_not_null(seat.drink)
	assert_almost_eq(seat.drink.position.y, 0.71, 0.0001, "the base rests on the table top")
	var meshes: Array[Node] = seat.drink.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 0, "the drink model loaded")
	var aabb: AABB = (meshes[0] as MeshInstance3D).get_aabb()
	assert_almost_eq(aabb.position.y, 0.0, 0.001, "model origin at its base")
	assert_lt(aabb.size.y, 0.25, "real-world size, not Blender units")
