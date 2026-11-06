# Game Design — Killing for the Memes

Living design document. Rules here are the source of truth for `src/core/`.
Tunable numbers live in one config resource (see `src/core/`), not scattered in code.

## Pitch

3–8 friends are chained to chairs around a table in a grimy, trap-filled room. Every round
everyone makes a meme for a prompt, the hosting player presents them one by one on the wall
TV, the room judges them, and the author of the worst meme is killed off in an over-the-top
cartoon death. Last survivor wins.

Tone: dark comedy first, horror flavour second. Deaths are slapstick (confetti, springs,
anvils, comically oversized contraptions), never realistic gore.

## Originality rules

Everything is original. Specifically **avoid** anything that evokes the Saw franchise:
no tricycle-riding puppet, no pig masks, no reverse bear trap, no "I want to play a game"
phrasing, no tape recorders as a captor's voice. Keep the room and traps our own.

There is no host character in the room: the player who hosts the game runs the show
(starts it, presents the memes, starts the next game). An earlier CRT-headed robot host
was removed.

## Presentation: 2D and 3D at the same time

- The room and players are low-poly 3D with moody lighting.
- Each player has an old CRT monitor in front of them. To make a meme, the camera zooms into
  the screen and the player works in a flat 2D editor. The editor is rendered in a
  `SubViewport` that is also the monitor's screen texture, so the zoom is seamless.
- During judging the camera pulls back; the meme is shown on a big wall TV while a
  spotlight focuses on the presenting player.

## The room (M3 greybox)

- Round table; seats spread evenly over a 250° arc facing the centre, leaving the side
  toward the wall TV open, so everyone can see it.
- Each seat: wooden chair, the player chained by both wrists to bolts in the table, a
  keyboard under their hands and a CRT monitor in front of them.
- One flickering lamp over the table, a ceiling spotlight for the presenting player,
  light fog. Everyone wears a different shirt colour so players are easy to tell apart.
- Camera: first-person from your own seat (looking at your monitor, gentle mouse drift),
  a TV view and an overview.

## Making a meme (M4)

- From your seat press **E** or click your monitor: the camera glides in until the CRT
  fills the screen and the editor takes over (still curved and scanlined). **Esc** looks up.
- Pick one of the templates: popular memes from Imgflip first, then reaction GIFs from
  GIPHY (both fetched by the host, see CREDITS.md; GIFs need the host's GIPHY key), then
  our original shots of this room (players in the spotlight, the empty chair...).
  Type a top and a bottom caption, press **Done**. GIF memes play on the wall TV.
  Captions are uppercase with a black outline and shrink to fit. You can resubmit until
  time runs out; the draft is submitted automatically at zero.

## Core round loop (MVP)

1. **Prompt** — the wall TV shows a prompt (from the active prompt pack).
2. **Create** — all living players make a meme simultaneously on a timer
   (pick a template, add top/bottom captions in a classic meme font).
3. **Spotlight reveal** — memes are shown one at a time on the wall TV. While a player is
   in the spotlight, everyone else votes and may shoot. The hosting player presents them at
   their own pace: each meme stays up until they press *Next meme* (they see how many have
   judged it), and after the last one *Show results*. (`GameConfig.host_paces_spotlight`;
   off, each meme gets `spotlight_duration` seconds.)
4. **Tally** — scores are computed by the server.
5. **Elimination** — lowest score dies with a cartoon death.
6. Repeat until one living player remains → **win screen**.

## Scoring (MVP defaults — all tunable)

| Action | Effect on spotlight player |
|---|---|
| 👍 vote | +1 |
| 👎 vote | −1 |
| No vote | 0 |
| Bullet | −3, visible to everyone |

- Each voter casts at most one 👍/👎 per spotlight and may change it until the host moves on.
- Bullets: **2 per player for the whole game**; at most 1 bullet per spotlight per shooter.
- You cannot vote on or shoot yourself.
- **No submission** → automatically ranked last for the round (still shown as a blank meme).
- **Tie-break** for lowest score: most bullets received this round → if still tied, fate
  picks at random (server RNG, announced dramatically).
- **Eliminated players** (MVP) stay as spectators who can still 👍/👎 vote, but cannot shoot.
  This keeps the final 1v1 decidable. Full "ghost" mechanics come later.
  (`GameConfig.eliminated_can_vote` turns this off.)
- Elimination order of rules: non-submitters → lowest score → most bullets taken → random.
  The reason is sent to clients so the TV can announce *why* someone died.

## Round flow details (implemented in `src/core/game_match.gd`)

- **Creation ends early** as soon as every living player has submitted. Players may
  resubmit (replace their meme) until creation ends.
- **Spotlight order** is shuffled every round. Every player alive when creation ended gets
  exactly one spotlight, including non-submitters, who are shown a blank meme.
- **Votes are secret** until the elimination results; each player only sees their own vote.
  **Shots are public** the moment they happen.
- **Results**: during the elimination phase everyone sees each player's score,
  👍/👎 counts, bullets taken and whether they submitted.
- **The final death** still gets its full elimination phase before the win screen.
- **Timers** always run from the moment a phase starts, so a server hitch never cuts the
  next phase short. Snapshots send `time_left`, not absolute times, so client clocks don't matter.
- **Hidden information**: clients never receive other players' memes before their spotlight
  or other players' votes, so a modified client can't peek.
- Clients auto-submit their current draft `auto_submit_lead` (1 s) before creation ends,
  so forgetting to press "Done" doesn't count as no submission.

## Default timings (tunable)

- Prompt announcement: 5 s
- Meme creation: 60 s (or until everyone submits)
- Spotlight per meme: as long as the host likes (12 s when not host-paced)
- Elimination sequence: 6 s

## Disconnects

- A player who disconnects mid-game is out for good ("walked out"). They are skipped in
  the spotlight, and their bullets and seat are gone.
- Walking out does **not** count as the round's death: the worst meme still dies.
- If their spotlight was on, the next spotlight starts immediately with full time.
- If only one player is left alive, that player wins at once.
- If the host (server) disconnects, the game ends for everyone and clients return to the menu.
- No late joining once a game has started.

## Post-MVP (design for, don't build yet)

- **Ghosts**: eliminated players haunt the room, vote, and interfere with living players.
- **Waiting activities** (modular plug-ins in `src/activities/`): sabotage another player's
  meme, bet on who dies to earn bullets, lockpicking minigame for a one-time escape, throwing
  physics objects at the spotlight player.
- **HP mode**: damage instead of instant death.
- **GIF search** in the editor (players search GIPHY themselves instead of one host-picked
  list), and the official "Powered by GIPHY" mark for a production key.
- **Caption boxes per template** (e.g. Drake's two panels) instead of top/bottom only.
- **Custom prompt packs** (JSON in `data/prompts/`, later user-loadable / Workshop).
- **Steam**: lobbies, friend invites, P2P relay networking, achievements, rich presence.
