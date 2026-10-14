local addonName, WC = ...

-- Reputation tab: Craftsman's Writs (+ the empty crate with a receipt), cost per reputation point.
local UI = WC.UI
local L = WC.L
local Money, Num, Pct, Font = WC.Money, UI.Num, UI.Pct, UI.Font
local C_GREEN, C_ORANGE, C_GREY, C_UNCOMMON = UI.C_GREEN, UI.C_ORANGE, UI.C_GREY, UI.C_UNCOMMON

local Tab = {}
UI.tabs.writs = Tab

local COL = {
  rank  = { x = 4, w = 26, justify = "CENTER" },
  writ  = { x = 36, w = 196 },
  item  = { x = 236, w = 156 },
  price = { r = 462, w = 68 },
  cost  = { r = 534, w = 68 },
  rep   = { r = 578, w = 40 },
  per   = { r = 650, w = 68 },
}

local STATUS_TEXT = {
  nowrit = L.ST_NOWRIT,
  noitem = L.ST_NOITEM,
  short = L.ST_ITEM_SHORT,
  itemunscanned = L.ST_ITEM_UNSCANNED,
  unscanned = L.ST_UNSCANNED,
}

local function WritTitle(w) return WC:WritTitle(w) end

local function ItemLine(w)
  return w.qty .. " × " .. WC:ItemName(w.item)
end

local function CrateName(crate)
  return (crate.crafted and C_UNCOMMON or "|cffffffff") .. WC:CrateShortName(crate) .. "|r"
end

local function StandingLine()
  local label, reaction = UI.StandingText()
  if not label then return nil end
  local color = reaction >= 5 and C_GREEN or C_ORANGE
  return L.STANDING_FMT:format(color .. label .. "|r")
end

function Tab:Create(panel)
  UI:CheckRow(panel, -2, {
    { L.HIDE_NO_WRIT, "hideNoWrit", L.HIDE_NO_WRIT_TIP },
    { L.HIDE_NO_ITEM, "hideNoItem", L.HIDE_NO_ITEM_TIP },
    { L.HIDE_DONE, "hideDone", L.HIDE_DONE_TIP },
  })
  self.hidden = Font(panel, "GameFontDisableSmall", "RIGHT", 90)
  self.hidden:SetPoint("TOPRIGHT", -2, -7)

  local label = UI:Cycler(panel, 0, -28, L.DIPLO_LABEL, "diplomatRank", 5, L.DIPLO_TIP)
  self.race = Font(panel, "GameFontDisableSmall", "LEFT", 270)
  self.race:SetPoint("TOPLEFT", label:GetStringWidth() + 6 + 44 + 18, -33)
  self.standing = Font(panel, "GameFontDisableSmall", "RIGHT", 200)
  self.standing:SetPoint("TOPRIGHT", -2, -33)

  self.best = UI:BestPanel(panel, -54, self)

  self.list = UI:List(panel, -140, -156, COL, #WC.WRITS + 1, function(row)
    row.name = UI.Cell(row, COL.writ, "GameFontHighlight", -3)
    row.sub = UI.Cell(row, COL.writ, "GameFontDisableSmall", -18)
    row.item = UI.Cell(row, COL.item, "GameFontHighlightSmall", -4)
    row.itemSub = UI.Cell(row, COL.item, "GameFontDisableSmall", -18)
    row.price = UI.Cell(row, COL.price, "GameFontHighlightSmall")
    row.cost = UI.Cell(row, COL.cost, "GameFontHighlightSmall")
    row.rep = UI.Cell(row, COL.rep, "GameFontHighlightSmall")
    row.per = UI.Cell(row, COL.per, "GameFontHighlight")
    row.hotA = UI.Hotspot(row, self, "a", function() return row.entry end)
    row.hotA:SetPoint("TOPLEFT", COL.writ.x - 4, 0)
    row.hotA:SetSize(COL.writ.w + 4, UI.ROW_H)
    row.hotB = UI.Hotspot(row, self, "b", function() return row.entry end)
    row.hotB:SetPoint("TOPLEFT", COL.item.x - 3, 0)
    row.hotB:SetSize(COL.item.w + 4, UI.ROW_H)
    row:SetScript("OnEnter", function(r) if r.entry then self:ShowTooltip(r, r.entry) end end)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end)
  local h = self.list.headers
  h.rank:SetText("#")
  h.writ:SetText(L.HEAD_WRIT)
  h.item:SetText(L.HEAD_ITEM)
  h.price:SetText(L.HEAD_WRIT_PRICE)
  h.cost:SetText(L.HEAD_ITEM_COST)
  h.rep:SetText(L.HEAD_REP)
  h.per:SetText(L.HEAD_PER_REP)
end

-- what a click searches: "a" = the writ (or the crate for the receipt row), "b" = the requested item
function Tab:SearchTarget(e, kind)
  if e.receipt then return kind == "a" and e.crate.id or nil end
  if kind == "a" then return e.writ.writ end
  if kind == "b" then return e.writ.item end
end

local function PriceCell(cost, status)
  if cost then return Money(cost) end
  if status == "short" then return C_ORANGE .. L.NO_STOCK .. "|r" end
  if status then return C_ORANGE .. L.NO_STOCK .. "|r" end
  return Money(nil)
end

function Tab:FillRow(row, e, isTop)
  row:SetAlpha(e.done and 0.5 or 1)
  row.rep:SetText(C_GREEN .. "+" .. Num(e.repGain) .. "|r")
  row.per:SetText(e.perRep and UI.Colored(Money(e.perRep), isTop and C_GREEN or "|cffffffff") or Money(nil))
  if e.receipt then
    row.name:SetText(C_GREEN .. L.RECEIPT_ROW .. "|r")
    row.sub:SetText(L.RECEIPT_SUB)
    row.item:SetText(CrateName(e.crate))
    row.itemSub:SetText(L.RECEIPT_ITEM)
    row.price:SetText(Money(e.writCost))
    row.cost:SetText(e.itemCost and Money(e.itemCost) or (C_GREY .. "15 Favor|r"))
    row.hotB:Hide()
    return
  end
  local w = e.writ
  row.hotB:Show()
  row.name:SetText(WritTitle(w))
  local sub = (L.PROF[w.prof] or w.prof) .. " · " .. (L.WRIT_TIER[w.rep] or "")
  if e.done then sub = sub .. " · " .. C_ORANGE .. L.DONE_TODAY .. "|r" end
  row.sub:SetText(sub)
  row.item:SetText((e.itemCost and C_GREEN or "|cffffffff") .. ItemLine(w) .. "|r")
  if e.status == "ok" then
    local r = e.itemRes
    row.itemSub:SetText((w.qty > 1 and r and r.min) and L.EACH_FMT:format(Money(r.min)) or "")
  else
    row.itemSub:SetText(C_ORANGE .. (STATUS_TEXT[e.status] or "") .. "|r")
  end
  row.price:SetText(PriceCell(e.writCost, e.writStatus))
  row.cost:SetText(PriceCell(e.itemCost, e.itemStatus))
end

function Tab:Refresh()
  self.race:SetText(WC:HasDiplomacy() and (C_GREEN .. L.RACE_HAS .. "|r") or L.RACE_NONE)
  self.standing:SetText(StandingLine() or "")

  local all = WC:EvaluateWrits()
  local vis = WC:VisibleWrits(all)
  local top = UI:FillList(self.list, vis, function(row, e, isTop) self:FillRow(row, e, isTop) end)
  local hiddenCount = #all - #vis
  self.hidden:SetText(hiddenCount > 0 and L.HIDDEN_N:format(hiddenCount) or "")

  local b = self.best
  if not top then
    UI:ShowBest(b, false, WC.Scanner.active and L.BEST_EMPTY_SCANNING or L.BEST_EMPTY)
    return
  end
  UI:ShowBest(b, true)
  b.frame.entry = top
  b.label:SetText(L.BEST_LABEL_REP)
  b.perLabel:SetText(L.PER_REP_COST)
  b.per:SetText(Money(top.perRep))
  if top.receipt then
    b.name:SetText(C_GREEN .. L.RECEIPT_ROW .. "|r  " .. C_GREY .. CrateName(top.crate) .. "|r")
    b.detail:SetText(L.BEST_DETAIL_RECEIPT:format(Money(top.writCost), top.itemCost and Money(top.itemCost) or "?", C_GREEN .. Num(top.repGain) .. "|r"))
    b.net:SetText(StandingLine() or L.RECEIPT_SUB)
    b.hot2:Hide()
  else
    local w = top.writ
    b.name:SetText(WritTitle(w) .. "  " .. C_GREY .. (L.PROF[w.prof] or "") .. " · " .. (L.WRIT_TIER[w.rep] or "") .. "|r")
    b.detail:SetText(L.BEST_DETAIL_WRIT:format(Money(top.writCost), C_GREEN .. ItemLine(w) .. "|r", Money(top.itemCost), C_GREEN .. Num(top.repGain) .. "|r"))
    b.net:SetText(L.TT_TOTAL .. " " .. Money(top.cost))
  end
end

function Tab:BestMessage()
  for _, e in ipairs(WC:VisibleWrits(WC:EvaluateWrits())) do
    if e.rank == 1 then
      local name = e.receipt and L.RECEIPT_ROW or WritTitle(e.writ)
      return L.PRINT_BEST_REP:format(name, Money(e.perRep))
    end
  end
end

local function StatusRight(cost, status, res, qty)
  if cost then
    local s = Money(cost)
    if res and res.min and qty and qty > 1 then
      s = s .. C_GREY .. L.TT_UNIT:format((Money(res.min):gsub("|r", "|r" .. C_GREY))) .. "|r"
    end
    return s
  end
  if not status then return C_GREY .. L.TT_NOT_SCANNED .. "|r" end
  if status == "short" then return C_ORANGE .. L.TT_SHORT:format(res and res.avail or 0) .. "|r" end
  if status == "timeout" then return C_GREY .. L.TT_TIMEOUT .. "|r" end
  return C_ORANGE .. L.TT_NOT_LISTED .. "|r"
end

function Tab:ShowTooltip(owner, e, kind)
  local bonus = WC:RepBonus()
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if e.receipt then
    GameTooltip:AddLine(C_GREEN .. L.RECEIPT_ROW .. "|r")
    GameTooltip:AddLine(L.TT_RECEIPT_HOWTO, 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L.TT_REP, L.TT_REP_VAL:format(Num(e.repGain), WC.REP.empty, Pct(bonus)), 1, 0.82, 0, 0.3, 1, 0.4)
    GameTooltip:AddDoubleLine(L.TT_CRATE_PRICE .. " (" .. WC:CrateShortName(e.crate) .. ")", Money(e.writCost), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.TT_RECEIPT_PRICE, e.itemCost and Money(e.itemCost) or (C_GREY .. "15 Favor|r"), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.TT_TOTAL, Money(e.cost), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.TT_PER_REP, Money(e.perRep), 1, 0.82, 0, 0.3, 1, 0.4)
    local st = StandingLine()
    if st then GameTooltip:AddLine(st, 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(L.CLICK_CRATE, 0.3, 1, 0.4)
    GameTooltip:Show()
    return
  end

  local w = e.writ
  GameTooltip:AddLine("|cffffffff" .. WC:ItemName(w.writ) .. "|r")
  GameTooltip:AddLine((L.PROF[w.prof] or w.prof) .. " · " .. (L.WRIT_TIER[w.rep] or ""), 0.7, 0.7, 0.7)
  GameTooltip:AddDoubleLine(L.TT_REP, L.TT_REP_VAL:format(Num(e.repGain), w.rep, Pct(bonus)), 1, 0.82, 0, 0.3, 1, 0.4)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine(L.TT_WRIT_PRICE, StatusRight(e.writCost, e.writStatus, e.writRes, 1), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.TT_ITEM_COST .. ": " .. ItemLine(w), StatusRight(e.itemCost, e.itemStatus, e.itemRes, w.qty), 1, 0.82, 0, 1, 1, 1)
  if e.cost then
    GameTooltip:AddDoubleLine(L.TT_TOTAL, Money(e.cost), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.TT_PER_REP, Money(e.perRep), 1, 0.82, 0, 0.3, 1, 0.4)
  elseif STATUS_TEXT[e.status] then
    GameTooltip:AddLine(STATUS_TEXT[e.status], 1, 0.6, 0.2)
  end
  GameTooltip:AddLine(" ")
  if e.done then GameTooltip:AddLine(L.TT_DONE, 1, 0.6, 0.2) else GameTooltip:AddLine(L.TT_DAILY, 0.8, 0.8, 0.8) end
  GameTooltip:AddLine(L.TT_WRIT_HOWTO, 0.55, 0.55, 0.55, true)
  GameTooltip:AddLine(L.TT_METHOD, 0.55, 0.55, 0.55, true)
  if kind == "a" then
    GameTooltip:AddLine(L.CLICK_WRIT, 0.3, 1, 0.4)
  elseif kind == "b" then
    GameTooltip:AddLine(L.CLICK_ITEM:format(ItemLine(w)), 0.3, 1, 0.4)
  else
    GameTooltip:AddLine(L.CLICK_HINT_WRIT, 0.3, 1, 0.4)
  end
  GameTooltip:Show()
end
