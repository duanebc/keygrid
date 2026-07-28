-- KeyGrid/LootData.lua
-- Enumerate a dungeon's loot from the Encounter Journal, filtered to the class's
-- armor type + spec, with collected (transmog) appearances optionally hidden.
-- No "remaining pool" API exists (see plan); "not looted" is approximated by
-- "appearance not collected" (account-wide).

local ADDON, NS = ...
local L = {}
NS.Loot = L

-- Optional hardcode filled from /kg lootdump: [challengeMapID] = journalInstanceID
NS.LOOT_INSTANCE = {}

local resolvedInstance = {}  -- mapID -> journalInstanceID or false (session cache)
local lootCache = {}         -- "mapID:specID" -> { {itemID,name,slot}, ... }

-- WoW classID -> the armor subclass it wears (Enum.ItemArmorSubclass: 1=Cloth
-- 2=Leather 3=Mail 4=Plate).
local CLASS_ARMOR = {
  [1] = 4, [2] = 4, [3] = 3, [4] = 2, [5] = 1, [6] = 4, [7] = 3,
  [8] = 1, [9] = 1, [10] = 2, [11] = 2, [12] = 2, [13] = 3,
}

local function itemInstant(itemID)
  if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(itemID) end
  if GetItemInfoInstant then return GetItemInfoInstant(itemID) end
end

-- True if this class can wear the item (armor-type gate; non-armor always ok).
local function classCanUseArmor(itemID, classID)
  local _, _, _, equipLoc, _, itemClassID, itemSubClassID = itemInstant(itemID)
  if itemClassID == nil then return true end
  if itemClassID ~= 4 then return true end                 -- weapons/misc: allow
  if equipLoc == "INVTYPE_CLOAK" then return true end       -- cloaks: everyone
  if itemSubClassID == nil or itemSubClassID == 0 or itemSubClassID > 4 then
    return true                                             -- jewelry/shields/relics
  end
  local want = CLASS_ARMOR[classID]
  if not want then return true end
  return itemSubClassID == want
end

function L.IsCollected(itemID)
  if C_TransmogCollection and C_TransmogCollection.PlayerHasTransmogByItemInfo then
    local ok, has = pcall(C_TransmogCollection.PlayerHasTransmogByItemInfo, itemID)
    if ok and has then return true end
  end
  return false
end

local function ejLoaded()
  local loaded
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    loaded = C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
    if not loaded and C_AddOns.LoadAddOn then
      pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
      loaded = C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
    end
  elseif IsAddOnLoaded then
    loaded = IsAddOnLoaded("Blizzard_EncounterJournal")
    if not loaded and UIParentLoadAddOn then
      pcall(UIParentLoadAddOn, "Blizzard_EncounterJournal")
      loaded = IsAddOnLoaded("Blizzard_EncounterJournal")
    end
  end
  return loaded and EJ_SelectInstance ~= nil
end
L.EJLoaded = ejLoaded

-- Resolve challengeMapID -> journalInstanceID: hardcode, else name-match across
-- ALL EJ tiers (season dungeons span expansions).
function L.InstanceFor(mapID)
  if NS.LOOT_INSTANCE[mapID] then return NS.LOOT_INSTANCE[mapID] end
  if resolvedInstance[mapID] ~= nil then return resolvedInstance[mapID] or nil end
  if not ejLoaded() then return nil end

  local dungeonName = NS.Dungeons.NameFor(mapID)
  if not dungeonName then resolvedInstance[mapID] = false; return nil end
  local target = dungeonName:lower()

  local found
  local numTiers = (EJ_GetNumTiers and EJ_GetNumTiers()) or 0
  for t = 1, numTiers do
    if EJ_SelectTier then pcall(EJ_SelectTier, t) end
    local i = 1
    while i <= 200 do
      local id, name = EJ_GetInstanceByIndex(i, false)  -- false = dungeons
      if not id then break end
      if name and name:lower() == target then found = id; break end
      i = i + 1
    end
    if found then break end
  end
  resolvedInstance[mapID] = found or false
  return found
end

-- Walk the instance's encounters, class-armor filtered. Returns the item list.
-- (We deliberately do NOT touch EJ difficulty — setting it globally zeroed the
--  loot query. We take whatever loot the journal exposes for the dungeon.)
local function enumerate(instID, classID, specID)
  local out, seen = {}, {}
  pcall(function()
    EJ_SelectInstance(instID)
    if EJ_SetLootFilter and classID and specID then EJ_SetLootFilter(classID, specID) end
    local e = 1
    while e <= 50 do
      local _, _, encID = EJ_GetEncounterInfoByIndex(e, instID)
      if not encID then break end
      if EJ_SelectEncounter then EJ_SelectEncounter(encID) end
      local num = (EJ_GetNumLoot and EJ_GetNumLoot()) or 0
      for l = 1, num do
        local li = C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex
          and C_EncounterJournal.GetLootInfoByIndex(l)
        if li and li.itemID and not seen[li.itemID] then
          seen[li.itemID] = true
          if (not classID) or classCanUseArmor(li.itemID, classID) then
            out[#out + 1] = { itemID = li.itemID, name = li.name, slot = li.slot }
          end
        end
      end
      e = e + 1
    end
  end)
  return out
end

-- Filter the bundled seasonal lootTable to (classID, specID) using the item
-- eligibility map. Mirrors KeystoneLoot's behaviour → the curated ~8-per-spec set.
local function fromSeasonData(mapID, classID, specID)
  local season = NS.SEASONLOOT
  if not (season and season.dungeons and season.dungeons[mapID]) then return nil end
  local out = {}
  for _, itemID in ipairs(season.dungeons[mapID]) do
    local elig = season.items and season.items[itemID]
    local show = false
    if not classID then
      show = true
    elseif elig and elig[classID] then
      if not specID then
        show = true
      else
        for _, s in ipairs(elig[classID]) do
          if s == specID then show = true; break end
        end
      end
    end
    if show then out[#out + 1] = { itemID = itemID } end
  end
  return out
end

-- Loot for (mapID, classID, specID). Prefers the curated seasonal data; falls
-- back to the Encounter Journal (full historical table) if it's absent.
function L.ItemsFor(mapID, classID, specID)
  local key = mapID .. ":" .. tostring(specID or 0)
  if lootCache[key] then return lootCache[key] end

  local seasonal = fromSeasonData(mapID, classID, specID)
  if seasonal then
    lootCache[key] = seasonal
    return seasonal
  end

  if not ejLoaded() then return nil end
  local instID = L.InstanceFor(mapID)
  if not instID then return nil end
  lootCache[key] = enumerate(instID, classID, specID)
  return lootCache[key]
end

function L.ClearCache()
  if wipe then wipe(lootCache); wipe(resolvedInstance) end
end

-- Names arrive async; when item data loads, refresh the loot tab (debounced).
local refreshQueued = false
NS.On("ITEM_DATA_LOAD_RESULT", function()
  if refreshQueued then return end
  refreshQueued = true
  NS.After(0.5, function()
    refreshQueued = false
    local UI = NS.UI
    if UI and UI.frame and UI.frame:IsShown()
       and (NS.Store.DB().ui.tab == 3) and UI.RefreshLoot then
      UI.RefreshLoot()
    end
  end)
end)

--------------------------------------------------------------------------------
-- Voidcache = the game's REAL bonus-roll pool per dungeon (per-character, shrinks
-- as items are transmuted). The "Contains one of…" list only exists on the LIVE
-- tooltip, not via GetItemByID — so we parse it at hover time (and from bag
-- items) and store it per character for the Loot tab to show exactly.
--------------------------------------------------------------------------------
NS.voidcaches = NS.voidcaches or {}   -- itemID -> name (diagnostic)

local function mapIDForName(name)
  if not name then return end
  local target = name:lower()
  for _, id in ipairs(NS.Store.SeasonMaps()) do
    local n = NS.Dungeons.NameFor(id)
    if n and n:lower() == target then return id end
  end
end

-- Parse live Voidcache tooltip lines: returns dungeonName, {itemNames}.
local function parseVoidcacheLines(lines)
  local dungeonName, items, listing = nil, {}, false
  for _, line in ipairs(lines) do
    local t = line.leftText or ""
    if not dungeonName then
      local dn = t:match("[Vv]oidcache:%s*(.+)$")
      if dn then dungeonName = (dn:gsub("%s+$", "")) end
    end
    if t:lower():find("contains one of", 1, true) then
      listing = true
    elseif listing then
      local name = (t:gsub("^%s*[%-•]?%s*", "")):gsub("%s+$", "")
      if name ~= "" then items[#items + 1] = name end
    end
  end
  return dungeonName, items
end

-- Store a captured pool into the current character (persisted, per dungeon).
function L.StoreVoidcache(dungeonName, items)
  local mapID = mapIDForName(dungeonName)
  if not (mapID and items and #items > 0) then return false end
  local key = NS.PlayerKey and NS.PlayerKey()
  if not key then return false end
  local c = NS.Store.GetOrCreateChar(key)
  c.voidcache = c.voidcache or {}
  c.voidcache[mapID] = items
  c.voidcacheAt = GetServerTime()
  local UI = NS.UI
  if UI and UI.frame and UI.frame:IsShown()
     and NS.Store.DB().ui.tab == 3 and UI.RefreshLoot then
    UI.RefreshLoot()
  end
  return true
end

-- Read a Voidcache in a bag slot (the live instance carries the dynamic list).
function L.ReadBagVoidcache(bag, slot)
  if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return end
  local data = C_TooltipInfo.GetBagItem(bag, slot)
  if not (data and data.lines) then return end
  return parseVoidcacheLines(data.lines)
end

-- Live tooltip hook: capture the pool the moment a Voidcache is shown (hover).
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
   and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
    if tt ~= GameTooltip or not data or not data.lines then return end
    local name = data.lines[1] and data.lines[1].leftText
    if not (name and name:lower():find("voidcache", 1, true)) then return end
    if data.id then NS.voidcaches[data.id] = name end
    local dungeonName, items = parseVoidcacheLines(data.lines)
    if dungeonName and #items > 0 then L.StoreVoidcache(dungeonName, items) end
  end)
end

-- /kg voidcache : report the pools captured for the current character.
function L.VoidcacheDump()
  local key = NS.PlayerKey and NS.PlayerKey()
  local c = key and NS.Store.DB().chars[key]
  if c and c.voidcache and next(c.voidcache) then
    NS.Print("Voidcache pools captured for this character:")
    for _, id in ipairs(NS.Store.SeasonMaps()) do
      local items = c.voidcache[id]
      if items then
        print(("  %s (%d): %s"):format(NS.Dungeons.NameFor(id) or "?", #items, table.concat(items, ", ")))
      end
    end
  else
    NS.Print("No pools captured yet. Open the Bonus Loot frame and hover each dungeon's Voidcache (its tooltip must show 'Contains one of the following items').")
  end
end

-- /kg lootdump : verify EJ resolution + loot counts for the current char's spec.
function L.Dump()
  if not ejLoaded() then
    NS.Print("Encounter Journal not available yet — open it once, then retry.")
    return
  end
  local classID = select(3, UnitClass("player"))
  local specID
  if GetSpecialization and GetSpecializationInfo then
    local idx = GetSpecialization()
    if idx then specID = GetSpecializationInfo(idx) end
  end
  NS.Print(("Loot resolve (classID %s, specID %s):"):format(tostring(classID), tostring(specID)))
  for _, id in ipairs(NS.Store.SeasonMaps()) do
    local name = NS.Dungeons.NameFor(id) or "?"
    local instID = L.InstanceFor(id)
    local items = instID and L.ItemsFor(id, classID, specID)
    print(("  map %d %-22s -> EJ %s, %d items"):format(
      id, name, tostring(instID), items and #items or 0))
  end
  NS.Print("If any EJ is nil, paste [mapID]=instanceID into LootData.lua NS.LOOT_INSTANCE.")
end
