-- S'mores group: your own camp items and cooldown, the roster, the other copies' reports (addon messages), and the
-- camp buffs members already wear. Everything here reads the game; Model.lua turns it into a plan.
local _, ns = ...
local D = ns.DATA

ns.PREFIX = "Smores"
local VERSION = "1"
local FEATURE_SPELLS = {}   -- use spell -> itemID (placing one starts the shared hourly cooldown)
for id, it in pairs(D.items) do FEATURE_SPELLS[it.spell] = id end
ns.FEATURE_SPELLS = FEATURE_SPELLS

local function secret(v) return issecretvalue and issecretvalue(v) or false end
ns.secret = secret

-- "Name" for your realm, "Name-Realm" otherwise: the same key from a unit and from an addon message's sender
function ns.UnitKey(unit)
	local name, realm = UnitName(unit)
	if not name or secret(name) then return nil end
	if realm and realm ~= "" and not secret(realm) then return name .. "-" .. realm end
	return name
end
function ns.SenderKey(sender)
	if Ambiguate then return Ambiguate(sender, "none") end
	return (sender:gsub("%-.*", ""))
end

-- ---------------------------------------------------------------- you
-- {[skill line] = skill}, or nil when the client does not answer
local function professions()
	if not (GetProfessions and GetProfessionInfo) then return nil end
	local list = { GetProfessions() }
	local out, any = {}, false
	for k = 1, select("#", GetProfessions()) do
		if list[k] then
			-- pcall: an empty or changing profession slot can throw on this client
			local ok, _, _, skill, _, _, _, skillLine = pcall(GetProfessionInfo, list[k])
			if ok and type(skillLine) == "number" and type(skill) == "number" then out[skillLine] = skill; any = true end
		end
	end
	return any and out or nil
end

local function usable(itemID, it, profs)
	if profs then return (profs[it.skill] or 0) >= it.rank end
	-- professions unreadable: ask the item (it checks the skill requirement)
	local ok, can = pcall(C_Item.IsUsableItem, itemID)   -- pcall: item data may not be loaded yet
	return ok and can and true or false
end

-- your camp items: lines = {[line] = best itemID}, fire = biggest campfire you can build
function ns.ScanSelf()
	local profs = professions()
	local lines, fire, items = {}, nil, {}
	local last = (NUM_BAG_SLOTS or 4) + 1   -- the reagent bag sits after the bags
	for bag = 0, last do
		local n = C_Container.GetContainerNumSlots(bag) or 0
		for slot = 1, n do
			local id = C_Container.GetContainerItemID(bag, slot)
			local it = id and D.items[id]
			if it and not items[id] and usable(id, it, profs) then
				items[id] = true
				if it.fire then
					if not fire or it.fire > fire then fire = it.fire end
				elseif it.line and it.line ~= "util" and it.line ~= "bot" then
					local had = lines[it.line] and D.items[lines[it.line]]
					if not had or (it.tier or 0) > (had.tier or 0) then lines[it.line] = id end
				end
			end
		end
	end
	return lines, fire, items, profs
end

-- the best item per buff line a set of professions can use (what you could drop if you carried it)
function ns.LinesForProfs(profs)
	local lines = {}
	for id, it in pairs(D.items) do
		if it.line and ns.LINE_NAME[it.line] and (profs[it.skill] or 0) >= it.rank then
			local had = lines[it.line] and D.items[lines[it.line]]
			if not had or (it.tier or 0) > (had.tier or 0) then lines[it.line] = id end
		end
	end
	return lines
end

-- copies of the members as if everyone carried the best item their professions allow (unknown professions: as is)
function ns.IdealMembers(members)
	local out = {}
	for i, m in ipairs(members) do
		local c = {}
		for k, v in pairs(m) do if k ~= "_p" then c[k] = v end end
		if m.known and m.profs then
			c.lines = ns.LinesForProfs(m.profs)
			for line, id in pairs(m.lines or {}) do c.lines[line] = c.lines[line] or id end
		end
		out[i] = c
	end
	return out
end

-- seconds left on the shared camp feature cooldown (0 when ready or unknown)
function ns.SelfCooldown(items)
	for id in pairs(items or {}) do
		local it = D.items[id]
		if not it.fire then
			-- pcall: cooldown reads can be restricted; out of combat they answer plain numbers
			local ok, start, duration = pcall(C_Container.GetItemCooldown, id)
			if ok and type(start) == "number" and type(duration) == "number" and not secret(start) and not secret(duration)
				and duration > 2 and start > 0 then
				return math.max(0, start + duration - GetTime())
			end
		end
	end
	return 0
end

function ns.SelfTalents()
	local t = {}
	for line, c in pairs(D.class) do
		if c.talent and IsPlayerSpell and IsPlayerSpell(c.talent) then t[line] = true end
	end
	return t
end

-- ---------------------------------------------------------------- the roster
local RAID_UNITS, PARTY_UNITS = {}, {}
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
for i = 1, 4 do PARTY_UNITS[i] = "party" .. i end

function ns.Units()
	local units = {}
	if IsInRaid() then
		for i = 1, math.min(GetNumGroupMembers(), 40) do units[#units + 1] = RAID_UNITS[i] end
	else
		units[1] = "player"
		if IsInGroup() then
			for i = 1, math.min(GetNumSubgroupMembers(), 4) do units[#units + 1] = PARTY_UNITS[i] end
		end
	end
	return units
end

ns.reports = {}   -- [key] = { lines, fire, cooldownUntil, talents, at } from other copies

-- /smores demo: you (real bags, level, cooldown) plus four made-up members at your level, so the panel can be seen
-- without a group. Nothing is sent while it is on. Each entry: name, class, level offset, items it carries (best per
-- line), fire kit, cooldown seconds, talents, has the addon, professions ([skill line] = rank).
local DEMO = {
	shaman = {
		-- Mana Well, Camp Tent, Journeyman kit; Leatherworking, Alchemy, Cooking
		{ "Kessa", "ROGUE", { 279956, 279978 }, 5, 0, {}, true, { [165] = 150, [171] = 120, [185] = 160 } },
		{ "Torvin", "SHAMAN", {}, nil, 0, {}, false },                         -- no addon
		-- Incense Candle, Camp Chair; Herbalism, Skinning, Fishing (no Fish Bowl in the bags)
		{ "Ilsa", "MAGE", { 279962, 279979 }, nil, 0, {}, true, { [182] = 150, [393] = 150, [356] = 60 } },
		-- First Aid Kit, Faction Banner; First Aid, Tailoring; 20 min cooldown
		{ "Brannoch", "PRIEST", { 279968, 279972 }, nil, 1200, {}, true, { [129] = 150, [197] = 150 } },
	},
	paladin = {
		{ "Kessa", "ROGUE", { 279956, 279978 }, 5, 0, {}, true, { [165] = 150, [171] = 120, [185] = 160 } },
		-- Fish Bowl; has Kings; Fishing, Mining (no Lodestone in the bags)
		{ "Aldric", "PALADIN", { 279967 }, nil, 0, { kings = true }, true, { [356] = 100, [186] = 120 } },
		{ "Ilsa", "MAGE", { 279962, 279979 }, nil, 0, {}, true, { [182] = 150, [393] = 150, [356] = 60 } },
		{ "Brannoch", "PRIEST", {}, nil, 0, {}, false },
	},
}
ns.DEMO_KINDS = { "shaman", "paladin" }

local function demoMembers(db, own)
	local level = UnitLevel("player")
	if type(level) ~= "number" or secret(level) or level <= 0 then level = 60 end
	local _, class = UnitClass("player")
	local me = ns.UnitKey("player") or "You"
	local out = { { key = me, name = (me:gsub("%-.*", "")), unit = "player", class = class or "WARRIOR", level = level,
		role = (db.roles and db.roles[me]) or ns.DefaultRole(class or "WARRIOR"), self = true, known = true,
		lines = own.lines, fire = own.fire, cooldown = own.cooldown, talents = own.talents, profs = own.profs } }
	for _, d in ipairs(DEMO[ns.demo] or DEMO.shaman) do
		local m = { key = d[1], name = d[1], class = d[2], level = level, role = (db.roles and db.roles[d[1]]) or ns.DefaultRole(d[2]),
			talents = d[6], known = d[7] }
		if m.known then
			m.lines, m.fire, m.cooldown, m.profs = {}, d[4], d[5], d[8]
			for _, id in ipairs(d[3]) do m.lines[D.items[id].line] = id end
		end
		out[#out + 1] = m
	end
	return out
end

-- ---------------------------------------------------------------- plan mode: a party or raid you make up
-- db.planRoster = { { class, level, role }, ... } (up to 20). The same roster travels as a short string between the
-- addon and the companion site: SM1:<goal L|P|A>:<class code><role letter><level>,...  e.g. SM1:P:WAt60,ROm60,PAh58
-- (CW1: codes from when it was called Campwise still load)
ns.PLAN_MAX = 20
ns.CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "SHAMAN", "PALADIN" }
local CLASS_CODE = { WARRIOR = "WA", ROGUE = "RO", HUNTER = "HU", MAGE = "MA", WARLOCK = "WL", PRIEST = "PR",
	DRUID = "DR", SHAMAN = "SH", PALADIN = "PA" }
local CODE_CLASS = {}
for c, k in pairs(CLASS_CODE) do CODE_CLASS[k] = c end
local ROLE_CODE = { tank = "t", melee = "m", ranged = "r", caster = "c", healer = "h" }
local CODE_ROLE = {}
for r, k in pairs(ROLE_CODE) do CODE_ROLE[k] = r end
local GOAL_CODE = { level = "L", progress = "P" }

function ns.ClassName(class)
	local n = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
	if type(n) == "string" and n ~= class then return n end
	return class:sub(1, 1) .. class:sub(2):lower()
end

function ns.PlanMembers(db)
	local out, seen = {}, {}
	for i, e in ipairs(db.planRoster or {}) do
		local base = ns.ClassName(e.class)
		seen[base] = (seen[base] or 0) + 1
		local name = seen[base] > 1 and (base .. " " .. seen[base]) or base
		out[#out + 1] = { key = "p" .. i, name = name, class = e.class, level = e.level or 60,
			role = e.role or ns.DefaultRole(e.class), talents = {}, known = false, planIndex = i }
	end
	-- a planned paladin, priest or druid is taken to have the talent buffs (Kings, Divine Spirit, Moonkin)
	for _, m in ipairs(out) do
		for line, c in pairs(D.class) do
			if c.kind == "talent" or line == "kings" then
				if c.class == m.class and (line ~= "crit" or m.role == "caster") then m.talents[line] = true end
			end
		end
	end
	return out
end

function ns.ExportPlan(roster, goal)
	local t = {}
	for _, e in ipairs(roster or {}) do
		t[#t + 1] = (CLASS_CODE[e.class] or "WA") .. (ROLE_CODE[e.role] or "m") .. math.floor(e.level or 60)
	end
	return ("SM1:%s:%s"):format(GOAL_CODE[goal] or "A", table.concat(t, ","))
end

-- returns roster, goal ("level" | "progress" | nil = by level); nil when the string is not a S'mores plan
function ns.ImportPlan(text)
	local g, list = (text or ""):match("SM1:([LPA]):(%S*)")
	if not g then g, list = (text or ""):match("CW1:([LPA]):(%S*)") end
	-- the site's extras after a member: planned professions ("-BsMi") and a name ("~Alcara", any letters): in game the
	-- real professions and names count
	list = list and list:gsub("~[^,]*", ""):gsub("%-%a*", "")
	if not g then return nil end
	local roster = {}
	for code, role, level in list:gmatch("(%u%u)(%l)(%d+)") do
		local class = CODE_CLASS[code]
		if class and #roster < ns.PLAN_MAX then
			level = math.max(1, math.min(60, tonumber(level)))
			roster[#roster + 1] = { class = class, role = CODE_ROLE[role] or ns.DefaultRole(class), level = level }
		end
	end
	return roster, (g == "L" and "level") or (g == "P" and "progress") or nil
end

-- members for the model; db.roles holds the roles the user picked
function ns.Members(db, own)
	if ns.demo then return demoMembers(db, own) end
	local out, me = {}, ns.UnitKey("player")
	for _, unit in ipairs(ns.Units()) do
		local key = ns.UnitKey(unit)
		local _, class = UnitClass(unit)
		local level = UnitLevel(unit)
		if key and class and type(level) == "number" and not secret(level) then
			if level <= 0 then level = 60 end   -- unknown (??): treat as the cap
			local assigned = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
			if secret(assigned) then assigned = nil end
			local m = { key = key, name = (key:gsub("%-.*", "")), unit = unit, class = class, level = level,
				role = (db.roles and db.roles[key]) or ns.DefaultRole(class, assigned), talents = {} }
			if key == me then
				m.self, m.known = true, true
				m.lines, m.fire, m.cooldown, m.talents, m.profs = own.lines, own.fire, own.cooldown, own.talents, own.profs
			else
				local r = ns.reports[key]
				if r then
					m.known = true
					m.lines, m.fire, m.talents, m.profs = r.lines, r.fire, r.talents, r.profs
					m.cooldown = math.max(0, (r.cooldownUntil or 0) - GetTime())
				end
			end
			out[#out + 1] = m
		end
	end
	return out
end

-- ---------------------------------------------------------------- what members wear (out of combat only)
-- seen[line] = a talent class buff someone wears (so the caster has the talent); applied[line] = a camp buff is up
function ns.ScanAuras(members)
	local seen, applied = {}, {}
	if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID) then return seen, applied end
	for _, m in ipairs(members) do
		if not m.unit then break end   -- demo members have no unit (they come after you)
		for line, c in pairs(D.class) do
			if c.talent and not seen[line] then
				for _, id in ipairs(c.auras) do
					-- pcall: a unit out of range or a restricted aura read can throw
					local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, m.unit, id)
					if ok and aura ~= nil and not secret(aura) then seen[line] = true break end
				end
			end
		end
		for line, c in pairs(D.camp) do
			if not applied[line] then
				local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, m.unit, c.aura)
				if ok and aura ~= nil and not secret(aura) then applied[line] = true end
			end
		end
	end
	return seen, applied
end

-- ---------------------------------------------------------------- addon messages
-- H1:<itemIDs, best per line + biggest fire kit>:<cooldown seconds left>:<talent lines>:<skill line=rank,...>
-- (the professions field came with 0.1.2; older copies leave it out)   Q1 = please send yours
function ns.HelloText(own)
	local ids = {}
	for _, id in pairs(own.lines or {}) do ids[#ids + 1] = id end
	if own.fire then
		for id, it in pairs(D.items) do if it.fire == own.fire then ids[#ids + 1] = id break end end
	end
	table.sort(ids)
	local t = {}
	for line in pairs(own.talents or {}) do t[#t + 1] = line end
	table.sort(t)
	local p = {}
	for line, rank in pairs(own.profs or {}) do p[#p + 1] = line .. "=" .. rank end
	table.sort(p)
	return ("H%s:%s:%d:%s:%s"):format(VERSION, table.concat(ids, ","), math.floor(own.cooldown or 0), table.concat(t, ","),
		table.concat(p, ","))
end

function ns.ParseHello(text)
	local v, ids, cd, talents, profs = text:match("^H(%d+):([%d,]*):(%d+):([%a,]*):?([%d=,]*)$")
	if not v then return nil end
	local r = { lines = {}, talents = {}, cooldownUntil = GetTime() + tonumber(cd) }
	for id in ids:gmatch("%d+") do
		local it = D.items[tonumber(id)]
		if it and it.fire then
			if not r.fire or it.fire > r.fire then r.fire = it.fire end
		elseif it and it.line and ns.LINE_NAME[it.line] then
			r.lines[it.line] = tonumber(id)
		end
	end
	for line in talents:gmatch("%a+") do
		if D.class[line] then r.talents[line] = true end
	end
	for skill, rank in profs:gmatch("(%d+)=(%d+)") do
		r.profs = r.profs or {}
		r.profs[tonumber(skill)] = tonumber(rank)
	end
	return r
end

function ns.Channel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

-- returns true when sent; never in combat or while chat is restricted
function ns.SendAddon(text)
	if ns.demo then return false end   -- the demo talks to nobody
	local channel = ns.Channel()
	if not channel or InCombatLockdown() then return false end
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false end
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, ns.PREFIX, text, channel)   -- pcall: throttled or blocked sends throw on some builds
	return ok and (result == nil or result == 0 or result == true)
end
