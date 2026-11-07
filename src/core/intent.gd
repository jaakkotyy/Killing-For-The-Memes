class_name Intent
extends RefCounted
## What became of a player's intent (an RPC asking the match to do something). The match
## validates every intent and answers with one of these; only OK changes anything.

enum Result { OK, WRONG_PHASE, NOT_ALLOWED, INVALID, ALREADY_DONE }
