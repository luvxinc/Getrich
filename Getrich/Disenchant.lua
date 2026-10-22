local addonName, WC = ...

-- Disenchanting: what an item disenchants into, what that is worth at current AH prices, and a recorder for the
-- player's own disenchants. The data table WC.DE (bands, noDE, mats, spell) comes from DataDisenchant.lua; this file
-- only adds functions to it. Bands come from the Forever client, odds/quantities from Classic, so values are an
-- estimate until the player has recorded db.deMeasuredCasts (default 20) real disenchants of a band; then that band
-- uses the measured odds.
--
-- Public:
--   DE:Band(itemID, ilvl)   -> band row | nil, reason ("loading"|"notgear"|"quality"|"nodisenchant"|"noband")
--   DE:BandKey(band)        -> "q:class:lo-hi" (key of db.deSamples)
--   DE:BandLabel(band)      -> "Uncommon armor, item level 21-25" (localized)
--   DE:ReasonText(reason)   -> localized text for a Band()/Value() reason
--   DE:Expected(band)       -> { {itemID, chance, min, max, itemID=, qty=, chance=, min=, max=}, ... }, measured, casts
--   DE:Value(itemID, ilvl)  -> { value, parts, missing, partial, priced, measured, casts, band, bandKey, skill, skillOK,
--                                time } | nil, reason
--   DE:Samples()            -> per-band summary of the recorded disenchants (for the UI)
--   DE:AddSample(band, totals) / DE:ClearSamples(bandKey|nil)
-- Sampling (automatic): UNIT_SPELLCAST_* for the Disenchant spell + ITEM_LOCK_CHANGED (which bag item the cast
-- locked) + LOOT_READY/LOOT_OPENED (what it produced). Samples go to GetrichDB.deSamples[bandKey] =
-- { casts = n, qty = { [itemID] = total }, hit = { [itemID] = castsContaining }, min = {...}, max = {...}, t = time }.

WC.AddLocale({
  enUS = {
    DE_REASON_loading = "Loading item data...",
    DE_REASON_notgear = "Not armor or a weapon",
    DE_REASON_quality = "Only green, blue and purple items can be disenchanted",
    DE_REASON_nodisenchant = "This item cannot be disenchanted",
    DE_REASON_noband = "No disenchant data for this item level",
    DE_Q2 = "Uncommon", DE_Q3 = "Rare", DE_Q4 = "Epic",
    DE_CLASS2 = "weapon", DE_CLASS4 = "armor",
    DE_BAND = "%s %s, item level %d-%d",
    DE_NOW_MEASURED = "%s: now using your own %d disenchants instead of the estimate.",
  },
  zhCN = {
    DE_REASON_loading = "正在读取物品信息…",
    DE_REASON_notgear = "不是护甲或武器",
    DE_REASON_quality = "只有绿色、蓝色和紫色物品可以分解",
    DE_REASON_nodisenchant = "这件物品不能分解",
    DE_REASON_noband = "没有这个物品等级的分解数据",
    DE_Q2 = "优秀", DE_Q3 = "精良", DE_Q4 = "史诗",
    DE_CLASS2 = "武器", DE_CLASS4 = "护甲",
    DE_BAND = "%s%s，物品等级 %d-%d",
    DE_NOW_MEASURED = "%s：已记录你自己的 %d 次分解，改用实际结果（不再是估算）。",
  },
  zhTW = {
    DE_REASON_loading = "正在讀取物品資訊…",
    DE_REASON_notgear = "不是護甲或武器",
    DE_REASON_quality = "只有綠色、藍色和紫色物品可以分解",
    DE_REASON_nodisenchant = "這件物品不能分解",
    DE_REASON_noband = "沒有這個物品等級的分解資料",
    DE_Q2 = "優秀", DE_Q3 = "精良", DE_Q4 = "史詩",
    DE_CLASS2 = "武器", DE_CLASS4 = "護甲",
    DE_BAND = "%s%s，物品等級 %d-%d",
    DE_NOW_MEASURED = "%s：已記錄你自己的 %d 次分解，改用實際結果（不再是估算）。",
  },
})

local L = WC.L

-- the data table (DataDisenchant.lua); stay usable if it failed to load
local DE = WC.DE
if type(DE) ~= "table" then DE = {}; WC.DE = DE end
DE.spell = DE.spell or 13262
DE.bands = DE.bands or {}
DE.noDE = DE.noDE or {}
if not DE.mats then
  local m = {}
  for _, b in ipairs(DE.bands) do
    for _, o in ipairs(b.out or {}) do m[o[1]] = true end
  end
  DE.mats = m
end

DE.MEASURED_MIN = 20   -- default of the setting deMeasuredCasts: casts per band before measured odds replace the estimate
if WC.Store and WC.Store.Default then WC.Store:Default("deMeasuredCasts", DE.MEASURED_MIN) end

-- read at use time, so changing the setting takes effect without a reload
local function measuredMin()
  local n = type(GetrichDB) == "table" and tonumber(GetrichDB.deMeasuredCasts)
  if n and n >= 1 then return math.floor(n) end
  return DE.MEASURED_MIN
end
DE.MeasuredMin = function() return measuredMin() end
DE.WINDOW = 5          -- seconds between the end of the cast and its loot

local LOCK_BEFORE = 2  -- a bag item locked this many seconds before the cast was sent may be its target
local CAST_MAX = 12    -- a cast still "casting" after this many seconds is stale
local WAIT_BAGS = 3    -- seconds to wait for the bag update that shows which item was used up

local pairs, ipairs, tonumber, type, pcall = pairs, ipairs, tonumber, type, pcall

-- ---------------------------------------------------------------------------
-- bands

-- equip slots that are never disenchantable even on armor/weapon items
local NOT_GEAR_SLOT = { [""] = true, INVTYPE_BODY = true, INVTYPE_TABARD = true,
  INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true }

local index, indexedFrom   -- [q * 100 + class] = { band rows }
local function bandIndex()
  if index and indexedFrom == DE.bands then return index end
  index, indexedFrom = {}, DE.bands
  for _, b in ipairs(DE.bands) do
    if b.q and b.class and b.lo and b.hi then
      local k = b.q * 100 + b.class
      local list = index[k]
      if not list then list = {}; index[k] = list end
      list[#list + 1] = b
    end
  end
  return index
end

local keyOf = setmetatable({}, { __mode = "k" })
local function bandKey(b)
  local k = keyOf[b]
  if not k then
    k = b.q .. ":" .. b.class .. ":" .. b.lo .. "-" .. b.hi
    keyOf[b] = k
  end
  return k
end

-- classID, equipLoc without needing the item cache
local function instantClass(itemID)
  local fn = C_Item and C_Item.GetItemInfoInstant
  if not fn then return nil end
  local ok, id, _, _, equipLoc, _, classID = pcall(fn, itemID)
  if ok and id then return classID, equipLoc end
end

function DE:Band(itemID, ilvl)
  itemID = tonumber(itemID)
  if not itemID then return nil, "notgear" end
  local name, _, quality, itemLevel, _, _, _, _, equipLoc, _, _, classID = WC.ItemInfo(itemID)
  if not name then
    local c, loc = instantClass(itemID)
    if c and ((c ~= 2 and c ~= 4) or NOT_GEAR_SLOT[loc or ""]) then return nil, "notgear" end
    if DE.noDE[itemID] then return nil, "nodisenchant" end
    WC.RequestItem(itemID)
    return nil, "loading"
  end
  if (classID ~= 2 and classID ~= 4) or NOT_GEAR_SLOT[equipLoc or ""] then return nil, "notgear" end
  if not quality or quality < 2 or quality > 4 then return nil, "quality" end
  if DE.noDE[itemID] then return nil, "nodisenchant" end
  local lvl = tonumber(ilvl)
  if not lvl or lvl <= 0 then lvl = itemLevel end
  local list = lvl and bandIndex()[quality * 100 + classID]
  if list then
    for i = 1, #list do
      local b = list[i]
      if lvl >= b.lo and lvl <= b.hi then return b end
    end
  end
  return nil, "noband"
end

function DE:BandKey(band) return band and bandKey(band) end

function DE:BandLabel(band)
  if not band then return "" end
  return (L.DE_BAND or "%s %s, %d-%d"):format(L["DE_Q" .. band.q] or tostring(band.q),
    L["DE_CLASS" .. band.class] or tostring(band.class), band.lo, band.hi)
end

function DE:ReasonText(reason)
  return reason and (L["DE_REASON_" .. reason] or reason) or ""
end

-- ---------------------------------------------------------------------------
-- expected output per cast

local samples          -- GetrichDB.deSamples (after DB_READY)
local expCache = {}    -- [band] = { list, measured, casts }; cleared when a sample is recorded

WC:On("DB_READY", function()
  local db = GetrichDB
  if type(db) ~= "table" then return end
  if type(db.deSamples) ~= "table" then db.deSamples = {} end
  samples = db.deSamples
  expCache = {}
end)
WC:On("SETTINGS_CHANGED", function() expCache = {} end)   -- deMeasuredCasts may have changed

-- positional fields follow SPEC §3.6 literally ({ itemID, chance, min, max }), named fields are the same values
local function entry(id, qty, chance, mn, mx)
  return { id, chance, mn, mx, itemID = id, qty = qty, chance = chance, min = mn, max = mx }
end

function DE:Expected(band)
  if not band then return {}, false, 0 end
  local c = expCache[band]
  if c then return c[1], c[2], c[3] end
  local rec = samples and samples[bandKey(band)]
  local casts = (rec and tonumber(rec.casts)) or 0
  local list, measured = {}, false
  if casts >= measuredMin() and type(rec.qty) == "table" then
    measured = true
    local hit, mins, maxs = rec.hit or {}, rec.min or {}, rec.max or {}
    local seen = {}
    for _, o in ipairs(band.out or {}) do
      local id = o[1]
      seen[id] = true
      local total = rec.qty[id] or 0
      if total > 0 then
        list[#list + 1] = entry(id, total / casts, (hit[id] or 0) / casts, mins[id] or o[3], maxs[id] or o[4])
      end
    end
    local extra = {}   -- outputs the server gave that the estimate does not know
    for id, total in pairs(rec.qty) do
      if not seen[id] and total > 0 then extra[#extra + 1] = id end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do
      list[#list + 1] = entry(id, rec.qty[id] / casts, (hit[id] or 0) / casts, mins[id], maxs[id])
    end
  else
    for _, o in ipairs(band.out or {}) do
      local id, chance, mn = o[1], o[2] or 0, o[3] or 1
      local mx = o[4] or mn
      list[#list + 1] = entry(id, chance * (mn + mx) / 2, chance, mn, mx)
    end
  end
  expCache[band] = { list, measured, casts }
  return list, measured, casts
end

-- ---------------------------------------------------------------------------
-- value at current AH prices

local function unitPrice(itemID)
  if not WC.UnitPrice then return nil end
  local ok, unit, t = pcall(WC.UnitPrice, WC, itemID)
  if ok and type(unit) == "number" then return unit, t end
end

local function enchantingSkill()
  if not WC.EnchantingSkill then return 0 end
  local ok, s = pcall(WC.EnchantingSkill, WC)
  return (ok and tonumber(s)) or 0
end

-- value = sum of expected qty x unit price x (1 - AH cut), from the priced outputs only (partial if any is missing)
function DE:Value(itemID, ilvl)
  local band, reason = self:Band(itemID, ilvl)
  if not band then return nil, reason end
  local list, measured, casts = self:Expected(band)
  local keep = 1 - (WC.AH_CUT or 0.05)
  local parts, missing, total, oldest = {}, {}, 0, nil
  for i = 1, #list do
    local e = list[i]
    local p = { e.itemID, e.qty, itemID = e.itemID, qty = e.qty, chance = e.chance, min = e.min, max = e.max }
    local unit, t = unitPrice(e.itemID)
    if unit then
      local v = e.qty * unit * keep
      p[3], p[4], p.unit, p.value = unit, v, unit, v
      total = total + v
      if t and (not oldest or t < oldest) then oldest = t end
    else
      missing[#missing + 1] = e.itemID
    end
    parts[i] = p
  end
  local skill = band.skill or 1
  return {
    value = total, parts = parts, missing = missing, partial = #missing > 0, priced = #list - #missing,
    measured = measured, casts = casts, band = band, bandKey = bandKey(band),
    skill = skill, skillOK = enchantingSkill() >= skill, time = oldest,
  }
end

-- ---------------------------------------------------------------------------
-- recorded samples

local function chat(msg)
  if WC.Print then pcall(WC.Print, WC, msg)
  elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(msg) end
end

-- totals = { [matItemID] = quantity looted from one cast }
function DE:AddSample(band, totals)
  if not samples or not band or type(totals) ~= "table" then return false end
  local key = bandKey(band)
  local rec = samples[key]
  if type(rec) ~= "table" then
    rec = { casts = 0, qty = {}, hit = {}, min = {}, max = {} }
    samples[key] = rec
  end
  rec.qty, rec.hit = rec.qty or {}, rec.hit or {}
  rec.min, rec.max = rec.min or {}, rec.max or {}
  rec.casts = (rec.casts or 0) + 1
  for id, q in pairs(totals) do
    rec.qty[id] = (rec.qty[id] or 0) + q
    rec.hit[id] = (rec.hit[id] or 0) + 1
    if not rec.min[id] or q < rec.min[id] then rec.min[id] = q end
    if not rec.max[id] or q > rec.max[id] then rec.max[id] = q end
  end
  rec.t = time and time() or nil
  expCache = {}
  if rec.casts == measuredMin() then
    chat((L.DE_NOW_MEASURED or "%s: %d"):format(self:BandLabel(band), rec.casts))
  end
  WC:Fire("DE_UPDATED", key)
  return true
end

function DE:ClearSamples(key)
  if not samples then return end
  if key then samples[key] = nil else for k in pairs(samples) do samples[k] = nil end end
  expCache = {}
  WC:Fire("DE_UPDATED", key)
end

function DE:Samples()
  local out = {}
  if not samples then return out end
  local need = measuredMin()
  local byKey = {}
  for _, b in ipairs(DE.bands) do
    if b.q and b.class and b.lo and b.hi then byKey[bandKey(b)] = b end
  end
  for key, rec in pairs(samples) do
    if type(rec) == "table" then
      local q, class, lo, hi = tostring(key):match("^(%d+):(%d+):(%d+)%-(%d+)$")
      local casts = tonumber(rec.casts) or 0
      local outputs = {}
      for id, total in pairs(rec.qty or {}) do
        local hits = (rec.hit and rec.hit[id]) or 0
        outputs[#outputs + 1] = { itemID = id, total = total, hits = hits,
          qty = casts > 0 and total / casts or 0, chance = casts > 0 and hits / casts or 0,
          min = rec.min and rec.min[id], max = rec.max and rec.max[id] }
      end
      table.sort(outputs, function(a, b) return a.qty > b.qty end)
      local band = byKey[key]
      out[#out + 1] = { key = key, band = band, q = tonumber(q), class = tonumber(class), lo = tonumber(lo),
        hi = tonumber(hi), casts = casts, measured = casts >= need,
        need = math.max(0, need - casts), outputs = outputs, t = rec.t,
        label = band and self:BandLabel(band) or key }
    end
  end
  table.sort(out, function(a, b)
    if (a.q or 0) ~= (b.q or 0) then return (a.q or 0) < (b.q or 0) end
    if (a.class or 0) ~= (b.class or 0) then return (a.class or 0) > (b.class or 0) end
    return (a.lo or 0) < (b.lo or 0)
  end)
  return out
end

-- ---------------------------------------------------------------------------
-- sampling the player's own disenchants
--
-- Target item: the bag slot that became locked (ITEM_LOCK_CHANGED + C_Container.GetContainerItemInfo().isLocked,
-- the same pair the default ContainerFrame uses) between LOCK_BEFORE seconds before the cast was sent and the end
-- of the cast. Exactly one such item must remain (an item unlocked while still in the bag was only moved). If that
-- is not unique, fall back to the bag contents: exactly one disenchantable item must have disappeared since the
-- cast started. Otherwise the sample is dropped (never guessed).
-- Loot: the first loot window that opens while the cast is running (auto-loot can be faster than
-- UNIT_SPELLCAST_SUCCEEDED) or within DE.WINDOW seconds after it. Every slot must be a known disenchant material.

local casts = {}       -- [castGUID] = { guid, t, state = "casting"|"ok", tOK, seen = {[key] = lock}, before, target, session }
local locks = {}       -- [bag * 1000 + slot] = { id, link, bag, slot, key, t }: disenchantable bag items now locked
local session          -- the loot window currently open
local waiters = {}     -- [cast] = true: casts waiting for BAG_UPDATE_DELAYED to identify the used-up item
local frame = CreateFrame("Frame")

local function now() return (GetTime and GetTime()) or 0 end

local spellIs = {}
local function isDE(spellID)
  if spellID == nil then return false end
  local v = spellIs[spellID]
  if v ~= nil then return v end
  v = (spellID == DE.spell) or (type(DE.spells) == "table" and DE.spells[spellID] and true) or false
  if not v and C_Spell and C_Spell.GetSpellName then
    -- same name as Disenchant (in case this client uses another spell ID for it)
    local ok1, a = pcall(C_Spell.GetSpellName, spellID)
    local ok2, b = pcall(C_Spell.GetSpellName, DE.spell)
    v = (ok1 and ok2 and type(a) == "string" and a ~= "" and a == b) or false
  end
  spellIs[spellID] = v
  return v
end

local function slotInfo(bag, slot)
  local fn = C_Container and C_Container.GetContainerItemInfo
  if not fn then return nil end
  local ok, info = pcall(fn, bag, slot)
  if ok and type(info) == "table" then return info end
end

-- could this bag item be disenchanted? (cheap; works without the item cache)
local function deGear(itemID, quality)
  if not itemID or DE.noDE[itemID] then return false end
  if not quality then
    local _, _, q = WC.ItemInfo(itemID)
    quality = q
  end
  if quality and (quality < 2 or quality > 4) then return false end
  local c, loc = instantClass(itemID)
  if c ~= 2 and c ~= 4 then return false end
  return not NOT_GEAR_SLOT[loc or ""]
end

-- disenchantable items in the bags: { [itemID] = count }
local function gearCounts()
  local counts = {}
  local numSlots = C_Container and C_Container.GetContainerNumSlots
  if not numSlots then return counts end
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    local ok, n = pcall(numSlots, bag)
    for slot = 1, (ok and tonumber(n)) or 0 do
      local info = slotInfo(bag, slot)
      if info and info.itemID and deGear(info.itemID, info.quality) then
        counts[info.itemID] = (counts[info.itemID] or 0) + 1
      end
    end
  end
  return counts
end

-- the one disenchantable item that left the bags since the cast started, or nil
local function vanished(c)
  if not c.before then return nil end
  local current = gearCounts()
  local gone, n = nil, 0
  for id, cnt in pairs(c.before) do
    local d = cnt - (current[id] or 0)
    if d > 0 then n = n + d; gone = id end
  end
  if n == 1 then return gone end
end

local function finish(c, ok, reason)
  c.done = true
  waiters[c] = nil
  if not next(waiters) then frame:UnregisterEvent("BAG_UPDATE_DELAYED") end
  if c.session and not ok then c.session.ignored = true end
  casts[c.guid] = nil
  if c.state == "ok" then
    local t = c.target
    DE.lastSample = { ok = ok, reason = reason, itemID = type(t) == "table" and t.id or nil,
      via = type(t) == "table" and t.via or nil, key = c.key, t = time and time() or nil }
  end
end

local function record(c)
  local band, why = c.target.band, nil
  if not band then band, why = DE:Band(c.target.id) end
  if not band then return finish(c, false, why or "noband") end
  c.key = bandKey(band)
  if not samples then return finish(c, false, "nodb") end
  DE:AddSample(band, c.totals)
  finish(c, true)
end

local tryCommit

local function startWait(c)
  c.waiting, c.waitStart = true, now()
  waiters[c] = true
  frame:RegisterEvent("BAG_UPDATE_DELAYED")
  local function timeout()
    if c.done or not c.waiting then return end
    local id = vanished(c)
    if id then
      c.waiting = false
      c.target = { id = id, via = "bags" }
      return record(c)
    end
    -- the item may stay in the bags until a manual loot window closes
    if c.session and not c.session.closed and now() - c.waitStart < 60 and C_Timer then
      return C_Timer.After(2, timeout)
    end
    finish(c, false, "notarget")
  end
  if C_Timer and C_Timer.After then C_Timer.After(WAIT_BAGS, timeout) else timeout() end
end

local function onBagsSettled()
  for c in pairs(waiters) do
    if not c.done and c.waiting then
      local id = vanished(c)
      if id then
        c.waiting = false
        c.target = { id = id, via = "bags" }
        record(c)
      end
    end
  end
end

tryCommit = function(c)
  if c.done or c.waiting or c.state ~= "ok" then return end
  local s = c.session
  if not s or not s.final then return end
  local bad = s.bad
  local totals, n = {}, 0
  if not bad then
    for _, it in pairs(s.items) do
      if not DE.mats[it[1]] then bad = "notmat"; break end
      totals[it[1]] = (totals[it[1]] or 0) + it[2]
      n = n + 1
    end
  end
  if not bad and n == 0 then bad = "empty" end
  if bad then return finish(c, false, bad) end
  c.totals = totals
  if type(c.target) ~= "table" then
    local id = vanished(c)
    if not id then return startWait(c) end
    c.target = { id = id, via = "bags" }
  end
  record(c)
end

local function newCast(guid, withSnapshot)
  local t = now()
  for g, o in pairs(casts) do   -- forget stale casts
    if o.done or t - (o.tOK or o.t) > 30 then casts[g] = nil; waiters[o] = nil end
  end
  local c = { guid = guid, t = t, state = "casting", seen = {} }
  for key, lk in pairs(locks) do
    if lk.t >= t - LOCK_BEFORE then c.seen[key] = lk end
  end
  if withSnapshot then c.before = gearCounts() end
  casts[guid] = c
  return c
end

-- at the end of the cast: the one locked item left among those seen during the cast
local function decideTarget(c)
  if type(c.target) == "table" then return end
  local cand, n = nil, 0
  for _, lk in pairs(c.seen) do
    local info = slotInfo(lk.bag, lk.slot)
    -- still in that slot but unlocked = it was only moved, not disenchanted
    if not (info and info.itemID == lk.id and not info.isLocked) then
      n = n + 1
      cand = lk
    end
  end
  if n == 1 then
    c.target = { id = cand.id, link = cand.link, via = "lock" }
    c.target.band = DE:Band(cand.id)
    locks[cand.key] = nil                     -- used up: never the target of a later cast
    for _, o in pairs(casts) do if o ~= c then o.seen[cand.key] = nil end end
  else
    c.target = false                          -- unknown or ambiguous: tryCommit falls back to the bag contents
  end
end

local function onLock(bag, slot)
  if not bag or not slot then return end      -- equipment slots (slot nil) can't be disenchanted
  local key = bag * 1000 + slot
  local info = slotInfo(bag, slot)
  if info and info.isLocked and deGear(info.itemID, info.quality) then
    local lk = locks[key]
    if not lk or lk.id ~= info.itemID then
      lk = { id = info.itemID, link = info.hyperlink, bag = bag, slot = slot, key = key, t = now() }
      locks[key] = lk
    end
    for _, c in pairs(casts) do
      if c.state == "casting" and not c.done then c.seen[key] = lk end
    end
  else
    local lk = locks[key]
    locks[key] = nil
    if lk and info and info.itemID == lk.id then
      -- unlocked but still there: not the target of a running cast
      for _, c in pairs(casts) do
        if c.state == "casting" then c.seen[key] = nil end
      end
    end
  end
end

-- which cast does a loot window that opens now belong to?
local function castForLoot(t)
  local best, bestOK
  for _, c in pairs(casts) do
    if not c.done and not c.session then
      if c.state == "ok" and t - c.tOK <= DE.WINDOW then
        if not bestOK or c.tOK > bestOK.tOK then bestOK = c end
      elseif c.state == "casting" and t - c.t <= CAST_MAX then
        if not best or c.t > best.t then best = c end
      end
    end
  end
  return bestOK or best
end

local function readLoot(s)
  local n = (GetNumLootItems and GetNumLootItems()) or 0
  for i = 1, n do
    if not s.items[i] then
      local link = GetLootSlotLink and GetLootSlotLink(i)
      -- texture, item, quantity, currencyID, itemQuality, locked, isQuestItem, questID, isActive, isCoin
      local _, _, qty, currencyID, _, _, _, _, _, isCoin = GetLootSlotInfo(i)
      local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
      if isCoin or currencyID then
        s.bad = "notitem"
      elseif id and qty and qty > 0 then
        s.items[i] = { id, qty }
      elseif qty and qty > 0 then
        s.bad = "unknown"                     -- an item we can't identify: can't prove it's all materials
      end
      if GetLootSourceInfo then
        local ok, guid = pcall(GetLootSourceInfo, i)
        if ok and type(guid) == "string" and (guid:find("^Creature") or guid:find("^GameObject") or guid:find("^Vehicle")) then
          s.bad = "source"                    -- mob / chest / herb loot, not a disenchant
        end
      end
    end
  end
end

local function onLoot(final)
  local t = now()
  if not session or session.closed then
    session = { t = t, items = {} }
    local c = castForLoot(t)
    if c then session.cast = c; c.session = session else session.ignored = true end
  end
  local s = session
  if s.ignored then return end                -- ordinary looting: no work
  local ok = pcall(readLoot, s)
  if not ok then s.bad = "error" end
  if final then s.final = true end
  if s.cast then tryCommit(s.cast) end
end

local H = {}
H.UNIT_SPELLCAST_SENT = function(unit, _, guid, spellID)        -- unit, target, castGUID, spellID
  if unit == "player" and isDE(spellID) then newCast(guid or "?", false) end
end
H.UNIT_SPELLCAST_START = function(unit, guid, spellID)
  if unit ~= "player" or not isDE(spellID) then return end
  guid = guid or "?"
  local c = casts[guid]
  if not c then c = newCast(guid, true) elseif not c.before then c.before = gearCounts() end
end
H.UNIT_SPELLCAST_SUCCEEDED = function(unit, guid, spellID)
  if unit ~= "player" or not isDE(spellID) then return end
  guid = guid or "?"
  local c = casts[guid] or newCast(guid, false)
  if c.state ~= "casting" then return end
  c.state, c.tOK = "ok", now()
  decideTarget(c)
  local s = c.session
  if s and c.tOK - s.t > DE.WINDOW then
    s.ignored, s.cast, c.session = true, nil, nil
  end
  tryCommit(c)
end
local function stopped(unit, guid)
  if unit ~= "player" then return end
  local c = casts[guid or "?"]
  if c and c.state == "casting" then finish(c, false, "failed") end
end
H.UNIT_SPELLCAST_FAILED = stopped
H.UNIT_SPELLCAST_FAILED_QUIET = stopped
H.UNIT_SPELLCAST_INTERRUPTED = stopped
H.ITEM_LOCK_CHANGED = onLock
H.LOOT_READY = function() onLoot(false) end
H.LOOT_OPENED = function() onLoot(true) end
H.LOOT_CLOSED = function()
  local s = session
  session = nil
  if not s then return end
  s.closed = true
  if not s.ignored then
    s.final = true
    if s.cast then tryCommit(s.cast) end
  end
end
H.BAG_UPDATE_DELAYED = onBagsSettled

frame:SetScript("OnEvent", function(_, event, ...)
  local fn = H[event]
  if not fn then return end
  local ok, err = pcall(fn, ...)
  if not ok and WC.Debug then pcall(WC.Debug, "DE " .. event, err) end
end)

for _, ev in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
  if not (frame.RegisterUnitEvent and pcall(frame.RegisterUnitEvent, frame, ev, "player")) then
    pcall(frame.RegisterEvent, frame, ev)
  end
end
for _, ev in ipairs({ "ITEM_LOCK_CHANGED", "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED" }) do
  pcall(frame.RegisterEvent, frame, ev)
end
