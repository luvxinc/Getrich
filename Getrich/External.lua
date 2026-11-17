local addonName, WC = ...

-- External.lua: where Getrich's Auction House prices come from. Since 2026.11.2 that is Auctionator: Getrich does
-- not scan the Auction House itself any more (Scanner.lua only searches a few entries exactly when asked to).
-- Auctionator keeps its prices between sessions, so they are there right after login.
--
-- Only Auctionator's add-on API is used (Auctionator.API.v1, the interface it documents for other add-ons):
--   GetAuctionPriceByItemID(callerID, itemID) -> the last scanned unit price (the cheapest listing), or nil
--   GetAuctionAgeByItemID(callerID, itemID)   -> whole days since it last saw the item, or nil
--   RegisterForDBUpdate(callerID, fn)         -> fn() when its price database has been updated
--   CreateShoppingList / ConvertToSearchString -> a shopping list in Auctionator (X:ShoppingList, at the end)
--
-- What that API does not tell, and what Getrich does about it:
--   * Whether an item is still for sale: the last price of an item that sold out stays. Auctionator's full scan
--     sees everything that is listed, so the day of its last full scan is found first (State: the newest age that
--     many crate and writ items share), and an item counts as for sale only when it was seen that day or later.
--   * How many are listed at the price. price x quantity is a lower bound of the real cost: right for one item,
--     optimistic for a bundle (a single cheap listing looks like a bargain for 20). Every such number is an
--     estimate ("est", shown with ~); the "check" button of a tab searches its best entries exactly.
--   * Whose auction it is: the cheapest listing may be the player's own (Getrich's own searches leave those out).
--   * When a price is from, closer than a day. While an Auction House is open Getrich looks at Auctionator's prices
--     of the crate and writ items every few seconds (and right away when Auctionator reports an update). Many of
--     them, of both kinds, changing together is a full scan, and Getrich notes when and where it saw it:
--       GetrichDB.extScans[marketKey] = { t = time(), ids = { itemID, ... } }   (ids: crate items the scan saw)
--     A scan Getrich has seen is dated to the second. One it has not seen (made before Getrich was installed, or
--     while it was switched off) is only known by its day.
--   * Which Auction House it is from: Auctionator keeps one database per ruleset, for both factions and the neutral
--     houses together. When the scan Getrich saw last was at another house of the ruleset, the prices are not used
--     at this one until Auctionator scans here.
--
-- It can only be asked for one item ID at a time, it cannot list what is for sale. The Flips and Disenchant tabs
-- need such a list, so they walk the built-in item table (DataItems.lua, WC.ItemTable).

local X = { caller = "Getrich", loadedAt = time() }
WC.External = X

WC.AddLocale({
  enUS = {
    EXT_NOAPI = "Getrich takes its Auction House prices from Auctionator. Install and enable Auctionator, then run a full scan in it.",
    EXT_NOSCAN = "Auctionator has no full scan of the Auction House yet. Run a full scan in Auctionator; Getrich uses its prices right away.",
    EXT_OTHER = "Auctionator's last full scan was at another Auction House (%s). Run a full scan in Auctionator here to get this house's prices.",
    EXT_OK = "Prices: Auctionator's full scan, %s. Crate items: %d priced, %d not for sale in that scan.",
    EXT_WATCHED = "Auctionator finished a full scan: Getrich's prices are up to date.",
    EXT_AGO = "%s ago",
    EXT_TODAY = "today",
    EXT_YESTERDAY = "yesterday",
    EXT_DAYS = "%d days ago",
  },
  zhCN = {
    EXT_NOAPI = "Getrich 的拍卖行价格全部来自 Auctionator。请安装并启用 Auctionator，然后在它里面做一次全扫描。",
    EXT_NOSCAN = "Auctionator 还没有全拍卖行扫描的数据。请在 Auctionator 里做一次全扫描，Getrich 会立刻用上。",
    EXT_OTHER = "Auctionator 最近一次全扫描是在另一个拍卖行（%s）。请在这里用 Auctionator 做一次全扫描，才有这个拍卖行的价格。",
    EXT_OK = "价格来源：Auctionator 的全扫描，%s。箱子相关物品：%d 个有价格，%d 个在那次扫描里没有在售。",
    EXT_WATCHED = "Auctionator 完成了一次全扫描：Getrich 的价格已更新。",
    EXT_AGO = "%s前",
    EXT_TODAY = "今天",
    EXT_YESTERDAY = "昨天",
    EXT_DAYS = "%d 天前",
  },
  zhTW = {
    EXT_NOAPI = "Getrich 的拍賣場價格全部來自 Auctionator。請安裝並啟用 Auctionator，然後在它裡面做一次全掃描。",
    EXT_NOSCAN = "Auctionator 還沒有全拍賣場掃描的資料。請在 Auctionator 裡做一次全掃描，Getrich 會立刻用上。",
    EXT_OTHER = "Auctionator 最近一次全掃描是在另一個拍賣場（%s）。請在這裡用 Auctionator 做一次全掃描，才有這個拍賣場的價格。",
    EXT_OK = "價格來源：Auctionator 的全掃描，%s。箱子相關物品：%d 個有價格，%d 個在那次掃描裡沒有在售。",
    EXT_WATCHED = "Auctionator 完成了一次全掃描：Getrich 的價格已更新。",
    EXT_AGO = "%s前",
    EXT_TODAY = "今天",
    EXT_YESTERDAY = "昨天",
    EXT_DAYS = "%d 天前",
  },
})

if WC.Store and WC.Store.Default then
  WC.Store:Default("quickTop", 5)   -- how many of a tab's best entries the "check" button searches exactly
end

local CACHE_SECONDS = 30        -- the state below is rebuilt at most this often (and whenever a look finds a change)
-- A day counts as the day of a full scan when Auctionator saw at least MIN_CRATE crate items and MIN_OTHER writ
-- items on it. A change counts as a full scan being stored when, among the items seen last, at least MIN_CHANGED
-- changed (seen again after a day or more, or at another price), MIN_EACH in each group. A search for one item or
-- a shopping list of crate materials does neither. (A second scan within minutes that finds fewer than
-- MIN_CHANGED of these prices changed is not told apart from no scan: its prices are used all the same, only the
-- time shown stays that of the scan before.)
local MIN_CRATE, MIN_OTHER, MIN_CHANGED, MIN_EACH = 10, 5, 8, 3
local MAX_IDS = 60              -- crate items noted per scan
local POLL = 5                  -- seconds between looks while an Auction House is open
local FLIP_MARGIN = 1.1         -- the built-in vendor price only narrows the list: the client's own can be 5% off

-- (Auctionator's global is read with rawget: it is another addon's and may not exist)
local function V1()
  local A = rawget(_G, "Auctionator")
  local v1 = type(A) == "table" and type(A.API) == "table" and A.API.v1 or nil
  if type(v1) == "table" and type(v1.GetAuctionPriceByItemID) == "function"
     and type(v1.GetAuctionAgeByItemID) == "function" then
    return v1
  end
  return nil
end

local function Price(v1, itemID)
  local ok, p = pcall(v1.GetAuctionPriceByItemID, X.caller, itemID)
  if ok and type(p) == "number" and p > 0 then return p end
  return nil
end

local function Age(v1, itemID)
  local ok, a = pcall(v1.GetAuctionAgeByItemID, X.caller, itemID)
  if ok and type(a) == "number" and a >= 0 then return a end
  return nil
end

-- the items a full scan is recognised by: { ids = { itemID, ... }, crate = { [itemID] = true } }
-- (crates and their materials first, then the writs and the items they ask for)
local function Sample()
  if X.sample then return X.sample end
  local s = { ids = {}, crate = {} }
  local seen = {}
  local function add(id, crate)
    if type(id) == "number" and not seen[id] then
      seen[id] = true
      s.ids[#s.ids + 1] = id
      if crate then s.crate[id] = true end
    end
  end
  for _, c in ipairs(WC.CRATES or {}) do
    add(c.id, true)
    for _, o in ipairs(c.opts or {}) do add(o[1], true) end
  end
  for _, w in ipairs(WC.WRITS or {}) do
    add(w.writ, false)
    add(w.item, false)
  end
  X.sample = s
  return s
end

-- what Auctionator says about the sample right now: { age = { [itemID] = days }, price = { [itemID] = copper } }
local function Read(v1)
  local snap = { age = {}, price = {} }
  for _, id in ipairs(Sample().ids) do
    snap.age[id] = Age(v1, id)
    snap.price[id] = Price(v1, id)
  end
  return snap
end

-- the newest age that at least MIN_CRATE crate items and MIN_OTHER writ items of a Read share, or nil
local function ScanDay(snap)
  local sample = Sample()
  local crate, other = {}, {}
  for _, id in ipairs(sample.ids) do
    local a = snap.age[id]
    if a and snap.price[id] then
      local t = sample.crate[id] and crate or other
      t[a] = (t[a] or 0) + 1
    end
  end
  local best
  for a, n in pairs(crate) do
    if n >= MIN_CRATE and (other[a] or 0) >= MIN_OTHER and (not best or a < best) then best = a end
  end
  return best
end

-- the ruleset part of a market key ("Forever PvP|Horde" -> "Forever PvP")
local function Ruleset(key)
  return type(key) == "string" and key:match("^(.*)|") or nil
end

-- { at, rows = {}, why = nil (prices in use) | "noapi" | "noscan" | "other",
--   h = age in days of Auctionator's last full scan, t = when that scan was (exact = Getrich saw it, to the second;
--   otherwise the earliest it can have been), v1, other = the other house's key }
function X:State()
  local s = self.state
  local now = GetTime()
  if s and now - s.at < CACHE_SECONDS then return s end
  s = { at = now, rows = {} }
  self.state = s
  local v1 = V1()
  if not v1 then s.why = "noapi"; return s end
  local h = ScanDay(Read(v1))
  if not h then s.why = "noscan"; return s end
  -- Auctionator files a price under the day its session was loaded, and counts the age in whole days: a scan
  -- that is h days old was made after this, at the earliest
  local earliest = (X.loadedAt or time()) - (h + 1) * 86400
  -- the scan Getrich saw that is exactly that old (the newest, among the houses of this ruleset). A record from
  -- before `earliest` is not this scan: Auctionator has scanned again since, without Getrich seeing it.
  local db = WC:DB()
  local key = db.market
  local ruleset = Ruleset(key)
  local best, bestKey
  for k, rec in pairs(type(db.extScans) == "table" and db.extScans or {}) do
    if type(rec) == "table" and type(rec.t) == "number" and rec.t >= earliest and type(rec.ids) == "table"
       and Ruleset(k) == ruleset then
      local recH
      for _, id in ipairs(rec.ids) do
        local a = Age(v1, id)
        if a and (not recH or a > recH) then recH = a end
      end
      if recH == h and (not best or rec.t > best.t) then best, bestKey = rec, k end
    end
  end
  if best and bestKey ~= key then
    s.why, s.other = "other", bestKey
    return s
  end
  if best then
    s.t, s.exact = best.t, true
  else
    s.t, s.exact = earliest, false
  end
  s.h, s.v1 = h, v1
  return s
end

-- Are Auctionator's prices in use right now?
function X:Usable()
  return self:State().h ~= nil
end

-- seconds since the scan in use, when Getrich saw it (nil otherwise: see AgeText)
function X:AgeSeconds()
  local s = self:State()
  if not (s.h and s.exact) then return nil end
  return math.max(0, time() - s.t)
end

-- how old the prices are, as text: "25 min ago" for a scan Getrich saw, else "today" / "yesterday" / "3 days ago"
function X:AgeText()
  local L = WC.L
  local s = self:State()
  if not s.h then return nil end
  if s.exact and WC.UI and WC.UI.Age then return L.EXT_AGO:format(WC.UI.Age(math.max(0, time() - s.t))) end
  if s.h == 0 then return L.EXT_TODAY end
  if s.h == 1 then return L.EXT_YESTERDAY end
  return L.EXT_DAYS:format(s.h)
end

-- One item for Store.lua: { min = unit price, t, ext = "auctionator", ilvl = item level of gear }, or
-- { none = true, t, ext } when the last full scan did not see it, or nil when Auctionator's prices are not in use.
function X:Row(itemID)
  local s = self:State()
  if not s.h or type(itemID) ~= "number" then return nil end
  local row = s.rows[itemID]
  if row == nil then
    local a = Age(s.v1, itemID)
    local p = (a and a <= s.h) and Price(s.v1, itemID) or nil
    if p then
      local _, _, ilvl = WC.StaticGear(itemID)
      row = { min = p, t = s.t, ext = "auctionator", ilvl = ilvl }
    else
      row = { none = true, t = s.t, ext = "auctionator" }
    end
    s.rows[itemID] = row
  end
  return row
end

-- The two lists Auctionator cannot give, from the built-in item table (one pass, kept as long as the state):
--   flips = { [itemID] = row }  for sale below (about) the vendor price
--   gear  = { [itemID] = row }  disenchantable weapons and armor that are for sale
-- Returns flips, gear, t (when the prices are from); nil when Auctionator's prices are not in use.
function X:Lists()
  local s = self:State()
  if not s.h then return nil end
  if not s.flips then
    local flips, gear = {}, {}
    local ids, sell, isGear = WC.ItemTable()
    local v1 = s.v1
    for i = 1, #ids do
      local id = ids[i]
      local p = Price(v1, id)
      if p then
        local vendor = sell[id]
        local cheap = vendor and vendor > 0 and p < vendor * FLIP_MARGIN
        if cheap or isGear[id] then
          local row = self:Row(id)
          if row.min then
            if cheap then flips[id] = row end
            if isGear[id] then gear[id] = row end
          end
        end
      end
    end
    s.flips, s.gear = flips, gear
  end
  return s.flips, s.gear, s.t
end

function X:Invalidate()
  self.state = nil
end

-- one line for the chat: where the prices are from, or why there are none (/gr auc)
function X:Describe()
  local L = WC.L
  self:Invalidate()
  local s = self:State()
  if s.why == "noapi" then return L.EXT_NOAPI end
  if s.why == "noscan" then return L.EXT_NOSCAN end
  if s.why == "other" then return L.EXT_OTHER:format(tostring(s.other)) end
  local priced, none = 0, 0
  local sample = Sample()
  for _, id in ipairs(sample.ids) do
    if sample.crate[id] then
      if self:Row(id).min then priced = priced + 1 else none = none + 1 end
    end
  end
  return L.EXT_OK:format(self:AgeText() or "?", priced, none)
end

-- a full scan was just stored: one price-history record per item Getrich follows (Store:RecordHistory keeps the
-- relevant ones; the quantity listed is not known)
local function RecordHistory()
  local Store = WC.Store
  if not (Store and Store.RelevantSet and Store.RecordHistory) then return end
  for itemID in pairs(Store:RelevantSet()) do
    local row = X:Row(itemID)
    if row and row.min then Store:RecordHistory(itemID, row.min, nil) end
  end
end

-- Look at what Auctionator knows now. X.base = the last look, X.before = the last look that found nothing new:
-- changes are counted from X.before, so a scan that Auctionator stores over several looks is seen whole, and
-- X.noted keeps it from being announced twice. final = the Auction House has just closed (X.market = the house).
local function Look(final)
  -- the age shown in the window ("25 min ago") moves on: say so once a minute
  local minute = math.floor(time() / 60)
  if X.minute ~= minute then
    if X.minute then WC:Fire("EXTERNAL_AGE") end
    X.minute = minute
  end
  local v1 = V1()
  if not v1 then return end
  local snap = Read(v1)
  local last = X.base
  X.base = snap
  local sample = Sample()
  local quiet = true
  if last then
    for _, id in ipairs(sample.ids) do
      if last.age[id] ~= snap.age[id] or last.price[id] ~= snap.price[id] then quiet = false; break end
    end
  end
  local db = WC:DB()
  local market = WC.ahOpen and db.market or (final and X.market) or nil
  if WC.ahOpen then X.market = db.market end
  if quiet or not X.before then
    X.before, X.noted = snap, false
    return
  end
  -- something changed: new prices of single items, or a scan
  X:Invalidate()
  local base = X.before
  local newest = ScanDay(snap)
  local changedCrate, changedOther = 0, 0
  local ids = {}
  if newest then
    for _, id in ipairs(sample.ids) do
      if snap.age[id] == newest and snap.price[id] then
        -- seen again (its age went down, or it is new) or at another price. An age that only went up is the day
        -- counter moving on at midnight, not a scan.
        local was = base.age[id]
        local changed = (was == nil or snap.age[id] < was or base.price[id] ~= snap.price[id])
        if sample.crate[id] then
          if changed then changedCrate = changedCrate + 1 end
          if #ids < MAX_IDS then ids[#ids + 1] = id end
        elseif changed then
          changedOther = changedOther + 1
        end
      end
    end
  end
  local first = false
  if type(market) == "string" and type(db.extScans) == "table"
     and changedCrate >= MIN_EACH and changedOther >= MIN_EACH and changedCrate + changedOther >= MIN_CHANGED then
    db.extScans[market] = { t = time(), ids = ids }
    if not X.noted then
      X.noted, first = true, true
      WC:Print(WC.L.EXT_WATCHED)
    end
    RecordHistory()
  end
  WC:Fire("PRICES_UPDATED", "external")
  if first then WC:Fire("EXTERNAL_SCAN") end
end

-- Auctionator's shopping lists, through its add-on API as well:
--   CreateShoppingList(callerID, listName, searchStrings)                  a named list of search terms the player
--                                                                          runs on Auctionator's Shopping tab
--   ConvertToSearchString(callerID, { searchString, isExact, quantity })   the term for one exact item name
-- items = { { itemID, qty }, ... }. Returns true, the list's name, the number of entries; or false and why:
--   "noapi" (no Auctionator, or one without shopping lists), "empty", "error",
--   "names" + how many item names the client has not loaded yet (they are asked for; try again in a moment).
function X:ShoppingList(listName, items)
  local A = rawget(_G, "Auctionator")
  local v1 = type(A) == "table" and type(A.API) == "table" and A.API.v1 or nil
  if type(v1) ~= "table" or type(v1.CreateShoppingList) ~= "function" then return false, "noapi" end
  if type(items) ~= "table" or #items == 0 then return false, "empty" end
  local terms, missing = {}, 0
  for _, it in ipairs(items) do
    local itemID, qty = it[1], tonumber(it[2]) or 1
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or nil
    if type(name) ~= "string" or name == "" then
      missing = missing + 1
      WC.RequestItem(itemID)
    else
      local term = name
      if type(v1.ConvertToSearchString) == "function" then
        local ok, str = pcall(v1.ConvertToSearchString, X.caller, { searchString = name, isExact = true, quantity = qty })
        if ok and type(str) == "string" and str ~= "" then term = str end
      end
      terms[#terms + 1] = term
    end
  end
  if missing > 0 then return false, "names", missing end
  local ok = pcall(v1.CreateShoppingList, X.caller, listName, terms)
  if not ok then return false, "error" end
  return true, listName, #terms
end

local function SafeLook(final)
  local ok, err = pcall(Look, final)
  if not ok and WC.Debug then pcall(WC.Debug, "External", err) end
end

-- Auctionator said its database changed: look in a moment, once, however often it says so (how often it calls
-- back while it stores a scan is its business; a look reads a few hundred prices).
local lookPending = false
local function LookSoon()
  if lookPending then return end
  if not (C_Timer and C_Timer.After) then SafeLook(); return end
  lookPending = true
  C_Timer.After(0.2, function()
    lookPending = false
    SafeLook()
  end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    -- Auctionator says when its database was updated: look then instead of at the next tick
    local A = rawget(_G, "Auctionator")
    local v1 = type(A) == "table" and type(A.API) == "table" and A.API.v1 or nil
    if type(v1) == "table" and type(v1.RegisterForDBUpdate) == "function" then
      pcall(v1.RegisterForDBUpdate, X.caller, LookSoon)
    end
  elseif event == "AUCTION_HOUSE_SHOW" then
    if X.ticker then X.ticker:Cancel(); X.ticker = nil end
    -- once per session: say why there are no prices (no Auctionator, no full scan yet, a scan of another house)
    if not X.hinted and C_Timer and C_Timer.After then
      C_Timer.After(1.5, function()
        if X.hinted or not WC.ahOpen then return end
        X:Invalidate()
        if X:State().why then
          X.hinted = true
          WC:Print(X:Describe())
        end
      end)
    end
    local v1 = V1()
    if not v1 then return end
    -- what Auctionator knows before anything is scanned in this visit: changes are measured against it
    local ok, snap = pcall(Read, v1)
    X.base = ok and snap or nil
    X.before, X.noted, X.market = X.base, false, nil
    if C_Timer and C_Timer.NewTicker then
      X.ticker = C_Timer.NewTicker(POLL, function() SafeLook() end)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if X.ticker then
      X.ticker:Cancel()
      X.ticker = nil
      SafeLook(true)          -- a scan that finished in the last seconds of the visit
    end
    X.market = nil
  end
end)

-- the Auction House in use decides whether the prices may be used
WC:On("DB_READY", function() X:Invalidate() end)
