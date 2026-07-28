-- KeyGrid/UI/Frame.lua
-- Main window shell: shared title bar, tab strip, and the M+ grid panel.
-- The Void Cores panel is built in UI/CoresGrid.lua; tabs live in UI/Tabs.lua.

local ADDON, NS = ...
NS.UI = NS.UI or {}
local UI = NS.UI

-- Layout constants (shared with Grid.lua / CoresGrid.lua via UI.M)
local M = {
  ROW_H     = 34,
  COL_CHAR  = 116,
  COL_ILVL  = 46,
  COL_SCORE = 56,
  COL_KEY   = 92,
  COL_VAULT = 68,
  COL_CREST = 50,
  COL_ACCOL = 56,   -- Field Accolades
  COL_MARL  = 52,   -- Voidlight Marl
  COL_DUN   = 46,
  PAD       = 12,
  TITLE_H   = 30,
  SUBHDR_H  = 16,   -- affix / reset line
  COLHDR_H  = 18,
  FOOTER_H  = 34,
  TABSTRIP_H = 30,  -- reserved at the bottom for tab buttons
}
UI.M = M

-- Scale a fontstring relative to its current size (e.g. 1.5 = 50% bigger).
function UI.ScaleFont(fs, mult)
  local file, size, flags = fs:GetFont()
  fs:SetFont(file or STANDARD_TEXT_FONT, (size or 10) * mult, flags)
end

-- Apply the user's manually-chosen size if they've resized, else the computed one.
function UI.SizeFrame(w, h)
  local f = UI.frame
  if not f then return end
  local s = NS.Store.DB().ui.size
  if s and s.w and s.h then
    f:SetSize(s.w, s.h)
  else
    f:SetSize(w, h)
  end
end

local BACKDROP = {
  bgFile   = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Buttons\\WHITE8x8",
  edgeSize = 1,
}
UI.BACKDROP = BACKDROP

--------------------------------------------------------------------------------
-- Column model: name, iLvl, score, key, vault, gearing currencies, then one per
-- season dungeon.
--------------------------------------------------------------------------------
function UI.BuildColumns()
  local cols = {}
  local x = M.PAD
  local function add(desc) desc.x = x; cols[#cols + 1] = desc; x = x + desc.w end
  add({ id = "name",  label = "Character", w = M.COL_CHAR,  align = "LEFT",   sortable = true })
  add({ id = "ilvl",  label = "iLvl",      w = M.COL_ILVL,  align = "CENTER", sortable = true })
  add({ id = "score", label = "Score",     w = M.COL_SCORE, align = "CENTER", sortable = true })
  add({ id = "key",   label = "Key",       w = M.COL_KEY,   align = "CENTER", sortable = false })
  add({ id = "vault", label = "Vault",     w = M.COL_VAULT, align = "CENTER", sortable = false })
  add({ id = "crest", label = "Crest",     w = M.COL_CREST, align = "CENTER", sortable = true })
  add({ id = "accol", label = "Accol",     w = M.COL_ACCOL, align = "CENTER", sortable = true })
  add({ id = "marl",  label = "Marl",      w = M.COL_MARL,  align = "CENTER", sortable = true })
  for _, dc in ipairs(NS.Dungeons.Columns()) do
    add({ id = dc.mapID, label = dc.abbr, w = M.COL_DUN, align = "CENTER",
          sortable = true, isDungeon = true, mapID = dc.mapID })
  end
  UI.columns = cols
  UI.contentWidth = x + M.PAD
  return cols
end

--------------------------------------------------------------------------------
-- Header text: affixes + reset countdown
--------------------------------------------------------------------------------
local function affixText()
  local ids = NS.Store.Affixes()
  if not ids or #ids == 0 then return "Affixes: —" end
  local names = {}
  for _, id in ipairs(ids) do
    local name
    if C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
      name = C_ChallengeMode.GetAffixInfo(id)
    end
    names[#names + 1] = name or ("#" .. id)
  end
  return "Affixes: " .. table.concat(names, ", ")
end

local function resetText()
  local secs = 0
  if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
    secs = C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
  end
  if secs <= 0 then return "Reset: —" end
  local d = math.floor(secs / 86400)
  local h = math.floor((secs % 86400) / 3600)
  return ("Reset in %dd %dh"):format(d, h)
end
UI.ResetText = resetText

local function footerText()
  local db = NS.Store.DB()
  local parts = {}
  local key = NS.PlayerKey()
  local me = key and db.chars[key]
  if me and me.vault then
    local filled = 0
    for _, slot in ipairs(me.vault) do
      if (slot.progress or 0) >= (slot.threshold or math.huge) then filled = filled + 1 end
    end
    local total = math.max(#me.vault, 3)
    local glyph = ""
    for i = 1, total do glyph = glyph .. (i <= filled and "|cff40ff40[x]|r" or "|cff555555[ ]|r") end
    parts[#parts + 1] = "Vault: " .. glyph .. (" %d/%d"):format(filled, total)
  end
  if db.lastSyncAt then
    parts[#parts + 1] = "Last sync: " .. NS.UI.Ago(db.lastSyncAt) ..
      " (" .. (db.lastSyncRegion and db.lastSyncRegion:upper() or "API") .. ")"
  else
    parts[#parts + 1] = "No API sync yet — run keygrid-sync"
  end
  return table.concat(parts, "   |   ")
end

-- "2h ago" style relative time
function UI.Ago(epoch)
  if not epoch then return "never" end
  local d = (GetServerTime() or time()) - epoch
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

local function sortArrow(colId)
  local key, dir = NS.Store.SortState()
  if key ~= colId then return "" end
  return dir == "desc" and " |cffffd100v|r" or " |cffffd100^|r"
end

--------------------------------------------------------------------------------
-- M+ grid panel construction (Tab 1)
--------------------------------------------------------------------------------
function UI.BuildGridPanel(f, panel)
  f.affixText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.affixText:SetPoint("TOPLEFT", panel, "TOPLEFT", M.PAD, -3)
  f.affixText:SetJustifyH("LEFT")

  f.header = CreateFrame("Frame", nil, panel)
  f.header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(M.SUBHDR_H + 4))
  f.header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(M.SUBHDR_H + 4))
  f.header:SetHeight(M.COLHDR_H)
  local hbg = f.header:CreateTexture(nil, "BACKGROUND")
  hbg:SetAllPoints(); hbg:SetColorTexture(0.10, 0.11, 0.14, 1)
  f.headerButtons = {}

  local scroll = CreateFrame("ScrollFrame", "KeyGridScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, M.FOOTER_H + 2)
  f.scroll = scroll

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  f.content = content

  f.footer = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  UI.ScaleFont(f.footer, 1.5)
  f.footer:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", M.PAD + 8, 12)
  f.footer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(M.PAD + 8), 12)
  f.footer:SetJustifyH("LEFT")
  f.footer:SetWordWrap(false)

  f.empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  f.empty:SetPoint("TOP", content, "TOP", 0, -20)
  f.empty:SetText("No characters with a rating yet.\nLog in on a rated character, or run keygrid-sync.\n/kg all shows everyone.")
  f.empty:Hide()
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------
function UI.EnsureFrame()
  if UI.frame then return UI.frame end

  local f = CreateFrame("Frame", "KeyGridFrame", UIParent, "BackdropTemplate")
  f:SetSize(560, 300)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetBackdrop(BACKDROP)
  f:SetBackdropColor(0.05, 0.06, 0.08, 0.94)
  f:SetBackdropBorderColor(0, 0, 0, 1)
  f:Hide()  -- frames are shown by default; start hidden so the first /kg opens it

  -- Title bar (drag handle), shared across tabs
  local title = CreateFrame("Frame", nil, f)
  title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT")
  title:SetHeight(M.TITLE_H)
  title:EnableMouse(true)
  title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", function() f:StartMoving() end)
  title:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local p, _, rp, x, y = f:GetPoint()
    NS.Store.SavePoint(p, rp, x, y)
  end)
  local tbg = title:CreateTexture(nil, "BACKGROUND")
  tbg:SetAllPoints(); tbg:SetColorTexture(0.12, 0.14, 0.18, 1)

  f.titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.titleText:SetPoint("LEFT", title, "LEFT", M.PAD, 0)
  f.titleText:SetText("KeyGrid — Midnight Season 1")

  f.subText = title:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.subText:SetPoint("RIGHT", title, "RIGHT", -30, 0)

  local close = CreateFrame("Button", nil, title, "UIPanelCloseButton")
  close:SetPoint("RIGHT", title, "RIGHT", 2, 0)
  close:SetScript("OnClick", function() UI.Hide() end)

  -- Body region between the title and the tab strip; each tab is a panel here.
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -M.TITLE_H)
  f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, M.TABSTRIP_H)

  f.gridPanel = CreateFrame("Frame", nil, f.body)
  f.gridPanel:SetAllPoints(f.body)
  f.coresPanel = CreateFrame("Frame", nil, f.body)
  f.coresPanel:SetAllPoints(f.body)
  f.panels = { f.gridPanel, f.coresPanel }
  local tabNames = { "M+ Grid", "Void Cores" }

  UI.BuildGridPanel(f, f.gridPanel)
  if UI.BuildCoresPanel then UI.BuildCoresPanel(f, f.coresPanel) end

  -- The Loot tab exists only in a developer checkout (SeasonLoot.lua present)
  -- with private mode switched on. Released builds have neither, so they get a
  -- two-tab strip and UI.ShowTab already falls back to tab 1 for a stale
  -- ui.tab = 3 in SavedVariables.
  if NS.PrivateMode() then
    f.lootPanel = CreateFrame("Frame", nil, f.body)
    f.lootPanel:SetAllPoints(f.body)
    f.panels[3] = f.lootPanel
    tabNames[3] = "Loot"
    UI.BuildLootPanel(f, f.lootPanel)
  end

  UI.CreateTabs(f, tabNames)

  -- Resize grip: the user can grow the window; the size is remembered.
  f:SetResizable(true)
  if f.SetResizeBounds then f:SetResizeBounds(360, 180) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
  grip:SetFrameLevel(f:GetFrameLevel() + 10)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    NS.Store.DB().ui.size = { w = math.floor(f:GetWidth()), h = math.floor(f:GetHeight()) }
    UI.Refresh()
  end)

  tinsert(UISpecialFrames, "KeyGridFrame")  -- Escape closes
  UI.frame = f
  UI.RestorePosition()
  UI.ShowTab(NS.Store.DB().ui.tab or 1)
  return f
end

function UI.RestorePosition()
  local f = UI.frame
  if not f then return end
  local p = NS.Store.GetPoint()
  if p and p.point then
    f:ClearAllPoints()
    f:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
  end
end

function UI.ResetPosition()
  NS.Store.ClearPoint()
  NS.Store.DB().ui.size = nil   -- also drop any manual resize
  if UI.frame then
    UI.frame:ClearAllPoints()
    UI.frame:SetPoint("CENTER")
    UI.Refresh()
  end
end

--------------------------------------------------------------------------------
-- Column header buttons (rebuilt each refresh since dungeon set can change)
--------------------------------------------------------------------------------
local function layoutHeaders(f, cols)
  for _, b in ipairs(f.headerButtons) do b:Hide() end
  for i, col in ipairs(cols) do
    local b = f.headerButtons[i]
    if not b then
      b = CreateFrame("Button", nil, f.header)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      b.text:SetAllPoints()
      f.headerButtons[i] = b
    end
    b:SetSize(col.w, M.COLHDR_H)
    b:ClearAllPoints()
    b:SetPoint("LEFT", f.header, "LEFT", col.x, 0)
    b.text:SetJustifyH(col.align == "LEFT" and "LEFT" or "CENTER")
    b.text:SetText((col.label or "") .. sortArrow(col.id))
    b.col = col
    if col.sortable then
      b:EnableMouse(true)
      b:SetScript("OnClick", function()
        NS.Store.SetSort(col.id)
        UI.Refresh()
      end)
      b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
      b:SetScript("OnLeave", function(self) self.text:SetTextColor(1, 0.82, 0) end)
    else
      b:EnableMouse(false)
      b:SetScript("OnClick", nil)
      b:SetScript("OnEnter", nil)
      b:SetScript("OnLeave", nil)
    end
    b.text:SetTextColor(1, 0.82, 0)
    b:Show()
  end
end

--------------------------------------------------------------------------------
-- Refresh: dispatch to the active tab's panel
--------------------------------------------------------------------------------
function UI.Refresh()
  if not UI.frame or not UI.frame:IsShown() then return end
  local tab = NS.Store.DB().ui.tab or 1
  if tab == 2 and UI.RefreshCores then
    UI.RefreshCores()
  elseif tab == 3 and UI.RefreshLoot then
    UI.RefreshLoot()
  else
    UI.RefreshGrid()
  end
end

function UI.RefreshGrid()
  local f = UI.frame
  if not f then return end
  local cols = UI.BuildColumns()
  layoutHeaders(f, cols)

  f.affixText:SetText(affixText())
  f.subText:SetText(resetText())
  f.footer:SetText(footerText())

  local list = NS.Store.CharList()
  NS.UI.RenderRows(f.content, cols, list)
  if #list == 0 then f.empty:Show() else f.empty:Hide() end

  local width = math.max(360, UI.contentWidth + 26)
  local rowsH = math.max(1, #list) * M.ROW_H
  f.content:SetSize(UI.contentWidth, rowsH)
  local chrome = M.TITLE_H + M.SUBHDR_H + M.COLHDR_H + M.FOOTER_H + M.TABSTRIP_H + 16
  local visibleRowsH = math.min(rowsH, 12 * M.ROW_H)
  UI.SizeFrame(width, chrome + visibleRowsH)
end

function UI.Show()
  UI.EnsureFrame()
  UI.frame:Show()
  if NS.Data then NS.Data.CaptureAll("open") end
  UI.ShowTab(NS.Store.DB().ui.tab or 1)
end

function UI.Hide()
  if UI.frame then UI.frame:Hide() end
end

function UI.Toggle()
  UI.EnsureFrame()
  if UI.frame:IsShown() then UI.Hide() else UI.Show() end
end
