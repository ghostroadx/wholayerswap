-- WhoLayerSwap
--
-- Everyone with this addon joins the swap channel (whoguildlayerswapchannel).
--  * The English / Latam / Portuguese buttons leave your guild and type a locked
--    phrase in the channel ("LayerSwap English" ...). They're secure macro buttons,
--    because leaving a guild is a Blizzard-only action.
--  * Members of the matching guild who run the addon get an "Invite <name>" button
--    (Forever only lets a guild invite go out from a real click). One click invites;
--    the button disappears for the rest of the guild.
--      <quien> : Latam      <who> : English      <quem> : Portuguese
--  * Invites from those three guilds are accepted automatically when the game
--    allows it, and joining one shows a "Relog to change layers" toast.
--
-- Built for WoW Forever (interface 16001): chat is a secret value during chat
-- lockdown (boss fights, rated PvP), so nothing happens then.

local ADDON  = ...
local PREFIX = "|cff33ff99WhoLayerSwap:|r "
local COMM   = "WHOLAYERSWAP"   -- addon-message prefix (requests on the channel, claims in guild)

------------------------------------------------------------------------------
-- Settings (Forever doesn't reload saved settings yet, so these are defaults)
------------------------------------------------------------------------------
local cfg = {
    enabled        = true,
    channel        = "whoguildlayerswapchannel",
    whisperTrigger = "ginv",
    autoAccept     = true,      -- accept invites from the three guilds (Settings)
    verbose        = true,      -- print a line when you invite someone
    debug          = false,     -- /wls debug: explain every request seen
}
-- Saved settings (may come back empty on Forever's beta; always read through DB()).
local function DB()
    if type(WhoLayerSwapDB) ~= "table" then WhoLayerSwapDB = {} end
    return WhoLayerSwapDB
end

-- Which guilds invite for which language. Every copy knows the built-in names
-- (main guild + backup in case the name is taken); Settings can add extra names.
-- Names compare ignoring capitals and spaces ("Who Two" = "whotwo"), nothing else.
local LANGS = { "english", "spanish", "portuguese" }
local BUILTIN_GUILDS = {
    english    = { "Who",   "Who Two" },
    spanish    = { "Quien", "Quien Two" },
    portuguese = { "Quem",  "Quem Two" },
}
local NAMES = {}   -- lang -> list of display names (built-in first, then extras)
local MATCH = {}   -- normalized guild name -> lang

local function GKey(name)
    return ((type(name) == "string" and name or ""):lower():gsub("%s", ""))
end

-- Extra names saved in Settings, comma-separated (guild names can't contain commas).
local function ExtraNames(lang)
    local raw = type(DB().guilds) == "table" and DB().guilds[lang]
    local list = {}
    if type(raw) ~= "string" then return list end
    for part in raw:gmatch("[^,]+") do
        local n = strtrim(part):sub(1, 24)
        if n ~= "" and #list < 5 then list[#list + 1] = n end
    end
    return list
end

-- Rebuild NAMES / MATCH in place (other code holds these tables).
local function ApplyGuildNames()
    for k in pairs(NAMES) do NAMES[k] = nil end
    for k in pairs(MATCH) do MATCH[k] = nil end
    for _, lang in ipairs(LANGS) do              -- built-ins first, so they always win
        NAMES[lang] = {}
        for _, n in ipairs(BUILTIN_GUILDS[lang]) do
            NAMES[lang][#NAMES[lang] + 1] = n
            MATCH[GKey(n)] = lang
        end
    end
    for _, lang in ipairs(LANGS) do
        for _, n in ipairs(ExtraNames(lang)) do
            local k = GKey(n)
            if k ~= "" and not MATCH[k] then     -- skip names another language already uses
                NAMES[lang][#NAMES[lang] + 1] = n
                MATCH[k] = lang
            end
        end
    end
end
ApplyGuildNames()

local function LangOfGuild(guild) return guild and MATCH[GKey(guild)] or nil end
local function InLangGuild(guild, lang) return guild ~= nil and MATCH[GKey(guild)] == lang end
local function IsKnownGuild(guild) return LangOfGuild(guild) ~= nil end

-- "<Who>/<Who Two>" for messages.
local function LabelFor(lang)
    local parts = {}
    for _, n in ipairs(NAMES[lang] or {}) do parts[#parts + 1] = "<" .. n .. ">" end
    return table.concat(parts, "/")
end

local function GuildList()
    return ("%s, %s and %s"):format(LabelFor("english"), LabelFor("spanish"), LabelFor("portuguese"))
end

local COOLDOWN   = 10   -- seconds; only filters duplicate copies of the same request
local JOIN_DELAY = 8    -- seconds after login before joining, so General/Trade keep /1 and /2

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------
local function Print(msg) print(PREFIX .. msg) end
local function Debug(msg) if cfg.debug then print("|cff888888WLS debug:|r " .. msg) end end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function InLockdown()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
        and C_ChatInfo.InChatMessagingLockdown() or false
end

local function MyGuild()
    local name = GetGuildInfo("player")
    if type(name) == "string" and not IsSecret(name) then return name:lower() end
end

local function Short(name)
    return (Ambiguate and Ambiguate(name, "none")) or name:match("^[^-]+") or name
end

local function Squash0(s) return ((type(s) == "string" and s or ""):lower():gsub("[%s%p]", "")) end

-- Is this sender me? Compare character GUIDs when the event gives one; otherwise
-- compare names without realm, ignoring spaces (Forever names are "First Last").
local function IsMe(name, guid)
    if type(guid) == "string" and guid ~= "" and not IsSecret(guid) then
        local mine = UnitGUID("player")
        if type(mine) == "string" and not IsSecret(mine) then return guid == mine end
    end
    if type(name) ~= "string" or IsSecret(name) then return false end
    -- A different realm in the name means it's someone else with my name.
    local realm = name:match("^[^-]+%-(.+)$")
    local myRealm = (UnitFullName and select(2, UnitFullName("player"))) or (GetNormalizedRealmName and GetNormalizedRealmName())
    if realm and type(myRealm) == "string" and myRealm ~= "" and Squash0(realm) ~= Squash0(myRealm) then return false end
    local base = Squash0(name:match("^([^-]+)") or name)
    for _, mine in ipairs({ UnitName("player"), (UnitFullName and UnitFullName("player")) }) do
        if type(mine) == "string" and not IsSecret(mine) and Squash0(mine) == base then return true end
    end
    return false
end

local function FullName(name)
    if not name:find("-", 1, true) and GetNormalizedRealmName then
        local realm = GetNormalizedRealmName()
        if realm and realm ~= "" then name = name .. "-" .. realm end
    end
    return name
end
local function Key(name) return FullName(name):lower() end

local function Squash(s) return ((type(s) == "string" and s or ""):lower():gsub("[%s%p]", "")) end

------------------------------------------------------------------------------
-- Locked request phrases (the buttons type these; people can type them too).
-- Only an exact match counts; capitals, spaces and punctuation are ignored.
------------------------------------------------------------------------------
local PHRASES = {
    english    = "LayerSwap English",
    spanish    = "LayerSwap Latam",
    portuguese = "LayerSwap Portuguese",
}
local PHRASE_LANG = {}
for lang, phrase in pairs(PHRASES) do PHRASE_LANG[Squash(phrase)] = lang end

local function ParseRequest(text)
    if type(text) ~= "string" or #text > 60 then return end
    return PHRASE_LANG[Squash(text)]
end

------------------------------------------------------------------------------
-- The hidden channel
------------------------------------------------------------------------------
-- The channel's number right now, or nil if we're not in it.
local function ChannelId()
    local want = Squash(cfg.channel)
    if GetChannelList then
        local list = { GetChannelList() }      -- id, name, disabled, id, name, disabled, ...
        for i = 1, #list, 3 do
            local id, name, disabled = list[i], list[i + 1], list[i + 2]
            if type(id) == "number" and type(name) == "string" and not disabled and Squash(name) == want then
                return id
            end
        end
    end
    local id = GetChannelName(cfg.channel)
    if type(id) == "number" and id > 0 then return id end
end

local function IsOurChannel(name, id)
    if type(name) == "string" and not IsSecret(name) then
        local plain = name:match("^%d+%.%s*(.+)$") or name
        if Squash(plain) == Squash(cfg.channel) then return true end
    end
    local mine = ChannelId()
    return mine ~= nil and type(id) == "number" and id == mine
end

-- The swap channel stays out of chat unless the player turns it on
-- (Settings, or /wls showchannel).
local function ApplyChannelVisibility()
    local frame = DEFAULT_CHAT_FRAME
    if not frame or not ChannelId() then return end
    local listed = false
    for _, name in pairs(frame.channelList or {}) do
        if type(name) == "string" and Squash(name) == Squash(cfg.channel) then listed = true end
    end
    local show = DB().showChannel == true
    if show and not listed and frame.AddChannel then
        pcall(frame.AddChannel, frame, cfg.channel)
    elseif not show and listed and frame.RemoveChannel then
        pcall(frame.RemoveChannel, frame, cfg.channel)
    end
end

local joinTries = 0
local function JoinHiddenChannel()
    if ChannelId() then ApplyChannelVisibility() return true end
    joinTries = joinTries + 1
    if JoinPermanentChannel then pcall(JoinPermanentChannel, cfg.channel, nil) end
    C_Timer.After(3, function()
        if ChannelId() then
            Debug(("joined the swap channel as /%d."):format(ChannelId()))
            ApplyChannelVisibility()
        elseif joinTries < 3 then
            JoinHiddenChannel()
        else
            Print(("Couldn't join the swap channel. You may already be in 10 chat channels; leave one and /reload."))
        end
    end)
end

------------------------------------------------------------------------------
-- Inviting: Forever only sends a guild invite from a real click, so requests go
-- into the invite queue: a small list, one row per person, each with its own Invite
-- button, gone after 20 seconds. Whoever clicks first claims the person (guild +
-- swap channel addon message); everyone else's row for them disappears.
------------------------------------------------------------------------------
local lastInvite = {}   -- [name-realm lower] = GetTime() I invited them
local claimed    = {}   -- [name-realm lower] = GetTime() someone in the guild invited them
local queue      = {}   -- { name =, key =, lang =, at = }, oldest first
local QUEUE_TTL  = 20   -- seconds a request stays on the list
local lastPing   = 0

local function Recently(tbl, key)
    return tbl[key] and (GetTime() - tbl[key]) < COOLDOWN
end

local function CanInviteNow()
    return IsInGuild() and CanGuildInvite() and not InLockdown()
end

local UpdateQueue   -- defined with the panel

local function PruneQueue()
    local now, kept = GetTime(), {}
    for _, e in ipairs(queue) do
        if now - e.at < QUEUE_TTL and not Recently(claimed, e.key) and not Recently(lastInvite, e.key) then
            kept[#kept + 1] = e
        end
    end
    queue = kept
end

local function Enqueue(name, lang, why)
    local key = Key(name)
    if Recently(lastInvite, key) or Recently(claimed, key) then return end
    for _, e in ipairs(queue) do
        if e.key == key then e.at = GetTime(); return end   -- asked again: keep one entry
    end
    queue[#queue + 1] = { name = name, key = key, lang = lang, at = GetTime() }
    -- one quiet ping now and then, not one per person
    if DB().noPing ~= true and GetTime() - lastPing > 8 and PlaySound and SOUNDKIT and SOUNDKIT.MAP_PING then
        lastPing = GetTime()
        pcall(PlaySound, SOUNDKIT.MAP_PING, "SFX")
    end
    Debug(("%s added to the invite queue (%s)."):format(Short(name), why))
    if UpdateQueue then UpdateQueue() end
end

local QUEUE_ROWS = 8
local queueSlots = {}   -- [row] = key of the person shown in that row

local function QueueEntry(key)
    if not key then return end
    for _, e in ipairs(queue) do if e.key == key then return e end end
end

local function RemoveFromQueue(key)
    for i, e in ipairs(queue) do
        if e.key == key then table.remove(queue, i); return end
    end
end

local function MarkClaimed(key)
    claimed[key] = GetTime()
    PruneQueue()
    if UpdateQueue then UpdateQueue() end
end

local LANG_LABEL = { english = "English", spanish = "Latam", portuguese = "Portuguese" }

-- A request seen in the swap channel.
local function HandleRequest(sender, guid, lang, how)
    local mine = MyGuild()
    local why
    if not mine then why = "you're not in a guild (or guild info hasn't loaded)"
    elseif not InLangGuild(mine, lang) then why = ("they want %s, you're in <%s>"):format(LabelFor(lang), mine)
    elseif not CanGuildInvite() then why = "your guild rank can't invite"
    elseif InLockdown() then why = "chat lockdown"
    end
    if why then
        Debug(("%s asked for %s (%s): not inviting, %s."):format(sender, LANG_LABEL[lang], how, why))
        return
    end
    Debug(("%s asked for %s (%s): added to your Invite button."):format(sender, LANG_LABEL[lang], how))
    Enqueue(sender, lang, LANG_LABEL[lang])
end

------------------------------------------------------------------------------
-- Toast: "Relog to change layers"
------------------------------------------------------------------------------
local toast
local function ShowToast(text)
    if not toast then
        toast = CreateFrame("Frame", "WhoLayerSwapToast", UIParent)
        toast:SetSize(260, 44)
        toast:SetPoint("TOP", UIParent, "TOP", 0, -170)
        toast:SetFrameStrata("HIGH")
        local bg = toast:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.05, 0.06, 0.08, 0.88)
        local edge = toast:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT"); edge:SetPoint("TOPRIGHT"); edge:SetHeight(2)
        edge:SetColorTexture(0.2, 1, 0.6, 0.9)
        toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        toast.text:SetPoint("CENTER", 0, -1)
        toast:Hide()
        toast:SetScript("OnUpdate", function(self, elapsed)
            if elapsed > 0.1 then elapsed = 0.1 end   -- a loading hitch shouldn't skip it
            self.t = self.t + elapsed
            local t = self.t
            if t < 0.25 then                          -- fade and slide in
                self:SetAlpha(t / 0.25)
                self:SetPoint("TOP", UIParent, "TOP", 0, -170 - 12 * (1 - t / 0.25))
            elseif t < 3.0 then                       -- hold until 3 s
                self:SetAlpha(1)
                self:SetPoint("TOP", UIParent, "TOP", 0, -170)
            elseif t < 3.4 then                       -- fade out
                self:SetAlpha(1 - (t - 3.0) / 0.4)
            else
                self:Hide()
            end
        end)
    end
    toast.text:SetText(text)
    toast.t = 0
    toast:SetAlpha(0)
    toast:Show()
end

------------------------------------------------------------------------------
-- Auto-accept invites from <quien>, <who> and <quem>
------------------------------------------------------------------------------
local pending          -- { lang =, at =, oldGuild = } while a swap is waiting for an invite
local acceptBlocked    -- the game refused AcceptGuild from an addon this session
local lastGuild        -- guild we were in at the last check, to spot a new join

local function OnGuildInvite(inviter, guildName)
    if not cfg.enabled or not cfg.autoAccept then return end
    if IsSecret(guildName) or type(guildName) ~= "string" then return end
    if not IsKnownGuild(guildName) then return end
    if acceptBlocked then
        Print(("Invite to <%s>: click Join on the invite window."):format(guildName))
        return
    end
    AcceptGuild()   -- if the game blocks this, Blizzard's window stays up for you to click Join
end

-- Called whenever the guild may have changed. Joining one of the three -> toast.
local function CheckGuildChange()
    local now = MyGuild()
    if IsInGuild() and not now then return end      -- still loading
    if now and now ~= lastGuild and IsKnownGuild(now) and lastGuild ~= false then
        pending = nil
        if GuildInviteFrame and GuildInviteFrame:IsShown() then
            GuildInviteFrame.accepted = true          -- or hiding it would decline
            GuildInviteFrame:Hide()
        end
        Print(("Joined <%s>."):format(GetGuildInfo("player") or now))
        ShowToast("Relog to change layers")
    end
    lastGuild = now
end

------------------------------------------------------------------------------
-- Swap buttons
------------------------------------------------------------------------------
-- Leaving a guild is a Blizzard-only action (/gquit is a secure slash command),
-- so the buttons are secure macro buttons: the click runs "/gquit" as if you typed
-- it. PlanSwap decides the macro before each click; AfterSwap sends the request.
local function PlanSwap(lang)
    if InCombatLockdown() then return nil, "Can't swap guilds in combat." end
    if InLockdown() then return nil, "Chat is locked right now (boss fight or rated PvP). Try again after." end
    if IsInGuild() and not GetGuildInfo("player") then
        if C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        return nil, "Your guild info is still loading. Try again in a few seconds."
    end
    local id = ChannelId()
    if not id then
        JoinHiddenChannel()
        return nil, "Still joining the hidden channel. Try again in a few seconds."
    end
    local current = MyGuild()
    if InLangGuild(current, lang) then return nil, ("You're already in <%s>."):format(GetGuildInfo("player") or current) end
    if current and IsGuildLeader() then
        return nil, "You're the guild leader, so you can't leave. Pass leadership first."
    end
    if current and not IsKnownGuild(current) then
        return nil, ("You're in <%s>, which isn't one of the three. Leave it yourself with /gquit if you mean to, then click again.")
            :format(GetGuildInfo("player"))
    end
    local lines = {}
    if current then lines[#lines + 1] = "/gquit" end
    lines[#lines + 1] = ("/%d %s"):format(id, PHRASES[lang])
    return { macro = table.concat(lines, "\n"), channelId = id, oldGuild = current, lang = lang }
end

local function AfterSwap(plan)
    -- The macro already typed the phrase in the channel. An invisible copy goes out
    -- too, in case the typed line didn't (the guild side ignores duplicates).
    pcall(C_ChatInfo.SendAddonMessage, COMM, "REQ:" .. plan.lang .. ":" .. (UnitGUID("player") or ""), "CHANNEL", tostring(plan.channelId))
    Print(("%sasked for %s."):format(plan.oldGuild and "Left your guild and " or "", LabelFor(plan.lang)))

    local mine = { lang = plan.lang, at = GetTime(), oldGuild = plan.oldGuild }
    pending = mine
    C_Timer.After(3, function()
        if pending == mine and plan.oldGuild and MyGuild() == plan.oldGuild then
            Print("You're still in your old guild. Type /gquit, then click again.")
        end
    end)
    C_Timer.After(45, function()
        if pending == mine and not IsInGuild() then
            Print(("No one from %s has invited you yet. Click again, or try another button."):format(LabelFor(plan.lang)))
            pending = nil
        end
    end)
end

------------------------------------------------------------------------------
-- Invite queue position (it holds secure buttons, so it only moves out of combat)
------------------------------------------------------------------------------
local panel
local ToggleSettings, RefreshSettings     -- defined with the settings window
local UpdateCharterButton, CharterMacro   -- defined with the charter button
local queuePreview = false                -- "Move queue": show it even when empty
local queuePosPending = false

local function QueuePoint()
    local p = DB().queuePoint
    if type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string"
        and type(p[3]) == "number" and type(p[4]) == "number" then
        return p
    end
end

local function ApplyQueuePosition()
    local q = panel and panel.queue
    if not q then return end
    if InCombatLockdown() then queuePosPending = true; return end
    q:ClearAllPoints()
    local p = QueuePoint()
    if p then
        q:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        q:SetPoint("TOPRIGHT", panel, "BOTTOMRIGHT", 0, -6)   -- default: under the Layer swap panel
    end
    queuePosPending = false
end

local function IsMoving() return queuePreview end

local function StopMoveMode()
    queuePreview = false
    if UpdateQueue then UpdateQueue() end
    if RefreshSettings then RefreshSettings() end
end

local function StartMoveMode()
    if InCombatLockdown() then Print("Can't move the invite queue in combat."); return end
    queuePreview = true
    if UpdateQueue then UpdateQueue() end
    if RefreshSettings then RefreshSettings() end
    Print("Drag the invite queue by its title. Click Done moving (or /wls movequeue) when finished.")
end

local function ResetQueuePosition()
    DB().queuePoint = nil
    ApplyQueuePosition()
    Print("Invite queue moved back under the Layer swap panel.")
end

------------------------------------------------------------------------------
-- The movable button panel by the minimap
------------------------------------------------------------------------------

local BUTTONS = {
    { lang = "english",    label = "English"    },
    { lang = "spanish",    label = "Latam"      },
    { lang = "portuguese", label = "Portuguese" },
}

local function PlacePanel()
    panel:ClearAllPoints()
    local p = DB().point
    if type(p) == "table" and type(p[1]) == "string" and type(p[2]) == "string"
        and type(p[3]) == "number" and type(p[4]) == "number" then
        panel:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    elseif MinimapCluster then
        panel:SetPoint("TOPRIGHT", MinimapCluster, "TOPLEFT", -6, -24)
    else
        panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -230, -40)
    end
end

local function RefreshPanel()
    if not panel or InCombatLockdown() then return end   -- secure buttons can't change in combat
    local current = MyGuild()
    for _, b in ipairs(panel.buttons) do
        local inIt = InLangGuild(current, b.lang)
        b:SetEnabled(not inIt)
        b:SetText(inIt and ("|cff33ff99" .. b.label .. "|r") or b.label)
    end
end

local function BuildPanel()
    panel = CreateFrame("Frame", "WhoLayerSwapPanel", UIParent)
    panel:SetSize(112, 104)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        if not DB().locked and not InCombatLockdown() then self:StartMoving() end
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        DB().point = { point, rel, x, y }
    end)

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", 0, -6)
    title:SetText("Layer swap")

    panel.buttons = {}
    for i, def in ipairs(BUTTONS) do
        -- Secure template last, so its OnClick (which runs the macro) is the one used.
        local b = CreateFrame("Button", "WhoLayerSwapButton" .. i, panel, "UIPanelButtonTemplate, SecureActionButtonTemplate")
        b:SetSize(100, 22)
        b:SetPoint("TOP", 0, -20 - (i - 1) * 26)
        b.lang, b.label = def.lang, def.label
        b:SetText(def.label)
        b:RegisterForClicks("AnyUp")
        b:SetAttribute("useOnKeyDown", false)
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "")
        b:SetScript("PreClick", function(self)
            self.plan = nil
            if InCombatLockdown() then Print("Can't swap guilds in combat."); return end
            local plan, why = PlanSwap(def.lang)
            self.plan = plan
            self:SetAttribute("macrotext", plan and plan.macro or "")
            if not plan then Print(why) end
        end)
        b:SetScript("PostClick", function(self)
            local plan = self.plan
            self.plan = nil
            if not InCombatLockdown() then self:SetAttribute("macrotext", "") end
            if plan then AfterSwap(plan) end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(def.label)
            GameTooltip:AddLine(("Leaves your guild and types \"%s\" in the swap channel, so %s invites you.")
                :format(PHRASES[def.lang], LabelFor(def.lang)), 1, 1, 1, true)
            GameTooltip:AddLine("Drag the panel's edge to move it.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        panel.buttons[i] = b
    end

    -- Invite queue: one row per person asking, each with its own secure Invite button
    -- (macro "/ginvite <name>", set at click time). Rows keep their slot until the
    -- person leaves the list, so nothing shifts under your mouse.
    local q = CreateFrame("Frame", "WhoLayerSwapQueue", UIParent)
    q:SetSize(224, 52)
    q:SetFrameStrata("MEDIUM")
    q:SetClampedToScreen(true)
    q:SetMovable(true)
    q:EnableMouse(true)
    q:RegisterForDrag("LeftButton")
    q:SetScript("OnDragStart", function(self) if not InCombatLockdown() then self:StartMoving() end end)
    q:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        DB().queuePoint = { point, rel, x, y }
    end)
    local qbg = q:CreateTexture(nil, "BACKGROUND")
    qbg:SetAllPoints()
    qbg:SetColorTexture(0, 0, 0, 0.6)
    q.title = q:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    q.title:SetPoint("TOPLEFT", 8, -6)
    q.title:SetText("Invite queue")
    q.count = q:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    q.count:SetPoint("TOPRIGHT", -8, -8)
    q.empty = q:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    q.empty:SetPoint("TOPLEFT", 10, -28)
    q.empty:SetText("No one waiting · drag the title to move")
    q.more = q:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    q.rows = {}
    for i = 1, QUEUE_ROWS do
        local y = -26 - (i - 1) * 22
        local r = {}
        r.name = q:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("TOPLEFT", 10, y - 3)
        r.name:SetWidth(112)
        r.name:SetJustifyH("LEFT")
        if r.name.SetWordWrap then r.name:SetWordWrap(false) end
        r.time = q:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.time:SetPoint("TOPRIGHT", -74, y - 5)
        local btn = CreateFrame("Button", "WhoLayerSwapQueueInvite" .. i, q, "UIPanelButtonTemplate, SecureActionButtonTemplate")
        btn:SetSize(62, 20)
        btn:SetPoint("TOPRIGHT", -6, y)
        btn:SetText("Invite")
        btn:RegisterForClicks("AnyUp")
        btn:SetAttribute("useOnKeyDown", false)
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", "")
        btn.slot = i
        btn:SetScript("PreClick", function(self, mouse)
            self.inviting = nil
            if InCombatLockdown() then Print("Can't invite in combat; they'll still be on the list after if there's time."); return end
            PruneQueue()
            local e = QueueEntry(queueSlots[self.slot])
            if not e then self:SetAttribute("macrotext", ""); return end
            if mouse == "RightButton" then                 -- right-click: skip this person
                RemoveFromQueue(e.key); self:SetAttribute("macrotext", ""); return
            end
            if not CanInviteNow() then
                Print("You can't invite right now (rank, guild or chat lockdown)."); self:SetAttribute("macrotext", ""); return
            end
            self.inviting = e
            self:SetAttribute("macrotext", "/ginvite " .. e.name)
        end)
        btn:SetScript("PostClick", function(self)
            local e = self.inviting
            self.inviting = nil
            if not InCombatLockdown() then self:SetAttribute("macrotext", "") end
            if e then
                lastInvite[e.key] = GetTime()
                RemoveFromQueue(e.key)
                if C_ChatInfo and C_ChatInfo.SendAddonMessage then
                    pcall(C_ChatInfo.SendAddonMessage, COMM, "CLAIM:" .. e.key, "GUILD")
                    -- and on the swap channel, so members of the backup guild stand down too
                    local cid = ChannelId()
                    if cid then pcall(C_ChatInfo.SendAddonMessage, COMM, "CLAIM:" .. e.key, "CHANNEL", tostring(cid)) end
                end
                if cfg.verbose then Print(("Invited %s."):format(Short(e.name))) end
            end
            UpdateQueue()
        end)
        btn:SetScript("OnEnter", function(self)
            local e = QueueEntry(queueSlots[self.slot])
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(e and Short(e.name) or "Invite")
            GameTooltip:AddLine("Left-click: invite. Right-click: skip.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:Hide()
        r.btn = btn
        q.rows[i] = r
    end
    q:Hide()
    panel.queue = q
    ApplyQueuePosition()

    -- Guild Charter button: big and glowing, just below the middle of the screen, shown
    -- while a charter is in your bags. Secure macro "/use item:<id>", so it opens the
    -- charter (or offers it to your target for a signature).
    local ch = CreateFrame("Button", "WhoLayerSwapCharterButton", UIParent, "UIPanelButtonTemplate, SecureActionButtonTemplate")
    ch:SetSize(280, 52)
    ch:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    ch:SetFrameStrata("DIALOG")
    ch:RegisterForClicks("AnyUp", "AnyDown")   -- down too, so the F1 key binding reaches it
    ch:SetAttribute("useOnKeyDown", false)     -- acts on release, for both mouse and F1
    ch:SetAttribute("type", "macro")
    ch:SetAttribute("macrotext", "")
    if ch.SetNormalFontObject then ch:SetNormalFontObject("GameFontNormalHuge") end
    if ch.SetHighlightFontObject then ch:SetHighlightFontObject("GameFontHighlightHuge") end
    ch:SetText("      Guild Charter")
    ch.icon = ch:CreateTexture(nil, "OVERLAY")
    ch.icon:SetSize(38, 38)
    ch.icon:SetPoint("LEFT", 10, 0)
    -- same pulsing Blizzard button glow as the invite button
    local cglow = ch:CreateTexture(nil, "BACKGROUND")
    cglow:SetTexture("Interface\\Buttons\\UI-Panel-Button-Glow")
    cglow:SetTexCoord(0, 0.75, 0, 0.609375)
    cglow:SetBlendMode("ADD")
    cglow:SetSize(340, 92)
    cglow:SetPoint("CENTER")
    local cpulse = cglow:CreateAnimationGroup()
    if cpulse then
        cpulse:SetLooping("BOUNCE")
        local fade = cpulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.35)
        fade:SetToAlpha(1)
        fade:SetDuration(0.7)
        fade:SetSmoothing("IN_OUT")
        ch:HookScript("OnShow", function() cpulse:Play() end)
        ch:HookScript("OnHide", function() cpulse:Stop() end)
    end
    local chint = ch:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    chint:SetPoint("TOP", ch, "BOTTOM", 0, -6)
    ch.hint = chint
    -- Each press: open the charter, or (window open + a player targeted) whisper them
    -- and press the window's Request Signature button, like the macro:
    --   /run SendChatMessage("Forming a guild...", "WHISPER", nil, GetUnitName("target"))
    --   /click PetitionFrameRequestButton
    ch:SetScript("PreClick", function(self, mouse, down)
        if down or InCombatLockdown() then return end   -- act on release; no attribute changes in combat
        self:SetAttribute("macrotext", CharterMacro(self))
    end)
    ch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Guild Charter")
        GameTooltip:AddLine("Press once to open your charter.", 1, 1, 1, true)
        GameTooltip:AddLine("Then target a player and press again: they get a whisper and a signature request.", 1, 1, 1, true)
        GameTooltip:AddLine("F1 does the same while you carry a charter (per character; Settings or /wls charterkey).", 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine("Turn the button off in Settings or with /wls charter.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    ch:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ch:Hide()
    panel.charter = ch

    -- Gear button: opens Settings (right-clicking the panel does too)
    local gear = CreateFrame("Button", "WhoLayerSwapSettingsButton", panel)
    gear:SetSize(14, 14)
    gear:SetPoint("TOPRIGHT", -4, -4)
    local gtex = gear:CreateTexture(nil, "ARTWORK")
    gtex:SetAllPoints()
    if gtex.SetAtlas then gtex:SetAtlas("questlog-icon-setting") end
    local ghi = gear:CreateTexture(nil, "HIGHLIGHT")
    ghi:SetAllPoints()
    if ghi.SetAtlas then ghi:SetAtlas("questlog-icon-setting") end
    ghi:SetBlendMode("ADD")
    gear:SetScript("OnClick", function() ToggleSettings() end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Settings")
        GameTooltip:AddLine("Guild names, invite button position and more.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.gear = gear
    panel:SetScript("OnMouseUp", function(self, mouse) if mouse == "RightButton" then ToggleSettings() end end)

    PlacePanel()
    RefreshPanel()
    if DB().hidden then panel:Hide() end
end

-- Redraw the invite queue. Rows hold secure buttons, so the list can only change
-- out of combat; in combat it stays as it was and catches up afterwards.
local queueDirty = false
UpdateQueue = function()
    local q = panel and panel.queue
    if not q then return end
    if InCombatLockdown() then
        queueDirty = true
        if q:IsShown() then q.count:SetText("in combat") end
        return
    end
    queueDirty = false
    PruneQueue()
    -- free the slots of people who left the list, then seat newcomers (oldest first)
    local seated = {}
    for i = 1, QUEUE_ROWS do
        if queueSlots[i] and not QueueEntry(queueSlots[i]) then queueSlots[i] = nil end
        if queueSlots[i] then seated[queueSlots[i]] = true end
    end
    for _, e in ipairs(queue) do
        if not seated[e.key] then
            for i = 1, QUEUE_ROWS do
                if not queueSlots[i] then queueSlots[i] = e.key; seated[e.key] = true; break end
            end
        end
    end
    local now, used, shown = GetTime(), 0, 0
    for i = 1, QUEUE_ROWS do
        local r, e = q.rows[i], QueueEntry(queueSlots[i])
        if e then
            r.name:SetText(Short(e.name))
            r.time:SetText(math.max(0, math.ceil(QUEUE_TTL - (now - e.at))) .. "s")
            r.btn:Show()
            used, shown = i, shown + 1
        else
            r.name:SetText("")
            r.time:SetText("")
            r.btn:Hide()
        end
    end
    local waiting = #queue - shown
    q.count:SetText(#queue > 0 and tostring(#queue) or "")
    q.empty:SetShown(#queue == 0)
    q.more:ClearAllPoints()
    q.more:SetPoint("TOPLEFT", 10, -28 - math.max(used, 1) * 22 + 4)
    q.more:SetText(waiting > 0 and ("+" .. waiting .. " more waiting") or "")
    q:SetHeight(32 + math.max(used, 1) * 22 + (waiting > 0 and 12 or 0))
    q:SetShown(#queue > 0 or queuePreview)
end

-- Count the seconds down while anyone is waiting.
local queueClock = CreateFrame("Frame")
local clockElapsed = 0
queueClock:SetScript("OnUpdate", function(self, elapsed)
    clockElapsed = clockElapsed + elapsed
    if clockElapsed < 0.5 then return end
    clockElapsed = 0
    if #queue > 0 or (panel and panel.queue and panel.queue:IsShown()) or queueDirty then UpdateQueue() end
end)

------------------------------------------------------------------------------
-- Guild Charter button
------------------------------------------------------------------------------
local CHARTER_ITEM_ID = 5863     -- Guild Charter in Classic; also matched by name below
local CHARTER_KEY = "F1"
local charterPending = false

-- F1 for the charter is on unless this character turned it off. It's an override
-- binding: it only exists while the charter is in your bags, and your saved key
-- bindings are never changed (F1 goes back to targeting yourself afterwards).
local function CharterKeyOn()
    local g, t = UnitGUID("player"), DB().charterKeyOff
    return not (type(t) == "table" and type(g) == "string" and t[g])
end

local function SetCharterKeyOn(on)
    local g = UnitGUID("player")
    if type(g) ~= "string" then return end
    if type(DB().charterKeyOff) ~= "table" then DB().charterKeyOff = {} end
    DB().charterKeyOff[g] = (not on) and true or nil
end

-- Returns the charter's item ID and icon if one is in your bags.
local function FindCharter()
    local names = { ["guild charter"] = true }
    if C_Item and C_Item.GetItemNameByID then
        local ok, n = pcall(C_Item.GetItemNameByID, CHARTER_ITEM_ID)   -- the name in the client's language
        if ok and type(n) == "string" and not IsSecret(n) then names[n:lower()] = true end
    end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        local okN, slots = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (okN and type(slots) == "number" and slots or 0) do
            local okI, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if okI and type(info) == "table" and type(info.itemID) == "number" then
                local name = info.itemName
                if info.itemID == CHARTER_ITEM_ID
                    or (type(name) == "string" and not IsSecret(name) and names[name:lower()]) then
                    return info.itemID, info.iconFileID
                end
            end
        end
    end
end

-- Whisper sent with each signature request (change with /wls charterwhisper <text>).
local DEFAULT_CHARTER_WHISPER = "Forming a guild, mind signing and you can quit later?"
local lastCharterWhisper = {}    -- [name] = GetTime(), so repeat presses don't spam

local function CharterWhisperText()
    local t = DB().charterWhisper
    return (type(t) == "string" and t ~= "") and t or DEFAULT_CHARTER_WHISPER
end

local function AlreadySigned(name)
    if not (GetNumPetitionNames and GetPetitionNameInfo) then return false end
    local short = Short(name):lower()
    for i = 1, (GetNumPetitionNames() or 0) do
        local signed = GetPetitionNameInfo(i)
        if type(signed) == "string" and not IsSecret(signed) and Short(signed):lower() == short then return true end
    end
    return false
end

-- Decide what this press does; returns the macro for the secure button to run.
CharterMacro = function(b)
    local open = "/use item:" .. tostring(b.itemID or CHARTER_ITEM_ID)
    local windowOpen = PetitionFrame and PetitionFrame:IsShown()
    local hasTarget = UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
    local name = hasTarget and GetUnitName("target", true)
    if not windowOpen then
        if hasTarget then Print("Charter opened. Press again to ask your target to sign.") end
        return open
    end
    if type(name) ~= "string" or IsSecret(name) then
        Print("Target a player, then press again to ask them to sign.")
        return ""
    end
    if AlreadySigned(name) then
        Print(("%s has already signed."):format(Short(name)))
        return ""
    end
    local key = name:lower()
    if not (lastCharterWhisper[key] and GetTime() - lastCharterWhisper[key] < 30) and not InLockdown() then
        lastCharterWhisper[key] = GetTime()
        pcall(C_ChatInfo.SendChatMessage, CharterWhisperText(), "WHISPER", nil, name)
    end
    return "/click PetitionFrameRequestButton"
end

UpdateCharterButton = function()
    local b = panel and panel.charter
    if not b then return end
    if InCombatLockdown() then charterPending = true; return end   -- secure button: change after combat
    charterPending = false
    local id, icon
    if DB().hideCharter ~= true then id, icon = FindCharter() end
    if ClearOverrideBindings then ClearOverrideBindings(b) end
    if id then
        b.itemID = id
        b:SetAttribute("macrotext", "/use item:" .. id)
        b.icon:SetTexture(icon or 134400)
        local keyOn = CharterKeyOn() and SetOverrideBindingClick ~= nil
        if keyOn then SetOverrideBindingClick(b, true, CHARTER_KEY, b:GetName(), "LeftButton") end
        b.hint:SetText((keyOn and ("Press " .. CHARTER_KEY .. " or click") or "Click")
            .. " to open · then target a player and press again to ask them to sign")
        b:Show()
    else
        b:SetAttribute("macrotext", "")
        b:Hide()
    end
end

------------------------------------------------------------------------------
-- Settings window (/wls settings, the panel's gear, or Options > AddOns)
------------------------------------------------------------------------------
local settings

local function ExtraText(lang) return table.concat(ExtraNames(lang), ", ") end

local function IsBuiltin(lang, name)
    for _, b in ipairs(BUILTIN_GUILDS[lang]) do
        if GKey(b) == GKey(name) then return true end
    end
    return false
end

-- Save the extra names for a language from a comma-separated string.
local function SetExtraNames(lang, text)
    text = type(text) == "string" and text or ""
    if type(DB().guilds) ~= "table" then DB().guilds = {} end
    local keep, skipped = {}, {}
    for part in text:gmatch("[^,]+") do
        local n = strtrim(part):sub(1, 24)
        local owner = n ~= "" and MATCH[GKey(n)]
        if n ~= "" and #keep < 5 then
            if owner and owner ~= lang then
                skipped[#skipped + 1] = n                -- belongs to another language
            elseif not IsBuiltin(lang, n) then
                keep[#keep + 1] = n                      -- built-in names don't need saving
            end
        end
    end
    local before = ExtraText(lang)
    DB().guilds[lang] = (#keep > 0) and table.concat(keep, ", ") or nil
    ApplyGuildNames()
    RefreshPanel()
    for _, n in ipairs(skipped) do
        Print(("<%s> is already a %s guild name; not added to %s."):format(n, LANG_LABEL[LangOfGuild(n)], LANG_LABEL[lang]))
    end
    if ExtraText(lang) ~= before then
        Print(("%s guilds: %s"):format(LANG_LABEL[lang], LabelFor(lang)))
    end
end

local function BuildSettings()
    local s = CreateFrame("Frame", "WhoLayerSwapSettings", UIParent, "DefaultPanelTemplate")
    s:SetSize(340, 508)
    s:SetPoint("CENTER")
    s:SetFrameStrata("DIALOG")
    s:SetClampedToScreen(true)
    s:SetMovable(true)
    s:EnableMouse(true)
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnDragStart", s.StartMoving)
    s:SetScript("OnDragStop", s.StopMovingOrSizing)
    if s.SetTitle then s:SetTitle("WhoLayerSwap Settings") end
    CreateFrame("Button", nil, s, "UIPanelCloseButtonDefaultAnchors")
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "WhoLayerSwapSettings") end
    s:Hide()

    local function Header(text, y)
        local h = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 18, y)
        h:SetText(text)
    end

    -- Guild names
    Header("Guild names", -34)
    s.edits = {}
    for i, lang in ipairs(LANGS) do
        local y = -58 - (i - 1) * 38
        local label = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPLEFT", 24, y - 1)
        label:SetText(LANG_LABEL[lang])
        local builtIn = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        builtIn:SetPoint("TOPLEFT", 24, y - 16)
        builtIn:SetText(table.concat(BUILTIN_GUILDS[lang], ", "))
        local e = CreateFrame("EditBox", "WhoLayerSwapGuildEdit" .. i, s, "InputBoxTemplate")
        e:SetSize(180, 20)
        e:SetPoint("TOPLEFT", 128, y)
        e:SetAutoFocus(false)
        e:SetMaxLetters(80)
        e.lang = lang
        local hint = e:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        hint:SetPoint("LEFT", 2, 0)
        hint:SetText("extra names (optional)")
        e.hint = hint
        local function UpdateHint(self) self.hint:SetShown((self:GetText() or "") == "") end
        e:SetScript("OnTextChanged", UpdateHint)
        e:SetScript("OnEnterPressed", function(self)
            SetExtraNames(lang, self:GetText())
            self:SetText(ExtraText(lang))
            self:ClearFocus()
        end)
        e:SetScript("OnEscapePressed", function(self)
            self:SetText(ExtraText(lang))
            self:ClearFocus()
        end)
        e:SetScript("OnEditFocusLost", function(self)
            if self:GetText() ~= ExtraText(lang) then
                SetExtraNames(lang, self:GetText())
                self:SetText(ExtraText(lang))
            end
        end)
        s.edits[lang] = e
    end
    local note = s:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 24, -170)
    note:SetWidth(296)
    note:SetJustifyH("LEFT")
    note:SetText("The grey names always work. To add more, type them in the box (separate several with commas) and press Enter. Capitals and spaces don't matter.")
    local resetNames = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    resetNames:SetSize(140, 22)
    resetNames:SetPoint("TOPLEFT", 22, -202)
    resetNames:SetText("Clear extra names")
    resetNames:SetScript("OnClick", function()
        for _, lang in ipairs(LANGS) do SetExtraNames(lang, "") end
        RefreshSettings()
    end)

    -- Invite button
    Header("Invite queue", -238)
    local move = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    move:SetSize(150, 22)
    move:SetPoint("TOPLEFT", 22, -260)
    move:SetScript("OnClick", function() if IsMoving() then StopMoveMode() else StartMoveMode() end end)
    s.move = move
    local resetPos = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    resetPos:SetSize(130, 22)
    resetPos:SetPoint("LEFT", move, "RIGHT", 8, 0)
    resetPos:SetText("Reset position")
    resetPos:SetScript("OnClick", ResetQueuePosition)

    -- General
    Header("General", -296)
    s.checks = {}
    local function Check(i, label, get, set)
        local c = CreateFrame("CheckButton", nil, s, "UICheckButtonTemplate")
        c:SetPoint("TOPLEFT", 18, -314 - (i - 1) * 26)
        if not c.Text then
            c.Text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            c.Text:SetPoint("LEFT", c, "RIGHT", 2, 1)
        end
        c.Text:SetText(label)
        c.get, c.set = get, set
        c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        s.checks[#s.checks + 1] = c
    end
    Check(1, "Accept invites from these three guilds automatically",
        function() return cfg.autoAccept end,
        function(v) cfg.autoAccept = v; DB().autoAccept = v end)
    Check(2, "Show the swap channel in chat",
        function() return DB().showChannel == true end,
        function(v) DB().showChannel = v or nil; ApplyChannelVisibility() end)
    Check(3, "Lock the Layer swap panel",
        function() return DB().locked == true end,
        function(v) DB().locked = v or nil end)
    Check(4, "Show a Guild Charter button when you carry one",
        function() return DB().hideCharter ~= true end,
        function(v) DB().hideCharter = (not v) and true or nil; UpdateCharterButton() end)
    Check(5, "F1 opens the Guild Charter (this character)",
        function() return CharterKeyOn() end,
        function(v) SetCharterKeyOn(v); UpdateCharterButton() end)
    Check(6, "Debug messages (why requests were or weren't invited)",
        function() return cfg.debug end,
        function(v) cfg.debug = v end)
    Check(7, "Ping when someone joins the invite queue",
        function() return DB().noPing ~= true end,
        function(v) DB().noPing = (not v) and true or nil end)

    s:SetScript("OnShow", function() RefreshSettings() end)
    s:SetScript("OnHide", function() StopMoveMode() end)
    settings = s
end

RefreshSettings = function()
    if not settings then return end
    for lang, e in pairs(settings.edits) do
        if not (e.HasFocus and e:HasFocus()) then e:SetText(ExtraText(lang)); e.hint:SetShown(ExtraText(lang) == "") end
    end
    settings.move:SetText(IsMoving() and "Done moving" or "Move invite queue")
    for _, c in ipairs(settings.checks) do c:SetChecked(c.get() and true or false) end
end

local function OpenSettings()
    if not settings then BuildSettings() end
    settings:Show()
    RefreshSettings()
end

ToggleSettings = function()
    if settings and settings:IsShown() then settings:Hide() else OpenSettings() end
end

-- An entry under Options > AddOns with a button that opens the window.
local function RegisterOptionsEntry()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local canvas = CreateFrame("Frame")
    local t = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText("WhoLayerSwap")
    local b = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    b:SetSize(200, 24)
    b:SetPoint("TOPLEFT", 16, -48)
    b:SetText("Open WhoLayerSwap settings")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel and not InCombatLockdown() then
            pcall(HideUIPanel, SettingsPanel)
        end
        OpenSettings()
    end)
    canvas:Hide()
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, canvas, "WhoLayerSwap")
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end

------------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------------
local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE", "PLAYER_REGEN_ENABLED", "BAG_UPDATE_DELAYED",
                     "GUILD_INVITE_REQUEST", "ADDON_ACTION_BLOCKED",
                     "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER", "CHAT_MSG_ADDON" }) do
    pcall(f.RegisterEvent, f, e)
end

local joinedOnce = false

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(COMM)
        end
        if type(DB().autoAccept) == "boolean" then cfg.autoAccept = DB().autoAccept end
        ApplyGuildNames()           -- saved names are loaded by now
        BuildPanel()
        pcall(RegisterOptionsEntry)
        lastGuild = false           -- first real reading sets it without a toast
        C_Timer.After(5, function()
            if lastGuild == false then lastGuild = MyGuild() end
        end)
        -- expire old requests from the button now and then
        local function tick() PruneQueue(); if UpdateQueue then UpdateQueue() end; C_Timer.After(10, tick) end
        C_Timer.After(10, tick)
        return
    end

    if event == "ADDON_ACTION_BLOCKED" then
        local who, func = ...
        if who == ADDON and type(func) == "string" and func:find("AcceptGuild") then
            acceptBlocked = true
            Print("The game doesn't let addons accept guild invites; click Join on the invite window.")
        end
        return
    end


    if event == "PLAYER_ENTERING_WORLD" then
        if not joinedOnce then
            joinedOnce = true
            C_Timer.After(JOIN_DELAY, JoinHiddenChannel)
        end
        RefreshPanel()
        UpdateCharterButton()
        return
    end

    if event == "BAG_UPDATE_DELAYED" then
        UpdateCharterButton()
        return
    end

    if event == "PLAYER_GUILD_UPDATE" or event == "PLAYER_REGEN_ENABLED" then
        if queuePosPending then ApplyQueuePosition() end
        if charterPending then UpdateCharterButton() end
        RefreshPanel()
        if lastGuild ~= false then CheckGuildChange() end
        if UpdateQueue then UpdateQueue() end
        return
    end

    if event == "GUILD_INVITE_REQUEST" then
        OnGuildInvite(...)
        return
    end

    if event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender, _, _, localId, channelName = ...
        if prefix ~= COMM or IsSecret(text) or type(text) ~= "string" then return end
        if type(sender) ~= "string" or IsSecret(sender) then return end
        if channel == "GUILD" then
            if IsMe(sender) then return end
            local who = text:match("^CLAIM:(.+)$")
            if who then MarkClaimed(who) end
            return
        end
        if channel == "CHANNEL" and IsOurChannel(channelName, localId) then
            local claimedKey = text:match("^CLAIM:(.+)$")
            if claimedKey then
                if not IsMe(sender) then MarkClaimed(claimedKey) end
                return
            end
            if not cfg.enabled or InLockdown() then return end
            -- "REQ:<lang>" or "REQ:<lang>:<Player-GUID>"; anything else is ignored
            local lang, guid = text:match("^REQ:(%a+):(Player%-[%w%-]+)$")
            if not lang then lang = text:match("^REQ:(%a+)$") end
            if not lang or not BUILTIN_GUILDS[lang] then return end
            if IsMe(sender, guid) then Debug("That was your own request; it goes to the other guilds.") return end
            HandleRequest(sender, guid, lang, "button")
        end
        return
    end

    if not cfg.enabled then return end
    if InLockdown() then return end

    local text, sender, _, channelName, _, _, _, channelIndex, channelBaseName, _, _, guid = ...
    if IsSecret(text) or IsSecret(sender) then return end
    if type(text) ~= "string" or type(sender) ~= "string" then return end

    if event == "CHAT_MSG_WHISPER" then
        if IsMe(sender, guid) then return end
        if strtrim(text):lower() == cfg.whisperTrigger and CanInviteNow() then
            Enqueue(sender, nil, "whisper")
        end
        return
    end

    -- Typed requests in the hidden channel ("/5 inv english")
    if not (IsOurChannel(channelBaseName, channelIndex) or IsOurChannel(channelName, channelIndex)) then return end
    local lang = ParseRequest(text)
    if not lang then return end
    if IsMe(sender, guid) then Debug("That was your own request; it goes to the other guilds.") return end
    HandleRequest(sender, guid, lang, "phrase")
end)

------------------------------------------------------------------------------
-- /wls
------------------------------------------------------------------------------
SLASH_WHOLAYERSWAP1 = "/wls"
SlashCmdList["WHOLAYERSWAP"] = function(input)
    local cmd, rest = strtrim(input or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "on" then
        cfg.enabled = true;  Print("On.")
    elseif cmd == "off" then
        cfg.enabled = false; Print("Off.")
    elseif cmd == "quiet" then
        cfg.verbose = not cfg.verbose
        Print("Invite messages " .. (cfg.verbose and "shown." or "hidden."))
    elseif cmd == "accept" then
        cfg.autoAccept = not cfg.autoAccept
        DB().autoAccept = cfg.autoAccept
        Print("Auto-accept from " .. GuildList() .. " " .. (cfg.autoAccept and "on." or "off."))
    elseif cmd == "show" or cmd == "hide" or cmd == "reset" then
        if InCombatLockdown() then Print("Can't do that in combat."); return end
        if cmd == "reset" then DB().point = nil; if panel then PlacePanel() end end
        DB().hidden = (cmd == "hide")
        if panel then panel:SetShown(cmd ~= "hide") end
    elseif cmd == "lock" then
        DB().locked = not DB().locked
        Print("Panel " .. (DB().locked and "locked." or "unlocked."))
    elseif cmd == "toast" then
        ShowToast("Relog to change layers")
    elseif cmd == "showchannel" then
        DB().showChannel = not (DB().showChannel == true) or nil
        ApplyChannelVisibility()
        Print("Swap channel " .. (DB().showChannel and "shown in" or "hidden from") .. " your main chat window.")
    elseif cmd == "settings" or cmd == "config" or cmd == "options" then
        OpenSettings()
    elseif cmd == "guild" then
        local which, name = rest:match("^(%S+)%s*(.-)$")
        local lang = which and ({ english = "english", eng = "english", latam = "spanish", spanish = "spanish",
                                  portuguese = "portuguese", port = "portuguese" })[which:lower()]
        if not lang then
            Print("Usage: /wls guild english|latam|portuguese <extra name, ...>  (empty = no extras)")
        else
            SetExtraNames(lang, name)
            Print(("%s guilds: %s"):format(LANG_LABEL[lang], LabelFor(lang)))
            RefreshSettings()
        end
    elseif cmd == "charter" then
        DB().hideCharter = not (DB().hideCharter == true) or nil
        UpdateCharterButton()
        RefreshSettings()
        Print("Guild Charter button " .. (DB().hideCharter and "off." or "on (shows while you carry a charter)."))
    elseif cmd == "charterwhisper" then
        DB().charterWhisper = (rest ~= "") and rest or nil
        Print("Signature whisper: \"" .. CharterWhisperText() .. "\"")
    elseif cmd == "charterkey" then
        SetCharterKeyOn(not CharterKeyOn())
        UpdateCharterButton()
        RefreshSettings()
        Print("F1 for the Guild Charter " .. (CharterKeyOn() and "on" or "off") .. " for this character.")
    elseif cmd == "movequeue" or cmd == "moveinvite" then
        if IsMoving() then StopMoveMode() else StartMoveMode() end
    elseif cmd == "phrases" then
        for _, b in ipairs({ "english", "spanish", "portuguese" }) do
            Print(("%s -> %s"):format(PHRASES[b], LabelFor(b)))
        end
    elseif cmd == "join" then
        joinTries = 0; JoinHiddenChannel()
    elseif cmd == "debug" then
        cfg.debug = not cfg.debug
        Print("Debug " .. (cfg.debug and "on: requests you see will say why they were or weren't invited." or "off."))
        if cfg.debug then
            Debug(("you are %s / %s / %s; swap channel: %s; guild: %s; can invite: %s"):format(
                tostring(UnitName("player")), tostring(UnitFullName and UnitFullName("player")), tostring(UnitGUID("player")),
                tostring(ChannelId()), tostring(MyGuild()), tostring(IsInGuild() and CanGuildInvite())))
        end
    elseif cmd == "test" and rest ~= "" then
        local lang = ParseRequest(rest)
        Print(("\"%s\" -> %s"):format(rest,
            lang and (lang .. " (" .. LabelFor(lang) .. ")") or "not one of the phrases (/wls phrases)"))
    else
        local g = MyGuild()
        local myLang
        if LangOfGuild(g) then myLang = LANG_LABEL[LangOfGuild(g)] end
        local id = ChannelId()
        Print(("%s · swap channel: %s · your guild: %s · you invite people asking for: %s · your rank can invite: %s"):format(
            cfg.enabled and "On" or "Off", id and ("joined (/" .. id .. ")") or "NOT joined (/wls join)",
            g and ("<" .. g .. ">") or "none", myLang or "nobody",
            (IsInGuild() and CanGuildInvite()) and "yes" or "no"))
        Print("/wls settings | guild <lang> <name> | movequeue | charter | charterkey | charterwhisper <text> | on | off | quiet | accept | show | hide | lock | reset | join | showchannel | phrases | toast | debug | test <message>")
    end
end
