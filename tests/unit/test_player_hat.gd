extends GutTest
## The artist's hat on the player's Head bone (assets/models/player/hat.glb).

var _avatar: PlayerAvatar


func before_each() -> void:
	_avatar = (load("res://src/world/player/player_avatar.tscn") as PackedScene).instantiate()
	_avatar.setup("Tester", 0)
	add_child_autofree(_avatar)


func test_the_hat_rides_on_the_head_bone() -> void:
	var hat: Node3D = _avatar.find_child("Hat", true, false) as Node3D
	assert_not_null(hat, "every player wears the hat")
	var attachment := hat.get_parent() as BoneAttachment3D
	assert_not_null(attachment, "the hat follows a bone")
	assert_eq(attachment.bone_name, PlayerAvatar.HAT_BONE)
	assert_true(_avatar.is_hat_visible())


func test_in_the_rest_pose_the_hat_sits_where_it_was_fitted() -> void:
	# hat.glb is exported in the model's rest space, so in the A-pose (rest) the hat's
	# transform must equal the model root's.
	_avatar.hold_pose(&"a_pose", 0.0)
	await wait_physics_frames(2)
	var hat: Node3D = _avatar.find_child("Hat", true, false) as Node3D
	var model: Node3D = _avatar.get_child(0) as Node3D
	assert_almost_eq(hat.global_position.distance_to(model.global_position), 0.0, 0.002)
	var ring: Dictionary = PlayerAvatar.metrics().get("hat_band", {})
	assert_false(ring.is_empty(), "player_metrics.json has the measured hat band")


func test_first_person_keeps_only_the_hat_shadow() -> void:
	var meshes: Array[Node] = _avatar.find_child("Hat", true, false).find_children("*", "GeometryInstance3D", true, false)
	assert_gt(meshes.size(), 0)
	_avatar.set_first_person(true)
	for mesh: Node in meshes:
		assert_eq((mesh as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	_avatar.set_first_person(false)
	for mesh: Node in meshes:
		assert_eq((mesh as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
