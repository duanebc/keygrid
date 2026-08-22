-- KeyGrid/UI/Tabs.lua
-- Bottom tab strip. Pattern per Blizzard's CharacterFrameTabTemplate +
-- PanelTemplates_* (tab buttons must be named "<frameName>TabN").
--
-- CreateTabs takes { {id=, name=, disabled=, reason=}, ... }. Tabs are addressed
-- by their string id, never by index: the strip gains a Loot tab in a developer
-- checkout and loses it in a release, so index 3 means different things in
-- different builds. The saved tab is an id for the same reason.
--
-- A disabled tab stays in the strip, greyed and unclickable, and says why on
-- hover -- PanelTemplates_* honours tab.isDisabled, so selecting another tab
-- never re-enables it.

local ADDON, NS = ...
NS.UI = NS.UI or {}
local UI = NS.UI

local function disableTab(f, tab, i)
  tab.isDisabled = 1
  if PanelTemplates_DisableTab then pcall(PanelTemplates_DisableTab, f, i) end
  tab:Disable()
  -- Disabled buttons drop mouse events unless motion scripts are kept alive,
  -- and the hover tooltip is the only place the reason can be shown.
  if tab.SetMotionScriptsWhileDisabled then tab:SetMotionScriptsWhileDisabled(true) end
  tab:SetScript("OnEnter", function(self)
    if not self.kgReason then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self:GetText(), 1, 1, 1)
    GameTooltip:AddLine(self.kgReason, 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.CreateTabs(f, tabs)
  f.Tabs = {}
  f.tabDefs = tabs
  UI.tabIndex = {}
  for i, def in ipairs(tabs) do
    UI.tabIndex[def.id] = i
    local tab = CreateFrame("Button", "KeyGridFrameTab" .. i, f, "CharacterFrameTabTemplate")
    tab:SetID(i)
    tab:SetText(def.name)
    if i == 1 then
      tab:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 6)
    else
      tab:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", -14, 0)
    end
    tab:SetScript("OnClick", function(self) UI.ShowTab(self:GetID()) end)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
    f.Tabs[i] = tab
  end
  if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(f, #tabs) end
  if PanelTemplates_SetTab then PanelTemplates_SetTab(f, 1) end
  -- After SetTab, so PanelTemplates_UpdateTabs can't undo the greying.
  for i, def in ipairs(tabs) do
    if def.disabled then
      f.Tabs[i].kgReason = def.reason
      disableTab(f, f.Tabs[i], i)
    end
  end
  -- The strip is laid out left to right and never wraps, so with four tabs it,
  -- not the columns, sets how narrow the window may get. Measured next frame:
  -- PanelTemplates_TabResize runs in a pcall above and widths settle after it.
  NS.After(0, function() UI.MeasureTabStrip(f) end)
end

-- Narrowest the window can be without the tab strip spilling past its edge.
UI.minWidth = 360

function UI.MeasureTabStrip(f)
  local last = f and f.Tabs and f.Tabs[#f.Tabs]
  if not (last and last.GetRight and f.GetLeft) then return end
  local right, left = last:GetRight(), f:GetLeft()
  if not (right and left) then return end
  UI.minWidth = math.max(360, math.ceil(right - left) + 12)
  if f.SetResizeBounds then pcall(f.SetResizeBounds, f, UI.minWidth, 180) end
end

function UI.TabIndex(id)
  if type(id) == "number" then return id end
  return UI.tabIndex and UI.tabIndex[id]
end

function UI.CurrentTabIndex()
  return UI.TabIndex(NS.Store.DB().ui.tabId or "grid") or 1
end

function UI.ActiveTabId()
  local f = UI.frame
  if not (f and f.tabDefs) then return NS.Store.DB().ui.tabId or "grid" end
  local def = f.tabDefs[UI.CurrentTabIndex()]
  return def and def.id or "grid"
end

function UI.TabDisabled(n)
  local f = UI.frame
  local tab = f and f.Tabs and f.Tabs[UI.TabIndex(n)]
  return tab and tab.isDisabled and true or false
end

-- Accepts an id ("settings") or an index. Falls back to the grid for a tab that
-- doesn't exist in this build or has been switched off since it was saved.
function UI.ShowTab(which)
  local f = UI.frame
  if not f then return end
  local n = UI.TabIndex(which or "grid")
  if not n or not f.panels[n] or UI.TabDisabled(n) then n = 1 end

  if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, f, n) end
  for i, panel in ipairs(f.panels) do
    if i == n then panel:Show() else panel:Hide() end
  end
  local def = f.tabDefs and f.tabDefs[n]
  NS.Store.DB().ui.tabId = (def and def.id) or "grid"
  UI.Refresh()
end
