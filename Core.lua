-- LFGEnhanced: filters for WoW Forever's Looking For Group browse list.
--
-- Blizzard's list lives in Blizzard_GroupFinder_VanillaStyle (load-on-demand). Its
-- LFGBrowseMixin:UpdateResultList() fetches the results, sorts them with the global
-- LFGBrowseUtil_SortSearchResults(results) and builds the list from that same table.
-- Filter.lua post-hooks the sort and drops filtered entries from the table in place.
--
-- Taint rules for this addon:
--  * Never call Blizzard's dropdown, CVar or search functions (C_LFGList.Search is restricted;
--    a dropdown rebuilt from addon code would later make Blizzard's own search get blocked).
--  * Never write fields onto Blizzard frames; keep per-frame data in our own tables.
--  * The only Blizzard function we call is LFGBrowseFrame:UpdateResultList() to redraw the list
--    after a filter change. That path only reaches unrestricted calls (whisper, InviteUnit).
local ADDON, ns = ...

ns.BLIZZARD_LFG = "Blizzard_GroupFinder_VanillaStyle"

-- Every filter starts "off", so the list looks exactly like Blizzard's until you change something.
ns.DEFAULTS = {
    version = 1,
    show = "all",                 -- "all" | "players" | "groups"
    hideDelisted = false,
    roleMode = "manual",          -- "manual" | "auto"
    roles = { tank = true, healer = true, dps = true },
    levelMode = "off",            -- "off" | "range" | "near"
    levelMin = 0,                 -- 0 = no bound
    levelMax = 0,
    levelNear = 3,
    hiddenClasses = {},           -- [classFile] = true
    groupsNeedMyRole = false,
    playstyles = { [1] = true, [2] = true, [3] = true, [4] = true },
    newPlayerFriendly = "any",    -- "any" | "only"
    discord = "any",              -- "any" | "only" | "hide"
    blocked = {},                 -- [leaderName] = time hidden
    panelShown = true,
}

-- Settings that "Reset filters" keeps.
local KEEP_ON_RESET = { blocked = true, panelShown = true, version = true }

local function ApplyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            -- Only fill keys for "shape" tables (roles, playstyles); free-form maps start empty.
            if next(v) ~= nil then
                ApplyDefaults(dst[k], v)
            end
        elseif dst[k] == nil or type(dst[k]) ~= type(v) then
            dst[k] = v
        end
    end
end

function ns.Print(msg)
    print("|cff33ff99LFGEnhanced|r: " .. msg)
end

------------------------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------------------------
local refreshPending = false

local function DoRefresh()
    refreshPending = false
    local browse = LFGBrowseFrame
    if browse and browse:IsVisible() and not browse.searching then
        browse:UpdateResultList()
    end
end

-- Coalesces any number of changes in one frame into a single redraw.
function ns.Refresh()
    if not refreshPending then
        refreshPending = true
        C_Timer.After(0, DoRefresh)
    end
end

-- Called after any change the user makes in the panel or on a row.
function ns.OnSettingsChanged()
    if ns.SyncPanel then
        ns.SyncPanel()
    end
    if ns.UpdateToggle then
        ns.UpdateToggle()
    end
    ns.Refresh()
end

function ns.ResetFilters()
    local db = ns.db
    for k in pairs(db) do
        if not KEEP_ON_RESET[k] then
            db[k] = nil
        end
    end
    ApplyDefaults(db, ns.DEFAULTS)
    ns.OnSettingsChanged()
end

function ns.BlockName(name)
    if not name or name == "" then
        return
    end
    ns.db.blocked[name] = time()
    ns.Print(("Hid %s. Unhide them from the filter panel."):format(name))
    ns.OnSettingsChanged()
end

function ns.UnblockName(name)
    ns.db.blocked[name] = nil
    ns.OnSettingsChanged()
end

function ns.ClearBlocked()
    wipe(ns.db.blocked)
    ns.OnSettingsChanged()
end

function ns.SetPanelShown(shown)
    ns.db.panelShown = shown and true or false
    if ns.ApplyPanelShown then
        ns.ApplyPanelShown()
    end
    if ns.UpdateToggle then
        ns.UpdateToggle()
    end
end

------------------------------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------------------------------
local function OnBlizzardLFGLoaded()
    if ns.blizzardReady then
        return
    end
    ns.blizzardReady = true
    ns.InstallFilterHook()
    ns.InstallRows()
    ns.CreatePanel()
    ns.OnSettingsChanged()
end

-- Things that change what Auto roles, "near my level" or "spot for my role" mean.
local REFRESH_EVENTS = {
    "GROUP_ROSTER_UPDATE",
    "PLAYER_ROLES_ASSIGNED",
    "LFG_LIST_ACTIVE_ENTRY_UPDATE",
    "LFG_LIST_ROLE_UPDATE",
    "PLAYER_LEVEL_UP",
}

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then
            return
        end
        self:UnregisterEvent("ADDON_LOADED")
        LFGEnhancedDB = LFGEnhancedDB or {}
        ns.db = LFGEnhancedDB
        ApplyDefaults(ns.db, ns.DEFAULTS)
        for _, e in ipairs(REFRESH_EVENTS) do
            self:RegisterEvent(e)
        end
        EventUtil.ContinueOnAddOnLoaded(ns.BLIZZARD_LFG, OnBlizzardLFGLoaded)
        return
    end
    if ns.blizzardReady then
        if ns.SyncPanel then
            ns.SyncPanel()
        end
        if ns.IsFilterActive() then
            ns.Refresh()
        end
    end
end)

------------------------------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------------------------------
SLASH_LFGENHANCED1 = "/lfg"
SLASH_LFGENHANCED2 = "/lfgenhanced"
SlashCmdList.LFGENHANCED = function(msg)
    msg = strtrim((msg or ""):lower())
    if not ns.db then
        return
    end
    if msg == "reset" then
        ns.ResetFilters()
        ns.Print("Filters reset. Hidden players are kept; use /lfg unhideall to clear them.")
    elseif msg == "unhideall" then
        ns.ClearBlocked()
        ns.Print("All hidden players are visible again.")
    elseif msg == "" or msg == "toggle" then
        ns.SetPanelShown(not ns.db.panelShown)
        if not (LFGBrowseFrame and LFGBrowseFrame:IsVisible()) then
            ns.Print(("Filter panel %s. It shows next to Looking For Group > Browse."):format(
                ns.db.panelShown and "on" or "off"))
        end
    else
        ns.Print("/lfg - show or hide the filter panel")
        ns.Print("/lfg reset - turn every filter off (hidden players are kept)")
        ns.Print("/lfg unhideall - clear your hidden players list")
    end
end
