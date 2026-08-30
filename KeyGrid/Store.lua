-- KeyGrid/Store.lua
-- SavedVariables schema, read/write, deterministic merge, staleness.
-- Loads AFTER Sync/KeyGridSyncData.lua so imported data is present at merge time.

local ADDON, NS = ...
local Store = {}
NS.Store = Store

local SCHEMA_VERSION = 3
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
  --
  -- tabId is a string, not an index: the tab strip gains and loses a Loot tab
  -- depending on the build, so a saved number means different things in
  -- different checkouts.
  ui = {
    sortKey = "score", sortDir = "desc", point = nil,
    hidden = {}, showAll = false,
    tabId = "grid", scale = 1,
    minimap = { angle = 200, hide = false, locked = false },
    privateMode = false, lootSpec = {}, lootHideCollected = true, lootSlot = "all",
  },
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
  -- Read the old shape BEFORE applyDefaults fills the gaps in, or every
  -- migration below sees a table that already looks migrated.
  local fresh = next(KeyGridDB) == nil
  local prev = KeyGridDB.version or 0
  local legacyTab = KeyGridDB.ui and KeyGridDB.ui.tab

  applyDefaults(KeyGridDB, DEFAULTS)

  -- v1 persisted the tab as an index, and index 3 meant the Loot tab -- but only
  -- in a developer checkout. Settings now occupies 3 in every build, so a stale
  -- number would silently drop people onto a tab they never chose.
  if not fresh and prev < 2 and type(legacyTab) == "number" then
    KeyGridDB.ui.tabId = (legacyTab == 2 and "cores")
      or (legacyTab == 3 and "loot")
      or "grid"
  end
  KeyGridDB.ui.tab = nil
  -- v2 kept one run per dungeon -- whichever was the higher level, timed or not
  -- -- so a blown timer could hide a beaten one. Move each stored run into the
  -- slot it belongs in; the one that is missing fills itself in on the next
  -- capture or sync.
  if not fresh and prev < 3 then
    for _, c in pairs(KeyGridDB.chars) do
      for mapID, b in pairs(c.best or {}) do
        if type(b) == "table" and b.level and not (b.intime or b.overtime) then
          c.best[mapID] = {
            [b.timed and "intime" or "overtime"] = {
              level = b.level, score = b.score, durationSec = b.durationSec or 0,
              completedAt = b.completedAt or 0, source = b.source,
            },
          }
        end
      end
    end
  end
  KeyGridDB.version = SCHEMA_VERSION
  -- Records written before scores were season-stamped have no high-water mark;
  -- seed it from the cached score so the roster filter behaves unchanged. The
  -- score itself stays unstamped, so it reads as "not this season" until the
  -- character is captured again -- which is the honest answer, since nothing
  -- here can tell whether that number survived the season roll.
  for _, c in pairs(KeyGridDB.chars) do
    if not c.peakScore and (c.score or 0) > 0 then c.peakScore = c.score end
  end
  -- Forget cached ids for currencies KeyGrid no longer tracks, so a retired key
  -- (last season's) can't sit in SavedVariables forever.
  if NS.Currencies then
    for key in pairs(KeyGridDB.currencyIDs) do
      if not NS.Currencies.DEFS[key] then KeyGridDB.currencyIDs[key] = nil end
    end
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

function Store.SetSeasonID(id)
  id = tonumber(id)
  if id and id > 0 then KeyGridDB.season.id = id end
end

function Store.SeasonID() return KeyGridDB.season.id or 0 end

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
function Store.MergeScore(c, score, at, source, season)
  if score == nil then return end
  at = at or 0
  local better = (not c.scoreAt)
    or (at > c.scoreAt)
    or (at == c.scoreAt and source == "api")
  if better then
    c.score = score
    c.scoreAt = at
    c.scoreSource = source
    -- Which season the number belongs to. Without this a rating captured last
    -- season is indistinguishable from a real one, and the game has since
    -- zeroed it.
    if season then c.scoreSeason = season end
    -- Sticky high-water mark. c.score legitimately drops to 0 at a season roll,
    -- and the roster filter needs to keep telling an M+ character apart from a
    -- bank alt that has never run one.
    if score > (c.peakScore or 0) then c.peakScore = score end
  end
end

-- The rating a character actually holds *this* season, which is what the grid
-- shows. 0 means either no runs this season or no capture since the season
-- rolled -- both cases where last season's number would be a lie.
function Store.SeasonScore(c)
  if not c then return 0 end
  local season = NS.Dungeons and NS.Dungeons.SeasonID and NS.Dungeons.SeasonID()
  -- Season unknown (API not ready, nothing cached): don't blank real data.
  if not season then return c.score or 0 end
  if c.scoreSeason ~= season then return 0 end
  return c.score or 0
end

--------------------------------------------------------------------------------
-- Best runs. A dungeon holds two records, the way the game's own
-- GetSeasonBestForMap answers: the best run you beat the timer on, and the best
-- one you did not. They are kept apart because they answer different questions
-- -- an over-time +14 says the group can clear the dungeon, a timed +10 is the
-- number that is actually worth score -- and one record could only ever hold the
-- higher of the two, which made a beaten timer invisible behind a blown one.
--
--   c.best[mapID] = { intime = <run>, overtime = <run> }
--   <run>         = { level, score, durationSec, completedAt, source }
--
-- Either slot may be missing. Store.ShownRun picks the one a cell displays.
--------------------------------------------------------------------------------
local function slotFor(run) return run.timed and "intime" or "overtime" end

function Store.MergeBest(c, mapID, run, source)
  mapID = tonumber(mapID)
  if not mapID or type(run) ~= "table" then return end
  local rec = c.best[mapID]
  if not rec then
    rec = {}
    c.best[mapID] = rec
  end
  local slot = slotFor(run)
  local newAt = run.completedAt or 0
  local existing = rec[slot]
  if not existing then
    rec[slot] = {
      level = run.level, score = run.score,
      durationSec = run.durationSec or 0, completedAt = newAt, source = source,
    }
    return
  end
  -- Both sources report a season best, so a later completion is a better run.
  -- The api tiebreak stands for a run KeyGrid saw in game and the API then
  -- confirmed: same run, better provenance.
  local oldAt = existing.completedAt or 0
  if newAt > oldAt or (newAt == oldAt and source == "api") then
    existing.level       = run.level
    existing.score       = run.score
    existing.durationSec = run.durationSec or 0
    existing.completedAt = newAt
    existing.source      = source
  end
end

-- The two records, timed first. Either may be nil.
function Store.Runs(c, mapID)
  local rec = c.best and c.best[mapID]
  if not rec then return nil, nil end
  return rec.intime, rec.overtime
end

-- What a dungeon cell shows: the best timed run, since that is the one that
-- carries score and the one a key is chosen against. A dungeon with nothing but
-- an over-time run still shows it -- "never timed" and "never run" are different
-- answers, and the cell marks which it is. Second return: true when the run
-- being shown is an over-time one.
function Store.ShownRun(c, mapID)
  local intime, overtime = Store.Runs(c, mapID)
  if intime then return intime, false end
  if overtime then return overtime, true end
  return nil, false
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
    Store.MergeScore(c, sc.score, sync.generatedAt, "api", sync.seasonId)
    if type(sc.best) == "table" then
      for mapID, entry in pairs(sc.best) do
        -- Sync data written before the split holds a single run per dungeon;
        -- MergeBest files it by its own `timed` flag either way, so old
        -- KeyGrid_SyncData still merges correctly (just half the picture, until
        -- keygrid-sync is run again).
        if entry.intime or entry.overtime then
          -- The slot it arrived in is what decides, not a flag inside it: set
          -- the flag to match so MergeBest files it there whatever the
          -- generator wrote.
          if entry.intime then
            entry.intime.timed = true
            Store.MergeBest(c, mapID, entry.intime, "api")
          end
          if entry.overtime then
            entry.overtime.timed = false
            Store.MergeBest(c, mapID, entry.overtime, "api")
          end
        else
          Store.MergeBest(c, mapID, entry, "api")
        end
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

-- Sort a dungeon column on what its cells show, so the order matches the eye.
local function levelScore(c, mapID)
  local b = Store.ShownRun(c, mapID)
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
    elseif NS.Currencies and NS.Currencies.ColumnByID(key) then
      -- Every gearing-currency column sorts on its on-hand count; the record
      -- lives on the character under the column's own id.
      av, bv = (a[key] and a[key].have) or 0, (b[key] and b[key].have) or 0
    elseif type(key) == "number" then
      local al, as = levelScore(a, key)
      local bl, bs = levelScore(b, key)
      av, bv = al, bl
      tieA, tieB = as, bs
    else -- "score"
      -- Sort on what the column shows, so the N/A rows collect at one end.
      av, bv = Store.SeasonScore(a), Store.SeasonScore(b)
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
    -- Filter on the high-water mark, not this season's score: a character who
    -- has simply not run a key yet this season still belongs in the grid.
    local score = c.peakScore or c.score or 0
    if not ui.hidden[key] and (ui.showAll or score > 0) then
      out[#out + 1] = c
    end
  end
  Store.SortList(out)
  return out
end

-- A sort key can name a column that is no longer on screen -- the season's
-- dungeon set rotates, and the saved key may be last season's mapID. Sorting by
-- it draws no arrow anywhere and leaves the roster in an order nothing explains,
-- so fall back to the first sortable column that is actually present.
function Store.EnsureSortVisible(cols)
  local key = KeyGridDB.ui.sortKey
  local first
  for _, c in ipairs(cols) do
    if c.sortable then
      if c.id == key then return false end
      first = first or c.id
    end
  end
  KeyGridDB.ui.sortKey = first or "name"
  KeyGridDB.ui.sortDir = (KeyGridDB.ui.sortKey == "name") and "asc" or "desc"
  return true
end

--------------------------------------------------------------------------------
-- Every known character, filtered by nothing.
--
-- Store.CharList hides characters that are hidden or have never scored, which is
-- exactly the set the Settings tab has to show -- you cannot un-hide a row you
-- cannot see.
--------------------------------------------------------------------------------
function Store.AllChars()
  local out = {}
  for key, c in pairs(KeyGridDB.chars) do
    c._key = key            -- CharList sets this as a side effect; cells rely on it
    out[#out + 1] = c
  end
  table.sort(out, function(a, b)
    return (a.name or a._key or ""):lower() < (b.name or b._key or ""):lower()
  end)
  return out
end

function Store.Forget(key) KeyGridDB.chars[key] = nil end

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
