#!/usr/bin/env python3
"""wowmock - a strict mock of the WoW Forever 1.60.1 (build 70450) client for running WaylaidCrate under Lua 5.1 (lupa).

    from wowmock import WowClient
    c = WowClient(locale="zhCN")                 # strict by default; every item in tests/fixtures/items.json is cached
    c.load_sv("/home/claude/brief/sv/WaylaidCrate.lua")   # optional: SavedVariables applied before ADDON_LOADED
    WC = c.load_addon("WaylaidCrate/WaylaidCrate.toc")    # runs the files in TOC order, fires ADDON_LOADED
    c.login()                                    # PLAYER_LOGIN + PLAYER_ENTERING_WORLD
    c.set_listings(2589, [(10, 30), (12, 200)])  # AH rows (unit price, quantity) - row count != unit total
    c.open_ah(); c.advance(60)                   # simulated clock; timers only advance here
    print(c.texts())                             # visible FontString texts of WaylaidCrateFrame
    assert not c.problems()                      # Lua errors, strict violations, unexpected globals

Strictness (API surface from tests/fixtures/forever_api.json = the client's Blizzard_APIDocumentationGenerated, build 70450):
  * reading an undefined global raises "wowmock strict: global 'X' does not exist ..." (allow-list ALLOW_ABSENT for names an
    addon may legitimately probe: removed globals like GetItemInfo, load-on-demand frames before their addon loads, ...);
  * reading an undefined member of a C_* namespace, Enum, Enum.X or SOUNDKIT raises; documented-but-unmocked functions
    return nothing and are listed as "mock gaps" (c.gaps);
  * calling a widget method that the widget type does not have (e.g. SetBackdrop without BackdropTemplate, SetText on a
    plain Frame) raises; SetScript with a handler the type lacks, RegisterEvent with an unknown event, invalid anchor
    points / strata / justify values, SetText on a FontString without a font, unknown templates / font objects raise
    like the client does; wrong argument types to client APIs raise "Usage: ...";
  * SetScript on a Blizzard frame (AH / profession rows ...) from addon code is recorded as "taint" (use HookScript);
  * the client has no `debug` / `io` / `require`: addon use of them is flagged;
  * every violation is also recorded (c.violations) so ones swallowed by pcall still fail the test;
  * errors escaping event handlers / timers / scripts are caught like the in-game error handler and listed (c.errors).
Client behaviour modelled: SavedVariables applied after files run and before ADDON_LOADED; C_Item.GetItemInfo returns nil
until the item is cached (GET_ITEM_INFO_RECEIVED later; bag and loot items are always cached); RequestLoadItemDataByID fires
ITEM_DATA_LOAD_RESULT synchronously for cached items too; AH targeted searches deliver rows (GetNum*SearchResults) whose
units differ from Get*SearchResultsQuantity, paged by AH.resultPageSize; browse results arrive in pages (BROWSE_RESULTS_
UPDATED, then _ADDED per RequestMoreBrowseResults); throttled AH messages: one in flight, later ones queued FIFO (max 3,
then DROPPED), 100 per minute; Blizzard_AuctionHouseUI and Blizzard_Professions are load-on-demand (ADDON_LOADED);
C_Timer and OnUpdate only advance through c.advance(); frames have real anchor-based layout (GetWidth/GetTop/... work).

Python API (WowClient):
  setup      add_item, cache/uncache, set_char (fixture characters), set_professions, set_recipes, learn_disenchant,
             load_sv, load_addon, login, logout_sv (client-style SV serializer), complete_quest
  time       advance(seconds, until=callable), now, server_time, set_server_time, fire(event, ...)
  AH         set_listings(itemID, rows, commodity=None), clear_listings, load_orderbooks (real SV books), open_ah,
             close_ah, ah_stats (searches per item, info calls per item, browses, drops, Blizzard queries),
             ah_blizzard_search / ah_blizzard_browse (Blizzard's own UI queries), ah_show_browse / _commodity / _item,
             ah_rows; knobs on c.M.AH: browsePageSize, resultPageSize, latency, dropNext, noAnswer[id], notLoadedOnce[id]
  game       open_profession(skillLine) / close_profession / recipe_rows, open_merchant / close_merchant, set_bags,
             add_bag_item, bag_count, find_bag_slot, disenchant(bag, slot, loot, autoloot, order, interrupt), loot_window
  UI         slash("/wc scan"), click_text(text), buttons, hover(widget) / hover_text(text) -> tooltip lines,
             tooltip_lines, type_into(editbox, text), scroll(widget, delta), texts(root, clip=True) (visible FontStrings,
             top-to-bottom), find_texts(regex), regions(root, kind)
  inspect    count_regions, addon_widget_count(kind), running_timers, onupdate_frames, playing_animations,
             idle_report, memory_kb, errors, violations, gaps, chat, sounds, new_globals, unexpected_globals,
             problems() (everything that should fail a test), report()
"""
import json, os, re, sys, time as _time

os.environ["TZ"] = "UTC"
try:
    _time.tzset()
except AttributeError:
    pass

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, "fixtures")
REPO = os.path.abspath(os.path.join(HERE, ".."))
DEFAULT_CHAR = "Player-0000-0000000A"      # user's Blacksmithing + Enchanting character (Getrich SV)
SECOND_CHAR = "Player-0000-0000000B"       # user's Tailoring + Enchanting character
SERVER_TIME0 = 1792600000                  # 2026-10-21 (the user's SV timestamps are ~1792.0M-1792.5M)

# names an addon may read even though they do not exist (feature probes / load-on-demand frames). Reading them returns nil.
ALLOW_ABSENT = [
    # removed or renamed globals that addons probe as fallbacks
    "GetItemInfo", "GetItemCount", "GetMerchantItemInfo", "GetAddOnMetadata", "IsAddOnLoaded", "LoadAddOn",
    "GetFactionInfoByID", "IsQuestFlaggedCompleted", "GetContainerNumSlots", "GetContainerItemInfo",
    "GetContainerItemLink", "GetContainerItemID", "GetSpellInfo", "IsAuctionHouseEnabled", "GetAuctionItemInfo",
    "InterfaceOptions_AddCategory", "EasyMenu", "GetItemQualityColor", "GetTradeSkillLine", "GetNumTradeSkills",
    "GetTradeSkillInfo", "GetCraftInfo", "GetNumCrafts", "UIDropDownMenu_EnableDropDown", "GetQuestsCompleted",
    # frames / tables that exist only after a load-on-demand Blizzard addon loaded
    "AuctionHouseFrame", "AuctionHouseFrameDisplayMode", "ProfessionsFrame", "Professions", "ProfessionsUtil",
    "AuctionFrame", "TradeSkillFrame", "CraftFrame", "AuctionHouseUtil",
    # Lua libraries the client does not ship (probing is fine, using is not)
    "jit", "bit32", "utf8",
]

INVALID_TEMPLATE_HINT = {
    "UIPanelInputBoxTemplate": "does not exist on Forever (use InputBoxTemplate)",
    "TabButtonTemplate": "does not exist on Forever (use PanelTabButtonTemplate)",
    "CharacterFrameTabButtonTemplate": "not loaded for the camelot (Forever) game type",
    "ChatConfigCheckButtonTemplate": "does not exist on Forever (use UICheckButtonTemplate)",
}


def _json(name):
    with open(os.path.join(FIXTURES, name), encoding="utf-8") as f:
        return json.load(f)


# =====================================================================================================================
# Lua: core (strict environment, clock, events, protected calls)
# =====================================================================================================================
LUA_CORE = r'''
local CFG, API = ...
local getinfo, traceback = debug.getinfo, debug.traceback
local MOCK = {
  strict = CFG.strict, locale = CFG.locale,
  violations = {}, vindex = {}, gaps = {}, gapIndex = {}, absent = {}, errors = {}, chat = {}, newGlobals = {},
  namedFrames = {}, missingFiles = {}, sounds = {}, stats = { events = {} }, prints = {},
}
rawset(_G, "__WOWMOCK", MOCK)
MOCK.API = API
MOCK.SCROLLBOX_METHODS = {}
for _, n in ipairs(API.scrollbox_methods or {}) do MOCK.SCROLLBOX_METHODS[#MOCK.SCROLLBOX_METHODS + 1] = n end
local DOC_GLOBALS, DOC_NS, DOC_EVENTS, DOC_ENUMS = API.globals, API.ns, API.events, API.enums
local UI_GLOBALS, ALLOW_ABSENT = API.ui_globals, API.allow_absent

local function addonWhere(level)
  for l = level, level + 14 do
    local info = getinfo(l, "Sl")
    if not info then break end
    local src = info.source or ""
    if src:sub(1, 1) == "@" and src:find("WaylaidCrate/", 1, true) then return src:sub(2) .. ":" .. (info.currentline or 0) end
  end
  return nil
end
MOCK.addonWhere = addonWhere

local function violation(kind, name, level)
  local w = addonWhere((level or 2) + 1) or "(not addon code)"
  local key = kind .. " " .. name .. " @ " .. w
  local v = MOCK.vindex[key]
  if not v then
    v = { kind = kind, name = name, where = w, n = 0 }
    MOCK.vindex[key] = v
    MOCK.violations[#MOCK.violations + 1] = v
  end
  v.n = v.n + 1
end
MOCK.violation = violation

local function strictError(kind, name, msg, level)
  violation(kind, name, (level or 2) + 1)
  if MOCK.strict then error("wowmock strict: " .. msg, (level or 2) + 1) end
end
MOCK.strictError = strictError

-- wrong arguments to a client API: recorded (even if the caller pcall-wraps it) and raised like the client does
function MOCK.usage(msg, level)
  violation("usage", msg, (level or 2) + 1)
  error(msg, (level or 2) + 1)
end

local function gap(name)
  local g = MOCK.gapIndex[name]
  if not g then g = { name = name, n = 0, where = addonWhere(3) }; MOCK.gapIndex[name] = g; MOCK.gaps[#MOCK.gaps + 1] = g end
  g.n = g.n + 1
end
MOCK.gap = gap
local function gapStub(name) return function() gap(name) end end

-- protected call like the client's error handler: errors are recorded, never propagated
local function protected(context, fn, ...)
  local n, a = select("#", ...), { ... }
  local ok, err = xpcall(function() return fn(unpack(a, 1, n)) end,
    function(e) return { msg = tostring(e), tb = traceback("", 2) } end)
  if not ok then
    local e = { context = context, msg = err.msg, tb = err.tb, t = MOCK.clock and MOCK.clock.now }
    MOCK.errors[#MOCK.errors + 1] = e
    if CFG.verbose then print("  !! LUA ERROR (" .. context .. "): " .. err.msg) end
  end
  return ok
end
MOCK.protected = protected

-- strict namespace tables
local function NS(name, impl)
  local doc = DOC_NS[name] or {}
  return setmetatable(impl or {}, { __index = function(t, k)
    if type(k) == "string" and doc[k] then gap(name .. "." .. k); local f = gapStub(name .. "." .. k); rawset(t, k, f); return f end
    if ALLOW_ABSENT[name .. "." .. tostring(k)] then MOCK.absent[name .. "." .. tostring(k)] = true; return nil end
    strictError("api", name .. "." .. tostring(k), name .. "." .. tostring(k) .. " does not exist in the WoW Forever 1.60.1 client", 2)
    return nil
  end })
end
MOCK.NS = NS

-- strict Enum (values from the client's API documentation)
local function strictEnum(ename, vals)
  local e = {}
  for k, v in pairs(vals) do e[k] = v end
  return setmetatable(e, { __index = function(_, k)
    strictError("enum", "Enum." .. ename .. "." .. tostring(k), "Enum." .. ename .. "." .. tostring(k) .. " does not exist (Forever 1.60.1)", 2)
  end })
end
Enum = setmetatable({}, { __index = function(t, k)
  local vals = DOC_ENUMS[k]
  if vals then local e = strictEnum(k, vals); rawset(t, k, e); return e end
  strictError("enum", "Enum." .. tostring(k), "Enum." .. tostring(k) .. " does not exist (Forever 1.60.1)", 2)
end })

-- ------------------------------------------------------------------------------------------------ clock and timers
local clock = { now = CFG.clock0, server0 = CFG.server0, start = CFG.clock0, frameNo = 0 }
MOCK.clock = clock
local timers, tseq = {}, 0
MOCK.timers = timers
local function schedule(delay, fn, label, internal, arg)
  tseq = tseq + 1
  local t = { at = clock.now + math.max(delay or 0, 0), fn = fn, seq = tseq, label = label, internal = internal,
              created = clock.now, where = (not internal) and addonWhere(3) or nil, arg = arg }
  timers[#timers + 1] = t
  return t
end
MOCK.schedule = schedule
function MOCK.after(delay, fn, label) return schedule(delay, fn, "mock:" .. (label or "?"), true) end

function GetTime() return clock.now end
function GetTimePreciseSec() return clock.now end
function GetServerTime() return math.floor(clock.server0 + (clock.now - clock.start)) end
function debugprofilestop() return clock.now * 1000 end
function debugprofilestart() end
local osdate, ostime, osclock, osdifftime = os.date, os.time, os.clock, os.difftime
function time(t) if t then return ostime(t) end return GetServerTime() end
function date(fmt, t) return osdate(fmt, t or GetServerTime()) end
function difftime(a, b) return osdifftime(a, b) end
os = { time = time, date = date, clock = function() return clock.now end, difftime = osdifftime }
function GetGameTime() local d = osdate("!*t", GetServerTime()); return d.hour, d.min end

local function newHandle(t, kind)
  local h = { _t = t, _kind = kind }
  function h:Cancel() self._t.cancelled = true; self._cancelled = true end
  function h:IsCancelled() return self._cancelled == true end
  return h
end
C_Timer = NS("C_Timer", {
  After = function(d, cb)
    if type(d) ~= "number" or type(cb) ~= "function" then MOCK.usage("Usage: C_Timer.After(seconds, callback)", 2) end
    schedule(d, cb, "C_Timer.After")
  end,
  NewTimer = function(d, cb)
    if type(d) ~= "number" or type(cb) ~= "function" then MOCK.usage("Usage: C_Timer.NewTimer(seconds, callback)", 2) end
    local t = schedule(d, nil, "C_Timer.NewTimer")
    local h = newHandle(t, "timer")
    t.fn = function() h._done = true; cb(h) end
    return h
  end,
  NewTicker = function(d, cb, iterations)
    if type(d) ~= "number" or type(cb) ~= "function" then MOCK.usage("Usage: C_Timer.NewTicker(seconds, callback, iterations)", 2) end
    local h = { _kind = "ticker", _count = 0, _where = addonWhere(2) }
    function h:Cancel() self._cancelled = true; if self._t then self._t.cancelled = true end end
    function h:IsCancelled() return self._cancelled == true end
    local function tick()
      if h._cancelled then return end
      h._count = h._count + 1
      cb(h)
      if not h._cancelled and (not iterations or h._count < iterations) then h._t = schedule(d, tick, "C_Timer.NewTicker"); h._t.ticker = h
      else h._done = true end
    end
    h._t = schedule(d, tick, "C_Timer.NewTicker"); h._t.ticker = h
    return h
  end,
})

-- frames with OnUpdate scripts / playing animation groups (filled by the widget code)
MOCK.updaters, MOCK.anims = {}, {}
local FRAME_MIN, FRAME_UPD = 1 / 60, 1 / 30
function MOCK.hasActiveUpdates()
  for f in pairs(MOCK.updaters) do if f._scripts.OnUpdate and f:IsVisible() then return true end end
  for g in pairs(MOCK.anims) do if g._playing then return true end end
  return false
end
function MOCK.run(seconds, stopWhen)
  local limit = clock.now + seconds
  local guard = 0
  while true do
    guard = guard + 1
    if guard > 3000000 then error("wowmock: scheduler runaway at t=" .. clock.now) end
    local nextAt
    for i = 1, #timers do local t = timers[i]; if not t.cancelled and (not nextAt or t.at < nextAt) then nextAt = t.at end end
    local busy = MOCK.hasActiveUpdates()
    local step
    if busy then
      step = FRAME_UPD
      if nextAt and nextAt - clock.now < step then step = math.max(nextAt - clock.now, FRAME_MIN) end
    elseif nextAt then
      step = math.max(nextAt - clock.now, FRAME_MIN)
    else
      step = limit - clock.now
    end
    if step <= 0 or clock.now + step > limit + 1e-9 then
      if clock.now < limit then clock.now = limit end
      return
    end
    local prev = clock.now
    clock.now = clock.now + step
    clock.frameNo = clock.frameNo + 1
    local due = {}
    for i = #timers, 1, -1 do
      local t = timers[i]
      if t.cancelled then table.remove(timers, i)
      elseif t.at <= clock.now + 1e-9 then due[#due + 1] = t; table.remove(timers, i) end
    end
    table.sort(due, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
    for _, t in ipairs(due) do
      if not t.cancelled and t.fn then protected("timer:" .. tostring(t.label) .. (t.where and (" @ " .. t.where) or ""), t.fn, t.arg) end
    end
    MOCK.stepUpdates(clock.now - prev)
    if stopWhen and stopWhen() then return end
  end
end

-- ------------------------------------------------------------------------------------------------ events
MOCK.eventRegs = {}     -- event -> ordered list of frames
MOCK.allEventFrames = {}
local function unitMatches(units, unit)
  if type(units) ~= "table" then return true end
  for _, u in ipairs(units) do if u == unit then return true end end
  return false
end
function MOCK.fire(event, ...)
  MOCK.stats.events[event] = (MOCK.stats.events[event] or 0) + 1
  local list = {}
  for _, f in ipairs(MOCK.eventRegs[event] or {}) do
    local u = f._events[event]
    if u and (u == true or unitMatches(u, (...))) then list[#list + 1] = f end
  end
  for _, f in ipairs(MOCK.allEventFrames) do list[#list + 1] = f end
  for _, f in ipairs(list) do
    if f._scripts.OnEvent then protected("OnEvent:" .. event, f._scripts.OnEvent, f, event, ...) end
  end
  if MOCK.onEvent then MOCK.onEvent(event, ...) end
end

-- ------------------------------------------------------------------------------------------------ strict globals
setmetatable(_G, {
  __index = function(t, k)
    if type(k) ~= "string" then return nil end
    if k:match("^WaylaidCrate") or k:match("^SLASH_WAYLAIDCRATE") then return nil end
    if ALLOW_ABSENT[k] then MOCK.absent[k] = (MOCK.absent[k] or 0) + 1; return nil end
    if DOC_GLOBALS[k] then gap(k); local f = gapStub(k); rawset(t, k, f); return f end
    if DOC_NS[k] then local ns = NS(k, {}); rawset(t, k, ns); return ns end
    if UI_GLOBALS[k] then
      strictError("ui-global", k, "client global '" .. k .. "' exists in Blizzard's UI code but wowmock does not implement it (mock gap - add it to tests/wowmock.py)", 2)
      return nil
    end
    strictError("global", k, "global '" .. k .. "' does not exist in the WoW Forever 1.60.1 client", 2)
    return nil
  end,
  __newindex = function(t, k, v)
    local w = addonWhere(2)
    if w then MOCK.newGlobals[k] = w end
    rawset(t, k, v)
  end,
})
'''

# =====================================================================================================================
# Lua: widgets, layout, templates, font objects, scroll boxes
# =====================================================================================================================
LUA_WIDGETS = r'''
local CFG, API = ...
local MOCK = __WOWMOCK
local strictError, violation, protected, addonWhere = MOCK.strictError, MOCK.violation, MOCK.protected, MOCK.addonWhere

local KIND_METHODS = {}
for kind, set in pairs(API.widget) do KIND_METHODS[kind] = set end
-- undocumented but real GameTooltip methods (C++), plus a few frame methods missing from the docs
local extra = {
  GameTooltip = { "SetOwner", "AddLine", "AddDoubleLine", "ClearLines", "NumLines", "GetOwner", "IsOwned", "SetHyperlink",
    "SetItemByID", "SetBagItem", "GetItem", "AddTexture", "AppendText", "SetAnchorType", "GetAnchorType", "FadeOut",
    "SetSpellByID", "SetUnit", "GetUnit", "GetSpell", "SetMerchantItem", "SetRecipeResultItem", "SetInventoryItem",
    "GetPrimaryTooltipData", "GetTooltipData", "ProcessInfo", "SetLootItem" },
}
for kind, list in pairs(extra) do for _, m in ipairs(list) do KIND_METHODS[kind][m] = true end end
KIND_METHODS.EventFrame = KIND_METHODS.Frame
KIND_METHODS.DropdownButton = KIND_METHODS.Button
KIND_METHODS.ScrollingMessageFrame = KIND_METHODS.Frame
local ALL_METHODS = {}
for _, set in pairs(KIND_METHODS) do for m in pairs(set) do ALL_METHODS[m] = true end end
-- mixin methods handed out by templates (absent on frames created without the template)
local MIXIN_METHODS = { "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "GetBackdrop", "GetBackdropColor",
  "GetBackdropBorderColor", "ApplyBackdrop", "ClearBackdrop", "OnBackdropLoaded", "OnBackdropSizeChanged", "HasBackdropInfo",
  "SetBorderBlendMode", "SetupTextureCoordinates", "SetDataProvider", "GetDataProvider", "ForEachFrame", "SetTitle", "SetupMenu",
  "SetDefaultText", "GenerateMenu", "RegisterCallback", "TriggerEvent", "UnregisterCallback", "Init", "SetSearchText", "StartSearch" }
for _, m in ipairs(MIXIN_METHODS) do ALL_METHODS[m] = true end
MOCK.KIND_METHODS, MOCK.ALL_METHODS = KIND_METHODS, ALL_METHODS

local SCRIPTS = {
  base = { OnShow = 1, OnHide = 1, OnUpdate = 1, OnEvent = 1, OnEnter = 1, OnLeave = 1, OnMouseDown = 1, OnMouseUp = 1,
    OnMouseWheel = 1, OnDragStart = 1, OnDragStop = 1, OnReceiveDrag = 1, OnSizeChanged = 1, OnLoad = 1, OnAttributeChanged = 1,
    OnKeyDown = 1, OnKeyUp = 1, OnChar = 1, OnHyperlinkClick = 1, OnHyperlinkEnter = 1, OnHyperlinkLeave = 1, OnEnable = 1,
    OnDisable = 1, OnGamePadButtonDown = 1, OnGamePadButtonUp = 1, OnGamePadStick = 1 },
  Button = { OnClick = 1, PreClick = 1, PostClick = 1, OnDoubleClick = 1 },
  EditBox = { OnTextChanged = 1, OnEnterPressed = 1, OnEscapePressed = 1, OnEditFocusGained = 1, OnEditFocusLost = 1,
    OnTabPressed = 1, OnSpacePressed = 1, OnTextSet = 1, OnCursorChanged = 1, OnArrowPressed = 1, OnInputLanguageChanged = 1, OnCharComposition = 1 },
  ScrollFrame = { OnScrollRangeChanged = 1, OnVerticalScroll = 1, OnHorizontalScroll = 1 },
  Slider = { OnValueChanged = 1, OnMinMaxChanged = 1 },
  StatusBar = { OnValueChanged = 1, OnMinMaxChanged = 1 },
  GameTooltip = { OnTooltipSetDefaultAnchor = 1, OnTooltipCleared = 1, OnTooltipAddMoney = 1, OnTooltipSetFrameStack = 1 },
  AnimationGroup = { OnPlay = 1, OnFinished = 1, OnStop = 1, OnLoop = 1, OnPause = 1, OnUpdate = 1 },
  Animation = { OnPlay = 1, OnFinished = 1, OnStop = 1, OnPause = 1, OnUpdate = 1 },
}
SCRIPTS.CheckButton = SCRIPTS.Button
SCRIPTS.DropdownButton = SCRIPTS.Button
local function scriptAllowed(kind, name)
  if kind == "AnimationGroup" or kind == "Animation" then return SCRIPTS[kind][name] end
  return SCRIPTS.base[name] or (SCRIPTS[kind] and SCRIPTS[kind][name])
end
local POINTS = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 1, CENTER = 1, RIGHT = 1, BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1 }
local STRATA = { BACKGROUND = 1, LOW = 1, MEDIUM = 1, HIGH = 1, DIALOG = 1, FULLSCREEN = 1, FULLSCREEN_DIALOG = 1, TOOLTIP = 1, PARENT = 1 }
local LAYERS = { BACKGROUND = 1, BORDER = 1, ARTWORK = 1, OVERLAY = 1, HIGHLIGHT = 1 }
local REGION = { FontString = true, Texture = true, Line = true, MaskTexture = true }
local FRAME_TYPES = { Frame = 1, Button = 1, CheckButton = 1, EditBox = 1, ScrollFrame = 1, Slider = 1, StatusBar = 1,
  GameTooltip = 1, Cooldown = 1, EventFrame = 1, DropdownButton = 1, ScrollingMessageFrame = 1 }
MOCK.FRAME_TYPES = FRAME_TYPES

MOCK.widgets, MOCK.frames = {}, {}
MOCK.created = {}     -- kind -> count
local W = {}          -- method implementations
MOCK.W = W
local Meta = {}
local function isWidget(v) return type(v) == "table" and rawget(v, "_kind") ~= nil end
MOCK.isWidget = isWidget
local function num(v, what, level) if type(v) ~= "number" then error(what .. ": number expected, got " .. type(v), (level or 2) + 1) end end

local function newWidget(kind, name, parent)
  local w = { _kind = kind, _name = name, _parent = parent, _scripts = {}, _shown = true, _points = {}, _events = {},
              _enabled = true, _children = {}, _regions = {}, _alpha = 1, _scale = 1, _level = 1, _strata = "MEDIUM", _anims = {},
              _id = #MOCK.widgets + 1, _created = MOCK.clock.now, _where = addonWhere(3),
              _blizzard = (MOCK.blizzardDepth or 0) > 0 or nil }
  setmetatable(w, Meta)
  MOCK.widgets[#MOCK.widgets + 1] = w
  MOCK.created[kind] = (MOCK.created[kind] or 0) + 1
  if parent and isWidget(parent) then
    if REGION[kind] then parent._regions[#parent._regions + 1] = w else parent._children[#parent._children + 1] = w end
    w._level = (parent._level or 0) + 1
  end
  if name then
    if type(name) == "string" and name:find("$parent", 1, true) then name = name:gsub("%$parent", (parent and parent._name) or "") ; w._name = name end
    rawset(_G, name, w)
    MOCK.namedFrames[name] = addonWhere(3) or "(mock)"
  end
  return w
end
MOCK.newWidget = newWidget

Meta.__index = function(t, k)
  local kind = rawget(t, "_kind")
  local set = KIND_METHODS[kind]
  if set and set[k] then
    local impl = W[k]
    if impl then return impl end
    return W.__generic(k)
  end
  if type(k) == "string" and ALL_METHODS[k] then
    local hint = ""
    if k:find("Backdrop") then hint = " (frames need the BackdropTemplate template for backdrop methods)" end
    strictError("widget", kind .. ":" .. k, kind .. " has no method " .. k .. hint, 2)
    return nil
  end
  return nil
end
local genericCache = {}
function W.__generic(k)
  local f = genericCache[k]
  if not f then
    if k:match("^Is") or k:match("^Has") or k:match("^Can") or k:match("^Does") then f = function() return false end
    else f = function() return nil end end
    genericCache[k] = f
  end
  return f
end

-- --------------------------------------------------------------------------- object basics
function W.GetObjectType(s) return s._kind == "CheckButton" and "CheckButton" or s._kind end
function W.IsObjectType(s, t)
  if s._kind == t then return true end
  if t == "Frame" then return not REGION[s._kind] and s._kind ~= "AnimationGroup" and s._kind ~= "Animation" end
  if t == "Button" then return s._kind == "CheckButton" or s._kind == "DropdownButton" end
  if t == "Region" or t == "ScriptRegion" or t == "Object" then return true end
  if t == "Texture" then return s._kind == "Line" or s._kind == "MaskTexture" end
  return false
end
function W.GetName(s) return s._name end
function W.GetDebugName(s) return s._name or ("<" .. s._kind .. "#" .. s._id .. ">") end
function W.GetParent(s) return s._parent end
function W.SetParent(s, p)
  local old = s._parent
  if old and isWidget(old) then
    local list = REGION[s._kind] and old._regions or old._children
    for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
  end
  s._parent = p
  if p and isWidget(p) then local list = REGION[s._kind] and p._regions or p._children; list[#list + 1] = s end
  MOCK.layoutGen = (MOCK.layoutGen or 0) + 1
end
function W.IsForbidden() return false end
function W.IsProtected() return false, false end
function W.CanChangeProtectedState() return true end
function W.GetObjectTable(s) return s end

-- --------------------------------------------------------------------------- scripts
function W.SetScript(s, name, fn)
  if s._blizzard and addonWhere(2) then
    violation("taint", s._kind .. ":SetScript(" .. tostring(name) .. ") on a Blizzard frame (" .. (s._name or "unnamed") .. ") - use HookScript", 2)
  end
  if REGION[s._kind] then strictError("script", s._kind .. ":SetScript", s._kind .. " regions have no scripts", 2) return end
  if not scriptAllowed(s._kind, name) then
    strictError("script", s._kind .. ":" .. tostring(name), s._kind .. ':SetScript(): ' .. s._kind .. ' doesn\'t have a "' .. tostring(name) .. '" script', 2)
    return
  end
  if fn ~= nil and type(fn) ~= "function" then error(s._kind .. ":SetScript(): handler must be a function or nil", 2) end
  s._scripts[name] = fn
  if name == "OnUpdate" then
    if fn then MOCK.updaters[s] = addonWhere(2) or true else MOCK.updaters[s] = nil end
  end
end
function W.GetScript(s, name) return s._scripts[name] end
function W.HasScript(s, name) return scriptAllowed(s._kind, name) and true or false end
function W.HookScript(s, name, fn)
  if not scriptAllowed(s._kind, name) then
    strictError("script", s._kind .. ":" .. tostring(name), s._kind .. ':HookScript(): doesn\'t have a "' .. tostring(name) .. '" script', 2)
    return
  end
  local old = s._scripts[name]
  s._scripts[name] = function(...) if old then old(...) end; return fn(...) end
  if name == "OnUpdate" then MOCK.updaters[s] = addonWhere(2) or true end
  return true
end
function W.ClearScripts(s) s._scripts = {}; MOCK.updaters[s] = nil end
local function fireScript(s, name, ...)
  local f = s._scripts[name]
  if f then return f(s, ...) end
end
MOCK.fireScript = fireScript

-- --------------------------------------------------------------------------- visibility (OnShow / OnHide propagate to children)
local function visible(s)
  local p = s
  while p do
    if not rawget(p, "_shown") then return false end
    p = rawget(p, "_parent")
    if p and not isWidget(p) then break end
  end
  return true
end
local function propagate(s, script)
  if not REGION[s._kind] then fireScript(s, script) end
  for _, c in ipairs(s._children) do if c._shown then propagate(c, script) end end
end
function W.Show(s)
  if s._shown then return end
  local parentVisible = (not s._parent) or (not isWidget(s._parent)) or visible(s._parent)
  s._shown = true
  if parentVisible then propagate(s, "OnShow") end
end
function W.Hide(s)
  if not s._shown then return end
  local wasVisible = visible(s)
  s._shown = false
  if wasVisible then propagate(s, "OnHide") end
end
function W.SetShown(s, v) if v then s:Show() else s:Hide() end end
function W.IsShown(s) return s._shown end
function W.IsVisible(s) return visible(s) end
MOCK.visible = visible

-- --------------------------------------------------------------------------- size / anchors / layout
MOCK.layoutGen = 0
local function dirty() MOCK.layoutGen = MOCK.layoutGen + 1 end
function W.SetSize(s, w, h) num(w, "SetSize"); num(h or w, "SetSize"); s._w, s._h = w, h or w; dirty()
  if s._scripts.OnSizeChanged then fireScript(s, "OnSizeChanged", s._w, s._h) end end
function W.SetWidth(s, w) num(w, "SetWidth"); s._w = w; dirty() end
function W.SetHeight(s, h) num(h, "SetHeight"); s._h = h; dirty() end
function W.SetPoint(s, point, rel, relPoint, x, y)
  if type(point) ~= "string" or not POINTS[point:upper()] then
    error(s._kind .. ":SetPoint(): Invalid region point " .. tostring(point), 2)
  end
  point = point:upper()
  if type(rel) == "number" then rel, relPoint, x, y = nil, nil, rel, relPoint end
  if type(rel) == "string" then
    local r = rawget(_G, rel)
    if not isWidget(r) then error(s._kind .. ":SetPoint(): Couldn't find region named '" .. rel .. "'", 2) end
    rel = r
  end
  if rel ~= nil and not isWidget(rel) then error(s._kind .. ":SetPoint(): relativeTo must be a region", 2) end
  if rel == s then error(s._kind .. ":SetPoint(): cannot anchor to itself", 2) end
  if type(relPoint) == "number" then relPoint, x, y = nil, relPoint, x end
  if relPoint ~= nil and (type(relPoint) ~= "string" or not POINTS[relPoint:upper()]) then
    error(s._kind .. ":SetPoint(): Invalid relative point " .. tostring(relPoint), 2)
  end
  if x ~= nil and type(x) ~= "number" then error(s._kind .. ":SetPoint(): offsetX must be a number", 2) end
  if y ~= nil and type(y) ~= "number" then error(s._kind .. ":SetPoint(): offsetY must be a number", 2) end
  for i = #s._points, 1, -1 do if s._points[i][1] == point then table.remove(s._points, i) end end
  s._points[#s._points + 1] = { point, rel or false, (relPoint and relPoint:upper()) or point, x or 0, y or 0 }
  dirty()
end
function W.ClearAllPoints(s) s._points = {}; dirty() end
function W.ClearPoint(s, p) for i = #s._points, 1, -1 do if s._points[i][1] == p then table.remove(s._points, i) end end; dirty() end
function W.SetAllPoints(s, rel)
  if type(rel) == "string" then rel = rawget(_G, rel) end
  if rel ~= nil and rel ~= true and not isWidget(rel) then error(s._kind .. ":SetAllPoints(): bad region", 2) end
  if rel == true then rel = nil end
  s._points = { { "TOPLEFT", rel or false, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel or false, "BOTTOMRIGHT", 0, 0 } }
  dirty()
end
function W.GetNumPoints(s) return #s._points end
function W.GetPoint(s, i)
  local p = s._points[i or 1]; if not p then return nil end
  return p[1], p[2] or s._parent, p[3], p[4], p[5]
end
function W.AdjustPointsOffset(s, dx, dy) for _, p in ipairs(s._points) do p[4] = p[4] + dx; p[5] = p[5] + dy end; dirty() end

local SCREEN_W, SCREEN_H = 1920, 1080
local rectCache, rectGen = {}, -1
local function textWidth(s)
  local t = s._text or ""
  t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  "):gsub("|A.-|a", "  ")
  local n = 0
  for ch in t:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + ((#ch > 1) and 12 or 6) end
  return n
end
MOCK.textWidth = textWidth
local hpos = { TOPLEFT = 0, LEFT = 0, BOTTOMLEFT = 0, TOP = 0.5, CENTER = 0.5, BOTTOM = 0.5, TOPRIGHT = 1, RIGHT = 1, BOTTOMRIGHT = 1 }
local vpos = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }
local computeRect
computeRect = function(s, depth)
  if MOCK.layoutGen ~= rectGen then rectCache = {}; rectGen = MOCK.layoutGen end
  local c = rectCache[s]
  if c then return c end
  depth = depth or 0
  if depth > 40 then return { 0, 0, 0, 0, false } end
  if s == UIParent or s == WorldFrame then
    c = { 0, SCREEN_W, SCREEN_H, 0, true }; rectCache[s] = c; return c
  end
  local ew, eh = s._w, s._h
  if s._kind == "FontString" then
    if not ew or ew == 0 then ew = textWidth(s) end
    if not eh or eh == 0 then eh = 12 end
  end
  local L, R, T, B
  local xs, ys = {}, {}
  for _, p in ipairs(s._points) do
    local rel = p[2] or s._parent or UIParent
    if not isWidget(rel) then rel = UIParent end
    local rr = computeRect(rel, depth + 1)
    local ax = rr[1] + (rr[2] - rr[1]) * hpos[p[3]] + p[4]
    local ay = rr[4] + (rr[3] - rr[4]) * vpos[p[3]] + p[5]
    xs[#xs + 1] = { hpos[p[1]], ax }
    ys[#ys + 1] = { vpos[p[1]], ay }
  end
  local function solve(list, extent)
    local lo, hi, mid
    for _, e in ipairs(list) do
      if e[1] == 0 then lo = e[2] elseif e[1] == 1 then hi = e[2] else mid = e[2] end
    end
    extent = extent or 0
    if lo and hi then return lo, hi end
    if lo then return lo, lo + extent end
    if hi then return hi - extent, hi end
    if mid then return mid - extent / 2, mid + extent / 2 end
    return nil
  end
  L, R = solve(xs, ew)
  B, T = solve(ys, eh)
  local valid = L ~= nil and B ~= nil
  -- scroll children are positioned at the scroll frame's top-left minus the scroll offset
  local p = s._parent
  if isWidget(p) and p._kind == "ScrollFrame" and p._scrollChild == s then
    local pr = computeRect(p, depth + 1)
    L = pr[1] - (p._hscroll or 0); R = L + (ew or 0)
    T = pr[3] + (p._vscroll or 0); B = T - (eh or 0)
    valid = pr[5]
  end
  c = { L or 0, R or (ew or 0), T or (eh or 0), B or 0, valid }
  rectCache[s] = c
  return c
end
MOCK.rect = computeRect
function W.GetWidth(s) local r = computeRect(s); local w = r[2] - r[1]; if w == 0 and s._w then return s._w end; return w end
function W.GetHeight(s) local r = computeRect(s); local h = r[3] - r[4]; if h == 0 and s._h then return s._h end; return h end
function W.GetSize(s) return s:GetWidth(), s:GetHeight() end
function W.GetLeft(s) local r = computeRect(s); if r[5] then return r[1] end end
function W.GetRight(s) local r = computeRect(s); if r[5] then return r[2] end end
function W.GetTop(s) local r = computeRect(s); if r[5] then return r[3] end end
function W.GetBottom(s) local r = computeRect(s); if r[5] then return r[4] end end
function W.GetCenter(s) local r = computeRect(s); if r[5] then return (r[1] + r[2]) / 2, (r[3] + r[4]) / 2 end end
function W.GetRect(s) local r = computeRect(s); if r[5] then return r[1], r[4], r[2] - r[1], r[3] - r[4] end end
function W.GetScaledRect(s) return s:GetRect() end
function W.IsRectValid(s) return computeRect(s)[5] end
function W.IsMouseOver(s) return MOCK.mouseFocus == s end
function W.IsMouseMotionFocus(s) return MOCK.mouseFocus == s end
function W.IsAnchoringRestricted() return false end
function W.IsDragging() return false end
function W.EnableMouse(s, v) s._mouse = v and true or false end
function W.IsMouseEnabled(s) return s._mouse == true end
function W.EnableMouseWheel(s, v) s._wheel = v and true or false end
function W.IsMouseWheelEnabled(s) return s._wheel == true end
function W.EnableMouseMotion(s, v) s._motion = v and true or false end
function W.SetMouseClickEnabled(s, v) s._click = v end
function W.SetMouseMotionEnabled(s, v) s._motion = v end

-- --------------------------------------------------------------------------- region / frame appearance
function W.SetAlpha(s, a) num(a, "SetAlpha"); s._alpha = a end
function W.GetAlpha(s) return s._alpha end
function W.GetEffectiveAlpha(s) local a, p = s._alpha, s._parent; while isWidget(p) do a = a * p._alpha; p = p._parent end; return a end
function W.SetScale(s, v) num(v, "SetScale"); if v <= 0 then error("SetScale(): scale must be > 0", 2) end; s._scale = v end
function W.GetScale(s) return s._scale end
function W.GetEffectiveScale(s) local a, p = s._scale, s._parent; while isWidget(p) do a = a * p._scale; p = p._parent end; return a end
function W.SetDrawLayer(s, layer, sub) if not LAYERS[layer] then error("SetDrawLayer(): invalid layer " .. tostring(layer), 2) end; s._layer = layer end
function W.GetDrawLayer(s) return s._layer or "ARTWORK", 0 end
function W.SetVertexColor(s, r, g, b, a) num(r, "SetVertexColor"); num(g, "SetVertexColor"); num(b, "SetVertexColor"); s._vcolor = { r, g, b, a or 1 } end
function W.GetVertexColor(s) local c = s._vcolor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function W.SetIgnoreParentAlpha(s, v) s._ignAlpha = v end
function W.SetIgnoreParentScale(s, v) s._ignScale = v end
function W.SetFrameStrata(s, v) if not STRATA[v] then error(s._kind .. ":SetFrameStrata(): invalid strata " .. tostring(v), 2) end; s._strata = v end
function W.GetFrameStrata(s) return s._strata end
function W.SetFrameLevel(s, v) num(v, "SetFrameLevel"); s._level = v end
function W.GetFrameLevel(s) return s._level end
function W.SetFixedFrameStrata(s, v) end
function W.SetFixedFrameLevel(s, v) end
function W.SetToplevel(s, v) s._toplevel = v end
function W.IsToplevel(s) return s._toplevel == true end
function W.SetMovable(s, v) s._movable = v end
function W.IsMovable(s) return s._movable == true end
function W.SetResizable(s, v) s._resizable = v end
function W.IsResizable(s) return s._resizable == true end
function W.SetResizeBounds(s, a, b, c, d) s._bounds = { a, b, c, d } end
function W.GetResizeBounds(s) local b = s._bounds or {}; return b[1] or 0, b[2] or 0, b[3] or 0, b[4] or 0 end
function W.SetClampedToScreen(s, v) s._clamped = v end
function W.IsClampedToScreen(s) return s._clamped == true end
function W.SetClampRectInsets() end
function W.SetUserPlaced(s, v) s._userPlaced = v end
function W.IsUserPlaced(s) return s._userPlaced == true end
function W.SetDontSavePosition() end
function W.RegisterForDrag(s, ...) s._drag = { ... } end
function W.StartMoving(s) s._moving = true end
function W.StartSizing(s) s._sizing = true end
function W.StopMovingOrSizing(s) s._moving, s._sizing = nil, nil end
function W.SetHitRectInsets(s, l, r, t, b) s._hit = { l, r, t, b } end
function W.GetHitRectInsets(s) local h = s._hit or { 0, 0, 0, 0 }; return h[1], h[2], h[3], h[4] end
function W.SetID(s, v) s._idv = v end
function W.GetID(s) return s._idv or 0 end
function W.SetAttribute(s, k, v) s._attrs = s._attrs or {}; s._attrs[k] = v; if s._scripts.OnAttributeChanged then fireScript(s, "OnAttributeChanged", k, v) end end
function W.GetAttribute(s, k) return s._attrs and s._attrs[k] end
function W.EnableKeyboard(s, v) s._keyboard = v end
function W.IsKeyboardEnabled(s) return s._keyboard == true end
function W.SetPropagateKeyboardInput(s, v) s._propKeys = v end
function W.GetPropagateKeyboardInput(s) return s._propKeys == true end
function W.SetClipsChildren(s, v) s._clips = v end
function W.DoesClipChildren(s) return s._clips == true end
function W.Raise(s) s._level = (s._level or 1) + 1 end
function W.Lower(s) s._level = math.max(0, (s._level or 1) - 1) end
function W.GetChildren(s) return unpack(s._children) end
function W.GetNumChildren(s) return #s._children end
function W.GetRegions(s) return unpack(s._regions) end
function W.GetNumRegions(s) return #s._regions end
function W.LockHighlight(s) s._hlLocked = true end
function W.UnlockHighlight(s) s._hlLocked = false end
function W.SetHighlightLocked(s, v) s._hlLocked = v end

-- --------------------------------------------------------------------------- events on frames
function W.RegisterEvent(s, e)
  if type(e) ~= "string" or not API.events[e] then
    strictError("event", tostring(e), s._kind .. ':RegisterEvent(): Attempt to register unknown event "' .. tostring(e) .. '"', 2)
    return false
  end
  if not s._events[e] then
    local list = MOCK.eventRegs[e]; if not list then list = {}; MOCK.eventRegs[e] = list end
    list[#list + 1] = s
  end
  s._events[e] = true
  return true
end
function W.RegisterUnitEvent(s, e, ...)
  if not W.RegisterEvent(s, e) then return false end
  local units = { ... }
  if #units > 0 then s._events[e] = units end
  return true
end
function W.UnregisterEvent(s, e)
  if s._events[e] then
    s._events[e] = nil
    local list = MOCK.eventRegs[e]
    for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
  end
end
function W.UnregisterAllEvents(s)
  for e in pairs(s._events) do W.UnregisterEvent(s, e) end
  for i = #MOCK.allEventFrames, 1, -1 do if MOCK.allEventFrames[i] == s then table.remove(MOCK.allEventFrames, i) end end
end
function W.RegisterAllEvents(s) MOCK.allEventFrames[#MOCK.allEventFrames + 1] = s end
function W.IsEventRegistered(s, e) return s._events[e] ~= nil end

-- --------------------------------------------------------------------------- font objects and font strings
MOCK.fontObjects = {}
local FontMeta = { __index = function(t, k)
  if KIND_METHODS.Font[k] then return W[k] or W.__generic(k) end
  if type(k) == "string" and ALL_METHODS[k] then strictError("widget", "Font:" .. k, "Font objects have no method " .. k, 2) end
end }
local function newFont(name, size)
  local f = setmetatable({ _kind = "Font", _name = name, _fontSize = size or 12, _color = { 1, 0.82, 0, 1 }, _scripts = {} }, FontMeta)
  if name then rawset(_G, name, f); MOCK.fontObjects[name] = f end
  return f
end
for name in pairs(API.fonts) do newFont(name, name:find("Large") and 16 or (name:find("Small") and 10 or 12)) end
function CreateFont(name) local f = newFont(name); if name then MOCK.namedFrames[name] = addonWhere(2) or "(mock)" end; return f end
function W.CopyFontObject(s, other) if type(other) == "string" then other = rawget(_G, other) end; if type(other) ~= "table" then error("CopyFontObject(): bad font", 2) end; s._fontSize = other._fontSize end
function W.GetFont(s) if not s._font and s._kind ~= "Font" then return nil end; return "Fonts\\FRIZQT__.TTF", s._fontSize or 12, "" end
function W.GetFontHeight(s) return s._fontSize or 12 end
local function resolveFont(f)
  if type(f) == "string" then
    local o = MOCK.fontObjects[f] or rawget(_G, f)
    if type(o) ~= "table" or (o._kind ~= "Font") then return nil end
    return o
  end
  if type(f) == "table" and f._kind == "Font" then return f end
  return nil
end
MOCK.resolveFont = resolveFont
function W.SetFontObject(s, f)
  local o = resolveFont(f)
  if not o then error(s._kind .. ":SetFontObject(): Couldn't find font object " .. tostring(f), 2) end
  s._font = o; s._fontSize = o._fontSize
end
function W.GetFontObject(s) return s._font end
function W.SetFont(s, path, size, flags)
  if type(path) ~= "string" then error(s._kind .. ":SetFont(): Usage: SetFont(path, height[, flags])", 2) end
  if type(size) ~= "number" then error(s._kind .. ":SetFont(): height must be a number", 2) end
  s._font = s._font or true; s._fontSize = size
  return true
end
function W.SetFontHeight(s, h) s._fontSize = h end
function W.SetTextHeight(s, h) s._fontSize = h end
function W.SetText(s, text)
  if text ~= nil and type(text) ~= "string" and type(text) ~= "number" then
    error(s._kind .. ":SetText(): Usage: " .. s._kind .. ":SetText([text]) - got " .. type(text), 2)
  end
  local k = s._kind
  if k == "FontString" or k == "EditBox" then
    if not s._font then error(k .. ":SetText(): Font not set", 2) end
    local old = s._text
    s._text = text ~= nil and tostring(text) or (k == "EditBox" and "" or nil)
    if k == "EditBox" then
      if s._maxLetters and s._maxLetters > 0 and #s._text > s._maxLetters then s._text = s._text:sub(1, s._maxLetters) end
      fireScript(s, "OnTextSet")
      fireScript(s, "OnTextChanged", false)
    end
    dirty()
  elseif k == "Button" or k == "CheckButton" or k == "DropdownButton" then
    local fs = s._fontString
    if fs then fs:SetText(text) end
    s._text = text ~= nil and tostring(text) or nil
  elseif k == "GameTooltip" then
    s:ClearLines(); s:AddLine(text)
  else
    strictError("widget", k .. ":SetText", k .. " has no method SetText", 2)
  end
end
function W.SetFormattedText(s, fmt, ...) return W.SetText(s, string.format(fmt, ...)) end
function W.GetText(s)
  if s._kind == "Button" or s._kind == "CheckButton" or s._kind == "DropdownButton" then
    if s._fontString then return s._fontString._text end
    return s._text
  end
  if s._kind == "EditBox" then return s._text or "" end
  return s._text
end
function W.ClearText(s) s._text = nil end
function W.GetStringWidth(s) return textWidth(s) end
function W.GetUnboundedStringWidth(s) return textWidth(s) end
function W.GetStringHeight(s) return s._fontSize or 12 end
function W.GetWrappedWidth(s) return math.min(textWidth(s), s._w or textWidth(s)) end
function W.IsTruncated(s) return s._w ~= nil and s._w > 0 and textWidth(s) > s._w and not s._wrap end
function W.GetNumLines(s) return 1 end
function W.SetTextColor(s, r, g, b, a) num(r, "SetTextColor"); num(g, "SetTextColor"); num(b, "SetTextColor"); s._color = { r, g, b, a or 1 } end
function W.GetTextColor(s) local c = s._color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function W.SetJustifyH(s, v) if v ~= "LEFT" and v ~= "CENTER" and v ~= "RIGHT" then error(s._kind .. ":SetJustifyH(): invalid value " .. tostring(v), 2) end; s._jh = v end
function W.GetJustifyH(s) return s._jh or "CENTER" end
function W.SetJustifyV(s, v) if v ~= "TOP" and v ~= "MIDDLE" and v ~= "BOTTOM" then error(s._kind .. ":SetJustifyV(): invalid value " .. tostring(v), 2) end; s._jv = v end
function W.GetJustifyV(s) return s._jv or "MIDDLE" end
function W.SetWordWrap(s, v) s._wrap = v and true or false end
function W.CanWordWrap(s) return s._wrap ~= false end
function W.SetNonSpaceWrap(s, v) s._nsw = v end
function W.SetMaxLines(s, n) s._maxLines = n end
function W.GetMaxLines(s) return s._maxLines or 0 end
function W.SetShadowColor() end
function W.SetShadowOffset() end
function W.SetSpacing() end

-- --------------------------------------------------------------------------- textures / lines
local BLEND = { DISABLE = 1, BLEND = 1, ALPHAKEY = 1, ADD = 1, MOD = 1 }
function W.SetTexture(s, tex, wrapH, wrapV, filter)
  if tex ~= nil and type(tex) ~= "string" and type(tex) ~= "number" then error(s._kind .. ":SetTexture(): bad texture " .. type(tex), 2) end
  s._texture = tex; s._colorTex = nil
  return true
end
function W.GetTexture(s) return s._texture end
function W.GetTextureFileID(s) return type(s._texture) == "number" and s._texture or nil end
function W.GetTextureFilePath(s) return type(s._texture) == "string" and s._texture or nil end
function W.SetColorTexture(s, r, g, b, a) num(r, "SetColorTexture"); num(g, "SetColorTexture"); num(b, "SetColorTexture"); s._colorTex = { r, g, b, a or 1 }; s._texture = nil end
function W.SetAtlas(s, atlas, useSize) if type(atlas) ~= "string" then error(s._kind .. ":SetAtlas(): atlas name expected", 2) end; s._atlas = atlas; return true end
function W.GetAtlas(s) return s._atlas end
function W.SetTexCoord(s, ...) local n = select("#", ...); if n ~= 4 and n ~= 8 then error(s._kind .. ":SetTexCoord(): 4 or 8 numbers expected", 2) end; s._texcoord = { ... } end
function W.GetTexCoord(s) return unpack(s._texcoord or { 0, 0, 0, 1, 1, 0, 1, 1 }) end
function W.SetBlendMode(s, v) if not BLEND[v] then error(s._kind .. ":SetBlendMode(): invalid mode " .. tostring(v), 2) end; s._blend = v end
function W.SetDesaturated(s, v) s._desat = v end
function W.IsDesaturated(s) return s._desat == true end
function W.SetGradient(s, orientation, minColor, maxColor)
  if orientation ~= "HORIZONTAL" and orientation ~= "VERTICAL" then error(s._kind .. ":SetGradient(): orientation must be HORIZONTAL or VERTICAL", 2) end
  if type(minColor) ~= "table" or type(maxColor) ~= "table" or not minColor.r or not maxColor.r then
    error(s._kind .. ":SetGradient(orientation, minColor, maxColor): colors must be ColorMixin tables (CreateColor)", 2)
  end
  s._gradient = { orientation, minColor, maxColor }
end
function W.SetRotation(s, r) s._rotation = r end
function W.SetHorizTile(s, v) end
function W.SetVertTile(s, v) end
function W.SetMask(s, m) s._mask = m end
function W.AddMaskTexture(s, m) s._mask = m end
function W.SetSnapToPixelGrid() end
function W.SetTexelSnappingBias() end
function W.SetStartPoint(s, p, rel, x, y) if not POINTS[p] then error("Line:SetStartPoint(): invalid point " .. tostring(p), 2) end; s._start = { p, rel, x, y } end
function W.SetEndPoint(s, p, rel, x, y) if not POINTS[p] then error("Line:SetEndPoint(): invalid point " .. tostring(p), 2) end; s._end = { p, rel, x, y } end
function W.GetStartPoint(s) local p = s._start or {}; return p[1], p[2], p[3], p[4] end
function W.GetEndPoint(s) local p = s._end or {}; return p[1], p[2], p[3], p[4] end
function W.SetThickness(s, v) num(v, "SetThickness"); s._thickness = v end
function W.GetThickness(s) return s._thickness or 1 end

-- --------------------------------------------------------------------------- creating regions
local function applyFontTemplate(fs, template, level)
  if template == nil then return end
  local o = resolveFont(template)
  if not o then
    strictError("template", tostring(template), "CreateFontString(): unknown font template '" .. tostring(template) .. "'", level + 1)
    return
  end
  fs._font = o; fs._fontSize = o._fontSize
end
function W.CreateFontString(s, name, layer, template)
  if layer ~= nil and not LAYERS[layer] then error(s._kind .. ":CreateFontString(): invalid layer " .. tostring(layer), 2) end
  local fs = newWidget("FontString", name, s)
  fs._layer = layer
  applyFontTemplate(fs, template, 2)
  return fs
end
function W.CreateTexture(s, name, layer, template, sublevel)
  if layer ~= nil and not LAYERS[layer] then error(s._kind .. ":CreateTexture(): invalid layer " .. tostring(layer), 2) end
  local t = newWidget("Texture", name, s); t._layer = layer
  return t
end
function W.CreateMaskTexture(s, name, layer) return newWidget("MaskTexture", name, s) end
function W.CreateLine(s, name, layer, template, sublevel)
  if layer ~= nil and not LAYERS[layer] then error(s._kind .. ":CreateLine(): invalid layer " .. tostring(layer), 2) end
  local l = newWidget("Line", name, s); l._layer = layer
  return l
end

-- --------------------------------------------------------------------------- animation groups
local ANIM_TYPES = { Alpha = 1, Translation = 1, Scale = 1, Rotation = 1, Path = 1, FlipBook = 1, VertexColor = 1,
  TextureCoordTranslation = 1, Animation = 1, LineScale = 1, LineTranslation = 1 }
function W.CreateAnimationGroup(s, name, template)
  local g = newWidget("AnimationGroup", name, nil)
  g._owner = s; g._animList = {}; g._looping = "NONE"; g._elapsed = 0
  s._anims[#s._anims + 1] = g
  return g
end
function W.GetAnimationGroups(s) return unpack(s._anims) end
function W.StopAnimating(s) for _, g in ipairs(s._anims) do g:Stop() end end
function W.CreateAnimation(g, atype, name, template)
  if atype ~= nil and not ANIM_TYPES[atype] then error("AnimationGroup:CreateAnimation(): unknown animation type " .. tostring(atype), 2) end
  local a = newWidget("Animation", name, nil)
  a._group = g; a._type = atype or "Animation"; a._duration = 0; a._startDelay = 0; a._endDelay = 0
  g._animList[#g._animList + 1] = a
  return a
end
function W.GetAnimations(g) return unpack(g._animList or {}) end
local function groupDuration(g)
  local d = 0
  for _, a in ipairs(g._animList or {}) do d = math.max(d, (a._startDelay or 0) + (a._duration or 0) + (a._endDelay or 0)) end
  return d
end
function W.Play(g)
  if g._kind == "Animation" then return end
  g._playing = true; g._elapsed = 0; MOCK.anims[g] = addonWhere(2) or true
  fireScript(g, "OnPlay")
end
function W.Restart(g) g:Stop(); g:Play() end
function W.Stop(g)
  if g._kind == "Animation" then return end
  local was = g._playing
  g._playing = false; MOCK.anims[g] = nil
  if was then fireScript(g, "OnStop", false) end
end
function W.Pause(g) g._playing = false; MOCK.anims[g] = nil; fireScript(g, "OnPause") end
function W.Finish(g) g._playing = false; MOCK.anims[g] = nil; fireScript(g, "OnFinished", false) end
function W.IsPlaying(g) return g._playing == true end
function W.IsDone(g) return not g._playing end
function W.IsPaused(g) return false end
function W.SetLooping(g, v) if v ~= "NONE" and v ~= "REPEAT" and v ~= "BOUNCE" then error("AnimationGroup:SetLooping(): invalid " .. tostring(v), 2) end; g._looping = v end
function W.GetLooping(g) return g._looping end
function W.GetDuration(a) if a._kind == "AnimationGroup" then return groupDuration(a) end; return a._duration end
function W.SetDuration(a, d) num(d, "SetDuration"); a._duration = d end
function W.SetStartDelay(a, d) a._startDelay = d end
function W.SetEndDelay(a, d) a._endDelay = d end
function W.SetOrder(a, o) a._order = o end
function W.SetFromAlpha(a, v) a._from = v end
function W.SetToAlpha(a, v) a._to = v end
function W.SetSmoothing(a, v) a._smoothing = v end
function W.SetTarget(a, t) a._target = t end
function W.SetChildKey(a, k) a._childKey = k end
function W.SetTargetKey(a, k) a._targetKey = k end
function W.SetToFinalAlpha(g, v) g._final = v end
function W.GetProgress(g) local d = groupDuration(g); return d > 0 and math.min(1, (g._elapsed or 0) / d) or 0 end
function MOCK.stepUpdates(elapsed)
  local list = {}
  for f in pairs(MOCK.updaters) do list[#list + 1] = f end
  table.sort(list, function(a, b) return a._id < b._id end)
  for _, f in ipairs(list) do
    if f._scripts.OnUpdate and f:IsVisible() then protected("OnUpdate", f._scripts.OnUpdate, f, elapsed) end
  end
  for g in pairs(MOCK.anims) do
    if g._playing then
      g._elapsed = (g._elapsed or 0) + elapsed
      if g._scripts.OnUpdate then protected("AnimOnUpdate", g._scripts.OnUpdate, g, elapsed) end
      local d = groupDuration(g)
      if g._elapsed >= d then
        if g._looping == "NONE" then
          g._playing = false; MOCK.anims[g] = nil
          if g._scripts.OnFinished then protected("AnimOnFinished", g._scripts.OnFinished, g, false) end
        else
          g._elapsed = 0
          if g._scripts.OnLoop then protected("AnimOnLoop", g._scripts.OnLoop, g, "FORWARD") end
        end
      end
    end
  end
end

-- --------------------------------------------------------------------------- buttons
function W.Click(s, button, down)
  if not s._enabled then return end
  button = button or "LeftButton"
  if s._kind == "CheckButton" then s._checked = not s._checked end
  fireScript(s, "PreClick", button, down or false)
  fireScript(s, "OnClick", button, down or false)
  fireScript(s, "PostClick", button, down or false)
end
function W.SetEnabled(s, v) if v then s:Enable() else s:Disable() end end
function W.Enable(s) local was = s._enabled; s._enabled = true; if not was then fireScript(s, "OnEnable") end end
function W.Disable(s) local was = s._enabled; s._enabled = false; if was then fireScript(s, "OnDisable") end end
function W.IsEnabled(s) return s._enabled end
function W.RegisterForClicks(s, ...) s._clicks = { ... } end
function W.RegisterForMouse(s, ...) end
local function texSetter(key)
  return function(s, tex)
    if tex == nil then s[key] = nil; return end
    if isWidget(tex) then s[key] = tex; return end
    if type(tex) ~= "string" and type(tex) ~= "number" then error(s._kind .. ":Set" .. key .. "(): bad texture", 2) end
    local t = rawget(s, key)
    if not t then t = newWidget("Texture", nil, s); rawset(s, key, t) end
    t._texture = tex
  end
end
local function texGetter(key) return function(s)
  local t = rawget(s, key)
  if not t then t = newWidget("Texture", nil, s); rawset(s, key, t) end
  return t end end
W.SetNormalTexture, W.GetNormalTexture = texSetter("_normalTex"), texGetter("_normalTex")
W.SetPushedTexture, W.GetPushedTexture = texSetter("_pushedTex"), texGetter("_pushedTex")
W.SetHighlightTexture, W.GetHighlightTexture = texSetter("_highlightTex"), texGetter("_highlightTex")
W.SetDisabledTexture, W.GetDisabledTexture = texSetter("_disabledTex"), texGetter("_disabledTex")
W.SetCheckedTexture, W.GetCheckedTexture = texSetter("_checkedTex"), texGetter("_checkedTex")
W.SetDisabledCheckedTexture = texSetter("_disCheckedTex")
function W.SetNormalAtlas(s, a) texGetter("_normalTex")(s)._atlas = a end
function W.SetHighlightAtlas(s, a) texGetter("_highlightTex")(s)._atlas = a end
function W.SetPushedAtlas(s, a) texGetter("_pushedTex")(s)._atlas = a end
function W.SetDisabledAtlas(s, a) texGetter("_disabledTex")(s)._atlas = a end
function W.ClearNormalTexture(s) s._normalTex = nil end
function W.ClearHighlightTexture(s) s._highlightTex = nil end
function W.SetNormalFontObject(s, f)
  local o = resolveFont(f); if not o then error(s._kind .. ":SetNormalFontObject(): unknown font " .. tostring(f), 2) end
  if not s._fontString then
    local fs = newWidget("FontString", nil, s); fs._font = o; fs._fontSize = o._fontSize; fs._text = s._text
    fs._points = { { "CENTER", false, "CENTER", 0, 0 } }
    s._fontString = fs
  else s._fontString._font = o end
end
function W.SetHighlightFontObject(s, f) if not resolveFont(f) then error("SetHighlightFontObject(): unknown font", 2) end end
function W.SetDisabledFontObject(s, f) if not resolveFont(f) then error("SetDisabledFontObject(): unknown font", 2) end end
function W.GetFontString(s) return s._fontString end
function W.SetFontString(s, fs) s._fontString = fs end
function W.GetTextWidth(s) return s._fontString and textWidth(s._fontString) or 0 end
function W.GetTextHeight(s) return 12 end
function W.SetButtonState(s, st, locked) s._bstate = st end
function W.GetButtonState(s) return s._bstate or "NORMAL" end
function W.SetPushedTextOffset() end
function W.SetMotionScriptsWhileDisabled(s, v) s._motionDisabled = v end
function W.SetChecked(s, v) s._checked = v and true or false end
function W.GetChecked(s) return s._checked == true end

-- --------------------------------------------------------------------------- edit boxes
function W.SetFocus(s) if MOCK.focus and MOCK.focus ~= s then MOCK.focus:ClearFocus() end; MOCK.focus = s; fireScript(s, "OnEditFocusGained") end
function W.ClearFocus(s) if MOCK.focus == s then MOCK.focus = nil; fireScript(s, "OnEditFocusLost") end end
function W.HasFocus(s) return MOCK.focus == s end
function W.SetAutoFocus(s, v) s._autoFocus = v end
function W.IsAutoFocus(s) return s._autoFocus ~= false end
function W.SetMaxLetters(s, n) s._maxLetters = n end
function W.GetMaxLetters(s) return s._maxLetters or 0 end
function W.SetMaxBytes(s, n) end
function W.SetNumeric(s, v) s._numeric = v end
function W.IsNumeric(s) return s._numeric == true end
function W.GetNumber(s) return tonumber(s._text or "") or 0 end
function W.SetNumber(s, n) W.SetText(s, tostring(n)) end
function W.SetMultiLine(s, v) s._multi = v end
function W.IsMultiLine(s) return s._multi == true end
function W.SetTextInsets() end
function W.GetTextInsets() return 0, 0, 0, 0 end
function W.HighlightText() end
function W.ClearHighlightText() end
function W.SetCursorPosition(s, p) s._cursor = p end
function W.GetCursorPosition(s) return s._cursor or 0 end
function W.GetNumLetters(s) return #(s._text or "") end
function W.HasText(s) return (s._text or "") ~= "" end
function W.Insert(s, t) W.SetText(s, (s._text or "") .. t) end
function W.SetHistoryLines() end
function W.AddHistoryLine() end
function W.SetBlinkSpeed() end

-- --------------------------------------------------------------------------- scroll frames / sliders / status bars
function W.SetScrollChild(s, c)
  if not isWidget(c) then error("ScrollFrame:SetScrollChild(): child must be a frame", 2) end
  s._scrollChild = c
  if c._parent ~= s then W.SetParent(c, s) end
  dirty()
end
function W.GetScrollChild(s) return s._scrollChild end
function W.GetVerticalScrollRange(s)
  local c = s._scrollChild; if not c then return 0 end
  return math.max(0, (c._h or c:GetHeight() or 0) - s:GetHeight())
end
function W.GetHorizontalScrollRange(s) return 0 end
function W.SetVerticalScroll(s, v) num(v, "SetVerticalScroll"); s._vscroll = v; dirty(); fireScript(s, "OnVerticalScroll", v) end
function W.GetVerticalScroll(s) return s._vscroll or 0 end
function W.SetHorizontalScroll(s, v) s._hscroll = v; dirty() end
function W.GetHorizontalScroll(s) return s._hscroll or 0 end
function W.UpdateScrollChildRect() end
function W.SetMinMaxValues(s, lo, hi)
  num(lo, s._kind .. ":SetMinMaxValues"); num(hi, s._kind .. ":SetMinMaxValues")
  if lo > hi then error(s._kind .. ":SetMinMaxValues(): min > max", 2) end
  s._min, s._max = lo, hi
  fireScript(s, "OnMinMaxChanged", lo, hi)
  if s._value then local v = math.max(lo, math.min(hi, s._value)); if v ~= s._value then s._value = v; fireScript(s, "OnValueChanged", v, false) end end
end
function W.GetMinMaxValues(s) return s._min or 0, s._max or 0 end
function W.SetValue(s, v, treatAsMouse)
  num(v, s._kind .. ":SetValue")
  if v ~= v then error(s._kind .. ":SetValue(): NaN", 2) end
  v = math.max(s._min or 0, math.min(s._max or 0, v))
  local old = s._value; s._value = v
  if old ~= v then fireScript(s, "OnValueChanged", v, treatAsMouse and true or false) end
end
function W.GetValue(s) return s._value or 0 end
function W.SetValueStep(s, v) s._step = v end
function W.GetValueStep(s) return s._step or 0 end
function W.SetObeyStepOnDrag(s, v) end
function W.SetOrientation(s, v) if v ~= "HORIZONTAL" and v ~= "VERTICAL" then error(s._kind .. ":SetOrientation(): invalid " .. tostring(v), 2) end; s._orient = v end
function W.GetOrientation(s) return s._orient or "HORIZONTAL" end
function W.SetThumbTexture(s, t) if t ~= nil and not isWidget(t) and type(t) ~= "string" and type(t) ~= "number" then error("SetThumbTexture(): bad texture", 2) end; s._thumb = t end
function W.GetThumbTexture(s) if not isWidget(s._thumb) then s._thumb = newWidget("Texture", nil, s) end; return s._thumb end
function W.SetStatusBarTexture(s, t) if t ~= nil and not isWidget(t) and type(t) ~= "string" and type(t) ~= "number" then error("SetStatusBarTexture(): bad texture", 2) end
  if not isWidget(s._sbtex) then s._sbtex = newWidget("Texture", nil, s) end; s._sbtex._texture = t end
function W.GetStatusBarTexture(s) if not isWidget(s._sbtex) then s._sbtex = newWidget("Texture", nil, s) end; return s._sbtex end
function W.SetStatusBarColor(s, r, g, b, a) num(r, "SetStatusBarColor"); num(g, "SetStatusBarColor"); num(b, "SetStatusBarColor"); s._sbcolor = { r, g, b, a or 1 } end
function W.GetStatusBarColor(s) local c = s._sbcolor or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function W.SetReverseFill(s, v) s._reverse = v end
function W.SetFillStyle(s, v) s._fillStyle = v end
function W.SetRotatesTexture() end
function W.SetStatusBarDesaturated() end

-- --------------------------------------------------------------------------- tooltip
MOCK.tooltipPostCalls = {}
function W.SetOwner(s, owner, anchor, x, y)
  if owner ~= nil and not isWidget(owner) then error("GameTooltip:SetOwner(): owner must be a frame", 2) end
  if anchor ~= nil and (type(anchor) ~= "string" or not anchor:match("^ANCHOR_")) then error("GameTooltip:SetOwner(): invalid anchor " .. tostring(anchor), 2) end
  s._owner = owner; s._lines = {}; s._data = nil
end
function W.GetOwner(s) return s._owner end
function W.IsOwned(s, f) return s._owner == f end
function W.ClearLines(s) s._lines = {}; s._data = nil end
function W.AddLine(s, text, r, g, b, wrap)
  if text ~= nil and type(text) ~= "string" and type(text) ~= "number" then error("GameTooltip:AddLine(): text must be a string", 2) end
  s._lines = s._lines or {}; s._lines[#s._lines + 1] = { tostring(text or "") }
end
function W.AddDoubleLine(s, l, r, ...)
  if (l ~= nil and type(l) ~= "string" and type(l) ~= "number") or (r ~= nil and type(r) ~= "string" and type(r) ~= "number") then
    error("GameTooltip:AddDoubleLine(): texts must be strings", 2)
  end
  s._lines = s._lines or {}; s._lines[#s._lines + 1] = { tostring(l or ""), tostring(r or "") }
end
function W.NumLines(s) return #(s._lines or {}) end
function W.AddTexture() end
function W.AppendText(s, t) local l = s._lines and s._lines[1]; if l then l[1] = l[1] .. tostring(t) end end
function W.SetMinimumWidth() end
function W.SetPadding() end
function W.SetAnchorType(s, a) s._anchor = a end
function W.FadeOut(s) s:Hide() end
local function tooltipItem(s, id, link)
  s:ClearLines()
  local it = MOCK.ITEMS[id]
  s._data = { type = 0, id = id, hyperlink = link or (MOCK.itemLink and MOCK.itemLink(id)), lines = {} }
  s:AddLine(it and it.name or ("item:" .. tostring(id)))
  for _, cb in ipairs(MOCK.tooltipPostCalls) do protected("TooltipPostCall", cb, s, s._data) end
end
function W.SetItemByID(s, id) num(id, "GameTooltip:SetItemByID"); tooltipItem(s, id) end
function W.SetHyperlink(s, link)
  if type(link) ~= "string" then error("GameTooltip:SetHyperlink(): link must be a string", 2) end
  local id = tonumber(link:match("item:(%d+)"))
  if id then tooltipItem(s, id, link) else s:ClearLines(); s:AddLine(link) end
end
function W.SetBagItem(s, bag, slot)
  local e = MOCK.BAGS[bag] and MOCK.BAGS[bag][slot]
  if e then tooltipItem(s, e.itemID) end
  return false, false, 0
end
function W.GetItem(s) local d = s._data; if d and d.type == 0 then local it = MOCK.ITEMS[d.id]; return it and it.name, d.hyperlink, d.id end end
function W.GetPrimaryTooltipData(s) return s._data end
function W.GetTooltipData(s) return s._data end

-- --------------------------------------------------------------------------- CreateFrame + templates
MOCK.templateHandlers = {}
local TEMPLATES = API.templates
local function templateChain(name, out, seen)
  out = out or {}; seen = seen or {}
  if seen[name] then return out end
  seen[name] = true
  local t = TEMPLATES[name]
  if t and t[2] then for inh in tostring(t[2]):gmatch("[^,%s]+") do templateChain(inh, out, seen) end end
  out[#out + 1] = name
  return out
end
MOCK.templateChain = templateChain
function MOCK.applyTemplates(f, template, level)
  if template == nil then return end
  if type(template) ~= "string" then error("CreateFrame(): template must be a string", level + 1) end
  for name in template:gmatch("[^,%s]+") do
    if not TEMPLATES[name] and not MOCK.templateHandlers[name] then
      local hint = API.template_hints[name] or "no such template on the Forever client"
      strictError("template", name, "CreateFrame(): Couldn't find inherited node '" .. name .. "' (" .. hint .. ")", level + 1)
    else
      local modeled = false
      for _, n in ipairs(templateChain(name)) do
        local h = MOCK.templateHandlers[n]
        if h then h(f); modeled = true end
      end
      if not modeled then MOCK.gap("template " .. name .. " (exists, not modeled by wowmock)") end
    end
  end
end
local function baseKindOfTemplate(name)
  for _, n in ipairs(templateChain(name)) do
    local t = TEMPLATES[n]
    if t and FRAME_TYPES[t[1]] then return t[1] end
  end
end
function CreateFrame(kind, name, parent, template, id)
  if type(kind) ~= "string" or not FRAME_TYPES[kind] then
    strictError("frametype", tostring(kind), "CreateFrame(): Unknown frame type '" .. tostring(kind) .. "'", 2)
    kind = "Frame"
  end
  if name ~= nil and type(name) ~= "string" then error("CreateFrame(): name must be a string or nil", 2) end
  if parent ~= nil and not isWidget(parent) then
    if type(parent) == "string" and isWidget(rawget(_G, parent)) then parent = rawget(_G, parent)
    else error("CreateFrame(): parent must be a frame", 2) end
  end
  local f = newWidget(kind, name, parent)
  MOCK.frames[#MOCK.frames + 1] = f
  if id then f._idv = id end
  if template then f._template = template; MOCK.applyTemplates(f, template, 2) end
  if f._scripts.OnLoad then protected("OnLoad", f._scripts.OnLoad, f) end
  return f
end
MOCK.baseKindOfTemplate = baseKindOfTemplate

-- frame types created by templates of the right base type: helpers used by the handlers
local function child(f, key, kind, template)
  local c = newWidget(kind, nil, f)
  MOCK.frames[#MOCK.frames + 1] = c
  if template then MOCK.applyTemplates(c, template, 2) end
  if key then rawset(f, key, c) end
  return c
end
local function fstring(f, key, font, text)
  local fs = newWidget("FontString", nil, f)
  if font then fs._font = resolveFont(font); fs._fontSize = fs._font and fs._font._fontSize end
  fs._text = text
  if key then rawset(f, key, fs) end
  return fs
end
local function tex(f, key) local t = newWidget("Texture", nil, f); if key then rawset(f, key, t) end; return t end
MOCK.child, MOCK.fstring, MOCK.tex = child, fstring, tex
'''

# =====================================================================================================================
# Lua: template handlers, Blizzard shared helpers (Mixin, colors, money, tooltips, menus, ScrollBox system)
# =====================================================================================================================
LUA_SHARED = r'''
local CFG, API = ...
local MOCK = __WOWMOCK
local strictError, protected, addonWhere, isWidget = MOCK.strictError, MOCK.protected, MOCK.addonWhere, MOCK.isWidget
local child, fstring, tex, W, NS = MOCK.child, MOCK.fstring, MOCK.tex, MOCK.W, MOCK.NS
local TH = MOCK.templateHandlers

-- ------------------------------------------------------------------------------------- Lua / string helpers WoW adds
function strtrim(s, chars)
  if type(s) ~= "string" then error("strtrim(): string expected", 2) end
  if chars then local p = "[" .. chars:gsub("%p", "%%%0") .. "]"; return (s:gsub("^" .. p .. "+", ""):gsub(p .. "+$", "")) end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
function strsplit(delim, str, pieces)
  if type(delim) ~= "string" or type(str) ~= "string" then error("strsplit(): Usage: strsplit(delimiter, str [, pieces])", 2) end
  local out, set = {}, "[" .. delim:gsub("%p", "%%%0") .. "]"
  local start = 1
  while true do
    if pieces and #out == pieces - 1 then out[#out + 1] = str:sub(start); break end
    local a, b = str:find(set, start)
    if not a then out[#out + 1] = str:sub(start); break end
    out[#out + 1] = str:sub(start, a - 1); start = b + 1
  end
  return unpack(out)
end
function strjoin(delim, ...) return table.concat({ ... }, delim) end
function strconcat(...) return table.concat({ ... }) end
function strsplittable(delim, str, pieces) return { strsplit(delim, str, pieces) } end
string.split, string.trim, string.join = strsplit, strtrim, strjoin
strlen, strsub, strfind, strmatch, strlower, strupper, strrep, strbyte, strchar, strrev, format, gsub, gmatch =
  string.len, string.sub, string.find, string.match, string.lower, string.upper, string.rep, string.byte, string.char, string.reverse, string.format, string.gsub, string.gmatch
strcmputf8i = function(a, b) a, b = a:lower(), b:lower(); if a < b then return -1 elseif a > b then return 1 end return 0 end
tinsert, tremove, sort, getn = table.insert, table.remove, table.sort, table.getn
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function tContains(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function tIndexOf(t, v) for i, x in ipairs(t) do if x == v then return i end end end
function tDeleteItem(t, v) local n = 0; for i = #t, 1, -1 do if t[i] == v then table.remove(t, i); n = n + 1 end end; return n end
function tInvert(t) local o = {}; for k, v in pairs(t) do o[v] = k end; return o end
function tAppendAll(t, src) for _, v in ipairs(src) do t[#t + 1] = v end end
function tFilter(t, pred, isIndexTable) local o = {}; for k, v in pairs(t) do if pred(v) then if isIndexTable then o[#o + 1] = v else o[k] = v end end end; return o end
function tCount(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
table.count = tCount
function CopyTable(t, shallow) local o = {}; for k, v in pairs(t) do if type(v) == "table" and not shallow then o[k] = CopyTable(v) else o[k] = v end end; return o end
function SafePack(...) return { n = select("#", ...), ... } end
function SafeUnpack(t) return unpack(t, 1, t.n) end
function Mixin(object, ...) for i = 1, select("#", ...) do local m = select(i, ...); for k, v in pairs(m) do object[k] = v end end; return object end
function CreateFromMixins(...) return Mixin({}, ...) end
function CreateAndInitFromMixin(m, ...) local o = CreateFromMixins(m); o:Init(...); return o end
function Clamp(v, lo, hi) return math.min(hi, math.max(lo, v)) end
function Saturate(v) return Clamp(v, 0, 1) end
function Lerp(a, b, t) return a + (b - a) * t end
function Round(v) return math.floor(v + 0.5) end
function GetValueOrCallFunction(t, k, ...) local v = t[k]; if type(v) == "function" then return v(...) end; return v end
math.huge = math.huge
-- bit library (the client ships the LuaBitOp-style 'bit' table)
local function tobit(x) x = math.floor(x) % 4294967296; return x end
local function bitop(a, b, f) a, b = tobit(a), tobit(b); local r, m = 0, 1; for _ = 1, 32 do local x, y = a % 2, b % 2; if f(x, y) then r = r + m end; a = (a - x) / 2; b = (b - y) / 2; m = m * 2 end; return r end
bit = {
  band = function(a, b, ...) local r = bitop(a, b, function(x, y) return x == 1 and y == 1 end); if ... then return bit.band(r, ...) end; return r end,
  bor = function(a, b, ...) local r = bitop(a, b, function(x, y) return x == 1 or y == 1 end); if ... then return bit.bor(r, ...) end; return r end,
  bxor = function(a, b) return bitop(a, b, function(x, y) return x ~= y end) end,
  bnot = function(a) return 4294967295 - tobit(a) end,
  lshift = function(a, n) return tobit(a * 2 ^ n) end,
  rshift = function(a, n) return math.floor(tobit(a) / 2 ^ n) end,
}
function hooksecurefunc(t, name, fn)
  if type(t) == "string" then t, name, fn = _G, t, name end
  local orig = t[name]
  if type(orig) ~= "function" then error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 2) end
  rawset(t, name, function(...) local r = { orig(...) }; fn(...); return unpack(r) end)
end
function securecall(fn, ...) if type(fn) == "string" then fn = _G[fn] end; return fn(...) end
function securecallfunction(fn, ...) return fn(...) end
function issecretvalue(v) return false end
function issecurevariable() return true, nil end
function InCombatLockdown() return MOCK.inCombat == true end
function debugstack() return "" end
function debuglocals() return "" end
local errHandler = function(e) error(e) end
function geterrorhandler() return errHandler end
function seterrorhandler(f) errHandler = f end
function CallErrorHandler(...) return errHandler(...) end
function print(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end; MOCK.prints[#MOCK.prints + 1] = table.concat(t, " ") end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function GetCursorPosition() return 960, 540 end
function IsShiftKeyDown() return MOCK.mods.shift == true end
function IsControlKeyDown() return MOCK.mods.ctrl == true end
function IsAltKeyDown() return MOCK.mods.alt == true end
function IsModifierKeyDown() return MOCK.mods.shift or MOCK.mods.ctrl or MOCK.mods.alt or false end
function IsModifiedClick(what) if what == "CHATLINK" or what == "DRESSUP" then return MOCK.mods.shift == true end; return IsModifierKeyDown() end
MOCK.mods = {}
function HandleModifiedItemClick(link) MOCK.lastModifiedClick = link; return IsModifiedClick("CHATLINK") end
function ChatEdit_InsertLink(link) MOCK.lastInsertedLink = link; return false end
function ChatEdit_GetActiveWindow() return nil end
function GetCursorInfo() return nil end
function CursorHasItem() return false end
function ClearCursor() end
function PlaySound(id, channel, forceNoDuplicates)
  if type(id) ~= "number" then error("PlaySound(): soundKitID must be a number (use SOUNDKIT.X)", 2) end
  MOCK.sounds[#MOCK.sounds + 1] = { id = id, t = MOCK.clock.now }
  return true, 1
end
function PlaySoundFile(path) MOCK.sounds[#MOCK.sounds + 1] = { file = path, t = MOCK.clock.now }; return true, 1 end
SOUNDKIT = setmetatable({}, { __index = function(_, k) strictError("soundkit", "SOUNDKIT." .. tostring(k), "SOUNDKIT." .. tostring(k) .. " does not exist in the Forever UI (SoundKitConstants.lua)", 2) end })
for k, v in pairs(API.soundkit) do rawset(SOUNDKIT, k, v) end
function FlashClientIcon() end
function GetFramerate() return 60 end

-- ------------------------------------------------------------------------------------- colors, money, formatting
ColorMixin = {}
function ColorMixin:OnLoad(r, g, b, a) self:SetRGBA(r, g, b, a) end
function ColorMixin:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function ColorMixin:SetRGB(r, g, b) self.r, self.g, self.b = r, g, b end
function ColorMixin:GetRGB() return self.r, self.g, self.b end
function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a or 1 end
function ColorMixin:GetRGBAsBytes() return math.floor(self.r * 255 + 0.5), math.floor(self.g * 255 + 0.5), math.floor(self.b * 255 + 0.5) end
function ColorMixin:GenerateHexColor() return string.format("ff%02x%02x%02x", self:GetRGBAsBytes()) end
function ColorMixin:GenerateHexColorMarkup() return "|c" .. self:GenerateHexColor() end
function ColorMixin:WrapTextInColorCode(t) return "|c" .. self:GenerateHexColor() .. tostring(t) .. "|r" end
function ColorMixin:IsEqualTo(o) return self.r == o.r and self.g == o.g and self.b == o.b end
function CreateColor(r, g, b, a) local c = CreateFromMixins(ColorMixin); c:OnLoad(r, g, b, a); return c end
function CreateColorFromHexString(hex) local a, r, g, b = hex:match("(%x%x)(%x%x)(%x%x)(%x%x)"); return CreateColor(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255, tonumber(a, 16) / 255) end
NORMAL_FONT_COLOR = CreateColor(1, 0.82, 0); HIGHLIGHT_FONT_COLOR = CreateColor(1, 1, 1); RED_FONT_COLOR = CreateColor(1, 0.1, 0.1)
GREEN_FONT_COLOR = CreateColor(0.1, 1, 0.1); GRAY_FONT_COLOR = CreateColor(0.5, 0.5, 0.5); DISABLED_FONT_COLOR = CreateColor(0.5, 0.5, 0.5)
YELLOW_FONT_COLOR = CreateColor(1, 1, 0); ORANGE_FONT_COLOR = CreateColor(1, 0.5, 0.25); WHITE_FONT_COLOR = CreateColor(1, 1, 1)
LIGHTGRAY_FONT_COLOR = CreateColor(0.75, 0.75, 0.75); DARKGRAY_COLOR = CreateColor(0.4, 0.4, 0.4); BLACK_FONT_COLOR = CreateColor(0, 0, 0)
PASSIVE_SPELL_FONT_COLOR = CreateColor(0.77, 0.64, 0); LINK_FONT_COLOR = CreateColor(0.4, 0.73, 1)
local QC = { [0] = { 0.62, 0.62, 0.62, "ff9d9d9d" }, { 1, 1, 1, "ffffffff" }, { 0.12, 1, 0, "ff1eff00" }, { 0, 0.44, 0.87, "ff0070dd" },
  { 0.64, 0.21, 0.93, "ffa335ee" }, { 1, 0.5, 0, "ffff8000" }, { 0.9, 0.8, 0.5, "ffe6cc80" }, { 0, 0.8, 1, "ff00ccff" } }
ITEM_QUALITY_COLORS = {}
for q, c in pairs(QC) do local col = CreateColor(c[1], c[2], c[3]); ITEM_QUALITY_COLORS[q] = { r = c[1], g = c[2], b = c[3], hex = "|c" .. c[4], color = col } end
MOCK.QUALITY_HEX = {}; for q, c in pairs(QC) do MOCK.QUALITY_HEX[q] = c[4] end
function WrapTextInColorCode(text, hex) return "|c" .. hex .. tostring(text) .. "|r" end
function WrapTextInColor(text, color) return color:WrapTextInColorCode(text) end
function BreakUpLargeNumbers(n)
  local s = tostring(math.floor(n)); local neg = s:sub(1, 1) == "-"; if neg then s = s:sub(2) end
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (neg and "-" or "") .. out
end
function FormatLargeNumber(n) return BreakUpLargeNumbers(n) end
GOLD_AMOUNT_SYMBOL, SILVER_AMOUNT_SYMBOL, COPPER_AMOUNT_SYMBOL = "g", "s", "c"
function GetMoneyString(money, separateThousands)
  if type(money) ~= "number" then error("GetMoneyString(): money must be a number", 2) end
  local g, s, c = math.floor(money / 10000), math.floor(money / 100) % 100, money % 100
  local t = {}
  if g > 0 then t[#t + 1] = (separateThousands and BreakUpLargeNumbers(g) or g) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t" end
  if s > 0 then t[#t + 1] = s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t" end
  if c > 0 or #t == 0 then t[#t + 1] = c .. "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" end
  return table.concat(t, " ")
end
GetCoinTextureString = GetMoneyString
function GetCoinText(money) local g, s, c = math.floor(money / 10000), math.floor(money / 100) % 100, money % 100; return g .. "g " .. s .. "s " .. c .. "c" end
function CreateTextureMarkup(file, fw, fh, w, h, l, r, t, b) return "|T" .. tostring(file) .. ":" .. (h or 0) .. "|t" end
function CreateSimpleTextureMarkup(file, w, h) return "|T" .. tostring(file) .. ":" .. (h or w or 0) .. "|t" end
function CreateAtlasMarkup(atlas, w, h) return "|A:" .. tostring(atlas) .. ":" .. (h or 0) .. ":" .. (w or 0) .. "|a" end
function SecondsToTime(sec) sec = math.floor(sec); local m, s = math.floor(sec / 60), sec % 60; if m > 0 then return m .. " Min " .. s .. " Sec" end; return s .. " Sec" end
function SecondsToClock(sec) sec = math.floor(sec); return string.format("%d:%02d", math.floor(sec / 60), sec % 60) end
-- a few GlobalStrings
CLOSE, OKAY, CANCEL, YES, NO, ACCEPT, SEARCH, NONE, UNKNOWN, ALL, DONE = "Close", "Okay", "Cancel", "Yes", "No", "Accept", "Search", "None", "Unknown", "All", "Done"
SEARCH_INSTRUCTIONS = "Search"
for i, s in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }) do rawset(_G, "FACTION_STANDING_LABEL" .. i, s) end
for i, s in pairs({ [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom" }) do rawset(_G, "ITEM_QUALITY" .. i .. "_DESC", s) end
AUCTION_HOUSE_CUT_PERCENTAGE = nil
NUM_BAG_SLOTS = 4
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4
BACKPACK_CONTAINER = 0
Constants = { InventoryConstants = { NumBagSlots = 4, NumReagentBagSlots = 0, NumBankBagSlots = 6 },
              AuctionConstants = { DEFAULT_AUCTION_PRICE_MULTIPLIER = 1.5 } }
WOW_PROJECT_MAINLINE, WOW_PROJECT_CAMELOT, WOW_PROJECT_CLASSIC = 1, 18, 2
WOW_PROJECT_ID = WOW_PROJECT_CAMELOT
LE_EXPANSION_CLASSIC, LE_EXPANSION_LEVEL_CURRENT = 0, 0

-- ------------------------------------------------------------------------------------- callback registry / EventRegistry
CallbackRegistryMixin = {}
local ownerSeq = 0
function CallbackRegistryMixin:OnLoad() self.callbackTables = {} end
function CallbackRegistryMixin:Init() self.callbackTables = {} end
function CallbackRegistryMixin:SetUndefinedEventsAllowed(v) self._undefinedOK = v end
function CallbackRegistryMixin:GenerateCallbackEvents(events) self.Event = self.Event or {}; for _, e in ipairs(events) do self.Event[e] = e end end
function CallbackRegistryMixin:RegisterCallback(event, func, owner, ...)
  if type(event) ~= "string" then error("CallbackRegistryMixin:RegisterCallback 'event' requires string type.", 2) end
  if type(func) ~= "function" then error("CallbackRegistryMixin:RegisterCallback 'func' requires function type.", 2) end
  self.callbackTables = self.callbackTables or {}
  if owner == nil then ownerSeq = ownerSeq + 1; owner = ownerSeq
  elseif type(owner) == "number" then error("CallbackRegistryMixin:RegisterCallback 'owner' as number is reserved internally.", 2) end
  local list = self.callbackTables[event]; if not list then list = {}; self.callbackTables[event] = list end
  for i = #list, 1, -1 do if list[i].owner == owner then table.remove(list, i) end end
  local args = SafePack(...)
  list[#list + 1] = { owner = owner, func = func, args = args }
  return owner
end
function CallbackRegistryMixin:UnregisterCallback(event, owner)
  local list = self.callbackTables and self.callbackTables[event]
  if list then for i = #list, 1, -1 do if list[i].owner == owner then table.remove(list, i) end end end
end
function CallbackRegistryMixin:UnregisterEvents(events) end
function CallbackRegistryMixin:TriggerEvent(event, ...)
  local list = self.callbackTables and self.callbackTables[event]
  if not list then return end
  local copy = {}; for i, e in ipairs(list) do copy[i] = e end
  for _, e in ipairs(copy) do
    if e.args.n > 0 then
      local a = {}; for i = 1, e.args.n do a[i] = e.args[i] end; local n = e.args.n
      for i = 1, select("#", ...) do a[n + i] = select(i, ...) end
      e.func(e.owner, unpack(a, 1, n + select("#", ...)))
    else
      e.func(e.owner, ...)
    end
  end
end
function CallbackRegistryMixin:HasRegistrantsForEvent(event) local l = self.callbackTables and self.callbackTables[event]; return l and #l > 0 end
EventRegistry = CreateFromMixins(CallbackRegistryMixin); EventRegistry:OnLoad()
function EventRegistry:RegisterFrameEventAndCallback(event, fn, owner, ...)
  if not API.events[event] then strictError("event", event, 'EventRegistry: unknown event "' .. tostring(event) .. '"', 2) end
  MOCK.frameEventCallbacks[#MOCK.frameEventCallbacks + 1] = { event = event, fn = fn, owner = owner or true }
  return owner
end
function EventRegistry:UnregisterFrameEventAndCallback(event, owner)
  for i = #MOCK.frameEventCallbacks, 1, -1 do local e = MOCK.frameEventCallbacks[i]; if e.event == event and e.owner == owner then table.remove(MOCK.frameEventCallbacks, i) end end
end
MOCK.frameEventCallbacks = {}
MOCK.addonLoadedCallbacks = {}
MOCK.loadedAddons = {}
EventUtil = {
  ContinueOnAddOnLoaded = function(name, cb)
    if type(name) ~= "string" or type(cb) ~= "function" then error("EventUtil.ContinueOnAddOnLoaded(addOnName, callback)", 2) end
    if MOCK.loadedAddons[name] then cb() else MOCK.addonLoadedCallbacks[#MOCK.addonLoadedCallbacks + 1] = { name = name, cb = cb } end
  end,
  ContinueAfterAllEvents = function(cb, ...) cb() end,
  RegisterOnceFrameEventAndCallback = function(event, cb, ...)
    MOCK.frameEventCallbacks[#MOCK.frameEventCallbacks + 1] = { event = event, fn = function(_, ...) cb(...) end, once = true, owner = true }
  end,
  CreateFrameEventHandler = nil,
}
MOCK.onEvent = function(event, ...)
  for i = #MOCK.frameEventCallbacks, 1, -1 do
    local e = MOCK.frameEventCallbacks[i]
    if e and e.event == event then
      if e.once then table.remove(MOCK.frameEventCallbacks, i) end
      protected("EventRegistry:" .. event, e.fn, e.owner, ...)
    end
  end
  if event == "ADDON_LOADED" then
    local name = ...
    MOCK.loadedAddons[name] = true
    local keep = {}
    for _, e in ipairs(MOCK.addonLoadedCallbacks) do
      if e.name == name then protected("ContinueOnAddOnLoaded:" .. name, e.cb) else keep[#keep + 1] = e end
    end
    MOCK.addonLoadedCallbacks = keep
  end
end

-- ------------------------------------------------------------------------------------- template handlers
local function withText(f, font)
  local fs = fstring(f, "Text", font or "GameFontNormal")
  fs._points = { { "CENTER", false, "CENTER", 0, 0 } }
  f._fontString = fs
  return fs
end
TH.BackdropTemplate = function(f)
  for k, v in pairs(BackdropTemplateMixin) do rawset(f, k, v) end
end
BackdropTemplateMixin = {}
function BackdropTemplateMixin:SetBackdrop(info)
  if info ~= nil and type(info) ~= "table" then error("SetBackdrop(): backdropInfo must be a table or nil", 2) end
  if info and not info.bgFile and not info.edgeFile then info = nil end
  self.backdropInfo = info
  if info and not rawget(self, "Center") then rawset(self, "Center", tex(self)) end
end
function BackdropTemplateMixin:GetBackdrop() return self.backdropInfo and CopyTable(self.backdropInfo) end
function BackdropTemplateMixin:SetBackdropColor(r, g, b, a) if not self.backdropInfo then return end; self._bdColor = { r, g, b, a or 1 } end
function BackdropTemplateMixin:GetBackdropColor() if self._bdColor then return unpack(self._bdColor) end end
function BackdropTemplateMixin:SetBackdropBorderColor(r, g, b, a) if not self.backdropInfo then return end; self._bdBorder = { r, g, b, a or 1 } end
function BackdropTemplateMixin:GetBackdropBorderColor() if self._bdBorder then return unpack(self._bdBorder) end end
function BackdropTemplateMixin:ApplyBackdrop() end
function BackdropTemplateMixin:ClearBackdrop() self.backdropInfo = nil end
function BackdropTemplateMixin:HasBackdropInfo(i) return self.backdropInfo == i end
function BackdropTemplateMixin:OnBackdropLoaded() end
function BackdropTemplateMixin:OnBackdropSizeChanged() end
function BackdropTemplateMixin:SetupTextureCoordinates() end
function BackdropTemplateMixin:SetBorderBlendMode() end
TH.TooltipBackdropTemplate = TH.BackdropTemplate
TH.UIPanelButtonNoTooltipTemplate = function(f)
  tex(f, "Left"); tex(f, "Right"); tex(f, "Middle")
  withText(f, "GameFontNormal")
  f._normalFont = "GameFontNormal"
end
TH.UIPanelButtonTemplate = function(f)
  rawset(f, "SetTooltip", function(self, t) self.tooltip = t end)
end
TH.UIPanelCloseButtonNoScripts = function(f) f._w, f._h = 24, 24 end
TH.UIPanelCloseButton = function(f)
  f._scripts.OnClick = function(self) local p = self:GetParent(); if p then p:Hide() end end
end
TH.UIPanelCloseButtonDefaultAnchors = function(f) end
TH.UICheckButtonArtTemplate = function(f) f._w, f._h = 32, 32 end
TH.UICheckButtonTemplate = function(f)
  local fs = fstring(f, "Text", "GameFontNormalSmall"); fs._points = { { "LEFT", f, "RIGHT", -2, 0 } }
end
TH.UIRadioButtonTemplate = function(f) local fs = fstring(f, "text", "GameFontNormalSmall"); fs._points = { { "LEFT", f, "RIGHT", 5, 0 } } end
TH.InputBoxScriptTemplate = function(f)
  f._scripts.OnEscapePressed = function(self) self:ClearFocus() end
  f._scripts.OnEditFocusLost = function(self) self:HighlightText(0, 0) end
  f._scripts.OnEditFocusGained = function(self) self:HighlightText() end
end
TH.InputBoxVisualTemplate = function(f) tex(f, "Left"); tex(f, "Right"); tex(f, "Middle"); f._font = MOCK.resolveFont("ChatFontNormal") or MOCK.resolveFont("GameFontHighlight"); f._autoFocus = false end
TH.InputBoxTemplate = function(f) end
TH.InputBoxInstructionsTemplate = function(f)
  local fs = fstring(f, "Instructions", "GameFontDisableSmall"); fs._points = { { "TOPLEFT", f, "TOPLEFT", 0, 0 } }
  f._scripts.OnTextChanged = function(self) InputBoxInstructions_OnTextChanged(self) end
end
function InputBoxInstructions_OnTextChanged(self) if self.Instructions then self.Instructions:SetShown(self:GetText() == "") end end
TH.SearchBoxTemplate = function(f)
  local icon = tex(f, "searchIcon")
  local clear = child(f, "clearButton", "Button")
  clear._scripts.OnClick = function(b) local eb = b:GetParent(); eb:SetText(""); eb:ClearFocus() end
  clear:Hide()
  f.Instructions._text = SEARCH
  f._scripts.OnTextChanged = function(self) SearchBoxTemplate_OnTextChanged(self) end
end
function SearchBoxTemplate_OnTextChanged(self)
  local empty = self:GetText() == ""
  if self.Instructions then self.Instructions:SetShown(empty) end
  if self.clearButton then self.clearButton:SetShown(not empty) end
end
function SearchBoxTemplate_OnLoad(self) end
function SearchBoxTemplateClearButton_OnClick(self) local eb = self:GetParent(); eb:SetText(""); eb:ClearFocus() end
TH.UIPanelScrollBarTemplate = function(f)
  child(f, "ScrollUpButton", "Button"); child(f, "ScrollDownButton", "Button"); f._min, f._max, f._value = 0, 0, 0
end
TH.UIPanelScrollFrameCodeTemplate = function(f)
  local bar = child(f, "ScrollBar", "Slider", "UIPanelScrollBarTemplate")
  f._scripts.OnVerticalScroll = function(self, offset) self.ScrollBar:SetValue(offset) end
  f._scripts.OnScrollRangeChanged = function(self, x, y) self.ScrollBar:SetMinMaxValues(0, y or 0) end
  bar._scripts.OnValueChanged = function(b, v) b:GetParent():SetVerticalScroll(v) end
end
TH.UIPanelScrollFrameTemplate = function(f) end
TH.ScrollFrameTemplate = function(f)
  local bar = child(f, "ScrollBar", "EventFrame", "MinimalScrollBar")
end
TH.MinimalScrollBar = function(f) for k, v in pairs(ScrollBarMixin) do rawset(f, k, v) end; f.callbackTables = {} end
TH.VerticalScrollBarTemplate = function(f) end
TH.WowScrollBox = function(f) for k, v in pairs(ScrollBoxListMixin) do rawset(f, k, v) end; f:OnLoad() end
TH.WowScrollBoxList = TH.WowScrollBox
TH.ScrollBoxBaseTemplate = function(f) local t = child(f, "ScrollTarget", "Frame"); t._points = { { "TOPLEFT", f, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0 } } end
TH.SharedTooltipTemplate = function(f) end
TH.GameTooltipTemplate = function(f) end
TH.PanelTabButtonTemplate = function(f)
  tex(f, "Left"); tex(f, "Middle"); tex(f, "Right"); tex(f, "LeftActive"); tex(f, "MiddleActive"); tex(f, "RightActive")
  withText(f, "GameFontNormalSmall")
end
TH.PanelTopTabButtonTemplate = function(f) end
TH.ButtonFrameBaseTemplate = function(f) end
local function titleFrame(f)
  if not rawget(f, "CloseButton") then local cb = child(f, "CloseButton", "Button", "UIPanelCloseButton") end
  local tc = child(f, "TitleContainer", "Frame")
  local tt = fstring(tc, "TitleText", "GameFontNormal"); rawset(f, "TitleText", tt)
  child(f, "NineSlice", "Frame"); tex(f, "Bg")
  rawset(f, "SetTitle", function(self, t) self.TitleText:SetText(t) end)
  rawset(f, "SetTitleFormatted", function(self, fmt, ...) self.TitleText:SetFormattedText(fmt, ...) end)
  rawset(f, "GetTitleText", function(self) return self.TitleText end)
  rawset(f, "SetPortraitToAsset", function() end)
  rawset(f, "SetPortraitTextureRaw", function() end)
  rawset(f, "SetPortraitShown", function() end)
end
TH.PortraitFrameTemplateNoCloseButton = function(f) titleFrame(f) end
TH.PortraitFrameTemplate = function(f) end
TH.ButtonFrameTemplate = function(f) local inset = child(f, "Inset", "Frame") end
TH.BasicFrameTemplate = function(f) titleFrame(f) end
TH.BasicFrameTemplateWithInset = function(f) child(f, "Inset", "Frame") end
TH.DefaultPanelBaseTemplate = function(f) titleFrame(f) end
TH.DefaultPanelTemplate = function(f) end
TH.InsetFrameTemplate = function(f) tex(f, "Bg"); child(f, "NineSlice", "Frame") end
TH.ThinGoldEdgeTemplate = function(f) end
TH.UISliderTemplate = function(f) f._min, f._max, f._value = 0, 0, 0; f._thumb = tex(f, "Thumb") end
TH.UISliderTemplateWithLabels = function(f) fstring(f, "Text", "GameFontNormalSmall"); fstring(f, "Low", "GameFontHighlightSmall"); fstring(f, "High", "GameFontHighlightSmall") end
TH.OptionsSliderTemplate = function(f) end
TH.UIDropDownMenuTemplate = function(f)
  tex(f, "Left"); tex(f, "Middle"); tex(f, "Right")
  fstring(f, "Text", "GameFontHighlightSmall"); child(f, "Button", "Button")
end
TH.UIMenuButtonStretchTemplate = function(f) withText(f, "GameFontHighlightSmall") end
TH.MagicButtonTemplate = function(f) end
TH.SecureFrameTemplate = function(f) end
TH.SecureActionButtonTemplate = function(f) end
TH.WowStyle1DropdownTemplate = function(f)
  withText(f, "GameFontHighlightSmall")
  for k, v in pairs(DropdownButtonMixin) do rawset(f, k, v) end
end
TH.WowStyle2DropdownTemplate = TH.WowStyle1DropdownTemplate
TH.EventButton = function(f) end
DropdownButtonMixin = {}
function DropdownButtonMixin:SetupMenu(gen) if type(gen) ~= "function" then error("SetupMenu(generator): function expected", 2) end; self._menuGen = gen end
function DropdownButtonMixin:GenerateMenu() if self._menuGen then local root = MOCK.menuDescription(); protected("menu", self._menuGen, self, root); self._menu = root end end
function DropdownButtonMixin:SetDefaultText(t) self._defaultText = t; if self._fontString and not self._fontString._text then self._fontString._text = t end end
function DropdownButtonMixin:OverrideText(t) if self._fontString then self._fontString._text = t end end
function DropdownButtonMixin:SetSelectionText(fn) self._selectionText = fn end
function DropdownButtonMixin:Update() end
function DropdownButtonMixin:SetText(t) if self._fontString then self._fontString._text = t end end
function DropdownButtonMixin:IsMenuOpen() return false end
function DropdownButtonMixin:CloseMenu() end
function DropdownButtonMixin:RegisterCallback() end
function MOCK.menuDescription()
  local d = { items = {} }
  local function add(kind, text, ...) local e = { kind = kind, text = text, args = { ... } }; d.items[#d.items + 1] = e
    local sub = MOCK.menuDescription(); e.sub = sub
    local proxy = setmetatable({}, { __index = function(_, k) return sub[k] or function() end end })
    return proxy end
  function d:CreateButton(text, cb, data) return add("button", text, cb, data) end
  function d:CreateRadio(text, isSel, setSel, data) return add("radio", text, isSel, setSel, data) end
  function d:CreateCheckbox(text, isSel, setSel, data) return add("checkbox", text, isSel, setSel, data) end
  function d:CreateTitle(text) return add("title", text) end
  function d:CreateDivider() return add("divider") end
  function d:CreateSpacer() return add("spacer") end
  function d:SetTag() end
  function d:SetScrollMode() end
  return d
end
MenuUtil = { CreateContextMenu = function(owner, gen) local root = MOCK.menuDescription(); protected("menu", gen, owner, root); MOCK.lastMenu = root; return root end,
             CreateButtonMenu = function() end, CreateRadioMenu = function() end }

-- legacy UIDropDownMenu (still loaded on Forever)
UIDROPDOWNMENU_MENU_LEVEL, UIDROPDOWNMENU_MENU_VALUE = 1, nil
function UIDropDownMenu_Initialize(frame, fn, displayMode, level, menuList) frame._ddInit = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info, level) MOCK.ddButtons = MOCK.ddButtons or {}; MOCK.ddButtons[#MOCK.ddButtons + 1] = info end
function UIDropDownMenu_SetWidth(frame, w) frame._w = w end
function UIDropDownMenu_SetText(frame, t) if frame.Text then frame.Text._text = t end end
function UIDropDownMenu_GetText(frame) return frame.Text and frame.Text._text end
function UIDropDownMenu_SetSelectedValue(frame, v) frame._ddValue = v end
function UIDropDownMenu_GetSelectedValue(frame) return frame._ddValue end
function UIDropDownMenu_SetSelectedID(frame, v) frame._ddID = v end
function UIDropDownMenu_JustifyText() end
function CloseDropDownMenus() end
function ToggleDropDownMenu() end

-- PanelTemplates
function PanelTemplates_SetNumTabs(frame, n) frame.numTabs = n end
function PanelTemplates_SetTab(frame, id) frame.selectedTab = id end
function PanelTemplates_GetSelectedTab(frame) return frame.selectedTab end
function PanelTemplates_UpdateTabs(frame) end
function PanelTemplates_TabResize(tab, padding, absoluteSize, minWidth, maxWidth) end
function PanelTemplates_SelectTab(tab) tab._selected = true end
function PanelTemplates_DeselectTab(tab) tab._selected = false end
function PanelTemplates_EnableTab(frame, id) end
function PanelTemplates_DisableTab(frame, id) end
function PanelTemplates_ResizeTabsToFit() end

-- StaticPopup
StaticPopupDialogs = {}
MOCK.popups = {}
function StaticPopup_Show(which, a, b, data)
  local d = StaticPopupDialogs[which]
  if not d then return nil end
  local p = { which = which, text = string.format(d.text or "", a or "", b or ""), data = data, dialog = d }
  MOCK.popups[#MOCK.popups + 1] = p
  return p
end
function StaticPopup_Hide(which) end
function StaticPopup_Visible(which) return nil end

-- Settings
Settings = {
  RegisterCanvasLayoutCategory = function(frame, name) local c = { frame = frame, name = name, ID = name }; function c:GetID() return self.ID end; return c, {} end,
  RegisterVerticalLayoutCategory = function(name) local c = { name = name, ID = name }; function c:GetID() return self.ID end; return c, {} end,
  RegisterAddOnCategory = function(c) MOCK.settingsCategory = c end,
  OpenToCategory = function(id) MOCK.settingsOpened = id; return true end,
  RegisterAddOnSetting = function() return {} end,
  CreateCheckbox = function() return {} end,
}

-- GameTooltip helpers
function GameTooltip_Hide() GameTooltip:Hide() end
function GameTooltip_SetDefaultAnchor(tt, parent) tt:SetOwner(parent, "ANCHOR_NONE") end
function GameTooltip_AddNormalLine(tt, text, wrap) tt:AddLine(text, 1, 0.82, 0, wrap) end
function GameTooltip_AddHighlightLine(tt, text, wrap) tt:AddLine(text, 1, 1, 1, wrap) end
function GameTooltip_AddErrorLine(tt, text, wrap) tt:AddLine(text, 1, 0.1, 0.1, wrap) end
function GameTooltip_AddDisabledLine(tt, text, wrap) tt:AddLine(text, 0.5, 0.5, 0.5, wrap) end
function GameTooltip_AddColoredLine(tt, text, color, wrap) tt:AddLine(text, color.r, color.g, color.b, wrap) end
function GameTooltip_AddBlankLineToTooltip(tt) tt:AddLine(" ") end
function GameTooltip_SetTitle(tt, text) tt:SetText(text) end
TooltipDataProcessor = {
  AddTooltipPostCall = function(kind, fn)
    if kind ~= 0 and kind ~= "ALL" and type(kind) ~= "number" then error("TooltipDataProcessor.AddTooltipPostCall(type, fn)", 2) end
    if type(fn) ~= "function" then error("TooltipDataProcessor.AddTooltipPostCall: function expected", 2) end
    if kind == 0 or kind == "ALL" then MOCK.tooltipPostCalls[#MOCK.tooltipPostCalls + 1] = fn end
  end,
  AddLinePreCall = function() end, AddLinePostCall = function() end,
}

-- ------------------------------------------------------------------------------------- data providers + ScrollBox
DataProviderMixin = CreateFromMixins(CallbackRegistryMixin)
DataProviderMixin.Event = { OnSizeChanged = "OnSizeChanged", OnInsert = "OnInsert", OnRemove = "OnRemove", OnSort = "OnSort" }
function DataProviderMixin:Init(tbl) self.callbackTables = {}; self.collection = {}; if tbl then for _, v in ipairs(tbl) do self.collection[#self.collection + 1] = v end end end
function DataProviderMixin:Changed() self:TriggerEvent("OnSizeChanged", false) end
function DataProviderMixin:Insert(...) for i = 1, select("#", ...) do self.collection[#self.collection + 1] = select(i, ...) end; self:SortIfNeeded(); self:Changed() end
function DataProviderMixin:InsertTable(t) for _, v in ipairs(t) do self.collection[#self.collection + 1] = v end; self:SortIfNeeded(); self:Changed() end
function DataProviderMixin:InsertTableRange(t, i, j) for k = i, j do self.collection[#self.collection + 1] = t[k] end; self:Changed() end
function DataProviderMixin:InsertAtIndex(v, i) table.insert(self.collection, i, v); self:Changed() end
function DataProviderMixin:Remove(...) for i = 1, select("#", ...) do tDeleteItem(self.collection, (select(i, ...))) end; self:Changed() end
function DataProviderMixin:RemoveIndex(i) table.remove(self.collection, i); self:Changed() end
function DataProviderMixin:RemoveIndexRange(i, j) for _ = i, j do table.remove(self.collection, i) end; self:Changed() end
function DataProviderMixin:RemoveByPredicate(p) for i = #self.collection, 1, -1 do if p(self.collection[i]) then table.remove(self.collection, i) end end; self:Changed() end
function DataProviderMixin:Flush() self.collection = {}; self:Changed() end
function DataProviderMixin:GetSize() return #self.collection end
function DataProviderMixin:IsEmpty() return #self.collection == 0 end
function DataProviderMixin:Find(i) return self.collection[i] end
function DataProviderMixin:FindIndex(v) return tIndexOf(self.collection, v) end
function DataProviderMixin:FindByPredicate(p) for i, v in ipairs(self.collection) do if p(v) then return i, v end end end
function DataProviderMixin:FindElementDataByPredicate(p) local _, v = self:FindByPredicate(p); return v end
function DataProviderMixin:FindIndexByPredicate(p) local i = self:FindByPredicate(p); return i end
function DataProviderMixin:ContainsByPredicate(p) return self:FindByPredicate(p) ~= nil end
function DataProviderMixin:Enumerate(i, j) i = (i or 1) - 1; j = j or #self.collection; local c = self.collection
  return function() i = i + 1; if i <= j and c[i] ~= nil then return i, c[i] end end end
function DataProviderMixin:EnumerateEntireRange() return self:Enumerate() end
function DataProviderMixin:ForEach(fn) for _, v in ipairs(self.collection) do fn(v) end end
function DataProviderMixin:GetCollection() return self.collection end
function DataProviderMixin:SetSortComparator(fn, skipSort) self.sortComparator = fn; if not skipSort then self:Sort() end end
function DataProviderMixin:ClearSortComparator() self.sortComparator = nil end
function DataProviderMixin:HasSortComparator() return self.sortComparator ~= nil end
function DataProviderMixin:SortIfNeeded() if self.sortComparator then table.sort(self.collection, self.sortComparator) end end
function DataProviderMixin:Sort() self:SortIfNeeded(); self:TriggerEvent("OnSort") end
function CreateDataProvider(tbl) local d = CreateFromMixins(DataProviderMixin); d:Init(tbl); return d end
function CreateIndexRangeDataProvider(n) local t = {}; for i = 1, n or 0 do t[i] = i end; return CreateDataProvider(t) end

-- tree data provider: nodes carry .data; GetData(); the view flattens non-collapsed nodes
TreeNodeMixin = {}
function TreeNodeMixin:GetData() return self.data end
function TreeNodeMixin:Insert(data) local n = CreateFromMixins(TreeNodeMixin); n.data = data; n.nodes = {}; n.parent = self; n.provider = self.provider; self.nodes[#self.nodes + 1] = n; if self.provider then self.provider:Changed() end; return n end
function TreeNodeMixin:GetNodes() return self.nodes end
function TreeNodeMixin:GetChildren() return self.nodes end
function TreeNodeMixin:GetParent() return self.parent end
function TreeNodeMixin:IsCollapsed() return self.collapsed == true end
function TreeNodeMixin:SetCollapsed(v) self.collapsed = v; if self.provider then self.provider:Changed() end end
function TreeNodeMixin:ToggleCollapsed() self:SetCollapsed(not self.collapsed) end
function TreeNodeMixin:GetDepth() local d, p = 0, self.parent; while p and p.parent do d = d + 1; p = p.parent end; return d end
function TreeNodeMixin:Flush() self.nodes = {}; if self.provider then self.provider:Changed() end end
TreeDataProviderMixin = CreateFromMixins(CallbackRegistryMixin)
function TreeDataProviderMixin:Init() self.callbackTables = {}; self.root = CreateFromMixins(TreeNodeMixin); self.root.nodes = {}; self.root.provider = self end
function TreeDataProviderMixin:Changed() self:TriggerEvent("OnSizeChanged", false) end
function TreeDataProviderMixin:GetRootNode() return self.root end
function TreeDataProviderMixin:Insert(data) return self.root:Insert(data) end
function TreeDataProviderMixin:Flush() self.root.nodes = {}; self:Changed() end
function TreeDataProviderMixin:IsEmpty() return #self.root.nodes == 0 end
function TreeDataProviderMixin:CollapseAll() end
function TreeDataProviderMixin:Flatten()
  local out = {}
  local function walk(n) for _, c in ipairs(n.nodes) do out[#out + 1] = c; if not c.collapsed then walk(c) end end end
  walk(self.root)
  return out
end
function TreeDataProviderMixin:GetSize() return #self:Flatten() end
function TreeDataProviderMixin:Enumerate() local list = self:Flatten(); local i = 0; return function() i = i + 1; if list[i] then return i, list[i] end end end
function TreeDataProviderMixin:EnumerateEntireRange() return self:Enumerate() end
function TreeDataProviderMixin:ForEach(fn) for _, n in ipairs(self:Flatten()) do fn(n) end end
function TreeDataProviderMixin:FindElementDataByPredicate(p) for _, n in ipairs(self:Flatten()) do if p(n) then return n end end end
function TreeDataProviderMixin:SetSortComparator() end
function CreateTreeDataProvider() local d = CreateFromMixins(TreeDataProviderMixin); d:Init(); return d end

local function newView(kind, ...)
  local v = { kind = kind, extent = 20, spacing = 0, pad = { ... } }
  function v:SetElementInitializer(template, initializer)
    if type(template) ~= "string" then error("SetElementInitializer(frameTemplateOrType, initializer)", 2) end
    if initializer ~= nil and type(initializer) ~= "function" then error("SetElementInitializer: initializer must be a function", 2) end
    self.factory = function(factory, elementData) factory(template, initializer) end
  end
  function v:SetElementFactory(fn) self.factory = fn end
  function v:SetElementExtent(e) self.extent = e end
  function v:SetElementExtentCalculator(fn) self.extentCalc = fn end
  function v:GetElementExtent() return self.extent end
  function v:SetElementResetter(fn) self.resetter = fn end
  function v:SetPadding(...) self.pad = { ... } end
  function v:SetPanExtent(e) end
  function v:SetHorizontal(h) end
  function v:SetDataProvider(dp) self.dataProvider = dp end
  function v:GetDataProvider() return self.dataProvider end
  function v:SetElementIndentCalculator(fn) end
  function v:SetVirtualized(b) end
  return v
end
function CreateScrollBoxListLinearView(top, bottom, left, right, spacing) local v = newView("linear", top, bottom, left, right); v.spacing = spacing or 0; return v end
function CreateScrollBoxListTreeListView(indent, top, bottom, left, right, spacing) local v = newView("tree", top, bottom, left, right); v.spacing = spacing or 0; v.indent = indent; return v end
function CreateScrollBoxLinearView() return newView("linear") end
function CreateScrollBoxListGridView(stride) local v = newView("grid"); v.stride = stride; return v end

ScrollBoxListMixin = CreateFromMixins(CallbackRegistryMixin)
ScrollBoxListMixin.Event = { OnInitializedFrame = "OnInitializedFrame", OnAcquiredFrame = "OnAcquiredFrame", OnReleasedFrame = "OnReleasedFrame",
  OnDataRangeChanged = "OnDataRangeChanged", OnLayout = "OnLayout", OnUpdate = "OnUpdate", OnScroll = "OnScroll", OnSizeChanged = "OnSizeChanged",
  OnAllowScrollChanged = "OnAllowScrollChanged", OnDataProviderReassigned = "OnDataProviderReassigned" }
ScrollBoxMixin = ScrollBoxListMixin
BaseScrollBoxEvents = ScrollBoxListMixin.Event
function ScrollBoxListMixin:OnLoad() self.callbackTables = {}; self._frames = {}; self._pool = {}; self._offset = 0; self._scrollPct = 0 end
function ScrollBoxListMixin:Init(view) self._view = view; self:FullUpdate() end
function ScrollBoxListMixin:GetView() return self._view end
function ScrollBoxListMixin:SetView(view) self._view = view end
function ScrollBoxListMixin:GetScrollTarget() return self.ScrollTarget end
function ScrollBoxListMixin:SetDataProvider(dp, retain)
  if self._dp and self._dp.UnregisterCallback then self._dp:UnregisterCallback("OnSizeChanged", self); self._dp:UnregisterCallback("OnSort", self) end
  self._dp = dp
  if self._view then self._view.dataProvider = dp end
  if dp and dp.RegisterCallback then
    dp:RegisterCallback("OnSizeChanged", function() self:FullUpdate() end, self)
    dp:RegisterCallback("OnSort", function() self:FullUpdate() end, self)
  end
  if not retain then self._scrollPct = 0 end
  self:FullUpdate()
end
function ScrollBoxListMixin:GetDataProvider() return self._dp end
function ScrollBoxListMixin:HasDataProvider() return self._dp ~= nil end
function ScrollBoxListMixin:ClearDataProvider() self:SetDataProvider(nil) end
function ScrollBoxListMixin:RemoveDataProvider() self:SetDataProvider(nil) end
function ScrollBoxListMixin:FlushDataProvider() if self._dp then self._dp:Flush() end end
local function elements(sb)
  local dp = sb._dp
  if not dp then return {} end
  if dp.Flatten then return dp:Flatten() end
  return dp.collection or {}
end
function ScrollBoxListMixin:GetDataProviderSize() return #elements(self) end
function ScrollBoxListMixin:VisibleCount(total)
  local view = self._view
  local extent = (view and view.extent or 20) + (view and view.spacing or 0)
  local h = self:GetHeight()
  local n
  if h and h > 0 and extent > 0 then n = math.ceil(h / extent) + 1 else n = MOCK.scrollBoxDefaultRows or 25 end
  return math.min(total, n)
end
function ScrollBoxListMixin:FullUpdate()
  if not self._view then return end
  local list = elements(self)
  local total = #list
  local nvis = self:VisibleCount(total)
  local first = math.floor((self._scrollPct or 0) * math.max(0, total - nvis) + 0.5) + 1
  self._first = first
  -- release frames no longer in range
  local keep = {}
  for _, fr in ipairs(self._frames) do
    local i = fr._elementIndex
    if i and i >= first and i < first + nvis and list[i] == fr._elementData then keep[i] = fr
    else
      self:TriggerEvent("OnReleasedFrame", fr, fr._elementData)
      if self._view.resetter then protected("ScrollBox resetter", self._view.resetter, fr, fr._elementData) end
      fr._elementData = nil; fr._elementIndex = nil
      fr:Hide()
      local pool = self._pool[fr._sbTemplate]; if not pool then pool = {}; self._pool[fr._sbTemplate] = pool end
      pool[#pool + 1] = fr
    end
  end
  self._frames = {}
  for i = first, first + nvis - 1 do
    local data = list[i]
    if data == nil then break end
    local fr = keep[i]
    if fr then
      self._frames[#self._frames + 1] = fr
    else
      local template, initializer
      self._view.factory(function(t, init) template, initializer = t, init end, data)
      if not template then error("ScrollBox: element factory did not provide a template") end
      local pool = self._pool[template]
      local new = false
      if pool and #pool > 0 then fr = table.remove(pool) else fr = MOCK.createScrollBoxFrame(self, template); new = true end
      fr._sbTemplate = template
      fr._elementData = data; fr._elementIndex = i
      local extent = self._view.extent or 20
      fr._points = { { "TOPLEFT", self.ScrollTarget or false, "TOPLEFT", 0, -((i - first) * (extent + (self._view.spacing or 0))) } }
      fr._h = fr._h or extent
      fr._w = self:GetWidth()
      self:TriggerEvent("OnAcquiredFrame", fr, data, new)
      fr:Show()
      if initializer then protected("ScrollBox initializer", initializer, fr, data) end
      self:TriggerEvent("OnInitializedFrame", fr, data)
      self._frames[#self._frames + 1] = fr
    end
  end
  MOCK.layoutGen = MOCK.layoutGen + 1
  self:TriggerEvent("OnDataRangeChanged", first, first + #self._frames - 1)
  self:TriggerEvent("OnLayout")
end
ScrollBoxListMixin.Update = ScrollBoxListMixin.FullUpdate
ScrollBoxListMixin.Layout = function() end
function ScrollBoxListMixin:ForEachFrame(fn) for _, fr in ipairs(self._frames) do fn(fr, fr._elementData) end end
function ScrollBoxListMixin:EnumerateFrames() local i = 0; local fs = self._frames; return function() i = i + 1; local f = fs[i]; if f then return i, f end end end
function ScrollBoxListMixin:GetFrames() return self._frames end
function ScrollBoxListMixin:GetFrameCount() return #self._frames end
function ScrollBoxListMixin:FindFrame(data) for _, fr in ipairs(self._frames) do if fr._elementData == data then return fr end end end
function ScrollBoxListMixin:FindFrameByPredicate(p) for _, fr in ipairs(self._frames) do if p(fr, fr._elementData) then return fr end end end
function ScrollBoxListMixin:FindElementDataByPredicate(p) for _, d in ipairs(elements(self)) do if p(d) then return d end end end
function ScrollBoxListMixin:FindElementDataIndexByPredicate(p) for i, d in ipairs(elements(self)) do if p(d) then return i end end end
function ScrollBoxListMixin:ScrollToElementDataIndex(i) local total = #elements(self); local n = self:VisibleCount(total); local range = math.max(1, total - n); self._scrollPct = math.max(0, math.min(1, (i - 1) / range)); self:FullUpdate() end
function ScrollBoxListMixin:ScrollToElementData(d) for i, x in ipairs(elements(self)) do if x == d then return self:ScrollToElementDataIndex(i) end end end
function ScrollBoxListMixin:ScrollToBegin() self._scrollPct = 0; self:FullUpdate() end
function ScrollBoxListMixin:ScrollToEnd() self._scrollPct = 1; self:FullUpdate() end
function ScrollBoxListMixin:SetScrollPercentage(p) self._scrollPct = math.max(0, math.min(1, p)); self:FullUpdate(); self:TriggerEvent("OnScroll", self._scrollPct) end
function ScrollBoxListMixin:GetScrollPercentage() return self._scrollPct or 0 end
function ScrollBoxListMixin:GetVisibleExtentPercentage() local t = #elements(self); if t == 0 then return 1 end; return math.min(1, self:VisibleCount(t) / t) end
function ScrollBoxListMixin:HasScrollableExtent() local t = #elements(self); return self:VisibleCount(t) < t end
function ScrollBoxListMixin:ScrollInDirection(pct, dir) self:SetScrollPercentage((self._scrollPct or 0) + pct * dir) end
function ScrollBoxListMixin:SetPanExtent() end
function ScrollBoxListMixin:SetInterpolateScroll() end
function ScrollBoxListMixin:IsAcquireLocked() return false end
function ScrollBoxListMixin:GetElementExtent() return self._view and self._view.extent or 20 end
function ScrollBoxListMixin:SelectElementData() end
function ScrollBoxListMixin:SetAlignmentOverlapIgnored() end
function ScrollBoxListMixin:SetUseShadowsForEdgeFade() end
function ScrollBoxListMixin:SetEdgeFadeLength() end
function ScrollBoxListMixin:ClearFrames() end
function ScrollBoxListMixin:HasView() return self._view ~= nil end
function ScrollBoxListMixin:GetDataIndexBegin() return self._first or 1 end
function ScrollBoxListMixin:GetDataIndexEnd() return (self._first or 1) + #self._frames - 1 end
function ScrollBoxListMixin:ForEachElementData(fn) for _, d in ipairs(elements(self)) do fn(d) end end
function ScrollBoxListMixin:EnumerateDataProvider() local l = elements(self); local i = 0; return function() i = i + 1; if l[i] ~= nil then return i, l[i] end end end
ScrollBoxListMixin.EnumerateDataProviderEntireRange = ScrollBoxListMixin.EnumerateDataProvider
function ScrollBoxListMixin:ContainsElementDataByPredicate(p) return self:FindElementDataByPredicate(p) ~= nil end
function ScrollBoxListMixin:FindElementData(i) return elements(self)[i] end
function ScrollBoxListMixin:FindElementDataIndex(d) for i, x in ipairs(elements(self)) do if x == d then return i end end end
function ScrollBoxListMixin:FindByPredicate(p) for i, d in ipairs(elements(self)) do if p(d) then return i, d end end end
function ScrollBoxListMixin:FindFrameElementDataIndex(fr) return fr._elementIndex end
function ScrollBoxListMixin:ScrollToElementDataByPredicate(p) local i = self:FindElementDataIndexByPredicate(p); if i then self:ScrollToElementDataIndex(i) end end
function ScrollBoxListMixin:ReinitializeFrames() for _, fr in ipairs(self._frames) do self:TriggerEvent("OnInitializedFrame", fr, fr._elementData) end end
function ScrollBoxListMixin:Rebuild() self:FullUpdate() end
function ScrollBoxListMixin:IsVirtualized() return true end
function ScrollBoxListMixin:ReverseForEachFrame(fn) for i = #self._frames, 1, -1 do local fr = self._frames[i]; fn(fr, fr._elementData) end end
function ScrollBoxListMixin:GetVisibleExtent() return self:GetHeight() end
function ScrollBoxListMixin:SetScrollAllowed() end
function ScrollBoxListMixin:SetUpdateLocked(v) self._locked = v end
function ScrollBoxListMixin:IsUpdateLocked() return self._locked == true end
function ScrollBoxListMixin:ScrollToOffset(o) end
function ScrollBoxListMixin:GetDerivedScrollOffset() return 0 end
function ScrollBoxListMixin:GetDerivedScrollRange() return 0 end
function ScrollBoxListMixin:GetExtent() return #elements(self) * ((self._view and self._view.extent or 20) + (self._view and self._view.spacing or 0)) end
function ScrollBoxListMixin:GetPadding() return nil end
for _, name in ipairs(MOCK.SCROLLBOX_METHODS or {}) do
  if ScrollBoxListMixin[name] == nil then local n = name; ScrollBoxListMixin[name] = function() MOCK.gap("ScrollBox:" .. n) end end
end

-- frames created by the scroll box for an element template
MOCK.rowTemplates = {}
function MOCK.createScrollBoxFrame(sb, template)
  local parent = sb.ScrollTarget or sb
  local builder = MOCK.rowTemplates[template]
  if builder then
    MOCK.blizzardDepth = (MOCK.blizzardDepth or 0) + 1
    local ok, f = pcall(builder, parent)
    MOCK.blizzardDepth = MOCK.blizzardDepth - 1
    if not ok then error(f, 0) end
    return f
  end
  local kind = MOCK.FRAME_TYPES[template] and template or MOCK.baseKindOfTemplate(template)
  if not kind then strictError("template", template, "ScrollBox: unknown element template '" .. tostring(template) .. "'", 3); kind = "Frame" end
  local f = MOCK.newWidget(kind, nil, parent)
  MOCK.frames[#MOCK.frames + 1] = f
  if not MOCK.FRAME_TYPES[template] then MOCK.applyTemplates(f, template, 3) end
  local sbref = sb
  rawset(f, "GetElementData", function(self) return self._elementData end)
  rawset(f, "GetElementDataIndex", function(self) return self._elementIndex end)
  rawset(f, "ElementDataMatches", function(self, d) return self._elementData == d end)
  rawset(f, "GetOrderIndex", function(self) return self._elementIndex end)
  return f
end

ScrollBarMixin = CreateFromMixins(CallbackRegistryMixin)
function ScrollBarMixin:SetScrollPercentage(p) self._pct = p end
function ScrollBarMixin:GetScrollPercentage() return self._pct or 0 end
function ScrollBarMixin:SetVisibleExtentPercentage(p) self._vis = p end
function ScrollBarMixin:GetVisibleExtentPercentage() return self._vis or 1 end
function ScrollBarMixin:SetPanExtentPercentage() end
function ScrollBarMixin:SetHideIfUnscrollable(v) self._hideIfUnscrollable = v end
function ScrollBarMixin:SetHideTrackIfThumbExceedsTrack() end
function ScrollBarMixin:HasScrollableExtent() return (self._vis or 1) < 1 end
function ScrollBarMixin:ScrollStepInDirection(dir) end
function ScrollBarMixin:SetInterpolateScroll() end
function ScrollBarMixin:Init() end
function ScrollBarMixin:Update() end

ScrollUtil = {}
function ScrollUtil.AddInitializedFrameCallback(scrollBox, callback, owner, iterateExisting)
  if iterateExisting then scrollBox:ForEachFrame(callback) end
  local function OnInitialized(o, frame, elementData) callback(o, frame, elementData) end
  scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, OnInitialized, owner)
end
function ScrollUtil.AddAcquiredFrameCallback(scrollBox, callback, owner, iterateExisting)
  if iterateExisting then scrollBox:ForEachFrame(callback) end
  local function OnAcquired(o, frame, elementData, new) callback(o, frame, elementData, new) end
  scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, OnAcquired, owner)
end
function ScrollUtil.AddReleasedFrameCallback(scrollBox, callback, owner)
  scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnReleasedFrame, function(o, frame, elementData) callback(o, frame, elementData) end, owner)
end
function ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
  if not (scrollBox and scrollBox.Init) then error("ScrollUtil.InitScrollBoxListWithScrollBar: scrollBox must be a WowScrollBoxList", 2) end
  scrollBox._scrollBar = scrollBar
  scrollBox:Init(view)
end
ScrollUtil.InitScrollBoxWithScrollBar = ScrollUtil.InitScrollBoxListWithScrollBar
function ScrollUtil.RegisterScrollBoxWithScrollBar(scrollBox, scrollBar) scrollBox._scrollBar = scrollBar end
function ScrollUtil.AddManagedScrollBarVisibilityBehavior(scrollBox, scrollBar, withBar, withoutBar) return {} end
function ScrollUtil.RegisterTableBuilder(scrollBox, tableBuilder, translator)
  local onInit = function(o, frame, elementData) tableBuilder:AddRow(frame, translator(elementData)) end
  scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnInitializedFrame, onInit, onInit)
end
function ScrollUtil.RegisterAlternateRowBehavior(scrollBox, fn) end
function ScrollUtil.CalculateScrollBoxElementExtent(count, frameExtent, spacing) return count * frameExtent + math.max(0, count - 1) * spacing end
'''

# =====================================================================================================================
# Lua: client APIs (items, AH, trade skills, merchant, bags, loot, spells, misc)
# =====================================================================================================================
LUA_API = r'''
local CFG, API = ...
local MOCK = __WOWMOCK
local strictError, protected, addonWhere, isWidget, NS, gap = MOCK.strictError, MOCK.protected, MOCK.addonWhere, MOCK.isWidget, MOCK.NS, MOCK.gap
local fire, after = MOCK.fire, MOCK.after

-- ------------------------------------------------------------------------------------- unit / realm / misc client
MOCK.player = { guid = CFG.char, name = "Aaron", realm = "Classic Beta PvP 2", nrealm = "ClassicBetaPvP2", class = "WARRIOR", className = "Warrior",
  level = CFG.level or 25, faction = "Horde", money = 1234567, race = "Orc" }
MOCK.loggedIn = false
function UnitGUID(unit)
  if unit == "player" then return MOCK.player.guid end
  if unit == "npc" and MOCK.merchant and MOCK.merchant.open then return "Creature-0-4613-1-1-" .. MOCK.merchant.npcID .. "-0000ABCDEF" end
  if unit == "target" and MOCK.target then return MOCK.target end
  return nil
end
function UnitName(unit)
  if unit == "player" then return MOCK.player.name, nil end
  if unit == "npc" and MOCK.merchant and MOCK.merchant.open then return MOCK.merchant.name, nil end
  return nil
end
function UnitFullName(unit) if unit == "player" then return MOCK.player.name, MOCK.loggedIn and MOCK.player.nrealm or nil end end
function UnitClass(unit) if unit == "player" then return MOCK.player.className, MOCK.player.class, 1 end end
function UnitClassBase(unit) if unit == "player" then return MOCK.player.class, 1 end end
function UnitRace(unit) if unit == "player" then return MOCK.player.race, MOCK.player.race, 2 end end
function UnitLevel(unit) if unit == "player" then return MOCK.player.level end; return 0 end
function UnitFactionGroup(unit) if unit == "player" or unit == "npc" then return MOCK.player.faction, MOCK.player.faction end end
function UnitExists(unit) return unit == "player" or (unit == "npc" and MOCK.merchant ~= nil and MOCK.merchant.open) end
function UnitIsUnit(a, b) return a == b end
function UnitAffectingCombat() return MOCK.inCombat == true end
function GetRealmName() return MOCK.player.realm end
function GetNormalizedRealmName() if MOCK.loggedIn then return MOCK.player.nrealm end return nil end
function GetCurrentRegion() return 110 end
function GetLocale() return MOCK.locale end
function GetBuildInfo() return "1.60.1", "70450", "Oct 16 2026", 16001, "", "", 16001 end
function GetMoney() return MOCK.player.money end
function IsLoggedIn() return MOCK.loggedIn end
function GetZoneText() return (MOCK.zone and MOCK.zone.name) or "Orgrimmar" end
function GetRealZoneText() return GetZoneText() end
function GetSubZoneText() return "" end
function GetMinimapZoneText() return GetZoneText() end
function IsInInstance() return false, "none" end
function GetPlayerFacing() return 0 end
C_Map = NS("C_Map", {
  GetBestMapForUnit = function(unit) if unit == "player" then return (MOCK.zone and MOCK.zone.map) or 1454 end end,
  GetPlayerMapPosition = function(mapID, unit)
    if unit ~= "player" then return nil end
    local x, y = (MOCK.zone and MOCK.zone.x) or 0.5, (MOCK.zone and MOCK.zone.y) or 0.5
    local v = { x = x, y = y }
    function v:GetXY() return self.x, self.y end
    return v
  end,
  GetMapInfo = function(id) return { mapID = id, name = GetZoneText(), mapType = 3, parentMapID = 0 } end,
})
C_DateAndTime = NS("C_DateAndTime", {
  GetCurrentCalendarTime = function() local d = os.date("!*t", GetServerTime())
    return { year = d.year, month = d.month, monthDay = d.day, weekday = d.wday, hour = d.hour, minute = d.min } end,
  GetServerTimeLocal = function() return GetServerTime() end,
  GetSecondsUntilDailyReset = function() return 3600 * 5 end,
})
C_AddOns = NS("C_AddOns", {
  GetAddOnMetadata = function(name, field)
    if type(name) ~= "string" and type(name) ~= "number" then MOCK.usage("Usage: C_AddOns.GetAddOnMetadata(addon, field)", 2) end
    if type(field) ~= "string" then MOCK.usage("Usage: C_AddOns.GetAddOnMetadata(addon, field)", 2) end
    local md = MOCK.addonMeta[name]; if not md then return nil end
    return md[field] or md[field:lower()]
  end,
  IsAddOnLoaded = function(name) return MOCK.loadedAddons[name] == true, MOCK.loadedAddons[name] == true end,
  LoadAddOn = function(name) if MOCK.lodLoaders[name] then MOCK.lodLoaders[name](); return true end; return MOCK.loadedAddons[name] == true end,
  GetNumAddOns = function() return 1 end,
  GetAddOnInfo = function(i) return "WaylaidCrate", "Waylaid Crate", "", true, "INSECURE", false end,
  DoesAddOnExist = function(name) return MOCK.addonMeta[name] ~= nil or MOCK.lodLoaders[name] ~= nil end,
  IsAddOnLoadOnDemand = function(name) return MOCK.lodLoaders[name] ~= nil end,
  GetAddOnEnableState = function() return 2 end,
})
MOCK.addonMeta, MOCK.lodLoaders = {}, {}
C_Reputation = NS("C_Reputation", {
  GetFactionDataByID = function(id)
    local f = MOCK.factions[id]; if not f then return nil end
    return { factionID = id, name = f.name, reaction = f.reaction, currentStanding = f.standing or 0, currentReactionThreshold = 0, nextReactionThreshold = 3000, isWatched = false }
  end,
})
MOCK.factions = { [2587] = { name = "Durotar Supply and Logistics", reaction = 5 }, [2586] = { name = "Azeroth Commerce Authority", reaction = 5 } }
MOCK.questsDone = {}
C_QuestLog = NS("C_QuestLog", { IsQuestFlaggedCompleted = function(q) return MOCK.questsDone[q] == true end,
  IsOnQuest = function() return false end, GetLogIndexForQuestID = function() return nil end })
MOCK.spells = { [13262] = { name = "Disenchant", known = false } }
function IsPlayerSpell(id) local s = MOCK.spells[id]; return s ~= nil and s.known == true end
function IsSpellKnown(id) return IsPlayerSpell(id) end
C_SpellBook = NS("C_SpellBook", {
  ContainsAnyDisenchantSpell = function() return IsPlayerSpell(13262) end,
  IsSpellKnown = function(id) return IsPlayerSpell(id) end,
  IsSpellInSpellBook = function(id) return IsPlayerSpell(id) end,
})
C_Spell = NS("C_Spell", {
  GetSpellInfo = function(id) local s = MOCK.spells[id]; if not s then return nil end
    return { name = s.name, spellID = id, iconID = 136244, castTime = 3000, minRange = 0, maxRange = 0, originalIconID = 136244 } end,
  GetSpellName = function(id) local s = MOCK.spells[id]; return s and s.name end,
  DoesSpellExist = function(id) return MOCK.spells[id] ~= nil end,
  GetSpellLink = function(id) local s = MOCK.spells[id]; return s and ("|cff71d5ff|Hspell:" .. id .. ":0|h[" .. s.name .. "]|h|r") end,
})
C_PlayerInteractionManager = NS("C_PlayerInteractionManager", { IsInteractingWithNpcOfType = function(t)
  if t == 21 then return MOCK.AH.open end; if t == 5 then return MOCK.merchant ~= nil and MOCK.merchant.open end; return false end })
C_SkillInfo = NS("C_SkillInfo", { GetSkillLineInfoByID = function(id)
  for _, p in ipairs(MOCK.profs) do if p.skillLine == id then return { skillID = id, name = p.name, rank = p.rank, maxRank = p.max, isHeader = false } end end
end })
C_CurrencyInfo = NS("C_CurrencyInfo", { GetCoinTextureString = function(m) return GetMoneyString(m) end,
  GetCurrencyInfo = function(id) return { name = "Currency " .. id, quantity = 0, iconFileID = 0 } end })

-- ------------------------------------------------------------------------------------- items
MOCK.ITEMS = MOCK.ITEMS or {}
MOCK.CACHED = {}
MOCK.LOADING = {}
MOCK.itemStats = { getInfoMiss = 0, requestLoad = 0, loadResults = 0, getInfoCalls = 0 }
local ITEMS, CACHED = MOCK.ITEMS, MOCK.CACHED
local TYPE_NAMES = { [0] = "Consumable", "Container", "Weapon", "Gem", "Armor", "Reagent", "Projectile", "Trade Goods", "Item Enhancement",
  "Recipe", "Money", "Quiver", "Quest", "Key", "Permanent", "Miscellaneous" }
function MOCK.itemLink(id)
  local it = ITEMS[id]; if not it then return nil end
  return "|c" .. (MOCK.QUALITY_HEX[it.quality] or "ffffffff") .. "|Hitem:" .. id .. "::::::::" .. MOCK.player.level .. ":::::::::|h[" .. it.name .. "]|h|r"
end
local function resolveID(item)
  if type(item) == "number" then return item end
  if type(item) == "string" then
    local id = tonumber(item:match("item:(%-?%d+)")) or tonumber(item)
    if id then return id end
    for iid, it in pairs(ITEMS) do if it.name == item and CACHED[iid] then return iid end end
    return nil
  end
  if type(item) == "table" and item.IsBagAndSlot then return MOCK.itemAtLocation(item) end
  return nil
end
MOCK.resolveID = resolveID
local function finishLoad(id)
  local st = MOCK.LOADING[id]; MOCK.LOADING[id] = nil
  if not ITEMS[id] then
    if st and st.result then MOCK.itemStats.loadResults = MOCK.itemStats.loadResults + 1; fire("ITEM_DATA_LOAD_RESULT", id, false) end
    return
  end
  local was = CACHED[id]
  CACHED[id] = true
  if not was then fire("GET_ITEM_INFO_RECEIVED", id, true) end
  if st and st.key then fire("ITEM_KEY_ITEM_INFO_RECEIVED", id) end
  if st and st.result then MOCK.itemStats.loadResults = MOCK.itemStats.loadResults + 1; fire("ITEM_DATA_LOAD_RESULT", id, true) end
end
local function startLoad(id, flags)
  local st = MOCK.LOADING[id]
  if st then for k, v in pairs(flags or {}) do st[k] = st[k] or v end; return end
  st = {}
  for k, v in pairs(flags or {}) do st[k] = v end
  MOCK.LOADING[id] = st
  after(MOCK.itemLoadDelay + (id % 7) * 0.03, function() finishLoad(id) end, "itemload")
end
MOCK.startLoad = startLoad
local function infoTuple(id)
  local it = ITEMS[id]
  return it.name, MOCK.itemLink(id), it.quality, it.ilvl, it.req or 0, TYPE_NAMES[it.classID] or "Miscellaneous", it.subName or "",
    it.stack or 1, it.equipLoc or "", it.icon or 134400, it.sell or 0, it.classID or 15, it.subclassID or 0, it.bind or 0, 0, nil,
    it.classID == 7, ""
end
C_Item = NS("C_Item", {
  GetItemInfo = function(item)
    MOCK.itemStats.getInfoCalls = MOCK.itemStats.getInfoCalls + 1
    if item == nil then MOCK.usage("Usage: C_Item.GetItemInfo(itemInfo)", 2) end
    local id = resolveID(item); if not id or not ITEMS[id] then return nil end
    if not CACHED[id] then MOCK.itemStats.getInfoMiss = MOCK.itemStats.getInfoMiss + 1; startLoad(id, {}); return nil end
    return infoTuple(id)
  end,
  GetItemInfoInstant = function(item)
    local id = resolveID(item); local it = id and ITEMS[id]; if not it then return nil end
    return id, TYPE_NAMES[it.classID] or "Miscellaneous", it.subName or "", it.equipLoc or "", it.icon or 134400, it.classID or 15, it.subclassID or 0
  end,
  GetItemNameByID = function(item)
    local id = resolveID(item); if not id or not ITEMS[id] then return nil end
    if not CACHED[id] then startLoad(id, {}); return nil end
    return ITEMS[id].name
  end,
  GetItemQualityByID = function(item) local id = resolveID(item); local it = id and ITEMS[id]; if it and CACHED[id] then return it.quality end end,
  GetItemIconByID = function(item) local id = resolveID(item); local it = id and ITEMS[id]; return it and (it.icon or 134400) end,
  GetItemLinkByGUID = function() return nil end,
  RequestLoadItemDataByID = function(item)
    local id = resolveID(item)
    if not id then MOCK.usage("Usage: C_Item.RequestLoadItemDataByID(itemInfo)", 2) end
    MOCK.itemStats.requestLoad = MOCK.itemStats.requestLoad + 1
    if CACHED[id] and ITEMS[id] then
      MOCK.itemStats.loadResults = MOCK.itemStats.loadResults + 1
      fire("ITEM_DATA_LOAD_RESULT", id, true)        -- synchronous for cached items (AsyncCallbackSystem relies on it)
    else
      startLoad(id, { result = true })
    end
  end,
  IsItemDataCachedByID = function(item) local id = resolveID(item); return id ~= nil and CACHED[id] == true end,
  DoesItemExistByID = function(item) local id = resolveID(item); return id ~= nil and ITEMS[id] ~= nil end,
  GetDetailedItemLevelInfo = function(item) local id = resolveID(item); local it = id and ITEMS[id]; if it and CACHED[id] then return it.ilvl, false, it.ilvl end end,
  GetItemCount = function(item, includeBank, includeUses, includeReagentBank, includeAccountBank)
    local id = resolveID(item); if not id then return 0 end
    local n = MOCK.bagCount(id)
    if includeBank then n = n + (MOCK.BANK[id] or 0) end
    return n
  end,
  GetItemQualityColor = function(q) local c = ITEM_QUALITY_COLORS[q]; if c then return c.r, c.g, c.b, c.hex end end,
  GetItemClassInfo = function(c) return TYPE_NAMES[c] end,
  GetItemSubClassInfo = function(c, s) return "Subclass " .. tostring(s) end,
  GetItemSpell = function() return nil end,
  IsEquippableItem = function(item) local id = resolveID(item); local it = id and ITEMS[id]; return it ~= nil and (it.equipLoc or "") ~= "" end,
  GetItemID = function(loc) return MOCK.itemAtLocation(loc) end,
  DoesItemExist = function(loc) return MOCK.itemAtLocation(loc) ~= nil end,
  GetItemLink = function(loc) local id = MOCK.itemAtLocation(loc); return id and MOCK.itemLink(id) end,
  GetCurrentItemLevel = function(loc) local id = MOCK.itemAtLocation(loc); return id and ITEMS[id] and ITEMS[id].ilvl end,
  GetItemQuality = function(loc) local id = MOCK.itemAtLocation(loc); return id and ITEMS[id] and ITEMS[id].quality end,
  IsLocked = function(loc) local e = MOCK.BAGS[loc.bagID] and MOCK.BAGS[loc.bagID][loc.slotIndex]; return e and e.locked or false end,
})
-- Item / ItemLocation mixins (Blizzard_ObjectAPI)
ItemLocationMixin = {}
function ItemLocationMixin:IsBagAndSlot() return self.bagID ~= nil end
function ItemLocationMixin:GetBagAndSlot() return self.bagID, self.slotIndex end
function ItemLocationMixin:IsEquipmentSlot() return false end
function ItemLocationMixin:IsValid() return self.bagID ~= nil end
ItemLocation = {}
function ItemLocation:CreateFromBagAndSlot(bag, slot) local l = CreateFromMixins(ItemLocationMixin); l.bagID, l.slotIndex = bag, slot; return l end
function ItemLocation:CreateEmpty() return CreateFromMixins(ItemLocationMixin) end
function MOCK.itemAtLocation(loc) if type(loc) ~= "table" then return nil end; local e = MOCK.BAGS[loc.bagID] and MOCK.BAGS[loc.bagID][loc.slotIndex]; return e and e.itemID end
ItemMixin = {}
Item = {}
function Item:CreateFromItemID(id) if type(id) ~= "number" then error("Item:CreateFromItemID(itemID)", 2) end; local o = CreateFromMixins(ItemMixin); o.itemID = id; return o end
function Item:CreateFromItemLink(link) local o = CreateFromMixins(ItemMixin); o.itemID = resolveID(link); o.itemLink = link; return o end
function ItemMixin:GetItemID() return self.itemID end
function ItemMixin:IsItemDataCached() return CACHED[self.itemID] == true end
function ItemMixin:IsItemEmpty() return ITEMS[self.itemID] == nil end
function ItemMixin:GetItemName() return CACHED[self.itemID] and ITEMS[self.itemID] and ITEMS[self.itemID].name end
function ItemMixin:GetItemLink() return CACHED[self.itemID] and MOCK.itemLink(self.itemID) end
function ItemMixin:GetItemQuality() return CACHED[self.itemID] and ITEMS[self.itemID] and ITEMS[self.itemID].quality end
function ItemMixin:GetItemIcon() return ITEMS[self.itemID] and (ITEMS[self.itemID].icon or 134400) end
function ItemMixin:GetCurrentItemLevel() return ITEMS[self.itemID] and ITEMS[self.itemID].ilvl end
function ItemMixin:ContinueOnItemLoad(cb)
  if type(cb) ~= "function" then error("ContinueOnItemLoad(callback)", 2) end
  if CACHED[self.itemID] then cb(); return end
  local id = self.itemID
  local f = { once = true }
  MOCK.itemCallbacks[id] = MOCK.itemCallbacks[id] or {}
  table.insert(MOCK.itemCallbacks[id], cb)
  C_Item.RequestLoadItemDataByID(id)
end
function ItemMixin:ContinueWithCancelOnItemLoad(cb) self:ContinueOnItemLoad(cb); return function() end end
MOCK.itemCallbacks = {}
local prevOnEvent = MOCK.onEvent
MOCK.onEvent = function(event, ...)
  prevOnEvent(event, ...)
  if event == "ITEM_DATA_LOAD_RESULT" then
    local id = ...
    local cbs = MOCK.itemCallbacks[id]
    if cbs then MOCK.itemCallbacks[id] = nil; for _, cb in ipairs(cbs) do protected("ContinueOnItemLoad", cb) end end
  end
end

-- ------------------------------------------------------------------------------------- bags
MOCK.BAGS = { [0] = {}, {}, {}, {}, {} }
MOCK.BANK = {}
MOCK.bagSlots = { [0] = 16, 16, 16, 16, 16 }
function MOCK.bagCount(id)
  local n = 0
  for bag = 0, 4 do for _, e in pairs(MOCK.BAGS[bag] or {}) do if e.itemID == id then n = n + e.count end end end
  return n
end
C_Container = NS("C_Container", {
  GetContainerNumSlots = function(bag) if type(bag) ~= "number" then MOCK.usage("Usage: C_Container.GetContainerNumSlots(containerIndex)", 2) end; return MOCK.bagSlots[bag] or 0 end,
  GetContainerNumFreeSlots = function(bag) local n = MOCK.bagSlots[bag] or 0; for _ in pairs(MOCK.BAGS[bag] or {}) do n = n - 1 end; return n, 0 end,
  GetContainerItemInfo = function(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" then MOCK.usage("Usage: C_Container.GetContainerItemInfo(containerIndex, slotIndex)", 2) end
    local e = MOCK.BAGS[bag] and MOCK.BAGS[bag][slot]; if not e then return nil end
    local it = ITEMS[e.itemID] or {}
    return { iconFileID = it.icon or 134400, stackCount = e.count, isLocked = e.locked or false, quality = it.quality, isReadable = false,
      hasLoot = false, hyperlink = MOCK.itemLink(e.itemID), isFiltered = false, hasNoValue = (it.sell or 0) == 0, itemID = e.itemID,
      isBound = e.bound or false, itemName = it.name }
  end,
  GetContainerItemLink = function(bag, slot) local e = MOCK.BAGS[bag] and MOCK.BAGS[bag][slot]; return e and MOCK.itemLink(e.itemID) end,
  GetContainerItemID = function(bag, slot) local e = MOCK.BAGS[bag] and MOCK.BAGS[bag][slot]; return e and e.itemID end,
  GetItemCooldown = function() return 0, 0, 1 end,
  GetContainerItemDurability = function() return nil end,
  PickupContainerItem = function() end,
  UseContainerItem = function() end,
  GetBagName = function(bag) return bag == 0 and "Backpack" or ("Bag " .. bag) end,
})

-- ------------------------------------------------------------------------------------- auction house
local AH = { open = false, listings = {}, results = { commodity = {}, item = {} }, sent = {}, latency = 0.25, queue = {}, queueMax = 3,
  sendTimes = {}, perMinute = 100, browse = { results = {}, full = true, pages = {}, delivered = 0, query = nil },
  browsePageSize = 50, resultPageSize = 500, noAnswer = {}, notLoadedOnce = {}, dropNext = 0, auctionSeq = 5000,
  stats = { searches = 0, browses = 0, requestMore = 0, dropped = 0, commodityInfoCalls = {}, itemInfoCalls = {}, searchByItem = {},
            blizzard = 0, numResultCalls = 0, quantityCalls = 0, sentWhileNotReady = 0 } }
MOCK.AH = AH
local function keyToken(k) return (k.itemID or 0) .. ":" .. (k.itemLevel or 0) .. ":" .. (k.itemSuffix or 0) .. ":" .. (k.battlePetSpeciesID or 0) end
function MOCK.isCommodity(id)
  local l = AH.listings[id]
  if l and l.commodity ~= nil then return l.commodity end
  local it = ITEMS[id]
  if not it then return true end
  if it.classID == 2 or it.classID == 4 then return false end
  return (it.stack or 1) > 1
end
local function validKey(k, fname, level)
  if type(k) ~= "table" or type(k.itemID) ~= "number" then MOCK.usage("Usage: C_AuctionHouse." .. fname .. "(itemKey, ...): itemKey must be an ItemKey table", level + 1) end
end
local function throttleOK()
  local now = MOCK.clock.now
  local keep = {}
  for _, t in ipairs(AH.sendTimes) do if now - t < 60 then keep[#keep + 1] = t end end
  AH.sendTimes = keep
  return #keep < AH.perMinute
end
-- one throttled message at a time: returns false (and fires MESSAGE_DROPPED) when the system is busy
-- Throttled messages (search / browse / "more"): one in flight, later ones queued FIFO (QUEUED event), the queue holds
-- AH.queueMax messages, more are dropped (DROPPED event); 100 per minute. IsThrottledMessageSystemReady() is false while
-- anything is in flight or queued. AH.dropNext = n makes the server drop the next n messages.
local startNext
local function startMessage(msg)
  AH.inflight = msg
  AH.sendTimes[#AH.sendTimes + 1] = MOCK.clock.now
  if msg.onSend then msg.onSend() end
  fire("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
  after(AH.latency, function()
    AH.inflight = nil
    if AH.open then
      fire("AUCTION_HOUSE_THROTTLED_MESSAGE_RESPONSE_RECEIVED")
      if msg.respond then msg.respond() end
    end
    startNext()
  end, "ahresponse")
end
startNext = function()
  if not AH.open then AH.queue = {}; return end
  local nextMsg = table.remove(AH.queue, 1)
  if nextMsg then startMessage(nextMsg) else fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY") end
end
local function dropMessage(source)
  AH.stats.dropped = AH.stats.dropped + 1
  after(0.05, function() fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED") end, "drop")
  return false, "dropped"
end
local function throttledSend(kind, source, respondFn, onSend)
  if not AH.open then return false, "closed" end
  if AH.dropNext > 0 then AH.dropNext = AH.dropNext - 1; return dropMessage(source) end
  if not throttleOK() then return dropMessage(source) end
  local msg = { kind = kind, source = source, respond = respondFn, onSend = onSend }
  if AH.inflight or #AH.queue > 0 then
    if source ~= "blizzard" then AH.stats.sentWhileNotReady = AH.stats.sentWhileNotReady + 1 end
    if #AH.queue >= AH.queueMax then return dropMessage(source) end
    AH.queue[#AH.queue + 1] = msg
    fire("AUCTION_HOUSE_THROTTLED_MESSAGE_QUEUED")
    return true, "queued"
  end
  startMessage(msg)
  return true
end
function MOCK.ahReady() return AH.open and AH.inflight == nil and #AH.queue == 0 and throttleOK() end
local function sortedRows(id)
  local l = AH.listings[id]
  local rows = {}
  if l then for _, r in ipairs(l.rows) do rows[#rows + 1] = r end end
  table.sort(rows, function(a, b) if a.unit ~= b.unit then return a.unit < b.unit end return a.auctionID < b.auctionID end)
  return rows
end
function MOCK.ahSearch(itemKey, source)
  local id = itemKey.itemID
  AH.stats.searches = AH.stats.searches + 1
  AH.stats.searchByItem[id] = (AH.stats.searchByItem[id] or 0) + 1
  AH.sent[#AH.sent + 1] = { kind = "search", id = id, t = MOCK.clock.now, source = source or "addon",
    keyCached = CACHED[id] == true }
  if source == "blizzard" then AH.stats.blizzard = AH.stats.blizzard + 1 end
  local function respondFn()
    if AH.noAnswer[id] then return end
    -- the AH ignores searches for items whose key info is not cached yet (Auctionator workaround) - realism switch
    if MOCK.ahIgnoreUncachedKeys and not CACHED[id] then return end
    local rows = sortedRows(id)
    local commodity = MOCK.isCommodity(id)
    if not commodity then
      -- random-suffix gear (rows with `sfx`): a search answers only for the itemKey's exact suffix
      local suffixed = false
      for _, r in ipairs(rows) do if r.sfx then suffixed = true end end
      if suffixed then
        local keep = {}
        for _, r in ipairs(rows) do if (r.sfx or 0) == (itemKey.itemSuffix or 0) then keep[#keep + 1] = r end end
        rows = keep
      end
    end
    local loaded = true
    if AH.notLoadedOnce[id] then AH.notLoadedOnce[id] = nil; loaded = false end
    local rec = { rows = rows, received = math.min(#rows, AH.resultPageSize), loaded = loaded, key = itemKey }
    if commodity then
      AH.results.commodity[id] = rec
      fire("COMMODITY_SEARCH_RESULTS_RECEIVED")
      fire("COMMODITY_SEARCH_RESULTS_UPDATED", id)
    else
      AH.results.item[keyToken(itemKey)] = rec
      -- the client passes its own ItemKey table, not the caller's (compare fields, not references)
      fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = itemKey.itemID, itemLevel = itemKey.itemLevel or 0, itemSuffix = itemKey.itemSuffix or 0,
        battlePetSpeciesID = itemKey.battlePetSpeciesID or 0 }, nil)
    end
  end
  throttledSend("search", source, respondFn)
end
local function matchesQuery(e, q)
  local it = ITEMS[e.itemID] or {}
  if q.searchString and q.searchString ~= "" then
    if not (it.name or ""):lower():find(q.searchString:lower(), 1, true) then return false end
  end
  local quals = {}
  local anyQ = false
  for _, f in ipairs(q.filters or {}) do
    if f >= 6 and f <= 12 then quals[f - 6] = true; anyQ = true end
  end
  if anyQ and not quals[it.quality or 1] then return false end
  if q.itemClassFilters and #q.itemClassFilters > 0 then
    local ok = false
    for _, cf in ipairs(q.itemClassFilters) do
      if cf.classID == it.classID and (cf.subClassID == nil or cf.subClassID == it.subclassID) then ok = true end
    end
    if not ok then return false end
  end
  if (q.minLevel or 0) > 0 and (it.req or 0) < q.minLevel then return false end
  if (q.maxLevel or 0) > 0 and (it.req or 0) > q.maxLevel then return false end
  return true
end
function MOCK.browseUniverse()
  -- one entry per itemKey (gear: per item level) with the cheapest unit price and total units, like BrowseResultInfo
  local out = {}
  for id, l in pairs(AH.listings) do
    local byLvl = {}
    for _, r in ipairs(l.rows) do
      local lvl = 0
      if not MOCK.isCommodity(id) then lvl = r.ilvl or (ITEMS[id] and ITEMS[id].ilvl) or 0 end
      local k = lvl .. ":" .. (r.sfx or 0)
      local e = byLvl[k]
      if not e then e = { itemID = id, ilvl = lvl, sfx = r.sfx, minPrice = r.unit, qty = 0 }; byLvl[k] = e end
      if r.unit < e.minPrice then e.minPrice = r.unit end
      e.qty = e.qty + r.qty
    end
    for _, e in pairs(byLvl) do out[#out + 1] = e end
  end
  for _, e in ipairs(AH.extraBrowse or {}) do out[#out + 1] = e end
  return out
end
local function sortBrowse(list, sorts)
  local s = sorts and sorts[1]
  table.sort(list, function(a, b)
    if s and s.sortOrder == 1 then
      local na, nb = (ITEMS[a.itemID] or {}).name or "", (ITEMS[b.itemID] or {}).name or ""
      if na ~= nb then if s.reverseSort then return na > nb end return na < nb end
    elseif s and s.sortOrder == 0 then
      if a.minPrice ~= b.minPrice then if s.reverseSort then return a.minPrice > b.minPrice end return a.minPrice < b.minPrice end
    end
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    if a.ilvl ~= b.ilvl then return a.ilvl < b.ilvl end
    return (a.sfx or 0) < (b.sfx or 0)
  end)
end
local function browseInfo(e)
  return { itemKey = { itemID = e.itemID, itemLevel = e.ilvl or 0, itemSuffix = e.sfx or 0, battlePetSpeciesID = e.pet or 0 },
           totalQuantity = e.qty, minPrice = e.minPrice, containsOwnerItem = false }
end
local function deliverBrowsePage(first)
  local b = AH.browse
  b.delivered = b.delivered + 1
  local page = b.pages[b.delivered] or {}
  local added = {}
  for _, e in ipairs(page) do local info = browseInfo(e); b.results[#b.results + 1] = info; added[#added + 1] = info end
  b.full = b.delivered >= #b.pages
  if first then fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") else fire("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", added) end
end
function MOCK.ahBrowse(query, source)
  AH.stats.browses = AH.stats.browses + 1
  AH.sent[#AH.sent + 1] = { kind = "browse", t = MOCK.clock.now, source = source or "addon", query = query }
  if source == "blizzard" then AH.stats.blizzard = AH.stats.blizzard + 1 end
  throttledSend("browse", source, function()
    local list = {}
    for _, e in ipairs(MOCK.browseUniverse()) do if matchesQuery(e, query) then list[#list + 1] = e end end
    sortBrowse(list, query.sorts)
    local pages = {}
    local size = AH.browsePageSize
    for i = 1, #list, size do local p = {}; for j = i, math.min(#list, i + size - 1) do p[#p + 1] = list[j] end; pages[#pages + 1] = p end
    if #pages == 0 then pages[1] = {} end
    AH.browse = { results = {}, full = false, pages = pages, delivered = 0, query = query }
    deliverBrowsePage(true)
  end)
end
-- Blizzard's Favorites button: QueryAll -> C_AuctionHouse.SearchForFavorites(sorts) (Blizzard_AuctionHouseFrame.lua:760-772);
-- the favorites list replaces the browse results (BROWSE_RESULTS_UPDATED). AH.favorites = { [itemID] = true }.
function MOCK.ahFavorites(sorts, source)
  AH.stats.browses = AH.stats.browses + 1
  AH.sent[#AH.sent + 1] = { kind = "favorites", t = MOCK.clock.now, source = source or "addon" }
  if source == "blizzard" then AH.stats.blizzard = AH.stats.blizzard + 1 end
  throttledSend("browse", source, function()
    local list = {}
    for _, e in ipairs(MOCK.browseUniverse()) do if (AH.favorites or {})[e.itemID] then list[#list + 1] = e end end
    sortBrowse(list, sorts)
    AH.browse = { results = {}, full = false, pages = { list }, delivered = 0, query = { favorites = true } }
    deliverBrowsePage(true)
  end)
end
local function validateBrowseQuery(q, level)
  if type(q) ~= "table" then MOCK.usage("Usage: C_AuctionHouse.SendBrowseQuery(query): query must be an AuctionHouseBrowseQuery table", level + 1) end
  if type(q.searchString) ~= "string" then MOCK.usage("C_AuctionHouse.SendBrowseQuery: query.searchString (string) is required", level + 1) end
  if type(q.sorts) ~= "table" then MOCK.usage("C_AuctionHouse.SendBrowseQuery: query.sorts (table of AuctionHouseSortType) is required", level + 1) end
  for _, s in ipairs(q.sorts) do
    if type(s) ~= "table" or type(s.sortOrder) ~= "number" or type(s.reverseSort) ~= "boolean" then
      MOCK.usage("C_AuctionHouse.SendBrowseQuery: each sort must be { sortOrder = Enum.AuctionHouseSortOrder.X, reverseSort = bool }", level + 1)
    end
  end
  if q.filters ~= nil then
    if type(q.filters) ~= "table" then MOCK.usage("C_AuctionHouse.SendBrowseQuery: query.filters must be a table of Enum.AuctionHouseFilter", level + 1) end
    for _, f in ipairs(q.filters) do if type(f) ~= "number" or f < 0 or f > 13 then MOCK.usage("C_AuctionHouse.SendBrowseQuery: invalid filter " .. tostring(f), level + 1) end end
  end
  if q.itemClassFilters ~= nil then
    if type(q.itemClassFilters) ~= "table" then MOCK.usage("C_AuctionHouse.SendBrowseQuery: query.itemClassFilters must be a table", level + 1) end
    for _, cf in ipairs(q.itemClassFilters) do
      if type(cf) ~= "table" or type(cf.classID) ~= "number" then MOCK.usage("C_AuctionHouse.SendBrowseQuery: itemClassFilters entries need classID", level + 1) end
    end
  end
end
local function validSorts(sorts, fname, level)
  if type(sorts) ~= "table" then MOCK.usage("Usage: C_AuctionHouse." .. fname .. "(itemKey, sorts, separateOwnerItems): sorts must be a table", level + 1) end
  for _, s in ipairs(sorts) do
    if type(s) ~= "table" or type(s.sortOrder) ~= "number" or type(s.reverseSort) ~= "boolean" then
      MOCK.usage("C_AuctionHouse." .. fname .. ": each sort must be { sortOrder = number, reverseSort = bool }", level + 1)
    end
  end
end
local function resultsFor(id) return AH.results.commodity[id] end
local function itemResults(key) return AH.results.item[keyToken(key)] end
C_AuctionHouse = NS("C_AuctionHouse", {
  MakeItemKey = function(id, ilvl, suffix, pet)
    if type(id) ~= "number" then MOCK.usage("Usage: C_AuctionHouse.MakeItemKey(itemID [, itemLevel, itemSuffix, battlePetSpeciesID])", 2) end
    return { itemID = id, itemLevel = ilvl or 0, itemSuffix = suffix or 0, battlePetSpeciesID = pet or 0 }
  end,
  IsThrottledMessageSystemReady = function() return MOCK.ahReady() end,
  GetItemKeyInfo = function(key, restrict)
    validKey(key, "GetItemKeyInfo", 2)
    local id = key.itemID
    local it = ITEMS[id]; if not it then return nil end
    if not CACHED[id] then startLoad(id, { key = true }); return nil end
    local commodity = MOCK.isCommodity(id)
    return { itemID = id, battlePetSpeciesID = 0, itemName = it.name, quality = it.quality, iconFileID = it.icon or 134400,
             isPet = false, isCommodity = commodity, isEquipment = (it.classID == 2 or it.classID == 4) }
  end,
  GetItemCommodityStatus = function(loc)
    if type(loc) ~= "table" or not loc.IsBagAndSlot then MOCK.usage("Usage: C_AuctionHouse.GetItemCommodityStatus(itemLocation) - takes an ItemLocation, not an itemID", 2) end
    local id = MOCK.itemAtLocation(loc); if not id then return 0 end
    return MOCK.isCommodity(id) and 2 or 1
  end,
  SendSearchQuery = function(itemKey, sorts, separateOwnerItems, minLevel, maxLevel)
    validKey(itemKey, "SendSearchQuery", 2)
    validSorts(sorts, "SendSearchQuery", 2)
    if type(separateOwnerItems) ~= "boolean" then MOCK.usage("Usage: C_AuctionHouse.SendSearchQuery(itemKey, sorts, separateOwnerItems [, minLevelFilter, maxLevelFilter]): separateOwnerItems must be a boolean", 2) end
    MOCK.ahSearch(itemKey, MOCK.ahSource or "addon")
  end,
  SendSellSearchQuery = function(itemKey, sorts, separateOwnerItems) validKey(itemKey, "SendSellSearchQuery", 2); MOCK.ahSearch(itemKey, MOCK.ahSource or "addon") end,
  SendBrowseQuery = function(query) validateBrowseQuery(query, 2); MOCK.ahBrowse(query, MOCK.ahSource or "addon") end,
  SearchForFavorites = function(sorts) validSorts(sorts, "SearchForFavorites", 2); MOCK.ahFavorites(sorts, MOCK.ahSource or "addon") end,
  RequestMoreBrowseResults = function()
    AH.stats.requestMore = AH.stats.requestMore + 1
    local b = AH.browse
    if b.full then return end
    throttledSend("browsemore", MOCK.ahSource or "addon", function() deliverBrowsePage(false) end)
  end,
  HasFullBrowseResults = function() return AH.browse.full == true end,
  GetBrowseResults = function()
    local out = {}
    for i, r in ipairs(AH.browse.results) do
      local k = r.itemKey
      out[i] = { itemKey = { itemID = k.itemID, itemLevel = k.itemLevel, itemSuffix = k.itemSuffix, battlePetSpeciesID = k.battlePetSpeciesID },
                 totalQuantity = r.totalQuantity, minPrice = r.minPrice, containsOwnerItem = r.containsOwnerItem }
    end
    return out
  end,
  GetNumBrowseResults = nil,
  HasSearchResults = function(key)
    validKey(key, "HasSearchResults", 2)
    local r = resultsFor(key.itemID) or itemResults(key)
    return r ~= nil and r.loaded ~= false
  end,
  HasFullCommoditySearchResults = function(id) local r = resultsFor(id); return r ~= nil and r.received >= #r.rows end,
  HasFullItemSearchResults = function(key) validKey(key, "HasFullItemSearchResults", 2); local r = itemResults(key); return r ~= nil and r.received >= #r.rows end,
  RequestMoreCommoditySearchResults = function(id)
    local r = resultsFor(id); if not r then return true end
    if r.received >= #r.rows then return true end
    throttledSend("more", MOCK.ahSource or "addon", function() r.received = math.min(#r.rows, r.received + AH.resultPageSize); fire("COMMODITY_SEARCH_RESULTS_ADDED", id) end)
    return false
  end,
  RequestMoreItemSearchResults = function(key)
    validKey(key, "RequestMoreItemSearchResults", 2)
    local r = itemResults(key); if not r then return true end
    if r.received >= #r.rows then return true end
    throttledSend("more", MOCK.ahSource or "addon", function() r.received = math.min(#r.rows, r.received + AH.resultPageSize); fire("ITEM_SEARCH_RESULTS_ADDED", key) end)
    return false
  end,
  RefreshCommoditySearchResults = function(id) end,
  RefreshItemSearchResults = function(key) end,
  GetNumCommoditySearchResults = function(id)
    AH.stats.numResultCalls = AH.stats.numResultCalls + 1
    local r = resultsFor(id); if not r or r.loaded == false then return 0 end; return r.received
  end,
  GetNumItemSearchResults = function(key)
    validKey(key, "GetNumItemSearchResults", 2)
    AH.stats.numResultCalls = AH.stats.numResultCalls + 1
    local r = itemResults(key); if not r or r.loaded == false then return 0 end; return r.received
  end,
  GetCommoditySearchResultsQuantity = function(id)
    AH.stats.quantityCalls = AH.stats.quantityCalls + 1
    local r = resultsFor(id); if not r or r.loaded == false then return 0 end
    local n = 0; for _, row in ipairs(r.rows) do n = n + row.qty end; return n
  end,
  GetItemSearchResultsQuantity = function(key)
    validKey(key, "GetItemSearchResultsQuantity", 2)
    AH.stats.quantityCalls = AH.stats.quantityCalls + 1
    local r = itemResults(key); if not r or r.loaded == false then return 0 end
    local n = 0; for _, row in ipairs(r.rows) do n = n + row.qty end; return n
  end,
  GetCommoditySearchResultInfo = function(id, index)
    if type(id) ~= "number" or type(index) ~= "number" then MOCK.usage("Usage: C_AuctionHouse.GetCommoditySearchResultInfo(itemID, commoditySearchResultIndex)", 2) end
    AH.stats.commodityInfoCalls[id] = (AH.stats.commodityInfoCalls[id] or 0) + 1
    local r = resultsFor(id); if not r or r.loaded == false or index < 1 or index > r.received then return nil end
    local row = r.rows[index]
    return { itemID = id, quantity = row.qty, unitPrice = row.unit, auctionID = row.auctionID, owners = { row.owner or "Seller" },
             totalNumberOfOwners = 1, timeLeftSeconds = 7200, numOwnerItems = row.mine and row.qty or 0, containsOwnerItem = row.mine == true,
             containsAccountItem = false }
  end,
  GetItemSearchResultInfo = function(key, index)
    validKey(key, "GetItemSearchResultInfo", 2)
    if type(index) ~= "number" then MOCK.usage("Usage: C_AuctionHouse.GetItemSearchResultInfo(itemKey, itemSearchResultIndex)", 2) end
    AH.stats.itemInfoCalls[key.itemID] = (AH.stats.itemInfoCalls[key.itemID] or 0) + 1
    local r = itemResults(key); if not r or r.loaded == false or index < 1 or index > r.received then return nil end
    local row = r.rows[index]
    return { itemKey = { itemID = key.itemID, itemLevel = row.ilvl or key.itemLevel or 0, itemSuffix = row.sfx or 0, battlePetSpeciesID = 0 },
             owners = { row.owner or "Seller" }, totalNumberOfOwners = 1, timeLeft = 2, auctionID = row.auctionID, quantity = row.qty,
             itemLink = MOCK.itemLink(key.itemID), containsOwnerItem = row.mine == true, containsAccountItem = false, containsSocketedItem = false,
             bidder = nil, minBid = row.bid, bidAmount = nil, buyoutAmount = row.bidOnly and nil or row.unit, timeLeftSeconds = 7200 }
  end,
  ReplicateItems = function() after(2, function() fire("REPLICATE_ITEM_LIST_UPDATE") end, "replicate") end,
  GetNumReplicateItems = function() return 0 end,
  GetReplicateItemInfo = function() return nil end,
  GetReplicateItemLink = function() return nil end,
  CalculateCommodityDeposit = function() return 0 end,
  IsSellItemValid = function() return true end,
  GetItemKeyFromItem = function(loc) local id = MOCK.itemAtLocation(loc); return id and { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end,
  FavoritesAreAvailable = function() return true end,
  IsFavoriteItem = function() return false end,
  GetItemKeySampleLink = function(key) return MOCK.itemLink(key.itemID) end,
})
rawset(C_AuctionHouse, "GetNumBrowseResults", nil)

-- ------------------------------------------------------------------------------------- professions / trade skills
MOCK.profs = {}         -- { skillLine, name, rank, max }
MOCK.recipes = {}       -- recipeID -> { name, skillLine, output, qmin, qmax, reagents = {{id, qty}}, tools = {...}, learned, categoryID }
MOCK.TS = { open = nil, ready = false, everOpened = {}, linked = false, guild = false, npc = false }
local PROF_NAMES = { [129] = "First Aid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
  [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning" }
MOCK.PROF_NAMES = PROF_NAMES
local ENUM_TO_SKILL = { [0] = 129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393, 755, 773, 794 }
local SKILL_TO_ENUM = {}; for e, s in pairs(ENUM_TO_SKILL) do SKILL_TO_ENUM[s] = e end
local SECONDARY = { [129] = true, [185] = true, [356] = true }
function GetProfessions()
  -- Forever (Camelot book): prof1, prof2, firstAid, fishing, cooking - addons must identify by skillLine, not position
  local prim, slots = {}, {}
  local fa, fish, cook
  for i, p in ipairs(MOCK.profs) do
    if p.skillLine == 129 then fa = i elseif p.skillLine == 356 then fish = i elseif p.skillLine == 185 then cook = i else prim[#prim + 1] = i end
  end
  if MOCK.profOrder == "shuffled" then return cook, fish, prim[2], fa, prim[1] end
  return prim[1], prim[2], fa, fish, cook
end
function GetProfessionInfo(i)
  local p = MOCK.profs[i]; if not p then return nil end
  return p.name, 136240, p.rank, p.max, 1, 0, p.skillLine, 0, 0, 0, p.name
end
local function openProf() for _, p in ipairs(MOCK.profs) do if p.skillLine == MOCK.TS.open then return p end end end
local function profInfo(p)
  if not p then return { professionID = 0, sourceCounter = 0, professionName = "", expansionName = "", skillLevel = 0, maxSkillLevel = 0, skillModifier = 0, isPrimaryProfession = false } end
  return { profession = SKILL_TO_ENUM[p.skillLine], professionID = p.skillLine, sourceCounter = 1, professionName = p.name, expansionName = "Classic",
           skillLevel = p.rank, maxSkillLevel = p.max, skillModifier = 0, isPrimaryProfession = not SECONDARY[p.skillLine], parentProfessionID = nil }
end
local function recipeVisible(id)
  local r = MOCK.recipes[id]
  return r ~= nil and MOCK.TS.open ~= nil and MOCK.TS.ready and r.skillLine == MOCK.TS.open
end
MOCK.tsStats = { schematicCalls = 0, infoCalls = 0, frames = {} }
C_TradeSkillUI = NS("C_TradeSkillUI", {
  IsTradeSkillReady = function() return MOCK.TS.open ~= nil and MOCK.TS.ready end,
  IsTradeSkillLinked = function() return MOCK.TS.linked, MOCK.TS.linked and "Someone" or nil end,
  IsTradeSkillGuild = function() return MOCK.TS.guild end,
  IsTradeSkillGuildMember = function() return false end,
  IsNPCCrafting = function() return MOCK.TS.npc end,
  IsRuneforging = function() return false end,
  GetBaseProfessionInfo = function() return profInfo(openProf()) end,
  GetChildProfessionInfo = function() local p = openProf(); local i = profInfo(p); if p then i.parentProfessionID = p.skillLine; i.parentProfessionName = p.name end; return i end,
  GetChildProfessionInfos = function() local p = openProf(); return p and { profInfo(p) } or {} end,
  GetProfessionInfoBySkillLineID = function(id) for _, p in ipairs(MOCK.profs) do if p.skillLine == id then return profInfo(p) end end; return profInfo(nil) end,
  GetProfessionInfoByRecipeID = function(id) local r = MOCK.recipes[id]; if r then for _, p in ipairs(MOCK.profs) do if p.skillLine == r.skillLine then return profInfo(p) end end end; return profInfo(nil) end,
  GetProfessionSkillLineID = function(e) return ENUM_TO_SKILL[e] end,
  GetAllRecipeIDs = function()
    local out = {}
    if not (MOCK.TS.open and MOCK.TS.everOpened[MOCK.TS.open]) then return out end
    for id, r in pairs(MOCK.recipes) do if r.skillLine == MOCK.TS.open then out[#out + 1] = id end end
    table.sort(out)
    return out
  end,
  GetFilteredRecipeIDs = function()
    local out = {}
    if not MOCK.TS.ready then return out end
    for id, r in pairs(MOCK.recipes) do if r.skillLine == MOCK.TS.open and r.learned then out[#out + 1] = id end end
    table.sort(out)
    return out
  end,
  GetRecipeInfo = function(id, level)
    MOCK.tsStats.infoCalls = MOCK.tsStats.infoCalls + 1
    if type(id) ~= "number" then MOCK.usage("Usage: C_TradeSkillUI.GetRecipeInfo(recipeSpellID [, recipeLevel])", 2) end
    if not recipeVisible(id) then return nil end
    local r = MOCK.recipes[id]
    return { recipeID = id, name = r.name, categoryID = r.categoryID or 1, learned = r.learned, disabled = false, favorite = false,
             craftable = true, supportsQualities = false, relativeDifficulty = 1, maxTrivialLevel = 100, itemLevel = 0, numSkillUps = 1,
             canSkillUp = true, firstCraft = false, skillLineAbilityID = id, icon = 136240, hyperlink = nil, isRecraft = false,
             isDummyRecipe = false, isGatheringRecipe = false, isEnchantingRecipe = r.output == nil and r.skillLine == 333, isSalvageRecipe = false,
             hasSingleItemOutput = r.output ~= nil, alternateVerb = (r.output == nil and r.skillLine == 333) and "Enchant" or nil }
  end,
  GetRecipeSchematic = function(id, isRecraft, level)
    MOCK.tsStats.schematicCalls = MOCK.tsStats.schematicCalls + 1
    local fno = MOCK.clock.frameNo
    MOCK.tsStats.frames[fno] = (MOCK.tsStats.frames[fno] or 0) + 1
    if type(id) ~= "number" then MOCK.usage("Usage: C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, isRecraft [, recipeLevel])", 2) end
    if type(isRecraft) ~= "boolean" then MOCK.usage("Usage: C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, isRecraft [, recipeLevel]): isRecraft (bool) is required", 2) end
    local r = MOCK.recipes[id]
    if not r then return nil end
    local slots = {}
    for i, rg in ipairs(r.reagents) do
      slots[#slots + 1] = { reagents = { { itemID = rg[1] } }, reagentType = 1, variableQuantities = {}, quantityRequired = rg[2],
        dataSlotType = 1, dataSlotIndex = i, slotIndex = i, required = true, hiddenInCraftingForm = false }
    end
    if r.optional then
      slots[#slots + 1] = { reagents = { { itemID = r.optional } }, reagentType = 0, variableQuantities = {}, quantityRequired = 1,
        dataSlotType = 1, dataSlotIndex = #slots + 1, slotIndex = #slots + 1, required = false, hiddenInCraftingForm = false }
    end
    local rtype = r.output and 1 or ((r.skillLine == 333) and 3 or 1)
    return { recipeID = id, icon = 136240, quantityMin = r.qmin, quantityMax = r.qmax, name = r.name, recipeType = rtype,
             outputItemID = r.output, reagentSlotSchematics = slots, isRecraft = isRecraft, hasCraftingOperationInfo = false }
  end,
  GetRecipeOutputItemData = function(id) local r = MOCK.recipes[id]; if r and r.output then return { icon = 134400, hyperlink = MOCK.itemLink(r.output), itemID = r.output } end; return { icon = 134400 } end,
  GetRecipeRequirements = function(id)
    local r = MOCK.recipes[id]; local out = {}
    if not r then return out end
    for _, t in ipairs(r.tools or {}) do out[#out + 1] = { name = t.name, met = t.met, type = t.type } end
    return out
  end,
  GetCraftableCount = function(id)
    local r = MOCK.recipes[id]; if not r then return 0 end
    local n = math.huge
    for _, rg in ipairs(r.reagents) do n = math.min(n, math.floor(MOCK.bagCount(rg[1]) / rg[2])) end
    if n == math.huge then n = 0 end
    return n
  end,
  GetRecipeLink = function(id) local r = MOCK.recipes[id]; return r and ("|cffffd000|Henchant:" .. id .. "|h[" .. r.name .. "]|h|r") end,
  GetRecipeCooldown = function() return nil, false, 0, 0 end,
  GetRecipeSourceText = function() return nil end,
  GetTradeSkillLineForRecipe = function(id) local r = MOCK.recipes[id]; if r then return r.skillLine, PROF_NAMES[r.skillLine], r.skillLine end end,
  SetShowUnlearned = function(v) MOCK.TS.showUnlearned = v end,
  GetShowUnlearned = function() return MOCK.TS.showUnlearned == true end,
  GetCategories = function() return 1 end,
  GetCategoryInfo = function(id) return { categoryID = id, name = "Category " .. id, numIndents = 0, hasProgressBar = false, type = "header" } end,
  OpenTradeSkill = function(skillLine) if MOCK.openProfession then MOCK.openProfession(skillLine); return true end; return false end,
  CloseTradeSkill = function() if MOCK.closeProfession then MOCK.closeProfession() end end,
  IsRecipeTracked = function() return false end,
  GetSalvagableItemIDs = function() return {} end,
})

-- ------------------------------------------------------------------------------------- merchant
MOCK.merchant = nil
function GetMerchantNumItems() local m = MOCK.merchant; if not (m and m.open) then return 0 end; return #m.items end
local function mitem(i) local m = MOCK.merchant; if not (m and m.open) then return nil end; return m.items[i] end
C_MerchantFrame = NS("C_MerchantFrame", {
  GetItemInfo = function(i)
    if type(i) ~= "number" then MOCK.usage("Usage: C_MerchantFrame.GetItemInfo(index)", 2) end
    local e = mitem(i); if not e then return nil end
    local it = ITEMS[e.itemID] or {}
    return { name = CACHED[e.itemID] and it.name or nil, texture = it.icon or 134400, price = e.price, stackCount = e.stackCount,
             numAvailable = e.numAvailable, isPurchasable = e.isPurchasable ~= false, isUsable = true, hasExtendedCost = e.hasExtendedCost == true,
             currencyID = e.currencyID, spellID = nil, isQuestStartItem = false }
  end,
  GetBuybackItemID = function() return nil end,
  GetNumJunkItems = function() return 0 end,
  IsMerchantItemRefundable = function() return false end,
  IsSellAllJunkEnabled = function() return false end,
})
function GetMerchantItemLink(i) local e = mitem(i); return e and MOCK.itemLink(e.itemID) end
function GetMerchantItemID(i) local e = mitem(i); return e and e.itemID end
function GetMerchantItemCostInfo(i) local e = mitem(i); if e and e.hasExtendedCost then return 1 end; return 0 end
function GetMerchantItemCostItem(i, j) local e = mitem(i); if e and e.hasExtendedCost then return 136240, 10, nil, "Currency" end end
function GetMerchantItemMaxStack(i) local e = mitem(i); return e and (ITEMS[e.itemID] and ITEMS[e.itemID].stack or 1) or 0 end
function GetMerchantNumBuybackItems() return 0 end
function CanMerchantRepair() return false end

-- ------------------------------------------------------------------------------------- loot + spellcasting
MOCK.loot = nil
function GetNumLootItems() return MOCK.loot and #MOCK.loot.items or 0 end
local function lootEntry(slot) return MOCK.loot and MOCK.loot.items[slot] end
function GetLootSlotInfo(slot)
  local e = lootEntry(slot); if not e then return nil end
  local it = ITEMS[e.itemID] or {}
  return it.icon or 134400, it.name, e.qty, nil, it.quality or 1, false, false, nil, false, false
end
function GetLootSlotLink(slot) local e = lootEntry(slot); return e and MOCK.itemLink(e.itemID) end
function GetLootSlotType(slot) local e = lootEntry(slot); return e and 1 or 0 end
function GetLootSourceInfo(slot)
  local e = lootEntry(slot); if not e then return nil end
  return MOCK.loot.source, e.qty
end
function LootSlot(slot) end
function CloseLoot() end
function LootSlotHasItem(slot) return lootEntry(slot) ~= nil end
function IsFishingLoot() return false end
function GetLootInfo() local out = {}; for i, e in ipairs(MOCK.loot and MOCK.loot.items or {}) do local it = ITEMS[e.itemID] or {}; out[i] = { item = it.name, quantity = e.qty, quality = it.quality, locked = false } end; return out end
function SpellIsTargeting() return MOCK.targetingSpell ~= nil end
function GetAutoLootDefault() return false end
'''

# =====================================================================================================================
# Lua: Blizzard frames that exist at login (UIParent, tooltip, chat) and the load-on-demand AH / Professions UIs
# =====================================================================================================================
LUA_FRAMES = r'''
local CFG, API = ...
local MOCK = __WOWMOCK
local newWidget, child, fstring, tex, protected, fire = MOCK.newWidget, MOCK.child, MOCK.fstring, MOCK.tex, MOCK.protected, MOCK.fire

MOCK.blizzardDepth = 1
UIParent = newWidget("Frame", "UIParent"); MOCK.frames[#MOCK.frames + 1] = UIParent
WorldFrame = newWidget("Frame", "WorldFrame")
UIParent._w, UIParent._h = 1920, 1080
GameTooltip = newWidget("GameTooltip", "GameTooltip", UIParent); MOCK.frames[#MOCK.frames + 1] = GameTooltip
GameTooltip._shown = false
ItemRefTooltip = newWidget("GameTooltip", "ItemRefTooltip", UIParent); ItemRefTooltip._shown = false
DEFAULT_CHAT_FRAME = newWidget("ScrollingMessageFrame", "ChatFrame1", UIParent)
rawset(DEFAULT_CHAT_FRAME, "AddMessage", function(self, msg, r, g, b)
  if msg ~= nil and type(msg) ~= "string" and type(msg) ~= "number" then error("ChatFrame:AddMessage(): message must be a string", 2) end
  MOCK.chat[#MOCK.chat + 1] = { t = MOCK.clock.now, msg = tostring(msg) }
end)
SELECTED_CHAT_FRAME = DEFAULT_CHAT_FRAME
MOCK.blizzardDepth = 0
SlashCmdList = {}
UISpecialFrames = {}
UIPanelWindows = {}
function ShowUIPanel(f) if f then f:Show() end end
function HideUIPanel(f) if f then f:Hide() end end
function CloseSpecialWindows()
  local found = false
  for _, name in ipairs(UISpecialFrames) do local f = rawget(_G, name); if f and f:IsShown() then f:Hide(); found = true end end
  return found
end
MOCK.shownFrames = function() local n = 0; for _, f in ipairs(MOCK.frames) do if f:IsVisible() then n = n + 1 end end; return n end

-- ------------------------------------------------------------------------------------- Blizzard_AuctionHouseUI (load on demand)
local function itemList(parent, key)
  local list = child(parent, key, "Frame")
  local sb = child(list, "ScrollBox", "Frame", "WowScrollBoxList")
  sb._points = { { "TOPLEFT", list, "TOPLEFT", 0, -20 }, { "BOTTOMRIGHT", list, "BOTTOMRIGHT", -20, 0 } }
  child(list, "ScrollBar", "EventFrame", "MinimalScrollBar")
  list._points = { { "TOPLEFT", parent, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0 } }
  local tb = { rows = {} }
  function tb:AddRow(row, key) local data = list.getEntry and list.getEntry(key); if not data then return end; row.rowData = data; self.rows[#self.rows + 1] = row end
  function tb:RemoveRow(row) tDeleteItem(self.rows, row) end
  list.tableBuilder = tb
  rawset(list, "SetDataProvider", function(self, fn) self.getEntry = fn end)
  rawset(list, "RefreshScrollFrame", function(self) self.ScrollBox:FullUpdate() end)
  rawset(list, "Reset", function(self) self.ScrollBox:SetDataProvider(CreateIndexRangeDataProvider(0)) end)
  rawset(list, "GetSelectedEntry", function() return nil end)
  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(20)
  view:SetElementFactory(function(factory, elementData) factory("AuctionHouseItemListLineTemplate", function(button, data) button:SetEnabled(true) end) end)
  ScrollUtil.InitScrollBoxListWithScrollBar(sb, list.ScrollBar, view)
  -- the table builder sets button.rowData in its OnInitializedFrame callback (registered at Init, i.e. before addons)
  ScrollUtil.RegisterTableBuilder(sb, tb, function(e) return e end)
  return list
end
MOCK.rowTemplates.AuctionHouseItemListLineTemplate = function(parent)
  local b = newWidget("Button", nil, parent); MOCK.frames[#MOCK.frames + 1] = b
  b._normalTex = newWidget("Texture", nil, b)
  local hl = tex(b, "SelectedHighlight"); hl._shown = false
  local hl2 = tex(b, "HighlightTexture")
  rawset(b, "GetElementData", function(self) return self._elementData end)
  rawset(b, "GetElementDataIndex", function(self) return self._elementIndex end)
  rawset(b, "GetRowData", function(self) return self.rowData end)
  return b
end
function MOCK.loadAuctionHouseUI()
  if MOCK.loadedAddons.Blizzard_AuctionHouseUI then return end
  MOCK.blizzardDepth = (MOCK.blizzardDepth or 0) + 1
  local f = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
  MOCK.namedFrames.AuctionHouseFrame = nil
  f._w, f._h = 800, 538
  f._points = { { "TOPLEFT", UIParent, "TOPLEFT", 16, -116 } }
  f._shown = false
  local bar = child(f, "SearchBar", "Frame")
  local box = child(bar, "SearchBox", "EditBox", "SearchBoxTemplate")
  child(bar, "SearchButton", "Button", "UIPanelButtonTemplate")
  child(bar, "FilterButton", "DropdownButton")
  rawset(bar, "SetSearchText", function(self, text) self.SearchBox:SetText(text or "") end)
  rawset(bar, "GetSearchText", function(self) return self.SearchBox:GetText() end)
  rawset(bar, "StartSearch", function(self)
    local text = self.SearchBox:GetText()
    MOCK.AH.blizzardSearchText = text
    f:SendBrowseQuery(text, 0, 0, {})
  end)
  for _, k in ipairs({ "CategoriesList", "BrowseResultsFrame", "CommoditiesBuyFrame", "ItemBuyFrame", "ItemSellFrame", "CommoditiesSellFrame",
                       "AuctionsFrame", "WoWTokenResults", "MoneyFrameBorder" }) do
    local c = child(f, k, "Frame"); c._points = { { "TOPLEFT", f, "TOPLEFT", 160, -90 }, { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 30 } }; c._shown = false
  end
  itemList(f.BrowseResultsFrame, "ItemList")
  itemList(f.CommoditiesBuyFrame, "ItemList")
  child(f.CommoditiesBuyFrame, "BuyDisplay", "Frame")
  itemList(f.ItemBuyFrame, "ItemList")
  for _, k in ipairs({ "BuyTab", "SellTab", "AuctionsTab" }) do child(f, k, "Button", "PanelTabButtonTemplate") end
  AuctionHouseFrameDisplayMode = {
    Buy = { "SearchBar", "CategoriesList", "BrowseResultsFrame" },
    WoWTokenBuy = { "SearchBar", "CategoriesList", "WoWTokenResults" },
    CommoditiesBuy = { "CommoditiesBuyFrame" },
    ItemBuy = { "ItemBuyFrame" },
    CommoditiesSell = { "CommoditiesSellFrame" },
    ItemSell = { "ItemSellFrame" },
    WoWTokenSell = { "WoWTokenSellFrame" },
    Auctions = { "AuctionsFrame" },
  }
  local M = AuctionHouseFrameDisplayMode
  local allKeys = { "SearchBar", "CategoriesList", "BrowseResultsFrame", "CommoditiesBuyFrame", "ItemBuyFrame", "ItemSellFrame", "CommoditiesSellFrame", "AuctionsFrame", "WoWTokenResults" }
  rawset(f, "SetDisplayMode", function(self, mode)
    if type(mode) ~= "table" then error("AuctionHouseFrame:SetDisplayMode(displayMode): use AuctionHouseFrameDisplayMode.X", 2) end
    self.displayMode = mode
    local on = {}; for _, k in ipairs(mode) do on[k] = true end
    for _, k in ipairs(allKeys) do local c = rawget(self, k); if c then c:SetShown(on[k] == true) end end
  end)
  rawset(f, "GetDisplayMode", function(self) return self.displayMode end)
  rawset(f, "SetSearchText", function(self, text)
    local m = self.displayMode
    if m ~= M.Buy and m ~= M.ItemBuy and m ~= M.CommoditiesBuy and m ~= M.WoWTokenBuy then return false end
    self.SearchBar:SetSearchText(text); return true
  end)
  rawset(f, "SendBrowseQuery", function(self, searchString, minLevel, maxLevel, filtersArray)
    MOCK.ahSource = "blizzard"
    local ok, err = pcall(C_AuctionHouse.SendBrowseQuery, { searchString = searchString or "", sorts = { { sortOrder = 0, reverseSort = false } },
      minLevel = minLevel, maxLevel = maxLevel, filters = filtersArray or {} })
    MOCK.ahSource = nil
    if not ok then error(err, 2) end
  end)
  rawset(f, "SelectBrowseResult", function(self, r) end)
  rawset(f, "QueryItem", function(self, ctx, itemKey, byItemID) MOCK.ahSource = "blizzard"; MOCK.ahSearch(itemKey, "blizzard"); MOCK.ahSource = nil end)
  rawset(f, "GetBrowseSortOrder", function() return { { sortOrder = 0, reverseSort = false } } end)
  f:SetDisplayMode(M.Buy)
  MOCK.blizzardDepth = MOCK.blizzardDepth - 1
  MOCK.lodLoaders.Blizzard_AuctionHouseUI = nil
  fire("ADDON_LOADED", "Blizzard_AuctionHouseUI", false)
end
MOCK.lodLoaders.Blizzard_AuctionHouseUI = function() MOCK.loadAuctionHouseUI() end
function MOCK.openAH()
  MOCK.loadAuctionHouseUI()
  MOCK.AH.open = true
  MOCK.AH.queue = {}
  if MOCK.ahShowOrder == "event-first" then
    fire("AUCTION_HOUSE_SHOW")
    fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
    AuctionHouseFrame:Show()
  else
    fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 21)
    AuctionHouseFrame:Show()
    fire("AUCTION_HOUSE_SHOW")
  end
end
function MOCK.closeAH()
  MOCK.AH.open = false
  fire("AUCTION_HOUSE_CLOSED")
  fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 21)
  if AuctionHouseFrame then AuctionHouseFrame:Hide() end
end
-- show Blizzard's own result lists (rows get rowData through the table builder, then OnInitializedFrame callbacks run)
function MOCK.ahShowBrowse()
  local f = AuctionHouseFrame
  f:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
  local list = f.BrowseResultsFrame.ItemList
  local results = C_AuctionHouse.GetBrowseResults()
  list.getEntry = function(i) return results[i] end
  list.ScrollBox:SetDataProvider(CreateIndexRangeDataProvider(#results))
  return list
end
function MOCK.ahShowCommodity(id)
  local f = AuctionHouseFrame
  f:SetDisplayMode(AuctionHouseFrameDisplayMode.CommoditiesBuy)
  local list = f.CommoditiesBuyFrame.ItemList
  local n = C_AuctionHouse.GetNumCommoditySearchResults(id)
  local rows = {}
  for i = 1, n do rows[i] = C_AuctionHouse.GetCommoditySearchResultInfo(id, i) end
  list.getEntry = function(i) return rows[i] end
  list.ScrollBox:SetDataProvider(CreateIndexRangeDataProvider(#rows))
  return list
end
function MOCK.ahShowItem(id)
  local f = AuctionHouseFrame
  f:SetDisplayMode(AuctionHouseFrameDisplayMode.ItemBuy)
  local list = f.ItemBuyFrame.ItemList
  local key = C_AuctionHouse.MakeItemKey(id)
  local n = C_AuctionHouse.GetNumItemSearchResults(key)
  local rows = {}
  for i = 1, n do rows[i] = C_AuctionHouse.GetItemSearchResultInfo(key, i) end
  list.getEntry = function(i) return rows[i] end
  list.ScrollBox:SetDataProvider(CreateIndexRangeDataProvider(#rows))
  return list
end

-- ------------------------------------------------------------------------------------- Blizzard_Professions (load on demand)
MOCK.rowTemplates.ProfessionsRecipeListRecipeTemplate = function(parent)
  local b = newWidget("Button", nil, parent); MOCK.frames[#MOCK.frames + 1] = b
  b._w, b._h = 300, 20
  local label = fstring(b, "Label", "GameFontHighlightSmall"); label._points = { { "LEFT", b, "LEFT", 11, 0 } }
  local count = fstring(b, "Count", "GameFontHighlightSmall"); count._points = { { "LEFT", label, "RIGHT", 0, 0 } }
  local su = child(b, "SkillUps", "Button"); su._w, su._h = 20, 20; tex(su, "Icon"); fstring(su, "Text", "GameFontHighlightSmall"); su._shown = false
  local li = child(b, "LockedIcon", "Button"); li._shown = false
  tex(b, "SelectedOverlay"); tex(b, "HighlightOverlay")
  rawset(b, "GetElementData", function(self) return self._elementData end)
  rawset(b, "Init", function(self, node, hide)
    local d = node:GetData()
    self.Label:SetText(d.recipeInfo.name)
    self.learned = d.recipeInfo.learned
    local n = C_TradeSkillUI.GetCraftableCount(d.recipeInfo.recipeID)
    if n > 0 and not hide then self.Count:SetFormattedText(" [%d] ", n); self.Count:Show() else self.Count:Hide() end
  end)
  rawset(b, "SetSelected", function(self, v) self.selected = v end)
  rawset(b, "SetLabelFontColors", function(self, c) end)
  return b
end
MOCK.rowTemplates.ProfessionsRecipeListCategoryTemplate = function(parent)
  local b = newWidget("Button", nil, parent); MOCK.frames[#MOCK.frames + 1] = b
  b._w, b._h = 300, 20
  fstring(b, "Label", "GameFontNormal")
  rawset(b, "GetElementData", function(self) return self._elementData end)
  rawset(b, "Init", function(self, node) self.Label:SetText(node:GetData().categoryInfo.name) end)
  rawset(b, "UpdateCollapsedState", function() end)
  return b
end
function MOCK.loadProfessionsUI()
  if MOCK.loadedAddons.Blizzard_Professions then return end
  MOCK.blizzardDepth = (MOCK.blizzardDepth or 0) + 1
  local f = CreateFrame("Frame", "ProfessionsFrame", UIParent)
  MOCK.namedFrames.ProfessionsFrame = nil
  f._w, f._h = 942, 658
  f._points = { { "TOPLEFT", UIParent, "TOPLEFT", 16, -116 } }
  f._shown = false
  local page = child(f, "CraftingPage", "Frame"); page._points = { { "TOPLEFT", f, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0 } }
  child(f, "BookPage", "Frame")
  local list = child(page, "RecipeList", "Frame"); list._w, list._h = 300, 560; list._points = { { "TOPLEFT", page, "TOPLEFT", 8, -80 } }
  local sb = child(list, "ScrollBox", "Frame", "WowScrollBoxList"); sb._points = { { "TOPLEFT", list, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", list, "BOTTOMRIGHT", -20, 0 } }
  child(list, "ScrollBar", "EventFrame", "MinimalScrollBar")
  list.selectionBehavior = { IsElementDataSelected = function() return false end, Select = function() end }
  local view = CreateScrollBoxListTreeListView(10, 5, 5, 0, 5, 1)
  view:SetElementExtent(20)
  view:SetElementFactory(function(factory, node)
    local d = node:GetData()
    if d.categoryInfo then factory("ProfessionsRecipeListCategoryTemplate", function(button, n) button:Init(n) end)
    else factory("ProfessionsRecipeListRecipeTemplate", function(button, n) button:Init(n, false) end) end
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(sb, list.ScrollBar, view)
  Professions = { GetHighestLearnedRecipe = function(info) return info end, InLocalCraftingMode = function() return true end }
  MOCK.blizzardDepth = MOCK.blizzardDepth - 1
  MOCK.lodLoaders.Blizzard_Professions = nil
  fire("ADDON_LOADED", "Blizzard_ProfessionsTemplates", false)
  fire("ADDON_LOADED", "Blizzard_Professions", false)
end
MOCK.lodLoaders.Blizzard_Professions = function() MOCK.loadProfessionsUI() end
function MOCK.populateRecipeList()
  local dp = CreateTreeDataProvider()
  local cat = dp:Insert({ categoryInfo = { name = MOCK.PROF_NAMES[MOCK.TS.open] or "Recipes", categoryID = 1 } })
  local ids = C_TradeSkillUI.GetFilteredRecipeIDs()
  for _, id in ipairs(ids) do cat:Insert({ recipeInfo = C_TradeSkillUI.GetRecipeInfo(id) }) end
  ProfessionsFrame.CraftingPage.RecipeList.ScrollBox:SetDataProvider(dp)
end
function MOCK.openProfession(skillLine, opts)
  opts = opts or {}
  MOCK.loadProfessionsUI()
  MOCK.TS.open = skillLine
  MOCK.TS.ready = false
  MOCK.TS.everOpened[skillLine] = true
  fire("TRADE_SKILL_DATA_SOURCE_CHANGING")
  fire("TRADE_SKILL_SHOW")
  ProfessionsFrame:Show()
  EventRegistry:TriggerEvent("ProfessionsFrame.Show")
  MOCK.after(opts.readyDelay or 0.2, function()
    if MOCK.TS.open ~= skillLine then return end
    MOCK.TS.ready = true
    fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
    fire("TRADE_SKILL_LIST_UPDATE")
    MOCK.populateRecipeList()
    EventRegistry:TriggerEvent("Professions.ProfessionSelected", C_TradeSkillUI.GetBaseProfessionInfo())
  end, "tradeskill-ready")
end
function MOCK.closeProfession()
  if not MOCK.TS.open then return end
  MOCK.TS.open = nil; MOCK.TS.ready = false
  fire("TRADE_SKILL_CLOSE")
  if ProfessionsFrame then ProfessionsFrame:Hide() end
  EventRegistry:TriggerEvent("ProfessionsFrame.Hide")
end

-- ------------------------------------------------------------------------------------- merchant / disenchant drivers
function MOCK.openMerchant(m)
  MOCK.merchant = m; m.open = true
  MOCK.zone = { name = m.zone, map = m.map, x = m.x, y = m.y }
  fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
  fire("MERCHANT_SHOW")
  MOCK.after(0.1, function() if MOCK.merchant == m and m.open then fire("MERCHANT_UPDATE") end end, "merchant-update")
end
function MOCK.closeMerchant()
  if not MOCK.merchant then return end
  MOCK.merchant.open = false
  fire("MERCHANT_CLOSED")
  fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
end
local castSeq = 0
function MOCK.bagChanged(bag) fire("BAG_UPDATE", bag); MOCK.after(0.05, function() fire("BAG_UPDATE_DELAYED") end, "bagdelayed") end
-- Disenchant cast on bag/slot, then the loot window with `items` ({ {itemID, qty}, ... })
function MOCK.disenchant(bag, slot, items, opts)
  opts = opts or {}
  local e = MOCK.BAGS[bag] and MOCK.BAGS[bag][slot]
  if not e then error("wowmock.disenchant: no item in bag " .. bag .. " slot " .. slot) end
  castSeq = castSeq + 1
  local guid = "Cast-3-4613-1-1-13262-" .. string.format("%010X", castSeq)
  MOCK.targetingSpell = 13262
  e.locked = true
  fire("ITEM_LOCK_CHANGED", bag, slot)
  fire("CURRENT_SPELL_CAST_CHANGED", false)
  fire("UNIT_SPELLCAST_SENT", "player", (MOCK.ITEMS[e.itemID] or {}).name or "", guid, 13262)
  fire("UNIT_SPELLCAST_START", "player", guid, 13262)
  MOCK.targetingSpell = nil
  local castTime = opts.castTime or 3
  MOCK.after(castTime, function()
    if opts.interrupt then
      fire("UNIT_SPELLCAST_INTERRUPTED", "player", guid, 13262)
      fire("UNIT_SPELLCAST_STOP", "player", guid, 13262)
      e.locked = false; fire("ITEM_LOCK_CHANGED", bag, slot)
      return
    end
    local function loot()
      MOCK.loot = { items = {}, source = "Item-4613-0-40000000" .. string.format("%08X", castSeq), kind = "disenchant" }
      for _, it in ipairs(items) do MOCK.loot.items[#MOCK.loot.items + 1] = { itemID = it[1], qty = it[2] }; MOCK.CACHED[it[1]] = MOCK.ITEMS[it[1]] and true or nil end
      fire("LOOT_READY", opts.autoloot and true or false)
      fire("LOOT_OPENED", opts.autoloot and true or false, false)
      MOCK.after(opts.lootDelay or 0.3, function()
        for i, it in ipairs(MOCK.loot and MOCK.loot.items or {}) do
          MOCK.addBagItem(it.itemID, it.qty, true)
          fire("LOOT_SLOT_CLEARED", i)
        end
        MOCK.loot = nil
        fire("LOOT_CLOSED")
        MOCK.bagChanged(0)
      end, "loot-close")
    end
    local function consume()
      MOCK.BAGS[bag][slot] = nil
      fire("ITEM_LOCK_CHANGED", bag, slot)
      MOCK.bagChanged(bag)
    end
    if opts.order == "loot-first" then
      loot(); fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, 13262); fire("UNIT_SPELLCAST_STOP", "player", guid, 13262); consume()
    else
      fire("UNIT_SPELLCAST_STOP", "player", guid, 13262)
      fire("UNIT_SPELLCAST_SUCCEEDED", "player", guid, 13262)
      consume()
      loot()
    end
  end, "disenchant-cast")
end
-- an unrelated loot window (mob corpse / chest)
function MOCK.lootWindow(items, source)
  MOCK.loot = { items = {}, source = source or "Creature-0-4613-1-1-3100-0000ABCDEF", kind = "other" }
  for _, it in ipairs(items) do MOCK.loot.items[#MOCK.loot.items + 1] = { itemID = it[1], qty = it[2] }; MOCK.CACHED[it[1]] = MOCK.ITEMS[it[1]] and true or nil end
  fire("LOOT_READY", false)
  fire("LOOT_OPENED", false, false)
  MOCK.after(0.3, function()
    for _, it in ipairs(MOCK.loot and MOCK.loot.items or {}) do MOCK.addBagItem(it.itemID, it.qty, true) end
    MOCK.loot = nil
    fire("LOOT_CLOSED")
    MOCK.bagChanged(0)
  end, "loot-close")
end
function MOCK.addBagItem(id, count, silent)
  MOCK.CACHED[id] = MOCK.ITEMS[id] and true or nil      -- the client always knows the items in your bags
  local stack = (MOCK.ITEMS[id] and MOCK.ITEMS[id].stack) or 1
  for bag = 0, 4 do
    for slot = 1, MOCK.bagSlots[bag] or 0 do
      local e = MOCK.BAGS[bag][slot]
      if e and e.itemID == id and e.count < stack and count > 0 then
        local add = math.min(stack - e.count, count); e.count = e.count + add; count = count - add
      end
    end
  end
  for bag = 0, 4 do
    for slot = 1, MOCK.bagSlots[bag] or 0 do
      if count <= 0 then break end
      if not MOCK.BAGS[bag][slot] then local add = math.min(stack, count); MOCK.BAGS[bag][slot] = { itemID = id, count = add }; count = count - add end
    end
  end
  if not silent then MOCK.bagChanged(0) end
end

-- ------------------------------------------------------------------------------------- SavedVariables serializer (like the client)
function MOCK.serialize(v, indent, seen)
  indent = indent or ""; seen = seen or {}
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("SavedVariables: cannot save " .. tostring(v)) end
    if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
    return string.format("%.17g", v)
  end
  if t == "boolean" then return tostring(v) end
  if t == "table" then
    if seen[v] then error("SavedVariables: table saved twice (shared reference)") end
    if rawget(v, "_kind") then error("SavedVariables: a frame/widget is stored in the saved table") end
    seen[v] = true
    local parts = {}
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) if type(a) == type(b) then return a < b end return type(a) == "number" end)
    for _, k in ipairs(keys) do
      local kt = type(k)
      if kt ~= "string" and kt ~= "number" and kt ~= "boolean" then error("SavedVariables: unsupported key type " .. kt) end
      local val = v[k]
      local vt = type(val)
      if vt == "function" or vt == "userdata" or vt == "thread" then error("SavedVariables: unsupported value type " .. vt .. " at key " .. tostring(k)) end
      parts[#parts + 1] = indent .. "\t[" .. (kt == "string" and string.format("%q", k) or tostring(k)) .. "] = " .. MOCK.serialize(val, indent .. "\t", seen) .. ","
    end
    seen[v] = nil
    return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
  end
  error("SavedVariables: unsupported type " .. t)
end
'''


# =====================================================================================================================
# Python API
# =====================================================================================================================
def _strip(text):
    if text is None:
        return None
    t = re.sub(r"\|c[0-9a-fA-F]{8}", "", str(text))
    t = t.replace("|r", "")
    t = re.sub(r"\|T[^|]*\|t", "", t)
    t = re.sub(r"\|A[^|]*\|a", "", t)
    t = re.sub(r"\|H[^|]*\|h(.*?)\|h", r"\1", t)
    return t


class WowClient:
    """A fresh simulated client. See the module docstring for an example."""

    def __init__(self, locale="enUS", char=DEFAULT_CHAR, strict=True, cached=True, server_time=SERVER_TIME0,
                 level=25, verbose=False, item_load_delay=0.05):
        self.locale = locale
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.G = self.lua.globals()
        api = _json("forever_api.json")
        L = self.lua.table_from
        sets = lambda items: L({k: True for k in items})
        api_lua = L({
            "globals": sets(api["globals"]),
            "ns": L({ns: sets(fns) for ns, fns in api["namespaces"].items()}),
            "events": sets(api["events"]),
            "enums": L({k: L(v) for k, v in api["enums"].items()}),
            "widget": L({k: sets(v) for k, v in api["widget"].items()}),
            "templates": L({k: L([v[0], v[1] or False]) for k, v in api["templates"].items()}),
            "template_hints": L(INVALID_TEMPLATE_HINT),
            "fonts": sets(api["fonts"]),
            "ui_globals": sets(api["ui_globals"]),
            "soundkit": L(api["soundkit"]),
            "allow_absent": sets(ALLOW_ABSENT),
            "scrollbox_methods": L(api.get("scrollbox_methods", [])),
        })
        cfg = L({"strict": strict, "locale": locale, "char": char, "clock0": 1000.0, "server0": server_time,
                 "verbose": verbose, "level": level})
        loader = self.lua.eval("function(src, name) local f, e = loadstring(src, name); if not f then error(e) end; return f end")
        for name, src in (("=wowmock-core", LUA_CORE), ("=wowmock-widgets", LUA_WIDGETS), ("=wowmock-shared", LUA_SHARED),
                          ("=wowmock-api", LUA_API), ("=wowmock-frames", LUA_FRAMES)):
            loader(src, name)(cfg, api_lua)
        self.lua.execute("""for _, k in ipairs({'io', 'require', 'dofile', 'loadfile', 'module', 'package'}) do rawset(_G, k, nil) end
          local real, M = debug, __WOWMOCK
          -- the client has no 'debug' library; lupa itself needs it, so only addon code is flagged
          rawset(_G, 'debug', setmetatable({}, { __index = function(_, k)
            if M.addonWhere(2) then M.violation('global', 'debug.' .. tostring(k), 2) end
            return real[k] end }))""")
        self.M = self.lua.eval("__WOWMOCK")
        self.M.itemLoadDelay = item_load_delay
        self._driver = self.lua.eval("function(src) local f, e = loadstring(src, '=driver'); if not f then error(e) end; return f end")
        self._rawget = self.lua.eval("function(k) return rawget(_G, k) end")
        self.items = {}
        fx = _json("items.json")["items"]
        for k, v in fx.items():
            self.add_item(int(k), **v)
        if cached:
            self.lua.execute("for id in pairs(__WOWMOCK.ITEMS) do __WOWMOCK.CACHED[id] = true end")
        self.WC = None
        self.sv_text = None
        self.toc = None
        self.set_char(char)

    # ------------------------------------------------------------------ helpers
    def eval(self, src, *args):
        """Run a Lua chunk (driver code, not addon code) with optional args (available as ...)."""
        return self._driver(src)(*args)

    def g(self, name):
        """rawget a global (does not trip the strict checks)."""
        return self._rawget(name)

    def table(self, obj):
        return self.lua.table_from(obj, recursive=True)

    # ------------------------------------------------------------------ fixtures
    def add_item(self, item_id, name, quality=1, ilvl=1, req=0, classID=7, subclassID=0, equipLoc="", sell=0, buy=0,
                 vstack=1, stack=20, flags=0, icon=134400, cached=None, **_):
        it = {"name": name, "quality": quality, "ilvl": ilvl, "req": req, "classID": classID, "subclassID": subclassID,
              "equipLoc": equipLoc, "sell": sell, "buy": buy, "vstack": vstack, "stack": stack, "flags": flags, "icon": icon}
        self.items[item_id] = it
        self.M.ITEMS[item_id] = self.lua.table_from(it)
        if cached is True:
            self.M.CACHED[item_id] = True
        elif cached is False:
            self.M.CACHED[item_id] = None

    def uncache(self, ids=None):
        if ids is None:
            self.lua.execute("for k in pairs(__WOWMOCK.CACHED) do __WOWMOCK.CACHED[k] = nil end")
        else:
            for i in ids:
                self.M.CACHED[i] = None

    def cache(self, ids=None):
        if ids is None:
            self.lua.execute("for id in pairs(__WOWMOCK.ITEMS) do __WOWMOCK.CACHED[id] = true end")
        else:
            for i in ids:
                self.M.CACHED[i] = True

    def set_char(self, guid, professions=None, recipes=None):
        """Select a character from tests/fixtures/recipes.json (professions + recipes) or pass them explicitly."""
        self.M.player.guid = guid
        data = _json("recipes.json")["chars"].get(guid)
        if professions is None:
            professions = [(sl, 150, 225) for sl in (data["professions"] if data else [])]
        if recipes is None:
            recipes = {int(k): v for k, v in (data["recipes"] if data else {}).items()}
        self.set_professions(professions)
        self.set_recipes(recipes)

    def set_professions(self, profs):
        names = self.M.PROF_NAMES
        self.M.profs = self.table([{"skillLine": sl, "name": names[sl] or ("Skill %d" % sl), "rank": rank, "max": mx}
                                   for sl, rank, mx in profs])

    def set_recipes(self, recipes):
        """recipes: {recipeID: {name, skillLine, output, qmin, qmax, reagents: [[itemID, qty]], tools: [{name, met, type}], learned}}"""
        out = {}
        for rid, r in recipes.items():
            out[int(rid)] = {"name": r["name"], "skillLine": r["skillLine"], "output": r.get("output"),
                             "qmin": r.get("qmin", 1), "qmax": r.get("qmax", 1),
                             "reagents": [list(x) for x in r.get("reagents", [])], "tools": r.get("tools", []),
                             "learned": r.get("learned", True), "categoryID": r.get("categoryID", 1)}
            if out[int(rid)]["output"] is None:
                del out[int(rid)]["output"]
        self.M.recipes = self.table(out)

    def learn_disenchant(self, known=True):
        self.M.spells[13262].known = known

    # ------------------------------------------------------------------ loading
    def load_sv(self, path_or_text):
        """SavedVariables to apply after the addon files ran and before ADDON_LOADED (like the client)."""
        if os.path.exists(str(path_or_text)):
            with open(path_or_text, encoding="utf-8") as f:
                self.sv_text = f.read()
        else:
            self.sv_text = path_or_text

    def load_addon(self, toc="WaylaidCrate/WaylaidCrate.toc", fire_loaded=True):
        toc_path = toc if os.path.isabs(toc) else os.path.join(REPO, toc)
        addon_dir = os.path.dirname(toc_path)
        addon = os.path.splitext(os.path.basename(toc_path))[0]
        meta, files, svs = {}, [], []
        with open(toc_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("##"):
                    k, _, v = line[2:].partition(":")
                    meta[k.strip()] = v.strip()
                    if k.strip() == "SavedVariables":
                        svs = [s.strip() for s in v.split(",") if s.strip()]
                elif line and not line.startswith("#"):
                    files.append(line.replace("\\", "/"))
        self.toc = {"meta": meta, "files": files, "sv": svs, "dir": addon_dir, "name": addon}
        self.M.addonMeta[addon] = self.lua.table_from(meta)
        ns = self.lua.table()
        run = self.lua.eval("""function(src, chunk, addon, ns, file)
          local f, err = loadstring(src, chunk)
          if not f then
            local M = __WOWMOCK; M.errors[#M.errors + 1] = { context = "load:" .. file, msg = err, tb = "" }
            return false
          end
          return __WOWMOCK.protected("load:" .. file, f, addon, ns)
        end""")
        self.loaded_files, self.missing_files = [], []
        for fname in files:
            path = os.path.join(addon_dir, fname)
            if not os.path.exists(path):
                self.missing_files.append(fname)
                self.M.missingFiles[len(self.missing_files)] = fname
                continue
            with open(path, encoding="utf-8") as f:
                src = f.read()
            run(src, "@%s/%s" % (addon, fname), addon, ns, fname)
            self.loaded_files.append(fname)
        self.WC = ns
        if self.sv_text is not None:
            env = self.eval("""local src = ...
              local f, err = loadstring(src, '=SavedVariables'); if not f then error(err) end
              local env = {}; setfenv(f, env); f(); return env""", self.sv_text)
            for name in svs:
                v = env[name]
                if v is not None:
                    self.lua.eval("rawset")(self.G, name, v)
        if fire_loaded:
            self.fire("ADDON_LOADED", addon, False)
        return ns

    def login(self):
        self.M.loggedIn = True
        self.fire("PLAYER_LOGIN")
        self.fire("PLAYER_ENTERING_WORLD", True, False)
        self.advance(0.5)
        self.fire("SKILL_LINES_CHANGED")
        self.fire("BAG_UPDATE_DELAYED")
        self.advance(0.5)

    def logout_sv(self):
        """Serialize the SavedVariables like the client does on logout (fails on functions / frames / shared tables)."""
        self.fire("PLAYER_LOGOUT")
        parts = []
        for name in self.toc["sv"]:
            v = self.g(name)
            if v is not None:
                parts.append("%s = %s\n" % (name, self.M.serialize(v)))
        return "".join(parts)

    # ------------------------------------------------------------------ time / events
    def advance(self, seconds, until=None):
        if until is not None and not callable(until):
            raise TypeError("until must be callable")
        stop = None
        if until is not None:
            stop = lambda: bool(until())
        self.M.run(float(seconds), stop)

    def now(self):
        return float(self.M.clock.now)

    def server_time(self):
        return int(self.eval("return GetServerTime()"))

    def set_server_time(self, t):
        """Jump the server clock (GetServerTime/time/date) without running timers."""
        c = self.M.clock
        c.server0 = t - (c.now - c.start)

    def fire(self, event, *args):
        self.M.fire(event, *args)

    # ------------------------------------------------------------------ auction house
    def set_listings(self, item_id, rows, commodity=None):
        """rows: [(unitPrice, quantity)] or dicts {unit, qty, owner, mine, ilvl, sfx, bidOnly}. Unit price is per item.
        sfx = random-suffix id: such rows form their own itemKey and only answer a search with that itemSuffix."""
        out = []
        for r in rows:
            if isinstance(r, dict):
                d = dict(r)
            else:
                d = {"unit": int(r[0]), "qty": int(r[1])}
                if len(r) > 2:
                    d["owner"] = r[2]
            self.M.AH.auctionSeq += 1
            d["auctionID"] = int(self.M.AH.auctionSeq)
            out.append(d)
        entry = {"rows": out}
        if commodity is not None:
            entry["commodity"] = commodity
        self.M.AH.listings[item_id] = self.table(entry)

    def clear_listings(self, item_id=None):
        if item_id is None:
            self.M.AH.listings = self.lua.table()
        else:
            self.M.AH.listings[item_id] = None

    def load_orderbooks(self, which=None):
        """Real order books from the user's WaylaidCrate SV (tests/fixtures/orderbooks.json)."""
        books = _json("orderbooks.json")["books"]
        for k, rows in books.items():
            if which is None or int(k) in which:
                self.set_listings(int(k), rows)
        return {int(k): v for k, v in books.items()}

    def open_ah(self):
        self.M.openAH()

    def close_ah(self):
        self.M.closeAH()

    def ah_stats(self):
        st = self.M.AH.stats
        conv = lambda t: {int(k): int(t[k]) for k in t.keys()}
        sent = self.M.AH.sent
        return {"searches": int(st.searches), "browses": int(st.browses), "requestMore": int(st.requestMore),
                "dropped": int(st.dropped), "blizzard": int(st.blizzard), "sentWhileNotReady": int(st.sentWhileNotReady),
                "commodityInfoCalls": conv(st.commodityInfoCalls), "itemInfoCalls": conv(st.itemInfoCalls),
                "searchByItem": conv(st.searchByItem), "numResultCalls": int(st.numResultCalls), "quantityCalls": int(st.quantityCalls),
                "sent": [dict(kind=sent[i].kind, id=sent[i].id, t=float(sent[i].t), source=sent[i].source) for i in range(1, len(sent) + 1)]}

    def ah_blizzard_search(self, item_id):
        """Blizzard's own AH UI searching an item (e.g. the user clicks a browse row)."""
        self.eval("local id = ...; __WOWMOCK.ahSearch(C_AuctionHouse.MakeItemKey(id), 'blizzard')", item_id)

    def ah_blizzard_favorites(self, item_ids):
        """Blizzard's Favorites button (QueryAll -> C_AuctionHouse.SearchForFavorites) listing these favorite items."""
        self.M.AH.favorites = self.table({int(i): True for i in item_ids})
        self.eval("__WOWMOCK.ahSource = 'blizzard'; C_AuctionHouse.SearchForFavorites({ { sortOrder = 1, reverseSort = false } }); __WOWMOCK.ahSource = nil")

    def ah_blizzard_browse(self, text=""):
        """Blizzard's AH search box (SearchBar:StartSearch -> SendBrowseQuery)."""
        self.eval("local t = ...; AuctionHouseFrame.SearchBar:SetSearchText(t); AuctionHouseFrame.SearchBar:StartSearch()", text)

    def ah_show_browse(self):
        return self.M.ahShowBrowse()

    def ah_show_commodity(self, item_id):
        return self.M.ahShowCommodity(item_id)

    def ah_show_item(self, item_id):
        return self.M.ahShowItem(item_id)

    def ah_rows(self, which="browse"):
        """Visible Blizzard AH list rows: list of (row frame, rowData)."""
        key = {"browse": "BrowseResultsFrame", "commodity": "CommoditiesBuyFrame", "item": "ItemBuyFrame"}[which]
        sb = self.eval("local k = ...; return AuctionHouseFrame[k].ItemList.ScrollBox", key)
        frames = sb._frames
        return [(frames[i], frames[i].rowData) for i in range(1, len(frames) + 1)]

    # ------------------------------------------------------------------ professions / merchant / bags / loot
    def open_profession(self, skill_line, ready_delay=0.2):
        self.eval("local s, d = ...; __WOWMOCK.openProfession(s, { readyDelay = d })", skill_line, ready_delay)

    def close_profession(self):
        self.M.closeProfession()

    def recipe_rows(self):
        """Visible ProfessionsFrame recipe rows: list of (row frame, recipeID or None for headers)."""
        sb = self.eval("return ProfessionsFrame.CraftingPage.RecipeList.ScrollBox")
        frames = sb._frames
        out = []
        for i in range(1, len(frames) + 1):
            fr = frames[i]
            d = fr._elementData.data
            out.append((fr, d.recipeInfo.recipeID if d.recipeInfo else None))
        return out

    def open_merchant(self, npc_id, name, items, zone="Orgrimmar", map_id=1454, x=0.5, y=0.5):
        """items: [{itemID, price (per purchase), stackCount, numAvailable=-1, isPurchasable=True, hasExtendedCost=False}]"""
        its = []
        for e in items:
            d = {"numAvailable": -1, "isPurchasable": True, "hasExtendedCost": False, "stackCount": 1}
            d.update(e)
            its.append(d)
        self.M.openMerchant(self.table({"npcID": npc_id, "name": name, "items": its, "zone": zone, "map": map_id, "x": x, "y": y}))

    def close_merchant(self):
        self.M.closeMerchant()

    def set_bags(self, contents):
        """contents: {(bag, slot): (itemID, count)}"""
        self.lua.execute("for b = 0, 4 do __WOWMOCK.BAGS[b] = {} end")
        for (bag, slot), (iid, cnt) in contents.items():
            self.M.BAGS[bag][slot] = self.table({"itemID": iid, "count": cnt})
            if iid in self.items:
                self.M.CACHED[iid] = True          # the client always knows the items in your bags
        self.M.bagChanged(0)

    def add_bag_item(self, item_id, count=1):
        self.M.addBagItem(item_id, count, False)

    def bag_count(self, item_id):
        return int(self.M.bagCount(item_id))

    def find_bag_slot(self, item_id):
        for bag in range(0, 5):
            b = self.M.BAGS[bag]
            for slot in list(b.keys()):
                if b[slot].itemID == item_id:
                    return bag, int(slot)
        return None

    def disenchant(self, bag, slot, loot, autoloot=False, order="normal", cast_time=3.0, interrupt=False, run=True):
        """Cast Disenchant on bag/slot; loot = [(itemID, qty)]. order: 'normal' or 'loot-first'."""
        self.M.disenchant(bag, slot, self.table([list(x) for x in loot]),
                          self.table({"autoloot": autoloot, "order": order, "castTime": cast_time, "interrupt": interrupt}))
        if run:
            self.advance(cast_time + 1.5)

    def loot_window(self, loot, source=None):
        self.M.lootWindow(self.table([list(x) for x in loot]), source)
        self.advance(1)

    def complete_quest(self, quest_id):
        self.M.questsDone[quest_id] = True

    # ------------------------------------------------------------------ UI driving
    def slash(self, text):
        """Run a slash command like the chat box does ("/wc scan")."""
        cmd, _, rest = text.strip().partition(" ")
        return self.eval("""local cmd, rest = ...
          cmd = cmd:lower()
          for key, fn in pairs(SlashCmdList) do
            local i = 1
            while true do
              local s = rawget(_G, "SLASH_" .. key .. i)
              if not s then break end
              if s:lower() == cmd then return __WOWMOCK.protected("slash " .. cmd, fn, rest, DEFAULT_CHAT_FRAME) end
              i = i + 1
            end
          end
          error("wowmock: no slash command " .. cmd)""", cmd, rest)

    def _root(self, root):
        if root is None:
            root = "WaylaidCrateFrame"
        if isinstance(root, str):
            return self.g(root)
        return root

    def regions(self, root=None, kind=None, visible_only=True):
        r = self._root(root)
        if r is None:
            return []
        out = []
        f = self.lua.eval("""function(root, kind, vis)
          local out = {}
          local function walk(w)
            for _, reg in ipairs(w._regions) do
              if (not kind or reg._kind == kind) and (not vis or __WOWMOCK.visible(reg)) then out[#out + 1] = reg end
            end
            for _, c in ipairs(w._children) do
              if (not kind or c._kind == kind) and (not vis or __WOWMOCK.visible(c)) then out[#out + 1] = c end
              if not vis or __WOWMOCK.visible(c) then walk(c) end
            end
          end
          if not vis or __WOWMOCK.visible(root) then walk(root) end
          return out
        end""")
        t = f(r, kind, visible_only)
        return [t[i] for i in range(1, len(t) + 1)]

    def _clipped(self, w):
        return bool(self.lua.eval("""function(w)
          local r = __WOWMOCK.rect(w)
          local p = w._parent
          while p and __WOWMOCK.isWidget(p) do
            if p._kind == "ScrollFrame" or p._clips then
              local pr = __WOWMOCK.rect(p)
              if pr[5] and (r[3] <= pr[4] + 0.5 or r[4] >= pr[3] - 0.5) then return true end
            end
            p = p._parent
          end
          return false
        end""")(w))

    def texts(self, root=None, strip=True, clip=False, with_regions=False):
        """Visible, non-empty FontString texts under root (default WaylaidCrateFrame), top-to-bottom, left-to-right."""
        out = []
        for fs in self.regions(root, "FontString"):
            t = fs._text
            if t is None or str(t) == "":
                continue
            if clip and self._clipped(fs):
                continue
            rect = self.M.rect(fs)
            out.append((-float(rect[3]), float(rect[1]), _strip(t) if strip else str(t), fs))
        out.sort(key=lambda e: (round(e[0]), e[1]))
        return [(e[2], e[3]) for e in out] if with_regions else [e[2] for e in out]

    def find_texts(self, pattern, root=None, clip=False):
        rx = re.compile(pattern)
        return [t for t in self.texts(root, clip=clip) if rx.search(t)]

    def buttons(self, root=None):
        return [w for w in self.regions(root) if w._kind in ("Button", "CheckButton", "DropdownButton")]

    def click_text(self, text, root=None, exact=False, button="LeftButton"):
        """Click the visible button whose label is `text`, or the topmost visible button covering a FontString with
        that text (hotspots over list cells). Returns the clicked widget."""
        def match(t):
            if t is None:
                return False
            s = _strip(t)
            return s == text if exact else (s == text or text in s)
        btns = [w for w in self.regions(root) if w._kind in ("Button", "CheckButton", "DropdownButton")]
        for b in btns:
            label = b.GetText(b)
            if match(label) and b._enabled:
                b.Click(b, button)
                return b
        for t, fs in self.texts(root, strip=False, with_regions=True):
            if not match(t):
                continue
            fr = self.M.rect(fs)
            cx, cy = (fr[1] + fr[2]) / 2.0, (fr[3] + fr[4]) / 2.0
            best = None
            for b in btns:
                r = self.M.rect(b)
                if r[5] and r[1] <= cx <= r[2] and r[4] <= cy <= r[3] and b._enabled:
                    if best is None or int(b._level) >= int(best._level):
                        best = b
            if best is None:
                p = fs._parent
                while p is not None and self.lua.eval("function(p) return __WOWMOCK.isWidget(p) end")(p):
                    if p._kind in ("Button", "CheckButton") and p._enabled:
                        best = p
                        break
                    p = p._parent
            if best is not None:
                best.Click(best, button)
                return best
        raise LookupError("wowmock.click_text: no visible clickable '%s'" % text)

    def hover(self, widget):
        """OnEnter on a widget; returns the GameTooltip lines (stripped)."""
        self.M.mouseFocus = widget
        self.eval("GameTooltip._lines = {}")
        self.lua.eval("function(w) local f = w._scripts.OnEnter; if f then __WOWMOCK.protected('OnEnter', f, w) end end")(widget)
        return self.tooltip_lines()

    def hover_text(self, text, root=None):
        for t, fs in self.texts(root, strip=False, with_regions=True):
            if _strip(t) == text or text in _strip(t):
                fr = self.M.rect(fs)
                cx, cy = (fr[1] + fr[2]) / 2.0, (fr[3] + fr[4]) / 2.0
                cands = [w for w in self.regions(root) if w._kind != "FontString" and w._kind != "Texture" and w._scripts.OnEnter is not None]
                best = None
                for b in cands:
                    r = self.M.rect(b)
                    if r[5] and r[1] <= cx <= r[2] and r[4] <= cy <= r[3]:
                        if best is None or int(b._level) >= int(best._level):
                            best = b
                if best is not None:
                    return self.hover(best)
        raise LookupError("wowmock.hover_text: nothing with OnEnter under '%s'" % text)

    def tooltip_lines(self, strip=True):
        lines = self.eval("return GameTooltip._lines")
        out = []
        if lines is None:
            return out
        for i in range(1, len(lines) + 1):
            l = lines[i]
            parts = [l[j] for j in range(1, len(l) + 1)]
            s = " | ".join(parts)
            out.append(_strip(s) if strip else s)
        return out

    def type_into(self, editbox, text):
        """User typing into an EditBox (OnTextChanged with userInput = true)."""
        self.lua.eval("""function(eb, t)
          eb._text = t
          local f = eb._scripts.OnTextChanged; if f then __WOWMOCK.protected('OnTextChanged', f, eb, true) end
        end""")(editbox, text)

    def scroll(self, widget, delta):
        self.lua.eval("function(w, d) local f = w._scripts.OnMouseWheel; if f then __WOWMOCK.protected('OnMouseWheel', f, w, d) end end")(widget, delta)

    # ------------------------------------------------------------------ inspection
    def count_regions(self, root=None):
        """Number of widgets created, by kind (root=None: everything the addon created; else the subtree)."""
        if root is None:
            c = self.M.created
            return {k: int(c[k]) for k in c.keys()}
        out = {}
        for w in self.regions(root, None, visible_only=False):
            out[w._kind] = out.get(w._kind, 0) + 1
        return out

    def addon_widget_count(self, kind=None):
        """Widgets created by addon code (optionally of one kind)."""
        return int(self.eval("""local kind = ...
          local n = 0
          for _, w in ipairs(__WOWMOCK.widgets) do if w._where and (not kind or w._kind == kind) then n = n + 1 end end
          return n""", kind))

    def running_timers(self, include_internal=False):
        """Pending C_Timer timers/tickers (addon ones by default): list of (label, seconds left, where)."""
        t = self.M.timers
        out = []
        for i in range(1, len(t) + 1):
            e = t[i]
            if e.cancelled:
                continue
            if e.internal and not include_internal:
                continue
            out.append((e.label, float(e.at) - self.now(), e.where))
        return out

    def onupdate_frames(self):
        """Visible frames with an OnUpdate script (they cost CPU every frame): list of where-created strings."""
        res = self.eval("""local out = {}
          for f, w in pairs(__WOWMOCK.updaters) do if f._scripts.OnUpdate and f:IsVisible() then out[#out + 1] = (type(w) == 'string' and w or '?') .. ' (' .. (f._name or f._kind) .. ')' end end
          return out""")
        return [res[i] for i in range(1, len(res) + 1)]

    def playing_animations(self):
        res = self.eval("""local out = {}
          for g, w in pairs(__WOWMOCK.anims) do if g._playing then out[#out + 1] = type(w) == 'string' and w or '?' end end
          return out""")
        return [res[i] for i in range(1, len(res) + 1)]

    def idle_report(self):
        return {"timers": self.running_timers(), "onupdate": self.onupdate_frames(), "animations": self.playing_animations()}

    def memory_kb(self, collect=True):
        if collect:
            self.lua.execute("collectgarbage('collect'); collectgarbage('collect')")
        return float(self.lua.eval("collectgarbage('count')"))

    @property
    def errors(self):
        e = self.M.errors
        return [{"context": e[i].context, "msg": e[i].msg, "tb": e[i].tb} for i in range(1, len(e) + 1)]

    @property
    def violations(self):
        v = self.M.violations
        return [{"kind": v[i].kind, "name": v[i].name, "where": v[i].where, "n": int(v[i].n)} for i in range(1, len(v) + 1)]

    @property
    def gaps(self):
        g = self.M.gaps
        return [{"name": g[i].name, "n": int(g[i].n), "where": g[i].where} for i in range(1, len(g) + 1)]

    @property
    def chat(self):
        c = self.M.chat
        return [_strip(c[i].msg) for i in range(1, len(c) + 1)]

    @property
    def sounds(self):
        s = self.M.sounds
        return [s[i].id for i in range(1, len(s) + 1)]

    def new_globals(self):
        ng = self.M.newGlobals
        return {k: ng[k] for k in ng.keys()}

    def named_frames(self):
        nf = self.M.namedFrames
        return {k: nf[k] for k in nf.keys()}

    def unexpected_globals(self):
        """Globals written by addon code (or named frames/fonts) outside the SPEC's allowed set."""
        allowed = re.compile(r"^(WaylaidCrateDB|WaylaidCrate\w*|SLASH_WAYLAIDCRATE\d+)$")
        bad = {}
        for k, w in self.new_globals().items():
            if not allowed.match(str(k)):
                bad[k] = w
        for k, w in self.named_frames().items():
            if w not in ("(mock)",) and not str(k).startswith("WaylaidCrate"):
                bad[k] = w
        return bad

    def problems(self, allow_violations=(), allow_errors=()):
        """Everything that should fail a test: Lua errors, strict violations, unexpected globals."""
        out = []
        for e in self.errors:
            if not any(a in e["msg"] for a in allow_errors):
                out.append("LUA ERROR (%s): %s" % (e["context"], e["msg"]))
        for v in self.violations:
            if not any(a in v["name"] for a in allow_violations):
                out.append("STRICT %s %s @ %s (x%d)" % (v["kind"], v["name"], v["where"], v["n"]))
        for k, w in self.unexpected_globals().items():
            out.append("GLOBAL %s created @ %s" % (k, w))
        return out

    def report(self):
        lines = []
        if self.toc:
            lines.append("files loaded: %d, missing: %s" % (len(self.loaded_files), ", ".join(self.missing_files) or "-"))
        for p in self.problems():
            lines.append("  " + p)
        for g in self.gaps:
            lines.append("  mock gap: %s (x%d) @ %s" % (g["name"], g["n"], g["where"]))
        return "\n".join(lines)


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Load WaylaidCrate in the mock client and print a short report")
    ap.add_argument("--locale", default="enUS")
    ap.add_argument("--sv", default=None)
    args = ap.parse_args()
    c = WowClient(locale=args.locale)
    if args.sv:
        c.load_sv(args.sv)
    c.load_addon("WaylaidCrate/WaylaidCrate.toc")
    c.login()
    c.load_orderbooks()
    c.open_ah()
    c.advance(120)
    print("\n".join(c.texts()[:40]))
    print(c.report())
