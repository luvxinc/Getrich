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

WC.AddLocale({
  enUS = {
    CORE_AUTO_SKIPPED = "This tab reads the whole Auction House (1-4 minutes), so it doesn't scan automatically. Click \"Scan Auction House\" when you want it.",
    CORE_NO_ERRORS = "No errors recorded.",
    IDLE_LAST_MANUAL = "Last scan %s · prices may have changed · click \"Scan Auction House\" to refresh",
    IDLE_NEVER_MANUAL = "Not scanned yet · click \"Scan Auction House\" (with the Auction House open)",
  },
  zhCN = {
    CORE_AUTO_SKIPPED = "这一页要翻完整个拍卖行（1-4 分钟），不会自动扫描。需要时点『扫描拍卖行』。",
    CORE_NO_ERRORS = "没有记录到错误。",
    IDLE_LAST_MANUAL = "上次扫描 %s · 价格可能已经变了 · 点『扫描拍卖行』更新",
    IDLE_NEVER_MANUAL = "还没扫描过 · 打开拍卖行后点『扫描拍卖行』",
  },
  zhTW = {
    CORE_AUTO_SKIPPED = "這一頁要翻完整個拍賣場（1-4 分鐘），不會自動掃描。需要時點『掃描拍賣場』。",
    CORE_NO_ERRORS = "沒有記錄到錯誤。",
    IDLE_LAST_MANUAL = "上次掃描 %s · 價格可能已經變了 · 點『掃描拍賣場』更新",
    IDLE_NEVER_MANUAL = "還沒掃描過 · 打開拍賣場後點『掃描拍賣場』",
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
    WarmItemCache()
    WC.UI:Create()
  elseif event == "AUCTION_HOUSE_SHOW" then
    WC.ahOpen = true
    WC.UI:ShowAtAuctionHouse()
    if WC:DB().autoScan then
      C_Timer.After(1.0, function()
        if not (WC.ahOpen and WC.Scanner and not WC.Scanner.active) then return end
        -- Flips / Disenchant read the whole AH page by page (1-4 minutes) and that replaces Blizzard's
        -- own browse list, so they only run when the player asks for them.
        local kind = WC.UI.ScanKindFor and WC.UI:ScanKindFor(WC:Tab()) or WC:Tab()
        if kind == "flips" or kind == "de" then
          WC:Print(WC.L.CORE_AUTO_SKIPPED)
          return
        end
        WC.UI:StartScan(WC:Tab())
      end)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    WC.ahOpen = false
    if WC.Scanner then WC.Scanner:Stop(WC.L.STOP_AH_CLOSED) end
    WC.UI:OnAuctionHouseClosed()
  elseif event == "PLAYER_LEVEL_UP" or event == "QUEST_TURNED_IN" or event == "UPDATE_FACTION" then
    C_Timer.After(0.5, function() WC.UI:Refresh() end)
  end
end)

-- ---------------------------------------------------------------------------
-- slash commands: /gr  /getrich  (and /wc, the old Waylaid Crate command)
--   /gr            open / close
--   /gr scan       scan the open tab          /gr scan <tab>   open that tab and scan it
--   /gr stop       stop the scan              /gr <tab>        open that tab
--   /gr settings   the Settings page (also /gr config, /gr options)
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
  elseif cmd == "scan" then
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
