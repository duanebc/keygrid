# Changelog

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
