local MAJOR, MINOR = "LibArtifactData-1.0", 1

assert(_G.LibStub, MAJOR .. " requires LibStub")
local lib = _G.LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local callback = _G.LibStub("CallbackHandler-1.0"):New(lib)

local Debug = function() end
if _G.AdiDebug then
	Debug = _G.AdiDebug:Embed({}, MAJOR)
end

-- local store
local artifacts = {}
local equippedID
local knowledgeLevel = 0
local knowledgeMultiplier = 1

-- constants
local _G                       = _G
local BACKPACK_CONTAINER       = _G.BACKPACK_CONTAINER
local BANK_CONTAINER           = _G.BANK_CONTAINER
local INVSLOT_MAINHAND         = _G.INVSLOT_MAINHAND
local LE_ITEM_QUALITY_ARTIFACT = _G.LE_ITEM_QUALITY_ARTIFACT
local NUM_BAG_SLOTS            = _G.NUM_BAG_SLOTS
local NUM_BANKBAGSLOTS         = _G.NUM_BANKBAGSLOTS

-- blizzard api
local aUI                            = _G.C_ArtifactUI
local Clear                          = aUI.Clear
local GetArtifactInfo                = aUI.GetArtifactInfo
local GetArtifactKnowledgeLevel      = aUI.GetArtifactKnowledgeLevel
local GetArtifactKnowledgeMultiplier = aUI.GetArtifactKnowledgeMultiplier
local GetContainerItemInfo           = _G.GetContainerItemInfo
local GetContainerNumSlots           = _G.GetContainerNumSlots
local GetEquippedArtifactInfo        = aUI.GetEquippedArtifactInfo
local GetNumObtainedArtifacts        = aUI.GetNumObtainedArtifacts
local GetNumPurchasableTraits        = _G.MainMenuBar_GetNumArtifactTraitsPurchasableFromXP
local GetNumRelicSlots               = aUI.GetNumRelicSlots
local GetPowerInfo                   = aUI.GetPowerInfo
local GetPowers                      = aUI.GetPowers
local GetRelicInfo                   = aUI.GetRelicInfo
local GetRelicSlotType               = aUI.GetRelicSlotType
local GetSpellInfo                   = _G.GetSpellInfo
local HasArtifactEquipped            = _G.HasArtifactEquipped
local IsViewedArtifactEquipped       = aUI.IsViewedArtifactEquipped
local SocketContainerItem            = _G.SocketContainerItem
local SocketInventoryItem            = _G.SocketInventoryItem

-- lua api
local strmatch = string.match

local frame = _G.CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, ...) self[event](self, ...) end)
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
--frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("ARTIFACT_RESPEC_PROMPT")
frame:RegisterEvent("ARTIFACT_XP_UPDATE")
frame:RegisterEvent("ADDON_LOADED")

local function CopyTable(tbl)
	if not tbl then return {} end
	local copy = {};
	for k, v in pairs(tbl) do
		if ( type(v) == "table" ) then
			copy[k] = CopyTable(v);
		else
			copy[k] = v;
		end
	end
	return copy;
end

function frame:PrepareForScan()
	self:UnregisterEvent("ARTIFACT_UPDATE")
	local ArtifactFrame = _G.ArtifactFrame

	if not ArtifactFrame or not ArtifactFrame:IsShown() then
		_G.UIParent:UnregisterEvent("ARTIFACT_UPDATE")
		if ArtifactFrame then
			ArtifactFrame:UnregisterEvent("ARTIFACT_UPDATE")
		end
	end
end

function frame:RestoreStateAfterScan()
	self:RegisterEvent("ARTIFACT_UPDATE")
	local ArtifactFrame = _G.ArtifactFrame

	if not ArtifactFrame or not ArtifactFrame:IsShown() then
		Clear()
		if ArtifactFrame then
			ArtifactFrame:RegisterEvent("ARTIFACT_UPDATE")
		end
		_G.UIParent:RegisterEvent("ARTIFACT_UPDATE")
	end
end

function frame:InformEquippedArtifactChanged(artifactID)
	if artifactID ~= equippedID then
		Debug("ARTIFACT_EQUIPPED_CHANGED", equippedID, artifactID)
		callback:Fire("ARTIFACT_EQUIPPED_CHANGED", equippedID, artifactID)
		equippedID = artifactID
	end
end

function frame:StoreArtifact(artifactID, name, icon, unspentPower, numRanksPurchased, numRanksPurchasable, power, maxPower, traits, relics)
	if not artifacts[artifactID] then
		artifacts[artifactID] = {
			name = name,
			icon = icon,
			unspentPower = unspentPower,
			numRanksPurchased = numRanksPurchased,
			numRanksPurchasable = numRanksPurchasable,
			power = power,
			maxPower = maxPower,
			powerForNextTrait = maxPower - power,
			traits = traits,
			relics = relics,
		}
		callback:Fire("ARTIFACT_ADDED", artifactID)
	else
		local current = artifacts[artifactID]
		current.unspentPower = unspentPower
		current.numRanksPurchased = numRanksPurchased -- numRanksPurchased does not include bonus traits from relics
		current.numRanksPurchasable = numRanksPurchasable
		current.power = power
		current.maxPower = maxPower
		current.powerForNextTrait = maxPower - power
		current.traits = traits
		current.relics = relics
	end
end

function frame:ScanTraits(artifactID)
	local traits = {}
	local powers = GetPowers()

	for i = 1, #powers do
		local traitID = powers[i]
		local spellID, _, currentRank, maxRank, bonusRanks, _, _, _, isStart, isGold, isFinal = GetPowerInfo(traitID)
		if currentRank > 0 then
			local name, _, icon = GetSpellInfo(spellID)
			traits[#traits + 1] = {
				traitID = traitID,
				spellID = spellID,
				name = name,
				icon = icon,
				currentRank = currentRank,
				maxRank = maxRank,
				bonusRanks = bonusRanks,
				isGold = isGold,
				isStart = isStart,
				isFinal = isFinal,
			}
		end
	end

	if artifactID then
		artifacts[artifactID].traits = traits
	end

	return traits
end

function frame:ScanRelics(artifactID)
	-- TODO: relics changes don't trigger ARTIFACT_XP_UPDATE; need to rescan traits
	local relics = {}
	for i = 1, GetNumRelicSlots() do
		local slotType = GetRelicSlotType(i)
		local lockedReason, name, icon, link = GetRelicInfo(i)
		local isLocked = lockedReason and true or false
		local itemID
		if name then
			itemID = strmatch(link, "item:(%d+):")
		end

		relics[i] = { type = slotType, isLocked = isLocked, name = name, icon = icon, itemID = itemID }
	end

	if artifactID then
		artifacts[artifactID].relics = relics
	end

	return relics
end

function frame:GetArtifactKnowledge()
	local kLvl = GetArtifactKnowledgeLevel() -- TODO: track chages without C_ArtifactUI -- GetCurrencyInfo(1171)
	local mult = GetArtifactKnowledgeMultiplier()
	if knowledgeMultiplier ~= mult or knowledgeLevel ~= kLvl then
		knowledgeLevel = kLvl
		knowledgeMultiplier = mult
		callback:Fire("Artifact_Knowledge_Changed", knowledgeLevel, knowledgeMultiplier)
	end
end

function frame:GetViewedArtifactData()
	self:GetArtifactKnowledge()
	local itemID, _, name, icon, unspentPower, numRanksPurchased = GetArtifactInfo() -- TODO: appearance stuff needed? altItemID ?
	Debug("GetViewedArtifactData", name, itemID)
	local numRanksPurchasable, power, maxPower = GetNumPurchasableTraits(numRanksPurchased, unspentPower)
	local traits = self:ScanTraits()
	local relics = self:ScanRelics()
	self:StoreArtifact(itemID, name, icon, unspentPower, numRanksPurchased, numRanksPurchasable, power, maxPower, traits, relics)

	if IsViewedArtifactEquipped() then
		self:InformEquippedArtifactChanged(itemID)
	end
end

function frame:ScanContainer(container, numObtained)
	for slot = 1, GetContainerNumSlots(container) do
		local _, _, _, quality = GetContainerItemInfo(container, slot)
		if quality == LE_ITEM_QUALITY_ARTIFACT then
			SocketContainerItem(container, slot)
			self:GetViewedArtifactData()
			Clear()
			numObtained = numObtained - 1
			if numObtained <= 0 then break end
		end
	end

	return numObtained
end

function frame:IterateContainers(from, to, numObtained)
	for container = from, to do
		numObtained = self:ScanContainer(container, numObtained)
		if numObtained <= 0 then break end
	end

	return numObtained
end

function frame:InitializeScan(event)
	if _G.ArtifactFrame and _G.ArtifactFrame:IsShown() then
		Debug("InitializeScan", "aborted because ArtifactFrame is open.")
		return
	end

	local numObtained = GetNumObtainedArtifacts() -- not available at cold login
	Debug("InitializeScan", event, "numObtained", numObtained)

	if numObtained > 0 then
		self:PrepareForScan()
		if HasArtifactEquipped() then -- scan equipped
			SocketInventoryItem(INVSLOT_MAINHAND)
			self:GetViewedArtifactData()
			Clear()
			numObtained = numObtained - 1
		end
		if numObtained > 0 then -- scan bags
			numObtained = self:IterateContainers(BACKPACK_CONTAINER, NUM_BAG_SLOTS, numObtained)
		end
		if numObtained > 0 then -- scan bank
			numObtained = self:ScanContainer(BANK_CONTAINER, numObtained)
			if numObtained > 0 then
				self:IterateContainers(NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS, numObtained)
			end
		end
		self:RestoreStateAfterScan()
	end
end

function frame:ADDON_LOADED(name)
	if (name ~= MAJOR) then return end

	_G.ladDB = {}
	local db = _G.ladDB

	for funcName in pairs(aUI) do
		db[#db + 1] = funcName
	end

	table.sort(db)

	self:UnregisterEvent("ADDON_LOADED")
end

function frame:PLAYER_ENTERING_WORLD()
	_G.C_Timer.After(5, function()
		frame:InitializeScan()
		frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	end)
end

function frame:ARTIFACT_UPDATE(newItem)
	-- register SPELLS_CHANGED to pick up traits changes
	Debug("ARTIFACT_UPDATE", newItem)
	if newItem then
		self:GetViewedArtifactData()
	else
		-- traits or relics updated?
		-- can only change traits and perks for equipped?
	end
end

function frame:ARTIFACT_XP_UPDATE()
	local itemID, _, _, _, unspentPower, numRanksPurchased = GetEquippedArtifactInfo()
	local numRanksPurchasable, power, maxPower = GetNumPurchasableTraits(numRanksPurchased, unspentPower)

	local equipped = artifacts[itemID]
	local diff = unspentPower - equipped.unspentPower

	if numRanksPurchased ~= equipped.numRanksPurchased then
		-- both learning traits and artifact respec trigger ARTIFACT_XP_UPDATE
		-- however respec has a positiv diff and learning traits has a negativ one
		self:ScanTraits(equippedID)
		callback:Fire("ARTIFACT_TRAITS_UPDATE", itemID, numRanksPurchased, CopyTable(artifacts[itemID].traits))
	end

	if diff ~= 0 then
		equipped.unspentPower = unspentPower
		equipped.power = power
		equipped.maxPower = maxPower
		equipped.numRanksPurchased = numRanksPurchased
		equipped.numRanksPurchasable = numRanksPurchasable
		equipped.powerForNextTrait = maxPower - power
		callback:Fire("ARTIFACT_XP_UPDATE", diff, unspentPower, power, maxPower, maxPower - power, numRanksPurchasable)
	end
end

function frame:PLAYER_EQUIPMENT_CHANGED(slot)
	if slot == INVSLOT_MAINHAND then
		local itemID = GetEquippedArtifactInfo()

		if itemID and GetNumObtainedArtifacts() ~= lib:GetNumObtainedArtifacts() then
			-- TODO: at this time on cold login GetNumObtainedArtifacts() returns 1 (only the equipped)
			self:InitializeScan("PLAYER_EQUIPMENT_CHANGED")
		end

		self:InformEquippedArtifactChanged(itemID)
	end
end

function frame:ARTIFACT_RESPEC_PROMPT(...)
	Debug("ARTIFACT_RESPEC_PROMPT", ...)
end

function lib:GetArtifactInfo(artifactID)
	artifactID = artifactID or equippedID
	return artifactID, CopyTable(artifacts[artifactID])
end

function lib:GetAllArtifactsInfo()
	return CopyTable(artifacts)
end

function lib:GetNumObtainedArtifacts()
	local numArtifacts = 0
	for artifact in pairs(artifacts) do
		numArtifacts = numArtifacts + 1
	end

	return numArtifacts
end

function lib:GetArtifactTraits(artifactID)
	artifactID = artifactID or equippedID
	for itemID, data in pairs(artifacts) do
		if itemID == artifactID then
			return artifactID, CopyTable(data.traits)
		end
	end
end

function lib:GetArtifactRelics(artifactID)
	artifactID = artifactID or equippedID
	for itemID, data in pairs(artifacts) do
		if itemID == artifactID then
			return artifactID, CopyTable(data.relics)
		end
	end
end

function lib:GetArtifactPower(artifactID)
	artifactID = artifactID or equippedID
	for itemID, data in pairs(artifacts) do
		if itemID == artifactID then
			return artifactID, data.unspentPower, data.power, data.maxPower, data.powerForNextTrait, data.numRanksPurchased, data.numRanksPurchasable
		end
	end
end

function lib:ForceUpdate()
	frame:InitializeScan("FORCE_UPDATE")
end
