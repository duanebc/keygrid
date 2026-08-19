-- KeyGrid/Dungeons.lua
-- challengeMapID -> abbreviation mapping, with a live-data fallback.
-- Populate NS.ABBR from `/kg dump` output to lock the polished labels.

local ADDON, NS = ...
local D = {}
NS.Dungeons = D

-- [challengeMapID] = "ABBR"   <- filled from live /kg dump output (Midnight S1).
NS.ABBR = {
  [556] = "PIT",     -- Pit of Saron
  [161] = "SKY",     -- Skyreach
  [402] = "AA",      -- Algeth'ar Academy
  [559] = "XENAS",   -- Nexus-Point Xenas
  [239] = "SEAT",    -- Seat of the Triumvirate
  [557] = "SPIRE",   -- Windrunner Spire
  [558] = "MT",      -- Magisters' Terrace
  [560] = "CAVERN",  -- Maisara Caverns
}

-- Intended header order/labels for Midnight S1 once NS.ABBR is filled.
D.ORDER = { "PIT", "SKY", "AA", "XENAS", "SEAT", "SPIRE", "MT", "CAVERN" }

--------------------------------------------------------------------------------
-- Season name
--
-- C_MythicPlus.GetCurrentSeason() returns a running counter that keeps climbing
-- across expansions (Midnight S2 = 18), and nothing in the API turns that into
-- "Midnight Season 2" — so the mapping is pinned here, one verified line per
-- season. `/kg dump` prints the live id when a new one needs adding.
--
-- Seasons are consecutive, so an id we haven't seen is still numbered correctly
-- by counting from a known season of the same expansion: next patch's 19 reads
-- "Midnight Season 3" with no code change. Only a new *expansion* needs an edit.
--------------------------------------------------------------------------------
NS.SEASONS = {
  [18] = { "Midnight", 2 },   -- observed in-game 2026-08-19
}

function D.SeasonID()
  if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
    local id = C_MythicPlus.GetCurrentSeason()
    -- -1 = between seasons / not loaded yet; fall through to the cached id.
    if id and id > 0 then return id end
  end
  local cached = NS.Store and NS.Store.SeasonID and NS.Store.SeasonID()
  if cached and cached > 0 then return cached end
end

local function expansionName()
  local level = GetExpansionLevel and GetExpansionLevel()
  return level and _G["EXPANSION_NAME" .. level] or nil
end

-- Whatever we can honestly say about the season, for the title bar. Falls back
-- to the expansion name and the raw id rather than guessing a season number —
-- a confidently wrong "Season 1" is worse than an unadorned title.
function D.SeasonTitle()
  local id = D.SeasonID()
  if not id then return expansionName() end

  local known = NS.SEASONS[id]
  if known then return ("%s Season %d"):format(known[1], known[2]) end

  local expansion = expansionName()
  if expansion then
    for knownID, entry in pairs(NS.SEASONS) do
      if entry[1] == expansion then
        local n = entry[2] + (id - knownID)
        if n >= 1 then return ("%s Season %d"):format(expansion, n) end
      end
    end
    return ("%s (season %d)"):format(expansion, id)
  end
  return ("Season %d"):format(id)
end
NS.SeasonTitle = D.SeasonTitle

D.names = {}   -- mapID -> localized dungeon name (cache)

function D.NameFor(mapID)
  if D.names[mapID] then return D.names[mapID] end
  if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    if name and name ~= "" then
      D.names[mapID] = name
      return name
    end
  end
  return nil
end

-- Fallback abbreviation: initials for multi-word names, first 5 chars otherwise.
function D.AutoAbbr(mapID)
  local name = D.NameFor(mapID)
  if not name then return "M" .. tostring(mapID) end
  local words = {}
  for w in name:gmatch("%S+") do
    local lw = w:lower()
    if lw ~= "the" and lw ~= "of" and lw ~= "and" then
      words[#words + 1] = w
    end
  end
  if #words >= 2 then
    local s = ""
    for _, w in ipairs(words) do s = s .. w:sub(1, 1) end
    return s:upper()
  end
  return name:sub(1, 5):upper()
end

function D.Abbr(mapID)
  return NS.ABBR[mapID] or D.AutoAbbr(mapID)
end

-- Column descriptors, ordered by D.ORDER (spec 4.6). Any dungeon whose abbr
-- isn't in ORDER (e.g. before NS.ABBR is filled) falls to the end, by mapID.
local function orderIndex(abbr)
  for i, a in ipairs(D.ORDER) do
    if a == abbr then return i end
  end
  return #D.ORDER + 1
end

function D.Columns()
  local cols = {}
  for _, id in ipairs(NS.Store.SeasonMaps()) do
    cols[#cols + 1] = { mapID = id, abbr = D.Abbr(id) }
  end
  table.sort(cols, function(a, b)
    local ai, bi = orderIndex(a.abbr), orderIndex(b.abbr)
    if ai ~= bi then return ai < bi end
    return a.mapID < b.mapID
  end)
  return cols
end

-- /kg dump : print each season mapID + name so NS.ABBR can be filled from live data.
function D.Dump()
  if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then
    NS.Print("Challenge-mode API not available yet.")
    return
  end
  local maps = C_ChallengeMode.GetMapTable()
  if not maps or #maps == 0 then
    NS.Print("No maps yet — RequestMapInfo may still be pending. Try again in a few seconds.")
    return
  end
  NS.Print(("Season id %s = %s"):format(tostring(D.SeasonID() or "?"),
    D.SeasonTitle() or "unnamed — add it to NS.SEASONS"))
  NS.Print(("Season dungeons (%d) — paste [id]=\"ABBR\" lines into Dungeons.lua NS.ABBR:"):format(#maps))
  for _, id in ipairs(maps) do
    local name = D.NameFor(id) or "?"
    print(("  [%d] = \"%s\",  -- %s"):format(id, D.Abbr(id), name))
  end
end
