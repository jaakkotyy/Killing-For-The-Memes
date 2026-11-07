class_name Protocol
extends RefCounted
## Shared networking constants and the list of RPCs.
##
## Bump VERSION whenever an RPC signature or payload shape changes; clients with a
## different VERSION are rejected when they try to join.
##
## RPCs (all live on the Session autoload, see src/autoload/session.gd):
##   client → server  _rpc_request_join(name: String, version: int)
##   client → server  _rpc_set_ready(is_ready: bool)
##   server → client  _rpc_lobby_snapshot(snapshot: Dictionary)   # LobbyState.to_dict(), with
##                    # the host's identity pack id
##   server → client  _rpc_join_rejected(reason: String)           # followed by a kick
##   server → client  _rpc_game_started(snapshot: Dictionary, config: Dictionary, pack_text: String)
##                    # LobbyState.to_dict(), GameConfig.to_dict(), and a custom identity
##                    # pack's JSON file ("" for a shipped pack), validated with
##                    # IdentityPack.receive() on arrival
##   client → server  _rpc_ask(question: Dictionary)               # {text: String} or {stock: int}
##   client → server  _rpc_answer(value: int)                      # 1 Yes, -1 No, 0 "I don't know"
##   client → server  _rpc_guess(entry_id: String)                 # an entry id of the game's pack
##   server → client  _rpc_match_snapshot(snapshot: Dictionary)    # GuessMatch.to_snapshot(now, you)
##   server → client  _rpc_returned_to_lobby(snapshot: Dictionary) # LobbyState.to_dict()
##
## Every client loads a shipped pack (data/identities/<id>.json) from its own files, so packs
## must be identical between builds that share a VERSION: bump it when packs are rebuilt.
## A custom pack (user://identities/<id>.json, host only) travels in _rpc_game_started.
##
## Match snapshots are sent whenever the match changes (phase, question, answer, guess,
## disconnect), at most once per frame. Clients count time_left down locally in between.
##
## The host has no RPC round trip to itself: Session calls ServerController directly.
## Host-only actions (start, back to the lobby) therefore need no RPC at all.

const VERSION: int = 9

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 8
const MIN_PLAYERS: int = 3

## Seconds a connected peer may take to send its join request before it is kicked.
const JOIN_REQUEST_TIMEOUT: float = 5.0
## Seconds a client waits for the transport to connect before giving up.
const CONNECT_TIMEOUT: float = 10.0

## Join rejection reasons. Sent to the rejected client and shown in its main menu.
const REJECT_VERSION_MISMATCH: String = "Version mismatch: everyone must run the same build of the game."
const REJECT_LOBBY_FULL: String = "The lobby is full."
const REJECT_GAME_IN_PROGRESS: String = "That game has already started."
const REJECT_TIMEOUT: String = "The join request timed out."
