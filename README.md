# KeyGrid

Every character's Mythic+ progress in one grid, readable from any character.

WoW keeps M+ data per character, so checking "which alt still owes a key?" normally
means logging in five times. KeyGrid saves a snapshot each time you log in a character
and shows all of them together, account-wide.

## What it shows

**M+ Grid tab** — one row per character:

| | |
|---|---|
| Keystone | the key that character is currently holding |
| Score | current season Mythic+ rating |
| iLvl | equipped item level |
| Vault | Great Vault progress (runs toward each slot) |
| Best runs | per-dungeon best level, colour-coded |
| Currencies | crest, Field Accolades, Voidlight Marl — with weekly earned/cap |

Sortable by any column. Characters with no score are hidden by default (`/kg all`
shows them).

**Void Cores tab** — collected / on-hand / spent / remaining / earned-this-week per
character, so you can see who still has upgrades banked.

## Install

CurseForge, Wago, or WoWInterface via your addon manager, or grab the zip from
[Releases](../../releases) and unpack it into
`World of Warcraft/_retail_/Interface/AddOns/`.

## Commands

```
/kg              toggle the window          (/keys and /keygrid also work)
/kg grid         open the M+ Grid tab
/kg cores        open the Void Cores tab
/kg all          show/hide zero-score characters
/kg hide Name-Realm    hide a row
/kg show Name-Realm    unhide a row
/kg capture      re-capture the current character now
/kg reset        reset the window position and size
```

## How the data works

This is the part worth understanding, because it explains what KeyGrid can and
cannot know.

The WoW addon API only ever exposes the **logged-in** character's M+ data. There is
no in-game way to read an alt's keystone. So KeyGrid captures a snapshot on login,
`/reload`, and on the relevant events, and stores it account-wide in `KeyGridDB`.

The practical consequence: **a character appears in the grid only after you have
logged into it at least once** with KeyGrid installed. Its keystone and vault are
as of that moment, not live.

Best runs and score can also come from Blizzard's REST API — see `keygrid-sync/`
below, which fills those in for alts you have not logged into.

## keygrid-sync (optional)

A small stdlib-only Python companion that pulls best-runs and rating for your whole
roster from the Blizzard API and writes them into a data file the addon merges at
load. See [keygrid-sync/README.md](keygrid-sync/README.md).

It needs a Blizzard API client (free) and never touches `KeyGridDB` — it writes a
separate global that the addon folds in on login. The addon works fine without it.

## Private mode

The source tree contains a Loot tab (`LootData.lua`, `UI/LootGrid.lua`) that shows
per-dungeon, per-spec M+ loot tables. It is **not part of released builds** and is
hidden unless you supply your own season data file (`KeyGrid/SeasonLoot.lua`) and
turn it on with `/kg private`.

The reason: a usable in-season loot table is a *curated* subset that no Blizzard API
exposes, and the one this was developed against belongs to another addon under an
All Rights Reserved licence. Shipping that data would be redistributing someone
else's work, so it stays out of every published artifact. The Encounter Journal
fallback in `LootData.lua` is KeyGrid's own code and is MIT like the rest.

## Building

Releases are produced by the [BigWigs packager](https://github.com/BigWigsMods/packager);
push a tag and CI publishes to CurseForge, Wago, WoWInterface and GitHub Releases.
To build locally without uploading:

```bash
curl -s https://raw.githubusercontent.com/BigWigsMods/packager/master/release.sh | bash -s -- -d
```

## Licence

MIT — see [LICENSE](LICENSE).
