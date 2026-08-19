-- KeyGrid/Config.lua
-- Slash commands.
--
-- The packager comments out the debug-marked blocks below, so they exist only in
-- a working checkout. That is where the developer-only dump commands and the
-- Loot tab live. (Don't write the marker tokens in prose -- the packager
-- substitutes them wherever they appear, including inside comments.)

local ADDON, NS = ...

SLASH_KEYGRID1 = "/kg"
SLASH_KEYGRID2 = "/keys"
SLASH_KEYGRID3 = "/keygrid"

--@debug@
-- Convenience reload alias. /reload and /reloadui are Blizzard built-ins; /rl is
-- not. Deliberately dev-only: several popular addons (ElvUI among them) also
-- claim /rl, and whoever loads last wins -- not a fight to pick in a release.
if not SlashCmdList["KGRELOAD"] then
  SLASH_KGRELOAD1 = "/rl"
  SlashCmdList["KGRELOAD"] = function() ReloadUI() end
end
--@end-debug@

-- Optional, and deliberately not advertised in the footer: it needs Python and a
-- Blizzard API client, which is a lot to put in front of someone who just wants
-- the grid. Whoever does type this has only ever seen the addon, not the repo, so
-- it has to be the whole recipe.
local function syncHelp()
  NS.Print("keygrid-sync fills in best runs + score for alts you haven't logged into.")
  -- .pkgmeta excludes keygrid-sync from the package, so an addon-manager install
  -- does NOT have it locally. GitHub is the only place to get it.
  print("  It is |cffff9999not part of the addon download|r — get the |cffffd100keygrid-sync|r folder from GitHub.")
  print("  1. Make a free API client at |cff88ccffhttps://develop.battle.net/access/clients|r")
  print("     and add the redirect URI |cffffd100https://localhost:8080/callback|r")
  print("  2. Set BNET_CLIENT_ID and BNET_CLIENT_SECRET (or fill ~/.keygrid/config.toml)")
  print("  3. Run it with Python 3.11+ from that folder:")
  print("     |cffffd100python keygrid_sync.py --verbose|r")
  print("     ...or without the browser step: |cffffd100python keygrid_sync.py --char "
    .. (NS.PlayerKey() or "Name-Realm") .. "|r")
  print("  4. First run creates the KeyGrid_SyncData addon: log out to character select")
  print("     once so the game sees it, then |cffffd100/reload|r. Later syncs need only /reload.")
  print("  Full setup: |cff88ccffhttps://github.com/duanebc/KeyGrid/tree/main/keygrid-sync|r")
end

local function usage()
  NS.Print("Commands:")
  NS.Print("  /kg                  toggle the window")
  NS.Print("  /kg grid             open the M+ grid tab")
  NS.Print("  /kg sync             how to run keygrid-sync (fills in alts)")
  NS.Print("  /kg all              toggle showing zero-score characters")
  NS.Print("  /kg hide Name-Realm  hide a row")
  NS.Print("  /kg show Name-Realm  unhide a row")
  NS.Print("  /kg capture          re-capture the current character now")
  NS.Print("  /kg reset            reset the window position")
  NS.Print("  /kg debug            toggle debug output")
  --@debug@
  NS.Print("Developer:")
  NS.Print("  /kg private          toggle the Loot tab")
  NS.Print("  /kg loot             open the Loot tab")
  NS.Print("  /kg lootall          toggle hiding loot you've already picked up")
  NS.Print("  /kg dump             print season mapIDs + names (fill NS.ABBR)")
  NS.Print("  /kg curdump          print currency IDs + what KeyGrid resolved")
  NS.Print("  /kg curfind <text>   search EVERY currency id by name")
  NS.Print("  /kg lootdump         verify Encounter Journal loot resolution")
  NS.Print("  /kg voidcache        dump hovered Voidcache IDs + contents")
  --@end-debug@
end

SlashCmdList["KEYGRID"] = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.-)$")
  cmd = (cmd or ""):lower()

  if cmd == "" then
    NS.UI.Toggle()
  elseif cmd == "grid" then
    NS.UI.Show(); NS.UI.ShowTab(1)
  elseif cmd == "sync" then
    syncHelp()
  elseif cmd == "cores" then
    -- Tab 2 is greyed out this season (see UI/Frame.lua); ShowTab would silently
    -- bounce back to the grid, so say why instead.
    NS.Print("The Void Cores tab is disabled — how cores work this season isn't pinned down yet.")
    NS.UI.Show(); NS.UI.ShowTab(1)
  --@debug@
  elseif cmd == "private" then
    if not NS.LootAvailable() then
      NS.Print("Loot tab unavailable: SeasonLoot.lua is not installed.")
    else
      local ui = NS.Store.DB().ui
      ui.privateMode = not ui.privateMode
      NS.Print("Private mode: " .. (ui.privateMode and "ON" or "OFF")
        .. " -- /reload to rebuild the tab strip.")
    end
  elseif cmd == "loot" then
    if NS.PrivateMode() then
      NS.UI.Show(); NS.UI.ShowTab(3)
    else
      NS.Print("Loot tab is off. Enable it with /kg private, then /reload.")
    end
  elseif cmd == "lootall" then
    local ui = NS.Store.DB().ui
    ui.lootHideCollected = not ui.lootHideCollected
    NS.Print("Loot tab: " .. (ui.lootHideCollected and "hiding items you've looted" or "showing all items"))
    if NS.PrivateMode() then NS.UI.Show(); NS.UI.ShowTab(3) end
  elseif cmd == "dump" then
    NS.Dungeons.Dump()
  elseif cmd == "curdump" then
    NS.Currencies.Dump()
  elseif cmd == "curfind" then
    NS.Currencies.Find(rest)
  elseif cmd == "lootdump" then
    if NS.Loot then NS.Loot.Dump() else NS.Print("Loot module not installed.") end
  elseif cmd == "voidcache" then
    if NS.Loot then NS.Loot.VoidcacheDump() else NS.Print("Loot module not installed.") end
  --@end-debug@
  elseif cmd == "all" then
    local on = NS.Store.ToggleAll()
    NS.Print("Zero-score characters: " .. (on and "shown" or "hidden"))
    NS.UI.Refresh()
  elseif cmd == "hide" then
    if rest ~= "" then
      NS.Store.Hide(rest); NS.Print("Hidden: " .. rest); NS.UI.Refresh()
    else NS.Print("Usage: /kg hide Name-Realm") end
  elseif cmd == "show" then
    if rest ~= "" then
      NS.Store.Unhide(rest); NS.Print("Shown: " .. rest); NS.UI.Refresh()
    else NS.Print("Usage: /kg show Name-Realm") end
  elseif cmd == "capture" then
    NS.Data.CaptureAll("manual")
    NS.Print("Captured " .. (NS.PlayerKey() or "current character") .. ".")
  elseif cmd == "reset" then
    if NS.UI.ResetPosition then NS.UI.ResetPosition() end
    NS.Print("Window position reset.")
  elseif cmd == "debug" then
    NS.debug = not NS.debug
    NS.Print("Debug: " .. (NS.debug and "ON" or "OFF"))
  else
    usage()
  end
end
