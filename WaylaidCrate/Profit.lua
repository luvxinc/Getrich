local addonName, WC = ...

-- Profit calculations (SPEC 3.7). Pure math on top of:
--   Store     WC:CostForAny, WC:UnitPrice, WC:DB() (results / browse)
--   Merchant  WC:VendorPrice
--   Recipes   WC.Recipes:ForChar, WC:EnchantingSkill
--   DE        WC.DE:Value
-- Results are cached and rebuilt in place (same tables reused) only after a bus message says an
-- input changed, so asking again while nothing changed costs nothing.
--
--   Profit:MatCost(itemID, qty)   cheapest way to buy qty of a material (AH order book vs vendor)
--   Profit:Craft(charKey)         profit of every captured recipe that makes an item
--   Profit:CraftEntry(recipeID)   one Craft entry of the current character (profession window label)
--   Profit:CraftCounts(charKey)   { total, noOutput, missing, loading, profitable, listed }
--   Profit:FlipCandidates(n)      items worth a targeted search for the flips scan
--   Profit:Flips()                AH listings cheaper than what a vendor pays
--   Profit:Disenchant()           disenchant value vs vendor / buy price for bag, AH and crafted gear
-- Everything returned is a shared cache: read it, never change it.

local Profit = WC.Profit or {}
WC.Profit = Profit

WC.AddLocale({
  enUS = {
    PROFIT_SCAN_LABEL  = "Crafting prices",
    PROFIT_SCAN_PHASE  = "Materials and products",
    PROFIT_NO_RECIPES  = "No recipes yet: open each profession window once so Waylaid Crate can read your recipes.",
  },
  zhCN = {
    PROFIT_SCAN_LABEL  = "制造价格",
    PROFIT_SCAN_PHASE  = "材料和成品",
    PROFIT_NO_RECIPES  = "还没有配方：请把每个专业窗口打开一次，Waylaid Crate 才能读取你的配方。",
  },
  zhTW = {
    PROFIT_SCAN_LABEL  = "製造價格",
    PROFIT_SCAN_PHASE  = "材料和成品",
    PROFIT_NO_RECIPES  = "還沒有配方：請把每個專業視窗打開一次，Waylaid Crate 才能讀取你的配方。",
  },
})
local L = WC.L

local pairs, type, tonumber, pcall, next = pairs, type, tonumber, pcall, next
local tsort = table.sort

local REQUEST_AGAIN = 30     -- seconds before asking the client again for an item that hasn't loaded
local BROWSE_SLACK  = 300    -- a browse takes up to ~4 min: entries stamped during it still count as current
local EMPTY = {}

local gen = 1                -- bumped when prices / recipes / vendor / DE samples / settings change
local bagGen = 1             -- bumped when the bags change (cash still needed, bag gear)

local function ClearArray(t, from)
  for i = #t, from or 1, -1 do t[i] = nil end
end

local function Now()
  return (GetTime and GetTime()) or 0
end

local function CurrentChar()
  local ok, key = pcall(WC.CharKey, WC)
  return (ok and key) or "?"
end

-- ---------------------------------------------------------------------------
-- item data: ask the client once (again after REQUEST_AGAIN s); when an item we asked for arrives,
-- caches are rebuilt and the UI is told (PRICES_UPDATED "items"), so "loading" rows fill in.

local requested, pendingLoad = {}, {}
-- the item-data events are only registered while something we asked for is still loading (nothing runs when idle)
local events, loadWatch = nil, false
local LOAD_EVENTS = { "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED" }

local function WatchLoads(on)
  if on == loadWatch or not events then return end
  loadWatch = on
  for i = 1, #LOAD_EVENTS do
    if on then pcall(events.RegisterEvent, events, LOAD_EVENTS[i])
    else pcall(events.UnregisterEvent, events, LOAD_EVENTS[i]) end
  end
end

local function Request(itemID)
  if not itemID then return end
  local now = Now()
  local last = requested[itemID]
  if last and now - last < REQUEST_AGAIN then return end
  requested[itemID] = now
  pendingLoad[itemID] = true
  WatchLoads(true)   -- before asking: a cached item answers synchronously
  WC.RequestItem(itemID)
end

-- vendor sell price per item: nil = not cached yet (requested), 0 = vendors don't buy it
local function Sell(itemID)
  local s = WC.SellPrice(itemID)
  if s == nil then Request(itemID) end
  return s
end

local function ItemLevelOf(itemID)
  local _, _, _, ilvl = WC.ItemInfo(itemID)
  return ilvl
end

-- weapon (2) or armor (4)? Uses the instant info, which works before the item is cached.
local function IsGearClass(itemID)
  local classID
  if C_Item and C_Item.GetItemInfoInstant then
    local ok, _, _, _, _, _, c = pcall(C_Item.GetItemInfoInstant, itemID)
    if ok then classID = c end
  end
  if classID == nil then
    local _, _, _, _, _, _, _, _, _, _, _, c = WC.ItemInfo(itemID)
    classID = c
  end
  return classID == 2 or classID == 4
end

-- ---------------------------------------------------------------------------
-- other modules, guarded (they are written in parallel and may be missing or fail)

local function DB()
  if WC.DB then
    local ok, db = pcall(WC.DB, WC)
    if ok and type(db) == "table" then return db end
  end
  if type(WaylaidCrateDB) == "table" then return WaylaidCrateDB end
  return nil
end

local function Results()
  local db = DB()
  local r = db and db.results
  if type(r) ~= "table" then r = WC.Scanner and WC.Scanner.results end
  if type(r) ~= "table" then return EMPTY end
  return r
end

local function Browse()
  local db = DB()
  local b = db and db.browse
  if type(b) == "table" then return b end
  return nil
end

-- cost, status, info{unit, time, source}
local function CostForAny(itemID, qty)
  if WC.CostForAny then
    local ok, cost, status, info = pcall(WC.CostForAny, WC, itemID, qty)
    if ok then return cost, status, info end
    return nil
  end
  if WC.CostFor then   -- 1.3.0 fallback: targeted results only
    local ok, cost, status, res = pcall(WC.CostFor, WC, itemID, qty)
    if ok and status then
      return cost, status, { unit = cost and cost / qty or (res and res.min), time = res and res.time, source = "search" }
    end
  end
  return nil
end

-- cheapest unit price, time, source
local function UnitPrice(itemID)
  if WC.UnitPrice then
    local ok, unit, t, source = pcall(WC.UnitPrice, WC, itemID)
    if ok then return unit, t, source end
    return nil
  end
  local r = Results()[itemID]
  if type(r) == "table" and r.status == "listed" and r.min then return r.min, r.time, "search" end
  return nil
end

-- unit price (per single item), info{source, npc, zone, x, y, bundle, limited, classic}
local function VendorPrice(itemID)
  if not WC.VendorPrice then return nil end
  local ok, unit, info = pcall(WC.VendorPrice, WC, itemID)
  if ok and type(unit) == "number" then return unit, info end
  return nil
end

local function RecipesFor(charKey)
  local R = WC.Recipes
  if not (R and R.ForChar) then return nil end
  local ok, t = pcall(R.ForChar, R, charKey)
  if ok and type(t) == "table" then return t end
  return nil
end

-- Enchanting skill of a character, or nil if it has no Enchanting
local function EnchSkill(charKey)
  if not WC.EnchantingSkill then return nil end
  local ok, s = pcall(WC.EnchantingSkill, WC, charKey)
  if ok and type(s) == "number" and s > 0 then return s end
  return nil
end

local function DEValue(itemID, ilvl)
  local DE = WC.DE
  if not (DE and DE.Value) then return nil, "nodata" end
  local ok, v, reason = pcall(DE.Value, DE, itemID, ilvl)
  if not ok then return nil, "error" end
  if type(v) ~= "table" then return nil, reason end
  return v
end

-- does a DE:Value result have at least one priced output? (all outputs unpriced -> value unknown, not 0)
local function DEPriced(v)
  local parts, missing = v.parts, v.missing
  if type(parts) == "table" and #parts > 0 then
    local nMissing = (type(missing) == "table") and #missing or 0
    return nMissing < #parts
  end
  return v.value ~= nil and (not v.partial or v.value > 0)
end

-- ---------------------------------------------------------------------------
-- materials

local matCache = {}   -- [itemID] = { [qty] = mat }

local function FillMat(m, itemID, qty)
  m.itemID, m.qty = itemID, qty

  -- Auction House: order-book walk (or browse estimate, status "est")
  local cost, status, info = CostForAny(itemID, qty)
  if type(info) ~= "table" then info = nil end
  local ah = m.ah
  ah.cost, ah.status = cost, status
  ah.unit = info and info.unit or nil
  ah.time = info and info.time or nil
  ah.source = info and info.source or nil
  local ahUsable = (cost ~= nil) and (status == "ok" or status == "est")   -- "short" = not enough listed

  -- vendor: unit price is per single item (a 10c bundle of 5 costs 2c per item)
  local vUnit, vInfo = VendorPrice(itemID)
  if type(vInfo) ~= "table" then vInfo = nil end
  local v = m.vendor
  v.unit, v.info = vUnit, vInfo
  v.cost = vUnit and vUnit * qty or nil
  v.bundle = vInfo and vInfo.bundle or nil
  v.limited = vInfo and vInfo.limited or nil
  v.stock = vInfo and tonumber(vInfo.stock) or nil          -- nil = unlimited
  -- a limited offer counts only if it has enough in stock for qty (sold out / too few: shown, not used)
  local vUsable = v.cost ~= nil and (not v.limited or (v.stock or 0) >= qty)
  v.insufficient = (v.cost ~= nil and not vUsable) or nil

  if vUsable and (not ahUsable or v.cost <= cost) then
    m.cost, m.unit, m.source, m.status = v.cost, vUnit, "vendor", "ok"
  elseif ahUsable then
    m.cost, m.unit, m.source, m.status = cost, cost / qty, "ah", status
  else
    m.cost, m.unit, m.source = nil, nil, nil
    m.status = status or "unscanned"   -- "short" | "none" | "timeout" | "unscanned"
  end
  m.missing = (m.cost == nil)
  m.est = (m.source == "ah" and status == "est") or nil
  m.bundle = v.bundle
  m.limited = (m.source == "vendor" and v.limited) or nil
end

-- { itemID, qty, cost, unit, source = "ah"|"vendor"|nil, status, est, bundle, limited, missing,
--   ah = { cost, status, unit, time, source }, vendor = { unit, cost, info, bundle, limited, stock, insufficient } }
-- cost is nil when neither the AH (enough listed) nor a vendor can supply qty. A limited vendor offer with
-- less than qty in stock is not used (vendor.insufficient = true).
function Profit:MatCost(itemID, qty)
  qty = tonumber(qty) or 1
  local byQty = matCache[itemID]
  if not byQty then byQty = {}; matCache[itemID] = byQty end
  local m = byQty[qty]
  if m and m.gen == gen then return m end
  if not m then
    m = { ah = {}, vendor = {} }
    byQty[qty] = m
  end
  FillMat(m, itemID, qty)
  m.gen = gen
  return m
end

-- ---------------------------------------------------------------------------
-- crafting

-- cash still needed for one craft: what is not in the bags, bought the cheapest way
local function FillCash(e, isMe)
  local reags = e.reagents
  local cash = 0
  for i = 1, #reags do
    local x = reags[i]
    local have = isMe and WC.BagCount(x.itemID) or 0
    local need = x.qty - have
    if need < 0 then need = 0 end
    x.have, x.need = have, need
    if need == 0 then
      x.cash = 0
    else
      local m = Profit:MatCost(x.itemID, need)
      x.cash = m.cost or (x.unit and x.unit * need) or nil
    end
    if cash and x.cash then cash = cash + x.cash else cash = nil end
  end
  if e.cost == nil then cash = nil end
  e.cash = cash
end

local function FillEntry(e, recipeID, r, ench, isMe)
  e.recipeID = recipeID
  e.name = r.n
  e.prof = r.p
  e.itemID = r.o
  e.tool = r.tool
  e.time = r.t
  local y1, y2 = tonumber(r.y1), tonumber(r.y2)
  local yield = ((y1 or y2 or 1) + (y2 or y1 or 1)) / 2
  if yield <= 0 then yield = 1 end
  e.yield = yield

  -- materials (owned ones count at today's price too)
  local reags = e.reagents
  if not reags then reags = {}; e.reagents = reags end
  local missing = e.missing
  if not missing then missing = {}; e.missing = missing end
  ClearArray(missing)
  local cost, est, n = 0, nil, 0
  local list = (type(r.r) == "table") and r.r or EMPTY
  for i = 1, #list do
    local rg = list[i]
    local itemID = (type(rg) == "table") and tonumber(rg[1] or rg.itemID) or nil
    if itemID then
      local qty = tonumber(rg[2] or rg.qty) or 1
      n = n + 1
      local x = reags[n]
      if not x then x = {}; reags[n] = x end
      local m = Profit:MatCost(itemID, qty)
      x.itemID, x.qty, x.mat = itemID, qty, m
      x.cost, x.unit, x.source, x.status = m.cost, m.unit, m.source, m.status
      x.missing, x.est, x.bundle, x.limited = m.missing, m.est, m.bundle, m.limited
      x.ah, x.vendor = m.ah, m.vendor
      if m.cost then cost = cost + m.cost else missing[#missing + 1] = itemID end
      if m.est then est = true end
    end
  end
  ClearArray(reags, n + 1)
  if #missing > 0 then cost = nil end
  e.cost = cost
  e.est = est
  FillCash(e, isMe)

  -- product
  local out = e.itemID
  local sell = Sell(out)
  e.sell = sell
  if sell then
    e.npc = sell * yield
    e.npcNoBuy = (sell == 0) or nil
  else
    e.npc, e.npcNoBuy = nil, nil
  end
  local ahUnit, ahTime, ahSource = UnitPrice(out)
  e.ahUnit, e.ahTime, e.ahSource = ahUnit, ahTime, ahSource
  e.ah = ahUnit and ahUnit * yield * (1 - (WC.AH_CUT or 0.05)) or nil

  e.de, e.deValue, e.dePartial, e.deSkillOK, e.deStatus, e.deMeasured = nil, nil, nil, nil, nil, nil
  if ench then
    local v, reason = DEValue(out)
    if v then
      e.deValue = v
      e.dePartial = v.partial and true or nil
      e.deMeasured = v.measured and true or nil
      e.deSkillOK = ench >= (tonumber(v.skill) or 0)
      if DEPriced(v) then
        e.de = (tonumber(v.value) or 0) * yield
        e.deStatus = e.dePartial and "partial" or "ok"
      else
        e.deStatus = "missing"
      end
    else
      e.deStatus = reason
      if reason == "loading" then Request(out) end
    end
  end

  -- profits (nil, never 0, when a price is unknown)
  local best, bestKind
  if cost then
    e.npcProfit = e.npc and (e.npc - cost) or nil
    e.ahProfit = e.ah and (e.ah - cost) or nil
    e.deProfit = e.de and (e.de - cost) or nil
    -- a route counts for best only when it is available: vendors buy it (sell > 0), it is listed on the AH,
    -- the skill is high enough to disenchant it. No available route -> best = nil.
    if e.npcProfit and not e.npcNoBuy then best, bestKind = e.npcProfit, "npc" end
    if e.ahProfit and (not best or e.ahProfit > best) then best, bestKind = e.ahProfit, "ah" end
    -- disenchanting counts as an option only when the skill is high enough
    if e.deProfit and e.deSkillOK and (not best or e.deProfit > best) then best, bestKind = e.deProfit, "de" end
  else
    e.npcProfit, e.ahProfit, e.deProfit = nil, nil, nil
  end
  e.best, e.bestKind = best, bestKind

  if cost == nil then
    e.status = "missing"
  elseif sell == nil then
    e.status = "loading"
  else
    e.status = "ok"
  end
end

-- best profit first; rows without a profit after; rows with missing prices last
local function CraftOrder(a, b)
  local ab, bb = a.best, b.best
  if ab and bb then
    if ab ~= bb then return ab > bb end
  elseif ab then
    return true
  elseif bb then
    return false
  else
    local am, bm = (a.status == "missing"), (b.status == "missing")
    if am ~= bm then return bm end
  end
  local an, bn = a.name or "", b.name or ""
  if an ~= bn then return an < bn end
  return a.recipeID < b.recipeID
end

local caches = {}   -- [charKey] = { gen, bagGen, list, byRecipe, counts }

local function BuildCraft(c, charKey)
  local recipes = RecipesFor(charKey)
  local isMe = (charKey == CurrentChar())
  local ench = EnchSkill(charKey)
  local list, byRecipe, counts = c.list, c.byRecipe, c.counts
  ClearArray(list)
  local total, noOutput, missing, loading, profitable = 0, 0, 0, 0, 0
  if recipes then
    for recipeID, r in pairs(recipes) do
      if type(r) == "table" then
        total = total + 1
        if r.o then
          local e = byRecipe[recipeID]
          if not e then e = {}; byRecipe[recipeID] = e end
          FillEntry(e, recipeID, r, ench, isMe)
          e.gen = gen
          list[#list + 1] = e
          if e.status == "missing" then
            missing = missing + 1
          elseif e.status == "loading" then
            loading = loading + 1
          end
          if e.best and e.best > 0 then profitable = profitable + 1 end
        else
          noOutput = noOutput + 1     -- enchants etc.: nothing to sell
        end
      end
    end
  end
  for k, e in pairs(byRecipe) do
    if e.gen ~= gen then byRecipe[k] = nil end
  end
  tsort(list, CraftOrder)
  counts.total, counts.noOutput, counts.missing = total, noOutput, missing
  counts.loading, counts.profitable, counts.listed = loading, profitable, #list
end

-- Array of entries (recipes that make an item), sorted best profit first, plus counts.
-- Entry: { recipeID, name, prof, itemID, yield, tool, time,
--   reagents = { { itemID, qty, cost, unit, source, status, missing, est, bundle, limited, have, need, cash,
--                  mat = MatCost table, ah = mat.ah, vendor = mat.vendor } },
--   cost, missing = { itemID, ... } (empty when none), est, cash,
--   sell, npc, npcNoBuy, npcProfit, ahUnit, ahTime, ahSource, ah, ahProfit,
--   de, deProfit, dePartial, deSkillOK, deMeasured, deStatus, deValue,
--   best, bestKind = "npc"|"ah"|"de", status = "ok"|"missing"|"loading" }
function Profit:Craft(charKey)
  charKey = charKey or CurrentChar()
  local c = caches[charKey]
  if not c then
    c = { list = {}, byRecipe = {}, counts = {} }
    caches[charKey] = c
  end
  if c.gen ~= gen then
    BuildCraft(c, charKey)
    c.gen, c.bagGen = gen, bagGen
  elseif c.bagGen ~= bagGen then
    local isMe = (charKey == CurrentChar())
    local list = c.list
    for i = 1, #list do FillCash(list[i], isMe) end
    c.bagGen = bagGen
  end
  return c.list, c.counts
end

function Profit:CraftEntry(recipeID)
  local charKey = CurrentChar()
  self:Craft(charKey)
  return caches[charKey].byRecipe[recipeID]
end

-- { total = recipes captured, noOutput = recipes without a product (not in Craft()),
--   missing, loading, profitable (best > 0), listed = #Craft() }
function Profit:CraftCounts(charKey)
  local _, counts = self:Craft(charKey)
  return counts
end

-- ---------------------------------------------------------------------------
-- crafting scan: materials without an unlimited vendor + products (+ DE materials for gear)

local function SortedKeys(set)
  local t = {}
  for k in pairs(set) do t[#t + 1] = k end
  tsort(t)
  return t
end

local function CraftScanItems()
  local recipes = RecipesFor(CurrentChar())
  local items = {}
  if not recipes then return items end
  local reag, outs, anyGear = {}, {}, false
  for _, r in pairs(recipes) do
    if type(r) == "table" and r.o then
      outs[r.o] = true
      local list = (type(r.r) == "table") and r.r or EMPTY
      for i = 1, #list do
        local rg = list[i]
        local id = (type(rg) == "table") and tonumber(rg[1] or rg.itemID) or nil
        if id and reag[id] == nil then
          -- skip the AH search only for a confirmed unlimited vendor; limited stock or a Classic-only
          -- location still gets searched so the AH price is known as a fallback
          local unit, info = VendorPrice(id)
          local confirmed = unit and type(info) == "table" and not info.limited and not info.classic
          reag[id] = not confirmed
        end
      end
    end
  end
  local seen = {}
  local function Add(id)
    if not seen[id] then seen[id] = true; items[#items + 1] = id end
  end
  local need = {}
  for id, search in pairs(reag) do
    if search then need[id] = true end
  end
  local list = SortedKeys(need)
  for i = 1, #list do Add(list[i]) end
  list = SortedKeys(outs)
  for i = 1, #list do
    Add(list[i])
    if not anyGear and IsGearClass(list[i]) then anyGear = true end
  end
  if anyGear and EnchSkill(CurrentChar()) and WC.DE and type(WC.DE.mats) == "table" then
    list = SortedKeys(WC.DE.mats)
    for i = 1, #list do Add(list[i]) end
  end
  return items
end
Profit.CraftScanItems = CraftScanItems

local kindRegistered = false
local function RegisterScanKind()
  if kindRegistered then return end
  local S = WC.Scanner
  if not (S and S.RegisterKind) then return end
  local ok = pcall(S.RegisterKind, S, "craft", {
    label = function() return L.PROFIT_SCAN_LABEL end,
    canStart = function()
      local recipes = RecipesFor(CurrentChar())
      if recipes and next(recipes) ~= nil then return true end
      return false, L.PROFIT_NO_RECIPES
    end,
    phases = {
      { type = "search", items = CraftScanItems, label = L.PROFIT_SCAN_PHASE },
    },
  })
  if ok then kindRegistered = true end
end

-- ---------------------------------------------------------------------------
-- flips: AH listings below the vendor sell price

-- itemIDs from the browse snapshot whose cheapest listing is below the vendor price,
-- biggest potential first: (sell - min) * min(qty, 20). Unknown sell prices are requested.
function Profit:FlipCandidates(n)
  n = tonumber(n) or 80
  local out = {}
  local browse = Browse()
  local items = browse and browse.items
  if type(items) ~= "table" then return out end
  local score = {}
  for itemID, b in pairs(items) do
    local min = type(b) == "table" and tonumber(b.min)
    if min and min > 0 then
      local sell = Sell(itemID)
      if sell and sell > 0 and min < sell then
        local q = tonumber(b.qty) or 1
        if q < 1 then q = 1 elseif q > 20 then q = 20 end
        out[#out + 1] = itemID
        score[itemID] = (sell - min) * q
      end
    end
  end
  tsort(out, function(a, b)
    local sa, sb = score[a], score[b]
    if sa ~= sb then return sa > sb end
    return a < b
  end)
  ClearArray(out, n + 1)
  return out
end

-- Browse items whose vendor price is still loading (the ones never asked for are asked for now). The flips scan
-- waits until this is 0 (or a timeout) before picking candidates: on a fresh login most items aren't cached yet.
-- Items the client could not load (ITEM_DATA_LOAD_RESULT false) don't count.
function Profit:FlipPending()
  local browse = Browse()
  local items = browse and browse.items
  if type(items) ~= "table" then return 0 end
  local n = 0
  for itemID, b in pairs(items) do
    local min = type(b) == "table" and tonumber(b.min)
    if min and min > 0 and WC.SellPrice(itemID) == nil then
      if requested[itemID] == nil then Request(itemID) end
      if pendingLoad[itemID] then n = n + 1 end
    end
  end
  return n
end

local flip = { list = {}, byItem = {}, stats = {} }
local flipSpare

-- Fill e for one item; returns true when it is (or just stopped being) a flip.
local function FillFlip(e, itemID, b, r, sell)
  local bmin = b and tonumber(b.min)
  local bt = b and tonumber(b.t)
  local browseSays = bmin and bmin > 0 and bmin < sell
  local rt = r and tonumber(r.time)
  -- an order book only speaks for the variant it was searched with: random-suffix gear must match the suffix of the
  -- variant the browse showed (Scanner stores the searched key's suffix as r.sfx)
  local sameKey = r and (tonumber(r.sfx) or 0) == (tonumber(b and b.sfx) or 0)
  e.itemID, e.sell, e.more = itemID, sell, nil
  if rt and sameKey and (not bt or rt >= bt) and (r.status == "listed" or r.status == "none") then
    -- searched after the browse: the order book is the truth
    local entries = (r.status == "listed" and type(r.entries) == "table") and r.entries or EMPTY
    local qty, cost, profit, last = 0, 0, 0, 0
    for i = 1, #entries do
      local unit, q = entries[i][1], entries[i][2]
      if unit and q and unit < sell then
        qty = qty + q
        cost = cost + unit * q
        profit = profit + (sell - unit) * q
        last = i
      else
        break
      end
    end
    local avail = tonumber(r.avail)
    if qty > 0 then
      local unit = entries[1][1]
      e.status, e.unit, e.qty, e.cost, e.profit = "ok", unit, qty, cost, profit
      e.perUnit, e.time, e.source, e.listed = sell - unit, rt, "search", avail
      if last == #entries and avail then
        -- every kept listing is profitable: more may exist beyond what was kept (qty is a minimum)
        local covered = 0
        for i = 1, #entries do covered = covered + (entries[i][2] or 0) end
        if avail > covered then e.more = true end
      end
      return true
    elseif browseSays then
      local unit = entries[1] and entries[1][1] or nil
      e.status, e.unit, e.qty, e.cost, e.profit = "gone", unit, 0, 0, 0
      e.perUnit = unit and (sell - unit) or nil
      e.time, e.source, e.listed = rt, "search", avail or 0
      return true
    end
    return false
  end
  if browseSays then
    -- only the browse snapshot: cheapest price known, quantity below the vendor price unknown
    e.status, e.unit, e.qty, e.cost, e.profit = "est", bmin, nil, bmin, sell - bmin
    e.perUnit, e.time, e.source, e.listed = sell - bmin, bt, "browse", tonumber(b.qty)
    return true
  end
  return false
end

local FLIP_RANK = { ok = 1, est = 2, gone = 3 }
local function FlipOrder(a, b)
  local ga, gb = (a.status == "gone"), (b.status == "gone")
  if ga ~= gb then return gb end
  if a.profit ~= b.profit then return a.profit > b.profit end
  local ra, rb = FLIP_RANK[a.status] or 9, FLIP_RANK[b.status] or 9
  if ra ~= rb then return ra < rb end
  return a.itemID < b.itemID
end

local function AddFlip(itemID, b, r, sell)
  local e = flip.byItem[itemID]
  local fresh = (e == nil)
  if fresh then
    e = flipSpare or {}
    flipSpare = nil
  end
  if FillFlip(e, itemID, b, r, sell) then
    if fresh then flip.byItem[itemID] = e end
    e.gen = gen
    flip.list[#flip.list + 1] = e
    return e.status
  end
  if fresh then flipSpare = e end
  return nil
end

-- Entries { itemID, unit, sell, qty, cost, profit, perUnit, status = "ok"|"est"|"gone", time,
--   source = "search"|"browse", listed (units listed, any price), more (qty is a minimum) },
-- sorted by profit ("gone" last), plus stats { ok, est, gone, loading }.
function Profit:Flips()
  if flip.gen == gen then return flip.list, flip.stats end
  local list, byItem, stats = flip.list, flip.byItem, flip.stats
  ClearArray(list)
  local counts = { ok = 0, est = 0, gone = 0 }
  local loading = 0
  local browse = Browse()
  local items = (browse and type(browse.items) == "table") and browse.items or EMPTY
  local results = Results()
  for itemID, b in pairs(items) do
    if type(b) == "table" then
      local sell = Sell(itemID)
      if sell == nil then
        loading = loading + 1
      elseif sell > 0 then
        local r = results[itemID]
        local st = AddFlip(itemID, b, type(r) == "table" and r or nil, sell)
        if st then counts[st] = counts[st] + 1 end
      end
    end
  end
  -- searched items that weren't in the browse (e.g. crate materials)
  for itemID, r in pairs(results) do
    if items[itemID] == nil and type(r) == "table" and r.status == "listed" then
      local sell = Sell(itemID)
      if sell == nil then
        loading = loading + 1
      elseif sell > 0 then
        local st = AddFlip(itemID, nil, r, sell)
        if st then counts[st] = counts[st] + 1 end
      end
    end
  end
  for k, e in pairs(byItem) do
    if e.gen ~= gen then byItem[k] = nil end
  end
  tsort(list, FlipOrder)
  stats.ok, stats.est, stats.gone, stats.loading = counts.ok, counts.est, counts.gone, loading
  flip.gen = gen
  return list, stats
end

-- ---------------------------------------------------------------------------
-- disenchanting

local de = { list = {}, bag = {}, ah = {}, craft = {}, bagList = {}, ahList = {}, craftList = {}, stats = {} }
local deSpare
local bagStamp = 0

local function BagRange()
  local first = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack) or BACKPACK_CONTAINER or 0
  local n = NUM_BAG_SLOTS
  if type(n) ~= "number" then
    n = Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots
  end
  if type(n) ~= "number" then n = 4 end
  return first, first + n
end

local function LinkLevel(link)
  if not (link and C_Item and C_Item.GetDetailedItemLevelInfo) then return nil end
  local ok, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
  if ok and type(ilvl) == "number" and ilvl > 0 then return ilvl end
  return nil
end

-- DE fields shared by every source. Returns false for items that aren't disenchantable gear
-- (keepUnDE: still return gear that can't be disenchanted, flagged by status).
local function FillDE(e, itemID, ilvl, ench, keepUnDE)
  local v, reason = DEValue(itemID, ilvl)
  e.itemID, e.de, e.reason = itemID, v, reason
  e.ilvl = ilvl or ItemLevelOf(itemID)
  if v then
    e.value = DEPriced(v) and (tonumber(v.value) or 0) or nil
    e.partial = v.partial and true or nil
    e.missing = v.missing
    e.measured = v.measured and true or nil
    e.casts, e.skill, e.band = v.casts, v.skill, v.band
    e.skillOK = (ench ~= nil) and ench >= (tonumber(v.skill) or 0)
    return true
  end
  e.value, e.partial, e.missing, e.measured, e.casts, e.skill, e.band = nil, nil, nil, nil, nil, nil, nil
  e.skillOK = false
  if reason == "loading" then
    Request(itemID)
    return true
  end
  if keepUnDE and (reason == "nodisenchant" or reason == "noband") then return true end
  return false
end

-- status from the DE fields and the price compared against
local function DEStatus(e, against)
  if not e.de then return e.reason or "missing" end
  if e.value == nil then return "missing" end
  if against == nil then return "loading" end
  if e.partial then return "partial" end
  return "ok"
end

local function SweepStamp(map, stamp)
  for k, e in pairs(map) do
    if e.stamp ~= stamp then map[k] = nil end
  end
end

local function TakeEntry(map, key)
  local e = map[key]
  if e then return e, false end
  e = deSpare or {}
  deSpare = nil
  return e, true
end

local function ScanBags(ench)
  local map, list = de.bag, de.bagList
  ClearArray(list)
  bagStamp = bagStamp + 1
  local stamp = bagStamp
  if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo then
    local first, last = BagRange()
    for bag = first, last do
      local okN, n = pcall(C_Container.GetContainerNumSlots, bag)
      if okN and type(n) == "number" then
        for slot = 1, n do
          local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
          local itemID = ok and type(info) == "table" and info.itemID or nil
          if itemID then
            local e = map[itemID]
            if e and e.stamp == stamp then
              e.count = e.count + (info.stackCount or 1)
            elseif IsGearClass(itemID) then
              local fresh
              e, fresh = TakeEntry(map, itemID)
              if FillDE(e, itemID, LinkLevel(info.hyperlink), ench, true) then
                map[itemID] = e
                e.stamp, e.source, e.count = stamp, "bag", info.stackCount or 1
                e.link, e.bound = info.hyperlink, info.isBound and true or nil
                e.recipeID, e.yield, e.time, e.listed, e.costMissing = nil, nil, nil, nil, nil
                e.sell = Sell(itemID)
                e.buy = nil
                e.gain = (e.value and e.sell) and (e.value - e.sell) or nil
                e.status = DEStatus(e, e.sell)
                list[#list + 1] = e
              elseif fresh then
                deSpare = e
              end
            end
          end
        end
      end
    end
  end
  SweepStamp(map, stamp)
  for i = 1, #list do
    local e = list[i]
    e.totalGain = e.gain and e.gain * e.count or nil
  end
end

local function ScanAH(ench)
  local map, list = de.ah, de.ahList
  ClearArray(list)
  local stamp = gen
  local browse = Browse()
  local items = browse and browse.items
  if ench and type(items) == "table" then
    -- only listings seen by the latest browse (older entries may be sold)
    local since = math.max(tonumber(browse.gear) or 0, tonumber(browse.full) or 0) - BROWSE_SLACK
    for itemID, b in pairs(items) do
      local min = type(b) == "table" and tonumber(b.min) or nil
      if min and min > 0 and (tonumber(b.t) or 0) >= since and IsGearClass(itemID) then
        local e, fresh = TakeEntry(map, itemID)
        if FillDE(e, itemID, tonumber(b.ilvl), ench, false) then
          map[itemID] = e
          e.stamp, e.source = stamp, "ah"
          e.count, e.link, e.bound, e.recipeID, e.yield, e.costMissing = nil, nil, nil, nil, nil, nil
          e.sell = Sell(itemID)
          e.buy, e.time, e.listed = min, tonumber(b.t), tonumber(b.qty)
          e.gain = e.value and (e.value - min) or nil
          e.totalGain = nil
          e.status = DEStatus(e, min)
          list[#list + 1] = e
        elseif fresh then
          deSpare = e
        end
      end
    end
  end
  SweepStamp(map, stamp)
end

local function ScanCraft(ench)
  local map, list = de.craft, de.craftList
  ClearArray(list)
  local stamp = gen
  if ench then
    local craft = Profit:Craft()
    for i = 1, #craft do
      local ce = craft[i]
      local v = ce.deValue
      if v then
        local e = map[ce.recipeID]
        if not e then e = {}; map[ce.recipeID] = e end
        e.stamp, e.source = stamp, "craft"
        e.itemID, e.recipeID, e.name, e.yield = ce.itemID, ce.recipeID, ce.name, ce.yield
        e.ilvl = ItemLevelOf(ce.itemID)
        e.de, e.reason = v, nil
        e.value = ce.de                      -- per craft (DE value x yield)
        e.partial, e.missing, e.measured = ce.dePartial, v.missing, ce.deMeasured
        e.casts, e.skill, e.band, e.skillOK = v.casts, v.skill, v.band, ce.deSkillOK and true or false
        e.count, e.link, e.bound, e.time, e.listed, e.totalGain = nil, nil, nil, nil, nil, nil
        e.sell = ce.sell
        e.buy = ce.cost                      -- material cost per craft
        e.costMissing = ce.missing           -- materials without a price
        e.gain = ce.deProfit
        if ce.cost == nil or e.value == nil then
          e.status = "missing"
        elseif e.partial then
          e.status = "partial"
        else
          e.status = "ok"
        end
        list[#list + 1] = e
      end
    end
  end
  SweepStamp(map, stamp)
end

local SRC_RANK = { bag = 1, ah = 2, craft = 3 }
local function DEOrder(a, b)
  local ga, gb = a.gain, b.gain
  if ga and gb then
    if ga ~= gb then return ga > gb end
  elseif ga then
    return true
  elseif gb then
    return false
  end
  local ra, rb = SRC_RANK[a.source] or 9, SRC_RANK[b.source] or 9
  if ra ~= rb then return ra < rb end
  if a.itemID ~= b.itemID then return a.itemID < b.itemID end
  return (a.recipeID or 0) < (b.recipeID or 0)
end

-- Entries { source = "bag"|"ah"|"craft", itemID, ilvl, count (bag), link, bound (bag), recipeID, name,
--   yield (craft), de = DE:Value table, value (DE value; nil if no output priced; per craft for
--   "craft"), sell (NPC price), buy (AH min / material cost per craft), gain (bag: value - sell;
--   ah/craft: value - buy), totalGain (bag: gain x count), skillOK, skill, partial, missing (DE mats
--   without a price), costMissing (craft), measured, casts, band, time, listed,
--   status = "ok"|"partial"|"missing"|"loading"|"nodisenchant"|"noband" },
-- sorted by gain (unknown last), plus stats { bag, ah, craft, lowSkill, loading, enchanting }.
function Profit:Disenchant()
  local ench = EnchSkill(CurrentChar())
  local changed = false
  if de.gen ~= gen then
    ScanAH(ench)
    ScanCraft(ench)
    ScanBags(ench)
    de.gen, de.bagGen = gen, bagGen
    changed = true
  elseif de.bagGen ~= bagGen then
    ScanBags(ench)
    de.bagGen = bagGen
    changed = true
  end
  if changed or not de.built then
    local list = de.list
    ClearArray(list)
    local lowSkill, loading = 0, 0
    local parts = { de.bagList, de.ahList, de.craftList }
    for p = 1, 3 do
      local src = parts[p]
      for i = 1, #src do
        local e = src[i]
        list[#list + 1] = e
        if e.de and not e.skillOK then lowSkill = lowSkill + 1 end
        if e.status == "loading" then loading = loading + 1 end
      end
    end
    tsort(list, DEOrder)
    local stats = de.stats
    stats.bag, stats.ah, stats.craft = #de.bagList, #de.ahList, #de.craftList
    stats.lowSkill, stats.loading, stats.enchanting = lowSkill, loading, ench
    de.built = true
  end
  return de.list, de.stats
end

-- ---------------------------------------------------------------------------
-- invalidation + events

local function Invalidate()
  gen = gen + 1
end
Profit.Invalidate = Invalidate

-- While a browse runs (flips / de scans), ask the client for the items it just listed, so their vendor
-- price and item level are known by the time FlipCandidates / Disenchant need them (right after the browse).
-- Only entries stamped since the previous call are looked at (the Scanner stamps t = time() per page).
local warmSince = 0
local function WarmBrowse()
  local browse = Browse()
  local items = browse and browse.items
  if type(items) ~= "table" then return end
  local since = warmSince
  warmSince = ((time and time()) or 0) - 1
  for itemID, b in pairs(items) do
    if type(b) == "table" and (tonumber(b.t) or 0) >= since and requested[itemID] == nil
       and WC.SellPrice(itemID) == nil then
      Request(itemID)
    end
  end
end

WC:On("PRICES_UPDATED", function(kind)
  Invalidate()
  if kind == "flips" or kind == "de" then WarmBrowse() end
end)
WC:On("RECIPES_UPDATED", Invalidate)
WC:On("VENDOR_UPDATED", Invalidate)
WC:On("DE_UPDATED", Invalidate)
WC:On("SETTINGS_CHANGED", Invalidate)
WC:On("BAGS_UPDATED", function() bagGen = bagGen + 1 end)
WC:On("DB_READY", function()
  RegisterScanKind()
  Invalidate()
end)

-- Scanner.lua loads before this file (TOC), so this normally registers right away.
RegisterScanKind()

events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED")
if next(pendingLoad) then WatchLoads(true) end   -- (items requested while this file loaded)

local function After(seconds, fn)
  if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) else fn() end
end

-- bag changes: one BAGS_UPDATED at most once per second, 1 s after the first change
local bagsPending = false
local function FireBags()
  bagsPending = false
  WC:Fire("BAGS_UPDATED")
end

-- items we asked for arrived: rebuild and let the UI refresh (at most twice a second)
local itemsPending = false
local function FireItems()
  itemsPending = false
  WC:Fire("PRICES_UPDATED", "items")
end

events:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "BAG_UPDATE_DELAYED" then
    if not bagsPending then
      bagsPending = true
      After(1, FireBags)
    end
  elseif a1 and pendingLoad[a1] then   -- ITEM_DATA_LOAD_RESULT / GET_ITEM_INFO_RECEIVED (itemID, success)
    pendingLoad[a1] = nil
    if next(pendingLoad) == nil then WatchLoads(false) end
    if a2 ~= false then
      requested[a1] = nil           -- loaded: nothing to remember (keeps the table small)
      if not itemsPending then
        itemsPending = true
        After(0.5, FireItems)
      end
    end
  end
end)
