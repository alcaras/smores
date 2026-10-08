-- S'mores panel: one row per member (who drops what), short notes (need, skip, blessings, totem), the coverage grid
-- as the detail view, and the Post button. Thin and quiet; every on-screen number lives in LAYOUT.
local _, ns = ...
local D = ns.DATA

local LAYOUT = {
	width = 380, pad = 8, rowH = 16, titleH = 18, noteH = 14, footH = 20, maxRows = 10, planRows = 20, codeH = 22,
	nameW = 78, roleW = 44, iconS = 14, itemW = 118, givesW = 70,
	gridLabelW = 84, gridCellW = 52, gridRowH = 14,
	bg = { 0.05, 0.05, 0.06, 0.88 }, border = { 0.35, 0.35, 0.38, 1 },
	point = { "CENTER", "UIParent", "CENTER", 260, 80 },
}
ns.LAYOUT = LAYOUT
local GRAY, GREEN, BLUE, RED = "|cff9d9d9d", "|cff5fd35f", "|cff6fa8ff", "|cffe0605a"
local ROLE_SHORT = { tank = "tank", melee = "melee", ranged = "ranged", caster = "caster", healer = "healer" }

local function classColor(class)
	local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	return c and c.colorStr and ("|c" .. c.colorStr) or "|cffffffff"
end

local function text(parent, template, justify, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	if width then fs:SetWidth(width) end
	fs:SetWordWrap(false)
	return fs
end

local function flatButton(parent, label, w, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, 16)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.2, 0.2, 0.22, 0.9)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.12)
	b.label = text(b, "GameFontHighlightSmall", "CENTER")
	b.label:SetPoint("CENTER")
	b.label:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

-- what a line gives at a level, short ("+34 Str", "+8% stats")
function ns.Gives(line, level)
	if line == "tent" then return "rested XP" end
	local a = ns.CampAmounts(line, level)
	if line == "motw" then
		local s = ("+%d armor"):format(a.armor or 0)
		if (a.stat or 0) > 0 then s = s .. (", +%d stats"):format(a.stat) end
		return s
	end
	if line == "kings" then return ("+%d%% stats"):format(a.pct or 0) end
	if line == "crit" then return ("+%d%% crit"):format(a.crit or 0) end
	local unit = { sta = "Sta", str = "Str", ap = "AP", mp5 = "mp5", spi = "Spi", int = "Int" }
	local _, v = next(a)
	return ("+%d %s"):format(v or 0, unit[line] or "")
end

-- ---------------------------------------------------------------- the frame
local f = CreateFrame("Frame", "SmoresFrame", UIParent, "BackdropTemplate")
f:SetPoint(LAYOUT.point[1], UIParent, LAYOUT.point[3], LAYOUT.point[4], LAYOUT.point[5])   -- anchored at once (engine rule)
f:SetSize(LAYOUT.width, 120)
f:SetFrameStrata("MEDIUM")
f:SetClampedToScreen(true)
f:Hide()
if f.SetBackdrop then
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f:SetBackdropColor(unpack(LAYOUT.bg))
	f:SetBackdropBorderColor(unpack(LAYOUT.border))
end
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local p, _, rp, x, y = self:GetPoint(1)
	if ns.db then ns.db.pos = { p, rp, x, y } end
end)
if UISpecialFrames then table.insert(UISpecialFrames, "SmoresFrame") end   -- Escape closes it
ns.frame = f

f.title = text(f, "GameFontNormalSmall")
f.title:SetPoint("TOPLEFT", LAYOUT.pad, -LAYOUT.pad)
f.title:SetText("S'mores")
f.fire = text(f, "GameFontHighlightSmall", "RIGHT", 130)
f.fire:SetPoint("TOPRIGHT", -LAYOUT.pad - 16, -LAYOUT.pad)
f.close = flatButton(f, "x", 14, function() f:Hide() end)
f.close:SetPoint("TOPRIGHT", -4, -4)
-- what the plan is for: the party or you, leveling or progression (click to switch)
f.scopeBtn = flatButton(f, "Party", 44, function() if ns.ToggleScope then ns.ToggleScope() end end)
f.scopeBtn:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
f.goalBtn = flatButton(f, "Leveling", 66, function() if ns.ToggleGoal then ns.ToggleGoal() end end)
f.goalBtn:SetPoint("LEFT", f.scopeBtn, "RIGHT", 4, 0)

f.rows = {}
for i = 1, LAYOUT.planRows do
	local r = CreateFrame("Frame", nil, f)
	r:SetSize(LAYOUT.width - 2 * LAYOUT.pad, LAYOUT.rowH)
	r:SetPoint("TOPLEFT", LAYOUT.pad, -(LAYOUT.pad + LAYOUT.titleH + (i - 1) * LAYOUT.rowH))
	r.name = text(r, "GameFontHighlightSmall", "LEFT", LAYOUT.nameW)
	r.name:SetPoint("LEFT")
	-- plan mode: click the name to change the class
	r.nameBtn = CreateFrame("Button", nil, r)
	r.nameBtn:SetPoint("LEFT")
	r.nameBtn:SetSize(LAYOUT.nameW - 4, LAYOUT.rowH)
	r.nameBtn:SetScript("OnClick", function(self) if ns.planMode and ns.CycleClass then ns.CycleClass(self.index) end end)
	r.role = flatButton(r, "", LAYOUT.roleW, function(self) if ns.CycleRole then ns.CycleRole(self.key) end end)
	r.role:SetPoint("LEFT", LAYOUT.nameW, 0)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(LAYOUT.iconS, LAYOUT.iconS)
	r.icon:SetPoint("LEFT", LAYOUT.nameW + LAYOUT.roleW + 6, 0)
	r.item = text(r, "GameFontHighlightSmall", "LEFT", LAYOUT.itemW)
	r.item:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
	r.gives = text(r, "GameFontDisableSmall", "LEFT", LAYOUT.givesW)
	r.gives:SetPoint("LEFT", r.item, "RIGHT", 2, 0)
	r.status = text(r, "GameFontHighlightSmall", "RIGHT", 44)
	r.status:SetPoint("RIGHT")
	r.remove = flatButton(r, "x", 14, function(self) if ns.RemovePlanMember then ns.RemovePlanMember(self.index) end end)
	r.remove:SetPoint("RIGHT")
	r.remove:Hide()
	r:Hide()
	f.rows[i] = r
end

f.notes = {}
for i = 1, 9 do
	local n = text(f, "GameFontHighlightSmall", "LEFT", LAYOUT.width - 2 * LAYOUT.pad)
	n:SetWordWrap(true)   -- a long Need / Best line wraps instead of being cut
	n:Hide()
	f.notes[i] = n
end

f.cover = text(f, "GameFontHighlightSmall")
f.post = flatButton(f, "Post to group", 92, function() if ns.Post then ns.Post() end end)
f.gridBtn = flatButton(f, "Grid", 44, function()
	if ns.db then ns.db.grid = not ns.db.grid end
	if ns.Refresh then ns.Refresh() end
end)
-- plan mode: add a member, and the plan code box (copy it to the site, or paste one from it and press Enter)
f.addBtn = flatButton(f, "+ Add", 44, function() if ns.AddPlanMember then ns.AddPlanMember() end end)
f.codeBtn = flatButton(f, "Code", 44, function()
	f.code:SetShown(not f.code:IsShown())
	if ns.Refresh then ns.Refresh() end
end)
f.addBtn:Hide()
f.codeBtn:Hide()
f.code = CreateFrame("EditBox", nil, f, "BackdropTemplate")
f.code:SetSize(LAYOUT.width - 2 * LAYOUT.pad, 18)
f.code:SetFontObject("GameFontHighlightSmall")
f.code:SetAutoFocus(false)
f.code:SetTextInsets(4, 4, 0, 0)
if f.code.SetBackdrop then
	f.code:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f.code:SetBackdropColor(0, 0, 0, 0.6)
	f.code:SetBackdropBorderColor(unpack(LAYOUT.border))
end
f.code:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
f.code:SetScript("OnEnterPressed", function(self)
	self:ClearFocus()
	if ns.ImportCode then ns.ImportCode(self:GetText()) end
end)
f.code:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
f.code:Hide()

-- the grid: rows = buff lines, columns = members
local g = CreateFrame("Frame", nil, f)
g:Hide()
f.grid = g
g.head, g.labels, g.cells = {}, {}, {}

local function cellText(c)
	if not c or c.kind == "none" then return "" end
	local pct = math.floor((c.pct or 0) * 100 + 0.5)
	if c.kind == "class" then return BLUE .. pct .. "|r" end
	if c.kind == "camp" then return GREEN .. pct .. "|r" end
	return RED .. "0|r"
end

local function renderGrid(plan, members, y)
	local cols = math.min(#members, 8)
	g:ClearAllPoints()
	g:SetPoint("TOPLEFT", LAYOUT.pad, -y)
	g:SetSize(LAYOUT.gridLabelW + cols * LAYOUT.gridCellW, (#ns.LINES + 1) * LAYOUT.gridRowH)
	for j = 1, 8 do
		g.head[j] = g.head[j] or text(g, "GameFontHighlightSmall", "CENTER", LAYOUT.gridCellW)
		local h = g.head[j]
		if j <= cols then
			local m = members[j]
			h:SetPoint("TOPLEFT", LAYOUT.gridLabelW + (j - 1) * LAYOUT.gridCellW, 0)
			h:SetText(classColor(m.class) .. m.name .. "|r")
			h:Show()
		else h:Hide() end
	end
	for i, line in ipairs(ns.LINES) do
		g.labels[i] = g.labels[i] or text(g, "GameFontDisableSmall", "LEFT", LAYOUT.gridLabelW)
		g.labels[i]:SetPoint("TOPLEFT", 0, -i * LAYOUT.gridRowH)
		g.labels[i]:SetText(ns.LINE_NAME[line])
		g.cells[i] = g.cells[i] or {}
		for j = 1, 8 do
			g.cells[i][j] = g.cells[i][j] or text(g, "GameFontHighlightSmall", "CENTER", LAYOUT.gridCellW)
			local c = g.cells[i][j]
			if j <= cols then
				c:SetPoint("TOPLEFT", LAYOUT.gridLabelW + (j - 1) * LAYOUT.gridCellW, -i * LAYOUT.gridRowH)
				c:SetText(cellText(plan.cells[members[j].key] and plan.cells[members[j].key][line]))
				c:Show()
			else c:Hide() end
		end
	end
	g:Show()
	return (#ns.LINES + 1) * LAYOUT.gridRowH + 4
end

local function minutes(s) return ("%dm"):format(math.ceil(s / 60)) end

-- ---------------------------------------------------------------- render
-- state: { plan, members, applied, me }
function ns.Render(state)
	local plan, members = state.plan, state.members
	if state.planMode then f.title:SetText("S'mores |cff66ccffplan|r")
	else f.title:SetText(ns.demo and "S'mores |cffffcc00demo|r" or "S'mores") end
	local fire
	if plan.capacity then
		local names = { [3] = "Basic", [5] = "Journeyman", [10] = "Expert" }
		local by = plan.fireBy and plan.fireBy:gsub("%-.*", "") or "?"
		fire = ("%s %d/%d (%s)"):format(names[plan.capacity] or "Camp", plan.used, plan.capacity, by)
	else
		fire = ("no kit known %d/5"):format(plan.used)
	end
	if state.planMode then fire = ("theory, Expert fire %d/10"):format(plan.used) end
	f.scopeBtn:SetShown(not state.planMode)
	f.scopeBtn.label:SetText(plan.focus and "You" or "Party")
	f.goalBtn.label:SetText(plan.goal == "level" and "Leveling" or "Progression")
	f.fire:SetText(GRAY .. fire .. "|r")

	-- rows: in a raid only those who drop something, you, and the unknown count
	local list, hidden = {}, 0
	local maxRows = state.planMode and LAYOUT.planRows or LAYOUT.maxRows
	for _, m in ipairs(members) do
		if #members <= maxRows or m.self or plan.drops[m.key] then list[#list + 1] = m else hidden = hidden + 1 end
	end
	for i, r in ipairs(f.rows) do
		local m = list[i]
		r.nameBtn.index, r.remove.index = m and m.planIndex, m and m.planIndex
		r.nameBtn:SetShown(state.planMode and m ~= nil)
		r.remove:SetShown(state.planMode and m ~= nil)
		if m and state.planMode then
			-- plan mode: class (click to change), role, the blessings this member gets, level
			r.name:SetText(classColor(m.class) .. m.name .. "|r")
			r.role.key = m.key
			r.role.label:SetText(GRAY .. ROLE_SHORT[m.role] .. "|r")
			r.icon:Hide()
			local b = {}
			for _, x in ipairs(plan.bless[m.key] or {}) do b[#b + 1] = D.class[x].name end
			r.item:SetText(#b > 0 and (GRAY .. "gets |r" .. table.concat(b, ", ")) or "")
			r.gives:SetText(GRAY .. "level " .. m.level .. "|r")
			r.status:SetText("")
			r:Show()
		elseif m then
			local line = plan.drops[m.key]
			r.name:SetText(classColor(m.class) .. m.name .. "|r")
			r.role.key = m.key
			r.role.label:SetText(GRAY .. ROLE_SHORT[m.role] .. "|r")
			if line then
				local id = m.lines[line]
				r.icon:SetTexture(C_Item.GetItemIconByID(id))
				r.icon:Show()
				r.item:SetText(D.items[id].name)
				local n = 0
				for _, mm in ipairs(members) do
					local c = plan.cells[mm.key][line]
					if c and c.kind == "camp" then n = n + 1 end
				end
				r.gives:SetText(ns.Gives(line, state.level) .. (n > 1 and (" x" .. n) or ""))
			else
				r.icon:Hide()
				local why
				if not m.known then why = "no addon"
				elseif (m.cooldown or 0) > 0 then why = "on cooldown"
				elseif not (m.lines and next(m.lines)) then why = "no camp items"
				else why = "keep cooldown" end
				r.item:SetText(GRAY .. why .. "|r")
				r.gives:SetText("")
			end
			local st
			if line and state.applied[line] then st = GREEN .. "placed|r"
			elseif not m.known then st = GRAY .. "?|r"
			elseif (m.cooldown or 0) > 0 then st = GRAY .. minutes(m.cooldown) .. "|r"
			elseif line then st = "ready" else st = "" end
			r.status:SetText(st)
			r:Show()
		else
			r:Hide()
		end
	end
	local y = LAYOUT.pad + LAYOUT.titleH + math.min(#list, maxRows) * LAYOUT.rowH + 4

	-- notes
	local notes = {}
	if state.planMode then
		-- the camp for this roster, ignoring professions
		local t = {}
		for _, line in ipairs(ns.LINES) do
			if plan.camp[line] then t[#t + 1] = ns.CAMP_NAME[line] .. " " .. GRAY .. ns.Gives(line, state.level) .. "|r" end
		end
		notes[#notes + 1] = "Camp  " .. (#t > 0 and table.concat(t, ", ") or GRAY .. "nothing adds anything|r")
	end
	if hidden > 0 then notes[#notes + 1] = GRAY .. hidden .. " more members (nothing to drop)|r" end
	if #plan.need > 0 then
		local t = {}
		for i = 1, math.min(3, #plan.need) do
			local line = plan.need[i].line
			t[#t + 1] = ns.CAMP_NAME[line] .. " " .. GRAY .. ns.Gives(line, state.level) .. "|r"
		end
		notes[#notes + 1] = (state.planMode and "Also  " or "Need  ") .. table.concat(t, ", ")
	end
	if #plan.skip > 0 then
		local t = {}
		for _, line in ipairs(plan.skip) do
			local c = D.class[line]
			t[#t + 1] = ns.CAMP_NAME[line] .. " " .. GRAY .. "(" .. c.name .. ")|r"
		end
		notes[#notes + 1] = "Skip  " .. table.concat(t, ", ")
	end
	local blessLine = ns.BlessingText(plan, members)
	if blessLine then notes[#notes + 1] = "Bless  " .. blessLine end
	if plan.totem then
		notes[#notes + 1] = ("Totem  Strength of Earth ~%d Str at %d%% uptime, a Sharpening Wheel %d"):format(
			math.floor(plan.totem.soe + 0.5), math.floor((state.uptime or 0.7) * 100 + 0.5), plan.totem.wheel)
	end
	-- the plan if everyone carried their professions' best item: who would drop something not in their bags
	local ideal = state.ideal
	if ideal then
		local t = {}
		for _, im in ipairs(ideal.members) do
			local best = ideal.drops[im.key]
			local m
			for _, x in ipairs(members) do if x.key == im.key then m = x end end
			if best and m and best ~= plan.drops[m.key] and not (m.lines and m.lines[best]) then
				t[#t + 1] = m.name .. ": " .. D.items[im.lines[best]].name
			end
		end
		if #t > 0 then notes[#notes + 1] = "Best  " .. table.concat(t, ", ") .. GRAY .. " (not in bags)|r" end
	end
	-- ignoring professions: the best set of features for this group
	local theory = state.theory
	if theory and #theory.lines > 0 then
		local t = {}
		for _, line in ipairs(theory.lines) do t[#t + 1] = ns.CAMP_NAME[line] end
		notes[#notes + 1] = "Theory  " .. table.concat(t, ", ")
	end
	local alt = state.me and plan.alt[state.me]
	if alt and alt[1] then
		notes[#notes + 1] = ("You  %s instead: %s%d%%|r"):format(ns.CAMP_NAME[alt[1].line], GRAY,
			math.floor(alt[1].delta * 100 + 0.5))
	end
	for i, n in ipairs(f.notes) do
		if notes[i] then
			n:ClearAllPoints()
			n:SetPoint("TOPLEFT", LAYOUT.pad, -y)
			n:SetText(notes[i])
			n:Show()
			y = y + math.max(LAYOUT.noteH, (n:GetStringHeight() or 0) + 2)
		else n:Hide() end
	end

	if ns.db and ns.db.grid then
		y = y + 4 + renderGrid(plan, members, y + 4)
	else
		g:Hide()
	end

	y = y + 4
	f.cover:ClearAllPoints()
	f.cover:SetPoint("TOPLEFT", LAYOUT.pad, -(y + 3))
	local now = math.floor(plan.pct * 100 + 0.5)
	local best = state.ideal and math.floor(state.ideal.pct * 100 + 0.5)
	local theo = state.theory and math.floor(state.theory.pct * 100 + 0.5)
	local parts = { ("Now %d%%"):format(now) }
	if best and best > now then parts[#parts + 1] = ("best items %d%%"):format(best) end
	if theo and theo > math.max(now, best or 0) then parts[#parts + 1] = ("theory %d%%"):format(theo) end
	f.cover:SetText(table.concat(parts, GRAY .. " / |r"))
	f.post:ClearAllPoints()
	f.post:SetPoint("TOPRIGHT", -LAYOUT.pad, -y)
	f.gridBtn:ClearAllPoints()
	f.gridBtn:SetPoint("RIGHT", f.post, "LEFT", -4, 0)
	f.addBtn:SetShown(state.planMode)
	f.codeBtn:SetShown(state.planMode)
	if state.planMode then
		f.codeBtn:ClearAllPoints()
		f.codeBtn:SetPoint("RIGHT", f.gridBtn, "LEFT", -4, 0)
		f.addBtn:ClearAllPoints()
		f.addBtn:SetPoint("RIGHT", f.codeBtn, "LEFT", -4, 0)
		f.cover:SetWidth(LAYOUT.width - 2 * LAYOUT.pad - 92 - 3 * 44 - 12)
	else
		f.code:Hide()
		f.cover:SetWidth(0)
	end
	if f.code:IsShown() then
		f.code:ClearAllPoints()
		f.code:SetPoint("TOPLEFT", LAYOUT.pad, -(y + LAYOUT.footH))
		if not f.code:HasFocus() then f.code:SetText(state.code or "") end
		y = y + LAYOUT.codeH
	end
	f:SetHeight(y + LAYOUT.footH + LAYOUT.pad)
end

-- "Might > Alca, Alcara; Wisdom > Lumen" (nil without a paladin)
function ns.BlessingText(plan, members)
	local by, order = {}, {}
	for _, m in ipairs(members) do
		for _, b in ipairs(plan.bless[m.key] or {}) do
			if not by[b] then by[b] = {}; order[#order + 1] = b end
			table.insert(by[b], m.name)
		end
	end
	if #order == 0 then return nil end
	local t = {}
	for _, b in ipairs(order) do t[#t + 1] = D.class[b].name .. " > " .. table.concat(by[b], ", ") end
	return table.concat(t, "; ")
end

-- the line the Post button sends (at most 255 characters)
function ns.PostText(plan, members)
	local drops = {}
	for _, m in ipairs(members) do
		local line = plan.drops[m.key]
		if line then drops[#drops + 1] = m.name .. " " .. D.items[m.lines[line]].name end
	end
	local who = ""
	if plan.focus then
		for _, m in ipairs(members) do if m.key == plan.focus then who = " (for " .. m.name .. ")" end end
	end
	local s = "S'mores" .. who .. ": " .. (#drops > 0 and table.concat(drops, ", ") or "nothing to drop")
	if #plan.need > 0 then
		local t = {}
		for i = 1, math.min(3, #plan.need) do t[#t + 1] = ns.CAMP_NAME[plan.need[i].line] end
		s = s .. ". Need: " .. table.concat(t, ", ")
	end
	local b = ns.BlessingText(plan, members)
	if b then s = s .. ". Blessings: " .. b end
	if #s > 255 then s = s:sub(1, 252) .. "..." end
	return s
end
