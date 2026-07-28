-- KeyGrid/UI/Grid.lua
-- Row/cell construction, colors, and tooltip wiring.

local ADDON, NS = ...
NS.UI = NS.UI or {}
local UI = NS.UI
local M = UI.M

-- Timed state colors (see spec 4.3). Never rely on color alone — the ▼ glyph
-- carries the untimed state for anyone who can't distinguish the hues.
local GREEN  = { 0.1, 1.0, 0.1 }
local UNTIME = { 1.0, 0.45, 0.20 }
local GREY   = { 0.42, 0.42, 0.42 }
local WHITE  = { 1.0, 1.0, 1.0 }
local AMBER  = { 1.0, 0.75, 0.10 }
local ACCOL  = { 0.86, 0.76, 0.46 }   -- Field Accolades
local MARL   = { 0.72, 0.58, 0.95 }   -- Voidlight Marl

-- Compact large counts so a five-digit stack can't overflow a ~52px column.
function UI.ShortNum(n)
  n = math.floor(tonumber(n) or 0)
  if n >= 100000 then return ("%dk"):format(math.floor(n / 1000)) end
  if n >= 10000 then
    local s = ("%.1fk"):format(n / 1000):gsub("%.0k$", "k")
    return s
  end
  return tostring(n)
end

local function scoreColor(score)
  if not score or score == 0 then return 0.6, 0.6, 0.6 end
  if C_ChallengeMode and C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor then
    local col = C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor(score)
    if col then return col.r, col.g, col.b end
  end
  if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor then
    local col = C_ChallengeMode.GetDungeonScoreRarityColor(score)
    if col then return col.r, col.g, col.b end
  end
  return 1, 1, 1
end
UI.ScoreColor = scoreColor

local function classColor(classFile)
  if classFile and C_ClassColor and C_ClassColor.GetClassColor then
    local c = C_ClassColor.GetClassColor(classFile)
    if c then return c.r, c.g, c.b end
  end
  if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
    local c = RAID_CLASS_COLORS[classFile]
    return c.r, c.g, c.b
  end
  return 0.9, 0.9, 0.9
end
UI.ClassColor = classColor

-- Vault column: the three M+ reward slots' key levels next reset, e.g. "14/12/0".
-- Sorted by threshold (1/4/8); a slot shows its level only once its runs are met.
function UI.VaultCell(c)
  local v = c.vault
  if not v or not v.capturedAt then return "--", GREY end
  if NS.Store.IsStale(v.capturedAt) then return "?", AMBER end
  local slots = {}
  for i = 1, #v do
    if type(v[i]) == "table" then slots[#slots + 1] = v[i] end
  end
  table.sort(slots, function(a, b) return (a.threshold or 0) < (b.threshold or 0) end)
  local parts, any = {}, false
  for i = 1, 3 do
    local s = slots[i]
    local lvl = (s and (s.progress or 0) >= (s.threshold or math.huge)) and (s.level or 0) or 0
    if lvl > 0 then any = true end
    parts[i] = tostring(lvl)
  end
  return table.concat(parts, "/"), any and WHITE or GREY
end

-- Key column text/color. Returns text, {r,g,b}, isUnknown
function UI.KeyCell(c)
  local ks = c.keystone
  if not ks or not ks.capturedAt or NS.Store.IsStale(ks.capturedAt) then
    return "?", AMBER, true                    -- stale or never captured
  end
  if not ks.mapID or not ks.level then
    return "--", GREY, false                   -- checked this reset, no key held
  end
  return NS.Dungeons.Abbr(ks.mapID) .. "+" .. ks.level, WHITE, false
end

--------------------------------------------------------------------------------
-- Cell primitives
--------------------------------------------------------------------------------
local function ensureCell(row, index)
  local cell = row.cells[index]
  if cell then return cell end
  cell = CreateFrame("Button", nil, row)
  cell.big = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  cell.big:SetPoint("TOP", cell, "TOP", 0, -2)
  cell.small = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  cell.small:SetPoint("BOTTOM", cell, "BOTTOM", 0, 2)
  cell:SetScript("OnLeave", function() if GameTooltip:IsOwned(cell) then GameTooltip:Hide() end end)
  row.cells[index] = cell
  return cell
end

local function setBig(cell, text, color, justify)
  cell.big:SetText(text or "")
  if color then cell.big:SetTextColor(color[1], color[2], color[3]) end
  cell.big:SetJustifyH(justify or "CENTER")
  cell.big:ClearAllPoints()
  if justify == "LEFT" then
    cell.big:SetPoint("LEFT", cell, "LEFT", 2, 0)
  else
    cell.big:SetPoint("CENTER", cell, "CENTER", 0, 0)
  end
end

--------------------------------------------------------------------------------
-- Per-column rendering
--------------------------------------------------------------------------------
local function renderCell(row, cell, col, c)
  cell.small:SetText("")
  cell:SetScript("OnEnter", nil)

  if col.id == "name" then
    local r, g, b = classColor(c.class)
    cell.big:ClearAllPoints()
    cell.big:SetPoint("LEFT", cell, "LEFT", 2, 0)
    cell.big:SetJustifyH("LEFT")
    cell.big:SetText(c.name or c._key or "?")
    cell.big:SetTextColor(r, g, b)
    cell:SetScript("OnEnter", function(self) NS.UI.ShowRowTooltip(self, c) end)

  elseif col.id == "ilvl" then
    local il = c.ilvl or 0
    setBig(cell, il > 0 and tostring(math.floor(il + 0.5)) or "--",
      il > 0 and { 0.82, 0.82, 0.9 } or GREY)

  elseif col.id == "score" then
    local score = c.score or 0
    setBig(cell, score > 0 and tostring(score) or "--",
      score > 0 and { scoreColor(score) } or GREY)

  elseif col.id == "key" then
    -- Smaller font + full-width box so long keys (e.g. CAVERN+9) fit and never
    -- overflow into neighbouring columns. WordWrap off truncates rather than spills.
    local text, color = UI.KeyCell(c)
    cell.big:SetFontObject("GameFontNormal")
    cell.big:ClearAllPoints()
    cell.big:SetPoint("LEFT", cell, "LEFT", 1, 0)
    cell.big:SetPoint("RIGHT", cell, "RIGHT", -1, 0)
    cell.big:SetWordWrap(false)
    cell.big:SetJustifyH("CENTER")
    cell.big:SetText(text)
    cell.big:SetTextColor(color[1], color[2], color[3])
    cell:SetScript("OnEnter", function(self) NS.UI.ShowKeyTooltip(self, c) end)

  elseif col.id == "vault" then
    local text, color = UI.VaultCell(c)
    cell.big:SetFontObject("GameFontNormal")
    cell.big:ClearAllPoints()
    cell.big:SetPoint("LEFT", cell, "LEFT", 1, 0)
    cell.big:SetPoint("RIGHT", cell, "RIGHT", -1, 0)
    cell.big:SetWordWrap(false)
    cell.big:SetJustifyH("CENTER")
    cell.big:SetText(text)
    cell.big:SetTextColor(color[1], color[2], color[3])
    cell:SetScript("OnEnter", function(self) NS.UI.ShowVaultTooltip(self, c) end)

  elseif col.id == "crest" then
    local cr = c.crest
    setBig(cell, (cr and cr.count) and tostring(cr.count) or "--",
      (cr and cr.count) and { 0.95, 0.8, 0.4 } or GREY)
    cell:SetScript("OnEnter", function(self) NS.UI.ShowCrestTooltip(self, c) end)

  elseif col.id == "accol" or col.id == "marl" then
    -- Gearing currencies. On-hand count is the headline; a weekly-capped currency
    -- also shows earned/cap underneath (nothing shown when there's no weekly cap).
    local isAccol = (col.id == "accol")
    local rec = isAccol and c.accolades or c.marl
    local n = rec and rec.have
    local weeklyCap = (rec and rec.weeklyCap) or 0
    -- "--" means never captured (unknown). A captured zero shows as a dim "0" so
    -- "none on this character" is visibly different from "no data".
    if n == 0 then
      setBig(cell, "0", GREY)
    else
      setBig(cell, n and UI.ShortNum(n) or "--", n and (isAccol and ACCOL or MARL) or GREY)
    end
    if n and n > 0 and weeklyCap > 0 then
      cell.big:ClearAllPoints()
      cell.big:SetPoint("TOP", cell, "TOP", 0, -1)   -- make room for the weekly line
      cell.small:SetText(("%d/%d"):format(rec.weekly or 0, weeklyCap))
      cell.small:SetTextColor(0.6, 0.6, 0.68)
    end
    cell:SetScript("OnEnter", function(self)
      NS.UI.ShowCurrencyTooltip(self, c, isAccol and "accolades" or "marl",
        NS.Currencies.Label(isAccol and "ACCOLADES" or "MARL"),
        isAccol and ACCOL or MARL)
    end)

  elseif col.isDungeon then
    local b = c.best and c.best[col.mapID]
    if not b or not b.level then
      setBig(cell, "--", GREY)
    else
      local lvlColor = b.timed and GREEN or UNTIME
      local glyph = b.timed and "" or " |cffff7733*|r"  -- '*' = over time (font-safe)
      cell.big:ClearAllPoints()
      cell.big:SetPoint("TOP", cell, "TOP", 0, -1)
      cell.big:SetJustifyH("CENTER")
      cell.big:SetText(tostring(b.level) .. glyph)
      cell.big:SetTextColor(lvlColor[1], lvlColor[2], lvlColor[3])
      cell.small:SetText(tostring(b.score or 0))
      local sr, sg, sb = scoreColor(b.score)
      cell.small:SetTextColor(sr, sg, sb)
    end
    cell:SetScript("OnEnter", function(self) NS.UI.ShowCellTooltip(self, c, col.mapID) end)
  end
end

function UI.renderRowCells(row, cols, c)
  -- hide stale cells if column count shrank
  for i, cell in ipairs(row.cells) do
    if i > #cols then cell:Hide() end
  end
  for i, col in ipairs(cols) do
    local cell = ensureCell(row, i)
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", row, "TOPLEFT", col.x, 0)
    cell:SetSize(col.w, M.ROW_H)
    renderCell(row, cell, col, c)
    cell:Show()
  end
end

function UI.RenderRows(content, cols, list)
  UI.rows = UI.rows or {}
  for _, row in ipairs(UI.rows) do row:Hide() end
  for i, c in ipairs(list) do
    local row = UI.rows[i]
    if not row then
      row = CreateFrame("Button", nil, content)
      row.cells = {}
      row.bg = row:CreateTexture(nil, "BACKGROUND")
      row.bg:SetAllPoints()
      UI.rows[i] = row
    end
    row:SetHeight(M.ROW_H)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * M.ROW_H)
    row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * M.ROW_H)
    row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.0)
    UI.renderRowCells(row, cols, c)
    row:Show()
  end
end
