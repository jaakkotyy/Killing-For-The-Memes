class_name WristChain
extends Node3D
## A sagging chain of torus links from a moving point (a wrist cuff) to a fixed anchor
## bolted to the table. Links are re-laid every frame so the chain follows the animation.

@export var link_length: float = 0.034
@export var link_radius: float = 0.012
@export var sag: float = 0.06

var _start: Node3D
var _anchor: Vector3
var _links: Array[MeshInstance3D] = []
var _link_mesh: TorusMesh
var _material: StandardMaterial3D


## `start` is followed every frame; `anchor` is a fixed global position.
func setup(start: Node3D, anchor: Vector3, material: StandardMaterial3D) -> void:
	_start = start
	_anchor = anchor
	_material = material
	_link_mesh = TorusMesh.new()
	_link_mesh.inner_radius = link_radius * 0.55
	_link_mesh.outer_radius = link_radius
	_link_mesh.rings = 10
	_link_mesh.ring_segments = 6
	top_level = true
	global_transform = Transform3D.IDENTITY


func _process(_delta: float) -> void:
	if _start == null or not is_instance_valid(_start):
		return
	var from: Vector3 = _start.global_position
	var span: float = from.distance_to(_anchor)
	var count: int = maxi(2, ceili(span / link_length))
	_ensure_links(count)
	var previous: Vector3 = from
	for i: int in count:
		var t: float = float(i + 1) / float(count)
		var point: Vector3 = from.lerp(_anchor, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var mid: Vector3 = (previous + point) / 2.0
		var along: Vector3 = point - previous
		if along.length_squared() > 1e-8:
			# Stretch the torus along the chain and alternate the link planes, like real chain.
			var forward: Vector3 = along.normalized()
			var side: Vector3 = forward.cross(Vector3.UP)
			if side.length_squared() < 1e-6:
				side = Vector3.RIGHT
			side = side.normalized()
			var up: Vector3 = side.cross(forward)
			var basis := Basis(forward, side if i % 2 == 0 else up, up if i % 2 == 0 else -side)
			basis = basis.scaled_local(Vector3(1.6, 1.0, 1.0))
			_links[i].global_transform = Transform3D(basis, mid)
		previous = point


func _ensure_links(count: int) -> void:
	while _links.size() < count:
		var link := MeshInstance3D.new()
		link.mesh = _link_mesh
		link.material_override = _material
		add_child(link)
		_links.append(link)
	for i: int in _links.size():
		_links[i].visible = i < count
