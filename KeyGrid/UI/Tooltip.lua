-- KeyGrid/UI/Tooltip.lua
-- Cell, key, and row tooltip content.

local ADDON, NS = ...
NS.UI = NS.UI or {}
local UI = NS.UI

local function fmtDuration(sec)
  sec = sec or 0
  if sec <= 0 then return "—" end
  local m = math.floor(sec / 60)
  local s = math.floor(sec % 60)
  return ("%d:%02d"):format(m, s)
end

local function fmtDate(epoch)
  if not epoch or epoch == 0 then return "—" end
  return date("%b %d", epoch)
end

local function sourceLabel(src) return src == "api" and "API" or "in-game" end

--------------------------------------------------------------------------------
-- Dungeon cell tooltip
--------------------------------------------------------------------------------
-- One run, four lines: the headline with its score, then how it went and where
-- the record came from. `tint` colors the headline so timed and over time are
-- told apart at a glance as well as by the label.
local function addRunBlock(label, run, tint)
  local r, g, b = tint[1], tint[2], tint[3]
  GameTooltip:AddDoubleLine(label .. " +" .. (run.level or 0),
    tostring(run.score or 0) .. " pts", r, g, b, 1, 1, 1)
  GameTooltip:AddDoubleLine("   Duration", fmtDuration(run.durationSec), 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddDoubleLine("   Completed", fmtDate(run.completedAt), 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddDoubleLine("   Source", sourceLabel(run.source), 0.55, 0.55, 0.55, 0.55, 0.55, 0.55)
end

function UI.ShowCellTooltip(anchor, c, mapID)
  local name = NS.Dungeons.NameFor(mapID) or ("Dungeon " .. tostring(mapID))
  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  GameTooltip:AddLine(name, 1, 1, 1)
  GameTooltip:AddLine(c.name or c._key or "", 0.7, 0.7, 0.7)

  -- The cell only has room for one number, so it shows the timed run. Both are
  -- here: the over-time run is where the group's real ceiling shows, and a key
  -- you have cleared but not timed is exactly the one worth another go.
  local timed, over = NS.Store.Runs(c, mapID)
  if not timed and not over then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Never run this season.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
    return
  end

  GameTooltip:AddLine(" ")
  if timed then
    addRunBlock("|cff19ff19Timed|r", timed, { 0.1, 1.0, 0.1 })
  else
    GameTooltip:AddDoubleLine("|cff19ff19Timed|r", "never this season", 0.1, 1.0, 0.1, 0.6, 0.6, 0.6)
  end
  if over then
    GameTooltip:AddLine(" ")
    addRunBlock("|cffff7733Over time *|r", over, { 1.0, 0.45, 0.20 })
  end

  -- What to do about it. A cleared-but-blown key above the timed best is the
  -- specific, useful version of "run a higher key".
  GameTooltip:AddLine(" ")
  if over and (not timed or (over.level or 0) > (timed.level or 0)) then
    GameTooltip:AddLine("Timing that +" .. (over.level or 0) .. " would raise this dungeon's score.",
      0.5, 0.8, 1)
  elseif timed then
    GameTooltip:AddLine("Timing +" .. ((timed.level or 0) + 1) .. " would raise this dungeon's score.",
      0.5, 0.8, 1)
  end
  GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Key column tooltip
--------------------------------------------------------------------------------
function UI.ShowKeyTooltip(anchor, c)
  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Keystone", 1, 1, 1)
  local ks = c.keystone
  if not ks or not ks.capturedAt then
    GameTooltip:AddLine("Unknown — this character hasn't been logged in.", 1, 0.75, 0.1)
    GameTooltip:AddLine("Log in on it once this week to capture its key.", 0.6, 0.6, 0.6)
  elseif NS.Store.IsStale(ks.capturedAt) then
    GameTooltip:AddLine("Unknown since the weekly reset.", 1, 0.75, 0.1)
    if ks.mapID and ks.level then
      GameTooltip:AddLine("Last seen (pre-reset): " .. NS.Dungeons.Abbr(ks.mapID) .. "+" .. ks.level,
        0.5, 0.5, 0.5)
    end
    GameTooltip:AddLine("Captured " .. UI.Ago(ks.capturedAt), 0.6, 0.6, 0.6)
  elseif not ks.mapID or not ks.level then
    GameTooltip:AddLine("No keystone held.", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Captured " .. UI.Ago(ks.capturedAt), 0.6, 0.6, 0.6)
  else
    local dungeon = NS.Dungeons.NameFor(ks.mapID) or NS.Dungeons.Abbr(ks.mapID)
    GameTooltip:AddLine(dungeon .. "  +" .. ks.level, 1, 1, 1)
    GameTooltip:AddLine("Captured " .. UI.Ago(ks.capturedAt) .. " (in-game)", 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Score column tooltip. "N/A" has two distinct causes and the difference is the
-- whole point: one needs a run, the other needs a login.
--------------------------------------------------------------------------------
function UI.ShowScoreTooltip(anchor, c)
  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Mythic+ rating", 1, 1, 1)
  GameTooltip:AddLine(c.name or c._key or "", 0.7, 0.7, 0.7)
  GameTooltip:AddLine(" ")

  local score = NS.Store.SeasonScore(c)
  if score > 0 then
    GameTooltip:AddDoubleLine("This season", tostring(score), 0.7, 0.7, 0.7, UI.ScoreColor(score))
    if c.scoreAt then
      GameTooltip:AddLine(("%s, %s"):format(sourceLabel(c.scoreSource), UI.Ago(c.scoreAt)), 0.5, 0.5, 0.5)
    end
  elseif c.scoreSeason then
    GameTooltip:AddLine("No Mythic+ run this season.", 0.7, 0.7, 0.7)
    if (c.peakScore or 0) > 0 then
      GameTooltip:AddDoubleLine("Best ever", tostring(c.peakScore), 0.5, 0.5, 0.5, 0.6, 0.6, 0.6)
    end
  else
    GameTooltip:AddLine("Not seen since the season rolled.", 1, 0.75, 0.1)
    GameTooltip:AddLine("Ratings reset each season, so the last number KeyGrid", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("captured is no longer this character's.", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Log in on it to fill this in.", 0.6, 0.6, 0.6)
    if (c.peakScore or 0) > 0 then
      GameTooltip:AddDoubleLine("Last known", tostring(c.peakScore), 0.5, 0.5, 0.5, 0.6, 0.6, 0.6)
    end
  end
  GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Vault column tooltip
--------------------------------------------------------------------------------
function UI.ShowVaultTooltip(anchor, c)
  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Great Vault — Mythic+", 1, 1, 1)
  GameTooltip:AddLine(c.name or c._key or "", 0.7, 0.7, 0.7)

  local v = c.vault
  if not v or not v.capturedAt then
    GameTooltip:AddLine("Unknown — log in on this character.", 1, 0.75, 0.1)
    GameTooltip:Show()
    return
  end
  if NS.Store.IsStale(v.capturedAt) then
    GameTooltip:AddLine("Unknown since the weekly reset — log in to update.", 1, 0.75, 0.1)
    GameTooltip:Show()
    return
  end

  local plan = NS.Data.VaultPlan(c)
  if not plan then
    GameTooltip:AddLine("Unknown — log in on this character.", 1, 0.75, 0.1)
    GameTooltip:Show()
    return
  end

  GameTooltip:AddLine(" ")

  -- The question the column exists to answer, first and in runs.
  --
  -- Being finished is visible in the slots themselves, so it is said for every
  -- character, run list or not. Telling somebody whose three slots already read
  -- 318 to go and log in is exactly the nagging this tooltip is meant to end.
  local said = false
  if plan.maxed then
    GameTooltip:AddDoubleLine("All three at top reward", "done",
      0.7, 0.7, 0.7, 0.3, 1, 0.3)
    said = true
  elseif plan.cap and plan.cap.runsNeeded then
    local n = plan.cap.runsNeeded
    GameTooltip:AddDoubleLine("All three at top reward",
      n <= 0 and "done"
        or ("%d more +%d%s"):format(n, plan.cap.level, n == 1 and "" or "s"),
      0.7, 0.7, 0.7, 1, 1, 1)
    said = true
  end

  -- What each slot will actually hand over. Item levels, in threshold order,
  -- because that is the number you would compare against what you are wearing.
  local parts = {}
  for _, slot in ipairs(plan.slots) do
    parts[#parts + 1] = slot.itemLevel and tostring(slot.itemLevel) or "—"
  end
  if #parts > 0 then
    local r, g, b = 1, 1, 1
    if plan.maxed then r, g, b = 0.3, 1, 0.3 end
    GameTooltip:AddDoubleLine("Rewards", table.concat(parts, " / "),
      0.7, 0.7, 0.7, r, g, b)
  end

  if plan.haveRuns then
    GameTooltip:AddDoubleLine("Runs this week", tostring(plan.runsThisWeek or 0),
      0.7, 0.7, 0.7, 1, 1, 1)
  elseif not said then
    -- Say what the target is even without the run list. Naming the ceiling costs
    -- nothing and is true for every character; withholding the whole answer
    -- until you log in is the opposite of what the roster is for.
    if plan.cap then
      GameTooltip:AddLine(("Top reward is %d, at +%d.")
        :format(plan.cap.itemLevel, plan.cap.level), 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("Run list not captured yet — log in to fill it.",
      0.5, 0.5, 0.5)
  end

  GameTooltip:AddLine("Captured " .. UI.Ago(v.capturedAt), 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Crest column tooltip
--------------------------------------------------------------------------------
-- The cell shows one number (the highest tier this character has earned), so the
-- tooltip is where every tier lives: count and season cap, lowest tier first.
function UI.ShowCrestTooltip(anchor, c)
  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  local cr = c.crest
  GameTooltip:AddLine("Crests", 1, 1, 1)
  GameTooltip:AddLine(c.name or c._key or "", 0.7, 0.7, 0.7)

  if not cr then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Unknown — log in on this character.", 1, 0.75, 0.1)
    GameTooltip:Show()
    return
  end

  GameTooltip:AddLine(" ")
  local list = c.crests
  if type(list) == "table" and #list > 0 then
    GameTooltip:AddDoubleLine("Tier", "Have / season cap", 0.55, 0.55, 0.55, 0.55, 0.55, 0.55)
    for _, s in ipairs(list) do
      local cap = UI.SeasonCap(s)
      local right = cap > 0 and ("%d / %d"):format(UI.CapProgress(s), cap)
        or tostring(s.have or 0)
      -- The tier the Crest column is showing is the one worth spotting fast.
      local isHead = (s.id == cr.id)
      local r, g, b = 0.8, 0.8, 0.85
      if isHead then r, g, b = 0.95, 0.8, 0.4 end
      GameTooltip:AddDoubleLine((isHead and "> " or "  ") .. (s.name or ("id " .. s.id)),
        right, r, g, b, r, g, b)
    end
    -- Weekly caps are per-tier, so only mention one when the game actually sets it.
    for _, s in ipairs(list) do
      if (s.weeklyCap or 0) > 0 then
        GameTooltip:AddDoubleLine("  " .. (s.name or "") .. " this week",
          ("%d / %d"):format(s.weekly or 0, s.weeklyCap), 0.6, 0.6, 0.6, 1, 1, 1)
      end
    end
  else
    -- Pre-upgrade snapshot: only the headline crest was ever stored.
    GameTooltip:AddDoubleLine(cr.name or "Crest", tostring(cr.count or 0),
      0.7, 0.7, 0.7, 0.95, 0.8, 0.4)
    GameTooltip:AddLine("Log in on this character to capture every tier.", 0.6, 0.6, 0.6)
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Column shows: " .. (cr.name or "highest crest earned"), 0.55, 0.75, 1)
  GameTooltip:AddLine("As of " .. UI.Ago(cr.capturedAt), 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- "What every character holds" block, for a currency you shuffle between alts.
-- Live warband data when the client exposes it, else KeyGrid's own captures —
-- which only cover characters you've logged into, and say so.
--------------------------------------------------------------------------------
local ROSTER_ROWS = 12

local function addAccountRoster(rows, r, g, b, heading, note)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(heading, 1, 0.82, 0)
  local total = 0
  for i, e in ipairs(rows) do
    total = total + (e.quantity or 0)
    if i <= ROSTER_ROWS then
      GameTooltip:AddDoubleLine("  " .. e.name, tostring(e.quantity) .. (e.age or ""),
        0.7, 0.7, 0.7, r, g, b)
    end
  end
  if #rows > ROSTER_ROWS then
    GameTooltip:AddLine(("  ...and %d more"):format(#rows - ROSTER_ROWS), 0.5, 0.5, 0.5)
  end
  GameTooltip:AddDoubleLine("  Total", tostring(total), 0.55, 0.75, 1, 0.55, 0.75, 1)
  if note then GameTooltip:AddLine(note, 0.5, 0.5, 0.5, true) end
end

-- KeyGrid's cached snapshots, used when the client has no warband currency API.
local function capturedRoster(field)
  local rows = {}
  for _, c in pairs(NS.Store.DB().chars) do
    local rec = c[field]
    if rec and rec.have then
      rows[#rows + 1] = { name = c.name or "?", quantity = rec.have,
                          age = " |cff808080(" .. UI.Ago(rec.capturedAt) .. ")|r" }
    end
  end
  if #rows == 0 then return nil end
  table.sort(rows, function(a, b)
    if a.quantity ~= b.quantity then return a.quantity > b.quantity end
    return a.name < b.name
  end)
  return rows
end

-- Worth the tooltip space for a currency you can move between characters — the
-- warband total is the number that decides what you can afford. The game's own
-- isAccountTransferable flag is the test, so any currency that becomes
-- transferable gets the block without a code change; a column can also opt in
-- explicitly, which is what covers a row captured before the flag was known.
-- Account-wide currencies are skipped: one shared pool, so "on hand" IS the total.
local function rosterWanted(field, rec)
  if rec and rec.accountWide then return false end
  if rec and rec.transferable then return true end
  local col = NS.Currencies.ColumnByID(field)
  return (col and col.roster) or false
end

local function addCurrencyRoster(field, rec, r, g, b)
  if not rosterWanted(field, rec) then return end
  local col = NS.Currencies.ColumnByID(field)
  -- Ask now so the answer is cached for the next hover; render what we have.
  NS.Currencies.RequestAccountData()
  local id = (rec and rec.id) or (col and NS.Currencies.Resolve(col.key))
  local live = NS.Currencies.AccountBalances(id)
  if live then
    addAccountRoster(live, r, g, b, "Every character (warband):")
  else
    local cached = capturedRoster(field)
    if cached then
      addAccountRoster(cached, r, g, b, "Every character KeyGrid has seen:",
        "Snapshots from characters you've logged into. The Blizzard API has no currency data to fill in the rest.")
    end
  end
end

-- Received this season, against the most the season has offered so far. Only a
-- column with a borrowed history has these (see NS.Currencies.COLUMNS.season);
-- an `offered` of 0 means the cap has not been read yet, so the count stands
-- alone rather than being measured against a zero.
local function addSeasonReceived(got, offered)
  if not got then return end
  if not (offered and offered > 0) then
    GameTooltip:AddDoubleLine("Received this season", tostring(got), 0.7, 0.7, 0.7, 1, 1, 1)
    return
  end
  GameTooltip:AddDoubleLine("Received this season", ("%d / %d"):format(got, offered),
    0.7, 0.7, 0.7, 1, 1, 1)
  -- The cap climbs by one a week and nothing expires, so a week you skipped is
  -- still there to be claimed rather than gone.
  local left = math.max(0, offered - got)
  GameTooltip:AddDoubleLine("Still to claim", tostring(left), 0.7, 0.7, 0.7,
    left > 0 and 1 or 0.3, left > 0 and 0.75 or 1, left > 0 and 0.1 or 0.3)
end

--------------------------------------------------------------------------------
-- Gearing-currency tooltip, shared by every NS.Currencies.COLUMNS entry. `field`
-- is the character-record key (the column id); snapshots come from
-- NS.Currencies.Snapshot/ItemSnapshot,
-- so a currency carries earned/spent/cap while a bag reagent carries only a count.
--------------------------------------------------------------------------------
function UI.ShowCurrencyTooltip(anchor, c, field, title, tint)
  local rec = c[field]
  local r, g, b = 1, 1, 1
  if tint then r, g, b = tint[1], tint[2], tint[3] end
  -- A column whose currency keeps no history of its own borrows one: the Spark
  -- column's season comes from the dust the game hands out beside it. nil for
  -- every other column.
  local col = NS.Currencies.ColumnByID(field)
  local got, offered
  if col and col.season then got, offered = col.season(c) end

  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  GameTooltip:AddLine((rec and rec.name) or title, 1, 1, 1)
  GameTooltip:AddLine(c.name or c._key or "", 0.7, 0.7, 0.7)

  if not rec then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Unknown — log in on this character.", 1, 0.75, 0.1)
    GameTooltip:AddLine("If it stays blank on a character you've played,", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("run /kg curdump — the name match may need an id.", 0.6, 0.6, 0.6)
    -- What the season gave this character is known even when the count isn't:
    -- the spark is a bag item KeyGrid may never have seen, while the dust that
    -- records it is a currency that answers on every character.
    if got then
      GameTooltip:AddLine(" ")
      addSeasonReceived(got, offered)
    end
    -- Still worth showing who does hold some, even from a row that has none.
    addCurrencyRoster(field, nil, r, g, b)
    GameTooltip:Show()
    return
  end

  GameTooltip:AddLine(" ")
  -- The numbers first and together: on hand, what the season has given, what has
  -- gone. Anything about *how* it is tracked -- the id, the transfer rules -- is
  -- below them, because it is context for the reader who goes looking rather
  -- than the answer they opened the tooltip for.
  GameTooltip:AddDoubleLine("On hand", tostring(rec.have or 0), 0.7, 0.7, 0.7, r, g, b)
  -- For a spark this is the line the count on its own cannot give: two in the bag
  -- is a season kept up with if the season has handed out two, and four missed
  -- weeks if it has handed out six.
  addSeasonReceived(got, offered)
  if rec.source == "item" then
    GameTooltip:AddLine("Tracked as a bag reagent (bags + banks).", 0.55, 0.75, 1)
    if got then
      GameTooltip:AddLine("Season count from Tidal Spark Dust, which the game", 0.6, 0.6, 0.6)
      GameTooltip:AddLine("hands you one of with every Spark of Tides.", 0.6, 0.6, 0.6)
    end
  else
    -- totalEarned isn't maintained for every currency; when it reads lower than
    -- what's on hand the game simply isn't counting, and "Collected 0" beside
    -- "On hand 6200" is worse than saying nothing.
    if (rec.collected or 0) >= (rec.have or 0) then
      -- "Collected" does not say when. A currency the game caps or measures per
      -- season resets its earned total with the season, so for those it is
      -- specifically this season's -- which is the useful reading, and the one
      -- that makes the number beside it mean something. For anything else the
      -- scope is not ours to claim.
      local seasonal = rec.useEarnedCap or (UI.SeasonCap(rec) > 0)
      GameTooltip:AddDoubleLine(seasonal and "Gained this season" or "Collected",
        tostring(rec.collected or 0), 0.7, 0.7, 0.7, 1, 1, 1)
      GameTooltip:AddDoubleLine("Spent", tostring(rec.spent or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    local cap = UI.SeasonCap(rec)
    if cap > 0 then
      local at = UI.CapProgress(rec)
      local label = rec.useEarnedCap and "Season cap (earned)" or "Season cap"
      GameTooltip:AddDoubleLine(label, ("%d / %d"):format(at, cap), 0.7, 0.7, 0.7, 1, 1, 1)
      GameTooltip:AddDoubleLine("Left before cap", tostring(math.max(0, cap - at)),
        0.7, 0.7, 0.7, 0.3, 1, 0.3)
    end
    if (rec.weeklyCap or 0) > 0 then
      GameTooltip:AddDoubleLine("This week", ("%d / %d"):format(rec.weekly or 0, rec.weeklyCap),
        0.7, 0.7, 0.7, 1, 1, 1)
    end
  end

  if rec.accountWide then
    GameTooltip:AddLine("Account-wide — the same pool on every character.", 0.55, 0.75, 1)
  elseif rec.transferable then
    local pct = tonumber(rec.transferPct)
    if pct and pct > 0 and pct < 100 then
      GameTooltip:AddLine(("Per character — transferable to another character (%d%% arrives)."):format(pct),
        0.55, 0.75, 1)
    else
      GameTooltip:AddLine("Per character — transferable to another character.", 0.55, 0.75, 1)
    end
  end
  if rec.id then
    GameTooltip:AddDoubleLine("Currency id", tostring(rec.id), 0.45, 0.45, 0.45, 0.5, 0.5, 0.5)
  end
  GameTooltip:AddLine("As of " .. UI.Ago(rec.capturedAt), 0.5, 0.5, 0.5)
  addCurrencyRoster(field, rec, r, g, b)
  GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Row / character tooltip
--------------------------------------------------------------------------------
function UI.ShowRowTooltip(anchor, c)
  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  local r, g, b = UI.ClassColor(c.class)
  GameTooltip:AddLine(c.name or c._key or "?", r, g, b)
  GameTooltip:AddLine(c._key or "", 0.6, 0.6, 0.6)
  GameTooltip:AddLine(" ")

  if c.class then GameTooltip:AddDoubleLine("Class", c.class, 0.7, 0.7, 0.7, 1, 1, 1) end
  if c.level then GameTooltip:AddDoubleLine("Level", tostring(c.level), 0.7, 0.7, 0.7, 1, 1, 1) end
  if c.ilvl and c.ilvl > 0 then
    GameTooltip:AddDoubleLine("Item level", ("%.1f"):format(c.ilvl), 0.7, 0.7, 0.7, 1, 1, 1)
  end
  local seasonScore = NS.Store.SeasonScore(c)
  if seasonScore > 0 then
    GameTooltip:AddDoubleLine("Rating", tostring(seasonScore), 0.7, 0.7, 0.7, UI.ScoreColor(seasonScore))
  else
    GameTooltip:AddDoubleLine("Rating", "N/A this season", 0.7, 0.7, 0.7, 0.6, 0.6, 0.6)
  end

  -- Per-source timestamps
  GameTooltip:AddLine(" ")
  if c.scoreAt then
    GameTooltip:AddLine(("Best runs: %s, %s"):format(sourceLabel(c.scoreSource), UI.Ago(c.scoreAt)), 0.55, 0.75, 1)
  end
  if c.keystone and c.keystone.capturedAt then
    GameTooltip:AddLine(("Keystone: in-game, %s"):format(UI.Ago(c.keystone.capturedAt)), 0.55, 0.75, 1)
  end

  -- Gearing currencies at a glance
  local cur = {}
  if c.crest then cur[#cur + 1] = { c.crest.name or "Crest", c.crest.count or 0 } end
  for _, col in ipairs(NS.Currencies.COLUMNS) do
    local rec = c[col.id]
    if rec then
      local cap = UI.SeasonCap(rec)
      cur[#cur + 1] = { rec.name or NS.Currencies.Label(col.key),
        cap > 0 and ("%d / %d"):format(UI.CapProgress(rec), cap) or (rec.have or 0) }
    end
  end
  if #cur > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Currencies:", 1, 0.82, 0)
    for _, e in ipairs(cur) do
      GameTooltip:AddDoubleLine("  " .. e[1], tostring(e[2]), 0.7, 0.7, 0.7, 1, 1, 1)
    end
  end

  -- Vault detail
  if c.vault and #c.vault > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Great Vault (M+):", 1, 0.82, 0)
    for i, slot in ipairs(c.vault) do
      local met = (slot.progress or 0) >= (slot.threshold or math.huge)
      local line = ("  Slot %d: %d/%d runs"):format(i, slot.progress or 0, slot.threshold or 0)
      if met and slot.level and slot.level > 0 then line = line .. ("  (+%d)"):format(slot.level) end
      if met then GameTooltip:AddLine(line, 0.3, 1, 0.3) else GameTooltip:AddLine(line, 0.6, 0.6, 0.6) end
    end
  end
  GameTooltip:Show()
end
