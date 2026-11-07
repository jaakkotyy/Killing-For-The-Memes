# Guess Mode — "Who Am I?"

A second game mode next to the meme game. Same room, same chained players, same CRT
terminals and cartoon deaths; different rules. The host picks the mode in the lobby.

Status: **design draft**. Defaults below are proposals; open questions are listed at the end.

## Pitch

Everyone gets a secret identity: a famous person, a movie, a band, a game character.
**Everyone can see your identity except you.** It hangs on a placard chained to your
chair. You ask yes/no questions, the others answer, and you use your CRT terminal to
search a database of every possible identity, narrowing thousands of candidates down
to a handful, until you dare to guess. Whoever is still clueless when the round ends dies.

## Round flow

```
WAITING → DEAL → TURN (ASK → ANSWER)×n → ROUND_END (ELIMINATION) → DEAL → … → GAME_OVER
```

1. **DEAL.** The server gives every living player an identity from the chosen pack
   (never the same one twice in a game). Placards flip. The wall TV shows the category
   ("Musicians").
2. **TURN.** The asker rotates among living players who haven't solved their identity yet.
   - **ASK** (`ask_duration`, 25 s): the asker sends one question, either
     - **structured**, built from the database fields ("Am I [born before] [1980]?"),
       which the **server answers truthfully and instantly**, or
     - **free text** ("Do I wear a hat?"), which goes to ANSWER.
   - **ANSWER** (`answer_duration`, 12 s, free-text questions only): everyone else votes
     Yes / No / Sort of. The wall TV spotlights the asker and shows the question and the
     tally live. The majority answer is recorded; ties show "Sort of".
   - Every answer is added to the asker's **clue log** on their terminal.
3. **GUESS (any time).** A player picks an entry from their search results and presses
   Guess. Guesses are database entry ids, never typed names, so spelling never matters.
   - Right: you're **solved**. Your placard turns green, and you keep answering everyone
     else's questions.
   - Wrong: you lose a **chain link** (`guess_lives`, 3). With no links left you die
     on the spot.
4. **ROUND_END** when only `unsolved_survivors` (1) living player is unsolved, or after
   `round_duration` (4 min). The unsolved player dies (if several are unsolved at the
   timeout, the one with the most wrong guesses dies, then the one with the fewest
   questions asked). Everyone's identity is revealed on the wall TV.
5. **GAME_OVER** when one player is alive.

Dead players spectate and still answer free-text questions, as in the meme game, so a
final 1v1 never deadlocks.

## The terminal (CRT)

Same look, phosphor green, zoom and input hand-off as the meme editor (`CrtZoom`,
`MemeStation` → `SearchStation`). Three panes:

- **Filters**: chips per database field (category, gender, decade of birth, country,
  occupation/genre, alive or dead, tags), each with a value and an operator. Players set
  them from the clue log. Clicking a clue applies it as a filter.
- **Results**: live count ("4,112 → 37 → 6") and a list with portrait, name and a few facts.
  Right-click strikes a candidate out (the Guess Who board feel); struck-out ones sink
  to the bottom, greyed.
- **Ask / Guess**: the question builder (structured or free text), and the Guess button
  with the selected candidate.

Search runs **locally**: the whole pack is public data, so the client filters it itself.
Only the *assignment* is secret.

## Data: identity packs

- `data/identities/<pack>.json`: `{id, name, category, fields: {...}, tags: [...], image?}`.
- Built offline by `tools/build_identities.ps1` from **Wikidata** (CC0, so no licensing
  problem) with one SPARQL query per pack, filtered by popularity (sitelink count) so
  everyone has a chance of knowing the person. The JSON is committed; the game never
  queries Wikidata at run time.
- Portraits: Wikimedia Commons thumbnails, fetched at run time like online templates and
  validated the same way (URL rebuilt from the file name, only `upload.wikimedia.org`).
  Each image's license is per file, so they are not shipped. Optional: the game works without them.
- First packs: **Musicians**, **Actors**, **Movies**, **Video game characters**,
  **Historical figures**. Later: **Our friends**, a hand-written pack (custom fields)
  loaded from `user://identities/`.
- Field types the structured questions and filters understand: `enum` (gender, country,
  genre), `year` (born, released), `bool` (alive, fictional), `tags` (has any of).

## Architecture

Nothing below `core/` changes shape; the mode is one more rules class.

| Layer | Meme mode (now) | Guess mode |
|---|---|---|
| `core/` rules | `GameMatch`, `MatchView` | `GuessMatch`, `GuessView` (same contract: `update(now)`, intent methods → `IntentResult`, `to_snapshot(now, viewer_id)`) |
| `core/` data | `PromptDeck`, `MemeSpec` | `IdentityPack` (load + validate), `IdentityQuery` (filters, also used to answer structured questions), `IdentityDeck` |
| shared | `PlayerState` (alive, bullets) | same, plus `lives` and `solved` |
| `GameConfig` | meme tunables | `mode`, `identity_pack`, `ask_duration`, `answer_duration`, `round_duration`, `guess_lives` |
| `LobbyState` | — | host-chosen `mode` + `pack`, shown to everyone in the lobby |
| `ServerController` | `_new_match()` | builds `GameMatch` or `GuessMatch` from `config.mode`; new `handle_ask`, `handle_answer`, `handle_guess` |
| `Session` | meme RPCs | `_rpc_ask(question)`, `_rpc_answer(value)`, `_rpc_guess(entry_id)`; snapshots go through the same `_rpc_match_snapshot`, carrying a `mode` key, parsed into `MatchView` or `GuessView` |
| `world/` | `MatchPresenter`, `MemeStation` | `GuessPresenter`, `SearchStation`, `IdentityPlacard` (Label3D + portrait on each seat) |
| `ui/` | `MatchHud` | `GuessHud` (turn, timer, lives, Yes/No/Sort-of keys 1/2/3) |
| bots | `AutoPlayer` memes | asks structured questions, answers truthfully from the data, guesses when ≤ 3 candidates |

**Hidden information:** `to_snapshot(now, viewer)` includes every other player's identity
id and **omits the viewer's own** until it is solved or revealed. A modified client
learns nothing it couldn't see on the placards anyway.

**Protocol:** new RPCs and snapshot fields → bump `Protocol.VERSION`.

## Milestones

- **G1 Data.** `IdentityPack`, `IdentityQuery`, `IdentityDeck` with unit tests; the
  Wikidata build script; first two packs (Musicians, Movies).
- **G2 Rules.** `GuessMatch` and `GuessView`: deal, turns, structured and free questions,
  answers, guesses, lives, round end, elimination, disconnects, snapshots. Rule tests and
  a seeded full-game simulation (like `test_game_simulation.gd`).
- **G3 Wiring.** Mode and pack in `GameConfig`/`LobbyState`/lobby UI, `ServerController`
  and `Session` RPCs, protocol bump, bots, `smoke_test.ps1 -Mode guess` (both modes must pass).
- **G4 Room.** `SearchStation` terminal, placards, wall TV question and tally, `GuessHud`,
  `GuessPresenter` choreography (spotlight on the asker, reveal on death), `--room-preview` support.
- **G5 Polish.** Portraits, more packs, custom "Our friends" pack, sounds, tuning from playtests.

## Open questions

1. **Hidden from yourself** (above) or **classic** (you know yours, everyone guesses
   everyone else's)? The terminal works for both; hidden-from-yourself is more of a party
   and needs no extra secrecy.
2. **Lying.** Optional "liar" role per round who can answer falsely and can be shot with
   the meme game's bullets?
3. **Death rule.** Last unsolved dies (above), or points over a fixed number of rounds
   with no deaths?
4. **Free-text questions** at all, or only structured ones (faster, no arguing, bots can
   play every part)?
