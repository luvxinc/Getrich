local addonName, WC = ...

-- Settings -> AddOns -> Getrich: every option, buttons that clear saved data, and an About section.
--
-- A canvas page (our own widgets in a scroll frame), registered with the game options through
--   Settings.RegisterCanvasLayoutCategory(frame, name) + Settings.RegisterAddOnCategory(category)
-- and opened with Settings.OpenToCategory(category:GetID())
-- (Blizzard_Settings_Shared/Blizzard_Settings.lua:134,144,162 and Blizzard_ImplementationReadme.lua, build 70450;
-- Blizzard_Settings_Shared loads in game and glue, it is not load-on-demand). The panel calls frame:OnRefresh() when
-- it shows the page and frame:OnDefault() for "Defaults". If the Settings API is missing, or during combat (opening
-- the panel is restricted), /gr settings shows the same page in a window of its own.
--
-- The widgets are built the first time the page is shown. Defaults belong to the modules that read the keys
-- (Store:Default); this page only reads and writes GetrichDB, fires SETTINGS_CHANGED(key) and redraws the window.
--
-- WC.Settings:Open(), :Build(), :Refresh(), :ResetSettings(), :Clear(what), .controls = { { kind, key, ... } }

local S = { controls = {} }
WC.Settings = S
local L = WC.L

WC.AddLocale({
  enUS = {
    SET_INTRO = "Money-making helper for WoW Forever. Changes apply right away.",
    SET_GENERAL = "General",
    SET_CHAT = "Print the best find in chat when a scan finishes",
    SET_CHAT_TIP = "One chat line with the best result of the scan.",
    SET_DOCK = "Put the window next to the Auction House",
    SET_DOCK_TIP = "When the Auction House opens, the Getrich window opens on its right side (unless you dragged it somewhere else).",
    SET_AHTINT = "Mark cheap listings in the Auction House",
    SET_AHTINT_TIP = "Rows in the Auction House lists that cost less than a vendor pays get a green tint and a \"vendor +X\" label.",
    SET_PROF = "Show profit in the profession window",
    SET_PROF_TIP = "A small profit label on each recipe in the profession window. Turning this off also turns off the skill-up marks.",
    SET_PROFLEVEL = "Mark the cheapest recipes to level a profession",
    SET_PROFLEVEL_TIP = "In the profession window, the 3 learned recipes that cost the least per skill point get a small mark.",
    SET_SCALE = "Window size",
    SET_SCALE_TIP = "Size of the Getrich window.",
    SET_FLIP_MIN = "Minimum profit",
    SET_FLIP_MIN_TIP = "Flips that make less than this in total are hidden.",
    SET_ANY = "any",
    SET_FLIP_GONE = "Show items that are no longer cheap",
    SET_FLIP_GONE_TIP = "The exact check sometimes finds an item already sold, or no longer below the vendor price. Those are hidden unless this is on.",
    SET_FLIP_CAND = "Items checked one by one",
    SET_FLIP_CAND_TIP = "After reading the whole Auction House, this many of the most promising items are searched one by one for exact prices. More items = a longer scan.",
    SET_CRAFT_ONLY = "Only profitable recipes",
    SET_CRAFT_ONLY_TIP = "Hides recipes that lose money however you sell the product.",
    SET_CRAFT_MISSING = "Hide recipes with missing prices",
    SET_CRAFT_MISSING_TIP = "Hides recipes with a material or product that has no price yet.",
    SET_CRAFT_UNLEARNED = "Also show recipes I haven't learned (trainer)",
    SET_CRAFT_UNLEARNED_TIP = "Adds the recipes a trainer can teach you, so you can see what is worth learning.",
    SET_OFFSET = "Leveling: value of what you make",
    SET_OFFSET_TIP = "When leveling a profession, what you get back for each crafted item is taken off its cost.\nBest of 3: the best of selling to a vendor, selling on the AH (after the 5% cut) and disenchanting.\nVendor + DE: only selling to a vendor or disenchanting.\nNone: count the full material cost.",
    SET_OFFSET_BEST = "Best of 3",
    SET_OFFSET_NPCDE = "Vendor + DE",
    SET_OFFSET_NONE = "None",
    SET_TARGET = "Leveling: target skill",
    SET_TARGET_TIP = "The skill the leveling plan goes up to. \"Current max\" = the highest skill your current training allows.",
    SET_TARGET_MAX = "Current max",
    SET_DE_SOURCE = "Show items from",
    SET_DE_SOURCE_TIP = "Which items the Disenchant tab lists.",
    SET_DE_ALL = "All", SET_DE_BAGS = "Bags", SET_DE_AH = "AH", SET_DE_CRAFT = "Crafted",
    SET_DE_SKILL = "Hide items I can't disenchant yet",
    SET_DE_SKILL_TIP = "Hides items that need a higher Enchanting skill.",
    SET_DE_LOSS = "Hide items where disenchanting doesn't pay",
    SET_DE_LOSS_TIP = "Hides items worth more as they are than their disenchant materials.",
    SET_DE_CASTS = "Use my own results after",
    SET_DE_CASTS_TIP = "Disenchant values start as an estimate (Classic odds). After this many of your own disenchants of the same kind of item, your real results are used instead.",
    SET_CASTS_FMT = "%d",
    SET_HIST_RANGE = "Chart range",
    SET_HIST_RANGE_TIP = "Time span the Prices tab shows first.",
    SET_RANGE_24H = "24 h", SET_RANGE_7D = "7 days", SET_RANGE_30D = "30 days", SET_RANGE_ALL = "All",
    SET_HIST_DAYS = "Merge hourly prices into one per day after",
    SET_HIST_DAYS_TIP = "Hourly price points older than this many days are merged into one point per day (low, average, high).",
    SET_PRUNE = "Delete listing details older than",
    SET_PRUNE_TIP = "Search results and whole-AH listing rows older than this many days are deleted. The price history is kept.",
    SET_DAYS_FMT = "%d days",
    SET_DATA = "Saved data",
    SET_DATA_SUMMARY = "Saved now: price history for %d items · %d search results · %d items from reading the whole AH · %d disenchants · %d vendor prices",
    SET_CLEAR_HISTORY = "Clear price history",
    SET_CLEAR_HISTORY_Q = "Delete the price history of every item?\nThis can't be undone.",
    SET_CLEAR_SCANS = "Clear scan results",
    SET_CLEAR_SCANS_Q = "Delete all Auction House scan results (prices from searches and from reading the whole AH)?\nThis can't be undone.",
    SET_CLEAR_DE = "Clear disenchant records",
    SET_CLEAR_DE_Q = "Delete the disenchant results you recorded?\nDisenchant values go back to estimates.",
    SET_CLEAR_VENDOR = "Clear merchant records",
    SET_CLEAR_VENDOR_Q = "Delete the vendor prices collected while you visited merchants?\nThe built-in vendor prices stay.",
    SET_RESET = "Reset settings",
    SET_RESET_Q = "Set every option back to its default?\nSaved prices and records are kept, and so are the two data-keeping options (merging hourly prices, deleting listing details).",
    SET_DONE_FMT = "%s: done.",
    SET_CONFIRM_AGAIN = "Click again to confirm",
    SET_SCAN_STOPPED = "Scan stopped (data cleared)",
    SET_ABOUT = "About",
    SET_VERSION_FMT = "Version %s · released %s",
    SET_AUTHOR = "Author",
    SET_CONTACT = "Contact",
    SET_WEBSITE = "GitHub",
    SET_COPY_HINT = "Click a box, then press Ctrl+C to copy.",
    SET_CREDITS = "Crate and writ data: Wowhead (WoW Forever beta). Slash commands: /gr, /getrich, /wc.",
  },
  zhCN = {
    SET_INTRO = "魔兽世界 Forever 挣钱助手。改动立即生效。",
    SET_GENERAL = "常规",
    SET_CHAT = "扫描完成时在聊天框显示最优结果",
    SET_CHAT_TIP = "在聊天框显示一行这次扫描的最优结果。",
    SET_DOCK = "窗口贴在拍卖行旁边",
    SET_DOCK_TIP = "打开拍卖行时，Getrich 窗口出现在拍卖行右边（你拖动过窗口的话就留在原处）。",
    SET_AHTINT = "在拍卖行标出便宜的挂单",
    SET_AHTINT_TIP = "拍卖行列表里比商店收购价还便宜的行，染成绿色并标上“卖店 +X”。",
    SET_PROF = "在专业窗口显示利润",
    SET_PROF_TIP = "在专业窗口的每个配方上显示一个小的利润标签。关掉后冲技能标记也不显示。",
    SET_PROFLEVEL = "标出冲技能最便宜的配方",
    SET_PROFLEVEL_TIP = "在专业窗口里，每涨 1 点技能花费最少的 3 个已学配方会有一个小标记。",
    SET_SCALE = "窗口大小",
    SET_SCALE_TIP = "Getrich 窗口的大小。",
    SET_FLIP_MIN = "最低利润",
    SET_FLIP_MIN_TIP = "总利润低于这个数的倒卖不显示。",
    SET_ANY = "不限",
    SET_FLIP_GONE = "显示已经不便宜的",
    SET_FLIP_GONE_TIP = "精确查询时，有些物品已经被买走，或者不再低于商店价。默认隐藏，勾选后显示。",
    SET_FLIP_CAND = "逐个精确查询的物品数",
    SET_FLIP_CAND_TIP = "读完整个拍卖行后，挑出最有希望的这么多种物品逐个查询准确价格。数量越多，扫描越久。",
    SET_CRAFT_ONLY = "只看赚钱的配方",
    SET_CRAFT_ONLY_TIP = "不管怎么卖成品都亏钱的配方不显示。",
    SET_CRAFT_MISSING = "隐藏缺价格的配方",
    SET_CRAFT_MISSING_TIP = "材料或成品还没有价格的配方不显示。",
    SET_CRAFT_UNLEARNED = "也显示还没学的配方（训练师）",
    SET_CRAFT_UNLEARNED_TIP = "加上训练师能教的配方，看看哪些值得去学。",
    SET_OFFSET = "冲技能：成品抵扣",
    SET_OFFSET_TIP = "冲技能时，每个做出来的成品能换回的钱从成本里扣掉。\n三选最高：卖商店、拍卖行卖（扣 5% 手续费）、分解，取最高。\n卖店 + 分解：只算卖商店或分解。\n不抵扣：按全部材料成本算。",
    SET_OFFSET_BEST = "三选最高",
    SET_OFFSET_NPCDE = "卖店 + 分解",
    SET_OFFSET_NONE = "不抵扣",
    SET_TARGET = "冲技能：目标技能",
    SET_TARGET_TIP = "冲技能路线算到的技能值。“当前上限”= 你现在的训练等级允许的最高技能。",
    SET_TARGET_MAX = "当前上限",
    SET_DE_SOURCE = "显示的物品来源",
    SET_DE_SOURCE_TIP = "分解页列出哪些物品。",
    SET_DE_ALL = "全部", SET_DE_BAGS = "背包", SET_DE_AH = "拍卖行", SET_DE_CRAFT = "自制",
    SET_DE_SKILL = "隐藏技能还不够分解的",
    SET_DE_SKILL_TIP = "需要更高附魔技能的物品不显示。",
    SET_DE_LOSS = "隐藏分解不划算的",
    SET_DE_LOSS_TIP = "原样卖比分解出来的材料更值钱的物品不显示。",
    SET_DE_CASTS = "用自己的分解结果，需要",
    SET_DE_CASTS_TIP = "分解价值一开始是估计值（经典旧世的几率）。同一类物品你自己分解够这么多次后，改用你实际分到的结果。",
    SET_CASTS_FMT = "%d 次",
    SET_HIST_RANGE = "走势图时间范围",
    SET_HIST_RANGE_TIP = "价格走势页默认显示的时间段。",
    SET_RANGE_24H = "24 小时", SET_RANGE_7D = "7 天", SET_RANGE_30D = "30 天", SET_RANGE_ALL = "全部",
    SET_HIST_DAYS = "每小时价格合并为每天一条，超过",
    SET_HIST_DAYS_TIP = "超过这么多天的每小时价格点合并成每天一个点（最低、平均、最高）。",
    SET_PRUNE = "删除超过这么多天的挂单明细",
    SET_PRUNE_TIP = "超过这么多天的搜索结果和全拍卖行挂单行会被删除。价格走势保留。",
    SET_DAYS_FMT = "%d 天",
    SET_DATA = "保存的数据",
    SET_DATA_SUMMARY = "当前保存：%d 种物品的价格走势 · %d 条搜索结果 · %d 种全拍卖行读取的物品 · %d 次分解 · %d 个商店价格",
    SET_CLEAR_HISTORY = "清除价格走势",
    SET_CLEAR_HISTORY_Q = "删除所有物品的价格走势记录？\n删除后无法恢复。",
    SET_CLEAR_SCANS = "清除扫描结果",
    SET_CLEAR_SCANS_Q = "删除所有拍卖行扫描结果（逐个搜索的价格和读取整个拍卖行的价格）？\n删除后无法恢复。",
    SET_CLEAR_DE = "清除分解记录",
    SET_CLEAR_DE_Q = "删除你记录的分解结果？\n分解价值会变回估计值。",
    SET_CLEAR_VENDOR = "清除商人记录",
    SET_CLEAR_VENDOR_Q = "删除你拜访商人时记下的商店价格？\n插件自带的商店价格保留。",
    SET_RESET = "恢复默认设置",
    SET_RESET_Q = "把所有选项恢复成默认值？\n保存的价格和记录不受影响，两个数据保留选项（每小时价格合并、删除挂单明细）也保持不变。",
    SET_DONE_FMT = "%s：完成。",
    SET_CONFIRM_AGAIN = "再点一次确认",
    SET_SCAN_STOPPED = "扫描已停止（数据已清除）",
    SET_ABOUT = "关于",
    SET_VERSION_FMT = "版本 %s · 发布于 %s",
    SET_AUTHOR = "作者",
    SET_CONTACT = "联系方式",
    SET_WEBSITE = "GitHub",
    SET_COPY_HINT = "点一下文本框，再按 Ctrl+C 复制。",
    SET_CREDITS = "箱子和 Writ 数据：Wowhead（魔兽世界 Forever 测试服）。命令：/gr、/getrich、/wc。",
  },
  zhTW = {
    SET_INTRO = "魔獸世界 Forever 賺錢助手。改動立即生效。",
    SET_GENERAL = "一般",
    SET_CHAT = "掃描完成時在聊天框顯示最佳結果",
    SET_CHAT_TIP = "在聊天框顯示一行這次掃描的最佳結果。",
    SET_DOCK = "視窗貼在拍賣場旁邊",
    SET_DOCK_TIP = "打開拍賣場時，Getrich 視窗出現在拍賣場右邊（你拖動過視窗的話就留在原處）。",
    SET_AHTINT = "在拍賣場標出便宜的掛單",
    SET_AHTINT_TIP = "拍賣場列表裡比商店收購價還便宜的行，染成綠色並標上「賣店 +X」。",
    SET_PROF = "在專業視窗顯示利潤",
    SET_PROF_TIP = "在專業視窗的每個配方上顯示一個小的利潤標籤。關掉後衝技能標記也不顯示。",
    SET_PROFLEVEL = "標出衝技能最便宜的配方",
    SET_PROFLEVEL_TIP = "在專業視窗裡，每漲 1 點技能花費最少的 3 個已學配方會有一個小標記。",
    SET_SCALE = "視窗大小",
    SET_SCALE_TIP = "Getrich 視窗的大小。",
    SET_FLIP_MIN = "最低利潤",
    SET_FLIP_MIN_TIP = "總利潤低於這個數的倒賣不顯示。",
    SET_ANY = "不限",
    SET_FLIP_GONE = "顯示已經不便宜的",
    SET_FLIP_GONE_TIP = "精確查詢時，有些物品已經被買走，或者不再低於商店價。預設隱藏，勾選後顯示。",
    SET_FLIP_CAND = "逐個精確查詢的物品數",
    SET_FLIP_CAND_TIP = "讀完整個拍賣場後，挑出最有希望的這麼多種物品逐個查詢準確價格。數量越多，掃描越久。",
    SET_CRAFT_ONLY = "只看賺錢的配方",
    SET_CRAFT_ONLY_TIP = "不管怎麼賣成品都虧錢的配方不顯示。",
    SET_CRAFT_MISSING = "隱藏缺價格的配方",
    SET_CRAFT_MISSING_TIP = "材料或成品還沒有價格的配方不顯示。",
    SET_CRAFT_UNLEARNED = "也顯示還沒學的配方（訓練師）",
    SET_CRAFT_UNLEARNED_TIP = "加上訓練師能教的配方，看看哪些值得去學。",
    SET_OFFSET = "衝技能：成品抵扣",
    SET_OFFSET_TIP = "衝技能時，每個做出來的成品能換回的錢從成本裡扣掉。\n三選最高：賣商店、拍賣場賣（扣 5% 手續費）、分解，取最高。\n賣店 + 分解：只算賣商店或分解。\n不抵扣：按全部材料成本算。",
    SET_OFFSET_BEST = "三選最高",
    SET_OFFSET_NPCDE = "賣店 + 分解",
    SET_OFFSET_NONE = "不抵扣",
    SET_TARGET = "衝技能：目標技能",
    SET_TARGET_TIP = "衝技能路線算到的技能值。「目前上限」= 你現在的訓練等級允許的最高技能。",
    SET_TARGET_MAX = "目前上限",
    SET_DE_SOURCE = "顯示的物品來源",
    SET_DE_SOURCE_TIP = "分解頁列出哪些物品。",
    SET_DE_ALL = "全部", SET_DE_BAGS = "背包", SET_DE_AH = "拍賣場", SET_DE_CRAFT = "自製",
    SET_DE_SKILL = "隱藏技能還不夠分解的",
    SET_DE_SKILL_TIP = "需要更高附魔技能的物品不顯示。",
    SET_DE_LOSS = "隱藏分解不划算的",
    SET_DE_LOSS_TIP = "原樣賣比分解出來的材料更值錢的物品不顯示。",
    SET_DE_CASTS = "用自己的分解結果，需要",
    SET_DE_CASTS_TIP = "分解價值一開始是估計值（經典舊世的機率）。同一類物品你自己分解夠這麼多次後，改用你實際分到的結果。",
    SET_CASTS_FMT = "%d 次",
    SET_HIST_RANGE = "走勢圖時間範圍",
    SET_HIST_RANGE_TIP = "價格走勢頁預設顯示的時間段。",
    SET_RANGE_24H = "24 小時", SET_RANGE_7D = "7 天", SET_RANGE_30D = "30 天", SET_RANGE_ALL = "全部",
    SET_HIST_DAYS = "每小時價格合併為每天一筆，超過",
    SET_HIST_DAYS_TIP = "超過這麼多天的每小時價格點合併成每天一個點（最低、平均、最高）。",
    SET_PRUNE = "刪除超過這麼多天的掛單明細",
    SET_PRUNE_TIP = "超過這麼多天的搜尋結果和全拍賣場掛單行會被刪除。價格走勢保留。",
    SET_DAYS_FMT = "%d 天",
    SET_DATA = "儲存的資料",
    SET_DATA_SUMMARY = "目前儲存：%d 種物品的價格走勢 · %d 筆搜尋結果 · %d 種全拍賣場讀取的物品 · %d 次分解 · %d 個商店價格",
    SET_CLEAR_HISTORY = "清除價格走勢",
    SET_CLEAR_HISTORY_Q = "刪除所有物品的價格走勢紀錄？\n刪除後無法復原。",
    SET_CLEAR_SCANS = "清除掃描結果",
    SET_CLEAR_SCANS_Q = "刪除所有拍賣場掃描結果（逐個搜尋的價格和讀取整個拍賣場的價格）？\n刪除後無法復原。",
    SET_CLEAR_DE = "清除分解紀錄",
    SET_CLEAR_DE_Q = "刪除你記錄的分解結果？\n分解價值會變回估計值。",
    SET_CLEAR_VENDOR = "清除商人紀錄",
    SET_CLEAR_VENDOR_Q = "刪除你拜訪商人時記下的商店價格？\n插件內建的商店價格保留。",
    SET_RESET = "恢復預設設定",
    SET_RESET_Q = "把所有選項恢復成預設值？\n儲存的價格和紀錄不受影響，兩個資料保留選項（每小時價格合併、刪除掛單明細）也保持不變。",
    SET_DONE_FMT = "%s：完成。",
    SET_CONFIRM_AGAIN = "再點一次確認",
    SET_SCAN_STOPPED = "掃描已停止（資料已清除）",
    SET_ABOUT = "關於",
    SET_VERSION_FMT = "版本 %s · 發佈於 %s",
    SET_AUTHOR = "作者",
    SET_CONTACT = "聯絡方式",
    SET_WEBSITE = "GitHub",
    SET_COPY_HINT = "點一下文字框，再按 Ctrl+C 複製。",
    SET_CREDITS = "箱子和 Writ 資料：Wowhead（魔獸世界 Forever 測試伺服器）。指令：/gr、/getrich、/wc。",
  },
})

local NAME = "Getrich"
local AUTHOR, EMAIL, WEBSITE = "Aaron Tong", "Luvx.inc@gmail.com", "https://github.com/luvxinc/Getrich"
local PAGE_W = 600          -- content width (the options canvas is about 665 px wide)
local LABEL_W = 240         -- label column of choice rows
local CHOICE_X = 28 + LABEL_W
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function UI() return WC.UI end
local function Font(parent, template, justify, width) return WC.UI.Font(parent, template, justify, width) end
local function Backdrop(frame, bg, border) return WC.UI.Backdrop(frame, bg, border) end

local function FirstLine(s) return (tostring(s or ""):gsub("\n.*$", "")) end

local function Default(key)
  local D = WC.Store and WC.Store.DEFAULTS
  if D then return D[key] end
end

-- current value of a setting (the registered default while the key is unset)
local function Value(key)
  local db = GetrichDB
  local v = db and db[key]
  if v == nil then v = Default(key) end
  return v
end

local function Count(t)
  local n = 0
  if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
  return n
end

local function Wipe(t)
  if type(t) ~= "table" then return end
  for k in pairs(t) do t[k] = nil end
end

-- a setting changed: tell every module (this page redraws itself from SETTINGS_CHANGED) and redraw the window
local function Changed(key)
  WC:Fire("SETTINGS_CHANGED", key)
  local ui = UI()
  if ui and ui.Refresh then ui:Refresh() end
end

local function Set(key, value)
  if not GetrichDB then return end
  GetrichDB[key] = value
  Changed(key)
end

local function Tip(widget, title, text)
  widget:SetScript("OnEnter", function(b)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    if text and text ~= "" then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", GameTooltip_Hide)
end

-- ---------------------------------------------------------------------------
-- the page (built on first show)

local content, y

local function Header(text)
  y = y - 16
  local fs = Font(content, "GameFontNormalLarge", "LEFT")
  fs:SetPoint("TOPLEFT", 16, y)
  fs:SetText(text)
  local rule = content:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(0.42, 0.33, 0.14, 0.6)
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", 16, y - 22)
  rule:SetPoint("TOPRIGHT", -8, y - 22)
  y = y - 32
  return fs
end

local function Note(text, template)
  local fs = Font(content, template or "GameFontHighlightSmall", "LEFT", PAGE_W - 40)
  fs:SetPoint("TOPLEFT", 24, y)
  fs:SetWordWrap(true)
  fs:SetText(text)
  local h = fs:GetStringHeight()
  if type(h) ~= "number" or h < 12 then h = 12 end
  y = y - h - 8
  return fs
end

local function CheckRow(key, label, tip)
  local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", 22, y)
  local fs = Font(cb, "GameFontHighlight", "LEFT")
  fs:SetPoint("LEFT", cb, "RIGHT", 4, 1)
  fs:SetText(label)
  local lw = tonumber(fs:GetStringWidth()) or 200
  cb:SetHitRectInsets(0, -(lw + 8), 0, 0)
  cb:SetScript("OnClick", function(b) Set(key, b:GetChecked() and true or false) end)
  Tip(cb, label, tip)
  S.controls[#S.controls + 1] = { kind = "check", key = key, widget = cb, label = label }
  y = y - 28
  return cb
end

local function StyleChoice(b, on)
  if on then
    b:SetBackdropColor(0.95, 0.72, 0.15, 0.25)
    b:SetBackdropBorderColor(0.95, 0.75, 0.2, 1)
    b.text:SetTextColor(1, 0.82, 0)
  else
    b:SetBackdropColor(1, 1, 1, 0.04)
    b:SetBackdropBorderColor(0.35, 0.33, 0.3, 1)
    b.text:SetTextColor(0.75, 0.75, 0.75)
  end
end

-- label + one small button per option (the chosen one is highlighted); options = { { value, text }, ... }
local function ChoiceRow(key, label, tip, options)
  local fs = Font(content, "GameFontHighlight", "LEFT", LABEL_W)
  fs:SetPoint("TOPLEFT", 28, y - 4)
  fs:SetText(label)
  local hot = CreateFrame("Frame", nil, content)
  hot:SetPoint("TOPLEFT", 24, y)
  hot:SetSize(LABEL_W, 22)
  hot:EnableMouse(true)
  Tip(hot, label, tip)
  local x, buttons = CHOICE_X, {}
  for i, opt in ipairs(options) do
    local b = CreateFrame("Button", nil, content, "BackdropTemplate")
    Backdrop(b, { 1, 1, 1, 0.04 }, { 0.35, 0.33, 0.3, 1 })
    b:SetHeight(22)
    b.text = Font(b, "GameFontHighlightSmall", "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(opt[2])
    local w = math.max(44, (tonumber(b.text:GetStringWidth()) or 30) + 18)
    if x + w > PAGE_W and x > CHOICE_X then
      x = CHOICE_X
      y = y - 26
    end
    b:SetWidth(w)
    b:SetPoint("TOPLEFT", x, y)
    x = x + w + 4
    b.value = opt[1]
    b:SetScript("OnClick", function() Set(key, opt[1]) end)
    Tip(b, label, tip)
    buttons[i] = b
  end
  S.controls[#S.controls + 1] = { kind = "choice", key = key, buttons = buttons, label = label }
  y = y - 30
  return buttons
end

-- "Are you sure?" dialog; returns true if it was shown
local function Confirm(text, fn)
  if not (StaticPopupDialogs and StaticPopup_Show) then return false end
  if not StaticPopupDialogs.GETRICH_CONFIRM then
    StaticPopupDialogs.GETRICH_CONFIRM = {
      text = "%s",
      button1 = YES or OKAY or "Yes",
      button2 = NO or CANCEL or "No",
      OnAccept = function(_, data) if type(data) == "function" then data() end end,
      OnCancel = function() end,
      timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
    }
  end
  local ok, dialog = pcall(StaticPopup_Show, "GETRICH_CONFIRM", text, nil, fn)
  return ok and dialog ~= nil
end

local ACTION_W = 250
local function ActionButton(text, question, what, x)
  local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  b:SetText(text)
  local w = ACTION_W
  b:SetSize(w, 24)
  b:SetPoint("TOPLEFT", x, y)
  local function Run()
    b.armed = nil
    b:SetText(text)
    S:Clear(what)
    WC:Print(L.SET_DONE_FMT:format(text))
  end
  b:SetScript("OnClick", function()
    if Confirm(question, Run) then return end
    -- no dialog available: a second click within 5 seconds confirms
    if b.armed and GetTime() - b.armed < 5 then
      Run()
    else
      b.armed = GetTime()
      b:SetText(L.SET_CONFIRM_AGAIN)
      C_Timer.After(5, function()
        if b.armed then b.armed = nil; b:SetText(text) end
      end)
    end
  end)
  Tip(b, text, question)
  S.controls[#S.controls + 1] = { kind = "action", what = what, widget = b, label = text }
  return b, w
end

-- read-only text box: click it and press Ctrl+C to copy
local function CopyRow(label, value)
  local fs = Font(content, "GameFontNormal", "LEFT", 110)
  fs:SetPoint("TOPLEFT", 28, y - 5)
  fs:SetText(label)
  local eb = CreateFrame("EditBox", nil, content, "BackdropTemplate")
  eb:SetSize(340, 22)
  eb:SetPoint("TOPLEFT", 28 + 116, y)
  eb:SetAutoFocus(false)
  eb:SetFontObject(_G.GameFontHighlight or "GameFontHighlight")
  eb:SetTextInsets(6, 6, 0, 0)
  Backdrop(eb, { 0, 0, 0, 0.45 }, { 0.35, 0.33, 0.3, 1 })
  eb.value = value
  eb:SetText(value)
  eb:SetCursorPosition(0)
  eb:SetScript("OnTextChanged", function(s, userInput)
    if userInput and s:GetText() ~= s.value then s:SetText(s.value); s:HighlightText() end
  end)
  eb:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
  eb:SetScript("OnEditFocusLost", function(s) s:HighlightText(0, 0) end)
  eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
  S.controls[#S.controls + 1] = { kind = "copy", widget = eb, value = value, label = label }
  y = y - 28
  return eb
end

local function DaysOptions(list)
  local out = {}
  for i, d in ipairs(list) do out[i] = { d, L.SET_DAYS_FMT:format(d) } end
  return out
end

function S:Build()
  if self.built then return end
  local f = self:CreateFrame()
  self.built = true
  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -14, 4)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(PAGE_W, 100)
  scroll:SetScrollChild(content)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, delta) S:ScrollBy(-delta * 60) end)
  scroll:SetScript("OnSizeChanged", function(_, w)
    if type(w) == "number" and w > PAGE_W then content:SetWidth(w) end
    S:UpdateThumb()
  end)
  local track = f:CreateTexture(nil, "ARTWORK")
  track:SetColorTexture(1, 1, 1, 0.05)
  track:SetPoint("TOPRIGHT", -4, -4)
  track:SetPoint("BOTTOMRIGHT", -4, 4)
  track:SetWidth(5)
  local thumb = f:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(0.95, 0.75, 0.2, 0.6)
  thumb:SetWidth(5)
  thumb:Hide()
  self.scroll, self.content, self.thumb = scroll, content, thumb

  local Money = WC.Money
  y = -8
  local title = Font(content, "GameFontNormalHuge", "LEFT")
  title:SetPoint("TOPLEFT", 16, y)
  title:SetText(NAME)
  self.versionLine = Font(content, "GameFontDisableSmall", "LEFT")
  self.versionLine:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 2)
  y = y - 30
  Note(L.SET_INTRO)

  Header(L.SET_GENERAL)
  CheckRow("autoScan", L.AUTO_SCAN, L.AUTO_SCAN_TIP)
  CheckRow("soundOnDone", L.UI_SOUND, L.UI_SOUND_TIP)
  CheckRow("chatOnDone", L.SET_CHAT, L.SET_CHAT_TIP)
  CheckRow("dockToAH", L.SET_DOCK, L.SET_DOCK_TIP)
  CheckRow("ahTint", L.SET_AHTINT, L.SET_AHTINT_TIP)
  CheckRow("profOverlay", L.SET_PROF, L.SET_PROF_TIP)
  CheckRow("profLevelMark", L.SET_PROFLEVEL, L.SET_PROFLEVEL_TIP)
  ChoiceRow("uiScale", L.SET_SCALE, L.SET_SCALE_TIP,
    { { 0.8, "80%" }, { 0.9, "90%" }, { 1.0, "100%" }, { 1.1, "110%" }, { 1.2, "120%" }, { 1.3, "130%" } })

  Header(L.UI_TAB_CRATES)
  CheckRow("onlyMine", L.ONLY_MINE, L.ONLY_MINE_TIP)
  CheckRow("hideNoCrate", L.HIDE_NO_CRATE, L.HIDE_NO_CRATE_TIP)
  CheckRow("hideNoMats", L.HIDE_NO_MATS, L.HIDE_NO_MATS_TIP)
  ChoiceRow("perfRank", L.PERF_LABEL, FirstLine(L.PERF_TIP), { { 0, "0" }, { 1, "1" }, { 2, "2" }, { 3, "3" } })

  Header(L.UI_TAB_WRITS)
  CheckRow("hideNoWrit", L.HIDE_NO_WRIT, L.HIDE_NO_WRIT_TIP)
  CheckRow("hideNoItem", L.HIDE_NO_ITEM, L.HIDE_NO_ITEM_TIP)
  CheckRow("hideDone", L.HIDE_DONE, L.HIDE_DONE_TIP)
  ChoiceRow("diplomatRank", L.DIPLO_LABEL, FirstLine(L.DIPLO_TIP),
    { { 0, "0" }, { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" }, { 5, "5" } })

  Header(L.UI_TAB_FLIPS)
  ChoiceRow("flipMinProfit", L.SET_FLIP_MIN, L.SET_FLIP_MIN_TIP,
    { { 0, L.SET_ANY }, { 1000, Money(1000) }, { 10000, Money(10000) }, { 50000, Money(50000) } })
  CheckRow("flipShowGone", L.SET_FLIP_GONE, L.SET_FLIP_GONE_TIP)
  ChoiceRow("flipCandidates", L.SET_FLIP_CAND, L.SET_FLIP_CAND_TIP, { { 40, "40" }, { 80, "80" }, { 150, "150" } })

  Header(L.UI_TAB_CRAFT)
  CheckRow("craftOnlyProfit", L.SET_CRAFT_ONLY, L.SET_CRAFT_ONLY_TIP)
  CheckRow("craftHideMissing", L.SET_CRAFT_MISSING, L.SET_CRAFT_MISSING_TIP)
  CheckRow("craftShowUnlearned", L.SET_CRAFT_UNLEARNED, L.SET_CRAFT_UNLEARNED_TIP)
  ChoiceRow("levelOffset", L.SET_OFFSET, L.SET_OFFSET_TIP,
    { { "best3", L.SET_OFFSET_BEST }, { "npcde", L.SET_OFFSET_NPCDE }, { "none", L.SET_OFFSET_NONE } })
  ChoiceRow("levelTarget", L.SET_TARGET, L.SET_TARGET_TIP, { { "max", L.SET_TARGET_MAX }, { 225, "225" }, { 300, "300" } })

  Header(L.UI_TAB_DE)
  ChoiceRow("deSource", L.SET_DE_SOURCE, L.SET_DE_SOURCE_TIP,
    { { "all", L.SET_DE_ALL }, { "bag", L.SET_DE_BAGS }, { "ah", L.SET_DE_AH }, { "craft", L.SET_DE_CRAFT } })
  CheckRow("deHideSkill", L.SET_DE_SKILL, L.SET_DE_SKILL_TIP)
  CheckRow("deHideLoss", L.SET_DE_LOSS, L.SET_DE_LOSS_TIP)
  local casts = {}
  for i, n in ipairs({ 10, 20, 30, 50 }) do casts[i] = { n, L.SET_CASTS_FMT:format(n) } end
  ChoiceRow("deMeasuredCasts", L.SET_DE_CASTS, L.SET_DE_CASTS_TIP, casts)

  Header(L.UI_TAB_HISTORY)
  ChoiceRow("historyRange", L.SET_HIST_RANGE, L.SET_HIST_RANGE_TIP,
    { { "24h", L.SET_RANGE_24H }, { "7d", L.SET_RANGE_7D }, { "30d", L.SET_RANGE_30D }, { "all", L.SET_RANGE_ALL } })
  ChoiceRow("historyDays", L.SET_HIST_DAYS, L.SET_HIST_DAYS_TIP, DaysOptions({ 7, 14, 30, 60, 90 }))
  ChoiceRow("pruneDays", L.SET_PRUNE, L.SET_PRUNE_TIP, DaysOptions({ 3, 7, 14, 30 }))

  Header(L.SET_DATA)
  self.summary = Note(L.SET_DATA_SUMMARY:format(0, 0, 0, 0, 0))
  self.summary:SetHeight(28)
  y = y - 12
  -- two per row; "reset settings" on a row of its own
  for i, a in ipairs({
    { L.SET_CLEAR_HISTORY, L.SET_CLEAR_HISTORY_Q, "history" },
    { L.SET_CLEAR_SCANS, L.SET_CLEAR_SCANS_Q, "scans" },
    { L.SET_CLEAR_DE, L.SET_CLEAR_DE_Q, "de" },
    { L.SET_CLEAR_VENDOR, L.SET_CLEAR_VENDOR_Q, "vendor" },
    { L.SET_RESET, L.SET_RESET_Q, "settings" },
  }) do
    ActionButton(a[1], a[2], a[3], (i % 2 == 0) and (24 + ACTION_W + 12) or 24)
    if i % 2 == 0 or i == 5 then y = y - 30 end
  end

  Header(L.SET_ABOUT)
  local name = Font(content, "GameFontNormalLarge", "LEFT")
  name:SetPoint("TOPLEFT", 28, y)
  name:SetText(NAME)
  self.aboutVersion = Font(content, "GameFontHighlight", "LEFT")
  self.aboutVersion:SetPoint("LEFT", name, "RIGHT", 10, 0)
  y = y - 28
  local meta = WC.UI and WC.UI.Meta
  local author = (meta and meta("Author")) or AUTHOR
  local fs = Font(content, "GameFontNormal", "LEFT", 110)
  fs:SetPoint("TOPLEFT", 28, y)
  fs:SetText(L.SET_AUTHOR)
  self.authorText = Font(content, "GameFontHighlight", "LEFT")
  self.authorText:SetPoint("TOPLEFT", 28 + 116 + 6, y)
  self.authorText:SetText(author)
  y = y - 24
  self.emailBox = CopyRow(L.SET_CONTACT, (meta and meta("X-Email")) or EMAIL)
  self.webBox = CopyRow(L.SET_WEBSITE, (meta and meta("X-Website")) or WEBSITE)
  Note(L.SET_COPY_HINT, "GameFontDisableSmall")
  Note(L.SET_CREDITS, "GameFontDisableSmall")

  self.contentH = -y + 16
  content:SetHeight(self.contentH)
end

function S:UpdateThumb()
  if not self.scroll then return end
  local view = tonumber(self.scroll:GetHeight()) or 0
  local total = self.contentH or 0
  if view <= 0 or total <= view + 1 then self.thumb:Hide(); return end
  local maxOff = total - view
  local off = tonumber(self.scroll:GetVerticalScroll()) or 0
  local thumbH = math.max(24, view * view / total)
  self.thumb:ClearAllPoints()
  self.thumb:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -4, -4 - (off / maxOff) * (view - thumbH))
  self.thumb:SetHeight(thumbH)
  self.thumb:Show()
end

function S:ScrollBy(dy)
  if not self.scroll then return end
  local view = tonumber(self.scroll:GetHeight()) or 0
  local maxOff = math.max(0, (self.contentH or 0) - view)
  local v = (tonumber(self.scroll:GetVerticalScroll()) or 0) + dy
  if v > maxOff then v = maxOff end
  if v < 0 then v = 0 end
  self.scroll:SetVerticalScroll(v)
  self:UpdateThumb()
end

-- show every control's current value
function S:Refresh()
  if not self.built then return end
  for _, c in ipairs(self.controls) do
    if c.kind == "check" then
      c.widget:SetChecked(Value(c.key) and true or false)
    elseif c.kind == "choice" then
      local v = Value(c.key)
      for _, b in ipairs(c.buttons) do StyleChoice(b, b.value == v) end
    end
  end
  local db = GetrichDB or {}
  local browse = type(db.browse) == "table" and db.browse.items
  local casts = 0
  if type(db.deSamples) == "table" then
    for _, s in pairs(db.deSamples) do casts = casts + (type(s) == "table" and tonumber(s.casts) or 0) end
  end
  self.summary:SetText(L.SET_DATA_SUMMARY:format(Count(db.history), Count(db.results), Count(browse), casts, Count(db.vendorObs)))
  local v = WC.VERSION or (WC.UI and WC.UI.Meta and WC.UI.Meta("Version")) or "?"
  local released = WC.RELEASED or (WC.UI and WC.UI.Meta and WC.UI.Meta("X-Released")) or "?"
  self.aboutVersion:SetText(L.SET_VERSION_FMT:format(v, released))
  self.versionLine:SetText("v" .. v)
  self:UpdateThumb()
end

-- ---------------------------------------------------------------------------
-- data buttons

-- what: "history" | "scans" | "de" | "vendor" | "settings"
function S:Clear(what)
  local db = GetrichDB
  if not db then return end
  if what == "history" then
    Wipe(db.history)
    WC:Fire("PRICES_UPDATED", "clear")
  elseif what == "scans" then
    if WC.Scanner and WC.Scanner.active then WC.Scanner:Stop(L.SET_SCAN_STOPPED) end
    Wipe(db.results)                       -- emptied in place: the Scanner keeps a reference to it
    if type(db.browse) == "table" then
      Wipe(db.browse.items)
      db.browse.full, db.browse.gear = nil, nil
    end
    Wipe(db.scannedAt)
    WC:Fire("PRICES_UPDATED", "clear")
  elseif what == "de" then
    Wipe(db.deSamples)                     -- emptied in place: Disenchant.lua keeps a reference to it
    WC:Fire("DE_UPDATED")
  elseif what == "vendor" then
    Wipe(db.vendorObs)
    WC:Fire("VENDOR_UPDATED")
  elseif what == "settings" then
    self:ResetSettings()
    return
  end
  local ui = UI()
  if ui and ui.frame then
    if not (WC.Scanner and WC.Scanner.active) then ui:SetIdleText() end
    ui:Refresh()
  end
  self:Refresh()
end

-- the data-keeping options are not reset: going back to their defaults would make Store compress / delete data
local KEEP_ON_RESET = { historyDays = true, pruneDays = true }

-- every registered setting back to its default (saved prices and records stay, and so do historyDays / pruneDays)
function S:ResetSettings()
  local db = GetrichDB
  local D = WC.Store and WC.Store.DEFAULTS
  if not (db and D) then return end
  local changed = {}
  for k, v in pairs(D) do
    if type(v) ~= "table" and not KEEP_ON_RESET[k] and db[k] ~= v then
      db[k] = v
      changed[#changed + 1] = k
    end
  end
  table.sort(changed)
  self.batch = true
  for _, k in ipairs(changed) do WC:Fire("SETTINGS_CHANGED", k) end
  self.batch = nil
  local ui = UI()
  if ui and ui.frame then ui:SelectTab(WC:Tab()) end
  self:Refresh()
  return changed
end

-- ---------------------------------------------------------------------------
-- registration and opening

function S:CreateFrame()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "GetrichSettingsPage")
  f:Hide()
  f.name = NAME
  -- called by the options panel (Blizzard_Settings_Shared/Blizzard_SettingsPanel.lua)
  f.OnRefresh = function() S:HideWindow(); S:Build(); S:Refresh() end
  f.OnDefault = function() S:ResetSettings() end
  f.OnCommit = function() end
  f:SetScript("OnShow", function() S:Build(); S:Refresh() end)
  self.frame = f
  return f
end

function S:Register()
  if self.category then return true end
  local API = _G.Settings
  if not (API and API.RegisterCanvasLayoutCategory and API.RegisterAddOnCategory) then return false end
  local f = self:CreateFrame()
  local ok, category = pcall(API.RegisterCanvasLayoutCategory, f, NAME)
  if not (ok and category) then return false end
  local ok2 = pcall(API.RegisterAddOnCategory, category)
  if not ok2 then return false end
  self.category = category
  return true
end

-- our own window for the page (no Settings API, or in combat)
function S:ShowWindow()
  local f = self:CreateFrame()
  local w = self.window
  if not w then
    w = CreateFrame("Frame", "GetrichSettingsWindow", UIParent, "BackdropTemplate")
    w:SetSize(680, 620)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    Backdrop(w, { 0.055, 0.06, 0.075, 0.97 }, { 0.42, 0.33, 0.14, 1 })
    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    tinsert(UISpecialFrames, "GetrichSettingsWindow")   -- ESC closes it
    w:Hide()
    self.window = w
  end
  f:SetParent(w)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", 8, -24)
  f:SetPoint("BOTTOMRIGHT", -8, 8)
  w:Show()
  f:Show()
  self:Build()
  self:Refresh()
end

function S:HideWindow()
  if self.window and self.window:IsShown() then self.window:Hide() end
end

-- /gr settings, the gear button in the window's title bar
function S:Open()
  local inCombat = InCombatLockdown and InCombatLockdown()
  if not inCombat and (self.category or self:Register()) then
    local API = _G.Settings
    local ok = pcall(API.OpenToCategory, self.category:GetID())
    if ok then return true end
  end
  self:ShowWindow()
  return false
end

-- register with the game options as soon as possible (retry at login if the API wasn't ready)
if not S:Register() then
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_LOGIN")
  ev:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    S:Register()
  end)
end
-- keep the page in step when a setting changes elsewhere (main window switches, other modules)
WC:On("SETTINGS_CHANGED", function()
  if S.built and not S.batch and S.frame and S.frame:IsShown() then S:Refresh() end
end)
