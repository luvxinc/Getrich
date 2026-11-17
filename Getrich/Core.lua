local addonName, WC = ...

-- Start-up, Auction House open/close, slash commands, and the Crates / Writs calculations.
-- Settings, saved prices and price lookups (WC:DB, WC:CostFor, ...) live in Store.lua;
-- the window and its tabs in UI.lua; WC:Tab() is defined in UI.lua (it needs the tab registry).

WC.ahOpen = false

-- Store.lua normally provides this; keep the crate / writ math working if it failed to load
if not WC.DB then
  function WC:DB() return GetrichDB or {} end
end

function WC:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffd4a017Getrich|r: " .. tostring(msg))
end

-- Item names come from the game client, so they are in the player's language.
-- Until the client has cached an item, fall back to the built-in English / Chinese name.
local function ClientName(itemID)
  if C_Item and C_Item.GetItemNameByID then
    local name = C_Item.GetItemNameByID(itemID)
    if name and name ~= "" then return name end
  end
end

function WC:ItemName(itemID)
  local name = ClientName(itemID)
  if name then return name end
  local d = WC.ITEMS[itemID]
  if not d then return "item:" .. tostring(itemID) end
  return WC.USE_CN_FALLBACK and d[2] or d[1]
end

-- Name after the "Waylaid Crate:" / "Craftsman's Writ:" prefix.
local function AfterColon(name)
  local p = name:find(": ", 1, true)
  if p then return name:sub(p + 2) end
  p = name:find("：", 1, true)
  if p then return name:sub(p + 3) end
  return name
end

function WC:WritTitle(w)
  local name = ClientName(w.writ)
  if name then return AfterColon(name) end
  return w.en
end

function WC:CrateShortName(crate)
  local name = ClientName(crate.id)
  if not name then return WC.USE_CN_FALLBACK and crate.cn or crate.en end
  return AfterColon(name)
end

-- ---------------------------------------------------------------------------
-- bonuses

-- Human "Diplomacy" (+10% reputation): not in Forever's racial list, but check the spell anyway.
function WC:HasDiplomacy()
  local ok, known = pcall(function()
    if IsPlayerSpell then return IsPlayerSpell(WC.DIPLOMACY_SPELL) end
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(WC.DIPLOMACY_SPELL) end
    return false
  end)
  return (ok and known) and true or false
end

-- reputation bonus as a fraction: Legacy Diplomat 2% per rank (+ racial if present)
function WC:RepBonus()
  local b = 0.02 * (tonumber(WC:DB().diplomatRank) or 0)
  if WC:HasDiplomacy() then b = b + 0.10 end
  return b
end

-- expected Merchant's Favor bonus: Legacy Performance Bonus 5% chance per rank of +100%
function WC:FavorBonus()
  return 0.05 * (tonumber(WC:DB().perfRank) or 0)
end

-- current standing with the crate faction, if the client exposes it
function WC:Standing()
  local id = WC.FACTION_IDS[UnitFactionGroup and UnitFactionGroup("player") or ""]
  if not id then return nil end
  local ok, name, reaction = pcall(function()
    if C_Reputation and C_Reputation.GetFactionDataByID then
      local d = C_Reputation.GetFactionDataByID(id)
      if d then return d.name, d.reaction end
    elseif GetFactionInfoByID then
      local n, _, standingID = GetFactionInfoByID(id)
      return n, standingID
    end
  end)
  if ok and name and reaction then return name, reaction end
  return nil
end

-- has this writ been turned in today? (writs are once a day)
function WC:WritDoneToday(questID)
  local ok, done = pcall(function()
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(questID) end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(questID) end
    return false
  end)
  return (ok and done) and true or false
end

-- ---------------------------------------------------------------------------
-- crate rewards: built-in values, corrected by what the game really paid

-- the "A Sealed Crate" quest a filled crate is handed in with
function WC:SealedQuest(crate)
  local list = WC.SEALED_QUESTS and WC.SEALED_QUESTS[crate.crafted and "green" or "white"]
  return list and list[crate.tier]
end

-- Favor, money (copper) and where the Favor number comes from:
--   "seen"  recorded from the player's own turn-ins (GetrichDB.crateObs)
--   "data"  the built-in value, confirmed by Wowhead
--   "guess" the built-in value of a crate nobody has published a reward for yet (crate.unconfirmed)
-- A recorded Favor replaces a confirmed built-in value only when it is lower or was seen 3 times: a single
-- turn-in can be a Performance Bonus double, which must not be taken for the base reward.
function WC:CrateReward(crate)
  local favor, silver, state = crate.favor, crate.silver, crate.unconfirmed and "guess" or "data"
  local obs = WC:DB().crateObs
  local o = type(obs) == "table" and obs[WC:SealedQuest(crate) or 0]
  if type(o) == "table" then
    if type(o.money) == "number" and o.money >= 0 then silver = o.money end
    local seen
    if type(o.f) == "table" then
      for _, v in ipairs(o.f) do
        if type(v) == "number" and v > 0 and (not seen or v < seen) then seen = v end
      end
    end
    if seen and (state == "guess" or seen < favor or (o.n or 0) >= 3) then favor, state = seen, "seen" end
  end
  return favor, silver, state, type(o) == "table" and o.n or 0
end

-- A sealed crate was handed in: remember the Favor and the money it paid. QUEST_TURNED_IN carries the money,
-- CURRENCY_DISPLAY_UPDATE the Favor gained; the two arrive within a moment of each other, in either order.
local lastGain, lastTurnIn
local function MatchCrateReward()
  if not (lastGain and lastTurnIn) or math.abs(lastGain.t - lastTurnIn.t) > 3 then return end
  local db = GetrichDB
  if type(db) == "table" then
    if type(db.crateObs) ~= "table" then db.crateObs = {} end
    local o = db.crateObs[lastTurnIn.quest]
    if type(o) ~= "table" then o = {}; db.crateObs[lastTurnIn.quest] = o end
    if type(o.f) ~= "table" then o.f = {} end
    o.n = (tonumber(o.n) or 0) + 1
    o.f[#o.f + 1] = lastGain.amount
    while #o.f > 5 do table.remove(o.f, 1) end
    o.money = lastTurnIn.money
  end
  lastGain, lastTurnIn = nil, nil
end

local sealedQuestSet
local function IsSealedQuest(questID)
  if not sealedQuestSet then
    sealedQuestSet = {}
    for _, list in pairs(WC.SEALED_QUESTS or {}) do
      for _, q in ipairs(list) do sealedQuestSet[q] = true end
    end
  end
  return sealedQuestSet[questID] or false
end

function WC:OnQuestTurnedIn(questID, _, money)
  if type(questID) ~= "number" or not IsSealedQuest(questID) then return end
  lastTurnIn = { quest = questID, money = type(money) == "number" and money or 0, t = GetTime() }
  MatchCrateReward()
end

function WC:OnCurrencyUpdate(currencyID, _, change)
  if currencyID ~= WC.FAVOR_CURRENCY or type(change) ~= "number" or change <= 0 then return end
  lastGain = { amount = change, t = GetTime() }
  MatchCrateReward()
end

local function ByScore(a, b)
  if a.score and b.score then
    if a.score ~= b.score then return a.score < b.score end
    return a.key < b.key
  end
  if a.score then return true end
  if b.score then return false end
  if a.group ~= b.group then return a.group < b.group end
  return a.key < b.key
end

-- ---------------------------------------------------------------------------
-- crates: cost per Merchant's Favor

-- For each crate the cheapest bundle the AH can fully supply is picked automatically.
-- Prices are the exact order book of a targeted search where there is one, else an estimate (WC:CostBest): e.crateEst,
-- opt.est and e.est (crate or chosen bundle estimated) say which numbers are estimates.
function WC:EvaluateCrates()
  local level = UnitLevel("player") or 0
  local favorMult = 1 + WC:FavorBonus()
  local list = {}
  for _, crate in ipairs(WC.CRATES) do
    local e = { crate = crate, opts = {}, locked = level < crate.lvl, key = crate.id, group = crate.tier }
    local crateCost, crateStatus, _, crateEst = WC:CostBest(crate.id, 1)
    e.crateCost, e.crateStatus, e.crateEst = crateCost, crateStatus, crateEst
    e.favor, e.silver, e.rewardState, e.rewardSeen = WC:CrateReward(crate)
    e.favorExp = e.favor * favorMult
    local anyListed = false
    for j, opt in ipairs(crate.opts) do
      local cost, status, res, est = WC:CostBest(opt[1], opt[2])
      if status then e.matsScanned = true end
      if status == "ok" or status == "short" then anyListed = true end
      e.opts[j] = { itemID = opt[1], qty = opt[2], note = opt[3], cost = cost, status = status, res = res, est = est }
      if cost and (not e.matCost or cost < e.matCost) then
        e.matCost = cost
        e.bestIdx = j
      end
    end
    if e.crateCost and e.matCost then
      e.net = e.crateCost + e.matCost - e.silver
      e.perFavor = math.max(e.net, 0) / e.favorExp
      e.status = "ok"
      e.est = (e.crateEst or e.opts[e.bestIdx].est) and true or false
    elseif not crateStatus and not e.matsScanned then
      e.status = "unscanned"
    elseif not e.crateCost then
      e.status = "nocrate"
    elseif anyListed then
      e.status = "short"     -- materials listed, but not enough of any bundle
    else
      e.status = "nomats"
    end
    e.score = e.perFavor
    list[#list + 1] = e
  end
  table.sort(list, ByScore)
  return list
end

function WC:VisibleCrates(list)
  local db = WC:DB()
  local out, rank = {}, 0
  for _, e in ipairs(list) do
    local show = true
    if db.onlyMine and e.locked then show = false end
    -- crate was scanned but can't be bought
    if db.hideNoCrate and e.crateStatus and not e.crateCost then show = false end
    -- materials were scanned but no bundle can be fully bought
    if db.hideNoMats and e.matsScanned and not e.matCost then show = false end
    if show then
      if e.score then rank = rank + 1; e.rank = rank else e.rank = nil end
      out[#out + 1] = e
    end
  end
  return out
end

-- cheapest Merchant's Favor you can make right now (crates you can open first); second value: it is an estimate
function WC:BestPerFavor()
  local best, bestAny, bestEst, anyEst
  for _, e in ipairs(WC:EvaluateCrates()) do
    if e.perFavor and e.rewardState ~= "guess" then      -- a guessed reward must not price anything else
      if not bestAny or e.perFavor < bestAny then bestAny, anyEst = e.perFavor, e.est end
      if not e.locked and (not best or e.perFavor < best) then best, bestEst = e.perFavor, e.est end
    end
  end
  if best then return best, bestEst and true or false end
  return bestAny, anyEst and true or false
end

-- ---------------------------------------------------------------------------
-- reputation: Craftsman's Writs (+ empty crate with a receipt)

function WC:EvaluateWrits()
  local repMult = 1 + WC:RepBonus()
  local list = {}
  for i, w in ipairs(WC.WRITS) do
    local e = { writ = w, key = i, group = -w.rep }
    e.writCost, e.writStatus, e.writRes, e.writEst = WC:CostBest(w.writ, 1)
    e.itemCost, e.itemStatus, e.itemRes, e.itemEst = WC:CostBest(w.item, w.qty)
    e.repGain = w.rep * repMult
    e.done = WC:WritDoneToday(w.quest)
    if e.writCost and e.itemCost then
      e.cost = e.writCost + e.itemCost
      e.perRep = e.cost / e.repGain
      e.status = "ok"
      e.est = (e.writEst or e.itemEst) and true or false
    elseif not e.writStatus then
      -- The writ itself has not been searched yet. Its requested item can already have a price from another scan
      -- (Unstable Trigger and Truesilver Transformer are crate materials too): that does not make it "not for sale".
      e.status = "unscanned"
    elseif not e.writCost then
      e.status = "nowrit"
    elseif e.itemStatus == "short" then
      e.status = "short"
    elseif e.itemStatus then
      e.status = "noitem"
    else
      e.status = "itemunscanned"
    end
    e.score = e.perRep
    list[#list + 1] = e
  end

  -- Empty crate + Forged Delivery Receipt (15 Favor, needs Friendly): +50 reputation.
  -- Uses the cheapest crate on the AH and values the 15 Favor at your cheapest Favor price.
  local cheapest, cheapestCrate, cheapestEst
  for _, c in ipairs(WC.CRATES) do
    local cost, _, _, est = WC:CostBest(c.id, 1)
    if cost and (not cheapest or cost < cheapest) then cheapest, cheapestCrate, cheapestEst = cost, c, est end
  end
  if cheapest then
    local perFavor, favorEst = WC:BestPerFavor()
    local e = { receipt = true, crate = cheapestCrate, key = 0, group = 0, status = "ok" }
    e.writEst, e.itemEst = cheapestEst, perFavor and favorEst or false
    e.est = (e.writEst or e.itemEst) and true or false
    e.writCost = cheapest                                   -- shown in the "writ" price column
    e.itemCost = perFavor and WC.REP.receiptFavor * perFavor or nil
    e.cost = cheapest + (e.itemCost or 0)
    e.repGain = WC.REP.empty * repMult
    e.perRep = e.cost / e.repGain
    e.score = e.perRep
    list[#list + 1] = e
  end

  table.sort(list, ByScore)
  return list
end

function WC:VisibleWrits(list)
  local db = WC:DB()
  local out, rank = {}, 0
  for _, e in ipairs(list) do
    local show = true
    if not e.receipt then
      if db.hideNoWrit and e.writStatus and not e.writCost then show = false end
      if db.hideNoItem and e.itemStatus and not e.itemCost then show = false end
      if db.hideDone and e.done then show = false end
    end
    if show then
      if e.score then rank = rank + 1; e.rank = rank else e.rank = nil end
      out[#out + 1] = e
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- events (the Scanner registers its own Auction House result events)

local frame = CreateFrame("Frame")

local function SafeRegister(event)
  pcall(frame.RegisterEvent, frame, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_LOGIN")
SafeRegister("AUCTION_HOUSE_SHOW")
SafeRegister("AUCTION_HOUSE_CLOSED")
SafeRegister("PLAYER_LEVEL_UP")
SafeRegister("QUEST_TURNED_IN")
SafeRegister("UPDATE_FACTION")
SafeRegister("CURRENCY_DISPLAY_UPDATE")

WC.AddLocale({
  enUS = {
    CORE_NO_ERRORS = "No errors recorded.",
    CORE_NEUTRAL_AH = "Neutral Auction House: its prices are kept apart from your faction's, and sales are costed with the 15% cut.",
  },
  zhCN = {
    CORE_NO_ERRORS = "没有记录到错误。",
    CORE_NEUTRAL_AH = "当前是中立拍卖行：价格和本阵营拍卖行分开记录，卖出手续费按 15% 计算。",
  },
  zhTW = {
    CORE_NO_ERRORS = "沒有記錄到錯誤。",
    CORE_NEUTRAL_AH = "目前是中立拍賣場：價格和本陣營拍賣場分開記錄，賣出手續費按 15% 計算。",
  },
})

local function ReportError(where, err)
  if WC.UI and WC.UI.Report then WC.UI.Report(where, err) else WC:Print(tostring(where) .. ": " .. tostring(err)) end
end

-- warm the item cache so crate / writ names show in the client's language
local function WarmItemCache()
  if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
  for itemID in pairs(WC.ITEMS) do pcall(C_Item.RequestLoadItemDataByID, itemID) end
  for _, w in ipairs(WC.WRITS) do
    pcall(C_Item.RequestLoadItemDataByID, w.writ)
    pcall(C_Item.RequestLoadItemDataByID, w.item)
  end
end

-- Is the open Auction House a neutral one? The auctioneer ("npc" while the window is open) then belongs to neither
-- faction group. Anything unclear counts as the player's own faction house, which is what the addon assumed before.
local function AtNeutralAuctionHouse()
  local ok, neutral = pcall(function()
    if not (UnitExists and UnitExists("npc")) or (UnitIsPlayer and UnitIsPlayer("npc")) then return false end
    local f = UnitFactionGroup("npc")
    if issecretvalue and issecretvalue(f) then return false end
    return f ~= "Alliance" and f ~= "Horde"
  end)
  return ok and neutral == true
end

-- load the price tables of the Auction House in use (Store:UseMarket)
local function UseMarket(neutral)
  WC.neutralAH = neutral and true or false
  if WC.External and WC.External.Invalidate then WC.External:Invalidate() end   -- Auctionator scans are per house
  local S = WC.Store
  if not (S and S.UseMarket and S.MarketKey) then return end
  local ok, err = pcall(function() S:UseMarket(S:MarketKey(neutral)) end)
  if not ok then ReportError("Store:UseMarket", err) end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    if WC.Store and WC.Store.Init then
      local ok, err = pcall(WC.Store.Init, WC.Store)
      if not ok then ReportError("Store:Init", err) end
    else
      GetrichDB = GetrichDB or {}
      WC:Fire("DB_READY")
    end
  elseif event == "PLAYER_LOGIN" then
    UseMarket(false)
    WarmItemCache()
    WC.UI:Create()
  elseif event == "AUCTION_HOUSE_SHOW" then
    WC.ahOpen = true
    local neutral = AtNeutralAuctionHouse()
    UseMarket(neutral)
    if neutral then WC:Print(WC.L.CORE_NEUTRAL_AH) end
    WC.UI:ShowAtAuctionHouse()      -- nothing is searched until the player presses the check button
  elseif event == "AUCTION_HOUSE_CLOSED" then
    WC.ahOpen = false
    if WC.Scanner then WC.Scanner:Stop(WC.L.STOP_AH_CLOSED) end
    if WC.neutralAH then UseMarket(false) end      -- away from the auctioneer, show the faction house again
    WC.UI:OnAuctionHouseClosed()
  elseif event == "CURRENCY_DISPLAY_UPDATE" then
    local ok, err = pcall(WC.OnCurrencyUpdate, WC, ...)
    if not ok then ReportError("crate reward", err) end
  elseif event == "PLAYER_LEVEL_UP" or event == "QUEST_TURNED_IN" or event == "UPDATE_FACTION" then
    if event == "QUEST_TURNED_IN" then
      local ok, err = pcall(WC.OnQuestTurnedIn, WC, ...)
      if not ok then ReportError("crate reward", err) end
    end
    C_Timer.After(0.5, function() WC.UI:Refresh() end)
  end
end)

-- ---------------------------------------------------------------------------
-- slash commands: /gr  /getrich  (and /wc, the old Waylaid Crate command)
--   /gr            open / close
--   /gr check      check the best entries of the open tab (exact searches); /gr check <tab> opens that tab first
--                  (/gr scan is the same: the name until 2026.11.1)
--   /gr stop       stop the check             /gr <tab>        open that tab
--   /gr settings   the Settings page (also /gr config, /gr options)
--   /gr auc        where the prices are from (Auctionator's last full scan), or what is missing
--   /gr errors     list errors caught inside the addon
-- tabs: crates writs flips craft de history (only the ones that are loaded)

local TAB_ALIASES = {
  crate = "crates", writ = "writs", flip = "flips", crafting = "craft", disenchant = "de",
  prices = "history", price = "history", hist = "history",
}

local function ResolveTab(word)
  word = TAB_ALIASES[word] or word
  if WC.UI.tabSpecs[word] then return word end
end

local function PrintHelp()
  WC:Print(WC.L.UI_HELP:format(table.concat(WC.UI:TabKeys(), ", ")))
end

SLASH_GETRICH1 = "/gr"
SLASH_GETRICH2 = "/getrich"
SLASH_GETRICH3 = "/wc"   -- old Waylaid Crate command, kept as an alias
SlashCmdList.GETRICH = function(msg)
  msg = strtrim(string.lower(msg or ""))
  local cmd, arg = msg:match("^(%S*)%s*(.-)$")
  local UI = WC.UI
  if cmd == "" then
    UI:Toggle()
  elseif cmd == "check" or cmd == "scan" then
    local key = WC:Tab()
    if arg ~= "" then
      key = ResolveTab(arg)
      if not key then
        WC:Print(WC.L.UI_UNKNOWN_TAB_FMT:format(arg))
        PrintHelp()
        return
      end
    end
    UI:Show()
    if key ~= WC:Tab() then UI:SelectTab(key) end
    UI:StartScan(key)
  elseif cmd == "stop" then
    if WC.Scanner then WC.Scanner:Stop(WC.L.STOP_MANUAL) end
  elseif cmd == "settings" or cmd == "config" or cmd == "options" or cmd == "option" then
    if WC.Settings then WC.Settings:Open() end
  elseif cmd == "errors" then
    local list = (UI.errors and #UI.errors > 0) and UI.errors or WC.errors
    if not list or #list == 0 then
      WC:Print(WC.L.CORE_NO_ERRORS)
    else
      for i, e in ipairs(list) do WC:Print(i .. ". " .. e) end
    end
  elseif cmd == "auc" or cmd == "auctionator" then
    if WC.External then WC:Print(WC.External:Describe()) end
  elseif cmd == "help" or cmd == "?" then
    PrintHelp()
  else
    local key = ResolveTab(cmd)
    if key then
      UI:Show()
      UI:SelectTab(key)
    else
      WC:Print(WC.L.UI_UNKNOWN_TAB_FMT:format(cmd))
      PrintHelp()
    end
  end
end
