local addonName, WC = ...

-- Crafting tab: what every recipe of this character costs and earns
-- (sell the product to a vendor, on the AH, or disenchant it). Numbers come from WC.Profit:Craft().
local UI = WC.UI
local L = WC.L

WC.AddLocale({
  enUS = {
    CRAFT_TAB = "Crafting",
    CRAFT_SUBTITLE = "Your recipes · materials at the cheaper of AH and vendor · AH sales after the 5% cut",
    CRAFT_SCAN_TIP = "Scans the materials of your recipes and the items they make (materials sold by vendors are skipped).",
    CRAFT_ONLY_PROFIT = "Only profitable",
    CRAFT_ONLY_PROFIT_TIP = "Hides recipes that lose money however you sell the product.",
    CRAFT_HIDE_MISSING = "Hide missing prices",
    CRAFT_HIDE_MISSING_TIP = "Hides recipes with a material that has no price yet (not on the AH and no vendor sells it), or whose product has no price.",
    CRAFT_PROF = "Profession",
    CRAFT_PROF_TIP = "Left-click: next profession. Right-click: previous.",
    CRAFT_ALL = "All",
    CRAFT_SEARCH = "Search recipe or item",
    CRAFT_HEAD_RECIPE = "Recipe (product)",
    CRAFT_HEAD_COST = "Materials",
    CRAFT_HEAD_NPC = "Sell to vendor",
    CRAFT_HEAD_AH = "Sell on AH",
    CRAFT_HEAD_DE = "Disenchant",
    CRAFT_NO_RECIPES = "Open each profession window once so Waylaid Crate can read your recipes.",
    CRAFT_BEST_LABEL = "Most profitable recipe",
    CRAFT_BEST_LOSS = "Nothing makes a profit right now · smallest loss",
    CRAFT_BEST_EMPTY = "Scan at the Auction House to price your recipes",
    CRAFT_PROFIT_VIA = "Profit · %s",
    CRAFT_KIND_npc = "sell to vendor",
    CRAFT_KIND_ah = "sell on AH",
    CRAFT_KIND_de = "disenchant",
    CRAFT_BEST_DETAIL = "Materials %s  ->  %s %s",
    CRAFT_CASH = "cash %s",
    CRAFT_ALL_IN_BAGS = "all in bags",
    CRAFT_MISSING_N = "%d without price",
    CRAFT_SELLS = "sells %s",
    CRAFT_NEEDS = "needs %s",
    CRAFT_LOADING = "loading…",
    CRAFT_PRINT_BEST = "Scan finished. Most profitable craft: %s, %s profit (%s).",
    CRAFT_PRINT_NONE = "Scan finished. None of your recipes makes a profit right now.",
    CRAFT_TT_LIST = "Shopping list (one craft)",
    CRAFT_TT_HAVE = "have %d",
    CRAFT_TT_EACH = "%s each",
    CRAFT_TT_AH = "AH (cheapest, %s)",
    CRAFT_TT_AH_EST = "AH (cheapest seen while browsing, %s)",
    CRAFT_TT_AH_SHORT = "not enough on the AH",
    CRAFT_TT_VENDOR = "Vendor: %s",
    CRAFT_TT_BUNDLE = "sold in %ds",
    CRAFT_TT_LIMITED = "limited stock",
    CRAFT_TT_CLASSIC = "Classic location — may differ",
    CRAFT_TT_ALSO = "also: %s",
    CRAFT_TT_NO_PRICE = "No price: not on the AH and no vendor sells it",
    CRAFT_TT_NOT_SCANNED = "Not scanned yet",
    CRAFT_TT_COST = "Materials",
    CRAFT_TT_CASH = "Cash still needed",
    CRAFT_TT_CASH_NOTE = "Materials in your bags count at market price.",
    CRAFT_TT_YIELD = "Makes",
    CRAFT_TT_YIELD_RANGE = "%d–%d (avg %s)",
    CRAFT_TT_NPC = "Sell to vendor",
    CRAFT_TT_AHS = "Sell on AH (after 5% cut)",
    CRAFT_TT_DE = "Disenchant (estimate)",
    CRAFT_TT_PROFIT = "profit %s",
    CRAFT_TT_NO_VENDOR = "vendors don't buy it",
    CRAFT_TT_NOT_CACHED = "price not loaded yet",
    CRAFT_TT_NOT_LISTED = "not on the AH (or not scanned)",
    CRAFT_TT_NO_DE = "can't be disenchanted",
    CRAFT_TT_NEED_COST = "needs all material prices",
    CRAFT_TT_TOOL = "Needs: %s",
    CRAFT_TT_PARTIAL = "Some disenchant materials have no price yet.",
    CRAFT_CLICK_PRODUCT = "Click: search %s on the Auction House",
    CRAFT_CLICK_MAT = "Click: search %s (the most expensive material from the AH)",
    CRAFT_CLICK_HINT = "Click the recipe to search the product · click the materials cost to search its most expensive AH material",
    CRAFT_AGO_NOW = "just now",
    CRAFT_AGO_MIN = "%d min ago",
    CRAFT_AGO_H = "%d h ago",
    CRAFT_NO_ITEMS = "None of your %d recipes makes an item that can be sold (enchantments, for example).",
    CRAFT_NO_OUTPUT_N = "%d recipes without an item not shown",
    CRAFT_TT_DE_SKILL = "needs Enchanting %d",
    CRAFT_TT_DE_MISSING = "disenchant materials have no price yet",
    CRAFT_TT_DE_MEASURED = "measured from your disenchants",
    CRAFT_TT_EST = "AH price from browsing: only the cheapest listing is known",
    CRAFT_AGO_D = "%d days ago",
  },
  zhCN = {
    CRAFT_TAB = "制造",
    CRAFT_SUBTITLE = "你会的配方 · 材料按拍卖行和商人里更便宜的算 · 拍卖行售价已扣 5% 手续费",
    CRAFT_SCAN_TIP = "扫描你的配方用到的材料和做出来的物品（商人有卖的材料不扫）。",
    CRAFT_ONLY_PROFIT = "只看赚钱的",
    CRAFT_ONLY_PROFIT_TIP = "隐藏怎么卖都亏钱的配方。",
    CRAFT_HIDE_MISSING = "隐藏缺价格的",
    CRAFT_HIDE_MISSING_TIP = "隐藏有材料还没有价格（拍卖行没有、商人也不卖）或者成品没有价格的配方。",
    CRAFT_PROF = "专业",
    CRAFT_PROF_TIP = "左键：下一个专业。右键：上一个。",
    CRAFT_ALL = "全部",
    CRAFT_SEARCH = "搜索配方或物品",
    CRAFT_HEAD_RECIPE = "配方（成品）",
    CRAFT_HEAD_COST = "材料成本",
    CRAFT_HEAD_NPC = "卖给商人",
    CRAFT_HEAD_AH = "拍卖行卖",
    CRAFT_HEAD_DE = "分解",
    CRAFT_NO_RECIPES = "请把每个专业窗口都打开一次，Waylaid Crate 才能读到你的配方。",
    CRAFT_BEST_LABEL = "最赚钱的配方",
    CRAFT_BEST_LOSS = "现在没有赚钱的配方 · 亏得最少的",
    CRAFT_BEST_EMPTY = "在拍卖行扫描后，这里显示最赚钱的配方",
    CRAFT_PROFIT_VIA = "利润 · %s",
    CRAFT_KIND_npc = "卖给商人",
    CRAFT_KIND_ah = "拍卖行卖",
    CRAFT_KIND_de = "分解",
    CRAFT_BEST_DETAIL = "材料 %s  ->  %s %s",
    CRAFT_CASH = "还需 %s",
    CRAFT_ALL_IN_BAGS = "材料都在包里",
    CRAFT_MISSING_N = "%d 种没价格",
    CRAFT_SELLS = "售价 %s",
    CRAFT_NEEDS = "需要%s",
    CRAFT_LOADING = "加载中…",
    CRAFT_PRINT_BEST = "扫描完成。最赚钱的制造：%s，利润 %s（%s）。",
    CRAFT_PRINT_NONE = "扫描完成。你的配方现在都不赚钱。",
    CRAFT_TT_LIST = "购物清单（做一次）",
    CRAFT_TT_HAVE = "包里有 %d",
    CRAFT_TT_EACH = "单价 %s",
    CRAFT_TT_AH = "拍卖行（最低价，%s）",
    CRAFT_TT_AH_EST = "拍卖行（浏览时看到的最低价，%s）",
    CRAFT_TT_AH_SHORT = "拍卖行数量不够",
    CRAFT_TT_VENDOR = "商人：%s",
    CRAFT_TT_BUNDLE = "每次买 %d 个",
    CRAFT_TT_LIMITED = "限量供应",
    CRAFT_TT_CLASSIC = "怀旧服的位置，可能不一样",
    CRAFT_TT_ALSO = "也可以：%s",
    CRAFT_TT_NO_PRICE = "没有价格：拍卖行没有，商人也不卖",
    CRAFT_TT_NOT_SCANNED = "还没扫描",
    CRAFT_TT_COST = "材料成本",
    CRAFT_TT_CASH = "还要花的钱",
    CRAFT_TT_CASH_NOTE = "包里已有的材料按市价算进成本。",
    CRAFT_TT_YIELD = "每次做出",
    CRAFT_TT_YIELD_RANGE = "%d–%d 个（平均 %s）",
    CRAFT_TT_NPC = "卖给商人",
    CRAFT_TT_AHS = "拍卖行卖（扣 5% 手续费）",
    CRAFT_TT_DE = "分解（估算）",
    CRAFT_TT_PROFIT = "利润 %s",
    CRAFT_TT_NO_VENDOR = "商人不收",
    CRAFT_TT_NOT_CACHED = "价格还没加载",
    CRAFT_TT_NOT_LISTED = "拍卖行没有（或还没扫描）",
    CRAFT_TT_NO_DE = "不能分解",
    CRAFT_TT_NEED_COST = "需要所有材料都有价格",
    CRAFT_TT_TOOL = "需要：%s",
    CRAFT_TT_PARTIAL = "有些分解材料还没有价格。",
    CRAFT_CLICK_PRODUCT = "点击：在拍卖行搜索 %s",
    CRAFT_CLICK_MAT = "点击：在拍卖行搜索 %s（从拍卖行买的最贵的材料）",
    CRAFT_CLICK_HINT = "点配方名 = 搜索成品 · 点材料成本 = 搜索从拍卖行买的最贵的材料",
    CRAFT_AGO_NOW = "刚刚",
    CRAFT_AGO_MIN = "%d 分钟前",
    CRAFT_AGO_H = "%d 小时前",
    CRAFT_NO_ITEMS = "你的 %d 个配方都做不出能卖的物品（比如附魔）。",
    CRAFT_NO_OUTPUT_N = "%d 个没有成品的配方不显示",
    CRAFT_TT_DE_SKILL = "需要附魔 %d",
    CRAFT_TT_DE_MISSING = "分解材料还没有价格",
    CRAFT_TT_DE_MEASURED = "按你自己的分解结果计算",
    CRAFT_TT_EST = "拍卖行价格来自浏览：只知道最便宜的那一条",
    CRAFT_AGO_D = "%d 天前",
  },
  zhTW = {
    CRAFT_TAB = "製造",
    CRAFT_SUBTITLE = "你會的配方 · 材料按拍賣場和商人裡較便宜的算 · 拍賣場售價已扣 5% 手續費",
    CRAFT_SCAN_TIP = "掃描你的配方用到的材料和做出來的物品（商人有賣的材料不掃）。",
    CRAFT_ONLY_PROFIT = "只看賺錢的",
    CRAFT_ONLY_PROFIT_TIP = "隱藏怎麼賣都虧錢的配方。",
    CRAFT_HIDE_MISSING = "隱藏缺價格的",
    CRAFT_HIDE_MISSING_TIP = "隱藏有材料還沒有價格（拍賣場沒有、商人也不賣）或者成品沒有價格的配方。",
    CRAFT_PROF = "專業",
    CRAFT_PROF_TIP = "左鍵：下一個專業。右鍵：上一個。",
    CRAFT_ALL = "全部",
    CRAFT_SEARCH = "搜尋配方或物品",
    CRAFT_HEAD_RECIPE = "配方（成品）",
    CRAFT_HEAD_COST = "材料成本",
    CRAFT_HEAD_NPC = "賣給商人",
    CRAFT_HEAD_AH = "拍賣場賣",
    CRAFT_HEAD_DE = "分解",
    CRAFT_NO_RECIPES = "請把每個專業視窗都打開一次，Waylaid Crate 才能讀到你的配方。",
    CRAFT_BEST_LABEL = "最賺錢的配方",
    CRAFT_BEST_LOSS = "現在沒有賺錢的配方 · 虧得最少的",
    CRAFT_BEST_EMPTY = "在拍賣場掃描後，這裡顯示最賺錢的配方",
    CRAFT_PROFIT_VIA = "利潤 · %s",
    CRAFT_KIND_npc = "賣給商人",
    CRAFT_KIND_ah = "拍賣場賣",
    CRAFT_KIND_de = "分解",
    CRAFT_BEST_DETAIL = "材料 %s  ->  %s %s",
    CRAFT_CASH = "還需 %s",
    CRAFT_ALL_IN_BAGS = "材料都在包裡",
    CRAFT_MISSING_N = "%d 種沒價格",
    CRAFT_SELLS = "售價 %s",
    CRAFT_NEEDS = "需要%s",
    CRAFT_LOADING = "載入中…",
    CRAFT_PRINT_BEST = "掃描完成。最賺錢的製造：%s，利潤 %s（%s）。",
    CRAFT_PRINT_NONE = "掃描完成。你的配方現在都不賺錢。",
    CRAFT_TT_LIST = "購物清單（做一次）",
    CRAFT_TT_HAVE = "包裡有 %d",
    CRAFT_TT_EACH = "單價 %s",
    CRAFT_TT_AH = "拍賣場（最低價，%s）",
    CRAFT_TT_AH_EST = "拍賣場（瀏覽時看到的最低價，%s）",
    CRAFT_TT_AH_SHORT = "拍賣場數量不夠",
    CRAFT_TT_VENDOR = "商人：%s",
    CRAFT_TT_BUNDLE = "每次買 %d 個",
    CRAFT_TT_LIMITED = "限量供應",
    CRAFT_TT_CLASSIC = "經典版的位置，可能不一樣",
    CRAFT_TT_ALSO = "也可以：%s",
    CRAFT_TT_NO_PRICE = "沒有價格：拍賣場沒有，商人也不賣",
    CRAFT_TT_NOT_SCANNED = "還沒掃描",
    CRAFT_TT_COST = "材料成本",
    CRAFT_TT_CASH = "還要花的錢",
    CRAFT_TT_CASH_NOTE = "包裡已有的材料按市價算進成本。",
    CRAFT_TT_YIELD = "每次做出",
    CRAFT_TT_YIELD_RANGE = "%d–%d 個（平均 %s）",
    CRAFT_TT_NPC = "賣給商人",
    CRAFT_TT_AHS = "拍賣場賣（扣 5% 手續費）",
    CRAFT_TT_DE = "分解（估算）",
    CRAFT_TT_PROFIT = "利潤 %s",
    CRAFT_TT_NO_VENDOR = "商人不收",
    CRAFT_TT_NOT_CACHED = "價格還沒載入",
    CRAFT_TT_NOT_LISTED = "拍賣場沒有（或還沒掃描）",
    CRAFT_TT_NO_DE = "不能分解",
    CRAFT_TT_NEED_COST = "需要所有材料都有價格",
    CRAFT_TT_TOOL = "需要：%s",
    CRAFT_TT_PARTIAL = "有些分解材料還沒有價格。",
    CRAFT_CLICK_PRODUCT = "點擊：在拍賣場搜尋 %s",
    CRAFT_CLICK_MAT = "點擊：在拍賣場搜尋 %s（從拍賣場買的最貴的材料）",
    CRAFT_CLICK_HINT = "點配方名 = 搜尋成品 · 點材料成本 = 搜尋從拍賣場買的最貴的材料",
    CRAFT_AGO_NOW = "剛剛",
    CRAFT_AGO_MIN = "%d 分鐘前",
    CRAFT_AGO_H = "%d 小時前",
    CRAFT_NO_ITEMS = "你的 %d 個配方都做不出能賣的物品（比如附魔）。",
    CRAFT_NO_OUTPUT_N = "%d 個沒有成品的配方不顯示",
    CRAFT_TT_DE_SKILL = "需要附魔 %d",
    CRAFT_TT_DE_MISSING = "分解材料還沒有價格",
    CRAFT_TT_DE_MEASURED = "按你自己的分解結果計算",
    CRAFT_TT_EST = "拍賣場價格來自瀏覽：只知道最便宜的那一條",
    CRAFT_AGO_D = "%d 天前",
  },
})

-- settings of this tab (registered before DB_READY)
if WC.Store and WC.Store.Default then
  WC.Store:Default("craftOnlyProfit", false)
  WC.Store:Default("craftHideMissing", false)
  WC.Store:Default("craftProf", "all")
end

local Money, Num, Font = WC.Money, UI.Num, UI.Font
local C_GREEN, C_ORANGE, C_GREY = UI.C_GREEN, UI.C_ORANGE, UI.C_GREY
local C_WHITE = "|cffffffff"
local C_RED = "|cffff5a4a"
local C_GREEN_DIM = "|cff8cc796"
local C_RED_DIM = "|cffc77a70"
local QUALITY = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000", "|cffe6cc80", "|cff00ccff" }

local Tab = {}

-- Two column layouts for the 662 px rows: with and without the disenchant column.
local COL_DE = {
  rank   = { x = 4, w = 26, justify = "CENTER" },
  recipe = { x = 36, w = 246 },
  cost   = { r = 368, w = 80 },
  npc    = { r = 462, w = 88 },
  ah     = { r = 556, w = 88 },
  de     = { r = 650, w = 88 },
}
local COL_NODE = {
  rank   = { x = 4, w = 26, justify = "CENTER" },
  recipe = { x = 36, w = 306 },
  cost   = { r = 438, w = 86 },
  npc    = { r = 544, w = 100 },
  ah     = { r = 650, w = 100 },
  de     = { r = 650, w = 100 },
}
Tab.COL_DE, Tab.COL_NODE = COL_DE, COL_NODE
local HEAD_Y, LIST_TOP = -140, -156

-- ---------------------------------------------------------------------------
-- small helpers

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function Ago(t)
  if not t then return "?" end
  local s = math.max(0, time() - t)
  if s < 60 then return L.CRAFT_AGO_NOW end
  if s < 3600 then return L.CRAFT_AGO_MIN:format(math.floor(s / 60)) end
  if s < 86400 then return L.CRAFT_AGO_H:format(math.floor(s / 3600)) end
  return L.CRAFT_AGO_D:format(math.floor(s / 86400))
end

-- item name (client language) and quality; unknown items are requested and refreshed once they load
function Tab:ItemName(itemID)
  local name, _, quality = WC.ItemInfo(itemID)
  if name then return name, quality end
  if C_Item and C_Item.GetItemNameByID then
    local ok, n = pcall(C_Item.GetItemNameByID, itemID)
    if ok and n and n ~= "" then return n, nil end
  end
  WC.RequestItem(itemID)
  self:WaitForNames()
  return nil, nil
end

local function ReagentID(r) return r.itemID or r[1] end
local function ReagentQty(r) return r.qty or r[2] or 1 end

local function GreyMoney(v) return UI.Colored(Money(v), C_GREY) end

-- "+1g 20s" / "-35s"
local function SignedMoney(v)
  if v > 0 then return "+" .. Money(v) end
  return Money(v)
end

local function ProfitColor(v, best)
  if v > 0 then return best and C_GREEN or C_GREEN_DIM end
  if v < 0 then return best and C_RED or C_RED_DIM end
  return C_WHITE
end

local function KindName(kind) return kind and L["CRAFT_KIND_" .. kind] or "" end

local function Revenue(e, kind)
  if kind == "npc" then return e.npc elseif kind == "ah" then return e.ah elseif kind == "de" then return e.de end
end

local function FontObj(name) return _G[name] or name end

local function DESkill(e)
  local v = e.deValue
  return type(v) == "table" and tonumber(v.skill) or nil
end

function Tab:ProductName(e)
  local name, quality = self:ItemName(e.itemID)
  if not name then return C_WHITE .. (e.name or ("item:" .. tostring(e.itemID))) .. "|r", false end
  return (QUALITY[quality or 1] or C_WHITE) .. name .. "|r", true
end

function Tab:ProductLabel(e)
  local s = self:ProductName(e)
  if e.yield and math.abs(e.yield - 1) > 0.001 then s = s .. C_GREY .. " ×" .. Num(e.yield) .. "|r" end
  return s
end

function Tab:ProfName(skillLine)
  local p = self.profs and self.profs[skillLine]
  if type(p) == "table" and (p.name or p[1]) then return p.name or p[1] end
  if type(p) == "string" then return p end
  if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLine)
    if ok and type(info) == "table" and info.professionName and info.professionName ~= "" then return info.professionName end
  end
  return tostring(skillLine)
end

-- the most expensive material bought on the AH (or, if none has an AH price, the first one without any price)
local function CostliestAH(e)
  local best, bestCost, firstMissing
  for _, r in ipairs(e.reagents or {}) do
    if r.source == "ah" and r.cost and (not bestCost or r.cost > bestCost) then
      best, bestCost = ReagentID(r), r.cost
    elseif r.missing and not firstMissing then
      firstMissing = ReagentID(r)
    end
  end
  return best or firstMissing
end
Tab.CostliestAH = CostliestAH

-- price details of one material: { ah = { cost, status, unit, time, source }, vendor = { unit, info } }
local function MatInfo(r)
  if type(r.mat) == "table" then return r.mat end
  if r.ah or r.vendor then return r end
  local P = WC.Profit
  if P and P.MatCost then
    local ok, m = pcall(P.MatCost, P, ReagentID(r), ReagentQty(r))
    if ok and type(m) == "table" then return m end
  end
  return {}
end

local function VendorWhere(info)
  if type(info) ~= "table" then return "?" end
  local s = info.npc or info.name or "?"
  if info.zone and info.zone ~= "" then s = s .. ", " .. info.zone end
  if info.x and info.y then s = s .. string.format(" (%.1f, %.1f)", info.x, info.y) end
  return s
end

local function VendorText(unit, info)
  local s = L.CRAFT_TT_EACH:format(Money(unit)) .. " — " .. L.CRAFT_TT_VENDOR:format(VendorWhere(info))
  if type(info) == "table" then
    if info.bundle and info.bundle > 1 then s = s .. " — " .. L.CRAFT_TT_BUNDLE:format(info.bundle) end
    if info.limited then s = s .. " — " .. L.CRAFT_TT_LIMITED end
  end
  return s
end

local function AHText(unit, a)
  local s = unit and (L.CRAFT_TT_EACH:format(Money(unit)) .. " — ") or ""
  if a.status == "est" or a.source == "browse" then return s .. L.CRAFT_TT_AH_EST:format(Ago(a.time)) end
  return s .. L.CRAFT_TT_AH:format(Ago(a.time))
end

-- ---------------------------------------------------------------------------
-- data

local NO_COUNTS = {}

-- Profit:Craft list + counts (never errors; empty when Profit is missing or fails)
function Tab:Entries(charKey)
  local P = WC.Profit
  if not (P and P.Craft) then return {}, NO_COUNTS end
  local ok, list, counts = pcall(P.Craft, P, charKey)
  if not ok or type(list) ~= "table" then
    if not ok and UI.Report then UI.Report("craft:Profit", list) end
    return {}, NO_COUNTS
  end
  if type(counts) ~= "table" and P.CraftCounts then
    local ok2, c = pcall(P.CraftCounts, P, charKey)
    counts = ok2 and c or nil
  end
  return list, type(counts) == "table" and counts or NO_COUNTS
end

-- number of captured recipes (with or without an item)
function Tab:RecipeCount(charKey, all, counts)
  if type(counts.total) == "number" then return counts.total end
  if #all > 0 then return #all end
  local R = WC.Recipes
  if R and R.HasData then
    local ok, has = pcall(R.HasData, R, charKey)
    if ok and has then return 1 end
  end
  return 0
end

function Tab:HasEnchanting(charKey, all)
  if WC.EnchantingSkill then
    local ok, skill = pcall(WC.EnchantingSkill, WC, charKey)
    if ok then return type(skill) == "number" and skill > 0 end
  end
  for _, e in ipairs(all) do if e.de ~= nil then return true end end
  return false
end

-- profession picker values: "all" + the character's professions that have recipes in the list, by name
function Tab:ProfValues(charKey, all)
  local profs
  local R = WC.Recipes
  if R and R.Professions then
    local ok, p = pcall(R.Professions, R, charKey)
    if ok and type(p) == "table" then profs = p end
  end
  self.profs = profs or {}
  local used, list = {}, {}
  for _, e in ipairs(all) do
    if e.prof ~= nil and not used[e.prof] then used[e.prof] = true; list[#list + 1] = e.prof end
  end
  table.sort(list, function(a, b)
    local na, nb = self:ProfName(a), self:ProfName(b)
    if na ~= nb then return na < nb end
    return tostring(a) < tostring(b)
  end)
  local values = self.profValues or {}
  for i = #values, 1, -1 do values[i] = nil end
  values[1] = "all"
  for i = 1, #list do values[i + 1] = list[i] end
  self.profValues = values
  return values
end

local function Matches(self, e, q)
  if q == "" then return true end
  if e.name and string.lower(e.name):find(q, 1, true) then return true end
  local name = self:ItemName(e.itemID)
  return name ~= nil and string.lower(name):find(q, 1, true) ~= nil
end

-- filtered + ranked list of wrappers { e = entry, rank } (reused tables; Profit's entries are not changed).
-- Returns vis, number of entries matching the profession + search (before the two switches).
function Tab:Visible(all)
  local db = WC:DB()
  local prof = db.craftProf
  local q = self.query or ""
  local vis, wraps = self.vis or {}, self.wraps or {}
  self.vis, self.wraps = vis, wraps
  local n, matched, rank = 0, 0, 0
  for _, e in ipairs(all) do
    if (prof == nil or prof == "all" or e.prof == prof) and Matches(self, e, q) then
      matched = matched + 1
      local show = true
      if db.craftOnlyProfit and not (e.best and e.best > 0) then show = false end
      if db.craftHideMissing and (e.cost == nil or e.best == nil) then show = false end
      if show then
        n = n + 1
        local w = wraps[n]
        if not w then w = {}; wraps[n] = w end
        w.e = e
        if e.best ~= nil then rank = rank + 1; w.rank = rank else w.rank = nil end
        vis[n] = w
      end
    end
  end
  for i = #vis, n + 1, -1 do vis[i] = nil end
  return vis, matched
end

-- ---------------------------------------------------------------------------
-- widgets

local function Place(fs, row, col, y)
  fs:ClearAllPoints()
  fs:SetWidth(col.w)
  if col.r then fs:SetPoint("TOPRIGHT", row, "TOPLEFT", col.r, y) else fs:SetPoint("TOPLEFT", row, "TOPLEFT", col.x, y) end
end

-- profession picker: the shell's value cycler with a value list that follows the character's professions
function Tab:CreateProfCycler(panel, x, y)
  -- the shell asks on every refresh, also while another tab is open: only compute when this tab is visible
  local function values()
    if self.profValues and not (self.panel and self.panel:IsShown()) then return self.profValues end
    local charKey = WC:CharKey()
    return self:ProfValues(charKey, (self:Entries(charKey)))
  end
  local function label(v)
    if v == nil or v == "all" then return L.CRAFT_ALL end
    return self:ProfName(v)
  end
  if UI.ValueCycler then
    local fs, b = UI:ValueCycler(panel, x, y, L.CRAFT_PROF, "craftProf", values, label, L.CRAFT_PROF_TIP)
    b.minWidth = 110
    self.profLabel, self.profButton, self.profLabelFn = fs, b, label
    return
  end
  -- fallback for a shell without ValueCycler
  local fs = Font(panel, "GameFontHighlightSmall", "LEFT")
  fs:SetPoint("TOPLEFT", x, y - 4)
  fs:SetText(L.CRAFT_PROF)
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(132, 20)
  b:SetPoint("LEFT", fs, "RIGHT", 6, 0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, button)
    local vals = values()
    local db = WC:DB()
    local cur = 1
    for i, v in ipairs(vals) do if v == db.craftProf then cur = i end end
    cur = (button == "RightButton") and (cur - 1) or (cur + 1)
    if cur > #vals then cur = 1 elseif cur < 1 then cur = #vals end
    if WaylaidCrateDB then WaylaidCrateDB.craftProf = vals[cur] end
    UI:Refresh()
  end)
  UI.Tip(b, L.CRAFT_PROF, L.CRAFT_PROF_TIP)
  self.profLabel, self.profButton, self.profLabelFn = fs, b, label
end

local function LocalEditBox(parent, w, placeholder, onChange)
  local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  eb:SetSize(w, 20)
  eb:SetAutoFocus(false)
  eb:SetFontObject(FontObj("GameFontHighlightSmall"))
  eb:SetTextInsets(6, 6, 0, 0)
  UI.Backdrop(eb, { 0, 0, 0, 0.45 }, { 0.35, 0.33, 0.3, 1 })
  local ph = Font(eb, "GameFontDisableSmall", "LEFT", w - 12)
  ph:SetPoint("LEFT", 7, 0)
  ph:SetText(placeholder)
  eb.placeholder = ph
  eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
  eb:SetScript("OnTextChanged", function(s)
    local t = s:GetText() or ""
    ph:SetShown(t == "")
    onChange(t)
  end)
  return eb
end

function Tab:Create(panel)
  self.panel = panel
  self.rows = {}
  self.query = ""
  self.cols, self.hasDE = COL_DE, true   -- rows built from now on follow self.cols

  UI:CheckRow(panel, -2, {
    { L.CRAFT_ONLY_PROFIT, "craftOnlyProfit", L.CRAFT_ONLY_PROFIT_TIP },
    { L.CRAFT_HIDE_MISSING, "craftHideMissing", L.CRAFT_HIDE_MISSING_TIP },
  })
  self.hidden = Font(panel, "GameFontDisableSmall", "RIGHT", 330)
  self.hidden:SetPoint("TOPRIGHT", -2, -7)

  self:CreateProfCycler(panel, 0, -28)
  local function onText(text)
    if type(text) ~= "string" then text = "" end
    local q = string.lower(Trim(text))
    if q == self.query then return end
    self.query = q
    if self.panel:IsShown() then self:Refresh() end
  end
  if UI.EditBox then
    self.search = UI:EditBox(panel, 200, L.CRAFT_SEARCH, function(text) onText(text) end)
  else
    self.search = LocalEditBox(panel, 200, L.CRAFT_SEARCH, onText)
  end
  self.search:ClearAllPoints()
  self.search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -27)

  self.best = UI:BestPanel(panel, -54, self)

  self.list = UI:List(panel, HEAD_Y, LIST_TOP, COL_DE, nil, function(row) self:BuildRow(row) end)
  local h = self.list.headers
  h.rank:SetText("#")
  h.recipe:SetText(L.CRAFT_HEAD_RECIPE)
  h.cost:SetText(L.CRAFT_HEAD_COST)
  h.npc:SetText(L.CRAFT_HEAD_NPC)
  h.ah:SetText(L.CRAFT_HEAD_AH)
  h.de:SetText(L.CRAFT_HEAD_DE)
end

-- called by the list for every row frame it builds (also later, when the list grows)
function Tab:BuildRow(row)
  local function cell(template) return Font(row, template, "LEFT") end
  row.name = cell("GameFontHighlight")
  row.sub = cell("GameFontDisableSmall")
  row.cost = cell("GameFontHighlightSmall")
  row.costSub = cell("GameFontDisableSmall")
  row.npc = cell("GameFontHighlightSmall")
  row.npcSub = cell("GameFontDisableSmall")
  row.ah = cell("GameFontHighlightSmall")
  row.ahSub = cell("GameFontDisableSmall")
  row.de = cell("GameFontHighlightSmall")
  row.deSub = cell("GameFontDisableSmall")
  row.hotA = UI.Hotspot(row, self, "a", function() return row.entry end)
  row.hotB = UI.Hotspot(row, self, "b", function() return row.entry end)
  row:SetScript("OnEnter", function(r) if r.entry then self:ShowTooltip(r, r.entry) end end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  self.rows[#self.rows + 1] = row
  self:LayoutRow(row)
end

function Tab:LayoutRow(row)
  local C, hasDE = self.cols or COL_DE, self.hasDE ~= false
  Place(row.name, row, C.recipe, -3)
  Place(row.sub, row, C.recipe, -18)
  for _, k in ipairs({ "cost", "npc", "ah", "de" }) do
    row[k]:SetJustifyH("RIGHT")
    row[k .. "Sub"]:SetJustifyH("RIGHT")
    Place(row[k], row, C[k], -4)
    Place(row[k .. "Sub"], row, C[k], -18)
  end
  row.de:SetShown(hasDE)
  row.deSub:SetShown(hasDE)
  local ROW_H = UI.ROW_H or 32
  row.hotA:ClearAllPoints()
  row.hotA:SetPoint("TOPLEFT", row, "TOPLEFT", C.recipe.x - 4, 0)
  row.hotA:SetSize(C.recipe.w + 4, ROW_H)
  row.hotB:ClearAllPoints()
  row.hotB:SetPoint("TOPLEFT", row, "TOPLEFT", C.cost.r - C.cost.w - 4, 0)
  row.hotB:SetSize(C.cost.w + 8, ROW_H)
end

-- switch between the layouts with / without the disenchant column
function Tab:ApplyLayout(hasDE)
  local C = hasDE and COL_DE or COL_NODE
  self.cols, self.hasDE = C, hasDE
  for key, fs in pairs(self.list.headers) do
    local col = C[key]
    if col then
      fs:ClearAllPoints()
      fs:SetWidth(col.w)
      fs:SetPoint("TOPLEFT", self.panel, "TOPLEFT", col.r and (col.r - col.w) or col.x, HEAD_Y)
    end
  end
  self.list.headers.de:SetShown(hasDE)
  for _, row in ipairs(self.rows) do self:LayoutRow(row) end
end

-- ---------------------------------------------------------------------------
-- rows

-- one profit column: main line = profit (the row's best brighter + larger), sub line = what it sells for
local function ProfitCell(main, sub, profit, revenue, isBest, partial, subText)
  local tilde = partial and "~" or ""
  if profit ~= nil then
    main:SetFontObject(FontObj(isBest and "GameFontHighlight" or "GameFontHighlightSmall"))
    main:SetText(UI.Colored(tilde .. SignedMoney(profit), ProfitColor(profit, isBest)))
  else
    main:SetFontObject(FontObj("GameFontHighlightSmall"))
    main:SetText(C_GREY .. "—|r")
  end
  if subText then
    sub:SetText(subText)
  elseif revenue == nil then
    sub:SetText("")
  else
    sub:SetText(L.CRAFT_SELLS:format(tilde .. GreyMoney(revenue)))
  end
end

function Tab:FillRow(row, w)
  local e = w.e
  row.name:SetText(self:ProductLabel(e))
  local parts = {}
  local prof = WC:DB().craftProf
  if prof == nil or prof == "all" then parts[#parts + 1] = self:ProfName(e.prof) end
  if e.tool and e.tool ~= "" then parts[#parts + 1] = L.CRAFT_NEEDS:format(e.tool) end
  if e.status == "loading" then parts[#parts + 1] = L.CRAFT_LOADING end
  row.sub:SetText(table.concat(parts, " · "))

  if e.cost then
    row.cost:SetText(Money(e.cost))
    if e.cash and e.cash < e.cost then
      row.costSub:SetText(e.cash <= 0 and (C_GREEN .. L.CRAFT_ALL_IN_BAGS .. "|r") or L.CRAFT_CASH:format(GreyMoney(e.cash)))
    else
      row.costSub:SetText("")
    end
  else
    row.cost:SetText(C_ORANGE .. "?|r")
    local n = type(e.missing) == "table" and #e.missing or 0
    row.costSub:SetText(n > 0 and (C_ORANGE .. L.CRAFT_MISSING_N:format(n) .. "|r") or "")
  end
  local noBuy = (e.npc == 0 or e.npcNoBuy) and (C_GREY .. L.CRAFT_TT_NO_VENDOR .. "|r") or nil
  ProfitCell(row.npc, row.npcSub, (not noBuy) and e.npcProfit or nil, e.npc, e.bestKind == "npc", false, noBuy)
  ProfitCell(row.ah, row.ahSub, e.ahProfit, e.ah, e.bestKind == "ah", false)
  if self.hasDE then
    local skill = DESkill(e)
    local low = e.deSkillOK == false and skill and (C_ORANGE .. L.CRAFT_TT_DE_SKILL:format(skill) .. "|r") or nil
    ProfitCell(row.de, row.deSub, e.deProfit, e.de, e.bestKind == "de", e.dePartial, low)
  end
  row.hotB:SetShown(CostliestAH(e) ~= nil)
end

function Tab:Refresh()
  if not self.list then return end
  local charKey = WC:CharKey()
  local all, counts = self:Entries(charKey)
  local hasDE = self:HasEnchanting(charKey, all)
  if hasDE ~= self.hasDE then self:ApplyLayout(hasDE) end

  -- profession picker: forget a profession this character doesn't have
  local values = self:ProfValues(charKey, all)
  local db = WC:DB()
  local known = false
  for _, v in ipairs(values) do if v == db.craftProf then known = true end end
  if not known and db.craftProf ~= nil and #all > 0 and WaylaidCrateDB then
    WaylaidCrateDB.craftProf = "all"
    self.profButton:SetText(L.CRAFT_ALL)
  end

  local nRecipes = self:RecipeCount(charKey, all, counts)
  local emptyText
  if nRecipes == 0 then emptyText = L.CRAFT_NO_RECIPES
  elseif #all == 0 then emptyText = L.CRAFT_NO_ITEMS:format(nRecipes) end

  local vis, matched = self:Visible(all)
  local top = UI:FillList(self.list, vis, function(row, w) self:FillRow(row, w) end, emptyText)
  local notes = {}
  local hiddenCount = matched - #vis
  if hiddenCount > 0 then notes[#notes + 1] = L.HIDDEN_N:format(hiddenCount) end
  if (counts.noOutput or 0) > 0 and #all > 0 then notes[#notes + 1] = L.CRAFT_NO_OUTPUT_N:format(counts.noOutput) end
  self.hidden:SetText(table.concat(notes, " · "))

  local b = self.best
  if emptyText then
    UI:ShowBest(b, false, emptyText)
    return
  end
  if not top then
    UI:ShowBest(b, false, (WC.Scanner and WC.Scanner.active) and L.BEST_EMPTY_SCANNING or L.CRAFT_BEST_EMPTY)
    return
  end
  local e = top.e
  UI:ShowBest(b, true)
  b.frame.entry = top
  b.label:SetText(e.best > 0 and L.CRAFT_BEST_LABEL or L.CRAFT_BEST_LOSS)
  b.name:SetText(self:ProductLabel(e) .. "  " .. C_GREY .. self:ProfName(e.prof) .. "|r")
  b.detail:SetText(L.CRAFT_BEST_DETAIL:format(Money(e.cost), KindName(e.bestKind), Money(Revenue(e, e.bestKind))))
  b.perLabel:SetText(L.CRAFT_PROFIT_VIA:format(KindName(e.bestKind)))
  b.per:SetText(UI.Colored(SignedMoney(e.best), ProfitColor(e.best, true)))
  if e.cash and e.cost and e.cash < e.cost then
    b.net:SetText(L.CRAFT_TT_CASH .. " " .. Money(e.cash))
  elseif e.tool and e.tool ~= "" then
    b.net:SetText(L.CRAFT_TT_TOOL:format(e.tool))
  else
    b.net:SetText("")
  end
  b.hot2:SetShown(CostliestAH(e) ~= nil)
end

function Tab:BestMessage()
  local all, counts = self:Entries(WC:CharKey())
  if #all == 0 then return (counts.total or 0) == 0 and L.CRAFT_NO_RECIPES or L.CRAFT_PRINT_NONE end
  local vis = self:Visible(all)
  local top = vis[1]
  if top and top.rank == 1 and top.e.best > 0 then
    local e = top.e
    return L.CRAFT_PRINT_BEST:format((self:ProductName(e)), Money(e.best), KindName(e.bestKind))
  end
  return L.CRAFT_PRINT_NONE
end

function Tab:Subtitle() return L.CRAFT_SUBTITLE end
function Tab:ScanTip() return L.CRAFT_SCAN_TIP end
function Tab:ScanKind() return "craft" end

-- what a click searches: "a" = the product, "b" = the most expensive material bought on the AH
function Tab:SearchTarget(w, kind)
  local e = w.e or w
  if kind == "a" then return e.itemID end
  if kind == "b" then return CostliestAH(e) end
end

-- ---------------------------------------------------------------------------
-- tooltip: the shopping list

local function OptionRight(value, profit, reason, partial)
  if value == nil then return C_GREY .. reason .. "|r" end
  local tilde = partial and "~" or ""
  local s = tilde .. Money(value)
  if profit ~= nil then
    s = s .. "   " .. UI.Colored(L.CRAFT_TT_PROFIT:format(tilde .. SignedMoney(profit)), ProfitColor(profit, true))
  else
    s = s .. "   " .. C_GREY .. L.CRAFT_TT_NEED_COST .. "|r"
  end
  return s
end

function Tab:YieldText(e)
  local R = WC.Recipes
  if R and R.ForChar and e.recipeID then
    local ok, recipes = pcall(R.ForChar, R, WC:CharKey())
    local rec = ok and type(recipes) == "table" and recipes[e.recipeID]
    if type(rec) == "table" and rec.y1 and rec.y2 and rec.y1 ~= rec.y2 then
      return L.CRAFT_TT_YIELD_RANGE:format(rec.y1, rec.y2, Num(e.yield or (rec.y1 + rec.y2) / 2))
    end
  end
  return Num(e.yield or 1)
end

-- "qty × name — have N" + total, then "unit — source" (+ the other source, + Classic note)
function Tab:ReagentLines(r)
  local T = GameTooltip
  local id, qty = ReagentID(r), ReagentQty(r)
  local name = self:ItemName(id) or ("item:" .. tostring(id))
  local have = r.have or WC.BagCount(id) or 0
  local haveColor = (have >= qty and C_GREEN) or (have > 0 and "|cffffd100") or C_GREY
  local left = qty .. " × " .. name .. " " .. haveColor .. "— " .. L.CRAFT_TT_HAVE:format(have) .. "|r"
  T:AddDoubleLine(left, r.cost and Money(r.cost) or (C_ORANGE .. "?|r"), 0.9, 0.9, 0.9, 1, 1, 1)

  local m = MatInfo(r)
  local a, v = m.ah or {}, m.vendor or {}
  local vinfo = v.info
  local classic = type(vinfo) == "table" and vinfo.classic
  local ahUsable = a.cost ~= nil and (a.status == "ok" or a.status == "est")
  local src = r.source or m.source
  if src == "vendor" and v.unit then
    T:AddLine("      " .. VendorText(v.unit, vinfo), 0.62, 0.62, 0.62)
    if classic then T:AddLine("      " .. L.CRAFT_TT_CLASSIC, 1, 0.6, 0.2) end
    if ahUsable then T:AddLine("      " .. L.CRAFT_TT_ALSO:format(AHText(a.unit, a)), 0.5, 0.5, 0.5) end
  elseif src == "ah" then
    T:AddLine("      " .. AHText(r.unit or a.unit, a), 0.62, 0.62, 0.62)
    if v.unit then
      T:AddLine("      " .. L.CRAFT_TT_ALSO:format(VendorText(v.unit, vinfo)), 0.5, 0.5, 0.5)
      if classic then T:AddLine("      " .. L.CRAFT_TT_CLASSIC, 1, 0.6, 0.2) end
    end
  else
    local why
    if a.status == "short" then why = L.CRAFT_TT_AH_SHORT
    elseif a.status == nil or r.status == "unscanned" then why = L.CRAFT_TT_NOT_SCANNED
    else why = L.CRAFT_TT_NO_PRICE end
    T:AddLine("      " .. why, 1, 0.6, 0.2)
  end
end

local function DEReason(e)
  local st = e.deStatus
  if st == "missing" then return L.CRAFT_TT_DE_MISSING end
  if st == "loading" then return L.CRAFT_LOADING end
  return L.CRAFT_TT_NO_DE
end

function Tab:ShowTooltip(owner, w, kind)
  local e = w.e or w
  local T = GameTooltip
  T:SetOwner(owner, "ANCHOR_RIGHT")
  T:AddLine(self:ProductLabel(e))
  local sub = self:ProfName(e.prof)
  local productName = self:ItemName(e.itemID)
  if e.name and e.name ~= productName then sub = e.name .. " · " .. sub end
  T:AddLine(sub, 0.7, 0.7, 0.7)
  T:AddLine(" ")
  T:AddLine(L.CRAFT_TT_LIST, 1, 0.82, 0)
  for _, r in ipairs(e.reagents or {}) do self:ReagentLines(r) end
  T:AddLine(" ")

  if e.cost then
    T:AddDoubleLine(L.CRAFT_TT_COST, Money(e.cost), 1, 0.82, 0, 1, 1, 1)
    if e.cash then
      T:AddDoubleLine(L.CRAFT_TT_CASH, Money(e.cash), 1, 0.82, 0, 1, 1, 1)
      if e.cash < e.cost then T:AddLine(L.CRAFT_TT_CASH_NOTE, 0.55, 0.55, 0.55, true) end
    end
    if e.est then T:AddLine(L.CRAFT_TT_EST, 0.55, 0.55, 0.55, true) end
  else
    local n = type(e.missing) == "table" and #e.missing or 0
    T:AddDoubleLine(L.CRAFT_TT_COST, C_ORANGE .. L.CRAFT_MISSING_N:format(n) .. "|r", 1, 0.82, 0, 1, 1, 1)
  end
  T:AddDoubleLine(L.CRAFT_TT_YIELD, self:YieldText(e), 1, 0.82, 0, 1, 1, 1)
  T:AddLine(" ")

  local function label(text, k)
    if e.bestKind == k then return C_GREEN .. "» " .. text .. "|r" end
    return "   " .. text
  end
  if e.npc == 0 or e.npcNoBuy then
    T:AddDoubleLine(label(L.CRAFT_TT_NPC, "npc"), C_GREY .. L.CRAFT_TT_NO_VENDOR .. "|r", 1, 0.82, 0, 1, 1, 1)
  else
    T:AddDoubleLine(label(L.CRAFT_TT_NPC, "npc"), OptionRight(e.npc, e.npcProfit, L.CRAFT_TT_NOT_CACHED), 1, 0.82, 0, 1, 1, 1)
  end
  local ahRight = OptionRight(e.ah, e.ahProfit, L.CRAFT_TT_NOT_LISTED)
  if e.ahUnit and e.yield and math.abs(e.yield - 1) > 0.001 then
    ahRight = C_GREY .. "(" .. L.CRAFT_TT_EACH:format(GreyMoney(e.ahUnit)) .. ")|r  " .. ahRight
  end
  T:AddDoubleLine(label(L.CRAFT_TT_AHS, "ah"), ahRight, 1, 0.82, 0, 1, 1, 1)
  if e.ahTime and e.ah then T:AddLine("      " .. AHText(nil, { time = e.ahTime, source = e.ahSource }), 0.5, 0.5, 0.5) end
  if self.hasDE then
    T:AddDoubleLine(label(L.CRAFT_TT_DE, "de"), OptionRight(e.de, e.deProfit, DEReason(e), e.dePartial), 1, 0.82, 0, 1, 1, 1)
    local skill = DESkill(e)
    if e.deSkillOK == false and skill then T:AddLine("      " .. L.CRAFT_TT_DE_SKILL:format(skill), 1, 0.6, 0.2) end
    if e.dePartial then T:AddLine("      " .. L.CRAFT_TT_PARTIAL, 0.55, 0.55, 0.55) end
    if e.deMeasured then T:AddLine("      " .. L.CRAFT_TT_DE_MEASURED, 0.55, 0.55, 0.55) end
  end
  if e.tool and e.tool ~= "" then
    T:AddLine(" ")
    T:AddLine(L.CRAFT_TT_TOOL:format(e.tool), 1, 0.6, 0.2)
  end
  if kind == "a" then
    T:AddLine(L.CRAFT_CLICK_PRODUCT:format(productName or e.name or "?"), 0.3, 1, 0.4)
  elseif kind == "b" then
    local id = CostliestAH(e)
    if id then T:AddLine(L.CRAFT_CLICK_MAT:format(self:ItemName(id) or ("item:" .. id)), 0.3, 1, 0.4) end
  else
    T:AddLine(L.CRAFT_CLICK_HINT, 0.3, 1, 0.4, true)
  end
  T:Show()
end

-- ---------------------------------------------------------------------------
-- item names that arrive later (reagents, search): one refresh after the client has loaded them

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
        if Tab.panel and Tab.panel:IsShown() then UI:Refresh() end
      end)
    end)
  end
  pcall(nameFrame.RegisterEvent, nameFrame, "ITEM_DATA_LOAD_RESULT")
end

-- ---------------------------------------------------------------------------
-- registration

if UI.RegisterTab then
  UI:RegisterTab("craft", { order = 4, label = function() return L.CRAFT_TAB end, tab = Tab })
else
  UI.tabs = UI.tabs or {}
  UI.tabs.craft = Tab
end
