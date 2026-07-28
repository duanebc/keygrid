# Changelog

## Unreleased

First public release.

- **M+ Grid tab** — account-wide row per character: keystone, score, item level,
  Great Vault progress, per-dungeon best runs, and crest / Field Accolades /
  Voidlight Marl counts with weekly earned-vs-cap. Sortable on every column.
- **Void Cores tab** — collected / on-hand / spent / remaining / earned-this-week
  per character.
- Currency resolution works even for currencies the character has never earned:
  a direct id probe, cached account-wide once any character resolves it, so a
  fresh alt reads a real `0` instead of a blank.
- `/kg all`, `/kg hide`, `/kg show` to control which rows appear;
  `/kg capture` to re-snapshot on demand; `/kg reset` to recover the window.
- Optional `keygrid-sync` companion fills in best runs and rating for alts you
  have not logged into, via the Blizzard API.
- No external libraries — pure Blizzard API, no Ace3, no LibStub.

### Not included in released builds

- The Loot tab is developer-only. It needs a season loot data file that is not
  distributable; see "Private mode" in the README.
