class_name SeatLayout
extends RefCounted
## Places the players' seats around the round table.
##
## Seats are spread evenly over an arc centred on +Z, which leaves the side facing the wall TV
## (-Z) open for the host and keeps the TV in everyone's sight. Pure math, unit-tested.

## Default arc the seats occupy, in degrees. Leaves 110° open toward the TV.
const DEFAULT_ARC_DEGREES: float = 250.0


## One floor-level transform per seat, ordered left to right as seen from the TV.
## The basis +Z axis points at the table centre (models exported from Blender face +Z).
static func seat_transforms(count: int, radius: float, arc_degrees: float = DEFAULT_ARC_DEGREES) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	if count <= 0:
		return result
	var arc: float = deg_to_rad(clampf(arc_degrees, 0.0, 360.0))
	var step: float = arc / float(count)
	for i: int in count:
		# Each seat sits in the middle of its own slice of the arc.
		var angle: float = -arc / 2.0 + (float(i) + 0.5) * step
		var origin := Vector3(sin(angle) * radius, 0.0, cos(angle) * radius)
		var facing := Basis.looking_at(-origin.normalized(), Vector3.UP, true)
		result.append(Transform3D(facing, origin))
	return result


## Distance between neighbouring seats along the table edge, for checking chairs fit.
static func seat_spacing(count: int, radius: float, arc_degrees: float = DEFAULT_ARC_DEGREES) -> float:
	if count <= 1:
		return INF
	var step: float = deg_to_rad(clampf(arc_degrees, 0.0, 360.0)) / float(count)
	return 2.0 * radius * sin(step / 2.0)
