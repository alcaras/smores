-- S'mores: plans the group's camp. Each member drops at most one camp feature an hour; class buffs beat their camp
-- copies, so the plan fills what the group's classes leave open, choosing the paladins' blessings with it.
-- Works alone (your bags, the group's classes and levels); with other copies in the group it plans for them too.
local ADDON, ns = ...
local D = ns.DATA
local f = ns.frame

local CAMPFIRE_NEARBY, WELCOMING = 1283391, 1229739   -- auras: smoke of a fire nearby / sitting at a fire
local REFRESH_EVERY = 5      -- seconds, only while the panel is open
local HELLO_GAP = 2          -- seconds between two of our addon messages
local DISMISS_FOR = 900      -- an auto-opened panel closed by hand stays closed this long (a fire lasts 15 min)

-- goal: nil = by your level (leveling below the cap, progression at it), "level", "progress"; scope: "party" | "you"
local defaults = { roles = {}, auto = true, uptime = 70, grid = false, scope = "party" }
local db
local me
local own = { lines = {}, items = {}, talents = {}, cooldown = 0 }
local lastHello, lastHelloAt, helloPending = nil, -100, false
local reopenAfterCombat, dismissedUntil, autoOpened = false, 0, false
local rosterSig

local function say(msg) print("|cff7fbf7fS'mores|r: " .. msg) end
ns.say = say

-- ---------------------------------------------------------------- refresh
local theory, theorySig
local planTheory, planSig

local function rescanSelf()
	own.lines, own.fire, own.items, own.profs = ns.ScanSelf()
	own.cooldown = ns.SelfCooldown(own.items)
	own.talents = ns.SelfTalents()
end

-- plan mode: the made-up roster, the theory as the camp, nothing read from bags or the group
local function refreshPlan()
	local members = ns.PlanMembers(db)
	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
	local opts = { uptime = (db.uptime or 70) / 100, maxLevel = maxLevel, seen = {}, goal = ns.Goal(members) }
	-- the roster only changes on a click: work the theory out again only then (a 20-member raid costs a few ms)
	local sig = ns.ExportPlan(db.planRoster, opts.goal) .. opts.uptime
	if sig ~= planSig then planTheory, planSig = ns.Theory(members, opts), sig end
	opts.camp = planTheory.lines
	local plan = ns.Plan(members, opts)
	local theory = planTheory
	ns.lastPlan, ns.lastMembers, ns.lastIdeal, ns.lastTheory = plan, members, nil, theory
	ns.Render({ plan = plan, theory = nil, members = members, applied = {}, planMode = true,
		level = members[1] and members[1].level or 60, uptime = opts.uptime,
		code = ns.ExportPlan(db.planRoster, db.goal) })
end

function ns.Refresh()
	if not db or not f:IsShown() or InCombatLockdown() then return end
	if ns.planMode then return refreshPlan() end
	own.cooldown = ns.SelfCooldown(own.items)
	local members = ns.Members(db, own)
	local seen, applied = ns.ScanAuras(members)
	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
	local opts = { uptime = (db.uptime or 70) / 100, maxLevel = maxLevel, seen = seen, goal = ns.Goal(),
		focus = db.scope == "you" and me or nil }
	local plan = ns.Plan(members, opts)
	local ideal = ns.Plan(ns.IdealMembers(members), opts)   -- as if everyone carried their professions' best item
	-- ignoring professions: depends only on who is here and the options, so it is worked out again only when those change
	local sig = { opts.goal, tostring(opts.focus), opts.uptime, maxLevel }
	for _, m in ipairs(members) do sig[#sig + 1] = m.key .. m.class .. m.level .. m.role end
	for line in pairs(seen) do sig[#sig + 1] = line end
	sig = table.concat(sig, "|")
	if sig ~= theorySig then theory, theorySig = ns.Theory(members, opts), sig end
	ns.lastPlan, ns.lastMembers, ns.lastIdeal, ns.lastTheory = plan, members, ideal, theory
	ns.Render({ plan = plan, ideal = ideal, theory = theory, members = members, applied = applied, me = me,
		level = UnitLevel("player") or 60, uptime = (db.uptime or 70) / 100 })
end

local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)   -- runs only while the panel is shown
	elapsed = elapsed + dt
	if elapsed >= REFRESH_EVERY then elapsed = 0; ns.Refresh() end
end)
f:SetScript("OnShow", function() elapsed = 0; ns.Refresh() end)

-- the goal in use: the saved choice, else by level (your level, or in plan mode the roster's highest)
function ns.Goal(members)
	if db and db.goal then return db.goal end
	local level, cap = UnitLevel("player"), GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
	if members and members[1] then
		level = 0
		for _, m in ipairs(members) do level = math.max(level, m.level) end
	end
	if type(level) == "number" and not ns.secret(level) and level > 0 and level < cap then return "level" end
	return "progress"
end
function ns.ToggleGoal()
	db.goal = ns.Goal(ns.planMode and ns.lastMembers or nil) == "level" and "progress" or "level"
	ns.Refresh()
end
function ns.ToggleScope()
	db.scope = db.scope == "you" and "party" or "you"
	ns.Refresh()
end

function ns.CycleRole(key)
	if not key or not db then return end
	if ns.planMode then
		local i = tonumber(key:match("^p(%d+)$"))
		local e = i and db.planRoster[i]
		if not e then return end
		local nextRole = ns.ROLES[1]
		for j, r in ipairs(ns.ROLES) do if r == e.role then nextRole = ns.ROLES[j % #ns.ROLES + 1] end end
		e.role = nextRole
		return ns.Refresh()
	end
	local current
	for _, m in ipairs(ns.lastMembers or {}) do if m.key == key then current = m.role end end
	local nextRole = ns.ROLES[1]
	for i, r in ipairs(ns.ROLES) do if r == current then nextRole = ns.ROLES[i % #ns.ROLES + 1] end end
	db.roles[key] = nextRole
	ns.Refresh()
end

-- ---------------------------------------------------------------- plan mode
local function planLevel()
	local level = UnitLevel("player")
	if type(level) ~= "number" or ns.secret(level) or level <= 0 then level = 60 end
	return level
end

-- a first roster: the group you are in (classes, levels, roles), else you alone
local function seedRoster()
	local roster = {}
	for _, m in ipairs(ns.Members(db, own)) do
		if #roster < ns.PLAN_MAX then roster[#roster + 1] = { class = m.class, level = m.level, role = m.role } end
	end
	if #roster == 0 then
		local _, class = UnitClass("player")
		roster[1] = { class = class or "WARRIOR", level = planLevel(), role = ns.DefaultRole(class or "WARRIOR") }
	end
	return roster
end

function ns.SetPlanMode(on)
	ns.planMode = on and true or nil
	if on then
		ns.demo = nil
		if not db.planRoster or #db.planRoster == 0 then db.planRoster = seedRoster() end
	end
	ns.lastPlan = nil
	if f:IsShown() then ns.Refresh() else autoOpened = false; f:Show() end
end

function ns.CycleClass(i)
	local e = i and db.planRoster[i]
	if not e then return end
	local nextClass = ns.CLASSES[1]
	for j, c in ipairs(ns.CLASSES) do if c == e.class then nextClass = ns.CLASSES[j % #ns.CLASSES + 1] end end
	e.class, e.role = nextClass, ns.DefaultRole(nextClass)
	ns.Refresh()
end

function ns.RemovePlanMember(i)
	if i and db.planRoster[i] then table.remove(db.planRoster, i) end
	ns.Refresh()
end

-- adds the first class the roster lacks (or a warrior), at the roster's level
function ns.AddPlanMember(class, level, role)
	if #db.planRoster >= ns.PLAN_MAX then say(("a plan holds up to %d."):format(ns.PLAN_MAX)) return end
	if not class then
		local have = {}
		for _, e in ipairs(db.planRoster) do have[e.class] = true end
		for _, c in ipairs(ns.CLASSES) do if not have[c] then class = c break end end
		class = class or "WARRIOR"
	end
	level = level or (db.planRoster[1] and db.planRoster[1].level) or planLevel()
	db.planRoster[#db.planRoster + 1] = { class = class, level = level, role = role or ns.DefaultRole(class) }
	ns.Refresh()
end

function ns.ImportCode(text)
	local roster, goal = ns.ImportPlan(text)
	if not roster or #roster == 0 then say("that is not an S'mores plan code (it starts with SM1:).") return end
	db.planRoster, db.goal = roster, goal
	say(("plan loaded: %d members."):format(#roster))
	ns.SetPlanMode(true)
end

local CLASS_WORDS = { warrior = "WARRIOR", rogue = "ROGUE", hunter = "HUNTER", mage = "MAGE", warlock = "WARLOCK",
	priest = "PRIEST", druid = "DRUID", shaman = "SHAMAN", paladin = "PALADIN" }

local function planSlash(arg)
	local sub, rest = arg:match("^(%S*)%s*(.-)$")
	if sub == "" then
		ns.SetPlanMode(not ns.planMode)
		say(ns.planMode and "plan mode: click a name to change the class, a role to change it; + Add, x to remove. "
			.. "/smores plan off to leave." or "plan mode off.")
	elseif sub == "off" then
		ns.SetPlanMode(false)
	elseif sub == "clear" then
		db.planRoster = {}
		ns.SetPlanMode(true)
	elseif sub == "add" then
		local class, level, role = rest:match("^(%a+)%s*(%d*)%s*(%a*)$")
		class = class and CLASS_WORDS[class]
		if not class then say("/smores plan add <class> [level] [tank|melee|ranged|caster|healer]") return end
		if not ns.planMode then ns.SetPlanMode(true) end
		ns.AddPlanMember(class, tonumber(level), ns.WEIGHTS[role] and role or nil)
	elseif sub == "level" and tonumber(rest) then
		local level = math.max(1, math.min(60, math.floor(tonumber(rest))))
		for _, e in ipairs(db.planRoster or {}) do e.level = level end
		ns.SetPlanMode(true)
	elseif CLASS_WORDS[sub] then
		-- /smores plan warrior rogue mage priest paladin: a whole roster at once
		local roster = {}
		for word in arg:gmatch("%a+") do
			local c = CLASS_WORDS[word]
			if c and #roster < ns.PLAN_MAX then roster[#roster + 1] = { class = c, level = planLevel(), role = ns.DefaultRole(c) } end
		end
		db.planRoster = roster
		ns.SetPlanMode(true)
	else
		say("/smores plan [off | clear | add <class> [level] [role] | level <n> | <class> <class> ...]")
	end
end

-- ---------------------------------------------------------------- talking to the other copies
local function sendHello(force)
	if not ns.Channel() then return end
	local text = ns.HelloText(own)
	local now = GetTime()
	if not force and text == lastHello and now - lastHelloAt < 60 then return end
	if now - lastHelloAt < HELLO_GAP or InCombatLockdown() then
		if not helloPending then
			helloPending = true
			C_Timer.After(HELLO_GAP, function() helloPending = false; sendHello(true) end)
		end
		return
	end
	if ns.SendAddon(text) then lastHello, lastHelloAt = text, now end
end
ns.SendHello = sendHello

local function onRoster()
	local keys = {}
	for _, unit in ipairs(ns.Units()) do keys[#keys + 1] = ns.UnitKey(unit) or "?" end
	table.sort(keys)
	local sig = table.concat(keys, ",")
	if sig == rosterSig then return end
	local joined = not rosterSig or #sig > #rosterSig
	rosterSig = sig
	local present = {}
	for _, k in ipairs(keys) do present[k] = true end
	for k in pairs(ns.reports) do if not present[k] then ns.reports[k] = nil end end
	if ns.Channel() and joined then
		ns.SendAddon("Q1")
		sendHello(true)
	end
	ns.Refresh()
end

-- ---------------------------------------------------------------- posting the plan
function ns.Post()
	local plan, members = ns.lastPlan, ns.lastMembers
	if not plan then return end
	if InCombatLockdown() then say("not in combat.") return end
	local text = ns.PostText(plan, members)
	local channel = ns.Channel()
	if ns.demo then say("(demo, not sent) " .. text) return end
	if not channel then say(text) return end   -- alone: show it to you only
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then say("chat is restricted right now.") return end
	C_ChatInfo.SendChatMessage(text, channel)
end

-- ---------------------------------------------------------------- opening by itself at a fire
local function nearFire()
	if InCombatLockdown() or not C_UnitAuras.GetPlayerAuraBySpellID then return false end
	for _, id in ipairs({ CAMPFIRE_NEARBY, WELCOMING }) do
		local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)   -- pcall: restricted aura reads can throw
		if ok and aura ~= nil and not ns.secret(aura) then return true end
	end
	return false
end


local function checkFire()
	if not db or not db.auto or f:IsShown() or not IsInGroup() or GetTime() < dismissedUntil then return end
	if nearFire() then
		autoOpened = true
		f:Show()
	end
end
f:HookScript("OnHide", function()
	if autoOpened and not InCombatLockdown() and not reopenAfterCombat then dismissedUntil = GetTime() + DISMISS_FOR end
	autoOpened = false
end)

-- ---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
	if event == "ADDON_LOADED" then
		if a1 ~= ADDON then return end
		SmoresDB = SmoresDB or {}
		db = SmoresDB
		for k, v in pairs(defaults) do if db[k] == nil then db[k] = v end end
		ns.db = db
		if C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX) end
	elseif event == "PLAYER_LOGIN" then
		me = ns.UnitKey("player")
		rescanSelf()
		if db and db.pos then
			-- pcall: a saved anchor can fail to resolve; the load-time position stays then
			pcall(function()
				f:ClearAllPoints()
				f:SetPoint(db.pos[1], UIParent, db.pos[2], db.pos[3], db.pos[4])
			end)
		end
		onRoster()
	elseif event == "GROUP_ROSTER_UPDATE" then
		onRoster()
	elseif event == "BAG_UPDATE_DELAYED" or event == "SKILL_LINES_CHANGED" or event == "PLAYER_LEVEL_UP" then
		rescanSelf()
		sendHello(false)
		ns.Refresh()
	elseif event == "CHAT_MSG_ADDON" then
		if a1 ~= ns.PREFIX or type(a2) ~= "string" or type(a4) ~= "string" then return end
		local key = ns.SenderKey(a4)
		if key == me then return end
		if a2:sub(1, 1) == "Q" then
			sendHello(true)
		elseif a2:sub(1, 1) == "H" then
			local r = ns.ParseHello(a2)
			if r then ns.reports[key] = r; ns.Refresh() end
		end
	elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
		if not ns.secret(a3) and ns.FEATURE_SPELLS[a3] and not D.items[ns.FEATURE_SPELLS[a3]].fire then
			C_Timer.After(1, function() rescanSelf(); sendHello(true); ns.Refresh() end)
		end
	elseif event == "UNIT_AURA" then
		checkFire()
	elseif event == "PLAYER_REGEN_DISABLED" then
		if f:IsShown() then reopenAfterCombat = true; f:Hide() end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if reopenAfterCombat then reopenAfterCombat = false; f:Show() end
	end
end)

-- ---------------------------------------------------------------- slash
SLASH_SMORES1 = "/smores"
SLASH_SMORES2 = "/smore"
SlashCmdList.SMORES = function(msg)
	local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "" then
		if f:IsShown() then f:Hide() else autoOpened = false; f:Show() end
	elseif cmd == "plan" then
		planSlash(arg)
	elseif cmd == "import" then
		local code = (msg or ""):match("[SsCc][MmWw]1:%S*")   -- from the message as typed: the code is case-sensitive
		ns.ImportCode(code and (code:sub(1, 3):upper() .. code:sub(4)) or "")
	elseif cmd == "export" then
		if not ns.planMode then ns.SetPlanMode(true) end
		f.code:Show()
		ns.Refresh()
		f.code:SetFocus()
	elseif cmd == "demo" then
		if arg == "off" or (arg == "" and ns.demo) then
			ns.demo = nil
			say("demo off.")
		else
			ns.demo, ns.planMode = (arg == "paladin") and "paladin" or "shaman", nil
			say(("demo on: you and four made-up members (%s group). Nothing is sent. /smores demo paladin | shaman | off"):format(ns.demo))
		end
		ns.lastPlan = nil
		if f:IsShown() then ns.Refresh() else autoOpened = false; f:Show() end
	elseif cmd == "goal" and (arg == "leveling" or arg == "level" or arg == "progress" or arg == "progression" or arg == "auto") then
		if arg == "auto" then db.goal = nil
		else db.goal = (arg == "progress" or arg == "progression") and "progress" or "level" end
		say(("planning for %s%s."):format(ns.Goal() == "level" and "leveling (XP)" or "progression", db.goal and "" or " (by your level)"))
		ns.Refresh()
	elseif cmd == "for" and (arg == "party" or arg == "you" or arg == "me") then
		db.scope = (arg == "party") and "party" or "you"
		say(db.scope == "you" and "planning for you (your class and role)." or "planning for the party.")
		ns.Refresh()
	elseif cmd == "post" then
		if not ns.lastPlan then ns.Refresh() end
		ns.Post()
	elseif cmd == "auto" and (arg == "on" or arg == "off") then
		db.auto = arg == "on"
		say("open at a campfire: " .. arg .. ".")
	elseif cmd == "uptime" and tonumber(arg) then
		db.uptime = math.max(0, math.min(100, math.floor(tonumber(arg))))
		say(("totems count at %d%% uptime."):format(db.uptime))
		ns.Refresh()
	elseif cmd == "reset" then
		db.pos, db.roles = nil, {}
		f:ClearAllPoints()
		f:SetPoint(ns.LAYOUT.point[1], UIParent, ns.LAYOUT.point[3], ns.LAYOUT.point[4], ns.LAYOUT.point[5])
		say("position and roles reset.")
		ns.Refresh()
	else
		say("/smores (open or close) | plan [...] | import <code> | export | demo [shaman|paladin|off] | "
			.. "goal leveling|progress|auto | for party|you | post | auto on|off | uptime <0-100> | reset")
	end
end
