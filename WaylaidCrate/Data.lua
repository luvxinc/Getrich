local addonName, WC = ...

-- Item names: [itemID] = { English, 中文 }
-- Item IDs from Wowhead (WoW Forever database).
WC.ITEMS = {
  -- cloth / leather
  [2589] = { "Linen Cloth", "亚麻布" },
  [2318] = { "Light Leather", "轻皮" },
  [2592] = { "Wool Cloth", "毛料" },
  [4306] = { "Silk Cloth", "丝绸" },
  [2319] = { "Medium Leather", "中皮" },
  [4338] = { "Mageweave Cloth", "魔纹布" },
  [4234] = { "Heavy Leather", "重皮" },
  -- ore
  [2770] = { "Copper Ore", "铜矿石" },
  [2771] = { "Tin Ore", "锡矿石" },
  [2775] = { "Silver Ore", "银矿石" },
  [2772] = { "Iron Ore", "铁矿石" },
  [2776] = { "Gold Ore", "金矿石" },
  [3858] = { "Mithril Ore", "秘银矿石" },
  -- herbs
  [2447] = { "Peacebloom", "宁神花" },
  [765]  = { "Silverleaf", "银叶草" },
  [2449] = { "Earthroot", "地根草" },
  [785]  = { "Mageroyal", "魔皇草" },
  [2450] = { "Briarthorn", "石南草" },
  [3820] = { "Stranglekelp", "荆棘藻" },
  [2453] = { "Bruiseweed", "跌打草" },
  [3355] = { "Wild Steelbloom", "野钢花" },
  [3369] = { "Grave Moss", "墓地苔" },
  [3356] = { "Kingsblood", "皇血草" },
  [3357] = { "Liferoot", "活根草" },
  [3818] = { "Fadeleaf", "枯叶草" },
  [3821] = { "Goldthorn", "金棘草" },
  [3358] = { "Khadgar's Whisker", "卡德加的胡须" },
  [3819] = { "Wintersbite", "冬刺草" },
  [4625] = { "Firebloom", "火焰花" },
  [8831] = { "Purple Lotus", "紫莲花" },
  [8836] = { "Arthas' Tears", "阿尔萨斯之泪" },
  -- enchanting
  [10940] = { "Strange Dust", "奇异之尘" },
  [10939] = { "Greater Magic Essence", "强效魔法精华" },
  [10978] = { "Small Glimmering Shard", "小块微光碎片" },
  [11084] = { "Large Glimmering Shard", "大块微光碎片" },
  [11083] = { "Soul Dust", "灵魂之尘" },
  [11082] = { "Greater Astral Essence", "强效星界精华" },
  [11138] = { "Small Glowing Shard", "小块闪光碎片" },
  [11139] = { "Large Glowing Shard", "大块闪光碎片" },
  [11137] = { "Vision Dust", "幻象之尘" },
  [11135] = { "Greater Mystic Essence", "强效秘法精华" },
  [11177] = { "Small Radiant Shard", "小块光芒碎片" },
  [11178] = { "Large Radiant Shard", "大块光芒碎片" },
  -- crafted cloth / hides
  [4231] = { "Cured Light Hide", "熟化轻毛皮" },
  [2996] = { "Bolt of Linen Cloth", "亚麻布卷" },
  [2997] = { "Bolt of Woolen Cloth", "毛料卷" },
  [4305] = { "Bolt of Silk Cloth", "丝绸卷" },
  [4233] = { "Cured Medium Hide", "熟化中毛皮" },
  [4339] = { "Bolt of Mageweave", "魔纹布卷" },
  [4236] = { "Cured Heavy Hide", "熟化重毛皮" },
  -- bars
  [2840] = { "Copper Bar", "铜锭" },
  [3576] = { "Tin Bar", "锡锭" },
  [2841] = { "Bronze Bar", "青铜锭" },
  [2842] = { "Silver Bar", "银锭" },
  [3575] = { "Iron Bar", "铁锭" },
  [3860] = { "Mithril Bar", "秘银锭" },
  [3859] = { "Steel Bar", "钢锭" },
  [3577] = { "Gold Bar", "金锭" },
  -- engineering parts
  [4359] = { "Handful of Copper Bolts", "一把铜螺栓" },
  [4361] = { "Copper Tube", "铜管" },
  [4363] = { "Copper Modulator", "铜制调节器" },
  [4371] = { "Bronze Tube", "青铜管" },
  [4375] = { "Whirring Bronze Gizmo", "嗡鸣青铜零件" },
  [4382] = { "Bronze Framework", "青铜框架" },
  [10558] = { "Gold Power Core", "金质能量核心" },
  [4387] = { "Iron Strut", "铁制支架" },
  [10559] = { "Mithril Tube", "秘银管" },
  [10560] = { "Unstable Trigger", "不稳定的触发器" },
  [10561] = { "Mithril Casing", "秘银外壳" },
}

local L = WC.L
WC.NOTES = { stack = L.NOTE_STACK, gme = L.NOTE_GME, wool = L.NOTE_WOOL }

-- Waylaid Crates usable at level 30 or below (Apprentice / Journeyman / Expert).
-- favor  = Merchant's Favor on turn-in (beta data, wow-professions.com)
-- silver = money reward on turn-in, in copper
-- opts   = fill with ONE of these bundles: { itemID, quantity, noteKey }
WC.CRATES = {
  { id = 248684, en = "Apprentice Textiles",    cn = "学徒·纺织",       tier = 1, lvl = 10, crafted = false, favor = 5,  silver = 250,
    opts = { { 2589, 40, "stack" }, { 2318, 20 } } },
  { id = 248683, en = "Apprentice Ore",         cn = "学徒·矿石",       tier = 1, lvl = 10, crafted = false, favor = 5,  silver = 250,
    opts = { { 2770, 20 }, { 2771, 20 } } },
  { id = 248682, en = "Apprentice Herbs",       cn = "学徒·草药",       tier = 1, lvl = 10, crafted = false, favor = 5,  silver = 250,
    opts = { { 2447, 20 }, { 765, 20 }, { 2449, 10 }, { 785, 10 }, { 2450, 10 } } },
  { id = 248685, en = "Apprentice Curiosities", cn = "学徒·奇物",       tier = 1, lvl = 10, crafted = false, favor = 5,  silver = 250,
    opts = { { 10940, 20 }, { 10939, 4, "gme" }, { 10978, 6 }, { 11084, 2 } } },
  { id = 248702, en = "Apprentice Fabrics",     cn = "学徒·布皮成品",   tier = 1, lvl = 10, crafted = true,  favor = 10, silver = 500,
    opts = { { 4231, 2 }, { 2996, 20 } } },
  { id = 248703, en = "Apprentice Ingots",      cn = "学徒·金属锭",     tier = 1, lvl = 10, crafted = true,  favor = 10, silver = 500,
    opts = { { 2840, 20 }, { 3576, 20 }, { 2841, 10 } } },
  { id = 248704, en = "Apprentice Parts",       cn = "学徒·工程零件",   tier = 1, lvl = 10, crafted = true,  favor = 10, silver = 500,
    opts = { { 4359, 16 }, { 4361, 16 }, { 4363, 4 } } },

  { id = 248688, en = "Journeyman Textiles",    cn = "熟练·纺织",       tier = 2, lvl = 10, crafted = false, favor = 10, silver = 500,
    opts = { { 2592, 20, "wool" }, { 4306, 40, "stack" }, { 2319, 20 } } },
  { id = 248687, en = "Journeyman Ore",         cn = "熟练·矿石",       tier = 2, lvl = 10, crafted = false, favor = 10, silver = 500,
    opts = { { 2775, 10 }, { 2772, 20 } } },
  { id = 248686, en = "Journeyman Herbs",       cn = "熟练·草药",       tier = 2, lvl = 10, crafted = false, favor = 10, silver = 500,
    opts = { { 3820, 10 }, { 2453, 10 }, { 3355, 10 }, { 3369, 10 }, { 3356, 10 } } },
  { id = 248689, en = "Journeyman Curiosities", cn = "熟练·奇物",       tier = 2, lvl = 10, crafted = false, favor = 10, silver = 500,
    opts = { { 11083, 20 }, { 11082, 4 }, { 11138, 6 }, { 11139, 2 } } },
  { id = 248705, en = "Journeyman Fabrics",     cn = "熟练·布皮成品",   tier = 2, lvl = 10, crafted = true,  favor = 20, silver = 1000,
    opts = { { 2997, 6 }, { 4305, 10 }, { 4233, 2 } } },
  { id = 248706, en = "Journeyman Ingots",      cn = "熟练·金属锭",     tier = 2, lvl = 10, crafted = true,  favor = 20, silver = 1000,
    opts = { { 2842, 10 }, { 3575, 20 } } },
  { id = 248707, en = "Journeyman Parts",       cn = "熟练·工程零件",   tier = 2, lvl = 10, crafted = true,  favor = 20, silver = 1000,
    opts = { { 4371, 8 }, { 4375, 7 }, { 4382, 4 }, { 10558, 45 } } },

  { id = 248693, en = "Expert Textiles",        cn = "专家·纺织",       tier = 3, lvl = 20, crafted = false, favor = 15, silver = 750,
    opts = { { 4338, 40, "stack" }, { 4234, 20 } } },
  { id = 248692, en = "Expert Ore",             cn = "专家·矿石",       tier = 3, lvl = 20, crafted = false, favor = 15, silver = 750,
    opts = { { 2776, 10 }, { 3858, 20 } } },
  { id = 248690, en = "Earthly Expert Herbs",   cn = "专家·草药（大地）", tier = 3, lvl = 20, crafted = false, favor = 15, silver = 750,
    opts = { { 3357, 20 }, { 3818, 10 }, { 3821, 10 }, { 3358, 10 } } },
  { id = 248691, en = "Flowering Expert Herbs", cn = "专家·草药（花卉）", tier = 3, lvl = 20, crafted = false, favor = 15, silver = 750,
    opts = { { 3819, 10 }, { 4625, 10 }, { 8831, 20 }, { 8836, 10 } } },
  { id = 248694, en = "Expert Curiosities",     cn = "专家·奇物",       tier = 3, lvl = 20, crafted = false, favor = 15, silver = 750,
    opts = { { 11137, 20 }, { 11135, 4 }, { 11177, 6 }, { 11178, 2 } } },
  { id = 248708, en = "Expert Fabrics",         cn = "专家·布皮成品",   tier = 3, lvl = 20, crafted = true,  favor = 30, silver = 1500,
    opts = { { 4339, 8 }, { 4236, 2 } } },
  { id = 248709, en = "Expert Ingots",          cn = "专家·金属锭",     tier = 3, lvl = 20, crafted = true,  favor = 30, silver = 1500,
    opts = { { 3860, 20 }, { 3859, 15 }, { 3577, 10 } } },
  { id = 248710, en = "Expert Parts",           cn = "专家·工程零件",   tier = 3, lvl = 20, crafted = true,  favor = 30, silver = 1500,
    opts = { { 4387, 8 }, { 10559, 5 }, { 10560, 12 }, { 10561, 5 } } },
}

WC.TIER_NAME = L.TIER

-- crate names as fallback (full item name, used for Auction House searches)
for _, c in ipairs(WC.CRATES) do
  WC.ITEMS[c.id] = WC.ITEMS[c.id] or { "Waylaid Crate: " .. c.en, c.cn }
end

-- Reputation (Durotar Supply and Logistics / Azeroth Commerce Authority), WoW Forever beta:
--   filled crate turn-in ............ 0 reputation (only Merchant's Favor)
--   empty crate + Forged Delivery Receipt (bought for 15 Favor, needs Friendly) ... +50 reputation
--   first crate ever (Shipping Label quest, one time) ... 2000 reputation + 50 Favor
-- Bonuses: Legacy "Diplomat" +2/4/6/8/10% reputation; Legacy "Performance Bonus" 5/10/15% chance
-- of +100% Favor per crate. Human "Diplomacy" (+10%) is not in Forever's racial list, but the
-- addon still checks the spell in case it comes back.
WC.REP = {
  fill = 0,
  empty = 50,
  receiptFavor = 15,
  labelRep = 2000,
  labelFavor = 50,
}
WC.DIPLOMACY_SPELL = 20599
WC.FACTION_IDS = { Alliance = 2586, Horde = 2587 }   -- Season of Discovery IDs; checked at run time
