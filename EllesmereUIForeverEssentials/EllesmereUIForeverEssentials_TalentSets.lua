if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_TalentSets.lua  (WoW Forever only)
--  Talent Set Bindings: on a switch between primary and secondary talents,
--  equips the new set's gear set and names its Cooldown Manager layout.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.talentSets; unset keys read these.
--   enabled             Talent Set Bindings
--   announce            report each gear swap in chat
--   chars[player GUID]  [talent set] = { gear = set name, layout = layout ID }
local F = module.Feature("talentSets", { enabled = false, announce = true })
local IsEnabled = F.Enabled

local ev = CreateFrame("Frame")

local function Say(msg)
    EllesmereUI.Print(EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r " .. msg)
end
local function Announce(msg)
    if F.Get("announce") then Say(msg) end
end
local function Hi(text)
    return EllesmereUI.HexColor(EllesmereUI.GetAccentColor()) .. tostring(text) .. "|r"
end

-- 1 = primary talents, 2 = secondary; nil before the game reports one.
local function ActiveSet()
    local set = C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup()
    return type(set) == "number" and set or nil
end

-- This character's binding for one talent set; nil until written, unless create.
local function Binding(set, create)
    local guid = UnitGUID("player")
    if not (guid and set) then return nil end
    local cfg = create and F.Cfg() or F.Read()
    if create then
        cfg.chars = cfg.chars or {}
        cfg.chars[guid] = cfg.chars[guid] or {}
        cfg.chars[guid][set] = cfg.chars[guid][set] or {}
    end
    local c = cfg.chars and cfg.chars[guid]
    return c and c[set]
end

local function SetBinding(set, key, value)
    local b = Binding(set, value ~= nil)
    if b then b[key] = value end
end

-------------------------------------------------------------------------------
--  Gear sets (the Equipment Manager's, by name)
-------------------------------------------------------------------------------
local NO_SETS = {}  -- read-only stand-in while the game lists none

local function ListGearSets()
    local list = {}
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or NO_SETS) do
        local name = C_EquipmentSet.GetEquipmentSetInfo(id)
        if name then list[#list + 1] = { name = name } end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

local function GearSetID(name)
    local wanted = name:lower()
    for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or NO_SETS) do
        local n = C_EquipmentSet.GetEquipmentSetInfo(id)
        if n and n:lower() == wanted then return id, n end
    end
end

local function EquipGear(name)
    local id, shown = GearSetID(name)
    if not id then
        Say(EllesmereUI.Lf("Gear set %s not found; it may have been renamed or deleted.", Hi(name)))
        return
    end
    local _, _, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(id)
    if isEquipped then return end
    -- The game's own Equip refuses these too. The cast name can read secret: test its type only.
    local busy = C_EquipmentSet.EquipmentSetContainsLockedItems(id) or type(UnitCastingInfo("player")) ~= "nil"
    local ok, result = false, false
    if not busy then ok, result = pcall(C_EquipmentSet.UseEquipmentSet, id) end
    if ok and result ~= false then
        Announce(EllesmereUI.Lf("Equipping gear set %s.", Hi(shown)))
    else
        Say(EllesmereUI.Lf("Could not equip gear set %s.", Hi(shown)))
    end
end

-------------------------------------------------------------------------------
--  Cooldown Manager layouts (the game's own, read only)
--  Never switch one from here: SetActiveLayoutByID saves and refreshes the
--  game's Cooldown Manager from addon code, which taints it until a reload.
-------------------------------------------------------------------------------
-- nil until the game has loaded its layouts.
local function LayoutManager()
    local s = CooldownViewerSettings
    if not (s and s.GetLayoutManager) then return nil end
    local ok, lm = pcall(s.GetLayoutManager, s)
    if ok and lm and lm.IsLoaded and lm:IsLoaded() then return lm end
end

-- The layouts this character can use: { id, name } by name.
local function ListLayouts()
    local list, lm = {}, LayoutManager()
    if not lm then return list end
    for id, layout in lm:EnumerateLayouts() do
        if lm:CanActivateLayout(layout) then
            list[#list + 1] = { id = id, name = CooldownManagerLayout_GetName(layout) }
        end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

local function RemindLayout(id)
    local lm = LayoutManager()
    if not lm or lm:GetActiveLayoutID() == id then return end
    local layout = lm:GetLayout(id)
    if not (layout and lm:CanActivateLayout(layout)) then
        Say(EllesmereUI.L("The Cooldown Manager layout picked for this talent set no longer exists."))
        return
    end
    Say(EllesmereUI.Lf("Switch the Cooldown Manager layout to %s for these talents.", Hi(CooldownManagerLayout_GetName(layout))))
end

-------------------------------------------------------------------------------
--  Apply
-------------------------------------------------------------------------------
local function ApplyBindings()
    if not IsEnabled() then return end
    if InCombatLockdown() then
        EllesmereUI.CombatQueue.Defer("TalentSets", ApplyBindings)
        return
    end
    local b = Binding(ActiveSet())
    if not b then return end
    if b.gear then EquipGear(b.gear) end
    if b.layout then RemindLayout(b.layout) end
end

-- Only a switch from one talent set to the other; next frame, after the event's other handlers.
ev:SetScript("OnEvent", function(_, _, curr, prev)
    if type(prev) == "number" and prev > 0 and curr ~= prev then
        C_Timer.After(0, ApplyBindings)
    end
end)

local function Apply()
    if IsEnabled() then
        ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    else
        ev:UnregisterAllEvents()
    end
end

-- Options-page entry points.
EllesmereUI._TalentSets = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
    Binding = Binding,
    SetBinding = SetBinding,
    ListGearSets = ListGearSets,
    ListLayouts = ListLayouts,
}

F.Start(Apply)
