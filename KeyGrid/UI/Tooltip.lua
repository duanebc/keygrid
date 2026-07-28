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
function UI.ShowCellTooltip(anchor, c, mapID)
  local name = NS.Dungeons.NameFor(mapID) or ("Dungeon " .. tostring(mapID))
  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  GameTooltip:AddLine(name, 1, 1, 1)
  GameTooltip:AddLine(c.name or c._key or "", 0.7, 0.7, 0.7)

  local b = c.best and c.best[mapID]
  if not b or not b.level then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Never run this season.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
    return
  end

  GameTooltip:AddLine(" ")
  local state = b.timed and "|cff19ff19Timed|r" or "|cffff7733Over time *|r"
  GameTooltip:AddDoubleLine("Best: +" .. b.level .. "  " .. state, tostring(b.score or 0) .. " pts", 1, 1, 1, 1, 1, 1)
  GameTooltip:AddDoubleLine("Duration", fmtDuration(b.durationSec), 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddDoubleLine("Completed", fmtDate(b.completedAt), 0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddDoubleLine("Source", sourceLabel(b.source), 0.7, 0.7, 0.7, 0.7, 0.7, 0.7)

  -- Score delta from timing one key level higher (rough hint)
  if b.timed and NS.UI.ScoreColor then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Timing +" .. (b.level + 1) .. " would raise this dungeon's score.", 0.5, 0.8, 1)
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
-- Vault column tooltip
--------------------------------------------------------------------------------
function UI.ShowVaultTooltip(anchor, c)
  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Great Vault — Mythic+", 1, 1, 1)
  local v = c.vault
  if not v or not v.capturedAt then
    GameTooltip:AddLine("Unknown — log in on this character.", 1, 0.75, 0.1)
  elseif NS.Store.IsStale(v.capturedAt) then
    GameTooltip:AddLine("Unknown since the weekly reset — log in to update.", 1, 0.75, 0.1)
  else
    GameTooltip:AddLine("Reward each slot grants next reset:", 0.7, 0.7, 0.7)
    local slots = {}
    for i = 1, #v do
      if type(v[i]) == "table" then slots[#slots + 1] = v[i] end
    end
    table.sort(slots, function(a, b) return (a.threshold or 0) < (b.threshold or 0) end)
    for i = 1, 3 do
      local s = slots[i]
      if s then
        local earned = (s.progress or 0) >= (s.threshold or math.huge)
        local left = ("  %d / %d runs"):format(s.progress or 0, s.threshold or 0)
        if earned then
          GameTooltip:AddDoubleLine(left, "Mythic +" .. (s.level or 0), 0.3, 1, 0.3, 1, 1, 1)
        else
          GameTooltip:AddDoubleLine(left, "not yet unlocked", 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
        end
      end
    end
    GameTooltip:AddLine("Captured " .. UI.Ago(v.capturedAt), 0.5, 0.5, 0.5)
  end
  GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Crest column tooltip
--------------------------------------------------------------------------------
function UI.ShowCrestTooltip(anchor, c)
  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  local cr = c.crest
  GameTooltip:AddLine((cr and cr.name) or "Mythic Crest", 1, 1, 1)
  if not cr then
    GameTooltip:AddLine("Unknown — log in on this character.", 1, 0.75, 0.1)
  else
    GameTooltip:AddDoubleLine("Have", tostring(cr.count or 0), 0.7, 0.7, 0.7, 0.95, 0.8, 0.4)
    -- Show which currency this actually is: the "highest crest" guess can land on
    -- a leftover previous-expansion crest if the season has none.
    if cr.id then
      GameTooltip:AddDoubleLine("Currency id", tostring(cr.id), 0.45, 0.45, 0.45, 0.6, 0.6, 0.6)
    end
    if (cr.weeklyCap or 0) > 0 then
      GameTooltip:AddDoubleLine("This week", ("%d / %d"):format(cr.weekly or 0, cr.weeklyCap or 0),
        0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:AddLine("As of " .. UI.Ago(cr.capturedAt), 0.5, 0.5, 0.5)
  end
  GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Gearing-currency tooltip (Field Accolades / Voidlight Marl). `field` is the
-- character-record key; snapshots come from NS.Currencies.Snapshot/ItemSnapshot,
-- so a currency carries earned/spent/cap while a bag reagent carries only a count.
--------------------------------------------------------------------------------
function UI.ShowCurrencyTooltip(anchor, c, field, title, tint)
  local rec = c[field]
  local r, g, b = 1, 1, 1
  if tint then r, g, b = tint[1], tint[2], tint[3] end

  GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
  GameTooltip:AddLine((rec and rec.name) or title, 1, 1, 1)
  GameTooltip:AddLine(c.name or c._key or "", 0.7, 0.7, 0.7)

  if not rec then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Unknown — log in on this character.", 1, 0.75, 0.1)
    GameTooltip:AddLine("If it stays blank on a character you've played,", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("run /kg curdump — the name match may need an id.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
    return
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("On hand", tostring(rec.have or 0), 0.7, 0.7, 0.7, r, g, b)
  if rec.id then
    GameTooltip:AddDoubleLine("Currency id", tostring(rec.id), 0.45, 0.45, 0.45, 0.6, 0.6, 0.6)
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
  if rec.source == "item" then
    GameTooltip:AddLine("Tracked as a bag reagent (bags + banks).", 0.55, 0.75, 1)
  else
    GameTooltip:AddDoubleLine("Collected", tostring(rec.collected or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Spent", tostring(rec.spent or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    if (rec.cap or 0) > 0 then
      local label = rec.useEarnedCap and "Season cap (earned)" or "Cap"
      GameTooltip:AddDoubleLine(label, ("%d / %d"):format(
        rec.useEarnedCap and (rec.collected or 0) or (rec.have or 0), rec.cap), 0.7, 0.7, 0.7, 1, 1, 1)
      local left = math.max(0, rec.cap - (rec.useEarnedCap and (rec.collected or 0) or (rec.have or 0)))
      GameTooltip:AddDoubleLine("Left before cap", tostring(left), 0.7, 0.7, 0.7, 0.3, 1, 0.3)
    end
    if (rec.weeklyCap or 0) > 0 then
      GameTooltip:AddDoubleLine("This week", ("%d / %d"):format(rec.weekly or 0, rec.weeklyCap),
        0.7, 0.7, 0.7, 1, 1, 1)
    end
  end
  GameTooltip:AddLine("As of " .. UI.Ago(rec.capturedAt), 0.5, 0.5, 0.5)
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
  GameTooltip:AddDoubleLine("Rating", tostring(c.score or 0), 0.7, 0.7, 0.7, UI.ScoreColor(c.score))

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
  if c.accolades then cur[#cur + 1] = { c.accolades.name or "Field Accolades", c.accolades.have or 0 } end
  if c.marl then cur[#cur + 1] = { c.marl.name or "Voidlight Marl", c.marl.have or 0 } end
  if c.cores then cur[#cur + 1] = { c.cores.name or "Void Cores", c.cores.have or 0 } end
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
