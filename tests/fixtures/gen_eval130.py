#!/usr/bin/env python3
"""Regenerate tests/fixtures/eval_130.json: crate / writ evaluations computed by WaylaidCrate 1.3.0 (git be084d5)
for the deterministic 1.3.0 test market (tests/test_merge.py MARKET_130), run inside tests/wowmock.py.
The merged addon must produce identical numbers (scenario crates_writs_130)."""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tests"))
from wowmock import WowClient            # noqa: E402
import test_merge as T                   # noqa: E402

REV = "be084d5"
out_dir = tempfile.mkdtemp(prefix="wc130-")
addon = os.path.join(out_dir, "WaylaidCrate")
os.makedirs(addon)
files = subprocess.check_output(["git", "-C", REPO, "ls-tree", "--name-only", REV, "WaylaidCrate/"], text=True).split()
for f in files:
    data = subprocess.check_output(["git", "-C", REPO, "show", "%s:%s" % (REV, f)])
    with open(os.path.join(out_dir, f), "wb") as fh:
        fh.write(data)
c = WowClient(locale="enUS", strict=False)
c.load_addon(os.path.join(addon, "WaylaidCrate.toc"))
c.login()
res = T.run_market_130(c)
problems = c.problems()
res["source"] = "WaylaidCrate 1.3.0 (git %s) in tests/wowmock.py, MARKET_130" % REV
json.dump(res, open(os.path.join(HERE, "eval_130.json"), "w"), indent=1, sort_keys=True)
print("crates", len(res["after_crates"]["crates"]), "writs", len(res["after_writs"]["writs"]))
print("problems seen while running 1.3.0 (informational):", problems[:10])
