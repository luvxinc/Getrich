local addonName, WC = ...

-- Skill-up planner (SPEC2 §2): which recipe gives the next profession skill point for the least money, and the
-- whole route to a target skill. Uses learned recipes (Recipes.lua) and recipes a trainer can teach (WC.RECIPES,
-- DataRecipes.lua). Prices follow Profit.lua exactly (Profit:MatCost, same product values), and results share
-- Profit's cache generation, so they are rebuilt only after a bus message (prices, recipes, vendor, DE, settings).
--
--   Leveling:Chance(rec, skill[, current])        -> chance 0..1, color ("orange"|"yellow"|"green"|"grey"|"red"), est
--   Leveling:Candidates(charKey, skillLine, skill) -> entries, sorted by cost per skill point (missing prices last)
--   Leveling:Plan(charKey, skillLine, from, to)    -> route { from, to, steps, mats, total, learn, missing, ... }
--   Leveling:ScanItems(charKey)                    -> reagent set, product set (for the "craft" scan kind)
--   Leveling:Skill(charKey, skillLine)             -> rank, max
-- Skill-up chance (Classic rule, WC.SKILLUP): below yellow = 1; yellow..grey = (grey - skill) / (grey - yellow);
-- grey or higher = 0. Green starts at floor((yellow + grey) / 2).
-- Everything returned is a shared cache: read it, never change it.

local Leveling = WC.Leveling or {}
WC.Leveling = Leveling

-- settings read here (Settings.lua shows them): "best3" | "npcde" | "none"; "max" | 225 | 300
if WC.Store and WC.Store.Default then
  WC.Store:Default("levelOffset", "best3")
  WC.Store:Default("levelTarget", "max")
end

local pairs, type, tonumber, pcall = pairs, type, tonumber, pcall
local floor, ceil, mmax, mmin = math.floor, math.ceil, math.max, math.min
local tsort = table.sort

local EST_WIDTH = 25      -- learned recipe without built-in data: yellow guessed 25 points below grey
local WINDOW = 50         -- craft scan looks this many points ahead of the current skill
local EMPTY = {}

local function PI() return (WC.Profit and WC.Profit.internal) or EMPTY end

local function ClearArray(t, from)
  for i = #t, from or 1, -1 do t[i] = nil end
end

local function CurrentChar()
  local ok, key = pcall(WC.CharKey, WC)
  return (ok and key) or "?"
end

local function Setting(key)
  local db
  if WC.DB then
    local ok, d = pcall(WC.DB, WC)
    if ok and type(d) == "table" then db = d end
  end
  return db and db[key]
end

local function Generation()
  local P = WC.Profit
  return (P and P.Generation and P:Generation()) or 0
end

local function RecipesFor(charKey)
  local R = WC.Recipes
  if not (R and R.ForChar) then return EMPTY end
  local ok, t = pcall(R.ForChar, R, charKey)
  if ok and type(t) == "table" then return t end
  return EMPTY
end

local function ProfsOf(charKey)
  local R = WC.Recipes
  if not (R and R.Professions) then return EMPTY end
  local ok, t = pcall(R.Professions, R, charKey)
  if ok and type(t) == "table" then return t end
  return EMPTY
end

-- adapted built-in row of a recipe, looked up in its own skill line only (WC.RECIPES decodes a line on first use:
-- never search the other lines for a learned recipe the data doesn't have)
local function Static(spellID, skillLine)
  local P = WC.Profit
  if not (P and P.StaticRecipe) or type(WC.RECIPES) ~= "table" then return nil end
  local line = WC.RECIPES[skillLine]
  if type(line) ~= "table" or type(line[spellID]) ~= "table" then return nil end
  local ok, a = pcall(P.StaticRecipe, P, spellID, skillLine)
  if ok and type(a) == "table" then return a end
  return nil
end

-- exact learn skill + training cost from the trainer when the player has seen it (Profit:LearnInfo)
local function LearnInfo(skillLine, spellID, row)
  local P = WC.Profit
  if P and P.LearnInfo then
    local ok, s, cost, guess = pcall(P.LearnInfo, P, skillLine, spellID, row)
    if ok then return s, cost, guess end
  end
  return row and tonumber(row.s), nil, row and row.se == 1
end

-- rank, max of a profession (Recipes:Skill when present, else the captured profession list)
function Leveling:Skill(charKey, skillLine)
  charKey = charKey or CurrentChar()
  local R = WC.Recipes
  if R and R.Skill then
    local ok, rank, max = pcall(R.Skill, R, charKey, skillLine)
    if ok and tonumber(rank) then return tonumber(rank), tonumber(max) end
  end
  local p = ProfsOf(charKey)[skillLine]
  if type(p) == "table" and tonumber(p.rank) then return tonumber(p.rank), tonumber(p.max) end
  return nil
end

-- target skill from db.levelTarget ("max" = the cap of the current rank)
local function Target(max)
  local n = tonumber(Setting("levelTarget"))
  if n then return n end
  return tonumber(max) or 300
end
Leveling.Target = function(_, max) return Target(max) end

-- ---------------------------------------------------------------------------
-- chance

-- learn skill, yellow, grey, est (true = yellow guessed from the captured grey level)
local function Thresholds(rec)
  local s, y, g = tonumber(rec.s), tonumber(rec.y), tonumber(rec.g)
  if y and g then return s, y, g, false end
  g = g or tonumber(rec.mt)
  if g then return s, g - EST_WIDTH, g, true end
  return s, nil, nil, true
end

-- rec: a WC.RECIPES row / adapted row / pool entry (s, y, g), or a captured recipe (mt = grey level,
-- d = relativeDifficulty 0 orange .. 3 grey, valid at the skill it was captured: pass current = that skill).
function Leveling:Chance(rec, skill, current)
  if type(rec) ~= "table" then return nil end
  skill = tonumber(skill) or 0
  local s, y, g, est = Thresholds(rec)
  if s and skill < s then return 0, "red", est end            -- can't be learned yet
  local d = tonumber(rec.d)
  local useD = est and d and current and skill == current
  if not g then
    if d == nil then return nil end                           -- nothing known about this recipe
    if current and skill ~= current then return nil end       -- the color is only known at the current skill
    if d == 0 then return 1, "orange", true end
    if d == 1 then return 0.75, "yellow", true end
    if d == 2 then return 0.25, "green", true end
    return 0, "grey", true
  end
  if useD then
    if d == 0 then return 1, "orange", true end
    if d >= 3 then return 0, "grey", true end
  end
  if skill >= g then return 0, "grey", est end
  if skill < y or g <= y then return 1, "orange", est end
  local chance = (g - skill) / (g - y)
  local color = (skill >= floor((y + g) / 2)) and "green" or "yellow"
  if useD then                                                -- trust the client's color for the guessed range
    if d == 1 then chance, color = mmax(chance, 0.5), "yellow" end
    if d == 2 then chance, color = mmin(chance, 0.5), "green" end
  end
  return chance, color, est
end

-- ---------------------------------------------------------------------------
-- pool: every learned + trainer recipe of one profession, priced (independent of the skill)

local pools = {}   -- [charKey] = { [skillLine] = { gen, list, byID, cand, plan } }

local function Offset(e, mode)
  if mode == "none" then return 0, nil end
  local best, kind
  if e.npc and not e.npcNoBuy and e.npc > 0 then best, kind = e.npc, "npc" end
  if mode ~= "npcde" and e.ah and (not best or e.ah > best) then best, kind = e.ah, "ah" end
  if e.de and e.deSkillOK and (not best or e.de > best) then best, kind = e.de, "de" end
  return best or 0, kind
end

local function Finish(e, mode)
  local off, kind = Offset(e, mode)
  e.offset, e.offsetKind = off, kind
  e.net = e.cost and (e.cost - off) or nil
end

-- skill points per successful craft: at least 1 (the client reports 0 for some recipes)
local function SkillUps(...)
  for i = 1, select("#", ...) do
    local v = tonumber((select(i, ...)))
    if v and v >= 1 then return floor(v) end
  end
  return 1
end

-- Ranking: money per expected skill point with profit counted as 0, so a profitable recipe never wins just by
-- being near grey (many crafts for few points). Ties: more points per craft (chance x skill-ups), then more
-- profit (lower net), then learned, then lower recipeID.
local INF = math.huge
local function RankKey(net, perCraft)
  if not net or not perCraft or perCraft <= 0 then return nil end
  local k = mmax(net, 0) / perCraft
  if k ~= k or k >= INF then return nil end
  return k
end

local function Before(rkA, cA, netA, learnedA, idA, rkB, cB, netB, learnedB, idB)
  if rkA ~= rkB then return rkA < rkB end
  if cA ~= cB then return cA > cB end
  if netA ~= netB then return netA < netB end
  if learnedA ~= learnedB then return learnedA and true or false end
  return idA < idB
end

local function BuildPool(pool, charKey, skillLine)
  local I = PI()
  local FillEntry = I.FillEntry
  local list, byID = pool.list, pool.byID
  local gen = Generation()
  ClearArray(list)
  pool.gen = gen
  if not FillEntry then return end
  local ench = I.EnchSkill and I.EnchSkill(charKey) or nil
  local isMe = (charKey == CurrentChar())
  local mode = Setting("levelOffset")
  if mode ~= "npcde" and mode ~= "none" then mode = "best3" end
  local recipes = RecipesFor(charKey)
  local function Take(id)
    local e = byID[id]
    if not e then e = {}; byID[id] = e end
    return e
  end
  for recipeID, r in pairs(recipes) do
    if type(r) == "table" and r.p == skillLine then
      local a = Static(recipeID, skillLine)
      local e = Take(recipeID)
      FillEntry(e, recipeID, r, ench, isMe)
      e.learned, e.source = true, a and a.src or nil
      -- learned: the learn skill no longer matters (and the data's trainer learn skill may be a guess)
      if a then
        e.s, e.y, e.g, e.est = nil, tonumber(a.y), tonumber(a.g), false
      else
        e.s, e.y, e.g, e.est = nil, nil, nil, true
      end
      e.learnCost, e.learnGuess, e.auto = nil, nil, nil
      e.mt, e.d = tonumber(r.mt), tonumber(r.d)
      e.skillUps = SkillUps(r.su, a and a.su)
      Finish(e, mode)
      e.gen = gen
      list[#list + 1] = e
    end
  end
  local rows = type(WC.RECIPES) == "table" and WC.RECIPES[skillLine] or nil
  if type(rows) == "table" then
    for spellID, row in pairs(rows) do
      if type(row) == "table" and (row.t == "t" or row.a == 1) and recipes[spellID] == nil then
        local a = Static(spellID, skillLine)
        if a then
          local e = Take(spellID)
          FillEntry(e, spellID, a, ench, isMe)
          if row.a == 1 then
            -- learned automatically with the profession once the skill reaches s: no trainer, no cost
            e.learned, e.source, e.auto = true, "auto", true
            e.s, e.learnCost, e.learnGuess = tonumber(row.s), nil, false
          else
            local s, learnCost, guess = LearnInfo(skillLine, spellID, row)
            e.learned, e.source, e.auto = false, "t", nil
            e.s, e.learnCost, e.learnGuess = s, learnCost, guess or nil
          end
          e.y, e.g, e.est, e.mt, e.d = tonumber(a.y), tonumber(a.g), false, nil, nil
          e.skillUps = SkillUps(a.su)
          Finish(e, mode)
          e.gen = gen
          list[#list + 1] = e
        end
      end
    end
  end
  for k, e in pairs(byID) do
    if e.gen ~= gen then byID[k] = nil end
  end
  pool.gen = gen
end

local function Pool(charKey, skillLine)
  local byChar = pools[charKey]
  if not byChar then byChar = {}; pools[charKey] = byChar end
  local pool = byChar[skillLine]
  if not pool then
    pool = { list = {}, byID = {} }
    byChar[skillLine] = pool
  end
  if pool.gen ~= Generation() then BuildPool(pool, charKey, skillLine) end
  return pool
end

-- ---------------------------------------------------------------------------
-- candidates at one skill level

local function CandOrder(a, b)
  local ra, rb = a.rankKey, b.rankKey
  if ra and rb then
    return Before(ra, a.chance * a.skillUps, a.net, a.learned, a.recipeID, rb, b.chance * b.skillUps, b.net, b.learned, b.recipeID)
  elseif ra then
    return true
  elseif rb then
    return false
  end
  if a.learned ~= b.learned then return a.learned and true or false end
  return a.recipeID < b.recipeID
end

-- Entries { recipeID, name, learned, auto (learned automatically at learnSkill), source ("t"|"i"|"auto"|nil),
--   learnSkill, learnCost, learnGuess, chance, color, skillUps, cost, missing, offset, offsetKind ("npc"|"ah"|"de"|nil),
--   npc, ah, de, net = cost - offset, perPoint = net / (chance x skillUps), rankKey = max(net, 0) / (chance x skillUps),
--   status ("ok"|"missing"|"loading"), itemID, yield, reagents, est (thresholds guessed), y, g, base = pool entry }
-- for learned recipes and trainer recipes with learn skill <= skill and chance > 0, sorted by rankKey (ties: more
-- points per craft, more profit), missing prices last.
function Leveling:Candidates(charKey, skillLine, skill)
  charKey = charKey or CurrentChar()
  local current = self:Skill(charKey, skillLine)
  skill = tonumber(skill) or current or 1
  local pool = Pool(charKey, skillLine)
  local c = pool.cand
  if c and c.gen == pool.gen and c.skill == skill and c.current == current then return c.list end
  if not c then
    c = { list = {}, byID = {} }
    pool.cand = c
  end
  local list, byID = c.list, c.byID
  ClearArray(list)
  local stamp = (c.stamp or 0) + 1
  c.stamp = stamp
  for i = 1, #pool.list do
    local p = pool.list[i]
    local chance, color = self:Chance(p, skill, current)
    if chance and chance > 0 then
      local e = byID[p.recipeID]
      if not e then e = {}; byID[p.recipeID] = e end
      e.recipeID, e.name, e.learned, e.source, e.learnSkill = p.recipeID, p.name, p.learned, p.source, p.s
      e.learnCost, e.learnGuess = p.learnCost, p.learnGuess
      e.itemID, e.yield, e.reagents, e.base, e.est, e.y, e.g = p.itemID, p.yield, p.reagents, p, p.est, p.y, p.g
      e.chance, e.color, e.skillUps = chance, color, p.skillUps
      e.cost, e.missing, e.status = p.cost, p.missing, p.status
      e.offset, e.offsetKind, e.npc, e.ah, e.de = p.offset, p.offsetKind, p.npc, p.ah, p.de
      e.net, e.auto = p.net, p.auto
      e.perPoint = p.net and p.net / (chance * p.skillUps) or nil      -- shown: real money per point
      e.rankKey = RankKey(p.net, chance * p.skillUps)                   -- sorted by (profit counted as 0)
      e.stamp = stamp
      list[#list + 1] = e
    end
  end
  for k, e in pairs(byID) do
    if e.stamp ~= stamp then byID[k] = nil end
  end
  tsort(list, CandOrder)
  c.gen, c.skill, c.current = pool.gen, skill, current
  return list
end

-- ---------------------------------------------------------------------------
-- plan: greedy per skill level

local function MatOrder(a, b)
  if a.cost and b.cost then
    if a.cost ~= b.cost then return a.cost > b.cost end
  elseif a.cost then
    return true
  elseif b.cost then
    return false
  end
  return a.itemID < b.itemID
end

local function ByStart(a, b)
  if a.s ~= b.s then return a.s < b.s end
  return a.p.recipeID < b.p.recipeID
end

local function BuildPlan(pool, from, to, current)
  local plan = { from = from, to = to, steps = {}, mats = {}, learn = {}, missing = {}, unknown = 0 }
  local steps, agg, learned = plan.steps, {}, {}
  local offsetTotal, crafts, netSteps = 0, 0, 0

  -- priced recipes with known thresholds, by learn skill; an "active" window keeps only the ones usable at L
  -- (learn skill reached, not grey yet), so each level looks at a few dozen recipes, not the whole table
  local prepared, dOnly = {}, {}
  for i = 1, #pool.list do
    local p = pool.list[i]
    if p.net then
      local s, y, g = Thresholds(p)
      if g then
        prepared[#prepared + 1] = { p = p, s = s or 0, y = y, g = g, useD = p.est and p.d ~= nil }
      elseif p.d ~= nil then
        dOnly[#dOnly + 1] = p          -- only the client's color at the current skill is known
      end
    end
  end
  tsort(prepared, ByStart)
  local active, nextIdx = {}, 1

  local best, bestRK, bestPC, bestChance
  local function Consider(p, chance)
    local pc = chance * p.skillUps
    local rk = RankKey(p.net, pc)
    if rk and (not best or Before(rk, pc, p.net, p.learned, p.recipeID, bestRK, bestPC, best.net, best.learned, best.recipeID)) then
      best, bestRK, bestPC, bestChance = p, rk, pc, chance
    end
  end

  local function BestAt(L)
    while nextIdx <= #prepared and prepared[nextIdx].s <= L do
      active[#active + 1] = prepared[nextIdx]
      nextIdx = nextIdx + 1
    end
    best, bestRK, bestPC, bestChance = nil, nil, nil, nil
    local i = 1
    while i <= #active do
      local a = active[i]
      if a.g <= L then
        active[i] = active[#active]     -- grey for good: drop it
        active[#active] = nil
      else
        local chance
        if a.useD and L == current then
          chance = Leveling:Chance(a.p, L, current)
        elseif L < a.y or a.g <= a.y then
          chance = 1
        else
          chance = (a.g - L) / (a.g - a.y)
        end
        if chance and chance > 0 then Consider(a.p, chance) end
        i = i + 1
      end
    end
    if L == current then
      for j = 1, #dOnly do
        local p = dOnly[j]
        local chance = Leveling:Chance(p, L, current)
        if chance and chance > 0 then Consider(p, chance) end
      end
    end
    return best, bestChance
  end

  local L, cur = from, nil
  local guard = 0
  while L < to do
    guard = guard + 1
    if guard > 1000 then plan.stuck = L; break end      -- hard cap (a level step is always >= 1)
    local p, chance = BestAt(L)
    if not p then plan.stuck = L; break end
    local n = 1 / chance
    local nextL = L + p.skillUps
    if not (nextL > L) or n ~= n or n >= INF then plan.stuck = L; break end
    if cur and cur.recipeID == p.recipeID then
      cur.to = mmin(nextL, to)
      cur.crafts = cur.crafts + n
    else
      cur = { from = L, to = mmin(nextL, to), recipeID = p.recipeID, name = p.name, learned = p.learned,
              itemID = p.itemID, crafts = n, unitCost = p.cost, offset = p.offset, offsetKind = p.offsetKind,
              chance = chance, skillUps = p.skillUps }
      steps[#steps + 1] = cur
      if not p.learned and not learned[p.recipeID] then
        learned[p.recipeID] = true
        plan.learn[#plan.learn + 1] = { recipeID = p.recipeID, name = p.name, skill = L, learnSkill = p.s,
                                        cost = p.learnCost, learnGuess = p.learnGuess }
        cur.learnCost = p.learnCost
      end
    end
    local reags = p.reagents or EMPTY
    for i = 1, #reags do
      local x = reags[i]
      agg[x.itemID] = (agg[x.itemID] or 0) + n * x.qty
    end
    offsetTotal = offsetTotal + n * p.offset
    crafts = crafts + n
    L = nextL
  end
  for i = 1, #steps do
    local s = steps[i]
    s.cost = s.crafts * s.unitCost
    s.net = s.cost - s.crafts * s.offset
    netSteps = netSteps + s.net
  end
  plan.reached = mmin(L, to)
  plan.crafts, plan.offset, plan.netSteps = crafts, offsetTotal, netSteps

  -- materials of the whole route, bought at once: re-costed for the total (deeper into the order book)
  local P = WC.Profit
  local matCost, short = 0, false
  for itemID, need in pairs(agg) do
    local qty = ceil(need - 1e-9)
    local m = P:MatCost(itemID, qty)
    plan.mats[#plan.mats + 1] = { itemID = itemID, qty = qty, need = need, cost = m.cost, unit = m.unit,
      source = m.source, missing = m.missing, est = m.est, mat = m }
    if m.cost then matCost = matCost + m.cost else short = true end
  end
  tsort(plan.mats, MatOrder)
  -- training: known costs are added to the total; unknown ones (trainer not visited yet) are counted
  local learnCost, learnUnknown = 0, 0
  for i = 1, #plan.learn do
    local c = plan.learn[i].cost
    if c then learnCost = learnCost + c else learnUnknown = learnUnknown + 1 end
  end
  plan.learnCost, plan.learnCostUnknown = learnCost, learnUnknown
  plan.matCost = (not short) and matCost or nil
  plan.short = short or nil
  plan.total = (not short) and (matCost - offsetTotal + learnCost) or nil

  -- recipes left out of the route because a material has no price (only those usable in the range)
  for i = 1, #pool.list do
    local p = pool.list[i]
    local L0 = mmax(from, p.s or from)
    if L0 < to then
      local chance = Leveling:Chance(p, L0, current)
      if chance == nil then
        plan.unknown = plan.unknown + 1
      elseif chance > 0 and not p.net then
        plan.missing[#plan.missing + 1] = p.recipeID
      end
    end
  end
  tsort(plan.missing)
  return plan
end

-- { from, to, reached, stuck (skill with no usable recipe), steps = { { from, to, recipeID, name, learned, itemID,
--   crafts (expected), cost, net, unitCost, offset, offsetKind, chance (at from), skillUps } },
--   mats = { { itemID, qty (to buy), need (expected), cost, unit, source, missing, est, mat } } (costliest first),
--   matCost, offset (product value of all crafts), total = matCost - offset (nil if a material can't be bought),
--   netSteps (sum of step nets at per-craft prices), crafts,
--   learn = { { recipeID, name, skill (needed at), learnSkill, cost (training, nil = unknown), learnGuess } },
--   learnCost (known training costs, included in total), learnCostUnknown (count),
--   missing = { recipeID, ... } (left out: no price), unknown (recipes without skill-up data), short }
-- total = matCost - offset + learnCost.
function Leveling:Plan(charKey, skillLine, fromSkill, toSkill)
  charKey = charKey or CurrentChar()
  local rank, max = self:Skill(charKey, skillLine)
  local from = floor(tonumber(fromSkill) or rank or 1)
  local to = floor(tonumber(toSkill) or Target(max))
  local pool = Pool(charKey, skillLine)
  local pc = pool.plan
  if pc and pc.gen == pool.gen and pc.from == from and pc.to == to and pc.current == rank then return pc.result end
  local result = BuildPlan(pool, from, to, rank)
  pool.plan = { gen = pool.gen, from = from, to = to, current = rank, result = result }
  return result
end

-- ---------------------------------------------------------------------------
-- craft scan: reagents + products of the recipes useful in [skill, min(target, skill + 50)] of every profession

-- does a recipe give points somewhere in [lo, hi)? s = learn skill (nil for a learned recipe)
local probe = {}
local function Useful(s, rec, lo, hi, current)
  local L0 = mmax(lo, s or lo)
  if L0 >= hi then return false end
  probe.s, probe.y, probe.g, probe.mt, probe.d = s, tonumber(rec.y), tonumber(rec.g), tonumber(rec.mt), tonumber(rec.d)
  local chance = Leveling:Chance(probe, L0, current)
  return (chance or 0) > 0
end

function Leveling:ScanItems(charKey)
  charKey = charKey or CurrentChar()
  local reag, outs = {}, {}
  local recipes = RecipesFor(charKey)
  for skillLine, prof in pairs(ProfsOf(charKey)) do
    local rank = type(prof) == "table" and tonumber(prof.rank) or nil
    if rank then
      local hi = mmin(Target(prof.max), rank + WINDOW)
      if hi > rank then
        for id, r in pairs(recipes) do
          if type(r) == "table" and r.p == skillLine and Useful(nil, Static(id, skillLine) or r, rank, hi, rank) then
            if r.o then outs[r.o] = true end
            local list = type(r.r) == "table" and r.r or EMPTY
            for i = 1, #list do
              local id2 = type(list[i]) == "table" and tonumber(list[i][1] or list[i].itemID)
              if id2 then reag[id2] = true end
            end
          end
        end
        local rows = type(WC.RECIPES) == "table" and WC.RECIPES[skillLine] or nil
        if type(rows) == "table" then
          for spellID, row in pairs(rows) do
            if type(row) == "table" and (row.t == "t" or row.a == 1) and recipes[spellID] == nil
               and Useful(row.a == 1 and tonumber(row.s) or (LearnInfo(skillLine, spellID, row)), row, rank, hi, nil) then
              if row.o then outs[row.o] = true end
              local flat = type(row.r) == "table" and row.r or EMPTY
              for i = 1, #flat - 1, 2 do reag[flat[i]] = true end
            end
          end
        end
      end
    end
  end
  return reag, outs
end
