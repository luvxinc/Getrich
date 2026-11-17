local addonName, WC = ...

-- Reputation tab: Craftsman's Writs (+ the empty crate with a receipt), cost per reputation point.
-- Two views (GetrichDB.writView): "list" ranks every writ; "plan" shows what to hand in today to get from the
-- reputation the character has to a target standing for the least money (WC:RepPlan in Core.lua): each row is
-- one turn-in with what has to be bought for it and what it costs, the gold panel has the totals, and the
-- shopping-list button puts everything to buy into an Auctionator shopping list.
local UI = WC.UI
local L = WC.L
local Money, Num, Pct, Font = WC.Money, UI.Num, UI.Pct, UI.Font
local C_GREEN, C_ORANGE, C_GREY, C_UNCOMMON = UI.C_GREEN, UI.C_ORANGE, UI.C_GREY, UI.C_UNCOMMON

WC.AddLocale({
  enUS = {
    WRIT_VIEW = "View",
    WRIT_VIEW_LIST = "All writs",
    WRIT_VIEW_PLAN = "Reputation plan",
    WRIT_VIEW_TIP = "All writs: every writ, ranked by cost per reputation.\nReputation plan: what to hand in today to reach a standing for the least money.",
    REP_TARGET = "Target",
    REP_TARGET_NEXT = "next: %s",
    REP_TARGET_ANY = "next standing",
    REP_TARGET_TIP = "The standing the plan aims at.",
    REP_CAP = "Max per rep",
    REP_CAP_NONE = "no limit",
    REP_CAP_TIP = "Writs and crate returns that cost more than this per reputation point are left out of the plan: they can wait for a cheaper day.",
    REP_FAVOR = "Use Favor",
    REP_FAVOR_TIP = "Lets the plan spend Merchant's Favor on Forged Delivery Receipts: an empty crate with a receipt gives 50 reputation (needs Friendly, 15 Favor each). The Favor is counted at what it costs to make with the best crate.",
    REP_SHOP_BTN = "Shopping list",
    REP_SHOP_TIP = "Puts everything the plan buys into an Auctionator shopping list named \"%s\" (exact names, with quantities).\nThen open Auctionator's Shopping tab and pick that list to buy.",
    REP_SHOP_NAME = "Getrich reputation",
    REP_SHOP_DONE = "Auctionator shopping list \"%s\": %d entries. Open Auctionator's Shopping tab and pick it.",
    REP_SHOP_NOAPI = "The shopping list needs Auctionator.",
    REP_SHOP_EMPTY = "The plan buys nothing.",
    REP_SHOP_NAMES = "%d item names are not loaded yet. Try again in a few seconds.",
    REP_SHOP_FAIL = "Auctionator did not accept the shopping list.",
    REP_PLAN_LABEL = "Reputation plan for today",
    REP_PLAN_GOAL = "%s %s  ->  %s %s  ·  %s to go",
    REP_PLAN_WRITS = "%d writs",
    REP_PLAN_RETURNS = "%d crate returns",
    REP_PLAN_TODAY = "Hand in %s  ->  +%s reputation",
    REP_PLAN_SPEND = "To spend today",
    REP_PLAN_REACHED = "Reaches %s today",
    REP_PLAN_DAYS = "%s short: about %d more days",
    REP_PLAN_SHORT = "%s short",
    REP_PLAN_NONE = "Nothing to hand in today.\nNo writ is for sale that is not done yet (or all are above the price cap).",
    REP_PLAN_NOPRICES = "No prices yet.\nRun a full scan in Auctionator: the plan is made from its prices.",
    REP_ASSUMED = "(no reputation shown by the game yet: counted from Neutral 0)",
    REP_TT_ASSUMED = "The game shows no reputation with the trade faction for this character yet, so the plan starts at Neutral 0.",
    REP_TOP = "Exalted: nothing left to plan.",
    REP_STANDING_NUM = "%s %s / %s",
    REP_DONE_TODAY = "today %d handed in, +%s",
    REP_OWNED = "in bags",
    REP_OWNED_N = "%d in bags",
    REP_BUY_N = "buy %d",
    REP_RETURN_ROW = "Empty crate + receipt × %d",
    REP_RETURN_FAVOR = "spends %d Favor",
    REP_RETURN_RECEIPTS = "%d receipts in bags",
    REP_RETURN_CRATES = "%d × %s",
    REP_TT_PLAN = "Reputation plan",
    REP_TT_NOW = "Reputation now",
    REP_TT_TARGET = "Target",
    REP_TT_NEED = "Still to go",
    REP_TT_DONE = "Handed in today",
    REP_TT_DONE_VAL = "%d writs, +%s",
    REP_TT_OPEN = "Writs still open today (with a price)",
    REP_TT_TODAY = "Today's plan",
    REP_TT_TODAY_VAL = "%d turn-ins, +%s",
    REP_TT_CASH = "Money to spend",
    REP_TT_FAVOR = "Merchant's Favor spent",
    REP_TT_FAVOR_VAL = "%d (counted at %s each)",
    REP_TT_AFTER = "After today",
    REP_TT_AFTER_VAL = "%s short, about %d days",
    REP_TT_DAILY = "A day at today's prices",
    REP_TT_DAILY_VAL = "%d writs, +%s for %s",
    REP_TT_SHOP = "To buy (%d entries)",
    REP_TT_MORE = "... and %d more",
    REP_TT_LABEL = "Not done yet: the one-time Shipping Label quest (your first filled crate) gives 2000 reputation.",
    REP_TT_BAGS = "What is in your bags is not bought again. Writs handed in today are left out.",
    REP_TT_CLICK = "\"Shopping list\" sends these to Auctionator. Click a name in the list to search it.",
    REP_TT_RETURN_HOW = "Buy Forged Delivery Receipts from the Uncertified Scribe (15 Favor each, needs Friendly), use one on each empty Waylaid Crate and hand the containers in.",
    REP_TT_CRATES = "Crates to buy",
    REP_TT_CRATES_OWNED = "Crates in bags",
    REP_TT_FAVOR_WORTH = "Worth of the Favor",
    SCAN_TIP_plan = "Searches everything the plan buys exactly (%d items, about %s) and plans again, until every price in the plan is exact.",
    PRINT_PLAN = "Plan checked: +%s reputation today for %s.",
  },
  zhCN = {
    WRIT_VIEW = "视图",
    WRIT_VIEW_LIST = "全部 Writ",
    WRIT_VIEW_PLAN = "冲声望",
    WRIT_VIEW_TIP = "全部 Writ：每张 Writ 按每点声望成本排名。\n冲声望：今天交哪些，能用最少的钱冲到目标声望。",
    REP_TARGET = "目标",
    REP_TARGET_NEXT = "下一级：%s",
    REP_TARGET_ANY = "下一级",
    REP_TARGET_TIP = "规划要冲到的声望等级。",
    REP_CAP = "每点上限",
    REP_CAP_NONE = "不限",
    REP_CAP_TIP = "每点声望成本超过这个数的 Writ 和空箱回收不放进方案，留到便宜的日子再交。",
    REP_FAVOR = "用 Favor",
    REP_FAVOR_TIP = "允许方案把 Merchant's Favor 花在 Forged Delivery Receipt 上：空箱 + 送货单 = 50 声望（需要友善，每张 15 Favor）。Favor 按最划算的箱子做出它的成本计入。",
    REP_SHOP_BTN = "购物清单",
    REP_SHOP_TIP = "把方案里要买的东西全部放进 Auctionator 的购物清单「%s」（精确名字，带数量）。\n然后打开 Auctionator 的「购物」页，选这个清单开始买。",
    REP_SHOP_NAME = "Getrich 声望",
    REP_SHOP_DONE = "Auctionator 购物清单「%s」已建立：%d 项。打开 Auctionator 的「购物」页，选它开始买。",
    REP_SHOP_NOAPI = "购物清单需要 Auctionator。",
    REP_SHOP_EMPTY = "方案里没有要买的东西。",
    REP_SHOP_NAMES = "还有 %d 个物品的名字没加载好，过几秒再点一次。",
    REP_SHOP_FAIL = "Auctionator 没有接受这份购物清单。",
    REP_PLAN_LABEL = "今天的冲声望方案",
    REP_PLAN_GOAL = "%s %s  →  %s %s  ·  还差 %s",
    REP_PLAN_WRITS = "%d 张 Writ",
    REP_PLAN_RETURNS = "%d 次空箱回收",
    REP_PLAN_TODAY = "交 %s  →  +%s 声望",
    REP_PLAN_SPEND = "今天要花",
    REP_PLAN_REACHED = "今天就能到%s",
    REP_PLAN_DAYS = "还差 %s：约再 %d 天",
    REP_PLAN_SHORT = "还差 %s",
    REP_PLAN_NONE = "今天没有可交的。\n没有还没交过又在售的 Writ（或者都超过了价格上限）。",
    REP_PLAN_NOPRICES = "还没有价格。\n请先在 Auctionator 里做一次全扫描，方案按它的价格来排。",
    REP_ASSUMED = "（游戏里还看不到声望：按中立 0 起算）",
    REP_TT_ASSUMED = "游戏里还看不到这个角色和贸易阵营的声望，所以方案从中立 0 起算。",
    REP_TOP = "已经崇拜，不用再规划了。",
    REP_STANDING_NUM = "%s %s / %s",
    REP_DONE_TODAY = "今天已交 %d 张，+%s",
    REP_OWNED = "背包已有",
    REP_OWNED_N = "背包已有 %d",
    REP_BUY_N = "买 %d",
    REP_RETURN_ROW = "空箱 + 送货单 × %d",
    REP_RETURN_FAVOR = "用掉 %d Favor",
    REP_RETURN_RECEIPTS = "背包已有 %d 张送货单",
    REP_RETURN_CRATES = "%d × %s",
    REP_TT_PLAN = "冲声望方案",
    REP_TT_NOW = "当前声望",
    REP_TT_TARGET = "目标",
    REP_TT_NEED = "还差",
    REP_TT_DONE = "今天已交",
    REP_TT_DONE_VAL = "%d 张，+%s",
    REP_TT_OPEN = "今天还能交（有价格）的 Writ",
    REP_TT_TODAY = "今天的方案",
    REP_TT_TODAY_VAL = "交 %d 次，+%s",
    REP_TT_CASH = "要花的钱",
    REP_TT_FAVOR = "用掉的 Merchant's Favor",
    REP_TT_FAVOR_VAL = "%d（每个按 %s 计入）",
    REP_TT_AFTER = "今天之后",
    REP_TT_AFTER_VAL = "还差 %s，约 %d 天",
    REP_TT_DAILY = "按今天的价格，每天",
    REP_TT_DAILY_VAL = "%d 张，+%s，%s",
    REP_TT_SHOP = "要买的（%d 项）",
    REP_TT_MORE = "…还有 %d 项",
    REP_TT_LABEL = "还没做：一次性的 Shipping Label 任务（交第一个装满的箱子）给 2000 声望。",
    REP_TT_BAGS = "背包里已有的不会再买。今天交过的 Writ 不在方案里。",
    REP_TT_CLICK = "「购物清单」把这些发到 Auctionator。点列表里的名字可以直接搜索。",
    REP_TT_RETURN_HOW = "在 Uncertified Scribe 那里买 Forged Delivery Receipt（每张 15 Favor，需要友善），对每个空的 Waylaid Crate 用一张，再把箱子交掉。",
    REP_TT_CRATES = "要买的箱子",
    REP_TT_CRATES_OWNED = "背包里的箱子",
    REP_TT_FAVOR_WORTH = "这些 Favor 的价值",
    SCAN_TIP_plan = "精确搜索方案里要买的全部物品（%d 件，约 %s），再重新规划，直到方案里每个价格都是精确的。",
    PRINT_PLAN = "方案已核实：今天 +%s 声望，要花 %s。",
  },
  zhTW = {
    WRIT_VIEW = "檢視",
    WRIT_VIEW_LIST = "全部 Writ",
    WRIT_VIEW_PLAN = "衝聲望",
    WRIT_VIEW_TIP = "全部 Writ：每張 Writ 按每點聲望成本排名。\n衝聲望：今天交哪些，能用最少的錢衝到目標聲望。",
    REP_TARGET = "目標",
    REP_TARGET_NEXT = "下一級：%s",
    REP_TARGET_ANY = "下一級",
    REP_TARGET_TIP = "規劃要衝到的聲望等級。",
    REP_CAP = "每點上限",
    REP_CAP_NONE = "不限",
    REP_CAP_TIP = "每點聲望成本超過這個數的 Writ 和空箱回收不放進方案，留到便宜的日子再交。",
    REP_FAVOR = "用 Favor",
    REP_FAVOR_TIP = "允許方案把 Merchant's Favor 花在 Forged Delivery Receipt 上：空箱 + 送貨單 = 50 聲望（需要友善，每張 15 Favor）。Favor 按最划算的箱子做出它的成本計入。",
    REP_SHOP_BTN = "購物清單",
    REP_SHOP_TIP = "把方案裡要買的東西全部放進 Auctionator 的購物清單「%s」（精確名字，帶數量）。\n然後打開 Auctionator 的「購物」頁，選這個清單開始買。",
    REP_SHOP_NAME = "Getrich 聲望",
    REP_SHOP_DONE = "Auctionator 購物清單「%s」已建立：%d 項。打開 Auctionator 的「購物」頁，選它開始買。",
    REP_SHOP_NOAPI = "購物清單需要 Auctionator。",
    REP_SHOP_EMPTY = "方案裡沒有要買的東西。",
    REP_SHOP_NAMES = "還有 %d 個物品的名字沒載入好，過幾秒再點一次。",
    REP_SHOP_FAIL = "Auctionator 沒有接受這份購物清單。",
    REP_PLAN_LABEL = "今天的衝聲望方案",
    REP_PLAN_GOAL = "%s %s  →  %s %s  ·  還差 %s",
    REP_PLAN_WRITS = "%d 張 Writ",
    REP_PLAN_RETURNS = "%d 次空箱回收",
    REP_PLAN_TODAY = "交 %s  →  +%s 聲望",
    REP_PLAN_SPEND = "今天要花",
    REP_PLAN_REACHED = "今天就能到%s",
    REP_PLAN_DAYS = "還差 %s：約再 %d 天",
    REP_PLAN_SHORT = "還差 %s",
    REP_PLAN_NONE = "今天沒有可交的。\n沒有還沒交過又在售的 Writ（或者都超過了價格上限）。",
    REP_PLAN_NOPRICES = "還沒有價格。\n請先在 Auctionator 裡做一次全掃描，方案按它的價格來排。",
    REP_ASSUMED = "（遊戲裡還看不到聲望：按中立 0 起算）",
    REP_TT_ASSUMED = "遊戲裡還看不到這個角色和貿易陣營的聲望，所以方案從中立 0 起算。",
    REP_TOP = "已經崇拜，不用再規劃了。",
    REP_STANDING_NUM = "%s %s / %s",
    REP_DONE_TODAY = "今天已交 %d 張，+%s",
    REP_OWNED = "背包已有",
    REP_OWNED_N = "背包已有 %d",
    REP_BUY_N = "買 %d",
    REP_RETURN_ROW = "空箱 + 送貨單 × %d",
    REP_RETURN_FAVOR = "用掉 %d Favor",
    REP_RETURN_RECEIPTS = "背包已有 %d 張送貨單",
    REP_RETURN_CRATES = "%d × %s",
    REP_TT_PLAN = "衝聲望方案",
    REP_TT_NOW = "目前聲望",
    REP_TT_TARGET = "目標",
    REP_TT_NEED = "還差",
    REP_TT_DONE = "今天已交",
    REP_TT_DONE_VAL = "%d 張，+%s",
    REP_TT_OPEN = "今天還能交（有價格）的 Writ",
    REP_TT_TODAY = "今天的方案",
    REP_TT_TODAY_VAL = "交 %d 次，+%s",
    REP_TT_CASH = "要花的錢",
    REP_TT_FAVOR = "用掉的 Merchant's Favor",
    REP_TT_FAVOR_VAL = "%d（每個按 %s 計入）",
    REP_TT_AFTER = "今天之後",
    REP_TT_AFTER_VAL = "還差 %s，約 %d 天",
    REP_TT_DAILY = "按今天的價格，每天",
    REP_TT_DAILY_VAL = "%d 張，+%s，%s",
    REP_TT_SHOP = "要買的（%d 項）",
    REP_TT_MORE = "…還有 %d 項",
    REP_TT_LABEL = "還沒做：一次性的 Shipping Label 任務（交第一個裝滿的箱子）給 2000 聲望。",
    REP_TT_BAGS = "背包裡已有的不會再買。今天交過的 Writ 不在方案裡。",
    REP_TT_CLICK = "「購物清單」把這些發到 Auctionator。點列表裡的名字可以直接搜尋。",
    REP_TT_RETURN_HOW = "在 Uncertified Scribe 那裡買 Forged Delivery Receipt（每張 15 Favor，需要友善），對每個空的 Waylaid Crate 用一張，再把箱子交掉。",
    REP_TT_CRATES = "要買的箱子",
    REP_TT_CRATES_OWNED = "背包裡的箱子",
    REP_TT_FAVOR_WORTH = "這些 Favor 的價值",
    SCAN_TIP_plan = "精確搜尋方案裡要買的全部物品（%d 件，約 %s），再重新規劃，直到方案裡每個價格都是精確的。",
    PRINT_PLAN = "方案已核實：今天 +%s 聲望，要花 %s。",
  },
})

local Tab = {}
UI:RegisterTab("writs", { order = 2, tab = Tab,
  label = function() return L.UI_TAB_WRITS end,      -- short name for the tab bar
  title = function() return L.TAB_WRITS end })      -- full name for the tab tooltip

local function DB() return WC:DB() end
local function PlanView() return DB().writView == "plan" end

function Tab:ScanKind() return "writs" end
function Tab:Subtitle() return L.SUBTITLE_WRITS end
function Tab:ScanTip()
  if PlanView() then
    local plan = WC:RepPlan()
    local n = plan and #plan.items or 0
    return L.SCAN_TIP_plan:format(n, UI.Duration(n * 0.8))
  end
  return L.SCAN_TIP_writs
end

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

-- 12345 -> "12,345"
local function Big(n)
  local str = tostring(math.floor((tonumber(n) or 0) + 0.5))
  local out, k = str:reverse():gsub("(%d%d%d)", "%1,")
  out = out:reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out
end

local function ReactionLabel(reaction)
  return _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or tostring(reaction)
end

-- "Standing: Friendly 4,250 / 9,000 · today 3 handed in, +375"
local function StandingLine(withToday)
  local _, reaction, value, _, hi = WC:Standing()
  if not reaction then return nil end
  local color = reaction >= 5 and C_GREEN or C_ORANGE
  local text = color .. ReactionLabel(reaction) .. "|r"
  if value and hi and hi > value then
    text = L.REP_STANDING_NUM:format(text, Big(value), Big(hi))
  end
  text = L.STANDING_FMT:format(text)
  if withToday then
    local n, rep = WC:WritsToday()
    if n > 0 then text = text .. " · " .. L.REP_DONE_TODAY:format(n, Big(rep)) end
  end
  return text
end

-- the standings the plan can aim at, for the target cycler: "next" first, then the ones after it
local function TargetValues()
  local vals, labs = {}, {}
  for i, r in ipairs(WC:RepTargets()) do
    if i == 1 then
      vals[1], labs[1] = "next", L.REP_TARGET_NEXT:format(ReactionLabel(r))
    else
      vals[#vals + 1], labs[#labs + 1] = r, ReactionLabel(r)
    end
  end
  if #vals == 0 then vals[1], labs[1] = "next", "—" end
  return vals, labs
end

local CAP_VALUES = { 0, 100, 200, 300, 500, 1000 }
local function CapLabel(v)
  if (tonumber(v) or 0) <= 0 then return L.REP_CAP_NONE end
  return Money(v)
end

function Tab:Create(panel)
  -- row 1, list view: the filters
  self.filters = UI:CheckRow(panel, -2, {
    { L.HIDE_NO_WRIT, "hideNoWrit", L.HIDE_NO_WRIT_TIP },
    { L.HIDE_NO_ITEM, "hideNoItem", L.HIDE_NO_ITEM_TIP },
    { L.HIDE_DONE, "hideDone", L.HIDE_DONE_TIP },
  })
  self.hidden = Font(panel, "GameFontDisableSmall", "RIGHT", 90)
  self.hidden:SetPoint("TOPRIGHT", -2, -7)

  -- row 1, plan view: target, price cap, Favor switch, shopping list
  local tLabel, tButton = UI:ValueCycler(panel, 0, -2, L.REP_TARGET, "repTarget", TargetValues, nil, L.REP_TARGET_TIP)
  local cLabel, cButton = UI:ValueCycler(panel, 0, -2, L.REP_CAP, "repCap", CAP_VALUES, CapLabel, L.REP_CAP_TIP)
  cLabel:ClearAllPoints()
  cLabel:SetPoint("LEFT", tButton, "RIGHT", 14, 0)
  local favor = UI:Check(panel, L.REP_FAVOR, 0, -2, "repUseFavor", L.REP_FAVOR_TIP)
  favor:ClearAllPoints()
  favor:SetPoint("LEFT", cButton, "RIGHT", 12, 0)
  local shop = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  shop:SetSize(110, 20)
  shop:SetPoint("TOPRIGHT", -2, -2)
  shop:SetText(L.REP_SHOP_BTN)
  shop:SetScript("OnClick", function() self:SendShoppingList() end)
  UI.Tip(shop, L.REP_SHOP_BTN, L.REP_SHOP_TIP:format(L.REP_SHOP_NAME))
  self.shopButton = shop
  self.planWidgets = { tLabel, tButton, cLabel, cButton, favor, shop }

  -- row 2: view, Legacy Diplomat, standing
  local vLabel, vButton = UI:ValueCycler(panel, 0, -28, L.WRIT_VIEW, "writView", { "list", "plan" },
                                         { L.WRIT_VIEW_LIST, L.WRIT_VIEW_PLAN }, L.WRIT_VIEW_TIP)
  self.viewButton = vButton
  local label, dButton = UI:Cycler(panel, 0, -28, L.DIPLO_LABEL, "diplomatRank", 5, L.DIPLO_TIP)
  label:ClearAllPoints()
  label:SetPoint("LEFT", vButton, "RIGHT", 16, 0)
  self.race = Font(panel, "GameFontDisableSmall", "LEFT", 150)
  self.race:SetPoint("LEFT", dButton, "RIGHT", 10, 0)
  self.standing = Font(panel, "GameFontDisableSmall", "RIGHT", 330)
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

local function PriceCell(cost, status, est)
  if cost then return (est and "~" or "") .. Money(cost) end
  if status == "short" then return C_ORANGE .. L.NO_STOCK .. "|r" end
  if status then return C_ORANGE .. L.NO_STOCK .. "|r" end
  return Money(nil)
end

-- a row of the plan: one turn-in, what is bought for it and what that costs ("in bags" for what is owned)
function Tab:FillPlanRow(row, e, isTop)
  row:SetAlpha(1)
  row.rep:SetText(C_GREEN .. "+" .. Num(e.repGain) .. "|r")
  row.per:SetText((e.est and "~" or "") .. UI.Colored(Money(e.perRep), isTop and C_GREEN or "|cffffffff"))
  local owned = C_GREEN .. L.REP_OWNED .. "|r"
  if e.receipt then
    row.hotB:Hide()
    row.name:SetText(C_GREEN .. L.REP_RETURN_ROW:format(e.n) .. "|r")
    local sub = {}
    if e.favor > 0 then sub[#sub + 1] = L.REP_RETURN_FAVOR:format(e.favor) end
    if e.haveReceipts > 0 then sub[#sub + 1] = L.REP_RETURN_RECEIPTS:format(e.haveReceipts) end
    row.sub:SetText(table.concat(sub, " · "))
    row.item:SetText(L.REP_RETURN_CRATES:format(e.n, CrateName(e.crate)))
    local isub = {}
    if e.buyCrates > 0 then isub[#isub + 1] = L.REP_BUY_N:format(e.buyCrates) end
    if e.haveCrates > 0 then isub[#isub + 1] = L.REP_OWNED_N:format(e.haveCrates) end
    row.itemSub:SetText(table.concat(isub, " · "))
    row.price:SetText(e.buyCrates > 0 and ((e.cashEst and "~" or "") .. Money(e.cash)) or owned)
    row.cost:SetText(e.favor > 0 and (C_GREY .. "~|r" .. Money(e.cost - e.cash)) or owned)
    return
  end
  local w = e.writ
  row.hotB:Show()
  row.name:SetText(WritTitle(w))
  row.sub:SetText((L.PROF[w.prof] or w.prof) .. " · " .. (L.WRIT_TIER[w.rep] or ""))
  row.item:SetText(ItemLine(w))
  local isub = {}
  if e.haveQty > 0 then isub[#isub + 1] = C_GREEN .. L.REP_OWNED_N:format(e.haveQty) .. "|r" end
  if e.buyQty > 0 and (e.haveQty > 0 or w.qty > 1) then isub[#isub + 1] = L.REP_BUY_N:format(e.buyQty) end
  if e.buyQty > 1 and e.itemRes and e.itemRes.min then isub[#isub + 1] = L.EACH_FMT:format(Money(e.itemRes.min)) end
  row.itemSub:SetText(table.concat(isub, " · "))
  row.price:SetText(e.haveWrit and owned or ((e.writEst and "~" or "") .. Money(e.writCost)))
  row.cost:SetText(e.buyQty == 0 and owned or ((e.itemEst and "~" or "") .. Money(e.itemCost)))
end

function Tab:FillRow(row, e, isTop)
  if e.plan then return self:FillPlanRow(row, e, isTop) end
  row:SetAlpha(e.done and 0.5 or 1)
  row.rep:SetText(C_GREEN .. "+" .. Num(e.repGain) .. "|r")
  row.per:SetText(e.perRep and ((e.est and "~" or "") .. UI.Colored(Money(e.perRep), isTop and C_GREEN or "|cffffffff")) or Money(nil))
  if e.receipt then
    row.name:SetText(C_GREEN .. L.RECEIPT_ROW .. "|r")
    row.sub:SetText(L.RECEIPT_SUB)
    row.item:SetText(CrateName(e.crate))
    row.itemSub:SetText(L.RECEIPT_ITEM)
    row.price:SetText((e.writEst and "~" or "") .. Money(e.writCost))
    row.cost:SetText(e.itemCost and ((e.itemEst and "~" or "") .. Money(e.itemCost)) or (C_GREY .. "15 Favor|r"))
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
  row.price:SetText(PriceCell(e.writCost, e.writStatus, e.writEst))
  row.cost:SetText(PriceCell(e.itemCost, e.itemStatus, e.itemEst))
end

-- the gold panel of the plan view: where the character stands, what today's plan gives and costs
function Tab:RefreshPlan()
  local b = self.best
  local plan = WC:RepPlan()
  local fill = function(row, e, isTop) self:FillRow(row, e, isTop) end
  local X = WC.External
  local function empty(text)
    UI:FillList(self.list, {}, fill, text)
    UI:ShowBest(b, false, text)
  end
  if plan.why == "top" then return empty(L.REP_TOP) end
  if #plan.steps == 0 then
    local noPrices = X and X.Usable and not X:Usable() and plan.open == 0
    return empty(noPrices and L.REP_PLAN_NOPRICES or L.REP_PLAN_NONE)
  end
  UI:FillList(self.list, plan.steps, fill)
  UI:ShowBest(b, true)
  b.hot1:Hide()
  b.hot2:Hide()
  b.frame.entry = { summary = true, plan = plan }
  local writs, returns = 0, 0
  for _, e in ipairs(plan.steps) do
    if e.receipt then returns = returns + e.n else writs = writs + 1 end
  end
  local parts = {}
  if writs > 0 then parts[#parts + 1] = L.REP_PLAN_WRITS:format(writs) end
  if returns > 0 then parts[#parts + 1] = L.REP_PLAN_RETURNS:format(returns) end
  b.label:SetText(L.REP_PLAN_LABEL .. (plan.assumed and ("  " .. C_ORANGE .. L.REP_ASSUMED .. "|r") or ""))
  b.name:SetText(L.REP_PLAN_GOAL:format(ReactionLabel(plan.reaction), Big(plan.value), C_GREEN .. ReactionLabel(plan.target) .. "|r",
                                        Big(plan.targetRep), Big(plan.need)))
  b.detail:SetText(L.REP_PLAN_TODAY:format(table.concat(parts, " + "), C_GREEN .. Big(plan.rep) .. "|r"))
  b.perLabel:SetText(L.REP_PLAN_SPEND)
  b.per:SetText((plan.cashEst and "~" or "") .. Money(plan.cash))
  if plan.reached then
    b.net:SetText(C_GREEN .. L.REP_PLAN_REACHED:format(ReactionLabel(plan.target)) .. "|r")
  elseif plan.days then
    b.net:SetText(C_ORANGE .. L.REP_PLAN_DAYS:format(Big(plan.short), plan.days) .. "|r")
  else
    b.net:SetText(C_ORANGE .. L.REP_PLAN_SHORT:format(Big(plan.short)) .. "|r")
  end
end

function Tab:Refresh()
  local planView = PlanView()
  local db = DB()
  self.race:SetText(WC:HasDiplomacy() and (C_GREEN .. L.RACE_HAS .. "|r") or "")
  self.standing:SetText(StandingLine(true) or "")
  for _, w in ipairs(self.filters) do w:SetShown(not planView) end
  self.hidden:SetShown(not planView)
  for _, w in ipairs(self.planWidgets) do w:SetShown(planView) end
  if planView then
    -- a target that is no longer above the current standing goes back to "next"
    local vals = TargetValues()
    local known = false
    for _, v in ipairs(vals) do if v == db.repTarget then known = true end end
    if not known and GetrichDB then GetrichDB.repTarget = "next" end
    return self:RefreshPlan()
  end

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
  b.per:SetText((top.est and "~" or "") .. Money(top.perRep))
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
  if PlanView() then
    local plan = WC:RepPlan()
    if #plan.steps == 0 then return nil end
    return L.PRINT_PLAN:format(Big(plan.rep), (plan.cashEst and "~" or "") .. Money(plan.cash))
  end
  for _, e in ipairs(WC:VisibleWrits(WC:EvaluateWrits())) do
    if e.rank == 1 then
      local name = e.receipt and L.RECEIPT_ROW or WritTitle(e.writ)
      return L.PRINT_BEST_REP:format(name, Money(e.perRep))
    end
  end
end

local function StatusRight(cost, status, res, qty)
  if cost then
    local s = ((res and res.est) and "~" or "") .. Money(cost)
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

-- everything the plan buys, as an Auctionator shopping list
function Tab:SendShoppingList()
  local plan = WC:RepPlan()
  local items = {}
  for _, x in ipairs(plan.shop or {}) do items[#items + 1] = { x.itemID, x.qty } end
  local X = WC.External
  if not (X and X.ShoppingList) then WC:Print(L.REP_SHOP_NOAPI); return false end
  local ok, a, n = X:ShoppingList(L.REP_SHOP_NAME, items)
  if ok then
    WC:Print(L.REP_SHOP_DONE:format(a, n))
    return true
  end
  if a == "noapi" then WC:Print(L.REP_SHOP_NOAPI)
  elseif a == "empty" then WC:Print(L.REP_SHOP_EMPTY)
  elseif a == "names" then WC:Print(L.REP_SHOP_NAMES:format(n or 0))
  else WC:Print(L.REP_SHOP_FAIL) end
  return false
end

local SHOP_LINES = 14

-- the gold panel's tooltip in the plan view: the numbers behind the plan and the shopping list
function Tab:ShowPlanTooltip(owner, plan)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(C_GREEN .. L.REP_TT_PLAN .. "|r")
  GameTooltip:AddDoubleLine(L.REP_TT_NOW, ReactionLabel(plan.reaction) .. " " .. Big(plan.value), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.REP_TT_TARGET, ReactionLabel(plan.target) .. " " .. Big(plan.targetRep), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.REP_TT_NEED, Big(plan.need), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine(L.REP_TT_DONE, L.REP_TT_DONE_VAL:format(plan.doneN, Big(plan.doneRep)), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.REP_TT_OPEN, tostring(plan.open or 0), 1, 0.82, 0, 1, 1, 1)
  local turnins = 0
  for _, e in ipairs(plan.steps) do turnins = turnins + (e.receipt and e.n or 1) end
  GameTooltip:AddDoubleLine(L.REP_TT_TODAY, L.REP_TT_TODAY_VAL:format(turnins, Big(plan.rep)), 1, 0.82, 0, 0.3, 1, 0.4)
  GameTooltip:AddDoubleLine(L.REP_TT_CASH, (plan.cashEst and "~" or "") .. Money(plan.cash), 1, 0.82, 0, 1, 1, 1)
  if plan.favor > 0 then
    local worth = (plan.cost - plan.cash) / plan.favor
    GameTooltip:AddDoubleLine(L.REP_TT_FAVOR, L.REP_TT_FAVOR_VAL:format(plan.favor, Money(worth)), 1, 0.82, 0, 1, 1, 1)
  end
  if not plan.reached then
    if plan.days then
      GameTooltip:AddDoubleLine(L.REP_TT_AFTER, L.REP_TT_AFTER_VAL:format(Big(plan.short), plan.days), 1, 0.82, 0, 1, 0.6, 0.2)
    else
      GameTooltip:AddDoubleLine(L.REP_TT_AFTER, L.REP_PLAN_SHORT:format(Big(plan.short)), 1, 0.82, 0, 1, 0.6, 0.2)
    end
    local d = plan.daily
    if d and d.n > 0 then
      GameTooltip:AddDoubleLine(L.REP_TT_DAILY, L.REP_TT_DAILY_VAL:format(d.n, Big(d.rep), Money(d.cost)), 1, 0.82, 0, 0.8, 0.8, 0.8)
    end
  end
  if #plan.shop > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.REP_TT_SHOP:format(#plan.shop), 1, 0.82, 0)
    for i = 1, math.min(#plan.shop, SHOP_LINES) do
      local x = plan.shop[i]
      GameTooltip:AddDoubleLine(x.qty .. " × " .. WC:ItemName(x.itemID), (x.est and "~" or "") .. Money(x.cost), 1, 1, 1, 1, 1, 1)
    end
    if #plan.shop > SHOP_LINES then GameTooltip:AddLine(L.REP_TT_MORE:format(#plan.shop - SHOP_LINES), 0.6, 0.6, 0.6) end
  end
  GameTooltip:AddLine(" ")
  if plan.assumed then GameTooltip:AddLine(L.REP_TT_ASSUMED, 1, 0.6, 0.2, true) end
  if plan.labelOpen then GameTooltip:AddLine(L.REP_TT_LABEL, 0.3, 1, 0.4, true) end
  GameTooltip:AddLine(L.REP_TT_BAGS, 0.55, 0.55, 0.55, true)
  if plan.cashEst then GameTooltip:AddLine(L.EST_NOTE, 1, 0.82, 0.4, true) end
  GameTooltip:AddLine(L.REP_TT_CLICK, 0.3, 1, 0.4, true)
  GameTooltip:Show()
end

-- a plan row's tooltip: what is bought, what is owned
function Tab:ShowPlanRowTooltip(owner, e, kind)
  local bonus = WC:RepBonus()
  local owned = C_GREEN .. L.REP_OWNED .. "|r"
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if e.receipt then
    GameTooltip:AddLine(C_GREEN .. L.REP_RETURN_ROW:format(e.n) .. "|r")
    GameTooltip:AddLine(L.REP_TT_RETURN_HOW, 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L.TT_REP, L.TT_REP_VAL:format(Num(e.repGain), WC.REP.empty * e.n, Pct(bonus)), 1, 0.82, 0, 0.3, 1, 0.4)
    if e.haveCrates > 0 then GameTooltip:AddDoubleLine(L.REP_TT_CRATES_OWNED, tostring(e.haveCrates), 1, 0.82, 0, 1, 1, 1) end
    if e.buyCrates > 0 then
      GameTooltip:AddDoubleLine(L.REP_TT_CRATES .. " (" .. e.buyCrates .. ")", (e.cashEst and "~" or "") .. Money(e.cash), 1, 0.82, 0, 1, 1, 1)
    end
    if e.haveReceipts > 0 then GameTooltip:AddLine(L.REP_RETURN_RECEIPTS:format(e.haveReceipts), 1, 1, 1) end
    if e.favor > 0 then
      GameTooltip:AddDoubleLine(L.REP_TT_FAVOR, tostring(e.favor), 1, 0.82, 0, 1, 1, 1)
      GameTooltip:AddDoubleLine(L.REP_TT_FAVOR_WORTH, "~" .. Money(e.cost - e.cash), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(L.TT_PER_REP, (e.est and "~" or "") .. Money(e.perRep), 1, 0.82, 0, 0.3, 1, 0.4)
    if kind == "a" then GameTooltip:AddLine(L.CLICK_CRATE, 0.3, 1, 0.4) end
    GameTooltip:Show()
    return
  end
  local w = e.writ
  GameTooltip:AddLine("|cffffffff" .. WC:ItemName(w.writ) .. "|r")
  GameTooltip:AddLine((L.PROF[w.prof] or w.prof) .. " · " .. (L.WRIT_TIER[w.rep] or ""), 0.7, 0.7, 0.7)
  GameTooltip:AddDoubleLine(L.TT_REP, L.TT_REP_VAL:format(Num(e.repGain), w.rep, Pct(bonus)), 1, 0.82, 0, 0.3, 1, 0.4)
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine(L.TT_WRIT_PRICE, e.haveWrit and owned or ((e.writEst and "~" or "") .. Money(e.writCost)), 1, 0.82, 0, 1, 1, 1)
  local itemLeft = L.TT_ITEM_COST .. ": " .. ItemLine(w)
  if e.haveQty > 0 then itemLeft = itemLeft .. " (" .. L.REP_OWNED_N:format(e.haveQty) .. ")" end
  GameTooltip:AddDoubleLine(itemLeft, e.buyQty == 0 and owned or ((e.itemEst and "~" or "") .. Money(e.itemCost)), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.TT_TOTAL, (e.est and "~" or "") .. Money(e.cost), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(L.TT_PER_REP, (e.est and "~" or "") .. Money(e.perRep), 1, 0.82, 0, 0.3, 1, 0.4)
  if e.est then GameTooltip:AddLine(L.EST_NOTE, 1, 0.82, 0.4, true) end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(L.TT_DAILY, 0.8, 0.8, 0.8)
  GameTooltip:AddLine(L.TT_WRIT_HOWTO, 0.55, 0.55, 0.55, true)
  if kind == "a" then
    GameTooltip:AddLine(L.CLICK_WRIT, 0.3, 1, 0.4)
  elseif kind == "b" then
    GameTooltip:AddLine(L.CLICK_ITEM:format(ItemLine(w)), 0.3, 1, 0.4)
  else
    GameTooltip:AddLine(L.CLICK_HINT_WRIT, 0.3, 1, 0.4)
  end
  GameTooltip:Show()
end

function Tab:ShowTooltip(owner, e, kind)
  if e.summary then return self:ShowPlanTooltip(owner, e.plan) end
  if e.plan then return self:ShowPlanRowTooltip(owner, e, kind) end
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
    GameTooltip:AddDoubleLine(L.TT_TOTAL, (e.est and "~" or "") .. Money(e.cost), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.TT_PER_REP, (e.est and "~" or "") .. Money(e.perRep), 1, 0.82, 0, 0.3, 1, 0.4)
    if e.est then GameTooltip:AddLine(L.EST_NOTE, 1, 0.82, 0.4, true) end
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
