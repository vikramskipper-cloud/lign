#!/usr/bin/env python3
"""Diff a replayed shadow database against production, object by object."""
import sys, collections

import re
def norm(s):
    # the two sides are extracted by different paths (MCP/JSON vs psql), so
    # collapse every whitespace run before comparing definitions
    return re.sub(r"\s+", " ", s).strip()

def load(path):
    d = {}
    for line in open(path, encoding="utf-8"):
        p = line.rstrip("\n").split("\t")
        p += [""] * (4 - len(p))
        kind, name, parent, deff = p[:4]
        if kind:
            d[(kind, name, norm(parent))] = norm(deff)
    return d

prod, shadow = load(sys.argv[1]), load(sys.argv[2])
kinds = ["TABLE", "POLICY", "TRIGGER", "FUNCTION", "INDEX", "GRANT"]
only_prod = sorted(set(prod) - set(shadow))
only_shadow = sorted(set(shadow) - set(prod))
both = set(prod) & set(shadow)
difdef = sorted(k for k in both if prod[k] != shadow[k])

print(f"production objects: {len(prod)}")
print(f"shadow objects:     {len(shadow)}\n")
print(f"{'kind':<9} {'prod':>5} {'shadow':>7} {'prod-only':>10} {'shadow-only':>12} {'def-differs':>12}")
for k in kinds:
    p = sum(1 for x in prod if x[0] == k); s = sum(1 for x in shadow if x[0] == k)
    po = sum(1 for x in only_prod if x[0] == k); so = sum(1 for x in only_shadow if x[0] == k)
    dd = sum(1 for x in difdef if x[0] == k)
    print(f"{k:<9} {p:>5} {s:>7} {po:>10} {so:>12} {dd:>12}")

def show(title, items, fmt):
    if not items: return
    print(f"\n{title} ({len(items)})")
    for k, n, par in items[:40]:
        print(fmt.format(k=k, n=n, par=par))
    if len(items) > 40: print(f"  ... and {len(items)-40} more")

show("IN PRODUCTION BUT NOT IN THE REPLAY  (created out-of-band)", only_prod,
     "  {k:<9} {n} {par}")
show("IN THE REPLAY BUT NOT IN PRODUCTION  (dropped out-of-band)", only_shadow,
     "  {k:<9} {n} {par}")
if difdef:
    print(f"\nDEFINITION DIFFERS ({len(difdef)})  <- out-of-band ALTER / CREATE OR REPLACE")
    for k, n, par in difdef[:25]:
        print(f"  {k:<9} {n} {par}")
        print(f"      prod  : {prod[(k,n,par)][:150]}")
        print(f"      shadow: {shadow[(k,n,par)][:150]}")
    if len(difdef) > 25: print(f"  ... and {len(difdef)-25} more")

print("\n" + "-"*60)
if not (only_prod or only_shadow or difdef):
    print("RESULT: IDENTICAL - replaying supabase/migrations/ reproduces production exactly.")
    sys.exit(0)
print(f"RESULT: {len(only_prod)+len(only_shadow)+len(difdef)} discrepancies")
sys.exit(1)
