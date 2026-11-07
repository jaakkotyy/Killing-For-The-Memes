# Adrift — Game Design

**Adrift** is an online "Who am I?" party game for 3–8 players. Everyone wakes up on a
round platform floating in deep space, chained to a chair at a table of old CRT
terminals, with a red planet and its moon hanging in the dark. Nobody knows who they are.
Everyone else does.

This file is the source of truth for the rules and the default numbers
(`src/core/game_config.gd`). Numbers are starting points for playtests.

Tone: mysterious and a little melancholy, never violent. Nobody dies; it's points over a
few rounds.

## Pitch

Everyone gets a secret identity: a famous musician, a movie, an actor, a historical
figure, a game character. **Everyone can see your identity except you**: it floats on a
glowing sign above your head. You ask yes/no questions, the others answer, and you search
your CRT's database of every possible identity, narrowing thousands of candidates down to
a handful, until you dare to guess. The fastest, sharpest guessers score the most.

## The place

- **The platform**: a round deck (radius 5.2 m) with glowing seams and an edge ring,
  floating in space. The table and the chairs stand in the middle, one seat per player
  (`SeatLayout`, an arc that leaves one side open for the screen).
- **Around it**: only space. A starfield sky with faint nebulae, a distant sun, the
  artist's red planet and its moon turning slowly (`world/space/SpaceBackdrop`).
- **Above the table**: a softly pulsing orb light.
- **The screen**: a floating panel on a slim pylon at the open side of the table. It shows
  the category, whose turn it is, the question, the answer and the reveal.
- **Your terminal**: the CRT in front of you. Press **E** or click it to zoom in;
  **Esc** looks up again. **Tab** cycles the camera (your seat, the screen, an overview).

## Round flow

```
WAITING → DEAL → (ASK → ANSWER → RESULT)×n → REVEAL → DEAL → … → GAME_OVER
```

1. **DEAL** (`deal_duration`, 5 s). The server gives every player an identity from the
   chosen pack (never the same one twice in a game, dealt from the pack's
   `deal_pool` = 300 best known entries). The signs light up; the screen shows the category.
2. **TURNS.** The asker rotates among players who haven't solved their identity yet.
   - **ASK** (`ask_duration`, 25 s): the asker sends one yes/no question, either
     - **their own**, typed freely ("Do I wear a hat?"), or
     - a **stock question** from the pack's list ("Am I a band?", "Was I born before
       1980?"). Stock questions are linked to a database field, so a clear answer becomes
       a one-click filter on the terminal.
     An asker who lets ASK run out loses the turn.
   - **ANSWER** (`answer_duration`, 12 s): the question shows on the screen with the
     spotlight on the asker. Everyone else answers **Yes / No / I don't know** (keys
     1/2/3; press again to change). The screen shows how many have answered, not how.
     The answer is the majority of Yes and No; a tie, or only "I don't know", is **Unclear**.
   - **RESULT** (`result_duration`, 3 s): the counts and the answer. Then the next asker.
   - Every answer goes into the asker's **clue log** on their terminal.
3. **GUESS (any time).** Pick an entry in your search results and press GUESS. Guesses
   are database entry ids, never typed names, so spelling never matters.
   - Right: you're **solved**, score points, your sign turns green, you stand up and wave,
     and you keep answering everyone else's questions.
   - Wrong: `wrong_guess_penalty` points off, and no more guesses until your next turn.
4. **REVEAL** (`reveal_duration`, 8 s) when everyone has solved or the round clock
   (`round_duration`, 4 min, from the end of the deal) runs out. Every identity is shown
   with the round's points.
5. **GAME_OVER** after `guess_rounds` rounds (3). Most points wins; a tie is shared. The
   winners celebrate. The host's *Play again* returns everyone to the lobby.

### Points

| Event | Points |
|---|---|
| Solve your identity | `solve_points` (100), minus `per_question_cost` (8) per question you asked this round, at least `solve_min` (30) |
| Solve first in the round | `first_bonus` (+25) |
| Wrong guess | `-wrong_guess_penalty` (15) |
| Answer with the final majority (Yes or No) | `+answer_points` (2), so people answer instead of hiding behind "I don't know" |

## Stock questions

Each pack has its own list, since the fields differ (a movie has no birth year). A stock
question is `{text, filter}`; the filter is what "Yes" means
(`{"field": "kind", "op": "is", "value": "band"}`), and "No" means its negation. The
terminal offers the filter after the answer but never applies it by itself: answers come
from people and can be wrong.

## The terminal (CRT)

Green phosphor on your monitor, 800x600 (`guess/terminal/SearchTerminal`):

- **FILTERS**: a field button, a value from a list (with how many open candidates have
  it; years by decade) and an operator (IS / IS NOT, HAS / HAS NOT, BEFORE / FROM).
- **CLUES**: this round's answers to your questions; FILTER turns a clear stock answer
  into a filter. A new answer switches here.
- **ASK**: your own question or the stock list. Your turn opens it.
- **Results**: a live count ("1263 → 37 left"), fame order, portrait, name and a few
  facts. Right-click crosses a candidate out; the identities on everyone else's signs are
  crossed out for you already.
- **Answer bar**: the HUD is hidden while you're zoomed in, so the terminal shows the
  current question with YES / NO / DON'T KNOW too. GUESS sits bottom right.

Search runs **locally**: the whole pack is public data; only the assignment is secret.

## Identity packs

- `data/identities/<pack>.json`: typed fields, entries, stock questions. Built offline by
  `tools/build_identities.ps1` from **Wikidata** (CC0), filtered by popularity (sitelink
  count) so everyone has a chance of knowing them. The game never queries Wikidata.
- Shipped: **Musicians** (the default; bands boosted ×1.5 in the fame order), **Movies**,
  **Actors**, **Historical figures** (born before 1900), **Video game characters**.
- **Custom packs** ("Our friends"): any `user://identities/<id>.json` the host writes
  (same format; example in `data/identity_examples/friends.json`). Only the host needs
  the file: it travels with the game start and clients validate it. The lobby's *Your
  packs folder* button opens the folder.
- Field types: `enum`, `year`, `bool`, `tags`.
- **Portraits**: Wikimedia Commons thumbnails fetched at run time (`PortraitCache`), never
  shipped; the URL is rebuilt from the entry's file name. Off with `--offline-portraits`
  or `online_portraits=false` in `settings.cfg`. A portrait that fails is left out.

## Hidden information

`GuessMatch.to_snapshot(now, viewer)` includes every other player's identity and
**omits the viewer's own** until it is solved or revealed. A modified client learns
nothing it couldn't see on the signs anyway.

## Lobby

The host picks the database (pack) and presses Start once there are at least 3 players
and every guest is ready. Up to 8 players. Join by IP, IP:port or join code (the IP and
port written in base32); Steam lobbies later.

## Decisions

- You can't see your own identity; everyone else can.
- No liar role; points over a fixed number of rounds; nobody dies.
- Questions are always answered by players, never by the server.
- The terminal only emits what the player wants to do (`ask_requested`,
  `stock_requested`, `answer_requested`, `guess_requested`); GuessPresenter sends it to Session.
- 2026-11-08: the meme game ("Killing for the Memes") was removed and the game moved to
  space as **Adrift**. The room became a floating platform; the signs float instead of
  hanging on chains.

## Later

- Steam (GodotSteam lobbies, invites, P2P, achievements) behind the existing transport
  and platform layers.
- Tuning from real playtests; more packs; sound effects that fit the music.
