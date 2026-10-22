local addonName, WC = ...

-- Recipes.lua: remembers the recipes each character knows and the character's professions.
--
-- Recipes can only be read while a profession window is open (all C_TradeSkillUI recipe calls describe the
-- open trade skill), so every profession has to be opened once per character. A capture runs after
-- TRADE_SKILL_SHOW / TRADE_SKILL_LIST_UPDATE / TRADE_SKILL_DATA_SOURCE_CHANGED (debounced), only for the
-- player's own trade skill (not a linked, guild or NPC-crafting one), and reads at most 25 recipes per frame.
--
-- SavedVariables (owned by this file):
--   db.recipes[charKey][recipeID] = { n = name, p = skillLineID, o = outputItemID|nil, y1 = min yield, y2 = max yield,
--                                     r = { { itemID, qty }, ... }, tool = "Anvil, Blacksmith Hammer"|nil, t = time }
--   db.chars[charKey] = { name, realm, class, profs = { [skillLine] = { name, rank, max } },
--                         captured = { [skillLine] = time of the last complete capture }, t }
-- `tool` is information only (station / tool the recipe needs). It never hides a recipe or blocks profit.
--
-- API checked against the Forever UI source (wow-ui-source, branch forever, 1.60.1.70450):
--   GetRecipeInfo / GetRecipeSchematic(id, isRecraft) / GetRecipeOutputItemData / GetRecipeRequirements /
--   GetBaseProfessionInfo / GetProfessionInfoByRecipeID: APIDoc/TradeSkillUIDocumentation.lua
--   IsTradeSkillReady / IsTradeSkillLinked / IsTradeSkillGuild(Member) / IsNPCCrafting / GetFilteredRecipeIDs:
--   called by Blizzard_ProfessionsTemplates/Blizzard_Professions.lua:281-285, 378-382, 847
--   GetProfessions() slot order differs between Camelot files -> professions are identified by skillLine.

local Recipes = {}
WC.Recipes = Recipes

local ENCHANTING = 333
local REAGENT_BASIC = 1          -- Enum.CraftingReagentType.Basic (ProfessionConstantsDocumentation.lua)
local PER_FRAME = 25
local DEBOUNCE = 0.3
local MAX_TRIES = 4              -- incomplete captures retried per profession per opened window

local ready = false              -- SavedVariables loaded
local allItems                   -- cache for Recipes:AllItemIDs()
local job                        -- the running capture
local generation = 0             -- bumping it cancels the running capture
local pending = 0                -- debounce token
local session = { done = {}, tries = {} }   -- per opened profession window

local function pack(...) return { n = select("#", ...), ... } end

local function DB()
  if not ready then
    if type(WaylaidCrateDB) ~= "table" then return nil end
    ready = true
  end
  local db = WC:DB()
  if type(db) ~= "table" then return nil end
  if type(db.recipes) ~= "table" then db.recipes = {} end
  if type(db.chars) ~= "table" then db.chars = {} end
  return db
end

local function Now() return (time and time()) or 0 end

-- ---------------------------------------------------------------------------
-- professions of the logged-in character (GetProfessions + GetProfessionInfo, keyed by skillLine)

local function ReadProfessions()
  if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
  local res = pack(pcall(GetProfessions))
  if not res[1] then return nil end
  local profs, n = {}, 0
  for i = 2, res.n do
    local index = res[i]
    if index then
      local ok, name, _, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, index)
      if ok and type(skillLine) == "number" and skillLine > 0 then
        profs[skillLine] = { name = name, rank = tonumber(rank) or 0, max = tonumber(maxRank) or 0 }
        n = n + 1
      end
    end
  end
  return profs, n
end

local function SameProfs(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    local w = b[k]
    if not w or w.rank ~= v.rank or w.max ~= v.max or w.name ~= v.name then return false end
  end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

-- prune = true removes the recipes of a profession the character no longer has (only from a live
-- SKILL_LINES_CHANGED read that still lists at least one profession, so a half-loaded login can't wipe data)
function Recipes:UpdateChar(prune)
  local db = DB()
  if not db then return end
  local key = WC:CharKey()
  local c = db.chars[key]
  if type(c) ~= "table" then c = {}; db.chars[key] = c end
  if UnitName then c.name = UnitName("player") end
  if GetRealmName then c.realm = GetRealmName() end
  if UnitClass then local _, class = UnitClass("player"); c.class = class end
  c.t = Now()
  local profs, n = ReadProfessions()
  if not profs then return end
  -- an empty list right after login usually means the skills aren't loaded yet: keep what we know
  if n == 0 and type(c.profs) == "table" and next(c.profs) then return end
  local changed = not SameProfs(c.profs, profs)
  if prune and n > 0 and type(c.profs) == "table" then
    local list = db.recipes[key]
    if type(list) == "table" then
      for id, r in pairs(list) do
        if c.profs[r.p] and not profs[r.p] then list[id] = nil; changed = true end
      end
    end
  end
  c.profs = profs
  if changed then
    allItems = nil
    WC:Fire("RECIPES_UPDATED", key)
  end
end

-- ---------------------------------------------------------------------------
-- the open trade skill

-- true while the open trade skill is someone else's list (linked, guild) or an NPC crafting window
function Recipes:IsExternal()
  local T = C_TradeSkillUI
  if type(T) ~= "table" then return true end
  local names = { "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting", "IsRuneforging" }
  for i = 1, #names do
    local fn = T[names[i]]
    if type(fn) == "function" then
      local ok, v = pcall(fn)
      if ok and v then return true end
    end
  end
  return false
end

-- skillLine id + name of the player's own open, ready trade skill (nil otherwise)
local function OpenProfession()
  local T = C_TradeSkillUI
  if type(T) ~= "table" or type(T.GetBaseProfessionInfo) ~= "function" then return nil end
  if type(T.IsTradeSkillReady) == "function" then
    local ok, isReady = pcall(T.IsTradeSkillReady)
    if not ok or not isReady then return nil end
  end
  if Recipes:IsExternal() then return nil end
  local ok, info = pcall(T.GetBaseProfessionInfo)
  if not ok or type(info) ~= "table" then return nil end
  local id = info.parentProfessionID or info.professionID
  if type(id) ~= "number" or id <= 0 then return nil end
  return id, info.parentProfessionName or info.professionName
end

-- one recipe -> stored record, or nil (+ "loading" when the client had no data for it yet)
local function ReadRecipe(T, id, prof, now)
  local ok, info = pcall(T.GetRecipeInfo, id)
  if not ok or type(info) ~= "table" then return nil, "loading" end
  if not info.learned then return nil end
  if info.isDummyRecipe or info.isRecraft or info.isSalvageRecipe or info.isGatheringRecipe then return nil end
  if type(T.GetProfessionInfoByRecipeID) == "function" then
    local okOwner, owner = pcall(T.GetProfessionInfoByRecipeID, id)
    if okOwner and type(owner) == "table" then
      local ownerID = owner.parentProfessionID or owner.professionID
      if type(ownerID) == "number" and ownerID > 0 and ownerID ~= prof then return nil end
    end
  end
  local okS, s = pcall(T.GetRecipeSchematic, id, false)
  if not okS or type(s) ~= "table" then return nil, "loading" end

  local out = s.outputItemID
  if (type(out) ~= "number" or out <= 0) and type(T.GetRecipeOutputItemData) == "function" then
    local okO, data = pcall(T.GetRecipeOutputItemData, id)
    out = okO and type(data) == "table" and data.itemID or nil
  end
  if type(out) ~= "number" or out <= 0 then out = nil end

  local reagents, slotOf = {}, {}
  if type(s.reagentSlotSchematics) == "table" then
    for _, slot in ipairs(s.reagentSlotSchematics) do
      if type(slot) == "table" and (slot.reagentType == nil or slot.reagentType == REAGENT_BASIC) and slot.required ~= false then
        local first = type(slot.reagents) == "table" and slot.reagents[1]
        local itemID = type(first) == "table" and first.itemID
        local qty = slot.quantityRequired
        if type(itemID) == "number" and itemID > 0 and type(qty) == "number" and qty > 0 then
          local at = slotOf[itemID]
          if at then reagents[at][2] = reagents[at][2] + qty
          else reagents[#reagents + 1] = { itemID, qty }; slotOf[itemID] = #reagents end
        end
      end
    end
  end

  local tool
  if type(T.GetRecipeRequirements) == "function" then
    local okR, reqs = pcall(T.GetRecipeRequirements, id)
    if okR and type(reqs) == "table" then
      local names = {}
      for _, q in ipairs(reqs) do
        if type(q) == "table" and type(q.name) == "string" and q.name ~= "" then names[#names + 1] = q.name end
      end
      if #names > 0 then tool = table.concat(names, ", ") end
    end
  end

  local y1 = tonumber(s.quantityMin) or 1
  if y1 < 1 then y1 = 1 end
  local y2 = tonumber(s.quantityMax) or y1
  if y2 < y1 then y2 = y1 end
  return { n = info.name or s.name, p = prof, o = out, y1 = y1, y2 = y2, r = reagents, tool = tool, t = now }
end

local function SameRecipe(a, b)
  if type(a) ~= "table" then return false end
  if a.n ~= b.n or a.p ~= b.p or a.o ~= b.o or a.y1 ~= b.y1 or a.y2 ~= b.y2 or a.tool ~= b.tool then return false end
  local ra, rb = a.r or {}, b.r
  if #ra ~= #rb then return false end
  for i = 1, #rb do
    if type(ra[i]) ~= "table" or ra[i][1] ~= rb[i][1] or ra[i][2] ~= rb[i][2] then return false end
  end
  return true
end

local function Finish(j)
  job = nil
  local db = DB()
  if not db then return end
  local key, prof = j.key, j.prof
  local list = db.recipes[key]
  if type(list) ~= "table" then list = {}; db.recipes[key] = list end

  local complete = j.full and j.loading == 0
  if complete and j.count == 0 then
    -- a full list without a single learned recipe is almost surely a half-loaded window: keep what we have
    for _, r in pairs(list) do if r.p == prof then complete = false; break end end
  end

  local changed = false
  if complete then
    for id, r in pairs(list) do
      if r.p == prof and not j.out[id] then list[id] = nil; changed = true end
    end
  end
  for id, r in pairs(j.out) do
    if not SameRecipe(list[id], r) then changed = true end
    list[id] = r
  end

  if complete then
    session.done[prof] = true
    local c = db.chars[key]
    if type(c) ~= "table" then c = {}; db.chars[key] = c end
    if type(c.captured) ~= "table" then c.captured = {} end
    c.captured[prof] = j.now
  else
    session.tries[prof] = (session.tries[prof] or 0) + 1
  end
  Recipes.lastCapture = { prof = prof, count = j.count, complete = complete, changed = changed, t = j.now }
  if changed then
    allItems = nil
    WC:Fire("RECIPES_UPDATED", key)
  end
end

local function Step(j)
  if j.gen ~= generation then return end
  if OpenProfession() ~= j.prof then job = nil; return end   -- window closed / profession switched
  local T = C_TradeSkillUI
  local ids, done = j.ids, 0
  while j.i <= #ids and done < PER_FRAME do
    local id = ids[j.i]
    j.i, done = j.i + 1, done + 1
    if type(id) == "number" and not j.seen[id] then
      j.seen[id] = true
      local r, why = ReadRecipe(T, id, j.prof, j.now)
      if r then j.out[id] = r; j.count = j.count + 1
      elseif why == "loading" then j.loading = j.loading + 1 end
    end
  end
  if j.i <= #ids then
    C_Timer.After(0, function() Step(j) end)
  else
    Finish(j)
  end
end

-- start a capture of the open trade skill now (cancels a running one). Returns true if one started.
function Recipes:Capture()
  generation = generation + 1
  job = nil
  if not DB() then return false end
  local prof, profName = OpenProfession()
  if not prof then return false end
  local T = C_TradeSkillUI
  local ids, full = nil, true
  if type(T.GetAllRecipeIDs) == "function" then
    local ok, v = pcall(T.GetAllRecipeIDs)          -- learned + unlearned, ignores the window's filters
    if ok and type(v) == "table" and #v > 0 then ids = v end
  end
  if not ids and type(T.GetFilteredRecipeIDs) == "function" then
    local ok, v = pcall(T.GetFilteredRecipeIDs)     -- respects filters: only add/update, never remove
    if ok and type(v) == "table" and #v > 0 then ids, full = v, false end
  end
  if not ids then return false end
  job = { gen = generation, key = WC:CharKey(), prof = prof, name = profName, ids = ids, i = 1, seen = {},
          out = {}, count = 0, loading = 0, full = full, now = Now() }
  Step(job)
  return true
end

-- debounced capture; force = restart even if this profession was already captured in this window
local function Schedule(force)
  if not force then
    local prof = OpenProfession()
    if not prof or session.done[prof] or (session.tries[prof] or 0) >= MAX_TRIES then return end
    if job and job.prof == prof and job.gen == generation then return end   -- already reading it
  end
  pending = pending + 1
  local token = pending
  C_Timer.After(DEBOUNCE, function()
    if token == pending then Recipes:Capture() end
  end)
end

-- ---------------------------------------------------------------------------
-- public read API

local EMPTY = setmetatable({}, { __newindex = function() end })

-- recipes table of a character (current character by default); never nil, may be empty
function Recipes:ForChar(charKey)
  local db = DB()
  local list = db and db.recipes[charKey or WC:CharKey()]
  if type(list) == "table" then return list end
  return EMPTY
end

function Recipes:HasData(charKey)
  return next(self:ForChar(charKey)) ~= nil
end

-- { [skillLine] = { name, rank, max } } of a character (current by default); never nil
function Recipes:Professions(charKey)
  local db = DB()
  local c = db and db.chars[charKey or WC:CharKey()]
  if type(c) == "table" and type(c.profs) == "table" then return c.profs end
  if not charKey or charKey == WC:CharKey() then
    local profs = ReadProfessions()
    if profs then return profs end
  end
  return EMPTY
end

-- time of the last complete capture of a profession, or nil if it was never read
function Recipes:CapturedAt(skillLine, charKey)
  local db = DB()
  local c = db and db.chars[charKey or WC:CharKey()]
  return type(c) == "table" and type(c.captured) == "table" and c.captured[skillLine] or nil
end

-- set { [itemID] = true } of every reagent and product of every character's recipes (cached)
function Recipes:AllItemIDs()
  if allItems then return allItems end
  local set = {}
  local db = DB()
  if not db then return set end
  for _, list in pairs(db.recipes) do
    if type(list) == "table" then
      for _, r in pairs(list) do
        if r.o then set[r.o] = true end
        if type(r.r) == "table" then
          for i = 1, #r.r do set[r.r[i][1]] = true end
        end
      end
    end
  end
  allItems = set
  return set
end

-- Enchanting skill of a character (current by default), or nil if it doesn't have Enchanting
function WC:EnchantingSkill(charKey)
  local p = Recipes:Professions(charKey)[ENCHANTING]
  return p and p.rank or nil
end

-- ---------------------------------------------------------------------------
-- events

local frame = CreateFrame("Frame")
local skillToken = 0
local function OnEvent(_, event, ...)
  if event == "TRADE_SKILL_SHOW" then
    session = { done = {}, tries = {} }
    Recipes:UpdateChar(false)
    Schedule(true)
  elseif event == "TRADE_SKILL_LIST_UPDATE" then
    Schedule(false)
  elseif event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    Schedule(true)
  elseif event == "TRADE_SKILL_DATA_SOURCE_CHANGING" then
    generation = generation + 1; job = nil
  elseif event == "TRADE_SKILL_CLOSE" then
    generation = generation + 1; job = nil
    pending = pending + 1
    session = { done = {}, tries = {} }
  elseif event == "NEW_RECIPE_LEARNED" then
    session.done, session.tries = {}, {}
    Schedule(false)
  elseif event == "SKILL_LINES_CHANGED" then
    -- fires for every weapon skill-up too: debounce and only fire RECIPES_UPDATED on real changes
    skillToken = skillToken + 1
    local token = skillToken
    C_Timer.After(1, function() if token == skillToken then Recipes:UpdateChar(true) end end)
  elseif event == "PLAYER_LOGIN" then
    Recipes:UpdateChar(false)
  end
end
frame:SetScript("OnEvent", function(...)
  local ok, err = pcall(OnEvent, ...)
  if not ok and WC.Debug then WC.Debug("Recipes", err) end
end)
for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED",
                     "TRADE_SKILL_DATA_SOURCE_CHANGING", "TRADE_SKILL_CLOSE", "NEW_RECIPE_LEARNED",
                     "SKILL_LINES_CHANGED", "PLAYER_LOGIN" }) do
  pcall(frame.RegisterEvent, frame, e)
end

WC:On("DB_READY", function()
  ready = true
  allItems = nil
end)
