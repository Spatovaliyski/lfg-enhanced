-- Additions inside Blizzard's Browse frame: a hide button on each row and the "Filters"
-- button between Send Message and Group Invite. Nothing is written onto Blizzard's frames;
-- per-row data lives in our own weak-keyed table.
local _, ns = ...

local hideButtons = setmetatable({}, { __mode = "k" }) -- [entry frame] = our hide button
local toggle, badge

------------------------------------------------------------------------------------------------
-- Hide button on rows
------------------------------------------------------------------------------------------------
local function OnEntryEnter(entry)
    local b = hideButtons[entry]
    if b and b.leaderName then
        b:Show()
    end
end

local function OnEntryLeave(entry)
    local b = hideButtons[entry]
    if b and not b:IsMouseOver() then
        b:Hide()
    end
end

local function GetHideButton(entry)
    local b = hideButtons[entry]
    if b then
        return b
    end
    b = CreateFrame("Button", nil, entry)
    b:SetSize(16, 16)
    b:SetPoint("TOPRIGHT", entry, "TOPRIGHT", -8, -6)
    b:SetFrameLevel(entry:GetFrameLevel() + 10)
    b:SetNormalAtlas("common-search-clearbutton")
    b:SetHighlightAtlas("common-search-clearbutton", "ADD")
    b:Hide()
    b:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        local name = self.leaderName
        self:Hide()
        GameTooltip_Hide()
        ns.BlockName(name)
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Hide " .. (self.leaderName or ""), HIGHLIGHT_FONT_COLOR:GetRGB())
        GameTooltip:AddLine("EnhancedLFG keeps this name out of the list. Unhide it from the filter panel.",
            NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip_Hide()
        if not entry:IsMouseOver() then
            self:Hide()
        end
    end)
    entry:HookScript("OnEnter", OnEntryEnter)
    entry:HookScript("OnLeave", OnEntryLeave)
    hideButtons[entry] = b
    return b
end

-- Post-hook of LFGBrowseSearchEntry_Init(entry, elementData, browseFrame): rows are pooled,
-- so every (re)use updates which name the button hides.
local function OnEntryInit(entry)
    local b = GetHideButton(entry)
    local name = nil
    if not ns.InChatLockdown() then
        local info = entry.resultID and C_LFGList.GetSearchResultInfo(entry.resultID)
        if info and not (issecretvalue and (issecretvalue(info.hasSelf) or issecretvalue(info.leaderName))) then
            name = not info.hasSelf and info.leaderName or nil
        end
    end
    b.leaderName = name
    if name and entry:IsMouseOver() then
        b:Show()
    else
        b:Hide()
    end
end

------------------------------------------------------------------------------------------------
-- "Filters" button
------------------------------------------------------------------------------------------------
function ns.UpdateToggle()
    if not toggle then
        return
    end
    local hidden = ns.hidden.players + ns.hidden.groups
    local text = "Filters"
    if ns.paused then
        text = "Filters (paused)"
    elseif hidden > 0 then
        text = ("Filters \194\183 %d hidden"):format(hidden)
    end
    local label = toggle.Label
    label:SetText(text)
    -- Fits between Send Message and Group Invite (196px apart).
    local width = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
    toggle:SetWidth(math.min(180, math.max(96, width + 32)))
    toggle:SetSelected(ns.db.panelShown)
    badge:SetShown(ns.HasResettableFilters())
end

-- Post-hook of LFGBrowseFrame:UpdateResults().
local function OnUpdateResults(frame)
    ns.UpdateToggle()
    if ns.SyncPanel then
        ns.SyncPanel()
    end
    local total = frame.totalResults or 0
    if not frame.searching and not frame.searchFailed and total > 0
        and type(frame.results) == "table" and #frame.results == 0 then
        frame.NoResultsFound:SetText("Everything here is hidden by your filters.")
        frame.NoResultsFound:Show()
    end
end

local function CreateToggle()
    -- Same height as Send Message / Group Invite beside it; gold edge while the panel is open.
    toggle = ns.CreateActionButton(LFGBrowseFrame, "Filters", 96, 28)
    toggle:SetPoint("BOTTOM", LFGBrowseFrame, "BOTTOM", 0, 16)
    toggle:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        ns.SetPanelShown(not ns.db.panelShown)
    end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("EnhancedLFG filters", HIGHLIGHT_FONT_COLOR:GetRGB())
        GameTooltip:AddLine("Click to show or hide the filter panel.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
            NORMAL_FONT_COLOR.b, true)
        if ns.HasResettableFilters() then
            GameTooltip:AddLine("The red X turns every filter off.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
                NORMAL_FONT_COLOR.b, true)
        end
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", GameTooltip_Hide)

    -- The Auction House's red X filter badge: shown while any filter is on, click to reset.
    badge = CreateFrame("Button", nil, toggle)
    badge:SetSize(22, 22)
    badge:SetPoint("CENTER", toggle, "TOPRIGHT", -3, -2)
    badge:SetFrameLevel(toggle:GetFrameLevel() + 2)
    badge:SetNormalAtlas("auctionhouse-ui-filter-redx")
    badge:SetHighlightAtlas("auctionhouse-ui-filter-redx", "ADD")
    badge:GetHighlightTexture():SetAlpha(0.4)
    badge:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        ns.ResetFilters()
    end)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset filters", HIGHLIGHT_FONT_COLOR:GetRGB())
        GameTooltip:AddLine("Your hidden players are kept.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g,
            NORMAL_FONT_COLOR.b, true)
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", GameTooltip_Hide)
    badge:Hide()
end

function ns.InstallRows()
    CreateToggle()
    hooksecurefunc("LFGBrowseSearchEntry_Init", OnEntryInit)
    hooksecurefunc(LFGBrowseFrame, "UpdateResults", OnUpdateResults)
end
