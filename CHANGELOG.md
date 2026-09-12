# Changelog

## v1.3.2 — 2026-09-12

- **Other characters' Coins, Marl and Accolades follow warband transfers.** A
  cell used to be a snapshot from the last time you played that character, so
  pooling coins onto one alt left every other row showing money it no longer
  had. The live warband balance is now written into each known character's cell
  as it arrives; the tooltip says "On hand as of … (warband data)" when that is
  where the number came from. Characters KeyGrid has never seen still need one
  login.
- **The Spark season count is what the game calls "Total".** It took the
  larger of on-hand and earned dust, and on one character earned read a step
  higher than on hand, so the grid said 7/7 where the game said 6/7. On hand
  is the figure now; the tooltip shows the dust's raw on-hand / earned / cap.

## v1.3.1 — 2026-09-01

- **The Vault column tells you how many keys you still owe.** It used to show
  runs done, runs needed, and the key level each slot would grant — four numbers
  a row, three rows, and not the one you wanted. Hovering now leads with the
  answer:

      All three at top reward   3 more +10s
      Rewards                   318 / 318 / 315
      Runs this week            5

  Eight runs at or above a level puts every slot at or above it, so that figure
  holds regardless of Blizzard's per-slot arithmetic.

- **Item levels, not just key levels.** A slot granting `+10` now also says what
  that is worth. `GetRewardLevelForDifficultyLevel` returns two values of which
  only one is reliably an item level — the other came back as `28` on a live
  client — and where both are item levels the larger is the vault and the smaller
  is the end-of-run drop. The ceiling is probed rather than written down, so it
  survives a season turning over.

- **A finished vault says so without being logged into.** A character whose three
  slots already read 318 is done, and that is visible from the stored data. Being
  told to log in on it was the opposite of what an account-wide grid is for.
  Where the run list genuinely is missing, the target is still named.

- **The per-slot run counter is no longer shown.** It does not behave like a run
  count: across the roster one character reported 4, 4 and 15 runs on its three
  slots at the same instant, and another reported ten runs against a threshold of
  eight while awarding nothing. Nothing is now derived from a number that cannot
  be explained.

- **This week's runs are recorded**, which is what the shortfall is counted
  from. Season bests are a different question: this one counts repeats and cares
  only about levels.

- **A full re-capture no longer lands after every pull.** Anything arriving
  during combat queued a sweep — eight dungeon queries, thirteen currency
  columns, the vault, bags — that ran the moment combat dropped. Held to one
  every fifteen seconds now, and two seconds clear of the frame combat ends on.

## v1.3.0 — 2026-08-30

- **Dungeon cells show your best _timed_ run.** They used to show whichever run
  was the higher key, timed or not — so an over-time +14 hid a timed +10, and the
  number on screen was the one worth no score. The timed run is the one a key is
  chosen against, so it is the one the grid shows, and the column sorts on it.
- **Over-time runs moved to the tooltip**, in full beside the timed one: level,
  score, duration, date and source for each. A dungeon you have cleared but never
  timed still shows that run in the cell, marked `*` — never timed and never run
  are different answers.
- The tooltip's closing hint is specific now: where you have an untimed key above
  your timed best, it names that level as the one to go back for.
- Both runs are kept per dungeon in saved data, and each merges on its own, so
  neither source can overwrite one with the other. Existing records are migrated
  in place; the missing half fills in on the next login or sync.
- `keygrid-sync` records both runs per dungeon too. Re-run it to fill in over-time
  runs for alts you have not logged into — until then those cells show only what
  the API's single best run gave.

## v1.2.0 — 2026-08-29

- **The Spark column counts Sparks of Tides**, not the Tidal Spark Dust they
  arrive with. The spark is what a craft is waiting on; the dust is only the
  game's tally of them.
- **How much of the season's sparks you have actually claimed.** The cell reads
  what you hold with `4/5` under it — received this season over what the season
  has offered so far — and the tooltip spells it out with how many are **still
  to claim**. The weekly allowance rises by one every week, so a week you missed
  is catch-up rather than gone. A spark is a bag item and keeps no history of its
  own, so this is read off the dust, which does.
- **The Spark cell headlines what you hold.** It read `5/5` with one spark in the
  bag: season progress, where the question is whether you can craft. The cap
  moved to the second line.
- **A Void Cores column**, next to Spark. The count was already captured for the
  (still greyed-out) Void Cores tab and had nowhere to be seen.
- **Currency tooltips lead with the numbers.** On hand, the season, and what has
  been spent now run together at the top; the currency id and transfer rules moved
  down beside the timestamp, where they read as provenance. A capped or seasonal
  currency says **Gained this season** rather than the ambiguous "Collected".

## v1.1.0 — 2026-08-22

- **Minimap button.** Left click opens the grid, right click opens the new
  Settings tab, and it drags anywhere around the minimap. Hand-rolled on the
  Blizzard API — no LibDBIcon, no LibStub, nothing embedded.
- **Settings tab** gathering every option in one place: show characters with no
  score, window scale, the minimap button, and a character list you can tick
  rows out of instead of typing `/kg hide`.
- In-game help explaining how the snapshot model works, with a copyable link for
  reporting bugs.
- `/kg settings` and `/kg minimap` added; `/kg reset` now also restores scale.

## v1.0.2 — 2026-08-20

- First CurseForge release. No addon changes; this tag exists to publish the
  build that v1.0.1 already produced.

## v1.0.1 — 2026-08-19

- Mythic+ rating reads **N/A** for a character with no run this season. Ratings
  reset at the season roll, but a cached score was never overwritten, so rows
  kept showing a rating the character no longer had.
- A character KeyGrid hasn't seen since the roll also reads N/A, since its
  stored rating can no longer be trusted; logging into it fills the value back
  in. The score tooltip says which of the two cases applies.
- Characters with no runs this season stay in the grid rather than being
  filtered out as zero-score.

## v1.0.0 — 2026-08-19

First public release.

- **M+ Grid tab** — account-wide row per character: keystone, score, item level,
  Great Vault progress, per-dungeon best runs, and Corrosive Coins / Voidlight
  Marl / Venomblight Manaflux / Tidal Spark Dust counts with weekly
  earned-vs-cap. Sortable on every column.
- **Crest column** — the highest tier earned, with every tier's count and season
  cap on hover. Tiers the season ships but nobody can earn are left out.
- **Warband-transferable currencies** (Corrosive Coins, Voidlight Marl, anything
  the game flags as transferable) list every character's balance and the account
  total on hover — from the game's warband currency data when the client exposes
  it, and from KeyGrid's own snapshots otherwise. The Blizzard REST API has no
  currency endpoint, so `keygrid-sync` cannot fill this in.
- The season in the title bar comes from the game's season id; a new season
  inside the same expansion numbers itself.
- **Void Cores tab** — present but disabled: how cores work this season isn't
  settled yet, so the tab is greyed out (the data is still captured).
- Currency resolution works even for currencies the character has never earned:
  a direct id probe, cached account-wide once any character resolves it, so a
  fresh alt reads a real `0` instead of a blank.
- `/kg sync` prints the full keygrid-sync recipe. The sync is optional and the
  window no longer implies it is a missing step: the footer reports a sync only
  once one has run.
- `/kg all`, `/kg hide`, `/kg show` to control which rows appear;
  `/kg capture` to re-snapshot on demand; `/kg reset` to recover the window.
- Optional `keygrid-sync` companion fills in best runs and rating for alts you
  have not logged into, via the Blizzard API.
- No external libraries — pure Blizzard API, no Ace3, no LibStub.

### Not included in released builds

- The Loot tab is developer-only. It needs a season loot data file that is not
  distributable; see "Private mode" in the README.
