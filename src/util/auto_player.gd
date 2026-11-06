extends Node
## Development bot (--auto-play): plays the local player's turns through the public Session
## API, exactly like the UI would. Used by the full-game smoke test and to fill seats when
## testing by hand with a few windows.
##
## Each round it submits a random template with a caption, votes on every spotlight it can
## and now and then spends a bullet.

const SHOOT_CHANCE: float = 0.3
## Reaction delay range, so bots don't all act on the same frame.
const MIN_DELAY: float = 0.05
const MAX_DELAY: float = 0.3

var _rng := RandomNumberGenerator.new()
var _submitted_round: int = -1
## "round:spotlight index" keys already handled.
var _handled_spotlights: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	Session.match_updated.connect(_on_match_updated)


func _on_match_updated(view: MatchView, _previous: MatchView) -> void:
	var me: int = Session.local_peer_id()
	match view.phase:
		GameMatch.Phase.CREATE:
			if view.is_alive(me) and _submitted_round != view.round_number:
				_submitted_round = view.round_number
				_after_delay(_submit.bind(view.round_number))
		GameMatch.Phase.SPOTLIGHT:
			var key: String = "%d:%d" % [view.round_number, view.spotlight_index]
			if not _handled_spotlights.has(key) and view.spotlight_id != me:
				_handled_spotlights[key] = true
				_after_delay(_judge.bind(key))


func _submit(round_number: int) -> void:
	var ids: PackedStringArray = Session.allowed_templates if not Session.allowed_templates.is_empty() \
		else MemeTemplateLibrary.get_default().ids()
	var spec := MemeSpec.new(ids[_rng.randi_range(0, ids.size() - 1)],
		"BOT MEME %d" % round_number, "BEEP BOOP")
	print("[AutoPlayer] Submitting %s" % spec.template_id)
	Session.submit_meme(spec)


func _judge(key: String) -> void:
	var view: MatchView = Session.match_view
	if view == null or "%d:%d" % [view.round_number, view.spotlight_index] != key:
		return  # The spotlight moved on while we waited.
	var me: int = Session.local_peer_id()
	if view.can_vote(me, Session.eliminated_can_vote()):
		Session.cast_vote(1 if _rng.randf() < 0.5 else -1)
	if view.can_shoot(me) and _rng.randf() < SHOOT_CHANCE:
		print("[AutoPlayer] Shooting %s" % view.player_name(view.spotlight_id))
		Session.shoot()


func _after_delay(callback: Callable) -> void:
	get_tree().create_timer(_rng.randf_range(MIN_DELAY, MAX_DELAY)).timeout.connect(callback)
