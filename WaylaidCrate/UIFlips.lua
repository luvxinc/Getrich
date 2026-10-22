local addonName, WC = ...

-- Flips tab: Auction House listings that cost less than what a vendor pays for them.
-- Data: WC.Profit:Flips() (Profit.lua). Also defines WC.UIA, small helpers shared with UIDisenchant.lua.
local UI = WC.UI
local L = WC.L
local Money, Font = WC.Money, UI.Font
local C_GREEN, C_ORANGE, C_GREY = UI.C_GREEN, UI.C_ORANGE, UI.C_GREY

WC.AddLocale({
  enUS = {
    FLIP_TAB = "Flips",
    FLIP_SUBTITLE = "AH listings cheaper than the vendor pays · buy them on the AH, sell them to any vendor",
    FLIP_SCAN_TIP = "Reads the whole Auction House (several pages, 1-3 minutes), then checks the cheapest items exactly.",
    FLIP_SHOW_GONE = "Show items that are no longer cheap",
    FLIP_SHOW_GONE_TIP = "The exact check sometimes finds an item already sold, or no longer below the vendor price. Those are hidden unless this is on.",
    FLIP_MIN_PROFIT = "Minimum profit",
    FLIP_MIN_PROFIT_TIP = "Hide flips that make less than this in total.",
    FLIP_ANY = "any",
    FLIP_NOTE = "Whole AH read %s · %d items",
    FLIP_NOTE_NEVER = "The whole AH has not been read yet",
    FLIP_HEAD_ITEM = "Item",
    FLIP_HEAD_PRICE = "AH price (each)",
    FLIP_HEAD_VENDOR = "Vendor pays",
    FLIP_HEAD_UNITS = "Units",
    FLIP_HEAD_PROFIT = "Profit",
    FLIP_EST = "estimate (scan again for exact quantity)",
    FLIP_EST_SHORT = "estimate",
    FLIP_GONE = "no longer below the vendor price",
    FLIP_EXACT = "exact · checked %s",
    FLIP_EACH = "+%s each",
    FLIP_BEST_LABEL = "Best flip",
    FLIP_BEST_PER = "Total profit",
    FLIP_BEST_DETAIL = "Buy %d × at about %s, vendor pays %s each, profit %s",
    FLIP_BEST_EST = "Buy at %s, vendor pays %s, profit at least %s · scan again for the exact quantity",
    FLIP_BEST_NET = "Cost %s · checked %s",
    FLIP_BEST_EMPTY = "After a scan, the best flip shows up here",
    FLIP_BEST_SCANNING = "Scanning… the best flip will show up here",
    FLIP_EMPTY_NODATA = "No Auction House data yet.\nPress Scan: Waylaid Crate reads the whole Auction House, then checks the cheapest items exactly.",
    FLIP_EMPTY_NONE = "Nothing on the Auction House is cheaper than what a vendor pays right now.",
    FLIP_TT_UNIT = "Cheapest AH price (each)",
    FLIP_TT_AVG = "Average price of the cheap ones",
    FLIP_TT_VENDOR = "Vendor pays (each)",
    FLIP_TT_UNITS = "Units below the vendor price",
    FLIP_TT_COST = "Total cost",
    FLIP_TT_PROFIT = "Total profit",
    FLIP_TT_AGE = "Price checked",
    FLIP_TT_EST = "Only the cheapest price is known so far, not how many are that cheap. Scan again for the exact quantity.",
    FLIP_TT_GONE = "The exact check found no listing below the vendor price any more.",
    FLIP_TT_MORE = "Every listing that was checked is below the vendor price, so there may be even more.",
    FLIP_TT_HOWTO = "Buy them on the Auction House, then sell them to any vendor.",
    FLIP_CLICK = "Click: search this item on the Auction House",
    FLIP_PRINT_BEST = "Scan finished. Best flip: %s, profit %s. %d items are cheaper than the vendor pays.",
    FLIP_PRINT_NONE = "Scan finished. Nothing on the Auction House is cheaper than the vendor pays.",
    FLIP_AGE_NOW = "just now",
    FLIP_AGE_MIN = "%d min ago",
    FLIP_AGE_HOUR = "%d h ago",
    FLIP_AGE_DAY = "%d days ago",
    FLIP_AGE_NEVER = "never",
  },
  zhCN = {
    FLIP_TAB = "倒卖",
    FLIP_SUBTITLE = "拍卖行上比商店收购价还便宜的东西 · 从拍卖行买下，卖给任意商人",
    FLIP_SCAN_TIP = "先读取整个拍卖行（分好几页，约 1-3 分钟），再逐个精确查询最便宜的物品。",
    FLIP_SHOW_GONE = "显示已经不便宜的",
    FLIP_SHOW_GONE_TIP = "精确查询时，有些物品已经被买走，或者不再低于商店价。默认隐藏，勾选后显示。",
    FLIP_MIN_PROFIT = "最低利润",
    FLIP_MIN_PROFIT_TIP = "总利润低于这个数的不显示。",
    FLIP_ANY = "不限",
    FLIP_NOTE = "整个拍卖行读取于 %s · %d 种物品",
    FLIP_NOTE_NEVER = "还没读取过整个拍卖行",
    FLIP_HEAD_ITEM = "物品",
    FLIP_HEAD_PRICE = "拍卖价（单个）",
    FLIP_HEAD_VENDOR = "商店收购价",
    FLIP_HEAD_UNITS = "数量",
    FLIP_HEAD_PROFIT = "利润",
    FLIP_EST = "估算（再扫描一次可得准确数量）",
    FLIP_EST_SHORT = "估算",
    FLIP_GONE = "已经不低于商店价了",
    FLIP_EXACT = "准确 · %s查过",
    FLIP_EACH = "每个 +%s",
    FLIP_BEST_LABEL = "最赚的倒卖",
    FLIP_BEST_PER = "总利润",
    FLIP_BEST_DETAIL = "买 %d 个（均价约 %s），商店每个收 %s，利润 %s",
    FLIP_BEST_EST = "%s 买入，商店收 %s，利润至少 %s · 再扫描一次可得准确数量",
    FLIP_BEST_NET = "成本 %s · %s查过",
    FLIP_BEST_EMPTY = "扫描后这里显示最赚的倒卖",
    FLIP_BEST_SCANNING = "扫描中…有结果后这里会显示最赚的倒卖",
    FLIP_EMPTY_NODATA = "还没有拍卖行数据。\n点『扫描』：先读取整个拍卖行，再精确查询最便宜的物品。",
    FLIP_EMPTY_NONE = "目前拍卖行上没有比商店收购价还便宜的东西。",
    FLIP_TT_UNIT = "拍卖行最低价（单个）",
    FLIP_TT_AVG = "便宜的那部分的均价",
    FLIP_TT_VENDOR = "商店收购价（单个）",
    FLIP_TT_UNITS = "低于商店价的数量",
    FLIP_TT_COST = "总成本",
    FLIP_TT_PROFIT = "总利润",
    FLIP_TT_AGE = "价格查询时间",
    FLIP_TT_EST = "目前只知道最低价，不知道有多少个这么便宜。再扫描一次可得准确数量。",
    FLIP_TT_GONE = "精确查询时已经没有低于商店价的挂单了。",
    FLIP_TT_MORE = "查到的挂单全都低于商店价，可能还有更多。",
    FLIP_TT_HOWTO = "从拍卖行买下，再卖给任意商人。",
    FLIP_CLICK = "点击：在拍卖行搜索这个物品",
    FLIP_PRINT_BEST = "扫描完成。最赚的倒卖：%s，利润 %s。共 %d 种物品比商店收购价便宜。",
    FLIP_PRINT_NONE = "扫描完成。拍卖行上没有比商店收购价还便宜的东西。",
    FLIP_AGE_NOW = "刚刚",
    FLIP_AGE_MIN = "%d 分钟前",
    FLIP_AGE_HOUR = "%d 小时前",
    FLIP_AGE_DAY = "%d 天前",
    FLIP_AGE_NEVER = "从未",
  },
  zhTW = {
    FLIP_TAB = "倒賣",
    FLIP_SUBTITLE = "拍賣場上比商店收購價還便宜的東西 · 從拍賣場買下，賣給任意商人",
    FLIP_SCAN_TIP = "先讀取整個拍賣場（分好幾頁，約 1-3 分鐘），再逐個精確查詢最便宜的物品。",
    FLIP_SHOW_GONE = "顯示已經不便宜的",
    FLIP_SHOW_GONE_TIP = "精確查詢時，有些物品已經被買走，或者不再低於商店價。預設隱藏，勾選後顯示。",
    FLIP_MIN_PROFIT = "最低利潤",
    FLIP_MIN_PROFIT_TIP = "總利潤低於這個數的不顯示。",
    FLIP_ANY = "不限",
    FLIP_NOTE = "整個拍賣場讀取於 %s · %d 種物品",
    FLIP_NOTE_NEVER = "還沒讀取過整個拍賣場",
    FLIP_HEAD_ITEM = "物品",
    FLIP_HEAD_PRICE = "拍賣價（單個）",
    FLIP_HEAD_VENDOR = "商店收購價",
    FLIP_HEAD_UNITS = "數量",
    FLIP_HEAD_PROFIT = "利潤",
    FLIP_EST = "估算（再掃描一次可得準確數量）",
    FLIP_EST_SHORT = "估算",
    FLIP_GONE = "已經不低於商店價了",
    FLIP_EXACT = "準確 · %s查過",
    FLIP_EACH = "每個 +%s",
    FLIP_BEST_LABEL = "最賺的倒賣",
    FLIP_BEST_PER = "總利潤",
    FLIP_BEST_DETAIL = "買 %d 個（均價約 %s），商店每個收 %s，利潤 %s",
    FLIP_BEST_EST = "%s 買入，商店收 %s，利潤至少 %s · 再掃描一次可得準確數量",
    FLIP_BEST_NET = "成本 %s · %s查過",
    FLIP_BEST_EMPTY = "掃描後這裡顯示最賺的倒賣",
    FLIP_BEST_SCANNING = "掃描中…有結果後這裡會顯示最賺的倒賣",
    FLIP_EMPTY_NODATA = "還沒有拍賣場資料。\n點『掃描』：先讀取整個拍賣場，再精確查詢最便宜的物品。",
    FLIP_EMPTY_NONE = "目前拍賣場上沒有比商店收購價還便宜的東西。",
    FLIP_TT_UNIT = "拍賣場最低價（單個）",
    FLIP_TT_AVG = "便宜的那部分的均價",
    FLIP_TT_VENDOR = "商店收購價（單個）",
    FLIP_TT_UNITS = "低於商店價的數量",
    FLIP_TT_COST = "總成本",
    FLIP_TT_PROFIT = "總利潤",
    FLIP_TT_AGE = "價格查詢時間",
    FLIP_TT_EST = "目前只知道最低價，不知道有多少個這麼便宜。再掃描一次可得準確數量。",
    FLIP_TT_GONE = "精確查詢時已經沒有低於商店價的掛單了。",
    FLIP_TT_MORE = "查到的掛單全都低於商店價，可能還有更多。",
    FLIP_TT_HOWTO = "從拍賣場買下，再賣給任意商人。",
    FLIP_CLICK = "點擊：在拍賣場搜尋這個物品",
    FLIP_PRINT_BEST = "掃描完成。最賺的倒賣：%s，利潤 %s。共 %d 種物品比商店收購價便宜。",
    FLIP_PRINT_NONE = "掃描完成。拍賣場上沒有比商店收購價還便宜的東西。",
    FLIP_AGE_NOW = "剛剛",
    FLIP_AGE_MIN = "%d 分鐘前",
    FLIP_AGE_HOUR = "%d 小時前",
    FLIP_AGE_DAY = "%d 天前",
    FLIP_AGE_NEVER = "從未",
  },
})

-- ---------------------------------------------------------------------------
-- WC.UIA: helpers shared by the Flips and Disenchant tabs (UIDisenchant.lua loads after this file)
local UIA = {}
WC.UIA = UIA
UIA.C_RED = "|cffff5a4a"
UIA.EMPTY = {}

function UIA.DB()
  if WC.DB then
    local ok, db = pcall(WC.DB, WC)
    if ok and type(db) == "table" then return db end
  end
  return WaylaidCrateDB or UIA.EMPTY
end

-- register a default setting with Store (only possible while files load, before DB_READY)
function UIA.Default(key, value)
  if WC.Store and WC.Store.Default then pcall(WC.Store.Default, WC.Store, key, value) end
end

function UIA.Register(key, order, labelKey, tab)
  if UI.RegisterTab then
    UI:RegisterTab(key, { order = order, label = function() return L[labelKey] end, tab = tab })
  else
    UI.tabs[key] = tab   -- 1.3.0 shell
  end
end

function UIA.IsShown(tab)
  return UI.frame and UI.frame:IsShown() and tab.panel and tab.panel:IsShown() and true or false
end

-- redraw the visible tab soon (the shell throttles it; 1.3.0 shell: right away)
function UIA.RequestRefresh(tab)
  if UI.RequestRefresh then UI:RequestRefresh()
  elseif tab and UIA.IsShown(tab) then pcall(tab.Refresh, tab) end
end

-- call a WC.Profit list function safely; an error never breaks the window
function UIA.ProfitList(fn)
  local P = WC.Profit
  if not (P and P[fn]) then return UIA.EMPTY, UIA.EMPTY end
  local ok, res, stats = pcall(P[fn], P)
  if ok and type(res) == "table" then return res, (type(stats) == "table") and stats or UIA.EMPTY end
  if not ok then
    if UI.Report then UI.Report("Profit:" .. fn, res) elseif WC.Debug then WC.Debug("Profit:" .. fn, res) end
  end
  return UIA.EMPTY, UIA.EMPTY
end

-- Rows shown by a tab are small wrappers { d = <Profit entry>, rank = n|nil } kept in a pool and reused,
-- because Profit rebuilds its lists in place (same tables), so a refresh allocates almost nothing.
function UIA.Wrapper(tab, n, entry, rank)
  local pool = tab.wrapPool
  if not pool then pool = {}; tab.wrapPool = pool end
  local w = pool[n]
  if not w then w = {}; pool[n] = w end
  w.d, w.rank = entry, rank
  return w
end

-- item names: request uncached items, redraw once the client has them (only while something is waiting)
local waiting = {}
local nameFrame = CreateFrame("Frame")
local nameQueued = false
nameFrame:SetScript("OnEvent", function()
  if nameQueued then return end
  nameQueued = true
  C_Timer.After(0.4, function()
    nameQueued = false
    nameFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    nameFrame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    local tabs = waiting
    waiting = {}
    for tab in pairs(tabs) do
      if UIA.IsShown(tab) then UIA.RequestRefresh(tab) end
    end
  end)
end)

local askedAt = {}   -- [itemID] = GetTime() of the last request (ask again after 30 s at most)
function UIA.NeedItem(tab, itemID)
  local now = GetTime()
  if not askedAt[itemID] or now - askedAt[itemID] > 30 then
    askedAt[itemID] = now
    WC.RequestItem(itemID)
  end
  if tab and not waiting[tab] then
    if not next(waiting) then
      nameFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
      nameFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    end
    waiting[tab] = true
  end
end

local QUALITY_HEX = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff" }

-- plain item name (client name once cached, built-in fallback before that)
function UIA.Name(tab, itemID)
  local name = WC.ItemInfo(itemID)
  if name then return name end
  UIA.NeedItem(tab, itemID)
  return WC:ItemName(itemID)
end

-- item name in its quality color
function UIA.ItemText(tab, itemID)
  local name, _, q = WC.ItemInfo(itemID)
  if not name then
    UIA.NeedItem(tab, itemID)
    name = WC:ItemName(itemID)
  end
  return "|c" .. (QUALITY_HEX[q or 1] or QUALITY_HEX[1]) .. name .. "|r"
end

-- "12 min ago"
function UIA.Age(t)
  if not t then return L.FLIP_AGE_NEVER end
  local s = math.max(0, time() - t)
  if s < 90 then return L.FLIP_AGE_NOW end
  if s < 5400 then return L.FLIP_AGE_MIN:format(math.floor(s / 60 + 0.5)) end
  if s < 172800 then return L.FLIP_AGE_HOUR:format(math.floor(s / 3600 + 0.5)) end
  return L.FLIP_AGE_DAY:format(math.floor(s / 86400))
end

-- expected quantities: 2.125 -> "2.1", 0.05 -> "0.05", 3 -> "3"
function UIA.Qty(q)
  q = q or 0
  local s = string.format(q < 0.095 and "%.2f" or "%.1f", q)
  s = s:gsub("(%.%d-)0+$", "%1"):gsub("%.$", "")
  return s
end

-- a text cell; right-aligned columns ({ r = }) may sit on a line too (y), unlike UI.Cell
function UIA.Cell(row, col, template, y)
  local fs = Font(row, template, col.r and "RIGHT" or (col.justify or "LEFT"), col.w)
  if col.r then fs:SetPoint("TOPRIGHT", row, "TOPLEFT", col.r, y or -10)
  else fs:SetPoint("TOPLEFT", col.x, y or -10) end
  return fs
end

-- label + button cycling through values: the shell's UI:ValueCycler (it redraws itself), or a small
-- stand-in for the 1.3.0 shell. Returns label, button; button.wcSync() updates the stand-in's text.
function UIA.Cycler(parent, x, y, label, key, values, textOf, tip)
  if UI.ValueCycler then
    local fs, b = UI:ValueCycler(parent, x, y, label, key, values, function(v) return textOf(v) end, tip)
    b.wcSync = b.wcSync or function() end
    return fs, b
  end
  local fs = Font(parent, "GameFontHighlightSmall", "LEFT")
  fs:SetPoint("TOPLEFT", x, y - 4)
  fs:SetText(label)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(80, 20)
  b:SetPoint("LEFT", fs, "RIGHT", 6, 0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local function Current()
    local cur = UIA.DB()[key]
    for i, v in ipairs(values) do if v == cur then return i end end
    return 1
  end
  function b.wcSync() b:SetText(textOf(values[Current()])) end
  b:SetScript("OnClick", function(_, button)
    if not WaylaidCrateDB then return end
    local i = Current() + ((button == "RightButton") and -1 or 1)
    if i > #values then i = 1 elseif i < 1 then i = #values end
    WaylaidCrateDB[key] = values[i]
    b.wcSync()
    UI:Refresh()
  end)
  UI.Tip(b, label, tip)
  b.wcSync()
  return fs, b
end

-- UI:List with the pool size the shell expects (nil = as many rows as fit; the 1.3.0 shell needs a number)
function UIA.List(panel, cols, buildRow)
  return UI:List(panel, -140, -156, cols, (not UI.RegisterTab) and 60 or nil, buildRow)
end

-- ---------------------------------------------------------------------------
-- the tab

local Tab = {}

local MIN_PROFIT = { 0, 1000, 10000, 50000 }   -- copper: any / 10s / 1g / 5g
UIA.Default("flipMinProfit", 0)
UIA.Default("flipShowGone", false)

-- content width 662: 4..30 | 36..272 | 280..372 | 378..462 | 470..528 | 536..650
local COL = {
  rank   = { x = 4, w = 26, justify = "CENTER" },
  item   = { x = 36, w = 236 },
  price  = { r = 372, w = 92 },
  vendor = { r = 462, w = 84 },
  units  = { r = 528, w = 58 },
  profit = { r = 650, w = 114 },
}

local function MinText(v)
  if not v or v == 0 then return L.FLIP_ANY end
  return Money(v)
end

local function UnitsText(e)
  if not e.qty then return C_GREY .. "?|r" end
  return tostring(math.floor(e.qty + 0.5)) .. (e.more and "+" or "")
end

function Tab:Create(panel)
  self.panel = panel
  UI:CheckRow(panel, -2, {
    { L.FLIP_SHOW_GONE, "flipShowGone", L.FLIP_SHOW_GONE_TIP },
  })
  self.hidden = Font(panel, "GameFontDisableSmall", "RIGHT", 90)
  self.hidden:SetPoint("TOPRIGHT", -2, -7)

  self.minLabel, self.minButton = UIA.Cycler(panel, 0, -28, L.FLIP_MIN_PROFIT, "flipMinProfit", MIN_PROFIT, MinText, L.FLIP_MIN_PROFIT_TIP)
  self.note = Font(panel, "GameFontDisableSmall", "RIGHT", 400)
  self.note:SetPoint("TOPRIGHT", -2, -33)

  self.best = UI:BestPanel(panel, -54, self)

  self.list = UIA.List(panel, COL, function(row)
    row.name = UIA.Cell(row, COL.item, "GameFontHighlight", -3)
    row.sub = UIA.Cell(row, COL.item, "GameFontDisableSmall", -18)
    row.price = UIA.Cell(row, COL.price, "GameFontHighlightSmall", -10)
    row.vendor = UIA.Cell(row, COL.vendor, "GameFontHighlightSmall", -10)
    row.units = UIA.Cell(row, COL.units, "GameFontHighlightSmall", -10)
    row.profit = UIA.Cell(row, COL.profit, "GameFontHighlight", -3)
    row.profitSub = UIA.Cell(row, COL.profit, "GameFontDisableSmall", -18)
    row.hotA = UI.Hotspot(row, self, "a", function() return row.entry end)
    row.hotA:SetPoint("TOPLEFT", COL.item.x - 4, 0)
    row.hotA:SetSize(COL.item.w + 4, UI.ROW_H)
    row:SetScript("OnEnter", function(r) if r.entry then self:ShowTooltip(r, r.entry) end end)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end)
  local h = self.list.headers
  h.rank:SetText("#")
  h.item:SetText(L.FLIP_HEAD_ITEM)
  h.price:SetText(L.FLIP_HEAD_PRICE)
  h.vendor:SetText(L.FLIP_HEAD_VENDOR)
  h.units:SetText(L.FLIP_HEAD_UNITS)
  h.profit:SetText(L.FLIP_HEAD_PROFIT)
end

-- all Profit entries, the visible rows ({ d = entry, rank }), and Profit's stats.
-- Hidden by default: "gone" rows (switch) and rows under the minimum profit (cycler); both counted in "N hidden".
function Tab:Visible()
  local all, stats = UIA.ProfitList("Flips")
  local db = UIA.DB()
  local minProfit = tonumber(db.flipMinProfit) or 0
  local showGone = db.flipShowGone and true or false
  local vis = self.vis or {}
  self.vis = vis
  for i = #vis, 1, -1 do vis[i] = nil end
  local n, rank = 0, 0
  for _, e in ipairs(all) do            -- Profit sorts "gone" last
    local show
    if e.status == "gone" then show = showGone else show = (e.profit or 0) >= minProfit end
    if show then
      local r
      if e.status ~= "gone" and (e.profit or 0) > 0 then rank = rank + 1; r = rank end
      n = n + 1
      vis[n] = UIA.Wrapper(self, n, e, r)
    end
  end
  return all, vis, stats
end

function Tab:SearchTarget(w) return w.d.itemID end

function Tab:FillRow(row, w, isTop)
  local e = w.d
  local gone = e.status == "gone"
  row:SetAlpha(gone and 0.5 or 1)
  row.name:SetText(UIA.ItemText(self, e.itemID))
  if e.status == "est" then
    row.sub:SetText(C_ORANGE .. L.FLIP_EST .. "|r")
  elseif gone then
    row.sub:SetText(L.FLIP_GONE)
  else
    row.sub:SetText(L.FLIP_EXACT:format(UIA.Age(e.time)))
  end
  row.price:SetText(Money(e.unit))
  row.vendor:SetText(Money(e.sell))
  if gone then
    row.units:SetText(C_GREY .. "0|r")
    row.profit:SetText(Money(nil))
    row.profitSub:SetText("")
    return
  end
  row.units:SetText(UnitsText(e))
  row.profit:SetText(UI.Colored(Money(e.profit), isTop and C_GREEN or "|cffffffff"))
  row.profitSub:SetText(e.perUnit and L.FLIP_EACH:format(Money(e.perUnit)) or "")
end

-- "Whole AH read 12 min ago · 2345 items"; the item count is only recounted when a new browse arrives
function Tab:BrowseNote()
  local b = UIA.DB().browse
  local t = type(b) == "table" and b.full
  if not t then return L.FLIP_NOTE_NEVER end
  if self.noteTime ~= t then
    local n = 0
    if type(b.items) == "table" then for _ in pairs(b.items) do n = n + 1 end end
    self.noteTime, self.noteCount = t, n
  end
  return L.FLIP_NOTE:format(UIA.Age(t), self.noteCount)
end

local function Scanning()
  return WC.Scanner and WC.Scanner.active and WC.Scanner.kind == "flips"
end

local function HasBrowse()
  local b = UIA.DB().browse
  return type(b) == "table" and b.full ~= nil
end

function Tab:EmptyText(all)
  if #all > 0 then return L.EMPTY_LIST end
  if Scanning() then return L.FLIP_BEST_SCANNING end
  if not HasBrowse() then return L.FLIP_EMPTY_NODATA end
  return L.FLIP_EMPTY_NONE
end

function Tab:Refresh()
  if not self.list then return end
  local all, vis = self:Visible()
  local top = UI:FillList(self.list, vis, function(row, w, isTop) self:FillRow(row, w, isTop) end, self:EmptyText(all))
  local hiddenCount = #all - #vis
  self.hidden:SetText(hiddenCount > 0 and L.HIDDEN_N:format(hiddenCount) or "")
  self.minButton.wcSync()
  self.note:SetText(self:BrowseNote())

  local b = self.best
  if not top then
    local text = L.FLIP_BEST_EMPTY
    if Scanning() then text = L.FLIP_BEST_SCANNING
    elseif #all > 0 or HasBrowse() then text = L.FLIP_EMPTY_NONE end
    UI:ShowBest(b, false, text)
    return
  end
  UI:ShowBest(b, true)
  b.frame.entry = top
  local e = top.d
  b.label:SetText(L.FLIP_BEST_LABEL)
  b.perLabel:SetText(L.FLIP_BEST_PER)
  local est = e.status == "est" or not e.qty
  b.name:SetText(UIA.ItemText(self, e.itemID) .. (est and ("  " .. C_ORANGE .. L.FLIP_EST_SHORT .. "|r") or ""))
  if est then
    b.detail:SetText(L.FLIP_BEST_EST:format(Money(e.unit), Money(e.sell), UI.Colored(Money(e.profit), C_GREEN)))
  else
    local avg = (e.cost and e.qty > 0) and (e.cost / e.qty) or e.unit
    b.detail:SetText(L.FLIP_BEST_DETAIL:format(math.floor(e.qty + 0.5), Money(avg), Money(e.sell), UI.Colored(Money(e.profit), C_GREEN)))
  end
  b.per:SetText(UI.Colored(Money(e.profit), C_GREEN))
  b.net:SetText(L.FLIP_BEST_NET:format(Money(e.cost), UIA.Age(e.time)))
end

function Tab:BestMessage()
  local _, vis = self:Visible()
  local n = 0
  for _, w in ipairs(vis) do if w.rank then n = n + 1 end end
  local top = vis[1]
  if not (top and top.rank == 1) then return L.FLIP_PRINT_NONE end
  return L.FLIP_PRINT_BEST:format(UIA.ItemText(self, top.d.itemID), Money(top.d.profit), n)
end

function Tab:ShowTooltip(owner, w, kind)
  local e = w.d
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(UIA.ItemText(self, e.itemID))
  if e.status == "est" then
    GameTooltip:AddLine(L.FLIP_EST, 1, 0.6, 0.2)
  elseif e.status == "gone" then
    GameTooltip:AddLine(L.FLIP_GONE, 0.6, 0.6, 0.6)
  end
  GameTooltip:AddDoubleLine(L.FLIP_TT_UNIT, Money(e.unit), 1, 0.82, 0, 1, 1, 1)
  if e.qty and e.qty > 0 and e.cost then
    GameTooltip:AddDoubleLine(L.FLIP_TT_AVG, Money(e.cost / e.qty), 1, 0.82, 0, 1, 1, 1)
  end
  GameTooltip:AddDoubleLine(L.FLIP_TT_VENDOR, Money(e.sell), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.FLIP_TT_UNITS, e.status == "gone" and "0" or UnitsText(e), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.FLIP_TT_COST, Money(e.cost), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.FLIP_TT_PROFIT, Money(e.status ~= "gone" and e.profit or nil), 1, 0.82, 0, 0.3, 1, 0.4)
  GameTooltip:AddDoubleLine(L.FLIP_TT_AGE, UIA.Age(e.time), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddLine(" ")
  if e.status == "est" then GameTooltip:AddLine(L.FLIP_TT_EST, 1, 0.6, 0.2, true)
  elseif e.status == "gone" then GameTooltip:AddLine(L.FLIP_TT_GONE, 0.6, 0.6, 0.6, true)
  elseif e.more then GameTooltip:AddLine(L.FLIP_TT_MORE, 0.8, 0.8, 0.8, true) end
  GameTooltip:AddLine(L.FLIP_TT_HOWTO, 0.55, 0.55, 0.55, true)
  GameTooltip:AddLine(L.FLIP_CLICK, 0.3, 1, 0.4)
  GameTooltip:Show()
end

function Tab:Subtitle() return L.FLIP_SUBTITLE end
function Tab:ScanTip() return L.FLIP_SCAN_TIP end
function Tab:ScanKind() return "flips" end

UIA.Register("flips", 3, "FLIP_TAB", Tab)
