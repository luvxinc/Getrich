local addonName, WC = ...

-- Disenchant tab: what gear turns into, and whether disenchanting beats the vendor (bags) or the price (AH, crafted).
-- Data: WC.Profit:Disenchant() (Profit.lua) and WC.DE (Disenchant.lua). Helpers: WC.UIA (UIFlips.lua).
local UI = WC.UI
local UIA = WC.UIA
local L = WC.L
local Money, Font, Pct = WC.Money, UI.Font, UI.Pct
local C_GREEN, C_ORANGE, C_GREY = UI.C_GREEN, UI.C_ORANGE, UI.C_GREY
local C_RED = UIA.C_RED

WC.AddLocale({
  enUS = {
    DE_UI_TAB = "Disenchant",
    DE_UI_SUBTITLE = "What your gear disenchants into · disenchant it or sell it to a vendor? · also AH gear and gear you can craft",
    DE_UI_SCAN_TIP = "Checks the price of every disenchanting material, then reads uncommon, rare and epic weapons and armor on the Auction House (1-3 minutes).",
    DE_UI_SOURCE = "Show",
    DE_UI_SOURCE_TIP = "Which gear to list: everything, gear in your bags, gear on the Auction House, or gear you can craft.",
    DE_UI_SRC_ALL = "All",
    DE_UI_SRC_BAG = "Bags",
    DE_UI_SRC_AH = "AH",
    DE_UI_SRC_CRAFT = "Crafted",
    DE_UI_HIDE_SKILL = "Hide what I can't disenchant yet",
    DE_UI_HIDE_SKILL_TIP = "Hides items that need more Enchanting skill than this character has.",
    DE_UI_HIDE_LOSS = "Hide where it's not worth it",
    DE_UI_HIDE_LOSS_TIP = "Hides items where disenchanting gives less than a vendor pays (bags) or less than the item costs (AH, crafted).",
    DE_UI_SKILL = "Enchanting %d",
    DE_UI_NO_ENCHANT = "This character has no Enchanting — showing what your gear would disenchant into.",
    DE_UI_NO_ENCHANT_SHORT = "No Enchanting on this character",
    DE_UI_HEAD_ITEM = "Item",
    DE_UI_HEAD_INTO = "Disenchants into (per item)",
    DE_UI_HEAD_VALUE = "DE value",
    DE_UI_HEAD_VS = "Vendor / cost",
    DE_UI_HEAD_GAIN = "Gain",
    DE_UI_TAG_BAG = "bags",
    DE_UI_TAG_AH = "AH",
    DE_UI_TAG_CRAFT = "crafted",
    DE_UI_ILVL = "ilvl %d",
    DE_UI_NEEDS = "needs Enchanting %d",
    DE_UI_EST = "estimate",
    DE_UI_MEASURED = "measured (%d)",
    DE_UI_BAND = "%s %s %d-%d",
    DE_UI_SEP = ", ",
    DE_UI_VS_VENDOR = "vendor",
    DE_UI_VS_AH = "AH price",
    DE_UI_VS_CRAFT = "craft cost",
    DE_UI_DO_DE = "disenchant",
    DE_UI_DO_VENDOR = "vendor it",
    DE_UI_DO_BUY = "buy it",
    DE_UI_DO_CRAFT = "craft it",
    DE_UI_DO_SKIP = "skip",
    DE_UI_CANT = "can't be disenchanted",
    DE_UI_LOADING = "loading item info…",
    DE_UI_NOBAND = "no disenchant data for this item level",
    DE_UI_BEST_LABEL = "Best to disenchant",
    DE_UI_BEST_PER_BAG = "More than the vendor pays",
    DE_UI_BEST_PER_BUY = "Profit after buying",
    DE_UI_BEST_DETAIL = "Disenchants into: %s",
    DE_UI_BEST_NET = "DE value %s · %s %s",
    DE_UI_BEST_EMPTY = "After a scan (or with gear in your bags), the best item to disenchant shows up here",
    DE_UI_BEST_NONE = "Nothing here is worth more disenchanted — selling it is better",
    DE_UI_EMPTY_BAGS = "No gear in your bags that can be disenchanted (uncommon or better weapons and armor).",
    DE_UI_EMPTY_AH = "No AH gear data yet.\nPress Scan on this tab: it reads uncommon, rare and epic weapons and armor on the Auction House.",
    DE_UI_EMPTY_CRAFT = "No gear you can craft was found.\nOpen each profession window once so Waylaid Crate can read your recipes.",
    DE_UI_EMPTY_NOENCH_SRC = "This character has no Enchanting, so AH gear and crafted gear are not checked.",
    DE_UI_EMPTY_ALL = "Nothing to show yet.\nPut gear in your bags, or press Scan on this tab.",
    DE_UI_TT_INTO = "One disenchant gives",
    DE_UI_TT_CHANCE = "%s chance, %s each time",
    DE_UI_TT_UNIT = "AH %s each",
    DE_UI_TT_NOPRICE = "no AH price yet",
    DE_UI_TT_BAND = "Group: %s",
    DE_UI_TT_SKILL = "Needs Enchanting %d (you have %s)",
    DE_UI_TT_EST = "The odds are an estimate. Your own disenchants are recorded, and after 20 of them the real odds replace the estimate.",
    DE_UI_TT_MEASURED = "Odds measured from your own %d disenchants of this group.",
    DE_UI_TT_VALUE = "DE value (after the 5% AH cut)",
    DE_UI_TT_SELL = "Vendor pays",
    DE_UI_TT_BUY_AH = "AH price",
    DE_UI_TT_BUY_CRAFT = "Craft cost",
    DE_UI_TT_GAIN = "Gain",
    DE_UI_TT_COUNT = "For all %d in your bags",
    DE_UI_TT_MISSING = "No AH price yet for: %s (scan this tab)",
    DE_UI_TT_PARTIAL = "~ means some materials have no price yet, so the real value is higher.",
    DE_UI_TT_COST_MISSING = "No price yet for these crafting materials: %s",
    DE_UI_CLICK_ITEM = "Click: search this item on the Auction House",
    DE_UI_CLICK_MAT = "Click: search %s on the Auction House",
    DE_UI_PRINT_BEST = "Scan finished. Best to disenchant: %s (+%s).",
    DE_UI_PRINT_NONE = "Scan finished. Nothing is worth more disenchanted right now.",
    DE_UI_PRINT_NOENCH = "Scan finished. This character has no Enchanting; the Disenchant tab shows what your gear would turn into.",
  },
  zhCN = {
    DE_UI_TAB = "分解",
    DE_UI_SUBTITLE = "装备能分解出什么 · 分解还是卖商店更划算 · 也看拍卖行的装备和自己能做的装备",
    DE_UI_SCAN_TIP = "先查所有附魔材料的价格，再读取拍卖行上绿色、蓝色、紫色的武器和护甲（约 1-3 分钟）。",
    DE_UI_SOURCE = "显示",
    DE_UI_SOURCE_TIP = "列出哪些装备：全部、背包里的、拍卖行上的、或者自己能做的。",
    DE_UI_SRC_ALL = "全部",
    DE_UI_SRC_BAG = "背包",
    DE_UI_SRC_AH = "拍卖行",
    DE_UI_SRC_CRAFT = "自制",
    DE_UI_HIDE_SKILL = "隐藏技能还不够的",
    DE_UI_HIDE_SKILL_TIP = "需要的附魔技能比这个角色高的物品不显示。",
    DE_UI_HIDE_LOSS = "隐藏不划算的",
    DE_UI_HIDE_LOSS_TIP = "分解所得比卖商店少（背包），或者比物品价格低（拍卖行、自制）的不显示。",
    DE_UI_SKILL = "附魔 %d",
    DE_UI_NO_ENCHANT = "这个角色没有学附魔——下面显示的是你的装备能分解出什么。",
    DE_UI_NO_ENCHANT_SHORT = "这个角色没有附魔",
    DE_UI_HEAD_ITEM = "物品",
    DE_UI_HEAD_INTO = "分解出（每件）",
    DE_UI_HEAD_VALUE = "分解价值",
    DE_UI_HEAD_VS = "商店价/成本",
    DE_UI_HEAD_GAIN = "多赚",
    DE_UI_TAG_BAG = "背包",
    DE_UI_TAG_AH = "拍卖行",
    DE_UI_TAG_CRAFT = "自制",
    DE_UI_ILVL = "物品等级 %d",
    DE_UI_NEEDS = "需要附魔 %d",
    DE_UI_EST = "估算",
    DE_UI_MEASURED = "实测（%d 次）",
    DE_UI_BAND = "%s%s %d-%d",
    DE_UI_SEP = "、",
    DE_UI_VS_VENDOR = "商店价",
    DE_UI_VS_AH = "拍卖价",
    DE_UI_VS_CRAFT = "制作成本",
    DE_UI_DO_DE = "分解",
    DE_UI_DO_VENDOR = "卖商店",
    DE_UI_DO_BUY = "买来分解",
    DE_UI_DO_CRAFT = "做来分解",
    DE_UI_DO_SKIP = "不划算",
    DE_UI_CANT = "不能分解",
    DE_UI_LOADING = "正在读取物品信息…",
    DE_UI_NOBAND = "没有这个物品等级的分解数据",
    DE_UI_BEST_LABEL = "最值得分解",
    DE_UI_BEST_PER_BAG = "比卖商店多赚",
    DE_UI_BEST_PER_BUY = "扣除成本后赚",
    DE_UI_BEST_DETAIL = "分解出：%s",
    DE_UI_BEST_NET = "分解价值 %s · %s %s",
    DE_UI_BEST_EMPTY = "扫描后（或者背包里有装备时），这里显示最值得分解的物品",
    DE_UI_BEST_NONE = "这里没有分解比卖掉更划算的",
    DE_UI_EMPTY_BAGS = "背包里没有能分解的装备（绿色或更好的武器和护甲）。",
    DE_UI_EMPTY_AH = "还没有拍卖行装备数据。\n在这一页点『扫描』：会读取拍卖行上绿色、蓝色、紫色的武器和护甲。",
    DE_UI_EMPTY_CRAFT = "没找到你能做的装备。\n每个专业窗口打开一次，Waylaid Crate 才能读到你的配方。",
    DE_UI_EMPTY_NOENCH_SRC = "这个角色没有附魔，所以不查拍卖行装备和自制装备。",
    DE_UI_EMPTY_ALL = "暂时没有内容。\n背包里放些装备，或者在这一页点『扫描』。",
    DE_UI_TT_INTO = "分解一次得到",
    DE_UI_TT_CHANCE = "%s 几率，每次 %s 个",
    DE_UI_TT_UNIT = "拍卖价每个 %s",
    DE_UI_TT_NOPRICE = "还没有拍卖价",
    DE_UI_TT_BAND = "分组：%s",
    DE_UI_TT_SKILL = "需要附魔 %d（你现在 %s）",
    DE_UI_TT_EST = "几率是估算的。你自己的分解会被记录下来，满 20 次后改用实测几率。",
    DE_UI_TT_MEASURED = "几率来自你自己对这一组的 %d 次分解。",
    DE_UI_TT_VALUE = "分解价值（已扣 5% 拍卖行手续费）",
    DE_UI_TT_SELL = "商店收购价",
    DE_UI_TT_BUY_AH = "拍卖价",
    DE_UI_TT_BUY_CRAFT = "制作成本",
    DE_UI_TT_GAIN = "多赚",
    DE_UI_TT_COUNT = "背包里 %d 件合计",
    DE_UI_TT_MISSING = "还没有拍卖价：%s（扫描这一页）",
    DE_UI_TT_PARTIAL = "~ 表示有材料还没有价格，实际价值更高。",
    DE_UI_TT_COST_MISSING = "这些制作材料还没有价格：%s",
    DE_UI_CLICK_ITEM = "点击：在拍卖行搜索这个物品",
    DE_UI_CLICK_MAT = "点击：在拍卖行搜索 %s",
    DE_UI_PRINT_BEST = "扫描完成。最值得分解：%s（+%s）。",
    DE_UI_PRINT_NONE = "扫描完成。目前没有分解比卖掉更划算的。",
    DE_UI_PRINT_NOENCH = "扫描完成。这个角色没有附魔；分解页显示的是你的装备能分解出什么。",
  },
  zhTW = {
    DE_UI_TAB = "分解",
    DE_UI_SUBTITLE = "裝備能分解出什麼 · 分解還是賣商店更划算 · 也看拍賣場的裝備和自己能做的裝備",
    DE_UI_SCAN_TIP = "先查所有附魔材料的價格，再讀取拍賣場上綠色、藍色、紫色的武器和護甲（約 1-3 分鐘）。",
    DE_UI_SOURCE = "顯示",
    DE_UI_SOURCE_TIP = "列出哪些裝備：全部、背包裡的、拍賣場上的、或者自己能做的。",
    DE_UI_SRC_ALL = "全部",
    DE_UI_SRC_BAG = "背包",
    DE_UI_SRC_AH = "拍賣場",
    DE_UI_SRC_CRAFT = "自製",
    DE_UI_HIDE_SKILL = "隱藏技能還不夠的",
    DE_UI_HIDE_SKILL_TIP = "需要的附魔技能比這個角色高的物品不顯示。",
    DE_UI_HIDE_LOSS = "隱藏不划算的",
    DE_UI_HIDE_LOSS_TIP = "分解所得比賣商店少（背包），或者比物品價格低（拍賣場、自製）的不顯示。",
    DE_UI_SKILL = "附魔 %d",
    DE_UI_NO_ENCHANT = "這個角色沒有學附魔——下面顯示的是你的裝備能分解出什麼。",
    DE_UI_NO_ENCHANT_SHORT = "這個角色沒有附魔",
    DE_UI_HEAD_ITEM = "物品",
    DE_UI_HEAD_INTO = "分解出（每件）",
    DE_UI_HEAD_VALUE = "分解價值",
    DE_UI_HEAD_VS = "商店價/成本",
    DE_UI_HEAD_GAIN = "多賺",
    DE_UI_TAG_BAG = "背包",
    DE_UI_TAG_AH = "拍賣場",
    DE_UI_TAG_CRAFT = "自製",
    DE_UI_ILVL = "物品等級 %d",
    DE_UI_NEEDS = "需要附魔 %d",
    DE_UI_EST = "估算",
    DE_UI_MEASURED = "實測（%d 次）",
    DE_UI_BAND = "%s%s %d-%d",
    DE_UI_SEP = "、",
    DE_UI_VS_VENDOR = "商店價",
    DE_UI_VS_AH = "拍賣價",
    DE_UI_VS_CRAFT = "製作成本",
    DE_UI_DO_DE = "分解",
    DE_UI_DO_VENDOR = "賣商店",
    DE_UI_DO_BUY = "買來分解",
    DE_UI_DO_CRAFT = "做來分解",
    DE_UI_DO_SKIP = "不划算",
    DE_UI_CANT = "不能分解",
    DE_UI_LOADING = "正在讀取物品資訊…",
    DE_UI_NOBAND = "沒有這個物品等級的分解資料",
    DE_UI_BEST_LABEL = "最值得分解",
    DE_UI_BEST_PER_BAG = "比賣商店多賺",
    DE_UI_BEST_PER_BUY = "扣除成本後賺",
    DE_UI_BEST_DETAIL = "分解出：%s",
    DE_UI_BEST_NET = "分解價值 %s · %s %s",
    DE_UI_BEST_EMPTY = "掃描後（或者背包裡有裝備時），這裡顯示最值得分解的物品",
    DE_UI_BEST_NONE = "這裡沒有分解比賣掉更划算的",
    DE_UI_EMPTY_BAGS = "背包裡沒有能分解的裝備（綠色或更好的武器和護甲）。",
    DE_UI_EMPTY_AH = "還沒有拍賣場裝備資料。\n在這一頁點『掃描』：會讀取拍賣場上綠色、藍色、紫色的武器和護甲。",
    DE_UI_EMPTY_CRAFT = "沒找到你能做的裝備。\n每個專業視窗打開一次，Waylaid Crate 才能讀到你的配方。",
    DE_UI_EMPTY_NOENCH_SRC = "這個角色沒有附魔，所以不查拍賣場裝備和自製裝備。",
    DE_UI_EMPTY_ALL = "暫時沒有內容。\n背包裡放些裝備，或者在這一頁點『掃描』。",
    DE_UI_TT_INTO = "分解一次得到",
    DE_UI_TT_CHANCE = "%s 機率，每次 %s 個",
    DE_UI_TT_UNIT = "拍賣價每個 %s",
    DE_UI_TT_NOPRICE = "還沒有拍賣價",
    DE_UI_TT_BAND = "分組：%s",
    DE_UI_TT_SKILL = "需要附魔 %d（你現在 %s）",
    DE_UI_TT_EST = "機率是估算的。你自己的分解會被記錄下來，滿 20 次後改用實測機率。",
    DE_UI_TT_MEASURED = "機率來自你自己對這一組的 %d 次分解。",
    DE_UI_TT_VALUE = "分解價值（已扣 5% 拍賣場手續費）",
    DE_UI_TT_SELL = "商店收購價",
    DE_UI_TT_BUY_AH = "拍賣價",
    DE_UI_TT_BUY_CRAFT = "製作成本",
    DE_UI_TT_GAIN = "多賺",
    DE_UI_TT_COUNT = "背包裡 %d 件合計",
    DE_UI_TT_MISSING = "還沒有拍賣價：%s（掃描這一頁）",
    DE_UI_TT_PARTIAL = "~ 表示有材料還沒有價格，實際價值更高。",
    DE_UI_TT_COST_MISSING = "這些製作材料還沒有價格：%s",
    DE_UI_CLICK_ITEM = "點擊：在拍賣場搜尋這個物品",
    DE_UI_CLICK_MAT = "點擊：在拍賣場搜尋 %s",
    DE_UI_PRINT_BEST = "掃描完成。最值得分解：%s（+%s）。",
    DE_UI_PRINT_NONE = "掃描完成。目前沒有分解比賣掉更划算的。",
    DE_UI_PRINT_NOENCH = "掃描完成。這個角色沒有附魔；分解頁顯示的是你的裝備能分解出什麼。",
  },
})

local Tab = {}

local SOURCES = { "all", "bag", "ah", "craft" }
local SOURCE_TEXT = { all = "DE_UI_SRC_ALL", bag = "DE_UI_SRC_BAG", ah = "DE_UI_SRC_AH", craft = "DE_UI_SRC_CRAFT" }
local TAG_COLOR = { bag = "|cff9fd0ff", ah = "|cffffd100", craft = C_GREEN }
local TAG_TEXT = { bag = "DE_UI_TAG_BAG", ah = "DE_UI_TAG_AH", craft = "DE_UI_TAG_CRAFT" }

UIA.Default("deSource", "all")
UIA.Default("deHideSkill", false)
UIA.Default("deHideLoss", false)

-- content width 662: 4..30 | 36..196 | 202..428 | 432..500 | 504..568 | 572..650
local COL = {
  rank  = { x = 4, w = 26, justify = "CENTER" },
  item  = { x = 36, w = 160 },
  into  = { x = 202, w = 226 },
  value = { r = 500, w = 68 },
  vs    = { r = 568, w = 64 },
  gain  = { r = 650, w = 78 },
}

-- Enchanting skill of this character, nil if it has none
local function EnchantSkill()
  if not WC.EnchantingSkill then return nil end
  local ok, s = pcall(WC.EnchantingSkill, WC)
  if ok and type(s) == "number" and s > 0 then return s end
end

-- DE:Value parts / DE:Expected rows carry named fields (and positional ones per SPEC); read either
local function Part(p) return p.itemID or p[1], p.qty or p[2], p.unit or p[3], p.value or p[4] end
local function Odds(x) return x.itemID or x[1], x.chance or x[2], x.min or x[3], x.max or x[4] end

local function DECall(fn, ...)
  local DE = WC.DE
  if not (DE and type(DE[fn]) == "function") then return nil end
  local ok, a, b, c = pcall(DE[fn], DE, ...)
  if ok then return a, b, c end
end

-- what an entry turns into: parts (DE:Value format) or nil + reason. Profit puts DE:Value in e.de;
-- if it is missing, ask DE directly so the column still says what the item becomes.
local function Outputs(e)
  local de = e.de
  if type(de) == "table" and type(de.parts) == "table" and #de.parts > 0 then return de.parts, de end
  local reason = e.reason
  if reason == "loading" or reason == "nodisenchant" or reason == "noband" or reason == "notgear" or reason == "quality" then
    return nil, nil, reason
  end
  local v, why = DECall("Value", e.itemID, e.ilvl)
  if type(v) == "table" and type(v.parts) == "table" and #v.parts > 0 then return v.parts, v end
  return nil, nil, why or reason or e.status
end

local function ReasonText(reason)
  local t = reason and DECall("ReasonText", reason)
  if type(t) == "string" and t ~= "" and t ~= reason then return t end
  if reason == "loading" then return L.DE_UI_LOADING end
  if reason == "noband" then return L.DE_UI_NOBAND end
  return L.DE_UI_CANT
end

function Tab:IntoText(e)
  local parts, _, reason = Outputs(e)
  if not parts then return C_GREY .. ReasonText(reason) .. "|r" end
  local out = self.intoBuf or {}
  self.intoBuf = out
  for i = #out, 1, -1 do out[i] = nil end
  for i, p in ipairs(parts) do
    local id, qty = Part(p)
    out[i] = UIA.Name(self, id) .. " ×" .. UIA.Qty(qty)
  end
  return table.concat(out, L.DE_UI_SEP)
end

-- "Uncommon armor 16-20" (short, for the row); the tooltip uses DE:BandLabel
local function BandShort(band)
  if type(band) ~= "table" then return nil end
  return L.DE_UI_BAND:format(L["DE_Q" .. tostring(band.q)] or "", L["DE_CLASS" .. tostring(band.class)] or "", band.lo or 0, band.hi or 0)
end

local function BandLong(band)
  local t = DECall("BandLabel", band)
  if type(t) == "string" and t ~= "" then return t end
  return BandShort(band)
end

local function OddsLabel(e)
  if e.measured then return L.DE_UI_MEASURED:format(e.casts or 0) end
  return L.DE_UI_EST
end

local function TagText(e, withCount)
  local s = (TAG_COLOR[e.source] or "") .. L[TAG_TEXT[e.source] or "DE_UI_TAG_BAG"] .. "|r"
  if withCount and e.source == "bag" and (e.count or 1) > 1 then s = s .. " ×" .. e.count end
  return s
end

function Tab:Create(panel)
  self.panel = panel
  UI:CheckRow(panel, -2, {
    { L.DE_UI_HIDE_SKILL, "deHideSkill", L.DE_UI_HIDE_SKILL_TIP },
    { L.DE_UI_HIDE_LOSS, "deHideLoss", L.DE_UI_HIDE_LOSS_TIP },
  })
  self.hidden = Font(panel, "GameFontDisableSmall", "RIGHT", 90)
  self.hidden:SetPoint("TOPRIGHT", -2, -7)

  self.srcLabel, self.srcButton = UIA.Cycler(panel, 0, -28, L.DE_UI_SOURCE, "deSource", SOURCES,
    function(v) return L[SOURCE_TEXT[v] or "DE_UI_SRC_ALL"] end, L.DE_UI_SOURCE_TIP)
  self.skill = Font(panel, "GameFontDisableSmall", "RIGHT", 480)
  self.skill:SetPoint("TOPRIGHT", -2, -33)

  self.best = UI:BestPanel(panel, -54, self)

  self.list = UIA.List(panel, COL, function(row)
    row.name = UIA.Cell(row, COL.item, "GameFontHighlight", -3)
    row.sub = UIA.Cell(row, COL.item, "GameFontDisableSmall", -18)
    row.into = UIA.Cell(row, COL.into, "GameFontHighlightSmall", -4)
    row.intoSub = UIA.Cell(row, COL.into, "GameFontDisableSmall", -18)
    row.value = UIA.Cell(row, COL.value, "GameFontHighlightSmall", -10)
    row.vs = UIA.Cell(row, COL.vs, "GameFontHighlightSmall", -4)
    row.vsSub = UIA.Cell(row, COL.vs, "GameFontDisableSmall", -18)
    row.gain = UIA.Cell(row, COL.gain, "GameFontHighlight", -3)
    row.gainSub = UIA.Cell(row, COL.gain, "GameFontDisableSmall", -18)
    row.hotA = UI.Hotspot(row, self, "a", function() return row.entry end)
    row.hotA:SetPoint("TOPLEFT", COL.item.x - 4, 0)
    row.hotA:SetSize(COL.item.w + 4, UI.ROW_H)
    row.hotB = UI.Hotspot(row, self, "b", function() return row.entry end)
    row.hotB:SetPoint("TOPLEFT", COL.into.x - 3, 0)
    row.hotB:SetSize(COL.into.w + 4, UI.ROW_H)
    row:SetScript("OnEnter", function(r) if r.entry then self:ShowTooltip(r, r.entry) end end)
    row:SetScript("OnLeave", GameTooltip_Hide)
  end)
  local h = self.list.headers
  h.rank:SetText("#")
  h.item:SetText(L.DE_UI_HEAD_ITEM)
  h.into:SetText(L.DE_UI_HEAD_INTO)
  h.value:SetText(L.DE_UI_HEAD_VALUE)
  h.vs:SetText(L.DE_UI_HEAD_VS)
  h.gain:SetText(L.DE_UI_HEAD_GAIN)
end

-- number of entries of the chosen source, the visible rows ({ d = entry, rank }), Enchanting skill.
-- Ranked: rows with a positive gain that this character can disenchant (any skill if it has no Enchanting).
function Tab:Visible()
  local all = UIA.ProfitList("Disenchant")
  local db = UIA.DB()
  local src = db.deSource or "all"
  local hideSkill, hideLoss = db.deHideSkill and true or false, db.deHideLoss and true or false
  local skill = EnchantSkill()
  local vis = self.vis or {}
  self.vis = vis
  for i = #vis, 1, -1 do vis[i] = nil end
  local count, n, rank = 0, 0, 0
  for _, e in ipairs(all) do            -- Profit sorts by gain, unknown last
    if src == "all" or e.source == src then
      count = count + 1
      local tooLow = skill ~= nil and e.de ~= nil and not e.skillOK
      local loss = e.gain ~= nil and e.gain <= 0
      if not ((hideSkill and (tooLow or not skill)) or (hideLoss and loss)) then
        local r
        if e.gain and e.gain > 0 and not tooLow then rank = rank + 1; r = rank end
        n = n + 1
        vis[n] = UIA.Wrapper(self, n, e, r)
      end
    end
  end
  return count, vis, skill
end

-- "a" = the item, "b" = the most valuable material it turns into
function Tab:SearchTarget(w, kind)
  local e = w.d
  if kind ~= "b" then return e.itemID end
  local parts = Outputs(e)
  local bestID, bestV
  for _, p in ipairs(parts or UIA.EMPTY) do
    local id, qty, unit, value = Part(p)
    local v = value or ((qty or 0) * (unit or 0))
    if id and (not bestV or v > bestV) then bestID, bestV = id, v end
  end
  return bestID
end

-- what the DE value is compared with: vendor price (bags), AH price, or material cost per craft
local function VsInfo(e)
  if e.source == "bag" then return e.sell, L.DE_UI_VS_VENDOR, L.DE_UI_TT_SELL end
  if e.source == "craft" then return e.buy, L.DE_UI_VS_CRAFT, L.DE_UI_TT_BUY_CRAFT end
  return e.buy, L.DE_UI_VS_AH, L.DE_UI_TT_BUY_AH
end

local function ValueText(e)
  if e.value == nil then return Money(nil) end
  return (e.partial and (C_ORANGE .. "~|r") or "") .. Money(e.value)
end

local function Verdict(e)
  if e.gain == nil then return "" end
  if e.gain > 0 then
    local word = (e.source == "ah" and L.DE_UI_DO_BUY) or (e.source == "craft" and L.DE_UI_DO_CRAFT) or L.DE_UI_DO_DE
    return C_GREEN .. word .. "|r"
  end
  return e.source == "bag" and L.DE_UI_DO_VENDOR or L.DE_UI_DO_SKIP
end

function Tab:FillRow(row, w, isTop)
  local e = w.d
  local skill = EnchantSkill()
  local tooLow = skill ~= nil and e.de ~= nil and not e.skillOK
  row:SetAlpha(tooLow and 0.5 or 1)
  row.name:SetText(UIA.ItemText(self, e.itemID))
  local sub
  if tooLow then
    sub = C_RED .. L.DE_UI_NEEDS:format(tonumber(e.skill) or 0) .. "|r"
  elseif e.ilvl then
    sub = L.DE_UI_ILVL:format(e.ilvl)
  end
  local tag = TagText(e, true)
  row.sub:SetText(sub and (tag .. " · " .. sub) or tag)

  row.into:SetText(self:IntoText(e))
  local band = BandShort(e.band)
  row.intoSub:SetText(e.de and (OddsLabel(e) .. (band and (" · " .. band) or "")) or "")
  row.value:SetText(ValueText(e))
  local vs, vsWord = VsInfo(e)
  row.vs:SetText(Money(vs))
  row.vsSub:SetText(vsWord)
  if e.gain then
    local color = isTop and C_GREEN or (e.gain > 0 and "|cffffffff" or C_RED)
    row.gain:SetText(UI.Colored(Money(e.gain), color))
  else
    row.gain:SetText(Money(nil))
  end
  row.gainSub:SetText(Verdict(e))
end

function Tab:EmptyText(count, skill)
  if count > 0 then return L.EMPTY_LIST end
  local src = UIA.DB().deSource or "all"
  if not skill and (src == "ah" or src == "craft") then return L.DE_UI_EMPTY_NOENCH_SRC end
  if src == "bag" then return L.DE_UI_EMPTY_BAGS end
  if src == "ah" then return L.DE_UI_EMPTY_AH end
  if src == "craft" then return L.DE_UI_EMPTY_CRAFT end
  return L.DE_UI_EMPTY_ALL
end

function Tab:Refresh()
  if not self.list then return end
  local count, vis, skill = self:Visible()
  local top = UI:FillList(self.list, vis, function(row, w, isTop) self:FillRow(row, w, isTop) end, self:EmptyText(count, skill))
  local hiddenCount = count - #vis
  self.hidden:SetText(hiddenCount > 0 and L.HIDDEN_N:format(hiddenCount) or "")
  self.srcButton.wcSync()
  self.skill:SetText(skill and (C_GREEN .. L.DE_UI_SKILL:format(skill) .. "|r") or (C_ORANGE .. L.DE_UI_NO_ENCHANT_SHORT .. "|r"))

  local b = self.best
  if not skill then
    UI:ShowBest(b, false, C_ORANGE .. L.DE_UI_NO_ENCHANT .. "|r")
    return
  end
  if not top then
    UI:ShowBest(b, false, count > 0 and L.DE_UI_BEST_NONE or L.DE_UI_BEST_EMPTY)
    return
  end
  UI:ShowBest(b, true)
  b.frame.entry = top
  local e = top.d
  b.label:SetText(L.DE_UI_BEST_LABEL)
  b.perLabel:SetText(e.source == "bag" and L.DE_UI_BEST_PER_BAG or L.DE_UI_BEST_PER_BUY)
  b.name:SetText(UIA.ItemText(self, e.itemID) .. "  " .. TagText(e, true))
  b.detail:SetText(L.DE_UI_BEST_DETAIL:format(self:IntoText(e)))
  b.per:SetText(UI.Colored(Money(e.gain), C_GREEN))
  local vs, vsWord = VsInfo(e)
  b.net:SetText(L.DE_UI_BEST_NET:format(ValueText(e), vsWord, Money(vs)))
end

function Tab:BestMessage()
  local _, vis, skill = self:Visible()
  if not skill then return L.DE_UI_PRINT_NOENCH end
  local top = vis[1]
  if top and top.rank == 1 then
    return L.DE_UI_PRINT_BEST:format(UIA.ItemText(self, top.d.itemID), Money(top.d.gain))
  end
  return L.DE_UI_PRINT_NONE
end

function Tab:ShowTooltip(owner, w, kind)
  local e = w.d
  local skill = EnchantSkill()
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(UIA.ItemText(self, e.itemID))
  GameTooltip:AddLine(TagText(e, true) .. (e.ilvl and (" · " .. L.DE_UI_ILVL:format(e.ilvl)) or ""), 0.7, 0.7, 0.7)
  GameTooltip:AddLine(" ")

  -- one line per material: expected quantity and value; below it chance, amount per disenchant, unit price
  local parts, v, reason = Outputs(e)
  GameTooltip:AddLine(L.DE_UI_TT_INTO, 1, 0.82, 0)
  if parts then
    local odds
    for _, p in ipairs(parts) do
      local id, qty, unit, value = Part(p)
      local chance, mn, mx = p.chance, p.min, p.max
      if chance == nil then   -- parts without odds: look them up in DE:Expected
        if odds == nil then
          odds = {}
          local exp = DECall("Expected", e.band or (v and v.band))
          for _, x in ipairs(type(exp) == "table" and exp or UIA.EMPTY) do
            local xid, xc, xmn, xmx = Odds(x)
            if xid then odds[xid] = { xc, xmn, xmx } end
          end
        end
        local o = odds[id]
        if o then chance, mn, mx = o[1], o[2], o[3] end
      end
      local right = value and Money(value) or (C_ORANGE .. L.DE_UI_TT_NOPRICE .. "|r")
      GameTooltip:AddDoubleLine("   " .. UIA.Name(self, id) .. "  ×" .. UIA.Qty(qty), right, 1, 1, 1, 1, 1, 1)
      local bits = {}
      if chance then
        local range = (mn and mx and mx ~= mn) and (mn .. "-" .. mx) or tostring(mn or 1)
        bits[#bits + 1] = L.DE_UI_TT_CHANCE:format(Pct(chance), range)
      end
      if unit then bits[#bits + 1] = L.DE_UI_TT_UNIT:format(Money(unit)) end
      if #bits > 0 then GameTooltip:AddLine("      " .. table.concat(bits, " · "), 0.6, 0.6, 0.6) end
    end
  else
    GameTooltip:AddLine("   " .. ReasonText(reason), 0.7, 0.7, 0.7)
  end
  local band = e.band or (v and v.band)
  if band then GameTooltip:AddLine(L.DE_UI_TT_BAND:format(BandLong(band)), 0.7, 0.7, 0.7) end
  local need = tonumber(e.skill or (v and v.skill))
  if need and (need > 1 or (skill and not e.skillOK)) then
    local ok = skill ~= nil and e.skillOK
    GameTooltip:AddLine(L.DE_UI_TT_SKILL:format(need, skill and tostring(skill) or "0"), ok and 0.7 or 1, ok and 0.7 or 0.35, ok and 0.7 or 0.3)
  end
  if e.de or v then
    if e.measured then GameTooltip:AddLine(L.DE_UI_TT_MEASURED:format(e.casts or 0), 0.3, 1, 0.4, true)
    else GameTooltip:AddLine(L.DE_UI_TT_EST, 0.55, 0.55, 0.55, true) end
  end
  if not skill then GameTooltip:AddLine(L.DE_UI_NO_ENCHANT, 1, 0.6, 0.2, true) end
  GameTooltip:AddLine(" ")

  local vs, _, vsLabel = VsInfo(e)
  GameTooltip:AddDoubleLine(L.DE_UI_TT_VALUE, ValueText(e), 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(vsLabel, Money(vs), 1, 0.82, 0, 1, 1, 1)
  if e.gain then
    GameTooltip:AddDoubleLine(L.DE_UI_TT_GAIN, UI.Colored(Money(e.gain), e.gain > 0 and C_GREEN or C_RED) .. "  " .. Verdict(e), 1, 0.82, 0, 1, 1, 1)
    if e.source == "bag" and (e.count or 1) > 1 then
      GameTooltip:AddDoubleLine(L.DE_UI_TT_COUNT:format(e.count), Money(e.totalGain or e.gain * e.count), 1, 0.82, 0, 1, 1, 1)
    end
  end
  if type(e.missing) == "table" and #e.missing > 0 then
    local names = {}
    for i, id in ipairs(e.missing) do names[i] = UIA.Name(self, id) end
    GameTooltip:AddLine(L.DE_UI_TT_MISSING:format(table.concat(names, L.DE_UI_SEP)), 1, 0.6, 0.2, true)
    if e.value then GameTooltip:AddLine(L.DE_UI_TT_PARTIAL, 0.55, 0.55, 0.55, true) end
  end
  if e.source == "craft" and type(e.costMissing) == "table" and #e.costMissing > 0 then
    local names = {}
    for i, id in ipairs(e.costMissing) do names[i] = UIA.Name(self, id) end
    GameTooltip:AddLine(L.DE_UI_TT_COST_MISSING:format(table.concat(names, L.DE_UI_SEP)), 1, 0.6, 0.2, true)
  end
  if kind == "b" then
    local id = self:SearchTarget(w, "b")
    if id then GameTooltip:AddLine(L.DE_UI_CLICK_MAT:format(UIA.Name(self, id)), 0.3, 1, 0.4) end
  else
    GameTooltip:AddLine(L.DE_UI_CLICK_ITEM, 0.3, 1, 0.4)
  end
  GameTooltip:Show()
end

function Tab:Subtitle() return L.DE_UI_SUBTITLE end
function Tab:ScanTip() return L.DE_UI_SCAN_TIP end
function Tab:ScanKind() return "de" end

UIA.Register("de", 5, "DE_UI_TAB", Tab)
