local addonName, WC = ...

-- Crates tab: cost per Merchant's Favor.
local UI = WC.UI
local L = WC.L

WC.AddLocale({
  enUS = {
    EST_NOTE = "~ = estimate: Auctionator only knows the cheapest price, so buying a whole bundle can cost more. \"Check the best\" searches the best entries exactly.",
    UI_AGE_MIN = "%d min",
    UI_AGE_HOUR = "%d h",
    TT_REWARD_GUESS = "Reward not confirmed: no source has published what an Artisan crate pays, so this continues the pattern of the lower tiers. The addon records the real reward the first time you turn one in.",
    TT_REWARD_SEEN = "Reward as recorded from your own turn-ins (%d).",
  },
  zhCN = {
    EST_NOTE = "~ = 估算：Auctionator 只记录最低价，整组购买可能更贵。点『核实前几名』会精确搜索排在前面的几项。",
    UI_AGE_MIN = "%d 分钟",
    UI_AGE_HOUR = "%d 小时",
    TT_REWARD_GUESS = "奖励未确认：目前没有任何来源公布 Artisan 箱子的奖励，这里按低等级箱子的规律估算。你交过一次后，插件会记下实际奖励并改用它。",
    TT_REWARD_SEEN = "奖励为你实际交箱记录到的数值（%d 次）。",
  },
  zhTW = {
    EST_NOTE = "~ = 估算：Auctionator 只記錄最低價，整組購買可能更貴。點『核實前幾名』會精確搜尋排在前面的幾項。",
    UI_AGE_MIN = "%d 分鐘",
    UI_AGE_HOUR = "%d 小時",
    TT_REWARD_GUESS = "獎勵未確認：目前沒有任何來源公布 Artisan 箱子的獎勵，這裡按低等級箱子的規律估算。你交過一次後，插件會記下實際獎勵並改用它。",
    TT_REWARD_SEEN = "獎勵為你實際交箱記錄到的數值（%d 次）。",
  },
})
local Money, Num, Pct, Font = WC.Money, UI.Num, UI.Pct, UI.Font
local C_GREEN, C_ORANGE, C_GREY, C_UNCOMMON = UI.C_GREEN, UI.C_ORANGE, UI.C_GREY, UI.C_UNCOMMON

local Tab = {}
UI:RegisterTab("crates", { order = 1, tab = Tab,
  label = function() return L.UI_TAB_CRATES end,      -- short name for the tab bar
  title = function() return L.TAB_CRATES end })      -- full name for the tab tooltip

function Tab:ScanKind() return "crates" end
function Tab:Subtitle() return L.SUBTITLE_CRATES end
function Tab:ScanTip() return L.SCAN_TIP_crates end

local COL = {
  rank  = { x = 4, w = 26, justify = "CENTER" },
  crate = { x = 36, w = 168 },
  fill  = { x = 208, w = 172 },
  price = { r = 458, w = 76 },
  mats  = { r = 536, w = 74 },
  per   = { r = 650, w = 80 },
}

local STATUS_TEXT = {
  nocrate   = L.ST_NOCRATE,
  nomats    = L.ST_NOMATS,
  short     = L.ST_SHORT,
  unscanned = L.ST_UNSCANNED,
}

local function CrateName(crate)
  return (crate.crafted and C_UNCOMMON or "|cffffffff") .. WC:CrateShortName(crate) .. "|r"
end

local function OptLine(e, j)
  local o = e.opts[j]
  return o.qty .. " × " .. WC:ItemName(o.itemID)
end

function Tab:Create(panel)
  local checks = UI:CheckRow(panel, -2, {
    { L.ONLY_MINE, "onlyMine", L.ONLY_MINE_TIP },
    { L.HIDE_NO_CRATE, "hideNoCrate", L.HIDE_NO_CRATE_TIP },
    { L.HIDE_NO_MATS, "hideNoMats", L.HIDE_NO_MATS_TIP },
  })
  self.hidden = Font(panel, "GameFontDisableSmall", "RIGHT", 90)
  self.hidden:SetPoint("TOPRIGHT", -2, -7)

  UI:Cycler(panel, 0, -28, L.PERF_LABEL, "perfRank", 3, L.PERF_TIP)
  local repNote = Font(panel, "GameFontDisableSmall", "RIGHT", 300)
  repNote:SetPoint("TOPRIGHT", -2, -33)
  repNote:SetText(L.TT_REP_FILL .. ": 0")

  self.best = UI:BestPanel(panel, -54, self)

  self.list = UI:List(panel, -140, -156, COL, #WC.CRATES, function(row)
    row.name = UI.Cell(row, COL.crate, "GameFontHighlight", -3)
    row.sub = UI.Cell(row, COL.crate, "GameFontDisableSmall", -18)
    row.fill = UI.Cell(row, COL.fill, "GameFontHighlightSmall", -4)
    row.fillSub = UI.Cell(row, COL.fill, "GameFontDisableSmall", -18)
    row.price = UI.Cell(row, COL.price, "GameFontHighlightSmall")
    row.mats = UI.Cell(row, COL.mats, "GameFontHighlightSmall")
    row.per = UI.Cell(row, COL.per, "GameFontHighlight")
    row.hotA = UI.Hotspot(row, self, "a", function() return row.entry end)
    row.hotA:SetPoint("TOPLEFT", COL.crate.x - 4, 0)
    row.hotA:SetSize(COL.crate.w + 4, UI.ROW_H)
    row.hotB = UI.Hotspot(row, self, "b", function() return row.entry end)
    row.hotB:SetPoint("TOPLEFT", COL.fill.x - 3, 0)
    row.hotB:SetSize(COL.fill.w + 4, UI.ROW_H)
    row:SetScript("OnEnter", function(r) if r.entry then self:ShowTooltip(r, r.entry) end end)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end)
  local h = self.list.headers
  h.rank:SetText("#")
  h.crate:SetText(L.HEAD_CRATE)
  h.fill:SetText(L.HEAD_FILL)
  h.price:SetText(L.HEAD_CRATE_PRICE)
  h.mats:SetText(L.HEAD_MATS)
  h.per:SetText(L.HEAD_PER)
end

-- what a click searches: "a" = the crate, "b" = the recommended material
function Tab:SearchTarget(e, kind)
  if kind == "a" then return e.crate.id end
  if kind == "b" and e.bestIdx then return e.opts[e.bestIdx].itemID end
end

function Tab:FillRow(row, e, isTop)
  local c = e.crate
  row:SetAlpha(e.locked and 0.5 or 1)
  row.name:SetText(CrateName(c))
  local lvlText = e.locked and ("|cffff5a4a" .. L.NEED_LEVEL_FMT:format(c.lvl) .. "|r") or L.LEVEL_FMT:format(c.lvl)
  row.sub:SetText(WC.TIER_NAME[c.tier] .. " · " .. lvlText .. " · " .. L.FAVOR_FMT:format(Num(e.favorExp) .. (e.rewardState == "guess" and "?" or "")))
  row.price:SetText(e.crateCost and ((e.crateEst and "~" or "") .. Money(e.crateCost)) or (e.crateStatus and (C_ORANGE .. L.NO_STOCK .. "|r") or Money(nil)))
  row.hotB:SetShown(e.bestIdx ~= nil)
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
  row.mats:SetText(((e.bestIdx and e.opts[e.bestIdx].est) and "~" or "") .. Money(e.matCost))
  row.per:SetText(e.perFavor and ((e.est and "~" or "") .. UI.Colored(Money(e.perFavor), isTop and C_GREEN or "|cffffffff")) or Money(nil))
end

function Tab:Refresh()
  local all = WC:EvaluateCrates()
  local vis = WC:VisibleCrates(all)
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
  local c = top.crate
  b.label:SetText(L.BEST_LABEL)
  b.perLabel:SetText(L.PER_FAVOR_COST)
  b.name:SetText(CrateName(c) .. "  " .. C_GREY .. WC.TIER_NAME[c.tier] .. " · " .. L.LEVEL_FMT:format(c.lvl) .. "|r")
  local o = top.opts[top.bestIdx]
  b.detail:SetText(L.BEST_DETAIL:format(Money(top.crateCost), C_GREEN .. o.qty .. " × " .. WC:ItemName(o.itemID) .. "|r", Money(top.matCost), Money(top.silver)))
  b.per:SetText((top.est and "~" or "") .. Money(top.perFavor))
  b.net:SetText(L.BEST_NET:format(Money(top.net), Num(top.favorExp) .. (top.rewardState == "guess" and "?" or "")))
end

function Tab:BestMessage()
  for _, e in ipairs(WC:VisibleCrates(WC:EvaluateCrates())) do
    if e.rank == 1 then return L.PRINT_BEST:format(CrateName(e.crate), Money(e.perFavor)) end
  end
end

function Tab:ShowTooltip(owner, e, kind)
  local c = e.crate
  local favorBonus = WC:FavorBonus()
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(CrateName(c))
  GameTooltip:AddLine(WC.TIER_NAME[c.tier] .. " · " .. L.NEED_LEVEL_FMT:format(c.lvl), 0.7, 0.7, 0.7)
  GameTooltip:AddDoubleLine(L.TT_REWARD, L.TT_REWARD_VAL:format(e.favor, Money(e.silver)), 1, 0.82, 0, 1, 1, 1)
  if e.rewardState == "guess" then
    GameTooltip:AddLine(L.TT_REWARD_GUESS, 1, 0.55, 0.2, true)
  elseif e.rewardState == "seen" then
    GameTooltip:AddLine(L.TT_REWARD_SEEN:format(e.rewardSeen or 0), 0.6, 0.6, 0.6, true)
  end
  GameTooltip:AddDoubleLine(L.TT_BONUS_FAVOR, Num(e.favorExp) .. (favorBonus > 0 and (C_GREEN .. " (+" .. Pct(favorBonus) .. ")|r") or ""), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.TT_REP_FILL, "0", 1, 0.82, 0, 1, 1, 1)
  local crateRight
  if e.crateCost then crateRight = (e.crateEst and "~" or "") .. Money(e.crateCost)
  elseif e.crateStatus then crateRight = C_ORANGE .. L.TT_NOT_LISTED .. "|r"
  else crateRight = C_GREY .. L.TT_NOT_SCANNED .. "|r" end
  GameTooltip:AddDoubleLine(L.TT_CRATE_PRICE, crateRight, 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(L.TT_FILL_HEAD, 1, 0.82, 0)
  for j, o in ipairs(e.opts) do
    local left = o.qty .. " × " .. WC:ItemName(o.itemID)
    local right
    local r = o.res
    if o.cost then
      right = (o.est and "~" or "") .. Money(o.cost)
      if r and r.min then right = right .. C_GREY .. L.TT_UNIT:format((Money(r.min):gsub("|r", "|r" .. C_GREY))) .. "|r" end
    elseif not o.status then right = C_GREY .. L.TT_NOT_SCANNED .. "|r"
    elseif o.status == "short" then right = C_ORANGE .. L.TT_SHORT:format(r and r.avail or 0) .. "|r"
    elseif o.status == "timeout" then right = C_GREY .. L.TT_TIMEOUT .. "|r"
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
    GameTooltip:AddDoubleLine(L.TT_NET, (e.est and "~" or "") .. Money(e.net), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.TT_PER, (e.est and "~" or "") .. Money(e.perFavor), 1, 0.82, 0, 0.3, 1, 0.4)
    if e.est then GameTooltip:AddLine(L.EST_NOTE, 1, 0.82, 0.4, true) end
  else
    GameTooltip:AddLine(STATUS_TEXT[e.status] or "", 1, 0.6, 0.2)
  end
  GameTooltip:AddLine(L.TT_METHOD, 0.55, 0.55, 0.55, true)
  if kind == "a" then
    GameTooltip:AddLine(L.CLICK_CRATE, 0.3, 1, 0.4)
  elseif kind == "b" and e.bestIdx then
    GameTooltip:AddLine(L.CLICK_MAT:format(OptLine(e, e.bestIdx)), 0.3, 1, 0.4)
  else
    GameTooltip:AddLine(L.CLICK_HINT, 0.3, 1, 0.4)
  end
  GameTooltip:Show()
end
