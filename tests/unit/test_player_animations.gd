extends GutTest
## The player's animations: the keyed ones and the artist's retargeted Meshy clips, and
## which one a body rests in (relaxed, typing, first person).


func _make(look_index: int) -> PlayerAvatar:
	var avatar: PlayerAvatar = (load("res://src/world/player/player_avatar.tscn") as PackedScene).instantiate()
	avatar.setup("Tester", look_index)
	add_child_autofree(avatar)
	return avatar


func _player(avatar: PlayerAvatar) -> AnimationPlayer:
	return avatar.find_children("*", "AnimationPlayer", true, false).front() as AnimationPlayer


func test_the_model_has_every_animation_the_metrics_list() -> void:
	var anim: AnimationPlayer = _player(_make(0))
	var names: Array = PlayerAvatar.metrics().get("animations", [])
	assert_gt(names.size(), 4)
	for name: Variant in names:
		assert_true(anim.has_animation(StringName(str(name))), "player.glb has '%s'" % name)
	for name: StringName in PlayerAvatar.ANIM_RELAXED + [PlayerAvatar.ANIM_DRINK, PlayerAvatar.ANIM_WAVE]:
		assert_true(name in names, "'%s' is built by build_player.py" % name)


func test_relaxed_idles_loop_and_one_shots_do_not() -> void:
	var anim: AnimationPlayer = _player(_make(0))
	for name: StringName in PlayerAvatar.ANIM_RELAXED:
		assert_eq(anim.get_animation(name).loop_mode, Animation.LOOP_LINEAR, "%s loops" % name)
	assert_eq(anim.get_animation(PlayerAvatar.ANIM_WAVE).loop_mode, Animation.LOOP_NONE)
	assert_eq(anim.get_animation(PlayerAvatar.ANIM_DRINK).loop_mode, Animation.LOOP_NONE)


func test_a_new_body_sits_relaxed_and_neighbours_differ() -> void:
	var first := _make(0)
	var second := _make(1)
	assert_true(first.is_relaxed())
	assert_true(first.rest_animation() in PlayerAvatar.ANIM_RELAXED)
	assert_ne(first.rest_animation(), second.rest_animation(), "neighbouring seats idle differently")
	assert_eq(StringName(_player(first).current_animation), first.rest_animation())


func test_typing_puts_the_hands_on_the_keyboard_and_relax_takes_them_off() -> void:
	var avatar := _make(2)
	avatar.type_on_keyboard()
	assert_eq(avatar.rest_animation(), PlayerAvatar.ANIM_IDLE)
	assert_eq(StringName(_player(avatar).current_animation), PlayerAvatar.ANIM_IDLE)
	avatar.relax()
	assert_true(avatar.rest_animation() in PlayerAvatar.ANIM_RELAXED)
	assert_eq(StringName(_player(avatar).current_animation), avatar.rest_animation())


func test_first_person_always_uses_the_keyboard_pose() -> void:
	# The first-person camera sits at the keyboard pose's eyes; a leaning idle would move
	# the head out from around it.
	var avatar := _make(1)
	avatar.set_first_person(true)
	assert_eq(StringName(_player(avatar).current_animation), PlayerAvatar.ANIM_IDLE)
	avatar.relax()
	assert_eq(avatar.rest_animation(), PlayerAvatar.ANIM_IDLE)
	avatar.set_first_person(false)
	assert_true(StringName(_player(avatar).current_animation) in PlayerAvatar.ANIM_RELAXED)


func test_one_shots_return_to_the_resting_loop() -> void:
	var avatar := _make(0)
	var anim: AnimationPlayer = _player(avatar)
	avatar.celebrate()
	assert_eq(StringName(anim.current_animation), PlayerAvatar.ANIM_WAVE)
	assert_eq(Array(anim.get_queue()), [avatar.rest_animation()])
	# Starting to type during the wave changes what follows it, not the wave itself.
	avatar.type_on_keyboard()
	assert_eq(StringName(anim.current_animation), PlayerAvatar.ANIM_WAVE)
	assert_eq(Array(anim.get_queue()), [PlayerAvatar.ANIM_IDLE])
	avatar.flinch()
	assert_eq(StringName(anim.current_animation), PlayerAvatar.ANIM_FLINCH)
	assert_eq(Array(anim.get_queue()), [PlayerAvatar.ANIM_IDLE])
