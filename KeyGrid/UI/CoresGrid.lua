-- KeyGrid/UI/CoresGrid.lua
-- Void Cores tab (Tab 2): per-character Collected / On hand / Spent / Left / weekly.

local ADDON, NS = ...
NS.UI = NS.UI or {}
local UI = NS.UI
local M = UI.M

local function coresColumns()
  local cols = {}
  local x = M.PAD
  local function add(id, label, w, align)
    cols[#cols + 1] = { id = id, label = label, w = w, align = align or "CENTER", x = x }
    x = x + w
  end
  add("name",      "Character", M.COL_CHAR, "LEFT")
  add("collected", "Collected", 78)
  add("have",      "On hand",   70)
  add("spent",     "Spent",     64)
  add("left",      "Left",      64)
  add("weekly",    "This wk",   70)
  UI.coresWidth = x + M.PAD
  return cols
end

function UI.BuildCoresPanel(f, panel)
  local cols = coresColumns()

  f.coresHeader = CreateFrame("Frame", nil, panel)
  f.coresHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
  f.coresHeader:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -4)
  f.coresHeader:SetHeight(M.COLHDR_H)
  local hbg = f.coresHeader:CreateTexture(nil, "BACKGROUND")
  hbg:SetAllPoints(); hbg:SetColorTexture(0.10, 0.11, 0.14, 1)
  for _, col in ipairs(cols) do
    local fs = f.coresHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("LEFT", f.coresHeader, "LEFT", col.x, 0)
    fs:SetWidth(col.w)
    fs:SetJustifyH(col.align == "LEFT" and "LEFT" or "CENTER")
    fs:SetText(col.label); fs:SetTextColor(1, 0.82, 0)
  end

  local scroll = CreateFrame("ScrollFrame", "KeyGridCoresScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f.coresHeader, "BOTTOMLEFT", 0, -2)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, M.FOOTER_H + 2)
  f.coresScroll = scroll
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  f.coresContent = content

  f.coresFooter = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  UI.ScaleFont(f.coresFooter, 1.5)
  f.coresFooter:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", M.PAD + 8, 12)
  f.coresFooter:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(M.PAD + 8), 12)
  f.coresFooter:SetJustifyH("LEFT")
  f.coresFooter:SetWordWrap(false)

  f.coresEmpty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  f.coresEmpty:SetPoint("TOP", content, "TOP", 0, -20)
  f.coresEmpty:SetText("No Void Cores captured yet.\nLog in on a character; run /kg curdump if numbers stay blank.")
  f.coresEmpty:Hide()
end

local function coresRow(i, content)
  UI.coresRows = UI.coresRows or {}
  local row = UI.coresRows[i]
  if not row then
    row = CreateFrame("Frame", nil, content)
    row.cells = {}
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    UI.coresRows[i] = row
  end
  return row
end

function UI.RefreshCores()
  local f = UI.frame
  if not f or not f.coresContent then return end
  local cols = coresColumns()
  local list = NS.Store.CharList()

  UI.coresRows = UI.coresRows or {}
  for _, r in ipairs(UI.coresRows) do r:Hide() end

  for i, c in ipairs(list) do
    local row = coresRow(i, f.coresContent)
    row:SetHeight(M.ROW_H)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT",  f.coresContent, "TOPLEFT",  0, -(i - 1) * M.ROW_H)
    row:SetPoint("TOPRIGHT", f.coresContent, "TOPRIGHT", 0, -(i - 1) * M.ROW_H)
    row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.0)

    local cn = c.cores
    for ci, col in ipairs(cols) do
      local cell = row.cells[ci]
      if not cell then
        cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.cells[ci] = cell
      end
      cell:ClearAllPoints()
      cell:SetPoint("LEFT", row, "LEFT", col.x, 0)
      cell:SetWidth(col.w)
      cell:SetJustifyH(col.align == "LEFT" and "LEFT" or "CENTER")
      cell:Show()

      if col.id == "name" then
        local r, g, b = UI.ClassColor(c.class)
        cell:SetText(c.name or c._key or "?"); cell:SetTextColor(r, g, b)
      elseif not cn then
        cell:SetText(col.id == "collected" and "|cff888888log in|r" or "—")
        cell:SetTextColor(0.5, 0.5, 0.5)
      elseif col.id == "weekly" then
        cell:SetText(("%d/%d"):format(cn.weekly or 0, cn.weeklyCap or 0))
        cell:SetTextColor(0.8, 0.85, 0.9)
      else
        local val = 0
        if col.id == "collected" then val = cn.collected or 0
        elseif col.id == "have" then val = cn.have or 0
        elseif col.id == "spent" then val = cn.spent or 0
        elseif col.id == "left" then
          val = (cn.cap and cn.cap > 0) and math.max(0, cn.cap - (cn.collected or 0)) or 0
        end
        cell:SetText(tostring(val)); cell:SetTextColor(0.9, 0.9, 0.95)
      end
    end
    for ci = #cols + 1, #row.cells do row.cells[ci]:Hide() end
    row:Show()
  end

  if #list == 0 then f.coresEmpty:Show() else f.coresEmpty:Hide() end

  local id = NS.Currencies and NS.Currencies.ResolveVoidCores and NS.Currencies.ResolveVoidCores()
  if id then
    f.coresFooter:SetText(("Void Cores (id %d) · Left = season cap − collected · This wk = earned/cap"):format(id))
  else
    f.coresFooter:SetText("Void Cores id not found — run /kg curdump, then paste it into Currencies.lua")
  end

  local width = math.max(360, (UI.coresWidth or 500) + 26)
  local rowsH = math.max(1, #list) * M.ROW_H
  f.coresContent:SetSize(UI.coresWidth or 500, rowsH)
  local chrome = M.TITLE_H + M.COLHDR_H + M.FOOTER_H + M.TABSTRIP_H + 20
  local visibleRowsH = math.min(rowsH, 12 * M.ROW_H)
  UI.SizeFrame(width, chrome + visibleRowsH)
end
