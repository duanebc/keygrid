# keygrid-sync

Pulls account-wide Mythic+ data from the Blizzard API and writes it into a small
companion addon, `KeyGrid_SyncData`, which KeyGrid merges at login.

The companion sits *beside* KeyGrid in `Interface/AddOns/`, not inside it, so an
addon manager updating KeyGrid can't delete your synced data. The script creates
it on first run — because it is a new `.toc`, you have to log out to character
select once for the game to notice it. After that a `/reload` is enough.

The addon works fine **without** this — it just won't show alts you haven't
logged in. The sync fills in every rated character's best runs and score
without alt-swapping.

## Setup

1. Create an API client at <https://develop.battle.net/access/clients>.
   - Register redirect URI `https://localhost:8080/callback` (needed only for
     the roster-enumeration flow).
2. Provide credentials one of two ways:
   - Env: `BNET_CLIENT_ID` and `BNET_CLIENT_SECRET`
   - `~/.keygrid/config.toml` (see `config.example.toml`)
3. Python 3.11+ (stdlib only; `cryptography` is optional and only smooths the
   HTTPS callback for the roster flow).

## Usage

```bash
# Full account roster (opens a browser once to authorize wow.profile):
python keygrid_sync.py --verbose

# Known characters only, no browser auth (client_credentials):
python keygrid_sync.py --char Yourchar-Yourrealm --char Youralt-Yourrealm

# See the output without writing:
python keygrid_sync.py --char Yourchar-Yourrealm --dry-run

# Explicit target / region / season:
python keygrid_sync.py --region us --season 14 --addon-path "<path to>/World of Warcraft/_retail_/Interface/AddOns/KeyGrid"
```

Flags: `--addon-path` (path to the installed **KeyGrid** folder; auto-detected if
omitted — `KeyGrid_SyncData` is created next to it), `--region` (default `us`),
`--season` (default: current), `--char Name-Realm` (repeatable), `--dry-run`,
`--verbose`.

The generated file is read at addon load, so a sync taken mid-session needs a
`/reload` in-game to appear. Running the script twice produces identical output
and never touches `KeyGridDB` — it writes a separate global that KeyGrid folds in
at login, so nothing you captured in-game is ever overwritten.

Keystones and Great Vault progress are deliberately **not** synced: the Blizzard
API doesn't expose them, so those stay in-game snapshots.
