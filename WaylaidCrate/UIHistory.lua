local addonName, WC = ...

-- Prices tab: price history of the scanned items.
-- Left: item list (watched items first, then relevant items that have history). Right: chart for 24h / 7d / 30d / all.
-- Chart regions (lines, dots, bars, hover frames) are pooled and reused; nothing is created per refresh.
local UI = WC.UI
local L = WC.L

local STAR = "|A:auctionhouse-icon-favorite:12:12|a"

WC.AddLocale({
  enUS = {
    HIST_TAB = "Prices",
    HIST_SUBTITLE = "Price history of everything you scan · one point per hour, one per day after 30 days · " .. STAR .. " = watched",
    HIST_SCAN_TIP = "Scans the items you watch (" .. STAR .. "). Every other scan saves the prices it sees, too.",
    HIST_SEARCH = "Search item (or item ID)",
    HIST_R_24h = "24h",
    HIST_R_7d = "7 days",
    HIST_R_30d = "30 days",
    HIST_R_all = "All",
    HIST_SPAN_24h = "24 hours",
    HIST_SPAN_7d = "7 days",
    HIST_SPAN_30d = "30 days",
    HIST_SPAN_all = "all time",
    HIST_EMPTY_LIST = "No prices saved yet.\nEvery Auction House scan is saved here (one point per hour).",
    HIST_NO_MATCH = "No item matches.",
    HIST_PICK = "Pick an item on the left.",
    HIST_NO_DATA = "No prices in this time range.\nTry \"All\", or scan this item.",
    HIST_NO_DATA_ITEM = "No prices saved for this item yet.\nWatch it (star) and scan from this tab.",
    HIST_STATS = "Now %s · Low %s · Avg %s · High %s",
    HIST_CHANGE = "%s over %s",
    HIST_OBS = "%d observations",
    HIST_OBS_ONE = "1 observation",
    HIST_LAST = "last price %s",
    HIST_WATCH_TIP = "Watch: this tab scans watched items, and their history is always kept.",
    HIST_UNWATCH_TIP = "Watched. Click to stop watching.",
    HIST_CLICK_SELECT = "Click: show the price chart",
    HIST_CLICK_STAR = "Star: watch / stop watching",
    HIST_CLICK_SEARCH = "Click: search on the Auction House",
    HIST_TT_LOWEST = "Lowest price",
    HIST_TT_RANGE = "Low – high",
    HIST_TT_AVG = "Average of the day",
    HIST_TT_QTY = "Listed",
    HIST_TT_OBS = "Observations",
    HIST_TT_DAILY = "one record per day",
    HIST_LEGEND = "Line: lowest price (daily average after 30 days) · bars: daily low–high · gaps: no scan",
    HIST_PRINT_DONE = "Scan finished. Prices of your watched items are saved.",
    HIST_AGO_NOW = "just now",
    HIST_AGO_MIN = "%d min ago",
    HIST_AGO_H = "%d h ago",
    HIST_AGO_D = "%d days ago",
  },
  zhCN = {
    HIST_TAB = "走势",
    HIST_SUBTITLE = "价格走势：扫描过的物品的价格记录 · 每小时一个点，30 天后每天一个点 · " .. STAR .. " = 关注",
    HIST_SCAN_TIP = "扫描你关注（" .. STAR .. "）的物品。其他扫描看到的价格也会自动保存。",
    HIST_SEARCH = "搜索物品（或物品 ID）",
    HIST_R_24h = "24小时",
    HIST_R_7d = "7天",
    HIST_R_30d = "30天",
    HIST_R_all = "全部",
    HIST_SPAN_24h = "24 小时",
    HIST_SPAN_7d = "7 天",
    HIST_SPAN_30d = "30 天",
    HIST_SPAN_all = "全部时间",
    HIST_EMPTY_LIST = "还没有保存价格。\n每次拍卖行扫描都会保存在这里（每小时一个点）。",
    HIST_NO_MATCH = "没有符合的物品。",
    HIST_PICK = "在左边选一个物品。",
    HIST_NO_DATA = "这个时间段没有价格。\n试试『全部』，或者扫描这个物品。",
    HIST_NO_DATA_ITEM = "这个物品还没有价格记录。\n点星标关注它，再在这一页扫描。",
    HIST_STATS = "现价 %s · 最低 %s · 平均 %s · 最高 %s",
    HIST_CHANGE = "%s（%s内）",
    HIST_OBS = "%d 次记录",
    HIST_OBS_ONE = "1 次记录",
    HIST_LAST = "最新价格 %s",
    HIST_WATCH_TIP = "关注：这一页会扫描关注的物品，并一直保留它们的价格记录。",
    HIST_UNWATCH_TIP = "已关注。点击取消关注。",
    HIST_CLICK_SELECT = "点击：显示价格图",
    HIST_CLICK_STAR = "星标：关注 / 取消关注",
    HIST_CLICK_SEARCH = "点击：在拍卖行搜索",
    HIST_TT_LOWEST = "最低价",
    HIST_TT_RANGE = "最低 – 最高",
    HIST_TT_AVG = "当天平均",
    HIST_TT_QTY = "在售数量",
    HIST_TT_OBS = "记录次数",
    HIST_TT_DAILY = "每天一条记录",
    HIST_LEGEND = "线：最低价（30 天前的按当天平均）· 竖条：当天最低到最高 · 断开：那段时间没扫描",
    HIST_PRINT_DONE = "扫描完成。关注物品的价格已保存。",
    HIST_AGO_NOW = "刚刚",
    HIST_AGO_MIN = "%d 分钟前",
    HIST_AGO_H = "%d 小时前",
    HIST_AGO_D = "%d 天前",
  },
  zhTW = {
    HIST_TAB = "走勢",
    HIST_SUBTITLE = "價格走勢：掃描過的物品的價格紀錄 · 每小時一個點，30 天後每天一個點 · " .. STAR .. " = 關注",
    HIST_SCAN_TIP = "掃描你關注（" .. STAR .. "）的物品。其他掃描看到的價格也會自動儲存。",
    HIST_SEARCH = "搜尋物品（或物品 ID）",
    HIST_R_24h = "24小時",
    HIST_R_7d = "7天",
    HIST_R_30d = "30天",
    HIST_R_all = "全部",
    HIST_SPAN_24h = "24 小時",
    HIST_SPAN_7d = "7 天",
    HIST_SPAN_30d = "30 天",
    HIST_SPAN_all = "全部時間",
    HIST_EMPTY_LIST = "還沒有儲存價格。\n每次拍賣場掃描都會儲存在這裡（每小時一個點）。",
    HIST_NO_MATCH = "沒有符合的物品。",
    HIST_PICK = "在左邊選一個物品。",
    HIST_NO_DATA = "這個時間段沒有價格。\n試試『全部』，或者掃描這個物品。",
    HIST_NO_DATA_ITEM = "這個物品還沒有價格紀錄。\n點星標關注它，再在這一頁掃描。",
    HIST_STATS = "現價 %s · 最低 %s · 平均 %s · 最高 %s",
    HIST_CHANGE = "%s（%s內）",
    HIST_OBS = "%d 次紀錄",
    HIST_OBS_ONE = "1 次紀錄",
    HIST_LAST = "最新價格 %s",
    HIST_WATCH_TIP = "關注：這一頁會掃描關注的物品，並一直保留它們的價格紀錄。",
    HIST_UNWATCH_TIP = "已關注。點擊取消關注。",
    HIST_CLICK_SELECT = "點擊：顯示價格圖",
    HIST_CLICK_STAR = "星標：關注 / 取消關注",
    HIST_CLICK_SEARCH = "點擊：在拍賣場搜尋",
    HIST_TT_LOWEST = "最低價",
    HIST_TT_RANGE = "最低 – 最高",
    HIST_TT_AVG = "當天平均",
    HIST_TT_QTY = "在售數量",
    HIST_TT_OBS = "紀錄次數",
    HIST_TT_DAILY = "每天一條紀錄",
    HIST_LEGEND = "線：最低價（30 天前的按當天平均）· 豎條：當天最低到最高 · 斷開：那段時間沒掃描",
    HIST_PRINT_DONE = "掃描完成。關注物品的價格已儲存。",
    HIST_AGO_NOW = "剛剛",
    HIST_AGO_MIN = "%d 分鐘前",
    HIST_AGO_H = "%d 小時前",
    HIST_AGO_D = "%d 天前",
  },
})

if WC.Store and WC.Store.Default then
  WC.Store:Default("historyRange", "7d")
end

local Money, Font = WC.Money, UI.Font
local C_GREEN, C_GREY = UI.C_GREEN, UI.C_GREY
local C_RED = "|cffff5a4a"
local QUALITY = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000", "|cffe6cc80", "|cff00ccff" }

local Tab = { ver = 0, itemsDirty = true, offset = 0 }

local RANGES = {
  { key = "24h", span = 86400 },
  { key = "7d", span = 7 * 86400 },
  { key = "30d", span = 30 * 86400 },
  { key = "all" },
}
local RANGE_BY_KEY = {}
for _, r in ipairs(RANGES) do RANGE_BY_KEY[r.key] = r end

-- layout (panel is 672 x 514)
local PANEL_W = (UI.W or 700) - 28
local LIST_W = 220
local ROW_H = 20
local LIST_TOP = -28
local LIST_ROWS = 22
local RIGHT_X = LIST_W + 14
local RIGHT_W = PANEL_W - RIGHT_X
local CHART_TOP = -60
local CHART_H = 340
local PL, PB, PR, PT = 64, 22, 12, 10          -- plot margins inside the chart frame
local PLOT_W = RIGHT_W - PL - PR
local PLOT_H = CHART_H - PB - PT
local MAX_POINTS = 180                         -- display buckets per chart
local BUCKETS = { 3600, 7200, 10800, 21600, 43200, 86400, 172800, 604800 }
local GOLD = { 0.95, 0.75, 0.2 }
Tab.PLOT_W, Tab.PLOT_H = PLOT_W, PLOT_H

-- ---------------------------------------------------------------------------
-- helpers

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function ServerNow()
  local S = WC.Store
  if S and S.ServerNow then
    local ok, t = pcall(S.ServerNow)
    if ok and t then return t end
  end
  return (GetServerTime and GetServerTime()) or time()
end

local function Ago(t)
  if not t then return "?" end
  local s = math.max(0, time() - t)
  if s < 60 then return L.HIST_AGO_NOW end
  if s < 3600 then return L.HIST_AGO_MIN:format(math.floor(s / 60)) end
  if s < 86400 then return L.HIST_AGO_H:format(math.floor(s / 3600)) end
  return L.HIST_AGO_D:format(math.floor(s / 86400))
end

-- money for labels: whole silver once it is 1 gold or more
local function ShortMoney(v)
  if v >= 10000 then v = math.floor(v / 100 + 0.5) * 100 end
  return Money(v)
end

local function SetAtlasSafe(tex, atlas, fallbackAlpha)
  local ok, res = false, nil
  if tex.SetAtlas then ok, res = pcall(tex.SetAtlas, tex, atlas) end
  if not ok or res == false then tex:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], fallbackAlpha or 1) end
end

-- noRequest: don't ask the client to load the item (used for search candidates without history)
function Tab:ItemName(itemID, noRequest)
  local name, _, quality = WC.ItemInfo(itemID)
  if name then return name, quality end
  if noRequest then return nil, nil end
  WC.RequestItem(itemID)
  self.namesPending = true
  self:WaitForNames()
  return nil, nil
end

function Tab:ColoredName(itemID)
  local name, quality = self:ItemName(itemID)
  if not name then return "|cffffffffitem:" .. tostring(itemID) .. "|r" end
  return (QUALITY[quality or 1] or "|cffffffff") .. name .. "|r"
end

local function DB() return WC:DB() end

local function IsWatched(itemID)
  local S = WC.Store
  if S and S.IsWatched then return S:IsWatched(itemID) end
  local w = DB().watch
  return w and w[itemID] == true
end

local function IsRelevant(itemID)
  local S = WC.Store
  if S and S.IsRelevant then
    local ok, rel = pcall(S.IsRelevant, S, itemID)
    if ok then return rel end
  end
  return true
end

local function History(itemID, from, to)
  local S = WC.Store
  if not (S and S.History and itemID) then return {} end
  local ok, pts = pcall(S.History, S, itemID, from, to)
  if ok and type(pts) == "table" then return pts end
  return {}
end

-- ---------------------------------------------------------------------------
-- item list (left)

local function HasHistory(rec)
  return type(rec) == "table" and ((type(rec.h) == "table" and next(rec.h) ~= nil) or (type(rec.d) == "table" and next(rec.d) ~= nil))
end

function Tab:BuildItems()
  self.itemsDirty = false
  self.namesPending = false
  local db = DB()
  local items, seen = self.items or {}, {}
  self.items = items
  local n = 0
  local q = self.query or ""
  local qid = tonumber(q:match("item:(%d+)") or q:match("^(%d+)$") or "")
  local function add(id, watched, noRequest)
    if seen[id] or type(id) ~= "number" then return end
    local name, quality = self:ItemName(id, noRequest)
    if noRequest and not name then return end
    seen[id] = true
    local show = (q == "") or (id == qid) or (name ~= nil and string.lower(name):find(q, 1, true) ~= nil)
    if show then
      n = n + 1
      local it = items[n]
      if not it then it = {}; items[n] = it end
      it.id, it.name, it.quality, it.watched = id, name or ("item:" .. id), quality, watched
    end
  end
  for id, on in pairs(db.watch or {}) do if on == true then add(id, true) end end
  for id, rec in pairs(db.history or {}) do
    if HasHistory(rec) and IsRelevant(id) then add(id, false) end
  end
  if q ~= "" then
    -- searching also finds relevant items that have no history yet, so they can be watched
    local S = WC.Store
    if S and S.RelevantSet then
      local ok, set = pcall(S.RelevantSet, S)
      if ok and type(set) == "table" then for id in pairs(set) do add(id, IsWatched(id), true) end end
    end
    if qid then add(qid, IsWatched(qid)) end
  end
  for i = #items, n + 1, -1 do items[i] = nil end
  table.sort(items, function(a, b)
    if a.watched ~= b.watched then return a.watched end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  local maxOff = math.max(0, #items - LIST_ROWS)
  if self.offset > maxOff then self.offset = maxOff end
end

function Tab:StarButton(parent, getID)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints()
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  SetAtlasSafe(hl, "auctionhouse-icon-favorite", 0.4)
  hl:SetAlpha(0.45)
  b:SetScript("OnClick", function()
    local id = getID()
    if id then self:ToggleWatch(id) end
  end)
  b:SetScript("OnEnter", function(s)
    local id = getID()
    if not id then return end
    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self:ColoredName(id))
    GameTooltip:AddLine(IsWatched(id) and L.HIST_UNWATCH_TIP or L.HIST_WATCH_TIP, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function SetStar(b, on)
  SetAtlasSafe(b.tex, on and "auctionhouse-icon-favorite" or "auctionhouse-icon-favorite-off", on and 1 or 0.25)
  b.tex:SetAlpha(on and 1 or 0.5)
end

function Tab:CreateItemList(panel)
  local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  box:SetPoint("TOPLEFT", 0, LIST_TOP)
  box:SetSize(LIST_W, LIST_ROWS * ROW_H + 4)
  UI.Backdrop(box, { 1, 1, 1, 0.02 }, { 0.25, 0.25, 0.28, 0.8 })
  box:EnableMouseWheel(true)
  box:SetScript("OnMouseWheel", function(_, delta) self:ScrollList(-delta * 3) end)
  self.listBox = box
  local thumb = box:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(0.95, 0.75, 0.2, 0.6)
  thumb:SetWidth(3)
  self.thumb = thumb
  self.itemRows = {}
  for i = 1, LIST_ROWS do
    local row = CreateFrame("Button", nil, box)
    row:SetSize(LIST_W - 8, ROW_H)
    row:SetPoint("TOPLEFT", 3, -2 - (i - 1) * ROW_H)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(0.95, 0.72, 0.15, 0.16)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    row.star = self:StarButton(row, function() return row.id end)
    row.star:SetPoint("LEFT", 2, 0)
    row.name = Font(row, "GameFontHighlightSmall", "LEFT", 128)
    row.name:SetPoint("LEFT", 22, 0)
    row.price = Font(row, "GameFontDisableSmall", "RIGHT", 64)
    row.price:SetPoint("RIGHT", -2, 0)
    row:SetScript("OnClick", function(r) if r.id then self:Select(r.id) end end)
    row:SetScript("OnEnter", function(r) if r.id then self:ItemTooltip(r, r.id, true) end end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    self.itemRows[i] = row
  end
  local empty = Font(box, "GameFontDisable", "CENTER", LIST_W - 24)
  empty:SetWordWrap(true)
  empty:SetPoint("TOP", 0, -40)
  self.listEmpty = empty
end

function Tab:FillItems()
  local items = self.items or {}
  local sel = DB().historyItem
  for i, row in ipairs(self.itemRows) do
    local it = items[self.offset + i]
    if it then
      row.id = it.id
      row.name:SetText((QUALITY[it.quality or 1] or "|cffffffff") .. it.name .. "|r")
      local unit = WC.UnitPrice and WC:UnitPrice(it.id)
      row.price:SetText(unit and ShortMoney(unit) or "")
      SetStar(row.star, it.watched)
      row.sel:SetShown(it.id == sel)
      row:Show()
    else
      row.id = nil
      row:Hide()
    end
  end
  if #items == 0 then
    self.listEmpty:SetText((self.query or "") ~= "" and L.HIST_NO_MATCH or L.HIST_EMPTY_LIST)
    self.listEmpty:Show()
  else
    self.listEmpty:Hide()
  end
  -- scroll thumb
  local total, viewH = #items, LIST_ROWS * ROW_H
  if total <= LIST_ROWS then
    self.thumb:Hide()
  else
    local h = math.max(16, viewH * LIST_ROWS / total)
    local off = self.offset / (total - LIST_ROWS)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOPRIGHT", self.listBox, "TOPRIGHT", -1, -2 - off * (viewH - h))
    self.thumb:SetHeight(h)
    self.thumb:Show()
  end
end

function Tab:ScrollList(delta)
  local maxOff = math.max(0, #(self.items or {}) - LIST_ROWS)
  local off = math.min(maxOff, math.max(0, self.offset + delta))
  if off ~= self.offset then
    self.offset = off
    self:FillItems()
  end
end

function Tab:Select(itemID)
  if WaylaidCrateDB then WaylaidCrateDB.historyItem = itemID end
  self.selected = itemID
  self:Refresh()
end

function Tab:ToggleWatch(itemID)
  local S = WC.Store
  if S and S.SetWatch then S:SetWatch(itemID, not IsWatched(itemID)) end
  self.itemsDirty = true
  self:Refresh()
end

function Tab:ItemTooltip(owner, itemID, fromList)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local ok = pcall(GameTooltip.SetItemByID, GameTooltip, itemID)
  if not ok then GameTooltip:AddLine(self:ColoredName(itemID)) end
  GameTooltip:AddLine(" ")
  local unit, t = nil, nil
  if WC.UnitPrice then unit, t = WC:UnitPrice(itemID) end
  if unit then GameTooltip:AddDoubleLine(L.HIST_TT_LOWEST, ShortMoney(unit) .. C_GREY .. "  (" .. Ago(t) .. ")|r", 1, 0.82, 0, 1, 1, 1) end
  if fromList then
    GameTooltip:AddLine(L.HIST_CLICK_SELECT, 0.3, 1, 0.4)
    GameTooltip:AddLine(L.HIST_CLICK_STAR, 0.3, 1, 0.4)
  else
    GameTooltip:AddLine(L.HIST_CLICK_SEARCH, 0.3, 1, 0.4)
  end
  GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- right side: title, range buttons, stats, chart

function Tab:CreateRangeButtons(panel)
  self.rangeButtons = {}
  local x = 0
  for i = #RANGES, 1, -1 do
    local r = RANGES[i]
    local b = CreateFrame("Button", nil, panel)
    b:SetHeight(20)
    local fs = Font(b, "GameFontNormalSmall", "CENTER")
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText(L["HIST_R_" .. r.key])
    b:SetWidth(math.max(40, fs:GetStringWidth() + 18))
    b.text = fs
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetPoint("BOTTOMLEFT")
    b.line:SetPoint("BOTTOMRIGHT")
    b.line:SetHeight(2)
    b.line:SetColorTexture(0.95, 0.75, 0.2, 1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    b:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -x, -1)
    x = x + b:GetWidth() + 4
    b:SetScript("OnClick", function()
      if WaylaidCrateDB then WaylaidCrateDB.historyRange = r.key end
      self:Refresh()
    end)
    self.rangeButtons[r.key] = b
  end
  return x
end

function Tab:CreateChart(panel)
  local chart = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  chart:SetPoint("TOPLEFT", RIGHT_X, CHART_TOP)
  chart:SetSize(RIGHT_W, CHART_H)
  UI.Backdrop(chart, { 1, 1, 1, 0.02 }, { 0.25, 0.25, 0.28, 0.8 })
  local plot = CreateFrame("Frame", nil, chart)
  plot:SetPoint("BOTTOMLEFT", PL, PB)
  plot:SetSize(PLOT_W, PLOT_H)
  self.chart, self.plot = chart, plot

  self.grid, self.yLabels, self.xLabels = {}, {}, {}
  for k = 1, 3 do
    local g = plot:CreateTexture(nil, "BACKGROUND")
    g:SetColorTexture(1, 1, 1, 0.07)
    g:SetHeight(1)
    self.grid[k] = g
    self.yLabels[k] = Font(chart, "GameFontDisableSmall", "RIGHT", PL - 8)
  end
  for k = 1, 5 do self.xLabels[k] = Font(chart, "GameFontDisableSmall", "CENTER", 80) end

  local mark = plot:CreateTexture(nil, "OVERLAY")
  mark:SetColorTexture(1, 1, 1, 0.25)
  mark:SetWidth(1)
  mark:Hide()
  local dot = plot:CreateTexture(nil, "OVERLAY")
  dot:SetColorTexture(1, 1, 1, 1)
  dot:SetSize(5, 5)
  dot:Hide()
  self.markLine, self.markDot = mark, dot

  self.chartEmpty = Font(chart, "GameFontDisable", "CENTER", RIGHT_W - 40)
  self.chartEmpty:SetWordWrap(true)
  self.chartEmpty:SetPoint("CENTER", 0, 0)

  self.pool = { lines = {}, dots = {}, bars = {}, hits = {} }
  self.dp = {}
end

function Tab:Create(panel)
  self.panel = panel
  self.query = ""
  self.search = self:CreateSearch(panel)
  self.search:ClearAllPoints()
  self.search:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -2)
  self:CreateItemList(panel)

  local rangesW = self:CreateRangeButtons(panel)
  self.titleStar = self:StarButton(panel, function() return self.selected end)
  self.titleStar:SetPoint("TOPLEFT", RIGHT_X, -4)
  local titleW = RIGHT_W - 22 - rangesW - 6
  self.title = Font(panel, "GameFontNormalLarge", "LEFT", titleW)
  self.title:SetPoint("TOPLEFT", RIGHT_X + 22, -3)
  local hot = CreateFrame("Button", nil, panel)
  hot:SetPoint("TOPLEFT", RIGHT_X + 18, 0)
  hot:SetSize(titleW + 4, 22)
  local line = hot:CreateTexture(nil, "HIGHLIGHT")
  line:SetPoint("BOTTOMLEFT", 2, 1)
  line:SetPoint("BOTTOMRIGHT", -2, 1)
  line:SetHeight(1)
  line:SetColorTexture(1, 0.82, 0, 0.9)
  hot:SetScript("OnClick", function() if self.selected then WC:SearchAuctionHouse(self.selected) end end)
  hot:SetScript("OnEnter", function(s) if self.selected then self:ItemTooltip(s, self.selected, false) end end)
  hot:SetScript("OnLeave", GameTooltip_Hide)
  self.titleHot = hot

  self.stats = Font(panel, "GameFontHighlightSmall", "LEFT", RIGHT_W)
  self.stats:SetPoint("TOPLEFT", RIGHT_X, -27)
  self.stats2 = Font(panel, "GameFontDisableSmall", "LEFT", RIGHT_W)
  self.stats2:SetPoint("TOPLEFT", RIGHT_X, -42)

  self:CreateChart(panel)
  local legend = Font(panel, "GameFontDisableSmall", "LEFT", RIGHT_W)
  legend:SetWordWrap(true)
  legend:SetPoint("TOPLEFT", RIGHT_X, CHART_TOP - CHART_H - 6)
  legend:SetText(L.HIST_LEGEND)
  self.legend = legend
end

-- search box: the shell's UI:EditBox when it exists, else a plain one in the same style
function Tab:CreateSearch(panel)
  if UI.EditBox then
    return UI:EditBox(panel, LIST_W, L.HIST_SEARCH, function(text)
      self:OnSearch(type(text) == "string" and text or "")
    end)
  end
  return self:CreateSearchBox(panel)
end

function Tab:CreateSearchBox(panel)
  local eb = CreateFrame("EditBox", nil, panel, "BackdropTemplate")
  eb:SetSize(LIST_W, 20)
  eb:SetAutoFocus(false)
  eb:SetFontObject(_G.GameFontHighlightSmall or "GameFontHighlightSmall")
  eb:SetTextInsets(6, 6, 0, 0)
  UI.Backdrop(eb, { 0, 0, 0, 0.45 }, { 0.3, 0.3, 0.33, 1 })
  local ph = Font(eb, "GameFontDisableSmall", "LEFT", LIST_W - 12)
  ph:SetPoint("LEFT", 6, 0)
  ph:SetText(L.HIST_SEARCH)
  eb.placeholder = ph
  eb:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(s)
    local t = s:GetText() or ""
    ph:SetShown(t == "")
    self:OnSearch(t)
  end)
  return eb
end

function Tab:OnSearch(text)
  local q = string.lower(Trim(text or ""))
  if q == self.query then return end
  self.query = q
  self.itemsDirty = true
  self.offset = 0
  if self.panel and self.panel:IsShown() then self:Refresh() end
end

-- ---------------------------------------------------------------------------
-- chart

local function Acquire(pool, i, make)
  local o = pool[i]
  if not o then
    o = make()
    pool[i] = o
  end
  o:Show()
  return o
end

local function HideFrom(pool, i)
  for k = i, #pool do pool[k]:Hide() end
end

-- smallest bucket that keeps the chart under MAX_POINTS points
local function DisplayBucket(span)
  for _, b in ipairs(BUCKETS) do
    if span / b <= MAX_POINTS then return b end
  end
  return BUCKETS[#BUCKETS]
end
Tab.DisplayBucket = DisplayBucket

-- Fold the store's records into display points (pooled tables in self.dp). Daily records stay their own point
-- while the display bucket is shorter than a day. Returns the number of points.
function Tab:Aggregate(pts, D)
  local dp, m, cur, curKey = self.dp, 0, nil, nil
  for _, p in ipairs(pts) do
    local own = p.daily and D < 86400
    local key = own and -p.t or math.floor(p.t / D)
    local lo, hi = p.lo or p.min, p.hi or p.min
    if key ~= curKey then
      m = m + 1
      cur = dp[m]
      if not cur then cur = {}; dp[m] = cur end
      curKey = key
      cur.t = own and p.t or key * D
      cur.w = own and 86400 or D
      cur.min, cur.lo, cur.hi, cur.last = p.min, lo, hi, p.min
      cur.n = p.n or 1
      cur.k = 1
      cur.daily = p.daily or false
      cur.avg = p.avg
      cur.qty = p.qty
    else
      if p.min < cur.min then cur.min = p.min end
      if lo < cur.lo then cur.lo = lo end
      if hi > cur.hi then cur.hi = hi end
      cur.last = p.min
      cur.n = cur.n + (p.n or 1)
      cur.k = cur.k + 1
      cur.daily = cur.daily or p.daily or false
      cur.avg = nil
      cur.qty = p.qty or cur.qty
    end
  end
  for i = #dp, m + 1, -1 do dp[i] = nil end
  return m
end

-- consecutive points more than 1.5 buckets apart are not joined
local function Gap(a, b)
  return (b.t - a.t) > 1.5 * math.max(a.w, b.w)
end
Tab.Gap = Gap

function Tab:HideChart(message)
  local P = self.pool
  HideFrom(P.lines, 1); HideFrom(P.dots, 1); HideFrom(P.bars, 1); HideFrom(P.hits, 1)
  for k = 1, 3 do self.grid[k]:Hide(); self.yLabels[k]:Hide() end
  for k = 1, 5 do self.xLabels[k]:Hide() end
  self.markLine:Hide()
  self.markDot:Hide()
  self.chartEmpty:SetText(message or "")
  self.chartEmpty:Show()
  self.drawnCount = 0
end

function Tab:Stats(itemID, pts, range)
  local n = #pts
  local unit, ut = nil, nil
  if WC.UnitPrice then unit, ut = WC:UnitPrice(itemID) end
  if n == 0 then
    self.stats:SetText(unit and L.HIST_STATS:format(Money(unit), "—", "—", "—") or "")
    self.stats2:SetText(unit and L.HIST_LAST:format(Ago(ut)) or "")
    return
  end
  local low, high, sum, obs = math.huge, 0, 0, 0
  for _, p in ipairs(pts) do
    local v = p.min
    if (p.lo or v) < low then low = p.lo or v end
    if (p.hi or v) > high then high = p.hi or v end
    sum = sum + v
    obs = obs + (p.n or 1)
  end
  local first, last = pts[1].min, pts[n].min
  self.stats:SetText(L.HIST_STATS:format(Money(last), Money(low), Money(sum / n), Money(high)))
  local parts = {}
  if n >= 2 and first > 0 then
    local ch = (last - first) / first * 100
    local color = (ch > 0.05 and C_GREEN) or (ch < -0.05 and C_RED) or "|cffffffff"
    parts[#parts + 1] = L.HIST_CHANGE:format(color .. string.format("%+.1f%%", ch) .. "|r", L["HIST_SPAN_" .. range.key])
  end
  parts[#parts + 1] = (obs == 1) and L.HIST_OBS_ONE or L.HIST_OBS:format(obs)
  parts[#parts + 1] = L.HIST_LAST:format(Ago(ut or pts[n].t))
  self.stats2:SetText(table.concat(parts, " · "))
end

local function XLabelFormat(span)
  if span <= 2 * 86400 then return "%H:%M" end
  if span <= 400 * 86400 then return "%m/%d" end
  return "%Y/%m"
end

function Tab:Draw(force)
  local itemID = self.selected
  local range = RANGE_BY_KEY[DB().historyRange] or RANGE_BY_KEY["7d"]
  local now = ServerNow()
  local minute = math.floor(now / 60)
  local d = self.drawn
  if not force and d and d.item == itemID and d.range == range.key and d.ver == self.ver and d.minute == minute then return end
  self.drawn = d or {}
  self.drawn.item, self.drawn.range, self.drawn.ver, self.drawn.minute = itemID, range.key, self.ver, minute

  if not itemID then
    self.stats:SetText("")
    self.stats2:SetText("")
    self:HideChart(L.HIST_PICK)
    return
  end
  local from = range.span and (now - range.span) or nil
  local pts = History(itemID, from, now)
  self:Stats(itemID, pts, range)
  if #pts == 0 then
    local any = range.span and #History(itemID, nil, now) > 0
    self:HideChart(any and L.HIST_NO_DATA or L.HIST_NO_DATA_ITEM)
    return
  end
  self.chartEmpty:Hide()

  -- time axis
  local t0, t1
  if range.span then
    t0, t1 = now - range.span, now
  else
    t0, t1 = pts[1].t, math.max(now, pts[#pts].t + 3600)
    if t1 - t0 < 6 * 3600 then t0 = t1 - 6 * 3600 end
    t0 = t0 - (t1 - t0) * 0.02
  end
  local D = DisplayBucket(t1 - t0)
  local m = self:Aggregate(pts, D)
  local dp = self.dp

  -- value axis: the drawn values with 5% padding (not from 0)
  local vLo, vHi = math.huge, -math.huge
  for i = 1, m do
    local p = dp[i]
    local lo, hi = p.min, p.min
    if p.daily then lo, hi = math.min(p.lo, p.min), math.max(p.hi, p.min) end
    if lo < vLo then vLo = lo end
    if hi > vHi then vHi = hi end
  end
  local pad = (vHi - vLo) * 0.05
  if pad <= 0 then pad = math.max(1, vHi * 0.05) end
  local yLo, yHi = math.max(0, vLo - pad), vHi + pad
  self.axis = self.axis or {}
  self.axis.t0, self.axis.t1, self.axis.yLo, self.axis.yHi, self.axis.D = t0, t1, yLo, yHi, D

  local plot, P = self.plot, self.pool
  local function X(t)
    local x = (t - t0) / (t1 - t0) * PLOT_W
    if x < 0 then return 0 elseif x > PLOT_W then return PLOT_W end
    return x
  end
  local function Y(v) return (v - yLo) / (yHi - yLo) * PLOT_H end

  for i = 1, m do
    local p = dp[i]
    p.x = X(p.t + p.w / 2)
    p.y = Y(p.min)
  end

  local nl, nd, nb = 0, 0, 0
  for i = 1, m do
    local p = dp[i]
    local joinPrev = i > 1 and not Gap(dp[i - 1], p)
    local joinNext = i < m and not Gap(p, dp[i + 1])
    if joinPrev then
      nl = nl + 1
      local q = dp[i - 1]
      local line = Acquire(P.lines, nl, function()
        local l = plot:CreateLine(nil, "ARTWORK")
        l:SetThickness(2)
        l:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        return l
      end)
      line:SetStartPoint("BOTTOMLEFT", plot, q.x, q.y)
      line:SetEndPoint("BOTTOMLEFT", plot, p.x, p.y)
    end
    if not joinPrev and not joinNext then
      nd = nd + 1
      local dot = Acquire(P.dots, nd, function()
        local t = plot:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
        t:SetSize(4, 4)
        return t
      end)
      dot:ClearAllPoints()
      dot:SetPoint("CENTER", plot, "BOTTOMLEFT", p.x, p.y)
    end
    if p.daily and p.hi > p.lo then
      nb = nb + 1
      local bar = Acquire(P.bars, nb, function()
        local t = plot:CreateTexture(nil, "BORDER")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
        t:SetWidth(3)
        return t
      end)
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOM", plot, "BOTTOMLEFT", p.x, Y(p.lo))
      bar:SetHeight(math.max(1, Y(p.hi) - Y(p.lo)))
    end
    -- hover strip from halfway to the previous point to halfway to the next one
    local left = (i > 1) and (dp[i - 1].x + p.x) / 2 or math.max(0, p.x - 8)
    local right = (i < m) and (p.x + dp[i + 1].x) / 2 or math.min(PLOT_W, p.x + 8)
    local hit = Acquire(P.hits, i, function()
      local f = CreateFrame("Frame", nil, plot)
      f:EnableMouse(true)
      f:SetScript("OnEnter", function(s) self:ShowPoint(s) end)
      f:SetScript("OnLeave", function()
        self.markLine:Hide()
        self.markDot:Hide()
        GameTooltip_Hide()
      end)
      return f
    end)
    hit:ClearAllPoints()
    hit:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", left, 0)
    hit:SetSize(math.max(2, right - left), PLOT_H)
    hit.p = p
  end
  HideFrom(P.lines, nl + 1)
  HideFrom(P.dots, nd + 1)
  HideFrom(P.bars, nb + 1)
  HideFrom(P.hits, m + 1)
  self.drawnCount, self.drawnLines, self.drawnDots, self.drawnBars = m, nl, nd, nb

  -- y labels + grid at bottom / middle / top
  for k = 1, 3 do
    local v = yLo + (yHi - yLo) * (k - 1) / 2
    local y = Y(v)
    local g = self.grid[k]
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y)
    g:SetPoint("BOTTOMRIGHT", plot, "BOTTOMLEFT", PLOT_W, y)
    g:Show()
    local fs = self.yLabels[k]
    fs:ClearAllPoints()
    fs:SetPoint("RIGHT", self.chart, "BOTTOMLEFT", PL - 6, PB + y)
    fs:SetText(ShortMoney(v))
    fs:Show()
  end
  -- x labels in local time
  local fmt = XLabelFormat(t1 - t0)
  for k = 1, 5 do
    local t = t0 + (t1 - t0) * (k - 1) / 4
    local fs = self.xLabels[k]
    fs:ClearAllPoints()
    local x = (k - 1) / 4 * PLOT_W
    if k == 1 then
      fs:SetJustifyH("LEFT")
      fs:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", x, -5)
    elseif k == 5 then
      fs:SetJustifyH("RIGHT")
      fs:SetPoint("TOPRIGHT", plot, "BOTTOMLEFT", x, -5)
    else
      fs:SetJustifyH("CENTER")
      fs:SetPoint("TOP", plot, "BOTTOMLEFT", x, -5)
    end
    fs:SetText(date(fmt, math.floor(t)))
    fs:Show()
  end
end

local function PointTime(p)
  if p.daily and p.k == 1 then return date("!%Y-%m-%d", p.t) .. "  " .. C_GREY .. "(" .. L.HIST_TT_DAILY .. ")|r" end
  if p.w >= 86400 then
    if p.w == 86400 then return date("!%Y-%m-%d", p.t) end
    return date("!%m/%d", p.t) .. " – " .. date("!%m/%d", p.t + p.w - 1)
  end
  if p.w == 3600 then return date("%m/%d %H:%M", p.t) end
  return date("%m/%d %H:%M", p.t) .. " – " .. date("%H:%M", p.t + p.w)
end

function Tab:ShowPoint(hit)
  local p = hit.p
  if not p then return end
  local plot = self.plot
  self.markLine:ClearAllPoints()
  self.markLine:SetPoint("BOTTOM", plot, "BOTTOMLEFT", p.x, 0)
  self.markLine:SetHeight(PLOT_H)
  self.markLine:Show()
  self.markDot:ClearAllPoints()
  self.markDot:SetPoint("CENTER", plot, "BOTTOMLEFT", p.x, p.y)
  self.markDot:Show()
  local T = GameTooltip
  T:SetOwner(hit, "ANCHOR_RIGHT")
  T:AddLine(PointTime(p))
  if p.daily and p.k == 1 then
    T:AddDoubleLine(L.HIST_TT_AVG, Money(p.min), 1, 0.82, 0, 1, 1, 1)
  else
    T:AddDoubleLine(L.HIST_TT_LOWEST, Money(p.min), 1, 0.82, 0, 1, 1, 1)
  end
  if p.hi > p.lo then T:AddDoubleLine(L.HIST_TT_RANGE, Money(p.lo) .. " – " .. Money(p.hi), 1, 0.82, 0, 1, 1, 1) end
  if p.qty and p.k == 1 then T:AddDoubleLine(L.HIST_TT_QTY, tostring(p.qty), 1, 0.82, 0, 1, 1, 1) end
  if p.n > 1 then T:AddDoubleLine(L.HIST_TT_OBS, tostring(p.n), 1, 0.82, 0, 1, 1, 1) end
  T:Show()
end

-- ---------------------------------------------------------------------------
-- refresh

function Tab:Refresh()
  if not self.panel then return end
  if self.itemsDirty or self.namesPending then self:BuildItems() end
  local db = DB()
  local sel = db.historyItem
  if not sel and self.items[1] then
    sel = self.items[1].id
    if WaylaidCrateDB then WaylaidCrateDB.historyItem = sel end
  end
  self.selected = sel
  self:FillItems()

  local range = db.historyRange
  if not RANGE_BY_KEY[range] then range = "7d" end
  for key, b in pairs(self.rangeButtons) do
    local on = (key == range)
    b.line:SetShown(on)
    b.bg:SetColorTexture(1, 1, 1, on and 0.06 or 0)
    if on then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.55, 0.57, 0.6) end
  end

  if sel then
    self.title:SetText(self:ColoredName(sel))
    SetStar(self.titleStar, IsWatched(sel))
    self.titleStar:Show()
    self.titleHot:Show()
  else
    self.title:SetText("")
    self.titleStar:Hide()
    self.titleHot:Hide()
  end
  self:Draw()
end

function Tab:BestMessage() return L.HIST_PRINT_DONE end
function Tab:Subtitle() return L.HIST_SUBTITLE end
function Tab:ScanTip() return L.HIST_SCAN_TIP end
function Tab:ScanKind() return "history" end
function Tab:OnShow() self.itemsDirty = true end

-- item names that arrive later: one rebuild + refresh after the client has loaded them
local nameFrame
function Tab:WaitForNames()
  if self.waiting then return end
  self.waiting = true
  if not nameFrame then
    nameFrame = CreateFrame("Frame")
    nameFrame:SetScript("OnEvent", function()
      if Tab.queued then return end
      Tab.queued = true
      C_Timer.After(0.5, function()
        Tab.queued, Tab.waiting = false, false
        pcall(nameFrame.UnregisterEvent, nameFrame, "ITEM_DATA_LOAD_RESULT")
        Tab.itemsDirty = true
        if Tab.panel and Tab.panel:IsShown() then UI:Refresh() end
      end)
    end)
  end
  pcall(nameFrame.RegisterEvent, nameFrame, "ITEM_DATA_LOAD_RESULT")
end

-- new prices / watch changes: rebuild the list and redraw on the next refresh
local function Invalidate()
  Tab.itemsDirty = true
  Tab.ver = Tab.ver + 1
end
WC:On("PRICES_UPDATED", Invalidate)
WC:On("SETTINGS_CHANGED", Invalidate)
WC:On("RECIPES_UPDATED", Invalidate)
WC:On("DB_READY", Invalidate)

if UI.RegisterTab then
  UI:RegisterTab("history", { order = 6, label = function() return L.HIST_TAB end, tab = Tab })
else
  UI.tabs = UI.tabs or {}
  UI.tabs.history = Tab
end
