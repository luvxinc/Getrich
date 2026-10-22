#!/usr/bin/env python3
"""Scenario tests for Getrich (formerly Waylaid Crate; 2026.10.2 merge + 2026.10.3 round 2), run against tests/wowmock.py.

usage: python3 tests/test_merge.py [--locale enUS|zhCN|zhTW] [-k substring] [-v] [--list]
Each scenario starts a fresh mock client, prints PASS / FAIL / ERROR with the reason, and every scenario also fails on
Lua errors, strict-API violations (calls to APIs that do not exist on WoW Forever 1.60.1) and unexpected globals.
Expected numbers are computed by hand from tests/fixtures (the arithmetic is in the comments next to each check).
"""
import argparse, json, math, os, re, sys, time, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from wowmock import WowClient, DEFAULT_CHAR, SECOND_CHAR, SERVER_TIME0, _strip, _json  # noqa: E402

REAL_SV = os.path.join(HERE, "fixtures", "sv_waylaidcrate_130.lua")   # the user's real 1.3.0 SavedVariables
ADDON_TOC = os.environ.get("WC_ADDON_TOC", "Getrich/Getrich.toc")   # --addon DIR overrides (mutation tests)
UNCACHED = False     # --uncached: start every client with an empty item cache (fresh login)
FIX = os.path.join(HERE, "fixtures")


# ===================================================================================================================
# tiny test framework
# ===================================================================================================================
class Fail(Exception):
    pass


class Ctx:
    """Per-scenario context: collects soft failures so one run reports everything that is wrong."""

    def __init__(self, name, locale, verbose):
        self.name, self.locale, self.verbose = name, locale, verbose
        self.failures, self.notes, self.clients = [], [], []

    def check(self, cond, msg):
        if not cond:
            self.failures.append(msg)
        return bool(cond)

    def eq(self, actual, expected, what, tol=1e-6):
        ok = False
        if isinstance(expected, float) or isinstance(actual, float):
            ok = actual is not None and expected is not None and abs(float(actual) - float(expected)) <= tol
        else:
            ok = actual == expected
        if not ok:
            self.failures.append("%s: expected %r, got %r" % (what, expected, actual))
        return ok

    def require(self, cond, msg):
        if not cond:
            raise Fail(msg)

    def money(self, copper):
        return copper_text(copper, self.locale)

    def note(self, msg):
        self.notes.append(msg)

    def log(self, *a):
        if self.verbose:
            print("      ", *a)

    def client(self, locale=None, char=DEFAULT_CHAR, sv=None, login=True, cached=True, **kw):
        if UNCACHED:
            cached = False
        c = WowClient(locale=locale or self.locale, char=char, cached=cached, **kw)
        if sv:
            c.load_sv(sv)
        c.load_addon(ADDON_TOC)
        if login:
            c.login()
        self.clients.append(c)
        return c


SCENARIOS = []


def scenario(name, doc=""):
    def deco(fn):
        SCENARIOS.append((name, fn, doc or (fn.__doc__ or "").strip().split("\n")[0]))
        return fn
    return deco


def lua_list(t):
    if t is None:
        return []
    return [t[i] for i in range(1, len(t) + 1)]


def lua_keys(t):
    return [] if t is None else list(t.keys())


def multi(v, n=2):
    """Normalize a Lua call result (lupa returns a tuple for several values) to a tuple of length n."""
    if isinstance(v, tuple):
        return tuple(v[:n]) + (None,) * (n - len(v))
    return (v,) + (None,) * (n - 1)


def first(v):
    return v[0] if isinstance(v, tuple) else v


def fnum(v):
    return None if v is None else float(v)


def copper_text(copper, locale="enUS"):
    """What WC.Money prints, without color codes ('1g 2s 3c'; zh uses 金/银/铜 per Locale.lua)."""
    neg = copper < 0
    c = int(math.floor(abs(copper) + 0.5))
    g, s, cp = c // 10000, (c % 10000) // 100, c % 100
    sym = {"enUS": ("g", "s", "c"), "zhCN": ("金", "银", "铜"), "zhTW": ("金", "銀", "銅")}[locale]
    parts = []
    if g:
        parts.append("%d%s" % (g, sym[0]))
    if s:
        parts.append("%d%s" % (s, sym[1]))
    if cp or not parts:
        parts.append("%d%s" % (cp, sym[2]))
    return ("-" if neg else "") + " ".join(parts)


def start_scan(c, kind, timeout=900):
    """Start a scan kind and run the clock until the scanner finished. Returns the seconds it took."""
    WC = c.WC
    t0 = c.now()
    ok = WC.Scanner.Start(WC.Scanner, kind)
    c.advance(timeout, until=lambda: not WC.Scanner.active)
    return ok, c.now() - t0


def visible_tab_texts(c):
    return c.texts(clip=True)


# ===================================================================================================================
# 1.3.0 market (port of tests/mock_test.py, same deterministic order books)
# ===================================================================================================================
MARKET_130 = r'''
local WC, M = ...
local function setL(id, rows, commodity)
  local t = {}
  for _, r in ipairs(rows) do M.AH.auctionSeq = M.AH.auctionSeq + 1; t[#t + 1] = { unit = r[1], qty = r[2], auctionID = M.AH.auctionSeq } end
  M.AH.listings[id] = { rows = t, commodity = commodity }
end
local seed = 7
local function rnd(a, b) seed = (seed * 1103515245 + 12345) % 2147483648; return a + seed % (b - a + 1) end
local BOOK, ITEM_PATH = {}, {}
for _, c in ipairs(WC.CRATES) do
  ITEM_PATH[c.id] = true
  BOOK[c.id] = { { rnd(5000, 30000), 1 }, { 40000, 1 } }
  for _, o in ipairs(c.opts) do BOOK[o[1]] = { { rnd(50, 500), 200 }, { rnd(600, 900), 500 } } end
end
for _, w in ipairs(WC.WRITS) do ITEM_PATH[w.writ] = true; BOOK[w.writ] = {} end
BOOK[2589] = { { 10, 30 } }                       -- Linen: only 30 (needs 40)
BOOK[2318] = { { 400, 10 }, { 900, 50 } }         -- 20 Light Leather = 13000
BOOK[248683] = {}                                 -- Apprentice Ore crate not for sale
for _, id in ipairs({ 2447, 765, 2449, 785, 2450 }) do BOOK[id] = {} end   -- herbs sold out
BOOK[248710] = { { 100, 1 } }                     -- Expert Parts crate: 1c
BOOK[10559] = { { 1, 100 } }                      -- Mithril Tube
M.AH.noAnswer[2771] = true                        -- Tin Ore never answers
M.AH.notLoadedOnce[4306] = true                   -- Silk Cloth answers 'not loaded' first
WRITS_LISTED = {
  [264072] = { writ = 5000,  item = 20000 },
  [264082] = { writ = 3000,  item = 9000 },
  [264037] = { writ = 2000,  item = 5 },
  [264013] = { writ = 1500,  item = 300 },
  [264124] = { writ = 9000,  item = 40000 },
  [264047] = { writ = 1000,  item = nil },
  [264085] = { writ = 4000,  item = 2500 },
  [264153] = { writ = 20000, item = 30000 },
}
for _, w in ipairs(WC.WRITS) do
  local s = WRITS_LISTED[w.writ]
  if s then
    BOOK[w.writ] = { { s.writ, 1 }, { s.writ * 2, 1 } }
    if s.item then BOOK[w.item] = { { s.item, 150 }, { s.item * 3, 300 } } else BOOK[w.item] = {} end
  elseif w.item ~= 10560 then
    BOOK[w.item] = { { 777, 5 } }
  end
end
M.questsDone[94213] = true                        -- Lesser Mana Potion writ done today
for id, rows in pairs(BOOK) do setL(id, rows, not ITEM_PATH[id]) end
'''

EVAL_DUMP = r'''
local WC = ...
local out = { crates = {}, writs = {} }
for _, e in ipairs(WC:EvaluateCrates()) do
  local best = e.bestIdx and e.opts[e.bestIdx]
  out.crates[#out.crates + 1] = { id = e.crate.id, crateCost = e.crateCost, crateStatus = e.crateStatus, matCost = e.matCost,
    best = best and best.itemID or false, net = e.net, perFavor = e.perFavor, status = e.status, locked = e.locked }
end
for _, e in ipairs(WC:EvaluateWrits()) do
  out.writs[#out.writs + 1] = { id = e.receipt and 0 or e.writ.writ, writCost = e.writCost, itemCost = e.itemCost, cost = e.cost,
    repGain = e.repGain, perRep = e.perRep, status = e.status, done = e.done or false, receipt = e.receipt or false }
end
return out
'''


def setup_market_130(c):
    c.clear_listings()
    c.eval(MARKET_130, c.WC, c.M)


def eval_dump(c):
    t = c.eval(EVAL_DUMP, c.WC)

    def norm(row):
        d = {}
        for k in row.keys():
            v = row[k]
            d[k] = round(v, 6) if isinstance(v, float) else v
        return d
    return {"crates": [norm(x) for x in lua_list(t.crates)], "writs": [norm(x) for x in lua_list(t.writs)]}


def run_market_130(c, ctx=None):
    """The 1.3.0 test session: crates scan on AH open, writs scan, writs scan with the filter off.
    Returns the evaluation dumps after each step."""
    WC = c.WC
    setup_market_130(c)
    c.open_ah()
    c.advance(400, until=lambda: WC.Scanner.kind == "crates" and not WC.Scanner.active and c.now() > 1002)
    c.advance(1)
    out = {"after_crates": eval_dump(c)}
    WC.UI.SelectTab(WC.UI, "writs")
    start_scan(c, "writs", 900)
    out["after_writs"] = eval_dump(c)
    c.g("GetrichDB").hideNoWrit = False
    start_scan(c, "writs", 1500)
    out["after_writs_all"] = eval_dump(c)
    return out


# ===================================================================================================================
# scenarios
# ===================================================================================================================
TABS = ["crates", "writs", "flips", "craft", "de", "history"]

# Simplified-only / traditional-only characters common in this addon's wording (heuristic script check).
SIMPLIFIED_ONLY = set("价钱扫卖买时间设显隐数项关开进结记录历势图单总计润这们个为东变认让说选择标题货币银铜级满处确输误栏统钟导启额实际专业应宽对齐无产资务场库种类测试发现获损坏状态动杂节点头层页签号码张条线网络电话质别长门钥锁鉴识难颜绿红蓝黄筛汇储仅当预览帮载报错购补赚亏职涨来观样换铁锡矿药剂炉锤")
TRADITIONAL_ONLY = set("價錢掃賣買時間設顯隱數項關開進結記錄歷勢圖單總計潤這們個為東變認讓說選擇標題貨幣銀銅級滿處確輸誤欄統鐘導啟額實際專業應寬對齊無產資務場庫種類測試發現獲損壞狀態動雜節點頭層頁簽號碼張條線網絡電話質別長門鑰鎖鑑識難顏綠紅藍黃篩匯儲僅當預覽幫載報錯購補賺虧職漲來觀樣換鐵錫礦藥劑爐錘")


def locale_strings(c):
    """All string values of WC.L (nested tables flattened) -> {key: text}"""
    out = {}

    def walk(prefix, t):
        for k in t.keys():
            v = t[k]
            key = "%s%s" % (prefix, k)
            if isinstance(v, str):
                out[key] = v
            elif v is not None and hasattr(v, "keys"):
                walk(key + ".", v)
    walk("", c.WC.L)
    return out


def check_clean(ctx, c, what=""):
    for p in c.problems():
        ctx.failures.append((what + ": " if what else "") + p)


# ------------------------------------------------------------------------------------------------------------------
@scenario("load_all_locales", "all TOC files load in order in enUS / zhCN / zhTW; every tab opens; zh strings in the right script")
def s_load(ctx):
    base = None
    for loc in ("enUS", "zhCN", "zhTW"):
        c = ctx.client(locale=loc)
        ctx.check(not c.missing_files, "%s: files listed in the TOC but missing: %s" % (loc, c.missing_files))
        ctx.eq(len(c.loaded_files), len(c.toc["files"]), "%s: files loaded" % loc)
        L = locale_strings(c)
        if loc == "enUS":
            base = L
        else:
            same = [k for k, v in L.items() if base.get(k) == v and re.search(r"[A-Za-z]{4,}", v) and not re.search(r"Writ|Favor|Crate|AH|%s|%d", v)]
            ctx.check(len(same) <= max(5, len(L) // 12), "%s: %d strings identical to English (untranslated?): %s" % (loc, len(same), same[:12]))
            bad = SIMPLIFIED_ONLY if loc == "zhTW" else TRADITIONAL_ONLY
            wrong = sorted((k, "".join(sorted(set(v) & bad))) for k, v in L.items() if set(v) & bad)
            ctx.check(not wrong, "%s: %d strings use characters of the other Chinese script, e.g. %s" % (loc, len(wrong), wrong[:8]))
        c.slash("/wc")
        frame = c.g("GetrichFrame")
        ctx.require(frame is not None, "%s: no GetrichFrame after /wc" % loc)
        ctx.check(frame.IsVisible(frame), "%s: /wc did not show the window" % loc)
        if loc == "enUS":
            t = c.texts()
            ver, rel = c.toc["meta"].get("Version"), c.toc["meta"].get("X-Released")
            ctx.check(ver and rel and any(ver in x and rel in x for x in t),
                      "title should show 'v%s · %s' (TOC Version + X-Released); texts: %s" % (ver, rel, t[:6]))
        ctx.eq(frame.GetWidth(frame), 700, "%s: window width" % loc)
        ctx.eq(frame.GetHeight(frame), 700, "%s: window height" % loc)
        for tab in TABS:
            c.slash("/wc " + tab)
            ctx.eq(c.g("GetrichDB").tab, tab, "%s: /wc %s -> db.tab" % (loc, tab))
            ctx.check(frame.IsVisible(frame), "%s: window hidden after /wc %s" % (loc, tab))
            n = len(c.texts(clip=True))
            ctx.check(n >= 8, "%s: tab %s shows only %d texts" % (loc, tab, n))
        check_clean(ctx, c, loc)


# ------------------------------------------------------------------------------------------------------------------
@scenario("crates_writs_130", "1.3.0 crates/writs session: evaluations identical to v1.3.0 (eval_130.json) + 1.3.0 UI checks")
def s_130(ctx):
    c = ctx.client(locale="enUS")
    got = run_market_130(c, ctx)
    ref = json.load(open(os.path.join(FIX, "eval_130.json")))
    for step in ("after_crates", "after_writs", "after_writs_all"):
        for part in ("crates", "writs"):
            a, b = got[step][part], ref[step][part]
            ctx.eq(len(a), len(b), "%s %s count" % (step, part))
            for x, y in zip(a, b):
                if x != y:
                    diff = {k: (x.get(k), y.get(k)) for k in set(x) | set(y) if x.get(k) != y.get(k)}
                    ctx.failures.append("%s %s id %s differs from 1.3.0 (new, 1.3.0): %s" % (step, part, y.get("id"), diff))
                    break
    WC = c.WC
    # 1.3.0 checks (tests/mock_test.py): filters, rank order, bonuses
    db = c.g("GetrichDB")
    ctx.eq(db.resultsFormat, 3, "resultsFormat after scans")
    ctx.check(db.scannedAt.crates and db.scannedAt.writs, "scannedAt.crates / .writs set")
    vis = lua_list(c.eval("local WC = ...; return WC:VisibleCrates(WC:EvaluateCrates())", WC))
    names = [v.crate.en for v in vis]
    ctx.check("Apprentice Ore" not in names and "Apprentice Herbs" not in names, "default crate filters hide Ore/Herbs: %s" % names)
    vw = lua_list(c.eval("local WC = ...; return WC:VisibleWrits(WC:EvaluateWrits())", WC))
    scores = [v.perRep for v in vw]
    ctx.check(None not in scores[:scores.index(None)] if None in scores else True, "unscored writs must come after scored ones")
    scored = [x for x in scores if x is not None]
    ctx.check(scored == sorted(scored), "writs ranked by cost per reputation")
    db.diplomatRank = 5
    e75 = [e for e in lua_list(c.eval("local WC = ...; return WC:EvaluateWrits()", WC)) if not e.receipt and e.writ.writ == 264013][0]
    ctx.eq(fnum(e75.repGain), 82.5, "Legacy Diplomat 5/5: 75 rep -> 75 x 1.10")
    db.diplomatRank = 0
    # click search: crate name -> "Waylaid Crate: Expert Parts"; recommended material -> "Mithril Tube"
    c.slash("/wc crates")
    c.click_text("Expert Parts")
    ctx.eq(c.eval("return AuctionHouseFrame.SearchBar.SearchBox:GetText()"), "Waylaid Crate: Expert Parts", "click crate name -> AH search box")
    c.click_text("Mithril Tube")
    ctx.eq(c.eval("return AuctionHouseFrame.SearchBar.SearchBox:GetText()"), "Mithril Tube", "click material -> AH search box")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("scanner_rows_vs_quantity", "1.3.0 bug: result loops must walk rows (GetNum*SearchResults), not units; paging keeps unit totals")
def s_rows(ctx):
    c = ctx.client()
    WC = c.WC
    # 3 rows holding 9000 units: the old loop asked GetCommoditySearchResultInfo 9000 times
    c.set_listings(2589, [(10, 3000), (11, 3000), (12, 3000)])
    c.set_listings(1273, [(5000, 1), (6000, 1)])                    # gear: item search, 2 rows of 1
    c.M.AH.resultPageSize = 2
    c.set_listings(2770, [(5, 1), (6, 1), (7, 100), (8, 100)])       # 4 rows, first page = 2 rows (2 units)
    for i in (2589, 1273, 2770):
        WC.Store.SetWatch(WC.Store, i, True)
    c.g("GetrichDB").autoScan = False
    c.open_ah()
    c.advance(1)
    ok, secs = start_scan(c, "history", 120)
    ctx.require(ok, "Scanner:Start('history') refused")
    st = c.ah_stats()
    calls = st["commodityInfoCalls"].get(2589, 0)
    searches = st["searchByItem"].get(2589, 1)
    ctx.check(calls <= 3 * searches + 2, "GetCommoditySearchResultInfo(2589) called %d times for 3 rows (%d searches) - loop over units?" % (calls, searches))
    ctx.check(st["itemInfoCalls"].get(1273, 0) <= 2 * st["searchByItem"].get(1273, 1) + 2, "GetItemSearchResultInfo(1273) called %d times for 2 rows" % st["itemInfoCalls"].get(1273, 0))
    res = c.g("GetrichDB").results
    r = res[2589]
    ctx.require(r is not None and r.status == "listed", "2589 not recorded as listed: %s" % (r and r.status))
    # KEEP_QTY 250: the first row (3000 units) already covers it -> one kept entry; avail = 3 x 3000 = 9000
    ctx.eq([[int(e[1]), int(e[2])] for e in lua_list(r.entries)], [[10, 3000]], "2589 kept entries")
    ctx.eq(int(r.avail), 9000, "2589 avail (sum of units)")
    ctx.eq(int(r.min), 10, "2589 min")
    r = res[1273]
    ctx.eq([[int(e[1]), int(e[2])] for e in lua_list(r.entries)] if r else None, [[5000, 1], [6000, 1]], "1273 entries (item search, buyout per unit)")
    r = res[2770]
    ctx.require(r is not None and r.status == "listed", "2770 (paged) not listed")
    ent = [[int(e[1]), int(e[2])] for e in lua_list(r.entries)]
    ctx.eq(ent[:2], [[5, 1], [6, 1]], "2770 first page rows")
    # either only the first page (avail from GetCommoditySearchResultsQuantity = 1+1+100+100) or all pages
    ctx.eq(int(r.avail), 202, "2770 avail = units listed (202), even if only page 1 was read")
    ctx.eq(WC.CostFor(WC, 2770, 2)[0], 11, "CostFor(2770, 2) = 5 + 6")
    info_calls = st["commodityInfoCalls"].get(2770, 0)
    ctx.check(info_calls <= 4 * st["searchByItem"].get(2770, 1) + 2, "GetCommoditySearchResultInfo(2770) called %d times" % info_calls)
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("scan_survives_noise", "Getrich regression: ITEM_DATA_LOAD_RESULT / bag updates / Blizzard's own AH queries / dropped messages never cancel or corrupt a scan")
def s_noise(ctx):
    c = ctx.client(cached=False)
    WC = c.WC
    books = c.load_orderbooks()
    crate_items = set()
    for cr in lua_list(WC.CRATES):
        crate_items.add(int(cr.id))
        for o in lua_list(cr.opts):
            crate_items.add(int(o[1]))
    c.set_listings(2835, [(3, 40)])            # not a crate item: Blizzard's UI will search it
    c.set_listings(1273, [(1000, 1)])
    c.g("GetrichDB").autoScan = False
    c.open_ah()
    c.advance(1)
    chat0 = len(c.chat)
    ok = WC.Scanner.Start(WC.Scanner, "crates")
    ctx.require(ok, "Scanner:Start('crates') refused")
    step, noise = 0, 0
    while WC.Scanner.active and step < 2000:
        step += 1
        c.advance(0.3)
        k = step % 9
        if k == 0:
            c.fire("ITEM_DATA_LOAD_RESULT", 2589 + step % 50, True)
        elif k == 1:
            c.fire("BAG_UPDATE", 0); c.fire("BAG_UPDATE_DELAYED")
        elif k == 2:
            c.fire("GET_ITEM_INFO_RECEIVED", 10940, True)
        elif k == 3 and step % 27 == 3:
            c.ah_blizzard_search(2835)              # COMMODITY_SEARCH_RESULTS_UPDATED(2835) while we wait for something else
        elif k == 4 and step % 36 == 4:
            c.ah_blizzard_search(1273)              # ITEM_SEARCH_RESULTS_UPDATED for another item
        elif k == 5 and step % 45 == 5:
            c.ah_blizzard_browse("Linen")           # Blizzard's search box (browse query)
        elif k == 6 and step % 54 == 6:
            c.M.AH.dropNext = 1                     # the server drops the next throttled message
        elif k == 7:
            c.fire("PLAYER_MONEY"); c.fire("UNIT_INVENTORY_CHANGED", "player")
        elif k == 8 and step > 30:
            # unsolicited updates of result sets the client still holds (Blizzard's lists refreshing) while we wait
            c.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2835)
            c.fire("ITEM_SEARCH_RESULTS_UPDATED", c.eval("return C_AuctionHouse.MakeItemKey(1273)"), None)
        noise += 1
    ctx.check(not WC.Scanner.active, "crates scan still running after %d s of noise" % int(step * 0.3))
    ctx.check(len(c.chat) > chat0, "no chat line when the scan finished: %s" % c.chat[-3:])
    res = c.g("GetrichDB").results
    missing, wrong = [], []
    for iid in sorted(crate_items):
        r = res[iid]
        if r is None:
            missing.append(iid)
            continue
        rows = books.get(iid)
        if rows and r.status == "listed":
            if int(r.min) != min(u for u, q in rows):
                wrong.append((iid, int(r.min), min(u for u, q in rows)))
        elif rows and r.status != "listed":
            wrong.append((iid, r.status, "listed"))
    ctx.check(not missing, "crate items without a result after the scan: %s" % missing)
    ctx.check(not wrong, "results that do not match the item's own listings (polluted by another search?): %s" % wrong[:8])
    st = c.ah_stats()
    ctx.check(st["blizzard"] >= 3, "test did not inject Blizzard queries (%d)" % st["blizzard"])
    own = sum(n for iid, n in st["searchByItem"].items() if iid in crate_items)
    # one search per item; Tin Ore (2771) is in the real books but answers fine here; dropped messages cost a retry each
    ctx.log("searches for crate items: %d for %d items, %d dropped" % (own, len(crate_items), st["dropped"]))
    ctx.check(own <= len(crate_items) + st["dropped"] + 3,
              "%d searches for %d crate items (%d dropped): results for other items made the scanner retry?" % (own, len(crate_items), st["dropped"]))
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
FLIP_LISTINGS = {
    # itemID: rows (unit, qty)                     sell price (items.json)
    4306: [(100, 5), (140, 10), (160, 200)],       # Silk Cloth, sell 150
    1273: [(1000, 1)],                             # Forest Chain (gear), sell 1656
    4338: [(200, 3), (300, 50)],                   # Mageweave Cloth, sell 250 (cheap row bought before our search)
    2592: [(40, 20)],                              # Wool Cloth, sell 33 -> not below vendor
    2589: [(12, 1), (13, 100)],                    # Linen Cloth, sell 13
    248684: [(5000, 1)],                           # Waylaid Crate, sell 0 -> vendors don't buy
    2319: [(49, 2)],                               # Medium Leather, sell 50
    2770: [(30, 20)], 2771: [(60, 20)], 2318: [(30, 10)], 2840: [(50, 4)], 2996: [(90, 5)],   # fillers above vendor price
}


PRICE_FIRES = {}


def count_price_fires(c):
    # a Lua listener (a Python callback inside addon code would trip the 'debug' check through lupa internals)
    c.eval("local WC, M = ...; M.priceFires = {}; WC:On('PRICES_UPDATED', function() M.priceFires[#M.priceFires + 1] = GetTime() end)", c.WC, c.M)
    PRICE_FIRES[id(c)] = c


def flip_market(c):
    c.clear_listings()
    for iid, rows in FLIP_LISTINGS.items():
        c.set_listings(iid, rows)
    c.M.AH.browsePageSize = 4          # 12 browse rows -> 3 pages


def flip_dump(c):
    lst = lua_list(first(c.WC.Profit.Flips(c.WC.Profit)))
    return [(int(e.itemID), e.status, None if e.qty is None else int(e.qty), fnum(e.profit), fnum(e.cost), fnum(e.unit), fnum(e.perUnit)) for e in lst]


@scenario("flips_scan", "flips: browse 3 pages -> candidates -> targeted searches -> exact profit, 'gone' when the cheap listing vanished")
def s_flips(ctx):
    c = ctx.client()
    WC = c.WC
    flip_market(c)
    count_price_fires(c)
    c.g("GetrichDB").autoScan = False
    c.open_ah()
    c.advance(1)
    ok = WC.Scanner.Start(WC.Scanner, "flips")
    ctx.require(ok, "Scanner:Start('flips') refused")
    # run until the first targeted search went out, then the cheap Mageweave row is bought by someone
    c.advance(120, until=lambda: c.ah_stats()["searches"] >= 1 or not WC.Scanner.active)
    c.set_listings(4338, [(300, 50)])
    c.advance(300, until=lambda: not WC.Scanner.active)
    ctx.require(not WC.Scanner.active, "flips scan did not finish")
    st = c.ah_stats()
    ctx.eq(st["browses"], 1, "browse queries sent")
    db = c.g("GetrichDB")
    items = db.browse["items"]
    got = {int(k): (int(items[k].min), int(items[k].qty)) for k in lua_keys(items)}
    # browse rows = cheapest unit + total units per itemKey: Silk 100/215, Mageweave 200/53, Linen 12/101 ...
    exp = {iid: (min(u for u, q in rows), sum(q for u, q in rows)) for iid, rows in FLIP_LISTINGS.items()}
    ctx.eq(got, exp, "db.browse.items after 3 pages (min, qty)")
    ctx.eq(int(items[1273].ilvl or 0), 25, "browse ilvl for gear (Forest Chain itemKey.itemLevel)")
    ctx.check(db.browse.full, "db.browse.full timestamp not set")
    # candidates: (sell - min) x min(qty, 20):
    #   Silk (150-100) x 20 = 1000; Mageweave (250-200) x 20 = 1000 (tie -> lower itemID first); Forest Chain 656 x 1 = 656;
    #   Linen (13-12) x 20 = 20; Medium Leather (50-49) x 2 = 2; Wool 40 >= 33 and the crate (sell 0) are not candidates
    cand = [int(x) for x in lua_list(WC.Profit.FlipCandidates(WC.Profit, 80))]
    ctx.eq(cand, [4306, 4338, 1273, 2589, 2319], "FlipCandidates(80)")
    searched = set(st["searchByItem"].keys())
    ctx.eq(searched, {4306, 4338, 1273, 2589, 2319}, "items searched in phase 2")
    # Flips (order book after the browse):
    #   Forest Chain: 1 x (1656-1000) = 656, cost 1000
    #   Silk: 5 x (150-100) + 10 x (150-140) = 250 + 100 = 350, qty 15, cost 5x100 + 10x140 = 1900
    #   Medium Leather: 2 x (50-49) = 2, cost 98;  Linen: 1 x (13-12) = 1, cost 12 (the 13c row is not below 13)
    #   Mageweave: searched after the browse, nothing below 250 any more -> "gone", last
    exp = [(1273, "ok", 1, 656.0, 1000.0, 1000.0, 656.0),
           (4306, "ok", 15, 350.0, 1900.0, 100.0, 50.0),
           (2319, "ok", 2, 2.0, 98.0, 49.0, 1.0),
           (2589, "ok", 1, 1.0, 12.0, 12.0, 1.0)]
    got = flip_dump(c)
    ctx.eq(got[:4], exp, "Profit:Flips() ok entries")
    ctx.check(len(got) == 5 and got[4][0] == 4338 and got[4][1] == "gone" and got[4][3] in (0, 0.0, None),
              "Mageweave should be the last entry with status 'gone': %s" % got[4:])
    # CostForAny: search newer than browse -> order book; browse only -> min x qty "est"
    cost, status, info = multi(WC.CostForAny(WC, 4306, 10), 3)
    ctx.eq((cost, status, info and info.source), (1200, "ok", "search"), "CostForAny(Silk, 10) = 5x100 + 5x140")
    cost, status, info = multi(WC.CostForAny(WC, 2770, 5), 3)
    ctx.eq((cost, status, info and info.source), (150, "est", "browse"), "CostForAny(Copper Ore, 5) from the browse = 5 x 30")
    cost, status, info = multi(WC.CostForAny(WC, 2770, 25), 3)
    ctx.eq(status, "short", "CostForAny(Copper Ore, 25): browse says only 20 listed")
    up = multi(WC.UnitPrice(WC, 2770), 3)
    ctx.eq((up[0], up[2]), (30, "browse"), "UnitPrice(Copper Ore) from the browse")
    # history from the browse: relevant items only (Copper Ore is a crate material, Forest Chain is not relevant)
    H = c.server_time() // 3600
    hist = c.g("GetrichDB").history
    rec = hist[2770] and hist[2770].h[H]
    ctx.eq(rec and (int(rec.min), int(rec.qty)), (30, 20), "browse wrote history for relevant Copper Ore")
    ctx.eq(hist[1273], None, "no history for Forest Chain (not relevant)")
    # PRICES_UPDATED at most ~4 per second
    times = sorted(float(x) for x in lua_list(c.M.priceFires)) if id(c) in PRICE_FIRES else []
    worst = max([sum(1 for u in times if t0 <= u < t0 + 1.0) for t0 in times] or [0])
    ctx.check(worst <= 5, "PRICES_UPDATED fired %d times within one second (spec: <= ~4/s)" % worst)
    # tab
    c.slash("/wc flips")
    t = c.texts(clip=True)
    ctx.check(any("Forest Chain" in x for x in t), "flips tab does not list Forest Chain: %s" % t[:30])
    tip = "\n".join(c.hover_text("Silk Cloth"))
    for need in (ctx.money(100), ctx.money(150), "15", ctx.money(1900), ctx.money(350)):
        ctx.check(need in tip, "Silk Cloth flip tooltip lacks %r:\n%s" % (need, tip))
    ctx.check(any(ctx.money(656) in x for x in t), "flips tab does not show the 656c profit (%s)" % ctx.money(656))
    ctx.check(any(ctx.money(350) in x for x in t), "flips tab does not show Silk's 350c profit (%s)" % ctx.money(350))
    check_clean(ctx, c)


@scenario("flips_fresh_login", "flips on a fresh login (nothing in the item cache): candidates still found once item data arrives")
def s_flips_fresh(ctx):
    # Real client: C_Item.GetItemInfo (sell price) is nil for items not seen this session until requested + loaded.
    # After a full browse most rows are such items; the search phase must not silently skip them.
    c = ctx.client(cached=False)
    WC = c.WC
    flip_market(c)
    c.g("GetrichDB").autoScan = False
    c.open_ah()
    c.advance(1)
    ok = WC.Scanner.Start(WC.Scanner, "flips")
    ctx.require(ok, "Scanner:Start('flips') refused")
    c.advance(300, until=lambda: not WC.Scanner.active)
    searched = set(c.ah_stats()["searchByItem"].keys())
    ctx.eq(searched, {4306, 4338, 1273, 2589, 2319},
           "items searched in phase 2 with a cold item cache (candidates whose sell price was still loading were skipped?)")
    got = {e[0]: e[1] for e in flip_dump(c)}
    ctx.eq(got.get(1273), "ok", "Forest Chain flip status after the scan (cold item cache)")
    check_clean(ctx, c)


def foreign_market(c, n=40):
    """n plain items (quality 1, sell 100+i) listed at 50 + (i*7) % 300 x 3; browse pages of 5 rows."""
    c.clear_listings()
    for i in range(n):
        iid = 800000 + i
        c.add_item(iid, "Market Item %d" % i, quality=1, ilvl=10, classID=7, sell=100 + i, cached=True)
        c.set_listings(iid, [(50 + (i * 7) % 300, 3)])
    c.M.AH.browsePageSize = 5


@scenario("browse_foreign_list", "review: a Favorites list (SearchForFavorites / a whole new BROWSE_RESULTS_UPDATED) during our full browse never wipes the snapshot")
def s_browse_foreign(ctx):
    for how in ("favorites", "raw_updated"):
        c = ctx.client()
        WC = c.WC
        foreign_market(c)
        c.g("GetrichDB").autoScan = False
        c.open_ah()
        c.advance(1)
        ok, _ = start_scan(c, "flips")
        ctx.require(ok and not WC.Scanner.active, "%s: first flips scan did not run" % how)
        db = c.g("GetrichDB")
        ctx.eq(len(lua_keys(db.browse["items"])), 40, "%s: snapshot after a complete full browse" % how)
        stamp = db.browse.full
        ctx.check(stamp is not None, "%s: db.browse.full not stamped after a complete browse" % how)
        c.advance(5)
        ok = WC.Scanner.Start(WC.Scanner, "flips")
        ctx.require(ok, "%s: second flips scan refused" % how)
        # 8 pages of 5: wait until our 3rd page is in and the next page request is in flight
        c.advance(120, until=lambda: WC.Scanner.browse is not None and WC.Scanner.browse.pages >= 3 and WC.Scanner.browse.state == "sent")
        ctx.require(WC.Scanner.browse is not None and WC.Scanner.browse.pages >= 3, "%s: browse did not reach page 3" % how)
        if how == "favorites":
            c.ah_blizzard_favorites([800001, 800002])          # Blizzard's Favorites button (hooked call)
        else:
            # the same list change arriving without our hook seeing the call (Blizzard_AuctionHouseFrame.lua:760-772)
            c.eval("""local AH = __WOWMOCK.AH
              AH.browse = { results = {
                { itemKey = { itemID = 800001, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }, totalQuantity = 3, minPrice = 57, containsOwnerItem = false },
                { itemKey = { itemID = 800002, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }, totalQuantity = 3, minPrice = 64, containsOwnerItem = false } },
                full = true, pages = {}, delivered = 0, query = {} }
              __WOWMOCK.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")""")
        c.advance(400, until=lambda: not WC.Scanner.active)
        ctx.require(not WC.Scanner.active, "%s: scan did not finish after the foreign list" % how)
        ctx.eq(len(lua_keys(db.browse["items"])), 40, "%s: snapshot kept (an interrupted browse deletes nothing)" % how)
        ctx.eq(db.browse.full, stamp, "%s: db.browse.full not re-stamped by an interrupted browse" % how)
        check_clean(ctx, c, how)


@scenario("gear_random_suffix", "review: random-suffix gear is searched with the browse row's exact itemKey (level + suffix); 'gone' only from that key")
def s_gear_suffix(ctx):
    c = ctx.client()
    WC = c.WC
    c.clear_listings()
    # a green sword with two random suffixes ("of the Monkey" 1201 cheap, "of the Bear" 1202 dear); vendor pays 1000c
    c.add_item(900001, "Mock Sword", quality=2, ilvl=20, classID=2, equipLoc="INVTYPE_WEAPON", sell=1000, stack=1, cached=True)
    c.set_listings(900001, [{"unit": 400, "qty": 1, "sfx": 1201}, {"unit": 1500, "qty": 1, "sfx": 1202}], commodity=False)
    c.g("GetrichDB").autoScan = False
    c.open_ah()
    c.advance(1)
    ok, _ = start_scan(c, "flips")
    ctx.require(ok and not WC.Scanner.active, "flips scan did not run")
    db = c.g("GetrichDB")
    b = db.browse["items"][900001]
    ctx.require(b is not None, "sword not in the browse snapshot")
    # cheapest variant: 400c, suffix 1201, item level 20; units of both variants: 2
    ctx.eq((int(b.min), int(b.qty), int(b.ilvl or 0), int(b.sfx or 0)), (400, 2, 20, 1201), "browse entry (min, qty, ilvl, sfx)")
    r = WC.Scanner.results[900001]
    ctx.require(r is not None, "sword was not searched")
    # searched with (900001, 20, 1201): the 400c row; without the suffix the AH answers nothing and the flip shows 'gone'
    ctx.eq((r.status, int(r.min or 0), int(r.sfx or 0)), ("listed", 400, 1201), "search result (status, min, searched suffix)")
    got = {e[0]: e for e in flip_dump(c)}
    ctx.eq(got.get(900001) and got[900001][1:4], ("ok", 1, 600.0), "sword flip (status, qty, profit = 1000 - 400)")
    # a later 'nothing listed' answer for another key (e.g. a level-0 search) must not turn the flip into 'gone'
    c.eval("local WC = ...; WC.Scanner.results[900001] = { status = 'none', avail = 0, time = time() + 5 }; WC:Fire('PRICES_UPDATED', 'test')", WC)
    got = {e[0]: e for e in flip_dump(c)}
    ctx.eq(got.get(900001) and got[900001][1], "est", "flip status after a 'none' answer for a different key")
    check_clean(ctx, c)


@scenario("flips_estimate", "flips: only browse data (search phase stopped) -> status 'est', profit = sell - min for one unit")
def s_flips_est(ctx):
    c = ctx.client()
    WC = c.WC
    flip_market(c)
    c.g("GetrichDB").autoScan = False
    c.open_ah()
    c.advance(1)
    WC.Scanner.Start(WC.Scanner, "flips")
    c.advance(120, until=lambda: c.ah_stats()["searches"] >= 1 or not WC.Scanner.active)
    WC.Scanner.Stop(WC.Scanner, "test")
    c.advance(2)
    # est profits = sell - min: Forest Chain 656, Silk 50, Mageweave 50 (tie -> itemID), Medium Leather 1, Linen 1
    got = [(i, s, q, p) for (i, s, q, p, _, _, _) in flip_dump(c)]
    ctx.eq(got, [(1273, "est", None, 656.0), (4306, "est", None, 50.0), (4338, "est", None, 50.0),
                 (2319, "est", None, 1.0), (2589, "est", None, 1.0)], "Profit:Flips() with browse data only")
    c.slash("/wc flips")
    t = " ".join(c.texts(clip=True)).lower()
    ctx.check(("estimate" in t) if ctx.locale == "enUS" else ("估" in t), "estimate rows are not marked as an estimate on the flips tab")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
CRAFT_LISTINGS = {
    2840: [(50, 4), (60, 100)],      # Copper Bar
    2318: [(30, 10)],                # Light Leather
    2880: [(150, 20)],               # Weak Flux on the AH (vendor sells it for 100 -> vendor wins)
    3470: [(25, 5)],                 # Rough Grinding Stone
    7955: [(1500, 1)],               # Copper Claymore (product, gear)
    10938: [(300, 20)],              # Lesser Magic Essence
    10940: [(40, 50), (45, 500)],    # Strange Dust
    10939: [(900, 10)],              # Greater Magic Essence
    10978: [(600, 10)],              # Small Glimmering Shard
    10998: [(1000, 10)],             # Lesser Astral Essence
}


def craft_setup(ctx, c):
    WC = c.WC
    c.open_profession(164)            # Blacksmithing: the addon captures the recipes
    c.advance(3)
    c.close_profession()
    c.advance(1)
    ck = WC.CharKey(WC)
    recs = c.g("GetrichDB").recipes[ck]
    ctx.require(recs is not None and recs[9983] is not None, "Blacksmithing recipes were not captured (db.recipes[%s][9983])" % ck)
    for iid, rows in CRAFT_LISTINGS.items():
        c.set_listings(iid, rows)
    c.set_bags({(0, 1): (2840, 3)})   # 3 Copper Bars already owned
    c.g("GetrichDB").autoScan = False
    c.open_ah()
    c.advance(1)
    ok, secs = start_scan(c, "craft", 900)
    ctx.require(ok, "Scanner:Start('craft') refused")
    c.advance(2)


@scenario("craft_profit", "craft scan + exact profits: vendor/AH mix, missing reagent, owned mats -> cash, Anvil recipes not hidden, DE route")
def s_craft(ctx):
    c = ctx.client()
    WC = c.WC
    craft_setup(ctx, c)
    st = c.ah_stats()
    searched = set(st["searchByItem"].keys())
    ctx.check(2880 not in searched, "Weak Flux (unlimited vendor item) should not be searched by the craft scan")
    for iid in (2840, 2318, 3470, 7955, 10938, 10940):
        ctx.check(iid in searched, "craft scan did not search %d" % iid)
    P = WC.Profit

    def entry(rid):
        e = P.CraftEntry(P, rid)
        ctx.require(e is not None, "Profit:CraftEntry(%d) is nil" % rid)
        return e
    # Copper Claymore 9983: 1 Light Leather 30 + 10 Copper Bar (4x50 + 6x60 = 560) + 2 Weak Flux from the vendor 2x100 = 200
    #   + 1 Rough Grinding Stone 25 = 815. NPC 241 -> -574. AH 1500 x 0.95 = 1425 -> +610.
    #   DE (weapon q2 ilvl 11, band 5-15): LME 0.8 x 1.5 = 1.2 x 300 + SD 0.2 x 1.5 = 0.3 x 40 = 372 x 0.95 = 353.4 -> -461.6
    #   cash: 3 bars owned -> 7 bars 4x50 + 3x60 = 380, + 30 + 200 + 25 = 635. Needs an Anvil (not met) - still shown.
    e = entry(9983)
    ctx.eq(e.status, "ok", "9983 status")
    ctx.eq(fnum(e.cost), 815.0, "9983 cost")
    ctx.eq(fnum(e.npc), 241.0, "9983 npc")
    ctx.eq(fnum(e.npcProfit), -574.0, "9983 npcProfit")
    ctx.eq(fnum(e.ah), 1425.0, "9983 ah")
    ctx.eq(fnum(e.ahProfit), 610.0, "9983 ahProfit")
    ctx.eq(fnum(e.de), 353.4, "9983 de (estimate)", tol=1e-6)
    ctx.eq(fnum(e.deProfit), -461.6, "9983 deProfit", tol=1e-6)
    ctx.eq(fnum(e.best), 610.0, "9983 best")
    ctx.eq(e.bestKind, "ah", "9983 bestKind")
    ctx.eq(fnum(e.cash), 635.0, "9983 cash still needed (3 bars owned)")
    ctx.check(e.tool is not None and "Anvil" in str(e.tool), "9983 tool/station text should mention Anvil: %r" % e.tool)
    flux = [x for x in lua_list(e.reagents) if int(x.itemID) == 2880]
    ctx.check(flux and flux[0].source == "vendor" and fnum(flux[0].cost) == 200.0, "Weak Flux should come from the vendor (2 x 100): %r" % ((flux[0].source, flux[0].cost) if flux else None,))
    # Copper Bracers 2663: 2 bars = 100; NPC 17 -> -83; not on the AH; quality 1 -> no DE. Owned bars cover it: cash 0
    e = entry(2663)
    ctx.eq(fnum(e.cost), 100.0, "2663 cost")
    ctx.eq(fnum(e.npcProfit), -83.0, "2663 npcProfit")
    ctx.eq(e.ah, None, "2663 ah (not listed)")
    ctx.eq(e.de, None, "2663 de (common quality)")
    ctx.eq(fnum(e.best), -83.0, "2663 best")
    ctx.eq(fnum(e.cash), 0.0, "2663 cash (3 bars owned >= 2)")
    # Copper Axe 2738: Linen Cloth is not listed and no vendor sells it -> missing
    e = entry(2738)
    ctx.eq(e.status, "missing", "2738 status")
    ctx.eq(e.cost, None, "2738 cost")
    ctx.eq([int(x) for x in lua_list(e.missing)], [2589], "2738 missing reagents")
    # Copper Dagger 8880: 30 + 6 bars (4x50 + 2x60 = 320) + 100 + 25 = 475; NPC 194 -> -281; DE 353.4 -> -121.6 = best (de)
    e = entry(8880)
    ctx.eq(fnum(e.cost), 475.0, "8880 cost")
    ctx.eq(fnum(e.deProfit), -121.6, "8880 deProfit", tol=1e-6)
    ctx.eq(e.bestKind, "de", "8880 bestKind")
    # Heavy Copper Maul 7408: 2 leather 60 + 12 bars (4x50 + 8x60 = 680) + 2 flux 200 = 940.
    #   DE (weapon q2 ilvl 16, band 16-20): GME 0.75 x 1.5 = 1.125 x 900 = 1012.5, SD 0.2 x 2.5 = 0.5 x 40 = 20,
    #   SGS 0.05 x 1 x 600 = 30 -> 1062.5 x 0.95 = 1009.375 -> deProfit 69.375 (best); NPC 466 -> -474
    e = entry(7408)
    ctx.eq(fnum(e.cost), 940.0, "7408 cost")
    ctx.eq(fnum(e.de), 1009.375, "7408 de", tol=1e-6)
    ctx.eq(fnum(e.best), 69.375, "7408 best", tol=1e-6)
    ctx.eq(e.bestKind, "de", "7408 bestKind")
    # order: best desc, missing last
    lst = lua_list(first(P.Craft(P)))
    bests = [fnum(x.best) for x in lst if x.best is not None]
    ctx.check(bests == sorted(bests, reverse=True), "Profit:Craft() not sorted by best desc")
    st_list = [x.status for x in lst]
    if "missing" in st_list:
        ctx.check(all(s == "missing" for s in st_list[st_list.index("missing"):]), "missing recipes should be last")
    # Getrich regression: prices do not expire after an hour
    c.set_server_time(c.server_time() + 2 * 3600)
    WC.Fire(WC, "SETTINGS_CHANGED", "test")
    e = entry(9983)
    ctx.eq(fnum(e.best), 610.0, "9983 best 2 hours later (no 1-hour freshness cut-off)")
    ctx.eq(WC.UnitPrice(WC, 2840)[0], 50, "UnitPrice(Copper Bar) 2 hours later")
    # crafted gear in the Disenchant list (Enchanting): Copper Claymore costs 815 to make -> gain 353.4 - 815 = -461.6
    de = [x for x in lua_list(first(P.Disenchant(P))) if x.source == "craft" and int(x.itemID) == 7955]
    ctx.check(de, "Profit:Disenchant() has no 'craft' entry for Copper Claymore")
    if de:
        ctx.eq(fnum(de[0].buy), 815.0, "DE craft entry buy = craft cost")
        ctx.eq(fnum(de[0].gain), -461.6, "DE craft entry gain", tol=1e-6)
    # tab + shopping-list tooltip (reagents, vendor NPC for Weak Flux, cash still needed, station)
    c.slash("/wc craft")
    t = c.texts(clip=True)
    ctx.check(any("Copper Claymore" in x for x in t), "craft tab does not list Copper Claymore")
    ctx.check(any(ctx.money(610) in x for x in t), "craft tab does not show the AH profit %s" % ctx.money(610))
    c.hover_text("Copper Claymore")        # the first hover may ask the client for item names it has not cached yet
    c.advance(1)
    tip = c.hover_text("Copper Claymore")
    joined = "\n".join(tip)
    for need in ("Light Leather", "Copper Bar", "Weak Flux", "Rough Grinding Stone", "Anvil", ctx.money(635), ctx.money(815)):
        ctx.check(need in joined, "Copper Claymore tooltip lacks %r:\n%s" % (need, joined))
    npc = c.eval("local WC = ...; local p, info = WC:VendorPrice(2880); return info and info.npc", WC)
    ctx.check(npc and npc in joined, "tooltip does not name the vendor NPC for Weak Flux (%s)" % npc)
    # a merchant selling Copper Bar for 30c (unlimited) -> VENDOR_UPDATED -> Copper Bracers = 2 x 30 = 60 from the vendor
    c.open_merchant(990002, "Test Smith", [{"itemID": 2840, "price": 30, "stackCount": 1}], zone="Orgrimmar", map_id=1454, x=0.3, y=0.4)
    c.advance(1); c.close_merchant(); c.advance(0.5)
    e = entry(2663)
    ctx.eq(fnum(e.cost), 60.0, "Copper Bracers after a vendor sells Copper Bar at 30c")
    ctx.eq(lua_list(e.reagents)[0].source, "vendor", "Copper Bar source after the merchant visit")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
DE_PRICES = {10940: [(40, 50)], 10938: [(300, 20)], 10998: [(1000, 10)], 10978: [(600, 10)], 10939: [(900, 10)]}


def de_setup(c, scan=True):
    for iid, rows in DE_PRICES.items():
        c.set_listings(iid, rows)
    if scan:
        c.g("GetrichDB").autoScan = False
        c.open_ah()
        c.advance(1)
        start_scan(c, "de", 600)
        c.advance(1)


def band_tuple(b):
    return None if b is None else (int(b.q), int(b["class"]), int(b.lo), int(b.hi))


@scenario("de_value", "disenchant bands + value (estimate) for uncommon/rare gear incl. new Forever IDs >= 240000; reasons; partial prices")
def s_de_value(ctx):
    c = ctx.client()
    WC = c.WC
    c.set_listings(241089, [(200, 1)])      # Scarlet Dagger on the AH (gear browse of the de scan)
    de_setup(c)
    DE = WC.DE
    for iid in (1273, 241089, 250482, 11287, 142503, 2589, 2853):
        DE.Band(DE, iid)                    # first call may answer "loading" and ask the client for the item
    c.advance(1)
    # bands
    b, why = multi(DE.Band(DE, 1273))
    ctx.eq(band_tuple(b), (2, 4, 21, 25), "Band(Forest Chain q2 armor ilvl 25)")
    b, why = multi(DE.Band(DE, 241089))
    ctx.eq(band_tuple(b), (2, 2, 5, 15), "Band(Scarlet Dagger 241089, q2 weapon ilvl 10) - Forever item ID >= 240000")
    b, why = multi(DE.Band(DE, 250482))
    ctx.eq(band_tuple(b), (3, 4, 5, 15), "Band(Glowing Copper Boots 250482, rare armor ilvl 15) - new Forever rare band")
    b, why = multi(DE.Band(DE, 1273, 18))
    ctx.eq(band_tuple(b), (2, 4, 16, 20), "Band(1273, ilvl 18) uses the explicit item level")
    for iid, reason, what in ((11287, "nodisenchant", "Lesser Magic Wand (flag 0x8000)"), (142503, "notgear", "shirt (INVTYPE_BODY)"),
                              (2589, "notgear", "Linen Cloth"), (2853, "quality", "Copper Bracers (common)")):
        b, why = multi(DE.Band(DE, iid))
        ctx.eq((b, why), (None, reason), "Band(%d %s)" % (iid, what))
    c.add_item(999001, "Test Green Vest", quality=2, ilvl=22, classID=4, subclassID=1, equipLoc="INVTYPE_CHEST", sell=400, stack=1, cached=False)
    b, why = multi(DE.Band(DE, 999001))
    ctx.eq((b, why), (None, "loading"), "Band(uncached item)")
    c.advance(1)
    b, why = multi(DE.Band(DE, 999001))
    ctx.eq(band_tuple(b), (2, 4, 21, 25), "Band(item after it loaded)")
    # value: Forest Chain band 21-25 armor: SD 0.75 x 5 = 3.75 x 40 = 150; LAE 0.15 x 1.5 = 0.225 x 1000 = 225;
    #   SGS 0.10 x 1 x 600 = 60 -> 435 x 0.95 = 413.25
    v = DE.Value(DE, 1273)
    ctx.require(v is not None, "DE:Value(1273) is nil")
    ctx.eq(fnum(v.value), 413.25, "Value(Forest Chain)")
    parts = {int(p.itemID if p.itemID else p[1]): fnum(p.qty if p.qty is not None else p[2]) for p in lua_list(v.parts)}
    ctx.eq({k: round(v, 9) for k, v in parts.items()}, {10940: 3.75, 10998: 0.225, 10978: 0.1}, "Value(1273).parts expected qty per cast")
    ctx.eq(bool(v.measured), False, "Value(1273).measured")
    ctx.eq(bool(v.partial), False, "Value(1273).partial")
    ctx.eq(bool(v.skillOK), True, "Value(1273).skillOK (Enchanting 150 >= band skill)")
    # Scarlet Dagger (weapon 5-15): LME 0.8 x 1.5 = 1.2 x 300 = 360 + SD 0.2 x 1.5 = 0.3 x 40 = 12 -> 372 x 0.95 = 353.4
    ctx.eq(fnum(DE.Value(DE, 241089).value), 353.4, "Value(Scarlet Dagger 241089)")
    # Glowing Copper Boots (rare 5-15, nearest Classic band): SGS 1 x 600 x 0.95 = 570
    ctx.eq(fnum(DE.Value(DE, 250482).value), 570.0, "Value(Glowing Copper Boots 250482, rare)")
    # AH gear from the de scan's browse: Scarlet Dagger for 200 -> gain 353.4 - 200 = 153.4
    lst = lua_list(first(WC.Profit.Disenchant(WC.Profit)))
    ah = [e for e in lst if e.source == "ah" and int(e.itemID) == 241089]
    ctx.check(ah, "Profit:Disenchant() has no AH entry for Scarlet Dagger 241089 (new Forever ID refused?)")
    if ah:
        ctx.eq(fnum(ah[0].buy), 200.0, "DE AH entry buy")
        ctx.eq(fnum(ah[0].gain), 153.4, "DE AH entry gain = 353.4 - 200")
    # partial: Lesser Astral Essence price unknown -> value from the priced outputs only: (150 + 60) x 0.95 = 199.5
    db = c.g("GetrichDB")
    db.results[10998] = None
    db.browse["items"][10998] = None
    WC.Fire(WC, "PRICES_UPDATED", "test")
    v = DE.Value(DE, 1273)
    ctx.eq([int(x) for x in lua_list(v.missing)], [10998], "Value(1273).missing without LAE price")
    ctx.eq(bool(v.partial), True, "Value(1273).partial without LAE price")
    ctx.eq(fnum(v.value), 199.5, "Value(1273) without LAE price")
    check_clean(ctx, c)


@scenario("de_tab_shows_outputs", "Getrich regression: the Disenchant tab shows what bag gear disenchants into and its value")
def s_de_tab(ctx):
    c = ctx.client()
    WC = c.WC
    de_setup(c)
    c.set_bags({(0, 1): (1273, 1), (0, 2): (241089, 1)})
    c.advance(2)
    c.slash("/wc de")
    t = c.texts(clip=True)
    ctx.check(any("Forest Chain" in x for x in t), "Disenchant tab does not list Forest Chain from the bags: %s" % t[:30])
    ctx.check(any("Strange Dust" in x for x in t), "Disenchant tab does not say what it disenchants into (Strange Dust)")
    ctx.check(any(ctx.money(413.25) in x for x in t), "Disenchant tab does not show the DE value %s" % ctx.money(413.25))
    ctx.check(any("Scarlet Dagger" in x for x in t), "Disenchant tab does not list Scarlet Dagger (ID 241089)")
    tip = "\n".join(c.hover_text("Forest Chain"))
    for need in ("Strange Dust", "Lesser Astral Essence", "Small Glimmering Shard", ctx.money(413.25)):
        ctx.check(need in tip, "Forest Chain DE tooltip lacks %r:\n%s" % (need, tip))
    lst = lua_list(first(WC.Profit.Disenchant(WC.Profit)))
    bag = [e for e in lst if e.source == "bag" and int(e.itemID) == 1273]
    ctx.check(bag, "Profit:Disenchant() has no bag entry for Forest Chain")
    if bag:
        # gain for bag gear = DE value - vendor price = 413.25 - 1656 = -1242.75
        ctx.eq(fnum(bag[0].gain), -1242.75, "bag Forest Chain gain (DE value - vendor price)")
        ctx.eq(fnum(bag[0].sell), 1656.0, "bag Forest Chain sell")
    check_clean(ctx, c)


def do_de_casts(c, plan, interleave=None):
    """plan: list of (loot list, kwargs). interleave: {index: callable} run after cast index."""
    for i, (loot, kw) in enumerate(plan, 1):
        slot = c.find_bag_slot(1273)
        assert slot, "no Forest Chain left in the bags"
        c.disenchant(slot[0], slot[1], loot, **kw)
        if interleave and i in interleave:
            interleave[i]()


@scenario("de_sampling", "20 recorded disenchants switch the band to measured odds; mob loot / interrupted casts are ignored")
def s_de_samples(ctx):
    c = ctx.client()
    WC = c.WC
    de_setup(c, scan=True)
    c.learn_disenchant()
    c.set_bags({(b, s): (1273, 1) for b in range(0, 2) for s in range(1, 13)})   # 24 Forest Chains
    plan = [([(10940, 4)], {})] * 15 + [([(10998, 2)], {})] * 3 + [([(10978, 1)], {})] + [([(10940, 4)], {})]
    for i in (12, 13):
        plan[i - 1] = (plan[i - 1][0], {"autoloot": True})
    inter = {
        5: lambda: c.loot_window([(10940, 7)]),                                            # mob corpse loot: not a DE
        # interrupted cast (no loot), then a mob corpse looted right away: neither counts
        10: lambda: (c.disenchant(*c.find_bag_slot(1273), [(10940, 9)], interrupt=True, run=False), c.advance(3.2), c.loot_window([(10998, 5)])),
    }
    do_de_casts(c, plan[:19], inter)
    band = first(WC.DE.Band(WC.DE, 1273))
    lst, measured, casts = WC.DE.Expected(WC.DE, band)
    ctx.eq((bool(measured), int(casts)), (False, 19), "after 19 casts: still an estimate")
    do_de_casts(c, plan[19:])
    lst, measured, casts = WC.DE.Expected(WC.DE, band)
    ctx.eq((bool(measured), int(casts)), (True, 20), "after 20 casts: measured")
    # 16 casts x 4 Strange Dust = 64 -> 3.2 per cast, hit 16/20 = 0.8; 3 x 2 LAE = 6 -> 0.3, 0.15; 1 SGS -> 0.05, 0.05
    got = {int(e.itemID): (round(fnum(e.qty), 6), round(fnum(e.chance), 6)) for e in lua_list(lst)}
    ctx.eq(got, {10940: (3.2, 0.8), 10998: (0.3, 0.15), 10978: (0.05, 0.05)}, "measured Expected()")
    rec = c.g("GetrichDB").deSamples["2:4:21-25"]
    ctx.require(rec is not None, "db.deSamples['2:4:21-25'] missing; keys: %s" % lua_keys(c.g("GetrichDB").deSamples))
    ctx.eq(int(rec.casts), 20, "deSamples casts")
    ctx.eq({int(k): int(rec.qty[k]) for k in lua_keys(rec.qty)}, {10940: 64, 10998: 6, 10978: 1}, "deSamples qty totals")
    ctx.eq({int(k): int(rec.hit[k]) for k in lua_keys(rec.hit)}, {10940: 16, 10998: 3, 10978: 1}, "deSamples casts containing")
    # measured value: (3.2 x 40 + 0.3 x 1000 + 0.05 x 600) x 0.95 = 458 x 0.95 = 435.1
    ctx.eq(fnum(WC.DE.Value(WC.DE, 1273).value), 435.1, "Value(Forest Chain) with measured odds")
    check_clean(ctx, c)


@scenario("de_sampling_event_order", "disenchant samples are recorded when LOOT_READY arrives before UNIT_SPELLCAST_SUCCEEDED")
def s_de_order(ctx):
    c = ctx.client()
    WC = c.WC
    de_setup(c, scan=False)
    c.learn_disenchant()
    c.set_bags({(0, s): (1273, 1) for s in range(1, 4)})
    do_de_casts(c, [([(10940, 5)], {"order": "loot-first"}), ([(10998, 1)], {"order": "loot-first"}), ([(10940, 4)], {})])
    rec = c.g("GetrichDB").deSamples["2:4:21-25"]
    ctx.require(rec is not None, "no samples recorded")
    ctx.eq(int(rec.casts), 3, "casts recorded")
    ctx.eq({int(k): int(rec.qty[k]) for k in lua_keys(rec.qty)}, {10940: 9, 10998: 1}, "qty totals")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("history_hourly", "history: one record per hour (overwrite), only relevant items, scans record history")
def s_hist(ctx):
    c = ctx.client()
    WC = c.WC
    S = WC.Store
    S.SetWatch(S, 2589, True)
    t0 = c.server_time()
    H = t0 // 3600
    ctx.check(S.RecordHistory(S, 2589, 100, 5, t0), "RecordHistory(watched item) returned false")
    S.RecordHistory(S, 2589, 90, 7, H * 3600 + 3599)            # same hour -> overwrite
    S.RecordHistory(S, 2589, 95, 6, (H + 1) * 3600 + 10)        # next hour
    h = c.g("GetrichDB").history[2589].h
    ctx.eq({int(k): (int(h[k].min), int(h[k].qty)) for k in lua_keys(h)}, {H: (90, 7), H + 1: (95, 6)}, "hourly records")
    c.add_item(999002, "Irrelevant Trinket", classID=15, stack=1)
    ctx.check(not S.RecordHistory(S, 999002, 50, 1, t0), "history recorded for an item that is not relevant")
    ctx.eq(c.g("GetrichDB").history[999002], None, "no history for an irrelevant item")
    hist = lua_list(S.History(S, 2589))
    ctx.eq([(int(x.t), int(x.min)) for x in hist], [(H * 3600, 90), ((H + 1) * 3600, 95)], "Store:History(2589)")
    # a watched-items scan records the hour's cheapest price; a second scan in the same hour overwrites it
    c.set_listings(2589, [(12, 100)])
    c.g("GetrichDB").autoScan = False
    c.open_ah(); c.advance(1)
    start_scan(c, "history", 60)
    H2 = c.server_time() // 3600
    rec = c.g("GetrichDB").history[2589].h[H2]
    ctx.eq(rec and (int(rec.min), int(rec.qty)), (12, 100), "history written by the scan")
    c.set_listings(2589, [(11, 50)])
    start_scan(c, "history", 60)
    rec = c.g("GetrichDB").history[2589].h[c.server_time() // 3600]
    ctx.eq(rec and (int(rec.min), int(rec.qty)), (11, 50), "second scan in the same hour overwrites")
    # Prices tab lists the watched item
    c.slash("/wc history")
    ctx.check(any("Linen Cloth" in x for x in c.texts(clip=True)), "Prices tab does not list the watched Linen Cloth")
    check_clean(ctx, c)


@scenario("history_compression", "hourly records older than 30 days fold into daily {lo, avg, hi, n} on load, merged into an existing day")
def s_hist_compress(ctx):
    H0 = SERVER_TIME0 // 3600
    D = (H0 - 800) // 24              # a day well past the 30-day (720 h) window
    D2 = D - 1
    sv = """GetrichDB = { resultsFormat = 3, watch = { [2589] = true }, history = { [2589] = {
      h = { [%d] = { min = 100, qty = 1 }, [%d] = { min = 80, qty = 2 }, [%d] = { min = 120, qty = 3 },
            [%d] = { min = 90, qty = 4 }, [%d] = { min = 77, qty = 5 } },
      d = { [%d] = { lo = 50, avg = 60, hi = 70, n = 2 } } } } }""" % (D * 24 + 1, D * 24 + 5, D * 24 + 9, D2 * 24 + 3, H0 - 10, D2)
    c = ctx.client(sv=sv)
    rec = c.g("GetrichDB").history[2589]
    ctx.require(rec is not None, "history[2589] gone after load")
    ctx.eq(sorted(int(k) for k in lua_keys(rec.h)), [H0 - 10], "hourly records kept (only the recent one)")
    d = {int(k): (fnum(rec.d[k].lo), round(fnum(rec.d[k].avg), 6), fnum(rec.d[k].hi), int(rec.d[k].n)) for k in lua_keys(rec.d)}
    # day D: 100, 80, 120 -> lo 80, avg 100, hi 120, n 3
    # day D2: existing {50, 60, 70, n 2} + hour 90 -> lo 50, avg (60 x 2 + 90) / 3 = 70, hi 90, n 3
    ctx.eq(d, {D: (80.0, 100.0, 120.0, 3), D2: (50.0, 70.0, 90.0, 3)}, "daily records")
    hist = lua_list(c.WC.Store.History(c.WC.Store, 2589))
    ctx.eq([(int(x.t), bool(x.daily), int(x.min)) for x in hist],
           [(D2 * 86400, True, 70), (D * 86400, True, 100), ((H0 - 10) * 3600, False, 77)], "Store:History() sorted, daily flagged")
    c.slash("/wc history")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
def fixture_merchant(npc_id):
    for m in json.load(open(os.path.join(FIX, "merchants.json")))["merchants"]:
        if m["npcID"] == npc_id:
            return m
    raise KeyError(npc_id)


@scenario("merchant_capture", "merchant window -> db.vendorObs (unit price, bundle, npc, zone, x/y 0-100), cheapest unlimited offer, VendorPrice sources")
def s_merchant(ctx):
    c = ctx.client()
    WC = c.WC
    m = fixture_merchant(4615)        # Katrina Alliestar, Undercity (real scan from the user's client)
    c.open_merchant(m["npcID"], m["name"], m["offers"], zone=m["zone"], map_id=m["map"], x=m["x"], y=m["y"])
    c.advance(1)
    c.close_merchant()
    obs = c.g("GetrichDB").vendorObs
    o = obs[3372]                      # Leaded Vial: 200c per 5 -> 40c each
    ctx.require(o is not None, "vendorObs[3372] (Leaded Vial) not recorded; keys %s" % sorted(int(k) for k in lua_keys(obs))[:10])
    ctx.eq((int(o.price), int(o.bundle), int(o.npc), o.name, o.zone, int(o.map)), (40, 5, 4615, "Katrina Alliestar", "Undercity", 1458), "vendorObs[3372]")
    ctx.eq(fnum(o.x), m["x"] * 100, "vendorObs x (0-100, 0.1 precision)", tol=0.051)
    ctx.eq(fnum(o.y), m["y"] * 100, "vendorObs y (0-100, 0.1 precision)", tol=0.051)
    ctx.eq(bool(o.limited), False, "vendorObs limited")
    ctx.eq(o.faction, "Horde", "vendorObs faction")
    p, info = WC.VendorPrice(WC, 3372)
    ctx.eq(p, 40, "VendorPrice(3372)")
    ctx.eq((info.source, info.npc, int(info.bundle)), ("seen", "Katrina Alliestar", 5), "VendorPrice(3372) info")
    o = obs[8925]
    ctx.eq(o and int(o.price), 500, "Crystal Vial 2500 per 5 -> 500")
    # limited vs unlimited: Kithas sells Lesser Magic Essence limited (1 left) for 800; another vendor unlimited for 1000
    c.open_merchant(3346, "Kithas", [{"itemID": 10938, "price": 800, "stackCount": 1, "numAvailable": 1}], zone="Orgrimmar", map_id=1454, x=0.5377, y=0.3829)
    c.advance(1); c.close_merchant()
    o = obs[10938]
    ctx.eq(o and (int(o.price), bool(o.limited)), (800, True), "only a limited offer known -> kept")
    c.open_merchant(990001, "Test Supplier", [{"itemID": 10938, "price": 1000, "stackCount": 1},
                                              {"itemID": 249496, "price": 0, "stackCount": 1, "hasExtendedCost": True},
                                              {"itemID": 2320, "price": 10, "stackCount": 1, "isPurchasable": False}],
                    zone="Orgrimmar", map_id=1454, x=0.4, y=0.6)
    c.advance(1); c.close_merchant()
    o = obs[10938]
    ctx.eq(o and (int(o.price), bool(o.limited), int(o.npc)), (1000, False, 990001), "cheapest UNLIMITED offer wins over a cheaper limited one")
    ctx.eq(obs[249496], None, "extended-cost (currency) offer skipped")
    ctx.eq(obs[2320], None, "non-purchasable offer skipped")
    # item never seen by this character: from the built-in data
    p, info = WC.VendorPrice(WC, 2880)
    ctx.eq((p, info and info.source), (100, "data"), "VendorPrice(Weak Flux) from WC.VENDOR")
    ctx.eq(WC.VendorPrice(WC, 1273), None, "VendorPrice(gear nobody sells) is nil")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("profession_capture", "recipes captured from the open profession (learned only, wholesale replace, linked skipped, interrupted capture)")
def s_prof(ctx):
    c = ctx.client()
    WC = c.WC
    fx = json.load(open(os.path.join(FIX, "recipes.json")))["chars"][DEFAULT_CHAR]["recipes"]
    bs = {int(k) for k, r in fx.items() if r["skillLine"] == 164 and r["learned"]}
    en = {int(k) for k, r in fx.items() if r["skillLine"] == 333 and r["learned"]}
    c.open_profession(164)
    c.advance(3)
    ck = WC.CharKey(WC)
    ctx.eq(ck, DEFAULT_CHAR, "WC:CharKey() = player GUID")
    db = c.g("GetrichDB")
    recs = db.recipes[ck]
    ctx.require(recs is not None, "db.recipes[charKey] missing")
    got = {int(k) for k in lua_keys(recs)}
    ctx.eq(got, bs, "captured Blacksmithing recipes")
    r = recs[9983]
    ctx.eq((r.n, int(r.p), int(r.o), int(r.y1), int(r.y2)), ("Copper Claymore", 164, 7955, 1, 1), "recipe 9983 fields")
    ctx.eq([[int(x[1]), int(x[2])] for x in lua_list(r.r)], [[2318, 1], [2840, 10], [2880, 2], [3470, 1]], "recipe 9983 reagents")
    ctx.check(r.tool is not None and "Anvil" in str(r.tool), "recipe 9983 tool text: %r" % r.tool)
    ctx.eq(recs[3115].tool, None, "Rough Weightstone has no tool")
    prof = db.chars[ck].profs
    ctx.eq(sorted(int(k) for k in lua_keys(prof)), [129, 164, 185, 333, 356], "db.chars profs (identified by skillLine)")
    ctx.eq((prof[164].name, int(prof[164].rank), int(prof[164].max)), ("Blacksmithing", 150, 225), "profs[164]")
    ctx.eq(WC.EnchantingSkill(WC), 150, "WC:EnchantingSkill()")
    per_frame = max([int(v) for v in c.M.tsStats.frames.values()] or [0])
    ctx.check(per_frame <= 25, "GetRecipeSchematic called %d times in one frame (spec: <= 25 recipes per frame)" % per_frame)
    # second profession keeps the first
    c.open_profession(333)
    c.advance(3)
    got = {int(k) for k in lua_keys(db.recipes[ck])}
    ctx.eq(got, bs | en, "Blacksmithing + Enchanting recipes")
    wrongp = [int(k) for k in lua_keys(db.recipes[ck]) if int(db.recipes[ck][k].p) != fx[str(int(k))]["skillLine"]]
    ctx.check(not wrongp, "recipes stored under the wrong profession: %s" % wrongp[:8])
    ids = c.WC.Recipes.AllItemIDs(c.WC.Recipes)
    ctx.check(ids[7955] and ids[2840], "Recipes:AllItemIDs() lacks 7955 / 2840")
    # unlearned recipe disappears after the next complete capture
    recipes = {int(k): dict(v) for k, v in fx.items()}
    recipes[2663]["learned"] = False
    c.set_recipes(recipes)
    c.open_profession(164)
    c.advance(3)
    ctx.eq(db.recipes[ck][2663], None, "unlearned recipe removed on recapture")
    ctx.check(db.recipes[ck][9983] is not None, "other recipes kept on recapture")
    # a linked (other player's) profession is never captured
    recipes[777001] = {"name": "Linked Recipe", "skillLine": 164, "output": 2853, "reagents": [[2840, 1]], "learned": True}
    c.set_recipes(recipes)
    c.M.TS.linked = True
    c.open_profession(164)
    c.advance(3)
    c.M.TS.linked = False
    ctx.eq(db.recipes[ck][777001], None, "linked profession captured")
    # switching profession while a capture runs: nothing ends up under the wrong profession
    c.open_profession(164, ready_delay=0.1)
    c.advance(0.15)
    c.open_profession(333, ready_delay=0.1)
    c.advance(3)
    wrongp = [int(k) for k in lua_keys(db.recipes[ck]) if fx.get(str(int(k))) and int(db.recipes[ck][k].p) != fx[str(int(k))]["skillLine"]]
    ctx.check(not wrongp, "interrupted capture stored recipes under the wrong profession: %s" % wrongp[:8])
    ctx.check(db.recipes[ck][9983] is not None and db.recipes[ck][7426] is not None, "recipes lost after switching professions mid-capture")
    check_clean(ctx, c)


@scenario("profession_overlay", "profit label on ProfessionsFrame recipe rows (reused font strings, refresh on price change)")
def s_overlay(ctx):
    c = ctx.client()
    WC = c.WC
    craft_setup(ctx, c)
    c.open_profession(164)
    c.advance(2)

    def label_of(rid):
        sb = c.eval("return ProfessionsFrame.CraftingPage.RecipeList.ScrollBox")
        idx = c.eval("""local sb, rid = ...
          for i, n in ipairs(sb:GetDataProvider():Flatten()) do local d = n:GetData(); if d.recipeInfo and d.recipeInfo.recipeID == rid then return i end end""", sb, rid)
        if idx is None:
            return None, None
        sb.ScrollToElementDataIndex(sb, idx)
        for fr, r in c.recipe_rows():
            if r == rid:
                texts = [(fs._text, fs) for fs in c.regions(fr, "FontString") if fs._where and fs._text]
                return fr, [t for t, _ in texts]
        return None, None
    fr, t = label_of(9983)
    ctx.require(fr is not None, "recipe 9983 row not found in ProfessionsFrame")
    ctx.check(t and any(ctx.money(610) in _strip(x) for x in t), "Copper Claymore row label should show +%s, got %s" % (ctx.money(610), t))
    fr, t = label_of(2663)
    ctx.check(t and any(ctx.money(-83).lstrip("-") in _strip(x) for x in t), "Copper Bracers row label should show the -83c loss, got %s" % t)
    fr, t = label_of(2738)
    ctx.check(not t or all(_strip(x).strip() == "" for x in t), "Copper Axe (missing price) should have no profit label, got %s" % t)
    label_of(9983); label_of(2663)                 # warm the scroll box frame pool first
    n0 = c.addon_widget_count("FontString")
    for _ in range(5):
        WC.Fire(WC, "PRICES_UPDATED", "test")
        c.advance(0.5)
        label_of(9983); label_of(2663)
    n1 = c.addon_widget_count("FontString")
    ctx.check(n1 - n0 <= 2, "profession overlay keeps creating font strings: +%d after 5 refreshes" % (n1 - n0))
    # a price change shows up after PRICES_UPDATED: Claymore now sells for 2000 -> 2000 x 0.95 - 815 = 1085
    c.set_listings(7955, [(2000, 1)])
    c.ah_blizzard_search(7955)    # (the addon only learns prices from its own scans; rescan the product)
    c.advance(1)
    WC.Store.SetWatch(WC.Store, 7955, True)
    start_scan(c, "history", 60)
    c.advance(1)
    fr, t = label_of(9983)
    ctx.check(t and any(ctx.money(1085) in _strip(x) for x in t), "label not refreshed after a new price: %s" % t)
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("ah_row_tint", "Blizzard AH rows cheaper than the vendor price get a 'vendor +X' label (browse, commodity and item lists)")
def s_tint(ctx):
    c = ctx.client()
    c.set_listings(4306, [(100, 5), (160, 200)])     # Silk Cloth, sell 150
    c.set_listings(1273, [(1000, 1), (2000, 1)])     # Forest Chain, sell 1656
    c.set_listings(2592, [(40, 20)])                 # Wool Cloth, sell 33
    c.g("GetrichDB").autoScan = False
    c.open_ah()
    c.advance(1)

    def labels(fr):
        out = [_strip(fs._text) for fs in c.regions(fr, "FontString") if fs._where and fs._text and _strip(fs._text).strip()]
        tints = [t for t in c.regions(fr, "Texture") if t._where]
        if out:
            ctx.check(tints, "tinted row has a label but no visible tint texture")
        else:
            ctx.check(not tints, "untinted row still shows a tint texture")
        return out
    c.ah_blizzard_browse("")
    c.advance(2)
    c.ah_show_browse()
    c.advance(0.5)
    rows = {int(rd.itemKey.itemID): labels(fr) for fr, rd in c.ah_rows("browse")}
    ctx.eq(sorted(rows), [1273, 2592, 4306], "browse rows shown")
    ctx.check(any(ctx.money(50) in x for x in rows.get(4306, [])), "Silk browse row (100 < 150) should say +%s: %s" % (ctx.money(50), rows.get(4306)))
    ctx.check(any(ctx.money(656) in x for x in rows.get(1273, [])), "Forest Chain browse row (1000 < 1656) should say +%s: %s" % (ctx.money(656), rows.get(1273)))
    ctx.check(not rows.get(2592), "Wool row (40 > 33) should have no vendor label: %s" % rows.get(2592))
    c.ah_blizzard_search(4306)
    c.advance(1)
    c.ah_show_commodity(4306)
    c.advance(0.5)
    rows = [(int(rd.unitPrice), labels(fr)) for fr, rd in c.ah_rows("commodity")]
    ctx.eq([u for u, _ in rows], [100, 160], "commodity rows")
    ctx.check(rows and any(ctx.money(50) in x for x in rows[0][1]), "commodity row at 100 should say +50c: %s" % rows[:1])
    ctx.check(len(rows) > 1 and not rows[1][1], "commodity row at 160 should have no label: %s" % rows[1:])
    c.ah_blizzard_search(1273)
    c.advance(1)
    c.ah_show_item(1273)
    c.advance(0.5)
    rows = [(int(rd.buyoutAmount), labels(fr)) for fr, rd in c.ah_rows("item")]
    ctx.eq([u for u, _ in rows], [1000, 2000], "item rows")
    ctx.check(rows and any(ctx.money(656) in x for x in rows[0][1]), "item row at 1000 should say +6s 56c: %s" % rows[:1])
    ctx.check(len(rows) > 1 and not rows[1][1], "item row at 2000 should have no label: %s" % rows[1:])
    st = c.ah_stats()
    ctx.eq(st["searches"] + st["browses"] - st["blizzard"], 0, "the row tint must not send AH queries of its own")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
@scenario("idle_progress_sound", "progress bar shows phase + elapsed time, completion chat + sound; nothing runs when idle")
def s_idle(ctx):
    c = ctx.client()
    WC = c.WC
    setup_market_130(c)
    c.open_ah()
    c.advance(1.5)
    ctx.check(WC.Scanner.active, "auto-scan did not start 1 s after the AH opened")
    c.advance(10)
    t = c.texts()
    ctx.check(any(re.search(r"\b1[01]s\b", x) or re.search(r"\b0:1[01]\b", x) or re.search(r"1[01] ?秒", x) for x in t),
              "elapsed time (~11s) not visible while scanning: %s" % [x for x in t if re.search(r"\d", x)][:8])
    chat0 = len(c.chat)
    c.advance(400, until=lambda: not WC.Scanner.active)
    ctx.check(len(c.chat) > chat0, "no chat line when the scan finished")
    snd = c.sounds
    ctx.check(len(snd) >= 1, "no sound when the scan finished (db.soundOnDone)")
    c.advance(2)
    idle = c.idle_report()
    ctx.check(not idle["timers"], "timers still pending after the scan: %s" % idle["timers"])
    ctx.check(not idle["onupdate"], "OnUpdate scripts running while idle (window open): %s" % idle["onupdate"])
    ctx.check(not idle["animations"], "animations playing while idle: %s" % idle["animations"])
    # writs: two phases visible in the bar
    c.slash("/wc writs")
    WC.Scanner.Start(WC.Scanner, "writs")
    c.advance(5)
    t = " ".join(c.texts())
    ctx.check(re.search(r"1\s*/\s*2", t), "phase '1/2' not shown during the writs scan")
    c.advance(900, until=lambda: not WC.Scanner.active)
    c.g("GetrichDB").soundOnDone = False
    n = len(c.sounds)
    start_scan(c, "crates", 400)
    ctx.eq(len(c.sounds), n, "sound played although soundOnDone = false")
    c.close_ah()
    c.advance(3)
    frame = c.g("GetrichFrame")
    ctx.check(not frame.IsVisible(frame), "window still shown after the AH closed (1.3.0 behaviour: hide with the AH)")
    idle = c.idle_report()
    ctx.check(not idle["timers"] and not idle["onupdate"] and not idle["animations"], "work while idle after AH close: %s" % idle)
    c.slash("/wc")
    c.advance(5)
    idle = c.idle_report()
    ctx.check(not idle["onupdate"] and not idle["timers"], "window opened with /wc runs work while idle: %s" % idle)
    check_clean(ctx, c)


@scenario("ah_closed_mid_scan", "closing the AH stops the scan, keeps what was scanned, hides the window, leaves no timers")
def s_close(ctx):
    c = ctx.client()
    WC = c.WC
    setup_market_130(c)
    c.open_ah()
    c.advance(12)
    ctx.check(WC.Scanner.active, "scan not running 12 s after AH open")
    c.close_ah()
    c.advance(5)
    ctx.check(not WC.Scanner.active, "scanner still active after AH close")
    frame = c.g("GetrichFrame")
    ctx.check(not frame.IsVisible(frame), "window still visible after AH close")
    n = sum(1 for k in lua_keys(c.g("GetrichDB").results))
    ctx.check(n >= 5, "results from before the close were dropped (%d left)" % n)
    ctx.check(not c.running_timers(), "timers left after AH close: %s" % c.running_timers())
    check_clean(ctx, c)


@scenario("memory_and_widgets", "memory sanity after scans and repeated refreshes; refreshing tabs creates no new widgets")
def s_mem(ctx):
    c = ctx.client()
    WC = c.WC
    # a big auction house: 1500 extra items for the full browse
    for i in range(1500):
        iid = 900000 + i
        c.add_item(iid, "Bulk Item %d" % i, quality=1 + (i % 3), ilvl=5 + i % 40, classID=(7 if i % 4 else 4), equipLoc=("" if i % 4 else "INVTYPE_CHEST"),
                   sell=10 + i % 300, stack=(20 if i % 4 else 1))
        c.set_listings(iid, [(50 + (i * 37) % 900, 1 + i % 30)])
    c.M.AH.browsePageSize = 500
    m0 = c.memory_kb()
    c.g("GetrichDB").autoScan = False
    c.open_ah(); c.advance(1)
    ok, secs = start_scan(c, "flips", 900)
    ctx.require(ok and not WC.Scanner.active, "flips scan did not finish")
    m1 = c.memory_kb()
    for tab in TABS:
        c.slash("/wc " + tab)
    # one warm-up round: the first refresh after the item data arrived fills caches once (craft + disenchant lists
    # including the trainer recipes of the character's professions); a leak is growth on every round after that
    mw = c.memory_kb()
    for tab in TABS:
        c.slash("/wc " + tab)
        WC.Fire(WC, "PRICES_UPDATED", "test")
        c.advance(0.3)
    w1 = c.addon_widget_count()
    m2 = c.memory_kb()
    for _ in range(5):
        for tab in TABS:
            c.slash("/wc " + tab)
            WC.Fire(WC, "PRICES_UPDATED", "test")
            c.advance(0.3)
    w2 = c.addon_widget_count()
    m3 = c.memory_kb()
    ctx.log("memory KB: start %.0f, after browse+search %.0f, tabs %.0f, 5 refresh rounds %.0f; widgets %d -> %d" % (m0, m1, m2, m3, w1, w2))
    ctx.note("Lua heap: %.0f KB after a 1500-item browse + flip searches (+%.0f KB), first refresh round +%.0f KB, +%.0f KB after 5 more; %d addon widgets"
             % (m1, m1 - m0, m2 - mw, m3 - m2, w2))
    ctx.check(m2 - mw < 1500, "the first refresh round grew the Lua heap by %.0f KB" % (m2 - mw))
    ctx.check(m1 - m0 < 4000, "1500-item browse grew the Lua heap by %.0f KB (> 4 MB)" % (m1 - m0))
    ctx.check(m3 - m2 < 300, "5 refresh rounds grew the Lua heap by %.0f KB (leak?)" % (m3 - m2))
    ctx.check(w2 - w1 <= 10, "refreshing tabs created %d new widgets" % (w2 - w1))
    check_clean(ctx, c)


@scenario("slash_commands", "/wc, /wc <tab>, /wc scan [tab], /wc stop")
def s_slash(ctx):
    c = ctx.client()
    WC = c.WC
    frame_shown = lambda: (c.g("GetrichFrame") is not None and c.g("GetrichFrame").IsVisible(c.g("GetrichFrame")))
    c.slash("/wc")
    ctx.check(frame_shown(), "/wc did not open the window")
    c.slash("/wc")
    ctx.check(not frame_shown(), "/wc did not toggle the window closed")
    n = len(c.chat)
    c.slash("/wc scan")
    ctx.check(not WC.Scanner.active and len(c.chat) > n, "/wc scan with the AH closed should print a hint")
    c.g("GetrichDB").autoScan = False
    setup_market_130(c)
    c.open_ah(); c.advance(1)
    c.slash("/wc scan writs")
    ctx.check(WC.Scanner.active and WC.Scanner.kind == "writs", "/wc scan writs did not start a writs scan")
    ctx.eq(c.g("GetrichDB").tab, "writs", "/wc scan writs selects the writs tab")
    c.advance(5)
    c.slash("/wc stop")
    ctx.check(not WC.Scanner.active, "/wc stop did not stop the scan")
    c.slash("/gr crates")
    ctx.eq(c.g("GetrichDB").tab, "crates", "/gr crates")
    check_clean(ctx, c)


@scenario("click_everything", "click every visible button and hover every widget on every tab (after data exists): no Lua errors")
def s_monkey(ctx):
    c = ctx.client()
    WC = c.WC
    craft_setup(ctx, c)
    de_setup(c, scan=False)
    flip_market(c)
    for iid, rows in CRAFT_LISTINGS.items():
        c.set_listings(iid, rows)
    start_scan(c, "flips", 300)
    c.set_bags({(0, 1): (1273, 1), (0, 2): (2840, 3)})
    c.WC.Store.SetWatch(c.WC.Store, 2589, True)
    clicked = 0
    for tab in TABS:
        c.slash("/wc " + tab)
        c.advance(0.2)
        for b in c.buttons():
            if not b.IsVisible(b) or not b._enabled:
                continue
            label = _strip(b.GetText(b) or "")
            if label and re.search(r"scan|stop|扫描|掃描|停止", label, re.I):
                continue
            c.hover(b)
            b.Click(b, "LeftButton")
            b.Click(b, "RightButton") if c.g("GetrichFrame").IsVisible(c.g("GetrichFrame")) else None
            clicked += 1
            if not c.g("GetrichFrame").IsVisible(c.g("GetrichFrame")):
                c.slash("/wc " + tab)
        for w in c.regions(None):
            if w._kind not in ("FontString", "Texture", "Line") and w._scripts.OnEnter is not None:
                c.hover(w)
    ctx.note("clicked %d buttons" % clicked)
    ctx.check(clicked >= 20, "only %d buttons found to click" % clicked)
    check_clean(ctx, c)


@scenario("savedvariables", "real 1.3.0 SV (format 2) upgrades keeping prices/settings; SV round-trip after scans; stable char key")
def s_sv(ctx):
    c = ctx.client(sv=REAL_SV)
    db = c.g("GetrichDB")
    ctx.eq(db.resultsFormat, 3, "resultsFormat upgraded 2 -> 3")
    r = db.results[2319]
    ctx.eq(r and (r.status, int(r.min), int(r.avail)), ("listed", 194, 8883), "results[2319] kept from the 1.3.0 SV")
    ctx.eq((db.autoScan, db.onlyMine, db.tab), (False, True, "crates"), "1.3.0 settings kept")
    ctx.eq(db.soundOnDone, True, "new default soundOnDone added")
    cost = c.WC.CostFor(c.WC, 2319, 20)
    ctx.eq(cost[0], 194 * 20, "CostFor(2319, 20) from saved results (80 listed at 194c)")
    c.open_ah()
    c.advance(5)
    ctx.check(not c.WC.Scanner.active, "autoScan = false in the SV, but a scan started")
    # round trip
    setup_market_130(c)
    start_scan(c, "crates", 400)
    c.WC.Store.SetWatch(c.WC.Store, 2589, True)
    text = c.logout_sv()
    ctx.check("GetrichDB" in text, "logout produced no SavedVariables")
    c2 = ctx.client(sv=text)
    db2 = c2.g("GetrichDB")
    ctx.eq(db2.results[2589] and int(db2.results[2589].min), 10, "results survive a reload")
    ctx.check(db2.watch[2589], "watch list survives a reload")
    keys = " ".join(str(k) for k in lua_keys(db2))
    ctx.check("Beta" not in keys and "Classic" not in keys, "realm names used as DB keys (Getrich market-key split): %s" % keys)
    check_clean(ctx, c)
    check_clean(ctx, c2, "reloaded")


@scenario("char_key_stable", "Getrich regression (market key split): the character key is the same before and after PLAYER_LOGIN")
def s_charkey(ctx):
    c = ctx.client(login=False)
    k1 = c.WC.CharKey(c.WC)
    c.login()
    k2 = c.WC.CharKey(c.WC)
    ctx.eq(k1, k2, "WC:CharKey() before vs after login")
    ctx.eq(k2, DEFAULT_CHAR, "WC:CharKey() is the player GUID")
    check_clean(ctx, c)


@scenario("second_character", "the Tailoring + Enchanting character: capture, craft scan, no errors")
def s_char2(ctx):
    c = ctx.client(char=SECOND_CHAR)
    WC = c.WC
    c.load_orderbooks()
    for sl in (197, 333, 185, 129):
        c.open_profession(sl)
        c.advance(3)
    c.close_profession()
    recs = c.g("GetrichDB").recipes[SECOND_CHAR]
    fx = json.load(open(os.path.join(FIX, "recipes.json")))["chars"][SECOND_CHAR]["recipes"]
    exp = {int(k) for k, r in fx.items() if r["learned"] and r["skillLine"] in (197, 333, 185, 129)}
    ctx.eq({int(k) for k in lua_keys(recs)} if recs else set(), exp, "captured recipes of the second character")
    c.g("GetrichDB").autoScan = False
    c.open_ah(); c.advance(1)
    ok, secs = start_scan(c, "craft", 900)
    ctx.check(ok and not WC.Scanner.active, "craft scan did not finish")
    lst, counts = WC.Profit.Craft(WC.Profit)
    ctx.check(len(lua_list(lst)) > 20, "Profit:Craft() returned only %d entries" % len(lua_list(lst)))
    c.slash("/wc craft")
    c.slash("/wc de")
    check_clean(ctx, c)


# ===================================================================================================================
# round 2 (SPEC2: Getrich 2026.10.3) - settings that change behaviour, old SV wipe
# ===================================================================================================================
CODEX_SV_REAL = "/home/claude/brief/sv/Getrich.lua"            # the user's real old (Codex-built) Getrich SavedVariables
CODEX_SV_FIXTURE = os.path.join(FIX, "sv_getrich_codex.lua")    # trimmed, anonymized copy with the same schema


@scenario("old_getrich_sv_wiped", "SPEC2 0.1: the old Codex-built GetrichDB (schemaVersion + markets + characters) is wiped, nothing migrated")
def s_codex_wipe(ctx):
    path = CODEX_SV_REAL if os.path.exists(CODEX_SV_REAL) else CODEX_SV_FIXTURE
    ctx.note("old SV: " + path)
    c = ctx.client(sv=path)
    db = c.g("GetrichDB")
    ctx.require(db is not None, "GetrichDB missing after load")
    for k in ("schemaVersion", "markets", "characters", "vendor", "disenchant", "settings"):
        ctx.eq(db[k], None, "old key GetrichDB.%s after load" % k)
    ctx.eq(db.resultsFormat, 3, "resultsFormat")
    ctx.eq((db.autoScan, db.tab, db.soundOnDone), (True, "crates", True), "defaults applied after the wipe")
    for k, v in (("historyDays", 30), ("pruneDays", 14), ("deMeasuredCasts", 20), ("flipCandidates", 80)):
        ctx.eq(db[k], v, "default %s" % k)
    ctx.eq(lua_keys(db.recipes), [], "no recipes migrated from the old SV")
    ctx.eq(lua_keys(db.vendorObs), [], "no merchant records migrated from the old SV")
    text = c.logout_sv()
    for word in ("schemaVersion", "markets", "observations", "normalizationComplete"):
        ctx.check(word not in text, "saved GetrichDB still contains the old '%s'" % word)
    # our own format is kept (a DB with resultsFormat is never wiped, even if it had a schemaVersion key)
    own = 'GetrichDB = { resultsFormat = 3, schemaVersion = 1, tab = "flips", watch = { [2589] = true } }'
    c2 = ctx.client(sv=own)
    db2 = c2.g("GetrichDB")
    ctx.eq((db2.tab, bool(db2.watch[2589])), ("flips", True), "a current-format GetrichDB is kept")
    check_clean(ctx, c)
    check_clean(ctx, c2, "current format")


def fire_setting(c, key, value):
    """Set a GetrichDB key the way the settings page does: write it, then fire SETTINGS_CHANGED(key)."""
    c.g("GetrichDB")[key] = value
    c.WC.Fire(c.WC, "SETTINGS_CHANGED", key)


@scenario("history_days_setting", "historyDays: hourly records older than N days fold into days on load and when the setting changes")
def s_history_days(ctx):
    H0 = SERVER_TIME0 // 3600
    h40, h20, h2 = H0 - 40 * 24 - 3, H0 - 20 * 24 - 3, H0 - 2 * 24
    sv = """GetrichDB = { resultsFormat = 3, watch = { [2589] = true }, historyDays = 30, history = { [2589] = {
      h = { [%d] = { min = 40, qty = 1 }, [%d] = { min = 20, qty = 2 }, [%d] = { min = 2, qty = 3 } }, d = {} } } }""" % (h40, h20, h2)
    c = ctx.client(sv=sv)
    rec = c.g("GetrichDB").history[2589]
    # historyDays 30: only the 40-day-old hour folds -> day (h40 // 24) = { lo 40, avg 40, hi 40, n 1 }
    ctx.eq(sorted(int(k) for k in lua_keys(rec.h)), sorted([h20, h2]), "hourly records kept with historyDays = 30")
    ctx.eq({int(k): (fnum(rec.d[k].lo), fnum(rec.d[k].avg), fnum(rec.d[k].hi), int(rec.d[k].n)) for k in lua_keys(rec.d)},
           {h40 // 24: (40.0, 40.0, 40.0, 1)}, "daily records with historyDays = 30")
    fire_setting(c, "historyDays", 14)
    # 14 days: the 20-day-old hour folds too; the 2-day-old one stays
    ctx.eq(sorted(int(k) for k in lua_keys(rec.h)), [h2], "hourly records kept after historyDays -> 14")
    ctx.eq(sorted(int(k) for k in lua_keys(rec.d)), sorted([h40 // 24, h20 // 24]), "daily records after historyDays -> 14")
    check_clean(ctx, c)


@scenario("prune_days_setting", "pruneDays: search results / browse rows older than N days are dropped on load and when the setting changes")
def s_prune_days(ctx):
    t0 = SERVER_TIME0
    d = 86400
    sv = """GetrichDB = { resultsFormat = 3, pruneDays = 14,
      results = { [2589] = { status = "listed", min = 10, avail = 5, time = %d, entries = { { 10, 5 } } },
                  [2318] = { status = "listed", min = 30, avail = 5, time = %d, entries = { { 30, 5 } } } },
      browse = { items = { [2770] = { min = 5, qty = 20, t = %d }, [2771] = { min = 9, qty = 20, t = %d } } } }""" % (
        t0 - 20 * d, t0 - 5 * d, t0 - 20 * d, t0 - 2 * d)
    c = ctx.client(sv=sv)
    db = c.g("GetrichDB")
    # 14 days: the 20-day-old search result (Linen) and browse row (Copper Ore) are dropped
    ctx.eq(sorted(int(k) for k in lua_keys(db.results)), [2318], "results kept with pruneDays = 14")
    ctx.eq(sorted(int(k) for k in lua_keys(db.browse["items"])), [2771], "browse rows kept with pruneDays = 14")
    ctx.eq(first(c.WC.UnitPrice(c.WC, 2589)), None, "UnitPrice of a pruned item")
    fire_setting(c, "pruneDays", 3)
    # 3 days: Light Leather (5 days) goes, Tin Ore's browse row (2 days) stays
    ctx.eq(sorted(int(k) for k in lua_keys(db.results)), [], "results kept after pruneDays -> 3")
    ctx.eq(sorted(int(k) for k in lua_keys(db.browse["items"])), [2771], "browse rows kept after pruneDays -> 3")
    ctx.eq(first(c.WC.UnitPrice(c.WC, 2771)), 9, "UnitPrice(Tin Ore) from the kept browse row")
    check_clean(ctx, c)


@scenario("flip_candidates_setting", "flipCandidates (40 / 80 / 150) limits how many cheap items the flips scan searches, best first")
def s_flip_n(ctx):
    for n, expect in ((40, 40), (150, 60)):
        c = ctx.client()
        WC = c.WC
        c.clear_listings()
        # 60 items the vendor buys for 1000c each, listed at 1000 - 10 x (i + 1): score (sell - min) x min(qty, 20) = 10 x (i + 1)
        for i in range(60):
            iid = 950000 + i
            c.add_item(iid, "Flip Item %d" % i, quality=1, ilvl=10, classID=7, sell=1000, stack=20, cached=True)
            c.set_listings(iid, [(1000 - 10 * (i + 1), 1)])
        c.M.AH.browsePageSize = 25
        c.g("GetrichDB").flipCandidates = n
        c.g("GetrichDB").autoScan = False
        c.open_ah(); c.advance(1)
        ok, _ = start_scan(c, "flips", 900)
        ctx.require(ok and not WC.Scanner.active, "flips scan did not finish (flipCandidates %d)" % n)
        searched = set(c.ah_stats()["searchByItem"])
        # the biggest scores are the highest i: flipCandidates 40 -> i = 20..59; 150 -> all 60
        ctx.eq(searched, {950000 + i for i in range(60 - expect, 60)}, "items searched with flipCandidates = %d" % n)
        check_clean(ctx, c, "flipCandidates %d" % n)


@scenario("de_measured_casts_setting", "deMeasuredCasts: with 10, ten recorded disenchants switch the band to measured odds")
def s_de_measured_n(ctx):
    c = ctx.client()
    WC = c.WC
    de_setup(c, scan=True)
    c.learn_disenchant()
    fire_setting(c, "deMeasuredCasts", 10)
    c.set_bags({(0, s): (1273, 1) for s in range(1, 13)})
    plan = [([(10940, 4)], {})] * 8 + [([(10998, 1)], {})] * 2
    do_de_casts(c, plan[:9])
    band = first(WC.DE.Band(WC.DE, 1273))
    lst, measured, casts = WC.DE.Expected(WC.DE, band)
    ctx.eq((bool(measured), int(casts)), (False, 9), "after 9 casts with deMeasuredCasts = 10")
    do_de_casts(c, plan[9:])
    lst, measured, casts = WC.DE.Expected(WC.DE, band)
    ctx.eq((bool(measured), int(casts)), (True, 10), "after 10 casts with deMeasuredCasts = 10")
    # 8 x 4 Strange Dust = 32 -> 3.2 per cast (hit 0.8); 2 x 1 LAE -> 0.2 (hit 0.2)
    got = {int(e.itemID): (round(fnum(e.qty), 6), round(fnum(e.chance), 6)) for e in lua_list(lst)}
    ctx.eq(got, {10940: (3.2, 0.8), 10998: (0.2, 0.2)}, "measured Expected() with 10 casts")
    # (3.2 x 40 + 0.2 x 1000) x 0.95 = 328 x 0.95 = 311.6
    ctx.eq(fnum(WC.DE.Value(WC.DE, 1273).value), 311.6, "Value(Forest Chain) measured from 10 casts")
    fire_setting(c, "deMeasuredCasts", 20)
    lst, measured, casts = WC.DE.Expected(WC.DE, band)
    ctx.eq((bool(measured), int(casts)), (False, 10), "back to the estimate after deMeasuredCasts -> 20")
    ctx.eq(fnum(WC.DE.Value(WC.DE, 1273).value), 413.25, "Value(Forest Chain) estimate again")
    check_clean(ctx, c)


SETTING_DEFAULTS = {   # SPEC2 5: every adjustable parameter and its default
    "autoScan": True, "soundOnDone": True, "chatOnDone": True, "ahTint": True, "profOverlay": True, "profLevelMark": True,
    "uiScale": 1.0, "dockToAH": True,
    "onlyMine": False, "hideNoCrate": True, "hideNoMats": True, "perfRank": 0,
    "hideNoWrit": True, "hideNoItem": True, "hideDone": True, "diplomatRank": 0,
    "flipMinProfit": 0, "flipShowGone": False, "flipCandidates": 80,
    "craftOnlyProfit": False, "craftHideMissing": False, "craftShowUnlearned": False, "levelOffset": "best3", "levelTarget": "max",
    "deSource": "all", "deHideSkill": False, "deHideLoss": False, "deMeasuredCasts": 20,
    "historyRange": "7d", "historyDays": 30, "pruneDays": 14,
}
SETTING_CHOICES = {    # option lists the page must offer (SPEC2 5)
    "flipMinProfit": {0, 1000, 10000, 50000}, "flipCandidates": {40, 80, 150}, "deMeasuredCasts": {10, 20, 30, 50},
    "historyDays": {7, 14, 30, 60, 90}, "pruneDays": {3, 7, 14, 30}, "levelOffset": {"best3", "npcde", "none"},
    "levelTarget": {"max", 225, 300}, "perfRank": {0, 1, 2, 3}, "diplomatRank": {0, 1, 2, 3, 4, 5},
}


def db_settings(c):
    db = c.g("GetrichDB")
    out = {}
    for k in lua_keys(db):
        v = db[k]
        if isinstance(v, (bool, int, float, str)):
            out[k] = v
    return out


def listen_settings_changed(c):
    c.eval("local WC, M = ...; M.settingsFired = {}; WC:On('SETTINGS_CHANGED', function(key) M.settingsFired[#M.settingsFired + 1] = tostring(key) end)", c.WC, c.M)
    return lambda: [x for x in lua_list(c.M.settingsFired)]


def fill_data(c):
    """Something in every data table the settings page can clear."""
    db = c.g("GetrichDB")
    H = c.server_time() // 3600
    c.eval("""local db, H, t = ...
      db.watch[2589] = true
      db.history[2589] = { h = { [H] = { min = 10, qty = 5 } }, d = {} }
      db.results[2589] = { status = "listed", min = 10, avail = 5, time = t, entries = { { 10, 5 } } }
      db.browse.items[2770] = { min = 5, qty = 20, t = t }
      db.deSamples["2:4:21-25"] = { casts = 3, qty = { [10940] = 12 }, hit = { [10940] = 3 }, min = {}, max = {} }
      db.vendorObs[3372] = { price = 40, bundle = 5, npc = 4615, name = "Katrina Alliestar", zone = "Undercity", limited = false, t = t }""",
           db, H, c.server_time())


def data_state(c):
    db = c.g("GetrichDB")
    return {"history": len(lua_keys(db.history)), "results": len(lua_keys(db.results)),
            "browse": len(lua_keys(db.browse["items"])), "deSamples": len(lua_keys(db.deSamples)),
            "vendorObs": len(lua_keys(db.vendorObs))}


@scenario("settings_page", "SPEC2 5: Settings -> AddOns -> Getrich page: every control writes its key + fires SETTINGS_CHANGED, data buttons, about")
def s_settings(ctx):
    c = ctx.client()
    WC = c.WC
    db = c.g("GetrichDB")
    # defaults registered for every parameter
    for k, v in SETTING_DEFAULTS.items():
        got = db[k]
        ctx.check(got == v or (isinstance(v, float) and got is not None and abs(float(got) - v) < 1e-9),
                  "default GetrichDB.%s: expected %r, got %r" % (k, v, got))
    cats = [x for x in c.settings_categories() if x["addon"]]
    ctx.require(len(cats) == 1, "expected one Settings category registered under AddOns, got %s" % [x["name"] for x in c.settings_categories()])
    cat = cats[0]
    ctx.eq(cat["name"], "Getrich", "Settings category name")
    # /gr settings opens the game options on our page (Settings.OpenToCategory(category:GetID()))
    c.slash("/gr settings")
    ctx.eq(c.settings_opened(), "Getrich", "/gr settings opens the Getrich category")
    page = cat["frame"] if cat["kind"] == "canvas" else None
    ctx.require(page is not None and page.IsVisible(page), "settings canvas page not visible after /gr settings")
    c.close_settings()
    c.slash("/gr config")
    ctx.eq(c.settings_opened(), "Getrich", "/gr config opens the Getrich category")
    # the gear button in the main window's title bar opens the same page
    c.close_settings()
    c.slash("/gr")
    c.advance(0.5)
    main = c.g("GetrichFrame")
    gears = [b for b in c.regions(main, "Button") if any("/gr settings" in x for x in c.hover(b))] if main is not None else []
    ctx.check(len(gears) == 1, "expected one title-bar button whose tooltip points to /gr settings, found %d" % len(gears))
    if gears:
        gears[0].Click(gears[0], "LeftButton")
        ctx.eq(c.settings_opened(), "Getrich", "the gear button opens the Getrich category")
    # about: author, contact, website, version from the TOC (copyable)
    t = c.texts(page, editboxes=True)
    meta = c.toc["meta"]
    for need in ("Aaron Tong", "Luvx.inc@gmail.com", "https://github.com/luvxinc/Getrich", meta["Version"], meta["X-Released"]):
        ctx.check(any(need in x for x in t), "settings page does not show %r" % need)
    boxes = [w for w in c.regions(page, "EditBox")]
    ctx.check(any("Luvx.inc@gmail.com" in str(w._text) for w in boxes), "contact e-mail is not in a (copyable) EditBox")
    # every control
    fired = listen_settings_changed(c)
    changed_by, values = {}, {}
    widgets = [w for w in c.regions(page) if w._kind in ("CheckButton", "Button") and w._enabled]
    actions = [w for w in widgets if w._kind == "Button" and "UIPanelButtonTemplate" in str(w._template or "")]
    others = [w for w in widgets if w not in actions]
    ctx.check(len(others) >= 40, "only %d setting controls found on the page" % len(others))
    for w in others:
        before = db_settings(c)
        n0 = len(fired())
        w.Click(w, "LeftButton")
        after = db_settings(c)
        diff = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
        got = fired()[n0:]
        for k in diff:
            changed_by.setdefault(k, 0)
            changed_by[k] += 1
            values.setdefault(k, set()).add(after.get(k))
            ctx.check(k in got, "changing %s did not fire SETTINGS_CHANGED('%s') (fired %s)" % (k, k, got))
        if w._kind == "CheckButton" and diff:
            w.Click(w, "LeftButton")          # back to the original value
        if "uiScale" in diff:
            f = c.g("GetrichFrame")
            if f is not None:
                ctx.eq(round(float(f.GetScale(f)), 3), round(float(after["uiScale"]), 3), "GetrichFrame scale after uiScale = %s" % after["uiScale"])
    missing = sorted(k for k in SETTING_DEFAULTS if k not in changed_by)
    ctx.check(not missing, "no control on the settings page changes: %s" % missing)
    for k, opts in SETTING_CHOICES.items():
        seen = {int(v) if isinstance(v, float) and v == int(v) else v for v in values.get(k, set())} | {SETTING_DEFAULTS[k]}
        ctx.check(opts <= seen, "%s: options %s offered, expected at least %s" % (k, sorted(map(str, seen)), sorted(map(str, opts))))
    sc = values.get("uiScale", set())
    ctx.check(sc and min(sc) >= 0.8 - 1e-9 and max(sc) <= 1.3 + 1e-9, "uiScale values outside 0.8-1.3: %s" % sorted(sc))
    # data buttons: confirmation first; cancel keeps everything, accept clears exactly one kind of data
    cleared = []
    for w in actions:
        fill_data(c)
        full = data_state(c)
        npop = len(c.popups())
        w.Click(w, "LeftButton")
        if len(c.popups()) <= npop and not c.popups():
            continue                           # not a data button
        c.accept_popup(cancel=True)
        ctx.eq(data_state(c), full, "cancelling '%s' kept the data" % _strip(w.GetText(w)))
        db.flipCandidates, db.historyDays, db.pruneDays = 150, 60, 30
        w.Click(w, "LeftButton")
        ctx.require(c.accept_popup() is not None, "no confirmation for '%s'" % _strip(w.GetText(w)))
        st = data_state(c)
        gone = sorted(k for k in st if st[k] == 0)
        reset = (db.flipCandidates == 80)
        cleared.append((tuple(gone), reset))
        # data retention is not an option to reset: historyDays / pruneDays survive every button
        ctx.eq((db.historyDays, db.pruneDays), (60, 30), "historyDays / pruneDays after '%s'" % _strip(w.GetText(w)))
    ctx.check(((("history",), False) in cleared), "no button clears only the price history: %s" % cleared)
    ctx.check(((("browse", "results"), False) in cleared), "no button clears scan results + browse snapshot: %s" % cleared)
    ctx.check(((("deSamples",), False) in cleared), "no button clears the disenchant records: %s" % cleared)
    ctx.check(((("vendorObs",), False) in cleared), "no button clears the merchant records: %s" % cleared)
    ctx.check((((), True) in cleared), "no 'reset settings' button that keeps the data: %s" % cleared)
    check_clean(ctx, c)


@scenario("settings_effects", "chatOnDone / ahTint / dockToAH / uiScale switch the behaviour they name")
def s_settings_effects(ctx):
    c = ctx.client()
    WC = c.WC
    setup_market_130(c)
    c.set_listings(4306, [(100, 5), (160, 200)])
    fire_setting(c, "chatOnDone", False)
    fire_setting(c, "uiScale", 1.2)
    fire_setting(c, "dockToAH", False)
    c.open_ah()
    c.advance(1.5)
    f = c.g("GetrichFrame")
    ctx.require(f is not None, "no GetrichFrame")
    ctx.eq(round(float(f.GetScale(f)), 3), 1.2, "GetrichFrame scale with uiScale = 1.2")
    def docked():   # compare the Lua tables in Lua (two Python wrappers of one table are never ==)
        return bool(c.eval("local f = ...; for _, p in ipairs(f._points) do if rawequal(p[2], AuctionHouseFrame) then return true end end return false", f))
    ctx.check(not docked(), "window docked to the AH although dockToAH = false")
    n = len(c.chat)
    c.advance(400, until=lambda: not WC.Scanner.active)
    ctx.eq(c.chat[n:], [], "chat lines after a scan with chatOnDone = false")
    # ahTint off: no vendor labels on Blizzard's rows
    fire_setting(c, "ahTint", False)
    c.ah_blizzard_search(4306)
    c.advance(1)
    c.ah_show_commodity(4306)
    c.advance(0.5)
    labels = [_strip(fs._text) for fr, rd in c.ah_rows("commodity") for fs in c.regions(fr, "FontString") if fs._where and fs._text and _strip(fs._text).strip()]
    ctx.eq(labels, [], "AH row labels with ahTint = false")
    c.close_ah()
    # dockToAH on (default): docked again next time
    fire_setting(c, "dockToAH", True)
    c.open_ah()
    c.advance(0.5)
    ctx.check(docked(), "window not docked to the AH with dockToAH = true")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
# skill-up planner (SPEC2 2). The built-in recipe table of the profession under test is replaced by a small controlled
# one (real spell/item IDs) so every number below is computed by hand; tailoring_data_rows checks the real table.
CHAR_TAILOR = SECOND_CHAR                     # the Tailoring + Enchanting character
TAILOR_LEARNED = {   # in the character's book (the mock's GetRecipeInfo colours come from y / g)
    2963: {"name": "Bolt of Linen Cloth", "skillLine": 197, "output": 2996, "reagents": [[2589, 2]], "y": 25, "g": 50},
    2387: {"name": "Linen Cloak", "skillLine": 197, "output": 2570, "reagents": [[2320, 1], [2996, 1]], "y": 35, "g": 60},
    12044: {"name": "Simple Linen Pants", "skillLine": 197, "output": 10045, "reagents": [[2320, 1], [2996, 1]], "y": 40, "g": 60},
    8776: {"name": "Linen Belt", "skillLine": 197, "output": 7026, "reagents": [[2320, 1], [2996, 1]], "y": 50, "g": 85},
}
TAILOR_ROWS = """local WC = ...
WC.RECIPES = type(WC.RECIPES) == "table" and WC.RECIPES or {}
rawset(WC.RECIPES, 197, {
  [2963]  = { s = 1,  y = 25, g = 50, o = 2996,  r = { 2589, 2 }, t = "t" },           -- learned
  [2387]  = { s = 15, y = 35, g = 60, o = 2570,  r = { 2320, 1, 2996, 1 }, t = "t" },  -- learned
  [12044] = { s = 15, y = 40, g = 60, o = 10045, r = { 2320, 1, 2996, 1 }, t = "t" },  -- learned
  [8776]  = { s = 15, y = 50, g = 85, o = 7026,  r = { 2320, 1, 2996, 1 }, t = "t" },  -- learned
  [3915]  = { s = 30, y = 35, g = 60, o = 4344,  r = { 2320, 1, 2996, 1 }, t = "t" },  -- Brown Linen Shirt: trainer, not learned
  [2385]  = { s = 50, y = 70, g = 95, o = 2568,  r = { 2320, 1, 2996, 1 }, t = "t" },  -- Brown Linen Vest: trainer, skill 50
  [2389]  = { s = 40, y = 55, g = 80, o = 2572,  r = { 2320, 1, 2996, 2 }, t = "i" },  -- Red Linen Robe: taught by a pattern
})"""
TAILOR_LISTINGS = {
    2589: [(30, 10), (35, 1000)],    # Linen Cloth
    2996: [(40, 10), (45, 1000)],    # Bolt of Linen Cloth (reagent and product; AH 40 x 0.95 = 38 < vendor 40)
    2570: [(30, 5)],                 # Linen Cloak: AH 30 x 0.95 = 28.5 > vendor 11
    4344: [(60, 5)],                 # Brown Linen Shirt: AH 60 x 0.95 = 57 > its 50 cost -> negative net
}


def tailoring_setup(ctx, rank=20, scan=True, keep_open=False, rows=None):
    c = ctx.client(char=CHAR_TAILOR, login=False)
    c.set_professions([(197, rank, 75)])          # Tailoring only (no Enchanting -> no disenchant offsets)
    c.set_recipes(TAILOR_LEARNED)
    c.eval(rows or TAILOR_ROWS, c.WC)
    c.login()
    c.open_profession(197)
    c.advance(3)
    ck = c.WC.CharKey(c.WC)
    recs = c.g("GetrichDB").recipes[ck]
    ctx.require(recs is not None and recs[2963] is not None, "Tailoring recipes were not captured")
    if not keep_open:
        c.close_profession()
        c.advance(1)
    if scan:
        for iid, rows in TAILOR_LISTINGS.items():
            c.set_listings(iid, rows)
        c.g("GetrichDB").autoScan = False
        c.open_ah()
        c.advance(1)
        ok, _ = start_scan(c, "craft", 900)
        ctx.require(ok, "Scanner:Start('craft') refused")
        c.advance(1)
    return c, ck


def chance_of(c, row, skill, current=None):
    return multi(c.eval("local LV, row, skill, cur = ...; return LV:Chance(row, skill, cur)", c.WC.Leveling, c.table(row), skill, current), 3)


@scenario("leveling_chance", "SPEC2 2: skill-up chance: orange 1, yellow/green (g - skill) / (g - y), grey 0, green from floor((y+g)/2), red below the learn skill")
def s_level_chance(ctx):
    c = ctx.client()
    bolt = {"s": 1, "y": 25, "g": 50}
    for skill, (ch, color) in {1: (1.0, "orange"), 24: (1.0, "orange"), 25: (1.0, "yellow"), 30: (0.8, "yellow"),
                               36: (0.56, "yellow"), 37: (0.52, "green"), 49: (0.04, "green"), 50: (0.0, "grey"), 80: (0.0, "grey")}.items():
        got = chance_of(c, bolt, skill)
        ctx.eq((round(fnum(got[0]), 9), got[1]), (ch, color), "Chance(Bolt of Linen 1/25/50, %d)" % skill)
    bag = {"s": 1, "y": 30, "g": 65}
    ctx.eq(round(fnum(chance_of(c, bag, 47)[0]), 7), 0.5142857, "Chance(y30 g65, 47) = 18 / 35")
    flat = {"s": 1, "y": 40, "g": 40}            # yellow == grey: orange right up to grey
    ctx.eq((fnum(chance_of(c, flat, 39)[0]), fnum(chance_of(c, flat, 40)[0])), (1.0, 0.0), "Chance(y40 g40) at 39 / 40")
    shirt = {"s": 30, "y": 35, "g": 60}
    ctx.eq(fnum(chance_of(c, shirt, 29)[0]), 0.0, "Chance below the learn skill")
    # learned recipe without built-in data: the client's colour at the current skill decides orange / grey
    ctx.eq(fnum(chance_of(c, {"mt": 60, "d": 0}, 50, 50)[0]), 1.0, "captured orange (d 0) at the current skill")
    ctx.eq(fnum(chance_of(c, {"mt": 60, "d": 3}, 50, 50)[0]), 0.0, "captured grey (d 3) at the current skill")
    check_clean(ctx, c)


@scenario("leveling_candidates", "SPEC2 2: candidates = learned + trainer recipes (not pattern-taught, not above the skill), offset = best of NPC / AH / DE, negative net")
def s_level_cand(ctx):
    c, ck = tailoring_setup(ctx)
    WC = c.WC
    searched = set(c.ah_stats()["searchByItem"])
    for iid in (2589, 2996, 2570, 4344, 2568):   # 4344 / 2568: products of trainer recipes not learned yet
        ctx.check(iid in searched, "craft scan did not search %d" % iid)
    ctx.check(2572 not in searched, "craft scan searched the product of a pattern-taught recipe the character does not know (2572)")
    ctx.check(2320 not in searched, "craft scan searched Coarse Thread (unlimited vendor item)")
    LV = WC.Leveling
    lst = lua_list(LV.Candidates(LV, ck, 197, 30))
    got = [(int(e.recipeID), bool(e.learned), e.color, round(fnum(e.chance), 9), fnum(e.cost), fnum(e.offset), e.offsetKind,
            fnum(e.net), round(fnum(e.perPoint), 9)) for e in lst]
    # at skill 30 (current 20): Brown Linen Shirt (trainer, learn 30) 50 - 57 (AH) = -7 per point;
    #   Linen Cloak 50 - 28.5 (AH) = 21.5; Bolt 60 - 40 (vendor) = 20 / 0.8 = 25; Pants 50 - 23 = 27; Belt 50 - 22 = 28.
    #   Brown Linen Vest (learn 50) and Red Linen Robe (pattern) are not candidates.
    ctx.eq(got, [
        (3915, False, "orange", 1.0, 50.0, 57.0, "ah", -7.0, -7.0),
        (2387, True, "orange", 1.0, 50.0, 28.5, "ah", 21.5, 21.5),
        (2963, True, "yellow", 0.8, 60.0, 40.0, "npc", 20.0, 25.0),
        (12044, True, "orange", 1.0, 50.0, 23.0, "npc", 27.0, 27.0),
        (8776, True, "orange", 1.0, 50.0, 22.0, "npc", 28.0, 28.0),
    ], "Leveling:Candidates(Tailoring, 30)")
    shirt = [e for e in lst if int(e.recipeID) == 3915]
    if shirt:
        e = shirt[0]
        ctx.eq((e.source, int(e.learnSkill or 0), e.name, int(e.skillUps)), ("t", 30, "Brown Linen Shirt", 1), "trainer candidate fields")
    # at skill 20 the shirt can't be learned yet; at 50 the bolt is grey
    ids20 = [int(e.recipeID) for e in lua_list(LV.Candidates(LV, ck, 197, 20))]
    ctx.eq(ids20, [2963, 2387, 12044, 8776], "Leveling:Candidates(Tailoring, 20)")
    ids50 = [int(e.recipeID) for e in lua_list(LV.Candidates(LV, ck, 197, 50))]
    ctx.check(2963 not in ids50 and 2385 in ids50, "candidates at 50: bolt (grey) must be gone, Brown Linen Vest (learn 50) in: %s" % ids50)
    # the profit list shows trainer recipes only with craftShowUnlearned
    P = WC.Profit
    ids = {int(e.recipeID) for e in lua_list(first(P.Craft(P)))}
    ctx.check(not ids & {3915, 2385, 2389}, "unlearned recipes listed although craftShowUnlearned = false: %s" % sorted(ids & {3915, 2385, 2389}))
    fire_setting(c, "craftShowUnlearned", True)
    lst = lua_list(first(P.Craft(P)))
    un = {int(e.recipeID): (bool(e.learned), int(e.learnSkill or 0), bool(e.learnable), fnum(e.cost), fnum(e.best), e.bestKind) for e in lst if not e.learned}
    # Shirt: 50 vs AH 57 -> +7 (ah); Vest: 50 vs vendor 31 -> -19 (npc); the pattern recipe never
    ctx.eq(un, {3915: (False, 30, False, 50.0, 7.0, "ah"), 2385: (False, 50, False, 50.0, -19.0, "npc")}, "unlearned trainer recipes in Profit:Craft")
    ctx.eq(int(P.CraftCounts(P).unlearned), 2, "CraftCounts().unlearned")
    # a skill-up to 30 makes the shirt learnable
    c.set_skill(197, 30)
    c.advance(2)
    e = P.CraftEntry(P, 3915)
    ctx.check(e is not None and bool(e.learnable), "Brown Linen Shirt not learnable at skill 30")
    check_clean(ctx, c)


@scenario("leveling_plan", "SPEC2 2: route 20 -> 40: greedy per level, merged steps, expected crafts, mats re-costed for the total, recipes to learn")
def s_level_plan(ctx):
    c, ck = tailoring_setup(ctx)
    WC = c.WC
    LV = WC.Leveling
    plan = LV.Plan(LV, ck, 197, 20, 40)
    ctx.require(plan is not None, "Leveling:Plan returned nil")
    # 20-26 Bolt (20 per point; at 26: 20 / 0.96 = 20.83 < Cloak 21.5): 6 + 1/0.96 crafts
    # 27-29 Linen Cloak (Bolt 20 / 0.92 = 21.74 > 21.5): 3 crafts
    # 30-39 Brown Linen Shirt (learn 30, -7 per craft): 5 orange + 1 + 1/0.96 + 1/0.92 + 1/0.88 + 1/0.84
    c_bolt = 6 + 1 / 0.96
    c_shirt = 5 + 1 + 1 / 0.96 + 1 / 0.92 + 1 / 0.88 + 1 / 0.84
    exp_steps = [(20, 27, 2963, True, c_bolt, c_bolt * 60, c_bolt * 20),
                 (27, 30, 2387, True, 3.0, 150.0, 64.5),
                 (30, 40, 3915, False, c_shirt, c_shirt * 50, c_shirt * -7)]
    steps = [(int(x["from"]), int(x.to), int(x.recipeID), bool(x.learned), fnum(x.crafts), fnum(x.cost), fnum(x.net)) for x in lua_list(plan.steps)]
    ctx.eq(len(steps), 3, "plan steps: %s" % steps)
    for got, exp in zip(steps, exp_steps):
        ok = got[:4] == exp[:4] and all(abs(a - b) < 1e-6 for a, b in zip(got[4:], exp[4:]))
        ctx.check(ok, "plan step: expected %s, got %s" % (exp, got))
    # materials for the whole route, bought at once (order book walked for the total):
    #   Linen 2 x 7.0417 = 14.08 -> 15 = 10 x 30 + 5 x 35 = 475; Coarse Thread 3 + 10.455 -> 14 x 10 (vendor) = 140;
    #   Bolt 10.455 + 3 -> 14 = 10 x 40 + 4 x 45 = 580
    mats = {int(m.itemID): (int(m.qty), fnum(m.cost), m.source) for m in lua_list(plan.mats)}
    ctx.eq(mats, {2589: (15, 475.0, "ah"), 2320: (14, 140.0, "vendor"), 2996: (14, 580.0, "ah")}, "plan.mats")
    ctx.eq([int(m.itemID) for m in lua_list(plan.mats)], [2996, 2589, 2320], "plan.mats order (costliest first)")
    offset = c_bolt * 40 + 3 * 28.5 + c_shirt * 57
    ctx.eq(fnum(plan.total), 1195 - offset, "plan.total = mats 1195 - products %.6f" % offset)
    ctx.eq([(int(x.recipeID), int(x.skill), int(x.learnSkill)) for x in lua_list(plan.learn)], [(3915, 30, 30)], "plan.learn")
    ctx.eq([int(x) for x in lua_list(plan.missing)], [], "plan.missing")
    ctx.eq((int(plan["from"]), int(plan.to), int(plan.reached or 0)), (20, 40, 40), "plan from / to / reached")
    # default range: current skill -> levelTarget ("max" = the rank's cap 75; 225 when set)
    d = LV.Plan(LV, ck, 197)
    ctx.eq((int(d["from"]), int(d.to)), (20, 75), "Plan() default range with levelTarget = max")
    fire_setting(c, "levelTarget", 225)
    d = LV.Plan(LV, ck, 197)
    ctx.eq(int(d.to), 225, "Plan() target with levelTarget = 225")
    # Crafting tab, skill-up mode: lists the candidates and the route
    fire_setting(c, "levelTarget", "max")
    c.g("GetrichDB").craftMode = "level"
    c.slash("/gr craft")
    c.advance(0.5)
    t = visible_tab_texts(c)
    for need in ("Bolt of Linen Cloth", "Linen Cloak"):
        ctx.check(any(need in x for x in t), "skill-up mode (current list) does not list %r" % need)
    ctx.check(not any("Brown Linen Shirt" in x for x in t), "the current list at 20 shows the shirt (learn skill 30)")
    c.g("GetrichDB").craftLevelView = "plan"        # route view: the three steps, the shirt to learn
    c.slash("/gr craft")
    c.advance(0.5)
    t = visible_tab_texts(c)
    for need in ("Bolt of Linen Cloth", "Linen Cloak", "Brown Linen Shirt"):
        ctx.check(any(need in x for x in t), "skill-up route view does not list %r" % need)
    check_clean(ctx, c)


def rank_key(e):
    """SPEC2 round 4 ranking: max(net, 0) / (chance x skill-ups); ties: higher chance x skill-ups, then more profit."""
    pc = fnum(e.chance) * max(int(e.skillUps or 1), 1)
    return (max(fnum(e.net), 0.0) / pc, -pc, fnum(e.net))


@scenario("leveling_offsets", "SPEC2 2: levelOffset best3 / npcde / none on Blacksmithing 85 (AH beats DE beats NPC; negative net when the AH pays more than the mats)")
def s_level_offsets(ctx):
    c = ctx.client(login=False)
    c.set_professions([(164, 85, 150), (333, 150, 225)])
    c.eval("""local WC = ...
      WC.RECIPES = type(WC.RECIPES) == "table" and WC.RECIPES or {}
      WC.RECIPES[164] = type(WC.RECIPES[164]) == "table" and WC.RECIPES[164] or {}
      WC.RECIPES[164][9983] = { s = 30, y = 65, g = 105, o = 7955, r = { 2318, 1, 2840, 10, 2880, 2, 3470, 1 }, t = "t" }
      WC.RECIPES[164][8880] = { s = 30, y = 65, g = 105, o = 7166, r = { 2318, 1, 2840, 6, 2880, 1, 3470, 1 }, t = "t" }""", c.WC)
    c.login()
    WC = c.WC
    craft_setup(ctx, c)
    ck = WC.CharKey(WC)
    LV = WC.Leveling

    def cand(rid):
        for e in lua_list(LV.Candidates(LV, ck, 164, 85)):
            if int(e.recipeID) == rid:
                return e
        return None
    # Copper Claymore at 85: green, (105 - 85) / 40 = 0.5. Cost 815; vendor 241, AH 1500 x 0.95 = 1425, DE 353.4
    # Copper Dagger: cost 475; vendor 194, not on the AH, DE 353.4
    expect = {
        "best3": {9983: (1425.0, "ah", -610.0, -1220.0), 8880: (353.4, "de", 121.6, 243.2)},
        "npcde": {9983: (353.4, "de", 461.6, 923.2), 8880: (353.4, "de", 121.6, 243.2)},
        "none": {9983: (0.0, None, 815.0, 1630.0), 8880: (0.0, None, 475.0, 950.0)},
    }
    for mode in ("best3", "npcde", "none"):
        fire_setting(c, "levelOffset", mode)
        for rid, (off, kind, net, pp) in expect[mode].items():
            e = cand(rid)
            ctx.require(e is not None, "recipe %d is not a candidate at 85" % rid)
            ctx.eq((round(fnum(e.chance), 9), e.color), (0.5, "green"), "%d chance at 85" % rid)
            got = (round(fnum(e.offset), 6), e.offsetKind, round(fnum(e.net), 6), round(fnum(e.perPoint), 6))
            ctx.eq(got, (off, kind, net, pp), "%s: %d offset / kind / net / perPoint" % (mode, rid))
        keys = [rank_key(e) for e in lua_list(LV.Candidates(LV, ck, 164, 85)) if e.net is not None]
        ctx.check(keys == sorted(keys), "%s: candidates not sorted by max(net, 0) / (chance x skill-ups), then chance, then profit" % mode)
        if mode == "best3":
            # both make money (Maul -69.375 at 87.5%%, Claymore -610 at 50%%): the surer skill-up ranks first
            order = [int(e.recipeID) for e in lua_list(LV.Candidates(LV, ck, 164, 85)) if int(e.recipeID) in (7408, 9983)]
            ctx.eq(order, [7408, 9983], "best3: order of two profitable recipes (higher chance first)")
    check_clean(ctx, c)


@scenario("craft_de_unlearned", "SPEC2 2: craft -> disenchant covers a trainer recipe the character has not learned (always; the profit list only with craftShowUnlearned)")
def s_craft_de_unlearned(ctx):
    c = ctx.client(login=False)
    recs = {int(k): dict(v) for k, v in _json("recipes.json")["chars"][DEFAULT_CHAR]["recipes"].items()}
    recs[7408]["learned"] = False                # Heavy Copper Maul: not learned, a trainer teaches it at 70
    c.set_recipes(recs)
    c.set_professions([(164, 85, 150), (333, 150, 225)])
    c.eval("""local WC = ...
      WC.RECIPES = type(WC.RECIPES) == "table" and WC.RECIPES or {}
      WC.RECIPES[164] = type(WC.RECIPES[164]) == "table" and WC.RECIPES[164] or {}
      WC.RECIPES[164][7408] = { s = 70, y = 80, g = 120, o = 6214, r = { 2318, 2, 2840, 12, 2880, 2 }, t = "t" }""", c.WC)
    c.login()
    WC = c.WC
    craft_setup(ctx, c)
    P = WC.Profit
    ck = WC.CharKey(WC)
    ctx.eq(c.g("GetrichDB").recipes[ck][7408], None, "Heavy Copper Maul must not be captured (not learned)")

    def de_craft():
        return {int(e.recipeID): e for e in lua_list(first(P.Disenchant(P))) if e.source == "craft"}
    ctx.check(9983 in de_craft(), "learned Copper Claymore missing from the craft->DE list")
    ctx.check(7408 not in {int(e.recipeID) for e in lua_list(first(P.Craft(P)))}, "unlearned Heavy Copper Maul in the profit list although craftShowUnlearned = false")
    for show in (False, True):
        fire_setting(c, "craftShowUnlearned", show)
        d = de_craft()
        ctx.check(7408 in d, "unlearned trainer recipe Heavy Copper Maul not in the craft->DE list (craftShowUnlearned = %s)" % show)
        if 7408 in d:
            e = d[7408]
            # 2 Light Leather 60 + 12 Copper Bar (4 x 50 + 8 x 60 = 680) + 2 Weak Flux 200 = 940; DE 1009.375 -> +69.375
            ctx.eq((int(e.itemID), fnum(e.buy), round(fnum(e.value), 6), round(fnum(e.gain), 6), e.status), (6214, 940.0, 1009.375, 69.375, "ok"),
                   "craft->DE entry for the unlearned Heavy Copper Maul (craftShowUnlearned = %s)" % show)
    ce = P.CraftEntry(P, 7408)
    ctx.check(ce is not None and ce.learned is False and int(ce.learnSkill) == 70 and bool(ce.learnable),
              "Profit:CraftEntry(7408): learned false, learnSkill 70, learnable at 85")
    c.slash("/gr de")
    c.advance(0.5)
    ctx.check(any("Heavy Copper Maul" in x for x in c.texts(clip=True)), "Disenchant tab does not list the unlearned Heavy Copper Maul")
    check_clean(ctx, c)


def recipe_label(c, rid):
    """(label frame, stripped text) of a recipe row in the open ProfessionsFrame (scrolls to it)."""
    sb = c.eval("return ProfessionsFrame.CraftingPage.RecipeList.ScrollBox")
    idx = c.eval("""local sb, rid = ...
      for i, n in ipairs(sb:GetDataProvider():Flatten()) do local d = n:GetData(); if d.recipeInfo and d.recipeInfo.recipeID == rid then return i end end""", sb, rid)
    if idx is None:
        return None, None
    sb.ScrollToElementDataIndex(sb, idx)
    for fr, r in c.recipe_rows():
        if r == rid:
            f = fr.wcProfit
            if f is None or not f.IsShown(f):
                return f, ""
            return f, _strip(f.text._text or "")
    return None, None


@scenario("profession_skillup_badges", "SPEC2 3: badges on the 3 learned recipes with the lowest cost per skill point + tooltip; follow skill-ups; profLevelMark / profOverlay off")
def s_badges(ctx):
    c, ck = tailoring_setup(ctx, keep_open=False)
    c.close_ah()
    c.open_profession(197)
    c.advance(2)
    mark = {"enUS": "Lv%d", "zhCN": "升%d", "zhTW": "升%d"}[ctx.locale]

    def marks():
        out = {}
        for rid in (2963, 2387, 12044, 8776):
            f, t = recipe_label(c, rid)
            m = [i for i in (1, 2, 3) if t and t.startswith(mark % i)]
            out[rid] = m[0] if m else None
        return out
    # at 20: Bolt 20 per point, Cloak 21.5, Pants 27 (Belt 28: no badge; the unlearned shirt is not in the book)
    ctx.eq(marks(), {2963: 1, 2387: 2, 12044: 3, 8776: None}, "badges at skill 20")
    f, t = recipe_label(c, 2963)
    tip = "\n".join(c.hover(f)) if f is not None else ""
    ctx.check("100%" in tip and ("20" + {"enUS": "c", "zhCN": "铜", "zhTW": "銅"}[ctx.locale]) in tip,
              "badge tooltip should give ~20c per skill point at 100%%:\n%s" % tip)
    # skill-up to 27: Cloak 21.5 < Bolt 20 / 0.92 = 21.74 < Pants 27
    c.set_skill(197, 27)
    c.advance(2)
    ctx.eq(marks(), {2963: 2, 2387: 1, 12044: 3, 8776: None}, "badges after the skill-up to 27")
    f, t = recipe_label(c, 2963)
    tip = "\n".join(c.hover(f)) if f is not None else ""
    ctx.check("92%" in tip, "badge tooltip of the bolt at 27 should show the 92%% chance:\n%s" % tip)
    fire_setting(c, "profLevelMark", False)
    c.advance(1)
    ctx.eq(marks(), {2963: None, 2387: None, 12044: None, 8776: None}, "badges with profLevelMark = false")
    fire_setting(c, "profLevelMark", True)
    fire_setting(c, "profOverlay", False)
    c.advance(1)
    shown = [rid for rid in (2963, 2387, 12044, 8776) if (recipe_label(c, rid)[1] or "").strip()]
    ctx.eq(shown, [], "labels shown with profOverlay = false")
    # a maxed profession gets no badges
    fire_setting(c, "profOverlay", True)
    c.set_skill(197, 75)
    c.advance(2)
    ctx.eq(marks(), {2963: None, 2387: None, 12044: None, 8776: None}, "badges when the profession is maxed (75/75)")
    check_clean(ctx, c)


@scenario("recipe_table_data", "SPEC2 1: DataRecipes.lua matches every recipe captured from the client (y / g / output / reagents), trainer vs pattern, skill-up rule")
def s_recipe_data(ctx):
    c = ctx.client()
    WC = c.WC
    R = WC.RECIPES
    ctx.require(R is not None, "WC.RECIPES missing")
    size = os.path.getsize(os.path.join(os.path.dirname(HERE), "Getrich", "DataRecipes.lua"))
    ctx.check(size <= 260 * 1024, "DataRecipes.lua is %d KB (spec: about 250 KB)" % (size // 1024))
    su = WC.SKILLUP
    ctx.check(su is not None and su.formula == "classic" and str(su.source or "").startswith("http"), "WC.SKILLUP {formula = 'classic', source = url} missing")
    for sl in (171, 164, 333, 202, 165, 197, 185, 129, 186):
        n = len(lua_keys(R[sl])) if R[sl] is not None else 0
        ctx.check(n > 0, "WC.RECIPES[%d] is empty" % sl)
    # every recipe the two fixture characters know (captured from the client, thresholds from SkillLineAbility)
    checked, bad = 0, []
    for guid, ch in _json("recipes.json")["chars"].items():
        for rid, r in ch["recipes"].items():
            if r.get("y") is None:
                continue
            rid, sl = int(rid), r["skillLine"]
            row = R[sl][rid] if R[sl] is not None else None
            if row is None:
                bad.append("%d %s: not in WC.RECIPES[%d]" % (rid, r["name"], sl))
                continue
            flat = lua_list(row.r)
            got = (row.y, row.g, row.o, sorted((int(flat[i]), int(flat[i + 1])) for i in range(0, len(flat) - 1, 2)))
            want = (r["y"], r["g"], r.get("output"), sorted((int(a), int(b)) for a, b in r["reagents"]))
            if got != want:
                bad.append("%d %s: %s, client %s" % (rid, r["name"], got, want))
            checked += 1
    ctx.check(checked >= 250, "only %d captured recipes checked" % checked)
    ctx.check(not bad, "WC.RECIPES differs from the client for %d recipes: %s" % (len(bad), bad[:8]))
    # spot checks: trainer / auto-learned vs taught by a pattern item
    b = R[197][2963]
    ctx.eq((b.s, b.y, b.g, b.o, [int(x) for x in lua_list(b.r)], b.t), (1, 25, 50, 2996, [2589, 2], "t"), "Bolt of Linen Cloth row")
    rl = R[197][2389]
    ctx.eq((rl.t, rl.ri), ("i", 2598), "Red Linen Robe: taught by Pattern: Red Linen Robe (2598)")
    # row shape: even reagent list, t in t/i/?, a recipe item for 'i' and none for 't', yields ordered, learn skill <= 300
    shape = c.eval("""local R = ...
      local bad = {}
      for sl, rows in pairs(R) do
        for id, row in pairs(rows) do
          local why
          if type(row.r) ~= "table" or #row.r == 0 or #row.r % 2 ~= 0 then why = "reagents" end
          if not (row.t == "t" or row.t == "i" or row.t == "?") then why = "t" end
          if (row.t == "i" and row.ri == nil) or (row.t == "t" and row.ri ~= nil) then why = "ri" end   -- '?' may name a missing item
          if not (type(row.s) == "number" and row.s <= 300 and type(row.y) == "number" and type(row.g) == "number" and row.y <= row.g) then why = "s/y/g" end
          if (row.n1 or 1) > (row.n2 or row.n1 or 1) then why = "yield" end
          if why and #bad < 10 then bad[#bad + 1] = sl .. ":" .. id .. " " .. why end
        end
      end
      return table.concat(bad, ", ")""", R)
    ctx.eq(shape, "", "malformed WC.RECIPES rows")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
# round 3 (SPEC2 8): trainer window capture -> exact learn skill + training cost in the planner; lazy recipe data
# the shirt and the vest with the data's guessed learn skill (se = 1: s = yellow), as DataRecipes ships trainer recipes
TAILOR_ROWS_GUESS = TAILOR_ROWS.replace(
    '[3915]  = { s = 30, y = 35, g = 60, o = 4344,  r = { 2320, 1, 2996, 1 }, t = "t" }',
    '[3915]  = { s = 35, y = 35, g = 60, o = 4344,  r = { 2320, 1, 2996, 1 }, t = "t", se = 1 }').replace(
    '[2385]  = { s = 50, y = 70, g = 95, o = 2568,  r = { 2320, 1, 2996, 1 }, t = "t" }',
    '[2385]  = { s = 70, y = 70, g = 95, o = 2568,  r = { 2320, 1, 2996, 1 }, t = "t", se = 1 }')
assert TAILOR_ROWS_GUESS.count("se = 1") == 2
TAILOR_TRAINER = [   # what the trainer window offers (filtered by the client's type filter)
    {"spellID": 2963, "itemID": 2996, "req": 1, "cost": 10, "learned": True},
    {"spellID": 2387, "itemID": 2570, "req": 15, "cost": 50, "learned": True},
    {"spellID": 12044, "itemID": 10045, "req": 15, "cost": 25, "learned": True},
    {"spellID": 3915, "itemID": 4344, "req": 30, "cost": 150},
    {"spellID": 2385, "itemID": 2568, "req": 50, "cost": 300, "nameDelay": 0.6},   # name arrives later (TRAINER_SERVICE_INFO_NAME_UPDATE)
    {"spellID": 0, "name": "Journeyman Tailoring", "req": 50, "cost": 500, "step": True},
]
for _i, _e in enumerate(TAILOR_TRAINER):
    if _e["spellID"]:
        _e["teachSpellID"] = 2000000 + _e["spellID"]   # the trainer's "teach" spell: not a recipe of the line
TRAINER_EXPECT = {2963: (1, 10), 2387: (15, 50), 12044: (15, 25), 3915: (30, 150), 2385: (50, 300)}


def visit_trainer(c, tooltip="item", late_names=True):
    c.set_trainer_filter(available=True, unavailable=False, used=False)   # the user shows only what they can learn now
    services = TAILOR_TRAINER if late_names else [{k: v for k, v in e.items() if k != "nameDelay"} for e in TAILOR_TRAINER]
    c.open_trainer(990010, "Tailoring Trainer", 197, services, tooltip=tooltip)
    c.advance(3)


def trainer_db(c):
    t = c.g("GetrichDB").trainer
    line = t[197] if t is not None else None
    return {int(k): (line[k].s, line[k].cost) for k in lua_keys(line)} if line is not None else {}


@scenario("trainer_capture", "SPEC2 8: trainer window -> db.trainer[skillLine][spellID] = { s, cost } for every service (also the ones the filter hides), filter restored")
def s_trainer_capture(ctx):
    for mode in ("item", "spell", "teach", "none"):   # what C_TooltipInfo.GetTrainerService gives is not in the UI source
        c, ck = tailoring_setup(ctx, rows=TAILOR_ROWS_GUESS, scan=False)
        WC = c.WC
        visit_trainer(c, tooltip=mode)
        got = trainer_db(c)
        ctx.eq({k: v for k, v in got.items() if k in TRAINER_EXPECT}, TRAINER_EXPECT, "db.trainer[197] (tooltip mode %s)" % mode)
        ctx.check(0 not in got, "the profession-rank service (Journeyman) was stored as a recipe (mode %s)" % mode)
        ctx.check(not [k for k in got if k >= 2000000], "teaching spell ids stored as recipes (mode %s): %s" % (mode, sorted(got)))
        ctx.eq(c.trainer_filter(), {"available": True, "unavailable": False, "used": False}, "the user's trainer filter after the capture (mode %s)" % mode)
        ctx.eq(multi(WC.Recipes.TrainerInfo(WC.Recipes, 197, 3915), 2), (30, 150), "Recipes:TrainerInfo(197, Brown Linen Shirt) (mode %s)" % mode)
        ctx.eq(multi(WC.Recipes.TrainerInfo(WC.Recipes, 197, 2389), 2), (None, None), "TrainerInfo of a recipe never seen at a trainer")
        c.close_trainer()
        c.advance(1)
        check_clean(ctx, c, "tooltip mode " + mode)
    # a class trainer is not a profession trainer: nothing is stored
    c, ck = tailoring_setup(ctx, rows=TAILOR_ROWS_GUESS, scan=False)
    c.open_trainer(990011, "Warrior Trainer", 197, [{"spellID": 0, "name": "Battle Shout", "cost": 100, "level": 12},
                                                    {"spellID": 0, "name": "Rend", "cost": 200, "level": 10}], tradeskill=False)
    c.advance(3)
    c.close_trainer()
    c.advance(1)
    ctx.eq(trainer_db(c), {}, "db.trainer after visiting a class trainer")
    check_clean(ctx, c, "class trainer")
    # account-wide data: kept in the SavedVariables
    c, ck = tailoring_setup(ctx, rows=TAILOR_ROWS_GUESS, scan=False)
    visit_trainer(c, late_names=False)
    text = c.logout_sv()
    ctx.check("trainer" in text and "= 150" in text.replace("=150", "= 150"), "db.trainer is not saved")


@scenario("trainer_plan", "SPEC2 8: the planner uses the trainer's exact learn skill (learnGuess cleared) and adds the training cost to the route total")
def s_trainer_plan(ctx):
    c, ck = tailoring_setup(ctx, rows=TAILOR_ROWS_GUESS)
    WC = c.WC
    LV = WC.Leveling
    c_bolt = 6 + 1 / 0.96
    yel = 1 + 1 / 0.96 + 1 / 0.92 + 1 / 0.88 + 1 / 0.84          # 35..39 at (60 - L) / 25
    # before the trainer visit the shirt's learn skill is the data's guess (35 = yellow): Cloak 27 -> 35, shirt 35 -> 40
    shirt = [e for e in lua_list(LV.Candidates(LV, ck, 197, 35)) if int(e.recipeID) == 3915]
    ctx.check(shirt and bool(shirt[0].learnGuess) and int(shirt[0].learnSkill) == 35, "before the trainer: shirt learnGuess with learn skill 35")
    ctx.check(not [e for e in lua_list(LV.Candidates(LV, ck, 197, 30)) if int(e.recipeID) == 3915], "before the trainer: shirt a candidate at 30 (guessed learn skill 35)")
    plan = LV.Plan(LV, ck, 197, 20, 40)
    steps = [(int(x["from"]), int(x.to), int(x.recipeID)) for x in lua_list(plan.steps)]
    ctx.eq(steps, [(20, 27, 2963), (27, 35, 2387), (35, 40, 3915)], "plan steps with the guessed learn skill")
    learn = [(int(x.recipeID), int(x.skill), int(x.learnSkill), x.cost, bool(x.learnGuess)) for x in lua_list(plan.learn)]
    ctx.eq(learn, [(3915, 35, 35, None, True)], "plan.learn before the trainer (cost unknown, guessed)")
    ctx.eq((fnum(plan.learnCost or 0), int(plan.learnCostUnknown or 0)), (0.0, 1), "learnCost / learnCostUnknown before the trainer")
    offset0 = c_bolt * 40 + 8 * 28.5 + yel * 57
    ctx.eq(fnum(plan.total), 1195 - offset0, "plan.total before the trainer (mats 1195 - products %.6f, training unknown)" % offset0)
    # the trainer: shirt at 30 for 1s 50c
    c.close_ah()
    visit_trainer(c, late_names=False)
    c.close_trainer()
    c.advance(1)
    shirt = [e for e in lua_list(LV.Candidates(LV, ck, 197, 30)) if int(e.recipeID) == 3915]
    ctx.check(shirt and not shirt[0].learnGuess and int(shirt[0].learnSkill) == 30, "after the trainer: shirt a candidate at 30, learnGuess cleared")
    plan = LV.Plan(LV, ck, 197, 20, 40)
    steps = [(int(x["from"]), int(x.to), int(x.recipeID)) for x in lua_list(plan.steps)]
    ctx.eq(steps, [(20, 27, 2963), (27, 30, 2387), (30, 40, 3915)], "plan steps with the trainer's learn skill")
    learn = [(int(x.recipeID), int(x.skill), int(x.learnSkill), fnum(x.cost), bool(x.learnGuess)) for x in lua_list(plan.learn)]
    ctx.eq(learn, [(3915, 30, 30, 150.0, False)], "plan.learn after the trainer")
    ctx.eq((fnum(plan.learnCost), int(plan.learnCostUnknown or 0)), (150.0, 0), "learnCost / learnCostUnknown after the trainer")
    offset1 = c_bolt * 40 + 3 * 28.5 + (5 + yel) * 57
    ctx.eq(fnum(plan.total), 1195 - offset1 + 150, "plan.total = mats 1195 - products %.6f + training 150" % offset1)
    # the vest: exact learn skill 50 instead of the guessed 70
    ids50 = [int(e.recipeID) for e in lua_list(LV.Candidates(LV, ck, 197, 50))]
    ctx.check(2385 in ids50, "Brown Linen Vest not a candidate at 50 after the trainer (guess was 70)")
    check_clean(ctx, c)


def lua_heap_kb(lua):
    return float(lua.eval("(function() collectgarbage('collect'); collectgarbage('collect'); return collectgarbage('count') end)()"))


@scenario("recipes_lazy_data", "SPEC2 8: recipe data stays encoded until a skill line is read (memory bound), decodes fast, RECIPE_LINES iteration, consumers still find recipes")
def s_lazy(ctx):
    from lupa import lua51
    path = os.path.join(os.path.dirname(HERE), "Getrich", "DataRecipes.lua")
    src = open(path, encoding="utf-8").read()
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    WCt = lua.table()
    load = lua.eval("function(src, WC) local f, e = loadstring(src, '=DataRecipes.lua'); if not f then error(e) end; f('Getrich', WC) end")
    base = lua_heap_kb(lua)
    load(src, WCt)                       # compile + run like the client; the compiled chunk is garbage afterwards
    after = lua_heap_kb(lua)
    ctx.note("Lua heap of DataRecipes.lua after load: %.0f KB" % (after - base))
    ctx.check(after - base <= 300, "DataRecipes.lua uses %.0f KB of Lua memory after load (limit 300 KB until a profession is used)" % (after - base))
    lines = [int(x) for x in lua_list(WCt.RECIPE_LINES)]
    ctx.check(lines == sorted(lines) and {171, 164, 333, 202, 165, 197, 185, 129, 186} <= set(lines), "WC.RECIPE_LINES: %s" % lines)
    R = WCt.RECIPES
    ctx.eq([k for k in R.keys()], [], "pairs(WC.RECIPES) before any line was read")
    rawget = lua.eval("rawget")
    ctx.eq(WCt.RecipeLine(2963) if WCt.RecipeLine else None, 197, "WC.RecipeLine(Bolt of Linen Cloth)")
    ctx.eq(rawget(R, 197), None, "WC.RecipeLine decoded the Tailoring line")
    timer = lua.eval("function(R, sl) local t0 = os.clock(); local rows = R[sl]; local dt = os.clock() - t0; local n = 0; for _ in pairs(rows or {}) do n = n + 1 end; return dt, n end")
    worst, total = (0, None), 0
    for sl in lines:
        dt, n = timer(R, sl)
        total += n
        ctx.check(n > 0, "WC.RECIPES[%d] decodes to nothing" % sl)
        if dt > worst[0]:
            worst = (dt, sl)
        ctx.check(lua.eval("rawequal")(R[sl], rawget(R, sl)), "WC.RECIPES[%d] is not cached after the first read" % sl)
    ctx.note("decoded %d recipes in %d lines; slowest line %s: %.1f ms; heap with every line decoded: %.0f KB"
             % (total, len(lines), worst[1], worst[0] * 1000, lua_heap_kb(lua) - base))
    ctx.check(worst[0] < 0.020, "decoding skill line %s took %.1f ms (limit 20 ms)" % (worst[1], worst[0] * 1000))
    ctx.check(total >= 2000, "only %d recipes decoded" % total)
    # in the addon: after login only lines something asked for are decoded; consumers find recipes in other lines
    c = ctx.client()
    WC = c.WC
    decoded = lambda: sorted(int(sl) for sl in lua_list(WC.RECIPE_LINES) if c.eval("local R, sl = ...; return rawget(R, sl) ~= nil", WC.RECIPES, sl))
    d0 = decoded()
    ctx.check(not set(d0) & {171, 202, 165, 197}, "lines of professions the character does not have were decoded at login: %s" % d0)
    a = WC.Profit.StaticRecipe(WC.Profit, 2963)                 # no skill line given: found via WC.RecipeLine
    ctx.check(a is not None and a.p == 197 and int(a.o) == 2996, "Profit:StaticRecipe(Bolt of Linen Cloth) without a skill line")
    ctx.eq(decoded(), sorted(set(d0) | {197}), "lines decoded after Profit:StaticRecipe(2963)")
    a = WC.Profit.StaticRecipe(WC.Profit, 3275)                 # Linen Bandage (First Aid)
    ctx.check(a is not None and a.p == 129, "Profit:StaticRecipe(Linen Bandage) without a skill line")
    st = c.eval("local WC = ...; local T = WC.UICraft or (WC.UI and WC.UI.tabs and WC.UI.tabs.craft); if T and T.StaticRecipe then return T:StaticRecipe(nil, 2963) end", WC)
    ctx.check(st is not None, "UICraft Tab:StaticRecipe(nil, Bolt of Linen Cloth) found nothing")
    check_clean(ctx, c)


# ------------------------------------------------------------------------------------------------------------------
# round 4 (review fixes)
def harmonic(lo, hi, g, y):
    """expected crafts for levels lo..hi-1 at chance (g - L) / (g - y) (1 below y)."""
    return sum(1.0 if L < y else (g - y) / (g - L) for L in range(lo, hi))


@scenario("leveling_skillups_zero", "review: a recipe captured with numSkillUps = 0 never hangs Leveling:Plan (counted as 1); profitable recipes tie at 0 -> surer skill-up, then more profit; long routes priced past the kept listings")
def s_level_su0(ctx):
    learned = dict(TAILOR_LEARNED)
    learned[3755] = {"name": "Linen Bag", "skillLine": 197, "output": 4238, "reagents": [[2320, 3], [2996, 3]], "y": 30, "g": 65, "su": 0}
    rows = TAILOR_ROWS.replace("})", '  [3755]  = { s = 1, y = 30, g = 65, o = 4238, r = { 2320, 3, 2996, 3 }, t = "t" },\n})')
    c = ctx.client(char=CHAR_TAILOR, login=False)
    c.set_professions([(197, 20, 75)])
    c.set_recipes(learned)
    c.eval(rows, c.WC)
    c.login()
    c.open_profession(197); c.advance(3); c.close_profession(); c.advance(1)
    WC = c.WC
    ck = WC.CharKey(WC)
    ctx.eq(c.g("GetrichDB").recipes[ck][3755].su, 0, "captured numSkillUps of Linen Bag")
    listings = dict(TAILOR_LISTINGS)
    listings[2996] = [(40, 7), (45, 300), (50, 1254)]   # 1561 bolts listed, the scanner keeps the cheapest 307
    for iid, r in listings.items():
        c.set_listings(iid, r)
    c.g("GetrichDB").autoScan = False
    c.open_ah(); c.advance(1)
    start_scan(c, "craft", 900)
    c.advance(1)
    LV = WC.Leveling
    bag = [e for e in lua_list(LV.Candidates(LV, ck, 197, 20)) if int(e.recipeID) == 3755]
    ctx.check(bag and int(bag[0].skillUps) == 1 and fnum(bag[0].perPoint) == -50.0,
              "Linen Bag candidate at 20: skillUps 1 and -50 per point (150 mats - 200 vendor), got %s" % ((int(bag[0].skillUps), fnum(bag[0].perPoint)) if bag else None,))
    ok, plan, ticks, secs = multi(c.eval("""local LV, ck = ...
      local n = 0
      debug.sethook(function() n = n + 1; if n > 20000 then debug.sethook(); error("instruction guard: Leveling:Plan runs away") end end, "", 1000)
      local t0 = os.clock()
      local ok, plan = pcall(LV.Plan, LV, ck, 197, 10, 75)
      debug.sethook()
      return ok, plan, n, os.clock() - t0""", LV, ck), 4)
    ctx.note("Leveling:Plan(197, 10, 75): %.0f ms, %d k instructions" % (secs * 1000, ticks))
    ctx.require(ok, "Leveling:Plan(197, 10, 75) did not finish: %s" % plan)
    ctx.check(secs < 1.0, "Leveling:Plan took %.2f s" % secs)
    # 10-30 Linen Bag (-50, orange); 30: Bag and Shirt both certain -> more profit (Bag); 31-47 Shirt (more likely than the
    # Bag: (60-L)/25 > (65-L)/35 below 47.5); 48-64 Bag; 65-74 Brown Linen Vest (19 per point, cheapest positive)
    c_bag1 = 21.0
    c_shirt = harmonic(31, 48, 60, 35)
    c_bag2 = harmonic(48, 65, 65, 30)
    c_vest = harmonic(65, 75, 95, 70)
    exp = [(10, 31, 3755, c_bag1), (31, 48, 3915, c_shirt), (48, 65, 3755, c_bag2), (65, 75, 2385, c_vest)]
    got = [(int(x["from"]), int(x.to), int(x.recipeID), fnum(x.crafts)) for x in lua_list(plan.steps)]
    ok_steps = len(got) == len(exp) and all(g[:3] == e[:3] and abs(g[3] - e[3]) < 1e-6 for g, e in zip(got, exp))
    ctx.check(ok_steps, "plan 10 -> 75 steps:\n   expected %s\n   got      %s" % (exp, got))
    ctx.eq([(int(x.recipeID), int(x.skill)) for x in lua_list(plan.learn)], [(3915, 31), (2385, 65)], "plan.learn")
    bags, shirts, vests = c_bag1 + c_bag2, c_shirt, c_vest
    n_bolt = math.ceil(3 * bags + shirts + vests - 1e-9)
    n_thread = math.ceil(3 * bags + shirts + vests - 1e-9)
    mats = {int(m.itemID): (int(m.qty), fnum(m.cost), m.source) for m in lua_list(plan.mats)}
    # bolts: 7 x 40 + 300 x 45 kept; the rest priced at the dearest kept price 45 (1561 listed >= need)
    bolt_cost = 7 * 40 + (n_bolt - 7) * 45
    ctx.eq(mats.get(2996), (n_bolt, float(bolt_cost), "ah"), "plan.mats Bolt of Linen Cloth (%d > 307 kept)" % n_bolt)
    ctx.eq(mats.get(2320), (n_thread, float(n_thread * 10), "vendor"), "plan.mats Coarse Thread")
    offset = bags * 200 + shirts * 57 + vests * 31
    ctx.check(plan.total is not None, "plan.total is nil for a route deeper than the kept listings")
    if plan.total is not None:
        ctx.eq(fnum(plan.total), bolt_cost + n_thread * 10 - offset, "plan.total (training costs unknown: %s)" % plan.learnCostUnknown)
    check_clean(ctx, c)


@scenario("cost_beyond_kept_listings", "review: CostForAny prices past the ~250 kept units at the dearest kept price when enough are listed ('est'); 'short' only when fewer are listed")
def s_cost_deep(ctx):
    c = ctx.client()
    WC = c.WC
    c.set_listings(2996, [(40, 7), (45, 300), (50, 1254)])
    c.g("GetrichDB").autoScan = False
    c.open_ah(); c.advance(1)
    WC.Store.SetWatch(WC.Store, 2996, True)
    start_scan(c, "history", 120)
    c.advance(1)
    r = c.g("GetrichDB").results[2996]
    ctx.require(r is not None and r.status == "listed", "Bolt of Linen Cloth was not scanned")
    ctx.eq(([[int(e[1]), int(e[2])] for e in lua_list(r.entries)], int(r.avail)), ([[40, 7], [45, 300]], 1561), "kept entries / avail")
    def cost(q):
        v = multi(WC.CostForAny(WC, 2996, q), 2)
        return (None if v[0] is None else fnum(v[0]), v[1])
    ctx.eq(cost(300), (280 + 293 * 45.0, "ok"), "CostForAny(300): inside the kept listings")
    ctx.eq(cost(909), (280 + 902 * 45.0, "est"), "CostForAny(909): 307 kept + 602 at 45")
    ctx.eq(cost(1561), (280 + 1554 * 45.0, "est"), "CostForAny(1561): everything listed")
    ctx.eq(cost(1600), (None, "short"), "CostForAny(1600): more than listed")
    m = WC.Profit.MatCost(WC.Profit, 2996, 909)
    ctx.eq((fnum(m.cost), m.source, bool(m.est)), (280 + 902 * 45.0, "ah", True), "Profit:MatCost(Bolt, 909)")
    # crates / writs keep the exact order book
    ctx.eq(multi(WC.CostFor(WC, 2996, 909), 2), (None, "short"), "CostFor(909) stays exact")
    check_clean(ctx, c)


@scenario("leveling_auto_learned", "review: recipes learned automatically with the profession (a = 1) are never 'to learn' and cost no training")
def s_level_auto(ctx):
    rows = TAILOR_ROWS.replace('[3915]  = { s = 30, y = 35, g = 60, o = 4344,  r = { 2320, 1, 2996, 1 }, t = "t" }',
                               '[3915]  = { s = 30, y = 35, g = 60, o = 4344,  r = { 2320, 1, 2996, 1 }, t = "t", a = 1 }')
    assert "a = 1" in rows
    c, ck = tailoring_setup(ctx, rows=rows)
    WC = c.WC
    LV = WC.Leveling
    plan = LV.Plan(LV, ck, 197, 20, 40)
    steps = [(int(x["from"]), int(x.to), int(x.recipeID)) for x in lua_list(plan.steps)]
    ctx.eq(steps, [(20, 27, 2963), (27, 30, 2387), (30, 40, 3915)], "plan steps (shirt automatic at 30)")
    ctx.eq([int(x.recipeID) for x in lua_list(plan.learn)], [], "plan.learn (nothing to learn at a trainer)")
    ctx.eq((fnum(plan.learnCost or 0), int(plan.learnCostUnknown or 0)), (0.0, 0), "learnCost / learnCostUnknown")
    c_bolt, c_shirt = 6 + 1 / 0.96, 5 + harmonic(35, 40, 60, 35)
    ctx.eq(fnum(plan.total), 1195 - (c_bolt * 40 + 3 * 28.5 + c_shirt * 57), "plan.total without training")
    # a trainer that lists it anyway changes nothing
    c.close_ah()
    visit_trainer(c, late_names=False)
    c.close_trainer(); c.advance(1)
    plan = LV.Plan(LV, ck, 197, 20, 40)
    ctx.eq(([int(x.recipeID) for x in lua_list(plan.learn)], fnum(plan.learnCost or 0)), ([], 0.0), "plan.learn / learnCost after a trainer visit")
    check_clean(ctx, c)


@scenario("craft_tab_lazy", "review: building the Crafting tab in profit mode decodes no recipe-data line itself (only Profit:Craft reads the character's own lines)")
def s_craft_lazy(ctx):
    c = ctx.client()
    WC = c.WC
    decoded = lambda: sorted(int(sl) for sl in lua_list(WC.RECIPE_LINES) if c.eval("local R, sl = ...; return rawget(R, sl) ~= nil", WC.RECIPES, sl))
    # who decodes: wrap the lazy table's __index and keep the Lua stack of every first read of a line
    c.eval("""local WC, M = ...
      local mt = getmetatable(WC.RECIPES)
      local orig = mt and mt.__index
      local traceback = debug.traceback      -- looked up here: inside the hook the caller is addon code
      M.decodes = {}
      if type(orig) == "function" then
        mt.__index = function(t, sl) M.decodes[#M.decodes + 1] = { sl = sl, tb = traceback("", 2) }; return orig(t, sl) end
      end""", WC, c.M)
    c.g("GetrichDB").craftMode = "profit"
    c.slash("/gr craft")
    c.advance(1)
    WC.Fire(WC, "PRICES_UPDATED", "test")
    c.advance(1)
    ctx.check(any(x.strip() for x in visible_tab_texts(c)), "craft tab is empty")
    mine = {int(sl) for sl in lua_keys(WC.Recipes.Professions(WC.Recipes))}
    ctx.check(set(decoded()) <= mine, "lines of professions the character does not have were decoded: %s (has %s)" % (decoded(), sorted(mine)))
    by_ui = [(int(d.sl), str(d.tb)) for d in lua_list(c.M.decodes) if "UICraft.lua" in str(d.tb) and "Profit.lua" not in str(d.tb)]
    ctx.check(not by_ui, "the Crafting tab (profit mode) decoded recipe lines itself: %s\n%s" % ([x[0] for x in by_ui], by_ui[0][1] if by_ui else ""))
    check_clean(ctx, c)


# ===================================================================================================================
# runner
# ===================================================================================================================
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--locale", default="enUS", choices=["enUS", "zhCN", "zhTW"])
    ap.add_argument("-k", default=None, help="only scenarios whose name contains this")
    ap.add_argument("-v", action="store_true", help="verbose")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--addon", default=None, help="addon folder to test instead of Getrich/ (e.g. a mutated copy)")
    ap.add_argument("--uncached", action="store_true", help="start with an empty item cache (fresh login) in every scenario")
    args = ap.parse_args()
    global UNCACHED
    UNCACHED = args.uncached
    if args.addon:
        global ADDON_TOC
        ADDON_TOC = os.path.join(os.path.abspath(args.addon), "Getrich.toc")
    if args.list:
        for name, _, doc in SCENARIOS:
            print("%-26s %s" % (name, doc))
        return 0
    results = []
    t_all = time.time()
    for name, fn, doc in SCENARIOS:
        if args.k and args.k not in name:
            continue
        ctx = Ctx(name, args.locale, args.v)
        t0 = time.time()
        status, detail = "PASS", []
        try:
            fn(ctx)
            if ctx.failures:
                status, detail = "FAIL", ctx.failures
        except Fail as e:
            status, detail = "FAIL", ctx.failures + [str(e)]
        except Exception as e:  # noqa: BLE001
            tb = traceback.format_exc().strip().split("\n")
            status, detail = "ERROR", ctx.failures + ["%s: %s" % (type(e).__name__, e)] + ["    " + l for l in tb[-6:]]
        gaps = set()
        for c in ctx.clients:
            for g in c.gaps:
                gaps.add(g["name"])
        dt = time.time() - t0
        results.append((name, status))
        print("%-5s %-26s %5.1fs  %s" % (status, name, dt, doc))
        for d in detail[:25]:
            print("        - " + str(d))
        if len(detail) > 25:
            print("        ... %d more" % (len(detail) - 25))
        for n in ctx.notes:
            print("        note: " + n)
        if gaps and (args.v or status != "PASS"):
            print("        mock gaps (documented API the mock does not implement): " + ", ".join(sorted(gaps)))
    n_pass = sum(1 for _, s in results if s == "PASS")
    print("\n%d scenarios: %d PASS, %d FAIL, %d ERROR  (%.1fs, locale %s)" % (
        len(results), n_pass, sum(1 for _, s in results if s == "FAIL"), sum(1 for _, s in results if s == "ERROR"),
        time.time() - t_all, args.locale))
    return 0 if n_pass == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
