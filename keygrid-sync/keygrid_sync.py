#!/usr/bin/env python3
"""keygrid-sync — pull account-wide Mythic+ data from the Blizzard API and
write it into the KeyGrid_SyncData companion addon.

Stdlib only (no pip install needed). See KeyGrid-SPEC.md section 5.

Auth:
  * client_credentials  — enough for character profile endpoints if you already
                          know the character names (pass --char Name-realm ...).
  * authorization_code  — with scope `wow.profile`, enumerates every character on
                          the account. Requires redirect URI
                          https://localhost:8080/callback registered on the
                          Blizzard dev app.

Credentials come from env (BNET_CLIENT_ID / BNET_CLIENT_SECRET) or
~/.keygrid/config.toml. Secrets are never written into the generated Lua file.
"""

from __future__ import annotations

import argparse
import base64
import http.server
import json
import os
import secrets
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

try:
    import tomllib  # py3.11+
except ModuleNotFoundError:  # pragma: no cover
    tomllib = None

CONFIG_DIR = Path.home() / ".keygrid"
CONFIG_FILE = CONFIG_DIR / "config.toml"
TOKEN_FILE = CONFIG_DIR / "token.json"
REDIRECT_URI = "https://localhost:8080/callback"
REDIRECT_PORT = 8080
SCOPE = "wow.profile"
LOCALE = "en_US"
INTER_REQUEST_SLEEP = 0.1  # be a good API citizen (limits are 100/s, 36k/hr)

VERBOSE = False


def log(msg: str) -> None:
    if VERBOSE:
        print(f"[keygrid-sync] {msg}", file=sys.stderr)


def die(msg: str, code: int = 1) -> "NoReturn":  # type: ignore[name-defined]
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


# ---------------------------------------------------------------------------
# Config / credentials
# ---------------------------------------------------------------------------
def load_config() -> dict:
    cfg: dict = {}
    if CONFIG_FILE.exists() and tomllib is not None:
        with CONFIG_FILE.open("rb") as fh:
            cfg = tomllib.load(fh)
    return cfg


def get_credentials(cfg: dict) -> tuple[str, str]:
    cid = os.environ.get("BNET_CLIENT_ID") or cfg.get("client_id")
    secret = os.environ.get("BNET_CLIENT_SECRET") or cfg.get("client_secret")
    if not cid or not secret:
        die(
            "missing Blizzard API credentials.\n"
            "  Set BNET_CLIENT_ID / BNET_CLIENT_SECRET, or put client_id / "
            f"client_secret in {CONFIG_FILE}.\n"
            "  Create an app at https://develop.battle.net/access/clients"
        )
    return cid, secret


def _write_secure_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data), encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass  # Windows: chmod is a no-op, ACLs govern access
    os.replace(tmp, path)


# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------
def http_get_json(url: str, token: str) -> dict | None:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None  # no runs / below M+ level requirement — skip quietly
        if e.code == 429:
            log("rate limited (429); backing off 1s")
            time.sleep(1.0)
            return http_get_json(url, token)
        raise
    finally:
        time.sleep(INTER_REQUEST_SLEEP)


def oauth_token(client_id: str, client_secret: str, data: dict) -> dict:
    body = urllib.parse.urlencode(data).encode()
    basic = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    req = urllib.request.Request(
        "https://oauth.battle.net/token",
        data=body,
        headers={
            "Authorization": f"Basic {basic}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        die(f"OAuth token request failed ({e.code}): {detail}")


# ---------------------------------------------------------------------------
# Token acquisition
# ---------------------------------------------------------------------------
def client_credentials_token(client_id: str, client_secret: str) -> str:
    log("requesting client_credentials token")
    tok = oauth_token(client_id, client_secret, {"grant_type": "client_credentials"})
    return tok["access_token"]


class _CallbackHandler(http.server.BaseHTTPRequestHandler):
    code: str | None = None
    expected_state: str | None = None

    def do_GET(self):  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/callback":
            self.send_response(404)
            self.end_headers()
            return
        params = urllib.parse.parse_qs(parsed.query)
        state = params.get("state", [None])[0]
        code = params.get("code", [None])[0]
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        if state == _CallbackHandler.expected_state and code:
            _CallbackHandler.code = code
            self.wfile.write(b"<h2>KeyGrid: authorized. You can close this tab.</h2>")
        else:
            self.wfile.write(b"<h2>KeyGrid: state mismatch. Try again.</h2>")

    def log_message(self, *_args):  # silence default logging
        pass


def _make_ssl_context() -> ssl.SSLContext | None:
    """Blizzard requires an https redirect URI. Generate a throwaway self-signed
    cert if `cryptography` is available; otherwise fall back to http and instruct
    the user to accept the browser warning / use http in the dev-app settings."""
    try:
        import datetime
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.x509.oid import NameOID
    except ModuleNotFoundError:
        return None

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "localhost")])
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.datetime.utcnow())
        .not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(minutes=10))
        .sign(key, hashes.SHA256())
    )
    tmp = CONFIG_DIR / "_cb.pem"
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    with tmp.open("wb") as fh:
        fh.write(cert.public_bytes(serialization.Encoding.PEM))
        fh.write(
            key.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.TraditionalOpenSSL,
                serialization.NoEncryption(),
            )
        )
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(str(tmp))
    return ctx


def authorization_code_token(client_id: str, client_secret: str) -> str:
    # reuse a cached refresh token if present
    if TOKEN_FILE.exists():
        try:
            cached = json.loads(TOKEN_FILE.read_text(encoding="utf-8"))
            if cached.get("refresh_token"):
                log("refreshing cached authorization token")
                tok = oauth_token(
                    client_id,
                    client_secret,
                    {"grant_type": "refresh_token", "refresh_token": cached["refresh_token"]},
                )
                if "access_token" in tok:
                    if "refresh_token" in tok:
                        _write_secure_json(TOKEN_FILE, tok)
                    return tok["access_token"]
        except (json.JSONDecodeError, urllib.error.HTTPError):
            log("cached token unusable; starting fresh authorization")

    state = secrets.token_urlsafe(16)
    _CallbackHandler.expected_state = state
    _CallbackHandler.code = None

    auth_url = "https://oauth.battle.net/authorize?" + urllib.parse.urlencode(
        {
            "client_id": client_id,
            "scope": SCOPE,
            "state": state,
            "redirect_uri": REDIRECT_URI,
            "response_type": "code",
        }
    )

    ctx = _make_ssl_context()
    server = http.server.HTTPServer(("localhost", REDIRECT_PORT), _CallbackHandler)
    if ctx is not None:
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
    else:
        log("no `cryptography` module: serving callback over http; accept the browser prompt")

    print("Opening browser to authorize KeyGrid (scope: wow.profile)...")
    print(f"If it doesn't open, visit:\n  {auth_url}")
    webbrowser.open(auth_url)

    # one-shot: handle requests until we capture the code
    deadline = time.time() + 300
    while _CallbackHandler.code is None and time.time() < deadline:
        server.handle_request()
    server.server_close()

    if not _CallbackHandler.code:
        die("did not receive an authorization code (timed out).")

    tok = oauth_token(
        client_id,
        client_secret,
        {
            "grant_type": "authorization_code",
            "code": _CallbackHandler.code,
            "redirect_uri": REDIRECT_URI,
        },
    )
    if "access_token" not in tok:
        die(f"authorization_code exchange failed: {tok}")
    _write_secure_json(TOKEN_FILE, tok)
    return tok["access_token"]


# ---------------------------------------------------------------------------
# Blizzard data
# ---------------------------------------------------------------------------
def api_base(region: str) -> str:
    return f"https://{region}.api.blizzard.com"


def realm_slug(realm: str) -> str:
    return realm.strip().lower().replace(" ", "-").replace("'", "")


def get_current_season_id(token: str, region: str) -> int | None:
    url = (
        f"{api_base(region)}/data/wow/mythic-keystone/season/index"
        f"?namespace=dynamic-{region}&locale={LOCALE}"
    )
    data = http_get_json(url, token)
    if not data:
        return None
    cur = data.get("current_season") or {}
    return cur.get("id")


def get_dungeon_index(token: str, region: str) -> dict[int, str]:
    url = (
        f"{api_base(region)}/data/wow/mythic-keystone/dungeon/index"
        f"?namespace=dynamic-{region}&locale={LOCALE}"
    )
    out: dict[int, str] = {}
    data = http_get_json(url, token)
    if data:
        for d in data.get("dungeons", []):
            out[d["id"]] = d.get("name", "")
    return out


def get_account_characters(token: str, region: str) -> list[tuple[str, str]]:
    """Enumerate (name, realmSlug) via the wow.profile roster endpoint."""
    url = f"{api_base(region)}/profile/user/wow?namespace=profile-{region}&locale={LOCALE}"
    data = http_get_json(url, token)
    chars: list[tuple[str, str]] = []
    if not data:
        return chars
    for account in data.get("wow_accounts", []):
        for ch in account.get("characters", []):
            name = ch.get("name", "")
            realm = ch.get("realm", {}).get("slug", "")
            if name and realm:
                chars.append((name, realm))
    return chars


def get_character_mplus(
    token: str, region: str, name: str, realm: str, season_id: int, dungeon_names: dict[int, str]
) -> dict | None:
    lname = name.lower()
    slug = realm_slug(realm)
    season_url = (
        f"{api_base(region)}/profile/wow/character/{slug}/{lname}"
        f"/mythic-keystone-profile/season/{season_id}"
        f"?namespace=profile-{region}&locale={LOCALE}"
    )
    season = http_get_json(season_url, token)

    overall_url = (
        f"{api_base(region)}/profile/wow/character/{slug}/{lname}"
        f"/mythic-keystone-profile"
        f"?namespace=profile-{region}&locale={LOCALE}"
    )
    overall = http_get_json(overall_url, token)

    if season is None and overall is None:
        return None  # 404 both — no M+ data, skip quietly

    rating = 0.0
    if overall and isinstance(overall.get("current_mythic_rating"), dict):
        rating = overall["current_mythic_rating"].get("rating", 0.0)

    best: dict[int, dict] = {}
    for run in (season or {}).get("best_runs", []):
        did = run.get("dungeon", {}).get("id")
        if did is None:
            continue
        if did not in dungeon_names:
            log(f"warning: dungeon id {did} ({run.get('dungeon', {}).get('name')}) "
                f"not in dungeon index — check against /kg dump")
        entry = {
            "level": run.get("keystone_level", 0),
            "score": round(run.get("mythic_rating", {}).get("rating", 0) or 0),
            "timed": bool(run.get("is_completed_within_time")),
            "durationSec": int((run.get("duration", 0) or 0) / 1000),
            "completedAt": int((run.get("completed_timestamp", 0) or 0) / 1000),
        }
        # keep the higher-level record per dungeon
        if did not in best or entry["level"] > best[did]["level"]:
            best[did] = entry

    return {"score": round(rating), "best": best}


# ---------------------------------------------------------------------------
# Lua output
# ---------------------------------------------------------------------------
def lua_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def render_lua(chars: dict[str, dict], region: str, season_id: int, generated_at: int) -> str:
    lines = [
        f"-- Generated by keygrid-sync at {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(generated_at))}. Do not edit.",
        "KeyGridSyncData = {",
        f"  generatedAt = {generated_at},",
        f'  region = "{region}",',
        f"  seasonId = {season_id},",
        "  chars = {",
    ]
    for key in sorted(chars):
        c = chars[key]
        lines.append(f'    ["{lua_escape(key)}"] = {{')
        lines.append(f"      score = {c['score']},")
        if c.get("name"):
            lines.append(f'      name = "{lua_escape(c["name"])}",')
        if c.get("realm"):
            lines.append(f'      realm = "{lua_escape(c["realm"])}",')
        lines.append("      best = {")
        for did in sorted(c["best"]):
            b = c["best"][did]
            lines.append(
                f"        [{did}] = {{ level={b['level']}, score={b['score']}, "
                f"timed={str(b['timed']).lower()}, durationSec={b['durationSec']}, "
                f"completedAt={b['completedAt']} }},"
            )
        lines.append("      },")
        lines.append("    },")
    lines.append("  },")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def write_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    os.replace(tmp, path)


# ---------------------------------------------------------------------------
# Companion addon
#
# The generated data used to live inside the KeyGrid folder. That folder is
# deleted and replaced wholesale every time an addon manager updates KeyGrid,
# which silently wiped the sync. It now goes in its own tiny addon that no
# updater manages.
# ---------------------------------------------------------------------------
SYNC_ADDON = "KeyGrid_SyncData"
FALLBACK_INTERFACE = "120007"


def keygrid_interface_version(keygrid_path: Path) -> str:
    """Read '## Interface:' out of the installed KeyGrid.toc so the companion
    addon never shows up as out of date after a patch."""
    toc = keygrid_path / "KeyGrid.toc"
    try:
        for line in toc.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.lower().startswith("## interface:"):
                value = line.split(":", 1)[1].strip()
                if value.isdigit():
                    return value
    except OSError:
        pass
    log(f"could not read Interface from {toc}; using {FALLBACK_INTERFACE}")
    return FALLBACK_INTERFACE


def render_toc(interface: str) -> str:
    return "\n".join([
        f"## Interface: {interface}",
        "## Title: KeyGrid Sync Data",
        "## Notes: Generated data for KeyGrid. Written by keygrid-sync.",
        "## Author: keygrid-sync",
        "## Version: 1.0",
        "## Dependencies: KeyGrid",
        "",
        "# This addon exists only to hold generated data outside the KeyGrid",
        "# folder, so addon-manager updates do not delete it. Safe to remove;",
        "# KeyGrid works fine without it.",
        "",
        "KeyGridSyncData.lua",
        "",
    ])


# ---------------------------------------------------------------------------
# Addon path auto-detection
# ---------------------------------------------------------------------------
def autodetect_addon_path() -> Path | None:
    candidates = [
        Path(r"C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/KeyGrid"),
        Path(r"C:/Program Files/World of Warcraft/_retail_/Interface/AddOns/KeyGrid"),
        Path.home() / "Applications/World of Warcraft/_retail_/Interface/AddOns/KeyGrid",
    ]
    for drive in "CDEFG":
        candidates.append(Path(f"{drive}:/World of Warcraft/_retail_/Interface/AddOns/KeyGrid"))
    for c in candidates:
        if c.exists():
            return c
    return None


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    global VERBOSE
    p = argparse.ArgumentParser(description="Sync account-wide M+ data into KeyGrid.")
    p.add_argument("--addon-path", help="Path to the installed KeyGrid addon folder")
    p.add_argument("--region", default="us", help="Region (us, eu, kr, tw). Default: us")
    p.add_argument("--season", type=int, help="Season id (default: current)")
    p.add_argument("--char", action="append", default=[],
                   help="Name-realm to sync (repeatable). Skips roster enumeration "
                        "and uses client_credentials only.")
    p.add_argument("--dry-run", action="store_true", help="Print the Lua, do not write")
    p.add_argument("--verbose", action="store_true")
    args = p.parse_args()
    VERBOSE = args.verbose
    region = args.region.lower()

    cfg = load_config()
    client_id, client_secret = get_credentials(cfg)

    # Choose auth flow: explicit --char list => client_credentials; else roster auth.
    if args.char:
        token = client_credentials_token(client_id, client_secret)
        roster = []
        for spec in args.char:
            if "-" not in spec:
                die(f"--char must be Name-Realm, got '{spec}'")
            name, realm = spec.split("-", 1)
            roster.append((name, realm))
    else:
        token = authorization_code_token(client_id, client_secret)
        log("enumerating account roster")
        roster = get_account_characters(token, region)
        if not roster:
            die("no characters returned from the account roster endpoint.")

    season_id = args.season or get_current_season_id(token, region)
    if not season_id:
        die("could not determine the current season id (pass --season).")
    log(f"season {season_id}, region {region}, {len(roster)} characters")

    dungeon_names = get_dungeon_index(token, region)

    chars: dict[str, dict] = {}
    for name, realm in roster:
        data = get_character_mplus(token, region, name, realm, season_id, dungeon_names)
        if data is None:
            log(f"skip {name}-{realm} (no M+ data)")
            continue
        # Store with a display realm (title-cased slug words) to match in-game key.
        display_realm = "".join(w.capitalize() for w in realm.replace("-", " ").split())
        key = f"{name}-{display_realm}"
        data["name"] = name
        data["realm"] = display_realm
        chars[key] = data
        log(f"ok  {key}: score={data['score']} runs={len(data['best'])}")

    generated_at = int(time.time())
    lua = render_lua(chars, region, season_id, generated_at)

    if args.dry_run:
        print(lua)
        print(f"\n-- dry run: {len(chars)} characters (not written)", file=sys.stderr)
        return

    addon_path = Path(args.addon_path) if args.addon_path else autodetect_addon_path()
    if not addon_path:
        die("could not auto-detect the KeyGrid addon folder; pass --addon-path.")
    addon_path = Path(addon_path)

    # Sibling of KeyGrid, not inside it -- see the SYNC_ADDON comment above.
    sync_dir = addon_path.parent / SYNC_ADDON
    is_new = not (sync_dir / f"{SYNC_ADDON}.toc").exists()
    write_atomic(sync_dir / f"{SYNC_ADDON}.toc", render_toc(keygrid_interface_version(addon_path)))
    out = sync_dir / "KeyGridSyncData.lua"
    write_atomic(out, lua)
    print(f"Wrote {len(chars)} characters to {out}")
    if is_new:
        print(f"Created the {SYNC_ADDON} addon. New .toc files are only picked up at")
        print("character select, so log out fully once -- a /reload is not enough.")
    else:
        print("Note: run /reload in-game for a mid-session sync to take effect.")


if __name__ == "__main__":
    main()
