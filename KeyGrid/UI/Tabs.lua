-- KeyGrid/UI/Tabs.lua
-- Bottom tab strip. Pattern per Blizzard's CharacterFrameTabTemplate +
-- PanelTemplates_* (tab buttons must be named "<frameName>TabN").

local ADDON, NS = ...
NS.UI = NS.UI or {}
local UI = NS.UI

function UI.CreateTabs(f, names)
  f.Tabs = {}
  for i, name in ipairs(names) do
    local tab = CreateFrame("Button", "KeyGridFrameTab" .. i, f, "CharacterFrameTabTemplate")
    tab:SetID(i)
    tab:SetText(name)
    if i == 1 then
      tab:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 6)
    else
      tab:SetPoint("LEFT", f.Tabs[i - 1], "RIGHT", -14, 0)
    end
    tab:SetScript("OnClick", function(self) UI.ShowTab(self:GetID()) end)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
    f.Tabs[i] = tab
  end
  if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(f, #names) end
  if PanelTemplates_SetTab then PanelTemplates_SetTab(f, 1) end
end

function UI.ShowTab(n)
  local f = UI.frame
  if not f then return end
  n = n or 1
  if not f.panels[n] then n = 1 end

  if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, f, n) end
  for i, panel in ipairs(f.panels) do
    if i == n then panel:Show() else panel:Hide() end
  end
  NS.Store.DB().ui.tab = n
  UI.Refresh()
end
