#!/usr/bin/env python3
"""Check the hand-kept game data of the addon (Data.lua, Writs.lua, Util.lua) against the live game.

    python3 tools/verify_game_data.py --db cache/1.60.1.70938 [--download --build 1.60.1.70938] [--wowhead]

--db DIR     wago.tools CSV exports of the client tables: ItemSparse, ItemXItemEffect, ItemEffect, SpellEffect,
             QuestV2, Faction, AuctionHouse, CurrencyTypes (--download fetches them for --build)
--wowhead    also read Wowhead's tooltips (nether.wowhead.com, the endpoint behind its embeddable tooltips; they
             are the client's own item and quest texts): the bundles of every crate, and the requested item and
             quantity of every writ. About 180 small requests.

Needs lupa (pip install lupa). Exit code 1 when anything disagrees.

Not covered, because Wowhead's pages refuse scripts: the rewards. Those were read in a browser on 2026-11-15 from
wowhead.com/forever: quests "A Sealed Crate" 91899-91907 (Merchant's Favor per sealed crate), "Shipping Label"
98247 / 98248 (2000 reputation + 50 Favor), "Crate Return" 93862 (50 reputation), item 262902 Forged Delivery Receipt
(15 Favor), and the quest list name:"Craftsman's Writ" (reputation of all 150 writs: 75 / 125 / 200, no money).
"""
import argparse, csv, html, json, os, re, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("--db", required=True)
ap.add_argument("--build", default="1.60.1.70938")
ap.add_argument("--download", action="store_true")
ap.add_argument("--wowhead", action="store_true")
ap.add_argument("--addon", default=os.path.join(HERE, "..", "Getrich"))
args = ap.parse_args()
TABLES = ["ItemSparse", "ItemXItemEffect", "ItemEffect", "SpellEffect", "QuestV2", "Faction", "AuctionHouse", "CurrencyTypes"]
UA = {"User-Agent": "Getrich-verify/1 (+https://github.com/luvxinc/Getrich)"}


def get(url, tries=4):
    for n in range(tries):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read()
        except OSError:                    # a dropped connection: wait a little and ask again
            if n == tries - 1:
                raise
            time.sleep(2 + 3 * n)


if args.download:
    os.makedirs(args.db, exist_ok=True)
    for t in TABLES:
        p = os.path.join(args.db, t + ".csv")
        if not os.path.exists(p):
            open(p, "wb").write(get("https://wago.tools/db2/%s/csv?build=%s" % (t, args.build)))


def table(name):
    return list(csv.DictReader(open(os.path.join(args.db, name + ".csv"), encoding="utf-8")))


from lupa import lua51
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
WC = lua.table()
WC.L = lua.eval("setmetatable({}, {__index = function(t, k) return k end})")
WC.AddLocale = lua.eval("function() end")
load = lua.eval("function(src, name, WC) assert(loadstring(src, '@' .. name))('Getrich', WC) end")
for f in ("Data.lua", "Writs.lua"):
    load(open(os.path.join(args.addon, f), encoding="utf-8").read(), f, WC)
CRATES = [dict(id=c.id, en=c.en, tier=c.tier, lvl=c.lvl, crafted=c.crafted, favor=c.favor,
               opts=[(o[1], o[2], o[3]) for o in c.opts.values()]) for c in WC.CRATES.values()]
WRITS = [dict(writ=w.writ, quest=w.quest, item=w.item, qty=w.qty, rep=w.rep, en=w.en, writName=w.writName)
         for w in WC.WRITS.values()]

S = {int(r["ID"]): r for r in table("ItemSparse")}
name = lambda i: S[i]["Display_lang"] if i in S else None
bad = []


def check(ok, msg):
    if not ok:
        bad.append(msg)
        print("  MISMATCH:", msg)


# ---------------------------------------------------------------------------------------------- crates, client
print("crates: %d in the addon" % len(CRATES))
client = {i for i, r in S.items() if r["Display_lang"].startswith("Waylaid Crate: ")}
check(client == {c["id"] for c in CRATES}, "crate items in the client and not in the addon (or the reverse): %s"
      % sorted(client ^ {c["id"] for c in CRATES}))
spell_of = {}
effect = {int(r["ID"]): int(r["SpellID"]) for r in table("ItemEffect")}
for r in table("ItemXItemEffect"):
    spell_of.setdefault(int(r["ItemID"]), effect.get(int(r["ItemEffectID"])))
qty_of = {}
for r in sorted(table("SpellEffect"), key=lambda r: int(r["EffectIndex"])):
    if r["Effect"] == "3":
        qty_of.setdefault(int(r["SpellID"]), []).append(int(float(r["EffectBasePointsF"])))
for c in CRATES:
    r = S.get(c["id"])
    if not r:
        continue
    check(r["Display_lang"] == "Waylaid Crate: " + c["en"], "%d name %r" % (c["id"], r["Display_lang"]))
    check(int(r["RequiredLevel"]) == c["lvl"], "%s: level %s in the client, %s in the addon" % (c["en"], r["RequiredLevel"], c["lvl"]))
    check((r["OverallQualityID"] == "2") == bool(c["crafted"]), "%s: quality %s vs crafted=%s" % (c["en"], r["OverallQualityID"], c["crafted"]))
    check(qty_of.get(spell_of.get(c["id"])) == [o[1] for o in c["opts"]],
          "%s: quantities %s in the client, %s in the addon" % (c["en"], qty_of.get(spell_of.get(c["id"])), [o[1] for o in c["opts"]]))
    for item, qty, note in c["opts"]:
        check(item in S, "%s: item %d is not in the client" % (c["en"], item))
        if item in S:
            en = WC.ITEMS[item][1] if WC.ITEMS[item] else None
            check(en == name(item), "item %d: %r in the addon, %r in the client" % (item, en, name(item)))
            over = qty > int(S[item]["Stackable"])
            check(over == (note == "stack"), "%s: %d x %s, stack %s, note %r" % (c["en"], qty, name(item), S[item]["Stackable"], note))

# ---------------------------------------------------------------------------------------------- writs, client
print("writs: %d in the addon" % len(WRITS))
client = {i for i, r in S.items() if r["Display_lang"].startswith("Craftsman's Writ: ")}
check(client == {w["writ"] for w in WRITS}, "writ items differ: %s" % sorted(client ^ {w["writ"] for w in WRITS}))
quests = {int(r["ID"]) for r in table("QuestV2")}
for w in WRITS:
    check(name(w["writ"]) == "Craftsman's Writ: " + w["writName"], "writ %d: %r vs %r" % (w["writ"], name(w["writ"]), w["writName"]))
    check(name(w["item"]) == w["en"], "writ %d asks for item %d: %r vs %r" % (w["writ"], w["item"], name(w["item"]), w["en"]))
    check(w["quest"] in quests, "writ quest %d is not in the client" % w["quest"])
    check(w["rep"] in (75, 125, 200), "writ %d: reputation %s" % (w["writ"], w["rep"]))
# (the "A Sealed Crate" quests of WC.SEALED_QUESTS are not in the client's QuestV2 table; see the docstring)

# ---------------------------------------------------------------------------------------------- constants
fac = {int(r["ID"]): r["Name_lang"] for r in table("Faction")}
check(fac.get(WC.FACTION_IDS.Alliance) == "Azeroth Commerce Authority", "faction %s: %r" % (WC.FACTION_IDS.Alliance, fac.get(WC.FACTION_IDS.Alliance)))
check(fac.get(WC.FACTION_IDS.Horde) == "Durotar Supply and Logistics", "faction %s: %r" % (WC.FACTION_IDS.Horde, fac.get(WC.FACTION_IDS.Horde)))
cur = {int(r["ID"]): r["Name_lang"] for r in table("CurrencyTypes")}
check(cur.get(WC.FAVOR_CURRENCY) == "Merchant's Favor", "currency %s: %r" % (WC.FAVOR_CURRENCY, cur.get(WC.FAVOR_CURRENCY)))
util = open(os.path.join(args.addon, "Util.lua"), encoding="utf-8").read()
cut = float(re.search(r"WC\.AH_CUT = ([0-9.]+)", util).group(1)) * 100
cut_n = float(re.search(r"WC\.AH_CUT_NEUTRAL = ([0-9.]+)", util).group(1)) * 100
rates = {}
for r in table("AuctionHouse"):
    # FactionID 1-6 are the Alliance / Horde city factions; the neutral houses belong to Gadgetzan (369)
    rates.setdefault("faction" if int(r["FactionID"]) <= 6 else "neutral", set()).add(int(r["ConsignmentRate"]))
check(rates.get("faction") == {int(cut)}, "faction auction house cut %s in the client, %s in the addon" % (rates.get("faction"), cut))
check(rates.get("neutral") == {int(cut_n)}, "neutral auction house cut %s in the client, %s in the addon" % (rates.get("neutral"), cut_n))
perk = {}
for r in table("SpellEffect"):
    if r["SpellID"] in ("1225456", "1225485") and r["EffectIndex"] == "0":
        perk[r["SpellID"]] = int(float(r["EffectBasePointsF"]))
check(perk.get("1225456") == 15, "Performance Bonus at max rank: %s (the addon uses 5%% per rank, 3 ranks)" % perk.get("1225456"))
check(perk.get("1225485") == 10, "Diplomat at max rank: %s (the addon uses 2%% per rank, 5 ranks)" % perk.get("1225485"))

# ---------------------------------------------------------------------------------------------- Wowhead tooltips
if args.wowhead:
    by_name = {}
    for i, r in S.items():
        by_name.setdefault(r["Display_lang"], []).append(i)

    def tip(kind, i):
        d = json.loads(get("https://nether.wowhead.com/forever/tooltip/%s/%d" % (kind, i)))
        return [x.strip() for x in html.unescape(re.sub(r"<[^>]+>", "\n", d["tooltip"])).split("\n") if x.strip()]

    print("Wowhead: crate bundles")
    for c in CRATES:
        got = []
        for line in tip("item", c["id"]):
            m = re.match(r"^- (\d+) (.+)$", line)
            if m:
                got.append((m.group(2), int(m.group(1))))
        want = [(name(o[0]), o[1]) for o in c["opts"]]
        check(got == want, "%s: tooltip %s, addon %s" % (c["en"], got, want))
    print("Wowhead: writ requirements")
    for w in WRITS:
        lines = tip("quest", w["quest"])
        req = [l[2:] for l in lines if l.startswith("- ")]
        item = name(w["item"]) + (" x %d" % w["qty"] if w["qty"] != 1 else "")
        check(sorted(req) == sorted(["Craftsman's Writ: " + w["writName"], item]), "quest %d: tooltip %s, addon wants %r" % (w["quest"], req, item))

print("%d mismatches" % len(bad))
sys.exit(1 if bad else 0)
