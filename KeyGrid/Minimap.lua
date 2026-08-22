-- KeyGrid/Minimap.lua
-- A self-contained, draggable minimap button. No libraries: LibDBIcon would drag
-- in LibStub and LibDataBroker with it, and "no Ace3, no LibStub" is a promise
-- the README and the CurseForge page both make.
--
-- The position is stored as an angle in degrees around the minimap, which is
-- resolution- and scale-independent -- unlike a saved x/y, which lands somewhere
-- else entirely the first time the minimap is resized.

local ADDON, NS = ...

local button
local ICON = "Interface\\AddOns\\KeyGrid\\Media\\KeyGridIcon"

-- math.atan2 is still present in WoW's Lua 5.1, but it is gone in 5.3+ and this
-- file is also loaded by the headless test harness.
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function db()
  if type(KeyGridDB) ~= "table" or not KeyGridDB.ui then return nil end
  return KeyGridDB.ui.minimap
end

--------------------------------------------------------------------------------
-- Where the button sits.
--
-- Pure function so the maths can be tested without a client. Square minimaps
-- (ElvUI and friends) need the offset clamped to the edge of the square rather
-- than a circle, or the button floats in dead space at the corners.
--------------------------------------------------------------------------------
function NS.MinimapOffset(angleDeg, radius, shape)
  local a = math.rad(angleDeg or 200)
  local x, y = math.cos(a) * radius, math.sin(a) * radius
  if shape and shape:upper():find("SQUARE", 1, true) then
    local edge = radius * math.sqrt(2)
    x = math.max(-edge, math.min(edge, x * math.sqrt(2)))
    y = math.max(-edge, math.min(edge, y * math.sqrt(2)))
    x = math.max(-radius, math.min(radius, x))
    y = math.max(-radius, math.min(radius, y))
  end
  return x, y
end

local function minimapShape()
  if type(GetMinimapShape) ~= "function" then return nil end
  local ok, shape = pcall(GetMinimapShape)
  return ok and shape or nil
end

local function UpdatePosition()
  local opts = db()
  if not (button and opts and Minimap) then return end
  -- A button collector (ElvUI's minimap bar, MinimapButtonBag) reparents the
  -- button; re-anchoring it to Minimap every event would rip it back out.
  if button:GetParent() ~= Minimap then return end
  local w = Minimap:GetWidth()
  if not w or w < 10 then w = 140 end   -- not laid out yet at PLAYER_LOGIN
  local x, y = NS.MinimapOffset(opts.angle, (w / 2) + 5, minimapShape())
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function DragUpdate()
  local opts = db()
  if not (opts and Minimap) then return end
  local mx, my = Minimap:GetCenter()
  if not mx then return end
  local scale = Minimap:GetEffectiveScale()
  if not scale or scale <= 0 then scale = 1 end
  local cx, cy = GetCursorPosition()
  opts.angle = math.deg(atan2((cy / scale) - my, (cx / scale) - mx))
  UpdatePosition()
end

local function applyDragEnabled()
  local opts = db()
  if not button then return end
  if opts and opts.locked then
    button:RegisterForDrag()
  else
    button:RegisterForDrag("LeftButton")
  end
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------
local function BuildButton()
  if button then return button end
  -- Some minimalist UIs remove the minimap outright.
  if not (Minimap and Minimap.GetWidth) then return nil end

  -- Named, so button collectors can find it at all.
  button = CreateFrame("Button", "KeyGridMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -6)
  icon:SetTexture(ICON)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", DragUpdate) end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "RightButton" then
      NS.UI.Show()
      NS.UI.ShowTab("settings")
    else
      NS.UI.Toggle()
    end
  end)

  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("KeyGrid", 1, 0.82, 0)
    GameTooltip:AddLine("Left click to open the grid.", 1, 1, 1)
    GameTooltip:AddLine("Right click for settings.", 1, 1, 1)
    local opts = db()
    if opts and opts.locked then
      GameTooltip:AddLine("Position locked.", 0.7, 0.7, 0.7)
    else
      GameTooltip:AddLine("Drag to move it around the minimap.", 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  applyDragEnabled()
  UpdatePosition()
  return button
end

--------------------------------------------------------------------------------
-- Public control, called from the Settings tab and /kg minimap
--------------------------------------------------------------------------------
function NS.SetMinimapShown(shown)
  local opts = db()
  if not opts then return end
  opts.hide = not shown
  if shown then
    BuildButton()
    if button then
      UpdatePosition()
      button:Show()
    end
  elseif button then
    button:Hide()
  end
end

function NS.SetMinimapLocked(locked)
  local opts = db()
  if not opts then return end
  opts.locked = locked and true or false
  if button then
    button:SetScript("OnUpdate", nil)   -- stop any drag already in flight
    applyDragEnabled()
  end
end

function NS.MinimapShown()
  local opts = db()
  return opts and not opts.hide
end

--------------------------------------------------------------------------------
-- Wiring. PLAYER_LOGIN is strictly after ADDON_LOADED, so Store.Init has already
-- populated KeyGridDB by the time we read it.
--------------------------------------------------------------------------------
NS.On("PLAYER_LOGIN", function()
  local opts = db()
  if opts and opts.hide then return end
  BuildButton()
end)

-- The minimap can be resized or rescaled well after login, by the game or by
-- another addon, which moves where the ring actually is.
local function reposition() UpdatePosition() end
NS.On("PLAYER_ENTERING_WORLD", reposition)
NS.On("DISPLAY_SIZE_CHANGED", reposition)
NS.On("UI_SCALE_CHANGED", reposition)
