-- The filter panel docked to the right of the Looking For Group window.
--
-- Styling:
--  * background: the panel template's flat background, made near-opaque,
--  * buttons: the LFG list rows' dark rounded art in one flat style (on = gold edge + flat gold tint),
--  * checkboxes: Blizzard's modern minimal checkbox.
local _, ns = ...

local PANEL_WIDTH = 320
local INSET_LEFT, INSET_RIGHT, INSET_TOP, INSET_BOTTOM = 8, 4, 66, 4 -- filter area, from the panel edges
local PAD_X = 12                                                      -- inside the filter area
local SCROLL_GAP = 18
local CONTENT_W = PANEL_WIDTH - INSET_LEFT - INSET_RIGHT - PAD_X * 2 - SCROLL_GAP
local ROW_GAP = 8
local GROUP_GAP = 16
local LABEL_H = 18
local TOGGLE_H = 28
local CHECK_SIZE = 24
local CHECK_ROW_H = 28
local BG_ALPHA = 0.96

-- WoW Forever has the nine original classes; anything else is never filtered.
local FOREVER_CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local ROLES = {
    { key = "tank", atlas = "groupfinder-icon-role-large-tank", micro = "groupfinder-icon-role-micro-tank", label = TANK },
    { key = "healer", atlas = "groupfinder-icon-role-large-heal", micro = "groupfinder-icon-role-micro-heal", label = HEALER },
    { key = "dps", atlas = "groupfinder-icon-role-large-dps", micro = "groupfinder-icon-role-micro-dps", label = DAMAGER },
}

------------------------------------------------------------------------------------------------
-- Fonts (13px minimum)
------------------------------------------------------------------------------------------------
local FONT_PATH, _, FONT_FLAGS = GameFontNormal:GetFont()

local function MakeFont(name, size, r, g, b)
    local font = CreateFont(name)
    font:CopyFontObject(GameFontNormal)
    font:SetFont(FONT_PATH, size, FONT_FLAGS or "")
    font:SetTextColor(r, g, b)
    return font
end

local Fonts = {
    label = MakeFont("EnhancedLFGFontLabel", 14, NORMAL_FONT_COLOR:GetRGB()),
    gold = MakeFont("EnhancedLFGFontGold", 13, NORMAL_FONT_COLOR:GetRGB()),
    text = MakeFont("EnhancedLFGFontText", 13, HIGHLIGHT_FONT_COLOR:GetRGB()),
    muted = MakeFont("EnhancedLFGFontMuted", 13, 0.8, 0.8, 0.8),
    dim = MakeFont("EnhancedLFGFontDim", 13, 0.58, 0.58, 0.58),
}
ns.Fonts = Fonts

local panel, content, summary, resetButton
local syncers = {}
local y = 0

local function Changed()
    ns.OnSettingsChanged()
end

local function Sound(on)
    PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
end

local function AddTooltip(frame, title, text)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title() or title, HIGHLIGHT_FONT_COLOR:GetRGB())
        local body = type(text) == "function" and text() or text
        if body then
            GameTooltip:AddLine(body, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
        end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end

local function Text(parent, font, text)
    local fs = parent:CreateFontString(nil, "ARTWORK")
    fs:SetFontObject(font or Fonts.text)
    fs:SetJustifyH("LEFT")
    if text then
        fs:SetText(text)
    end
    return fs
end

------------------------------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------------------------------
-- The row art is drawn for 312x72 list rows; nine-slice it so the rounded corners survive
-- on smaller buttons.
local SLICE_MODE = Enum.UITextureSliceMode and Enum.UITextureSliceMode.Stretched or 0
local function RowArt(texture, atlas)
    texture:SetAtlas(atlas)
    if texture.SetTextureSliceMargins then
        texture:SetTextureSliceMargins(12, 12, 12, 12)
        texture:SetTextureSliceMode(SLICE_MODE)
    end
    texture:SetAllPoints()
    return texture
end

-- Flat solid fills sit 3px inside the rounded art so their corners stay within its curve.
local function InnerFill(b, layer, r, g, bl, a)
    local t = b:CreateTexture(nil, layer)
    t:SetPoint("TOPLEFT", 3, -3)
    t:SetPoint("BOTTOMRIGHT", -3, 3)
    t:SetColorTexture(r, g, bl, a)
    return t
end

-- The one button style: the list rows' dark rounded art, no gradients.
-- On (selected) = the art's edge tinted gold plus a flat gold tint. Hover = a flat light tint.
-- offFont / onFont: label fonts for the two states.
function ns.CreateButton(parent, width, height, text, offFont, onFont)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b:SetMotionScriptsWhileDisabled(true)
    b.Base = RowArt(b:CreateTexture(nil, "BACKGROUND"), "common-button-list-mid2")
    b.Tint = InnerFill(b, "BORDER", 1, 0.78, 0.25, 0.16)
    b.Tint:Hide()
    InnerFill(b, "HIGHLIGHT", 1, 1, 1, 0.07)
    b.offFont, b.onFont = offFont or Fonts.muted, onFont or Fonts.text
    if text then
        b.Label = Text(b, b.offFont, text)
        b.Label:SetJustifyH("CENTER")
        b.Label:SetPoint("LEFT", 8, 0)
        b.Label:SetPoint("RIGHT", -8, 0)
        b.Label:SetWordWrap(false)
    end
    function b:SetSelected(on)
        self.selected = on
        self.Tint:SetShown(on)
        if on then
            self.Base:SetVertexColor(1, 0.8, 0.4)
        else
            self.Base:SetVertexColor(1, 1, 1)
        end
        if self.Label and self:IsEnabled() then
            self.Label:SetFontObject(on and self.onFont or self.offFont)
        end
    end
    -- Disabled: dim text and art; the selected look is kept.
    function b:SetActive(enabled)
        self:SetEnabled(enabled)
        self.Base:SetAlpha(enabled and 1 or 0.6)
        if self.Label then
            self.Label:SetFontObject(not enabled and Fonts.dim or (self.selected and self.onFont or self.offFont))
        end
    end
    return b
end

-- A text toggle for segmented controls: muted text when off, white on gold when on.
local function CreateTextToggle(parent, text, width)
    return ns.CreateButton(parent, width, TOGGLE_H, text, Fonts.muted, Fonts.text)
end

-- An action button (Reset, Clear all, Filters): gold text like Blizzard's buttons.
function ns.CreateActionButton(parent, text, width, height)
    return ns.CreateButton(parent, width, height or 26, text, Fonts.gold, Fonts.text)
end

-- Segmented control: options = { { value, label, tooltip? }, ... }.
local function CreateSegmented(parent, width, options, get, set)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, TOGGLE_H)
    local gap = 6
    local w = (width - gap * (#options - 1)) / #options
    local buttons = {}
    for i, opt in ipairs(options) do
        local b = CreateTextToggle(frame, opt[2], w)
        b:SetPoint("LEFT", frame, "LEFT", (i - 1) * (w + gap), 0)
        b:SetScript("OnClick", function()
            if get() ~= opt[1] then
                set(opt[1])
                Sound(true)
                Changed()
            end
        end)
        if opt[3] then
            AddTooltip(b, opt[2], opt[3])
        end
        b.value = opt[1]
        buttons[i] = b
    end
    syncers[#syncers + 1] = function()
        local v = get()
        for _, b in ipairs(buttons) do
            b:SetSelected(b.value == v)
        end
    end
    return frame
end

-- Blizzard's modern minimal checkbox with a 13px label.
local function CreateCheck(parent, label, get, set, labelWidth)
    local cb = CreateFrame("CheckButton", nil, parent, "MinimalCheckboxArtTemplate")
    cb:SetSize(CHECK_SIZE, CHECK_SIZE)
    for _, key in ipairs({ "NormalTexture", "PushedTexture", "HighlightTexture", "CheckedTexture", "DisabledCheckedTexture" }) do
        local texture = cb[key]
        if texture then
            texture:ClearAllPoints()
            texture:SetAllPoints()
        end
    end
    cb.Label = Text(cb, Fonts.text, label)
    cb.Label:SetPoint("LEFT", cb, "RIGHT", 6, 0)
    cb.Label:SetWidth(labelWidth)
    cb.Label:SetWordWrap(false)
    cb:SetHitRectInsets(0, -(labelWidth + 6), 0, 0)
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        set(on)
        Sound(on)
        Changed()
    end)
    syncers[#syncers + 1] = function()
        cb:SetChecked(get() and true or false)
    end
    return cb
end

-- zeroIsEmpty: show 0 as an empty box (level bounds); otherwise show the number.
local function CreateNumberBox(name, parent, get, set, zeroIsEmpty)
    local eb = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    eb:SetSize(36, 24)
    eb:SetFontObject(Fonts.text)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(2)
    eb:SetJustifyH("CENTER")
    eb:SetScript("OnEnterPressed", EditBox_ClearFocus)
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            set(self:GetNumber())
            Changed()
        end
    end)
    syncers[#syncers + 1] = function()
        if not eb:HasFocus() then
            local v = get()
            eb:SetText((zeroIsEmpty and v <= 0) and "" or tostring(v))
        end
    end
    return eb
end

------------------------------------------------------------------------------------------------
-- Layout (top to bottom inside the scroll child)
------------------------------------------------------------------------------------------------
local function Place(region, height, gap, x)
    region:SetPoint("TOPLEFT", content, "TOPLEFT", x or 0, -y)
    y = y + height + (gap or ROW_GAP)
end

-- A plain gold label starts each group; spacing does the rest (no divider lines).
local function Label(text)
    if y > 0 then
        y = y + GROUP_GAP
    end
    local fs = Text(content, Fonts.label, text)
    Place(fs, LABEL_H, 6)
    return fs
end

-- Checkboxes in a grid: items = { { label, get, set }, ... }.
local function CheckGrid(items, cols)
    local colW = CONTENT_W / cols
    for i, item in ipairs(items) do
        local cb = CreateCheck(content, item[1], item[2], item[3], colW - CHECK_SIZE - 6)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        cb:SetPoint("TOPLEFT", content, "TOPLEFT", col * colW, -(y + row * CHECK_ROW_H))
    end
    y = y + math.ceil(#items / cols) * CHECK_ROW_H + ROW_GAP
end

------------------------------------------------------------------------------------------------
-- Status texts
------------------------------------------------------------------------------------------------
local function RoleNames(roles)
    local parts = {}
    for _, r in ipairs(ROLES) do
        if roles[r.key] then
            parts[#parts + 1] = r.label
        end
    end
    return table.concat(parts, ", ")
end

local function RoleIcons(roles)
    local parts = {}
    for _, r in ipairs(ROLES) do
        if roles[r.key] then
            parts[#parts + 1] = CreateAtlasMarkup(r.micro, 16, 16)
        end
    end
    return table.concat(parts, " ")
end

local function White(text)
    return "|cffffffff" .. text .. "|r"
end

local function AutoStatusText()
    local roles, source = ns.auto.roles, ns.auto.source
    if source == "full" then
        return "Your group is full, so every player is shown."
    elseif source == "raid" then
        return "Auto works for dungeon groups, not raids. Every role is shown."
    elseif source == "nondungeon" then
        return "Your listing isn't a dungeon, so every role is shown."
    elseif roles then
        if roles.tank and roles.healer and roles.dps then
            return "Your group needs every role, so every player is shown."
        end
        if source == "solo" then
            return "From your LFG role, you need: " .. White(RoleNames(roles))
        end
        return "Your group needs: " .. White(RoleNames(roles))
    end
    return "Shows only players who fill a role your group is missing."
end

local function SummaryText()
    if ns.paused then
        return "|cffff8040Paused during chat lockdown|r"
    end
    local p, g = ns.hidden.players, ns.hidden.groups
    if p + g == 0 then
        return ns.IsFilterActive() and "Nothing hidden right now" or "No filters on"
    end
    local parts = {}
    if p > 0 then
        parts[#parts + 1] = p == 1 and "1 player" or (p .. " players")
    end
    if g > 0 then
        parts[#parts + 1] = g == 1 and "1 group" or (g .. " groups")
    end
    return table.concat(parts, ", ") .. " hidden"
end

------------------------------------------------------------------------------------------------
-- Groups of controls
------------------------------------------------------------------------------------------------
local function BuildShow()
    Label("Show")
    Place(CreateSegmented(content, CONTENT_W, {
        { "all", "All" },
        { "players", "Players", "Only solo players looking for a group." },
        { "groups", "Groups", "Only groups looking for more players." },
    }, function() return ns.db.show end, function(v) ns.db.show = v end), TOGGLE_H)
    local delisted = CreateCheck(content, "Hide delisted players and groups",
        function() return ns.db.hideDelisted end, function(v) ns.db.hideDelisted = v end,
        CONTENT_W - CHECK_SIZE - 6)
    AddTooltip(delisted, "Hide delisted", "Drops the greyed-out rows of players and groups who already left the list.")
    Place(delisted, CHECK_SIZE)
end

local function BuildRoles()
    Label("Roles")
    Place(CreateSegmented(content, CONTENT_W, {
        { "manual", "Choose roles", "Pick the roles a player must be able to fill." },
        { "auto", "Auto", "Show only players who can fill a role your group is still missing (1 tank, 1 healer, 3 damage)." },
    }, function() return ns.db.roleMode end, function(v) ns.db.roleMode = v end), TOGGLE_H)

    local row = CreateFrame("Frame", nil, content)
    row:SetSize(CONTENT_W, 60)
    local gap = 8
    local w = (CONTENT_W - gap * 2) / 3
    local toggles = {}
    for i, role in ipairs(ROLES) do
        local b = ns.CreateButton(row, w, 60)
        b:SetPoint("LEFT", row, "LEFT", (i - 1) * (w + gap), 0)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAtlas(role.atlas)
        icon:SetSize(28, 28)
        icon:SetPoint("TOP", 0, -8)
        local label = Text(b, Fonts.muted, role.label)
        label:SetJustifyH("CENTER")
        label:SetPoint("BOTTOM", 0, 7)
        b:SetScript("OnClick", function()
            local roles = ns.db.roles
            roles[role.key] = not roles[role.key]
            Sound(roles[role.key])
            Changed()
        end)
        AddTooltip(b, role.label, function()
            if ns.db.roleMode == "auto" then
                return "Auto picks the roles from your group. Switch to Choose roles to pick them yourself."
            end
            return "Click to show or hide players who can play this role."
        end)
        function b:SetState(on, enabled)
            self:SetSelected(on)
            icon:SetDesaturated(not on)
            icon:SetAlpha(on and 1 or 0.4)
            label:SetFontObject(on and Fonts.text or Fonts.dim)
            self:SetEnabled(enabled)
        end
        toggles[role.key] = b
    end
    Place(row, 60)

    local status = Text(content, Fonts.muted)
    status:SetWidth(CONTENT_W)
    status:SetHeight(34)
    status:SetJustifyV("TOP")
    status:SetWordWrap(true)
    Place(status, 34, 0)

    syncers[#syncers + 1] = function()
        local db = ns.db
        local auto = db.roleMode == "auto"
        local roles = auto and ns.auto.roles or db.roles
        for _, role in ipairs(ROLES) do
            local on = roles == nil or roles[role.key] and true or false
            toggles[role.key]:SetState(on, not auto)
        end
        if auto then
            status:SetText(AutoStatusText())
        elseif not (db.roles.tank or db.roles.healer or db.roles.dps) then
            status:SetText("|cffff8040No role picked, so every solo player is hidden.|r")
        elseif db.roles.tank and db.roles.healer and db.roles.dps then
            status:SetText("Players of every role are shown.")
        else
            status:SetText("Showing players who can play: " .. White(RoleNames(db.roles)))
        end
    end
end

local function BuildLevel()
    Label(LEVEL)
    Place(CreateSegmented(content, CONTENT_W, {
        { "off", "Any" },
        { "range", "Range", "Only players between two levels. Leave a box empty for no bound." },
        { "near", "Near me", "Only players within a few levels of you." },
    }, function() return ns.db.levelMode end, function(v) ns.db.levelMode = v end), TOGGLE_H)

    local row = CreateFrame("Frame", nil, content)
    row:SetSize(CONTENT_W, 26)
    Place(row, 26)

    local range = CreateFrame("Frame", nil, row)
    range:SetAllPoints()
    local from = Text(range, Fonts.muted, "From")
    from:SetPoint("LEFT", 0, 0)
    local minBox = CreateNumberBox("EnhancedLFGLevelMin", range,
        function() return ns.db.levelMin end, function(v) ns.db.levelMin = v end, true)
    minBox:SetPoint("LEFT", from, "RIGHT", 12, 0)
    local to = Text(range, Fonts.muted, "to")
    to:SetPoint("LEFT", minBox, "RIGHT", 8, 0)
    local maxBox = CreateNumberBox("EnhancedLFGLevelMax", range,
        function() return ns.db.levelMax end, function(v) ns.db.levelMax = v end, true)
    maxBox:SetPoint("LEFT", to, "RIGHT", 12, 0)
    minBox.nextEditBox, maxBox.nextEditBox = maxBox, minBox

    local near = CreateFrame("Frame", nil, row)
    near:SetAllPoints()
    local within = Text(near, Fonts.muted, "Within \194\177")
    within:SetPoint("LEFT", 0, 0)
    local nearBox = CreateNumberBox("EnhancedLFGLevelNear", near,
        function() return ns.db.levelNear end, function(v) ns.db.levelNear = v end)
    nearBox:SetPoint("LEFT", within, "RIGHT", 12, 0)
    local mine = Text(near, Fonts.muted)
    mine:SetPoint("LEFT", nearBox, "RIGHT", 8, 0)

    local any = Text(row, Fonts.dim, "Players of any level are shown.")
    any:SetPoint("LEFT", 0, 0)

    syncers[#syncers + 1] = function()
        local m = ns.db.levelMode
        range:SetShown(m == "range")
        near:SetShown(m == "near")
        any:SetShown(m == "off")
        mine:SetText(("levels of me (%d)"):format(UnitLevel("player")))
    end
end

local function BuildClasses()
    Label(CLASS)
    local items = {}
    for _, classFile in ipairs(FOREVER_CLASSES) do
        local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if color then
            name = color:WrapTextInColorCode(name)
        end
        items[#items + 1] = {
            name,
            function() return not ns.db.hiddenClasses[classFile] end,
            function(v) ns.db.hiddenClasses[classFile] = (not v) or nil end,
        }
    end
    CheckGrid(items, 3)
end

local function BuildGroups()
    Label("Groups")
    local cb = CreateCheck(content, "Only groups with a spot for my role",
        function() return ns.db.groupsNeedMyRole end, function(v) ns.db.groupsNeedMyRole = v end,
        CONTENT_W - CHECK_SIZE - 6)
    AddTooltip(cb, "Only groups with a spot for my role", "Uses the roles ticked in your own LFG listing.")
    Place(cb, CHECK_SIZE, 4)
    local mine = Text(content, Fonts.dim)
    mine:SetWidth(CONTENT_W)
    Place(mine, 18)
    syncers[#syncers + 1] = function()
        local roles = C_LFGListRoles.GetRoles()
        if roles and (roles.tank or roles.healer or roles.dps) then
            mine:SetText("Your LFG roles: " .. RoleIcons(roles))
        else
            mine:SetText("Tick your roles in the Listing tab first.")
        end
    end
end

local function PlaystyleLabel(i)
    local text = GetGeneralPlaystyleString and GetGeneralPlaystyleString(i)
    if not text or text == "" then
        text = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. i]
    end
    return text or ({ "Learning", "Relaxed", "Competitive", "Expert" })[i]
end

local function BuildListing()
    Label("Playstyle")
    local items = {}
    for i = 1, 4 do
        items[i] = {
            PlaystyleLabel(i),
            function() return ns.db.playstyles[i] end,
            function(v) ns.db.playstyles[i] = v end,
        }
    end
    CheckGrid(items, 2)

    Label("New-player friendly")
    Place(CreateSegmented(content, CONTENT_W, {
        { "any", "Any" },
        { "only", "Only these", "Only listings marked new-player friendly." },
    }, function() return ns.db.newPlayerFriendly end, function(v) ns.db.newPlayerFriendly = v end), TOGGLE_H)

    Label("Discord voice chat")
    Place(CreateSegmented(content, CONTENT_W, {
        { "any", "Any" },
        { "only", "Only", "Only listings that use Discord voice chat." },
        { "hide", "Hide", "Hide listings that use Discord voice chat." },
    }, function() return ns.db.discord end, function(v) ns.db.discord = v end), TOGGLE_H)
end

local function BuildHidden()
    local title = Label("Hidden players")
    local clear = ns.CreateActionButton(content, "Clear all", 90, 24)
    clear:SetPoint("RIGHT", title, "LEFT", CONTENT_W, 0)
    clear:SetScript("OnClick", function()
        Sound(false)
        ns.ClearBlocked()
    end)

    local hint = Text(content, Fonts.dim, "Hover a row in the list and click its "
        .. CreateAtlasMarkup("common-search-clearbutton", 14, 14) .. " to hide that player or group.")
    hint:SetWidth(CONTENT_W)
    hint:SetWordWrap(true)
    hint:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)

    local startY = y
    local ROW_H, ROW_SPACING = 30, 6
    local rows = {}
    local function GetRow(i)
        if rows[i] then
            return rows[i]
        end
        local row = ns.CreateButton(content, CONTENT_W, ROW_H)
        row:EnableMouse(false)
        row.Name = Text(row, Fonts.text)
        row.Name:SetPoint("LEFT", 12, 0)
        row.Name:SetPoint("RIGHT", -34, 0)
        row.Name:SetWordWrap(false)
        local unhide = CreateFrame("Button", nil, row)
        unhide:SetSize(18, 18)
        unhide:SetPoint("RIGHT", -8, 0)
        unhide:SetNormalAtlas("common-search-clearbutton")
        unhide:SetHighlightAtlas("common-search-clearbutton", "ADD")
        unhide:SetScript("OnClick", function()
            Sound(false)
            ns.UnblockName(row.name)
        end)
        AddTooltip(unhide, function() return "Show " .. (row.name or "") .. " again" end)
        rows[i] = row
        return row
    end

    syncers[#syncers + 1] = function()
        local names = {}
        for name in pairs(ns.db.blocked) do
            names[#names + 1] = name
        end
        table.sort(names)
        title:SetText(#names > 0 and ("Hidden players (" .. #names .. ")") or "Hidden players")
        clear:SetShown(#names > 0)
        hint:SetShown(#names == 0)
        for i, name in ipairs(names) do
            local row = GetRow(i)
            row.name = name
            row.Name:SetText(name)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(startY + (i - 1) * (ROW_H + ROW_SPACING)))
            row:Show()
        end
        for i = #names + 1, #rows do
            rows[i]:Hide()
        end
        local listHeight = #names > 0 and (#names * (ROW_H + ROW_SPACING)) or 36
        content:SetHeight(startY + listHeight + 12)
    end
end

------------------------------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------------------------------
function ns.SyncPanel()
    if not panel or not panel:IsVisible() then
        return
    end
    if ns.db.roleMode == "auto" then
        local ok, roles, source = pcall(ns.ComputeAutoRoles, LFGBrowseFrame and LFGBrowseFrame.results)
        if ok then
            ns.auto.roles, ns.auto.source = roles, source
        end
    end
    summary:SetText(SummaryText())
    resetButton:SetActive(ns.HasResettableFilters())
    for _, sync in ipairs(syncers) do
        sync()
    end
end

function ns.ApplyPanelShown()
    if panel then
        panel:SetShown(ns.db.panelShown)
    end
end

-- The flat background, recoloured to the LFG window's near-black warm tone and made
-- near-opaque so the world barely shows through.
local BG_COLOR = { 0.07, 0.063, 0.05 }
local function MakeBackgroundOpaque(bg)
    if not bg then
        return
    end
    local r, g, b = BG_COLOR[1], BG_COLOR[2], BG_COLOR[3]
    for _, region in ipairs({ bg:GetRegions() }) do
        if region:IsObjectType("Texture") then
            if region:GetAtlas() then
                region:SetVertexColor(r, g, b, BG_ALPHA)
            else
                region:SetColorTexture(r, g, b, BG_ALPHA)
            end
        end
    end
end

function ns.CreatePanel()
    local parent = LFGParentFrame
    panel = CreateFrame("Frame", "EnhancedLFGPanel", LFGBrowseFrame, "DefaultPanelFlatTemplate")
    panel:SetWidth(PANEL_WIDTH)
    -- Clear Blizzard's side tabs (Listing / Browse / Who) on the window's right edge.
    local tabs = parent.ListingTab
    local offset = math.max(tabs and tabs:GetWidth() or 0, 40) + 6
    panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", offset, 0)
    panel:SetPoint("BOTTOMLEFT", parent, "BOTTOMRIGHT", offset, 0)
    panel:EnableMouse(true)
    MakeBackgroundOpaque(panel.Bg)

    -- Layout area for the filters below the header (no art of its own: the background is flat).
    local inset = CreateFrame("Frame", nil, panel)
    inset:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET_LEFT, -INSET_TOP)
    inset:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -INSET_RIGHT, INSET_BOTTOM)

    if panel.TitleContainer and panel.TitleContainer.TitleText then
        panel.TitleContainer.TitleText:SetFontObject(Fonts.label)
        panel.TitleContainer.TitleText:SetText("Filters")
    end

    -- Same size and spot as Camelot's UIPanelCloseButtonDefaultAnchorsMixin.
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButtonNoScripts")
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 3)
    close:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        ns.SetPanelShown(false)
    end)

    -- Header on the stone band, centred between the title bar and the inner frame.
    local headerY = -(21 + INSET_TOP) / 2
    resetButton = ns.CreateActionButton(panel, "Reset", 84, 26)
    resetButton:SetPoint("RIGHT", panel, "TOPRIGHT", -(INSET_RIGHT + 8), headerY)
    resetButton:SetScript("OnClick", function()
        Sound(false)
        ns.ResetFilters()
    end)
    AddTooltip(resetButton, "Reset filters", "Turns every filter off. Your hidden players are kept.")

    summary = Text(panel, Fonts.text)
    summary:SetPoint("LEFT", panel, "TOPLEFT", INSET_LEFT + 8, headerY)
    summary:SetPoint("RIGHT", resetButton, "LEFT", -8, 0)
    summary:SetWordWrap(false)

    local scroll = CreateFrame("ScrollFrame", nil, inset)
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", PAD_X, -PAD_X)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -(PAD_X + SCROLL_GAP), 10)
    local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 900)
    scroll:SetScrollChild(content)
    ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)
    scroll:EnableMouseWheel(true)
    scroll:HookScript("OnScrollRangeChanged", function(_, _, vRange)
        scrollBar:SetShown((vRange or 0) > 0.5)
    end)

    y = 0
    BuildShow()
    BuildRoles()
    BuildLevel()
    BuildClasses()
    BuildGroups()
    BuildListing()
    BuildHidden()

    panel:SetScript("OnShow", ns.SyncPanel)
    ns.ApplyPanelShown()
end
