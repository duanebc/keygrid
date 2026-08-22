-- KeyGrid/UI/Settings.lua
-- Settings tab: every option in one place, plus in-game help.
--
-- Controls bind to the DB through get/set closures rather than a flat key name,
-- because KeyGrid's settings are variously nested (ui.minimap.hide), inverted
-- (the box says "show", the DB stores "hide") or keyed by a dynamic character
-- id, and a single key name cannot express any of that.
--
-- Two collections of checkboxes, deliberately kept apart: `statics` are built
-- once and re-read from the DB on every refresh, while character rows are pooled
-- and rebound to a different character each refresh. Mixing them would let the
-- refresh loop stamp a recycled row with whichever character it last held.

local ADDON, NS = ...
NS.UI = NS.UI or {}
local UI = NS.UI
local M = UI.M

local GOLD = { 1, 0.82, 0 }
local ROW_H = 22
local SETTINGS_MIN_W = 470

local statics = {}    -- checkboxes bound to a fixed setting
local charRows = {}   -- pooled rows for the character list

--------------------------------------------------------------------------------
-- Widget factories
--------------------------------------------------------------------------------
local function heading(parent, text, x, y)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetText(text)
  fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  return fs
end

local function body(parent, text, x, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetWidth(width or 420)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  fs:SetTextColor(0.75, 0.75, 0.8)
  return fs
end

-- get() -> boolean, set(boolean).
local function MakeCheck(parent, label, tooltip, x, y, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  cb:SetSize(22, 22)
  local fs = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("LEFT", cb, "RIGHT", 3, 0)
  fs:SetText(label)
  cb.label = fs
  cb.__get = get
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    UI.Refresh()
  end)
  if tooltip then
    cb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(label, GOLD[1], GOLD[2], GOLD[3])
      GameTooltip:AddLine(tooltip, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  statics[#statics + 1] = cb
  return cb
end

local function MakeButton(parent, label, x, y, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 130, 22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

-- A number you type and commit, rather than a slider. A slider over this range
-- moves the whole window on every pixel of drag, which is unusable in practice;
-- typing 110 and pressing Enter is precise and stays still until you ask.
local function MakeNumberField(parent, name, x, y, onCommit)
  local edit = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
  edit:SetSize(48, 20)
  edit:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  edit:SetAutoFocus(false)
  edit:SetNumeric(true)
  edit:SetMaxLetters(3)
  edit:SetJustifyH("CENTER")
  edit:SetScript("OnEnterPressed", function(self) onCommit(self) end)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); UI.RefreshSettings() end)
  return edit
end

--------------------------------------------------------------------------------
-- A selectable box. WoW cannot open a URL and chat links are not clickable, so
-- letting the user copy the text is the only way to hand them a link.
--------------------------------------------------------------------------------
function UI.ShowLinkBox(title, url)
  local box = UI.linkBox
  if not box then
    box = CreateFrame("Frame", "KeyGridLinkBox", UIParent, "BackdropTemplate")
    box:SetSize(430, 118)
    box:SetPoint("CENTER")
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:EnableMouse(true)
    box:SetMovable(true)
    box:RegisterForDrag("LeftButton")
    box:SetScript("OnDragStart", box.StartMoving)
    box:SetScript("OnDragStop", box.StopMovingOrSizing)
    if box.SetBackdrop then
      box:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 },
      })
    end
    box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.title:SetPoint("TOPLEFT", 16, -14)
    box.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

    box.edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    box.edit:SetSize(376, 22)
    box.edit:SetPoint("TOPLEFT", 22, -42)
    box.edit:SetAutoFocus(false)
    box.edit:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
      box:Hide()
    end)

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", box.edit, "BOTTOMLEFT", 0, -8)
    hint:SetText("Ctrl+C to copy, Escape to close.")

    local close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    tinsert(UISpecialFrames, "KeyGridLinkBox")
    UI.linkBox = box
  end
  box.title:SetText(title)
  box.edit:SetText(url)
  box:Show()
  box.edit:SetFocus()
  box.edit:HighlightText()
end

--------------------------------------------------------------------------------
-- Panel construction
--------------------------------------------------------------------------------
function UI.BuildSettingsPanel(f, panel)
  local scroll = CreateFrame("ScrollFrame", "KeyGridSettingsScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -6)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 6)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  f.settingsContent = content

  local X = M.PAD + 4
  local y = -4

  -- Display -------------------------------------------------------------------
  heading(content, "DISPLAY", X, y)
  y = y - 20

  MakeCheck(content, "Show characters with no score",
    "Characters that have never earned a Mythic+ rating are hidden by default. "
      .. "Turn this on to see every character KeyGrid has captured.",
    X, y,
    function() return NS.Store.DB().ui.showAll end,
    function(v) NS.Store.DB().ui.showAll = v end)
  y = y - 30

  local scaleLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  scaleLabel:SetPoint("TOPLEFT", content, "TOPLEFT", X + 2, y - 4)
  scaleLabel:SetText("Window scale")

  local commitScale
  f.settingsScaleEdit = MakeNumberField(content, "KeyGridScaleInput", X + 104, y,
    function(self) commitScale() end)

  local pct = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pct:SetPoint("LEFT", f.settingsScaleEdit, "RIGHT", 4, 0)
  pct:SetText("%")

  commitScale = function()
    local edit = f.settingsScaleEdit
    local want = tonumber(edit:GetText())
    -- An empty or silly value snaps back to what is actually in effect rather
    -- than to some default the user never chose.
    if not want then
      UI.RefreshSettings()
      edit:ClearFocus()
      return
    end
    want = math.max(70, math.min(150, want))
    edit:ClearFocus()
    UI.ApplyScale(want / 100)
    -- Re-read the point from the frame: SetClampedToScreen may have corrected it.
    local fr = UI.frame
    if fr and NS.Store.GetPoint() then
      local p, _, rp, px, py = fr:GetPoint()
      if p then NS.Store.SavePoint(p, rp or p, px, py) end
    end
    UI.RefreshSettings()
    UI.Refresh()
  end

  MakeButton(content, "Set", X + 150, y - 1, 50, commitScale)

  local hint = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", content, "TOPLEFT", X + 208, y - 11)
  hint:SetText("70-150%, Enter or Set to apply")
  y = y - 34

  -- Minimap -------------------------------------------------------------------
  heading(content, "MINIMAP BUTTON", X, y)
  y = y - 20

  MakeCheck(content, "Show the minimap button",
    "Left click opens KeyGrid, right click opens these settings, and you can "
      .. "drag it anywhere around the minimap. /kg works either way.",
    X, y,
    function() return not NS.Store.DB().ui.minimap.hide end,
    function(v) if NS.SetMinimapShown then NS.SetMinimapShown(v) end end)

  MakeCheck(content, "Lock its position",
    "Stops the button being dragged around the minimap by accident.",
    X + 230, y,
    function() return NS.Store.DB().ui.minimap.locked end,
    function(v) if NS.SetMinimapLocked then NS.SetMinimapLocked(v) end end)
  y = y - 34

  -- Characters ----------------------------------------------------------------
  heading(content, "CHARACTERS", X, y)
  y = y - 18
  f.settingsCharNote = body(content, "", X, y, 430)
  y = y - 26
  f.settingsCharTop = y
  f.settingsCharX = X

  -- Help ----------------------------------------------------------------------
  -- Anchored in RefreshSettings, because everything below the character list
  -- moves as characters are added.
  f.settingsHelp = {
    heading = heading(content, "HOW IT WORKS", X, y),
    body = body(content,
      "World of Warcraft only ever exposes the Mythic+ data of the character "
        .. "you are logged in on. There is no way to read an alt's keystone from "
        .. "inside the game.\n\n"
        .. "So KeyGrid snapshots each character as you play it and shows them all "
        .. "together. A character appears here once you have logged into it, and "
        .. "its keystone and vault are as of that moment rather than live.\n\n"
        .. "Ratings reset when a season rolls over, so a character you have not "
        .. "logged into since then reads N/A rather than showing a number it no "
        .. "longer has.",
      X, y, 430),
  }
  local h = f.settingsHelp
  h.reset = MakeButton(content, "Reset window", X, y, 130, function()
    UI.ResetPosition()
    UI.RefreshSettings()
  end)
  h.commands = MakeButton(content, "Show commands", X + 138, y, 130, function()
    if NS.PrintUsage then NS.PrintUsage() end
  end)
  h.help = MakeButton(content, "Get help", X + 276, y, 130, function()
    UI.ShowLinkBox("KeyGrid - report a bug or ask for a feature",
      "https://github.com/duanebc/keygrid/issues")
  end)

  -- OnShow fires even while the parent window is hidden and will not fire again
  -- when it becomes visible, so the panel is also refreshed through kgRefresh.
  panel:SetScript("OnShow", function() UI.RefreshSettings() end)
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------
local function charRow(content, i)
  local row = charRows[i]
  if not row then
    row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_H)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(20, 20)
    row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.name:SetWidth(190)
    row.name:SetJustifyH("LEFT")
    row.note = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.note:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.note:SetWidth(200)
    row.note:SetJustifyH("LEFT")
    charRows[i] = row
  end
  return row
end

function UI.RefreshSettings()
  local f = UI.frame
  if not (f and f.settingsContent) then return end
  local content = f.settingsContent
  local ui = NS.Store.DB().ui

  -- Re-read every fixed control from the DB, so none can go stale.
  for _, cb in ipairs(statics) do
    cb:SetChecked(cb.__get() and true or false)
  end
  if f.settingsScaleEdit and not f.settingsScaleEdit:HasFocus() then
    f.settingsScaleEdit:SetText(tostring(math.floor((ui.scale or 1) * 100 + 0.5)))
  end

  -- Character list. Sourced from every known character rather than
  -- Store.CharList, which filters out exactly the rows you need to un-hide.
  local list = NS.Store.AllChars()
  for _, row in ipairs(charRows) do row:Hide() end

  local top = f.settingsCharTop
  for i, c in ipairs(list) do
    local row = charRow(content, i)
    local key = c._key
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", f.settingsCharX, top - (i - 1) * ROW_H)
    row:SetWidth(430)
    row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.03 or 0.0)

    local r, g, b = UI.ClassColor(c.class)
    row.name:SetText(c.name or key or "?")
    row.name:SetTextColor(r, g, b)
    row.check:SetChecked(not ui.hidden[key])
    row.check:SetScript("OnClick", function(self)
      if self:GetChecked() then
        NS.Store.Unhide(key)
        -- A character with no rating stays invisible behind the zero-score
        -- filter, so ticking it here would otherwise appear to do nothing.
        if (c.peakScore or 0) <= 0 and not NS.Store.DB().ui.showAll then
          NS.Store.DB().ui.showAll = true
          NS.Print(("Also switched on \"show characters with no score\", or %s would stay hidden.")
            :format(c.name or key or "that character"))
        end
      else
        NS.Store.Hide(key)
      end
      UI.RefreshSettings()
      UI.Refresh()
    end)
    if (c.peakScore or 0) <= 0 and not ui.showAll then
      row.note:SetText("no score - needs the option above")
    else
      row.note:SetText("")
    end
    row:Show()
  end

  local n = #list
  f.settingsCharNote:SetText(n == 0
    and "No characters captured yet. Log in on a character to add it."
    or ("Untick a character to hide its row from the grid. %d known."):format(n))

  -- Everything below the list moves with it.
  local afterList = f.settingsCharTop - (n * ROW_H) - 12
  local h = f.settingsHelp
  h.heading:ClearAllPoints()
  h.heading:SetPoint("TOPLEFT", content, "TOPLEFT", f.settingsCharX, afterList)
  h.body:ClearAllPoints()
  h.body:SetPoint("TOPLEFT", content, "TOPLEFT", f.settingsCharX, afterList - 20)
  local afterHelp = afterList - 20 - (h.body:GetStringHeight() or 90) - 14
  for i, btn in ipairs({ h.reset, h.commands, h.help }) do
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", content, "TOPLEFT", f.settingsCharX + (i - 1) * 138, afterHelp)
  end

  content:SetSize(460, math.abs(afterHelp) + 46)

  -- The panel never writes ui.size -- switching tabs must not resize the window
  -- out from under the grid. It only widens the frame if the controls cannot fit.
  if f:GetWidth() < SETTINGS_MIN_W then f:SetWidth(SETTINGS_MIN_W) end
end
