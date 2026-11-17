local addonName, WC = ...

-- External.lua: prices another addon has already collected. Getrich uses them as estimates until it has searched
-- an item itself. Today that is Auctionator, and only through its add-on API (Auctionator.API.v1, the interface it
-- documents for other add-ons); nothing else of Auctionator is read:
--   GetAuctionPriceByItemID(callerID, itemID) -> the last scanned unit price (the cheapest listing), or nil
--   GetAuctionAgeByItemID(callerID, itemID)   -> whole days since it last saw the item, or nil
--   RegisterForDBUpdate(callerID, fn)         -> fn() when its price database has been updated
--
-- What that API does not tell:
--   * when a price is from, closer than a day;
--   * which Auction House it is from: Auctionator keeps one database per ruleset, for both factions and the
--     neutral houses together;
--   * whether the item is still for sale: the last price of an item that sold out stays;
--   * how many are listed at the price. price x quantity is a lower bound of the real cost: right for one item,
--     optimistic for a bundle;
--   * whose auction it is: the cheapest listing may be the player's own (Getrich's searches leave those out).
--
-- So Getrich only uses a scan it has watched. While an Auction House is open it looks at Auctionator's prices of
-- the crate and writ items every few seconds (and right away when Auctionator reports a database update). When
-- many of them, of both kinds, change together, that is a whole-AH scan and not a search or a shopping list, and
-- Getrich notes the time, the Auction House (GetrichDB.market) and which crate items the scan saw:
--   GetrichDB.extScans[marketKey] = { t = time(), ids = { itemID, ... } }
-- From then on, for 12 hours and while no newer scan was watched at another house of the same ruleset:
--   * an item Auctionator has seen in that scan or later has its price, dated to the scan (an estimate, "est");
--   * any other item was not for sale in that scan ("none").
-- "In that scan or later" is decided by the age in days: an item counts when it is not older than the oldest of
-- the items noted for the scan (their age grows by one each day, together with everything else from that scan).
-- Only the crate and writ tabs use these prices (WC:CostBest in Store.lua); the other tabs are priced as before.
--
-- Why 12 hours: checked against real data of 2026-11-15 (one Auction House, an Auctionator scan and a full Getrich
-- crate scan some hours apart): single prices had moved by a quarter in either direction, yet the five best crates
-- by exact prices were at ranks 1, 5, 2, 3 and 6 by Auctionator's prices. Good enough to choose what to search, for
-- some hours; nothing is known about a day.

local X = { caller = "Getrich" }
WC.External = X

WC.AddLocale({
  enUS = {
    EXT_NOAPI = "Auctionator: not loaded, so its prices are not used.",
    EXT_OFF = "Auctionator: its prices are switched off in the Getrich settings.",
    EXT_NOSCAN = "Auctionator: Getrich has not seen it finish a full scan of this Auction House yet. Run one full scan in Auctionator; its prices are used from then on.",
    EXT_OLD = "Auctionator: its last full scan of this Auction House finished %s ago. That is too old (limit: 12 hours); scan again in Auctionator.",
    EXT_OTHER = "Auctionator: its newest full scan was at another Auction House (%s). Its prices are not used here until it scans this one.",
    EXT_GONE = "Auctionator: the prices of its last full scan are no longer in its database.",
    EXT_OK = "Auctionator: full scan %s ago in use. Crate items: %d priced, %d not for sale in that scan. Quick scans: %s.",
    EXT_ON = "on",
    EXT_OFF_WORD = "off",
    EXT_WATCHED = "Auctionator finished a full scan: its prices now fill the Crates and Writs tabs (marked ~), and a scan there only checks the best entries.",
  },
  zhCN = {
    EXT_NOAPI = "Auctionator：没有加载，不使用它的价格。",
    EXT_OFF = "Auctionator：已在 Getrich 设置里关闭使用它的价格。",
    EXT_NOSCAN = "Auctionator：Getrich 还没有看到它在这个拍卖行完成过全拍卖行扫描。请在 Auctionator 里做一次全扫描，之后就会用上它的价格。",
    EXT_OLD = "Auctionator：它上一次在这个拍卖行的全扫描完成于%s前，太旧了（上限 12 小时）。请在 Auctionator 里重新扫描。",
    EXT_OTHER = "Auctionator：它最近一次全扫描是在另一个拍卖行（%s）。在它扫描这个拍卖行之前，这里不使用它的价格。",
    EXT_GONE = "Auctionator：它上一次全扫描的价格已经不在它的数据库里。",
    EXT_OK = "Auctionator：正在使用%s前的全扫描。箱子相关物品：%d 个有价格，%d 个在那次扫描里没有在售。快速扫描：%s。",
    EXT_ON = "开",
    EXT_OFF_WORD = "关",
    EXT_WATCHED = "Auctionator 完成了一次全扫描：箱子页和 Writ 页已用它的价格估算（带 ~），在这两页点扫描只需核实排在前面的几项。",
  },
  zhTW = {
    EXT_NOAPI = "Auctionator：沒有載入，不使用它的價格。",
    EXT_OFF = "Auctionator：已在 Getrich 設定裡關閉使用它的價格。",
    EXT_NOSCAN = "Auctionator：Getrich 還沒有看到它在這個拍賣場完成過全拍賣場掃描。請在 Auctionator 裡做一次全掃描，之後就會用上它的價格。",
    EXT_OLD = "Auctionator：它上一次在這個拍賣場的全掃描完成於%s前，太舊了（上限 12 小時）。請在 Auctionator 裡重新掃描。",
    EXT_OTHER = "Auctionator：它最近一次全掃描是在另一個拍賣場（%s）。在它掃描這個拍賣場之前，這裡不使用它的價格。",
    EXT_GONE = "Auctionator：它上一次全掃描的價格已經不在它的資料庫裡。",
    EXT_OK = "Auctionator：正在使用%s前的全掃描。箱子相關物品：%d 個有價格，%d 個在那次掃描裡沒有在售。快速掃描：%s。",
    EXT_ON = "開",
    EXT_OFF_WORD = "關",
    EXT_WATCHED = "Auctionator 完成了一次全掃描：箱子頁和 Writ 頁已用它的價格估算（帶 ~），在這兩頁點掃描只需核實排在前面的幾項。",
  },
})

if WC.Store and WC.Store.Default then
  WC.Store:Default("useAuctionator", true)   -- use Auctionator's prices as estimates
  WC.Store:Default("quickScan", true)        -- with such estimates, a crate / writ scan only searches the top entries
  WC.Store:Default("quickTop", 5)            -- how many of the best entries a quick scan makes exact
end

local MAX_SECONDS = 12 * 3600   -- a watched scan is used this long
local CACHE_SECONDS = 30        -- the state below is rebuilt at most this often (and after each watched scan)
-- A change of Auctionator's database counts as a whole-AH scan when, among the items it saw last (smallest age),
-- there are at least MIN_CRATE crate items and MIN_OTHER writ items, and at least MIN_CHANGED of them changed, at
-- least MIN_EACH in each group. A search for one item, a shopping list of crate materials, or prices Auctionator may
-- pick up from Getrich's own searches (one tab, so one group) do not do that.
local MIN_CRATE, MIN_OTHER, MIN_CHANGED, MIN_EACH = 10, 5, 8, 3
local MAX_IDS = 60              -- crate items noted per scan
local POLL = 5                  -- seconds between looks while an Auction House is open

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

-- the items a whole-AH scan is recognised by: { ids = { itemID, ... }, crate = { [itemID] = true } }
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

-- Look at what Auctionator knows now. X.base = the last look, X.before = the last look that found nothing new:
-- changes are counted from X.before, so a scan that Auctionator stores over several looks is seen whole, and
-- X.noted keeps it from being announced twice. final = the Auction House has just closed (X.market = the house).
local function Look(final)
  local db = WC:DB()
  if db.useAuctionator == false then return end
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
  local market = WC.ahOpen and db.market or (final and X.market) or nil
  if WC.ahOpen then X.market = db.market end
  if quiet or not X.before then
    X.before, X.noted = snap, false
    return
  end
  -- something changed: new prices of single items, or a scan
  X:Invalidate()
  local base = X.before
  local newest
  for _, a in pairs(snap.age) do
    if not newest or a < newest then newest = a end
  end
  local crate, other, changedCrate, changedOther = 0, 0, 0, 0
  local ids = {}
  for _, id in ipairs(sample.ids) do
    if snap.age[id] == newest and snap.price[id] then
      local changed = (base.age[id] ~= newest or base.price[id] ~= snap.price[id])
      if sample.crate[id] then
        crate = crate + 1
        if changed then changedCrate = changedCrate + 1 end
        if #ids < MAX_IDS then ids[#ids + 1] = id end
      else
        other = other + 1
        if changed then changedOther = changedOther + 1 end
      end
    end
  end
  local first = false
  if type(market) == "string" and type(db.extScans) == "table"
     and crate >= MIN_CRATE and other >= MIN_OTHER and changedCrate >= MIN_EACH and changedOther >= MIN_EACH
     and changedCrate + changedOther >= MIN_CHANGED then
    db.extScans[market] = { t = time(), ids = ids }
    if not X.noted then
      X.noted, first = true, true
      WC:Print(WC.L.EXT_WATCHED)
    end
  end
  WC:Fire("PRICES_UPDATED", "external")
  if first then WC:Fire("EXTERNAL_SCAN") end     -- Scanner.lua: a running full crate / writ scan goes on as a quick one
end

local function SafeLook(final)
  local ok, err = pcall(Look, final)
  if not ok and WC.Debug then pcall(WC.Debug, "External", err) end
end

-- { at, rows = {}, why = nil (in use) | "off" | "noapi" | "noscan" | "old" | "other" | "gone",
--   t = when the scan in use finished, h = age in days of what that scan saw, v1, other = the other house's key }
function X:State()
  local s = self.state
  local now = GetTime()
  if s and now - s.at < CACHE_SECONDS then return s end
  s = { at = now, rows = {} }
  self.state = s
  local db = WC:DB()
  if db.useAuctionator == false then s.why = "off"; return s end
  local v1 = V1()
  if not v1 then s.why = "noapi"; return s end
  local key = db.market
  local scans = db.extScans
  local rec = (type(key) == "string" and type(scans) == "table") and scans[key] or nil
  if type(rec) ~= "table" or type(rec.t) ~= "number" or type(rec.ids) ~= "table" then s.why = "noscan"; return s end
  s.t = rec.t
  if time() - rec.t > MAX_SECONDS then s.why = "old"; return s end
  -- one Auctionator database for all houses of a ruleset: a newer scan at another of them replaced these prices
  local ruleset = key:match("^(.*)|")
  for k, r in pairs(scans) do
    if k ~= key and type(k) == "string" and type(r) == "table" and (tonumber(r.t) or 0) > rec.t
       and k:match("^(.*)|") == ruleset then
      s.why, s.other = "other", k
      return s
    end
  end
  local h
  for _, id in ipairs(rec.ids) do
    local a = Age(v1, id)
    if a and (not h or a > h) then h = a end
  end
  if not h then s.why = "gone"; return s end
  s.h, s.v1 = h, v1
  return s
end

-- Is a watched Auctionator scan of this Auction House in use right now?
function X:Usable()
  return self:State().h ~= nil
end

-- seconds since the scan in use finished, or nil
function X:AgeSeconds()
  local s = self:State()
  if not s.h then return nil end
  return math.max(0, time() - s.t)
end

-- A browse-like row of one item for Store.lua: { min = unit price, t, ext = "auctionator" }, or { none = true, t,
-- ext } when the scan in use did not see it, or nil when no scan is in use.
function X:Row(itemID)
  local s = self:State()
  if not s.h or type(itemID) ~= "number" then return nil end
  local row = s.rows[itemID]
  if row == nil then
    local a = Age(s.v1, itemID)
    local p = (a and a <= s.h) and Price(s.v1, itemID) or nil
    if p then
      row = { min = p, t = s.t, ext = "auctionator" }
    else
      row = { none = true, t = s.t, ext = "auctionator" }
    end
    s.rows[itemID] = row
  end
  return row
end

function X:Invalidate()
  self.state = nil
end

-- one line for the chat: is Auctionator in use, and if not, why (/gr auc)
function X:Describe()
  local L = WC.L
  self:Invalidate()
  local s = self:State()
  local age = WC.UI and WC.UI.Age or function(sec) return tostring(math.floor(sec / 60)) .. " min" end
  if s.why == "off" then return L.EXT_OFF end
  if s.why == "noapi" then return L.EXT_NOAPI end
  if s.why == "noscan" then return L.EXT_NOSCAN end
  if s.why == "old" then return L.EXT_OLD:format(age(math.max(0, time() - s.t))) end
  if s.why == "other" then return L.EXT_OTHER:format(tostring(s.other)) end
  if s.why == "gone" then return L.EXT_GONE end
  local priced, none = 0, 0
  local sample = Sample()
  for _, id in ipairs(sample.ids) do
    if sample.crate[id] then
      local row = self:Row(id)
      if row and row.min then priced = priced + 1 else none = none + 1 end
    end
  end
  local quick = WC.Scanner and WC.Scanner.IsQuick and WC.Scanner.IsQuick()
  return L.EXT_OK:format(age(self:AgeSeconds() or 0), priced, none, quick and L.EXT_ON or L.EXT_OFF_WORD)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    -- Auctionator says when its database was updated: look at once instead of at the next tick
    local A = rawget(_G, "Auctionator")
    local v1 = type(A) == "table" and type(A.API) == "table" and A.API.v1 or nil
    if type(v1) == "table" and type(v1.RegisterForDBUpdate) == "function" then
      pcall(v1.RegisterForDBUpdate, X.caller, function() SafeLook() end)
    end
  elseif event == "AUCTION_HOUSE_SHOW" then
    if X.ticker then X.ticker:Cancel(); X.ticker = nil end
    local v1 = V1()
    if not v1 then return end
    -- what Auctionator knows before anything is scanned in this visit: changes are measured against it
    local ok, snap = pcall(Read, v1)
    X.base = ok and snap or nil
    X.before, X.noted, X.market = X.base, false, nil
    if C_Timer and C_Timer.NewTicker then
      X.ticker = C_Timer.NewTicker(POLL, function() SafeLook() end)
    end
    -- once per session: say why Auctionator's prices are not in use (no scan watched yet, too old, other house)
    if not X.hinted and C_Timer and C_Timer.After then
      C_Timer.After(1.5, function()
        if X.hinted or not WC.ahOpen then return end
        X:Invalidate()
        local why = X:State().why
        if why == "noscan" or why == "old" or why == "other" then
          X.hinted = true
          WC:Print(X:Describe())
        end
      end)
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

-- settings and the Auction House in use decide whether the prices may be used
WC:On("SETTINGS_CHANGED", function() X:Invalidate() end)
WC:On("DB_READY", function() X:Invalidate() end)
