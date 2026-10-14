local addonName, WC = ...

local UI = {}
WC.UI = UI
local L = WC.L

local W, H = 700, 672
local ROW_H = 32
local LIST_TOP = -284
local HEAD_Y = -266
local ICON = "Interface\\Icons\\INV_Crate_07"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local C_GREEN  = "|cff4cff6a"
local C_ORANGE = "|cffff9a2e"
local C_GREY   = "|cff8a8f98"
local C_UNCOMMON = "|cff1eff00"
local RANK_COLOR = { [1] = { 1, 0.82, 0.1 }, [2] = { 0.82, 0.85, 0.9 }, [3] = { 0.85, 0.55, 0.3 } }

-- column layout inside a row: left edge / right edge, width
local COL = {
  rank  = { x = 4, w = 26 },
  crate = { x = 36, w = 168 },
  fill  = { x = 208, w = 172 },
  price = { r = 458, w = 76 },
  mats  = { r = 534, w = 72 },
  rep   = { r = 580, w = 42 },
  per   = { r = 656, w = 72 },
}

-- ---------------------------------------------------------------------------
-- helpers

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
local Money = WC.Money

-- 55 -> "55", 5.75 -> "5.8"
local function Num(v)
  local s = string.format("%.1f", v or 0)
  return (s:gsub("%.0$", ""))
end

local function Pct(fraction)
  return Num((fraction or 0) * 100) .. "%"
end

local function CrateName(crate)
  return (crate.crafted and C_UNCOMMON or "|cffffffff") .. WC:CrateShortName(crate) .. "|r"
end

local function Font(parent, template, justify, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", template)
  if justify then fs:SetJustifyH(justify) end
  if width then fs:SetWidth(width) end
  fs:SetWordWrap(false)
  return fs
end

local function Backdrop(frame, bg, border)
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  frame:SetBackdropColor(unpack(bg))
  frame:SetBackdropBorderColor(unpack(border))
end

local function Tip(widget, title, text)
  widget:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", GameTooltip_Hide)
end

local STATUS_TEXT = {
  nocrate   = L.ST_NOCRATE,
  nomats    = L.ST_NOMATS,
  short     = L.ST_SHORT,
  unscanned = L.ST_UNSCANNED,
}

local function StandingText()
  local _, reaction = WC:Standing()
  if not reaction then return L.BEST_NEED_FRIENDLY end
  local label = _G["FACTION_STANDING_LABEL" .. reaction] or tostring(reaction)
  local color = reaction >= 5 and C_GREEN or C_ORANGE
  return L.BEST_STANDING:format(color .. label .. "|r")
end

-- ---------------------------------------------------------------------------
-- click to search: puts the item name into the Auction House search box and searches

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

-- an invisible button over part of a row; underlines on hover
local function Hotspot(parent, kind, getEntry)
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
    if not e then return end
    if kind == "crate" then
      WC:SearchAuctionHouse(e.crate.id)
    elseif e.bestIdx then
      WC:SearchAuctionHouse(e.opts[e.bestIdx].itemID)
    end
  end)
  b:SetScript("OnEnter", function(s)
    local e = getEntry()
    if e then UI:ShowTooltip(s, e, kind) end
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

-- ---------------------------------------------------------------------------
-- window

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
  local sub = Font(f, "GameFontDisableSmall", "LEFT")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  sub:SetText(L.SUBTITLE)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 0, 0)
  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.42, 0.33, 0.14, 0.6)
  rule:SetPoint("TOPLEFT", 12, -50)
  rule:SetPoint("TOPRIGHT", -12, -50)
  rule:SetHeight(1)

  -- scan button + auto-scan switch
  local scan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  scan:SetSize(150, 24)
  scan:SetPoint("TOPLEFT", 14, -60)
  scan:SetText(L.SCAN)
  scan:SetScript("OnClick", function()
    if WC.Scanner.active then WC.Scanner:Stop(L.STOP_MANUAL) else WC.Scanner:Start() end
  end)
  Tip(scan, L.SCAN_TIP_TITLE, L.SCAN_TIP)
  self.scanButton = scan
  self.checks = {}
  self.checks.autoScan = self:Check(f, L.AUTO_SCAN, 178, -61, "autoScan", L.AUTO_SCAN_TIP)

  -- priority switch: Merchant's Favor / Reputation
  local repBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  repBtn:SetSize(104, 22)
  repBtn:SetPoint("TOPRIGHT", -14, -61)
  repBtn:SetText(L.MODE_REP)
  local favBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  favBtn:SetSize(104, 22)
  favBtn:SetPoint("RIGHT", repBtn, "LEFT", -4, 0)
  favBtn:SetText(L.MODE_FAVOR)
  local modeLabel = Font(f, "GameFontNormalSmall", "RIGHT")
  modeLabel:SetPoint("RIGHT", favBtn, "LEFT", -6, 0)
  modeLabel:SetText(L.MODE_LABEL)
  local function SetMode(mode)
    if WaylaidCrateDB then WaylaidCrateDB.mode = mode end
    UI:Refresh()
  end
  favBtn:SetScript("OnClick", function() SetMode("favor") end)
  repBtn:SetScript("OnClick", function() SetMode("rep") end)
  Tip(favBtn, L.MODE_FAVOR, L.MODE_TIP_FAVOR)
  Tip(repBtn, L.MODE_REP, L.MODE_TIP_REP)
  self.modeButtons = { favor = favBtn, rep = repBtn }

  -- progress bar
  local barBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
  barBg:SetPoint("TOPLEFT", 14, -92)
  barBg:SetPoint("TOPRIGHT", -14, -92)
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

  -- filters (each switch starts after the previous label, so longer English text still fits)
  local x = 14
  local c1 = self:Check(f, L.ONLY_MINE, x, -120, "onlyMine", L.ONLY_MINE_TIP)
  x = x + 22 + c1.labelWidth + 18
  local c2 = self:Check(f, L.HIDE_NO_CRATE, x, -120, "hideNoCrate", L.HIDE_NO_CRATE_TIP)
  x = x + 22 + c2.labelWidth + 18
  local c3 = self:Check(f, L.HIDE_NO_MATS, x, -120, "hideNoMats", L.HIDE_NO_MATS_TIP)
  self.checks.onlyMine, self.checks.hideNoCrate, self.checks.hideNoMats = c1, c2, c3
  local hidden = Font(f, "GameFontDisableSmall", "RIGHT", 90)
  hidden:SetPoint("TOPRIGHT", -16, -125)
  self.hiddenText = hidden

  -- bonuses: Legacy perks (set by the player) + racial (detected)
  self.cyclers = {}
  local perfLabel, perfBtn = self:Cycler(f, 14, -148, L.PERF_LABEL, "perfRank", 3, L.PERF_TIP)
  local x2 = 14 + perfLabel:GetStringWidth() + 6 + 44 + 22
  local _, diploBtn = self:Cycler(f, x2, -148, L.DIPLO_LABEL, "diplomatRank", 5, L.DIPLO_TIP)
  self.cyclers.perfRank, self.cyclers.diplomatRank = perfBtn, diploBtn
  local race = Font(f, "GameFontDisableSmall", "RIGHT", 260)
  race:SetPoint("TOPRIGHT", -16, -153)
  self.raceText = race

  -- best plan panel
  local best = CreateFrame("Frame", nil, f, "BackdropTemplate")
  best:SetPoint("TOPLEFT", 14, -176)
  best:SetPoint("TOPRIGHT", -14, -176)
  best:SetHeight(78)
  Backdrop(best, { 0.95, 0.72, 0.15, 0.09 }, { 0.95, 0.75, 0.2, 0.85 })
  local bLabel = Font(best, "GameFontNormalSmall", "LEFT")
  bLabel:SetPoint("TOPLEFT", 12, -9)
  local bName = Font(best, "GameFontNormalLarge", "LEFT", 400)
  bName:SetPoint("TOPLEFT", 12, -25)
  local bDetail = Font(best, "GameFontHighlightSmall", "LEFT", 480)
  bDetail:SetPoint("TOPLEFT", 12, -50)
  local bPerLabel = Font(best, "GameFontNormalSmall", "RIGHT", 170)
  bPerLabel:SetPoint("TOPRIGHT", -12, -9)
  local bPer = Font(best, "GameFontNormalLarge", "RIGHT", 180)
  bPer:SetPoint("TOPRIGHT", -12, -25)
  local bNet = Font(best, "GameFontDisableSmall", "RIGHT", 190)
  bNet:SetPoint("TOPRIGHT", -12, -50)
  local bEmpty = Font(best, "GameFontDisable", "CENTER", W - 60)
  bEmpty:SetPoint("CENTER")
  best:EnableMouse(true)
  best:SetScript("OnEnter", function(p) if p.entry then UI:ShowTooltip(p, p.entry) end end)
  best:SetScript("OnLeave", GameTooltip_Hide)
  self.best = { frame = best, name = bName, detail = bDetail, per = bPer, perLabel = bPerLabel, net = bNet, label = bLabel, empty = bEmpty }
  local bestCrate = Hotspot(best, "crate", function() return best.entry end)
  bestCrate:SetPoint("TOPLEFT", 8, -21)
  bestCrate:SetSize(404, 24)
  local bestMat = Hotspot(best, "mat", function() return best.entry end)
  bestMat:SetPoint("TOPLEFT", 8, -46)
  bestMat:SetSize(484, 18)
  self.best.crateBtn, self.best.matBtn = bestCrate, bestMat

  -- column headers
  local function Header(col, justify)
    local fs = Font(f, "GameFontDisableSmall", justify or "LEFT", col.w)
    if col.r then fs:SetPoint("TOPLEFT", 14 + col.r - col.w, HEAD_Y) else fs:SetPoint("TOPLEFT", 14 + col.x, HEAD_Y) end
    return fs
  end
  Header(COL.rank, "CENTER"):SetText("#")
  Header(COL.crate):SetText(L.HEAD_CRATE)
  self.hFill = Header(COL.fill)
  Header(COL.price, "RIGHT"):SetText(L.HEAD_CRATE_PRICE)
  self.hMats = Header(COL.mats, "RIGHT")
  Header(COL.rep, "RIGHT"):SetText(L.HEAD_REP)
  self.hPer = Header(COL.per, "RIGHT")

  -- scrolling list
  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", 14, LIST_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -24, 34)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(W - 38, ROW_H)
  scroll:SetScrollChild(content)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(s, delta)
    local maxOff = math.max(0, content:GetHeight() - s:GetHeight())
    local off = math.min(maxOff, math.max(0, s:GetVerticalScroll() - delta * ROW_H * 2))
    s:SetVerticalScroll(off)
    UI:UpdateThumb()
  end)
  local track = f:CreateTexture(nil, "ARTWORK")
  track:SetColorTexture(1, 1, 1, 0.05)
  track:SetPoint("TOPRIGHT", -14, LIST_TOP)
  track:SetPoint("BOTTOMRIGHT", -14, 34)
  track:SetWidth(4)
  local thumb = f:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(0.95, 0.75, 0.2, 0.6)
  thumb:SetWidth(4)
  self.scroll, self.content, self.track, self.thumb = scroll, content, track, thumb

  local empty = Font(f, "GameFontDisable", "CENTER", W - 80)
  empty:SetPoint("TOP", scroll, "TOP", 0, -40)
  self.emptyText = empty

  self.rows = {}
  for i = 1, #WC.CRATES do self.rows[i] = self:CreateRow(content, i) end

  -- footer
  local foot = Font(f, "GameFontDisableSmall", "LEFT", W - 30)
  foot:SetPoint("BOTTOMLEFT", 14, 12)
  foot:SetText(L.FOOTER)

  self:SetIdleText()
  self:Refresh()
end

function UI:Check(parent, label, x, y, key, tip)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("TOPLEFT", x, y)
  local fs = Font(cb, "GameFontHighlightSmall", "LEFT")
  fs:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  fs:SetText(label)
  cb.labelWidth = fs:GetStringWidth()
  cb:SetHitRectInsets(0, -(cb.labelWidth + 6), 0, 0)
  cb:SetChecked(WaylaidCrateDB and WaylaidCrateDB[key])
  cb:SetScript("OnClick", function(b)
    if WaylaidCrateDB then WaylaidCrateDB[key] = b:GetChecked() and true or false end
    UI:Refresh()
  end)
  Tip(cb, label, tip)
  return cb
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
  return fs, b
end

local function Place(fs, row, col)
  if col.r then fs:SetPoint("RIGHT", row, "LEFT", col.r, 0) else fs:SetPoint("TOPLEFT", col.x, 0) end
end

function UI:CreateRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(W - 38, ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
  row.bg = bg
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.07)
  local accent = row:CreateTexture(nil, "ARTWORK")
  accent:SetColorTexture(0.95, 0.75, 0.2, 1)
  accent:SetPoint("TOPLEFT")
  accent:SetPoint("BOTTOMLEFT")
  accent:SetWidth(2)
  row.accent = accent

  row.rank = Font(row, "GameFontNormal", "CENTER", COL.rank.w)
  row.rank:SetPoint("LEFT", COL.rank.x, 0)
  row.name = Font(row, "GameFontHighlight", "LEFT", COL.crate.w)
  row.name:SetPoint("TOPLEFT", COL.crate.x, -3)
  row.sub = Font(row, "GameFontDisableSmall", "LEFT", COL.crate.w)
  row.sub:SetPoint("TOPLEFT", COL.crate.x, -18)
  row.fill = Font(row, "GameFontHighlightSmall", "LEFT", COL.fill.w)
  row.fill:SetPoint("TOPLEFT", COL.fill.x, -4)
  row.fillSub = Font(row, "GameFontDisableSmall", "LEFT", COL.fill.w)
  row.fillSub:SetPoint("TOPLEFT", COL.fill.x, -18)
  row.price = Font(row, "GameFontHighlightSmall", "RIGHT", COL.price.w)
  Place(row.price, row, COL.price)
  row.mats = Font(row, "GameFontHighlightSmall", "RIGHT", COL.mats.w)
  Place(row.mats, row, COL.mats)
  row.rep = Font(row, "GameFontHighlightSmall", "RIGHT", COL.rep.w)
  Place(row.rep, row, COL.rep)
  row.per = Font(row, "GameFontHighlight", "RIGHT", COL.per.w)
  Place(row.per, row, COL.per)

  row.crateBtn = Hotspot(row, "crate", function() return row.entry end)
  row.crateBtn:SetPoint("TOPLEFT", COL.crate.x - 4, 0)
  row.crateBtn:SetSize(COL.crate.w + 4, ROW_H)
  row.matBtn = Hotspot(row, "mat", function() return row.entry end)
  row.matBtn:SetPoint("TOPLEFT", COL.fill.x - 3, 0)
  row.matBtn:SetSize(COL.fill.w + 4, ROW_H)

  row:SetScript("OnEnter", function(r) if r.entry then UI:ShowTooltip(r, r.entry) end end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  return row
end

-- ---------------------------------------------------------------------------
-- rendering

local function OptLine(e, j)
  local o = e.opts[j]
  return o.qty .. " × " .. WC:ItemName(o.itemID)
end

local function Colored(text, color)
  return color .. (text:gsub("|r", "|r" .. color)) .. "|r"
end

function UI:FillRow(row, e, isTop, mode)
  local c = e.crate
  row.entry = e
  row:SetAlpha(e.locked and 0.5 or 1)
  row.accent:SetShown(isTop)
  if isTop then row.bg:SetColorTexture(0.95, 0.72, 0.15, 0.1) end

  if e.rank then
    local col = RANK_COLOR[e.rank]
    row.rank:SetText(e.rank)
    if col then row.rank:SetTextColor(col[1], col[2], col[3]) else row.rank:SetTextColor(0.55, 0.57, 0.6) end
  else
    row.rank:SetText("–")
    row.rank:SetTextColor(0.4, 0.42, 0.45)
  end

  row.name:SetText(CrateName(c))
  local lvlText = e.locked and ("|cffff5a4a" .. L.NEED_LEVEL_FMT:format(c.lvl) .. "|r") or L.LEVEL_FMT:format(c.lvl)
  row.sub:SetText(WC.TIER_NAME[c.tier] .. " · " .. lvlText .. " · " .. L.FAVOR_FMT:format(Num(e.favorExp)))
  row.price:SetText(e.crateCost and Money(e.crateCost) or (e.crateRes and (C_ORANGE .. L.NO_STOCK .. "|r") or Money(nil)))

  if mode == "rep" then
    row.matBtn:Hide()
    if e.crateCost then
      row.fill:SetText(C_GREEN .. L.REP_ROUTE .. "|r")
      row.fillSub:SetText(L.REP_ROUTE_SUB:format(WC.REP.receiptFavor))
    else
      row.fill:SetText(C_ORANGE .. (e.crateRes and L.ST_NOCRATE or L.ST_UNSCANNED) .. "|r")
      row.fillSub:SetText(L.REP_ROUTE_SUB:format(WC.REP.receiptFavor))
    end
    row.mats:SetText(e.receiptGold and Money(e.receiptGold) or (C_GREY .. L.RECEIPT_UNPRICED .. "|r"))
    row.rep:SetText(C_GREEN .. "+" .. Num(e.repGain) .. "|r")
    row.per:SetText(e.perRep and Colored(Money(e.perRep), isTop and C_GREEN or "|cffffffff") or Money(nil))
    return
  end

  -- Merchant's Favor mode
  row.matBtn:SetShown(e.bestIdx ~= nil)
  local stocked = 0
  for _, o in ipairs(e.opts) do if o.cost then stocked = stocked + 1 end end
  if e.bestIdx then
    local o = e.opts[e.bestIdx]
    row.fill:SetText(C_GREEN .. OptLine(e, e.bestIdx) .. "|r")
    row.fillSub:SetText(L.PICK_FMT:format(#e.opts, stocked) .. (o.note and (C_ORANGE .. " !|r") or ""))
  else
    row.fill:SetText(C_ORANGE .. (STATUS_TEXT[e.status] or STATUS_TEXT.nomats) .. "|r")
    row.fillSub:SetText(L.PICK_ONE_FMT:format(#e.opts))
  end
  if e.status == "nocrate" and e.bestIdx then
    row.fillSub:SetText(C_ORANGE .. L.ST_NOCRATE .. "|r")
  end
  row.mats:SetText(Money(e.matCost))
  row.rep:SetText(C_GREY .. Num(e.repFill) .. "|r")   -- filled crates give 0 reputation
  row.per:SetText(e.perFavor and Colored(Money(e.perFavor), isTop and C_GREEN or "|cffffffff") or Money(nil))
end

function UI:Refresh()
  if not self.frame then return end
  local db = WaylaidCrateDB or {}
  local mode = WC:Mode()
  for k, cb in pairs(self.checks) do cb:SetChecked(db[k]) end
  for k, b in pairs(self.cyclers) do b:SetText((tonumber(db[k]) or 0) .. "/" .. b.max) end
  for m, b in pairs(self.modeButtons) do
    local fs = b.GetFontString and b:GetFontString()
    if m == mode then
      b:LockHighlight()
      if fs then fs:SetTextColor(1, 1, 1) end
    else
      b:UnlockHighlight()
      if fs then fs:SetTextColor(0.55, 0.55, 0.55) end
    end
  end
  self.checks.hideNoMats:SetAlpha(mode == "rep" and 0.4 or 1)   -- materials don't matter for reputation
  self.raceText:SetText(WC:HasDiplomacy() and (C_GREEN .. L.RACE_HAS .. "|r") or L.RACE_NONE)

  if mode == "rep" then
    self.hFill:SetText(L.HEAD_FILL_REP)
    self.hMats:SetText(L.HEAD_RECEIPT)
    self.hPer:SetText(L.HEAD_PER_REP)
  else
    self.hFill:SetText(L.HEAD_FILL)
    self.hMats:SetText(L.HEAD_MATS)
    self.hPer:SetText(L.HEAD_PER)
  end

  local all = WC:Evaluate()
  local vis = WC:Visible(all)
  local top = nil
  for _, e in ipairs(vis) do if e.rank == 1 then top = e break end end

  for i, row in ipairs(self.rows) do
    local e = vis[i]
    row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
    if e then
      self:FillRow(row, e, e == top, mode)
      row:Show()
    else
      row.entry = nil
      row:Hide()
    end
  end
  self.content:SetHeight(math.max(ROW_H, #vis * ROW_H))
  local maxOff = math.max(0, self.content:GetHeight() - self.scroll:GetHeight())
  if self.scroll:GetVerticalScroll() > maxOff then self.scroll:SetVerticalScroll(maxOff) end
  self:UpdateThumb()

  local hiddenCount = #all - #vis
  self.hiddenText:SetText(hiddenCount > 0 and L.HIDDEN_N:format(hiddenCount) or "")
  if #vis == 0 then
    self.emptyText:SetText(L.EMPTY_LIST)
    self.emptyText:SetWordWrap(true)
    self.emptyText:Show()
  else
    self.emptyText:Hide()
  end

  self:RenderBest(top, mode)
end

function UI:RenderBest(e, mode)
  local b = self.best
  b.frame.entry = e
  local show = e ~= nil
  for _, k in ipairs({ "name", "detail", "per", "perLabel", "net", "label" }) do b[k]:SetShown(show) end
  b.empty:SetShown(not show)
  b.crateBtn:SetShown(show)
  b.matBtn:SetShown(show and mode ~= "rep")
  if not e then
    b.frame:SetBackdropBorderColor(0.35, 0.33, 0.3, 0.8)
    b.frame:SetBackdropColor(1, 1, 1, 0.03)
    b.empty:SetText(WC.Scanner.active and L.BEST_EMPTY_SCANNING or L.BEST_EMPTY)
    return
  end
  b.frame:SetBackdropBorderColor(0.95, 0.75, 0.2, 0.85)
  b.frame:SetBackdropColor(0.95, 0.72, 0.15, 0.09)
  local c = e.crate
  b.name:SetText(CrateName(c) .. "  " .. C_GREY .. WC.TIER_NAME[c.tier] .. " · " .. L.LEVEL_FMT:format(c.lvl) .. "|r")
  if mode == "rep" then
    b.label:SetText(L.BEST_LABEL_REP)
    b.perLabel:SetText(L.PER_REP_COST)
    b.detail:SetText(L.BEST_DETAIL_REP:format(Money(e.crateCost), WC.REP.receiptFavor,
      e.receiptGold and Money(e.receiptGold) or "?", C_GREEN .. Num(e.repGain) .. "|r"))
    b.per:SetText(Money(e.perRep))
    b.net:SetText(StandingText())
  else
    b.label:SetText(L.BEST_LABEL)
    b.perLabel:SetText(L.PER_FAVOR_COST)
    local o = e.opts[e.bestIdx]
    b.detail:SetText(L.BEST_DETAIL:format(Money(e.crateCost), C_GREEN .. o.qty .. " × " .. WC:ItemName(o.itemID) .. "|r", Money(e.matCost), Money(c.silver)))
    b.per:SetText(Money(e.perFavor))
    b.net:SetText(L.BEST_NET:format(Money(e.net), Num(e.favorExp)))
  end
end

function UI:UpdateThumb()
  if not self.scroll then return end
  local viewH = self.scroll:GetHeight()
  local contentH = self.content:GetHeight()
  if contentH <= viewH + 1 then self.thumb:Hide(); return end
  local trackH = viewH
  local thumbH = math.max(24, trackH * viewH / contentH)
  local off = self.scroll:GetVerticalScroll() / (contentH - viewH)
  self.thumb:ClearAllPoints()
  self.thumb:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -14, LIST_TOP - off * (trackH - thumbH))
  self.thumb:SetHeight(thumbH)
  self.thumb:Show()
end

function UI:ShowTooltip(owner, e, hint)
  local c = e.crate
  local mode = WC:Mode()
  local favorBonus, repBonus = WC:FavorBonus(), WC:RepBonus()
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(CrateName(c))
  GameTooltip:AddLine(WC.TIER_NAME[c.tier] .. " · " .. L.NEED_LEVEL_FMT:format(c.lvl), 0.7, 0.7, 0.7)

  -- rewards
  GameTooltip:AddDoubleLine(L.TT_REWARD, L.TT_REWARD_VAL:format(c.favor, Money(c.silver)), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.TT_BONUS_FAVOR, Num(e.favorExp) .. (favorBonus > 0 and (C_GREEN .. " (+" .. Pct(favorBonus) .. ")|r") or ""), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.TT_REP_FILL, "0", 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.TT_REP_EMPTY, L.TT_REP_EMPTY_VAL:format(Num(e.repGain), WC.REP.receiptFavor), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.TT_BONUS_REP, "+" .. Pct(repBonus), 1, 0.82, 0, 1, 1, 1)

  local crateRight
  if e.crateCost then crateRight = Money(e.crateCost)
  elseif e.crateRes then crateRight = C_ORANGE .. L.TT_NOT_LISTED .. "|r"
  else crateRight = C_GREY .. L.TT_NOT_SCANNED .. "|r" end
  GameTooltip:AddDoubleLine(L.TT_CRATE_PRICE, crateRight, 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddLine(" ")

  if mode == "rep" then
    GameTooltip:AddDoubleLine(L.TT_RECEIPT, e.receiptGold and Money(e.receiptGold) or (C_GREY .. L.RECEIPT_UNPRICED .. "|r"), 1, 0.82, 0, 1, 1, 1)
    if e.perRep then
      GameTooltip:AddDoubleLine(L.TT_PER_REP, Money(e.perRep), 1, 0.82, 0, 0.3, 1, 0.4)
    end
    GameTooltip:AddLine(StandingText(), 0.8, 0.8, 0.8)
  else
    GameTooltip:AddLine(L.TT_FILL_HEAD, 1, 0.82, 0)
    for j, o in ipairs(e.opts) do
      local left = o.qty .. " × " .. WC:ItemName(o.itemID)
      local right
      local r = o.res
      if o.cost then
        right = Money(o.cost)
        if r and r.min then right = right .. C_GREY .. L.TT_UNIT:format((Money(r.min):gsub("|r", "|r" .. C_GREY))) .. "|r" end
      elseif not r then right = C_GREY .. L.TT_NOT_SCANNED .. "|r"
      elseif r.status == "short" then right = C_ORANGE .. L.TT_SHORT:format(r.avail or 0) .. "|r"
      elseif r.status == "timeout" then right = C_GREY .. L.TT_TIMEOUT .. "|r"
      else right = C_GREY .. L.NO_STOCK .. "|r" end
      if j == e.bestIdx then
        GameTooltip:AddDoubleLine(C_GREEN .. "» " .. left .. "|r", right .. "  " .. C_GREEN .. L.TT_RECOMMEND .. "|r")
      else
        GameTooltip:AddDoubleLine("   " .. left, right, 0.85, 0.85, 0.85)
      end
      if o.note and WC.NOTES[o.note] then
        GameTooltip:AddLine("      " .. WC.NOTES[o.note], 1, 0.6, 0.2)
      end
    end
    GameTooltip:AddLine(" ")
    if e.perFavor then
      GameTooltip:AddDoubleLine(L.TT_NET, Money(e.net), 1, 0.82, 0, 1, 1, 1)
      GameTooltip:AddDoubleLine(L.TT_PER, Money(e.perFavor), 1, 0.82, 0, 0.3, 1, 0.4)
    else
      GameTooltip:AddLine(STATUS_TEXT[e.status] or "", 1, 0.6, 0.2)
    end
    GameTooltip:AddLine(L.TT_METHOD, 0.55, 0.55, 0.55, true)
  end
  GameTooltip:AddLine(L.TT_FIRST, 0.55, 0.55, 0.55, true)

  if hint == "crate" then
    GameTooltip:AddLine(L.CLICK_CRATE, 0.3, 1, 0.4)
  elseif hint == "mat" and e.bestIdx then
    GameTooltip:AddLine(L.CLICK_MAT:format(OptLine(e, e.bestIdx)), 0.3, 1, 0.4)
  else
    GameTooltip:AddLine(mode == "rep" and L.CLICK_HINT_REP or L.CLICK_HINT, 0.3, 1, 0.4)
  end
  GameTooltip:Show()
end

-- ---------------------------------------------------------------------------
-- progress bar states

local function StopSpark(self) self.spark:Hide() end

function UI:SetIdleText()
  local db = WaylaidCrateDB
  if db and db.scannedAt then
    self.bar:SetStatusBarColor(0.35, 0.37, 0.4)
    self.bar:SetValue(1)
    self.barText:SetText(L.IDLE_LAST:format(date("%m/%d %H:%M", db.scannedAt)))
  else
    self.bar:SetStatusBarColor(0.35, 0.37, 0.4)
    self.bar:SetValue(0)
    self.barText:SetText(L.IDLE_NEVER)
  end
  StopSpark(self)
end

function UI:OnScanStart(total)
  self:Create()
  self.frame:Show()
  self.scanButton:SetText(L.STOP_SCAN)
  self.bar:SetStatusBarColor(1, 0.76, 0.18)
  self.bar:SetValue(0)
  self.barText:SetText(L.SCAN_STARTING:format(total))
  self.spark:Show()
  self:Refresh()
end

function UI:OnScanProgress(done, total, itemID)
  if not self.frame then return end
  local pct = total > 0 and done / total or 0
  self.bar:SetValue(pct)
  self.spark:ClearAllPoints()
  self.spark:SetPoint("CENTER", self.bar, "LEFT", self.bar:GetWidth() * pct, 0)
  local left = math.ceil((total - done) * 0.8)
  self.barText:SetText(L.SCAN_PROGRESS:format(done + 1, total, WC:ItemName(itemID), left))
end

function UI:OnScanDone(total, listed, missing, seconds)
  if not self.frame then return end
  self.scanButton:SetText(L.RESCAN)
  self.bar:SetStatusBarColor(0.25, 0.75, 0.35)
  self.bar:SetValue(1)
  StopSpark(self)
  self.barText:SetText(L.SCAN_DONE:format(date("%H:%M"), total, listed, missing, math.floor(seconds + 0.5)))
  self:Refresh()
  local repMode = WC:Mode() == "rep"
  for _, e in ipairs(WC:Visible(WC:Evaluate())) do
    if e.rank == 1 then
      if repMode then
        WC:Print(L.PRINT_BEST_REP:format(CrateName(e.crate), Money(e.perRep)))
      else
        WC:Print(L.PRINT_BEST:format(CrateName(e.crate), Money(e.perFavor)))
      end
      return
    end
  end
  WC:Print(L.PRINT_NONE)
end

function UI:OnScanStopped(reason, done, total)
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
