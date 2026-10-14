local addonName, WC = ...

WC.ahOpen = false

-- version comes from the TOC so it is set in one place
do
  local ok, v = pcall(function()
    if C_AddOns and C_AddOns.GetAddOnMetadata then return C_AddOns.GetAddOnMetadata(addonName, "Version") end
    if GetAddOnMetadata then return GetAddOnMetadata(addonName, "Version") end
  end)
  WC.VERSION = ok and v or nil
end

local RESULTS_FORMAT = 2   -- bump when the saved price format changes

local DEFAULTS = {
  autoScan = true,        -- scan the open tab when the Auction House opens
  tab = "crates",         -- "crates" (Merchant's Favor) or "writs" (reputation)
  -- crates tab
  onlyMine = false,       -- only crates my level can open
  hideNoCrate = true,     -- ignore crates that nobody is selling
  hideNoMats = true,      -- ignore crates whose materials are all out of stock
  perfRank = 0,           -- Legacy Performance Bonus rank (0-3)
  -- reputation tab
  hideNoWrit = true,      -- ignore writs nobody is selling
  hideNoItem = true,      -- ignore writs whose requested item can't be bought
  hideDone = true,        -- ignore writs already turned in today
  diplomatRank = 0,       -- Legacy Diplomat rank (0-5)
}

function WC:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffd4a017Waylaid Crate|r: " .. tostring(msg))
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
  if not d then return "item:" .. itemID end
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

function WC:SaveResults()
  if not WaylaidCrateDB then return end
  WaylaidCrateDB.results = WC.Scanner.results
  WaylaidCrateDB.resultsFormat = RESULTS_FORMAT
  WaylaidCrateDB.scannedAt = WaylaidCrateDB.scannedAt or {}
  if type(WaylaidCrateDB.scannedAt) ~= "table" then WaylaidCrateDB.scannedAt = {} end
  WaylaidCrateDB.scannedAt[WC.Scanner.kind or "crates"] = time()
end

-- ---------------------------------------------------------------------------
-- bonuses

function WC:DB() return WaylaidCrateDB or DEFAULTS end
function WC:Tab() return WC:DB().tab == "writs" and "writs" or "crates" end

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
function WC:EvaluateCrates()
  local level = UnitLevel("player") or 0
  local favorMult = 1 + WC:FavorBonus()
  local list = {}
  for _, crate in ipairs(WC.CRATES) do
    local e = { crate = crate, opts = {}, locked = level < crate.lvl, key = crate.id, group = crate.tier }
    local crateCost, crateStatus = WC:CostFor(crate.id, 1)
    e.crateCost, e.crateStatus = crateCost, crateStatus
    e.favorExp = crate.favor * favorMult
    local anyListed = false
    for j, opt in ipairs(crate.opts) do
      local cost, status, res = WC:CostFor(opt[1], opt[2])
      if status then e.matsScanned = true end
      if status == "ok" or status == "short" then anyListed = true end
      e.opts[j] = { itemID = opt[1], qty = opt[2], note = opt[3], cost = cost, status = status, res = res }
      if cost and (not e.matCost or cost < e.matCost) then
        e.matCost = cost
        e.bestIdx = j
      end
    end
    if e.crateCost and e.matCost then
      e.net = e.crateCost + e.matCost - crate.silver
      e.perFavor = math.max(e.net, 0) / e.favorExp
      e.status = "ok"
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

-- cheapest Merchant's Favor you can make right now (crates you can open first)
function WC:BestPerFavor()
  local best, bestAny
  for _, e in ipairs(WC:EvaluateCrates()) do
    if e.perFavor then
      if not bestAny or e.perFavor < bestAny then bestAny = e.perFavor end
      if not e.locked and (not best or e.perFavor < best) then best = e.perFavor end
    end
  end
  return best or bestAny
end

-- ---------------------------------------------------------------------------
-- reputation: Craftsman's Writs (+ empty crate with a receipt)

function WC:EvaluateWrits()
  local repMult = 1 + WC:RepBonus()
  local list = {}
  for i, w in ipairs(WC.WRITS) do
    local e = { writ = w, key = i, group = -w.rep }
    e.writCost, e.writStatus, e.writRes = WC:CostFor(w.writ, 1)
    e.itemCost, e.itemStatus, e.itemRes = WC:CostFor(w.item, w.qty)
    e.repGain = w.rep * repMult
    e.done = WC:WritDoneToday(w.quest)
    if e.writCost and e.itemCost then
      e.cost = e.writCost + e.itemCost
      e.perRep = e.cost / e.repGain
      e.status = "ok"
    elseif not e.writStatus and not e.itemStatus then
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
  local cheapest, cheapestCrate
  for _, c in ipairs(WC.CRATES) do
    local cost = WC:CostFor(c.id, 1)
    if cost and (not cheapest or cost < cheapest) then cheapest, cheapestCrate = cost, c end
  end
  if cheapest then
    local perFavor = WC:BestPerFavor()
    local e = { receipt = true, crate = cheapestCrate, key = 0, group = 0, status = "ok" }
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
-- events

local frame = CreateFrame("Frame")

local function SafeRegister(event)
  pcall(frame.RegisterEvent, frame, event)
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_LOGIN")
SafeRegister("AUCTION_HOUSE_SHOW")
SafeRegister("AUCTION_HOUSE_CLOSED")
SafeRegister("COMMODITY_SEARCH_RESULTS_UPDATED")
SafeRegister("ITEM_SEARCH_RESULTS_UPDATED")
SafeRegister("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
SafeRegister("PLAYER_LEVEL_UP")
SafeRegister("QUEST_TURNED_IN")
SafeRegister("UPDATE_FACTION")

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= addonName then return end
    WaylaidCrateDB = WaylaidCrateDB or {}
    for k, v in pairs(DEFAULTS) do
      if WaylaidCrateDB[k] == nil then WaylaidCrateDB[k] = v end
    end
    WaylaidCrateDB.mode = nil   -- removed in 1.3.0
    if WaylaidCrateDB.resultsFormat == RESULTS_FORMAT and type(WaylaidCrateDB.results) == "table" then
      WC.Scanner.results = WaylaidCrateDB.results
    else
      WaylaidCrateDB.results, WaylaidCrateDB.scannedAt = nil, nil
    end
  elseif event == "PLAYER_LOGIN" then
    -- warm the item cache so names show in the client's language
    if C_Item and C_Item.RequestLoadItemDataByID then
      for itemID in pairs(WC.ITEMS) do pcall(C_Item.RequestLoadItemDataByID, itemID) end
      for _, w in ipairs(WC.WRITS) do
        pcall(C_Item.RequestLoadItemDataByID, w.writ)
        pcall(C_Item.RequestLoadItemDataByID, w.item)
      end
    end
    WC.UI:Create()
  elseif event == "AUCTION_HOUSE_SHOW" then
    WC.ahOpen = true
    WC.UI:ShowAtAuctionHouse()
    if WaylaidCrateDB and WaylaidCrateDB.autoScan then
      C_Timer.After(1.0, function()
        if WC.ahOpen and not WC.Scanner.active then WC.Scanner:Start(WC:Tab()) end
      end)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    WC.ahOpen = false
    WC.Scanner:Stop(WC.L.STOP_AH_CLOSED)
    WC.UI:OnAuctionHouseClosed()
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    WC.Scanner:OnCommodityResults(...)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    WC.Scanner:OnItemResults(...)
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    WC.Scanner:OnMessageDropped()
  elseif event == "PLAYER_LEVEL_UP" or event == "QUEST_TURNED_IN" or event == "UPDATE_FACTION" then
    C_Timer.After(0.5, function() WC.UI:Refresh() end)
  end
end)

-- ---------------------------------------------------------------------------
-- slash commands: /wc  /waylaid

SLASH_WAYLAIDCRATE1 = "/wc"
SLASH_WAYLAIDCRATE2 = "/waylaid"
SlashCmdList.WAYLAIDCRATE = function(msg)
  msg = strtrim(string.lower(msg or ""))
  if msg == "scan" then
    WC.UI:Show()
    WC.Scanner:Start(WC:Tab())
  elseif msg == "scan writs" or msg == "writs" then
    WC.UI:Show()
    WC.UI:SelectTab("writs")
    WC.Scanner:Start("writs")
  elseif msg == "scan crates" or msg == "crates" then
    WC.UI:Show()
    WC.UI:SelectTab("crates")
    WC.Scanner:Start("crates")
  elseif msg == "stop" then
    WC.Scanner:Stop(WC.L.STOP_MANUAL)
  else
    WC.UI:Toggle()
  end
end
