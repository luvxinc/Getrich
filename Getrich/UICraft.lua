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
    CRAFT_NO_RECIPES = "Open each profession window once so Getrich can read your recipes.",
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
    -- round 2: modes, unlearned recipes, skill-up planner
    CRAFT_MODE_PROFIT = "Profit",
    CRAFT_MODE_PROFIT_TIP = "What each recipe earns when you sell the product.",
    CRAFT_MODE_LEVEL = "Skill-up",
    CRAFT_MODE_LEVEL_TIP = "The cheapest way to raise a profession: learned recipes and recipes a trainer can teach. The product's value (best of vendor, AH, disenchant) counts against the cost.",
    CRAFT_SHOW_UNLEARNED = "Show unlearned",
    CRAFT_SHOW_UNLEARNED_TIP = "Also list recipes a trainer can teach you that you haven't learned yet.",
    CRAFT_UNLEARNED = "not learned · trainer %d",
    CRAFT_UNLEARNED_ITEM = "not learned · recipe item",
    CRAFT_TT_UNLEARNED = "Not learned yet: a trainer teaches it at skill %d.",
    CRAFT_LV_SUBTITLE = "Cheapest way to raise a profession · learned + trainer recipes · the product's value counts against the cost",
    CRAFT_LV_VIEW_LIST = "Now",
    CRAFT_LV_VIEW_PLAN = "Route",
    CRAFT_LV_VIEW_TIP = "Now: recipes that give points at your current skill. Route: step by step to the target.",
    CRAFT_LV_HEADER = "%s %d/%d  ->  target %d",
    CRAFT_LV_TARGET = "Target",
    CRAFT_LV_TARGET_TIP = "Skill to plan for: the profession's current maximum, 225 or 300.",
    CRAFT_LV_TARGET_MAX = "Max (%d)",
    CRAFT_LV_HEAD_RECIPE = "Recipe",
    CRAFT_LV_HEAD_CHANCE = "Chance",
    CRAFT_LV_HEAD_NET = "Cost per craft",
    CRAFT_LV_HEAD_POINT = "Per skill point",
    CRAFT_LV_HEAD_SKILL = "Skill",
    CRAFT_LV_HEAD_STEP = "Cost",
    CRAFT_LV_HEAD_TOTAL = "Total so far",
    CRAFT_LV_COLOR_orange = "orange",
    CRAFT_LV_COLOR_yellow = "yellow",
    CRAFT_LV_COLOR_green = "green",
    CRAFT_LV_COLOR_grey = "grey",
    CRAFT_LV_GREY_AT = "grey at %d",
    CRAFT_LV_MATS = "mats %s",
    CRAFT_LV_PER_CRAFT = "+%d per craft",
    CRAFT_LV_POINTS = "+%d points",
    CRAFT_LV_LEARN = "learn at trainer",
    CRAFT_LV_PLAN_LABEL = "Skill-up route · %d -> %d",
    CRAFT_LV_PLAN_DETAIL = "%d steps · learn %d recipes at a trainer",
    CRAFT_LV_TOTAL = "Total cost to %d",
    CRAFT_LV_SHOP_HINT = "Hover for the shopping list",
    CRAFT_LV_MISSING = "%d recipes skipped: no price yet (scan first)",
    CRAFT_LV_SHORT = "Not enough on the AH for the whole route",
    CRAFT_LV_STUCK = "Stops at %d: no recipe gives points there",
    CRAFT_LV_EST = "estimate",
    CRAFT_UNLEARNED_GUESS = "not learned · trainer ~%d",
    CRAFT_LV_GUESS = "Learn skill estimated — visit the trainer once to make it exact.",
    CRAFT_LV_TT_TRAIN = "Training cost",
    CRAFT_LV_TT_TRAIN_UNKNOWN = "unknown (visit the trainer once)",
    CRAFT_LV_LEARN_UNKNOWN = "%d training costs unknown",
    CRAFT_LV_PLAN_DETAIL_COST = "%d steps · learn %d recipes at a trainer (%s)",
    CRAFT_LV_TT_VALUE = "Products sold",
    CRAFT_LV_NO_PROF = "No crafting profession found. Open each profession window once so Getrich can read it.",
    CRAFT_LV_AT_TARGET = "%s is at %d already. Pick a higher target, or train the next rank.",
    CRAFT_LV_NONE = "No recipe gives skill points at %d (learned or from a trainer).",
    CRAFT_LV_NO_ENGINE = "The skill-up planner isn't available.",
    CRAFT_LV_TT_CHANCE = "Skill-up chance",
    CRAFT_LV_TT_COLORS = "orange %d · yellow %d · green %d · grey %d",
    CRAFT_LV_TT_OFFSET = "Product value (%s)",
    CRAFT_LV_TT_NO_OFFSET = "Product value not counted",
    CRAFT_LV_TT_NET = "Cost per craft",
    CRAFT_LV_TT_POINT = "Cost per skill point",
    CRAFT_LV_TT_EARNS = "earns %s",
    CRAFT_LV_TT_STEP = "Materials for this step (%d crafts)",
    CRAFT_LV_TT_EXPECTED = "Expected crafts",
    CRAFT_LV_TT_SHOP = "Shopping list to %d",
    CRAFT_LV_TT_LEARN = "Learn at a trainer:",
    CRAFT_LV_TT_LEARN_AT = "%s (at %d)",
    CRAFT_LV_TT_TOTAL = "Total (after selling the products)",
    CRAFT_LV_PRINT = "Scan finished. %s %d -> %d: about %s.",
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
    CRAFT_NO_RECIPES = "请把每个专业窗口都打开一次，Getrich 才能读到你的配方。",
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
    CRAFT_MODE_PROFIT = "赚钱",
    CRAFT_MODE_PROFIT_TIP = "每个配方做出来卖掉能赚多少。",
    CRAFT_MODE_LEVEL = "冲技能",
    CRAFT_MODE_LEVEL_TIP = "最便宜的冲技能方法：已学的配方和训练师能教的配方都算。成品的价值（卖商人、拍卖行、分解里最高的）抵扣成本。",
    CRAFT_SHOW_UNLEARNED = "显示未学的",
    CRAFT_SHOW_UNLEARNED_TIP = "同时列出训练师能教、但你还没学的配方。",
    CRAFT_UNLEARNED = "未学 · 训练师 %d",
    CRAFT_UNLEARNED_ITEM = "未学 · 配方书",
    CRAFT_TT_UNLEARNED = "还没学：训练师在技能 %d 时可以教。",
    CRAFT_LV_SUBTITLE = "最便宜的冲技能路线 · 已学 + 训练师配方 · 成品价值抵扣成本",
    CRAFT_LV_VIEW_LIST = "当前",
    CRAFT_LV_VIEW_PLAN = "路线",
    CRAFT_LV_VIEW_TIP = "当前：现在的技能下能加点的配方。路线：一步一步冲到目标。",
    CRAFT_LV_HEADER = "%s %d/%d  ->  目标 %d",
    CRAFT_LV_TARGET = "目标",
    CRAFT_LV_TARGET_TIP = "要冲到多少：这个专业当前的上限、225 或 300。",
    CRAFT_LV_TARGET_MAX = "上限 (%d)",
    CRAFT_LV_HEAD_RECIPE = "配方",
    CRAFT_LV_HEAD_CHANCE = "加点几率",
    CRAFT_LV_HEAD_NET = "每次成本",
    CRAFT_LV_HEAD_POINT = "每点技能",
    CRAFT_LV_HEAD_SKILL = "技能",
    CRAFT_LV_HEAD_STEP = "花费",
    CRAFT_LV_HEAD_TOTAL = "累计",
    CRAFT_LV_COLOR_orange = "橙色",
    CRAFT_LV_COLOR_yellow = "黄色",
    CRAFT_LV_COLOR_green = "绿色",
    CRAFT_LV_COLOR_grey = "灰色",
    CRAFT_LV_GREY_AT = "%d 变灰",
    CRAFT_LV_MATS = "材料 %s",
    CRAFT_LV_PER_CRAFT = "每次 +%d",
    CRAFT_LV_POINTS = "+%d 点",
    CRAFT_LV_LEARN = "去训练师学",
    CRAFT_LV_PLAN_LABEL = "冲技能路线 · %d -> %d",
    CRAFT_LV_PLAN_DETAIL = "%d 步 · 要去训练师学 %d 个配方",
    CRAFT_LV_TOTAL = "冲到 %d 总花费",
    CRAFT_LV_SHOP_HINT = "鼠标悬停看购物清单",
    CRAFT_LV_MISSING = "%d 个配方没价格被跳过（请先扫描）",
    CRAFT_LV_SHORT = "拍卖行的货不够买完整条路线",
    CRAFT_LV_STUCK = "到 %d 就停了：那里没有能加点的配方",
    CRAFT_LV_EST = "估算",
    CRAFT_UNLEARNED_GUESS = "未学 · 训练师 ~%d",
    CRAFT_LV_GUESS = "学习技能是估算的，去训练师那里看一次就准确了。",
    CRAFT_LV_TT_TRAIN = "训练费",
    CRAFT_LV_TT_TRAIN_UNKNOWN = "未知（去训练师那里看一次）",
    CRAFT_LV_LEARN_UNKNOWN = "%d 个训练费未知",
    CRAFT_LV_PLAN_DETAIL_COST = "%d 步 · 要去训练师学 %d 个配方（%s）",
    CRAFT_LV_TT_VALUE = "卖掉成品",
    CRAFT_LV_NO_PROF = "没找到制造专业。请把每个专业窗口打开一次，Getrich 才能读到。",
    CRAFT_LV_AT_TARGET = "%s 已经到 %d 了。选更高的目标，或者去训练师学下一级。",
    CRAFT_LV_NONE = "技能 %d 时没有能加点的配方（已学的和训练师的都算）。",
    CRAFT_LV_NO_ENGINE = "冲技能规划不可用。",
    CRAFT_LV_TT_CHANCE = "加点几率",
    CRAFT_LV_TT_COLORS = "橙 %d · 黄 %d · 绿 %d · 灰 %d",
    CRAFT_LV_TT_OFFSET = "成品价值（%s）",
    CRAFT_LV_TT_NO_OFFSET = "不计算成品价值",
    CRAFT_LV_TT_NET = "每次成本",
    CRAFT_LV_TT_POINT = "每点技能成本",
    CRAFT_LV_TT_EARNS = "赚 %s",
    CRAFT_LV_TT_STEP = "这一步的材料（做 %d 次）",
    CRAFT_LV_TT_EXPECTED = "预计制作次数",
    CRAFT_LV_TT_SHOP = "冲到 %d 的购物清单",
    CRAFT_LV_TT_LEARN = "要去训练师学：",
    CRAFT_LV_TT_LEARN_AT = "%s（技能 %d）",
    CRAFT_LV_TT_TOTAL = "合计（扣掉卖成品的钱）",
    CRAFT_LV_PRINT = "扫描完成。%s %d -> %d 约需 %s。",
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
    CRAFT_NO_RECIPES = "請把每個專業視窗都打開一次，Getrich 才能讀到你的配方。",
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
    CRAFT_MODE_PROFIT = "賺錢",
    CRAFT_MODE_PROFIT_TIP = "每個配方做出來賣掉能賺多少。",
    CRAFT_MODE_LEVEL = "衝技能",
    CRAFT_MODE_LEVEL_TIP = "最便宜的衝技能方法：已學的配方和訓練師能教的配方都算。成品的價值（賣商人、拍賣場、分解裡最高的）抵扣成本。",
    CRAFT_SHOW_UNLEARNED = "顯示未學的",
    CRAFT_SHOW_UNLEARNED_TIP = "同時列出訓練師能教、但你還沒學的配方。",
    CRAFT_UNLEARNED = "未學 · 訓練師 %d",
    CRAFT_UNLEARNED_ITEM = "未學 · 配方書",
    CRAFT_TT_UNLEARNED = "還沒學：訓練師在技能 %d 時可以教。",
    CRAFT_LV_SUBTITLE = "最便宜的衝技能路線 · 已學 + 訓練師配方 · 成品價值抵扣成本",
    CRAFT_LV_VIEW_LIST = "目前",
    CRAFT_LV_VIEW_PLAN = "路線",
    CRAFT_LV_VIEW_TIP = "目前：現在的技能下能加點的配方。路線：一步一步衝到目標。",
    CRAFT_LV_HEADER = "%s %d/%d  ->  目標 %d",
    CRAFT_LV_TARGET = "目標",
    CRAFT_LV_TARGET_TIP = "要衝到多少：這個專業目前的上限、225 或 300。",
    CRAFT_LV_TARGET_MAX = "上限 (%d)",
    CRAFT_LV_HEAD_RECIPE = "配方",
    CRAFT_LV_HEAD_CHANCE = "加點機率",
    CRAFT_LV_HEAD_NET = "每次成本",
    CRAFT_LV_HEAD_POINT = "每點技能",
    CRAFT_LV_HEAD_SKILL = "技能",
    CRAFT_LV_HEAD_STEP = "花費",
    CRAFT_LV_HEAD_TOTAL = "累計",
    CRAFT_LV_COLOR_orange = "橙色",
    CRAFT_LV_COLOR_yellow = "黃色",
    CRAFT_LV_COLOR_green = "綠色",
    CRAFT_LV_COLOR_grey = "灰色",
    CRAFT_LV_GREY_AT = "%d 變灰",
    CRAFT_LV_MATS = "材料 %s",
    CRAFT_LV_PER_CRAFT = "每次 +%d",
    CRAFT_LV_POINTS = "+%d 點",
    CRAFT_LV_LEARN = "去訓練師學",
    CRAFT_LV_PLAN_LABEL = "衝技能路線 · %d -> %d",
    CRAFT_LV_PLAN_DETAIL = "%d 步 · 要去訓練師學 %d 個配方",
    CRAFT_LV_TOTAL = "衝到 %d 總花費",
    CRAFT_LV_SHOP_HINT = "滑鼠懸停看購物清單",
    CRAFT_LV_MISSING = "%d 個配方沒價格被跳過（請先掃描）",
    CRAFT_LV_SHORT = "拍賣場的貨不夠買完整條路線",
    CRAFT_LV_STUCK = "到 %d 就停了：那裡沒有能加點的配方",
    CRAFT_LV_EST = "估算",
    CRAFT_UNLEARNED_GUESS = "未學 · 訓練師 ~%d",
    CRAFT_LV_GUESS = "學習技能是估算的，去訓練師那裡看一次就準確了。",
    CRAFT_LV_TT_TRAIN = "訓練費",
    CRAFT_LV_TT_TRAIN_UNKNOWN = "未知（去訓練師那裡看一次）",
    CRAFT_LV_LEARN_UNKNOWN = "%d 個訓練費未知",
    CRAFT_LV_PLAN_DETAIL_COST = "%d 步 · 要去訓練師學 %d 個配方（%s）",
    CRAFT_LV_TT_VALUE = "賣掉成品",
    CRAFT_LV_NO_PROF = "沒找到製造專業。請把每個專業視窗打開一次，Getrich 才能讀到。",
    CRAFT_LV_AT_TARGET = "%s 已經到 %d 了。選更高的目標，或者去訓練師學下一級。",
    CRAFT_LV_NONE = "技能 %d 時沒有能加點的配方（已學的和訓練師的都算）。",
    CRAFT_LV_NO_ENGINE = "衝技能規劃不可用。",
    CRAFT_LV_TT_CHANCE = "加點機率",
    CRAFT_LV_TT_COLORS = "橙 %d · 黃 %d · 綠 %d · 灰 %d",
    CRAFT_LV_TT_OFFSET = "成品價值（%s）",
    CRAFT_LV_TT_NO_OFFSET = "不計算成品價值",
    CRAFT_LV_TT_NET = "每次成本",
    CRAFT_LV_TT_POINT = "每點技能成本",
    CRAFT_LV_TT_EARNS = "賺 %s",
    CRAFT_LV_TT_STEP = "這一步的材料（做 %d 次）",
    CRAFT_LV_TT_EXPECTED = "預計製作次數",
    CRAFT_LV_TT_SHOP = "衝到 %d 的購物清單",
    CRAFT_LV_TT_LEARN = "要去訓練師學：",
    CRAFT_LV_TT_LEARN_AT = "%s（技能 %d）",
    CRAFT_LV_TT_TOTAL = "合計（扣掉賣成品的錢）",
    CRAFT_LV_PRINT = "掃描完成。%s %d -> %d 約需 %s。",
    CRAFT_NO_ITEMS = "你的 %d 個配方都做不出能賣的物品（比如附魔）。",
    CRAFT_NO_OUTPUT_N = "%d 個沒有成品的配方不顯示",
    CRAFT_TT_DE_SKILL = "需要附魔 %d",
    CRAFT_TT_DE_MISSING = "分解材料還沒有價格",
    CRAFT_TT_DE_MEASURED = "按你自己的分解結果計算",
    CRAFT_TT_EST = "拍賣場價格來自瀏覽：只知道最便宜的那一條",
    CRAFT_AGO_D = "%d 天前",
  },
})

-- settings of this tab (registered before DB_READY; keys shared with other modules only if nobody registered them)
do
  local S = WC.Store
  if S and S.Default then
    S:Default("craftMode", "profit")          -- "profit" | "level"
    S:Default("craftOnlyProfit", false)
    S:Default("craftHideMissing", false)
    S:Default("craftProf", "all")             -- profession filter of the profit list
    S:Default("craftLevelView", "list")       -- skill-up mode: "list" (now) | "plan" (route)
    local function Shared(key, value)
      if not (type(S.DEFAULTS) == "table" and S.DEFAULTS[key] ~= nil) then S:Default(key, value) end
    end
    Shared("craftShowUnlearned", false)       -- read by Profit
    Shared("levelTarget", "max")              -- read by Leveling
  end
end

local Money, Num, Font = WC.Money, UI.Num, UI.Font
local C_GREEN, C_ORANGE, C_GREY = UI.C_GREEN, UI.C_ORANGE, UI.C_GREY
local C_WHITE = "|cffffffff"
local C_RED = "|cffff5a4a"
local C_GREEN_DIM = "|cff8cc796"
local C_RED_DIM = "|cffc77a70"
local QUALITY = { [0] = "|cff9d9d9d", "|cffffffff", "|cff1eff00", "|cff0070dd", "|cffa335ee", "|cffff8000", "|cffe6cc80", "|cff00ccff" }
-- trade skill difficulty colours (orange / yellow / green / grey), as the profession window uses them
local DIFF = {
  orange = { 1, 0.5, 0.25, "|cffff8040" },
  yellow = { 1, 1, 0, "|cffffff00" },
  green  = { 0.25, 0.75, 0.25, "|cff40bf40" },
  grey   = { 0.5, 0.5, 0.5, "|cff808080" },
}

local Tab = {}

-- Column layouts for the 662 px rows. Cells c1..c4 change meaning with the mode:
--   profit: c1 materials cost | c2 sell to vendor | c3 sell on AH | c4 disenchant (only with Enchanting)
--   level (now):   c1 chance | c2 cost per craft | c3 per skill point
--   level (route): c1 skill range | c2 step cost | c3 running total
-- hot = the column under the second click target (search the costliest AH material).
local LAYOUT = {
  profit_de = { recipe = { x = 36, w = 246 }, c1 = { r = 368, w = 80 }, c2 = { r = 462, w = 88 }, c3 = { r = 556, w = 88 },
                c4 = { r = 650, w = 88 }, hot = "c1", dot = false },
  profit = { recipe = { x = 36, w = 306 }, c1 = { r = 438, w = 86 }, c2 = { r = 544, w = 100 }, c3 = { r = 650, w = 100 },
             hot = "c1", dot = false },
  level = { recipe = { x = 50, w = 296 }, c1 = { r = 440, w = 84 }, c2 = { r = 545, w = 100 }, c3 = { r = 650, w = 100 },
            hot = "c2", dot = true },
}
LAYOUT.plan = LAYOUT.level
Tab.LAYOUT = LAYOUT
local HEAD_Y, LIST_TOP = -140, -156
local CELLS = { "c1", "c2", "c3", "c4" }

-- ---------------------------------------------------------------------------
-- small helpers

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function DB() return WC:DB() end

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
  if not itemID then return nil end
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

-- a cost that can be negative (profitable while levelling): cost white, gain green "+x"
local function CostText(v, approx)
  if v == nil then return C_ORANGE .. "?|r" end
  if v < 0 then return UI.Colored("+" .. Money(-v), C_GREEN) end
  return (approx and "≈ " or "") .. Money(v)
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

local function MatCost(itemID, qty)
  local P = WC.Profit
  if P and P.MatCost then
    local ok, m = pcall(P.MatCost, P, itemID, qty)
    if ok and type(m) == "table" then return m end
  end
  return nil
end

-- price details of one material: { ah = { cost, status, unit, time, source }, vendor = { unit, info } }
local function MatInfo(r)
  if type(r.mat) == "table" then return r.mat end
  if r.ah or r.vendor then return r end
  return MatCost(ReagentID(r), ReagentQty(r)) or {}
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
-- recipe data for the skill-up mode: the character's own capture first, else the built-in table WC.RECIPES

-- itemID, qty of reagent i in either layout ({ {id, qty}, ... } captured, or { id, qty, id, qty } built in)
local function ReagentAt(r, i)
  if type(r) ~= "table" then return nil end
  if type(r[1]) == "table" then
    local x = r[i]
    if x then return x[1] or x.itemID, x[2] or x.qty or 1 end
    return nil
  end
  local id = r[2 * i - 1]
  if id then return id, r[2 * i] or 1 end
  return nil
end

function Tab:StaticRecipe(skillLine, recipeID)
  local R = WC.RECIPES
  local list = type(R) == "table" and skillLine and R[skillLine]
  local s = type(list) == "table" and list[recipeID] or nil
  if s == nil and type(R) == "table" and not skillLine then
    -- lines are decoded lazily (pairs(R) lists only decoded ones): find the recipe's line, then read that line
    local sl = WC.RecipeLine and WC.RecipeLine(recipeID)
    local l = sl and R[sl]
    s = type(l) == "table" and l[recipeID] or nil
  end
  return type(s) == "table" and s or nil
end

-- output itemID, reagent list (either layout), static row (thresholds) of a recipe
function Tab:RecipeData(recipeID, skillLine)
  local mine
  local Rc = WC.Recipes
  if Rc and Rc.ForChar then
    local ok, t = pcall(Rc.ForChar, Rc, WC:CharKey())
    mine = ok and type(t) == "table" and t[recipeID] or nil
  end
  local st = self:StaticRecipe(skillLine, recipeID)
  local out = (type(mine) == "table" and mine.o) or (st and st.o) or nil
  local reags = (type(mine) == "table" and mine.r) or (st and st.r) or nil
  return out, reags, st, type(mine) == "table" and mine or nil
end

-- the costliest material bought on the AH for `crafts` crafts of a recipe (as Profit would buy it)
function Tab:CostliestFor(recipeID, skillLine, crafts)
  local _, reags = self:RecipeData(recipeID, skillLine)
  local best, bestCost, firstMissing
  local i = 1
  while true do
    local id, qty = ReagentAt(reags, i)
    if not id then break end
    local m = MatCost(id, qty * (crafts or 1))
    if m and m.source == "ah" and m.cost and (not bestCost or m.cost > bestCost) then
      best, bestCost = id, m.cost
    elseif (not m or m.cost == nil) and not firstMissing then
      firstMissing = id
    end
    i = i + 1
  end
  return best or firstMissing
end

-- difficulty colour of a recipe at a skill (built-in thresholds); nil if unknown
local function ColorAt(st, skill)
  if not (st and st.y and st.g and skill) then return nil end
  if skill < st.y then return "orange" end
  if skill < math.floor((st.y + st.g) / 2) then return "yellow" end
  if skill < st.g then return "green" end
  return "grey"
end

-- ---------------------------------------------------------------------------
-- data: profit mode

local NO_COUNTS = {}
local EMPTY = {}

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

function Tab:LoadProfs(charKey)
  local profs
  local R = WC.Recipes
  if R and R.Professions then
    local ok, p = pcall(R.Professions, R, charKey)
    if ok and type(p) == "table" then profs = p end
  end
  self.profs = profs or {}
  return self.profs
end

local function SortByName(self, list)
  table.sort(list, function(a, b)
    local na, nb = self:ProfName(a), self:ProfName(b)
    if na ~= nb then return na < nb end
    return tostring(a) < tostring(b)
  end)
end

-- profit-mode profession picker: "all" + the professions that have recipes in the list, by name
function Tab:ProfValues(charKey, all)
  self:LoadProfs(charKey)
  local used, list = {}, {}
  for _, e in ipairs(all) do
    if e.prof ~= nil and not used[e.prof] then used[e.prof] = true; list[#list + 1] = e.prof end
  end
  SortByName(self, list)
  local values = self.profValues or {}
  for i = #values, 1, -1 do values[i] = nil end
  values[1] = "all"
  for i = 1, #list do values[i + 1] = list[i] end
  self.profValues = values
  return values
end

-- does the built-in table have recipes for a skill line? Decodes nothing: WC.RECIPE_LINES lists the encoded
-- lines; rawget finds lines added at runtime. WC.RECIPES[line] is read only for the profession shown in skill-up mode.
local function HasStaticLine(skillLine)
  local lines = WC.RECIPE_LINES
  if type(lines) == "table" then
    for i = 1, #lines do if lines[i] == skillLine then return true end end
  end
  local R = WC.RECIPES
  local rows = type(R) == "table" and rawget(R, skillLine)
  return type(rows) == "table" and next(rows) ~= nil
end

-- skill-up picker: the character's crafting professions (recipes captured or in the built-in table), no "All"
function Tab:LevelValues(charKey)
  local profs = self:LoadProfs(charKey)
  local has = {}
  local R = WC.Recipes
  if R and R.ForChar then
    local ok, t = pcall(R.ForChar, R, charKey)
    if ok and type(t) == "table" then
      for _, r in pairs(t) do if type(r) == "table" and r.p then has[r.p] = true end end
    end
  end
  local list = {}
  for skillLine in pairs(profs) do
    if has[skillLine] or HasStaticLine(skillLine) then list[#list + 1] = skillLine end
  end
  SortByName(self, list)
  local values = self.levelValues or {}
  for i = #values, 1, -1 do values[i] = nil end
  for i = 1, #list do values[i] = list[i] end
  self.levelValues = values
  return values
end

local function Matches(self, e, q)
  if q == "" then return true end
  if e.name and string.lower(e.name):find(q, 1, true) then return true end
  local name = self:ItemName(e.itemID)
  return name ~= nil and string.lower(name):find(q, 1, true) ~= nil
end

-- filtered + ranked list of wrappers { e = entry, rank } (reused tables; Profit's entries are not changed).
-- Returns vis, number of entries matching the profession + search (before the switches).
function Tab:Visible(all)
  local db = DB()
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
        w.e, w.c, w.s, w.plan = e, nil, nil, nil
        if e.best ~= nil then rank = rank + 1; w.rank = rank else w.rank = nil end
        vis[n] = w
      end
    end
  end
  for i = #vis, n + 1, -1 do vis[i] = nil end
  return vis, matched
end

-- ---------------------------------------------------------------------------
-- data: skill-up mode

local function Leveling(method, ...)
  local Lv = WC.Leveling
  local fn = Lv and Lv[method]
  if type(fn) ~= "function" then return nil, "missing" end
  local ok, a, b = pcall(fn, Lv, ...)
  if not ok then
    if UI.Report then UI.Report("craft:Leveling." .. method, a) end
    return nil, "error"
  end
  return a, b
end

function Tab:Skill(charKey, skillLine)
  local R = WC.Recipes
  if R and R.Skill then
    local ok, rank, max = pcall(R.Skill, R, charKey, skillLine)
    if ok and rank then return rank, max or rank end
  end
  local p = self.profs and self.profs[skillLine]
  if type(p) == "table" and p.rank then return p.rank, p.max or p.rank end
  return nil
end

-- target skill from db.levelTarget ("max" = the profession's current maximum)
local function Target(setting, max)
  local n = tonumber(setting)
  if n then return n end
  return max
end

-- wrappers for the "now" list ({ c = candidate, rank }) and the route ({ s = step, rank = step number, total })
function Tab:LevelRows(cands, plan, view)
  local vis, wraps = self.lvis or {}, self.lwraps or {}
  self.lvis, self.lwraps = vis, wraps
  local n = 0
  if view == "plan" then
    local total = 0
    for i, s in ipairs(plan and plan.steps or EMPTY) do
      n = n + 1
      local w = wraps[n]
      if not w then w = {}; wraps[n] = w end
      if s.net then total = total + s.net end
      w.e, w.c, w.plan, w.s, w.rank, w.total = nil, nil, nil, s, i, total
      vis[n] = w
    end
  else
    local rank = 0
    for _, c in ipairs(cands or EMPTY) do
      n = n + 1
      local w = wraps[n]
      if not w then w = {}; wraps[n] = w end
      w.e, w.s, w.plan, w.c, w.total = nil, nil, nil, c, nil
      if c.perPoint ~= nil then rank = rank + 1; w.rank = rank else w.rank = nil end
      vis[n] = w
    end
  end
  for i = #vis, n + 1, -1 do vis[i] = nil end
  return vis
end

-- ---------------------------------------------------------------------------
-- widgets

local function Place(fs, row, col, y)
  fs:ClearAllPoints()
  fs:SetWidth(col.w)
  if col.r then fs:SetPoint("TOPRIGHT", row, "TOPLEFT", col.r, y) else fs:SetPoint("TOPLEFT", row, "TOPLEFT", col.x, y) end
end

-- flat tab-like toggle button (same look as the window's tab bar)
local function SegButton(parent, text, small)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(small and 20 or 22)
  local fs = Font(b, small and "GameFontNormalSmall" or "GameFontNormal", "CENTER")
  fs:SetPoint("CENTER", 0, 1)
  fs:SetText(text)
  b:SetWidth(math.max(small and 44 or 60, fs:GetStringWidth() + (small and 18 or 24)))
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
  return b
end

local function SetSeg(b, on)
  b.line:SetShown(on)
  b.bg:SetColorTexture(1, 1, 1, on and 0.06 or 0)
  if on then b.text:SetTextColor(1, 0.82, 0) else b.text:SetTextColor(0.55, 0.57, 0.6) end
end

-- value cycler (the shell's when it exists) for a db key with a value list that changes at runtime
function Tab:Cycler(panel, x, y, label, key, values, labels, tip, minWidth)
  if UI.ValueCycler then
    local fs, b = UI:ValueCycler(panel, x, y, label, key, values, labels, tip)
    b.minWidth = minWidth
    return fs, b
  end
  local fs = Font(panel, "GameFontHighlightSmall", "LEFT")
  fs:SetPoint("TOPLEFT", x, y - 4)
  fs:SetText(label)
  local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  b:SetSize(minWidth or 110, 20)
  b:SetPoint("LEFT", fs, "RIGHT", 6, 0)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", function(_, button)
    local vals = values()
    local db = DB()
    local cur = 1
    for i, v in ipairs(vals) do if v == db[key] then cur = i end end
    cur = (button == "RightButton") and (cur - 1) or (cur + 1)
    if cur > #vals then cur = 1 elseif cur < 1 then cur = #vals end
    if GetrichDB then GetrichDB[key] = vals[cur] end
    WC:Fire("SETTINGS_CHANGED", key)
    UI:Refresh()
  end)
  UI.Tip(b, label, tip)
  return fs, b
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

function Tab:SetMode(mode)
  if GetrichDB then GetrichDB.craftMode = mode end
  if UI.subtitle then UI.subtitle:SetText(self:Subtitle()) end
  UI:Refresh()
end

function Tab:SetView(view)
  if GetrichDB then GetrichDB.craftLevelView = view end
  UI:Refresh()
end

function Tab:Create(panel)
  self.panel = panel
  self.rows = {}
  self.query = ""
  self.layoutKey = "profit_de"   -- rows built from now on follow self.layoutKey

  -- line 1: mode switch, profession picker(s), search box / route toggle
  local mp = SegButton(panel, L.CRAFT_MODE_PROFIT)
  mp:SetPoint("TOPLEFT", 0, -1)
  local ml = SegButton(panel, L.CRAFT_MODE_LEVEL)
  ml:SetPoint("LEFT", mp, "RIGHT", 4, 0)
  mp:SetScript("OnClick", function() self:SetMode("profit") end)
  ml:SetScript("OnClick", function() self:SetMode("level") end)
  UI.Tip(mp, L.CRAFT_MODE_PROFIT, L.CRAFT_MODE_PROFIT_TIP)
  UI.Tip(ml, L.CRAFT_MODE_LEVEL, L.CRAFT_MODE_LEVEL_TIP)
  self.modeProfit, self.modeLevel = mp, ml
  local px = mp:GetWidth() + ml:GetWidth() + 4 + 18

  -- the shell asks for the values on every refresh, also while another tab is open: compute only when shown
  local function profValues()
    if self.profValues and not (self.panel:IsShown() and self.mode == "profit") then return self.profValues end
    local charKey = WC:CharKey()
    return self:ProfValues(charKey, (self:Entries(charKey)))
  end
  local function levelValues()
    if self.levelValues and not (self.panel:IsShown() and self.mode == "level") then return self.levelValues end
    return self:LevelValues(WC:CharKey())
  end
  local function profLabel(v)
    if v == nil or v == "all" then return L.CRAFT_ALL end
    return self:ProfName(v)
  end
  self.profLabel, self.profButton = self:Cycler(panel, px, -2, L.CRAFT_PROF, "craftProf", profValues, profLabel, L.CRAFT_PROF_TIP, 110)
  self.levelLabel, self.levelButton = self:Cycler(panel, px, -2, L.CRAFT_PROF, "levelProf", levelValues, profLabel, L.CRAFT_PROF_TIP, 110)

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
  self.search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)

  local vp = SegButton(panel, L.CRAFT_LV_VIEW_PLAN, true)
  vp:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
  local vl = SegButton(panel, L.CRAFT_LV_VIEW_LIST, true)
  vl:SetPoint("RIGHT", vp, "LEFT", -4, 0)
  vl:SetScript("OnClick", function() self:SetView("list") end)
  vp:SetScript("OnClick", function() self:SetView("plan") end)
  UI.Tip(vl, L.CRAFT_LV_VIEW_LIST, L.CRAFT_LV_VIEW_TIP)
  UI.Tip(vp, L.CRAFT_LV_VIEW_PLAN, L.CRAFT_LV_VIEW_TIP)
  self.viewList, self.viewPlan = vl, vp

  -- line 2: profit switches + hidden count | skill-up header + target
  self.checks = UI:CheckRow(panel, -28, {
    { L.CRAFT_ONLY_PROFIT, "craftOnlyProfit", L.CRAFT_ONLY_PROFIT_TIP },
    { L.CRAFT_HIDE_MISSING, "craftHideMissing", L.CRAFT_HIDE_MISSING_TIP },
    { L.CRAFT_SHOW_UNLEARNED, "craftShowUnlearned", L.CRAFT_SHOW_UNLEARNED_TIP },
  })
  self.hidden = Font(panel, "GameFontDisableSmall", "RIGHT", 250)
  self.hidden:SetPoint("TOPRIGHT", -2, -33)
  self.levelHead = Font(panel, "GameFontNormal", "LEFT", 400)
  self.levelHead:SetPoint("TOPLEFT", 0, -31)
  local function targetValues() return { "max", 225, 300 } end
  local function targetLabel(v)
    if v == "max" then
      local _, max = self:Skill(WC:CharKey(), DB().levelProf)
      return L.CRAFT_LV_TARGET_MAX:format(max or 0)
    end
    return tostring(v)
  end
  self.targetLabel, self.targetButton = self:Cycler(panel, 450, -28, L.CRAFT_LV_TARGET, "levelTarget", targetValues, targetLabel, L.CRAFT_LV_TARGET_TIP, 90)

  self.best = UI:BestPanel(panel, -54, self)

  local cols = { rank = { x = 4, w = 26, justify = "CENTER" }, recipe = LAYOUT.profit_de.recipe,
                 c1 = LAYOUT.profit_de.c1, c2 = LAYOUT.profit_de.c2, c3 = LAYOUT.profit_de.c3, c4 = LAYOUT.profit_de.c4 }
  self.list = UI:List(panel, HEAD_Y, LIST_TOP, cols, nil, function(row) self:BuildRow(row) end)
  self.list.headers.rank:SetText("#")
  self:ApplyLayout("profit_de")
end

-- called by the list for every row frame it builds (also later, when the list grows)
function Tab:BuildRow(row)
  row.name = Font(row, "GameFontHighlight", "LEFT")
  row.sub = Font(row, "GameFontDisableSmall", "LEFT")
  for _, k in ipairs(CELLS) do
    row[k] = Font(row, "GameFontHighlightSmall", "RIGHT")
    row[k .. "Sub"] = Font(row, "GameFontDisableSmall", "RIGHT")
  end
  row.dot = row:CreateTexture(nil, "ARTWORK")
  row.dot:SetSize(8, 8)
  row.dot:SetPoint("TOPLEFT", row, "TOPLEFT", 37, -7)
  row.hotA = UI.Hotspot(row, self, "a", function() return row.entry end)
  row.hotB = UI.Hotspot(row, self, "b", function() return row.entry end)
  row:SetScript("OnEnter", function(r) if r.entry then self:ShowTooltip(r, r.entry) end end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  self.rows[#self.rows + 1] = row
  self:LayoutRow(row)
end

function Tab:LayoutRow(row)
  local C = LAYOUT[self.layoutKey] or LAYOUT.profit_de
  Place(row.name, row, C.recipe, -3)
  Place(row.sub, row, C.recipe, -18)
  for _, k in ipairs(CELLS) do
    local col = C[k]
    if col then
      Place(row[k], row, col, -4)
      Place(row[k .. "Sub"], row, col, -18)
    end
    row[k]:SetShown(col ~= nil)
    row[k .. "Sub"]:SetShown(col ~= nil)
  end
  row.dot:SetShown(C.dot)
  local ROW_H = UI.ROW_H or 32
  local hot = C[C.hot]
  row.hotA:ClearAllPoints()
  row.hotA:SetPoint("TOPLEFT", row, "TOPLEFT", C.recipe.x - 4, 0)
  row.hotA:SetSize(C.recipe.w + 4, ROW_H)
  row.hotB:ClearAllPoints()
  row.hotB:SetPoint("TOPLEFT", row, "TOPLEFT", hot.r - hot.w - 4, 0)
  row.hotB:SetSize(hot.w + 8, ROW_H)
end

local HEADS = {
  profit_de = { recipe = "CRAFT_HEAD_RECIPE", c1 = "CRAFT_HEAD_COST", c2 = "CRAFT_HEAD_NPC", c3 = "CRAFT_HEAD_AH", c4 = "CRAFT_HEAD_DE" },
  profit = { recipe = "CRAFT_HEAD_RECIPE", c1 = "CRAFT_HEAD_COST", c2 = "CRAFT_HEAD_NPC", c3 = "CRAFT_HEAD_AH" },
  level = { recipe = "CRAFT_LV_HEAD_RECIPE", c1 = "CRAFT_LV_HEAD_CHANCE", c2 = "CRAFT_LV_HEAD_NET", c3 = "CRAFT_LV_HEAD_POINT" },
  plan = { recipe = "CRAFT_LV_HEAD_RECIPE", c1 = "CRAFT_LV_HEAD_SKILL", c2 = "CRAFT_LV_HEAD_STEP", c3 = "CRAFT_LV_HEAD_TOTAL" },
}

-- switch the columns (profit with / without disenchant, skill-up now / route); only re-anchors, never creates
function Tab:ApplyLayout(key)
  self.layoutKey = key
  local C = LAYOUT[key]
  local heads = HEADS[key]
  for k, fs in pairs(self.list.headers) do
    local col = (k == "rank") and { x = 4, w = 26 } or C[k]
    if col then
      fs:ClearAllPoints()
      fs:SetWidth(col.w)
      fs:SetPoint("TOPLEFT", self.panel, "TOPLEFT", col.r and (col.r - col.w) or col.x, HEAD_Y)
      if heads[k] then fs:SetText(L[heads[k]]) end
    end
    fs:SetShown(col ~= nil)
  end
  for _, row in ipairs(self.rows) do self:LayoutRow(row) end
end

-- show the controls of a mode
function Tab:ShowControls(mode, view)
  local level = (mode == "level")
  SetSeg(self.modeProfit, not level)
  SetSeg(self.modeLevel, level)
  self.profLabel:SetShown(not level)
  self.profButton:SetShown(not level)
  self.search:SetShown(not level)
  for _, cb in ipairs(self.checks) do cb:SetShown(not level) end
  self.hidden:SetShown(not level)
  self.levelLabel:SetShown(level)
  self.levelButton:SetShown(level)
  self.viewList:SetShown(level)
  self.viewPlan:SetShown(level)
  self.levelHead:SetShown(level)
  self.targetLabel:SetShown(level)
  self.targetButton:SetShown(level)
  SetSeg(self.viewList, view ~= "plan")
  SetSeg(self.viewPlan, view == "plan")
end

-- ---------------------------------------------------------------------------
-- rows: profit mode

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

function Tab:FillProfitRow(row, e)
  row.name:SetText(self:ProductLabel(e))
  local parts = {}
  if e.learned == false then parts[#parts + 1] = self:LearnTag(e, e.prof) end
  local prof = DB().craftProf
  if prof == nil or prof == "all" then parts[#parts + 1] = self:ProfName(e.prof) end
  if e.tool and e.tool ~= "" then parts[#parts + 1] = L.CRAFT_NEEDS:format(e.tool) end
  if e.status == "loading" then parts[#parts + 1] = L.CRAFT_LOADING end
  row.sub:SetText(table.concat(parts, " · "))

  if e.cost then
    row.c1:SetText(Money(e.cost))
    if e.cash and e.cash < e.cost then
      row.c1Sub:SetText(e.cash <= 0 and (C_GREEN .. L.CRAFT_ALL_IN_BAGS .. "|r") or L.CRAFT_CASH:format(GreyMoney(e.cash)))
    else
      row.c1Sub:SetText("")
    end
  else
    row.c1:SetText(C_ORANGE .. "?|r")
    local n = type(e.missing) == "table" and #e.missing or 0
    row.c1Sub:SetText(n > 0 and (C_ORANGE .. L.CRAFT_MISSING_N:format(n) .. "|r") or "")
  end
  row.c1:SetFontObject(FontObj("GameFontHighlightSmall"))
  local noBuy = (e.npc == 0 or e.npcNoBuy) and (C_GREY .. L.CRAFT_TT_NO_VENDOR .. "|r") or nil
  ProfitCell(row.c2, row.c2Sub, (not noBuy) and e.npcProfit or nil, e.npc, e.bestKind == "npc", false, noBuy)
  ProfitCell(row.c3, row.c3Sub, e.ahProfit, e.ah, e.bestKind == "ah", false)
  if self.layoutKey == "profit_de" then
    local skill = DESkill(e)
    local low = e.deSkillOK == false and skill and (C_ORANGE .. L.CRAFT_TT_DE_SKILL:format(skill) .. "|r") or nil
    ProfitCell(row.c4, row.c4Sub, e.deProfit, e.de, e.bestKind == "de", e.dePartial, low)
  end
  row.hotB:SetShown(CostliestAH(e) ~= nil)
end

-- ---------------------------------------------------------------------------
-- rows: skill-up mode

local function SetDot(row, color)
  local d = color and DIFF[color]
  if d then
    row.dot:SetColorTexture(d[1], d[2], d[3], 1)
    row.dot:Show()
  else
    row.dot:Hide()
  end
end

-- built-in learn skill of a recipe (for "not learned · trainer N")
function Tab:LearnSkill(c, skillLine)
  if c.learnSkill then return c.learnSkill end
  local st = self:StaticRecipe(skillLine, c.recipeID)
  return st and st.s or nil
end

-- learn skill, training cost (nil = unknown), guessed? of an unlearned recipe: the engine's fields (candidate, or the
-- route's learn entry for a step), then Recipes:TrainerInfo (what a trainer showed), then the built-in learn skill
function Tab:LearnInfo(x, skillLine)
  local le = self.learnByID and self.learnByID[x.recipeID]
  local s = x.learnSkill or (le and le.learnSkill)
  local cost = x.learnCost or (le and le.cost)
  local guess = x.learnGuess or (le and (le.learnGuess or le.guess)) or false
  local R = WC.Recipes
  if (s == nil or cost == nil) and R and R.TrainerInfo and x.recipeID then
    local ok, ts, tc = pcall(R.TrainerInfo, R, skillLine, x.recipeID)
    if ok then
      if ts and s == nil then s, guess = ts, false end
      if cost == nil then cost = tc end
    end
  end
  if s == nil then s = self:LearnSkill(x, skillLine) end
  return s, cost, guess and true or false
end

-- "not learned · trainer 105 · 1s 50c" (orange tag, "~105" when the learn skill is a guess)
function Tab:LearnTag(x, skillLine)
  local s, cost, guess = self:LearnInfo(x, skillLine)
  local t
  if s then t = (guess and L.CRAFT_UNLEARNED_GUESS or L.CRAFT_UNLEARNED):format(s) else t = L.CRAFT_UNLEARNED_ITEM end
  return C_ORANGE .. t .. "|r" .. (cost and (" · " .. Money(cost)) or "")
end

-- tooltip lines: learn skill, training cost, and the "estimated" note
function Tab:LearnLines(x, skillLine)
  local T = GameTooltip
  local s, cost, guess = self:LearnInfo(x, skillLine)
  if s then T:AddLine(L.CRAFT_TT_UNLEARNED:format(s), 1, 0.6, 0.2) else T:AddLine(L.CRAFT_LV_LEARN, 1, 0.6, 0.2) end
  T:AddDoubleLine(L.CRAFT_LV_TT_TRAIN, cost and Money(cost) or (C_GREY .. L.CRAFT_LV_TT_TRAIN_UNKNOWN .. "|r"), 1, 0.82, 0, 1, 1, 1)
  if guess then T:AddLine(L.CRAFT_LV_GUESS, 0.55, 0.55, 0.55, true) end
end

-- learn skill, yellow, grey, estimated? of a candidate (engine fields first, then the built-in table)
function Tab:Thresholds(c, skillLine)
  local _, _, st = self:RecipeData(c.recipeID, skillLine)
  local s = c.learnSkill or (st and st.s)
  local y, g = c.y or (st and st.y), c.g or (st and st.g)
  return s, y, g, c.est and true or false
end

function Tab:FillCandRow(row, c)
  local skillLine = self.levelProf
  local _, _, grey, est = self:Thresholds(c, skillLine)
  SetDot(row, c.color)
  row.name:SetText(C_WHITE .. (c.name or ("#" .. tostring(c.recipeID))) .. "|r")
  local parts = {}
  if c.learned == false then parts[#parts + 1] = self:LearnTag(c, skillLine) end
  if grey then parts[#parts + 1] = L.CRAFT_LV_GREY_AT:format(grey) .. (est and ("~") or "") end
  row.sub:SetText(table.concat(parts, " · "))

  local d = DIFF[c.color or ""]
  local pct = c.chance and (UI.Num((c.chance or 0) * 100) .. "%") or "?"
  row.c1:SetFontObject(FontObj("GameFontHighlightSmall"))
  row.c1:SetText((d and d[4] or C_WHITE) .. pct .. "|r")
  row.c1Sub:SetText(c.color and L["CRAFT_LV_COLOR_" .. c.color] or "")

  row.c2:SetFontObject(FontObj("GameFontHighlightSmall"))
  if c.net ~= nil then
    row.c2:SetText(CostText(c.net))
    row.c2Sub:SetText(c.cost and L.CRAFT_LV_MATS:format(GreyMoney(c.cost)) or "")
  else
    row.c2:SetText(C_ORANGE .. "?|r")
    local n = type(c.missing) == "table" and #c.missing or 0
    row.c2Sub:SetText(n > 0 and (C_ORANGE .. L.CRAFT_MISSING_N:format(n) .. "|r") or "")
  end
  row.c3:SetFontObject(FontObj("GameFontHighlight"))
  row.c3:SetText(c.perPoint ~= nil and CostText(c.perPoint, true) or (C_GREY .. "—|r"))
  row.c3Sub:SetText((c.skillUps or 1) > 1 and L.CRAFT_LV_PER_CRAFT:format(c.skillUps) or "")
  row.hotB:SetShown(self:CostliestFor(c.recipeID, skillLine) ~= nil)
end

-- difficulty colour of a recipe at a skill (the engine's rule; the built-in thresholds as a fallback)
function Tab:ColorAt(recipeID, skillLine, skill)
  local _, _, st, mine = self:RecipeData(recipeID, skillLine)
  local Lv = WC.Leveling
  local rec = st or mine
  if rec and Lv and Lv.Chance then
    local ok, _, color = pcall(Lv.Chance, Lv, rec, skill)
    if ok and DIFF[color or ""] then return color end
  end
  return ColorAt(st, skill)
end

function Tab:FillStepRow(row, s, total)
  local skillLine = self.levelProf
  SetDot(row, self:ColorAt(s.recipeID, skillLine, s.from))
  local crafts = math.ceil((s.crafts or 0) - 0.001)
  row.name:SetText(C_WHITE .. (s.name or ("#" .. tostring(s.recipeID))) .. "|r" .. C_GREY .. " ×" .. crafts .. "|r")
  local parts = { L.CRAFT_LV_POINTS:format((s.to or 0) - (s.from or 0)) }
  if s.learned == false then
    local _, cost = self:LearnInfo(s, skillLine)
    parts[#parts + 1] = C_ORANGE .. L.CRAFT_LV_LEARN .. "|r" .. (cost and (" · " .. Money(cost)) or "")
  end
  row.sub:SetText(table.concat(parts, " · "))
  row.c1:SetFontObject(FontObj("GameFontHighlightSmall"))
  row.c1:SetText((s.from or "?") .. "–" .. (s.to or "?"))
  row.c1Sub:SetText("")
  row.c2:SetFontObject(FontObj("GameFontHighlight"))
  row.c2:SetText(CostText(s.net, true))
  row.c2Sub:SetText(s.cost and s.net and s.cost ~= s.net and L.CRAFT_LV_MATS:format(GreyMoney(s.cost)) or "")
  row.c3:SetFontObject(FontObj("GameFontHighlightSmall"))
  row.c3:SetText(CostText(total, true))
  row.c3Sub:SetText("")
  row.hotB:SetShown(self:CostliestFor(s.recipeID, skillLine, 1) ~= nil)
end

function Tab:FillRow(row, w)
  if w.e then return self:FillProfitRow(row, w.e) end
  if w.c then return self:FillCandRow(row, w.c) end
  if w.s then return self:FillStepRow(row, w.s, w.total) end
end

-- ---------------------------------------------------------------------------
-- refresh

function Tab:Refresh()
  if not self.list then return end
  local db = DB()
  local mode = (db.craftMode == "level") and "level" or "profit"
  local view = (db.craftLevelView == "plan") and "plan" or "list"
  self.mode = mode
  self:ShowControls(mode, view)
  if mode == "level" then return self:RefreshLevel(view) end
  return self:RefreshProfit()
end

function Tab:RefreshProfit()
  local charKey = WC:CharKey()
  local all, counts = self:Entries(charKey)
  local key = self:HasEnchanting(charKey, all) and "profit_de" or "profit"
  if key ~= self.layoutKey then self:ApplyLayout(key) end

  -- profession picker: forget a profession this character doesn't have
  local values = self:ProfValues(charKey, all)
  local db = DB()
  local known = false
  for _, v in ipairs(values) do if v == db.craftProf then known = true end end
  if not known and db.craftProf ~= nil and #all > 0 and GetrichDB then
    GetrichDB.craftProf = "all"
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

local function MissingCount(t)
  local n = 0
  if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
  return n
end

-- the most important problem of a route, or nil
function Tab:PlanNote(plan)
  if plan.stuck then return L.CRAFT_LV_STUCK:format(plan.stuck) end
  if plan.total == nil and (plan.short or plan.netSteps) then return L.CRAFT_LV_SHORT end
  local n = MissingCount(plan.missing)
  if n > 0 then return L.CRAFT_LV_MISSING:format(n) end
  if (tonumber(plan.learnCostUnknown) or 0) > 0 then return L.CRAFT_LV_LEARN_UNKNOWN:format(plan.learnCostUnknown) end
  return nil
end

-- route total incl. training (the engine's total already has it; the fallback adds it to the step sum)
function Tab:PlanTotal(plan)
  if plan.total ~= nil then return plan.total end
  if plan.netSteps == nil then return nil end
  return plan.netSteps + (tonumber(plan.learnCost) or 0)
end

-- recipeID -> the route's learn entry (cost, learn skill, guessed), reused table
function Tab:IndexLearn(plan)
  local map = self.learnByID or {}
  self.learnByID = map
  for k in pairs(map) do map[k] = nil end
  if plan and type(plan.learn) == "table" then
    for _, v in pairs(plan.learn) do
      if type(v) == "table" and (v.recipeID or v[1]) then map[v.recipeID or v[1]] = v end
    end
  end
end

local function CountLearn(plan)
  local n = 0
  if type(plan.learn) == "table" then for _ in pairs(plan.learn) do n = n + 1 end end
  return n
end

-- the costliest plan material bought on the AH (search target of the best panel's second line)
local function PlanCostliest(plan)
  local best, bestCost, firstMissing
  for _, m in ipairs(plan.mats or EMPTY) do
    local id = m.itemID or m[1]
    if m.source == "ah" and m.cost and (not bestCost or m.cost > bestCost) then best, bestCost = id, m.cost
    elseif m.cost == nil and not firstMissing then firstMissing = id end
  end
  return best or firstMissing
end

function Tab:RefreshLevel(view)
  local key = (view == "plan") and "plan" or "level"
  if key ~= self.layoutKey then self:ApplyLayout(key) end
  local charKey = WC:CharKey()
  local fill = function(row, w) self:FillRow(row, w) end
  local b = self.best
  local values = self:LevelValues(charKey)
  local db = DB()
  local prof = db.levelProf
  local known = false
  for _, v in ipairs(values) do if v == prof then known = true end end
  if not known then
    prof = values[1]
    if GetrichDB then GetrichDB.levelProf = prof end
    if prof then self.levelButton:SetText(self:ProfName(prof)) end
  end
  self.levelProf = prof
  local function empty(text)
    UI:FillList(self.list, self:LevelRows(nil, nil, "list"), fill, text)
    UI:ShowBest(b, false, text)
  end
  if not prof then
    self.levelHead:SetText("")
    return empty(L.CRAFT_LV_NO_PROF)
  end
  local skill, max = self:Skill(charKey, prof)
  skill, max = skill or 1, max or skill or 1
  local target = Target(db.levelTarget, max)
  self.levelHead:SetText(L.CRAFT_LV_HEADER:format(self:ProfName(prof), skill, max, target))
  if not WC.Leveling then return empty(L.CRAFT_LV_NO_ENGINE) end
  if skill >= target then return empty(L.CRAFT_LV_AT_TARGET:format(self:ProfName(prof), skill)) end

  local plan = Leveling("Plan", charKey, prof, skill, target)
  if type(plan) ~= "table" then plan = nil end
  self.plan = plan
  self:IndexLearn(plan)
  local cands
  if view ~= "plan" then
    cands = Leveling("Candidates", charKey, prof, skill)
    if type(cands) ~= "table" then cands = nil end
  end
  local vis = self:LevelRows(cands, plan, view)
  local top = UI:FillList(self.list, vis, fill, L.CRAFT_LV_NONE:format(skill))

  local steps = plan and plan.steps or EMPTY
  if #steps == 0 then
    UI:ShowBest(b, false, (#vis > 0 and top) and L.CRAFT_BEST_EMPTY or L.CRAFT_LV_NONE:format(skill))
    return
  end
  local first = steps[1]
  local pw = self.planWrap or {}
  self.planWrap = pw
  pw.plan, pw.e, pw.c, pw.s = plan, nil, nil, nil
  UI:ShowBest(b, true)
  b.frame.entry = pw
  b.label:SetText(L.CRAFT_LV_PLAN_LABEL:format(plan.from or skill, plan.to or target))
  local crafts = math.ceil((first.crafts or 0) - 0.001)
  b.name:SetText(C_WHITE .. (first.name or "?") .. "|r" .. C_GREY .. " ×" .. crafts .. "  (" .. (first.from or "?") .. "–" .. (first.to or "?") .. ")|r")
  local learnCost = tonumber(plan.learnCost)
  if learnCost and learnCost > 0 then
    b.detail:SetText(L.CRAFT_LV_PLAN_DETAIL_COST:format(#steps, CountLearn(plan), Money(learnCost)))
  else
    b.detail:SetText(L.CRAFT_LV_PLAN_DETAIL:format(#steps, CountLearn(plan)))
  end
  b.perLabel:SetText(L.CRAFT_LV_TOTAL:format(plan.to or target))
  b.per:SetText(CostText(self:PlanTotal(plan), true))
  local note = self:PlanNote(plan)
  b.net:SetText(note and (C_ORANGE .. note .. "|r") or L.CRAFT_LV_SHOP_HINT)
  b.hot1:SetShown(self:SearchTarget(pw, "a") ~= nil)
  b.hot2:SetShown(PlanCostliest(plan) ~= nil)
end

function Tab:BestMessage()
  local db = DB()
  if db.craftMode == "level" then
    local charKey = WC:CharKey()
    local prof = db.levelProf
    local skill, max = self:Skill(charKey, prof)
    if not (prof and skill) then return nil end
    local target = Target(db.levelTarget, max or skill)
    if skill >= target then return nil end
    local plan = Leveling("Plan", charKey, prof, skill, target)
    local total = type(plan) == "table" and self:PlanTotal(plan) or nil
    if total == nil or #(plan.steps or EMPTY) == 0 then return nil end
    return L.CRAFT_LV_PRINT:format(self:ProfName(prof), skill, target, total < 0 and ("+" .. Money(-total)) or Money(total))
  end
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

function Tab:Subtitle()
  if DB().craftMode == "level" then return L.CRAFT_LV_SUBTITLE end
  return L.CRAFT_SUBTITLE
end
function Tab:ScanTip() return L.CRAFT_SCAN_TIP end
function Tab:ScanKind() return "craft" end

-- product of a skill-up candidate / step
function Tab:ProductOf(x)
  if x.itemID or x.o then return x.itemID or x.o end
  local out = self:RecipeData(x.recipeID, self.levelProf)
  return out
end

-- what a click searches: "a" = the product, "b" = the most expensive material bought on the AH
function Tab:SearchTarget(w, kind)
  if w.plan then
    local first = w.plan.steps and w.plan.steps[1]
    if kind == "a" then return first and self:ProductOf(first) end
    if kind == "b" then return PlanCostliest(w.plan) end
    return nil
  end
  local x = w.c or w.s
  if x then
    if kind == "a" then return self:ProductOf(x) end
    -- ranked by the cost of one craft: a whole step's quantity may be more than the AH has listed
    if kind == "b" then return self:CostliestFor(x.recipeID, self.levelProf, 1) end
    return nil
  end
  local e = w.e or w
  if kind == "a" then return e.itemID end
  if kind == "b" then return CostliestAH(e) end
end

-- ---------------------------------------------------------------------------
-- tooltips

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

-- tooltip lines for qty of a material bought the cheapest way (Profit:MatCost for the whole amount)
function Tab:MatLines(itemID, qty)
  local m = MatCost(itemID, qty) or {}
  self:ReagentLines({ itemID = itemID, qty = qty, cost = m.cost, unit = m.unit, source = m.source, status = m.status, mat = m })
end

-- materials for `crafts` crafts of a recipe
function Tab:RecipeMatLines(recipeID, crafts)
  local _, reags = self:RecipeData(recipeID, self.levelProf)
  local i = 1
  while true do
    local id, qty = ReagentAt(reags, i)
    if not id then break end
    self:MatLines(id, qty * crafts)
    i = i + 1
  end
end

local function DEReason(e)
  local st = e.deStatus
  if st == "missing" then return L.CRAFT_TT_DE_MISSING end
  if st == "loading" then return L.CRAFT_LOADING end
  return L.CRAFT_TT_NO_DE
end

function Tab:ShowTooltip(owner, w, kind)
  if w.plan then return self:PlanTooltip(owner, w.plan, kind) end
  if w.c then return self:CandTooltip(owner, w.c, kind) end
  if w.s then return self:StepTooltip(owner, w.s, kind) end
  return self:ProfitTooltip(owner, w.e or w, kind)
end

local function ClickLine(self, kind, x)
  local T = GameTooltip
  if kind == "a" then
    local id = self:SearchTarget(x, "a")
    if id then T:AddLine(L.CRAFT_CLICK_PRODUCT:format(self:ItemName(id) or ("item:" .. id)), 0.3, 1, 0.4) end
  elseif kind == "b" then
    local id = self:SearchTarget(x, "b")
    if id then T:AddLine(L.CRAFT_CLICK_MAT:format(self:ItemName(id) or ("item:" .. id)), 0.3, 1, 0.4) end
  else
    T:AddLine(L.CRAFT_CLICK_HINT, 0.3, 1, 0.4, true)
  end
end

function Tab:ProfitTooltip(owner, e, kind)
  local T = GameTooltip
  T:SetOwner(owner, "ANCHOR_RIGHT")
  T:AddLine(self:ProductLabel(e))
  local sub = self:ProfName(e.prof)
  local productName = self:ItemName(e.itemID)
  if e.name and e.name ~= productName then sub = e.name .. " · " .. sub end
  T:AddLine(sub, 0.7, 0.7, 0.7)
  if e.learned == false and e.learnSkill then T:AddLine(L.CRAFT_TT_UNLEARNED:format(e.learnSkill), 1, 0.6, 0.2) end
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
  if self.layoutKey == "profit_de" then
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
  ClickLine(self, kind, { e = e })
  T:Show()
end

function Tab:CandTooltip(owner, c, kind)
  local T = GameTooltip
  local skillLine = self.levelProf
  local ls, ly, lg, est = self:Thresholds(c, skillLine)
  T:SetOwner(owner, "ANCHOR_RIGHT")
  local d = DIFF[c.color or ""]
  T:AddLine((d and d[4] or C_WHITE) .. (c.name or "?") .. "|r")
  T:AddLine(self:ProfName(skillLine), 0.7, 0.7, 0.7)
  if c.learned == false then self:LearnLines(c, skillLine) end
  if ly and lg then
    T:AddLine(L.CRAFT_LV_TT_COLORS:format(ls or 1, ly, math.floor((ly + lg) / 2), lg) .. (est and (" (" .. L.CRAFT_LV_EST .. ")") or ""), 0.7, 0.7, 0.7)
  end
  T:AddDoubleLine(L.CRAFT_LV_TT_CHANCE, (d and d[4] or C_WHITE) .. UI.Num((c.chance or 0) * 100) .. "%|r" ..
    ((c.skillUps or 1) > 1 and ("  " .. C_GREY .. L.CRAFT_LV_PER_CRAFT:format(c.skillUps) .. "|r") or ""), 1, 0.82, 0, 1, 1, 1)
  T:AddLine(" ")
  T:AddLine(L.CRAFT_TT_LIST, 1, 0.82, 0)
  if type(c.reagents) == "table" and #c.reagents > 0 then
    for _, r in ipairs(c.reagents) do self:ReagentLines(r) end
  else
    self:RecipeMatLines(c.recipeID, 1)
  end
  T:AddLine(" ")
  if c.cost then
    T:AddDoubleLine(L.CRAFT_TT_COST, Money(c.cost), 1, 0.82, 0, 1, 1, 1)
  else
    T:AddDoubleLine(L.CRAFT_TT_COST, C_ORANGE .. L.CRAFT_MISSING_N:format(MissingCount(c.missing)) .. "|r", 1, 0.82, 0, 1, 1, 1)
  end
  if c.offsetKind and c.offset then
    T:AddDoubleLine(L.CRAFT_LV_TT_OFFSET:format(KindName(c.offsetKind)), "-" .. Money(c.offset), 1, 0.82, 0, 0.3, 1, 0.4)
  else
    T:AddLine(L.CRAFT_LV_TT_NO_OFFSET, 0.55, 0.55, 0.55)
  end
  T:AddDoubleLine(L.CRAFT_LV_TT_NET, CostText(c.net), 1, 0.82, 0, 1, 1, 1)
  T:AddDoubleLine(L.CRAFT_LV_TT_POINT, c.perPoint ~= nil and CostText(c.perPoint, true) or (C_GREY .. "—|r"), 1, 0.82, 0, 1, 1, 1)
  ClickLine(self, kind, { c = c })
  T:Show()
end

function Tab:StepTooltip(owner, s, kind)
  local T = GameTooltip
  local crafts = math.ceil((s.crafts or 0) - 0.001)
  T:SetOwner(owner, "ANCHOR_RIGHT")
  T:AddLine(C_WHITE .. (s.name or "?") .. "|r" .. C_GREY .. "  " .. (s.from or "?") .. "–" .. (s.to or "?") .. "|r")
  if s.learned == false then self:LearnLines(s, self.levelProf) end
  T:AddDoubleLine(L.CRAFT_LV_TT_EXPECTED, UI.Num(s.crafts or 0), 1, 0.82, 0, 1, 1, 1)
  T:AddLine(" ")
  T:AddLine(L.CRAFT_LV_TT_STEP:format(crafts), 1, 0.82, 0)
  self:RecipeMatLines(s.recipeID, crafts)
  T:AddLine(" ")
  if s.cost then T:AddDoubleLine(L.CRAFT_TT_COST, Money(s.cost), 1, 0.82, 0, 1, 1, 1) end
  T:AddDoubleLine(L.CRAFT_LV_TT_TOTAL, CostText(s.net, true), 1, 0.82, 0, 1, 1, 1)
  ClickLine(self, kind, { s = s })
  T:Show()
end

-- best panel in skill-up mode: the whole route's shopping list
function Tab:PlanTooltip(owner, plan, kind)
  local T = GameTooltip
  T:SetOwner(owner, "ANCHOR_RIGHT")
  T:AddLine(L.CRAFT_LV_PLAN_LABEL:format(plan.from or 0, plan.to or 0))
  T:AddLine(" ")
  T:AddLine(L.CRAFT_LV_TT_SHOP:format(plan.to or 0), 1, 0.82, 0)
  for _, m in ipairs(plan.mats or EMPTY) do
    local id, qty = m.itemID or m[1], m.qty or m[2] or 0
    local mc = (type(m.mat) == "table" and m.mat) or MatCost(id, qty) or {}
    self:ReagentLines({ itemID = id, qty = qty, cost = m.cost, unit = m.cost and qty > 0 and m.cost / qty or mc.unit,
                        source = m.source or mc.source, status = mc.status, mat = mc })
  end
  local learn, names, anyGuess = {}, {}, false
  if type(plan.learn) == "table" then
    for k, v in pairs(plan.learn) do
      local rid, at
      if type(v) == "table" then rid, at = v.recipeID or v[1], v.skill or v[2]
        if v.name and rid then names[rid] = v.name end
      elseif type(v) == "number" and type(k) == "number" and k > 1000 then rid, at = k, v
      else rid = v end
      if rid then learn[#learn + 1] = { rid, at } end
    end
  end
  if #learn > 0 then
    table.sort(learn, function(a, b) return (a[2] or 0) < (b[2] or 0) end)
    T:AddLine(" ")
    T:AddLine(L.CRAFT_LV_TT_LEARN, 1, 0.82, 0)
    for _, x in ipairs(learn) do
      local name = names[x[1]]
      if not name then for _, s in ipairs(plan.steps or EMPTY) do if s.recipeID == x[1] then name = s.name break end end end
      name = name or ("#" .. tostring(x[1]))
      local _, cost, g = self:LearnInfo({ recipeID = x[1] }, self.levelProf)
      if g then anyGuess = true end
      T:AddDoubleLine("   " .. (x[2] and L.CRAFT_LV_TT_LEARN_AT:format(name, x[2]) or name),
        cost and Money(cost) or (C_GREY .. L.CRAFT_LV_TT_TRAIN_UNKNOWN .. "|r"), 1, 0.6, 0.2, 1, 1, 1)
    end
    if anyGuess then T:AddLine(L.CRAFT_LV_GUESS, 0.55, 0.55, 0.55, true) end
  end
  T:AddLine(" ")
  local note = self:PlanNote(plan)
  if note then T:AddLine(note, 1, 0.6, 0.2, true) end
  if plan.matCost then T:AddDoubleLine(L.CRAFT_TT_COST, Money(plan.matCost), 1, 0.82, 0, 1, 1, 1) end
  if plan.offset and plan.offset > 0 then T:AddDoubleLine(L.CRAFT_LV_TT_VALUE, "-" .. Money(plan.offset), 1, 0.82, 0, 0.3, 1, 0.4) end
  if plan.learnCost or (plan.learnCostUnknown or 0) > 0 then
    T:AddDoubleLine(L.CRAFT_LV_TT_TRAIN, Money(plan.learnCost or 0) ..
      (((plan.learnCostUnknown or 0) > 0) and (" " .. C_GREY .. "+?|r") or ""), 1, 0.82, 0, 1, 1, 1)
  end
  T:AddDoubleLine(L.CRAFT_LV_TT_TOTAL, CostText(self:PlanTotal(plan), true), 1, 0.82, 0, 1, 1, 1)
  ClickLine(self, kind, { plan = plan })
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
