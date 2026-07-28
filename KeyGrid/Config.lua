-- KeyGrid/Config.lua
-- Slash commands.
--
-- Blocks marked --@debug@ / --@end-debug@ are commented out by the packager, so
-- they exist only in a working checkout. That is where the developer-only dump
-- commands and the Loot tab live.

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

local function usage()
  NS.Print("Commands:")
  NS.Print("  /kg                  toggle the window")
  NS.Print("  /kg grid             open the M+ grid tab")
  NS.Print("  /kg cores            open the Void Cores tab")
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
  elseif cmd == "cores" then
    NS.UI.Show(); NS.UI.ShowTab(2)
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
