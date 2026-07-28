-- KeyGrid/Core.lua
-- Addon namespace, event router, init. Loaded first.

local ADDON, NS = ...
_G.KeyGrid = NS            -- expose global so /kg dump and KeyGrid.ABBR work per spec
NS.name = ADDON
-- Substituted by the packager at build time from the git tag. An unsubstituted
-- token means this is a working checkout, not a release.
NS.version = "@project-version@"
if NS.version:find("project%-version") then NS.version = "dev" end

--------------------------------------------------------------------------------
-- Private mode
--
-- The Loot tab depends on SeasonLoot.lua, which is stripped from packaged builds
-- (its data is not ours to redistribute — see README). So the file's presence is
-- what distinguishes a developer checkout from a release, and even then the tab
-- stays hidden until /kg private turns it on.
--------------------------------------------------------------------------------
function NS.LootAvailable()
  return NS.SEASONLOOT ~= nil and NS.UI ~= nil and NS.UI.BuildLootPanel ~= nil
end

function NS.PrivateMode()
  return NS.LootAvailable() and NS.Store.DB().ui.privateMode == true
end

--------------------------------------------------------------------------------
-- Output helpers
--------------------------------------------------------------------------------
function NS.Print(...)
  print("|cff66ccffKeyGrid|r:", ...)
end

NS.debug = false
function NS.Debug(fmt, ...)
  if not NS.debug then return end
  local ok, s = pcall(string.format, fmt, ...)
  print("|cff888888KeyGrid dbg|r:", ok and s or tostring(fmt))
end

function NS.After(sec, fn)
  if C_Timer and C_Timer.After then
    C_Timer.After(sec, fn)
  else
    fn()
  end
end

--------------------------------------------------------------------------------
-- Event router: NS.On(event, handler). Handlers run inside pcall so one bad
-- capture never breaks the rest (acceptance: no Lua errors, no cascade).
--------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
NS.eventFrame = frame
local handlers = {}

function NS.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then NS.Debug("could not register event %s", event) end
  end
  table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, event, ...)
    if not ok then NS.Debug("handler error [%s]: %s", event, tostring(err)) end
  end
end)

--------------------------------------------------------------------------------
-- Init flow
--------------------------------------------------------------------------------
NS.On("ADDON_LOADED", function(_, name)
  if name ~= ADDON then return end
  NS.Store.Init()
  NS.initialized = true
  NS.Debug("initialized; %d cached characters", NS.Store.CharCount())
end)

-- KeyGridSyncData lives in the separate KeyGrid_SyncData addon (so addon-manager
-- updates can't delete it), which loads after us. PLAYER_LOGIN is the first
-- event guaranteed to fire once every addon has loaded, so merge there.
-- MergeSyncData is a no-op when the companion addon isn't installed.
NS.On("PLAYER_LOGIN", function()
  NS.Store.MergeSyncData()
end)

NS.On("PLAYER_ENTERING_WORLD", function()
  -- Fires on both login AND /reload. Season pool + affixes are async: request
  -- now, then re-capture this character's stats. Two passes because best-run and
  -- season data can populate a little later on a fresh reload — the second pass
  -- catches anything the first was too early to read.
  if C_MythicPlus then
    if C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
    if C_MythicPlus.RequestCurrentAffixes then pcall(C_MythicPlus.RequestCurrentAffixes) end
  end
  NS.After(2, function() if NS.Data then NS.Data.CaptureAll("enter-world") end end)
  NS.After(6, function() if NS.Data then NS.Data.CaptureAll("enter-world-2") end end)
end)
