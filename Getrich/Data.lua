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
  -- Artisan crates (level 35)
  [13464] = { "Golden Sansam", "黄金参" },
  [8838]  = { "Sungrass", "太阳草" },
  [8839]  = { "Blindweed", "盲目草" },
  [8845]  = { "Ghost Mushroom", "幽灵菇" },
  [8846]  = { "Gromsblood", "格罗姆之血" },
  [13463] = { "Dreamfoil", "梦叶草" },
  [13465] = { "Mountain Silversage", "山鼠草" },
  [13466] = { "Plaguebloom", "瘟疫花" },
  [13467] = { "Icecap", "冰盖草" },
  [7911]  = { "Truesilver Ore", "真银矿石" },
  [10620] = { "Thorium Ore", "瑟银矿石" },
  [11370] = { "Dark Iron Ore", "黑铁矿石" },
  [14047] = { "Runecloth", "符文布" },
  [4304]  = { "Thick Leather", "厚皮" },
  [8170]  = { "Rugged Leather", "硬甲皮" },
  [11176] = { "Dream Dust", "梦境之尘" },
  [11175] = { "Greater Nether Essence", "强效虚空精华" },
  [14343] = { "Small Brilliant Shard", "小块魔光碎片" },
  [14344] = { "Large Brilliant Shard", "大块魔光碎片" },
  [14048] = { "Bolt of Runecloth", "符文布卷" },
  [8172]  = { "Cured Thick Hide", "熟化厚毛皮" },
  [11371] = { "Dark Iron Bar", "黑铁锭" },
  [6037]  = { "Truesilver Bar", "真银锭" },
  [12359] = { "Thorium Bar", "瑟银锭" },
  [15994] = { "Thorium Widget", "瑟银零件" },
  [18631] = { "Truesilver Transformer", "真银变压器" },
  [16000] = { "Thorium Tube", "瑟银管" },
}

local L = WC.L
-- stack: the bundle is more than one stack (ItemSparse.Stackable is 20 for all five such materials)
WC.NOTES = { stack = L.NOTE_STACK }

-- The 30 labelled Waylaid Crates of the live game (level cap 60): Apprentice / Journeyman (level 10), Expert (20),
-- Artisan (35). Checked on 2026-11-15 against the live client, build 1.60.1.70938 (tools/verify_game_data.py):
--   opts   = fill with ONE of these bundles: { itemID, quantity, noteKey }. Bundles and their order are the item's own
--            tooltip ("Fill the crate with any bundle from the following list"), quantities also the client's
--            SpellEffect rows of each crate's "Stock Crate" spell; lvl = ItemSparse.RequiredLevel.
--   favor  = Merchant's Favor for the sealed crate. Wowhead quest "A Sealed Crate": 5 / 10 / 15 (white, raw
--            materials: quests 91899-91901), 10 / 20 / 30 (green, crafted goods: quests 91904-91906).
--            Artisan (quests 91902 / 91907): no source has the reward yet (Wowhead has none, the guides say
--            "unconfirmed"), so 20 / 40 continues the pattern and is marked unconfirmed = true. Core.lua records the
--            real reward the first time such a crate is turned in (GetrichDB.crateObs) and uses that from then on.
--   silver = money on turn-in, in copper: 50 copper per Favor in the beta guides (wow-professions.com and others).
--            Wowhead lists no money for these quests, so this too is replaced by what the game really pays.
WC.CRATES = {
  { id = 248684, en = "Apprentice Textiles",    cn = "学徒·纺织",       tier = 1, lvl = 10, crafted = false, favor = 5,  silver = 250,
    opts = { { 2589, 40, "stack" }, { 2318, 20 } } },
  { id = 248683, en = "Apprentice Ore",         cn = "学徒·矿石",       tier = 1, lvl = 10, crafted = false, favor = 5,  silver = 250,
    opts = { { 2770, 20 }, { 2771, 20 } } },
  { id = 248682, en = "Apprentice Herbs",       cn = "学徒·草药",       tier = 1, lvl = 10, crafted = false, favor = 5,  silver = 250,
    opts = { { 2447, 20 }, { 765, 20 }, { 2449, 10 }, { 785, 10 }, { 2450, 10 } } },
  { id = 248685, en = "Apprentice Curiosities", cn = "学徒·奇物",       tier = 1, lvl = 10, crafted = false, favor = 5,  silver = 250,
    opts = { { 10940, 20 }, { 10939, 4 }, { 10978, 6 }, { 11084, 2 } } },
  { id = 248702, en = "Apprentice Fabrics",     cn = "学徒·布皮成品",   tier = 1, lvl = 10, crafted = true,  favor = 10, silver = 500,
    opts = { { 4231, 2 }, { 2996, 20 } } },
  { id = 248703, en = "Apprentice Ingots",      cn = "学徒·金属锭",     tier = 1, lvl = 10, crafted = true,  favor = 10, silver = 500,
    opts = { { 2840, 20 }, { 3576, 20 }, { 2841, 10 } } },
  { id = 248704, en = "Apprentice Parts",       cn = "学徒·工程零件",   tier = 1, lvl = 10, crafted = true,  favor = 10, silver = 500,
    opts = { { 4359, 16 }, { 4361, 16 }, { 4363, 4 } } },

  { id = 248688, en = "Journeyman Textiles",    cn = "熟练·纺织",       tier = 2, lvl = 10, crafted = false, favor = 10, silver = 500,
    opts = { { 2592, 20 }, { 4306, 40, "stack" }, { 2319, 20 } } },
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
    opts = { { 4371, 8 }, { 4375, 7 }, { 4382, 4 }, { 10558, 45, "stack" } } },

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

  { id = 248698, en = "Artisan Textiles",        cn = "工匠·纺织",       tier = 4, lvl = 35, crafted = false, favor = 20, silver = 1000, unconfirmed = true,
    opts = { { 14047, 40, "stack" }, { 4304, 20 }, { 8170, 20 } } },
  { id = 248697, en = "Artisan Ore",             cn = "工匠·矿石",       tier = 4, lvl = 35, crafted = false, favor = 20, silver = 1000, unconfirmed = true,
    opts = { { 7911, 10 }, { 10620, 20 }, { 11370, 20 } } },
  { id = 248695, en = "Earthly Artisan Herbs",   cn = "工匠·草药（大地）", tier = 4, lvl = 35, crafted = false, favor = 20, silver = 1000, unconfirmed = true,
    opts = { { 13464, 10 }, { 8838, 20 }, { 8839, 10 }, { 8845, 10 }, { 8846, 10 } } },
  { id = 248696, en = "Flowering Artisan Herbs", cn = "工匠·草药（花卉）", tier = 4, lvl = 35, crafted = false, favor = 20, silver = 1000, unconfirmed = true,
    opts = { { 13463, 20 }, { 13465, 20 }, { 13466, 20 }, { 13467, 20 } } },
  { id = 248699, en = "Artisan Curiosities",     cn = "工匠·奇物",       tier = 4, lvl = 35, crafted = false, favor = 20, silver = 1000, unconfirmed = true,
    opts = { { 11176, 20 }, { 11175, 4 }, { 14343, 6 }, { 14344, 2 } } },
  { id = 248711, en = "Artisan Fabrics",         cn = "工匠·布皮成品",   tier = 4, lvl = 35, crafted = true,  favor = 40, silver = 2000, unconfirmed = true,
    opts = { { 14048, 8 }, { 8172, 2 } } },
  { id = 248712, en = "Artisan Ingots",          cn = "工匠·金属锭",     tier = 4, lvl = 35, crafted = true,  favor = 40, silver = 2000, unconfirmed = true,
    opts = { { 11371, 2 }, { 6037, 10 }, { 12359, 20 } } },
  { id = 248713, en = "Artisan Parts",           cn = "工匠·工程零件",   tier = 4, lvl = 35, crafted = true,  favor = 40, silver = 2000, unconfirmed = true,
    opts = { { 15994, 5 }, { 18631, 5 }, { 16000, 2 } } },
}

-- "A Sealed Crate" turn-in quest of each sealed crate, by quality and tier (Wowhead, WoW Forever, 2026-11-15).
-- Quests 91903 / 91908 would be the Elite tier: the client has Sealed Elite Crates but no Elite Waylaid Crate yet.
WC.SEALED_QUESTS = {
  white = { 91899, 91900, 91901, 91902 },   -- raw materials
  green = { 91904, 91905, 91906, 91907 },   -- crafted goods
}
WC.FAVOR_CURRENCY = 3402                     -- Merchant's Favor (client table CurrencyTypes)

WC.TIER_NAME = L.TIER

-- crate names as fallback (full item name, used for Auction House searches)
for _, c in ipairs(WC.CRATES) do
  WC.ITEMS[c.id] = WC.ITEMS[c.id] or { "Waylaid Crate: " .. c.en, c.cn }
end

-- Reputation (Durotar Supply and Logistics / Azeroth Commerce Authority). Checked on Wowhead (WoW Forever) on
-- 2026-11-15; the faction page lists exactly these reputation sources: the 150 writs, Crate Return, Shipping Label.
--   filled crate turn-in ("A Sealed Crate") ... 0 reputation, only Merchant's Favor
--   empty crate + Forged Delivery Receipt (item 262902, 15 Favor from the Uncertified Scribe) = quest 93862
--     "Crate Return" ... +50 reputation. The guides say the scribe needs Friendly; Wowhead shows no requirement.
--   first crate ever (quest "Shipping Label" 98247 / 98248, one time) ... 2000 reputation + 50 Favor
-- Bonuses (client spell data, build 1.60.1.70938): Legacy "Diplomat" +2% reputation per rank, 10% at rank 5 (spell
-- 1225485); Legacy "Performance Bonus" 5 / 10 / 15% chance of +100% Favor per crate (spell 1225456).
-- Human "Diplomacy" (+10%, spell 20599) is not in the Forever client, but the addon still checks the spell in case
-- it comes back.
WC.REP = {
  fill = 0,
  empty = 50,
  receiptFavor = 15,
  labelRep = 2000,
  labelFavor = 50,
}
WC.DIPLOMACY_SPELL = 20599
WC.FACTION_IDS = { Alliance = 2586, Horde = 2587 }   -- Azeroth Commerce Authority / Durotar Supply and Logistics (Wowhead)
