-- Filter decisions and the post-hook on Blizzard's sort.
local _, ns = ...

-- Results of the last filter pass, read by the panel and the "Filters" button.
ns.hidden = { players = 0, groups = 0 }
ns.paused = false
ns.auto = { roles = nil, source = nil }

-- Blizzard's own dungeon expectations (Blizzard_LFGVanilla_Browse.lua).
local EXPECTED = { tank = 1, healer = 1, dps = 3 }
local ROLE_TOKEN = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local DISCORD = Enum.LFGEntryVoiceMode and Enum.LFGEntryVoiceMode.Discord or 2

local function AllRoles(r)
    return r.tank and r.healer and r.dps
end

local function AnyRole(r)
    return r.tank or r.healer or r.dps
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- While chat messaging is locked down (boss fights and similar), search data comes back as
-- secret values that addon code may not test, so everything here stands down.
local function InChatLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() and true or false
end
ns.InChatLockdown = InChatLockdown

------------------------------------------------------------------------------------------------
-- What counts as "a filter is on"
------------------------------------------------------------------------------------------------
function ns.LevelFilterActive()
    local db = ns.db
    if db.levelMode == "range" then
        return db.levelMin > 0 or db.levelMax > 0
    end
    return db.levelMode == "near"
end

function ns.PlaystyleFilterActive()
    for i = 1, 4 do
        if not ns.db.playstyles[i] then
            return true
        end
    end
    return false
end

-- Everything "Reset filters" turns off (the hidden-players list is kept on reset).
function ns.HasResettableFilters()
    local db = ns.db
    if not db then
        return false
    end
    return db.show ~= "all"
        or db.hideDelisted
        or db.roleMode == "auto"
        or not AllRoles(db.roles)
        or ns.LevelFilterActive()
        or next(db.hiddenClasses) ~= nil
        or db.groupsNeedMyRole
        or ns.PlaystyleFilterActive()
        or db.newPlayerFriendly ~= "any"
        or db.discord ~= "any"
end

function ns.IsFilterActive()
    return ns.HasResettableFilters() or (ns.db ~= nil and next(ns.db.blocked) ~= nil)
end

------------------------------------------------------------------------------------------------
-- Auto roles: which roles does my group still need?
------------------------------------------------------------------------------------------------
local function ActiveListingIsDungeon()
    if not C_LFGList.HasActiveEntryInfo() then
        return nil -- no listing
    end
    local entry = C_LFGList.GetActiveEntryInfo()
    if not entry or not entry.activityIDs then
        return nil
    end
    for _, activityID in ipairs(entry.activityIDs) do
        local activity = C_LFGList.GetActivityInfoTable(activityID)
        if activity and activity.useDungeonRoleExpectations then
            return true
        end
    end
    return false
end

-- Assigned roles of my party, or my one ticked LFG role when solo.
local function CountMyGroup()
    local have = { tank = 0, healer = 0, dps = 0 }
    if IsInGroup() then
        local units = { "player" }
        for i = 1, GetNumSubgroupMembers() do
            units[#units + 1] = "party" .. i
        end
        for _, unit in ipairs(units) do
            local role = ROLE_TOKEN[UnitGroupRolesAssigned(unit)]
            if role then
                have[role] = have[role] + 1
            end
        end
    else
        local mine = C_LFGListRoles.GetRoles()
        local count, only = 0, nil
        for role in pairs(EXPECTED) do
            if mine[role] then
                count, only = count + 1, role
            end
        end
        if count == 1 then
            have[only] = 1
        end
    end
    return have
end

-- Returns roles = { tank, healer, dps } (true = needed) or nil, plus where the answer came from.
-- source: "listing" | "party" | "solo" | "full" | "raid" | "nondungeon"
function ns.ComputeAutoRoles(results)
    -- 1. My own listing in the results carries the server's open-slot counts.
    if type(results) == "table" then
        for i = 1, #results do
            local resultID = results[i]
            local info = C_LFGList.GetSearchResultInfo(resultID)
            if info and info.hasSelf then
                local counts = C_LFGList.GetSearchResultMemberCounts(resultID)
                if counts and counts.TANK_REMAINING ~= nil then
                    local needs = {
                        tank = (counts.TANK_REMAINING or 0) > 0,
                        healer = (counts.HEALER_REMAINING or 0) > 0,
                        dps = (counts.DAMAGER_REMAINING or 0) > 0,
                    }
                    if not AnyRole(needs) then
                        return nil, "full"
                    end
                    return needs, "listing"
                end
                break
            end
        end
    end

    -- 2. Otherwise my group against the dungeon expectations (raids and other content: no auto).
    if IsInRaid() then
        return nil, "raid"
    end
    if ActiveListingIsDungeon() == false then
        return nil, "nondungeon"
    end
    local have = CountMyGroup()
    local needs = {
        tank = have.tank < EXPECTED.tank,
        healer = have.healer < EXPECTED.healer,
        dps = have.dps < EXPECTED.dps,
    }
    if not AnyRole(needs) then
        return nil, "full"
    end
    return needs, IsInGroup() and "party" or "solo"
end

-- The roles a solo player must offer to stay in the list, or nil for "no role filter".
local function WantedRoles()
    local db = ns.db
    local roles = db.roleMode == "auto" and ns.auto.roles or db.roles
    if not roles or AllRoles(roles) then
        return nil
    end
    return roles
end

------------------------------------------------------------------------------------------------
-- Per-result decision
------------------------------------------------------------------------------------------------
local function PassesListingRules(info, db)
    if db.hideDelisted and info.isDelisted then
        return false
    end
    if info.leaderName and db.blocked[info.leaderName] then
        return false
    end
    local playstyle = info.generalPlaystyle
    if playstyle and playstyle > 0 and db.playstyles[playstyle] == false then
        return false
    end
    if db.newPlayerFriendly == "only" and not info.newPlayerFriendly then
        return false
    end
    if db.discord ~= "any" then
        local usesDiscord = info.voiceMode == DISCORD
        if (db.discord == "only") ~= usesDiscord then
            return false
        end
    end
    return true
end

local function PassesPlayerRules(resultID, db, wantRoles, myLevel)
    local member = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
    if not member then
        return true
    end
    if wantRoles then
        local r = member.lfgRoles
        if not (r and ((wantRoles.tank and r.tank) or (wantRoles.healer and r.healer) or (wantRoles.dps and r.dps))) then
            return false
        end
    end
    if member.classFilename and db.hiddenClasses[member.classFilename] then
        return false
    end
    local level = member.level
    if level then
        if db.levelMode == "range" then
            if (db.levelMin > 0 and level < db.levelMin) or (db.levelMax > 0 and level > db.levelMax) then
                return false
            end
        elseif db.levelMode == "near" then
            if math.abs(level - myLevel) > db.levelNear then
                return false
            end
        end
    end
    return true
end

-- Groups with an open slot for a role I have ticked in my LFG roles.
local function PassesGroupRules(resultID, myRoles)
    if not myRoles then
        return true
    end
    local counts = C_LFGList.GetSearchResultMemberCounts(resultID)
    if not counts then
        return true
    end
    return (myRoles.tank and (counts.TANK_REMAINING or 0) > 0)
        or (myRoles.healer and (counts.HEALER_REMAINING or 0) > 0)
        or (myRoles.dps and (counts.DAMAGER_REMAINING or 0) > 0)
        or false
end

-- Returns keep, isPlayer.
local function Decide(resultID, db, wantRoles, myRoles, myLevel)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info or IsSecret(info.numMembers) or IsSecret(info.hasSelf) or info.hasSelf then
        return true, false
    end
    local isPlayer = info.numMembers <= 1
    if db.show == "players" and not isPlayer then
        return false, false
    elseif db.show == "groups" and isPlayer then
        return false, true
    end
    if not PassesListingRules(info, db) then
        return false, isPlayer
    end
    if isPlayer then
        return PassesPlayerRules(resultID, db, wantRoles, myLevel), true
    end
    return PassesGroupRules(resultID, myRoles), false
end

------------------------------------------------------------------------------------------------
-- The hook
------------------------------------------------------------------------------------------------
-- Decides every entry first and only then rewrites the table, so an error can never leave
-- Blizzard's list half-compacted.
local function Collect(results, keep)
    local db = ns.db
    local wantRoles = WantedRoles()
    local myRoles = nil
    if db.groupsNeedMyRole then
        local mine = C_LFGListRoles.GetRoles()
        if mine and AnyRole(mine) then
            myRoles = mine
        end
    end
    local myLevel = UnitLevel("player")
    local hidden = ns.hidden
    for i = 1, #results do
        local ok, isPlayer = Decide(results[i], db, wantRoles, myRoles, myLevel)
        if ok then
            keep[#keep + 1] = results[i]
        elseif isPlayer then
            hidden.players = hidden.players + 1
        else
            hidden.groups = hidden.groups + 1
        end
    end
end

local function FilterResults(results)
    local hidden = ns.hidden
    hidden.players, hidden.groups = 0, 0
    ns.paused = false
    if not ns.db or type(results) ~= "table" or not ns.IsFilterActive() then
        return
    end
    if InChatLockdown() then
        ns.paused = true
        return
    end
    if ns.db.roleMode == "auto" then
        local ok, roles, source = pcall(ns.ComputeAutoRoles, results)
        if ok then
            ns.auto.roles, ns.auto.source = roles, source
        else
            ns.auto.roles, ns.auto.source = nil, nil
            geterrorhandler()(roles)
        end
    end

    local keep = {}
    local ok, err = pcall(Collect, results, keep)
    if not ok then
        hidden.players, hidden.groups = 0, 0
        geterrorhandler()(err)
        return
    end
    local count = #results
    if #keep == count then
        return
    end
    for i = 1, #keep do
        if results[i] ~= keep[i] then
            results[i] = keep[i]
        end
    end
    for i = count, #keep + 1, -1 do
        results[i] = nil
    end
end

function ns.InstallFilterHook()
    hooksecurefunc("LFGBrowseUtil_SortSearchResults", FilterResults)
end
