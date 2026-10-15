-- Mock Forever client for WhoLayerSwap tests.
OUT, LOG = {}, {}
function print(s) OUT[#OUT + 1] = s end
local function log(s) LOG[#LOG + 1] = s end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- clock + timers
NOW = 1000
TIMERS = {}
GetTime = function() return NOW end
C_Timer = { After = function(d, fn) TIMERS[#TIMERS + 1] = { at = NOW + d, fn = fn } end }
function ADVANCE(sec)
    local target = NOW + sec
    while true do
        table.sort(TIMERS, function(a, b) return a.at < b.at end)
        local t = TIMERS[1]
        if not t or t.at > target then break end
        table.remove(TIMERS, 1)
        NOW = t.at
        t.fn()
    end
    NOW = target
end

-- widgets
local W = {}
local FIELDS = { hasSecure = 1, rows = 1, count = 1, empty = 1, more = 1, title = 1, slot = 1, queue = 1, itemID = 1, fname = 1, charter = 1, icon = 1, tex = 1, hint = 1, edits = 1, checks = 1, move = 1, gear = 1, get = 1, set = 1, Text = 1, checked = 1, ag = 1, kids = 1, playing = 1, inviting = 1, invite = 1, plan = 1, attrs = 1, secure = 1, scripts = 1, txt = 1, shown = 1, enabled = 1, text = 1, buttons = 1, t = 1, lang = 1, label = 1, accepted = 1, alpha = 1, points = 1 }
W.__index = function(t, k) if FIELDS[k] then return nil end return W[k] or function() end end
function W:SetScript(n, fn) local s = rawget(self, "scripts") or {}; rawset(self, "scripts", s); s[n] = fn end
function W:CreateTexture() return setmetatable({}, W) end
function W:CreateFontString() return setmetatable({}, W) end
function W:Show() self.shown = true end
function W:Hide()
    local was = self.shown; self.shown = false
    if was and self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function W:IsShown() return self.shown end
function W:SetShown(v) if v then self:Show() else self:Hide() end end
function W:SetText(t) self.txt = t end
function W:SetEnabled(v) self.enabled = v end
function W:SetAlpha(a) self.alpha = a end
function W:SetPoint(...) self.points = { ... } end
function W:GetPoint() return "TOPRIGHT", nil, "TOPRIGHT", -100, -50 end
function W:SetAttribute(k, v)
    if INCOMBAT and rawget(self, "secure") then error("ADDON_ACTION_BLOCKED SetAttribute in combat") end
    local a = rawget(self, "attrs") or {}; rawset(self, "attrs", a); a[k] = v
end
function W:GetAttribute(k) local a = rawget(self, "attrs"); return a and a[k] end
FRAMES = {}
function CreateFrame(kind, name, parent, template)
    local w = setmetatable({}, W); FRAMES[#FRAMES + 1] = w
    if template and template:find("SecureActionButtonTemplate") then rawset(w, "secure", true) end
    if name then _G[name] = w end
    return w
end
UIParent = setmetatable({}, W); MinimapCluster = setmetatable({}, W)
GameTooltip = setmetatable({}, W)
-- Blizzard's invite window: hiding it without .accepted declines the invite
GuildInviteFrame = setmetatable({}, W)
GuildInviteFrame:SetScript("OnHide", function(self) if not self.accepted then DeclineGuild() end end)
DeclineGuild = function() log("DECLINE") end
AcceptGuild = function() log("ACCEPT") end

SlashCmdList, StaticPopupDialogs = {}, {}
ACCEPT, CANCEL = "Accept", "Cancel"
POPUP = nil
StaticPopup_Show = function(n, a, b, data) POPUP = { n = n, a = a, b = b, data = data } end

-- player / guild
ME, MYREALM = "Ryan", "Dreamscythe"
GUILD, GUILD_KNOWN, LEADER, CAN_INVITE = "Who", true, false, true
ROSTER = {}          -- [name] = true for members of my guild
LEAVE_BLOCKED = false
GetGuildInfo = function() if GUILD and GUILD_KNOWN then return GUILD, "Member", 3 end end
IsInGuild = function() return GUILD ~= nil end
CanGuildInvite = function() return CAN_INVITE end
IsGuildLeader = function() return LEADER end
UnitName = function() return ME end
GetNormalizedRealmName = function() return MYREALM end
Ambiguate = function(n) local nm, realm = n:match("^([^-]+)-(.+)$"); if realm == MYREALM then return nm end return n end
C_GuildInfo = {
    Invite = function(n) log("INVITE " .. n) end,
    Leave = function()
        if not SECURE_CONTEXT then log("BLOCKED C_GuildInfo.Leave"); return end
        if LEAVE_BLOCKED then log("LEAVE-BLOCKED") return end log("LEAVE " .. tostring(GUILD)); GUILD = nil end,
    MemberExistsByName = function(n) return ROSTER[n] == true end,
    GuildRoster = function() log("ROSTER-REQUEST") end,
}

-- chat
LOCKDOWN = false
SECRET = {}      -- values registered here count as secret
issecretvalue = function(v) return SECRET[v] == true end
CHANNELS = { { 1, "General", false }, { 2, "Trade", false }, { 6, "WhoGuild", false } }
GetChannelName = function(n)
    for _, c in ipairs(CHANNELS) do if c[2] == n then return c[1], c[2] end end   -- exact, case-sensitive
    return 0
end
GetChannelList = function()
    local r = {}
    for _, c in ipairs(CHANNELS) do r[#r + 1] = c[1]; r[#r + 1] = c[2]; r[#r + 1] = c[3] end
    return unpack(r)
end
unpack = unpack or table.unpack
C_ChatInfo = {
    InChatMessagingLockdown = function() return LOCKDOWN end,
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(p, m, c) log("ADDONMSG " .. m) end,
    SendChatMessage = function(m, t, l, id) log("SAY " .. t .. " " .. tostring(id) .. " " .. m) end,
}
CLUBS = { [77] = "WhoGuild", [88] = "WhoGuild Fans", [99] = "Raiders" }
CLUB_MSGS = {}
C_Club = {
    GetClubInfo = function(id) if CLUBS[id] then return { clubId = id, name = CLUBS[id] } end end,
    GetSubscribedClubs = function()
        local r = {}
        for id, n in pairs(CLUBS) do r[#r + 1] = { clubId = id, name = n } end
        table.sort(r, function(a, b) return a.clubId < b.clubId end)
        return r
    end,
    GetStreams = function() return { { streamId = 1, streamType = 1 }, { streamId = 2, streamType = 0 } } end,
    SendMessage = function(c, s, m) log("CLUB " .. c .. " " .. s .. " " .. m) end,
    GetMessageInfo = function(c, s, id) return CLUB_MSGS[id] end,
}
Enum = { ClubStreamType = { General = 0 } }
GUIDS = {}
GetPlayerInfoByGUID = function(g) local p = GUIDS[g]; if p then return "Class", "CLASS", "Race", "RACE", 0, p[1], p[2] end end

-- combat + secure execution
INCOMBAT = false
InCombatLockdown = function() return INCOMBAT end
SECURE_CONTEXT = false
-- what the secure button does on click: run its macro as typed commands
function RUN_MACRO(text)
    for line in (text or ""):gmatch("[^\n]+") do
        if line == "/gquit" then SECURE_CONTEXT = true; C_GuildInfo.Leave(); SECURE_CONTEXT = false
        else log("MACRO " .. line) end
    end
end
function CLICK(b)
    if b.scripts.PreClick then b.scripts.PreClick(b, "LeftButton", false) end
    if not INCOMBAT or true then RUN_MACRO(b:GetAttribute("type") == "macro" and b:GetAttribute("macrotext") or "") end
    if b.scripts.PostClick then b.scripts.PostClick(b, "LeftButton", false) end
end
-- hidden channel
JOIN_FAILS = false
JoinPermanentChannel = function(name, pw, frame)
    log("JOIN " .. name .. " frame=" .. tostring(frame))
    if JOIN_FAILS then return end
    CHANNELS[#CHANNELS + 1] = { 5, name, false }
    return 0, name
end
RemoveChatWindowChannel = function(i, name) end
C_ChatInfo.SendAddonMessage = function(p, m, c, t) log("ADDONMSG " .. tostring(c) .. " " .. tostring(t) .. " " .. m); return ADDONMSG_RESULT or 0 end
DEFAULT_CHAT_FRAME = { channelList = {}, zoneChannelList = {} }
function DEFAULT_CHAT_FRAME:AddChannel(n) log("CHATFRAME-ADD " .. n); self.channelList[#self.channelList + 1] = n end
function DEFAULT_CHAT_FRAME:RemoveChannel(n)
    log("CHATFRAME-REMOVE " .. n)
    for i, v in pairs(self.channelList) do if v:upper() == n:upper() then self.channelList[i] = nil end end
end
-- Forever: guild invites need a hardware event; direct addon calls are blocked.
C_GuildInfo.Invite = function(n)
    if not SECURE_CONTEXT then log("BLOCKED C_GuildInfo.Invite"); return end
    log("INVITE " .. n)
end
ACCEPT_BLOCKED = false
AcceptGuild = function()
    if ACCEPT_BLOCKED then log("BLOCKED AcceptGuild"); EV("ADDON_ACTION_BLOCKED", "WhoLayerSwap", "AcceptGuild()"); return end
    log("ACCEPT")
end
function RUN_MACRO(text)
    for line in (text or ""):gmatch("[^\n]+") do
        if line == "/gquit" then SECURE_CONTEXT = true; C_GuildInfo.Leave(); SECURE_CONTEXT = false
        elseif line:match("^/ginvite ") then SECURE_CONTEXT = true; C_GuildInfo.Invite(line:match("^/ginvite (.+)$")); SECURE_CONTEXT = false
        else log("MACRO " .. line) end
    end
end
function CLICK(b, mouse)
    mouse = mouse or "LeftButton"
    if b.scripts.PreClick then b.scripts.PreClick(b, mouse, false) end
    RUN_MACRO(b:GetAttribute("type") == "macro" and b:GetAttribute("macrotext") or "")
    if b.scripts.PostClick then b.scripts.PostClick(b, mouse, false) end
end
MYGUID = "Player-1-0000ME"
UnitGUID = function(u) if u == "player" then return MYGUID end end
UnitFullName = function(u) if u == "player" then return ME, MYREALM end end
ROSTER_GUIDS = {}
GetNumGuildMembers = function() return #ROSTER_GUIDS end
GetGuildRosterInfo = function(i) return "n","r",1,1,"c","z","","",true,0,"C",0,0,false,false,0, ROSTER_GUIDS[i] end
SOUNDKIT = { READY_CHECK = 8960 }
PlaySound = function() log("SOUND") end
SOUNDKIT.MAP_PING = 3175
PlaySound = function(id) log("SOUND " .. tostring(id)) end
local AG = {}
AG.__index = function(t, k) return AG[k] or function() end end
function AG:Play() self.playing = true end
function AG:Stop() self.playing = false end
function AG:CreateAnimation() return setmetatable({}, AG) end
function W:CreateAnimationGroup() local g = setmetatable({}, AG); rawset(self, "ag", g); return g end
function W:CreateTexture() local t = setmetatable({}, W); local k = rawget(self, "kids") or {}; rawset(self, "kids", k); k[#k+1] = t; return t end
function W:HookScript(n, fn)
    local s = rawget(self, "scripts") or {}; rawset(self, "scripts", s)
    local old = s[n]; s[n] = old and function(...) old(...) fn(...) end or fn
end
local baseShow, baseHide = W.Show, W.Hide
function W:Show() local was = rawget(self, "shown"); baseShow(self); local s = rawget(self, "scripts"); if not was and s and s.OnShow then s.OnShow(self) end end
function W:GetText() return rawget(self, "txt") end
function W:SetChecked(v) rawset(self, "checked", v and true or false) end
function W:GetChecked() return rawget(self, "checked") == true end
function W:HasFocus() return false end
UISpecialFrames = {}
SETTINGS_CATS = {}
Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) local c = { name = name, frame = frame }; return c, {} end,
    RegisterAddOnCategory = function(c) SETTINGS_CATS[#SETTINGS_CATS + 1] = c.name end,
}
-- bags: BAGS[bag][slot] = { itemID =, itemName =, iconFileID = }
BAGS = { [0] = {}, [1] = {}, [2] = {}, [3] = {}, [4] = {} }
NUM_BAG_SLOTS = 4
C_Container = {
    GetContainerNumSlots = function(bag) return BAGS[bag] and 16 or 0 end,
    GetContainerItemInfo = function(bag, slot) return BAGS[bag] and BAGS[bag][slot] or nil end,
}
ITEM_NAMES = { [5863] = "Guild Charter" }
C_Item = { GetItemNameByID = function(id) return ITEM_NAMES[id] end }
function W:SetTexture(t) rawset(self, "tex", t) end
OVERRIDES = {}   -- key -> button name
function SetOverrideBindingClick(owner, prio, key, btn, mouse)
    if INCOMBAT then error("ADDON_ACTION_BLOCKED SetOverrideBindingClick in combat") end
    OVERRIDES[key] = btn
end
function ClearOverrideBindings(owner)
    if INCOMBAT then error("ADDON_ACTION_BLOCKED ClearOverrideBindings in combat") end
    for k, v in pairs(OVERRIDES) do if v == owner:GetName() then OVERRIDES[k] = nil end end
end
function W:GetName() return rawget(self, "fname") end
local _CF = CreateFrame
function CreateFrame(kind, name, parent, template) local w = _CF(kind, name, parent, template); if name then rawset(w, "fname", name) end; return w end
PetitionFrame = setmetatable({}, W)
TARGET = nil          -- { name = "Bob-Dreamscythe", player = true, me = false }
UnitExists = function(u) return u == "target" and TARGET ~= nil or u == "player" end
UnitIsPlayer = function(u) return u == "target" and TARGET ~= nil and TARGET.player ~= false end
UnitIsUnit = function(a, b) return a == "target" and b == "player" and TARGET ~= nil and TARGET.me == true end
GetUnitName = function(u, realm) if u == "target" and TARGET then return TARGET.name end end
SIGNED = {}
GetNumPetitionNames = function() return #SIGNED end
GetPetitionNameInfo = function(i) return SIGNED[i] end
-- Combat protection: secure buttons and frames holding them can't be shown, hidden,
-- moved or resized in combat (the real client blocks it).
local function guarded(self) return rawget(self, "secure") or rawget(self, "hasSecure") end
local function protect(name)
    local orig = W[name]
    W[name] = function(self, ...)
        if INCOMBAT and guarded(self) then error("ADDON_ACTION_BLOCKED " .. name .. " on protected frame in combat") end
        return orig(self, ...)
    end
end
for _, n in ipairs({ "Show", "Hide", "SetShown", "SetPoint", "ClearAllPoints", "SetHeight", "SetSize" }) do
    W[n] = W[n] or function() end
    protect(n)
end
local _CF2 = CreateFrame
function CreateFrame(kind, name, parent, template)
    local w = _CF2(kind, name, parent, template)
    if template and template:find("SecureActionButtonTemplate") and type(parent) == "table" then rawset(parent, "hasSecure", true) end
    return w
end
-- ADVANCE also runs OnUpdate scripts (frames are visible unless hidden, like WoW), in 0.25s steps.
local _ADV = ADVANCE
function ADVANCE(sec)
    local left = sec
    while left > 1e-9 do
        local step = math.min(0.25, left)
        _ADV(step)
        for _, fr in ipairs(FRAMES) do
            local sc = rawget(fr, "scripts")
            if sc and sc.OnUpdate and rawget(fr, "shown") ~= false and fr ~= rawget(_G, "WhoLayerSwapToast") then
                sc.OnUpdate(fr, step)
            end
        end
        left = left - step
    end
end
