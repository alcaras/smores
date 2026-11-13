-- Timer.lua: how long you still have to sit at the campfire. Welcoming Campfire (1229739; 1289723 lets you craft too)
-- is on you while you sit at a fire; after its minute (60 s, SpellDuration 3) it casts Camp Benefits (1229741), the
-- buffs of the camp's features. A thin line above your character counts that minute down; when it ends with Camp
-- Benefits on, the line turns green for a moment, then goes. Gone when you get up and in combat. With Camp Benefits
-- already on you it still counts, labelled "refresh": the minute casts them again (the user, 2026-11-10: "show the
-- campfire gaining buffs even when i have the buff (refreshing)"). (The user, 2026-11-06: "do something like the
-- bedroll timer, but not overlapping with it, for how long you have to sit"; Bedroll's line is at 190, its reminder at
-- 240.) /smores timer on | off.
local ADDON, ns = ...

local SITTING = { 1229739, 1289723 }   -- Welcoming Campfire (both)
local BENEFITS = 1229741               -- Camp Benefits

-- Every number that is visible on screen.
local LAYOUT = {
	strata    = "LOW",
	width     = 300,
	lineH     = 4,
	y         = 150,     -- under Bedroll's line (190) and its label
	track     = { 0.15, 0.15, 0.15, 0.8 },
	fill      = { 0.6, 0.6, 0.6, 0.85 },
	full      = { 0.45, 0.8, 0.45, 0.9 },   -- Camp Benefits on
	fillTex   = "Interface\\Buttons\\WHITE8X8",
	spark     = "Interface\\CastingBar\\UI-CastingBar-Spark",
	sparkW    = 14,
	sparkH    = 16,
	font      = "GameFontHighlight",        -- the time, right of the line
	labelFont = "GameFontNormal",           -- what it is, above it
	textGap   = 6,
	labelGap  = 3,
	doneHold  = 4,                          -- seconds the green line stays
	endSlack  = 1.5,                        -- seconds before its end the sitting aura may go and still count as done
	tick      = 0.1,
}

local function Aura(id)
	if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
	local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)   -- pcall: restricted aura reads can throw
	if ok and type(a) == "table" and not ns.secret(a) then return a end
end

local function Num(v)
	if v == nil or ns.secret(v) or type(v) ~= "number" then return nil end
	return v
end

-- the sitting aura's end and length (GetTime), or nil
local function Sitting()
	for _, id in ipairs(SITTING) do
		local a = Aura(id)
		if a then
			local exp, dur = Num(a.expirationTime), Num(a.duration)
			if exp and exp > 0 then return exp, (dur and dur > 0) and dur or 60 end
		end
	end
end

local function On() return not (ns.db and ns.db.timer == false) end

--------------------------------------------------------------------- the line
local line = CreateFrame("Frame", "SmoresTimer", UIParent)
line:SetSize(LAYOUT.width, LAYOUT.lineH)
line:SetPoint("CENTER", UIParent, "CENTER", 0, LAYOUT.y)
line:SetFrameStrata(LAYOUT.strata)
line:Hide()

local bg = line:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(unpack(LAYOUT.track))

local bar = CreateFrame("StatusBar", nil, line)
bar:SetAllPoints()
bar:SetStatusBarTexture(LAYOUT.fillTex)
bar:SetStatusBarColor(unpack(LAYOUT.fill))
bar:SetMinMaxValues(0, 1)
bar:SetValue(0)

local spark = bar:CreateTexture(nil, "OVERLAY")
spark:SetTexture(LAYOUT.spark)
spark:SetBlendMode("ADD")
spark:SetSize(LAYOUT.sparkW, LAYOUT.sparkH)

local timeText = bar:CreateFontString(nil, "OVERLAY", LAYOUT.font)
timeText:SetPoint("LEFT", line, "RIGHT", LAYOUT.textGap, 0)
local label = bar:CreateFontString(nil, "OVERLAY", LAYOUT.labelFont)
label:SetPoint("BOTTOM", line, "TOP", 0, LAYOUT.labelGap)

local doneAt   -- GetTime() Camp Benefits landed, while the green line shows
local sat      -- the sitting aura's end (GetTime) at the last look, while it is on
local refresh  -- Camp Benefits were already on while the minute ran (it renews them)
local doneRefresh

local function Clock(s)
	s = math.max(0, math.floor(s + 0.5))
	return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function Draw(share, left, done, renew)
	share = math.max(0, math.min(1, share))
	bar:SetValue(share)
	bar:SetStatusBarColor(unpack(done and LAYOUT.full or LAYOUT.fill))
	spark:ClearAllPoints()
	spark:SetPoint("CENTER", line, "LEFT", LAYOUT.width * share, 0)
	spark:SetShown(not done)
	if done then label:SetText(renew and "Camp benefits refreshed" or "Camp benefits on")
	else label:SetText(renew and "Camp benefits: refresh" or "Camp benefits") end
	timeText:SetText(done and "" or Clock(left))
end

local function Update()
	local now = GetTime()
	if not On() or ns.InCombat() then sat, refresh, doneAt = nil, nil, nil line:Hide() return end
	if doneAt then
		if now - doneAt >= LAYOUT.doneHold then doneAt = nil line:Hide() else Draw(1, 0, true, doneRefresh) line:Show() end
		return
	end
	local exp, dur = Sitting()
	if exp then
		-- a new minute (first look, or the aura put on again): is it a refresh?
		if not sat or exp > sat + LAYOUT.endSlack then refresh = Aura(BENEFITS) ~= nil end
		sat = exp
		Draw(1 - (exp - now) / dur, exp - now, false, refresh)
		line:Show()
		return
	end
	-- the minute ran out with the benefits on you: green, then gone; got up early: gone
	if sat and now >= sat - LAYOUT.endSlack and Aura(BENEFITS) then
		doneAt, doneRefresh = now, refresh
		Draw(1, 0, true, refresh)
		line:Show()
	else
		line:Hide()
	end
	sat, refresh = nil, nil
end
ns.TimerUpdate = Update

-- polled only while the line shows; the aura events start it
local elapsed = 0
line:SetScript("OnUpdate", function(_, d)
	elapsed = elapsed + d
	if elapsed < LAYOUT.tick then return end
	elapsed = 0
	local ok, err = pcall(Update)   -- pcall: a client change must not raise every tenth of a second
	if not ok then line:Hide() line:SetScript("OnUpdate", nil) print("|cff7fbf7fS'mores|r: the sitting timer stopped: " .. tostring(err)) end
end)

local ev = CreateFrame("Frame")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
	local ok = pcall(Update)   -- pcall: as above
	if not ok then line:Hide() end
end)

function ns.TimerCommand(arg)
	if arg == "on" or arg == "off" then
		ns.db.timer = (arg == "on")
		Update()
	end
	ns.say("sitting timer at the campfire: " .. (On() and "on" or "off") .. ".")
end
