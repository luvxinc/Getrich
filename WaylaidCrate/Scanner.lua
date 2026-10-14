local addonName, WC = ...

-- Scans the Auction House one item at a time with C_AuctionHouse.SendSearchQuery.
-- Blizzard limits search queries to about 100 per minute, so queries are paced.
local Scanner = {
  active = false,
  results = {},   -- [itemID] = { status = "ok"|"short"|"none"|"timeout", min, cost, need, avail, time }
  index = 0,
  total = 0,
}
WC.Scanner = Scanner

local MIN_INTERVAL = 0.7   -- seconds between queries (~85 per minute)
local TIMEOUT      = 4     -- seconds to wait for results before retrying
local MAX_TRIES    = 3     -- searches per item (empty / partial answers are retried)
local CACHE_WAIT   = 3     -- seconds to wait for the item to enter the client cache

local function PriceSorts()
  local priceOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
  return { { sortOrder = priceOrder, reverseSort = false } }
end

function Scanner:BuildQueue()
  local queue, byID = {}, {}
  local function add(itemID, need)
    local q = byID[itemID]
    if q then
      if need > q.need then q.need = need end
    else
      q = { itemID = itemID, need = need }
      byID[itemID] = q
      queue[#queue + 1] = q
    end
  end
  for _, crate in ipairs(WC.CRATES) do
    add(crate.id, 1)
    for _, opt in ipairs(crate.opts) do
      add(opt[1], opt[2])
    end
  end
  return queue
end

function Scanner:Start()
  if self.active then return end
  if not WC.ahOpen then
    WC:Print(WC.L.OPEN_AH_FIRST)
    return
  end
  if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey) then
    WC:Print(WC.L.NO_API)
    return
  end
  self.queue = self:BuildQueue()
  self.total = #self.queue
  self.index = 0
  self.active = true
  self.itemToken = 0
  self.startedAt = GetTime()
  self.results = {}
  WC.UI:OnScanStart(self.total)
  self:Next()
end

function Scanner:Stop(reason)
  if not self.active then return end
  self.active = false
  self.current = nil
  self.itemToken = (self.itemToken or 0) + 1
  if self.timer then self.timer:Cancel(); self.timer = nil end
  WC:SaveResults()
  WC.UI:OnScanStopped(reason, self.index - 1, self.total)
end

function Scanner:Next()
  if not self.active then return end
  if self.timer then self.timer:Cancel(); self.timer = nil end
  self.index = self.index + 1
  if self.index > self.total then
    self:Finish()
    return
  end
  self.itemToken = self.itemToken + 1
  self.current = self.queue[self.index]
  self.current.tries = 0
  self.current.cacheWaitStart = GetTime()
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, self.current.itemID) end
  WC.UI:OnScanProgress(self.index - 1, self.total, self.current.itemID)
  self:TrySend(self.itemToken)
end

function Scanner:TrySend(token)
  if not self.active or token ~= self.itemToken then return end
  local wait = 0
  local since = GetTime() - (self.lastSend or 0)
  if since < MIN_INTERVAL then wait = MIN_INTERVAL - since end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    if wait < 0.25 then wait = 0.25 end
  end
  -- The AH ignores searches for items whose key info isn't cached yet (same workaround as Auctionator).
  local cur = self.current
  cur.key = cur.key or C_AuctionHouse.MakeItemKey(cur.itemID)
  if C_AuctionHouse.GetItemKeyInfo and not C_AuctionHouse.GetItemKeyInfo(cur.key)
     and GetTime() - (cur.cacheWaitStart or 0) < CACHE_WAIT then
    if wait < 0.1 then wait = 0.1 end
  end
  if wait > 0.001 then
    -- never schedule a near-zero wait, so a rounding remainder can't spin
    C_Timer.After(math.max(wait, 0.05), function() self:TrySend(token) end)
    return
  end
  self:Send(token)
end

function Scanner:Send(token)
  local cur = self.current
  cur.tries = cur.tries + 1
  cur.key = cur.key or C_AuctionHouse.MakeItemKey(cur.itemID)
  self.lastSend = GetTime()
  local ok = pcall(C_AuctionHouse.SendSearchQuery, cur.key, PriceSorts(), false)
  if not ok then
    self:Record(cur, nil)
    return
  end
  if self.timer then self.timer:Cancel() end
  self.timer = C_Timer.NewTimer(TIMEOUT, function() self:OnTimeout(token) end)
end

function Scanner:OnTimeout(token)
  if not self.active or token ~= self.itemToken then return end
  self.timer = nil
  local cur = self.current
  if cur.tries < MAX_TRIES then
    self:TrySend(token)
  else
    self:Record(cur, nil)
  end
end

-- A dropped query (throttled by the server) is re-sent right away.
function Scanner:OnMessageDropped()
  if not self.active or not self.current then return end
  local token = self.itemToken
  if self.timer then self.timer:Cancel(); self.timer = nil end
  if self.current.tries < MAX_TRIES + 1 then
    C_Timer.After(0.5, function() self:TrySend(token) end)
  end
end

-- Results that are missing or partial-but-empty are not trusted; search again.
function Scanner:ResultsLoaded(has, full, quantity)
  if has == false then return false end
  if has and full == false and (quantity or 0) == 0 then return false end
  return true
end

function Scanner:RetryOrGiveUp(cur)
  if self.timer then self.timer:Cancel(); self.timer = nil end
  if cur.tries < MAX_TRIES then
    self:TrySend(self.itemToken)
  else
    self:Record(cur, nil)
  end
end

function Scanner:OnCommodityResults(itemID)
  local cur = self.current
  if not self.active or not cur or cur.itemID ~= itemID then return end
  local has = C_AuctionHouse.HasSearchResults and C_AuctionHouse.HasSearchResults(cur.key)
  local full = C_AuctionHouse.HasFullCommoditySearchResults and C_AuctionHouse.HasFullCommoditySearchResults(itemID)
  if not self:ResultsLoaded(has, full, C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID)) then
    self:RetryOrGiveUp(cur)
    return
  end
  local entries = {}
  local n = C_AuctionHouse.GetCommoditySearchResultsQuantity(itemID) or 0
  for i = 1, n do
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if info and info.unitPrice and info.quantity and info.quantity > 0 then
      entries[#entries + 1] = { unit = info.unitPrice, qty = info.quantity }
    end
  end
  self:Record(cur, entries)
end

function Scanner:OnItemResults(itemKey)
  local cur = self.current
  if not self.active or not cur or type(itemKey) ~= "table" or itemKey.itemID ~= cur.itemID then return end
  local has = C_AuctionHouse.HasSearchResults and C_AuctionHouse.HasSearchResults(itemKey)
  local full = C_AuctionHouse.HasFullItemSearchResults and C_AuctionHouse.HasFullItemSearchResults(itemKey)
  if not self:ResultsLoaded(has, full, C_AuctionHouse.GetItemSearchResultsQuantity(itemKey)) then
    self:RetryOrGiveUp(cur)
    return
  end
  local entries = {}
  local n = C_AuctionHouse.GetItemSearchResultsQuantity(itemKey) or 0
  for i = 1, n do
    local info = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    -- skip bid-only auctions and my own listings (can't buy those)
    if info and info.buyoutAmount and info.buyoutAmount > 0 and not info.containsOwnerItem then
      local qty = (info.quantity and info.quantity > 0) and info.quantity or 1
      -- buyoutAmount is per item (Auctionator treats it the same way)
      entries[#entries + 1] = { unit = info.buyoutAmount, qty = qty }
    end
  end
  self:Record(cur, entries)
end

-- Price for the quantity a crate needs, buying the cheapest listings first.
function WC.PriceForQuantity(entries, need)
  table.sort(entries, function(a, b) return a.unit < b.unit end)
  local remain, cost, avail = need, 0, 0
  for _, e in ipairs(entries) do
    avail = avail + e.qty
    if remain > 0 then
      local take = math.min(remain, e.qty)
      cost = cost + take * e.unit
      remain = remain - take
    end
  end
  local res = { need = need, avail = avail }
  if #entries == 0 then
    res.status = "none"
  else
    res.min = entries[1].unit
    if remain > 0 then
      res.status = "short"
    else
      res.status = "ok"
      res.cost = cost
    end
  end
  return res
end

function Scanner:Record(cur, entries)
  if self.timer then self.timer:Cancel(); self.timer = nil end
  local res
  if entries == nil then
    res = { status = "timeout", need = cur.need, avail = 0 }
  else
    res = WC.PriceForQuantity(entries, cur.need)
  end
  res.time = time()
  self.results[cur.itemID] = res
  WC.UI:Refresh()
  self:Next()
end

function Scanner:Finish()
  self.active = false
  self.current = nil
  WC:SaveResults()
  local listed, missing = 0, 0
  for _, r in pairs(self.results) do
    if r.status == "ok" or r.status == "short" then listed = listed + 1 else missing = missing + 1 end
  end
  WC.UI:OnScanDone(self.total, listed, missing, GetTime() - (self.startedAt or GetTime()))
end
