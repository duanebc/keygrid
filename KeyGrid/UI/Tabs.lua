-- KeyGrid/UI/Tabs.lua
-- Bottom tab strip. Pattern per Blizzard's CharacterFrameTabTemplate +
-- PanelTemplates_* (tab buttons must be named "<frameName>TabN").
--
-- CreateTabs takes { {name=, disabled=, reason=}, ... }. A disabled tab stays in
-- the strip, greyed and unclickable, and says why on hover -- PanelTemplates_*
-- honours tab.isDisabled, so selecting another tab never re-enables it.

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
  for i, def in ipairs(tabs) do
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
end

function UI.TabDisabled(n)
  local f = UI.frame
  local tab = f and f.Tabs and f.Tabs[n]
  return tab and tab.isDisabled and true or false
end

function UI.ShowTab(n)
  local f = UI.frame
  if not f then return end
  n = n or 1
  -- Fall back to the grid for a tab that no longer exists (a released build
  -- reading a dev SavedVariables) or one that's been switched off since.
  if not f.panels[n] or UI.TabDisabled(n) then n = 1 end

  if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, f, n) end
  for i, panel in ipairs(f.panels) do
    if i == n then panel:Show() else panel:Hide() end
  end
  NS.Store.DB().ui.tab = n
  UI.Refresh()
end
