local addonName, WC = ...

-- UIProfessions.lua: a small profit label on the right of each recipe row in Blizzard's profession window
-- (ProfessionsFrame.CraftingPage.RecipeList), with a short breakdown tooltip on the label, plus skill-up badges
-- ("Lv1".."Lv3") on the 3 learned recipes with the lowest cost per skill point (WC.Leveling:Candidates).
-- Settings (registered with Store:Default): profOverlay (all labels on/off), profLevelMark (badges on/off).
--
-- Verified in the Forever UI source (wow-ui-source, branch forever, 1.60.1.70450):
--   Blizzard_Professions is LoadOnDemand (Blizzard_Professions.toc:3); RecipeList is a ProfessionsRecipeListTemplate
--   with .ScrollBox using a tree list view (Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRecipeList.lua:20).
--   Recipe rows: node:GetData().recipeInfo (category rows carry .categoryInfo instead), template
--   ProfessionsRecipeListRecipeTemplate with .Label, .Count, .LockedIcon (right-anchored when shown), .SkillUps.
--   ScrollUtil.AddInitializedFrameCallback (Blizzard_SharedXML/Shared/Scroll/ScrollUtil.lua:21): registered
--   callbacks are called callback(owner, frame, elementData) (CallbackRegistry.lua: securecallfunction(func, owner, ...)),
--   while ScrollBox:ForEachFrame calls func(frame, elementData) (ScrollBoxListView.lua:150). OnRow handles both.
--
-- Taint: nothing of Blizzard's is changed. The label is our own child frame on the row; it takes mouse motion only
-- (SetMouseClickEnabled(false)), so clicks on it still reach the row. When a long recipe name would run under the
-- label, our frame shows a small dark backdrop behind its text instead of resizing Blizzard's name FontString
-- (Blizzard only resets that width in Init, Blizzard_ProfessionsRecipeList.lua:349-350).

local L = WC.L

WC.AddLocale({
  enUS = {
    PROF_TIP_MATS = "Materials",
    PROF_TIP_NO_PRICE = "No price yet:",
    PROF_TIP_NPC = "Sell to a vendor",
    PROF_TIP_AH = "Sell on the AH (after 5% cut)",
    PROF_TIP_DE = "Disenchant",
    PROF_TIP_NO_BUY = "vendors don't buy it",
    PROF_TIP_BEST = "Best: %s",
    PROF_KIND_npc = "sell to a vendor",
    PROF_KIND_ah = "sell on the AH",
    PROF_KIND_de = "disenchant",
    PROF_TIP_YIELD = "Makes %s per craft",
    PROF_TIP_CASH = "Still to buy (not in bags)",
    PROF_TIP_NEEDS = "Needs: %s",
    PROF_TIP_PARTIAL = "~ some disenchant prices are missing",
    PROF_TIP_EST = "~ some AH prices are from the quick browse (scan Crafting for exact prices)",
    PROF_TIP_MORE = "Shopping list: /gr craft",
    PROF_MARK = "Lv%d",
    PROF_TIP_LEVEL = "Skill-up pick %d: ~%s per skill point (chance %d%%)",
    PROF_TIP_LEVEL_GAIN = "Skill-up pick %d: earns ~%s per skill point (chance %d%%)",
  },
  zhCN = {
    PROF_TIP_MATS = "材料",
    PROF_TIP_NO_PRICE = "还没有价格：",
    PROF_TIP_NPC = "卖给商人",
    PROF_TIP_AH = "拍卖行出售（扣 5% 手续费）",
    PROF_TIP_DE = "分解",
    PROF_TIP_NO_BUY = "商人不收",
    PROF_TIP_BEST = "最佳：%s",
    PROF_KIND_npc = "卖给商人",
    PROF_KIND_ah = "拍卖行出售",
    PROF_KIND_de = "分解",
    PROF_TIP_YIELD = "每次制造 %s 个",
    PROF_TIP_CASH = "还需购买（背包里没有的）",
    PROF_TIP_NEEDS = "需要：%s",
    PROF_TIP_PARTIAL = "~ 部分分解材料没有价格",
    PROF_TIP_EST = "~ 部分拍卖价来自快速浏览（扫描“制造”页可得准确价格）",
    PROF_TIP_MORE = "购物清单：/gr craft",
    PROF_MARK = "升%d",
    PROF_TIP_LEVEL = "冲技能第 %d 选：每点技能约 %s（成功率 %d%%）",
    PROF_TIP_LEVEL_GAIN = "冲技能第 %d 选：每点技能约赚 %s（成功率 %d%%）",
  },
  zhTW = {
    PROF_TIP_MATS = "材料",
    PROF_TIP_NO_PRICE = "還沒有價格：",
    PROF_TIP_NPC = "賣給商人",
    PROF_TIP_AH = "拍賣場出售（扣 5% 手續費）",
    PROF_TIP_DE = "分解",
    PROF_TIP_NO_BUY = "商人不收",
    PROF_TIP_BEST = "最佳：%s",
    PROF_KIND_npc = "賣給商人",
    PROF_KIND_ah = "拍賣場出售",
    PROF_KIND_de = "分解",
    PROF_TIP_YIELD = "每次製造 %s 個",
    PROF_TIP_CASH = "還需購買（背包裡沒有的）",
    PROF_TIP_NEEDS = "需要：%s",
    PROF_TIP_PARTIAL = "~ 部分分解材料沒有價格",
    PROF_TIP_EST = "~ 部分拍賣價來自快速瀏覽（掃描「製造」頁可得準確價格）",
    PROF_TIP_MORE = "購物清單：/gr craft",
    PROF_MARK = "升%d",
    PROF_TIP_LEVEL = "衝技能第 %d 選：每點技能約 %s（成功率 %d%%）",
    PROF_TIP_LEVEL_GAIN = "衝技能第 %d 選：每點技能約賺 %s（成功率 %d%%）",
  },
})

-- settings (defaults registered before DB_READY; the Settings page writes them and fires SETTINGS_CHANGED)
if WC.Store and WC.Store.Default then
  WC.Store:Default("profOverlay", true)
  WC.Store:Default("profLevelMark", true)
end

local Overlay = {}          -- callback owner (must be a table: CallbackRegistry rejects numbers)
WC.ProfOverlay = Overlay
local scrollBox             -- ProfessionsFrame.CraftingPage.RecipeList.ScrollBox once hooked
local refreshToken = 0

local GREEN, GREY = "|cff40ff40", "|cff9d9d9d"
local MARK_COLOR = { orange = "|cffff8040", yellow = "|cffffff00", green = "|cff40c040" }

-- compact money for the label: "1g 5s", "12s 30c", "8c"
local function Short(copper)
  local c = math.floor(math.abs(copper) + 0.5)
  local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
  if g > 0 then return s > 0 and (g .. L.G .. " " .. s .. L.S) or (g .. L.G) end
  if s > 0 then return cp > 0 and (s .. L.S .. " " .. cp .. L.C) or (s .. L.S) end
  return cp .. L.C
end

local function Money(copper)
  if WC.Money then return WC.Money(copper) end
  if copper == nil then return "-" end
  return (copper < 0 and "-" or "") .. Short(copper)
end

-- whole copper (profits are often fractional: yields like 1.5, unit prices like 0.05c)
local function Round(copper) return math.floor(copper + 0.5) end

local function Signed(copper)
  if copper == nil then return "" end
  copper = Round(copper)
  if copper > 0 then return GREEN .. "+" .. Short(copper) .. "|r" end
  if copper < 0 then return "|cffff5050-" .. Short(copper) .. "|r" end
  return GREY .. "0|r"
end

local function Entry(recipeID)
  local P = WC.Profit
  if type(P) ~= "table" or type(P.CraftEntry) ~= "function" then return nil end
  local ok, e = pcall(P.CraftEntry, P, recipeID)
  if ok and type(e) == "table" then return e end
  return nil
end

local function External()
  return WC.Recipes and WC.Recipes.IsExternal and WC.Recipes:IsExternal() or false
end

local function Setting(key)
  local db = WC:DB()
  return type(db) ~= "table" or db[key] ~= false
end

-- skill-up badges: { [recipeID] = { rank = 1..3, perPoint, chance, color, name } } for the open profession, or nil.
-- Cached; rebuilt after bus messages (marksDirty) or when another profession is opened.
local marks, marksDirty, marksProf = nil, true, nil
local function Marks()
  local R, LV = WC.Recipes, WC.Leveling
  if not Setting("profLevelMark") or type(R) ~= "table" or type(LV) ~= "table" or type(LV.Candidates) ~= "function" then
    return nil
  end
  local prof = R.OpenSkillLine and R:OpenSkillLine()
  if not marksDirty and prof == marksProf then return marks end
  marksDirty, marksProf, marks = false, prof, nil
  if not prof then return nil end
  local rank, max = R:Skill(nil, prof)
  if type(rank) ~= "number" or type(max) ~= "number" or rank >= max then return nil end   -- maxed: nothing to level
  local ok, list = pcall(LV.Candidates, LV, WC:CharKey(), prof, rank)
  if not ok or type(list) ~= "table" then return nil end
  local m, n = {}, 0
  for i = 1, #list do
    local c = list[i]
    if type(c) == "table" and c.learned and c.recipeID and not m[c.recipeID] and type(c.perPoint) == "number"
       and type(c.chance) == "number" and c.chance > 0 then
      n = n + 1
      m[c.recipeID] = { rank = n, perPoint = c.perPoint, chance = c.chance, color = c.color, name = c.name }
      if n >= 3 then break end
    end
  end
  if n > 0 then marks = m end
  return marks
end

local function ItemName(itemID)
  if WC.ItemName then
    local ok, n = pcall(WC.ItemName, WC, itemID)
    if ok and n then return n end
  end
  return (WC.ItemInfo(itemID)) or ("item:" .. tostring(itemID))
end

-- ---------------------------------------------------------------------------
-- tooltip

local function ShowTip(f)
  local e = f.recipeID and Entry(f.recipeID)
  if e and type(e.best) ~= "number" and not f.mark then e = nil end
  local mark = f.mark
  if not e and not mark then return end
  local tt = GameTooltip
  tt:SetOwner(f, "ANCHOR_RIGHT")
  tt:AddLine((e and (e.name or (e.itemID and ItemName(e.itemID)))) or (mark and mark.name) or "?", 1, 1, 1)
  if mark then
    local pct = math.floor(mark.chance * 100 + 0.5)
    if mark.perPoint < 0 then
      tt:AddLine(string.format(L.PROF_TIP_LEVEL_GAIN, mark.rank, Short(mark.perPoint), pct), 1, 0.5, 0.25, true)
    else
      tt:AddLine(string.format(L.PROF_TIP_LEVEL, mark.rank, Short(mark.perPoint), pct), 1, 0.5, 0.25, true)
    end
  end
  if not e then
    tt:Show()
    return
  end
  if e.yield and e.yield ~= 1 then
    tt:AddLine(string.format(L.PROF_TIP_YIELD, (string.format("%.1f", e.yield):gsub("%.0$", ""))), 0.8, 0.8, 0.8)
  end
  tt:AddDoubleLine(L.PROF_TIP_MATS, ((e.est and e.cost) and "~" or "") .. Money(e.cost), 1, 0.82, 0, 1, 1, 1)
  if type(e.missing) == "table" and #e.missing > 0 then
    local names = {}
    for i = 1, math.min(#e.missing, 4) do names[#names + 1] = ItemName(e.missing[i]) end
    if #e.missing > 4 then names[#names + 1] = "..." end
    tt:AddLine(L.PROF_TIP_NO_PRICE .. " " .. table.concat(names, ", "), 1, 0.4, 0.4, true)
  end
  if e.npc ~= nil then
    if e.npc == 0 then tt:AddDoubleLine(L.PROF_TIP_NPC, L.PROF_TIP_NO_BUY, 1, 0.82, 0, 0.6, 0.6, 0.6)
    else tt:AddDoubleLine(L.PROF_TIP_NPC, Money(e.npc) .. "  " .. Signed(e.npcProfit), 1, 0.82, 0, 1, 1, 1) end
  end
  if e.ah ~= nil then
    tt:AddDoubleLine(L.PROF_TIP_AH, Money(e.ah) .. "  " .. Signed(e.ahProfit), 1, 0.82, 0, 1, 1, 1)
  end
  if e.de ~= nil then
    tt:AddDoubleLine(L.PROF_TIP_DE, (e.dePartial and "~" or "") .. Money(e.de) .. "  " .. Signed(e.deProfit), 1, 0.82, 0, 1, 1, 1)
  end
  if e.bestKind and L["PROF_KIND_" .. e.bestKind] then
    tt:AddLine(string.format(L.PROF_TIP_BEST, L["PROF_KIND_" .. e.bestKind]), 0.25, 1, 0.25)
  end
  if e.cash ~= nil and e.cost ~= nil and e.cash ~= e.cost then
    tt:AddDoubleLine(L.PROF_TIP_CASH, Money(e.cash), 0.8, 0.8, 0.8, 1, 1, 1)
  end
  if e.tool then tt:AddLine(string.format(L.PROF_TIP_NEEDS, e.tool), 0.6, 0.6, 0.6, true) end
  if e.est and e.cost then tt:AddLine(L.PROF_TIP_EST, 0.6, 0.6, 0.6, true) end
  if e.dePartial and e.de ~= nil then tt:AddLine(L.PROF_TIP_PARTIAL, 0.6, 0.6, 0.6, true) end
  tt:AddLine(L.PROF_TIP_MORE, 0.5, 0.5, 0.5)
  tt:Show()
end

local function HideTip(f)
  if not GameTooltip.IsOwned or GameTooltip:IsOwned(f) then GameTooltip:Hide() end
end

-- ---------------------------------------------------------------------------
-- row label

local function Label(row)
  local f = row.wcProfit
  if f then return f end
  f = CreateFrame("Frame", nil, row)
  f:SetSize(40, 16)
  if f.SetMouseClickEnabled and f.SetMouseMotionEnabled then
    -- hover for the tooltip, but let clicks fall through to the recipe row
    pcall(f.SetMouseClickEnabled, f, false)
    pcall(f.SetMouseMotionEnabled, f, true)
  end
  local bg = f:CreateTexture(nil, "BACKGROUND")    -- only shown when the recipe name runs under the label
  bg:SetAllPoints(f)
  bg:SetColorTexture(0.05, 0.04, 0.03, 0.9)
  bg:Hide()
  f.bg = bg
  local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("RIGHT", f, "RIGHT", -2, 0)
  text:SetJustifyH("RIGHT")
  f.text = text
  f:SetScript("OnEnter", ShowTip)
  f:SetScript("OnLeave", HideTip)
  row.wcProfit = f
  return f
end

-- would the recipe name (+ craftable count) run under our label? Only reads Blizzard's regions.
-- Unknown geometry -> true (the backdrop is harmless).
local function Overlaps(row, f)
  local name = row.Label
  if not name or not name.GetLeft then return true end
  local rowLeft, nameLeft = row:GetLeft(), name:GetLeft()
  if not rowLeft or not nameLeft then return true end
  local labelLeft = row:GetWidth() - 4 - f:GetWidth()
  if row.LockedIcon and row.LockedIcon:IsShown() then labelLeft = labelLeft - 2 - row.LockedIcon:GetWidth() end
  local count = (row.Count and row.Count:IsShown()) and row.Count:GetStringWidth() or 0
  local nameRight = (nameLeft - rowLeft) + math.min(name:GetWidth(), name:GetStringWidth()) + count
  return nameRight > labelLeft - 2
end

local function UpdateRow(row, node)
  if type(row) ~= "table" then return end
  local data = type(node) == "table" and node.GetData and node:GetData()
  local info = type(data) == "table" and data.recipeInfo
  local f = row.wcProfit
  local id = type(info) == "table" and info.recipeID
  local e, mark
  if id and Setting("profOverlay") and not External() then
    e = Entry(id)
    if e and type(e.best) ~= "number" then e = nil end
    local m = Marks()
    mark = m and m[id]
  end
  if not e and not mark then
    if f then f.recipeID, f.mark = nil, nil; f:Hide() end
    return
  end
  f = Label(row)
  f.recipeID, f.mark = id, mark
  local text = ""
  if mark then text = (MARK_COLOR[mark.color] or MARK_COLOR.orange) .. string.format(L.PROF_MARK, mark.rank) .. "|r" end
  if e then
    local best = Round(e.best)          -- |best| < 0.5c shows a grey "0", never "+0c"
    local p
    if best > 0 then p = GREEN .. "+" .. Short(best) .. "|r"
    elseif best < 0 then p = GREY .. "-" .. Short(best) .. "|r"
    else p = GREY .. "0|r" end
    text = (text ~= "" and (text .. " ") or "") .. p
  end
  f.text:SetText(text)
  f:SetWidth(math.max(16, (f.text:GetStringWidth() or 30) + 6))
  f:ClearAllPoints()
  if row.LockedIcon and row.LockedIcon:IsShown() then f:SetPoint("RIGHT", row.LockedIcon, "LEFT", -2, 0)
  else f:SetPoint("RIGHT", row, "RIGHT", -4, 0) end
  f:Show()
  local ok, over = pcall(Overlaps, row, f)
  f.bg:SetShown(not ok or over)
end

-- both call shapes: (owner, frame, elementData) from the registry, (frame, elementData) from ForEachFrame
local function OnRow(a, b, c)
  local row, node
  if a == Overlay then row, node = b, c else row, node = a, b end
  local ok, err = pcall(UpdateRow, row, node)
  if not ok and WC.Debug then WC.Debug("UIProfessions", err) end
end
Overlay.OnRow = OnRow

function Overlay:Refresh()
  if not scrollBox then return end
  if ProfessionsFrame and ProfessionsFrame.IsShown and not ProfessionsFrame:IsShown() then return end
  pcall(scrollBox.ForEachFrame, scrollBox, OnRow)
end

-- coalesce bursts of bus messages (PRICES_UPDATED can arrive several times a second during a scan)
local function QueueRefresh()
  marksDirty = true
  if not scrollBox then return end
  refreshToken = refreshToken + 1
  local token = refreshToken
  C_Timer.After(0.25, function() if token == refreshToken then Overlay:Refresh() end end)
end

function Overlay:Hook()
  if scrollBox then return true end
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local sb = page and page.RecipeList and page.RecipeList.ScrollBox
  if type(sb) ~= "table" or not (ScrollUtil and ScrollUtil.AddInitializedFrameCallback) then return false end
  -- register for future rows; existing rows are done right after with ForEachFrame (separately, so a
  -- ScrollBox without a view yet can't stop the registration)
  local ok = pcall(ScrollUtil.AddInitializedFrameCallback, sb, OnRow, Overlay, false)
  if not ok then return false end
  scrollBox = sb
  pcall(sb.ForEachFrame, sb, OnRow)
  return true
end

-- ---------------------------------------------------------------------------
-- events

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == "Blizzard_Professions" then Overlay:Hook() end
  elseif event == "PLAYER_LOGIN" then
    if ProfessionsFrame then Overlay:Hook() end
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    if not scrollBox and ProfessionsFrame then Overlay:Hook() end
    QueueRefresh()
  end
end)
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
  pcall(frame.RegisterEvent, frame, e)
end
if ProfessionsFrame then Overlay:Hook() end   -- already loaded by another addon

for _, msg in ipairs({ "PRICES_UPDATED", "RECIPES_UPDATED", "VENDOR_UPDATED", "DE_UPDATED", "SETTINGS_CHANGED" }) do
  WC:On(msg, QueueRefresh)
end
