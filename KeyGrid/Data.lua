-- KeyGrid/Data.lua
-- Capture the current character's keystone, best runs, score, vault, identity.
-- All capture is gated behind combat and wrapped so a nil API never errors.

local ADDON, NS = ...
local Data = {}
NS.Data = Data

local function playerKey()
  local name = UnitName("player")
  local realm = GetNormalizedRealmName() or GetRealmName() or ""
  realm = realm:gsub("%s+", "")
  return name .. "-" .. realm, name, realm
end
NS.PlayerKey = playerKey

local function refreshUI()
  if NS.UI and NS.UI.Refresh then NS.UI.Refresh() end
end

--------------------------------------------------------------------------------
-- Individual captures
--------------------------------------------------------------------------------
function Data.CaptureIdentity(c)
  c.name = UnitName("player") or c.name
  local _, classFile, classID = UnitClass("player")
  c.class = classFile or c.class
  c.classId = classID or c.classId
  c.level = UnitLevel("player") or c.level
  -- Only overwrite the cached iLvl with a real value. GetAverageItemLevel returns
  -- 0 (not nil) before it's ready / mid-logout, and 0 is truthy in Lua, so a naive
  -- assignment would wipe the cached value for alts. Keep the last good value.
  local overall, equipped = GetAverageItemLevel()
  local il = (equipped and equipped > 0) and equipped or overall
  if il and il > 0 then c.ilvl = il end
  c.ilvl = c.ilvl or 0
  -- current spec (for the Loot tab's default filter)
  if GetSpecialization and GetSpecializationInfo then
    local idx = GetSpecialization()
    if idx then
      local sid = GetSpecializationInfo(idx)
      if sid then c.specId = sid end
    end
  end
end

-- M+ data isn't there the instant you log in, and GetOverallDungeonScore reads 0
-- until it arrives. Once the season's map table has landed the API is answering
-- properly, and from then on a 0 means what it says: no runs this season.
local function mplusDataReady()
  if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return false end
  local maps = C_ChallengeMode.GetMapTable()
  return type(maps) == "table" and #maps > 0
end

function Data.CaptureScore(c, now)
  if not (C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore) then return end
  local score = C_ChallengeMode.GetOverallDungeonScore()
  if not score then return end
  -- A 0 before the data loads is noise and must not overwrite a cached score;
  -- a 0 afterwards is a real "hasn't run one this season" and has to land, or
  -- the row keeps showing a rating the character no longer has.
  if score == 0 and not mplusDataReady() then return end
  NS.Store.MergeScore(c, score, now, "ingame", NS.Dungeons.SeasonID())
end

local function completionEpoch(cd)
  if type(cd) == "number" then return cd end
  if type(cd) == "table" then
    local ok, t = pcall(time, {
      year = cd.year, month = cd.month, day = cd.day,
      hour = cd.hour or 0, min = cd.minute or cd.min or 0,
    })
    if ok and t then return t end
  end
  return GetServerTime()
end

local function normRun(info, timed)
  if not info then return nil end
  return {
    level = info.level,
    score = info.dungeonScore,
    timed = timed,
    durationSec = info.durationSec or 0,
    completedAt = completionEpoch(info.completionDate),
  }
end

-- Both of the game's season bests, stored side by side. Picking one used to lose
-- the other: an over-time +14 outranked a timed +10 and the grid showed the +14,
-- which is the run that is worth nothing. See Store.MergeBest.
function Data.CaptureBest(c, now)
  if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return end
  local maps = C_ChallengeMode.GetMapTable()
  if type(maps) ~= "table" or #maps == 0 then return end
  NS.Store.SetSeasonMaps(maps)
  for _, mapID in ipairs(maps) do
    if C_MythicPlus and C_MythicPlus.GetSeasonBestForMap then
      local intime, overtime = C_MythicPlus.GetSeasonBestForMap(mapID)
      local timed, over = normRun(intime, true), normRun(overtime, false)
      if timed and timed.level then NS.Store.MergeBest(c, mapID, timed, "ingame") end
      if over and over.level then NS.Store.MergeBest(c, mapID, over, "ingame") end
    end
  end
end

-- Parse "Hkeystone:itemID:challengeMapID:level:affix1:affix2:affix3:affix4".
local function parseKeystoneLink(link)
  local payload = link:match("keystone:([%-%d:]+)")
  if not payload then return end
  local parts = { strsplit(":", payload) }
  local mapID = tonumber(parts[2])
  local level = tonumber(parts[3])
  return mapID, level
end

-- Bags are readable once the backpack (bag 0) reports its slots. Until then a
-- nil keystone accessor just means data isn't loaded yet, not "no key".
local function bagsReadable()
  if not (C_Container and C_Container.GetContainerNumSlots) then return false end
  return (C_Container.GetContainerNumSlots(0) or 0) > 0
end

function Data.ScanBagsForKeystone()
  if not (C_Container and C_Container.GetContainerNumSlots) then return end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    local slots = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, slots do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link and link:find("keystone:", 1, true) then
        local mapID, level = parseKeystoneLink(link)
        if mapID and level then return mapID, level end
      end
    end
  end
end

-- Returns true when the keystone state was read *authoritatively* (a key was
-- found, or bags were readable and held none). Returns false when we couldn't
-- read yet — in which case the cached key is left untouched so an early-login
-- race can never wipe a real key. This is what makes each character's key
-- survive in the account-wide cache for other characters to read.
function Data.CaptureKeystone(c, now)
  local mapID, level
  if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
    mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
  end
  if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel then
    level = C_MythicPlus.GetOwnedKeystoneLevel()
  end
  if not (mapID and level) then
    local bMap, bLevel = Data.ScanBagsForKeystone()
    mapID = mapID or bMap
    level = level or bLevel
  end

  if mapID and level then
    c.keystone = { mapID = mapID, level = level, capturedAt = now }
    return true
  end

  -- No key found. Only record an authoritative keyless snapshot (shows "--")
  -- once bags are confirmed readable; otherwise keep whatever we had cached.
  if bagsReadable() then
    c.keystone = { mapID = nil, level = nil, capturedAt = now }
    return true
  end
  return false
end

function Data.CaptureVault(c, now)
  if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities) then return end
  local kind = (Enum and Enum.WeeklyRewardChestThresholdType
    and Enum.WeeklyRewardChestThresholdType.Activities) or 1
  local acts = C_WeeklyRewards.GetActivities(kind)
  if type(acts) ~= "table" then return end
  local vault = { capturedAt = now }
  for _, a in ipairs(acts) do
    vault[#vault + 1] = { threshold = a.threshold, progress = a.progress, level = a.level }
  end
  c.vault = vault
  if C_MythicPlus and C_MythicPlus.IsWeeklyRewardAvailable then
    c.vaultAvailable = C_MythicPlus.IsWeeklyRewardAvailable()
  end
end

-- Gearing currencies: one snapshot per NS.Currencies.COLUMNS entry, plus the
-- companion currencies and the season's crest set. Each is collected/on-hand/spent/season-cap.
-- In-game only, cached per character in the account-wide DB (like keystones), so
-- alts keep showing their last count. A currency that can't be resolved leaves
-- the cached snapshot untouched rather than blanking it — the same early-login
-- race guard the keystone capture uses.
-- This week's completed runs, high to low.
--
-- CaptureBest records season bests per map, which is a different question: the
-- vault is built from this week, counts repeats of the same dungeon, and cares
-- only about levels. Without them "how many more keys do I need" has to be
-- worked out by hand, per character, which is the thing the grid exists to
-- spare you.
--
-- Twenty is kept although the thresholds stop at eight: headroom for showing the
-- top eight, and for a threshold that moves in a later season.
local MAX_WEEKLY_RUNS = 20

function Data.CaptureWeeklyRuns(c, now)
  if not (C_MythicPlus and C_MythicPlus.GetRunHistory) then return false end

  -- The two-argument form asks for this week only, completed only. Clients have
  -- disagreed about the signature, so a no-argument call is the fallback and the
  -- week is filtered by hand afterwards.
  local ok, runs = pcall(C_MythicPlus.GetRunHistory, false, true)
  if not ok or type(runs) ~= "table" then
    ok, runs = pcall(C_MythicPlus.GetRunHistory)
  end
  if not ok or type(runs) ~= "table" then return false end

  local levels = {}
  for _, run in ipairs(runs) do
    if type(run) == "table" then
      -- thisWeek is absent on the filtered form; absence means yes, since this
      -- week is what was asked for.
      local thisWeek = (run.thisWeek == nil) or run.thisWeek
      local level = tonumber(run.level)
      if thisWeek and level and level > 0 and run.completed ~= false then
        levels[#levels + 1] = level
      end
    end
  end

  -- Nothing read is not the same as nothing run. An empty answer in the first
  -- seconds after login would otherwise wipe a good snapshot, which is the same
  -- race the keystone capture guards against.
  if #levels == 0 and c.weeklyRuns and #(c.weeklyRuns.levels or {}) > 0
    and not NS.Store.IsStale(c.weeklyRuns.capturedAt) then
    return false
  end

  table.sort(levels, function(a, b) return a > b end)
  while #levels > MAX_WEEKLY_RUNS do table.remove(levels) end
  c.weeklyRuns = { capturedAt = now, levels = levels }
  return true
end

--------------------------------------------------------------------------------
-- Vault arithmetic
--------------------------------------------------------------------------------

-- The vault reward is the lowest of your top eight runs, so eight is the number
-- every "how many more" answer is measured against.
local VAULT_TOP_RUNS = 8
local MAX_PROBE = 40

local rewardCache = {}

-- The item level the vault grants for a key level.
--
-- GetRewardLevelForDifficultyLevel returns two values and only one of them is
-- reliably an item level; the other came back as 28 on a live client. Where both
-- look like item levels, the larger is the vault and the smaller is the
-- end-of-run drop: on a +9 the pair was 318 against a dungeon capping at 311.
-- The vault is what this column is about, so the larger is the one to take.
function Data.VaultRewardLevel(keyLevel)
  keyLevel = tonumber(keyLevel)
  if not keyLevel or keyLevel < 1 then return nil end
  local hit = rewardCache[keyLevel]
  if hit ~= nil then return hit or nil end
  if not (C_MythicPlus and C_MythicPlus.GetRewardLevelForDifficultyLevel) then
    return nil
  end

  local ok, a, b = pcall(C_MythicPlus.GetRewardLevelForDifficultyLevel, keyLevel)
  if not ok then return nil end
  a, b = tonumber(a), tonumber(b)
  if a and a < 100 then a = nil end
  if b and b < 100 then b = nil end

  local level
  if a and b then level = math.max(a, b) else level = a or b end
  rewardCache[keyLevel] = level or false
  return level
end

-- The highest key level that still improves the vault, and what it grants.
--
-- Probed rather than written down. A hardcoded +10 is right until the season
-- turns over, which is precisely the moment it becomes wrong and nobody is
-- watching for it.
local capLevel, capItemLevel, capProbed

function Data.VaultCapLevel()
  if capProbed then return capLevel, capItemLevel end
  capProbed = true

  local bestLevel, bestItem
  for level = 2, MAX_PROBE do
    local item = Data.VaultRewardLevel(level)
    if item and (not bestItem or item > bestItem) then
      bestLevel, bestItem = level, item
    end
  end
  capLevel, capItemLevel = bestLevel, bestItem
  return capLevel, capItemLevel
end

function Data.ForgetVaultCache()
  rewardCache = {}
  capLevel, capItemLevel, capProbed = nil, nil, nil
end

-- How many further runs at this level or above are needed before all eight of
-- the top runs sit at or above it.
local function runsNeededFor(levels, level)
  local have = 0
  for _, l in ipairs(levels or {}) do
    if l >= level then have = have + 1 end
  end
  return math.max(0, VAULT_TOP_RUNS - have), have
end

-- Everything the vault tooltip needs, as data. No side effects, no drawing.
--
-- Built from two fields only: each slot's level, and the run list. The per-slot
-- progress counter is deliberately not used. It does not behave like a run
-- count -- across the live roster one character reads 4, 4 and 15 runs on its
-- three slots at the same instant, and another reads ten runs against a
-- threshold of eight while awarding nothing -- and a number nobody can explain
-- has no business being the basis of an answer.
function Data.VaultPlan(c)
  local v = c and c.vault
  if not v or not v.capturedAt then return nil end
  if NS.Store.IsStale(v.capturedAt) then return nil end

  local slots = {}
  for i = 1, #v do
    if type(v[i]) == "table" then
      local s = v[i]
      local level = s.level or 0
      slots[#slots + 1] = {
        threshold = s.threshold or 0,
        level = level,
        -- A slot with no level attached is one you have not earned. This field
        -- agrees with itself across every character stored; the counter does not.
        unlocked = level > 0,
        itemLevel = level > 0 and Data.VaultRewardLevel(level) or nil,
      }
    end
  end
  table.sort(slots, function(a, b) return a.threshold < b.threshold end)

  local plan = { slots = slots }

  local runs = c.weeklyRuns
  local fresh = (runs and runs.levels and not NS.Store.IsStale(runs.capturedAt))
    and true or false
  plan.haveRuns = fresh
  if fresh then plan.runsThisWeek = #runs.levels end

  -- The ceiling, and what stands between you and having every slot pay it.
  --
  -- Eight runs at or above a level puts all three thresholds at or above it,
  -- whatever the per-slot rule turns out to be. That makes this the one figure
  -- here that does not depend on knowing Blizzard's exact arithmetic.
  local cap, capItem = Data.VaultCapLevel()
  if cap and capItem then
    plan.cap = { level = cap, itemLevel = capItem }
    if fresh then plan.cap.runsNeeded = runsNeededFor(runs.levels, cap) end
    plan.maxed = true
    for _, slot in ipairs(slots) do
      if not slot.itemLevel or slot.itemLevel < capItem then plan.maxed = false end
    end
  end

  return plan
end

function Data.CaptureCurrencies(c, now)
  local Cur = NS.Currencies
  if not Cur then return end

  -- Anything still unresolved kicks off a one-time id probe; re-capture when it
  -- lands so the columns fill in without a /reload.
  Cur.EnsureResolved(function()
    local key = playerKey()
    pcall(Data.CaptureCurrencies, NS.Store.GetOrCreateChar(key), GetServerTime())
    refreshUI()
  end)

  -- Warband balances are asynchronous: ask here so the answer is already cached
  -- by the time a currency cell is hovered -- and apply whatever answer is
  -- already in hand, so the other rows follow a transfer made from this one.
  Cur.RequestAccountData()
  pcall(Data.MergeWarbandBalances, now)

  for _, col in ipairs(Cur.COLUMNS) do
    -- A currency if the game lists it as one, else (where the def names a bag
    -- item) a reagent. Once we've seen the item we remember its id, so a later
    -- count of 0 reads as 0 rather than reverting to unknown.
    local snap = Cur.Snapshot(Cur.Resolve(col.key), now)
    if not snap then
      local cached = c[col.id]
      local knownID = (NS.ITEM and NS.ITEM[col.key]) or (cached and cached.itemID)
      snap = Cur.ItemSnapshot(col.key, now, knownID)
    end
    c[col.id] = snap or c[col.id]
  end

  -- Currencies with no column of their own: the Spark column's season line is
  -- read off the dust, which has to be captured for it to be there on an alt.
  for _, e in ipairs(Cur.COMPANIONS) do
    c[e.id] = Cur.Snapshot(Cur.Resolve(e.key), now) or c[e.id]
  end

  -- Every crest tier this season, for the Crest column's tooltip. c.crest keeps
  -- the headline tier in its own shape, which is what the cell renders.
  local crests = Cur.CrestSnapshots(now)
  if #crests > 0 then
    c.crests = crests
    local head = Cur.HeadlineCrest(crests)
    c.crest = {
      id = head.id, name = head.name, count = head.have,
      collected = head.collected, cap = head.cap, useEarnedCap = head.useEarnedCap,
      weekly = head.weekly, weeklyCap = head.weeklyCap,
      capturedAt = now,
    }
  end
end

-- Obtained-item tracker. Seeds from currently equipped gear + bags, and grows
-- via loot events (below). Persisted per character in the account-wide DB so the
-- Loot tab can hide what you've already looted. Updated on capture/logout/reload.
function Data.CaptureObtained(c)
  c.obtained = c.obtained or {}
  for slot = 1, 19 do
    local id = GetInventoryItemID and GetInventoryItemID("player", slot)
    if id then c.obtained[id] = true end
  end
  if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID then
    for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
      local n = C_Container.GetContainerNumSlots(bag) or 0
      for s = 1, n do
        local id = C_Container.GetContainerItemID(bag, s)
        if id then c.obtained[id] = true end
      end
    end
  end
end

-- Map a dungeon name (from a Voidcache) to its challengeMapID.
local function mapIDForDungeonName(name)
  if not name then return end
  local target = name:lower()
  for _, id in ipairs(NS.Store.SeasonMaps()) do
    local n = NS.Dungeons.NameFor(id)
    if n and n:lower() == target then return id end
  end
end

-- Auto-detect the game's real bonus-roll pools: scan bags for "Voidcache" items
-- and read each one's remaining contents. Cached per character so the Loot tab
-- can show the exact remaining list without any manual steps.
function Data.CaptureVoidcaches(c)
  if not (C_Container and C_Container.GetContainerNumSlots
          and NS.Loot and NS.Loot.ReadBagVoidcache) then return end
  local byMap, found = {}, 0
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local link = C_Container.GetContainerItemLink(bag, slot)
      if link and link:lower():find("voidcache", 1, true) then
        local dungeonName, items = NS.Loot.ReadBagVoidcache(bag, slot)
        local mapID = mapIDForDungeonName(dungeonName)
        if mapID and items and #items > 0 then
          byMap[mapID] = items
          found = found + 1
        end
      end
    end
  end
  if found > 0 then
    c.voidcache = c.voidcache or {}
    for mapID, items in pairs(byMap) do c.voidcache[mapID] = items end
    c.voidcacheAt = GetServerTime()
    NS.Debug("captured %d voidcaches from bags", found)
  end
end

-- The season id drives the window title. Cached in the DB so the title still
-- reads correctly on a character where the API hasn't answered yet.
function Data.CaptureSeason()
  if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
    NS.Store.SetSeasonID(C_MythicPlus.GetCurrentSeason())
  end
end

function Data.CaptureAffixes()
  if not (C_MythicPlus and C_MythicPlus.GetCurrentAffixes) then return end
  local affixes = C_MythicPlus.GetCurrentAffixes()
  if type(affixes) ~= "table" then return end
  local ids = {}
  for _, a in ipairs(affixes) do ids[#ids + 1] = a.id end
  NS.Store.SetAffixes(ids)
end

--------------------------------------------------------------------------------
-- Orchestration + combat gating
--------------------------------------------------------------------------------
local pending = false

-- A full sweep is not cheap: eight GetSeasonBestForMap calls, thirteen currency
-- columns, the vault, the run history, the voidcaches and a bag scan. Once at
-- login that is nothing. Once after every pull it is a hitch you can feel, and
-- that is what was happening -- looting during combat sets `pending`, and
-- leaving combat spends it, so a key with thirty pulls paid for thirty sweeps.
--
-- Nothing it reads changes fast enough to be worth that. Fifteen seconds is far
-- below the rate any of it moves, and the moments that genuinely matter say so
-- by name and skip the throttle.
local MIN_CAPTURE_GAP = 15
local lastCaptureAt = 0

-- Named in rather than out. An allow-list would have quietly swallowed
-- enter-world-2 -- the six-second retry that exists because the API is not ready
-- at two -- and a capture that silently does not happen is worse than one that
-- happens too often. Only the repeating one is held back; anything added later
-- runs until somebody decides otherwise.
local THROTTLED = { ["post-combat"] = true }

function Data.CaptureAll(reason)
  if InCombatLockdown() then
    pending = true
    return
  end

  local now = GetTime and GetTime() or 0
  if THROTTLED[reason or ""] and (now - lastCaptureAt) < MIN_CAPTURE_GAP then
    NS.Debug("CaptureAll(%s) skipped -- %.0fs since the last one",
      tostring(reason), now - lastCaptureAt)
    return
  end
  lastCaptureAt = now
  local key, name, realm = playerKey()
  local c = NS.Store.GetOrCreateChar(key)
  c.name, c.realm = name, realm
  local now = GetServerTime()
  local ok, err = pcall(function()
    Data.CaptureIdentity(c)
    Data.CaptureScore(c, now)
    Data.CaptureBest(c, now)
    Data.CaptureKeystone(c, now)
    Data.CaptureVault(c, now)
    Data.CaptureWeeklyRuns(c, now)
    Data.CaptureCurrencies(c, now)
    Data.CaptureObtained(c)
    Data.CaptureVoidcaches(c)
    Data.CaptureSeason()
    Data.CaptureAffixes()
  end)
  c.updatedAt = now
  c.updatedBy = "ingame"
  NS.Debug("CaptureAll(%s) key=%s ok=%s%s", tostring(reason), key, tostring(ok),
    ok and "" or (" err=" .. tostring(err)))
  refreshUI()
end

--------------------------------------------------------------------------------
-- Event wiring
--------------------------------------------------------------------------------
-- Keystone accessors return nil in the first seconds after login. Retry the
-- keystone-only capture until it reads authoritatively so this character's key
-- always lands in the account-wide cache for other characters to see.
NS.On("PLAYER_ENTERING_WORLD", function()
  local key, name, realm = playerKey()
  local tries = 0
  local function tryKey()
    tries = tries + 1
    local c = NS.Store.GetOrCreateChar(key)
    c.name, c.realm = name, realm
    local ok, authoritative = pcall(Data.CaptureKeystone, c, GetServerTime())
    refreshUI()
    if not (ok and authoritative) and tries < 6 then
      NS.After(2, tryKey)   -- keep retrying through the post-login data race
    end
  end
  NS.After(2, tryKey)
end)

NS.On("CHALLENGE_MODE_MAPS_UPDATE", function()
  if InCombatLockdown() then pending = true; return end
  local key = playerKey()
  local c = NS.Store.GetOrCreateChar(key)
  pcall(Data.CaptureBest, c, GetServerTime())
  refreshUI()
end)

NS.On("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", function()
  pcall(Data.CaptureAffixes)
  refreshUI()
end)

NS.On("CHALLENGE_MODE_COMPLETED", function()
  Data.CaptureAll("mplus-complete")
end)

local lastBag = 0
NS.On("BAG_UPDATE_DELAYED", function()
  local t = GetTime()
  if t - lastBag < 1 then return end      -- throttle to 1/sec
  lastBag = t
  if InCombatLockdown() then pending = true; return end
  local key = playerKey()
  local c = NS.Store.GetOrCreateChar(key)
  pcall(Data.CaptureKeystone, c, GetServerTime())
  pcall(Data.CaptureVoidcaches, c)
  -- Voidlight Marl may be a bag reagent, which CURRENCY_DISPLAY_UPDATE never fires for.
  pcall(Data.CaptureCurrencies, c, GetServerTime())
  refreshUI()
end)

NS.On("WEEKLY_REWARDS_UPDATE", function()
  if InCombatLockdown() then pending = true; return end
  local key = playerKey()
  local c = NS.Store.GetOrCreateChar(key)
  pcall(Data.CaptureVault, c, GetServerTime())
  refreshUI()
end)

local lastCurrency = 0
NS.On("CURRENCY_DISPLAY_UPDATE", function()
  local t = GetTime()
  if t - lastCurrency < 1 then return end   -- throttle
  lastCurrency = t
  local key = playerKey()
  local c = NS.Store.GetOrCreateChar(key)
  pcall(Data.CaptureCurrencies, c, GetServerTime())
  refreshUI()
end)

--------------------------------------------------------------------------------
-- Other characters' balances, from the warband-transfer data
--
-- A cell is a snapshot taken while logged in on that character, so moving coins
-- between two characters updates one row and leaves the other wrong until it is
-- next played. The transfer UI's data knows every account character's balance
-- for a transferable currency; writing it into the rows KeyGrid already has
-- keeps them honest without a login. Rows are never created from it: a name and
-- a number is not a character.
--------------------------------------------------------------------------------

-- The store key for the API's "Name-Realm", spelled the way playerKey spells it.
local function storeKeyFromFull(full)
  local name, realm = full:match("^([^%-]+)%-(.+)$")
  if not name then return nil end
  return name .. "-" .. realm:gsub("%s+", "")
end

-- Without a realm, a name matches only when exactly one row carries it.
local function rowByBareName(chars, name)
  local found
  for key, c in pairs(chars) do
    if c.name == name or key:match("^(.-)%-") == name then
      if found then return nil end
      found = c
    end
  end
  return found
end

function Data.MergeWarbandBalances(now)
  local Cur = NS.Currencies
  if not Cur then return end
  local chars = NS.Store.DB().chars or {}
  local me = playerKey()
  local changed = false
  for _, col in ipairs(Cur.COLUMNS) do
    local id = Cur.Resolve(col.key)
    -- nil when the client has no API, has not answered yet, or the currency is
    -- not transferable -- in every case there is nothing to say.
    local list = id and Cur.AccountBalances(id)
    if list then
      -- The list names only characters holding some. Every other known row
      -- has none -- which is exactly the row that goes stale after a transfer
      -- out, so the absence is the more important half of the answer.
      local listed = {}
      for _, e in ipairs(list) do
        local key = e.full and storeKeyFromFull(e.full)
        local c = key and chars[key] or (not key and rowByBareName(chars, e.name)) or nil
        if c then listed[c] = e.quantity end
      end
      for key, c in pairs(chars) do
        if key ~= me then
          local qty = listed[c] or 0
          local rec = c[col.id]
          if not rec then
            rec = { id = id, name = col.label, have = 0, source = "currency",
                    transferable = true }
            c[col.id] = rec
          end
          if rec.have ~= qty then
            -- Only what is on hand: a transfer is not a spend, and everything
            -- else in the record is still what that character last reported.
            rec.have = qty
            changed = true
          end
          rec.warbandAt = now
        end
      end
    end
  end
  return changed
end

-- Warband currency data landing. The event name is client-dependent, and NS.On
-- quietly swallows one this client doesn't know.
NS.On("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", function()
  if NS.Currencies then NS.Currencies.AccountDataReceived() end
  pcall(Data.MergeWarbandBalances, GetServerTime())
  refreshUI()
end)

-- Grow the obtained set as loot is received (boss loot + bonus rolls fire
-- ENCOUNTER_LOOT_RECEIVED; personal pickups fire CHAT_MSG_LOOT).
local function recordObtained(itemID)
  itemID = tonumber(itemID)
  if not itemID then return end
  local key = playerKey()
  local c = NS.Store.GetOrCreateChar(key)
  c.obtained = c.obtained or {}
  if not c.obtained[itemID] then
    c.obtained[itemID] = true
    refreshUI()
  end
end

NS.On("ENCOUNTER_LOOT_RECEIVED", function(_, _, itemID, _, _, playerName)
  local me = UnitName("player")
  if playerName and me and playerName ~= me and not playerName:find(me, 1, true) then return end
  recordObtained(itemID)
end)

NS.On("CHAT_MSG_LOOT", function(_, text)
  if not text or not text:find("You receive", 1, true) then return end
  local id = text:match("Hitem:(%d+):")
  if id then recordObtained(id) end
end)

NS.On("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
  if unit and unit ~= "player" then return end
  local key = playerKey()
  local c = NS.Store.GetOrCreateChar(key)
  pcall(Data.CaptureIdentity, c)
  if NS.Loot and NS.Loot.ClearCache then NS.Loot.ClearCache() end
  refreshUI()
end)

NS.On("PLAYER_REGEN_ENABLED", function()
  if not pending then return end
  pending = false
  -- Two seconds after the fight rather than the instant it ends. Combat leaving
  -- is already a busy frame -- auras falling off, nameplates going, other addons
  -- doing their own tidying -- and this has no reason to be in it.
  C_Timer.After(2, function()
    if not InCombatLockdown() then Data.CaptureAll("post-combat") end
  end)
end)

NS.On("PLAYER_LOGOUT", function()
  -- Final flush. SavedVariables is written on logout; capture once more if safe.
  if not InCombatLockdown() then
    pcall(Data.CaptureAll, "logout")
  end
end)
