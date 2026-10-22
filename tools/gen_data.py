#!/usr/bin/env python3
"""Generate WaylaidCrate/DataVendor.lua (WC.VENDOR) and WaylaidCrate/DataDisenchant.lua (WC.DE).

Deterministic: the same inputs and arguments always give byte-identical output (all lists are sorted).
Python 3.8+, standard library only. lupa (pip install lupa) is used only by --check.

Inputs
  --db DIR        wago.tools DB2 CSV exports of the WoW Forever client build (ItemSparse.csv, Item.csv,
                  ItemDisenchantLoot.csv, SkillLineAbility.csv, SpellReagents.csv).
  --build B       client build of those CSVs, e.g. 1.60.1.70450 (header text; also the build --download fetches).
  --download      first download the five CSVs for --build from https://wago.tools/db2/<Table>/csv?build=B into --db.
  --sv FILE       SavedVariables file with merchant scans made in the Forever client (repeatable). Understood:
                    GetrichDB.vendor.observations  (Getrich.lua; only the scan facts are read)
                    WaylaidCrateDB.vendorObs       (WaylaidCrate.lua, Merchant.lua format)
                  Every item seen sold for gold with unlimited stock becomes an entry with seen = true.
  --pfquest DIR   checkout of https://github.com/shagu/pfQuest (MIT). Classic 1.12 vendor lists (db/items.lua "V"),
                  NPC coordinates/factions (db/units.lua), English NPC and zone names (db/enUS/). Used for recipe
                  reagents sold with unlimited stock (entries/NPCs marked classic). Optional.
  --out DIR       addon folder to write into (default: ../WaylaidCrate next to this script).
  --date D        date written into the headers (default: today, UTC). Pass it to reproduce a file exactly.
  --max-skill N   recipes whose yellow skill (TrivialSkillLineRankLow) is <= N count (default 300).
  --per-side N    at most N Classic NPCs per faction side for an item (default 3).
  --check         load the two Lua files with lupa (Lua 5.1) and run the consistency checks (after generating,
                  or alone when no --db is given).

Example (paths of the 2026-10-21 run):
  S=/tmp/claude-0/-home-claude/55dced39-fef5-5660-8cd3-4ed424fad23e/scratchpad
  python3 tools/gen_data.py --db $S/wago/db70450 --build 1.60.1.70450 \
      --sv /home/claude/brief/sv/Getrich.lua --pfquest $S/gh/pfQuest --date 2026-10-21 --check
"""

import argparse
import collections
import csv
import datetime
import math
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
WAGO = "https://wago.tools/db2/{table}/csv?build={build}"
TABLES = ("ItemSparse", "Item", "ItemDisenchantLoot", "SkillLineAbility", "SpellReagents")

# Profession skill lines (Forever SkillLine.csv). 40 = Poisons (rogue trade skill window).
PROFESSIONS = {129: "First Aid", 164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy", 182: "Herbalism",
               185: "Cooking", 186: "Mining", 197: "Tailoring", 202: "Engineering", 333: "Enchanting",
               356: "Fishing", 393: "Skinning", 40: "Poisons"}

CAPITAL_ZONES = {"Stormwind City", "Ironforge", "Darnassus", "Orgrimmar", "Undercity", "Thunder Bluff"}
# Smokywood Pastures vendors exist only during the Feast of Winter Veil: not a year-round source.
SEASONAL_NPC = re.compile(r"Copperpinch|Jinglepocket")
FACTION_CODE = {"Alliance": "A", "Horde": "H"}

DE_SPELL = 13262
NO_DISENCHANT_FLAG = 0x8000          # ItemSparse Flags_0: ITEM_FLAG_NO_DISENCHANT
GEAR_CLASSES = (2, 4)                # weapon, armor
DE_QUALITIES = (2, 3, 4)             # uncommon, rare, epic
NODE_MAX_LEVEL = 70

# ---------------------------------------------------------------------------------------------------------------
# Classic disenchant outputs per Classic band: { (quality, class): [ (lo, hi, [ (itemID, chance, min, max), ... ]) ] }
# Band boundaries = Classic Era 1.15.9 ItemDisenchantLoot (rare: wiki 1-25). Odds/quantities = Classic 1.12 disenchant_loot_template
# (vmangos / cmangos classic-db; a 0-chance group member gets the remainder of 100%), cross-checked 2026-10-21 against
# warcraft.wiki.gg "Disenchanting tables" and DisenchantForever Materials.lua (MIT, vmangos-based). All three agree
# on every band up to item level 60 except where noted:
#   rare 56-60      vmangos/cmangos/DisenchantForever 100% Large Brilliant Shard (wiki lists 56-65 as 99.5% + 0.5% Nexus)
#   rare 61-99      wiki and cmangos 66-70 99.5% LBS + 0.5% Nexus Crystal (cmangos 61-65 100% LBS; DisenchantForever 99%+1%)
#   uncommon 61-99  wiki + DisenchantForever Greater Eternal Essence 2-3 (cmangos 2)
SD, SOUL, VISION, DREAM, ILLUSION = 10940, 11083, 11137, 11176, 16204
LME, GME, LAE, GAE, LMYE, GMYE, LNE, GNE, LEE, GEE = 10938, 10939, 10998, 11082, 11134, 11135, 11174, 11175, 16202, 16203
SGS, LGS, SGLOW, LGLOW, SRAD, LRAD, SBS, LBS, NEXUS = 10978, 11084, 11138, 11139, 11177, 11178, 14343, 14344, 20725

_ARMOR2 = [
    (5, 15, [(SD, .80, 1, 2), (LME, .20, 1, 2)]),
    (16, 20, [(SD, .75, 2, 3), (GME, .20, 1, 2), (SGS, .05, 1, 1)]),
    (21, 25, [(SD, .75, 4, 6), (LAE, .15, 1, 2), (SGS, .10, 1, 1)]),
    (26, 30, [(SOUL, .75, 1, 2), (GAE, .20, 1, 2), (LGS, .05, 1, 1)]),
    (31, 35, [(SOUL, .75, 2, 5), (LMYE, .20, 1, 2), (SGLOW, .05, 1, 1)]),
    (36, 40, [(VISION, .75, 1, 2), (GMYE, .20, 1, 2), (LGLOW, .05, 1, 1)]),
    (41, 45, [(VISION, .75, 2, 5), (LNE, .20, 1, 2), (SRAD, .05, 1, 1)]),
    (46, 50, [(DREAM, .75, 1, 2), (GNE, .20, 1, 2), (LRAD, .05, 1, 1)]),
    (51, 55, [(DREAM, .75, 2, 5), (LEE, .20, 1, 2), (SBS, .05, 1, 1)]),
    (56, 60, [(ILLUSION, .75, 1, 2), (GEE, .20, 1, 2), (LBS, .05, 1, 1)]),
    (61, 99, [(ILLUSION, .75, 2, 5), (GEE, .20, 2, 3), (LBS, .05, 1, 1)]),
]
_WEAPON2 = [
    (5, 15, [(LME, .80, 1, 2), (SD, .20, 1, 2)]),
    (16, 20, [(GME, .75, 1, 2), (SD, .20, 2, 3), (SGS, .05, 1, 1)]),
    (21, 25, [(LAE, .75, 1, 2), (SD, .15, 4, 6), (SGS, .10, 1, 1)]),
    (26, 30, [(GAE, .75, 1, 2), (SOUL, .20, 1, 2), (LGS, .05, 1, 1)]),
    (31, 35, [(LMYE, .75, 1, 2), (SOUL, .20, 2, 5), (SGLOW, .05, 1, 1)]),
    (36, 40, [(GMYE, .75, 1, 2), (VISION, .20, 1, 2), (LGLOW, .05, 1, 1)]),
    (41, 45, [(LNE, .75, 1, 2), (VISION, .20, 2, 5), (SRAD, .05, 1, 1)]),
    (46, 50, [(GNE, .75, 1, 2), (DREAM, .20, 1, 2), (LRAD, .05, 1, 1)]),
    (51, 55, [(LEE, .75, 1, 2), (DREAM, .22, 2, 5), (SBS, .03, 1, 1)]),
    (56, 60, [(GEE, .75, 1, 2), (ILLUSION, .22, 1, 2), (LBS, .03, 1, 1)]),
    (61, 99, [(GEE, .75, 2, 3), (ILLUSION, .22, 2, 5), (LBS, .03, 1, 1)]),
]
_RARE = [
    (1, 25, [(SGS, 1.0, 1, 1)]),         # wiki: rare 1-25 (Classic Era DB2 / cmangos start the band at 20; same output)
    (26, 30, [(LGS, 1.0, 1, 1)]),
    (31, 35, [(SGLOW, 1.0, 1, 1)]),
    (36, 40, [(LGLOW, 1.0, 1, 1)]),
    (41, 45, [(SRAD, 1.0, 1, 1)]),
    (46, 50, [(LRAD, 1.0, 1, 1)]),
    (51, 55, [(SBS, 1.0, 1, 1)]),
    (56, 60, [(LBS, 1.0, 1, 1)]),
    (61, 99, [(LBS, .995, 1, 1), (NEXUS, .005, 1, 1)]),
]
_EPIC = [
    (40, 45, [(SRAD, 1.0, 2, 4)]),
    (46, 50, [(LRAD, 1.0, 2, 4)]),
    (51, 55, [(SBS, 1.0, 2, 4)]),
    (56, 60, [(NEXUS, 1.0, 1, 1)]),
    (61, 99, [(NEXUS, 1.0, 1, 2)]),
]
CLASSIC_DE = {(2, 4): _ARMOR2, (2, 2): _WEAPON2, (3, 4): _RARE, (3, 2): _RARE, (4, 4): _EPIC, (4, 2): _EPIC}


# ---------------------------------------------------------------------------------------------------------------
# small helpers

def die(msg):
    sys.stderr.write("gen_data.py: " + msg + "\n")
    sys.exit(1)


def read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def to_int(s, default=0):
    try:
        return int(s)
    except (TypeError, ValueError):
        try:
            return int(float(s))
        except (TypeError, ValueError):
            return default


def lua_str(s):
    s = str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
    return '"' + s + '"'


def lua_num(x):
    if x is None:
        return "nil"
    if isinstance(x, bool):
        return "true" if x else "false"
    if isinstance(x, int):
        return str(x)
    if float(x).is_integer():
        return str(int(x))
    return ("%.4f" % x).rstrip("0").rstrip(".")


def coord(v):
    """0-1 fraction -> 0-100 with one decimal (None stays None)."""
    if v is None:
        return None
    return round(float(v) * 100 + 1e-9, 1)


def download(db, build):
    os.makedirs(db, exist_ok=True)
    for t in TABLES:
        url = WAGO.format(table=t, build=build)
        req = urllib.request.Request(url, headers={"User-Agent": "WaylaidCrate-gen_data/1.0 (+github.com/luvxinc/WaylaidCrate)"})
        with urllib.request.urlopen(req, timeout=120) as r:
            data = r.read()
        if data[:1] == b"<":
            die("wago.tools returned HTML instead of CSV for %s (unknown build %s?)" % (t, build))
        with open(os.path.join(db, t + ".csv"), "wb") as f:
            f.write(data)
        print("downloaded %s (%d bytes)" % (url, len(data)))


# ---------------------------------------------------------------------------------------------------------------
# minimal reader for SavedVariables files (Lua table literals; no code execution)

_TOKEN = re.compile(r"""
    (?P<ws>\s+|--\[(?P<eq1>=*)\[.*?\](?P=eq1)\]|--[^\n]*)
  | (?P<lstr>\[(?P<eq2>=*)\[.*?\](?P=eq2)\])
  | (?P<str>"(?:[^"\\\n]|\\.|\\\n)*"|'(?:[^'\\\n]|\\.|\\\n)*')
  | (?P<num>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z_0-9]*)
  | (?P<op>[{}\[\]=,;])
""", re.S | re.X)

_ESC = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
        "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def _unescape(body):
    out, i, n = [], 0, len(body)
    while i < n:
        c = body[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = body[i + 1] if i + 1 < n else ""
        if nxt.isdigit():
            j = i + 1
            while j < n and j < i + 4 and body[j].isdigit():
                j += 1
            out.append(chr(int(body[i + 1:j])))
            i = j
        else:
            out.append(_ESC.get(nxt, nxt))
            i += 2
    return "".join(out)


def _tokens(text):
    pos, n = 0, len(text)
    while pos < n:
        m = _TOKEN.match(text, pos)
        if not m:
            die("cannot parse SavedVariables near: %r" % text[pos:pos + 40])
        pos = m.end()
        if m.group("ws") is not None:
            continue
        if m.group("lstr") is not None:
            s = m.group("lstr")
            k = len(m.group("eq2"))
            body = s[2 + k:-2 - k]
            yield ("str", body[1:] if body.startswith("\n") else body)
        elif m.group("str") is not None:
            yield ("str", _unescape(m.group("str")[1:-1]))
        elif m.group("num") is not None:
            t = m.group("num")
            v = int(t, 16) if t.lower().lstrip("-").startswith("0x") else float(t)
            if isinstance(v, float) and v.is_integer() and "." not in t and "e" not in t.lower():
                v = int(v)
            yield ("num", v)
        elif m.group("name") is not None:
            yield ("name", m.group("name"))
        else:
            yield ("op", m.group("op"))


def read_savedvariables(path):
    """Returns {globalName: value}; tables become dicts (array items keyed 1..n)."""
    with open(path, encoding="utf-8", errors="replace") as f:
        toks = list(_tokens(f.read()))
    pos = [0]

    def peek(k=0):
        i = pos[0] + k
        return toks[i] if i < len(toks) else ("eof", None)

    def take():
        t = peek()
        pos[0] += 1
        return t

    def expect(op):
        t = take()
        if t != ("op", op):
            die("%s: expected %r, got %r" % (path, op, t))

    def value():
        kind, v = take()
        if kind in ("str", "num"):
            return v
        if kind == "name":
            if v == "true":
                return True
            if v == "false":
                return False
            if v == "nil":
                return None
        if (kind, v) == ("op", "{"):
            return table()
        die("%s: unexpected token %r" % (path, (kind, v)))

    def table():
        t, n = {}, 0
        while True:
            if peek() == ("op", "}"):
                take()
                return t
            if peek() == ("op", "["):
                take()
                k = value()
                expect("]")
                expect("=")
                t[k] = value()
            elif peek()[0] == "name" and peek(1) == ("op", "="):
                k = take()[1]
                take()
                t[k] = value()
            else:
                n += 1
                t[n] = value()
            if peek() in (("op", ","), ("op", ";")):
                take()

    out = {}
    while peek()[0] != "eof":
        kind, name = take()
        if kind != "name":
            die("%s: expected a global name, got %r" % (path, (kind, name)))
        expect("=")
        out[name] = value()
    return out


# ---------------------------------------------------------------------------------------------------------------
# pfQuest (Classic 1.12 database, MIT). Line-based reader for its generated db/*.lua files.

_KEY_LINE = re.compile(r'^  \[(\d+)\] = \{\s*$')
_STR_LINE = re.compile(r'^  \[(\d+)\] = "((?:[^"\\]|\\.)*)",?\s*$')


def pfquest_strings(path):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = _STR_LINE.match(line)
            if m:
                out[int(m.group(1))] = _unescape(m.group(2))
    return out


def pfquest_vendors(path):
    """{itemID: {npcID: maxStock}}; maxStock 0 = unlimited."""
    out, cur, in_v = {}, None, False
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = _KEY_LINE.match(line)
            if m:
                cur, in_v = int(m.group(1)), False
                continue
            if line.startswith('    ["V"] = {'):
                in_v = True
                continue
            if in_v:
                if line.startswith("    }"):
                    in_v = False
                    continue
                m = re.match(r'^      \[(\d+)\] = (\d+),', line)
                if m and cur is not None:
                    out.setdefault(cur, {})[int(m.group(1))] = int(m.group(2))
    return out


def pfquest_units(path):
    """{npcID: {"coords": [(x, y, zoneID), ...], "fac": "A"|"H"|"AH"|None}}"""
    out, cur, in_c = {}, None, False
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = _KEY_LINE.match(line)
            if m:
                cur, in_c = int(m.group(1)), False
                out[cur] = {"coords": [], "fac": None}
                continue
            if cur is None:
                continue
            if line.startswith('    ["coords"] = {'):
                in_c = not line.rstrip().endswith("{},")
                continue
            if in_c:
                if line.startswith("    }"):
                    in_c = False
                    continue
                m = re.match(r'^      \[\d+\] = \{ (-?[\d.]+), (-?[\d.]+), (\d+)', line)
                if m:
                    out[cur]["coords"].append((float(m.group(1)), float(m.group(2)), int(m.group(3))))
                continue
            m = re.match(r'^    \["fac"\] = "(\w+)"', line)
            if m:
                out[cur]["fac"] = m.group(1)
    return out


def pfquest_commit(root):
    head = os.path.join(root, ".git", "HEAD")
    try:
        with open(head) as f:
            ref = f.read().strip()
        if ref.startswith("ref:"):
            p = os.path.join(root, ".git", ref[5:])
            if os.path.exists(p):
                with open(p) as f:
                    return f.read().strip()[:7]
            with open(os.path.join(root, ".git", "packed-refs")) as f:
                for line in f:
                    if line.strip().endswith(ref[5:]):
                        return line.split()[0][:7]
        return ref[:7]
    except OSError:
        return "unknown"


# ---------------------------------------------------------------------------------------------------------------
# merchant scans

def merchant_offers(sv_paths):
    """Flatten the scans to a list of offer dicts:
       {item, npc, name, zone, x, y, price (per purchase), qty, unlimited, gold, faction, t, char, build, obs}"""
    offers, files = [], []
    for path in sv_paths:
        g = read_savedvariables(path)
        files.append(os.path.basename(path))
        gr = g.get("GetrichDB")
        obs = gr.get("vendor", {}).get("observations", {}) if isinstance(gr, dict) else {}
        for key in sorted(obs, key=str):
            o = obs[key]
            if not isinstance(o, dict):
                continue
            for ik, f in sorted((o.get("offers") or {}).items(), key=lambda kv: str(kv[0])):
                if not isinstance(f, dict):
                    continue
                item = to_int(f.get("itemID", ik))
                cond = f.get("conditions") if isinstance(f.get("conditions"), dict) else {}
                offers.append({
                    "item": item, "npc": to_int(f.get("npcID", o.get("npcID"))), "name": f.get("npcName") or "",
                    "zone": f.get("locationText") or "", "x": coord(f.get("x")), "y": coord(f.get("y")),
                    "price": f.get("pricePerPurchase"), "qty": to_int(f.get("purchaseQuantity"), 1) or 1,
                    "unlimited": (not f.get("limited")) and to_int(f.get("numAvailable"), -1) < 0,
                    "gold": not f.get("hasExtendedCost") and (f.get("pricePerPurchase") or 0) > 0,
                    "faction": FACTION_CODE.get(cond.get("faction"), ""), "t": to_int(f.get("timestamp", o.get("timestamp"))),
                    "char": str(o.get("characterKey") or f.get("characterKey") or ""),
                    "build": str(f.get("verifiedBuild") or ""), "obs": str(key),
                })
        wc = g.get("WaylaidCrateDB")
        vo = wc.get("vendorObs", {}) if isinstance(wc, dict) else {}
        for ik in sorted(vo, key=str):
            v = vo[ik]
            if not isinstance(v, dict) or not v.get("price"):
                continue
            bundle = to_int(v.get("bundle"), 1) or 1
            offers.append({
                "item": to_int(ik), "npc": to_int(v.get("npc")), "name": v.get("name") or "", "zone": v.get("zone") or "",
                "x": round(float(v["x"]), 1) if v.get("x") is not None else None,
                "y": round(float(v["y"]), 1) if v.get("y") is not None else None,
                "price": int(round(float(v["price"]) * bundle)), "qty": bundle,
                "unlimited": not v.get("limited"), "gold": True, "faction": FACTION_CODE.get(v.get("faction"), ""),
                "t": to_int(v.get("t")), "char": "WaylaidCrate", "build": "", "obs": "wc:%s" % v.get("npc"),
            })
    return offers, files


def list_prices(offers, sparse):
    """Undo personal vendor discounts (reputation / Bartering): per scan, the most common ratio between the price paid
    and the client list price (ItemSparse BuyPrice) is that scan's discount. Returns {offer index: list price}."""
    by_obs = collections.defaultdict(list)
    for i, o in enumerate(offers):
        if o["gold"]:
            by_obs[o["obs"]].append(i)
    out = {}
    for key in sorted(by_obs):
        ratios = collections.Counter()
        for i in by_obs[key]:
            o = offers[i]
            s = sparse.get(o["item"])
            bp = to_int(s["BuyPrice"]) if s else 0
            if bp > 0 and o["qty"] == (to_int(s["VendorStackCount"]) or 1):
                ratios[round(o["price"] / bp, 2)] += 1
        factor = 1.0
        if ratios:
            best = sorted(ratios.items(), key=lambda kv: (-kv[1], -kv[0]))[0][0]
            if 0.5 <= best < 0.995:
                factor = best
        for i in by_obs[key]:
            o = offers[i]
            price = o["price"]
            if factor == 1.0:
                out[i] = int(round(price))
                continue
            s = sparse.get(o["item"])
            bp = to_int(s["BuyPrice"]) if s else 0
            if bp > 0 and abs(math.ceil(bp * factor - 1e-9) - price) <= 1:
                out[i] = bp
            else:
                out[i] = int(round(price / factor))
    return out


# ---------------------------------------------------------------------------------------------------------------
# WC.VENDOR

def recipe_reagents(sla_rows, reagent_rows, max_skill):
    spells = {}
    for r in sla_rows:
        sl = to_int(r["SkillLine"])
        if sl in PROFESSIONS and to_int(r["TrivialSkillLineRankLow"]) <= max_skill and to_int(r["MinSkillLineRank"]) <= max_skill:
            spells.setdefault(to_int(r["Spell"]), set()).add(sl)
    used = {}
    for r in reagent_rows:
        sp = to_int(r["SpellID"])
        if sp not in spells:
            continue
        for k in range(8):
            item, cnt = to_int(r.get("Reagent_%d" % k)), to_int(r.get("ReagentCount_%d" % k))
            if item > 0 and cnt > 0:
                used.setdefault(item, set()).update(spells[sp])
    return used, len(spells)


def side_ok(fac, side):
    return fac == "" or fac == side


def build_vendor(args, sparse, items, stats):
    offers, sv_files = merchant_offers(args.sv)
    lp = list_prices(offers, sparse)
    used, nspells = recipe_reagents(read_csv(os.path.join(args.db, "SkillLineAbility.csv")),
                                    read_csv(os.path.join(args.db, "SpellReagents.csv")), args.max_skill)
    stats["recipes"], stats["reagents"] = nspells, len(used)

    pf = None
    if args.pfquest:
        dbdir = os.path.join(args.pfquest, "db")
        pf = {"vendors": pfquest_vendors(os.path.join(dbdir, "items.lua")),
              "units": pfquest_units(os.path.join(dbdir, "units.lua")),
              "names": pfquest_strings(os.path.join(dbdir, "enUS", "units.lua")),
              "zones": pfquest_strings(os.path.join(dbdir, "enUS", "zones.lua")),
              "commit": pfquest_commit(args.pfquest)}

    def pf_fac(npc, fallback):
        if pf and npc in pf["units"]:
            f = pf["units"][npc]["fac"]
            return {"A": "A", "H": "H"}.get(f, "")
        return fallback

    # --- (a) seen: gold, unlimited stock
    seen = collections.defaultdict(list)
    for i, o in enumerate(offers):
        if o["gold"] and o["unlimited"]:
            seen[o["item"]].append(i)
    stats["scans"] = len({o["obs"] for o in offers})
    stats["scan_npcs"] = len({o["npc"] for o in offers})
    stats["scan_builds"] = sorted({o["build"] for o in offers if o["build"]})
    stats["sv_files"] = sv_files

    # one description per scanned NPC: from its latest scan
    npc_seen = {}
    for o in sorted(offers, key=lambda o: (o["t"], o["obs"])):
        npc_seen[o["npc"]] = [o["npc"], o["name"], o["zone"], o["x"], o["y"], pf_fac(o["npc"], o["faction"])]

    entries = {}
    discounted, db_mismatch, stale = 0, [], []
    target_build = to_int(str(args.build).split(".")[-1])
    for item in sorted(seen):
        idx = seen[item]
        # prices change between builds (e.g. throwing weapons 30c at 70374, 299c at 70450): the newest scan wins;
        # within one scan time prefer an offer without a personal discount, then the most common price.
        newest = max(offers[i]["t"] for i in idx)
        pool = [i for i in idx if offers[i]["t"] == newest]
        plain = [i for i in pool if lp[i] == int(round(offers[i]["price"]))]
        pool = plain or pool
        buy = sorted(collections.Counter(lp[i] for i in pool).items(), key=lambda kv: (-kv[1], -kv[0]))[0][0]
        qty = sorted(collections.Counter(offers[i]["qty"] for i in pool).items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
        if any(lp[i] != int(round(offers[i]["price"])) for i in idx):
            discounted += 1
        s = sparse.get(item)
        # a scan from an older client build that disagrees with this build's ItemSparse is out of date (the 70450 scans
        # match 70450 ItemSparse on every offer, while 70374 scans showed throwing weapons at other prices)
        scan_build = max(to_int(offers[i]["build"].split(".")[-1]) for i in pool)
        if s and scan_build and scan_build < target_build and to_int(s["BuyPrice"]) > 0 \
                and (to_int(s["BuyPrice"]), to_int(s["VendorStackCount"]) or 1) != (buy, qty):
            stale.append((item, s["Display_lang"], buy, qty, scan_build))
            buy, qty = to_int(s["BuyPrice"]), to_int(s["VendorStackCount"]) or 1
        if s and (to_int(s["BuyPrice"]) != buy or (to_int(s["VendorStackCount"]) or 1) != qty):
            db_mismatch.append((item, s["Display_lang"], buy, qty, to_int(s["BuyPrice"]), to_int(s["VendorStackCount"])))
        lst = sorted((npc_seen[n] for n in {offers[i]["npc"] for i in idx}),
                     key=lambda n: (n[2] not in CAPITAL_ZONES, n[2], n[1], n[0]))
        entries[item] = {"buy": buy, "stack": qty, "npcs": lst, "seen": True}
    stats["seen"] = len(entries)
    stats["seen_discounted"] = discounted
    stats["seen_db_mismatch"] = db_mismatch
    stats["seen_stale"] = stale

    # --- (b) recipe reagents that Classic vendors sold with unlimited stock (pfQuest), priced from the Forever client
    classic_added, dropped_npcs, no_price, limited_only = 0, 0, [], []

    def classic_npcs(item, already):
        nonlocal dropped_npcs
        cands = []
        for npc, stock in sorted(pf["vendors"].get(item, {}).items()):
            if stock != 0 or npc in already:
                continue
            if npc in npc_seen:
                # scanned in Forever without an unlimited offer of this item (limited stock, gone, or a partial scan)
                dropped_npcs += 1
                continue
            name = pf["names"].get(npc)
            u = pf["units"].get(npc, {"coords": [], "fac": None})
            if not name or not u["coords"] or SEASONAL_NPC.search(name):
                continue          # no spawn point in the world (GM/test NPCs) or holiday-only vendor
            c = u["coords"][0]
            zone = pf["zones"].get(c[2], "")
            fac = {"A": "A", "H": "H"}.get(u["fac"], "")
            cands.append([npc, name, zone, c[0], c[1], fac, True])
        cands.sort(key=lambda n: (n[2] not in CAPITAL_ZONES, n[5] != "", n[0]))
        return cands

    def pick(cands, current):
        chosen = []
        for side in ("A", "H"):
            # a side is covered by the scans if a seen NPC of that faction (or a neutral one in a capital) sells it
            if any(len(n) < 7 and side_ok(n[5], side) and (n[5] == side or n[2] in CAPITAL_ZONES) for n in current):
                continue
            have = [n for n in current + chosen if len(n) > 6 and side_ok(n[5], side)]
            need = args.per_side - len(have)
            for n in cands:
                if need <= 0:
                    break
                if side_ok(n[5], side) and n not in chosen:
                    chosen.append(n)
                    need -= 1
        chosen.sort(key=lambda n: (n[2] not in CAPITAL_ZONES, n[5] != "", n[0]))
        return chosen

    if pf:
        for item in sorted(used):
            stock = pf["vendors"].get(item)
            if not stock:
                continue
            if all(v != 0 for v in stock.values()):
                if item not in entries:
                    limited_only.append(item)
                continue
            if item in entries:
                e = entries[item]
                extra = pick(classic_npcs(item, {n[0] for n in e["npcs"]}), e["npcs"])
                # capital-city NPCs first (seen before Classic), then the other seen NPCs, then other Classic ones:
                # WC:VendorPrice shows the first NPC usable by the player's faction.
                e["npcs"] = sorted(e["npcs"] + extra, key=lambda n: (n[2] not in CAPITAL_ZONES, len(n) > 6))
                continue
            s = sparse.get(item)
            buy = to_int(s["BuyPrice"]) if s else 0
            if buy <= 0:
                no_price.append(item)
                continue
            npcs = pick(classic_npcs(item, set()), [])
            if not npcs:
                continue
            entries[item] = {"buy": buy, "stack": to_int(s["VendorStackCount"]) or 1, "npcs": npcs, "classic": True}
            classic_added += 1
    stats["classic"] = classic_added
    stats["dropped_npcs"] = dropped_npcs
    stats["no_price"] = no_price
    stats["limited_only"] = limited_only
    stats["vendor_total"] = len(entries)
    stats["reagents_covered"] = len([i for i in used if i in entries])
    stats["pfquest_commit"] = pf["commit"] if pf else None
    return entries


def write_vendor(path, entries, sparse, args, stats):
    names = lambda i: (sparse.get(i) or {}).get("Display_lang") or "?"
    L = []
    L.append("local addonName, WC = ...")
    L.append("")
    L.append("-- Waylaid Crate vendor data. GENERATED by tools/gen_data.py on %s -- do not edit by hand." % args.date)
    L.append("-- WoW Forever client build %s (DB2 tables from wago.tools)." % args.build)
    L.append("-- WC.VENDOR[itemID] = { buy = copper per purchase, stack = items per purchase, npcs = {...}, seen = true|nil,")
    L.append("--                        classic = true|nil }")
    L.append("--   npc = { npcID, name, zone, x, y, faction, classicLocation }   x, y = map coordinates 0-100 (nil if unknown);")
    L.append("--         faction \"A\" Alliance, \"H\" Horde, \"\" both/unknown; classicLocation = true for NPCs taken from Classic data.")
    L.append("-- Only items sold for gold with unlimited stock. Prices are list prices: the merchant may show less")
    L.append("-- (reputation discounts, the Bartering perk); Merchant.lua records what the player really pays.")
    L.append("-- Sources:")
    L.append("--   seen = true: the user's own merchant scans in the Forever client (%s; %d scans, %d NPCs, builds %s)."
             % (", ".join(stats["sv_files"]) or "none", stats["scans"], stats["scan_npcs"], ", ".join(stats["scan_builds"]) or "-"))
    L.append("--     Price and bundle as seen in the newest scan (personal discounts removed; a scan from an older build that")
    L.append("--     disagrees with this build's ItemSparse is replaced by ItemSparse), exact NPC positions.")
    L.append("--   classic = true: reagents of Forever profession recipes (SkillLineAbility, yellow skill <= %d) that Classic"
             % args.max_skill)
    L.append("--     vendors sold with unlimited stock; buy/stack from Forever ItemSparse (BuyPrice, VendorStackCount); NPCs,")
    L.append("--     factions and positions from the pfQuest Classic 1.12 database (Forever may have moved or removed them).")
    L.append("--     Left out: NPCs without a spawn point, Winter Veil-only vendors, NPCs the user scanned (the scan decides);")
    L.append("--     at most %d Classic NPCs per faction, none for a faction that a seen NPC covers." % args.per_side)
    L.append("-- Contents: %d items (%d seen in the client, %d Classic-vendor recipe reagents)."
             % (stats["vendor_total"], stats["seen"], stats["classic"]))
    if stats.get("pfquest_commit"):
        L.append("--")
        L.append("-- pfQuest database (https://github.com/shagu/pfQuest, commit %s) is used under the MIT License:" % stats["pfquest_commit"])
        L.extend("--   " + line if line else "--" for line in PFQUEST_LICENSE.strip().split("\n"))
    # every NPC tuple is written once and shared by the items it sells (saves memory; treat the tables as read-only)
    npc_src = {}
    for item in sorted(entries):
        for n in entries[item]["npcs"]:
            f = [lua_num(n[0]), lua_str(n[1]), lua_str(n[2]), lua_num(n[3]), lua_num(n[4]), lua_str(n[5])]
            if len(n) > 6 and n[6]:
                f.append("true")
            src = "{" + ",".join(f) + "}"
            if npc_src.setdefault(n[0], src) != src:
                die("NPC %d has two different descriptions" % n[0])
    L.append("")
    L.append("-- NPCs, shared by the item entries below (read-only)")
    L.append("local N = {")
    for npc in sorted(npc_src):
        L.append("  [%d]=%s," % (npc, npc_src[npc]))
    L.append("}")
    L.append("")
    L.append("WC.VENDOR = {")
    for item in sorted(entries):
        e = entries[item]
        parts = ["buy=" + lua_num(e["buy"]), "stack=" + lua_num(e["stack"])]
        if e.get("seen"):
            parts.append("seen=true")
        if e.get("classic"):
            parts.append("classic=true")
        parts.append("npcs={" + ",".join("N[%d]" % n[0] for n in e["npcs"]) + "}")
        L.append("  [%d]={%s}, -- %s" % (item, ",".join(parts), names(item).replace("\n", " ")))
    L.append("}")
    L.append("")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L))


PFQUEST_LICENSE = """
MIT License

Copyright (c) 2017-2021 Eric Mauser (Shagu)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""


# ---------------------------------------------------------------------------------------------------------------
# WC.DE

def classic_rows_for(q, cls, lo, hi):
    """Classic outputs for a Forever band: the Classic band that contains it, else the nearest one (est)."""
    rows = CLASSIC_DE.get((q, cls))
    if not rows:
        return None, None
    for clo, chi, out in rows:
        if clo <= lo and hi <= chi:
            return out, None
    dist = lambda r: 0 if (r[0] <= hi and lo <= r[1]) else min(abs(r[0] - hi), abs(lo - r[1]))
    best = sorted(rows, key=lambda r: (dist(r), r[0]))[0]
    return best[2], "nearest"


def build_de(args, sparse, items, stats):
    bands, unknown = [], []
    for r in read_csv(os.path.join(args.db, "ItemDisenchantLoot.csv")):
        q, cls = to_int(r["Quality"]), to_int(r["Class"])
        if q not in DE_QUALITIES or cls not in GEAR_CLASSES:
            continue
        lo, hi = to_int(r["MinLevel"]), to_int(r["MaxLevel"])
        out, est = classic_rows_for(q, cls, lo, hi)
        if out is None:
            unknown.append(r["ID"])
            continue
        skill = max(1, to_int(r.get("SkillRequired")))
        bands.append({"q": q, "class": cls, "lo": lo, "hi": hi, "skill": skill, "out": out, "est": est,
                      "id": to_int(r["ID"])})
    bands.sort(key=lambda b: (b["q"], b["class"], b["lo"], b["hi"]))
    nodE = []
    for i, s in sparse.items():
        it = items.get(i)
        if not it or to_int(it["ClassID"]) not in GEAR_CLASSES:
            continue
        if to_int(s["OverallQualityID"]) not in DE_QUALITIES:
            continue
        if not (to_int(s["Flags_0"]) & 0xFFFFFFFF) & NO_DISENCHANT_FLAG:
            continue
        if to_int(s["ItemLevel"]) > NODE_MAX_LEVEL or to_int(s["RequiredLevel"]) > NODE_MAX_LEVEL:
            continue
        nodE.append(i)
    mats = sorted({o[0] for b in bands for o in b["out"]})
    stats["bands"] = len(bands)
    stats["bands_est"] = ["%s %d %d-%d" % ({2: "uncommon", 3: "rare", 4: "epic"}[b["q"]], b["class"], b["lo"], b["hi"])
                          for b in bands if b["est"]]
    stats["bands_unknown"] = unknown
    stats["noDE"] = len(nodE)
    stats["mats"] = len(mats)
    return {"bands": bands, "noDE": sorted(nodE), "mats": mats}


def write_de(path, de, sparse, args, stats):
    names = lambda i: (sparse.get(i) or {}).get("Display_lang") or "?"
    qn = {2: "uncommon", 3: "rare", 4: "epic"}
    cn = {2: "weapon", 4: "armor"}
    L = []
    L.append("local addonName, WC = ...")
    L.append("")
    L.append("-- Waylaid Crate disenchant data. GENERATED by tools/gen_data.py on %s -- do not edit by hand." % args.date)
    L.append("-- Bands (quality, class 2 weapon / 4 armor, item-level range): WoW Forever client ItemDisenchantLoot,")
    L.append("--   build %s (wago.tools)." % args.build)
    L.append("-- Odds and quantities are ESTIMATES from Classic 1.12: vmangos / cmangos disenchant_loot_template, cross-checked")
    L.append("--   with warcraft.wiki.gg \"Disenchanting tables\" and DisenchantForever Materials.lua (MIT, APGM82). Forever's")
    L.append("--   real yields are decided by the server and are not published; Disenchant.lua measures them from real casts.")
    L.append("-- Forever band changes vs Classic Era: new rare bands 5-15 and 16-20 and rare 20-25 became 21-25; all three are")
    L.append("--   inside the wiki's Classic rare 1-25 row (Small Glimmering Shard 100%); uncommon/epic bands unchanged.")
    L.append("-- est = \"nearest\" would mark a band with no Classic equivalent (outputs of the nearest band); none at present.")
    L.append("-- skill: ItemDisenchantLoot.SkillRequired is 0 for every Forever band (as in Classic Era, where any enchanter")
    L.append("--   can disenchant anything; the Wrath-based 3.80 client fills it with 1/25/50/...), so skill = 1 = \"has Enchanting\".")
    L.append("-- out = { { itemID, chance (0-1), minQty, maxQty }, ... }; the chances of one band sum to 1.")
    L.append("-- noDE: weapons/armor of quality 2-4, item and required level <= %d, with ItemSparse Flags_0 0x8000"
             % NODE_MAX_LEVEL)
    L.append("--   (ITEM_FLAG_NO_DISENCHANT), e.g. Lesser Magic Wand 11287, Greater Magic Wand 11288, Lesser Mystic Wand 11289.")
    L.append("-- mats: every itemID that appears in any band's out.")
    L.append("")
    L.append("WC.DE = {")
    L.append("  spell = %d, -- Disenchant" % DE_SPELL)
    L.append("  bands = {")
    for b in de["bands"]:
        outs = ",".join("{%d,%s,%d,%d}" % (o[0], lua_num(o[1]), o[2], o[3]) for o in b["out"])
        extra = ',est="nearest"' if b["est"] else ""
        desc = ", ".join("%s %s%% x%s" % (names(o[0]), "%g" % round(o[1] * 100, 2),
                                          "%d-%d" % (o[2], o[3]) if o[2] != o[3] else "%d" % o[2]) for o in b["out"])
        L.append("    {q=%d,class=%d,lo=%d,hi=%d,skill=%d%s,out={%s}}, -- %s %s: %s"
                 % (b["q"], b["class"], b["lo"], b["hi"], b["skill"], extra, outs, qn[b["q"]], cn[b["class"]], desc))
    L.append("  },")
    L.append("  noDE = {")
    ids = de["noDE"]
    for k in range(0, len(ids), 10):
        L.append("    " + "".join("[%d]=true," % i for i in ids[k:k + 10]))
    L.append("  },")
    L.append("  mats = {")
    for i in de["mats"]:
        L.append("    [%d]=true, -- %s" % (i, names(i)))
    L.append("  },")
    L.append("}")
    L.append("")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L))


# ---------------------------------------------------------------------------------------------------------------
# --check: load both files in Lua 5.1 (lupa) and verify them

def check(out_dir):
    try:
        import lupa.lua51 as lupa_mod
    except ImportError:
        try:
            import lupa as lupa_mod
        except ImportError:
            die("--check needs lupa (pip install lupa)")
    lua = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    WC = lua.table()
    globals_of = lua.eval("function() local n = {} for k in pairs(_G) do n[#n + 1] = tostring(k) end return table.concat(n, ' ') end")
    loader = lua.eval("function(s, n) local f, e = loadstring(s, n) if not f then error(e) end return f end")
    before = set(globals_of().split())
    for name in ("DataVendor.lua", "DataDisenchant.lua"):
        with open(os.path.join(out_dir, name), encoding="utf-8") as f:
            src = f.read()
        loader(src, "@" + name)("WaylaidCrate", WC)
    leaked = set(globals_of().split()) - before
    problems = []

    def ok(cond, msg):
        if not cond:
            problems.append(msg)

    V, DE = WC.VENDOR, WC.DE
    ok(V is not None and DE is not None, "WC.VENDOR / WC.DE missing")
    nv = 0
    for item, e in V.items():
        nv += 1
        ok(isinstance(item, int) and item > 0, "bad vendor key %r" % (item,))
        ok(isinstance(e.buy, (int, float)) and e.buy > 0, "%s: bad buy" % item)
        ok(isinstance(e.stack, int) and e.stack >= 1, "%s: bad stack" % item)
        ok(e.npcs is not None and len(e.npcs) >= 1, "%s: no npcs" % item)
        ok(not (e.seen and e.classic), "%s: both seen and classic" % item)
        for k, n in (e.npcs or {}).items():
            ok(isinstance(n[1], int) and isinstance(n[2], str) and isinstance(n[3], str), "%s: npc %s fields" % (item, k))
            for c in (n[4], n[5]):
                ok(c is None or (0 <= c <= 100), "%s: npc %s coord %r" % (item, k, c))
            ok(n[6] in ("A", "H", ""), "%s: npc %s faction %r" % (item, k, n[6]))
            ok(n[7] in (None, True), "%s: npc %s classic flag" % (item, k))
            if e.classic:
                ok(n[7] is True, "%s: classic entry with a non-classic npc" % item)
    bands = list(DE.bands.values())
    outs = set()
    for b in bands:
        tag = "band q%s c%s %s-%s" % (b.q, b["class"], b.lo, b.hi)
        ok(b.lo <= b.hi, tag + ": lo > hi")
        ok(b.q in (2, 3, 4) and b["class"] in (2, 4), tag + ": bad quality/class")
        ok(isinstance(b.skill, int) and b.skill >= 1, tag + ": bad skill")
        total = 0
        for o in b.out.values():
            total += o[2]
            outs.add(o[1])
            ok(1 <= o[3] <= o[4], tag + ": bad quantities")
            ok(DE.mats[o[1]] is True, tag + ": %s missing from mats" % o[1])
        ok(abs(total - 1) <= 0.001, tag + ": chances sum to %.4f" % total)
    ok(set(DE.mats.keys()) == outs, "mats has items that are no band output")
    ok(DE.spell == 13262, "spell id")

    def band(q, cls, ilvl):
        for b in bands:
            if b.q == q and b["class"] == cls and b.lo <= ilvl <= b.hi:
                return b
        return None

    def outmap(b):
        return {o[1]: (o[2], o[3], o[4]) for o in b.out.values()} if b else {}

    # spot checks
    e = V[2320]
    ok(e is not None and e.buy == 10 and e.stack == 1, "Coarse Thread 2320 should be buy 10 stack 1")
    e = V[3371]
    ok(e is not None and e.buy == 20 and e.stack == 5 and e.buy / e.stack == 4, "Empty Vial 3371 should be 20 per 5 (4c each)")
    ok(10940 in outmap(band(2, 4, 10)), "Strange Dust should come from uncommon armor 5-15")
    m = outmap(band(2, 4, 23))
    ok(m.get(10940) == (0.75, 4, 6) and m.get(10998) == (0.15, 1, 2) and m.get(10978) == (0.1, 1, 1),
       "uncommon armor 21-25 should be SD 75%% 4-6 / LAE 15%% 1-2 / SGS 10%% 1: %r" % (m,))
    m = outmap(band(2, 2, 23))
    ok(m.get(10998) == (0.75, 1, 2) and m.get(10940) == (0.15, 4, 6), "uncommon weapon 21-25 should be LAE 75 / SD 15")
    for lvl in (8, 18):
        b = band(3, 4, lvl)
        ok(b is not None and b.est is None and outmap(b).get(10978) == (1, 1, 1),
           "rare armor ilvl %d should be Small Glimmering Shard 100%% (Classic rare 1-25), no est" % lvl)
    b = band(3, 2, 21)
    ok(b is not None and b.lo == 21 and b.est is None, "rare weapon 21-25 band (Forever moved 20 -> 21)")
    for i in (11287, 11288, 11289):
        ok(DE.noDE[i] is True, "wand %d should be in noDE" % i)
    ok(DE.noDE[2589] is None, "Linen Cloth must not be in noDE")
    ok(DE.mats[247786] is None, "Mote of Magic is not a disenchant output")
    ok(not leaked, "files created globals: %s" % sorted(leaked))
    if problems:
        for p in problems:
            print("CHECK FAILED:", p)
        sys.exit(1)
    nnode = len(list(DE.noDE.keys()))
    print("check OK: %d vendor items, %d DE bands, %d noDE items, %d mats" % (nv, len(bands), nnode, len(outs)))


# ---------------------------------------------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db")
    ap.add_argument("--build", default="1.60.1.70450")
    ap.add_argument("--download", action="store_true")
    ap.add_argument("--sv", action="append", default=[])
    ap.add_argument("--pfquest")
    ap.add_argument("--out", default=os.path.join(HERE, "..", "WaylaidCrate"))
    ap.add_argument("--date", default=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"))
    ap.add_argument("--max-skill", type=int, default=300)
    ap.add_argument("--per-side", type=int, default=3)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    out = os.path.normpath(args.out)

    if args.db:
        if args.download:
            download(args.db, args.build)
        for t in TABLES:
            if not os.path.exists(os.path.join(args.db, t + ".csv")):
                die("missing %s.csv in %s (use --download)" % (t, args.db))
        sparse = {to_int(r["ID"]): r for r in read_csv(os.path.join(args.db, "ItemSparse.csv"))}
        items = {to_int(r["ID"]): r for r in read_csv(os.path.join(args.db, "Item.csv"))}
        stats = {}
        os.makedirs(out, exist_ok=True)
        vendor = build_vendor(args, sparse, items, stats)
        de = build_de(args, sparse, items, stats)
        write_vendor(os.path.join(out, "DataVendor.lua"), vendor, sparse, args, stats)
        write_de(os.path.join(out, "DataDisenchant.lua"), de, sparse, args, stats)
        if not args.quiet:
            print("WC.VENDOR: %d items = %d seen in the client + %d Classic-vendor reagents"
                  % (stats["vendor_total"], stats["seen"], stats["classic"]))
            print("  recipes <= %d skill: %d, distinct reagents %d, of which vendor-sold here %d"
                  % (args.max_skill, stats["recipes"], stats["reagents"], stats["reagents_covered"]))
            print("  seen items with a personal discount removed: %d" % stats["seen_discounted"])
            print("  seen only in an older build with another price (ItemSparse price used): %d" % len(stats["seen_stale"]))
            for m in stats["seen_stale"]:
                print("    %d %s: seen %d per %d in build %d" % m)
            print("  seen price/bundle differs from ItemSparse: %d" % len(stats["seen_db_mismatch"]))
            for m in stats["seen_db_mismatch"]:
                print("    %d %s: seen %d per %d, ItemSparse %d per %d" % m)
            print("  reagents sold by Classic vendors in limited stock only (left out): %d %s"
                  % (len(stats["limited_only"]), stats["limited_only"]))
            print("  reagents without a Forever BuyPrice (left out): %s" % stats["no_price"])
            print("  Classic NPCs dropped (seen in Forever not selling it / limited): %d" % stats["dropped_npcs"])
            print("WC.DE: %d bands (est=nearest: %s), %d noDE items, %d mats"
                  % (stats["bands"], ", ".join(stats["bands_est"]) or "-", stats["noDE"], stats["mats"]))
            if stats["bands_unknown"]:
                print("  bands without a Classic table (skipped): %s" % stats["bands_unknown"])
    elif not args.check:
        ap.error("--db is required to generate (or use --check alone)")
    if args.check:
        check(out)


if __name__ == "__main__":
    main()
