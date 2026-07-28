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

function Data.CaptureScore(c, now)
  if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
    local score = C_ChallengeMode.GetOverallDungeonScore()
    -- Ignore a 0 (not-ready / mid-logout) so it can't overwrite a cached score.
    if score and score > 0 then NS.Store.MergeScore(c, score, now, "ingame") end
  end
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

-- Prefer the higher key level; on equal level prefer the timed record.
function Data.PickBestRun(intime, overtime)
  local a = normRun(intime, true)
  local b = normRun(overtime, false)
  if a and b then
    if (a.level or 0) >= (b.level or 0) then return a else return b end
  end
  return a or b
end

function Data.CaptureBest(c, now)
  if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return end
  local maps = C_ChallengeMode.GetMapTable()
  if type(maps) ~= "table" or #maps == 0 then return end
  NS.Store.SetSeasonMaps(maps)
  for _, mapID in ipairs(maps) do
    if C_MythicPlus and C_MythicPlus.GetSeasonBestForMap then
      local intime, overtime = C_MythicPlus.GetSeasonBestForMap(mapID)
      local best = Data.PickBestRun(intime, overtime)
      if best and best.level then
        NS.Store.MergeBest(c, mapID, best, "ingame")
      end
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

-- Gearing currencies: Void Cores, Field Accolades, Voidlight Marl, Mythic crest.
-- Each is collected/on-hand/spent/season-cap. In-game only, cached per character
-- in the account-wide DB (like keystones), so alts keep showing their last count.
-- A currency that can't be resolved leaves the cached snapshot untouched rather
-- than blanking it — the same early-login race guard the keystone capture uses.
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

  c.cores     = Cur.Snapshot(Cur.Resolve("VOIDCORES"), now) or c.cores
  c.accolades = Cur.Snapshot(Cur.Resolve("ACCOLADES"), now) or c.accolades

  -- Voidlight Marl: a currency if the game lists it as one, else a bag reagent.
  -- Once we've seen the item we remember its id, so a later count of 0 reads as 0.
  local marl = Cur.Snapshot(Cur.Resolve("MARL"), now)
  if not marl then
    local knownID = (NS.ITEM and NS.ITEM.MARL) or (c.marl and c.marl.itemID)
    marl = Cur.ItemSnapshot("MARL", now, knownID)
  end
  c.marl = marl or c.marl

  -- Mythic crest count (for the M+ Grid Crest column). Kept in its own shape for
  -- back-compat with the existing crest cell/tooltip.
  local crest = Cur.Snapshot(Cur.ResolveMythicCrest and Cur.ResolveMythicCrest(), now)
  if crest then
    c.crest = {
      id = crest.id, name = crest.name, count = crest.have,
      weekly = crest.weekly, weeklyCap = crest.weeklyCap,
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

function Data.CaptureAll(reason)
  if InCombatLockdown() then
    pending = true
    return
  end
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
    Data.CaptureCurrencies(c, now)
    Data.CaptureObtained(c)
    Data.CaptureVoidcaches(c)
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
  if pending then
    pending = false
    Data.CaptureAll("post-combat")
  end
end)

NS.On("PLAYER_LOGOUT", function()
  -- Final flush. SavedVariables is written on logout; capture once more if safe.
  if not InCombatLockdown() then
    pcall(Data.CaptureAll, "logout")
  end
end)
