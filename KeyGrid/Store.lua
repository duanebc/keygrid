-- KeyGrid/Store.lua
-- SavedVariables schema, read/write, deterministic merge, staleness.
-- Loads AFTER Sync/KeyGridSyncData.lua so imported data is present at merge time.

local ADDON, NS = ...
local Store = {}
NS.Store = Store

local SCHEMA_VERSION = 1
local WEEK = 7 * 24 * 3600

local DEFAULTS = {
  version = SCHEMA_VERSION,
  season  = { id = 0, mapIDs = {} },
  affixes = {},
  chars   = {},
  -- key -> currencyID, resolved once and shared by every character (the in-game
  -- currency list only shows what the logged-in character has actually earned).
  currencyIDs = {},
  -- privateMode gates the developer-only Loot tab; it has no effect in a
  -- released build, where SeasonLoot.lua and UI/LootGrid.lua are not shipped.
  ui      = { sortKey = "score", sortDir = "desc", point = nil, hidden = {}, showAll = false, tab = 1, privateMode = false, lootSpec = {}, lootHideCollected = true, lootSlot = "all" },
}

local function applyDefaults(db, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(db[k]) ~= "table" then db[k] = {} end
      applyDefaults(db[k], v)
    elseif db[k] == nil then
      db[k] = v
    end
  end
end

function Store.Init()
  KeyGridDB = KeyGridDB or {}
  applyDefaults(KeyGridDB, DEFAULTS)
  if (KeyGridDB.version or 0) < SCHEMA_VERSION then
    KeyGridDB.version = SCHEMA_VERSION
  end
  Store.db = KeyGridDB
end

function Store.DB() return KeyGridDB end

function Store.CharCount()
  local n = 0
  for _ in pairs(KeyGridDB.chars) do n = n + 1 end
  return n
end

function Store.GetOrCreateChar(key)
  local c = KeyGridDB.chars[key]
  if not c then
    c = { best = {} }
    KeyGridDB.chars[key] = c
  end
  c.best = c.best or {}
  return c
end

--------------------------------------------------------------------------------
-- Season / affixes
--------------------------------------------------------------------------------
function Store.SetSeasonMaps(maps)
  if type(maps) ~= "table" then return end
  local out = {}
  for i, id in ipairs(maps) do out[i] = id end
  KeyGridDB.season.mapIDs = out
end

function Store.SetSeasonMapsFromGame()
  if C_ChallengeMode and C_ChallengeMode.GetMapTable then
    local m = C_ChallengeMode.GetMapTable()
    if m and #m > 0 then Store.SetSeasonMaps(m) end
  end
end

function Store.SeasonMaps() return KeyGridDB.season.mapIDs or {} end

function Store.SetAffixes(ids) KeyGridDB.affixes = ids or {} end
function Store.Affixes() return KeyGridDB.affixes or {} end

--------------------------------------------------------------------------------
-- Staleness. resetAt = server-now + seconds-until-reset. Anything captured
-- before the most recent reset (resetAt - 1 week) is stale.
--------------------------------------------------------------------------------
function Store.NextResetAt()
  local secs = 0
  if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
    secs = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
  end
  return (GetServerTime() or time()) + secs
end

function Store.LastResetAt()
  return Store.NextResetAt() - WEEK
end

function Store.IsStale(capturedAt)
  if not capturedAt then return true end
  return capturedAt < Store.LastResetAt()
end

--------------------------------------------------------------------------------
-- Deterministic field-level merge (see spec 3.6). Newer wins; ties prefer api.
--------------------------------------------------------------------------------
function Store.MergeScore(c, score, at, source)
  if score == nil then return end
  at = at or 0
  local better = (not c.scoreAt)
    or (at > c.scoreAt)
    or (at == c.scoreAt and source == "api")
  if better then
    c.score = score
    c.scoreAt = at
    c.scoreSource = source
  end
end

function Store.MergeBest(c, mapID, run, source)
  mapID = tonumber(mapID)
  if not mapID or type(run) ~= "table" then return end
  local newAt = run.completedAt or 0
  local existing = c.best[mapID]
  if not existing then
    c.best[mapID] = {
      level = run.level, score = run.score, timed = run.timed,
      durationSec = run.durationSec or 0, completedAt = newAt, source = source,
    }
    return
  end
  local oldAt = existing.completedAt or 0
  if newAt > oldAt or (newAt == oldAt and source == "api") then
    existing.level       = run.level
    existing.score       = run.score
    existing.timed       = run.timed
    existing.durationSec = run.durationSec or 0
    existing.completedAt = newAt
    existing.source      = source
  end
end

-- Fold the sync-generated global into KeyGridDB. Never touches keystone/vault.
function Store.MergeSyncData()
  local sync = _G.KeyGridSyncData
  if type(sync) ~= "table" or type(sync.chars) ~= "table" then return end
  if sync.seasonId and (not KeyGridDB.season.id or KeyGridDB.season.id == 0) then
    KeyGridDB.season.id = sync.seasonId
  end
  KeyGridDB.lastSyncAt = sync.generatedAt
  KeyGridDB.lastSyncRegion = sync.region

  local count = 0
  for key, sc in pairs(sync.chars) do
    local c = Store.GetOrCreateChar(key)
    if not c.name then
      local name, realm = strsplit("-", key)
      c.name, c.realm = name, realm
    end
    if sc.name then c.name = sc.name end
    if sc.realm then c.realm = sc.realm end
    if sc.class and not c.class then c.class = sc.class end
    Store.MergeScore(c, sc.score, sync.generatedAt, "api")
    if type(sc.best) == "table" then
      for mapID, run in pairs(sc.best) do
        Store.MergeBest(c, mapID, run, "api")
      end
    end
    -- keystone & vault are in-game-only: intentionally not populated here.
    count = count + 1
  end
  NS.Debug("merged %d characters from KeyGridSyncData", count)
end

--------------------------------------------------------------------------------
-- Roster filter + sort for the UI
--------------------------------------------------------------------------------
function Store.SetSort(key)
  local ui = KeyGridDB.ui
  if ui.sortKey == key then
    ui.sortDir = (ui.sortDir == "desc") and "asc" or "desc"
  else
    ui.sortKey = key
    ui.sortDir = (key == "name") and "asc" or "desc"
  end
end

function Store.SortState() return KeyGridDB.ui.sortKey, KeyGridDB.ui.sortDir end

local function levelScore(c, mapID)
  local b = c.best and c.best[mapID]
  if not b then return 0, 0 end
  return b.level or 0, b.score or 0
end

function Store.SortList(list)
  local key = KeyGridDB.ui.sortKey or "score"
  local desc = (KeyGridDB.ui.sortDir or "desc") == "desc"

  table.sort(list, function(a, b)
    local av, bv, tieA, tieB
    if key == "name" then
      av, bv = (a.name or ""):lower(), (b.name or ""):lower()
    elseif key == "ilvl" then
      av, bv = a.ilvl or 0, b.ilvl or 0
    elseif key == "crest" then
      av, bv = (a.crest and a.crest.count) or 0, (b.crest and b.crest.count) or 0
    elseif key == "accol" then
      av, bv = (a.accolades and a.accolades.have) or 0, (b.accolades and b.accolades.have) or 0
    elseif key == "marl" then
      av, bv = (a.marl and a.marl.have) or 0, (b.marl and b.marl.have) or 0
    elseif type(key) == "number" then
      local al, as = levelScore(a, key)
      local bl, bs = levelScore(b, key)
      av, bv = al, bl
      tieA, tieB = as, bs
    else -- "score"
      av, bv = a.score or 0, b.score or 0
    end

    if av ~= bv then
      if desc then return av > bv else return av < bv end
    end
    -- stable tiebreaks
    if tieA and tieA ~= tieB then
      if desc then return tieA > tieB else return tieA < tieB end
    end
    local as, bs = a.score or 0, b.score or 0
    if as ~= bs then return as > bs end
    return (a._key or "") < (b._key or "")
  end)
end

function Store.CharList()
  local ui = KeyGridDB.ui
  local out = {}
  for key, c in pairs(KeyGridDB.chars) do
    c._key = key
    local score = c.score or 0
    if not ui.hidden[key] and (ui.showAll or score > 0) then
      out[#out + 1] = c
    end
  end
  Store.SortList(out)
  return out
end

function Store.Hide(key)   KeyGridDB.ui.hidden[key] = true end
function Store.Unhide(key) KeyGridDB.ui.hidden[key] = nil end
function Store.ToggleAll()
  KeyGridDB.ui.showAll = not KeyGridDB.ui.showAll
  return KeyGridDB.ui.showAll
end

function Store.SavePoint(point, relPoint, x, y)
  KeyGridDB.ui.point = { point = point, relPoint = relPoint, x = x, y = y }
end
function Store.GetPoint() return KeyGridDB.ui.point end
function Store.ClearPoint() KeyGridDB.ui.point = nil end
