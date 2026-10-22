local addonName, WC = ...

-- Auction House overlay: tints rows of Blizzard's AH lists whose price is below what a vendor pays,
-- with a small "vendor +Xs" label (profit per item). Purely cosmetic; every call is pcall-wrapped.
--
-- Verified in wow-ui-source (branch forever, 1.60.1.70450), Blizzard_AuctionHouseUI:
--  * The three buy lists are AuctionHouseItemListTemplate / AuctionHouseCommoditiesBuyListTemplate frames with a
--    .ScrollBox (WowScrollBoxList, linear view). Their data provider is CreateIndexRangeDataProvider, so a row's
--    elementData is its index, and list.getEntry(index) returns the row data (Shared/Blizzard_AuctionHouseItemList.lua
--    :71-80, :355; Blizzard_SharedXML/IndexRangeDataProvider.lua:22-35).
--  * row.rowData is set by the table builder in its own OnInitializedFrame callback (SharedXML ScrollUtil.lua:1661,
--    TableBuilder.lua:323-328). CallbackRegistry runs callbacks in hash order (CallbackRegistry.lua:204), so ours may
--    run first and see a stale rowData; therefore we read the row data through list.getEntry(elementData).
--  * Row data: browse = BrowseResultInfo { itemKey, minPrice, totalQuantity } (BrowseResultsFrame.lua:47-51);
--    commodity = CommoditySearchResultInfo { itemID, unitPrice, quantity } (CommoditiesList.lua:133-134, 236-237);
--    item = ItemSearchResultInfo { itemKey, buyoutAmount (per item), quantity } (ItemBuyFrame.lua:94-95, 112).
--  * Rows are 20 px buttons (Mainline/Blizzard_AuctionHouseItemList.xml:4); cells are child frames laid out by the
--    table builder; we only add one texture pair + one font string per row frame, created once and reused.
local L = WC.L

WC.AddLocale({
  enUS = { AHL_VENDOR = "vendor +%s" },
  zhCN = { AHL_VENDOR = "商店 +%s" },
  zhTW = { AHL_VENDOR = "商店 +%s" },
})

local AHL = { hooked = false }
WC.AuctionTint = AHL

if WC.Store and WC.Store.Default then pcall(WC.Store.Default, WC.Store, "ahTint", true) end

-- col = table-builder column the label lines up with; "right" = right edge of that column, "after" = just after it
local LISTS = {
  { key = "browse",    frame = "BrowseResultsFrame",  col = 2, side = "right" },   -- price | name | (level) | qty | fav
  { key = "commodity", frame = "CommoditiesBuyFrame", col = 1, side = "after" },   -- unit price | quantity
  { key = "item",      frame = "ItemBuyFrame",        col = 3, side = "right" },   -- bid | buyout | qty | info | time
}
AHL.LISTS = LISTS

local function Enabled()
  local db = WaylaidCrateDB
  return not (db and db.ahTint == false)
end

-- item + price of one item for a row's data
local function RowPrice(spec, list, data)
  if type(data) ~= "table" then return nil end
  if spec.key == "browse" then
    local k = data.itemKey
    if type(k) ~= "table" or (k.battlePetSpeciesID or 0) ~= 0 or (data.totalQuantity or 0) <= 0 then return nil end
    return k.itemID, data.minPrice
  elseif spec.key == "commodity" then
    return data.itemID or list.itemID, data.unitPrice
  end
  if data.isVirtualEntry then return nil end
  local k = data.itemKey
  return type(k) == "table" and k.itemID or nil, data.buyoutAmount
end

-- vendor prices of items the client hasn't cached yet: ask for them, re-tint when they arrive
local pending = {}
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, itemID)
  if event == "AUCTION_HOUSE_SHOW" then
    if not AHL.hooked then AHL:TryHook() end
    return
  end
  if itemID and pending[itemID] then
    pending[itemID] = nil
    AHL:Refresh()
  end
end)
events:RegisterEvent("AUCTION_HOUSE_SHOW")

local function SellPrice(itemID)
  local sell = WC.SellPrice(itemID)
  if sell == nil and itemID then
    WC.RequestItem(itemID)
    if not next(pending) then
      events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
      events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    end
    pending[itemID] = true
  end
  return sell
end

-- x offset (from the row's left edge) for the label, from the list's table-builder columns
local function LabelX(spec, list)
  local tb = list.tableBuilder
  local cols = tb and tb.GetColumns and tb:GetColumns()
  local c = cols and cols[spec.col]
  local w = c and c:GetCalculatedWidth()
  if not w then return nil end
  local x = tb:GetTableMargins() or 0
  for i = 1, spec.col do
    x = x + (cols[i]:GetPadding() or 0)
    if i < spec.col then x = x + (cols[i]:GetCalculatedWidth() or 0) end
  end
  if spec.side == "after" then return x + w + 6 end
  local _, rightPad = c:GetCellPadding()
  return x + w - (rightPad or 0) - 4
end

local function Hide(p)
  if p then p.tex:Hide(); p.bar:Hide(); p.label:Hide() end
end

-- the tint parts of a row frame, created once per frame
local function Parts(row)
  local p = row.WaylaidCrateTint
  if p then return p end
  p = {}
  p.tex = row:CreateTexture(nil, "OVERLAY", nil, -1)
  p.tex:SetAllPoints()
  p.tex:SetColorTexture(0.2, 0.95, 0.35, 0.13)
  p.bar = row:CreateTexture(nil, "OVERLAY", nil, -1)
  p.bar:SetPoint("TOPLEFT")
  p.bar:SetPoint("BOTTOMLEFT")
  p.bar:SetWidth(2)
  p.bar:SetColorTexture(0.3, 1, 0.42, 0.9)
  p.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  p.label:SetWordWrap(false)
  p.label:SetTextColor(0.3, 1, 0.42)
  row.WaylaidCrateTint = p
  return p
end

local function Tint(spec, row, elementData)
  local list = spec.list
  local data
  if type(elementData) == "number" and type(list.getEntry) == "function" then data = list.getEntry(elementData) end
  if data == nil then data = row.rowData end
  local diff
  if Enabled() then
    local itemID, unit = RowPrice(spec, list, data)
    if itemID and unit and unit > 0 then
      local sell = SellPrice(itemID)
      if sell and sell > unit then diff = sell - unit end
    end
  end
  if not diff then
    Hide(row.WaylaidCrateTint)
    return
  end
  local p = Parts(row)
  local okX, x = pcall(LabelX, spec, list)
  if not okX then x = nil end
  p.label:ClearAllPoints()
  if spec.side == "after" then
    p.label:SetJustifyH("LEFT")
    p.label:SetWidth(100)
    p.label:SetPoint("LEFT", row, "LEFT", x or 156, 0)
  else
    p.label:SetJustifyH("RIGHT")
    p.label:SetWidth(120)
    if x then p.label:SetPoint("RIGHT", row, "LEFT", x, 0) else p.label:SetPoint("RIGHT", row, "RIGHT", -150, 0) end
  end
  p.label:SetText(L.AHL_VENDOR:format(WC.Money(diff)))
  p.tex:Show()
  p.bar:Show()
  p.label:Show()
end

local function SafeTint(spec, row, elementData)
  local ok, err = pcall(Tint, spec, row, elementData)
  if not ok and WC.Debug then WC.Debug("AuctionTint", err) end
end

-- tint every row currently shown in the visible lists
function AHL:RetintNow()
  for _, spec in ipairs(LISTS) do
    local list = spec.list
    if list then
      pcall(function()
        if not list:IsVisible() then return end
        local box = list.ScrollBox
        if box.HasView and not box:HasView() then return end
        box:ForEachFrame(function(row, elementData) SafeTint(spec, row, elementData) end)
      end)
    end
  end
  if not next(pending) then
    events:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    events:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
  end
end

function AHL:Refresh()
  if self.queued or not self.hooked then return end
  self.queued = true
  C_Timer.After(0.2, function()
    self.queued = false
    self:RetintNow()
  end)
end

function AHL:Hook()
  local ah = _G.AuctionHouseFrame
  if self.hooked or not ah then return end
  self.hooked = true
  for _, spec in ipairs(LISTS) do
    local ok, err = pcall(function()
      local parent = ah[spec.frame]
      local list = type(parent) == "table" and parent.ItemList
      local box = type(list) == "table" and list.ScrollBox
      if not (box and box.RegisterCallback) then return end
      spec.list = list
      -- new frames: cb(owner, frame, elementData) (ScrollUtil.lua:21-30, ScrollBox.lua:743-745)
      local function OnInit(_, row, elementData) SafeTint(spec, row, elementData) end
      local function OnRelease(_, row) pcall(Hide, row and row.WaylaidCrateTint) end
      if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
        ScrollUtil.AddInitializedFrameCallback(box, OnInit, spec, false)
      else
        box:RegisterCallback("OnInitializedFrame", OnInit, spec)
      end
      if ScrollUtil and ScrollUtil.AddReleasedFrameCallback then
        ScrollUtil.AddReleasedFrameCallback(box, OnRelease, spec)
      else
        box:RegisterCallback("OnReleasedFrame", OnRelease, spec)
      end
    end)
    if not ok and WC.Debug then WC.Debug("AuctionTint hook", err) end
  end
  self:RetintNow()
end

function AHL:TryHook()
  local ok, err = pcall(self.Hook, self)
  if not ok and WC.Debug then WC.Debug("AuctionTint", err) end
end

WC:On("SETTINGS_CHANGED", function() AHL:Refresh() end)
WC:On("DB_READY", function() AHL:Refresh() end)

-- Blizzard_AuctionHouseUI is load-on-demand
do
  local ok = false
  if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    ok = pcall(EventUtil.ContinueOnAddOnLoaded, "Blizzard_AuctionHouseUI", function() AHL:TryHook() end)
  end
  if not ok then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(s, _, name)
      if name == "Blizzard_AuctionHouseUI" then
        s:UnregisterEvent("ADDON_LOADED")
        AHL:TryHook()
      end
    end)
    if _G.AuctionHouseFrame then AHL:TryHook() end
  end
end
