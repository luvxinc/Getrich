local addonName, WC = ...

-- SavedVariables layout, prices and price history.
--
-- GetrichDB = {
--   <settings>          see DEFAULTS below (+ keys other modules add with Store:Default)
--   resultsFormat = 3,
--   results   = { [itemID] = { status = "listed"|"none"|"timeout", entries = { {unit, qty}, ... } cheapest first,
--                              min, avail, time } }            -- latest targeted search (same as 1.3.0)
--   (Init drops results and browse rows older than pruneDays, default 14)
--   browse    = { full = <time of last full browse>, gear = <time of last gear browse>,
--                 items = { [itemID] = { min = cheapest unit, qty = units listed, t = time, ilvl = item level|nil } } }
--   scannedAt = { [kind] = time },
--   history   = { [itemID] = { h = { [hourIndex] = { min = , qty = } },
--                              d = { [dayIndex] = { lo = , avg = , hi = , n = } } } }
--   watch     = { [itemID] = true },
--   vendorObs = {}  (Merchant.lua)   recipes = {}, chars = {}  (Recipes.lua)   deSamples = {}  (Disenchant.lua)
-- }
-- hourIndex = floor(serverTime / 3600), dayIndex = floor(hourIndex / 24) (UTC days).
-- Hourly records older than historyDays (default 30) are folded into one daily record { lo, avg, hi, n } when the
-- addon loads or the setting changes (avg = average of that day's hourly cheapest prices, n = hourly records folded in).
-- An old Codex-built "Getrich" database (schemaVersion + markets/characters, no resultsFormat) is wiped on load.

local Store = {}
WC.Store = Store

local RESULTS_FORMAT = 3

Store.DEFAULTS = {
  tab = "crates",         -- open tab
  autoScan = true,        -- scan the open tab when the Auction House opens
  soundOnDone = true,     -- play a sound when a scan finishes
  -- crates tab
  onlyMine = false,       -- only crates my level can open
  hideNoCrate = true,     -- ignore crates that nobody is selling
  hideNoMats = true,      -- ignore crates whose materials are all out of stock
  perfRank = 0,           -- Legacy Performance Bonus rank (0-3)
  -- writs tab
  hideNoWrit = true,      -- ignore writs nobody is selling
  hideNoItem = true,      -- ignore writs whose requested item can't be bought
  hideDone = true,        -- ignore writs already turned in today
  diplomatRank = 0,       -- Legacy Diplomat rank (0-5)
}
local DEFAULTS = Store.DEFAULTS

-- tables every DB has (owners noted in the header)
local TABLES = { "results", "scannedAt", "history", "watch", "vendorObs", "recipes", "chars", "deSamples" }

-- what WC:DB() returns before the SavedVariables are loaded: defaults + empty tables
local PRELOAD = setmetatable({ browse = { items = {} } }, { __index = DEFAULTS })
for _, k in ipairs(TABLES) do PRELOAD[k] = {} end

function WC:DB()
  return GetrichDB or PRELOAD
end

local function ServerNow()
  local ok, t = pcall(function() return GetServerTime and GetServerTime() end)
  if ok and t then return t end
  return time()
end
Store.ServerNow = ServerNow

-- register a default setting (call at file load time, before DB_READY)
function Store:Default(key, value)
  DEFAULTS[key] = value
  if GetrichDB and GetrichDB[key] == nil then GetrichDB[key] = value end
end

Store:Default("historyDays", 30)   -- hourly price history kept this many days, then one record per day
Store:Default("pruneDays", 14)     -- search results / browse rows older than this are not used for prices

-- a whole number of days from the settings (the default if missing or out of range)
local function Days(key, lo, hi)
  local v = tonumber(WC:DB()[key])
  if not v or v < lo or v > hi then return DEFAULTS[key] end
  return math.floor(v)
end

-- ---------------------------------------------------------------------------
-- load / upgrade

function Store:Init()
  local db = GetrichDB
  if type(db) ~= "table" then db = {}; GetrichDB = db end
  -- The old Codex-built "Getrich" used the same SavedVariables name with a different layout. The user wants it gone
  -- completely (SPEC2 0.1): nothing is migrated.
  if db.resultsFormat == nil and db.schemaVersion ~= nil and (db.markets ~= nil or db.characters ~= nil) then
    db = {}
    GetrichDB = db
    self.wipedOld = true
  end
  for k, v in pairs(DEFAULTS) do
    if db[k] == nil then db[k] = v end
  end
  db.mode = nil   -- removed in 1.3.0

  -- results: format 2 (1.3.0) and 3 have the same per-item layout, so they are kept as they are.
  -- Anything older (or broken) is dropped, like 1.3.0 did.
  local fmt = db.resultsFormat
  if (fmt == 2 or fmt == RESULTS_FORMAT) and type(db.results) == "table" then
    for itemID, r in pairs(db.results) do
      if type(itemID) ~= "number" or type(r) ~= "table" or type(r.status) ~= "string" then db.results[itemID] = nil end
    end
  else
    db.results, db.scannedAt = {}, {}
  end
  db.resultsFormat = RESULTS_FORMAT

  for _, k in ipairs(TABLES) do
    if type(db[k]) ~= "table" then db[k] = {} end
  end
  if type(db.browse) ~= "table" then db.browse = {} end
  if type(db.browse.items) ~= "table" then db.browse.items = {} end

  self.db = db
  self:PruneOld()
  self:Compress()
  if WC.Scanner then WC.Scanner.results = db.results end
  self.relevant = nil
  WC:Fire("DB_READY")
end

-- Drop search results and browse rows older than pruneDays. Returns results dropped, browse rows dropped.
function Store:PruneOld(now)
  local db = GetrichDB
  if not db or type(db.results) ~= "table" or type(db.browse) ~= "table" or type(db.browse.items) ~= "table" then return 0, 0 end
  local cutoff = (now or time()) - Days("pruneDays", 1, 3650) * 86400
  local nr, nb = 0, 0
  for itemID, r in pairs(db.results) do
    if type(r.time) == "number" and r.time < cutoff then db.results[itemID] = nil; nr = nr + 1 end
  end
  for itemID, b in pairs(db.browse.items) do
    if type(b) ~= "table" or (type(b.t) == "number" and b.t < cutoff) then db.browse.items[itemID] = nil; nb = nb + 1 end
  end
  return nr, nb
end

-- Fold hourly records older than historyDays into daily { lo, avg, hi, n } (merged into an existing day).
-- Returns the number of hourly records folded.
function Store:Compress(now)
  local db = GetrichDB
  if not db or type(db.history) ~= "table" then return 0 end
  local cutoff = math.floor((now or ServerNow()) / 3600) - Days("historyDays", 1, 3650) * 24
  local folded = 0
  for itemID, rec in pairs(db.history) do
    if type(rec) ~= "table" then
      db.history[itemID] = nil
    else
      rec.h = type(rec.h) == "table" and rec.h or {}
      rec.d = type(rec.d) == "table" and rec.d or {}
      for hour, r in pairs(rec.h) do
        if type(hour) ~= "number" or type(r) ~= "table" or type(r.min) ~= "number" then
          rec.h[hour] = nil
        elseif hour < cutoff then
          local day = math.floor(hour / 24)
          local d = rec.d[day]
          if d then
            d.avg = (d.avg * d.n + r.min) / (d.n + 1)
            d.n = d.n + 1
            if r.min < d.lo then d.lo = r.min end
            if r.min > d.hi then d.hi = r.min end
          else
            rec.d[day] = { lo = r.min, avg = r.min, hi = r.min, n = 1 }
          end
          rec.h[hour] = nil
          folded = folded + 1
        end
      end
      if next(rec.h) == nil and next(rec.d) == nil then db.history[itemID] = nil end
    end
  end
  return folded
end

-- ---------------------------------------------------------------------------
-- relevant items (the only ones that get history)

function WC:CrateItemSet()
  local set = {}
  for _, c in ipairs(WC.CRATES or {}) do
    set[c.id] = true
    for _, o in ipairs(c.opts) do set[o[1]] = true end
  end
  return set
end

function WC:WritItemSet()
  local set = {}
  for _, w in ipairs(WC.WRITS or {}) do set[w.writ] = true; set[w.item] = true end
  return set
end

-- copy itemIDs from a set ({ [id] = true }) or a list ({ id, ... }) into `into`
local function AddIDs(into, t)
  if type(t) ~= "table" then return end
  for k, v in pairs(t) do
    if v == true and type(k) == "number" then into[k] = true
    elseif type(v) == "number" then into[v] = true end
  end
end

function Store:RelevantSet()
  if self.relevant then return self.relevant end
  local set = WC:CrateItemSet()
  AddIDs(set, WC:WritItemSet())
  if WC.Recipes and WC.Recipes.AllItemIDs then
    local ok, ids = pcall(WC.Recipes.AllItemIDs, WC.Recipes)
    if ok then AddIDs(set, ids) end
  end
  if WC.DE and WC.DE.mats then AddIDs(set, WC.DE.mats) end
  AddIDs(set, WC:DB().watch)
  self.relevant = set
  return set
end

function Store:IsRelevant(itemID)
  return itemID ~= nil and self:RelevantSet()[itemID] == true
end

local function Invalidate() Store.relevant = nil end
WC:On("RECIPES_UPDATED", Invalidate)
WC:On("SETTINGS_CHANGED", Invalidate)
WC:On("DB_READY", Invalidate)

-- a shorter history / prune window takes effect right away
WC:On("SETTINGS_CHANGED", function(key)
  if not GetrichDB then return end
  if key == "historyDays" then Store:Compress() elseif key == "pruneDays" then Store:PruneOld() end
end)

-- ---------------------------------------------------------------------------
-- watch list

function Store:IsWatched(itemID)
  return WC:DB().watch[itemID] == true
end

function Store:SetWatch(itemID, on)
  if type(itemID) ~= "number" then return end
  local watch = WC:DB().watch
  local new = on and true or nil
  if watch[itemID] == new then return end
  watch[itemID] = new
  self.relevant = nil
  WC:Fire("SETTINGS_CHANGED", "watch")
end

-- watched itemIDs, sorted
function Store:Watched()
  local list = {}
  for itemID, on in pairs(WC:DB().watch) do
    if on == true and type(itemID) == "number" then list[#list + 1] = itemID end
  end
  table.sort(list)
  return list
end

-- ---------------------------------------------------------------------------
-- history

-- Store this hour's record (repeated calls in the same hour overwrite it). Only relevant items are kept.
-- t = observation time in epoch seconds (default: server time now). Returns true if stored.
function Store:RecordHistory(itemID, min, qty, t)
  if type(min) ~= "number" or min <= 0 then return false end
  if not GetrichDB or not self:IsRelevant(itemID) then return false end
  local hist = GetrichDB.history
  local rec = hist[itemID]
  if not rec then rec = { h = {}, d = {} }; hist[itemID] = rec end
  rec.h[math.floor((t or ServerNow()) / 3600)] = { min = min, qty = qty }
  return true
end

-- Records of one item between fromTime and toTime (epoch seconds, nil = open), sorted by time:
-- { t = bucket start, min, qty } for hours; { t = day start, min = day average, lo, hi, avg, n, daily = true } for days.
function Store:History(itemID, fromTime, toTime)
  local out = {}
  local rec = WC:DB().history[itemID]
  if not rec then return out end
  local function inRange(t)
    return (not fromTime or t >= fromTime) and (not toTime or t <= toTime)
  end
  for hour, r in pairs(rec.h or {}) do
    local t = hour * 3600
    if inRange(t) then out[#out + 1] = { t = t, min = r.min, qty = r.qty } end
  end
  for day, d in pairs(rec.d or {}) do
    local t = day * 86400
    if inRange(t) then
      out[#out + 1] = { t = t, min = math.floor(d.avg + 0.5), avg = d.avg, lo = d.lo, hi = d.hi, n = d.n, daily = true }
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end

-- itemIDs that have any history (unsorted)
function Store:HistoryItems()
  local list = {}
  for itemID in pairs(WC:DB().history) do list[#list + 1] = itemID end
  return list
end

-- ---------------------------------------------------------------------------
-- prices

local function Results()
  return (WC.Scanner and WC.Scanner.results) or WC:DB().results
end

-- Cost of buying `qty` of an item from the scanned listings, cheapest first (targeted searches only).
-- Returns cost (nil if unscanned / not listed / not enough), status, result.
-- status: "ok" | "short" | "none" | "timeout" | nil (not scanned)
function WC:CostFor(itemID, qty)
  local res = Results()[itemID]
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

-- the targeted result if it should be used (exists, has an answer, not older than the browse entry)
local function PickSearch(itemID)
  local res = Results()[itemID]
  local b = WC:DB().browse.items[itemID]
  if res and res.status == "timeout" and b then res = nil end   -- no answer: the browse snapshot knows more
  if res and (not b or (res.time or 0) >= (b.t or 0)) then return res, nil end
  return nil, b
end

-- Cost of `qty` items from the best data we have: the targeted order book, or else the browse snapshot
-- (cheapest price x qty, status "est" because the price of the deeper listings is unknown).
-- status: "ok" | "short" | "est" | "none" | "timeout" | nil (no data)
-- info = { unit, time, source = "search"|"browse", avail }
function WC:CostForAny(itemID, qty)
  qty = qty or 1
  local res, b = PickSearch(itemID)
  if res then
    local cost, status = WC:CostFor(itemID, qty)
    local info = { time = res.time, source = "search", avail = res.avail }
    if status == "short" and (tonumber(res.avail) or 0) >= qty then
      -- Only the cheapest ~250 units are kept (Scanner KEEP_QTY), but the AH lists enough: price the rest at the
      -- dearest kept unit price (a lower bound). CostFor itself stays exact for crates / writs.
      local remain, last = qty, nil
      cost = 0
      for _, e in ipairs(res.entries or {}) do
        local take = math.min(remain, e[2])
        cost = cost + take * e[1]
        remain = remain - take
        last = e[1]
      end
      cost = cost + remain * (last or res.min or 0)
      status, info.estDepth = "est", true
    end
    info.unit = (cost and qty > 0) and cost / qty or res.min
    return cost, status, info
  end
  if b and b.min then
    local info = { unit = b.min, time = b.t, source = "browse", avail = b.qty }
    -- the browse row does tell how many are listed in total
    if b.qty and b.qty < qty then return nil, "short", info end
    return b.min * qty, "est", info
  end
  return nil, nil, nil
end

-- cheapest unit price, time, source ("search"|"browse"); nil if not listed / unknown
function WC:UnitPrice(itemID)
  local res, b = PickSearch(itemID)
  if res then
    if res.status == "listed" and res.min then return res.min, res.time, "search" end
    return nil
  end
  if b and b.min then return b.min, b.t, "browse" end
  return nil
end
