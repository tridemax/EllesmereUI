if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_TalentSets.lua  (WoW Forever only)
--  Talent Set Bindings: on a switch between primary and secondary talents,
--  equips the new set's gear set and switches to its Cooldown Manager layout.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.talentSets; unset keys read these.
--   enabled             Talent Set Bindings
--   announce            report each gear and layout swap in chat
--   chars[player GUID]  [talent set] = { gear = set name, layout = layout ID }
local F = module.Feature("talentSets", { enabled = false, announce = true })
local IsEnabled = F.Enabled

local ev = CreateFrame("Frame")
local switching = false  -- a talent set switch has started and not ended yet

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
    local ok, result = pcall(C_EquipmentSet.UseEquipmentSet, id)
    if ok and result ~= false then
        Announce(EllesmereUI.Lf("Equipping gear set %s.", Hi(shown)))
    else
        Say(EllesmereUI.Lf("Could not equip gear set %s.", Hi(shown)))
    end
end

-------------------------------------------------------------------------------
--  Cooldown Manager layouts (the game's own)
--  A switch from addon code taints the game's Cooldown Manager until a
--  reload, so every switch offers one.
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

local function SwitchLayout(id)
    local s, lm = CooldownViewerSettings, LayoutManager()
    if not lm or lm:GetActiveLayoutID() == id then return end
    local layout = lm:GetLayout(id)
    if not (layout and lm:CanActivateLayout(layout)) then
        Say(EllesmereUI.L("The Cooldown Manager layout picked for this talent set no longer exists."))
        return
    end
    local name = Hi(CooldownManagerLayout_GetName(layout))
    -- The switch saves the game's layouts: never over unsaved edits in its settings.
    if lm:HasPendingChanges() then
        Say(EllesmereUI.Lf("Cooldown Manager layout %s not switched to: its settings have unsaved changes.", name))
        return
    end
    if not pcall(s.SetActiveLayoutByID, s, id) then
        Say(EllesmereUI.Lf("Could not switch the Cooldown Manager layout to %s.", name))
        return
    end
    Announce(EllesmereUI.Lf("Switched the Cooldown Manager layout to %s.", name))
    local cdm = EllesmereUI._ModuleNS and EllesmereUI._ModuleNS.EllesmereUICooldownManager
    if cdm and cdm.ResyncWithBlizzardLayout then cdm.ResyncWithBlizzardLayout() end
    -- A confirm, not RequestReload: an event cannot reload, its click can.
    EllesmereUI:ShowConfirmPopup({
        title       = EllesmereUI.L("Reload Required"),
        message     = EllesmereUI.L("The Cooldown Manager layout was switched. Reload so its cooldowns and buffs update."),
        confirmText = EllesmereUI.L("Reload Now"),
        cancelText  = EllesmereUI.L("Later"),
        reload      = true,
    })
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
    if b.layout then SwitchLayout(b.layout) end
end

-- A switch starts with ACTIVE_TALENT_GROUP_CHANGED and ends with PLAYER_SPECIALIZATION_CHANGED.
-- Apply a frame after the end, once the game has finished the switch.
ev:SetScript("OnEvent", function(_, event)
    if event == "ACTIVE_TALENT_GROUP_CHANGED" then
        switching = true
    elseif switching then
        switching = false
        C_Timer.After(0, ApplyBindings)
    end
end)

local function Apply()
    if IsEnabled() then
        ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        ev:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    else
        ev:UnregisterAllEvents()
        switching = false
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
