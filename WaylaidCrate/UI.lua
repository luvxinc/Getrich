local addonName, WC = ...

-- Window shell: title, tab bar, scan button, progress bar and the widgets every tab shares.
-- Tabs add themselves with
--   UI:RegisterTab(key, { order = n, label = function() return L.X end, tab = Tab, title = function()|nil })
-- A tab object implements Create(panel) and Refresh(), and optionally BestMessage() -> string|nil,
-- Subtitle() -> string, ScanTip() -> string, ScanKind() -> kind (default: its key) and OnShow().
-- A tab's panel is built the first time the tab is opened; only the visible tab is refreshed,
-- and nothing is refreshed while the window is hidden.
local UI = WC.UI or {}
WC.UI = UI
UI.tabs = UI.tabs or {}          -- [key] = tab object
UI.tabSpecs = UI.tabSpecs or {}  -- [key] = registration
UI.checks, UI.cyclers, UI.valueCyclers = {}, {}, {}
UI.errors = {}                   -- errors caught inside tabs (also sent to the error handler once)
local L = WC.L

WC.AddLocale({
  enUS = {
    UI_TAB_CRATES = "Crates", UI_TAB_WRITS = "Writs", UI_TAB_FLIPS = "Flips",
    UI_TAB_CRAFT = "Crafting", UI_TAB_DE = "Disenchant", UI_TAB_HISTORY = "Prices",
    UI_VERSION_FMT = "v%s · %s",
    UI_SCANNING_FMT = "Scanning %s",
    UI_PHASE_FMT = "Phase %d/%d · %s",
    UI_ELAPSED_FMT = "%s elapsed",
    UI_LEFT_FMT = "about %s left",
    UI_SEC_FMT = "%ds",
    UI_MIN_FMT = "%dm %02ds",
    UI_STARTING_FMT = "Starting scan: %s…",
    UI_STARTING_N_FMT = "Starting scan: %s · %d items…",
    UI_DONE_FMT = "Scan finished %s · %d items, %d listed, %d missing · %s",
    UI_DONE_BROWSED_FMT = "%d items browsed",
    UI_DONE_CHAT_FMT = "Scan finished: %s (%s).",
    UI_SOUND = "Sound when done",
    UI_SOUND_TIP = "Plays a sound when a scan finishes.",
    UI_CYCLE_HINT = "Left-click: next · Right-click: previous",
    UI_SEARCH = "Search…",
    UI_SEARCH_AFTER_SCAN = "A scan is running, so \"%s\" was only put into the search box. Press Search when the scan is done.",
    UI_TAB_ERROR_FMT = "Error in the %s tab: %s",
    UI_HELP = "/wc: open or close · /wc scan: scan this tab · /wc scan <tab> · /wc stop · /wc <tab>: open a tab. Tabs: %s",
    UI_UNKNOWN_TAB_FMT = "There is no \"%s\" tab.",
  },
  zhCN = {
    UI_TAB_CRATES = "箱子", UI_TAB_WRITS = "Writ", UI_TAB_FLIPS = "倒卖",
    UI_TAB_CRAFT = "制造", UI_TAB_DE = "分解", UI_TAB_HISTORY = "走势",
    UI_SCANNING_FMT = "正在扫描：%s",
    UI_PHASE_FMT = "第 %d/%d 步 · %s",
    UI_ELAPSED_FMT = "已用 %s",
    UI_LEFT_FMT = "约剩 %s",
    UI_SEC_FMT = "%d 秒",
    UI_MIN_FMT = "%d 分 %02d 秒",
    UI_STARTING_FMT = "开始扫描：%s…",
    UI_STARTING_N_FMT = "开始扫描：%s · %d 件物品…",
    UI_DONE_FMT = "扫描完成 %s · %d 件物品，有货 %d，没货 %d · 用时 %s",
    UI_DONE_BROWSED_FMT = "浏览了 %d 种物品",
    UI_DONE_CHAT_FMT = "扫描完成：%s（用时 %s）。",
    UI_SOUND = "完成时提示音",
    UI_SOUND_TIP = "扫描完成时播放一声提示音。",
    UI_CYCLE_HINT = "左键：下一个 · 右键：上一个",
    UI_SEARCH = "搜索…",
    UI_SEARCH_AFTER_SCAN = "正在扫描，所以只把「%s」填进了搜索栏。扫描结束后再点搜索。",
    UI_TAB_ERROR_FMT = "「%s」页出错：%s",
    UI_HELP = "/wc：打开或关闭 · /wc scan：扫描当前页 · /wc scan <页> · /wc stop：停止 · /wc <页>：打开某页。页：%s",
    UI_UNKNOWN_TAB_FMT = "没有「%s」这一页。",
  },
  zhTW = {
    UI_TAB_CRATES = "箱子", UI_TAB_WRITS = "Writ", UI_TAB_FLIPS = "倒賣",
    UI_TAB_CRAFT = "製造", UI_TAB_DE = "分解", UI_TAB_HISTORY = "走勢",
    UI_SCANNING_FMT = "正在掃描：%s",
    UI_PHASE_FMT = "第 %d/%d 步 · %s",
    UI_ELAPSED_FMT = "已用 %s",
    UI_LEFT_FMT = "約剩 %s",
    UI_SEC_FMT = "%d 秒",
    UI_MIN_FMT = "%d 分 %02d 秒",
    UI_STARTING_FMT = "開始掃描：%s…",
    UI_STARTING_N_FMT = "開始掃描：%s · %d 件物品…",
    UI_DONE_FMT = "掃描完成 %s · %d 件物品，有貨 %d，沒貨 %d · 用時 %s",
    UI_DONE_BROWSED_FMT = "瀏覽了 %d 種物品",
    UI_DONE_CHAT_FMT = "掃描完成：%s（用時 %s）。",
    UI_SOUND = "完成時提示音",
    UI_SOUND_TIP = "掃描完成時播放一聲提示音。",
    UI_CYCLE_HINT = "左鍵：下一個 · 右鍵：上一個",
    UI_SEARCH = "搜尋…",
    UI_SEARCH_AFTER_SCAN = "正在掃描，所以只把「%s」填進了搜尋欄。掃描結束後再點搜尋。",
    UI_TAB_ERROR_FMT = "「%s」頁出錯：%s",
    UI_HELP = "/wc：開啟或關閉 · /wc scan：掃描目前頁面 · /wc scan <頁> · /wc stop：停止 · /wc <頁>：開啟某頁。頁：%s",
    UI_UNKNOWN_TAB_FMT = "沒有「%s」這一頁。",
  },
})

local W, H = 700, 700
UI.W = W
UI.ROW_H = 32
local PANEL_TOP = -150
local PANEL_BOTTOM = 30
local PANEL_H = H + (PANEL_TOP - 6) - PANEL_BOTTOM   -- 514: height of a tab panel
local TAB_AREA, TAB_GAP, TAB_PAD, TAB_MIN_PAD = W - 28, 4, 36, 10
local ICON = "Interface\\Icons\\INV_Crate_07"
local WHITE = "Interface\\Buttons\\WHITE8X8"

UI.C_GREEN  = "|cff4cff6a"
UI.C_ORANGE = "|cffff9a2e"
UI.C_GREY   = "|cff8a8f98"
UI.C_UNCOMMON = "|cff1eff00"
UI.RANK_COLOR = { [1] = { 1, 0.82, 0.1 }, [2] = { 0.82, 0.85, 0.9 }, [3] = { 0.85, 0.55, 0.3 } }
local C_GREY = UI.C_GREY

local function DB()
  if WC.DB then return WC:DB() end
  return WaylaidCrateDB or {}
end

-- an error inside a tab must not break the window or a running scan
local reported = {}
local function Report(where, err)
  local msg = tostring(where) .. ": " .. tostring(err)
  if reported[msg] then return end
  reported[msg] = true
  if #UI.errors < 50 then UI.errors[#UI.errors + 1] = msg end
  local handler = geterrorhandler and geterrorhandler()
  if handler then
    pcall(handler, msg)
  elseif WC.Print then
    WC:Print(L.UI_TAB_ERROR_FMT:format(tostring(where), tostring(err)))
  end
end
UI.Report = Report

-- call an optional tab method safely; returns its first result (nil if missing or failed)
local function TabCall(key, method, ...)
  local tab = UI.tabs[key]
  local fn = tab and tab[method]
  if type(fn) ~= "function" then return nil end
  local ok, res = pcall(fn, tab, ...)
  if ok then return res end
  Report(key .. ":" .. method, res)
end

-- ---------------------------------------------------------------------------
-- helpers shared by all tabs

function WC.Money(copper)
  if copper == nil then return C_GREY .. "—|r" end
  local neg = copper < 0
  local c = math.floor(math.abs(copper) + 0.5)
  local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "|cffffd100" .. L.G .. "|r" end
  if s > 0 then parts[#parts + 1] = s .. "|cffc7c7cf" .. L.S .. "|r" end
  if cp > 0 or #parts == 0 then parts[#parts + 1] = cp .. "|cffeda55f" .. L.C .. "|r" end
  return (neg and "-" or "") .. table.concat(parts, " ")
end

-- 55 -> "55", 5.75 -> "5.8"
function UI.Num(v)
  local s = string.format("%.1f", v or 0)
  return (s:gsub("%.0$", ""))
end

function UI.Pct(fraction)
  return UI.Num((fraction or 0) * 100) .. "%"
end

-- 12 -> "12s", 75 -> "1m 15s"
function UI.Duration(seconds)
  local s = math.max(0, math.floor((seconds or 0) + 0.5))
  if s < 60 then return L.UI_SEC_FMT:format(s) end
  return L.UI_MIN_FMT:format(math.floor(s / 60), s % 60)
end

-- recolor a money string (its parts reset the color with |r)
function UI.Colored(text, color)
  return color .. (text:gsub("|r", "|r" .. color)) .. "|r"
end

function UI.Font(parent, template, justify, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  if justify then fs:SetJustifyH(justify) end
  if width then fs:SetWidth(width) end
  fs:SetWordWrap(false)
  return fs
end
local Font = UI.Font

function UI.Backdrop(frame, bg, border)
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  frame:SetBackdropColor(unpack(bg))
  frame:SetBackdropBorderColor(unpack(border))
end
local Backdrop = UI.Backdrop

function UI.Tip(widget, title, text)
  widget:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", GameTooltip_Hide)
end
local Tip = UI.Tip

function UI.StandingText()
  local _, reaction = WC:Standing()
  if not reaction then return nil, nil end
  local label = _G["FACTION_STANDING_LABEL" .. reaction] or tostring(reaction)
  return label, reaction
end

-- Put an item name into the Auction House search box and search.
-- While our own scan runs, only the text is filled: the search would be a throttled browse query
-- that also replaces the browse results the scanner may be reading.
function WC:SearchAuctionHouse(itemID)
  local name = WC:ItemName(itemID)
  local ah = _G.AuctionHouseFrame
  if not (ah and ah:IsShown()) then
    WC:Print(L.OPEN_AH_FIRST)
    return
  end
  local scanning = WC.Scanner and WC.Scanner.active
  local ok = pcall(function()
    -- switch to the Buy tab first if the player is on Sell / Auctions / another addon's tab
    local M = _G.AuctionHouseFrameDisplayMode
    if M and ah.GetDisplayMode and ah.SetDisplayMode then
      local mode = ah:GetDisplayMode()
      if mode ~= M.Buy and mode ~= M.ItemBuy and mode ~= M.CommoditiesBuy then
        ah:SetDisplayMode(M.Buy)
      end
    end
    local bar = ah.SearchBar
    if bar.SetSearchText then bar:SetSearchText(name) else bar.SearchBox:SetText(name) end
    if not scanning then bar:StartSearch() end
  end)
  if not ok then
    WC:Print(L.SEARCH_FAILED:format(name))
  elseif scanning then
    WC:Print(L.UI_SEARCH_AFTER_SCAN:format(name))
  end
end

-- An invisible button over part of a row; underlines on hover.
-- tab:SearchTarget(entry, kind) gives the item to search, tab:ShowTooltip(owner, entry, kind) the tooltip.
function UI.Hotspot(parent, tab, kind, getEntry)
  local b = CreateFrame("Button", nil, parent)
  local bg = b:CreateTexture(nil, "HIGHLIGHT")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 0.82, 0, 0.08)
  local line = b:CreateTexture(nil, "HIGHLIGHT")
  line:SetPoint("BOTTOMLEFT", 2, 2)
  line:SetPoint("BOTTOMRIGHT", -2, 2)
  line:SetHeight(1)
  line:SetColorTexture(1, 0.82, 0, 0.9)
  b:SetScript("OnClick", function()
    local e = getEntry()
    local itemID = e and tab:SearchTarget(e, kind)
    if itemID then WC:SearchAuctionHouse(itemID) end
  end)
  b:SetScript("OnEnter", function(s)
    local e = getEntry()
    if e then tab:ShowTooltip(s, e, kind) end
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- settings widgets write WaylaidCrateDB[key], tell other modules (SETTINGS_CHANGED) and redraw
local function SettingChanged(key)
  WC:Fire("SETTINGS_CHANGED", key)
  UI:Refresh()
end

function UI:Check(parent, label, x, y, key, tip)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("TOPLEFT", x, y)
  local fs = Font(cb, "GameFontHighlightSmall", "LEFT")
  fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  fs:SetText(label)
  cb.labelWidth = fs:GetStringWidth()
  cb.key = key
  cb:SetHitRectInsets(0, -(cb.labelWidth + 6), 0, 0)
  cb:SetChecked(WaylaidCrateDB and WaylaidCrateDB[key])
  cb:SetScript("OnClick", function(b)
    if WaylaidCrateDB then WaylaidCrateDB[key] = b:GetChecked() and true or false end
    SettingChanged(key)
  end)
  Tip(cb, label, tip)
  self.checks[#self.checks + 1] = cb
  return cb
end

-- a row of switches; each starts after the previous label so longer English text still fits
function UI:CheckRow(parent, y, specs)
  local x = 0
  local out = {}
  for _, s in ipairs(specs) do
    local cb = self:Check(parent, s[1], x, y, s[2], s[3])
    out[#out + 1] = cb
    x = x + 22 + cb.labelWidth + 18
  end
  return out
end

-- label + small button showing "rank/max"; left-click +1, right-click -1 (wraps around)
function UI:Cycler(parent, x, y, label, key, max, tip)
  local fs = Font(parent, "GameFontHighlightSmall", "LEFT")
  fs:SetPoint("TOPLEFT", x, y - 4)
  fs:SetText(label)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(44, 20)
  b:SetPoint("LEFT", fs, "RIGHT", 6, 0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.key, b.max = key, max
  b:SetScript("OnClick", function(_, button)
    if not WaylaidCrateDB then return end
    local v = tonumber(WaylaidCrateDB[key]) or 0
    v = (button == "RightButton") and (v - 1) or (v + 1)
    if v > max then v = 0 elseif v < 0 then v = max end
    WaylaidCrateDB[key] = v
    SettingChanged(key)
  end)
  Tip(b, label, tip)
  self.cyclers[#self.cyclers + 1] = b
  return fs, b
end

-- ValueCycler options: values = { v1, v2, ... } or function() return values, labels end;
-- labels = { "text1", ... } (same order), function(value, index) -> text, or nil (tostring).
local function CyclerOptions(b)
  local vals, labs = b.values, b.labels
  if type(vals) == "function" then
    local ok, v, l = pcall(vals)
    if ok then vals, labs = v, l or labs else vals = nil end
  end
  return vals or {}, labs
end

local function CyclerLabel(vals, labs, i)
  local v = vals[i]
  if type(labs) == "table" and labs[i] ~= nil then return tostring(labs[i]) end
  if type(labs) == "function" then
    local ok, s = pcall(labs, v, i)
    if ok and s ~= nil then return tostring(s) end
  end
  return tostring(v)
end

local function CyclerIndex(vals, value)
  for i, v in ipairs(vals) do
    if v == value then return i end
  end
end

local function UpdateValueCycler(b)
  local vals, labs = CyclerOptions(b)
  local db = DB()
  local i = CyclerIndex(vals, db[b.key])
  local text
  if i then text = CyclerLabel(vals, labs, i)
  elseif db[b.key] == nil and #vals > 0 then text = CyclerLabel(vals, labs, 1)
  else text = tostring(db[b.key] or "") end
  b:SetText(text)
  local tw = tonumber(b.GetTextWidth and b:GetTextWidth()) or 0
  b:SetWidth(math.max(60, tw + 24))
end

-- label + button that cycles through a list of values (strings or numbers), e.g. a profession
-- picker. Left-click next, right-click previous; writes db[key], fires SETTINGS_CHANGED, redraws.
function UI:ValueCycler(parent, x, y, label, key, values, labels, tip)
  local fs = Font(parent, "GameFontHighlightSmall", "LEFT")
  fs:SetPoint("TOPLEFT", x, y - 4)
  fs:SetText(label or "")
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(60, 20)
  if label and label ~= "" then b:SetPoint("LEFT", fs, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", x, y) end
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.key, b.values, b.labels = key, values, labels
  b:SetScript("OnClick", function(_, button)
    if not WaylaidCrateDB then return end
    local vals = CyclerOptions(b)
    if #vals == 0 then return end
    local i = CyclerIndex(vals, WaylaidCrateDB[key]) or 1
    i = (button == "RightButton") and (i - 1) or (i + 1)
    if i > #vals then i = 1 elseif i < 1 then i = #vals end
    WaylaidCrateDB[key] = vals[i]
    SettingChanged(key)
  end)
  b:SetScript("OnEnter", function(s)
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(label or "")
    if tip then GameTooltip:AddLine(tip, 1, 1, 1, true) end
    local vals, labs = CyclerOptions(s)
    local cur = CyclerIndex(vals, DB()[key]) or 1
    for i = 1, #vals do
      if i == cur then
        GameTooltip:AddLine("» " .. CyclerLabel(vals, labs, i), 0.3, 1, 0.4)
      else
        GameTooltip:AddLine("   " .. CyclerLabel(vals, labs, i), 0.8, 0.8, 0.8)
      end
    end
    GameTooltip:AddLine(L.UI_CYCLE_HINT, 0.55, 0.55, 0.55)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  self.valueCyclers[#self.valueCyclers + 1] = b
  UpdateValueCycler(b)
  return fs, b
end

-- Search box with a placeholder and a clear button. onChange(text, editBox) runs on every change
-- (also when the text is cleared). editBox:Query() returns the trimmed, lower-cased text.
-- Also accepts the short form UI:EditBox(parent, width, onChange).
function UI:EditBox(parent, width, placeholder, onChange)
  if type(placeholder) == "function" then placeholder, onChange = nil, placeholder end
  local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  eb:SetSize(width or 160, 20)
  eb:SetAutoFocus(false)
  eb:SetFontObject(_G.GameFontHighlightSmall or "GameFontHighlightSmall")
  eb:SetTextInsets(6, 20, 0, 0)
  eb:SetMaxLetters(64)
  Backdrop(eb, { 0, 0, 0, 0.45 }, { 0.35, 0.33, 0.3, 1 })
  local ph = Font(eb, "GameFontDisableSmall", "LEFT")
  ph:SetPoint("LEFT", 7, 0)
  ph:SetText(placeholder or L.UI_SEARCH)
  local clear = CreateFrame("Button", nil, eb)
  clear:SetSize(16, 16)
  clear:SetPoint("RIGHT", -3, 0)
  local x = Font(clear, "GameFontNormalSmall", "CENTER")
  x:SetPoint("CENTER", 0, 1)
  x:SetText("×")
  clear:SetScript("OnClick", function() eb:SetText(""); eb:ClearFocus() end)
  clear:Hide()
  eb.placeholder, eb.clearButton, eb.lastText = ph, clear, ""
  eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
  eb:SetScript("OnHide", function(s) s:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(s)
    local t = s:GetText() or ""
    ph:SetShown(t == "")
    clear:SetShown(t ~= "")
    if t ~= s.lastText then
      s.lastText = t
      if onChange then onChange(t, s) end
    end
  end)
  function eb:Query()
    local t = self:GetText() or ""
    return string.lower((t:gsub("^%s+", ""):gsub("%s+$", "")))
  end
  return eb
end

-- gold "best plan" panel; returns a table of its parts
function UI:BestPanel(parent, y, tab)
  local best = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  best:SetPoint("TOPLEFT", 0, y)
  best:SetPoint("TOPRIGHT", 0, y)
  best:SetHeight(78)
  Backdrop(best, { 0.95, 0.72, 0.15, 0.09 }, { 0.95, 0.75, 0.2, 0.85 })
  local p = { frame = best }
  p.label = Font(best, "GameFontNormalSmall", "LEFT")
  p.label:SetPoint("TOPLEFT", 12, -9)
  p.name = Font(best, "GameFontNormalLarge", "LEFT", 420)
  p.name:SetPoint("TOPLEFT", 12, -25)
  p.detail = Font(best, "GameFontHighlightSmall", "LEFT", 470)
  p.detail:SetPoint("TOPLEFT", 12, -50)
  p.perLabel = Font(best, "GameFontNormalSmall", "RIGHT", 170)
  p.perLabel:SetPoint("TOPRIGHT", -12, -9)
  p.per = Font(best, "GameFontNormalLarge", "RIGHT", 180)
  p.per:SetPoint("TOPRIGHT", -12, -25)
  p.net = Font(best, "GameFontDisableSmall", "RIGHT", 200)
  p.net:SetPoint("TOPRIGHT", -12, -50)
  p.empty = Font(best, "GameFontDisable", "CENTER", W - 60)
  p.empty:SetPoint("CENTER")
  best:EnableMouse(true)
  best:SetScript("OnEnter", function(f) if f.entry then tab:ShowTooltip(f, f.entry) end end)
  best:SetScript("OnLeave", GameTooltip_Hide)
  p.hot1 = UI.Hotspot(best, tab, "a", function() return best.entry end)
  p.hot1:SetPoint("TOPLEFT", 8, -21)
  p.hot1:SetSize(424, 24)
  p.hot2 = UI.Hotspot(best, tab, "b", function() return best.entry end)
  p.hot2:SetPoint("TOPLEFT", 8, -46)
  p.hot2:SetSize(474, 18)
  return p
end

function UI:ShowBest(p, show, emptyText)
  for _, k in ipairs({ "name", "detail", "per", "perLabel", "net", "label" }) do p[k]:SetShown(show) end
  p.empty:SetShown(not show)
  p.hot1:SetShown(show)
  p.hot2:SetShown(show)
  if show then
    p.frame:SetBackdropBorderColor(0.95, 0.75, 0.2, 0.85)
    p.frame:SetBackdropColor(0.95, 0.72, 0.15, 0.09)
  else
    p.frame:SetBackdropBorderColor(0.35, 0.33, 0.3, 0.8)
    p.frame:SetBackdropColor(1, 1, 1, 0.03)
    p.empty:SetText(emptyText or "")
    p.frame.entry = nil
  end
end

-- ---------------------------------------------------------------------------
-- list with column headers and a fixed pool of row frames (virtual scrolling):
-- row i shows entries[offset + i]; the mouse wheel moves offset (Shift = a page).
--   UI:List(parent, headY, top, cols, rowCount, buildRow, opts)
--   cols: { key = { x = left } or { r = right edge }, w = width, justify }  (a "rank" column shows the rank)
--   rowCount: most rows ever built (nil = as many as fit); buildRow(row, i) adds the row's cells.
--   opts (optional): { rowH = 32, height = <visible list height if the parent is not a tab panel>,
--                      width = <row width>, bottom = 2, noRank = true }
--   UI:FillList(list, entries, fillRow, emptyText) -> the rank-1 entry; fillRow(row, entry, isTop)

local function MakeRow(list, i)
  local row = CreateFrame("Button", nil, list.content)
  local y = -(i - 1) * list.rowH
  row:SetHeight(list.rowH)
  row:SetPoint("TOPLEFT", 0, y)
  row:SetPoint("TOPRIGHT", 0, y)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.07)
  row.accent = row:CreateTexture(nil, "ARTWORK")
  row.accent:SetColorTexture(0.95, 0.75, 0.2, 1)
  row.accent:SetPoint("TOPLEFT")
  row.accent:SetPoint("BOTTOMLEFT")
  row.accent:SetWidth(2)
  row.rank = Font(row, "GameFontNormal", "CENTER", 26)
  row.rank:SetPoint("LEFT", 4, 0)
  if not list.hasRank then row.rank:Hide() end
  row:Hide()
  list.rows[i] = row
  list.build(row, i)
  return row
end

local ListMethods = {}

-- visible height of the list area (the real size once laid out, else from the known geometry)
function ListMethods:ViewHeight()
  local h = self.scroll:GetHeight()
  if type(h) == "number" and h >= self.rowH then return h end
  if self.opts.height then return self.opts.height end
  local ph = self.parent:GetHeight()
  if type(ph) == "number" and ph + self.top - self.bottom >= self.rowH then return ph + self.top - self.bottom end
  return PANEL_H + self.top - self.bottom
end

-- number of row frames needed to cover the view, and how many of them are fully visible
function ListMethods:PoolSize()
  local viewH = self:ViewHeight()
  local need = math.max(1, math.ceil(viewH / self.rowH - 0.01))
  local full = math.max(1, math.floor(viewH / self.rowH + 0.01))
  if self.maxRows and need > self.maxRows then need = self.maxRows end
  if full > need then full = need end
  return need, full, viewH
end

function ListMethods:Render()
  local vis = self.entries or {}
  local n = #vis
  local need, full, viewH = self:PoolSize()
  for i = #self.rows + 1, need do MakeRow(self, i) end
  self.pool, self.visible = need, full
  local maxOff = math.max(0, n - full)
  if self.offset > maxOff then self.offset = maxOff end
  if self.offset < 0 then self.offset = 0 end
  local top, fill = self.topEntry, self.fill
  for i, row in ipairs(self.rows) do
    local idx = self.offset + i
    local e = (i <= need) and vis[idx] or nil
    if e and fill then
      row.entry = e
      row.index = idx
      row.bg:SetColorTexture(1, 1, 1, (idx % 2 == 0) and 0.025 or 0)
      local isTop = (e == top)
      row.accent:SetShown(isTop)
      if isTop then row.bg:SetColorTexture(0.95, 0.72, 0.15, 0.1) end
      if self.hasRank then
        if e.rank then
          local c = UI.RANK_COLOR[e.rank]
          row.rank:SetText(e.rank)
          if c then row.rank:SetTextColor(c[1], c[2], c[3]) else row.rank:SetTextColor(0.55, 0.57, 0.6) end
        else
          row.rank:SetText("–")
          row.rank:SetTextColor(0.4, 0.42, 0.45)
        end
      end
      fill(row, e, isTop)
      row:Show()
    else
      row.entry, row.index = nil, nil
      row:Hide()
    end
  end
  self.content:SetHeight(math.max(self.rowH, need * self.rowH))
  self:UpdateThumb(n, viewH)
  self.empty:SetShown(n == 0)
end

function ListMethods:UpdateThumb(n, viewH)
  n = n or #(self.entries or {})
  local vis = self.visible or 1
  if n <= vis then
    self.thumb:Hide()
    self.thumbFrac = nil
    return
  end
  viewH = viewH or self:ViewHeight()
  local thumbH = math.max(24, viewH * vis / n)
  local frac = self.offset / (n - vis)
  self.thumb:ClearAllPoints()
  self.thumb:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", 0, self.top - frac * (viewH - thumbH))
  self.thumb:SetHeight(thumbH)
  self.thumb:Show()
  self.thumbFrac, self.thumbH = frac, thumbH
end

function ListMethods:ScrollTo(offset)
  self.offset = math.floor(offset or 0)
  if self.filled then self:Render() end
end

function ListMethods:Scroll(rows)
  self:ScrollTo(self.offset + rows)
end

function UI:List(parent, headY, top, cols, rowCount, buildRow, opts)
  opts = opts or {}
  local list = { cols = cols or {}, rows = {}, headers = {}, entries = {}, offset = 0, opts = opts,
                 rowH = opts.rowH or UI.ROW_H, maxRows = rowCount, build = buildRow or function() end,
                 parent = parent, top = top, bottom = opts.bottom or 2 }
  for k, fn in pairs(ListMethods) do list[k] = fn end
  list.hasRank = (cols and cols.rank ~= nil) and not opts.noRank
  for key, col in pairs(list.cols) do
    local fs = Font(parent, "GameFontDisableSmall", col.justify or (col.r and "RIGHT" or "LEFT"), col.w)
    if col.r then fs:SetPoint("TOPLEFT", col.r - col.w, headY) else fs:SetPoint("TOPLEFT", col.x, headY) end
    list.headers[key] = fs
  end
  local scroll = CreateFrame("ScrollFrame", nil, parent)   -- only used to clip the rows
  scroll:SetPoint("TOPLEFT", 0, top)
  scroll:SetPoint("BOTTOMRIGHT", -10, list.bottom)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(opts.width or (W - 38), list.rowH)
  scroll:SetScrollChild(content)
  scroll:EnableMouseWheel(true)
  local thumb = parent:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(0.95, 0.75, 0.2, 0.6)
  thumb:SetWidth(4)
  thumb:Hide()
  local track = parent:CreateTexture(nil, "ARTWORK")
  track:SetColorTexture(1, 1, 1, 0.05)
  track:SetPoint("TOPRIGHT", 0, top)
  track:SetPoint("BOTTOMRIGHT", 0, list.bottom)
  track:SetWidth(4)
  list.scroll, list.content, list.thumb, list.track = scroll, content, thumb, track
  scroll:SetScript("OnMouseWheel", function(_, delta)
    local step = (IsShiftKeyDown and IsShiftKeyDown()) and math.max(1, (list.visible or 2) - 1) or 2
    list:Scroll(-delta * step)
    GameTooltip_Hide()
  end)
  scroll:SetScript("OnSizeChanged", function(_, w)
    if type(w) == "number" and w > 0 and not opts.width then content:SetWidth(w) end
    if list.filled then list:Render() end
  end)
  local empty = Font(parent, "GameFontDisable", "CENTER", W - 80)
  empty:SetPoint("TOP", scroll, "TOP", 0, -40)
  empty:SetWordWrap(true)
  empty:Hide()
  list.empty = empty
  -- build the rows that fit now (more are added later if the list turns out taller)
  local need = list:PoolSize()
  for i = 1, need do MakeRow(list, i) end
  return list
end

-- place a row font string into a column
function UI.Cell(row, col, template, y)
  local fs = Font(row, template, col.r and "RIGHT" or "LEFT", col.w)
  if col.r then fs:SetPoint("RIGHT", row, "LEFT", col.r, 0) else fs:SetPoint("TOPLEFT", col.x, y or 0) end
  return fs
end

-- show entries in the list (keeps the scroll position); returns the rank-1 entry.
-- The empty text (emptyText or L.EMPTY_LIST) is set here, so a tab may still change
-- list.empty's text after FillList and scrolling won't reset it.
function UI:FillList(list, vis, fillRow, emptyText)
  local top
  for _, e in ipairs(vis) do if e.rank == 1 then top = e break end end
  list.entries, list.fill, list.topEntry, list.filled = vis, fillRow, top, true
  if #vis == 0 then list.empty:SetText(emptyText or L.EMPTY_LIST) end
  list:Render()
  return top
end

-- ---------------------------------------------------------------------------
-- tab registry

function UI:RegisterTab(key, spec)
  if type(key) ~= "string" or type(spec) ~= "table" or type(spec.tab) ~= "table" then return end
  spec.key = key
  spec.order = tonumber(spec.order) or 99
  self.tabSpecs[key] = spec
  self.tabs[key] = spec.tab
  if self.frame then self:LayoutTabs() end
  return spec.tab
end

function UI:TabKeys()
  local keys = {}
  for key in pairs(self.tabSpecs) do keys[#keys + 1] = key end
  local specs = self.tabSpecs
  table.sort(keys, function(a, b)
    if specs[a].order ~= specs[b].order then return specs[a].order < specs[b].order end
    return a < b
  end)
  return keys
end

local function ShortLabel(key) return L["UI_TAB_" .. string.upper(key)] end

function UI:TabLabel(key)
  local spec = self.tabSpecs[key]
  local label = spec and spec.label
  if type(label) == "function" then
    local ok, s = pcall(label)
    if ok and type(s) == "string" and s ~= "" then return s end
  elseif type(label) == "string" and label ~= "" then
    return label
  end
  return ShortLabel(key) or key
end

-- the tab that shows the results of a scan kind (the open tab first)
function UI:TabForKind(kind)
  local cur = WC:Tab()
  if self.tabSpecs[cur] and self:ScanKindFor(cur) == kind then return cur end
  if self.tabSpecs[kind] and self:ScanKindFor(kind) == kind then return kind end
  for _, key in ipairs(self:TabKeys()) do
    if self:ScanKindFor(key) == kind then return key end
  end
end

function UI:ScanKindFor(key)
  return TabCall(key, "ScanKind") or key
end

function UI:CurrentScanKind()
  return self:ScanKindFor(WC:Tab())
end

local function KindLabel(kind)
  local key = UI:TabForKind(kind)
  if key then return UI:TabLabel(key) end
  local S = WC.Scanner
  local k = S and type(S.kinds) == "table" and S.kinds[kind]
  if k and type(k.label) == "function" then
    local ok, s = pcall(k.label)
    if ok and s then return s end
  end
  return (L.KIND and L.KIND[kind]) or tostring(kind)
end

-- db.tab if that tab is registered, else "crates"
function WC:Tab()
  local t = DB().tab
  if t and UI.tabSpecs[t] then return t end
  return "crates"
end

-- start a scan of what a tab shows (default: the open tab)
function UI:StartScan(key)
  local S = WC.Scanner
  if not S or S.active then return end
  S:Start(self:ScanKindFor(key or WC:Tab()))
end

-- ---------------------------------------------------------------------------
-- window

local function Meta(field)
  local ok, v = pcall(function()
    if C_AddOns and C_AddOns.GetAddOnMetadata then return C_AddOns.GetAddOnMetadata(addonName, field) end
    if GetAddOnMetadata then return GetAddOnMetadata(addonName, field) end
  end)
  if ok and type(v) == "string" and v ~= "" then return v end
end
WC.VERSION = Meta("Version")
WC.RELEASED = Meta("X-Released")

function UI.VersionText()
  local v = WC.VERSION or Meta("Version") or "?"
  local released = WC.RELEASED or Meta("X-Released")
  if released then return L.UI_VERSION_FMT:format(v, released) end
  return "v" .. v
end

function UI:MakeTabButton(key)
  local b = CreateFrame("Button", nil, self.frame)
  b:SetHeight(26)
  local fs = Font(b, "GameFontNormal", "CENTER")
  fs:SetPoint("CENTER", 0, 1)
  b.text = fs
  b.key = key
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
  b:SetScript("OnClick", function() UI:SelectTab(key) end)
  b:SetScript("OnEnter", function(s)
    local spec = UI.tabSpecs[key]
    local title
    if spec and type(spec.title) == "function" then
      local ok, t = pcall(spec.title)
      if ok then title = t end
    end
    GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(title or UI:TabLabel(key))
    local sub = TabCall(key, "Subtitle")
    if sub and sub ~= "" then GameTooltip:AddLine(sub, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  self.tabButtons[key] = b
  return b
end

-- lay the tab buttons out in one row of 672 px: natural width + padding; if that is too wide,
-- use the short names, then less padding, and as a last resort equal widths (text gets cut)
function UI:LayoutTabs()
  if not self.frame then return end
  local keys = self:TabKeys()
  local n = #keys
  if n == 0 then return end
  local widths = {}
  for i, key in ipairs(keys) do
    local b = self.tabButtons[key] or self:MakeTabButton(key)
    b.text:SetWidth(0)
    b.text:SetText(self:TabLabel(key))
    widths[i] = b.text:GetStringWidth()
  end
  local function Total(pad)
    local s = (n - 1) * TAB_GAP
    for i = 1, n do s = s + widths[i] + pad end
    return s
  end
  if Total(TAB_PAD) > TAB_AREA then
    for i, key in ipairs(keys) do
      local short = ShortLabel(key)
      if short then
        local b = self.tabButtons[key]
        b.text:SetText(short)
        widths[i] = b.text:GetStringWidth()
      end
    end
  end
  local pad = TAB_PAD
  if Total(pad) > TAB_AREA then
    local sumText = 0
    for i = 1, n do sumText = sumText + widths[i] end
    pad = math.max(TAB_MIN_PAD, math.floor((TAB_AREA - (n - 1) * TAB_GAP - sumText) / n))
  end
  local squeeze = Total(pad) > TAB_AREA
  local even = math.floor((TAB_AREA - (n - 1) * TAB_GAP) / n)
  local prev
  for i, key in ipairs(keys) do
    local b = self.tabButtons[key]
    local w = widths[i] + pad
    if squeeze then
      w = even
      b.text:SetWidth(even - 6)
    end
    b:SetWidth(w)
    b.layoutWidth = w
    b:ClearAllPoints()
    if prev then b:SetPoint("LEFT", prev, "RIGHT", TAB_GAP, 0) else b:SetPoint("TOPLEFT", 14, -56) end
    b:Show()
    prev = b
  end
  self.tabOrder = keys
end

function UI:Create()
  if self.frame then return end
  local f = CreateFrame("Frame", "WaylaidCrateFrame", UIParent, "BackdropTemplate")
  self.frame = f
  f:SetSize(W, H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); UI.userMoved = true end)
  Backdrop(f, { 0.055, 0.06, 0.075, 0.97 }, { 0.42, 0.33, 0.14, 1 })
  f:Hide()
  tinsert(UISpecialFrames, "WaylaidCrateFrame")   -- ESC closes the window
  f:SetScript("OnShow", function() TabCall(WC:Tab(), "OnShow") end)

  -- title
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(30, 30)
  icon:SetPoint("TOPLEFT", 12, -10)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local title = Font(f, "GameFontNormalLarge", "LEFT")
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
  title:SetText("Waylaid Crate")
  local version = Font(f, "GameFontDisableSmall", "LEFT")
  version:SetPoint("LEFT", title, "RIGHT", 8, -1)
  version:SetText(UI.VersionText())
  self.versionText = version
  self.subtitle = Font(f, "GameFontDisableSmall", "LEFT", W - 90)
  self.subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- tab bar
  self.tabButtons = {}
  self:LayoutTabs()
  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.42, 0.33, 0.14, 0.6)
  rule:SetPoint("TOPLEFT", 12, -82)
  rule:SetPoint("TOPRIGHT", -12, -82)
  rule:SetHeight(1)

  -- scan button + switches
  local scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scan:SetSize(150, 24)
  scan:SetPoint("TOPLEFT", 14, -92)
  scan:SetText(L.SCAN)
  scan:SetScript("OnClick", function()
    local S = WC.Scanner
    if not S then return end
    if S.active then S:Stop(L.STOP_MANUAL) else UI:StartScan(WC:Tab()) end
  end)
  scan:SetScript("OnEnter", function(b)
    local key = WC:Tab()
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(TabCall(key, "ScanTip") or L["SCAN_TIP_" .. key] or L.SCAN)
    GameTooltip:AddLine(L.SCAN_TIP, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  scan:SetScript("OnLeave", GameTooltip_Hide)
  self.scanButton = scan
  local auto = self:Check(f, L.AUTO_SCAN, 178, -93, "autoScan", L.AUTO_SCAN_TIP)
  self.soundCheck = self:Check(f, L.UI_SOUND, 178 + 22 + auto.labelWidth + 18, -93, "soundOnDone", L.UI_SOUND_TIP)

  -- progress bar
  local barBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
  barBg:SetPoint("TOPLEFT", 14, -122)
  barBg:SetPoint("TOPRIGHT", -14, -122)
  barBg:SetHeight(20)
  Backdrop(barBg, { 0, 0, 0, 0.5 }, { 0.25, 0.25, 0.28, 1 })
  local bar = CreateFrame("StatusBar", nil, barBg)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("BOTTOMRIGHT", -1, 1)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  local spark = bar:CreateTexture(nil, "OVERLAY")
  spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  spark:SetBlendMode("ADD")
  spark:SetSize(16, 34)
  spark:Hide()
  -- indeterminate state (total unknown, e.g. while browsing): a block sliding back and forth.
  -- An animation group runs in the client, no Lua OnUpdate; it is stopped whenever it is hidden.
  local glow = bar:CreateTexture(nil, "ARTWORK")
  glow:SetColorTexture(1, 0.76, 0.18, 0.55)
  glow:SetSize(110, 18)
  glow:SetPoint("LEFT", bar, "LEFT", 0, 0)
  glow:Hide()
  local anim = glow:CreateAnimationGroup()
  anim:SetLooping("BOUNCE")
  local move = anim:CreateAnimation("Translation")
  move:SetOffset(W - 30 - 110, 0)
  move:SetDuration(1.2)
  local barText = Font(bar, "GameFontHighlightSmall", "CENTER")
  barText:SetPoint("CENTER")
  barText:SetWidth(W - 40)
  self.bar, self.spark, self.barText, self.glow, self.glowAnim = bar, spark, barText, glow, anim

  -- footer
  local foot = Font(f, "GameFontDisableSmall", "LEFT", W - 30)
  foot:SetPoint("BOTTOMLEFT", 14, 12)
  foot:SetText(L.FOOTER)

  self:SetIdleText()
  self:SelectTab(WC:Tab())
end

-- build a tab's panel the first time it is opened
function UI:EnsurePanel(key)
  local tab = self.tabs[key]
  if not tab then return end
  if tab.panel then return tab.panel end
  local panel = CreateFrame("Frame", nil, self.frame)
  panel:SetPoint("TOPLEFT", 14, PANEL_TOP - 6)
  panel:SetPoint("BOTTOMRIGHT", -14, PANEL_BOTTOM)
  panel:Hide()
  tab.panel = panel
  if type(tab.Create) == "function" then
    local ok, err = pcall(tab.Create, tab, panel)
    if not ok then Report(key .. ":Create", err) end
  end
  return panel
end

function UI:SelectTab(key)
  if not self.frame then return end
  if not (key and self.tabSpecs[key]) then key = WC:Tab() end
  if not self.tabSpecs[key] then return end
  if WaylaidCrateDB then WaylaidCrateDB.tab = key end
  self:EnsurePanel(key)
  for k, b in pairs(self.tabButtons) do
    local on = (k == key)
    b.line:SetShown(on)
    b.bg:SetColorTexture(1, 1, 1, on and 0.06 or 0)
    if on then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.55, 0.57, 0.6) end
  end
  for k, tab in pairs(self.tabs) do
    if tab.panel then tab.panel:SetShown(k == key) end
  end
  self.subtitle:SetText(TabCall(key, "Subtitle") or "")
  if not (WC.Scanner and WC.Scanner.active) then self:SetIdleText() end
  if self.frame:IsShown() then TabCall(key, "OnShow") end
  self:Refresh()
end

-- redraw the visible tab now (does nothing while the window is hidden)
local requested, served, pending = 0, 0, false
function UI:Refresh()
  served = requested
  if not (self.frame and self.frame:IsShown()) then return end
  local db = DB()
  for _, cb in ipairs(self.checks) do cb:SetChecked(db[cb.key]) end
  for _, b in ipairs(self.cyclers) do b:SetText((tonumber(db[b.key]) or 0) .. "/" .. b.max) end
  for _, b in ipairs(self.valueCyclers) do UpdateValueCycler(b) end
  local key = WC:Tab()
  local tab = self.tabs[key]
  if tab and tab.panel and type(tab.Refresh) == "function" then
    local ok, err = pcall(tab.Refresh, tab)
    if not ok then Report(key .. ":Refresh", err) end
  end
end

-- redraw soon, at most 4 times a second (used for bus messages that can come in bursts)
function UI:RequestRefresh()
  requested = requested + 1
  if pending then return end
  pending = true
  C_Timer.After(0.25, function()
    pending = false
    if served < requested then UI:Refresh() end
  end)
end

for _, msg in ipairs({ "PRICES_UPDATED", "RECIPES_UPDATED", "VENDOR_UPDATED", "DE_UPDATED", "BAGS_UPDATED", "SETTINGS_CHANGED" }) do
  WC:On(msg, function() UI:RequestRefresh() end)
end
WC:On("DB_READY", function()
  if UI.frame then UI:SelectTab(WC:Tab()) end
end)

-- ---------------------------------------------------------------------------
-- progress bar
--   Scanner calls: OnScanStart(kind, total), OnScanPhase(kind, i, n, label),
--   OnScanProgress(kind, done, total, label), OnScanDone(kind, stats), OnScanStopped(kind, reason, done, total).
--   total may be nil (unknown) -> sliding bar. A 1-second ticker keeps the elapsed time current;
--   it exists only while a scan is running.

function UI:SetIndeterminate(on)
  if not self.glow then return end
  if on then
    self.spark:Hide()
    self.bar:SetValue(0)
    self.glow:Show()
    if not self.glowAnim:IsPlaying() then self.glowAnim:Play() end
  else
    self.glowAnim:Stop()
    self.glow:Hide()
  end
  self.indeterminate = on and true or false
end

function UI:StopTicker()
  if self.ticker then
    self.ticker:Cancel()
    self.ticker = nil
  end
end

function UI:StartTicker()
  self:StopTicker()
  local function Tick()
    if not (WC.Scanner and WC.Scanner.active and UI.prog) then
      UI:StopTicker()
      return
    end
    UI:RenderProgress()
  end
  if C_Timer.NewTicker then
    self.ticker = C_Timer.NewTicker(1, Tick)
  else
    local t = {}
    t.Cancel = function() t.cancelled = true end
    local function Loop()
      if t.cancelled then return end
      Tick()
      if not t.cancelled then C_Timer.After(1, Loop) end
    end
    C_Timer.After(1, Loop)
    self.ticker = t
  end
end

function UI:RenderProgress()
  local p = self.prog
  if not (p and self.bar) then return end
  local parts = {}
  local total, done = p.total, p.done or 0
  local starting = (done == 0) and not p.label and not p.phases
  if p.phases and p.phases > 1 then
    parts[#parts + 1] = L.UI_PHASE_FMT:format(p.phase or 1, p.phases, p.phaseLabel or KindLabel(p.kind))
  elseif starting then
    if total and total > 0 then
      parts[#parts + 1] = L.UI_STARTING_N_FMT:format(KindLabel(p.kind), total)
    else
      parts[#parts + 1] = L.UI_STARTING_FMT:format(KindLabel(p.kind))
    end
  else
    parts[#parts + 1] = L.UI_SCANNING_FMT:format(p.phaseLabel or KindLabel(p.kind))
  end
  if total and total > 0 and not starting then
    parts[#parts + 1] = math.min(done + 1, total) .. " / " .. total
  end
  if p.label and p.label ~= "" then parts[#parts + 1] = p.label end
  parts[#parts + 1] = L.UI_ELAPSED_FMT:format(UI.Duration(GetTime() - p.started))
  if total and total > done then
    parts[#parts + 1] = L.UI_LEFT_FMT:format(UI.Duration((total - done) * 0.8))
  end
  if total and total > 0 then
    self:SetIndeterminate(false)
    local pct = math.min(1, done / total)
    self.bar:SetValue(pct)
    self.spark:ClearAllPoints()
    self.spark:SetPoint("CENTER", self.bar, "LEFT", self.bar:GetWidth() * pct, 0)
    self.spark:Show()
  else
    self:SetIndeterminate(true)
  end
  self.barText:SetText(table.concat(parts, " · "))
end

-- open the tab that shows this kind of scan (if the open tab doesn't)
function UI:SelectTabForKind(kind)
  local key = self:TabForKind(kind)
  if key and key ~= WC:Tab() then self:SelectTab(key) end
end

function UI:OnScanStart(kind, total)
  self:Create()
  self.frame:Show()
  self:SelectTabForKind(kind)
  local S = WC.Scanner
  self.prog = { kind = kind, total = total, done = 0, started = (S and S.startedAt) or GetTime() }
  self.scanButton:SetText(L.STOP_SCAN)
  self.bar:SetStatusBarColor(1, 0.76, 0.18)
  self.bar:SetValue(0)
  self:RenderProgress()
  self:StartTicker()
  self:Refresh()
end

function UI:OnScanPhase(kind, phase, phases, phaseLabel)
  if not (self.frame and self.prog) then return end
  local p = self.prog
  p.phase, p.phases, p.phaseLabel = phase, phases, phaseLabel
  p.done, p.total, p.label = 0, nil, nil
  self:RenderProgress()
end

-- label: item name, "page N · M items", or (1.3.0 scanner) an itemID
function UI:OnScanProgress(kind, done, total, label)
  if not (self.frame and self.prog) then return end
  if type(label) == "number" then label = WC:ItemName(label) end
  local p = self.prog
  p.done, p.total, p.label = done or 0, total, label
  self:RenderProgress()
end

local function PlayDoneSound()
  local play = _G.PlaySound or (C_Sound and C_Sound.PlaySound)
  -- SOUNDKIT.READY_CHECK (8960): Blizzard_SharedXML/Mainline/SoundKitConstants.lua, played by
  -- Blizzard_FrameXML/Mainline/ReadyCheck.lua (loads for the mainline family, which includes Forever)
  local id = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960
  if play then pcall(play, id) end
end

-- stats = { total, listed, missing, seconds, browsed = n|nil } (1.3.0: kind, total, listed, missing, seconds)
function UI:OnScanDone(kind, stats, ...)
  if not self.frame then return end
  if type(stats) ~= "table" then
    local listed, missing, seconds = ...
    stats = { total = stats, listed = listed, missing = missing, seconds = seconds }
  end
  local started = self.prog and self.prog.started
  local seconds = stats.seconds or (started and GetTime() - started) or 0
  self:StopTicker()
  self.prog = nil
  self:SetIndeterminate(false)
  self.scanButton:SetText(L.RESCAN)
  self.bar:SetStatusBarColor(0.25, 0.75, 0.35)
  self.bar:SetValue(1)
  self.spark:Hide()
  local text = L.UI_DONE_FMT:format(date("%H:%M"), stats.total or 0, stats.listed or 0, stats.missing or 0, UI.Duration(seconds))
  if stats.browsed then text = text .. " · " .. L.UI_DONE_BROWSED_FMT:format(stats.browsed) end
  self.barText:SetText(text)
  self:Refresh()
  local key = self:TabForKind(kind)
  local tab = key and self.tabs[key]
  local msg = key and TabCall(key, "BestMessage")
  if not msg then
    if tab and tab.BestMessage then msg = L.PRINT_NONE
    else msg = L.UI_DONE_CHAT_FMT:format(KindLabel(kind), UI.Duration(seconds)) end
  end
  WC:Print(msg)
  if DB().soundOnDone then PlayDoneSound() end
end

function UI:OnScanStopped(kind, reason, done, total)
  local started = self.prog and self.prog.started
  self:StopTicker()
  self.prog = nil
  if not self.frame then return end
  self:SetIndeterminate(false)
  self.scanButton:SetText(L.SCAN)
  self.bar:SetStatusBarColor(0.55, 0.45, 0.3)
  self.spark:Hide()
  local text
  if total and total > 0 then
    text = L.STOPPED_FMT:format(reason or L.STOPPED, math.max(done or 0, 0), total)
  else
    text = reason or L.STOPPED
  end
  if started then text = text .. " · " .. L.UI_ELAPSED_FMT:format(UI.Duration(GetTime() - started)) end
  self.barText:SetText(text)
  self:Refresh()
end

function UI:SetIdleText()
  if not self.bar then return end
  local db = DB()
  local kind = self:CurrentScanKind()
  local at = type(db.scannedAt) == "table" and db.scannedAt[kind]
  -- Flips / Disenchant (whole-AH reads) and auto-scan switched off: only a click starts a scan
  local manual = (kind == "flips" or kind == "de" or not db.autoScan)
  self:SetIndeterminate(false)
  self.bar:SetStatusBarColor(0.35, 0.37, 0.4)
  if at then
    self.bar:SetValue(1)
    self.barText:SetText(((manual and L.IDLE_LAST_MANUAL) or L.IDLE_LAST):format(date("%m/%d %H:%M", at)))
  else
    self.bar:SetValue(0)
    self.barText:SetText((manual and L.IDLE_NEVER_MANUAL) or L.IDLE_NEVER)
  end
  self.scanButton:SetText(L.SCAN)
  self.spark:Hide()
end

-- ---------------------------------------------------------------------------
-- show / hide

function UI:ShowAtAuctionHouse()
  self:Create()
  local ah = _G.AuctionHouseFrame
  if ah and not self.userMoved then
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, 0)
  end
  self:CreateAuctionHouseButton()
  self.frame:Show()
  self:Refresh()
end

-- small crate button on the right edge of the Auction House, shown while the window is closed
function UI:CreateAuctionHouseButton()
  local ah = _G.AuctionHouseFrame
  if not ah or self.ahButton then return end
  local b = CreateFrame("Button", nil, ah)
  b:SetSize(34, 34)
  b:SetPoint("TOPLEFT", ah, "TOPRIGHT", 4, -40)
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetAllPoints()
  t:SetTexture(ICON)
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b:SetScript("OnClick", function() UI:Toggle() end)
  Tip(b, "Waylaid Crate", L.AH_BTN_TIP)
  self.ahButton = b
  self.frame:HookScript("OnShow", function() b:Hide() end)
  self.frame:HookScript("OnHide", function() b:Show() end)
  b:SetShown(not self.frame:IsShown())
end

function UI:OnAuctionHouseClosed()
  if self.frame then self.frame:Hide() end
end

function UI:Show()
  self:Create()
  self.frame:Show()
  self:Refresh()
end

function UI:Toggle()
  self:Create()
  if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end
