extends GutTest

const RADIUS: float = 2.0


func test_no_seats_for_zero_players() -> void:
	assert_eq(SeatLayout.seat_transforms(0, RADIUS).size(), 0)


func test_every_seat_is_on_the_circle_and_faces_the_centre() -> void:
	for count: int in range(1, Protocol.MAX_PLAYERS + 1):
		var seats: Array[Transform3D] = SeatLayout.seat_transforms(count, RADIUS)
		assert_eq(seats.size(), count)
		for seat: Transform3D in seats:
			assert_almost_eq(seat.origin.length(), RADIUS, 0.001)
			assert_almost_eq(seat.origin.y, 0.0, 0.001)
			var to_centre: Vector3 = -seat.origin.normalized()
			assert_almost_eq(seat.basis.z.dot(to_centre), 1.0, 0.001, "+Z faces the table centre")
			assert_almost_eq(seat.basis.y.dot(Vector3.UP), 1.0, 0.001, "seats stay upright")


func test_the_tv_side_stays_open() -> void:
	var half_arc: float = deg_to_rad(SeatLayout.DEFAULT_ARC_DEGREES / 2.0)
	for count: int in range(Protocol.MIN_PLAYERS, Protocol.MAX_PLAYERS + 1):
		for seat: Transform3D in SeatLayout.seat_transforms(count, RADIUS):
			var angle: float = absf(atan2(seat.origin.x, seat.origin.z))
			assert_true(angle < half_arc, "no seat in the open arc toward the TV (-Z)")


func test_neighbours_are_evenly_spaced() -> void:
	var seats: Array[Transform3D] = SeatLayout.seat_transforms(6, RADIUS)
	var expected: float = SeatLayout.seat_spacing(6, RADIUS)
	for i: int in range(1, seats.size()):
		assert_almost_eq(seats[i].origin.distance_to(seats[i - 1].origin), expected, 0.001)


func test_layout_is_symmetric() -> void:
	var seats: Array[Transform3D] = SeatLayout.seat_transforms(5, RADIUS)
	for i: int in seats.size():
		var mirrored: Vector3 = seats[seats.size() - 1 - i].origin * Vector3(-1, 1, 1)
		assert_almost_eq(seats[i].origin.distance_to(mirrored), 0.0, 0.001)
	assert_almost_eq(seats[2].origin.x, 0.0, 0.001, "the middle seat faces the TV head-on")


func test_a_full_table_leaves_room_for_chairs() -> void:
	assert_gt(SeatLayout.seat_spacing(Protocol.MAX_PLAYERS, RADIUS), 0.9, "8 chairs fit side by side")
