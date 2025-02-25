local _, ns = ...
local oUF = ns.oUF or oUF

local _G = _G
local addon = {}
ns.oUF_RaidDebuffs = addon
_G.oUF_RaidDebuffs = ns.oUF_RaidDebuffs
if not _G.oUF_RaidDebuffs then
	_G.oUF_RaidDebuffs = addon
end

local format, floor = format, floor
local type, pairs, wipe = type, pairs, wipe

local GetActiveSpecGroup = _G.GetActiveSpecGroup
local GetSpecialization = _G.GetSpecialization
local IsSpellKnown = _G.IsSpellKnown
local GetTime = _G.GetTime
local UnitAura = _G.UnitAura
local UnitCanAttack = _G.UnitCanAttack
local UnitIsCharmed = _G.UnitIsCharmed

local debuff_data = {}
addon.DebuffData = debuff_data
addon.ShowDispellableDebuff = true
addon.FilterDispellableDebuff = true
addon.MatchBySpellName = false
addon.priority = 10

local UnitAura = UnitAura

if not UnitAura then
	UnitAura = function(unitToken, index, filter)
		local auraData = C_UnitAuras.GetAuraDataByIndex(unitToken, index, filter);

		if not auraData then
			return nil
		end

		return AuraUtil.UnpackAuraData(auraData)
	end
end

local function add(spell, priority, stackThreshold)
	if addon.MatchBySpellName and type(spell) == "number" then
		spell = Toolkit.Functions.GetSpellInfo(spell)
	end

	if(spell) then
		debuff_data[spell] = {
			priority = (addon.priority + priority),
			stackThreshold = (stackThreshold or 0),
		}
	end
end

function addon:RegisterDebuffs(t)
	for spell, value in pairs(t) do
		if type(t[spell]) == "boolean" then
			local oldValue = t[spell]
			t[spell] = { enable = oldValue, priority = 0, stackThreshold = 0 }
		else
			if t[spell].enable then
				add(spell, t[spell].priority, t[spell].stackThreshold)
			end
		end
	end
end

function addon:ResetDebuffData()
	wipe(debuff_data)
end

local DispellColor = {
	["Magic"]	= {.2, .6, 1},
	["Curse"]	= {.6, 0, 1},
	["Poison"]	= {0, .6, 0},
	["Disease"]	= {.6, .4, 0},
	["none"]	= {1, 0, 0}
}

local DispellPriority = {
	["Magic"]	= 4,
	["Curse"]	= 3,
	["Poison"]	= 1,
	["Disease"]	= 2
}

local class = select(2, UnitClass("player"))

local DispellFilterClasses = {
	["DRUID"] = {
		["Magic"] = false,
		["Curse"] = true,
		["Poison"] = true,
		["Disease"] = false
	},
	["EVOKER"] = {
		["Magic"] = true,
		["Curse"] = true,
		["Poison"] = true,
		["Disease"] = true
	},
	["MAGE"] = {
		["Curse"] = true
	},
	["MONK"] = {
		["Magic"] = (oUF.isRetail and true or false),
		["Poison"] = true,
		["Disease"] = true
	},
	["PALADIN"] = {
		["Magic"] = true,
		["Poison"] = true,
		["Disease"] = true
	},
	["PRIEST"] = {
		["Magic"] = true,
		["Disease"] = true
	},
	["SHAMAN"] = {
		["Magic"] = false,
		["Curse"] = (oUF.isRetail and true) or (oUF.isClassic and true) or false,
		["Poison"] = true,
		["Disease"] = true
	}
}

local DispellFilter = DispellFilterClasses[class] or {}

local function CheckTalentTree(tree)
	local activeSpecGroup = GetActiveSpecGroup(false)
	local currentSpec = GetSpecialization(false, false, activeSpecGroup)
	return (currentSpec == tree)
end

local function CheckSpecialization()
	if (class == "DRUID") then
		local isRestoration = CheckTalentTree(4)
		DispellFilter.Magic = isRestoration
	elseif (class == "EVOKER") then
		local isPreservation = CheckTalentTree(2)
		DispellFilter.Magic = isPreservation
		DispellFilter.Curse = isPreservation
		DispellFilter.Poison = isPreservation
		DispellFilter.Disease = isPreservation
	elseif (class == "MONK") then
		local isMistweaver = CheckTalentTree(2)
		DispellFilter.Magic = isMistweaver
	elseif (class == "PALADIN") then
		local isHoly = CheckTalentTree(1)
		DispellFilter.Magic = isHoly
	elseif (class == "PRIEST") then
		-- do nothing
	elseif (class == "SHAMAN") then
		local isRestoration = CheckTalentTree(3)
		DispellFilter.Magic = isRestoration
	end
end

local function UpdateDispellFilter(self, event, ...)
	if (event == "CHARACTER_POINTS_CHANGED") then
		local levels = ...
		-- Not interested in gained points from leveling
		if (levels > 0) then return end
	elseif (event == "UNIT_SPELLCAST_SUCCEEDED") then
		local unit, _, spellID = ...
		-- watch if player change spec
		if (unit ~= "player") then return end
		-- 200749 = 'Activating Specialization'
		-- 384255 = 'Changing Talents'
		if (spellID ~= 200749 and spellID ~= 384255) then return end
	end

	CheckSpecialization()
end

local function formatTime(s)
	if s > 60 then
		return format("%dm", s/60), s%60
	elseif s < 1 then
		return format("%.1f", s), s - floor(s)
	else
		return format("%d", s), s - floor(s)
	end
end

local abs = math.abs
local function OnUpdate(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed >= 0.1 then
		local timeLeft = self.endTime - GetTime()
		if self.reverse then timeLeft = abs((self.endTime - GetTime()) - self.duration) end
		if timeLeft > 0 then
			local text = formatTime(timeLeft)
			self.time:SetText(text)
		else
			self:SetScript("OnUpdate", nil)
			self.time:Hide()
		end
		self.elapsed = 0
	end
end

local function UpdateDebuff(self, name, icon, count, debuffType, duration, endTime, spellId, stackThreshold)
	local f = self.RaidDebuffs

	if name and (count >= stackThreshold) then
		f.icon:SetTexture(icon)
		f.icon:Show()
		f.duration = duration

		if f.count then
			if count and (count > 1) then
				f.count:SetText(count)
				f.count:Show()
			else
				f.count:SetText("")
				f.count:Hide()
			end
		end

		if f.time then
			if duration and (duration > 0) and f:GetSize() > 20 then
				f.endTime = endTime
				f.nextUpdate = 0
				f:SetScript("OnUpdate", OnUpdate)
				f.time:Show()
			else
				f:SetScript("OnUpdate", nil)
				f.time:Hide()
			end
		end

		if f.cd then
			if duration and (duration > 0) then
				f.cd:SetCooldown(endTime - duration, duration)
				f.cd:Show()
			else
				f.cd:Hide()
			end
		end

		local c = DispellColor[debuffType] or DispellColor.none

		if f.Backdrop then
			f.Backdrop:SetBorderColor(c[1], c[2], c[3])
		else
			f:SetBackdropBorderColor(c[1], c[2], c[3])
		end

		f:Show()
	else
		f:Hide()
	end
end

local function Update(self, event, unit)
	if unit ~= self.unit then return end
	local _name, _icon, _count, _dtype, _duration, _endTime, _spellId, _
	local _priority, priority = 0, 0
	local _stackThreshold = 0

	-- store if the unit its charmed, mind controlled units (Imperial Vizier Zor'lok: Convert)
	local isCharmed = UnitIsCharmed(unit)

	-- store if we cand attack that unit, if its so the unit its hostile (Amber-Shaper Un'sok: Reshape Life)
	local canAttack = UnitCanAttack("player", unit)

	for i = 1, 40 do
		local name, icon, count, debuffType, duration, expirationTime, unitCaster, isStealable, shouldConsolidate, spellId, canApplyAura, isBossDebuff = UnitAura(unit, i, "HARMFUL")
		if (not name) then break end

		-- we coudln't dispell if the unit its charmed, or its not friendly
		if addon.ShowDispellableDebuff and (self.RaidDebuffs.showDispellableDebuff ~= false) and debuffType and (not isCharmed) and (not canAttack) then

			if addon.FilterDispellableDebuff then
				DispellPriority[debuffType] = (DispellPriority[debuffType] or 0) + addon.priority -- make Dispell buffs on top of Boss Debuffs
				priority = DispellFilter[debuffType] and DispellPriority[debuffType] or 0
				if priority == 0 then
					debuffType = nil
				end
			else
				priority = DispellPriority[debuffType] or 0
			end

			if priority > _priority then
				_priority, _name, _icon, _count, _dtype, _duration, _endTime, _spellId = priority, name, icon, count, debuffType, duration, expirationTime, spellId
			end
		end

		local debuff
		if self.RaidDebuffs.onlyMatchSpellID then
			debuff = debuff_data[spellId]
		else
			if debuff_data[spellId] then
				debuff = debuff_data[spellId]
			else
				debuff = debuff_data[name]
			end
		end

		priority = debuff and debuff.priority
		if priority and not self.RaidDebuffs.BlackList[spellId] and (priority > _priority) then
			_priority, _name, _icon, _count, _dtype, _duration, _endTime, _spellId = priority, name, icon, count, debuffType, duration, expirationTime, spellId
		end
	end

	if self.RaidDebuffs.forceShow then
		_spellId = 47540
		_name, _, _icon = Toolkit.Functions.GetSpellInfo(_spellId)
		_count, _dtype, _duration, _endTime, _stackThreshold = 5, "Magic", 0, 60, 0
	end

	if _name then
		_stackThreshold = debuff_data[addon.MatchBySpellName and _name or _spellId] and debuff_data[addon.MatchBySpellName and _name or _spellId].stackThreshold or _stackThreshold
	end

	UpdateDebuff(self, _name, _icon, _count, _dtype, _duration, _endTime, _spellId, _stackThreshold)

	-- Reset the DispellPriority
	DispellPriority["Magic"] = 4
	DispellPriority["Curse"] = 3
	DispellPriority["Disease"] = 2
	DispellPriority["Poison"] = 1
end

local function Enable(self)
	if self.RaidDebuffs then
		self:RegisterEvent("PLAYER_LOGIN", UpdateDispellFilter, true)

		if oUF.isRetail then
			self:RegisterEvent("PLAYER_TALENT_UPDATE", UpdateDispellFilter, true)
			self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", UpdateDispellFilter, true)
		end

		if oUF.isClassic then
			self:RegisterEvent("CHARACTER_POINTS_CHANGED", UpdateDispellFilter, true)
		end

		self:RegisterEvent("UNIT_AURA", Update)

		self.RaidDebuffs.BlackList = self.RaidDebuffs.BlackList or {
			[105171] = true, -- Deep Corruption
			[108220] = true, -- Deep Corruption
			[116095] = true, -- Disable, Slow
			[137637] = true  -- Warbringer, Slow
		}

		return true
	end
end

local function Disable(self)
	if self.RaidDebuffs then
		if oUF.isRetail then
			self:UnregisterEvent("PLAYER_TALENT_UPDATE", UpdateDispellFilter, true)
			self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED", UpdateDispellFilter, true)
		end

		if oUF.isClassic then
			self:UnregisterEvent("CHARACTER_POINTS_CHANGED", UpdateDispellFilter, true)
		end

		self:UnregisterEvent("UNIT_AURA", Update)

		self.RaidDebuffs:Hide()
	end
end

oUF:AddElement("RaidDebuffs", Update, Enable, Disable)
