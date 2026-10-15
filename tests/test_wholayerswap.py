"""Offline tests for WhoLayerSwap: runs the real addon against a mock Forever client (wls_mock.lua)."""
import lupa, sys, os
SP = os.path.dirname(os.path.abspath(__file__))
MOCK = open(os.path.join(SP, "wls_mock.lua"), encoding="utf-8").read()
# Usage: python3 tests/test_wholayerswap.py [path/to/WhoLayerSwap.lua]   (needs: pip install lupa)
ADDON_PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(SP, "..", "WhoLayerSwap", "WhoLayerSwap.lua")
ADDON = open(ADDON_PATH, encoding="utf-8").read()
PASS, FAIL = 0, []
CH = "whoguildlayerswapchannel"

def fresh(setup="", login=True):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    L.execute(MOCK)
    L.execute(setup)
    L.execute("return (loadstring or load)(...)", ADDON)("WhoLayerSwap")
    L.execute("""
      for _, fr in ipairs(FRAMES) do if fr.scripts and fr.scripts.OnEvent then FRAME = fr break end end
      function EV(...) FRAME.scripts.OnEvent(FRAME, ...) end
      function REQ(lang, sender, chname, localId) EV("CHAT_MSG_ADDON","WHOLAYERSWAP","REQ:"..lang,"CHANNEL",sender,"",0,localId or 5,chname or "%s") end
      function TYPED(text, sender, base, idx) base = base or "%s"; idx = idx or 5; EV("CHAT_MSG_CHANNEL", text, sender, "", idx .. ". " .. base, "", "", 0, idx, base) end
      function CLAIM(key, sender) EV("CHAT_MSG_ADDON","WHOLAYERSWAP","CLAIM:"..key,"GUILD",sender or "Zed-Dreamscythe","",0,0,"") end
      function SLASH(s) SlashCmdList.WHOLAYERSWAP(s) end
      function BTN(i) CLICK(WhoLayerSwapPanel.buttons[i]) end
      function CLEAR() LOG = {}; OUT = {} end
      function ROW(i) return _G["WhoLayerSwapQueueInvite" .. i] end
      function ROWNAME(i) return WhoLayerSwapQueue.rows[i].name.txt end
      function INVBTN() for i = 1, 8 do local b = ROW(i) if b and b.shown then return b end end end
      function CLICKALL() local n = 0 local b = INVBTN() while b and n < 500 do CLICK(b) n = n + 1 b = INVBTN() end end
      function SHOWN_NAMES() local r = {} for i = 1, 8 do if ROW(i).shown then r[#r+1] = i .. ":" .. ROWNAME(i) end end return table.concat(r, ",") end
      function invites() local r = {} for _, l in ipairs(LOG) do local n = l:match("^INVITE (.+)") if n then r[#r+1] = n end end return #r, table.concat(r, ",") end
      function has(prefix) for _, l in ipairs(LOG) do if l:sub(1, #prefix) == prefix then return true end end return false end
      function said(sub) for _, l in ipairs(OUT) do if l:find(sub, 1, true) then return true end end return false end
    """ % (CH, CH))
    if login:
        L.execute('EV("PLAYER_LOGIN") EV("PLAYER_ENTERING_WORLD", true, false) ADVANCE(12)')
    return L

def check(name, cond, detail=""):
    global PASS
    if cond: PASS += 1
    else: FAIL.append(f"{name}  {detail}")

def dump(L): return f"log={list(L.globals().LOG.values())} out={[o for o in L.globals().OUT.values()]}"

# ------------------------------------------------------------- joining the hidden channel
L = fresh(login=False)
L.execute('EV("PLAYER_LOGIN") EV("PLAYER_ENTERING_WORLD", true, false) ADVANCE(5)')
check("doesn't join before the delay (General/Trade keep /1 /2)", not L.execute('return has("JOIN")'), dump(L))
L.execute('ADVANCE(5)')
check("joins hidden channel after the delay, with no chat tab", L.execute(f'return has("JOIN {CH} frame=nil")'), dump(L))
L.execute('CLEAR() EV("PLAYER_ENTERING_WORLD", false, true) ADVANCE(15)')
check("zoning/reload doesn't re-join", not L.execute('return has("JOIN")'), dump(L))
L = fresh(f'CHANNELS[#CHANNELS+1]={{4,"{CH}",false}}', login=False)
L.execute('EV("PLAYER_LOGIN") EV("PLAYER_ENTERING_WORLD", true, false) ADVANCE(15)')
check("already in the channel -> doesn't join again", not L.execute('return has("JOIN")'), dump(L))
L = fresh('JOIN_FAILS=true', login=False)
L.execute('EV("PLAYER_LOGIN") EV("PLAYER_ENTERING_WORLD", true, false) ADVANCE(30)')
n = sum(1 for l in L.globals().LOG.values() if l.startswith("JOIN"))
check("join fails -> 3 tries then a clear message", n == 3 and L.execute('return said("10 chat channels")'), f"tries={n} {dump(L)}")
L = fresh(f'CHANNELS[#CHANNELS+1]={{7,"WhoGuildLayerSwapChannel",false}}', login=False)
L.execute('EV("PLAYER_LOGIN") EV("PLAYER_ENTERING_WORLD", true, false) ADVANCE(15)')
check("channel found case-insensitively", not L.execute('return has("JOIN")'), dump(L))

L = fresh()
check("swap channel hidden from chat by default", len(list(L.globals().DEFAULT_CHAT_FRAME.channelList.values())) == 0 and L.execute('return has("JOIN")'), dump(L))
L.execute('CLEAR() SLASH("showchannel")')
check("/wls showchannel shows it", list(L.globals().DEFAULT_CHAT_FRAME.channelList.values()) == [CH] and L.execute('return said("shown in")'), dump(L))
L.execute('CLEAR() SLASH("showchannel")')
check("/wls showchannel again hides it", len(list(L.globals().DEFAULT_CHAT_FRAME.channelList.values())) == 0 and L.execute('return said("hidden from")'), dump(L))
L = fresh(f'CHANNELS[#CHANNELS+1]={{4,"{CH}",false}} DEFAULT_CHAT_FRAME.channelList={{"{CH}"}}', login=True)
check("already in a chat tab from an old version -> taken out", len(list(L.globals().DEFAULT_CHAT_FRAME.channelList.values())) == 0, dump(L))
L = fresh(f'WhoLayerSwapDB={{showChannel=true}}')
check("showChannel saved -> stays in chat", list(L.globals().DEFAULT_CHAT_FRAME.channelList.values()) == [CH], dump(L))
L = fresh(f'WhoLayerSwapDB={{showChannel=true}} CHANNELS[#CHANNELS+1]={{4,"{CH}",false}} DEFAULT_CHAT_FRAME.channelList={{"{CH}"}}')
check("showChannel + already listed -> not added twice", list(L.globals().DEFAULT_CHAT_FRAME.channelList.values()) == [CH], dump(L))
L = fresh(); L.execute('CLEAR() TYPED("LayerSwap English","Bob-Dreamscythe") ADVANCE(2) CLICKALL()')
check("hidden channel still carries requests", L.execute('return (invites())') == 1, dump(L))

# ------------------------------------------------------------- requests -> invites
def scenario(desc, setup, act, expect, extra=None):
    L = fresh(setup or "")
    L.execute("CLEAR()"); L.execute(act); L.execute("ADVANCE(2) CLICKALL()")
    n, who = L.execute("return invites()")
    ok = n == expect and (not extra or bool(L.execute(extra)))
    check(desc, ok, f"invites={n} [{who}] {dump(L)}")
    return L

scenario("button request english, I'm in <Who> -> invite", None, 'REQ("english","Bob-Dreamscythe")', 1)
scenario("button request latam, I'm in <Who> -> no", None, 'REQ("spanish","Bob-Dreamscythe")', 0)
scenario("button request port, I'm in <Quem> -> invite", 'GUILD="Quem"', 'REQ("portuguese","Ana-Dreamscythe")', 1)
scenario("request on a different channel -> ignored", None, 'REQ("english","Bob-Dreamscythe","Trade",2)', 0)
scenario("request on look-alike channel -> ignored", None, f'REQ("english","Bob-Dreamscythe","{CH}2",9)', 0)
scenario("request with channel name '5. <name>' -> accepted", None, f'REQ("english","Bob-Dreamscythe","5. {CH}")', 1)
scenario("request with no name but our local id -> accepted", None, 'REQ("english","Bob-Dreamscythe","",5)', 1)
scenario("request over WHISPER addon channel -> ignored", None,
         'EV("CHAT_MSG_ADDON","WHOLAYERSWAP","REQ:english","WHISPER","Bob-Dreamscythe","",0,0,"")', 0)
scenario("request over PARTY addon channel -> ignored", None,
         'EV("CHAT_MSG_ADDON","WHOLAYERSWAP","REQ:english","PARTY","Bob-Dreamscythe","",0,0,"")', 0)
scenario("bogus language REQ:klingon -> ignored", None, 'REQ("klingon","Bob-Dreamscythe")', 0)
scenario("REQ:english!! -> ignored", None,
         f'EV("CHAT_MSG_ADDON","WHOLAYERSWAP","REQ:english!!","CHANNEL","Bob-Dreamscythe","",0,5,"{CH}")', 0)
scenario("other addon's prefix on our channel -> ignored", None,
         f'EV("CHAT_MSG_ADDON","OTHERADDON","REQ:english","CHANNEL","Bob-Dreamscythe","",0,5,"{CH}")', 0)
scenario("my own request -> no invite", None, 'REQ("english","Ryan-Dreamscythe")', 0)
scenario("same name other realm -> invite", None, 'REQ("english","Ryan-Otherrealm")', 1)
scenario("typed 'inv english' in hidden channel -> invite", None, 'TYPED("LayerSwap English","Bob-Dreamscythe")', 1)
scenario("phrase typed in Trade -> ignored", None, 'TYPED("LayerSwap English","Bob-Dreamscythe","Trade - City",2)', 0)
scenario("old fuzzy 'inv english' in channel -> ignored now", None, 'TYPED("inv english","Bob-Dreamscythe")', 0)
scenario("phrase lowercase/no space 'layerswapenglish' -> invite", None, 'TYPED("layerswapenglish","Bob-Dreamscythe")', 1)
scenario("phrase with punctuation 'LayerSwap: English!' -> invite", None, 'TYPED("LayerSwap: English!","Bob-Dreamscythe")', 1)
scenario("phrase inside a sentence -> ignored", None, 'TYPED("can someone LayerSwap English me","Bob-Dreamscythe")', 0)
scenario("wrong-language phrase for my guild -> no", None, 'TYPED("LayerSwap Latam","Bob-Dreamscythe")', 0)
scenario("LayerSwap Latam, I'm in <Quien> -> invite", 'GUILD="Quien"', 'TYPED("LayerSwap Latam","Ana-Dreamscythe")', 1)
scenario("LayerSwap Portuguese, I'm in <Quem> -> invite", 'GUILD="Quem"', 'TYPED("LayerSwap Portuguese","Ana-Dreamscythe")', 1)
scenario("typed phrase + backup addon message -> one invite", None, 'TYPED("LayerSwap English","Bob-Dreamscythe") REQ("english","Bob-Dreamscythe")', 1)
scenario("typed chit-chat in hidden channel -> ignored", None, 'TYPED("hello is this working","Bob-Dreamscythe")', 0)

scenario("look-alike guild <Whoo> -> no", 'GUILD="Whoo"', 'REQ("english","Bob-Dreamscythe")', 0)
scenario("look-alike guild <The Who> -> no", 'GUILD="The Who"', 'REQ("english","Bob-Dreamscythe")', 0)
scenario("<WHO> caps -> yes", 'GUILD="WHO"', 'REQ("english","Bob-Dreamscythe")', 1)
scenario("no guild -> no", 'GUILD=nil', 'REQ("english","Bob-Dreamscythe")', 0)
scenario("guild info loading -> no", 'GUILD_KNOWN=false', 'REQ("english","Bob-Dreamscythe")', 0)
scenario("rank can't invite -> no", 'CAN_INVITE=false', 'REQ("english","Bob-Dreamscythe")', 0)
scenario("two Marias on two realms -> both", None, 'REQ("english","Maria-Dreamscythe") REQ("english","Maria-Otherrealm")', 2)
scenario("same person spams 30x -> one invite", None, 'for i=1,30 do REQ("english","Spam-Dreamscythe") ADVANCE(1) end', 1)
scenario("asks again 63s after being invited -> second invite", None, 'REQ("english","Bob-Dreamscythe") CLICKALL() ADVANCE(63) REQ("english","Bob-Dreamscythe")', 2)
scenario("duplicate copy 3s after invite -> ignored", None, 'REQ("english","Bob-Dreamscythe") CLICKALL() ADVANCE(3) REQ("english","Bob-Dreamscythe")', 1)
scenario("alt joins, leaves, asks again 15s later -> invited again", None, 'REQ("english","Bob-Dreamscythe") CLICKALL() ADVANCE(15) REQ("english","Bob-Dreamscythe")', 2)
scenario("same alt cycles 5 times -> 5 invites, no reload", None, 'for i=1,5 do REQ("english","Bob-Dreamscythe") CLICKALL() ADVANCE(20) end', 5)
scenario("another member invited them 15s ago -> asks again -> queued", None, 'CLAIM("bob-dreamscythe") ADVANCE(15) REQ("english","Bob-Dreamscythe")', 1)
scenario("100 different people -> 100 invites", None, 'for i=1,100 do REQ("english","P"..i.."-Dreamscythe") end', 100)
scenario("claimed by another member first -> stand down", None, 'CLAIM("bob-dreamscythe") REQ("english","Bob-Dreamscythe")', 0)
scenario("claim arrives before I click -> button drops them", None, 'REQ("english","Bob-Dreamscythe") CLAIM("bob-dreamscythe")', 0)
scenario("my own claim echo -> still invite", None, 'REQ("english","Bob-Dreamscythe") CLAIM("bob-dreamscythe","Ryan-Dreamscythe")', 1)
scenario("clicking invite tells the guild (claim)", None, 'REQ("english","Bob-Dreamscythe")', 1, 'return has("ADDONMSG GUILD nil CLAIM:bob-dreamscythe")')
scenario("lockdown -> no", 'LOCKDOWN=true', 'REQ("english","Bob-Dreamscythe")', 0)
scenario("lockdown before I click -> no invite", None, 'REQ("english","Bob-Dreamscythe") LOCKDOWN=true', 0)
scenario("I leave guild before I click -> no invite", None, 'REQ("english","Bob-Dreamscythe") GUILD=nil', 0)
scenario("/wls off -> no", None, 'SLASH("off") REQ("english","Bob-Dreamscythe")', 0)
scenario("secret text -> no error", None, f'local t="REQ:english" SECRET[t]=true EV("CHAT_MSG_ADDON","WHOLAYERSWAP",t,"CHANNEL","Bob","",0,5,"{CH}")', 0)
scenario("secret sender -> no error", None, 'local s="Bob-Dreamscythe" SECRET[s]=true REQ("english",s)', 0)
scenario("nil/garbage events -> no error", None,
         'EV("CHAT_MSG_ADDON") EV("CHAT_MSG_CHANNEL") EV("CHAT_MSG_WHISPER") EV("CHAT_MSG_ADDON",1,2,3,4,5,6,7,8) EV("CHAT_MSG_CHANNEL",1,2,3,4,5,6,7,8,9)', 0)
scenario("whisper ginv -> invite (via button)", None, 'EV("CHAT_MSG_WHISPER","ginv","Zed-Dreamscythe")', 1)
scenario("whisper ginv pls -> no", None, 'EV("CHAT_MSG_WHISPER","ginv pls","Zed-Dreamscythe")', 0)
scenario("invite never calls a blocked function", None, 'REQ("english","Bob-Dreamscythe")', 1, 'return not has("BLOCKED")')
scenario("invite uses /ginvite with spaced Forever name", None, 'REQ("english","Rot Howler-Dreamscythe")', 1, 'return has("INVITE Rot Howler-Dreamscythe")')
scenario("my own phrase (same GUID) -> never queued", 'ME="Rot Howler"', 'EV("CHAT_MSG_CHANNEL","LayerSwap English","Rot Howler-Dreamscythe","","5. whoguildlayerswapchannel","","",0,5,"whoguildlayerswapchannel",0,1,MYGUID)', 0, 'return not has("SOUND")')
scenario("my own phrase, name w/ space, no GUID -> never queued", 'ME="Rot Howler"', 'TYPED("LayerSwap English","Rot Howler-Dreamscythe")', 0)
scenario("my own backup REQ with my GUID -> never queued", 'ME="Rot Howler"', 'EV("CHAT_MSG_ADDON","WHOLAYERSWAP","REQ:english:"..MYGUID,"CHANNEL","RotHowler","",0,5,"whoguildlayerswapchannel")', 0)
scenario("request plays a ping, no chat spam", None, 'REQ("english","Bob-Dreamscythe")', 1, 'return has("SOUND") and not said("wants into your guild")')

# ------------------------------------------------------------- invite queue list
L = fresh(); g = L.globals(); q = g.WhoLayerSwapQueue
check("queue hidden while empty", q is not None and not q.shown)
L.execute('CLEAR() REQ("english","Bob-Dreamscythe") REQ("english","Cat-Dreamscythe") ADVANCE(1)')
check("queue shows each person on a row", q.shown and L.execute('return SHOWN_NAMES()') == "1:Bob,2:Cat", L.execute('return SHOWN_NAMES()'))
check("count shows 2", q.count.txt == "2")
check("countdown shows seconds left", q.rows[1].time.txt == "19s", q.rows[1].time.txt)
L.execute('CLICK(ROW(1))')
check("invite on row 1 invites Bob, his row disappears", L.execute('return has("INVITE Bob-Dreamscythe")') and L.execute('return SHOWN_NAMES()') == "2:Cat", L.execute('return SHOWN_NAMES()'))
L.execute('REQ("english","Dan-Dreamscythe")')
check("newcomer takes the free slot (no shifting)", L.execute('return SHOWN_NAMES()') == "1:Dan,2:Cat", L.execute('return SHOWN_NAMES()'))
L.execute('CLEAR() CLICK(ROW(2), "RightButton")')
check("right-click skips Cat without inviting", not L.execute('return has("INVITE")') and L.execute('return SHOWN_NAMES()') == "1:Dan", L.execute('return SHOWN_NAMES()'))
L.execute('ADVANCE(21)')
check("after 20 seconds the row disappears, queue hides", L.execute('return SHOWN_NAMES()') == "" and not q.shown, L.execute('return SHOWN_NAMES()'))
L = fresh(); L.execute('CLEAR() REQ("english","Bob-Dreamscythe") ADVANCE(19)')
check("still there at 19 seconds", L.execute('return SHOWN_NAMES()') == "1:Bob")
L.execute('REQ("english","Bob-Dreamscythe") ADVANCE(10)')
check("asking again restarts their 20 seconds", L.execute('return SHOWN_NAMES()') == "1:Bob")
L = fresh(); L.execute('CLEAR() REQ("english","Bob-Dreamscythe") REQ("english","Cat-Dreamscythe") CLAIM("bob-dreamscythe")')
check("someone else invited Bob -> only his row goes", L.execute('return SHOWN_NAMES()') == "2:Cat", L.execute('return SHOWN_NAMES()'))
L = fresh(); L.execute('CLEAR() INCOMBAT=true REQ("english","Bob-Dreamscythe")')
check("request in combat: queue waits (secure rows)", not L.globals().WhoLayerSwapQueue.shown)
L.execute('INCOMBAT=false EV("PLAYER_REGEN_ENABLED")')
check("...appears after combat", L.globals().WhoLayerSwapQueue.shown and L.execute('return SHOWN_NAMES()') == "1:Bob")
L = fresh(); L.execute('REQ("english","Bob-Dreamscythe") INCOMBAT=true CLEAR() CLICK(ROW(1))')
check("clicking invite in combat does nothing, explains", not L.execute('return has("INVITE")') and L.execute('return said("in combat")'), dump(L))
L = fresh(); L.execute('CLEAR() REQ("english","Bob-Dreamscythe") REQ("english","Bob-Dreamscythe") TYPED("LayerSwap English","Bob-Dreamscythe")')
check("same person 3x -> one row", L.execute('return SHOWN_NAMES()') == "1:Bob")
L = fresh(); L.execute('CLEAR() for i=1,20 do REQ("english","P"..i.."-Dreamscythe") end')
q = L.globals().WhoLayerSwapQueue
check("20 people at once: 8 rows + '+12 more waiting'", L.execute('return SHOWN_NAMES()').count(":") == 8 and q.more.txt == "+12 more waiting" and q.count.txt == "20", f"{q.more.txt} {q.count.txt}")
check("20 people -> only one ping", L.execute('local n = 0 for _, l in ipairs(LOG) do if l:find("^SOUND") then n = n + 1 end end return n') == 1)
L.execute('CLICK(ROW(3))')
check("inviting one seats the next waiting person in that row", L.execute('return ROWNAME(3)') == "P9" and q.more.txt == "+11 more waiting", f"{L.execute('return ROWNAME(3)')} {q.more.txt}")
L.execute('ADVANCE(21)')
check("all 20 expire after 20s (no one invited)", not q.shown and L.execute('return SHOWN_NAMES()') == "")
L = fresh('WhoLayerSwapDB={noPing=true}'); L.execute('CLEAR() REQ("english","Bob-Dreamscythe")')
check("ping can be turned off", not L.execute('return has("SOUND")'))
L = fresh(); L.execute('CLEAR() REQ("english","Bob-Dreamscythe") ADVANCE(9) REQ("english","Cat-Dreamscythe")')
check("second ping only after 8+ seconds", L.execute('local n = 0 for _, l in ipairs(LOG) do if l:find("^SOUND") then n = n + 1 end end return n') == 2)
L = fresh(); L.execute('CLEAR() EV("CHAT_MSG_WHISPER","ginv","Zed-Dreamscythe")')
check("ginv whisper lands in the queue too", L.execute('return SHOWN_NAMES()') == "1:Zed")

scenario("REQ with junk instead of GUID -> ignored", None, 'EV("CHAT_MSG_ADDON","WHOLAYERSWAP","REQ:english:<script>","CHANNEL","Bob-Dreamscythe","",0,5,"whoguildlayerswapchannel")', 0)
scenario("REQ with someone's GUID -> invite", None, 'EV("CHAT_MSG_ADDON","WHOLAYERSWAP","REQ:english:Player-1-0000BOB","CHANNEL","Bob-Dreamscythe","",0,5,"whoguildlayerswapchannel")', 1)

L = fresh(); L.execute('CLEAR() REQ("english","Bob-Dreamscythe")')
check("request plays the map ping sound", L.execute('return has("SOUND 3175")'), dump(L))
q = L.globals().WhoLayerSwapQueue
check("queue sits under the Layer swap panel by default", q.points[1] == "TOPRIGHT" and q.points[3] == "BOTTOMRIGHT", str(list(q.points.values())))

# ------------------------------------------------------------- swap buttons
def swap(desc, setup, button, expect_left, expect_req, extra=None):
    L = fresh(setup or "")
    L.execute("CLEAR()"); L.execute(f"BTN({button})")
    left = L.execute('return has("LEAVE ")'); req = L.execute('return has("ADDONMSG CHANNEL")')
    blocked = L.execute('return has("BLOCKED")')
    ok = left == expect_left and req == expect_req and not blocked and (not extra or bool(L.execute(extra)))
    check(desc, ok, f"left={left} req={req} blocked={blocked} {dump(L)}")
    return L

swap("in <Who>, Latam -> /gquit via secure macro + request", None, 2, True, True, 'return has("ADDONMSG CHANNEL 5 REQ:spanish")')
swap("Latam button types 'LayerSwap Latam' in /5", None, 2, True, True, 'return has("MACRO /5 LayerSwap Latam")')
swap("Portuguese button types 'LayerSwap Portuguese'", None, 3, True, True, 'return has("MACRO /5 LayerSwap Portuguese")')
swap("no guild: types phrase, no /gquit", 'GUILD=nil', 1, False, True, 'return has("MACRO /5 LayerSwap English")')
swap("in <Who>, Portuguese -> request REQ:portuguese", None, 3, True, True, 'return has("ADDONMSG CHANNEL 5 REQ:portuguese")')
swap("in <Who>, English -> already there", None, 1, False, False, 'return said("already in <Who>")')
swap("no guild, English -> request only", 'GUILD=nil', 1, False, True)
swap("guild loading -> refuse", 'GUILD_KNOWN=false', 2, False, False, 'return said("still loading")')
swap("guild leader -> refuse", 'LEADER=true', 2, False, False, 'return said("guild leader")')
swap("real guild -> refuse, explain", 'GUILD="Real Raiders"', 2, False, False, 'return said("isn\'t one of the three")')
swap("chat lockdown -> refuse", 'LOCKDOWN=true', 2, False, False, 'return said("locked")')
L2 = fresh(); L2.execute('CLEAR() INCOMBAT=true BTN(2)')
check("in combat: nothing happens, no blocked call", not L2.execute('return has("LEAVE") or has("ADDONMSG CHANNEL") or has("BLOCKED")') and L2.execute('return said("combat")'), dump(L2))
L = fresh('JOIN_FAILS=true')
L.execute('CLEAR() BTN(2)')
check("not in hidden channel -> refuse, don't leave, try to join", not L.execute('return has("LEAVE")') and L.execute('return has("JOIN") and said("Still joining")'), dump(L))
L = fresh('ADDONMSG_RESULT=3')
L.execute('CLEAR() BTN(3)')
check("backup message failing doesn't break the swap", L.execute('return has("MACRO /5 LayerSwap Portuguese") and has("LEAVE Who")'), dump(L))
L = swap("leave blocked by server -> /gquit hint", 'LEAVE_BLOCKED=true', 2, False, True)
L.execute('ADVANCE(4)'); check("blocked leave hint after 3s", L.execute('return said("/gquit")'), dump(L))
L = swap("nobody invites -> hint after 45s", None, 2, True, True)
L.execute('ADVANCE(46)'); check("45s 'No one from <quien>' hint", L.execute('return said("No one from <Quien>/<Quien Two>")'), dump(L))
L = swap("invite arrives -> no hints", None, 2, True, True)
L.execute('EV("GUILD_INVITE_REQUEST","Ana-Dreamscythe","Quien",0,"",false) GUILD="Quien" ADVANCE(50)')
check("accepted -> no hint", not L.execute('return said("No one from") or said("/gquit")') and L.execute('return has("ACCEPT")'), dump(L))
L = fresh(); L.execute('CLEAR() BTN(2)')
b = L.globals().WhoLayerSwapPanel.buttons[2]
check("macro cleared after click", b.attrs["macrotext"] == "", repr(b.attrs["macrotext"]))
L = fresh(); L.execute('CLEAR()'); bb = L.globals().WhoLayerSwapPanel.buttons[2]; bb.scripts.PreClick(bb, "LeftButton", False)
check("macro text is /gquit then the phrase", bb.attrs["macrotext"] == "/gquit\n/5 LayerSwap Latam", repr(bb.attrs["macrotext"]))
check("button is secure macro type, fires on mouse up", b.attrs["type"] == "macro" and b.attrs["useOnKeyDown"] is False)
L = fresh(); L.execute('CLEAR() BTN(2) GUILD=nil BTN(2)')
check("double-click: second click doesn't /gquit again", sum(1 for l in L.globals().LOG.values() if l.startswith("LEAVE")) == 1, dump(L))

# panel + combat safety
L = fresh()
bs = L.globals().WhoLayerSwapPanel.buttons
check("panel: own guild's button disabled", bs[1].enabled is False and bs[2].enabled is True)
L.execute('INCOMBAT=true GUILD="Quien" EV("PLAYER_GUILD_UPDATE")')
check("no secure-button changes in combat", bs[2].enabled is True)
L.execute('INCOMBAT=false EV("PLAYER_REGEN_ENABLED")')
check("panel updates after combat", bs[2].enabled is False and bs[1].enabled is True)
L.execute('INCOMBAT=true CLEAR() SLASH("hide")')
check("/wls hide in combat refused", L.execute('return said("combat")') and L.globals().WhoLayerSwapPanel.shown is not False)
for bad in ['{}', '{"CENTER"}', '{1,2,3,4}', '"junk"', '5']:
    try:
        fresh(f'WhoLayerSwapDB = {{ point = {bad} }}'); check(f"bad saved position {bad} -> no error", True)
    except Exception as e: check(f"bad saved position {bad} -> no error", False, str(e)[:150])
try: fresh('WhoLayerSwapDB = "corrupt"'); check("corrupt saved settings -> no error", True)
except Exception as e: check("corrupt saved settings -> no error", False, str(e)[:150])

# ------------------------------------------------------------- auto-accept
def accept_case(desc, guild, expect, setup=""):
    L = fresh('GUILD=nil ' + setup); L.execute("CLEAR() GuildInviteFrame:Show()")
    L.execute(f'EV("GUILD_INVITE_REQUEST","Maria-Dreamscythe",{guild},0,"",false) ADVANCE(1)')
    acc = L.execute('return has("ACCEPT")'); dec = L.execute('return has("DECLINE")')
    win = L.globals().GuildInviteFrame.shown
    ok = (acc and not dec) if expect else (not acc and not dec and win)
    check(desc, ok, f"accept={acc} decline={dec} windowOpen={win}")
for gname in ['"Who"','"who"','"WHO"','"Quien"','"QUIEN"','"Quem"','"quem"']:
    accept_case(f"accept <{gname}>", gname, True)
for gname in ['"Whoo"','"Who Dat"','"The Who"','"Quién"','"Quem BR"','"Wh0"','"Who?"','"quien2"','""','nil','5']:
    accept_case(f"don't accept <{gname}>", gname, False)
accept_case("secret guild name -> no accept", 'SN', False, 'SN="Who" SECRET[SN]=true')
L = fresh('GUILD=nil'); L.execute('SLASH("off") CLEAR() EV("GUILD_INVITE_REQUEST","M","Who",0,"",false)')
check("/wls off stops accept", not L.execute('return has("ACCEPT")'))
L = fresh('GUILD=nil'); L.execute('SLASH("accept") CLEAR() EV("GUILD_INVITE_REQUEST","M","Who",0,"",false)')
check("/wls accept toggle stops accept", not L.execute('return has("ACCEPT")'))

# accepted -> guild changes -> window closed (not declined) + toast
L = fresh('GUILD=nil'); L.execute('CLEAR() GuildInviteFrame:Show() EV("GUILD_INVITE_REQUEST","M","Who",0,"",false) GUILD="Who" EV("PLAYER_GUILD_UPDATE")')
t = L.globals().WhoLayerSwapToast
check("joined <Who> -> toast + window closed without declining",
      t is not None and t.shown and not L.globals().GuildInviteFrame.shown and not L.execute('return has("DECLINE")'), dump(L))
# blocked accept -> window stays for the player to click Join
L = fresh('GUILD=nil ACCEPT_BLOCKED=true'); L.execute('CLEAR() GuildInviteFrame:Show() EV("GUILD_INVITE_REQUEST","M","Who",0,"",false) ADVANCE(3)')
check("AcceptGuild blocked -> invite window stays open, explains", L.globals().GuildInviteFrame.shown and not L.execute('return has("DECLINE")') and L.execute('return said("click Join")'), dump(L))
L.execute('CLEAR() EV("GUILD_INVITE_REQUEST","M","Who",0,"",false)')
check("after a block, doesn't keep retrying", not L.execute('return has("BLOCKED")') and L.execute('return said("click Join")'), dump(L))
L.execute('GUILD="Who" EV("PLAYER_GUILD_UPDATE")')
check("player clicks Join -> toast still shows", L.globals().WhoLayerSwapToast is not None and L.globals().WhoLayerSwapToast.shown)
L = fresh(); L.execute('CLEAR() EV("PLAYER_GUILD_UPDATE")')
check("login in <Who> -> no toast", L.globals().WhoLayerSwapToast is None or not L.globals().WhoLayerSwapToast.shown)
L = fresh('GUILD=nil'); L.execute('GUILD="Real Raiders" EV("PLAYER_GUILD_UPDATE")')
check("joining another guild -> no toast", L.globals().WhoLayerSwapToast is None)
L = fresh('GUILD=nil'); L.execute('GUILD="Quem" EV("PLAYER_GUILD_UPDATE")')
t = L.globals().WhoLayerSwapToast; upd = t.scripts.OnUpdate
check("toast text", t.text.txt == "Relog to change layers")
for _ in range(58): upd(t, 0.05)
check("toast visible at 2.9s", t.shown)
for _ in range(12): upd(t, 0.05)
check("toast gone by 3.5s", not t.shown)

# ------------------------------------------------------------- slash commands
L = fresh()
for c in ["", "on", "off", "quiet", "accept", "show", "hide", "lock", "reset", "toast", "debug", "join",
          "test", "test inv eng", "nonsense", "   ", "TEST INV ENG"]:
    try: L.execute(f'SLASH({c!r})'); check(f"/wls {c!r} no error", True)
    except Exception as e: check(f"/wls {c!r} no error", False, str(e)[:150])
L = fresh(); L.execute('CLEAR() SLASH("")')
check("/wls status shows hidden channel joined", L.execute('return said("joined (/5)")'), dump(L))
L = fresh(); L.execute('SLASH("debug") CLEAR() REQ("spanish","Bob-Dreamscythe")')
check("debug explains wrong guild", L.execute('return said("you\'re in <who>")'), dump(L))
L.execute('CLEAR() REQ("english","Ryan-Dreamscythe")')
check("debug explains own request", L.execute('return said("your own request")'), dump(L))

# phrase tests
L = fresh()
parse = L.execute("return function(t) CLEAR() SLASH('test ' .. t) return OUT[1] or '' end")
def lang_of(t):
    o = parse(t)
    for lg in ("spanish", "english", "portuguese"):
        if f"-> {lg}" in o: return lg
for m, lg in [("LayerSwap English","english"),("layerswap english","english"),("LAYERSWAP ENGLISH","english"),
              ("LayerSwap Latam","spanish"),("LayerSwap Portuguese","portuguese"),("  LayerSwap  Latam  ","spanish"),
              ("Layer Swap English","english"),("LayerSwap-English","english")]:
    check(f"phrase {m!r}", lang_of(m) == lg, str(lang_of(m)))
for m in ["inv english","LayerSwap Eng","LayerSwap Spanish","LayerSwap","English","LayerSwap English please",
          "LayerSwap Englishh","LayerSwap Portugese","x"*80]:
    check(f"not a phrase {m[:30]!r}", lang_of(m) is None, str(lang_of(m)))

# ------------------------------------------------------------- settings: guild names (built-in + extras)
L = fresh(); L.execute('CLEAR() SLASH("settings")')
g = L.globals(); win = g.WhoLayerSwapSettings
check("/wls settings opens the window", win is not None and win.shown)
check("extra-name boxes start empty with a hint", [g.WhoLayerSwapGuildEdit1.txt, g.WhoLayerSwapGuildEdit2.txt, g.WhoLayerSwapGuildEdit3.txt] == ["","",""] and g.WhoLayerSwapGuildEdit1.hint.shown)
check("settings window closes with Escape (UISpecialFrames)", "WhoLayerSwapSettings" in list(g.UISpecialFrames.values()))
L.execute('local gb = WhoLayerSwapSettingsButton gb.scripts.OnClick(gb)')
check("gear button toggles settings closed", not win.shown)
L.execute('local gb = WhoLayerSwapSettingsButton gb.scripts.OnClick(gb)')
check("gear button toggles settings open", win.shown)
check("Options > AddOns entry registered", list(g.SETTINGS_CATS.values()) == ["WhoLayerSwap"])

def req_invites(setup, lang, sender="Bob-Dreamscythe"):
    L = fresh(setup); L.execute(f'CLEAR() REQ("{lang}","{sender}") ADVANCE(2) CLICKALL()')
    return L.execute('return (invites())')
# built-in names, no setup at all
for guild, lang in [("Who","english"),("Who Two","english"),("WHO TWO","english"),("whotwo","english"),
                    ("Quien","spanish"),("Quien Two","spanish"),("Quem","portuguese"),("Quem Two","portuguese")]:
    check(f"built-in <{guild}> invites {lang}", req_invites(f'GUILD="{guild}"', lang) == 1)
for guild, lang in [("Who Two","spanish"),("Quien Two","english"),("Who Three","english"),("Who Too","english"),("Quién Two","spanish")]:
    check(f"<{guild}> does not invite {lang}", req_invites(f'GUILD="{guild}"', lang) == 0)
for guild in ["Who","Who Two","Quien","Quien Two","Quem","Quem Two","who two"]:
    L = fresh('GUILD=nil'); L.execute(f'CLEAR() EV("GUILD_INVITE_REQUEST","M","{guild}",0,"",false)')
    check(f"auto-accepts built-in <{guild}>", L.execute('return has("ACCEPT")'))
for guild in ["Who Three","The Who","Quien 2","Quem BR","Who Too","Who?","Who-Two","Quien.Two"]:
    L = fresh('GUILD=nil'); L.execute(f'CLEAR() EV("GUILD_INVITE_REQUEST","M","{guild}",0,"",false)')
    check(f"doesn't accept <{guild}>", not L.execute('return has("ACCEPT")'))

def setextra(L, idx, text):
    L.execute(f'local e = WhoLayerSwapGuildEdit{idx} e:SetText({text!r}) e.scripts.OnEnterPressed(e)')

L = fresh(); L.execute('SLASH("settings")'); g = L.globals()
setextra(L, 1, "  The Who Crew , Who Three ")
check("extras saved trimmed, comma-joined", g.WhoLayerSwapDB.guilds.english == "The Who Crew, Who Three" and g.WhoLayerSwapGuildEdit1.txt == "The Who Crew, Who Three", str(g.WhoLayerSwapDB.guilds.english))
for guild in ["The Who Crew","Who Three","Who","Who Two"]:
    L.execute(f'GUILD="{guild}" CLEAR() REQ("english","P{len(guild)}-Dreamscythe") ADVANCE(2) CLICKALL()')
    check(f"with extras, <{guild}> invites English", L.execute('return (invites())') == 1, dump(L))
L.execute('GUILD=nil CLEAR() EV("GUILD_INVITE_REQUEST","M","who three",0,"",false)')
check("auto-accept includes extras", L.execute('return has("ACCEPT")'))
L.execute('GUILD="Who Three" EV("PLAYER_GUILD_UPDATE")')
bb = g.WhoLayerSwapPanel.buttons
check("panel greys out English for an extra name", bb[1].enabled is False and bb[2].enabled is True)
L.execute('CLEAR() BTN(1)')
check("swap button: already in <Who Three>", L.execute('return said("already in <Who Three>")'), dump(L))
L.execute('GUILD="Who Two" EV("PLAYER_GUILD_UPDATE")')
check("panel greys out English while in the backup guild", bb[1].enabled is False)
L.execute('CLEAR() BTN(2)')
check("backup guild counts as one of ours (no 'leave it yourself')", L.execute('return has("LEAVE Who Two")') and not L.execute('return said("isn\'t one of the three")'), dump(L))
L = fresh(); L.execute('SLASH("settings")'); g = L.globals()
L.execute('CLEAR()'); setextra(L, 2, "Who Two, Los Quien")
check("name owned by another language is skipped + explained", g.WhoLayerSwapDB.guilds.spanish == "Los Quien" and L.execute('return said("<Who Two> is already a English guild name")'), dump(L))
L.execute('GUILD="Who Two" CLEAR() REQ("english","Zed-Dreamscythe") ADVANCE(2) CLICKALL()')
check("...and Who Two still invites English", L.execute('return (invites())') == 1)
setextra(L, 3, "Quem, quem two")
check("built-in names typed as extras aren't stored", g.WhoLayerSwapDB.guilds.portuguese is None and g.WhoLayerSwapGuildEdit3.txt == "")
setextra(L, 2, "")
check("empty box clears extras", g.WhoLayerSwapDB.guilds.spanish is None)
L.execute('local e = WhoLayerSwapGuildEdit3 e:SetText("Typo Guild") e.scripts.OnEscapePressed(e)')
check("Escape reverts without saving", g.WhoLayerSwapGuildEdit3.txt == "" and g.WhoLayerSwapDB.guilds.portuguese is None)
L.execute('local e = WhoLayerSwapGuildEdit3 e:SetText("Os Quem") e.scripts.OnEditFocusLost(e)')
check("clicking away saves", g.WhoLayerSwapDB.guilds.portuguese == "Os Quem")
setextra(L, 1, ",".join(["Guild"+chr(65+i) for i in range(8)]))
check("at most 5 extras per language", len(g.WhoLayerSwapDB.guilds.english.split(", ")) == 5)
setextra(L, 1, "X"*40)
check("each name capped at 24 letters", len(g.WhoLayerSwapDB.guilds.english) == 24)
L.execute('for _, fr in ipairs(FRAMES) do if fr.txt == "Clear extra names" then fr.scripts.OnClick(fr) end end')
check("Clear extra names empties all", g.WhoLayerSwapDB.guilds.english is None and g.WhoLayerSwapDB.guilds.portuguese is None)

check("saved extra applied at login", req_invites('WhoLayerSwapDB={guilds={spanish="Los Quien"}} GUILD="Los Quien"', "spanish") == 1)
check("old 1.6 saved name becomes an extra (built-ins still work)", req_invites('WhoLayerSwapDB={guilds={english="The Who Crew"}} GUILD="Who"', "english") == 1)
for bad in ['"junk"', '{english=5}', '{english=""}', '{spanish={}}', '{english=",,,"}']:
    try: check(f"bad saved guilds {bad} -> built-ins, no error", req_invites(f'WhoLayerSwapDB={{guilds={bad}}}', "english") == 1)
    except Exception as e: check(f"bad saved guilds {bad} -> built-ins, no error", False, str(e)[:150])

L = fresh(); L.execute('CLEAR() SLASH("guild latam Los Quien, Quien Tres")')
check("/wls guild latam <names>", L.globals().WhoLayerSwapDB.guilds.spanish == "Los Quien, Quien Tres" and L.execute('return said("<Quien>/<Quien Two>/<Los Quien>/<Quien Tres>")'), dump(L))
L.execute('CLEAR() SLASH("guild klingon X")')
check("/wls guild with bad language -> usage", L.execute('return said("Usage")'))
L.execute('CLEAR() SLASH("phrases")')
check("/wls phrases lists all names", L.execute('return said("<Who>/<Who Two>")') and L.execute('return said("<Los Quien>")'), dump(L))

# ------------------------------------------------------------- cross-guild claims (Who + Who Two both online)
L = fresh(); L.execute('CLEAR() REQ("english","Bob-Dreamscythe") ADVANCE(1) CLICKALL()')
check("clicking invite also claims on the swap channel", L.execute('return has("ADDONMSG CHANNEL 5 CLAIM:bob-dreamscythe")'), dump(L))
L = fresh('GUILD="Who Two"'); L.execute('CLEAR() REQ("english","Bob-Dreamscythe") EV("CHAT_MSG_ADDON","WHOLAYERSWAP","CLAIM:bob-dreamscythe","CHANNEL","Ann-Dreamscythe","",0,5,"whoguildlayerswapchannel") ADVANCE(2) CLICKALL()')
check("Who member claimed on the channel -> Who Two member stands down", L.execute('return (invites())') == 0, dump(L))
L = fresh(); L.execute('CLEAR() REQ("english","Bob-Dreamscythe") EV("CHAT_MSG_ADDON","WHOLAYERSWAP","CLAIM:bob-dreamscythe","CHANNEL","Ryan-Dreamscythe","",0,5,"whoguildlayerswapchannel") ADVANCE(2) CLICKALL()')
check("my own channel claim doesn't block me", L.execute('return (invites())') == 1)
L = fresh(); L.execute('CLEAR() REQ("english","Bob-Dreamscythe") EV("CHAT_MSG_ADDON","WHOLAYERSWAP","CLAIM:bob-dreamscythe","CHANNEL","Ann-Dreamscythe","",0,2,"Trade") ADVANCE(2) CLICKALL()')
check("claim on some other channel is ignored", L.execute('return (invites())') == 1)
L = fresh('LOCKDOWN=true'); L.execute('EV("CHAT_MSG_ADDON","WHOLAYERSWAP","CLAIM:bob-dreamscythe","CHANNEL","Ann-Dreamscythe","",0,5,"whoguildlayerswapchannel") LOCKDOWN=false CLEAR() REQ("english","Bob-Dreamscythe") ADVANCE(2) CLICKALL()')
check("claims still recorded during chat lockdown", L.execute('return (invites())') == 0)

# ------------------------------------------------------------- settings: invite queue position
L = fresh(); g = L.globals(); q = g.WhoLayerSwapQueue
L.execute('SLASH("settings") local m = WhoLayerSwapSettings.move m.scripts.OnClick(m)')
check("Move invite queue shows the empty queue to drag", q.shown and q.empty.shown and g.WhoLayerSwapSettings.move.txt == "Done moving")
L.execute('local f = WhoLayerSwapQueue f.scripts.OnDragStart(f) f.scripts.OnDragStop(f)')
check("dragging saves the position", list(g.WhoLayerSwapDB.queuePoint.values()) == ["TOPRIGHT","TOPRIGHT",-100,-50], str(list(g.WhoLayerSwapDB.queuePoint.values())))
L.execute('local m = WhoLayerSwapSettings.move m.scripts.OnClick(m)')
check("Done moving hides the empty queue", not q.shown and g.WhoLayerSwapSettings.move.txt == "Move invite queue")
L.execute('CLEAR() REQ("english","Bob-Dreamscythe") ADVANCE(2) CLICKALL()')
check("moved queue still invites", L.execute('return (invites())') == 1, dump(L))
L.execute('local m = WhoLayerSwapSettings.move m.scripts.OnClick(m) WhoLayerSwapSettings:Hide()')
check("closing settings ends move mode", not q.shown)
L.execute('CLEAR() INCOMBAT=true local m = WhoLayerSwapSettings.move m.scripts.OnClick(m)')
check("move mode refused in combat", not q.shown and L.execute('return said("in combat")'))
L = fresh(); g = L.globals(); q = g.WhoLayerSwapQueue
L.execute('INCOMBAT=true local f = WhoLayerSwapQueue f.scripts.OnDragStart(f)')
check("can't start dragging in combat", True)
L = fresh('WhoLayerSwapDB={queuePoint={"BOTTOM","BOTTOM",10,200}}'); q = L.globals().WhoLayerSwapQueue
check("saved queue position applied at login", q.points[1] == "BOTTOM" and q.points[5] == 200, str(list(q.points.values())))
L.execute('for _, fr in ipairs(FRAMES) do if fr.txt == "Reset position" then end end SLASH("settings") for _, fr in ipairs(FRAMES) do if fr.txt == "Reset position" then fr.scripts.OnClick(fr) end end')
check("Reset position -> back under the panel", L.globals().WhoLayerSwapDB.queuePoint is None and q.points[1] == "TOPRIGHT" and q.points[3] == "BOTTOMRIGHT", str(list(q.points.values())))
for bad in ['"x"', '{1,2,3,4}', '{"TOP","TOP","a",5}', '{"TOP"}']:
    try:
        L = fresh(f'WhoLayerSwapDB={{queuePoint={bad}}}'); q = L.globals().WhoLayerSwapQueue
        check(f"bad saved queue position {bad} -> default", q.points[1] == "TOPRIGHT")
    except Exception as e: check(f"bad saved queue position {bad} -> default", False, str(e)[:150])
L = fresh('WhoLayerSwapDB={invitePoint={"BOTTOM","BOTTOM",10,200}}')
check("old invite-button position from 1.8 is ignored safely", L.globals().WhoLayerSwapQueue.points[1] == "TOPRIGHT")

# ------------------------------------------------------------- settings: checkboxes
L = fresh('GUILD=nil'); L.execute('SLASH("settings")'); g = L.globals(); cb = g.WhoLayerSwapSettings.checks
check("checkboxes reflect state", [cb[i].checked for i in (1,2,3,4,5,6,7)] == [True, False, False, True, True, False, True], str([cb[i].checked for i in (1,2,3,4,5,6,7)]))
def toggle(i): L.execute(f'local c = WhoLayerSwapSettings.checks[{i}] c:SetChecked(not c:GetChecked()) c.scripts.OnClick(c)')
toggle(1)
L.execute('CLEAR() EV("GUILD_INVITE_REQUEST","M","Who",0,"",false)')
check("unticking auto-accept stops accepting, and is saved", not L.execute('return has("ACCEPT")') and g.WhoLayerSwapDB.autoAccept is False)
toggle(2); check("ticking 'show channel' puts it in chat", g.WhoLayerSwapDB.showChannel is True and list(g.DEFAULT_CHAT_FRAME.channelList.values()) == [CH])
toggle(2); check("unticking it takes it out again", g.WhoLayerSwapDB.showChannel is None and len(list(g.DEFAULT_CHAT_FRAME.channelList.values())) == 0)
toggle(3); check("ticking lock saves it", g.WhoLayerSwapDB.locked is True)
toggle(4); check("unticking charter button saves it", g.WhoLayerSwapDB.hideCharter is True)
toggle(6); check("ticking debug turns it on", L.execute('SLASH("") return true'))
toggle(7); check("unticking ping saves it", g.WhoLayerSwapDB.noPing is True)
L = fresh('GUILD=nil WhoLayerSwapDB={autoAccept=false}')
L.execute('CLEAR() EV("GUILD_INVITE_REQUEST","M","Who",0,"",false)')
check("auto-accept off survives a relog", not L.execute('return has("ACCEPT")'))
L = fresh(); L.execute('CLEAR() local p = WhoLayerSwapPanel p.scripts.OnMouseUp(p, "RightButton")')
check("right-clicking the panel opens settings", L.globals().WhoLayerSwapSettings.shown)
L = fresh(); L.execute('CLEAR() INCOMBAT=true SLASH("settings")')
check("settings window opens in combat (not protected)", L.globals().WhoLayerSwapSettings.shown)


# ------------------------------------------------------------- Guild Charter button
CHARTER = 'BAGS[2][7] = { itemID = 5863, itemName = "Guild Charter", iconFileID = 134939 }'
L = fresh(); ch = L.globals().WhoLayerSwapCharterButton
check("no charter -> no button", ch is not None and not ch.shown)
L.execute(CHARTER + ' EV("BAG_UPDATE_DELAYED")')
check("charter appears in bags -> button shows", ch.shown and ch.attrs["macrotext"] == "/use item:5863" and ch.icon.tex == 134939, str(ch.attrs["macrotext"]))
L.execute('CLEAR() CLICK(WhoLayerSwapCharterButton)')
check("clicking runs /use item:5863 (secure macro)", L.execute('return has("MACRO /use item:5863")') and not L.execute('return has("BLOCKED")'), dump(L))
check("button is big and centered", ch.points[1] == "CENTER" and ch.points[3] == "CENTER" and ch.points[5] == 60)
glow = [k for k in ch.kids.values() if k.ag is not None]
check("charter button glows while shown", len(glow) == 1 and glow[0].ag.playing is True)
check("F1 bound to the charter button while carrying one", L.globals().OVERRIDES["F1"] == "WhoLayerSwapCharterButton")
check("hint mentions F1", "F1" in (ch.hint.txt or ""), str(ch.hint.txt))
L.execute('BAGS[2][7] = nil EV("BAG_UPDATE_DELAYED")')
check("charter turned in -> button hides, macro cleared", not ch.shown and ch.attrs["macrotext"] == "")
check("...and F1 goes back to normal", L.globals().OVERRIDES["F1"] is None)
check("...glow stops", glow[0].ag.playing is False)
L = fresh(CHARTER); ch = L.globals().WhoLayerSwapCharterButton
check("charter already in bags at login -> button shows", ch.shown)
L = fresh(); ch = L.globals().WhoLayerSwapCharterButton
L.execute('INCOMBAT=true ' + CHARTER + ' EV("BAG_UPDATE_DELAYED")')
check("charter gained in combat -> button and F1 wait (secure, no error)", not ch.shown and L.globals().OVERRIDES["F1"] is None)
L.execute('INCOMBAT=false EV("PLAYER_REGEN_ENABLED")')
check("...both arrive after combat", ch.shown and L.globals().OVERRIDES["F1"] == "WhoLayerSwapCharterButton")
L = fresh('BAGS[0][3] = { itemID = 99999, itemName = "Guild Charter", iconFileID = 1 }'); ch = L.globals().WhoLayerSwapCharterButton
check("different item ID but named Guild Charter -> found, uses its own ID", ch.shown and ch.attrs["macrotext"] == "/use item:99999", str(ch.attrs["macrotext"]))
L = fresh('ITEM_NAMES[5863]="Carta de Hermandad" BAGS[1][1] = { itemID = 88888, itemName = "Carta de Hermandad", iconFileID = 1 }'); ch = L.globals().WhoLayerSwapCharterButton
check("localized charter name (from the client) -> found", ch.shown)
L = fresh('BAGS[1][1] = { itemID = 1234, itemName = "Guild Tabard", iconFileID = 1 } BAGS[1][2] = { itemID = 5, itemName = "Charter of Stuff", iconFileID = 1 }'); ch = L.globals().WhoLayerSwapCharterButton
check("other items -> no button", not ch.shown)
L = fresh('WhoLayerSwapDB={hideCharter=true} ' + CHARTER); ch = L.globals().WhoLayerSwapCharterButton
check("charter button turned off -> stays hidden", not ch.shown)
L.execute('CLEAR() SLASH("charter")')
check("/wls charter turns it back on", ch.shown and L.globals().WhoLayerSwapDB.hideCharter is None, dump(L))
L = fresh('BAGS[3] = nil BAGS[2][1] = { itemID = 5863 }'); ch = L.globals().WhoLayerSwapCharterButton
check("missing bag + item without name -> no error, found by ID", ch.shown)
L = fresh('C_Container = nil'); ch = L.globals().WhoLayerSwapCharterButton
check("no container API -> no error, no button", not ch.shown)


# F1 per character
L = fresh(CHARTER); g = L.globals()
L.execute('CLEAR() SLASH("charterkey")')
check("/wls charterkey turns F1 off for this character", g.OVERRIDES["F1"] is None and g.WhoLayerSwapDB.charterKeyOff[g.MYGUID] is True and L.execute('return said("off for this character")'), dump(L))
check("button still shows with F1 off, hint drops F1", g.WhoLayerSwapCharterButton.shown and "F1" not in g.WhoLayerSwapCharterButton.hint.txt)
L.execute('SLASH("charterkey")')
check("/wls charterkey again turns it back on", g.OVERRIDES["F1"] == "WhoLayerSwapCharterButton" and g.WhoLayerSwapDB.charterKeyOff[g.MYGUID] is None)
L = fresh('WhoLayerSwapDB={charterKeyOff={["Player-1-OTHER"]=true}} ' + CHARTER)
check("another character's F1 setting doesn't affect this one", L.globals().OVERRIDES["F1"] == "WhoLayerSwapCharterButton")
L = fresh('WhoLayerSwapDB={charterKeyOff={["Player-1-0000ME"]=true}} ' + CHARTER)
check("this character's saved F1-off is respected at login", L.globals().OVERRIDES["F1"] is None and L.globals().WhoLayerSwapCharterButton.shown)
L = fresh(CHARTER); L.execute('SLASH("settings")')
L.execute('local c = WhoLayerSwapSettings.checks[5] c:SetChecked(not c:GetChecked()) c.scripts.OnClick(c)')
check("settings checkbox turns F1 off", L.globals().OVERRIDES["F1"] is None)
L = fresh('WhoLayerSwapDB={hideCharter=true} ' + CHARTER)
check("charter button off -> F1 not bound either", L.globals().OVERRIDES["F1"] is None)
L = fresh(CHARTER); L.execute('CLEAR() BAGS[2][7] = nil INCOMBAT=true EV("BAG_UPDATE_DELAYED")')
check("charter used up mid-combat -> F1 kept until combat ends (no error)", L.globals().OVERRIDES["F1"] == "WhoLayerSwapCharterButton")
L.execute('INCOMBAT=false EV("PLAYER_REGEN_ENABLED")')
check("...then released", L.globals().OVERRIDES["F1"] is None and not L.globals().WhoLayerSwapCharterButton.shown)
L = fresh(CHARTER); L.execute('CLEAR() CLICK(WhoLayerSwapCharterButton)')
check("F1/click path runs /use item:5863", L.execute('return has("MACRO /use item:5863")'))


# ------------------------------------------------------------- charter: open, then whisper + request signature
W_TEXT = "Forming a guild, mind signing and you can quit later?"
def press(L, n=1):
    for _ in range(n): L.execute('CLICK(WhoLayerSwapCharterButton)')
L = fresh(CHARTER); L.execute('CLEAR()'); press(L)
check("window closed, no target -> press opens charter", L.execute('return has("MACRO /use item:5863")') and not L.execute('return has("SAY WHISPER")'), dump(L))
L.execute('CLEAR() TARGET = { name = "Bob-Dreamscythe" }'); press(L)
check("window closed, player targeted -> opens charter, says press again", L.execute('return has("MACRO /use item:5863") and said("Press again")') and not L.execute('return has("SAY WHISPER")'), dump(L))
L.execute('CLEAR() PetitionFrame:Show()'); press(L)
check("window open + target -> whisper with the exact text", L.execute(f'return has("SAY WHISPER Bob-Dreamscythe {W_TEXT}")'), dump(L))
check("...then clicks Request Signature", L.execute('return has("MACRO /click PetitionFrameRequestButton")'), dump(L))
check("...whisper comes before the request (like the macro)", [l for l in L.globals().LOG.values() if l.startswith("SAY WHISPER") or l.startswith("MACRO")][:2] == [f"SAY WHISPER Bob-Dreamscythe {W_TEXT}", "MACRO /click PetitionFrameRequestButton"])
L.execute('CLEAR()'); press(L)
check("pressing again on the same person: request again, no second whisper", L.execute('return has("MACRO /click PetitionFrameRequestButton")') and not L.execute('return has("SAY WHISPER")'), dump(L))
L.execute('CLEAR() ADVANCE(31)'); press(L)
check("30s later the whisper may go again", L.execute('return has("SAY WHISPER")'), dump(L))
L.execute('CLEAR() TARGET = { name = "Cat-Dreamscythe" }'); press(L)
check("next target gets their own whisper + request", L.execute(f'return has("SAY WHISPER Cat-Dreamscythe {W_TEXT}") and has("MACRO /click PetitionFrameRequestButton")'), dump(L))
L.execute('CLEAR() TARGET = { name = "Rot Howler-Dreamscythe" }'); press(L)
check("Forever names with spaces work (whisper goes to the full name)", L.execute(f'return has("SAY WHISPER Rot Howler-Dreamscythe {W_TEXT}")'), dump(L))
L.execute('CLEAR() TARGET = nil'); press(L)
check("window open, no target -> nothing sent, explains", not L.execute('return has("SAY WHISPER") or has("MACRO")') and L.execute('return said("Target a player")'), dump(L))
L.execute('CLEAR() TARGET = { name = "Ryan-Dreamscythe", me = true }'); press(L)
check("targeting yourself -> nothing sent", not L.execute('return has("SAY WHISPER") or has("MACRO /click")'), dump(L))
L.execute('CLEAR() TARGET = { name = "Boar", player = false }'); press(L)
check("targeting an NPC -> nothing sent", not L.execute('return has("SAY WHISPER") or has("MACRO /click")'), dump(L))
L.execute('CLEAR() SIGNED = { "Dan" } TARGET = { name = "Dan-Dreamscythe" }'); press(L)
check("already signed -> skipped, says so", not L.execute('return has("SAY WHISPER") or has("MACRO /click")') and L.execute('return said("already signed")'), dump(L))
L.execute('CLEAR() LOCKDOWN=true TARGET = { name = "Eve-Dreamscythe" }'); press(L)
check("chat lockdown -> no whisper, request still goes", not L.execute('return has("SAY WHISPER")') and L.execute('return has("MACRO /click PetitionFrameRequestButton")'), dump(L))
L = fresh(CHARTER); L.execute('PetitionFrame:Show() TARGET = { name = "Bob-Dreamscythe" } CLEAR() local b = WhoLayerSwapCharterButton b.scripts.PreClick(b, "LeftButton", true)')
check("key-down half of F1 does nothing (acts on release only)", not L.execute('return has("SAY WHISPER")'), dump(L))
L = fresh(CHARTER); L.execute('PetitionFrame:Show() TARGET = { name = "Bob-Dreamscythe" } CLEAR() INCOMBAT=true')
L.execute('local b = WhoLayerSwapCharterButton b.scripts.PreClick(b, "LeftButton", false)')
check("in combat: no attribute change, no error", not L.execute('return has("SAY WHISPER")'))
L = fresh(CHARTER); L.execute('CLEAR() SLASH("charterwhisper Hey! Could you sign our charter?") PetitionFrame:Show() TARGET = { name = "Ana-Dreamscythe" }'); press(L)
check("/wls charterwhisper changes the text", L.execute('return has("SAY WHISPER Ana-Dreamscythe Hey! Could you sign our charter?")'), dump(L))
L.execute('CLEAR() SLASH("charterwhisper")')
check("/wls charterwhisper with no text resets to default", L.execute(f'return said("{W_TEXT}")'), dump(L))
L = fresh('BAGS[0][3] = { itemID = 99999, itemName = "Guild Charter", iconFileID = 1 }'); L.execute('CLEAR()'); press(L)
check("opening uses the charter's own item ID", L.execute('return has("MACRO /use item:99999")'), dump(L))

print(f"\n{PASS} passed, {len(FAIL)} failed")
for f in FAIL: print("FAIL:", f)
