-- KeyGrid/Currencies.lua
-- Resolve, snapshot + dump the gearing currencies (Corrosive Coins, Voidlight
-- Marl, Venomblight Manaflux, Tidal Spark Dust, Void Cores, and the crest set).
--
-- Resolution is the hard part. The in-game currency list (GetCurrencyListInfo)
-- only contains currencies THIS character has earned, and the Currency tab's
-- "<Name> Only" filter can hide more — so a currency you have none of cannot be
-- found by walking the list at all. Three layers, in order:
--   1. NS.CURRENCY.<KEY>            -- hardcoded override, always wins
--   2. KeyGridDB.currencyIDs.<KEY>  -- account-wide cache: once ANY character
--                                      resolved it, every character can read it
--   3. list walk, then a direct id probe (C.ScanIDs) that finds a currency by
--      name even at quantity 0
-- With an id in hand, GetCurrencyInfo(id) works on every character and returns
-- quantity 0 for one that has none — which is what makes the column honest
-- ("0" rather than "--" = unknown).

local ADDON, NS = ...
local C = {}
NS.Currencies = C

-- Fill from /kg curdump to pin an id permanently. Left nil = resolve at runtime.
NS.CURRENCY = {
  VOIDCORES = nil, COINS = nil, MARL = nil, MANAFLUX = nil, SPARKDUST = nil,
}

-- Fill if one of these turns out to be a bag item rather than a currency
-- (see C.ItemSnapshot). Left nil = discover it by name from bags.
NS.ITEM = { MARL = nil, MANAFLUX = nil, SPARKDUST = nil }

-- Name matchers, deliberately loose so a rename/plural/spacing change still hits.
-- key -> {
--   label     display name
--   match     (lowercased currency name) -> truthy
--   scan      false = never id-probe this key (too many historical matches)
--   item      bag-item name fragment, if it might not be a currency at all
-- }
-- Crests are the one thing that can't be matched this way -- see C.CrestIDs.
local DEFS = {
  VOIDCORES = {
    label = "Void Cores",
    match = function(n) return n:find("void", 1, true) and n:find("core", 1, true) end,
  },
  COINS = {
    label = "Corrosive Coin",   -- singular in-game (id 3448)
    match = function(n) return n:find("corrosive", 1, true) end,
  },
  MARL = {
    label = "Voidlight Marl",
    match = function(n) return n:find("marl", 1, true) end,
    item  = "marl",
  },
  MANAFLUX = {
    label = "Venomblight Manaflux",
    match = function(n) return n:find("manaflux", 1, true) or n:find("venomblight", 1, true) end,
    item  = "manaflux",
  },
  SPARKDUST = {
    label = "Tidal Spark Dust",
    match = function(n) return n:find("spark", 1, true) and n:find("dust", 1, true) end,
    item  = "spark dust",
  },
}
C.DEFS = DEFS

-- Grid columns for the per-character currencies, in display order. `id` is both
-- the column id and the field name on the character record; `key` indexes DEFS.
-- style = "capped" shows on-hand / season cap ("3/4") instead of a bare count.
-- Every warband-transferable currency lists all characters' balances and the
-- total on hover; that's driven by the game's own isAccountTransferable flag, so
-- roster = true is only needed to force the block on before a character has been
-- captured (or if the client stops setting the flag).
C.COLUMNS = {
  { key = "COINS",     id = "coins",     label = "Coins", w = 56, color = { 0.86, 0.76, 0.46 },
    roster = true },
  { key = "MARL",      id = "marl",      label = "Marl",  w = 52, color = { 0.72, 0.58, 0.95 },
    roster = true },
  { key = "MANAFLUX",  id = "manaflux",  label = "Flux",  w = 52, color = { 0.45, 0.95, 0.65 } },
  { key = "SPARKDUST", id = "sparkdust", label = "Dust",  w = 56, color = { 0.45, 0.85, 1.00 },
    style = "capped" },
}

function C.ColumnByID(id)
  for _, col in ipairs(C.COLUMNS) do
    if col.id == id then return col end
  end
end

function C.Label(key) return (DEFS[key] and DEFS[key].label) or key end

local function currencyInfo(id)
  if not (id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return end
  local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
  return ok and info or nil
end

--------------------------------------------------------------------------------
-- Account-wide id cache
--------------------------------------------------------------------------------
local function dbIDs()
  if type(KeyGridDB) ~= "table" then return nil end   -- pre-ADDON_LOADED
  KeyGridDB.currencyIDs = KeyGridDB.currencyIDs or {}
  return KeyGridDB.currencyIDs
end

-- Guard against a cached id that no longer names what we cached it for (a wrong
-- paste, or a season swap). Unknown/not-yet-loaded names are treated as "keep".
local function stillMatches(key, id)
  local def = DEFS[key]
  if not (def and id) then return false end
  local info = currencyInfo(id)
  local name = info and info.name
  if not name or name == "" then return true end
  return def.match(name:lower()) and true or false
end

function C.CachedID(key)
  if NS.CURRENCY[key] then return NS.CURRENCY[key] end
  local ids = dbIDs()
  local id = ids and ids[key]
  if not id then return nil end
  if stillMatches(key, id) then return id end
  ids[key] = nil
  NS.Debug("dropped stale %s currencyID %s", C.Label(key), tostring(id))
  return nil
end

local function remember(key, id)
  local ids = dbIDs()
  if ids then ids[key] = id end
  NS.Debug("resolved %s currencyID = %s", C.Label(key), tostring(id))
end

--------------------------------------------------------------------------------
-- Layer 3a: the character's own currency list
--------------------------------------------------------------------------------
-- A reliable currencyID for a list row: prefer the field, fall back to the link
-- (older clients omit .currencyID from GetCurrencyListInfo).
local function currencyIDForIndex(info, index)
  if info and info.currencyID then return info.currencyID end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListLink and C_CurrencyInfo.GetCurrencyIDFromLink then
    local link = C_CurrencyInfo.GetCurrencyListLink(index)
    if link then return C_CurrencyInfo.GetCurrencyIDFromLink(link) end
  end
end

-- Iterate the currency list, expanding collapsed headers so nothing is hidden.
-- fn(info, index, currencyID) is called per non-header row; return true to stop.
local function forEachCurrency(fn)
  if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize) then return end
  local i = 1
  local guard = 0
  while i <= (C_CurrencyInfo.GetCurrencyListSize() or 0) and guard < 1000 do
    guard = guard + 1
    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
    if info then
      if info.isHeader then
        if not info.isHeaderExpanded and C_CurrencyInfo.ExpandCurrencyList then
          C_CurrencyInfo.ExpandCurrencyList(i, true)   -- reveals children after i
        end
      else
        if fn(info, i, currencyIDForIndex(info, i)) then return end
      end
    end
    i = i + 1
  end
end
C.ForEach = forEachCurrency

local function scanList(key)
  local def = DEFS[key]
  if not def then return end
  local found
  forEachCurrency(function(info, _, cid)
    if not cid then return end
    local name = info.name and info.name:lower() or ""
    if def.match(name) then
      found = cid
      return true                          -- first match wins
    end
  end)
  return found
end

-- Resolve one registry key to a currencyID. Cheap and safe to call every capture.
function C.Resolve(key)
  local id = C.CachedID(key)
  if id then return id end
  if not DEFS[key] then return end
  id = scanList(key)
  if id then remember(key, id) end
  return id
end

function C.ResolveVoidCores() return C.Resolve("VOIDCORES") end

--------------------------------------------------------------------------------
-- Layer 3b: direct id probe
-- GetCurrencyInfo(id) returns a currency's name whether or not this character has
-- ever earned it, so probing ids finds what the filtered list cannot. Chunked
-- across frames so there's no hitch, run at most once per session, and every hit
-- is persisted — so this normally happens exactly once per account.
--------------------------------------------------------------------------------
local MAX_CURRENCY_ID = 5000
local CHUNK = 500
local scanning, scanned = false, false

local function unresolvedKeys()
  local want = {}
  for key, def in pairs(DEFS) do
    if def.scan ~= false and not C.CachedID(key) then want[#want + 1] = key end
  end
  return want
end

function C.ScanIDs(onDone, force)
  if scanning then return end
  if scanned and not force then
    if onDone then onDone(0) end
    return
  end
  if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return end
  local want = unresolvedKeys()
  if #want == 0 then
    scanned = true
    if onDone then onDone(0) end
    return
  end

  scanning = true
  local id, found = 1, 0
  local function step()
    local stop = math.min(id + CHUNK - 1, MAX_CURRENCY_ID)
    while id <= stop do
      local info = currencyInfo(id)
      local name = info and info.name
      if name and name ~= "" then
        local lower = name:lower()
        for i = #want, 1, -1 do
          local key = want[i]
          if DEFS[key].match(lower) then
            remember(key, id)
            found = found + 1
            table.remove(want, i)
          end
        end
      end
      id = id + 1
    end
    if #want > 0 and id <= MAX_CURRENCY_ID then
      NS.After(0, step)                      -- next frame
    else
      scanning = false
      scanned = true
      NS.Debug("currency id scan done: %d found, %d still missing", found, #want)
      if onDone then onDone(found) end
    end
  end
  step()
end

-- Called from Data.CaptureCurrencies: if anything is still unresolved, kick the
-- probe off once and re-capture when it lands.
function C.EnsureResolved(onResolved)
  for key in pairs(DEFS) do C.Resolve(key) end
  if #unresolvedKeys() == 0 then return end
  C.ScanIDs(function(found)
    if found and found > 0 and onResolved then onResolved() end
  end)
end

--------------------------------------------------------------------------------
-- Snapshots (the shape Data.lua caches per character)
--------------------------------------------------------------------------------
-- One currency's full state. `spent` is derived: totalEarned - quantity.
function C.Snapshot(id, now)
  local info = currencyInfo(id)
  if not info then return end
  local collected = info.totalEarned or 0
  local have = info.quantity or 0
  return {
    id           = id,
    name         = info.name,
    collected    = collected,
    have         = have,
    -- totalEarned is not always maintained; never report a negative spend.
    spent        = math.max(0, collected - have),
    cap          = info.maxQuantity or 0,
    useEarnedCap = info.useTotalEarnedForMaxQty,
    weekly       = info.quantityEarnedThisWeek or 0,
    weeklyCap    = info.maxWeeklyQuantity or 0,
    -- Two distinct things: isAccountWide = one shared pool for the whole warband.
    -- isAccountTransferable = still a per-character balance, but it can be sent to
    -- another character (transferPercentage is what survives the transfer).
    accountWide  = info.isAccountWide or nil,
    transferable = info.isAccountTransferable or nil,
    transferPct  = info.transferPercentage,
    source       = "currency",
    capturedAt   = now,
  }
end

local function itemCount(itemID)
  local fn = (C_Item and C_Item.GetItemCount) or _G.GetItemCount
  if not fn then return end
  -- includeBank + includeReagentBank + includeAccountBank: a reagent lives anywhere.
  local ok, n = pcall(fn, itemID, true, false, true, true)
  if not ok then ok, n = pcall(fn, itemID, true) end
  return ok and (n or 0) or nil
end

-- Find an item's ID by (partial, lowercased) name across the bags. Only used the
-- first time — the id is cached on the character so a later count of 0 is still
-- reported as 0 rather than "unknown".
local function findItemIDByName(target)
  if not (C_Container and C_Container.GetContainerNumSlots) then return end
  for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
    local n = C_Container.GetContainerNumSlots(bag) or 0
    for slot = 1, n do
      local link = C_Container.GetContainerItemLink(bag, slot)
      local name = link and link:match("%[(.-)%]")
      if name and name:lower():find(target, 1, true) then
        return C_Container.GetContainerItemID(bag, slot), name
      end
    end
  end
end

-- Item-backed fallback for a registry key whose def carries `item`. knownID is
-- the id cached from a previous capture (or NS.ITEM.*). Returns nil when the item
-- has never been seen, so the caller can leave the cached value alone.
function C.ItemSnapshot(key, now, knownID)
  local def = DEFS[key]
  if not (def and def.item) then return end
  local id, name = knownID, nil
  if not id then id, name = findItemIDByName(def.item) end
  if not id then return end
  local n = itemCount(id)
  if not n then return end
  return {
    itemID     = id,
    name       = name,
    have       = n,
    source     = "item",
    capturedAt = now,
  }
end

--------------------------------------------------------------------------------
-- Warband balances: what OTHER characters hold
--
-- Blizzard's REST API has no currency endpoint, so keygrid-sync can't fill this
-- in — the only source for a character KeyGrid has never seen is the data behind
-- the currency-transfer UI, which knows every account character's balance for a
-- transferable currency. Those functions are new enough (and were named more
-- than once) that they're probed rather than called outright: a client without
-- them simply falls back to KeyGrid's own per-character captures.
--------------------------------------------------------------------------------
local ACCOUNT_FETCH = {
  "FetchCurrencyDataFromAccountCharacters",
  "GetCurrencyDataFromAccountCharacters",
  "GetCurrencyDataForAccountCharacters",
}
local ACCOUNT_REQUEST = {
  "RequestCurrencyDataForAccountCharacters",
  "RequestCurrencyDataFromAccountCharacters",
}

local function accountFn(names)
  if not C_CurrencyInfo then return nil end
  for _, n in ipairs(names) do
    if type(C_CurrencyInfo[n]) == "function" then return C_CurrencyInfo[n], n end
  end
end

-- Name of the API this client actually has, for /kg curdump.
function C.AccountAPIName()
  local _, name = accountFn(ACCOUNT_FETCH)
  return name
end

-- The data arrives asynchronously, so ask early (capture time) and the answer is
-- already cached by the time anyone hovers a cell.
local lastAccountRequest = 0
function C.RequestAccountData()
  local fn = accountFn(ACCOUNT_REQUEST)
  if not fn then return end
  local now = (GetTime and GetTime()) or 0
  if now > 0 and now - lastAccountRequest < 10 then return end
  lastAccountRequest = now
  pcall(fn)
end

-- -> array of { name, quantity }, richest first. nil when the client has no such
-- API, or hasn't answered yet. Field names are read loosely for the same reason
-- the functions are probed.
function C.AccountBalances(id)
  local fn = accountFn(ACCOUNT_FETCH)
  if not (id and fn) then return nil end
  local ok, data = pcall(fn, id)
  if not ok or type(data) ~= "table" then return nil end
  local out = {}
  local me = UnitName and UnitName("player")
  local haveMe = false
  for _, e in pairs(data) do
    if type(e) == "table" then
      local name = e.characterName or e.name or e.character
      local qty = tonumber(e.quantity or e.amount or e.currencyQuantity)
      if name and qty then
        if name == me then haveMe = true end
        out[#out + 1] = { name = name, quantity = qty }
      end
    end
  end
  -- Empty means the answer hasn't arrived yet (the fetch is asynchronous), which
  -- is not the same as "nobody has any" — say nothing rather than report a total
  -- that is missing every alt.
  if #out == 0 then return nil end
  -- The list is the OTHER characters on the account: this one is read straight
  -- from the currency, or the total is short by everything you're carrying.
  if me and not haveMe then
    local info = currencyInfo(id)
    if info then
      out[#out + 1] = { name = me, quantity = info.quantity or 0, isPlayer = true }
    end
  end
  table.sort(out, function(a, b)
    if a.quantity ~= b.quantity then return a.quantity > b.quantity end
    return a.name < b.name
  end)
  return out
end

--------------------------------------------------------------------------------
-- Crests
--
-- Every expansion ships a full set of crests (one per tier) and old ones stay in
-- the currency list forever, so no name match can pick out "this season's". What
-- is reliable: one expansion's crests occupy adjacent currency ids, in ascending
-- tier order. So take every crest in THIS character's list, and keep the newest
-- contiguous run of ids — that's the current set, lowest tier first.
--
-- Deliberately never cached account-wide: a character who has earned none this
-- season would resolve to a leftover cluster and poison every row.
--------------------------------------------------------------------------------
local CREST_CLUSTER_GAP = 8
local CREST_PROBE_STEPS = 4

local function isCrestID(id)
  local info = currencyInfo(id)
  local name = info and info.name
  return name and name ~= "" and name:lower():find("crest", 1, true) and true or false
end

function C.CrestIDs()
  local ids = {}
  forEachCurrency(function(info, _, cid)
    local name = info.name and info.name:lower()
    if cid and name and name:find("crest", 1, true) then ids[#ids + 1] = cid end
  end)
  table.sort(ids)
  local cluster = {}
  for i = #ids, 1, -1 do
    if #cluster == 0 or (cluster[1] - ids[i]) <= CREST_CLUSTER_GAP then
      table.insert(cluster, 1, ids[i])       -- keep ascending = tier order
    else
      break
    end
  end
  if #cluster == 0 then return cluster end

  -- The list holds only the tiers this character has earned, so fill in the
  -- rest: every id across the cluster's span (a tier you've never earned leaves
  -- a hole in the middle just as easily as at either end), then a bounded walk
  -- outward. GetCurrencyInfo names a currency you have none of, and a tier
  -- reading "0" beats a tier missing from the tooltip. Bounded because far
  -- enough out is another expansion's crest block.
  local out = {}
  for id = cluster[1], cluster[#cluster] do
    if isCrestID(id) then out[#out + 1] = id end
  end
  local id, steps = cluster[1] - 1, 0
  while steps < CREST_PROBE_STEPS and isCrestID(id) do
    table.insert(out, 1, id)
    id, steps = id - 1, steps + 1
  end
  id, steps = cluster[#cluster] + 1, 0
  while steps < CREST_PROBE_STEPS and isCrestID(id) do
    out[#out + 1] = id
    id, steps = id + 1, steps + 1
  end
  return out
end

-- The id block also holds crests nobody can earn: Midnight S2 ships four extra
-- "Mistcrest" entries that duplicate real tier names with no season cap and no
-- way to gain them. Drop anything with no cap that has never been earned — but
-- only when a genuinely capped tier exists, so a season that simply doesn't cap
-- its crests still lists every tier.
local function dropUnearnableTiers(list)
  local anyCapped = false
  for _, s in ipairs(list) do
    if (s.cap or 0) > 0 then anyCapped = true end
  end
  if not anyCapped then return list end
  local out = {}
  for _, s in ipairs(list) do
    if (s.cap or 0) > 0 or (s.have or 0) > 0 or (s.collected or 0) > 0 then
      out[#out + 1] = s
    end
  end
  return out
end

-- Full snapshot per crest tier, each carrying its own season cap.
function C.CrestSnapshots(now)
  local all = {}
  for _, id in ipairs(C.CrestIDs()) do
    local snap = C.Snapshot(id, now)
    if snap then all[#all + 1] = snap end
  end
  local out = dropUnearnableTiers(all)
  for tier, snap in ipairs(out) do snap.tier = tier end
  return out
end

-- Headline for the Crest column: the highest tier this character has actually
-- seen, else the top tier (so a fresh character reads "0", not "unknown").
function C.HeadlineCrest(list)
  if not list or #list == 0 then return nil end
  for i = #list, 1, -1 do
    local s = list[i]
    if (s.have or 0) > 0 or (s.collected or 0) > 0 then return s end
  end
  return list[#list]
end

--------------------------------------------------------------------------------
-- Diagnostics
--------------------------------------------------------------------------------
local DUMP_ORDER = { "VOIDCORES", "COINS", "MARL", "MANAFLUX", "SPARKDUST" }

local function printResolved()
  NS.Print("Resolved (account-wide cache):")
  for _, key in ipairs(DUMP_ORDER) do
    local id = C.Resolve(key)
    local label = C.Label(key)
    if id then
      local info = currencyInfo(id)
      local src = NS.CURRENCY[key] and "hardcoded" or "cached"
      print(("  %s = %d (%s)  have=%s earned=%s  [%s]"):format(
        label, id, (info and info.name) or "?", tostring(info and info.quantity),
        tostring(info and info.totalEarned), src))
    else
      local def = DEFS[key]
      local snap = def.item and C.ItemSnapshot(key, 0, NS.ITEM[key])
      if snap then
        print(("  %s = item %d (x%d) — not a currency; tracked from bags")
          :format(label, snap.itemID, snap.have or 0))
      elseif def.scan == false then
        print(("  |cffff5555%s = NOT FOUND|r (not in this character's currency list)"):format(label))
      else
        print(("  |cffff5555%s = NOT FOUND|r (no currency id 1-%d matches, none in bags)")
          :format(label, MAX_CURRENCY_ID))
      end
    end
  end

  local crests = C.CrestSnapshots(GetServerTime())
  if #crests == 0 then
    print("  |cffff5555Crests = NOT FOUND|r (none in this character's currency list)")
  else
    local head = C.HeadlineCrest(crests)
    print(("  Crests (%d, newest id cluster — headline is %s):"):format(#crests, head and head.name or "?"))
    for _, s in ipairs(crests) do
      print(("    [%d] %s  have=%d earned=%d cap=%s wk=%d/%d"):format(
        s.id, s.name or "?", s.have or 0, s.collected or 0, tostring(s.cap or 0),
        s.weekly or 0, s.weeklyCap or 0))
    end
  end

  -- Whether this client can tell us what other characters hold.
  local api = C.AccountAPIName()
  if api then
    local coins = C.AccountBalances(C.Resolve("COINS"))
    print(("  Warband API: |cff40ff40C_CurrencyInfo.%s|r — %s for %s"):format(
      api, coins and ((#coins) .. " characters") or "no data yet", C.Label("COINS")))
    for _, e in ipairs(coins or {}) do
      print(("    %s  %d"):format(e.name, e.quantity))
    end
  else
    print("  Warband API: |cffff5555none on this client|r — roster falls back to KeyGrid's captures")
  end

  NS.Print("Missing? /kg curfind <text> to search every currency by name, then set")
  print("  NS.CURRENCY.<KEY> = <id> in Currencies.lua (KEY = "
    .. table.concat(DUMP_ORDER, "/") .. ")")
end

function C.Dump()
  if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize) then
    NS.Print("Currency API unavailable.")
    return
  end
  NS.Print("This character's currency list (expanding all headers):")
  local n = 0
  forEachCurrency(function(info, _, cid)
    n = n + 1
    local d = cid and currencyInfo(cid)
    if d then
      print(("  [%s] %s  have=%s earned=%s cap=%s wk=%s/%s earnedCap=%s"):format(
        tostring(cid), info.name or "?", tostring(d.quantity or 0),
        tostring(d.totalEarned or 0), tostring(d.maxQuantity or 0),
        tostring(d.quantityEarnedThisWeek or 0), tostring(d.maxWeeklyQuantity or 0),
        tostring(d.useTotalEarnedForMaxQty)))
    else
      print(("  [%s] %s  have=%s"):format(tostring(cid), info.name or "?", tostring(info.quantity or 0)))
    end
  end)
  if n == 0 then
    NS.Print("No currencies listed — open the character currency tab once, then retry.")
  else
    print(("  (%d rows — this list only contains currencies this character has earned)"):format(n))
  end
  -- Resolve pass may need the id probe; print the summary once it's finished.
  C.ScanIDs(function() printResolved() end, true)
end

-- Search EVERY currency id by name — the way to find something this character
-- has none of (it never appears in the list above).
function C.Find(text)
  if not text or text == "" then
    NS.Print("Usage: /kg curfind <part of a currency name>")
    return
  end
  local target = text:lower()
  NS.Print(("Searching currency ids 1-%d for '%s'..."):format(MAX_CURRENCY_ID, text))
  local id, hits = 1, 0
  local function step()
    local stop = math.min(id + CHUNK - 1, MAX_CURRENCY_ID)
    while id <= stop do
      local info = currencyInfo(id)
      local name = info and info.name
      if name and name ~= "" and name:lower():find(target, 1, true) then
        hits = hits + 1
        if hits <= 40 then
          print(("  [%d] %s  have=%s earned=%s cap=%s wk=%s/%s"):format(
            id, name, tostring(info.quantity or 0), tostring(info.totalEarned or 0),
            tostring(info.maxQuantity or 0), tostring(info.quantityEarnedThisWeek or 0),
            tostring(info.maxWeeklyQuantity or 0)))
        end
      end
      id = id + 1
    end
    if id <= MAX_CURRENCY_ID then
      NS.After(0, step)
    else
      NS.Print(("%d match%s."):format(hits, hits == 1 and "" or "es")
        .. (hits > 40 and " (first 40 shown)" or ""))
    end
  end
  step()
end
