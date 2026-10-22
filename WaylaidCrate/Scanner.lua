local addonName, WC = ...

-- Auction House scanner.
--
-- A scan "kind" is an ordered list of phases. Each phase is evaluated only when it is reached, so a later
-- phase can depend on what an earlier one found (writs: requested items of the writs for sale).
--   search phase: one C_AuctionHouse.SendSearchQuery per item. Blizzard: "restricted to 100 calls per minute",
--                 so queries are paced 0.7 s apart and only sent when IsThrottledMessageSystemReady().
--   browse phase: C_AuctionHouse.SendBrowseQuery, then RequestMoreBrowseResults() until HasFullBrowseResults().
-- Every answer is recorded the moment it arrives (prices + history), so a stopped scan keeps what it got.
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
    SCAN_NO_API = "This client has no Auction House search API, so it can't scan.",
    SCAN_UNKNOWN_KIND = "There is nothing to scan for this tab.",
    SCAN_PAGE_FMT = "page %d · %d items",
    SCAN_KIND_CRATES = "crates",
    SCAN_KIND_WRITS = "writs",
    SCAN_KIND_FLIPS = "vendor flips",
    SCAN_KIND_DE = "disenchanting",
    SCAN_KIND_HISTORY = "watched items",
    SCAN_PH_CRATES = "crates and materials",
    SCAN_PH_WRITS = "Craftsman's Writs",
    SCAN_PH_WRIT_ITEMS = "requested items",
    SCAN_PH_BROWSE_ALL = "all listings",
    SCAN_PH_FLIP_CHECK = "checking cheap listings",
    SCAN_PH_DE_MATS = "enchanting materials",
    SCAN_PH_DE_GEAR = "green, blue and purple gear",
    SCAN_PH_WATCHED = "watched items",
    SCAN_PH_WAIT_ITEMS = "loading item data",
    SCAN_WAIT_ITEMS_FMT = "loading item data · %d left",
    HIST_NOTHING_WATCHED = "No watched items yet. Mark items with |A:auctionhouse-icon-favorite:12:12|a on the Prices tab first.",
  },
  zhCN = {
    SCAN_OPEN_AH_FIRST = "请先打开拍卖行。",
    SCAN_NO_API = "这个客户端没有拍卖行搜索接口，无法扫描。",
    SCAN_UNKNOWN_KIND = "这一页没有可扫描的内容。",
    SCAN_PAGE_FMT = "第 %d 页 · %d 种物品",
    SCAN_KIND_CRATES = "箱子",
    SCAN_KIND_WRITS = "Writ",
    SCAN_KIND_FLIPS = "倒卖",
    SCAN_KIND_DE = "附魔分解",
    SCAN_KIND_HISTORY = "关注物品",
    SCAN_PH_CRATES = "箱子和材料",
    SCAN_PH_WRITS = "Craftsman's Writ",
    SCAN_PH_WRIT_ITEMS = "需求物品",
    SCAN_PH_BROWSE_ALL = "全部拍卖",
    SCAN_PH_FLIP_CHECK = "核对低价物品",
    SCAN_PH_DE_MATS = "附魔材料",
    SCAN_PH_DE_GEAR = "绿色、蓝色和紫色装备",
    SCAN_PH_WATCHED = "关注物品",
    SCAN_PH_WAIT_ITEMS = "读取物品信息",
    SCAN_WAIT_ITEMS_FMT = "读取物品信息 · 还剩 %d 个",
    HIST_NOTHING_WATCHED = "还没有关注的物品。请先在“走势”页用 |A:auctionhouse-icon-favorite:12:12|a 标记物品。",
  },
  zhTW = {
    SCAN_OPEN_AH_FIRST = "請先打開拍賣場。",
    SCAN_NO_API = "這個用戶端沒有拍賣場搜尋介面，無法掃描。",
    SCAN_UNKNOWN_KIND = "這一頁沒有可掃描的內容。",
    SCAN_PAGE_FMT = "第 %d 頁 · %d 種物品",
    SCAN_KIND_CRATES = "箱子",
    SCAN_KIND_WRITS = "Writ",
    SCAN_KIND_FLIPS = "倒賣",
    SCAN_KIND_DE = "附魔分解",
    SCAN_KIND_HISTORY = "關注物品",
    SCAN_PH_CRATES = "箱子和材料",
    SCAN_PH_WRITS = "Craftsman's Writ",
    SCAN_PH_WRIT_ITEMS = "需求物品",
    SCAN_PH_BROWSE_ALL = "全部拍賣",
    SCAN_PH_FLIP_CHECK = "核對低價物品",
    SCAN_PH_DE_MATS = "附魔材料",
    SCAN_PH_DE_GEAR = "綠色、藍色和紫色裝備",
    SCAN_PH_WATCHED = "關注物品",
    SCAN_PH_WAIT_ITEMS = "讀取物品資訊",
    SCAN_WAIT_ITEMS_FMT = "讀取物品資訊 · 還剩 %d 個",
    HIST_NOTHING_WATCHED = "還沒有關注的物品。請先在「走勢」頁用 |A:auctionhouse-icon-favorite:12:12|a 標記物品。",
  },
})
-- |A:auctionhouse-icon-favorite| = the AH favorite star atlas (Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRecipeSchematicForm.xml:45,
-- Blizzard_Professions/Blizzard_ProfessionsCrafterOrderPage.lua:105); the ★ glyph may not exist in the enUS font.
local L = WC.L

local Scanner = {
  active = false,
  kind = nil,
  -- [itemID] = { status = "listed"|"none"|"timeout", entries = { {unit, qty}, ... } cheapest first, min, avail, time }
  -- (replaced by WaylaidCrateDB.results in Store:Init)
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
local BROWSE_TIMEOUT   = 10    -- seconds to wait for a browse page
local BROWSE_MAX_PAGES = 60
local BROWSE_MAX_TIME  = 240   -- seconds per browse phase
local FIRE_INTERVAL    = 0.25  -- PRICES_UPDATED at most 4 times a second
local ITEM_MORE_PAGES  = 4     -- extra result pages per non-commodity item (RequestMoreItemSearchResults)
local WAIT_POLL        = 0.5   -- wait phases re-check this often

local AH_FILTER = (Enum and Enum.AuctionHouseFilter) or {}   -- AHE:70-91
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

-- Blizzard's default sort for every browse context: Price, then Name, both ascending
-- (AHUI/Shared/Blizzard_AuctionHouseFrame.lua:197-199; at most 2 sorts, :141).
local function BrowseSorts()
  return { { sortOrder = SORT.Price or 0, reverseSort = false }, { sortOrder = SORT.Name or 1, reverseSort = false } }
end

-- The query Blizzard sends when you press Search with an empty box and default filters:
-- SearchBar:StartSearch (AHUI/Shared/Blizzard_AuctionHouseSearchBar.lua:203-207) -> AuctionHouseFrame:SendBrowseQuery
-- -> SendBrowseQueryInternal (AHUI/Shared/Blizzard_AuctionHouseFrame.lua:794-823). Defaults: level range 0-0
-- (SearchBar.lua:3-7); filters = the filters that are on by default, i.e. the 7 quality filters
-- (AHUI/Mainline/Blizzard_AuctionHouseUtil.lua:21-33, turned into an array by CalculateFiltersArray, SearchBar.lua:98-106);
-- itemClassFilters = nil when no category is selected (AHUI/Shared/Blizzard_AuctionHouseCategoriesList.lua:180-187).
-- Query struct: AuctionHouseBrowseQuery {searchString, sorts, minLevel?, maxLevel?, filters?, itemClassFilters?} (AHD:1539).
function Scanner.FullBrowseQuery()
  return {
    searchString = "", minLevel = 0, maxLevel = 0, sorts = BrowseSorts(),
    filters = { AH_FILTER.PoorQuality or 6, AH_FILTER.CommonQuality or 7, AH_FILTER.UncommonQuality or 8,
                AH_FILTER.RareQuality or 9, AH_FILTER.EpicQuality or 10, AH_FILTER.LegendaryQuality or 11,
                AH_FILTER.ArtifactQuality or 12 },
  }
end

-- Gear that can be disenchanted: uncommon / rare / epic quality filters, weapons + armor.
-- AuctionHouseItemClassFilter = {classID, subClassID?, inventoryType?} (AHD:1561); a class-only filter is what
-- Blizzard itself uses for the Quest Items / Miscellaneous categories (AHUI/Camelot/Blizzard_AuctionData.lua:209,214).
function Scanner.GearBrowseQuery()
  return {
    searchString = "", minLevel = 0, maxLevel = 0, sorts = BrowseSorts(),
    filters = { AH_FILTER.UncommonQuality or 8, AH_FILTER.RareQuality or 9, AH_FILTER.EpicQuality or 10 },
    itemClassFilters = { { classID = ITEM_CLASS.Weapon or 2 }, { classID = ITEM_CLASS.Armor or 4 } },
  }
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

local function HasFullBrowse()
  if not C_AuctionHouse.HasFullBrowseResults then return false end
  local ok, full = pcall(C_AuctionHouse.HasFullBrowseResults)
  return ok and full == true
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
--   { type = "search", items = function() return { itemID, ... } end, label = "..." | function }
--   { type = "browse", query = function() return AuctionHouseBrowseQuery end, scope = "full"|"gear", label = ... }
--   { type = "wait", ["until"] = function() return done, progressLabel end, timeout = 20, label = ... }
--       ("until" is a Lua keyword, so the field is written ["until"]; `check` is accepted too.) Polls every 0.5 s while
--       the scan runs and ends when done is true or after timeout seconds; skipped if already done when reached.

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
  self:HookBrowse()
  self.kind, self.def = kind, def
  self.active = true
  self.token = self.token + 1
  self.startedAt = GetTime()
  self.listed, self.missing, self.browsed = 0, 0, nil
  self.searched = {}
  self.phase, self.phaseCount = 0, #def.phases
  self.index, self.total = 0, 0
  self.current, self.browse, self.queue, self.wait = nil, nil, nil, nil
  local hasWork = self:AdvancePhase()
  local total = 0
  if hasWork then total = self.total end   -- nil when the first phase is a browse (unknown size)
  UICall("OnScanStart", kind, total)
  if hasWork then self:BeginPhase() else self:Finish() end
  return true
end

function Scanner:Stop(reason)
  if not self.active then return end
  local br = self.browse
  local done, total
  if br then done, total = br.pages, nil else done, total = math.max((self.index or 1) - 1, 0), self.total end
  self.active = false
  self:CancelTimer()
  self.token = self.token + 1
  if br then self.browsed = (self.browsed or 0) + br.items end
  if self.listed + self.missing > 0 or self.browsed then WC:DB().scannedAt[self.kind] = time() end
  self.current, self.browse, self.queue, self.wait = nil, nil, nil, nil
  self:FlushPrices()
  UICall("OnScanStopped", self.kind, reason, done, total)
end

function Scanner:Finish()
  self.active = false
  self:CancelTimer()
  self.token = self.token + 1
  self.current, self.browse, self.queue, self.wait = nil, nil, nil, nil
  if self.listed + self.missing > 0 or self.browsed then WC:DB().scannedAt[self.kind] = time() end
  self:FlushPrices()
  UICall("OnScanDone", self.kind, {
    total = self.listed + self.missing, listed = self.listed, missing = self.missing,
    seconds = GetTime() - (self.startedAt or GetTime()), browsed = self.browsed,
  })
end

-- Moves to the next phase that has work. Returns false when no phase is left.
function Scanner:AdvancePhase()
  while true do
    self.phase = self.phase + 1
    local spec = self.def.phases[self.phase]
    if not spec then return false end
    if self:PreparePhase(spec) then return true end
  end
end

function Scanner:PreparePhase(spec)
  self.current, self.browse, self.queue, self.wait = nil, nil, nil, nil
  self.index = 0
  if spec.type == "wait" then
    local check = spec["until"] or spec.check
    if type(check) ~= "function" then return false end
    local ok, done = pcall(check)
    if not ok or done then return false end   -- nothing to wait for
    self.wait = { check = check, timeout = tonumber(spec.timeout) or 20, startedAt = GetTime() }
    self.total = nil
    return true
  end
  if spec.type == "browse" then
    if not (C_AuctionHouse.SendBrowseQuery and C_AuctionHouse.GetBrowseResults) then return false end
    local scope = (spec.scope == "gear") and "gear" or "full"
    local query
    if spec.query then
      local ok, q = pcall(spec.query)
      if ok then query = q end
    else
      query = (scope == "gear") and Scanner.GearBrowseQuery() or Scanner.FullBrowseQuery()
    end
    if type(query) ~= "table" then return false end
    self.browse = { scope = scope, query = query, seen = {}, rows = {},
                    pages = 0, items = 0, tries = 0, state = "pending", startedAt = GetTime() }
    self.total = nil
    return true
  end
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
  local spec = self.def.phases[self.phase]
  UICall("OnScanPhase", self.kind, self.phase, self.phaseCount, Text(spec.label))
  if self.browse then
    self:BrowseTrySend()
  elseif self.wait then
    self:WaitTick()
  else
    self:Next()
  end
end

function Scanner:PhaseDone()
  self.current, self.browse, self.queue, self.wait = nil, nil, nil, nil
  if self:AdvancePhase() then
    self:BeginPhase()
  else
    self:Finish()
  end
end

-- wait phase: poll until the condition holds (or the timeout), then go on with what is there
function Scanner:WaitTick()
  local w = self.wait
  if not self.active or not w then return end
  local ok, done, label = pcall(w.check)
  if not ok then
    Debug("wait", done)
    done = true
  end
  if done or GetTime() - w.startedAt >= w.timeout then
    self.wait = nil
    self:PhaseDone()
    return
  end
  UICall("OnScanProgress", self.kind, 0, nil, label)
  self:Schedule(WAIT_POLL, self.WaitTick)
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
-- Blizzard searches the exact key of the browse row the user picked (SelectBrowseResult -> QueryItem,
-- AHUI/Shared/Blizzard_AuctionHouseFrame.lua:683-752), so the key of the cheapest variant the browse reported is used.
-- 1.3.0 searched MakeItemKey(itemID) (level 0), proven for crates and writs: for gear without a suffix, the other
-- level (0 / the item's level) is tried once when the first key finds nothing. Random-suffix gear has no fallback.
function Scanner:KeyFor(cur)
  local id = cur.itemID
  local b = WC:DB().browse.items[id]
  local lvl, sfx = tonumber(b and b.ilvl) or 0, tonumber(b and b.sfx) or 0
  cur.altLevel = nil
  if lvl > 0 or sfx > 0 then
    if sfx == 0 then cur.altLevel = 0 end
    return MakeKey(id, lvl, sfx)
  end
  if IsWeaponOrArmor(id) and WC.ItemInfo then
    local _, _, _, ilvl = WC.ItemInfo(id)
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
  local br = self.browse
  if br then
    if br.state ~= "sent" then return end
    if br.tries < MAX_TRIES + 1 then
      br.state = "pending"
      self:Schedule(0.5, self.BrowseTrySend)
    else
      self:BrowseDone(false)
    end
    return
  end
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
  if self.browse then
    self:BrowseTrySend()
  elseif cur and cur.state == "more" then
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
  if not self.active or self.browse or not cur or cur.itemID ~= itemID or cur.tries == 0 then return end
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
  if not self.active or self.browse or not cur or type(itemKey) ~= "table" or itemKey.itemID ~= cur.itemID
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
  -- the key the answer is for (gear): Profit trusts a "nothing listed" only for the variant the browse showed
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
-- browse phase
-- Paging as in Blizzard's BrowseResultsFrame (AHUI/Shared/Blizzard_AuctionHouseBrowseResultsFrame.lua:74-124):
-- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED -> GetBrowseResults() (all rows so far); RequestMoreBrowseResults() ->
-- AUCTION_HOUSE_BROWSE_RESULTS_ADDED(addedBrowseResults) (AHD:1141-1155); stop when HasFullBrowseResults() (AHD:722).
-- BrowseResultInfo = {itemKey, appearanceLink?, totalQuantity, minPrice, containsOwnerItem} (AHD:1608).

function Scanner:BrowseTrySend()
  local br = self.browse
  if not self.active or not br or br.state ~= "pending" then return end
  local wait = self:SendWait()
  if wait > 0.001 then
    self:Schedule(math.max(wait, 0.05), self.BrowseTrySend)
    return
  end
  br.tries = br.tries + 1
  br.state = "sent"
  br.sentOnce = true
  self.lastSend = GetTime()
  self.waitingThrottle = false
  local ok, err
  if br.pages == 0 then
    self.sendingBrowse = true
    ok, err = pcall(C_AuctionHouse.SendBrowseQuery, br.query)   -- AHD:1021
    self.sendingBrowse = false
  else
    ok, err = pcall(C_AuctionHouse.RequestMoreBrowseResults)   -- AHD:951
  end
  if not ok then
    Debug("browse", err)
    self:BrowseDone(false)
    return
  end
  self:Schedule(BROWSE_TIMEOUT, self.OnBrowseTimeout)
end

-- merge browse rows into db.browse.items (min over variants of one itemID, units summed); returns new rows
function Scanner:MergeBrowse(br, list)
  local items = WC:DB().browse.items
  local now, server = time(), ServerNow()
  local added = 0
  for _, row in ipairs(list) do
    local key = type(row) == "table" and row.itemKey
    local id = key and key.itemID
    local price = key and row.minPrice
    -- skip battle pets (they share one itemID) and rows without a buyout price
    if id and (key.battlePetSpeciesID or 0) == 0 and type(price) == "number" and price > 0 then
      local lvl, sfx = key.itemLevel or 0, key.itemSuffix or 0
      local rowKey = id .. ":" .. lvl .. ":" .. sfx
      if not br.rows[rowKey] then
        br.rows[rowKey] = true
        added = added + 1
        local qty = row.totalQuantity or 0
        local e = items[id]
        if not br.seen[id] or not e then
          br.seen[id] = true
          br.items = br.items + 1
          e = { min = price, qty = qty, t = now, ilvl = (lvl > 0) and lvl or nil, sfx = (sfx > 0) and sfx or nil }
          items[id] = e
        else
          e.qty = (e.qty or 0) + qty
          if price < e.min then   -- key of the cheapest variant, searched later by the flips scan
            e.min = price
            e.ilvl = (lvl > 0) and lvl or nil
            e.sfx = (sfx > 0) and sfx or nil
          end
        end
        if WC.Store then WC.Store:RecordHistory(id, e.min, e.qty, server) end
      end
    end
  end
  return added
end

-- AUCTION_HOUSE_BROWSE_RESULTS_UPDATED (isUpdate) / _ADDED(addedBrowseResults)
function Scanner:OnBrowseResults(added, isUpdate)
  local br = self.browse
  if not self.active or not br or not br.sentOnce or br.foreign then return end
  if isUpdate and br.pages > 0 then
    -- our pages after the first arrive as _ADDED; a whole new list now is somebody else's query, e.g. Blizzard's
    -- Favorites button (QueryAll -> C_AuctionHouse.SearchForFavorites, AHUI/Shared/Blizzard_AuctionHouseFrame.lua:760-772).
    -- End our browse with what it has and delete nothing.
    br.foreign = true
    br.state = "done"
    self:BrowseDone(false)
    return
  end
  local list = added
  if type(list) ~= "table" then
    local ok, all = pcall(C_AuctionHouse.GetBrowseResults)   -- AHD:216
    list = (ok and type(all) == "table") and all or {}
  end
  local newRows = self:MergeBrowse(br, list)
  if br.state ~= "sent" and newRows == 0 then return end   -- an echo between our requests: nothing new
  self:CancelTimer()
  br.pages = br.pages + 1
  br.tries = 0
  UICall("OnScanProgress", self.kind, br.pages, nil, L.SCAN_PAGE_FMT:format(br.pages, br.items))
  self:PricesChanged()
  if HasFullBrowse() then
    self:BrowseDone(true)
  elseif br.pages >= BROWSE_MAX_PAGES or GetTime() - br.startedAt >= BROWSE_MAX_TIME then
    self:BrowseDone(false)
  else
    br.state = "pending"
    self:BrowseTrySend()
  end
end

function Scanner:OnBrowseTimeout()
  local br = self.browse
  if not br or br.state ~= "sent" then return end
  if br.pages > 0 and HasFullBrowse() then
    self:BrowseDone(true)
  elseif br.tries < MAX_TRIES then
    br.state = "pending"
    self:BrowseTrySend()
  else
    self:BrowseDone(false)
  end
end

-- AUCTION_HOUSE_BROWSE_FAILURE (AHD:1135)
function Scanner:OnBrowseFailure()
  local br = self.browse
  if not self.active or not br or br.state ~= "sent" then return end
  if br.tries < MAX_TRIES then
    br.state = "pending"
    self:Schedule(1, self.BrowseTrySend)
  else
    self:BrowseDone(false)
  end
end

-- gear the gear browse should have returned (weapon/armor, uncommon..epic); unknown quality = keep the entry
local function CoveredByGearBrowse(itemID)
  if not IsWeaponOrArmor(itemID) or not WC.ItemInfo then return false end
  local _, _, quality = WC.ItemInfo(itemID)
  return quality ~= nil and quality >= 2 and quality <= 4
end

-- complete = the AH said it sent everything: entries this browse should have seen but didn't are gone.
function Scanner:BrowseDone(complete)
  self:CancelTimer()
  local br = self.browse
  if not br then return end
  local db = WC:DB()
  if complete then
    local items = db.browse.items
    for itemID in pairs(items) do
      if not br.seen[itemID] and (br.scope == "full" or CoveredByGearBrowse(itemID)) then items[itemID] = nil end
    end
    db.browse[br.scope] = time()   -- only a complete browse counts as "the AH as of then"
  end
  self.browsed = (self.browsed or 0) + br.items
  self.browse = nil
  self:PricesChanged()
  self:PhaseDone()
end

-- Someone else (the AH window, another addon) started a browse while ours runs: the next results are theirs,
-- so our browse phase ends with what it has (nothing is deleted) and the scan goes on.
-- Both replace the browse result list: SendBrowseQuery (AHD:1021) and SearchForFavorites(sorts) (AHD:1000).
local function OnForeignBrowse()
  local br = Scanner.browse
  if Scanner.sendingBrowse or not Scanner.active or not br or br.foreign then return end
  br.foreign = true
  br.state = "done"
  Scanner:Schedule(0.1, function(self) if self.browse == br then self:BrowseDone(false) end end)
end

function Scanner:HookBrowse()
  if self.hooked or not hooksecurefunc then return end
  self.hooked = true
  for _, fname in ipairs({ "SendBrowseQuery", "SearchForFavorites" }) do
    if C_AuctionHouse[fname] then pcall(hooksecurefunc, C_AuctionHouse, fname, OnForeignBrowse) end
  end
end

-- ---------------------------------------------------------------------------
-- events (the scanner's own frame; AH show/close is handled in Core.lua)

local HANDLERS = {
  COMMODITY_SEARCH_RESULTS_UPDATED = Scanner.OnCommodityResults,
  ITEM_SEARCH_RESULTS_UPDATED = Scanner.OnItemResults,
  ITEM_SEARCH_RESULTS_ADDED = Scanner.OnItemResults,
  AUCTION_HOUSE_BROWSE_RESULTS_UPDATED = function(self) self:OnBrowseResults(nil, true) end,
  AUCTION_HOUSE_BROWSE_RESULTS_ADDED = function(self, added) self:OnBrowseResults(added, false) end,
  AUCTION_HOUSE_BROWSE_FAILURE = Scanner.OnBrowseFailure,
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
-- scan kinds owned by the scanner (craft is registered by Profit.lua)

Scanner:RegisterKind("crates", {
  label = function() return L.SCAN_KIND_CRATES end,
  phases = {
    { type = "search", label = function() return L.SCAN_PH_CRATES end,
      items = function()
        local list = {}
        for _, c in ipairs(WC.CRATES or {}) do
          list[#list + 1] = c.id
          for _, o in ipairs(c.opts) do list[#list + 1] = o[1] end
        end
        return list
      end },
  },
})

Scanner:RegisterKind("writs", {
  label = function() return L.SCAN_KIND_WRITS end,
  phases = {
    { type = "search", label = function() return L.SCAN_PH_WRITS end,
      items = function()
        local list = {}
        for _, w in ipairs(WC.WRITS or {}) do list[#list + 1] = w.writ end
        return list
      end },
    -- the requested items, only for writs that are for sale (unless "ignore writs not for sale" is off)
    { type = "search", label = function() return L.SCAN_PH_WRIT_ITEMS end,
      items = function()
        local db, list = WC:DB(), {}
        for _, w in ipairs(WC.WRITS or {}) do
          local _, status = WC:CostFor(w.writ, 1)
          if not db.hideNoWrit or status == "ok" then list[#list + 1] = w.item end
        end
        return list
      end },
  },
})

Scanner:RegisterKind("flips", {
  label = function() return L.SCAN_KIND_FLIPS end,
  phases = {
    { type = "browse", scope = "full", label = function() return L.SCAN_PH_BROWSE_ALL end,
      query = Scanner.FullBrowseQuery },
    -- on a fresh login most browsed items have no vendor price yet (C_Item.GetItemInfo is nil until the item data
    -- arrives): wait for them, or the search phase would skip them
    { type = "wait", timeout = 20, label = function() return L.SCAN_PH_WAIT_ITEMS end,
      ["until"] = function()
        local n = 0
        if WC.Profit and WC.Profit.FlipPending then n = WC.Profit:FlipPending() or 0 end
        return n == 0, L.SCAN_WAIT_ITEMS_FMT:format(n)
      end },
    -- listings cheaper than the vendor pays, biggest first (Profit decides)
    { type = "search", label = function() return L.SCAN_PH_FLIP_CHECK end,
      items = function()
        if WC.Profit and WC.Profit.FlipCandidates then return WC.Profit:FlipCandidates(80) or {} end
        return {}
      end },
  },
})

Scanner:RegisterKind("de", {
  label = function() return L.SCAN_KIND_DE end,
  phases = {
    { type = "search", label = function() return L.SCAN_PH_DE_MATS end,
      items = function() return (WC.DE and WC.DE.mats) or {} end },
    { type = "browse", scope = "gear", label = function() return L.SCAN_PH_DE_GEAR end,
      query = Scanner.GearBrowseQuery },
  },
})

Scanner:RegisterKind("history", {
  label = function() return L.SCAN_KIND_HISTORY end,
  canStart = function()
    if WC.Store and #WC.Store:Watched() > 0 then return true end
    return false, L.HIST_NOTHING_WATCHED
  end,
  phases = {
    { type = "search", label = function() return L.SCAN_PH_WATCHED end,
      items = function() return WC.Store and WC.Store:Watched() or {} end },
  },
})
