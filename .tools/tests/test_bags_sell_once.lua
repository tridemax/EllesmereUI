-- lua .tools/tests/test_bags_sell_once.lua (from the repository root)
-- Real mark storage, classification and selling over a simulated inventory.
local function Read(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return text
end
local checks = 0
local function Check(ok, message)
    checks = checks + 1
    assert(ok, message)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local owner = "Player-A"
local profile, inventory, queue, sold = {}, {}, {}, {}
local combat, held, refuse, secret = false, false, false, false
local sets, pins, special = {}, {}, nil
function UnitGUID() return owner end
function InCombatLockdown() return combat end
function CursorHasItem() return held end
function issecretvalue() return secret end
function BP() return profile end
local function Slot(bag, slot) return inventory[bag * 1000 + slot] end
local function Put(bag, slot, id, guid, quality, count)
    local info = {itemID = id, guid = guid, quality = quality or 2, stackCount = count or 1, hyperlink = 'item:' .. id}
    inventory[bag * 1000 + slot] = info
    return info
end
ItemLocation = {CreateFromBagAndSlot = function(_, bag, slot)
    return {bag = bag, slot = slot, SetBagAndSlot = function(self, b, s) self.bag, self.slot = b, s end}
end}
C_Item = {
    DoesItemExist = function(loc) return Slot(loc.bag, loc.slot) ~= nil end,
    GetItemGUID = function(loc) local info = Slot(loc.bag, loc.slot); return info and info.guid end,
    GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, 4 end,
    GetItemInfo = function() return 'Item', nil, 2, nil, nil, nil, nil, nil, nil, nil, 100 end,
}
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 10 or (bag == 1 and 4 or 0) end,
    GetContainerItemInfo = Slot,
    GetContainerItemID = function(bag, slot) local info = Slot(bag, slot); return info and info.itemID end,
    GetContainerItemQuestInfo = function() end,
    GetContainerItemPurchaseInfo = function(bag, slot) return {refundSeconds = Slot(bag, slot).refund or 0} end,
    UseContainerItem = function(bag, slot)
        sold[#sold + 1] = Slot(bag, slot).guid
        if not refuse then inventory[bag * 1000 + slot] = nil end
    end,
}
C_EquipmentSet = {GetEquipmentSetIDs = function() return {} end}
Enum = {ItemClass = {Consumable=0, Container=1, Weapon=2, Gem=3, Armor=4, Reagent=5,
    Tradegoods=7, ItemEnhancement=8, Recipe=9, Questitem=12, Miscellaneous=15}}
EllesmereUI = {
    IS_FOREVER = true, _bagsDB = {profile = profile}, Lite = {IsDBReady = function() return true end},
    L = function(s) return s end,
    Lf = function(s, ...) return string.format(s:gsub('%%1%$', '%%'), ...) end,
    COLOR_CODES = {BRAND = ''}, Print = function() end,
}
EllesmereUIDB = {}
ns = {
    SpecialBags = function() return special end,
    PinnedItems = function() return pins end,
    IsItemPinned = function(p, _, id) return p[id] end,
}
assert(loadfile('EllesmereUIBags/EllesmereUIBags_Categories.lua'))('Bags', ns)
local CM = EUI_CategoryManager
Put(0, 1, 100, 'item-A')
Put(0, 2, 100, 'item-B')
Check(not CM:IsSellOnce(100, 0, 1) and EllesmereUIDB.bagSellOnceByChar == nil, 'Reads must not create saved marks')
Check(CM:ToggleSellOnce(0, 1), 'Mark an item')
Check(CM:IsSellOnce(100, 0, 1) and not CM:IsSellOnce(100, 0, 2), 'Identical copy must remain unmarked')
Check(not CM:IsJunk(100, 2) and CM:IsJunk(100, 2, 0, 1), 'One-time mark must not become a permanent rule')
owner = 'Player-B'
Check(not CM:IsJunk(100, 2, 0, 1), 'Another character must not inherit a mark')
owner = 'Player-A'
inventory[1001], inventory[1] = inventory[1], nil
Check(CM:IsSellOnce(100, 1, 1), 'Mark must follow a moved item')
local saved = EllesmereUIDB
EUI_CategoryManager = nil
assert(loadfile('EllesmereUIBags/EllesmereUIBags_Categories.lua'))('Bags', ns)
CM = EUI_CategoryManager
Check(EllesmereUIDB == saved, 'Reload must preserve saved marks')
Check(CM:IsSellOnce(100, 1, 1), 'Mark must survive reloading the module')
CM:FinishSellOnce('item-A')
Check(CM:IsSellOnce(100, 1, 1), 'Moved item must not be mistaken for a sale')
CM:ToggleSellOnce(1, 1)
Check(not CM:IsSellOnce(100, 1, 1), 'Second click must unmark')
CM:AssignItem(100, 'Armor')
CM:ToggleSellOnce(1, 1)
local items = {
    {bag=1, slot=1, info=inventory[1001], itemLink='item:100'},
    {bag=0, slot=2, info=inventory[2], itemLink='item:100'},
}
CM:ClassifyAll(items)
Check(CM:GetCategories()[items[1].categoryIndex].isJunk and items[1]._isJunk, 'Marked instance must go to Junk')
Check(CM:GetCategories()[items[2].categoryIndex]._defaultName == 'Armor' and not items[2]._isJunk, 'Other copy keeps its category')
Check(CM:IsJunkData(items[1], 2) and not CM:IsJunkData(items[2], 2), 'Renderers read the classification stamps')
Check(CM:IsJunkData({bag=1, slot=1, info=inventory[1001]}, 2), 'An unclassified entry reads its slot')
CM:ToggleSellOnce(1, 1)
CM:ClassifyAll(items)
Check(CM:GetCategories()[items[1].categoryIndex]._defaultName == 'Armor', 'Unmark must restore custom assignment')
CM:ToggleJunk(100)
Check(CM:IsJunk(100, 2, 0, 2), 'Permanent marking still applies to every copy')
Check(not CM:ToggleSellOnce(0, 2), 'One-time mode must not silently change a permanent rule')
CM:ToggleJunk(100)
Check(EllesmereUIDB.bagItemAssignments[100] == 'Armor', 'Permanent unmark restores prior assignment')
secret = true
Check(not CM:ToggleSellOnce(0, 2), 'Secret identity must never be indexed or persisted')
secret = false
inventory[2].guid = ''
Check(not CM:ToggleSellOnce(0, 2), 'Missing identity must fail closed')
inventory[2].guid = 'item-B'
CM:ToggleSellOnce(0, 2)
inventory[2].stackCount = 2
Check(not CM:IsSellOnce(100, 0, 2), 'Adding an unmarked item to a stack cannot authorize selling it')
inventory[2].stackCount = 1
Check(CM:IsSellOnce(100, 0, 2), 'Original marked quantity remains eligible')

-- A stack that shrank (with the bags closed: BAG_UPDATE only) cannot be refilled into the sale.
local stack = Put(0, 3, 102, 'stack', 2, 20)
CM:ToggleSellOnce(0, 3)
stack.stackCount = 5; stack.isLocked = true
CM:ClampSellOnce(0)
stack.stackCount = 20; stack.isLocked = nil
Check(CM:IsSellOnce(102, 0, 3), 'A locked stack (mid-split) keeps its marked size')
stack.stackCount = 5
CM:ClampSellOnce(0)
stack.stackCount = 20
Check(not CM:IsSellOnce(102, 0, 3), 'A refilled stack must not sell the refill')
stack.stackCount = 5
Check(CM:IsSellOnce(102, 0, 3), 'The shrunken stack itself stays marked')
stack.stackCount = 3
Check(CM:IsSellOnce(102, 0, 3), 'A read clamps too')
stack.stackCount = 5
Check(not CM:IsSellOnce(102, 0, 3), 'Each shrink lowers the marked size')
CM:ClampSellOnce('not a bag')
inventory[3] = nil

-- What Sell Junk would always keep back cannot be marked, but can be unmarked.
CM.GetSetGearLookup = function() return sets end
for _, protection in ipairs({'pinned', 'set', 'refund', 'value'}) do
    local info = Put(0, 4, 103, 'blocked-' .. protection)
    wipe(pins); wipe(sets)
    if protection == 'pinned' then pins[103] = true
    elseif protection == 'set' then sets[4] = true
    elseif protection == 'refund' then info.refund = 100
    else info.hasNoValue = true end
    local ok, reason = CM:ToggleSellOnce(0, 4)
    Check(not ok and type(reason) == 'string' and not CM:IsSellOnce(103, 0, 4), 'Refuse marking: ' .. protection)
end
wipe(pins); wipe(sets)
Put(0, 4, 103, 'pinned-later')
CM:ToggleSellOnce(0, 4)
pins[103] = true
Check(CM:ToggleSellOnce(0, 4) and not CM:IsSellOnce(103, 0, 4), 'A mark can always be removed')
wipe(pins); inventory[4] = nil

-- Exercise the actual sale loop, including its delayed steps and rechecks.
EUI_Bags = {}
_openItemPanels = {merchant = true}
GetItemInfo = C_Item.GetItemInfo
function PinnedItems() return pins end
function IsItemPinned(p, _, id) return p[id] end
CM.GetSetGearLookup = function() return sets end
C_CurrencyInfo = {GetCoinTextureString = tostring}
C_Timer = {After = function(_, fn) queue[#queue + 1] = fn end}
function CreateFrame()
    return {SetScript=function(self, _, fn) self.handler=fn end, RegisterEvent=function() end, UnregisterAllEvents=function() end}
end
local selectSource = Read('EllesmereUIBags/EUI_Bags_Select.lua')
local start = assert(selectSource:find('local function GatherJunkSlots', 1, true))
local finish = assert(selectSource:find('-- Profile switch:', start, true))
assert(loadstring(selectSource:sub(start, finish - 1)))()
local function Flush()
    local n = 0
    while #queue > 0 do
        n = n + 1; assert(n < 50, 'Unexpected rescheduling')
        table.remove(queue, 1)()
    end
end
local function Reset()
    wipe(inventory); wipe(queue); wipe(sold); wipe(sets); wipe(pins)
    EllesmereUIDB = {}; special = nil; combat = false; held = false; refuse = false
    EUI_Bags._junkSelling = nil; _openItemPanels.merchant = true
end
Reset()
Put(0, 1, 100, 'sale-A'); Put(0, 2, 100, 'keep-B')
CM:ToggleSellOnce(0, 1)
EUI_Bags:SellJunk(); Flush()
Check(#sold == 1 and sold[1] == 'sale-A' and inventory[2], 'Only the marked instance sells')
Put(0, 1, 100, 'sale-A')
Check(not CM:IsSellOnce(100, 0, 1), 'Successful sale clears mark even if bought back')
Reset()
Put(0, 1, 100, 'refused'); CM:ToggleSellOnce(0, 1); refuse = true
EUI_Bags:SellJunk(); Flush()
Check(CM:IsSellOnce(100, 0, 1), 'Refused sale retains mark for next visit')
Reset()
Put(0, 1, 100, 'first'); Put(0, 2, 101, 'second')
CM:ToggleSellOnce(0, 1); CM:ToggleSellOnce(0, 2)
EUI_Bags:SellJunk()
Put(0, 2, 101, 'replacement')
CM:AssignItem(101, CM.JUNK_KEY)
Flush()
Check(#sold == 1 and inventory[2].guid == 'replacement', 'Same-ID replacement must not sell, even if permanent junk')
for _, protection in ipairs({'pinned', 'set', 'refund', 'value', 'locked', 'combat', 'cursor', 'closed', 'special'}) do
    Reset()
    local info = Put(0, 1, 100, protection)
    CM:ToggleSellOnce(0, 1)
    if protection == 'pinned' then pins[100] = true
    elseif protection == 'set' then sets[1] = true
    elseif protection == 'refund' then info.refund = 100
    elseif protection == 'value' then info.hasNoValue = true
    elseif protection == 'locked' then info.isLocked = true
    elseif protection == 'combat' then combat = true
    elseif protection == 'cursor' then held = true
    elseif protection == 'closed' then _openItemPanels.merchant = false
    elseif protection == 'special' then special = {[0]=true} end
    EUI_Bags:SellJunk(); Flush()
    Check(#sold == 0 and CM:IsSellOnce(100, 0, 1), 'Preserve protected mark: ' .. protection)
end
Reset()
Put(0, 1, 100, 'first'); Put(0, 2, 101, 'pin-later')
CM:ToggleSellOnce(0, 1); CM:ToggleSellOnce(0, 2)
EUI_Bags:SellJunk(); pins[101] = true; Flush()
Check(#sold == 1 and inventory[2], 'Protection acquired during sale must be rechecked')
Reset()
Put(0, 1, 100, 'carried'); Put(0, 2, 101, 'sold-by-hand')
CM:ToggleSellOnce(0, 1); CM:ToggleSellOnce(0, 2)
inventory[2] = nil
_openItemPanels.merchant = false; EUI_Bags:SellJunk(); Flush()
Check(next(EllesmereUIDB.bagSellOnceByChar[owner]) ~= nil, 'No pruning without a sweep')
_openItemPanels.merchant = true; refuse = true; EUI_Bags:SellJunk(); Flush()
local left = EllesmereUIDB.bagSellOnceByChar[owner]
Check(left['carried'] and not left['sold-by-hand'], 'A sweep drops marks of items no longer carried')

-- Every Recent Items entry point uses the classification result, per instance.
local predicates = 0
for _, path in ipairs({'EUI_Bags_Refresh.lua', 'EllesmereUIBags_Grid.lua', 'EllesmereUIBags_List.lua'}) do
    local text = Read('EllesmereUIBags/' .. path)
    for line in text:gmatch('[^\n]+') do
        if line:find('_isJunk', 1, true) then
            local expr = line:match('if (.-) then') or line:match('show = (.+)')
            if expr then
                predicates = predicates + 1
                local check = assert(loadstring('return function(data, d, EUI_Bags, recentSet) return ' .. expr .. ' end'))()
                local d = {info={itemID=100}, _isJunk=true}
                Check(not check(d, d, {_recentItems={[100]=1}}, {[100]=1}), path .. ': junk excluded')
                d._isJunk = false
                Check(check(d, d, {_recentItems={[100]=1}}, {[100]=1}), path .. ': unmarked copy retained')
            end
        end
    end
end
Check(predicates == 5, 'All five Recent Items filters tested')
local dataSource = Read('EllesmereUIBags/EUI_Bags_Data.lua')
local merge = assert(dataSource:match('(local function MergeDuplicates.-)\n%-%- Saved visual order'))
SetPaintedPanelOpen = function() end
IsGearCategory = function() return false end
AcquireSlotTable = function() return {} end
local Merge = assert(loadstring(merge .. '\nreturn MergeDuplicates'))()
local a = {itemLink='item:100', info={stackCount=1}, _sellOnce=true}
local b = {itemLink='item:100', info={stackCount=1}}
Check(#Merge({a,b}) == 2, 'Marked instance must stay separate from its identical copy')
a._sellOnce = nil; EUI_Bags._junkMode = 'sell'
Check(#Merge({a,b}) == 2, 'Sell selection exposes real stacks')
EUI_Bags._junkMode = nil
Check(#Merge({a,b}) == 1, 'Normal merging resumes after selection')

-- The actual header/catcher callbacks choose different persistence rules.
Reset()
local ctrl, cursor = false, false
local entered, exited, tip
EUI = EllesmereUI
EUI.HideWidgetTooltip = function() tip = nil end
EUI.ShowWidgetTooltip = function(_, text) tip = text end
EUI.PadCursorShown = function() return false end
function IsControlKeyDown() return ctrl end
function GetCursorInfo() if cursor then return 'item', 100 end end
function ClearCursor() cursor = false end
function EnterAssignSelectMode(_, mode) entered = mode; EUI_Bags._junkMode = mode end
function ExitAssignSelectMode() exited = true; EUI_Bags._junkMode = nil end
EUI_Bags.RefreshInventory = function() end
ns.RefreshOpenBank = function() end
junk = {SetScript = function(self, _, fn) self.click = fn end}
local clickStart = assert(selectSource:find('    junk:SetScript("OnClick", function(self)', 1, true))
local clickEnd = assert(selectSource:find('    -- A double-click', clickStart, true))
assert(loadstring(selectSource:sub(clickStart, clickEnd - 1)))()
junk.click(junk)
Check(entered == 'sell', 'Normal button click enters one-time mode')
junk.click(junk)
Check(exited and not EUI_Bags._junkMode, 'Second button click exits')
ctrl = true; junk.click(junk)
Check(entered == true, 'Ctrl-click enters permanent mode')
ExitAssignSelectMode(); combat = true; entered = nil
junk.click(junk)
Check(entered == nil, 'Combat cannot enter selection mode')
combat = false; ctrl = false; cursor = true
junk.click(junk)
Check(cursor and tip and entered == nil, 'Cursor item without identity is not guessed or permanently marked')
local cursorLoc = {bag = 0, slot = 1}
function cursorLoc:IsBagAndSlot() return self.bag ~= nil end
function cursorLoc:GetBagAndSlot() return self.bag, self.slot end
C_Cursor = {GetCursorItem = function() return cursorLoc end}
Put(0, 1, 100, 'carried-mark')
tip = nil; junk.click(junk)
Check(not cursor and CM:IsSellOnce(100, 0, 1) and not CM:IsJunk(100, 2) and entered == nil,
    'A carried bag item is marked for a one-time sale and put back')
cursor = true; junk.click(junk)
Check(not cursor and not CM:IsSellOnce(100, 0, 1), 'Carrying it again unmarks it')
cursor = true; pins[100] = true; tip = nil; junk.click(junk)
Check(cursor and tip and not CM:IsSellOnce(100, 0, 1), 'A carried item Sell Junk keeps back stays carried, with the reason')
wipe(pins); cursorLoc.bag = nil; tip = nil; junk.click(junk)
Check(cursor and tip and not CM:IsSellOnce(100, 0, 1), 'A carried item from outside the bags is refused')
C_Cursor = nil
cursor = false
cf = {SetScript = function(self, _, fn) self.click = fn end}
local catcherStart = assert(selectSource:find('        cf:SetScript("OnMouseDown", function(_, button)', 1, true))
local catcherEnd = assert(selectSource:find('        cf:SetAllPoints(UIParent)', catcherStart, true))
assert(loadstring(selectSource:sub(catcherStart, catcherEnd - 1)))()
ClearHover = function() end
FindBtnUnderCursor = function()
    return {GetID = function() return 1 end, GetParent = function() return {GetID = function() return 0 end} end}
end
ns.RepaintJunkItem = function() end
_assignSelectCatKey = CM.JUNK_KEY
Put(0, 1, 100, 'clicked')
EUI_Bags._junkMode = 'sell'
cf.click(cf, 'LeftButton')
Check(CM:IsSellOnce(100, 0, 1) and not CM:IsJunk(100, 2), 'Item click in sell mode creates only an instance mark')
cf.click(cf, 'LeftButton')
Check(not CM:IsSellOnce(100, 0, 1), 'Item click in sell mode also removes it')
cf.click(cf, 'LeftButton'); EUI_Bags._junkMode = true
cf.click(cf, 'LeftButton')
Check(CM:IsJunk(100, 2) and not CM:IsSellOnce(100, 0, 1), 'Permanent mode converts the selected temporary mark')
cf.click(cf, 'LeftButton')
Check(not CM:IsJunk(100, 2, 0, 1), 'Permanent mode removes permanent junk')
EUI_Bags._junkMode = 'sell'; cf.click(cf, 'RightButton')
Check(not EUI_Bags._junkMode, 'Right-click exits selection')
EUI.IS_FOREVER = false; entered = nil; junk.click(junk)
Check(entered == true, 'Retail keeps its existing normal-click behavior')

-- Exercise the real mode exit and the real OnShow refresh decision together.
local exitStart = assert(selectSource:find('local function ExitAssignSelectMode()', 1, true))
local exitEnd = assert(selectSource:find("-- Select modes' hit-test:", exitStart, true))
ExitAssignSelectMode = assert(loadstring(selectSource:sub(exitStart, exitEnd - 1) .. '\nreturn ExitAssignSelectMode'))()
local startSource = Read('EllesmereUIBags/EUI_Bags_Start.lua')
local showStart = assert(startSource:find('    EUI_Bags:HookScript("OnShow", function(self)', 1, true))
local showEnd = assert(startSource:find('        -- Controller cursor: scroll aids', showStart, true))
EUI_Bags.HookScript = function(self, _, fn) self.onShow = fn end
EUI_Bags.Raise = function() end
EUI_Bags.RepinIconLevels = function() end
PlaySound = function() end
SOUNDKIT = {IG_BACKPACK_OPEN = 1}
assert(loadstring(startSource:sub(showStart, showEnd - 1) .. '\nend)'))()
EUI_Bags.IsShown = function(self) return self.shown end
EUI_Bags.IsVisible = function(self) return self.shown end
EUI_Bags.SyncMergeButton = function() end
local refreshSource = Read('EllesmereUIBags/EUI_Bags_Refresh.lua')
local refreshStart = assert(refreshSource:find('function EUI_Bags:RefreshInventory()', 1, true))
local refreshEnd = assert(refreshSource:find('    ns.ApplySlotMetrics()', refreshStart, true))
local rendered
function PaintMergedItems() rendered = Merge({a,b}) end
assert(loadstring(refreshSource:sub(refreshStart, refreshEnd - 1) .. '\nPaintMergedItems()\nend'))()
EUI.IS_FOREVER = true
for _, exitBy in ipairs({'coin', 'right-click', 'escape', 'close'}) do
    for _, merging in ipairs({true, false}) do
        profile.bagMergeDuplicates = merging
        EUI_Bags.shown = true
        EUI_Bags._junkMode = 'sell'
        EUI_Bags._assignSelectMode = true
        EUI_Bags._junkDirty = true
        EUI_Bags:RefreshInventory()
        Check(#rendered == 2, exitBy .. ': individual stacks during selection')
        if exitBy == 'coin' then junk.click(junk)
        elseif exitBy == 'right-click' then cf.click(cf, 'RightButton')
        else
            if exitBy == 'close' then EUI_Bags.shown = false end
            ExitAssignSelectMode()
        end
        Check(not EUI_Bags._junkMode, exitBy .. ': clears the mode')
        if exitBy == 'close' then
            EUI_Bags.shown = true
            EUI_Bags:onShow()
        end
        Check(#rendered == (merging and 1 or 2), exitBy .. ': restores the configured grouping')
        Check(profile.bagMergeDuplicates == merging, exitBy .. ': preserves the saved preference')
    end
end
print('PASS test_bags_sell_once (' .. checks .. ' checks)')
