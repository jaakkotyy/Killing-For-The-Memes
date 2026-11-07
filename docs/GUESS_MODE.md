# Guess Mode — "Who Am I?"

A second game mode next to the meme game. Same room, same chained players, same CRT
terminals; different rules, and nobody dies. The host picks the mode in the lobby.

Status: **design agreed** (2026-11-07). Numbers are starting points for playtests.

## Pitch

Everyone gets a secret identity: a famous person, a movie, a band, a game character.
**Everyone can see your identity except you.** It hangs on a placard chained to your
chair. You ask yes/no questions, the others answer, and you use your CRT terminal to
search a database of every possible identity, narrowing thousands of candidates down
to a handful, until you dare to guess. Nobody dies in this mode: the fastest, sharpest
guessers score the most points over a few rounds.

## Round flow

```
WAITING → DEAL → (ASK → ANSWER → RESULT)×n → REVEAL → DEAL → … → GAME_OVER
```

1. **DEAL.** The server gives every player an identity from the chosen pack (never the
   same one twice in a game). Placards flip. The wall TV shows the category ("Musicians").
2. **TURN.** The asker rotates among players who haven't solved their identity yet.
   - **ASK** (`ask_duration`, 25 s): the asker sends one yes/no question, either
     - **their own**, typed freely ("Do I wear a hat?"), or
     - a **stock question** from the pack's list ("Am I a band?", "Was I born before
       1980?", "Am I still alive?"). Stock questions are quicker and are linked to a
       database field, so a clear answer becomes a one-click filter on the terminal.
   - **ANSWER** (`answer_duration`, 12 s): the question shows on the wall TV with the
     spotlight on the asker. Everyone else votes **Yes / No / I don't know** (keys 1/2/3).
     The TV shows how many have answered, but not how, so nobody just follows the crowd.
     Answers can change until everyone has answered or the time is up. The answer is the
     majority of Yes and No; a tie, or only "I don't know" votes, is recorded as **Unclear**.
   - **RESULT** (`result_duration`, 3 s): the counts and the answer on the TV. Then the
     next asker. An asker who lets ASK run out simply loses the turn.
   - Every answer goes into the asker's **clue log** on their terminal.
3. **GUESS (any time).** A player picks an entry from their search results and presses
   Guess. Guesses are database entry ids, never typed names, so spelling never matters.
   - Right: you're **solved** and score points (below). Your placard turns green, and
     you keep answering everyone else's questions.
   - Wrong: `wrong_guess_penalty` points off, and you can't guess again until your next turn.
4. **REVEAL** (`reveal_duration`, 8 s) when everyone has solved, or when the round clock
   (`round_duration`, 4 min, started after the deal) runs out, whatever phase it is in. Every
   identity is revealed on the wall TV with the round's points.
5. **GAME_OVER** after `guess_rounds` rounds (3). Most points wins; a tie is shared.
   The winner celebrates, everyone else stays seated (no deaths in this mode).

### Points

| Event | Points |
|---|---|
| Solve your identity | `solve_points` (100), minus `per_question_cost` (8) per question you asked this round, at least `solve_min` (30) |
| Solve first in the round | `first_bonus` (+25) |
| Wrong guess | `-wrong_guess_penalty` (15) |
| Answer a question with the final majority | `+answer_points` (2), so people answer instead of pressing "I don't know" |

## Stock questions

Each pack has its own list, since the database fields differ (a movie has no birth year).
A stock question is `{text, filter}`; the filter is what a "Yes" means
(`{"field": "kind", "op": "is", "value": "band"}`), and "No" means its negation. The
terminal offers the filter after the answer, but never applies it by itself: the
answers come from people and can be wrong.

## The terminal (CRT)

Same look, phosphor green, zoom and input hand-off as the meme editor (`CrtZoom`,
`MemeStation` → `SearchStation`). Three panes:

- **Filters**: chips per database field (category, gender, decade of birth, country,
  occupation/genre, alive or dead, tags), each with a value and an operator. Players set
  them from the clue log. Clicking a clue applies it as a filter.
- **Results**: live count ("4,112 → 37 → 6") and a list with portrait, name and a few facts.
  Right-click strikes a candidate out (the Guess Who board feel); struck-out ones sink
  to the bottom, greyed.
- **Ask / Guess**: a text box for your own question and the stock question list, and the Guess button
  with the selected candidate.

Search runs **locally**: the whole pack is public data, so the client filters it itself.
Only the *assignment* is secret.

## Data: identity packs

- `data/identities/<pack>.json`: `{id, name, category, fields: {...}, tags: [...], image?}`.
- Built offline by `tools/build_identities.ps1` (Python) from **Wikidata** (CC0, so no licensing
  problem) with one SPARQL query per pack, filtered by popularity (sitelink count) so
  everyone has a chance of knowing the person. The JSON is committed; the game never
  queries Wikidata at run time.
- Portraits: Wikimedia Commons thumbnails, fetched at run time like online templates and
  validated the same way (URL rebuilt from the file name, only `upload.wikimedia.org`).
  Each image's license is per file, so they are not shipped. Optional: the game works without them.
- First packs: **Musicians**, **Actors**, **Movies**, **Video game characters**,
  **Historical figures**. Later: **Our friends**, a hand-written pack (custom fields)
  loaded from `user://identities/`.
- Field types the filters and stock questions understand: `enum` (gender, country,
  genre), `year` (born, released), `bool` (alive, fictional), `tags` (has any of).

## Architecture

Nothing below `core/` changes shape; the mode is one more rules class.

| Layer | Meme mode (now) | Guess mode |
|---|---|---|
| `core/` rules | `GameMatch`, `MatchView` | `GuessMatch`, `GuessView` (same contract: `update(now)`, intent methods → `IntentResult`, `to_snapshot(now, viewer_id)`) |
| `core/` data | `PromptDeck`, `MemeSpec` | `IdentityPack` (load + validate), `IdentityQuery` (filters; bots also use it to answer stock questions), `IdentityDeck` |
| shared | `PlayerState` (alive, bullets) | same; guess mode uses `score` and a per-round `solved` |
| `GameConfig` | meme tunables | `mode`, `identity_pack`, `guess_rounds`, `ask_duration`, `answer_duration`, `round_duration` and the point values above |
| `LobbyState` | — | host-chosen `mode` + `pack`, shown to everyone in the lobby |
| `ServerController` | `_new_match()` | builds `GameMatch` or `GuessMatch` from `config.mode`; new `handle_ask`, `handle_answer`, `handle_guess` |
| `Session` | meme RPCs | `_rpc_ask(question)` (text or stock index), `_rpc_answer(value)`, `_rpc_guess(entry_id)`; snapshots go through the same `_rpc_match_snapshot`, carrying a `mode` key, parsed into `MatchView` or `GuessView` |
| `world/` | `MatchPresenter`, `MemeStation` | `GuessPresenter`, `SearchStation`, `IdentityPlacard` (Label3D + portrait on each seat) |
| `ui/` | `MatchHud` | `GuessHud` (turn, timer, scores, Yes/No/I don't know keys 1/2/3) |
| bots | `AutoPlayer` memes | ask stock questions, answer stock questions truthfully from the data (free ones "I don't know"), apply clear answers as filters, guess when ≤ 3 candidates |

**Hidden information:** `to_snapshot(now, viewer)` includes every other player's identity
id and **omits the viewer's own** until it is solved or revealed. A modified client
learns nothing it couldn't see on the placards anyway.

**Protocol:** new RPCs and snapshot fields → bump `Protocol.VERSION`.

## Milestones

- [x] **G1 Data.** `IdentityPack`, `IdentityFilter`, `IdentityQuery`, `IdentityDeck` with
  unit tests; the Wikidata build script; first two packs (Musicians, Movies).
- [x] **G2 Rules.** `GuessMatch` and `GuessView`: deal, turns, own and stock questions,
  answers, guesses, points, round end, game over, disconnects, snapshots. Rule tests and
  a seeded full-game simulation (like `test_game_simulation.gd`).
- [x] **G3 Wiring.** Mode and pack in `GameConfig`/`LobbyState`/lobby UI, `ServerController`
  and `Session` RPCs, protocol bump, bots, `smoke_test.ps1 -Mode guess` (both modes must pass).
- **G4 Room.** `SearchStation` terminal, placards, wall TV question and tally, `GuessHud`,
  `GuessPresenter` choreography (spotlight on the asker, reveals at round end), `--room-preview` support.
- **G5 Polish.** Portraits, more packs, custom "Our friends" pack, sounds, tuning from playtests.

## Decisions

- You can't see your own identity; everyone else can (2026-11-07).
- No liar role.
- Points over a fixed number of rounds; nobody dies in this mode.
- Questions are always answered by the players (Yes / No / I don't know), never by the
  server. Players type their own or pick a stock question; stock questions carry a
  database filter the terminal can offer.
