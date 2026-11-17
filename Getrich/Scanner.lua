local addonName, WC = ...

-- Exact searches of single items ("check"). Since 2026.11.2 Getrich does not scan the Auction House: prices come
-- from Auctionator (External.lua). What is left here is the part that asks the Auction House about a handful of
-- items when the player presses a tab's check button, to get what Auctionator cannot give: the order book (how
-- many are listed at which price), without the player's own auctions.
--
-- A "kind" (one per tab) is an ordered list of phases; each phase is a list of items, evaluated only when it is
-- reached, so it can depend on what was found before. A phase marked `again` is run again ("round 2, 3, ...") as
-- long as its list has something that was not searched yet (crates: exact prices change which crates are the
-- best, and those are checked next, until the best ones are all exact). An item is searched once per check.
--   one C_AuctionHouse.SendSearchQuery per item. Blizzard: "restricted to 100 calls per minute", so queries are
--   paced 0.7 s apart and only sent when IsThrottledMessageSystemReady().
-- Every answer is recorded the moment it arrives (prices + history), so a stopped check keeps what it got.
-- The scanner never stops itself because of an event; it only reacts to answers for what it is waiting on.
--
-- API facts are from the Blizzard UI source for this client (github.com/Gethe/wow-ui-source, branch "forever",
-- build 1.60.1.70450, commit 172a387), paths under Interface/AddOns/:
--   AHD = Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua
--   AHE = Blizzard_APIDocumentationGenerated/AuctionHouseEnumsDocumentation.lua
--   AHUI = Blizzard_AuctionHouseUI/

WC.AddLocale({
  enUS = {
    SCAN_OPEN_AH_FIRST = "Open the Auction House first.",
    SCAN_NO_API = "This client has no Auction House search API, so nothing can be checked.",
    SCAN_UNKNOWN_KIND = "There is nothing to check on this tab.",
    SCAN_NOTHING = "Nothing to check here yet.",
    SCAN_KIND_CRATES = "crates",
    SCAN_KIND_WRITS = "writs",
    SCAN_KIND_FLIPS = "vendor flips",
    SCAN_KIND_DE = "disenchanting",
    SCAN_KIND_HISTORY = "watched items",
    SCAN_PH_QUICK = "the best %d",
    SCAN_PH_PLAN = "the plan's items",
    SCAN_PH_FLIP_CHECK = "cheap listings",
    SCAN_PH_DE_MATS = "enchanting materials",
    SCAN_PH_WATCHED = "watched items",
    HIST_NOTHING_WATCHED = "No watched items yet. Mark items with |A:auctionhouse-icon-favorite:12:12|a on the Prices tab first.",
  },
  zhCN = {
    SCAN_OPEN_AH_FIRST = "请先打开拍卖行。",
    SCAN_NO_API = "这个客户端没有拍卖行搜索接口，无法核实价格。",
    SCAN_UNKNOWN_KIND = "这一页没有可核实的内容。",
    SCAN_NOTHING = "这里还没有可核实的条目。",
    SCAN_KIND_CRATES = "箱子",
    SCAN_KIND_WRITS = "Writ",
    SCAN_KIND_FLIPS = "倒卖",
    SCAN_KIND_DE = "附魔分解",
    SCAN_KIND_HISTORY = "关注物品",
    SCAN_PH_QUICK = "排在前面的 %d 项",
    SCAN_PH_PLAN = "方案里要买的物品",
    SCAN_PH_FLIP_CHECK = "低价物品",
    SCAN_PH_DE_MATS = "附魔材料",
    SCAN_PH_WATCHED = "关注物品",
    HIST_NOTHING_WATCHED = "还没有关注的物品。请先在“走势”页用 |A:auctionhouse-icon-favorite:12:12|a 标记物品。",
  },
  zhTW = {
    SCAN_OPEN_AH_FIRST = "請先打開拍賣場。",
    SCAN_NO_API = "這個用戶端沒有拍賣場搜尋介面，無法核實價格。",
    SCAN_UNKNOWN_KIND = "這一頁沒有可核實的內容。",
    SCAN_NOTHING = "這裡還沒有可核實的條目。",
    SCAN_KIND_CRATES = "箱子",
    SCAN_KIND_WRITS = "Writ",
    SCAN_KIND_FLIPS = "倒賣",
    SCAN_KIND_DE = "附魔分解",
    SCAN_KIND_HISTORY = "關注物品",
    SCAN_PH_QUICK = "排在前面的 %d 項",
    SCAN_PH_PLAN = "方案裡要買的物品",
    SCAN_PH_FLIP_CHECK = "低價物品",
    SCAN_PH_DE_MATS = "附魔材料",
    SCAN_PH_WATCHED = "關注物品",
    HIST_NOTHING_WATCHED = "還沒有關注的物品。請先在「走勢」頁用 |A:auctionhouse-icon-favorite:12:12|a 標記物品。",
  },
})
-- |A:auctionhouse-icon-favorite| = the AH favorite star atlas (Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRecipeSchematicForm.xml:45,
-- Blizzard_Professions/Blizzard_ProfessionsCrafterOrderPage.lua:105); the ★ glyph may not exist in the enUS font.
local L = WC.L

-- how many below-vendor-price items the Flips check searches (Settings: 40 / 80 / 150)
if WC.Store and WC.Store.Default then WC.Store:Default("flipCandidates", 80) end

local Scanner = {
  active = false,
  kind = nil,
  -- [itemID] = { status = "listed"|"none"|"timeout", entries = { {unit, qty}, ... } cheapest first, min, avail, time }
  -- (replaced by GetrichDB.results in Store:Init)
  results = {},
  kinds = {},
  index = 0,
  total = 0,
  token = 0,
}
WC.Scanner = Scanner

local MIN_INTERVAL     = 0.7   -- seconds between throttled messages (~85 per minute; limit is 100/min, AHD:1031)
local TIMEOUT          = 4     -- seconds to wait for search results before retrying
local MAX_TRIES        = 3     -- searches per item (empty / partial answers are retried)
local CACHE_WAIT       = 3     -- seconds to wait for the item to enter the client cache
local KEEP_QTY         = 250   -- keep listings until this many items are covered (largest need is 200)
local KEEP_ROWS        = 40
local THROTTLE_POLL    = 0.25  -- re-check IsThrottledMessageSystemReady this often while it says no
local FIRE_INTERVAL    = 0.25  -- PRICES_UPDATED at most 4 times a second
local ITEM_MORE_PAGES  = 4     -- extra result pages per non-commodity item (RequestMoreItemSearchResults)

local ITEM_CLASS = (Enum and Enum.ItemClass) or {}           -- ItemConstantsDocumentation.lua:269 (Weapon 2, Armor 4)
local SORT = (Enum and Enum.AuctionHouseSortOrder) or {}     -- AHE:122-135 (Price 0, Name 1, Bid 3, Buyout 4)

-- Commodity searches sort by price, ascending: what 1.3.0 sent in the real client. Entries are re-sorted locally.
local function SearchSorts()
  return { { sortOrder = SORT.Price or 0, reverseSort = false } }
end

-- Non-commodity searches: Blizzard's sorts for its item search contexts, Buyout then Bid, ascending
-- (AHUI/Shared/Blizzard_AuctionHouseFrame.lua:200-202, used by QueryItem via GetSortTypes, :737-752).
local function ItemSorts()
  return { { sortOrder = SORT.Buyout or 4, reverseSort = false }, { sortOrder = SORT.Bid or 3, reverseSort = false } }
end

-- ---------------------------------------------------------------------------
-- helpers

local function Print(msg)
  if WC.Print then WC:Print(msg) elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(tostring(msg)) end
end

local function Debug(...)
  if WC.Debug then pcall(WC.Debug, ...) end
end

-- call WC.UI:<method>(...) if the UI has it; an error there must not break the scan
local function UICall(method, ...)
  local ui = WC.UI
  if ui and ui[method] then
    local ok, err = pcall(ui[method], ui, ...)
    if not ok then Debug(method, err) end
  end
end

local function Text(x)
  if type(x) == "function" then
    local ok, s = pcall(x)
    return ok and s or nil
  end
  return x
end

local function ItemLabel(itemID)
  if WC.ItemName then
    local ok, name = pcall(WC.ItemName, WC, itemID)
    if ok and name then return name end
  end
  if C_Item and C_Item.GetItemNameByID then
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if ok and name and name ~= "" then return name end
  end
  return "item:" .. tostring(itemID)
end

local function ServerNow()
  if WC.Store and WC.Store.ServerNow then return WC.Store.ServerNow() end
  return time()
end

local function ClassOf(itemID)
  if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
  local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
  if ok then return classID end
end

local function IsWeaponOrArmor(itemID)
  local classID = ClassOf(itemID)
  return classID == (ITEM_CLASS.Weapon or 2) or classID == (ITEM_CLASS.Armor or 4)
end

-- itemIDs from a list ({ id, ... }, order kept) or a set ({ [id] = true }, sorted)
local function IDList(t)
  local out = {}
  if type(t) ~= "table" then return out end
  for _, v in ipairs(t) do if type(v) == "number" then out[#out + 1] = v end end
  if #out == 0 then
    for k, v in pairs(t) do if v == true and type(k) == "number" then out[#out + 1] = k end end
    table.sort(out)
  end
  return out
end

-- ---------------------------------------------------------------------------
-- kinds
--   Scanner:RegisterKind(kind, { label = function() return L.X end, phases = { phaseSpec, ... },
--                                canStart = function() return ok, message end })   -- canStart optional
--   phaseSpec = { items = function() return { itemID, ... } end, label = "..." | function,
--                 again = true: run the phase again while its list has items not searched yet }

function Scanner:RegisterKind(kind, def)
  def = def or {}
  def.phases = def.phases or {}
  self.kinds[kind] = def
end

function Scanner:HasKind(kind)
  return self.kinds[kind] ~= nil
end

function Scanner:KindLabel(kind)
  local def = self.kinds[kind]
  return (def and Text(def.label)) or tostring(kind)
end

-- ---------------------------------------------------------------------------
-- timers: at most one scan timer at a time (pacing wait, throttle poll or answer timeout), cancelled on stop/finish

function Scanner:CancelTimer()
  if self.timer then self.timer:Cancel(); self.timer = nil end
end

function Scanner:Schedule(delay, fn)
  self:CancelTimer()
  local token = self.token
  local handle
  handle = C_Timer.NewTimer(math.max(delay or 0, 0.01), function()
    if self.timer == handle then self.timer = nil end
    if self.active and token == self.token then fn(self) end
  end)
  self.timer = handle
end

-- seconds until the next throttled message may be sent (0 = now)
function Scanner:SendWait()
  local wait = 0
  local since = GetTime() - (self.lastSend or -1000)
  if since < MIN_INTERVAL then wait = MIN_INTERVAL - since end
  if C_AuctionHouse.IsThrottledMessageSystemReady then
    local ok, ready = pcall(C_AuctionHouse.IsThrottledMessageSystemReady)   -- AHD:825
    if ok and not ready then
      self.waitingThrottle = true
      if wait < THROTTLE_POLL then wait = THROTTLE_POLL end
    end
  end
  return wait
end

-- PRICES_UPDATED(kind), at most FIRE_INTERVAL apart; flushed when the scan ends
function Scanner:PricesChanged()
  self.dirty = true
  if self.fireTimer then return end
  local wait = FIRE_INTERVAL - (GetTime() - (self.lastFire or -1000))
  if wait <= 0 then
    self:FlushPrices()
  else
    self.fireTimer = C_Timer.NewTimer(wait, function()
      self.fireTimer = nil
      self:FlushPrices()
    end)
  end
end

function Scanner:FlushPrices()
  if self.fireTimer then self.fireTimer:Cancel(); self.fireTimer = nil end
  if not self.dirty then return end
  self.dirty = false
  self.lastFire = GetTime()
  WC:Fire("PRICES_UPDATED", self.kind)
end

-- ---------------------------------------------------------------------------
-- start / stop / phases

function Scanner:Start(kind)
  if self.active then return false end
  kind = kind or "crates"
  local def = self.kinds[kind]
  if not def then
    Print(L.SCAN_UNKNOWN_KIND)
    return false
  end
  if not WC.ahOpen then
    Print(L.SCAN_OPEN_AH_FIRST)
    return false
  end
  if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey) then
    Print(L.SCAN_NO_API)
    return false
  end
  if def.canStart then
    local ok, can, msg = pcall(def.canStart)
    if ok and not can then
      if msg then Print(msg) end
      return false
    end
  end
  self.kind, self.def = kind, def
  self.active = true
  self.token = self.token + 1
  self.startedAt = GetTime()
  self.listed, self.missing = 0, 0
  self.searched = {}
  self.phases = def.phases
  self.phase, self.phaseCount, self.round = 0, #self.phases, 1
  self.index, self.total = 0, 0
  self.current, self.queue = nil, nil
  local hasWork = self:AdvancePhase()
  UICall("OnScanStart", kind, hasWork and self.total or 0)
  if hasWork then self:BeginPhase() else self:Finish() end
  return true
end

function Scanner:Stop(reason)
  if not self.active then return end
  local done, total = math.max((self.index or 1) - 1, 0), self.total
  self.active = false
  self:CancelTimer()
  self.token = self.token + 1
  if self.listed + self.missing > 0 then WC:DB().scannedAt[self.kind] = time() end
  self.current, self.queue = nil, nil
  self:FlushPrices()
  UICall("OnScanStopped", self.kind, reason, done, total)
end

function Scanner:Finish()
  self.active = false
  self:CancelTimer()
  self.token = self.token + 1
  self.current, self.queue = nil, nil
  if self.listed + self.missing > 0 then WC:DB().scannedAt[self.kind] = time() end
  self:FlushPrices()
  UICall("OnScanDone", self.kind, {
    total = self.listed + self.missing, listed = self.listed, missing = self.missing,
    seconds = GetTime() - (self.startedAt or GetTime()),
  })
end

-- Moves to the next phase that has work. Returns false when no phase is left.
-- A phase marked `again` is first asked again: what it found may have changed what it wants searched. This ends,
-- because an item is searched once per check and a round without anything new moves on.
function Scanner:AdvancePhase()
  local cur = self.phases[self.phase]
  if cur and cur.again and self:PreparePhase(cur) then
    self.round = (self.round or 1) + 1
    return true
  end
  while true do
    self.phase = self.phase + 1
    local spec = self.phases[self.phase]
    if not spec then return false end
    if self:PreparePhase(spec) then
      self.round = 1
      return true
    end
  end
end

function Scanner:PreparePhase(spec)
  self.current, self.queue = nil, nil
  self.index = 0
  local ids = {}
  if spec.items then
    local ok, list = pcall(spec.items)
    if ok then ids = IDList(list) end
  end
  local queue = {}
  for _, itemID in ipairs(ids) do
    if not self.searched[itemID] then          -- each item once per scan
      self.searched[itemID] = true
      queue[#queue + 1] = { itemID = itemID }
    end
  end
  if #queue == 0 then return false end
  -- forget old prices only for the items this phase will search (other tabs keep theirs)
  for _, q in ipairs(queue) do self.results[q.itemID] = nil end
  self.queue, self.total = queue, #queue
  return true
end

function Scanner:BeginPhase()
  local spec = self.phases[self.phase]
  UICall("OnScanPhase", self.kind, self.phase, self.phaseCount, Text(spec.label), spec.again and self.round or nil)
  self:Next()
end

function Scanner:PhaseDone()
  self.current, self.queue = nil, nil
  if self:AdvancePhase() then
    self:BeginPhase()
  else
    self:Finish()
  end
end

-- ---------------------------------------------------------------------------
-- search phase (1.3.0 logic: pacing, throttle check, item-cache wait, retries, timeout, dropped messages)

-- MakeItemKey(itemID, itemLevel=0, itemSuffix=0, battlePetSpeciesID=0) -> ItemKey (AHD:834)
local function MakeKey(itemID, itemLevel, itemSuffix)
  itemLevel, itemSuffix = itemLevel or 0, itemSuffix or 0
  if itemLevel > 0 or itemSuffix > 0 then return C_AuctionHouse.MakeItemKey(itemID, itemLevel, itemSuffix) end
  return C_AuctionHouse.MakeItemKey(itemID)
end

-- Gear is keyed by item level and suffix (ItemKey {itemID, itemLevel, itemSuffix, battlePetSpeciesID}, AHD:1637).
-- 1.3.0 searched MakeItemKey(itemID) (level 0), proven for crates and writs: for gear the other level (the item's
-- own) is tried once when the first key finds nothing. Random-suffix gear ("of the Bear") is listed under its
-- suffix, which nothing here knows: a search that finds nothing proves nothing for it (Profit.lua does not treat
-- such gear as gone).
function Scanner:KeyFor(cur)
  local id = cur.itemID
  cur.altLevel = nil
  if IsWeaponOrArmor(id) then
    local ilvl
    if WC.ItemInfo then
      local _, _, _, lvl = WC.ItemInfo(id)
      ilvl = lvl
    end
    if not ilvl and WC.StaticGear then
      local _, _, lvl = WC.StaticGear(id)
      ilvl = lvl
    end
    if ilvl and ilvl > 0 then cur.altLevel = ilvl end
  end
  return MakeKey(id)
end

function Scanner:Next()
  if not self.active then return end
  self:CancelTimer()
  self.token = self.token + 1
  self.index = self.index + 1
  local cur = self.queue and self.queue[self.index]
  if not cur then
    self:PhaseDone()
    return
  end
  self.current = cur
  cur.tries, cur.state, cur.cacheWaitStart = 0, "pending", GetTime()
  if WC.RequestItem then WC.RequestItem(cur.itemID) end
  cur.key = self:KeyFor(cur)
  UICall("OnScanProgress", self.kind, self.index - 1, self.total, ItemLabel(cur.itemID))
  self:TrySend()
end

function Scanner:TrySend()
  local cur = self.current
  if not self.active or not cur or cur.state ~= "pending" then return end
  local wait = self:SendWait()
  -- The AH ignores searches for items whose key info isn't cached yet (same workaround as Auctionator).
  -- GetItemKeyInfo returns nil until cached (AHD:326); asking also starts the load.
  if C_AuctionHouse.GetItemKeyInfo and GetTime() - cur.cacheWaitStart < CACHE_WAIT then
    local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, cur.key)
    if ok and not info and wait < 0.1 then wait = 0.1 end
  end
  if wait > 0.001 then
    -- never schedule a near-zero wait, so a rounding remainder can't spin
    self:Schedule(math.max(wait, 0.05), self.TrySend)
    return
  end
  self:Send()
end

function Scanner:Send()
  local cur = self.current
  cur.tries = cur.tries + 1
  cur.state = "sent"
  self.lastSend = GetTime()
  self.waitingThrottle = false
  local sorts = SearchSorts()
  if C_AuctionHouse.GetItemKeyInfo then
    local okInfo, info = pcall(C_AuctionHouse.GetItemKeyInfo, cur.key)   -- ItemKeyInfo.isCommodity (AHD:326)
    if okInfo and type(info) == "table" and info.isCommodity == false then sorts = ItemSorts() end
  end
  -- SendSearchQuery(itemKey, sorts, separateOwnerItems) (AHD:1031)
  local ok, err = pcall(C_AuctionHouse.SendSearchQuery, cur.key, sorts, false)
  if not ok then
    Debug("SendSearchQuery", err)
    self:Record(cur, nil)
    return
  end
  self:Schedule(TIMEOUT, self.OnSearchTimeout)
end

function Scanner:OnSearchTimeout()
  local cur = self.current
  if not cur or cur.state ~= "sent" then return end
  if cur.tries < MAX_TRIES then
    cur.state = "pending"
    self:TrySend()
  else
    self:Record(cur, nil)
  end
end

-- AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED (AHD:1286): the server dropped a message; re-send ours.
function Scanner:OnMessageDropped()
  if not self.active then return end
  local cur = self.current
  if cur and cur.state == "moresent" then
    cur.moreDrops = (cur.moreDrops or 0) + 1
    if cur.moreDrops <= 2 then
      cur.state = "more"
      self:Schedule(0.5, self.TrySendMore)
    else
      self:Record(cur, cur.partial, cur.partialUnits)
    end
    return
  end
  if not cur or cur.state ~= "sent" then return end
  if cur.tries < MAX_TRIES + 1 then
    cur.state = "pending"
    self:Schedule(0.5, self.TrySend)
  else
    self:Record(cur, nil)    -- (1.3.0 stalled here)
  end
end

-- AUCTION_HOUSE_THROTTLED_SYSTEM_READY (AHD:1310): send now instead of waiting for the next poll.
function Scanner:OnThrottleReady()
  if not self.active or not self.waitingThrottle then return end
  self.waitingThrottle = false
  local cur = self.current
  if cur and cur.state == "more" then
    self:TrySendMore()
  elseif cur then
    self:TrySend()
  end
end

-- Results that are missing or partial-but-empty are not trusted; search again.
function Scanner:ResultsLoaded(has, full, quantity)
  if has == false then return false end
  if has and full == false and (quantity or 0) == 0 then return false end
  return true
end

function Scanner:RetryOrGiveUp(cur)
  if cur.tries < MAX_TRIES then
    cur.state = "pending"
    self:TrySend()
  else
    self:Record(cur, nil)
  end
end

-- COMMODITY_SEARCH_RESULTS_UPDATED(itemID) (AHD:1415)
function Scanner:OnCommodityResults(itemID)
  local cur = self.current
  if not self.active or not cur or cur.itemID ~= itemID or cur.tries == 0 then return end
  local AH = C_AuctionHouse
  local has = AH.HasSearchResults and AH.HasSearchResults(cur.key)
  local full = AH.HasFullCommoditySearchResults and AH.HasFullCommoditySearchResults(itemID)
  local quantity = AH.GetCommoditySearchResultsQuantity and AH.GetCommoditySearchResultsQuantity(itemID)
  if not self:ResultsLoaded(has, full, quantity) then
    self:RetryOrGiveUp(cur)
    return
  end
  -- Loop over rows: GetNumCommoditySearchResults = rows received (AHD:504);
  -- GetCommoditySearchResultsQuantity = sum of units (AHD:256) (1.3.0 looped over units).
  local entries = {}
  local n = (AH.GetNumCommoditySearchResults and AH.GetNumCommoditySearchResults(itemID)) or 0
  for i = 1, n do
    local info = AH.GetCommoditySearchResultInfo(itemID, i)   -- 1-based (AHD:240)
    -- my own units can't be bought: CommoditySearchResultInfo.numOwnerItems (AHD:1631); Blizzard computes
    -- quantityAvailable = quantity - numOwnerItems (AHUI/Shared/Blizzard_AuctionHouseUtil.lua:217,241)
    local qty = info and info.quantity and (info.quantity - (tonumber(info.numOwnerItems) or 0))
    if info and info.unitPrice and qty and qty > 0 then
      entries[#entries + 1] = { info.unitPrice, qty }
    end
  end
  -- first page only (enough for pricing); if more pages exist, the unit total still tells what is listed
  self:Record(cur, entries, (full == false) and quantity or nil)
end

-- ITEM_SEARCH_RESULTS_UPDATED(itemKey, newAuctionID?) (AHD:1465) / ITEM_SEARCH_RESULTS_ADDED(itemKey) (AHD:1455)
function Scanner:OnItemResults(itemKey)
  local cur = self.current
  if not self.active or not cur or type(itemKey) ~= "table" or itemKey.itemID ~= cur.itemID
     or cur.tries == 0 or cur.state == "done" then return end
  local AH = C_AuctionHouse
  local paging = (cur.state == "more" or cur.state == "moresent")
  local has = AH.HasSearchResults and AH.HasSearchResults(itemKey)
  local full = AH.HasFullItemSearchResults and AH.HasFullItemSearchResults(itemKey)
  local quantity = AH.GetItemSearchResultsQuantity and AH.GetItemSearchResultsQuantity(itemKey)   -- units (AHD:390)
  if not paging and not self:ResultsLoaded(has, full, quantity) then
    self:RetryOrGiveUp(cur)
    return
  end
  local entries, covered = {}, 0
  local n = (AH.GetNumItemSearchResults and AH.GetNumItemSearchResults(itemKey)) or 0   -- rows (AHD:519)
  for i = 1, n do
    local info = AH.GetItemSearchResultInfo(itemKey, i)   -- 1-based (AHD:374)
    -- skip bid-only auctions and my own listings (can't buy those)
    if info and info.buyoutAmount and info.buyoutAmount > 0 and not info.containsOwnerItem then
      local qty = (info.quantity and info.quantity > 0) and info.quantity or 1
      -- buyoutAmount is per item (AHUI/Shared/Blizzard_AuctionHouseItemSellFrame.lua:438-441 multiplies it by quantity)
      entries[#entries + 1] = { info.buyoutAmount, qty }
      covered = covered + qty
    end
  end
  local unitsListed = (full == false) and quantity or nil
  -- more pages, while the kept listings don't cover KEEP_QTY units (Blizzard's ItemBuyFrame pages the same way,
  -- AHUI/Shared/Blizzard_AuctionHouseItemBuyFrame.lua:105; RequestMoreItemSearchResults(itemKey) -> hasFullResults, AHD:970)
  if full == false and covered < KEEP_QTY and (cur.morePages or 0) < ITEM_MORE_PAGES and AH.RequestMoreItemSearchResults then
    cur.morePages = (cur.morePages or 0) + 1
    cur.partial, cur.partialUnits, cur.moreKey = entries, unitsListed, itemKey
    cur.state = "more"
    self:TrySendMore()
    return
  end
  self:Record(cur, entries, unitsListed)
end

function Scanner:TrySendMore()
  local cur = self.current
  if not self.active or not cur or cur.state ~= "more" then return end
  local wait = self:SendWait()
  if wait > 0.001 then
    self:Schedule(math.max(wait, 0.05), self.TrySendMore)
    return
  end
  cur.state = "moresent"
  self.lastSend = GetTime()
  self.waitingThrottle = false
  local ok, hasFull = pcall(C_AuctionHouse.RequestMoreItemSearchResults, cur.moreKey)
  if not ok or hasFull == true then
    self:Record(cur, cur.partial, cur.partialUnits)   -- nothing more will come
    return
  end
  self:Schedule(TIMEOUT, self.OnMoreTimeout)
end

function Scanner:OnMoreTimeout()
  local cur = self.current
  if not cur or cur.state ~= "moresent" then return end
  self:Record(cur, cur.partial, cur.partialUnits)
end

-- Keep the cheapest listings (enough to cover the largest need) for later pricing.
function WC.Summarize(entries)
  table.sort(entries, function(a, b) return a[1] < b[1] end)
  local res = { avail = 0 }
  if #entries == 0 then
    res.status = "none"
    return res
  end
  res.status = "listed"
  res.min = entries[1][1]
  res.entries = {}
  local covered = 0
  for _, e in ipairs(entries) do
    res.avail = res.avail + e[2]
    if covered < KEEP_QTY and #res.entries < KEEP_ROWS then
      res.entries[#res.entries + 1] = { e[1], e[2] }
      covered = covered + e[2]
    end
  end
  return res
end

-- Store one item's answer right away (entries = nil: no answer), then go on.
function Scanner:Record(cur, entries, unitsListed)
  self:CancelTimer()
  cur.state = "done"
  local res
  if entries == nil then
    res = { status = "timeout", avail = 0 }
  else
    res = WC.Summarize(entries)
    if res.status == "none" and cur.altLevel and not cur.altTried then
      -- gear: try the other item-level key once before calling it "not listed"
      cur.altTried = true
      cur.key = MakeKey(cur.itemID, cur.altLevel, 0)
      cur.tries, cur.state, cur.cacheWaitStart = 0, "pending", GetTime()
      self:TrySend()
      return
    end
    if res.status == "listed" and unitsListed and unitsListed > res.avail then res.avail = unitsListed end
  end
  res.time = time()
  -- the key the answer is for (gear)
  local k = cur.key
  if type(k) == "table" then
    if (k.itemLevel or 0) > 0 then res.ilvl = k.itemLevel end
    if (k.itemSuffix or 0) > 0 then res.sfx = k.itemSuffix end
  end
  self.results[cur.itemID] = res
  if res.status == "listed" then
    self.listed = self.listed + 1
    if WC.Store then WC.Store:RecordHistory(cur.itemID, res.min, res.avail, ServerNow()) end
  else
    self.missing = self.missing + 1
  end
  self:PricesChanged()
  self:Next()
end

-- ---------------------------------------------------------------------------
-- events (the scanner's own frame; AH show/close is handled in Core.lua)

local HANDLERS = {
  COMMODITY_SEARCH_RESULTS_UPDATED = Scanner.OnCommodityResults,
  ITEM_SEARCH_RESULTS_UPDATED = Scanner.OnItemResults,
  ITEM_SEARCH_RESULTS_ADDED = Scanner.OnItemResults,
  AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED = Scanner.OnMessageDropped,
  AUCTION_HOUSE_THROTTLED_SYSTEM_READY = Scanner.OnThrottleReady,
}

local frame = CreateFrame("Frame")
for event in pairs(HANDLERS) do pcall(frame.RegisterEvent, frame, event) end
frame:SetScript("OnEvent", function(_, event, ...)
  local handler = HANDLERS[event]
  if not handler then return end
  local ok, err = pcall(handler, Scanner, ...)
  if not ok then Debug(event, err) end
end)

-- ---------------------------------------------------------------------------
-- the kinds owned by the scanner (craft is registered by Profit.lua)

-- What a tab's check button searches: its best entries. Prices come from Auctionator, where only the cheapest
-- price of an item is known, and not whether it is still listed (an item that sold out since the scan keeps its
-- price). An exact search adds how many are listed at which price (a single cheap listing is not a bargain for a
-- bundle of 20), which can change the order. So the best quickTop entries are searched in rounds: after a round
-- the list is ranked again and what is new among the best is searched next, until the best quickTop entries are
-- all exact. With prices from a moment ago that is one round or two; the older Auctionator's scan, the more of
-- its best entries are gone and the more rounds it takes.
local function QuickTop()
  local n = tonumber(WC:DB().quickTop) or 5
  if n < 1 or n > 50 then n = 5 end
  return math.floor(n)
end
Scanner.QuickTop = QuickTop

-- the crate and every bundle material of the best ranked crates that are shown
local function TopCrateItems()
  local list, n, top = {}, 0, QuickTop()
  for _, e in ipairs(WC:VisibleCrates(WC:EvaluateCrates())) do
    if e.perFavor then
      list[#list + 1] = e.crate.id
      for _, o in ipairs(e.crate.opts) do list[#list + 1] = o[1] end
      n = n + 1
      if n >= top then break end
    end
  end
  return list
end

-- The writ and the requested item of the best ranked writs that are shown. In the plan view of the tab
-- (GetrichDB.writView = "plan"): everything today's reputation plan buys (WC:RepPlan in Core.lua).
local function TopWritItems()
  if WC:DB().writView == "plan" and WC.RepPlan then
    local ok, plan = pcall(WC.RepPlan, WC, true)
    return (ok and type(plan) == "table" and plan.items) or {}
  end
  local list, n, top = {}, 0, QuickTop()
  for _, e in ipairs(WC:VisibleWrits(WC:EvaluateWrits())) do
    if e.perRep and not e.receipt then
      list[#list + 1] = e.writ.writ
      list[#list + 1] = e.writ.item
      n = n + 1
      if n >= top then break end
    end
  end
  return list
end

local function QuickLabel()
  return L.SCAN_PH_QUICK:format(QuickTop())
end

local function WritLabel()
  if WC:DB().writView == "plan" then return L.SCAN_PH_PLAN end
  return QuickLabel()
end

-- without Auctionator's prices there is no ranking, so nothing to check: say what is missing
local function NeedPrices(items)
  return function()
    local X = WC.External
    if X and X.Usable and not X:Usable() then return false, X:Describe() end
    if #items() == 0 then return false, L.SCAN_NOTHING end
    return true
  end
end

Scanner:RegisterKind("crates", {
  label = function() return L.SCAN_KIND_CRATES end,
  canStart = NeedPrices(TopCrateItems),
  phases = {
    { label = QuickLabel, items = TopCrateItems, again = true },
  },
})

Scanner:RegisterKind("writs", {
  label = function() return L.SCAN_KIND_WRITS end,
  canStart = NeedPrices(TopWritItems),
  phases = {
    { label = WritLabel, items = TopWritItems, again = true },
  },
})

-- listings cheaper than the vendor pays, biggest first (Profit decides): how many there really are
local function FlipItems()
  local n = tonumber(WC:DB().flipCandidates) or 80   -- setting (40 / 80 / 150)
  if n < 1 or n > 1000 then n = 80 end
  if WC.Profit and WC.Profit.FlipCandidates then return WC.Profit:FlipCandidates(math.floor(n)) or {} end
  return {}
end

Scanner:RegisterKind("flips", {
  label = function() return L.SCAN_KIND_FLIPS end,
  canStart = NeedPrices(FlipItems),
  phases = {
    { label = function() return L.SCAN_PH_FLIP_CHECK end, items = FlipItems },
  },
})

-- what gear disenchants into decides every value on the tab
Scanner:RegisterKind("de", {
  label = function() return L.SCAN_KIND_DE end,
  phases = {
    { label = function() return L.SCAN_PH_DE_MATS end,
      items = function() return (WC.DE and WC.DE.mats) or {} end },
  },
})

Scanner:RegisterKind("history", {
  label = function() return L.SCAN_KIND_HISTORY end,
  canStart = function()
    if WC.Store and #WC.Store:Watched() > 0 then return true end
    return false, L.HIST_NOTHING_WATCHED
  end,
  phases = {
    { label = function() return L.SCAN_PH_WATCHED end,
      items = function() return WC.Store and WC.Store:Watched() or {} end },
  },
})
