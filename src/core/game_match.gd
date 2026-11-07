class_name GameMatch
extends RefCounted
## The authoritative round loop: prompt → create → one spotlight per player → elimination,
## repeated until one player is left. Pure logic, so it is fully unit-testable:
##   - time is passed in as `now` (seconds, any monotonic clock); nothing reads the real clock
##   - randomness comes from an injected RandomNumberGenerator
##   - player input arrives as intents (submit_meme, cast_vote, shoot, present_next) that
##     return an IntentResult and never trust their arguments
## The server calls update(now) every frame and broadcasts to_snapshot() to each peer.

signal phase_changed(phase: Phase)
signal shot_fired(shooter_id: int, target_id: int)
## [param reason] is a Scoring.Reason.
signal player_eliminated(player_id: int, reason: int)
signal player_left(player_id: int)
## [param winner_id] is 0 when nobody is left (everyone disconnected).
signal game_over(winner_id: int)

enum Phase { WAITING, PROMPT, CREATE, SPOTLIGHT, ELIMINATION, GAME_OVER }
enum IntentResult { OK, WRONG_PHASE, NOT_ALLOWED, INVALID, ALREADY_DONE }

const MIN_PLAYERS_TO_START: int = 2

var config: GameConfig
var phase: Phase = Phase.WAITING
var round_number: int = 0
var prompt: String = ""
var phase_ends_at: float = 0.0
var winner_id: int = 0

var _players: Dictionary[int, PlayerState] = {}
var _deck: PromptDeck
var _rng: RandomNumberGenerator
## Template ids accepted by submit_meme(); empty accepts any well-formed id.
var _allowed_templates: PackedStringArray = []
## When set, decides instead which template ids submit_meme() accepts (id -> bool). The
## server sets it so memes may use any online template, even one just found by a search.
var template_accepts: Callable

# --- Current round ---
var _submissions: Dictionary[int, MemeSpec] = {}
## Spotlight order for this round (players alive when creation ended).
var _spotlight_order: Array[int] = []
var _spotlight_index: int = -1
## target id -> {voter id: +1 / -1}
var _votes: Dictionary[int, Dictionary] = {}
## target id -> shooter ids
var _shots: Dictionary[int, Array] = {}
## Outcome of the most recent elimination, as sent to clients.
var _last_elimination: Dictionary = {}


func _init(
		p_config: GameConfig,
		lobby_players: Array[LobbyPlayer],
		deck: PromptDeck,
		rng: RandomNumberGenerator,
		allowed_templates: PackedStringArray = PackedStringArray()) -> void:
	config = p_config
	_deck = deck
	_rng = rng
	_allowed_templates = allowed_templates
	for lobby_player: LobbyPlayer in lobby_players:
		_players[lobby_player.id] = PlayerState.new(lobby_player.id, lobby_player.name, lobby_player.seat, config.bullets_per_player)


func start(now: float) -> void:
	assert(phase == Phase.WAITING, "match already started")
	assert(living_ids().size() >= MIN_PLAYERS_TO_START, "not enough players")
	_begin_round(now)


## Advances through every phase whose time is up. Call every frame on the server.
## Untimed phases (a host-paced spotlight) never end here, whatever `now` is.
func update(now: float) -> void:
	while _is_running() and not is_inf(phase_ends_at) and now >= phase_ends_at:
		_advance(now)


# --- Intents ------------------------------------------------------------------------------

## A player submits (or replaces) their meme. [param data] is untrusted (see MemeSpec.from_untrusted).
func submit_meme(player_id: int, data: Variant, now: float) -> IntentResult:
	if phase != Phase.CREATE:
		return IntentResult.WRONG_PHASE
	if not _is_alive(player_id):
		return IntentResult.NOT_ALLOWED
	var custom: bool = template_accepts.is_valid()
	var spec: MemeSpec = MemeSpec.from_untrusted(data, PackedStringArray() if custom else _allowed_templates)
	if spec == null or (custom and not bool(template_accepts.call(spec.template_id))):
		return IntentResult.INVALID
	_submissions[player_id] = spec
	if _everyone_submitted():
		_start_spotlights(now)
	return IntentResult.OK


## Votes on the player in the spotlight: +1 up, -1 down, 0 takes the vote back.
## Votes can change until the spotlight ends.
func cast_vote(voter_id: int, value: Variant, _now: float) -> IntentResult:
	if phase != Phase.SPOTLIGHT:
		return IntentResult.WRONG_PHASE
	if typeof(value) != TYPE_INT or not [-1, 0, 1].has(value):
		return IntentResult.INVALID
	var target: int = current_spotlight_id()
	if voter_id == target or not _can_vote(voter_id):
		return IntentResult.NOT_ALLOWED
	var votes: Dictionary = _votes.get_or_add(target, {})
	if value == 0:
		votes.erase(voter_id)
	else:
		votes[voter_id] = value
	return IntentResult.OK


## Spends one bullet on the player in the spotlight. Visible to everyone.
func shoot(shooter_id: int, _now: float) -> IntentResult:
	if phase != Phase.SPOTLIGHT:
		return IntentResult.WRONG_PHASE
	var target: int = current_spotlight_id()
	if shooter_id == target or not _is_alive(shooter_id) or _players[shooter_id].bullets <= 0:
		return IntentResult.NOT_ALLOWED
	var shooters: Array = _shots.get_or_add(target, [])
	if shooters.has(shooter_id):
		return IntentResult.ALREADY_DONE
	shooters.append(shooter_id)
	_players[shooter_id].bullets -= 1
	shot_fired.emit(shooter_id, target)
	return IntentResult.OK


## The presenter (the hosting player; ServerController checks who) moves on from the meme
## on the wall TV: to the next one, or to the results after the last. [param from_index]
## is the spotlight index they were looking at, so a double press or a press that crosses
## a timeout never skips a meme.
func present_next(from_index: Variant, now: float) -> IntentResult:
	if phase != Phase.SPOTLIGHT:
		return IntentResult.WRONG_PHASE
	if typeof(from_index) != TYPE_INT:
		return IntentResult.INVALID
	if from_index != _spotlight_index:
		return IntentResult.ALREADY_DONE
	_next_spotlight(now)
	return IntentResult.OK


## Whether the current phase runs until someone acts instead of on a timer.
func is_untimed() -> bool:
	return _is_running() and is_inf(phase_ends_at)


## A player disconnected. They are out for good; the game carries on without them.
## Leaving does not replace the round's elimination: the worst meme still dies.
func remove_player(player_id: int, now: float) -> void:
	if not _players.has(player_id) or _players[player_id].status == PlayerState.Status.LEFT:
		return
	var player: PlayerState = _players[player_id]
	var was_in_spotlight: bool = phase == Phase.SPOTLIGHT and current_spotlight_id() == player_id
	if player.is_alive():
		player.out_in_round = round_number
	player.status = PlayerState.Status.LEFT
	player_left.emit(player_id)

	if not _is_running():
		return
	if living_ids().size() <= 1 and phase != Phase.ELIMINATION:
		_finish()
	elif was_in_spotlight:
		_next_spotlight(now)
	elif phase == Phase.CREATE and _everyone_submitted():
		_start_spotlights(now)


# --- Queries ------------------------------------------------------------------------------

func get_player(player_id: int) -> PlayerState:
	return _players.get(player_id)


func living_ids() -> Array[int]:
	var ids: Array[int] = []
	for player: PlayerState in _players.values():
		if player.is_alive():
			ids.append(player.id)
	ids.sort()
	return ids


## The player whose meme is on the wall TV, or 0 outside the spotlight phase.
func current_spotlight_id() -> int:
	if phase != Phase.SPOTLIGHT or _spotlight_index < 0 or _spotlight_index >= _spotlight_order.size():
		return 0
	return _spotlight_order[_spotlight_index]


## Position of the current spotlight in this round's order (-1 before the first).
func current_spotlight_index() -> int:
	return _spotlight_index


func get_submission(player_id: int) -> MemeSpec:
	return _submissions.get(player_id)


func get_last_elimination() -> Dictionary:
	return _last_elimination


## State as one peer may see it. Hidden information (other players' memes before their
## spotlight, other players' votes before the results) is left out, so a modified client
## cannot peek.
func to_snapshot(now: float, viewer_id: int) -> Dictionary:
	var players: Array[Dictionary] = []
	var sorted_players: Array[PlayerState] = []
	sorted_players.assign(_players.values())
	sorted_players.sort_custom(func(a: PlayerState, b: PlayerState) -> bool: return a.seat < b.seat)
	for player: PlayerState in sorted_players:
		players.append(player.to_dict())

	var submitted: Array[int] = []
	submitted.assign(_submissions.keys())
	submitted.sort()

	var snapshot: Dictionary = {
		"phase": phase,
		"round": round_number,
		"prompt": prompt,
		# -1: no timer (the host presents at their own pace).
		"time_left": -1.0 if is_untimed() else (maxf(0.0, phase_ends_at - now) if _is_running() else 0.0),
		"players": players,
		"submitted": submitted,
		"my_meme": _submissions[viewer_id].to_dict() if _submissions.has(viewer_id) else {},
		"spotlight": {},
		"my_vote": 0,
		"elimination": {},
		"winner_id": winner_id,
	}

	var target: int = current_spotlight_id()
	if target != 0:
		var meme: MemeSpec = _submissions.get(target, MemeSpec.new())
		var shooters: Array[int] = []
		shooters.assign(_shots.get(target, []))
		# How many have voted, never who or how: lets the host see when to move on.
		var judges: int = 0
		for player: PlayerState in _players.values():
			if player.id != target and _can_vote(player.id):
				judges += 1
		snapshot["spotlight"] = {
			"player_id": target,
			"meme": meme.to_dict(),
			"shooters": shooters,
			"index": _spotlight_index,
			"count": _spotlight_order.size(),
			"judged": (_votes.get(target, {}) as Dictionary).size(),
			"judges": judges,
		}
		snapshot["my_vote"] = int(_votes.get(target, {}).get(viewer_id, 0))

	if phase == Phase.ELIMINATION or phase == Phase.GAME_OVER:
		snapshot["elimination"] = _last_elimination
	return snapshot


# --- Phase flow ---------------------------------------------------------------------------

func _advance(now: float) -> void:
	match phase:
		Phase.PROMPT:
			_set_phase(Phase.CREATE, now + config.create_duration)
		Phase.CREATE:
			_start_spotlights(now)
		Phase.SPOTLIGHT:
			_next_spotlight(now)
		Phase.ELIMINATION:
			if living_ids().size() <= 1:
				_finish()
			else:
				_begin_round(now)


func _begin_round(now: float) -> void:
	round_number += 1
	_submissions.clear()
	_spotlight_order.clear()
	_spotlight_index = -1
	_votes.clear()
	_shots.clear()
	_last_elimination = {}
	prompt = _deck.draw()
	_set_phase(Phase.PROMPT, now + config.prompt_duration)


func _start_spotlights(now: float) -> void:
	_spotlight_order = living_ids()
	# Fisher-Yates with the injected RNG: reproducible from a seed.
	for i: int in range(_spotlight_order.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: int = _spotlight_order[i]
		_spotlight_order[i] = _spotlight_order[j]
		_spotlight_order[j] = tmp
	_spotlight_index = -1
	_next_spotlight(now)


## Moves to the next player still alive; resolves the round after the last one.
func _next_spotlight(now: float) -> void:
	_spotlight_index += 1
	while _spotlight_index < _spotlight_order.size() and not _is_alive(_spotlight_order[_spotlight_index]):
		_spotlight_index += 1
	if _spotlight_index >= _spotlight_order.size():
		_resolve_round(now)
	else:
		_set_phase(Phase.SPOTLIGHT, INF if config.host_paces_spotlight else now + config.spotlight_duration)


func _resolve_round(now: float) -> void:
	var candidates: Array[int] = living_ids()
	if candidates.size() <= 1:
		_finish()
		return
	var scores: Dictionary = {}
	var bullets_taken: Dictionary = {}
	var results: Array[Dictionary] = []
	for player_id: int in candidates:
		var votes: Dictionary = _votes.get(player_id, {})
		var bullets: int = _shots.get(player_id, []).size()
		scores[player_id] = Scoring.spotlight_score(votes, bullets, config)
		bullets_taken[player_id] = bullets
		results.append({
			"player_id": player_id,
			"score": scores[player_id],
			"upvotes": votes.values().count(1),
			"downvotes": votes.values().count(-1),
			"bullets": bullets,
			"submitted": _submissions.has(player_id),
		})

	var submitted: Array[int] = []
	submitted.assign(_submissions.keys())
	var outcome: Dictionary = Scoring.choose_elimination(candidates, scores, bullets_taken, submitted, _rng)
	var loser_id: int = int(outcome["player_id"])
	var loser: PlayerState = _players[loser_id]
	loser.status = PlayerState.Status.ELIMINATED
	loser.out_in_round = round_number

	_last_elimination = {
		"player_id": loser_id,
		"reason": outcome["reason"],
		"results": results,
	}
	player_eliminated.emit(loser_id, int(outcome["reason"]))
	_set_phase(Phase.ELIMINATION, now + config.elimination_duration)


func _finish() -> void:
	var survivors: Array[int] = living_ids()
	winner_id = survivors[0] if survivors.size() == 1 else 0
	phase = Phase.GAME_OVER
	phase_ends_at = 0.0
	phase_changed.emit(phase)
	game_over.emit(winner_id)


func _set_phase(new_phase: Phase, ends_at: float) -> void:
	phase = new_phase
	phase_ends_at = ends_at
	phase_changed.emit(phase)


# --- Helpers ------------------------------------------------------------------------------

func _is_running() -> bool:
	return phase != Phase.WAITING and phase != Phase.GAME_OVER


func _is_alive(player_id: int) -> bool:
	return _players.has(player_id) and _players[player_id].is_alive()


func _can_vote(player_id: int) -> bool:
	if not _players.has(player_id):
		return false
	var player: PlayerState = _players[player_id]
	return player.is_alive() or (player.status == PlayerState.Status.ELIMINATED and config.eliminated_can_vote)


func _everyone_submitted() -> bool:
	for player_id: int in living_ids():
		if not _submissions.has(player_id):
			return false
	return true
