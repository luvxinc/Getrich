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

-- Current standing with the crate faction, if the client exposes it: name, reaction (4 Neutral, 5 Friendly,
-- 6 Honored, 7 Revered, 8 Exalted), reputation earned so far, and where this standing starts and ends.
-- (FactionData fields: Blizzard_APIDocumentationGenerated/ReputationInfoDocumentation.lua; the reputation frame
-- draws its bar from currentReactionThreshold, nextReactionThreshold and currentStanding.)
function WC:Standing()
  local id = WC.FACTION_IDS[UnitFactionGroup and UnitFactionGroup("player") or ""]
  if not id then return nil end
  local ok, name, reaction, value, lo, hi = pcall(function()
    if C_Reputation and C_Reputation.GetFactionDataByID then
      local d = C_Reputation.GetFactionDataByID(id)
      if d then return d.name, d.reaction, d.currentStanding, d.currentReactionThreshold, d.nextReactionThreshold end
    elseif GetFactionInfoByID then
      local n, _, standingID, barMin, barMax, barValue = GetFactionInfoByID(id)
      return n, standingID, barValue, barMin, barMax
    end
  end)
  if ok and name and reaction then return name, reaction, tonumber(value), tonumber(lo), tonumber(hi) end
  return nil
end

local function ServerNow()
  if WC.Store and WC.Store.ServerNow then return WC.Store.ServerNow() end
  return (GetServerTime and GetServerTime()) or time()
end

-- ---------------------------------------------------------------------------
-- writs turned in today
-- Each writ can be handed in once a day. The game flags its quest as completed until the daily reset
-- (C_QuestLog.IsQuestFlaggedCompleted). Getrich also writes down the turn-ins it sees:
--   GetrichDB.writLog[charKey] = { reset = server time of the daily reset that ends this day, done = { [questID] = time } }
-- A writ counts as done today when either says so. The record is dropped once its reset has passed; without the
-- client's reset time (C_DateAndTime.GetSecondsUntilDailyReset) nothing is written down and only the flag counts.

local function NextDailyReset(now)
  local ok, secs = pcall(function()
    return C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset()
  end)
  if ok and type(secs) == "number" and secs > 0 and secs <= 86400 + 3600 then return now + secs end
  return nil
end

-- today's record of this character (create = true: start one); nil when there is none
function WC:WritLog(create)
  local db = GetrichDB
  if type(db) ~= "table" then return nil end
  if type(db.writLog) ~= "table" then
    if not create then return nil end
    db.writLog = {}
  end
  local key = WC:CharKey()
  local now = ServerNow()
  local log = db.writLog[key]
  if log ~= nil and (type(log) ~= "table" or type(log.reset) ~= "number" or type(log.done) ~= "table" or now >= log.reset) then
    db.writLog[key] = nil
    log = nil
  end
  if not log and create then
    local reset = NextDailyReset(now)
    if not reset then return nil end
    log = { reset = reset, done = {} }
    db.writLog[key] = log
  end
  return log
end

local writByQuest
local function WritOfQuest(questID)
  if not writByQuest then
    writByQuest = {}
    for _, w in ipairs(WC.WRITS) do writByQuest[w.quest] = w end
  end
  return writByQuest[questID]
end

-- has this writ been turned in today? (the game's flag, or Getrich's own record of today)
function WC:WritDoneToday(questID)
  local ok, done = pcall(function()
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then return C_QuestLog.IsQuestFlaggedCompleted(questID) end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(questID) end
    return false
  end)
  if ok and done then return true end
  local log = WC:WritLog()
  return (log and log.done[questID]) and true or false
end

-- how many writs were turned in today, and the reputation they gave (with the bonus set now)
function WC:WritsToday()
  local n, rep = 0, 0
  local mult = 1 + WC:RepBonus()
  for _, w in ipairs(WC.WRITS) do
    if WC:WritDoneToday(w.quest) then
      n = n + 1
      rep = rep + w.rep * mult
    end
  end
  return n, rep
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
  if type(questID) ~= "number" then return end
  if WritOfQuest(questID) then           -- a Craftsman's Writ: done for today
    local log = WC:WritLog(true)
    if log then log.done[questID] = ServerNow() end
    return
  end
  if not IsSealedQuest(questID) then return end
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
-- reputation plan: from the reputation the character has to a target standing, for the least money
--
-- What can be handed in today:
--   * every Craftsman's Writ that was not turned in today, once (the writ + the item it asks for). What is already
--     in the bags is not bought: an owned writ costs nothing, and of the requested item only the missing part is
--     priced (WC:CostBest for that quantity: order book if the item was checked, else Auctionator's price).
--   * the empty crate with a Forged Delivery Receipt (needs Friendly), as often as the receipts in the bags and
--     the Merchant's Favor owned allow (15 Favor a receipt). Its cost is the crate (owned crates first, then the
--     cheapest listings) plus the Favor at what it costs to make (WC:BestPerFavor); only the crate is money.
-- All of them give multiples of 25 reputation (75 / 125 / 200 for writs, 50 for a crate return; the bonus
-- multiplies them alike), and within one kind the cheapest come first, so the cheapest combination is found by
-- trying every count of each kind: at most 46 x 61 x 46 combinations, each a sum of four prefix sums.
-- A writ or crate return that costs more per reputation than the cap (repCap, copper; 0 = no cap) is left out.

WC.REP_START = { [5] = 3000, [6] = 9000, [7] = 21000, [8] = 42000 }   -- reputation at which a standing starts
WC.RECEIPT_ITEM = 262902                                                -- Forged Delivery Receipt
local REP_UNIT = 25

-- standings the plan can aim at (above the current one): { reaction, ... }
function WC:RepTargets()
  local _, reaction = WC:Standing()
  local out = {}
  for r = math.max(5, (tonumber(reaction) or 4) + 1), 8 do out[#out + 1] = r end
  return out
end

local function BagCount(itemID)
  local n = WC.BagCount and WC.BagCount(itemID) or 0
  return (type(n) == "number" and n > 0) and n or 0
end

local function FavorOwned()
  local ok, q = pcall(function()
    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(WC.FAVOR_CURRENCY)
    return info and info.quantity
  end)
  return (ok and type(q) == "number" and q > 0) and q or 0
end

-- The crates on the Auction House, cheapest first: { { price, qty (math.huge when only Auctionator's price is
-- known), id, est }, ... }
local function CrateOffers()
  local offers = {}
  for _, c in ipairs(WC.CRATES) do
    local cost, _, res, est = WC:CostBest(c.id, 1)
    if cost then
      if est or type(res) ~= "table" or type(res.entries) ~= "table" then
        offers[#offers + 1] = { cost, math.huge, c.id, true }
      else
        for _, e in ipairs(res.entries) do offers[#offers + 1] = { e[1], e[2], c.id, false } end
      end
    end
  end
  table.sort(offers, function(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[3] < b[3]
  end)
  return offers
end

local function ByCost(a, b)
  if a.cost ~= b.cost then return a.cost < b.cost end
  return a.key < b.key
end

-- prefix sums of a list of steps' costs: pre[0] = 0, pre[i] = cost of the cheapest i
local function Prefix(list)
  local pre = { [0] = 0 }
  for i = 1, #list do pre[i] = pre[i - 1] + list[i].cost end
  return pre
end

local repGen, planCache = 0, nil
function WC:RepChanged()
  repGen = repGen + 1
end

-- The plan (a shared cache: read it, never change it):
--   { why = nil | "top" (nothing above the current standing),
--     reaction, value (assumed = true: the game shows no reputation yet, taken as Neutral 0),
--     target (reaction aimed at), targetRep, need (reputation missing),
--     steps = { entry, ... } what to hand in today, cheapest reputation first. A writ entry looks like one of
--       WC:EvaluateWrits (writ, writCost, itemCost, cost, repGain, perRep, est, status = "ok") with plan = true,
--       haveWrit, haveQty / buyQty (of the requested item), writRes / itemRes (prices of what is bought);
--       the crate-return entry: receipt = true, n (times), buyCrates, haveCrates, haveReceipts, favor (spent),
--       crate (cheapest type), cash, cost, repGain, perRep, est, cashEst (the crate prices are estimates),
--     rep (gained by the steps), cash (money to spend), cost (cash + the Favor's worth), favor (Favor spent),
--     cashEst (some price to pay is an estimate), est (that, or the Favor's worth is one),
--     reached (the steps reach the target), short (reputation still missing),
--     doneN / doneRep (turned in today), open (writs that could still be handed in today, at any price),
--     daily = { n, rep, cost } what all writs for sale give in a day at today's prices (under the cap),
--     days (more days needed for `short` at that rate; nil when unknown),
--     shop = { { itemID, qty, cost, est, kind = "writ"|"item"|"crate" }, ... } everything to buy,
--     items = { itemID, ... } the same items, for the check button (which asks with fresh = true),
--     labelOpen (the one-time Shipping Label quest, +2000, is not done yet) }
function WC:RepPlan(fresh)
  local db = WC:DB()
  local now = GetTime()
  local bucket = math.floor(now / 30)
  if planCache and planCache.gen == repGen and planCache.bucket == bucket then return planCache.plan end
  -- while a check stores prices (several times a second) the plan on screen may be up to a second behind;
  -- the check itself asks for a fresh one (fresh = true)
  if not fresh and planCache and WC.Scanner and WC.Scanner.active and now - planCache.at < 1 then return planCache.plan end
  local plan = { steps = {}, shop = {}, items = {}, rep = 0, cash = 0, cost = 0, favor = 0, est = false, cashEst = false }
  planCache = { gen = repGen, bucket = bucket, plan = plan, at = now }

  local mult = 1 + WC:RepBonus()
  plan.doneN, plan.doneRep = WC:WritsToday()
  local _, reaction, value, _, hi = WC:Standing()
  if not reaction or not value then
    -- the game shows no reputation with the faction yet (nothing handed in so far): Neutral, at 0
    reaction, value, hi = 4, 0, WC.REP_START[5]
    plan.assumed = true
  end
  plan.reaction, plan.value = reaction, value
  local targets = WC:RepTargets()
  if #targets == 0 then
    plan.why = "top"
    return plan
  end
  local target = tonumber(db.repTarget)
  local known = false
  for _, r in ipairs(targets) do if r == target then known = true end end
  if not known then target = targets[1] end            -- "next", or a standing already reached
  plan.target = target
  -- the next standing starts where the game says this one ends; the others at the usual thresholds
  plan.targetRep = (target == reaction + 1 and hi and hi > value) and hi or WC.REP_START[target]
  plan.need = math.max(0, plan.targetRep - value)
  local cap = tonumber(db.repCap) or 0

  -- the one-time first crate ("Shipping Label")
  local labelDone = false
  for _, q in ipairs(WC.LABEL_QUESTS or {}) do
    if WC:WritDoneToday(q) then labelDone = true end
  end
  plan.labelOpen = not labelDone

  -- writs: what handing each in costs today
  local tiers, tierOf = {}, {}
  local daily = { n = 0, rep = 0, cost = 0 }
  local open = 0
  for i, w in ipairs(WC.WRITS) do
    local done = WC:WritDoneToday(w.quest)
    local gain = w.rep * mult
    -- a day at today's prices, bought in full (the bags are for today only)
    local fullWrit = WC:CostBest(w.writ, 1)
    local fullItem = WC:CostBest(w.item, w.qty)
    if fullWrit and fullItem and (cap <= 0 or (fullWrit + fullItem) / gain <= cap) then
      daily.n, daily.rep, daily.cost = daily.n + 1, daily.rep + gain, daily.cost + fullWrit + fullItem
    end
    if not done then
      local haveWrit = BagCount(w.writ) > 0
      local haveQty = math.min(BagCount(w.item), w.qty)
      local buyQty = w.qty - haveQty
      local writCost, writRes, writEst = 0, nil, false
      if not haveWrit then
        local c, _, res, est = WC:CostBest(w.writ, 1)
        writCost, writRes, writEst = c, res, est
      end
      local itemCost, itemRes, itemEst = 0, nil, false
      if buyQty > 0 then
        local c, _, res, est = WC:CostBest(w.item, buyQty)
        itemCost, itemRes, itemEst = c, res, est
      end
      if writCost and itemCost then
        open = open + 1
        local cost = writCost + itemCost
        if cap <= 0 or cost / gain <= cap then
          local e = { writ = w, key = i, plan = true, status = "ok", haveWrit = haveWrit, haveQty = haveQty, buyQty = buyQty,
                      writCost = writCost, writRes = writRes, writEst = writEst and true or false,
                      itemCost = itemCost, itemRes = itemRes, itemEst = itemEst and true or false,
                      cost = cost, cash = cost, repGain = gain, perRep = cost / gain,
                      est = (writEst or itemEst) and true or false }
          e.cashEst = e.est
          local t = tierOf[w.rep]
          if not t then
            t = { units = w.rep / REP_UNIT, list = {} }
            tierOf[w.rep] = t
            tiers[#tiers + 1] = t
          end
          t.list[#t.list + 1] = e
        end
      end
    end
  end
  plan.open, plan.daily = open, daily
  table.sort(tiers, function(a, b) return a.units < b.units end)
  for _, t in ipairs(tiers) do
    table.sort(t.list, ByCost)
    t.pre = Prefix(t.list)
  end

  -- crate returns
  local returns = { units = WC.REP.empty / REP_UNIT, list = {} }
  local haveReceipts, haveCrates, favorOwned = BagCount(WC.RECEIPT_ITEM), 0, FavorOwned()
  local offers, perFavor, favorEst
  if db.repUseFavor ~= false and reaction >= 5 then
    for _, c in ipairs(WC.CRATES) do haveCrates = haveCrates + BagCount(c.id) end
    offers = CrateOffers()
    perFavor, favorEst = WC:BestPerFavor()
    local maxUses = haveReceipts + math.floor(favorOwned / WC.REP.receiptFavor)
    local gain = WC.REP.empty * mult
    local oi, left = 1, offers[1] and offers[1][2] or 0
    for j = 1, maxUses do
      local step = { key = j, cash = 0, favor = 0, est = false, cashEst = false }
      if j > haveCrates then                                    -- a crate to buy
        while offers[oi] and left <= 0 do
          oi = oi + 1
          left = offers[oi] and offers[oi][2] or 0
        end
        local o = offers[oi]
        if not o then break end                                  -- no more crates for sale
        left = left - 1
        step.cash, step.crateID, step.est, step.cashEst = o[1], o[3], o[4], o[4]
      end
      local cost = step.cash
      if j > haveReceipts then                                   -- a receipt to buy with Favor
        step.favor = WC.REP.receiptFavor
        cost = cost + step.favor * (perFavor or 0)
        if favorEst or not perFavor then step.est = true end
      end
      step.cost = cost
      if cap > 0 and cost / gain > cap then break end            -- (costs only go up from here)
      returns.list[#returns.list + 1] = step
    end
  end
  returns.pre = Prefix(returns.list)

  -- the cheapest combination that reaches the target: counts of each kind
  local U = math.ceil(plan.need / (REP_UNIT * mult) - 1e-9)
  local t1, t2, t3 = tiers[1], tiers[2], tiers[3]
  local n1, n2, n3 = t1 and #t1.list or 0, t2 and #t2.list or 0, t3 and #t3.list or 0
  local u1, u2, u3 = t1 and t1.units or 0, t2 and t2.units or 0, t3 and t3.units or 0
  local p1, p2, p3 = t1 and t1.pre or { [0] = 0 }, t2 and t2.pre or { [0] = 0 }, t3 and t3.pre or { [0] = 0 }
  local nr, ur, pr = #returns.list, returns.units, returns.pre
  local best
  if U > n1 * u1 + n2 * u2 + n3 * u3 + nr * ur then
    best = { a = n1, b = n2, c = n3, r = nr }                    -- not reachable today: everything there is
  elseif U > 0 then
    for a = 0, n1 do
      local ua = a * u1
      for b = 0, n2 do
        local ub = ua + b * u2
        for c = 0, n3 do
          local rem = U - ub - c * u3
          local r = rem > 0 and math.ceil(rem / ur) or 0
          if r <= nr then
            local cost = p1[a] + p2[b] + p3[c] + pr[r]
            local count = a + b + c + r
            if not best or cost < best.cost - 1e-6 or (cost < best.cost + 1e-6 and count < best.count) then
              best = { a = a, b = b, c = c, r = r, cost = cost, count = count }
            end
          end
          if rem <= 0 then break end                             -- one more of this kind only costs more
        end
        if ub >= U then break end
      end
      if ua >= U then break end
    end
    if not best then best = { a = n1, b = n2, c = n3, r = nr } end
  else
    best = { a = 0, b = 0, c = 0, r = 0 }
  end

  -- the steps
  local steps = plan.steps
  local function Take(t, n)
    for i = 1, n do steps[#steps + 1] = t.list[i] end
  end
  if t1 then Take(t1, best.a) end
  if t2 then Take(t2, best.b) end
  if t3 then Take(t3, best.c) end
  local shopCrates = {}
  if best.r > 0 then
    local e = { receipt = true, plan = true, key = 0, status = "ok", n = best.r, cash = 0, cost = 0, favor = 0, est = false,
                cashEst = false,
                haveCrates = math.min(haveCrates, best.r), haveReceipts = math.min(haveReceipts, best.r),
                repGain = best.r * WC.REP.empty * mult, perFavor = perFavor }
    e.buyCrates = best.r - e.haveCrates
    for j = 1, best.r do
      local st = returns.list[j]
      e.cash, e.cost, e.favor = e.cash + st.cash, e.cost + st.cost, e.favor + st.favor
      if st.est then e.est = true end
      if st.cashEst then e.cashEst = true end
      if st.crateID then
        local sc = shopCrates[st.crateID]
        if not sc then
          sc = { itemID = st.crateID, qty = 0, cost = 0, est = false, kind = "crate" }
          shopCrates[st.crateID] = sc
        end
        sc.qty, sc.cost = sc.qty + 1, sc.cost + st.cash
        if st.cashEst then sc.est = true end
        if not e.crate then e.crateID = st.crateID end
      end
    end
    for _, c in ipairs(WC.CRATES) do
      if c.id == e.crateID or (not e.crateID and not e.crate and BagCount(c.id) > 0) then e.crate = c end
    end
    e.crate = e.crate or WC.CRATES[1]
    e.perRep = e.cost / e.repGain
    e.writCost, e.itemCost = e.cash, e.cost - e.cash            -- the two price columns: crates, the Favor's worth
    steps[#steps + 1] = e
  end
  table.sort(steps, function(x, y)
    if x.perRep ~= y.perRep then return x.perRep < y.perRep end
    return x.key < y.key
  end)

  -- totals and the shopping list
  local shop, items = plan.shop, plan.items
  for rank, e in ipairs(steps) do
    e.rank, e.score = rank, e.perRep
    plan.rep, plan.cash, plan.cost = plan.rep + e.repGain, plan.cash + e.cash, plan.cost + e.cost
    if e.est then plan.est = true end
    if e.cashEst then plan.cashEst = true end
    if e.receipt then
      plan.favor = plan.favor + e.favor
    else
      local w = e.writ
      if not e.haveWrit then
        shop[#shop + 1] = { itemID = w.writ, qty = 1, cost = e.writCost, est = e.writEst, kind = "writ" }
      end
      if e.buyQty > 0 then
        shop[#shop + 1] = { itemID = w.item, qty = e.buyQty, cost = e.itemCost, est = e.itemEst, kind = "item" }
      end
    end
  end
  for _, c in ipairs(WC.CRATES) do
    if shopCrates[c.id] then shop[#shop + 1] = shopCrates[c.id] end
  end
  for _, x in ipairs(shop) do items[#items + 1] = x.itemID end
  plan.reached = plan.rep >= plan.need - 1e-6
  plan.short = plan.reached and 0 or (plan.need - plan.rep)
  if plan.short > 0 and daily.rep > 0 then plan.days = math.ceil(plan.short / daily.rep - 1e-9) end
  return plan
end

WC:On("PRICES_UPDATED", function() repGen = repGen + 1 end)
WC:On("BAGS_UPDATED", function() repGen = repGen + 1 end)
WC:On("SETTINGS_CHANGED", function() repGen = repGen + 1 end)
WC:On("DB_READY", function() repGen = repGen + 1 end)

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
    WC:RepChanged()
    local ok, err = pcall(WC.OnCurrencyUpdate, WC, ...)
    if not ok then ReportError("crate reward", err) end
  elseif event == "PLAYER_LEVEL_UP" or event == "QUEST_TURNED_IN" or event == "UPDATE_FACTION" then
    WC:RepChanged()
    if event == "QUEST_TURNED_IN" then
      local ok, err = pcall(WC.OnQuestTurnedIn, WC, ...)
      if not ok then ReportError("quest turned in", err) end
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
