-- S'mores model: what each buff is worth to each member, and the plan (who drops what, which blessing goes where).
-- Pure Lua on plain tables (no game calls), so the harness can drive it directly.
local _, ns = ...
local D = ns.DATA

-- display order; tent last (rested XP, no stat)
ns.LINES = { "sta", "motw", "kings", "str", "ap", "mp5", "spi", "int", "crit", "tent" }
ns.LINE_NAME = {
	sta = "Stamina", motw = "Armor, stats", kings = "Stats %", str = "Strength", ap = "Melee AP", mp5 = "Mana / 5",
	spi = "Spirit", int = "Intellect", crit = "Crit", tent = "Rested XP",
}
ns.BLESSINGS = { "kings", "ap", "mp5" }
ns.CAMP_NAME = {}   -- line -> tier 1 feature name ("Fish Bowl")
for _, it in pairs(D.items) do
	if it.tier == 1 and it.line then ns.CAMP_NAME[it.line] = it.name end
end

-- How much one point of each stat is worth to a role. Rough on purpose: the plan only needs the order right.
-- crit is per 1%; armor and resistances per point; pct (Kings) goes through the estimated stats below.
local WEIGHTS = {
	tank = { sta = 1.0, armor = 0.05, str = 0.6, agi = 0.6, int = 0, spi = 0, ap = 0.15, mp5 = 0, crit = 6, res = 0.1 },
	melee = { sta = 0.3, armor = 0.01, str = 1.0, agi = 1.0, int = 0, spi = 0, ap = 0.5, mp5 = 0, crit = 20, res = 0.05 },
	ranged = { sta = 0.3, armor = 0.01, str = 0, agi = 1.0, int = 0.4, spi = 0.1, ap = 0, mp5 = 1.0, crit = 20, res = 0.05 },
	caster = { sta = 0.3, armor = 0.01, str = 0, agi = 0, int = 1.0, spi = 0.4, ap = 0, mp5 = 2.0, crit = 12, res = 0.05 },
	healer = { sta = 0.3, armor = 0.01, str = 0, agi = 0, int = 1.0, spi = 0.7, ap = 0, mp5 = 2.5, crit = 6, res = 0.05 },
}
ns.ROLES = { "tank", "melee", "ranged", "caster", "healer" }
ns.WEIGHTS = WEIGHTS
-- the goal: "level" (XP: the tent's rested XP counts, mana and spirit mean less drinking) or "progress" (power only)
local REST = { level = 60, progress = 0 }   -- the tent's rested XP, for a member below the level cap
local BOOST = { level = { mp5 = 1.5, spi = 1.5, sta = 1.2 }, progress = {} }
ns.GOALS = { "level", "progress" }

-- class -> role when the group has no assigned roles (the user can click a row to change it)
local DEFAULT_ROLE = {
	WARRIOR = "melee", ROGUE = "melee", HUNTER = "ranged", MAGE = "caster", WARLOCK = "caster",
	PRIEST = "healer", DRUID = "healer", SHAMAN = "healer", PALADIN = "healer",
}
local DAMAGER_ROLE = { PALADIN = "melee", SHAMAN = "melee", DRUID = "melee", PRIEST = "caster" }
function ns.DefaultRole(class, assigned)
	if assigned == "TANK" then return "tank" end
	if assigned == "HEALER" then return "healer" end
	if assigned == "DAMAGER" then return DAMAGER_ROLE[class] or DEFAULT_ROLE[class] or "melee" end
	return DEFAULT_ROLE[class] or "melee"
end

-- value of a {from level, value} step list at a level (0 below the first step)
function ns.Step(steps, level)
	local v = 0
	for _, s in ipairs(steps) do
		if level >= s[1] then v = s[2] else break end
	end
	return v
end

local function amounts(entry, level)
	local out = {}
	for comp, steps in pairs(entry.comp) do out[comp] = ns.Step(steps, level) end
	return out
end
function ns.CampAmounts(line, level) return amounts(D.camp[line], level) end
function ns.ClassAmounts(line, level) return amounts(D.class[line], level) end

-- a rough stat of a level (Kings and the Fish Bowl are a percentage of it)
local function estStat(level) return 2 * level + 20 end

local function worth(role, level, amts, goal)
	local w = WEIGHTS[role] or WEIGHTS.melee
	local b = BOOST[goal or "progress"] or BOOST.progress
	local all = w.str + w.agi + w.sta * (b.sta or 1) + w.int + w.spi * (b.spi or 1)
	local v = 0
	for comp, x in pairs(amts) do
		if comp == "stat" then v = v + x * all
		elseif comp == "res" then v = v + x * w.res * 5
		elseif comp == "pct" then v = v + x / 100 * estStat(level) * all
		else v = v + x * (w[comp] or 0) * (b[comp] or 1) end
	end
	return v
end
ns.Worth = worth

-- Precompute what each member gets per line from every source. Members:
--   { key, name, class, level, role, known, lines = {[line] = itemID}, fire, cooldown, talents = {[line] = true} }
-- opts: { uptime = 0..1 (totems), maxLevel, seen = {[line] = true} (talent buffs seen on someone),
--         goal = "level" | "progress", focus = a member key (plan for that member only; nil = the whole group) }
local function prepare(members, opts)
	local best = {}            -- class -> highest level in the group
	local paladins, talentBy = 0, {}
	for _, m in ipairs(members) do
		best[m.class] = math.max(best[m.class] or 0, m.level)
		if m.class == "PALADIN" then paladins = paladins + 1 end
		for line in pairs(m.talents or {}) do talentBy[line] = math.max(talentBy[line] or 0, m.level) end
	end
	local seen = opts.seen or {}
	local goal = opts.goal or "progress"
	local info = { paladins = paladins, subsets = {}, kings = false, focus = opts.focus }
	-- a paladin's Kings counts when one reports the talent or someone wears it
	if paladins > 0 and (talentBy.kings or seen.kings) then info.kings = true end
	local avail = {}
	for _, b in ipairs(ns.BLESSINGS) do
		if b ~= "kings" or info.kings then avail[#avail + 1] = b end
	end
	-- every set of at most `paladins` different blessings
	local n = #avail
	for mask = 0, 2 ^ n - 1 do
		local set, size, x = {}, 0, mask
		for i = 1, n do
			if x % 2 == 1 then set[#set + 1] = avail[i]; size = size + 1 end
			x = math.floor(x / 2)
		end
		if size <= paladins then info.subsets[#info.subsets + 1] = set end
	end
	for _, m in ipairs(members) do
		local p = { base = {}, camp = {}, full = {}, bless = {} }
		for _, line in ipairs(ns.LINES) do
			if line == "tent" then
				local v = (m.level < (opts.maxLevel or 60)) and REST[goal] or 0
				p.camp[line], p.full[line], p.base[line] = v, v, 0
			else
				p.camp[line] = worth(m.role, m.level, ns.CampAmounts(line, m.level), goal)
				-- a full set: the class buff of your level, or the camp copy where that is more (no class buff yet)
				p.full[line] = math.max(worth(m.role, m.level, ns.ClassAmounts(line, m.level), goal), p.camp[line])
				local c = D.class[line]
				local base = 0
				if c.kind == "all" and best[c.class] then
					base = worth(m.role, m.level, ns.ClassAmounts(line, best[c.class]), goal)
				elseif c.kind == "talent" and (talentBy[line] or seen[line]) then
					base = worth(m.role, m.level, ns.ClassAmounts(line, talentBy[line] or best[c.class] or m.level), goal)
				elseif c.kind == "totem" and best[c.class] then
					base = worth(m.role, m.level, ns.ClassAmounts(line, best[c.class]), goal) * (opts.uptime or 0.7)
				elseif c.kind == "blessing" and best.PALADIN and (line ~= "kings" or info.kings) then
					p.bless[line] = worth(m.role, m.level, ns.ClassAmounts(line, best.PALADIN), goal)
				end
				p.base[line] = base
			end
		end
		m._p = p
	end
	return info
end

-- one member's total for a camp set, and the blessings that give it
local function memberScore(m, camp, info)
	local p, total = m._p, 0
	for _, line in ipairs(ns.LINES) do
		if not p.bless[line] then
			total = total + math.max(p.base[line], camp[line] and p.camp[line] or 0)
		end
	end
	if info.paladins == 0 then return total, nil end
	local bestV, bestSet = -1, nil
	for _, set in ipairs(info.subsets) do
		local v = 0
		for _, b in ipairs(ns.BLESSINGS) do
			if p.bless[b] then
				local given = false
				for _, s in ipairs(set) do if s == b then given = true end end
				v = v + math.max(given and p.bless[b] or 0, camp[b] and p.camp[b] or 0)
			end
		end
		if v > bestV + 1e-9 then bestV, bestSet = v, set end
	end
	return total + math.max(bestV, 0), bestSet
end

local function score(members, camp, info)
	local s = 0
	for _, m in ipairs(members) do
		if not info.focus or m.key == info.focus then s = s + (memberScore(m, camp, info)) end
	end
	return s
end

-- The theoretical best for this group, ignoring professions (Cooking too: an Expert fire): the set of buff lines,
-- one feature per member at most, that scores highest. Returns { lines = {line, ...}, pct }.
function ns.Theory(members, opts)
	local copies = {}
	for i, m in ipairs(members) do
		local c = {}
		for k, v in pairs(m) do if k ~= "_p" then c[k] = v end end
		copies[i] = c
	end
	local info = prepare(copies, opts or {})
	local n = #ns.LINES
	local k = math.min(10, #copies)
	local bestS, bestMask, camp = -1, 0, {}
	for mask = 0, 2 ^ n - 1 do
		local x, size = mask, 0
		for i = 1, n do
			if x % 2 == 1 then camp[ns.LINES[i]] = true; size = size + 1 else camp[ns.LINES[i]] = nil end
			x = math.floor(x / 2)
		end
		if size <= k then
			local s = score(copies, camp, info)
			if s > bestS + 1e-6 then bestS, bestMask = s, mask end
		end
	end
	local out, x, full = {}, bestMask, 0
	for i = 1, n do
		if x % 2 == 1 then out[#out + 1] = ns.LINES[i] end
		x = math.floor(x / 2)
	end
	for _, c in ipairs(copies) do
		if not info.focus or c.key == info.focus then
			for _, line in ipairs(ns.LINES) do full = full + c._p.full[line] end
		end
	end
	return { lines = out, pct = full > 0 and bestS / full or 0 }
end

local EXHAUSTIVE = 50000   -- combinations; above this the plan is built greedily (raids)

-- The plan (opts.camp = a list of lines to take as placed instead of searching: plan mode). Returns { drops = {[key] = line}, camp = {[line] = key}, capacity, fireBy, score, full, pct, bless,
-- cells, need, skip, alt, totem }.
function ns.Plan(members, opts)
	opts = opts or {}
	local info = prepare(members, opts)
	local capacity, fireBy
	local droppers = {}
	for _, m in ipairs(members) do
		if m.fire and (not capacity or m.fire > capacity) then capacity, fireBy = m.fire, m.key end
		if m.known and (m.cooldown or 0) <= 0 and m.lines and next(m.lines) then
			local opts2 = {}
			for _, line in ipairs(ns.LINES) do if m.lines[line] then opts2[#opts2 + 1] = line end end
			droppers[#droppers + 1] = { m = m, options = opts2 }
		end
	end
	local cap = capacity or 5   -- no known kit: assume a Journeyman fire
	if opts.camp then droppers = {} end   -- a given camp set (plan mode: the theory): no search
	local combos = 1
	for _, d in ipairs(droppers) do combos = combos * (#d.options + 1) end

	local bestScore, bestPick = -1, {}
	local camp, pick = {}, {}
	if combos <= EXHAUSTIVE then
		local function rec(i, count)
			if i > #droppers then
				local s = score(members, camp, info)
				if s > bestScore + 1e-6 then
					bestScore = s
					for k in pairs(bestPick) do bestPick[k] = nil end
					for k, v in pairs(pick) do bestPick[k] = v end
				end
				return
			end
			rec(i + 1, count)   -- this dropper keeps the cooldown (ties keep it)
			if count < cap then
				local d = droppers[i]
				for _, line in ipairs(d.options) do
					if not camp[line] then
						camp[line], pick[i] = d.m.key, line
						rec(i + 1, count + 1)
						camp[line], pick[i] = nil, nil
					end
				end
			end
		end
		rec(1, 0)
	else
		local used, count = {}, 0
		bestScore = score(members, camp, info)
		while count < cap do
			local gain, gi, gl = 1e-6, nil, nil
			for i, d in ipairs(droppers) do
				if not used[i] then
					for _, line in ipairs(d.options) do
						if not camp[line] then
							camp[line] = d.m.key
							local g = score(members, camp, info) - bestScore
							camp[line] = nil
							if g > gain then gain, gi, gl = g, i, line end
						end
					end
				end
			end
			if not gi then break end
			used[gi], camp[gl], bestPick[gi] = true, droppers[gi].m.key, gl
			bestScore, count = bestScore + gain, count + 1
		end
		for k in pairs(camp) do camp[k] = nil end
	end

	local plan = { drops = {}, camp = {}, capacity = capacity, fireBy = fireBy, bless = {}, cells = {},
		need = {}, skip = {}, alt = {}, members = members, goal = opts.goal or "progress", focus = opts.focus }
	for i, line in pairs(bestPick) do
		plan.drops[droppers[i].m.key] = line
		plan.camp[line] = droppers[i].m.key
	end
	if opts.camp then
		for _, line in ipairs(opts.camp) do plan.camp[line] = "theory" end
		plan.capacity = 10
	end
	plan.used = 0
	for _ in pairs(plan.camp) do plan.used = plan.used + 1 end
	plan.score = score(members, plan.camp, info)

	-- cells and coverage
	local full = 0
	for _, m in ipairs(members) do
		local _, set = memberScore(m, plan.camp, info)
		plan.bless[m.key] = set
		local given = {}
		for _, b in ipairs(set or {}) do given[b] = true end
		local p, row = m._p, {}
		local counted = not info.focus or m.key == info.focus
		for _, line in ipairs(ns.LINES) do
			local f = p.full[line]
			if counted then full = full + f end
			local class = math.max(p.base[line], given[line] and p.bless[line] or 0)
			local c = plan.camp[line] and p.camp[line] or 0
			if f <= 0 then row[line] = { kind = "none" }
			elseif class > 0 and class >= c then row[line] = { kind = "class", pct = class / f }
			elseif c > 0 then row[line] = { kind = "camp", pct = c / f }
			else row[line] = { kind = "missing", pct = 0 } end
		end
		plan.cells[m.key] = row
	end
	plan.full = full
	plan.pct = full > 0 and plan.score / full or 0

	-- what nobody here can drop but would help, and what is carried but adds nothing
	local carried = {}
	for _, d in ipairs(droppers) do for _, line in ipairs(d.options) do carried[line] = true end end
	for _, m in ipairs(members) do
		for line in pairs(m.lines or {}) do carried[line] = carried[line] or "cooldown" end
	end
	for _, line in ipairs(ns.LINES) do
		if not plan.camp[line] then
			plan.camp[line] = "?"
			local g = score(members, plan.camp, info) - plan.score
			plan.camp[line] = nil
			if not carried[line] and g > 0.5 then
				plan.need[#plan.need + 1] = { line = line, gain = g }
			elseif carried[line] and g <= 1e-6 and line ~= "tent" and line ~= "bot" then
				plan.skip[#plan.skip + 1] = line
			end
		end
	end
	table.sort(plan.need, function(a, b) return a.gain > b.gain end)

	-- each dropper's other choices and how much worse the plan gets
	for _, d in ipairs(droppers) do
		local mine = plan.drops[d.m.key]
		local list = {}
		for _, line in ipairs(d.options) do
			if line ~= mine and (not plan.camp[line]) then
				if mine then plan.camp[mine] = nil end
				plan.camp[line] = d.m.key
				local s = score(members, plan.camp, info)
				plan.camp[line] = nil
				if mine then plan.camp[mine] = d.m.key end
				list[#list + 1] = { line = line, delta = plan.score > 0 and (s - plan.score) / plan.score or 0 }
			end
		end
		table.sort(list, function(a, b) return a.delta > b.delta end)
		plan.alt[d.m.key] = list
	end

	-- a shaman and a Sharpening Wheel in the group: Strength of Earth (at its uptime) against the Wheel, so the
	-- shaman can judge whether the earth slot is better spent on Stoneskin or Tremor
	if plan.camp.str or carried.str then
		for _, m in ipairs(members) do
			if m.class == "SHAMAN" then
				local soe = ns.ClassAmounts("str", m.level).str * (opts.uptime or 0.7)
				local wheel = ns.CampAmounts("str", m.level).str
				plan.totem = { by = m.key, soe = soe, wheel = wheel }
				break
			end
		end
	end
	return plan
end
