-- KeyGrid/UI/LootGrid.lua
-- Loot tab (Tab 3): rows = characters, columns = dungeons. Each cell lists the
-- seasonal loot for that character's selected spec, minus what they've looted.
-- Per-row spec toggle + a slot filter bar across the top.

local ADDON, NS = ...
NS.UI = NS.UI or {}
local UI = NS.UI
local M = UI.M

local LOOT_CHAR_W   = 124
local LOOT_DUN_W    = 150
local ROW_MIN       = 40
local LOOT_FOOTER_H = 56
local SLOTBAR_H     = 22

-- Slot filters (equipLoc strings from GetItemInfoInstant).
local SLOTS = {
  { key = "all",      label = "All" },
  { key = "head",     label = "Head",     loc = { INVTYPE_HEAD = true } },
  { key = "neck",     label = "Neck",     loc = { INVTYPE_NECK = true } },
  { key = "shoulder", label = "Shoulder", loc = { INVTYPE_SHOULDER = true } },
  { key = "back",     label = "Back",     loc = { INVTYPE_CLOAK = true } },
  { key = "chest",    label = "Chest",    loc = { INVTYPE_CHEST = true, INVTYPE_ROBE = true } },
  { key = "wrist",    label = "Wrist",    loc = { INVTYPE_WRIST = true } },
  { key = "hands",    label = "Hands",    loc = { INVTYPE_HAND = true } },
  { key = "waist",    label = "Waist",    loc = { INVTYPE_WAIST = true } },
  { key = "legs",     label = "Legs",     loc = { INVTYPE_LEGS = true } },
  { key = "feet",     label = "Feet",     loc = { INVTYPE_FEET = true } },
  { key = "finger",   label = "Ring",     loc = { INVTYPE_FINGER = true } },
  { key = "trinket",  label = "Trinket",  loc = { INVTYPE_TRINKET = true } },
  { key = "weapon",   label = "Weapon",   loc = {
      INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
      INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
      INVTYPE_HOLDABLE = true, INVTYPE_SHIELD = true } },
}
local slotByKey = {}
for _, s in ipairs(SLOTS) do slotByKey[s.key] = s end

local function itemEquipLoc(itemID)
  if C_Item and C_Item.GetItemInfoInstant then return select(4, C_Item.GetItemInfoInstant(itemID)) end
  if GetItemInfoInstant then return select(4, GetItemInfoInstant(itemID)) end
end

local function matchSlot(itemID, slotKey)
  if not slotKey or slotKey == "all" then return true end
  local def = slotByKey[slotKey]
  if not def or not def.loc then return true end
  local loc = itemEquipLoc(itemID)
  return (loc and def.loc[loc]) and true or false
end

-- Shorten a name to fit the column on one line (avoids word-wrap). Truncating
-- long names with "..." is intentional.
local function truncName(s, colW)
  if not s then return s end
  local maxc = math.max(6, math.floor((colW - 8) / 6.2))
  if #s > maxc then return s:sub(1, maxc - 3) .. "..." end
  return s
end

local function lootColumns()
  local cols = {}
  local x = M.PAD
  cols[#cols + 1] = { id = "name", label = "Character", w = LOOT_CHAR_W, x = x }
  x = x + LOOT_CHAR_W
  for _, dc in ipairs(NS.Dungeons.Columns()) do
    cols[#cols + 1] = { mapID = dc.mapID, label = dc.abbr, w = LOOT_DUN_W, x = x }
    x = x + LOOT_DUN_W
  end
  UI.lootWidth = x + M.PAD
  return cols
end

function UI.SpecLabel(classID, specID)
  if not classID then return "—" end
  if specID and GetSpecializationInfoByID then
    local _, name = GetSpecializationInfoByID(specID)
    if name then return name .. "  v" end
  end
  return "pick spec  v"
end

function UI.CycleLootSpec(c)
  local classID = c.classId
  if not classID or not (GetNumSpecializationsForClassID and GetSpecializationInfoForClassID) then return end
  local n = GetNumSpecializationsForClassID(classID) or 0
  if n == 0 then return end
  local cur = NS.Store.DB().ui.lootSpec[c._key] or c.specId
  local idx = 1
  for i = 1, n do
    if GetSpecializationInfoForClassID(classID, i) == cur then idx = i; break end
  end
  local nextSid = GetSpecializationInfoForClassID(classID, (idx % n) + 1)
  NS.Store.DB().ui.lootSpec[c._key] = nextSid
  UI.RefreshLoot()
end

function UI.SetLootSlot(key)
  NS.Store.DB().ui.lootSlot = key
  UI.RefreshLoot()
end

function UI.RefreshSlotBar(f)
  local cur = NS.Store.DB().ui.lootSlot or "all"
  for _, b in ipairs(f.lootSlotButtons or {}) do
    if b.slotKey == cur then
      b.text:SetTextColor(1, 0.82, 0); b.hl:Show()
    else
      b.text:SetTextColor(0.6, 0.6, 0.6); b.hl:Hide()
    end
  end
end

function UI.BuildLootPanel(f, panel)
  -- Slot filter bar
  f.lootSlotBar = CreateFrame("Frame", nil, panel)
  f.lootSlotBar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -2)
  f.lootSlotBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -2)
  f.lootSlotBar:SetHeight(SLOTBAR_H)
  f.lootSlotButtons = {}
  local x = M.PAD
  for i, s in ipairs(SLOTS) do
    local b = CreateFrame("Button", nil, f.lootSlotBar)
    local hl = b:CreateTexture(nil, "BACKGROUND"); hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.18); hl:Hide(); b.hl = hl
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(s.label)
    local w = math.max(26, (b.text:GetStringWidth() or 20) + 12)
    b:SetSize(w, SLOTBAR_H - 4)
    b:SetPoint("LEFT", f.lootSlotBar, "LEFT", x, 0)
    x = x + w + 4
    b.slotKey = s.key
    b:SetScript("OnClick", function() UI.SetLootSlot(s.key) end)
    b:SetScript("OnEnter", function(self)
      if NS.Store.DB().ui.lootSlot ~= self.slotKey then self.text:SetTextColor(1, 1, 1) end
    end)
    b:SetScript("OnLeave", function() UI.RefreshSlotBar(f) end)
    f.lootSlotButtons[i] = b
  end

  -- Column header (below the slot bar)
  f.lootHeader = CreateFrame("Frame", nil, panel)
  f.lootHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(SLOTBAR_H + 4))
  f.lootHeader:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(SLOTBAR_H + 4))
  f.lootHeader:SetHeight(M.COLHDR_H)
  local hbg = f.lootHeader:CreateTexture(nil, "BACKGROUND")
  hbg:SetAllPoints(); hbg:SetColorTexture(0.10, 0.11, 0.14, 1)
  f.lootHeaderLabels = {}

  local scroll = CreateFrame("ScrollFrame", "KeyGridLootScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f.lootHeader, "BOTTOMLEFT", 0, -2)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, LOOT_FOOTER_H + 4)
  f.lootScroll = scroll
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  f.lootContent = content

  f.lootFooter = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  UI.ScaleFont(f.lootFooter, 1.5)
  f.lootFooter:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", M.PAD + 12, 20)
  f.lootFooter:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(M.PAD + 12), 20)
  f.lootFooter:SetJustifyH("LEFT")
  f.lootFooter:SetWordWrap(false)

  f.lootEmpty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  f.lootEmpty:SetPoint("TOP", content, "TOP", 0, -20)
  f.lootEmpty:SetText("No characters yet.\nLog in on a character, then run /kg lootdump if cells stay blank.")
  f.lootEmpty:Hide()
end

local function layoutLootHeader(f, cols)
  for _, fs in ipairs(f.lootHeaderLabels) do fs:Hide() end
  for i, col in ipairs(cols) do
    local fs = f.lootHeaderLabels[i]
    if not fs then
      fs = f.lootHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      f.lootHeaderLabels[i] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", f.lootHeader, "LEFT", col.x, 0)
    fs:SetWidth(col.w)
    fs:SetJustifyH(col.id == "name" and "LEFT" or "CENTER")
    fs:SetText(col.label); fs:SetTextColor(1, 0.82, 0)
    fs:Show()
  end
end

local function lootRow(i, content)
  UI.lootRows = UI.lootRows or {}
  local row = UI.lootRows[i]
  if not row then
    row = CreateFrame("Frame", nil, content)
    row.cells = {}
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.spec = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    UI.lootRows[i] = row
  end
  return row
end

function UI.RefreshLoot()
  local f = UI.frame
  if not f or not f.lootContent then return end
  UI.RefreshSlotBar(f)
  local cols = lootColumns()
  layoutLootHeader(f, cols)

  local slotKey = NS.Store.DB().ui.lootSlot or "all"
  local hideOwned = NS.Store.DB().ui.lootHideCollected
  local list = NS.Store.CharList()
  UI.lootRows = UI.lootRows or {}
  for _, r in ipairs(UI.lootRows) do r:Hide() end

  local usedVoidcache = false
  local y = 0
  for i, c in ipairs(list) do
    local row = lootRow(i, f.lootContent)
    local selSpec = NS.Store.DB().ui.lootSpec[c._key] or c.specId

    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", cols[1].x, -2)
    row.name:SetWidth(LOOT_CHAR_W - 4); row.name:SetJustifyH("LEFT")
    local cr, cg, cb = UI.ClassColor(c.class)
    row.name:SetText(c.name or c._key or "?"); row.name:SetTextColor(cr, cg, cb)

    row.spec:ClearAllPoints()
    row.spec:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.spec:SetSize(LOOT_CHAR_W - 8, 20)
    row.spec:SetText(UI.SpecLabel(c.classId, selSpec))
    row.spec:SetEnabled(c.classId ~= nil)
    row.spec:SetScript("OnClick", function() UI.CycleLootSpec(c) end)

    local maxH = ROW_MIN
    for ci = 2, #cols do
      local col = cols[ci]
      local cell = row.cells[ci]
      if not cell then
        cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        local cf, cs, cfl = cell:GetFont()
        cell:SetFont(cf or STANDARD_TEXT_FONT, (cs or 10) + 1, cfl)  -- +1 for readability
        row.cells[ci] = cell
      end
      cell:ClearAllPoints()
      cell:SetPoint("TOPLEFT", row, "TOPLEFT", col.x, -2)
      cell:SetWidth(col.w - 4); cell:SetJustifyH("LEFT"); cell:SetSpacing(1)
      cell:Show()

      local text
      local vc = c.voidcache and c.voidcache[col.mapID]
      if vc then
        -- Exact remaining pool read from the in-game Voidcache (ground truth).
        usedVoidcache = true
        if #vc == 0 then
          text = "|cff557755(all done)|r"
        else
          local vlines = {}
          for _, nm in ipairs(vc) do vlines[#vlines + 1] = truncName(nm, col.w) end
          text = table.concat(vlines, "\n")
        end
      elseif not c.classId then
        text = "|cff777777log in|r"
      else
        local items = NS.Loot and NS.Loot.ItemsFor(col.mapID, c.classId, selSpec)
        if not items then
          text = "|cff777777—|r"
        else
          local owned = c.obtained
          local lines = {}
          for _, it in ipairs(items) do
            if matchSlot(it.itemID, slotKey)
               and not (hideOwned and owned and owned[it.itemID]) then
              local nm = it.name
              if not nm and C_Item and C_Item.GetItemInfo then nm = C_Item.GetItemInfo(it.itemID) end
              if not nm then
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(it.itemID) end
                nm = "..."
              end
              lines[#lines + 1] = truncName(nm, col.w)
            end
          end
          if #lines == 0 then
            text = "|cff777777—|r"
          else
            text = table.concat(lines, "\n")
          end
        end
      end
      cell:SetText(text); cell:SetTextColor(0.85, 0.85, 0.9)
      local h = (cell:GetStringHeight() or 0) + 4
      if h > maxH then maxH = h end
    end
    for ci = #cols + 1, #row.cells do if row.cells[ci] then row.cells[ci]:Hide() end end

    local rowH = math.max(ROW_MIN, maxH + 6)
    row:SetHeight(rowH)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT",  f.lootContent, "TOPLEFT",  0, -y)
    row:SetPoint("TOPRIGHT", f.lootContent, "TOPRIGHT", 0, -y)
    row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.0)
    row:Show()
    y = y + rowH
  end

  if #list == 0 then f.lootEmpty:Show() else f.lootEmpty:Hide() end
  f.lootContent:SetSize(UI.lootWidth or 600, math.max(1, y))

  local slotLabel = slotByKey[slotKey] and slotByKey[slotKey].label or "All"
  if usedVoidcache then
    f.lootFooter:SetText(("Slot: %s  ·  live Voidcache pool = exact remaining (auto-read from bags)  ·  click a spec to switch"):format(slotLabel))
  else
    local mode = hideOwned and "hiding items you've looted" or "showing all"
    f.lootFooter:SetText(("Slot: %s  ·  %s  ·  /kg lootall = show everything  ·  click a spec to switch"):format(slotLabel, mode))
  end

  local width = math.max(420, (UI.lootWidth or 600) + 26)
  local chrome = M.TITLE_H + SLOTBAR_H + M.COLHDR_H + LOOT_FOOTER_H + M.TABSTRIP_H + 22
  local visibleH = math.min(math.max(1, y), 14 * M.ROW_H)
  UI.SizeFrame(width, chrome + visibleH)
end
