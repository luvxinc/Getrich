local addonName, WC = ...

-- Window shell: title, tab bar, scan controls and progress bar shared by both tabs.
-- Tab contents live in UICrates.lua (Merchant's Favor) and UIWrits.lua (reputation).
local UI = { tabs = {} }
WC.UI = UI
local L = WC.L

local W, H = 700, 700
UI.W = W
UI.ROW_H = 32
local PANEL_TOP = -150
local ICON = "Interface\\Icons\\INV_Crate_07"
local WHITE = "Interface\\Buttons\\WHITE8X8"

UI.C_GREEN  = "|cff4cff6a"
UI.C_ORANGE = "|cffff9a2e"
UI.C_GREY   = "|cff8a8f98"
UI.C_UNCOMMON = "|cff1eff00"
UI.RANK_COLOR = { [1] = { 1, 0.82, 0.1 }, [2] = { 0.82, 0.85, 0.9 }, [3] = { 0.85, 0.55, 0.3 } }
local C_GREY = UI.C_GREY

-- ---------------------------------------------------------------------------
-- helpers shared by both tabs

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
function WC:SearchAuctionHouse(itemID)
  local name = WC:ItemName(itemID)
  local ah = _G.AuctionHouseFrame
  if not (ah and ah:IsShown()) then
    WC:Print(L.OPEN_AH_FIRST)
    return
  end
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
    bar:StartSearch()
  end)
  if not ok then WC:Print(L.SEARCH_FAILED:format(name)) end
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
    UI:Refresh()
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
    UI:Refresh()
  end)
  Tip(b, label, tip)
  self.cyclers[#self.cyclers + 1] = b
  return fs, b
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

-- Scrolling list with column headers.
-- cols: { key = { x = left } or { r = right edge }, w = width, justify }
function UI:List(parent, headY, top, cols, rowCount, buildRow)
  local list = { cols = cols, rows = {} }
  list.headers = {}
  for key, col in pairs(cols) do
    local fs = Font(parent, "GameFontDisableSmall", col.justify or (col.r and "RIGHT" or "LEFT"), col.w)
    if col.r then fs:SetPoint("TOPLEFT", col.r - col.w, headY) else fs:SetPoint("TOPLEFT", col.x, headY) end
    list.headers[key] = fs
  end
  local scroll = CreateFrame("ScrollFrame", nil, parent)
  scroll:SetPoint("TOPLEFT", 0, top)
  scroll:SetPoint("BOTTOMRIGHT", -10, 2)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(W - 38, UI.ROW_H)
  scroll:SetScrollChild(content)
  scroll:EnableMouseWheel(true)
  local thumb = parent:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(0.95, 0.75, 0.2, 0.6)
  thumb:SetWidth(4)
  local track = parent:CreateTexture(nil, "ARTWORK")
  track:SetColorTexture(1, 1, 1, 0.05)
  track:SetPoint("TOPRIGHT", 0, top)
  track:SetPoint("BOTTOMRIGHT", 0, 2)
  track:SetWidth(4)
  list.scroll, list.content, list.thumb, list.top, list.parent = scroll, content, thumb, top, parent
  function list:UpdateThumb()
    local viewH = scroll:GetHeight()
    local contentH = content:GetHeight()
    if contentH <= viewH + 1 then thumb:Hide(); return end
    local thumbH = math.max(24, viewH * viewH / contentH)
    local off = scroll:GetVerticalScroll() / (contentH - viewH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, top - off * (viewH - thumbH))
    thumb:SetHeight(thumbH)
    thumb:Show()
  end
  scroll:SetScript("OnMouseWheel", function(s, delta)
    local maxOff = math.max(0, content:GetHeight() - s:GetHeight())
    s:SetVerticalScroll(math.min(maxOff, math.max(0, s:GetVerticalScroll() - delta * UI.ROW_H * 2)))
    list:UpdateThumb()
  end)
  for i = 1, rowCount do
    local row = CreateFrame("Button", nil, content)
    row:SetSize(W - 38, UI.ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * UI.ROW_H)
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
    buildRow(row, i)
    list.rows[i] = row
  end
  local empty = Font(parent, "GameFontDisable", "CENTER", W - 80)
  empty:SetPoint("TOP", scroll, "TOP", 0, -40)
  empty:SetWordWrap(true)
  list.empty = empty
  return list
end

-- place a row font string into a column
function UI.Cell(row, col, template, y)
  local fs = Font(row, template, col.r and "RIGHT" or "LEFT", col.w)
  if col.r then fs:SetPoint("RIGHT", row, "LEFT", col.r, 0) else fs:SetPoint("TOPLEFT", col.x, y or 0) end
  return fs
end

-- fill rows from entries; fillRow(row, entry, isTop)
function UI:FillList(list, vis, fillRow)
  local top
  for _, e in ipairs(vis) do if e.rank == 1 then top = e break end end
  for i, row in ipairs(list.rows) do
    local e = vis[i]
    row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
    if e then
      row.entry = e
      local isTop = (e == top)
      row.accent:SetShown(isTop)
      if isTop then row.bg:SetColorTexture(0.95, 0.72, 0.15, 0.1) end
      if e.rank then
        local c = UI.RANK_COLOR[e.rank]
        row.rank:SetText(e.rank)
        if c then row.rank:SetTextColor(c[1], c[2], c[3]) else row.rank:SetTextColor(0.55, 0.57, 0.6) end
      else
        row.rank:SetText("–")
        row.rank:SetTextColor(0.4, 0.42, 0.45)
      end
      fillRow(row, e, isTop)
      row:Show()
    else
      row.entry = nil
      row:Hide()
    end
  end
  list.content:SetHeight(math.max(UI.ROW_H, #vis * UI.ROW_H))
  local maxOff = math.max(0, list.content:GetHeight() - list.scroll:GetHeight())
  if list.scroll:GetVerticalScroll() > maxOff then list.scroll:SetVerticalScroll(maxOff) end
  list:UpdateThumb()
  if #vis == 0 then
    list.empty:SetText(L.EMPTY_LIST)
    list.empty:Show()
  else
    list.empty:Hide()
  end
  return top
end

-- ---------------------------------------------------------------------------
-- window

function UI:Create()
  if self.frame then return end
  self.checks, self.cyclers = {}, {}
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
  tinsert(UISpecialFrames, "WaylaidCrateFrame")

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
  version:SetText("v" .. (WC.VERSION or "?"))
  self.subtitle = Font(f, "GameFontDisableSmall", "LEFT", W - 90)
  self.subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)

  -- tab bar
  self.tabButtons = {}
  local function TabButton(key, text, anchor)
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(26)
    local fs = Font(b, "GameFontNormal", "CENTER")
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText(text)
    b:SetWidth(fs:GetStringWidth() + 36)
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
    if anchor then b:SetPoint("LEFT", anchor, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 14, -56) end
    b:SetScript("OnClick", function() UI:SelectTab(key) end)
    self.tabButtons[key] = b
    return b
  end
  local t1 = TabButton("crates", L.TAB_CRATES)
  TabButton("writs", L.TAB_WRITS, t1)
  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.42, 0.33, 0.14, 0.6)
  rule:SetPoint("TOPLEFT", 12, -82)
  rule:SetPoint("TOPRIGHT", -12, -82)
  rule:SetHeight(1)

  -- scan button + auto-scan switch
  local scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scan:SetSize(150, 24)
  scan:SetPoint("TOPLEFT", 14, -92)
  scan:SetText(L.SCAN)
  scan:SetScript("OnClick", function()
    if WC.Scanner.active then WC.Scanner:Stop(L.STOP_MANUAL) else WC.Scanner:Start(WC:Tab()) end
  end)
  scan:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(L["SCAN_TIP_" .. WC:Tab()])
    GameTooltip:AddLine(L.SCAN_TIP, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  scan:SetScript("OnLeave", GameTooltip_Hide)
  self.scanButton = scan
  self:Check(f, L.AUTO_SCAN, 178, -93, "autoScan", L.AUTO_SCAN_TIP)

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
  local barText = Font(bar, "GameFontHighlightSmall", "CENTER")
  barText:SetPoint("CENTER")
  barText:SetWidth(W - 40)
  self.bar, self.spark, self.barText = bar, spark, barText

  -- tab panels
  for key, tab in pairs(self.tabs) do
    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT", 14, PANEL_TOP - 6)
    panel:SetPoint("BOTTOMRIGHT", -14, 30)
    tab.panel = panel
    tab:Create(panel)
    panel:Hide()
  end

  -- footer
  local foot = Font(f, "GameFontDisableSmall", "LEFT", W - 30)
  foot:SetPoint("BOTTOMLEFT", 14, 12)
  foot:SetText(L.FOOTER)

  self:SetIdleText()
  self:SelectTab(WC:Tab())
end

function UI:SelectTab(key)
  if not self.frame then return end
  key = (key == "writs") and "writs" or "crates"
  if WaylaidCrateDB then WaylaidCrateDB.tab = key end
  for k, b in pairs(self.tabButtons) do
    local on = (k == key)
    b.line:SetShown(on)
    b.bg:SetColorTexture(1, 1, 1, on and 0.06 or 0)
    if on then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.55, 0.57, 0.6) end
  end
  for k, tab in pairs(self.tabs) do tab.panel:SetShown(k == key) end
  self.subtitle:SetText(key == "writs" and L.SUBTITLE_WRITS or L.SUBTITLE_CRATES)
  if not WC.Scanner.active then self:SetIdleText() end
  self:Refresh()
end

function UI:Refresh()
  if not self.frame then return end
  local db = WaylaidCrateDB or {}
  for _, cb in ipairs(self.checks) do cb:SetChecked(db[cb.key]) end
  for _, b in ipairs(self.cyclers) do b:SetText((tonumber(db[b.key]) or 0) .. "/" .. b.max) end
  local tab = self.tabs[WC:Tab()]
  if tab and tab.panel then tab:Refresh() end
end

-- ---------------------------------------------------------------------------
-- progress bar states

local function StopSpark(self) self.spark:Hide() end

function UI:SetIdleText()
  if not self.bar then return end
  local db = WaylaidCrateDB
  local at = db and type(db.scannedAt) == "table" and db.scannedAt[WC:Tab()]
  self.bar:SetStatusBarColor(0.35, 0.37, 0.4)
  if at then
    self.bar:SetValue(1)
    self.barText:SetText(L.IDLE_LAST:format(date("%m/%d %H:%M", at)))
  else
    self.bar:SetValue(0)
    self.barText:SetText(L.IDLE_NEVER)
  end
  self.scanButton:SetText(L.SCAN)
  StopSpark(self)
end

function UI:OnScanStart(kind, total)
  self:Create()
  self.frame:Show()
  if WC:Tab() ~= kind then self:SelectTab(kind) end
  self.scanButton:SetText(L.STOP_SCAN)
  self.bar:SetStatusBarColor(1, 0.76, 0.18)
  self.bar:SetValue(0)
  self.barText:SetText(L.SCAN_STARTING:format(total))
  self.spark:Show()
  self:Refresh()
end

function UI:OnScanProgress(kind, done, total, itemID)
  if not self.frame then return end
  local pct = total > 0 and done / total or 0
  self.bar:SetValue(pct)
  self.spark:ClearAllPoints()
  self.spark:SetPoint("CENTER", self.bar, "LEFT", self.bar:GetWidth() * pct, 0)
  local left = math.ceil((total - done) * 0.8)
  self.barText:SetText(L.SCAN_PROGRESS:format(L.KIND[kind] or "", done + 1, total, WC:ItemName(itemID), left))
end

function UI:OnScanDone(kind, total, listed, missing, seconds)
  if not self.frame then return end
  self.scanButton:SetText(L.RESCAN)
  self.bar:SetStatusBarColor(0.25, 0.75, 0.35)
  self.bar:SetValue(1)
  StopSpark(self)
  self.barText:SetText(L.SCAN_DONE:format(date("%H:%M"), total, listed, missing, math.floor(seconds + 0.5)))
  self:Refresh()
  local tab = self.tabs[kind]
  local msg = tab and tab:BestMessage()
  WC:Print(msg or L.PRINT_NONE)
end

function UI:OnScanStopped(kind, reason, done, total)
  if not self.frame then return end
  self.scanButton:SetText(L.SCAN)
  self.bar:SetStatusBarColor(0.55, 0.45, 0.3)
  StopSpark(self)
  self.barText:SetText(L.STOPPED_FMT:format(reason or L.STOPPED, math.max(done, 0), total))
  self:Refresh()
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
