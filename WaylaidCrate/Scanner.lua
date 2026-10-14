local addonName, WC = ...

-- Scans the Auction House one item at a time with C_AuctionHouse.SendSearchQuery.
-- Blizzard limits search queries to about 100 per minute, so queries are paced.
--
-- Two scan kinds:
--   "crates" - the 22 crates and their 69 materials
--   "writs"  - phase 1: the 150 Craftsman's Writ items
--              phase 2: the requested items (only for writs that are for sale, unless the
--                       "ignore writs not for sale" filter is off)
local Scanner = {
  active = false,
  kind = nil,
  -- [itemID] = { status = "listed"|"none"|"timeout", entries = { {unit, qty}, ... } cheapest first, min, avail, time }
  results = {},
  index = 0,
  total = 0,
}
WC.Scanner = Scanner

local MIN_INTERVAL = 0.7   -- seconds between queries (~85 per minute)
local TIMEOUT      = 4     -- seconds to wait for results before retrying
local MAX_TRIES    = 3     -- searches per item (empty / partial answers are retried)
local CACHE_WAIT   = 3     -- seconds to wait for the item to enter the client cache
local KEEP_QTY     = 250   -- keep listings until this many items are covered (largest need is 200)
local KEEP_ROWS    = 40

local function PriceSorts()
  local priceOrder = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
  return { { sortOrder = priceOrder, reverseSort = false } }
end

-- ---------------------------------------------------------------------------
-- prices

-- Cost of buying `qty` of an item from the scanned listings, cheapest first.
-- Returns cost (nil if unscanned / not listed / not enough), status, result.
-- status: "ok" | "short" | "none" | "timeout" | nil (not scanned)
function WC:CostFor(itemID, qty)
  local res = Scanner.results[itemID]
  if not res then return nil, nil, nil end
  if res.status ~= "listed" then return nil, res.status, res end
  local remain, cost = qty, 0
  for _, e in ipairs(res.entries or {}) do
    local take = math.min(remain, e[2])
    cost = cost + take * e[1]
    remain = remain - take
    if remain <= 0 then return cost, "ok", res end
  end
  return nil, "short", res
end

-- ---------------------------------------------------------------------------
-- item sets per scan kind

local function Adder(queue, byID)
  return function(itemID)
    if not byID[itemID] then
      byID[itemID] = true
      queue[#queue + 1] = { itemID = itemID }
    end
  end
end

function WC:CrateItemSet()
  local set = {}
  for _, c in ipairs(WC.CRATES) do
    set[c.id] = true
    for _, o in ipairs(c.opts) do set[o[1]] = true end
  end
  return set
end

function WC:WritItemSet()
  local set = {}
  for _, w in ipairs(WC.WRITS) do set[w.writ] = true; set[w.item] = true end
  return set
end

function Scanner:BuildQueue(kind)
  local queue, byID = {}, {}
  local add = Adder(queue, byID)
  if kind == "writs" then
    for _, w in ipairs(WC.WRITS) do add(w.writ) end
  else
    for _, c in ipairs(WC.CRATES) do
      add(c.id)
      for _, o in ipairs(c.opts) do add(o[1]) end
    end
  end
  return queue, byID
end

-- Phase 2 of a writ scan: the requested items.
function Scanner:WritPhase2()
  local db = WC:DB()
  local add = Adder(self.queue, self.queued)
  for _, w in ipairs(WC.WRITS) do
    local _, status = WC:CostFor(w.writ, 1)
    if not db.hideNoWrit or status == "ok" then add(w.item) end
  end
end

-- ---------------------------------------------------------------------------
-- scan loop

function Scanner:Start(kind)
  if self.active then return end
  kind = (kind == "writs") and "writs" or "crates"
  if not WC.ahOpen then
    WC:Print(WC.L.OPEN_AH_FIRST)
    return
  end
  if not (C_AuctionHouse and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey) then
    WC:Print(WC.L.NO_API)
    return
  end
  self.kind = kind
  self.phase = 1
  self.queue, self.queued = self:BuildQueue(kind)
  -- forget old prices for everything this scan covers (items shared with the other tab stay
  -- until they are scanned again, so the other tab keeps its numbers)
  local mine = (kind == "writs") and WC:WritItemSet() or WC:CrateItemSet()
  local other = (kind == "writs") and WC:CrateItemSet() or WC:WritItemSet()
  for itemID in pairs(mine) do
    if not other[itemID] then self.results[itemID] = nil end
  end
  self.total = #self.queue
  self.index = 0
  self.active = true
  self.itemToken = 0
  self.startedAt = GetTime()
  self.listed, self.missing = 0, 0
  WC.UI:OnScanStart(kind, self.total)
  self:Next()
end

function Scanner:Stop(reason)
  if not self.active then return end
  self.active = false
  self.current = nil
  self.itemToken = (self.itemToken or 0) + 1
  if self.timer then self.timer:Cancel(); self.timer = nil end
  WC:SaveResults()
  WC.UI:OnScanStopped(self.kind, reason, self.index - 1, self.total)
end

function Scanner:Next()
  if not self.active then return end
  if self.timer then self.timer:Cancel(); self.timer = nil end
  self.index = self.index + 1
  if self.index > #self.queue and self.kind == "writs" and self.phase == 1 then
    self.phase = 2
    self:WritPhase2()
    self.total = #self.queue
  end
  if self.index > #self.queue then
    self:Finish()
    return
  end
  self.itemToken = self.itemToken + 1
  self.current = self.queue[self.index]
  self.current.tries = 0
  self.current.cacheWaitStart = GetTime()
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, self.current.itemID) end
  WC.UI:OnScanProgress(self.kind, self.index - 1, self.total, self.current.itemID, self.phase)
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
      entries[#entries + 1] = { info.unitPrice, info.quantity }
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
      entries[#entries + 1] = { info.buyoutAmount, qty }
    end
  end
  self:Record(cur, entries)
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

function Scanner:Record(cur, entries)
  if self.timer then self.timer:Cancel(); self.timer = nil end
  local res
  if entries == nil then
    res = { status = "timeout", avail = 0 }
  else
    res = WC.Summarize(entries)
  end
  res.time = time()
  self.results[cur.itemID] = res
  if res.status == "listed" then self.listed = self.listed + 1 else self.missing = self.missing + 1 end
  WC.UI:Refresh()
  self:Next()
end

function Scanner:Finish()
  self.active = false
  self.current = nil
  WC:SaveResults()
  WC.UI:OnScanDone(self.kind, self.total, self.listed, self.missing, GetTime() - (self.startedAt or GetTime()))
end
