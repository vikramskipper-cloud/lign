#!/usr/bin/env python3
"""Proves every object in the deployed database traces to supabase/migrations/.

Three checks, all against the migration files as the reference:

  1. FORWARD   every live object is CREATEd by some migration
               (catches objects made out-of-band via execute_sql or the dashboard)
  2. REVERSE   every object a migration creates is live, or explicitly DROPped
               by a later migration (catches out-of-band deletions)
  3. BODIES    every function's prosrc is byte-identical to a definition in the
               migrations (catches out-of-band CREATE OR REPLACE)

This is provenance, not a replay. It does not prove the migrations apply
cleanly in order into an empty database -- only a shadow-database replay
(`supabase db diff`, or a Supabase preview branch) does that.

Usage:
    psql "$SUPABASE_DB_URL" -At -F$'\t' -f ops/schema_inventory.sql > /tmp/inv.tsv
    ops/audit_schema_provenance.py /tmp/inv.tsv

Exit codes: 0 clean - 1 discrepancies found - 2 usage error.
"""
import collections
import glob
import hashlib
import os
import re
import sys

KINDS = ["TABLE", "POLICY", "TRIGGER", "FUNCTION", "INDEX"]
CREATE = {
    "TABLE":    r"create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?\"?{n}\"?\b",
    "POLICY":   r'create\s+policy\s+"?{n}"?',
    "TRIGGER":  r"create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+{n}\b",
    "FUNCTION": r"create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?{n}\s*\(",
    "INDEX":    r"create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?{n}\b",
}
HARVEST = {
    "TABLE":    r"create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?\"?([a-z0-9_]+)\"?",
    "POLICY":   r'create\s+policy\s+"?([a-z0-9_]+)"?',
    "TRIGGER":  r"create\s+(?:or\s+replace\s+)?trigger\s+\"?([a-z0-9_]+)\"?",
    "FUNCTION": r"create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?\"?([a-z0-9_]+)\"?\s*\(",
    "INDEX":    r"create\s+(?:unique\s+)?index\s+(?:concurrently\s+)?(?:if\s+not\s+exists\s+)?\"?([a-z0-9_]+)\"?",
}


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = sorted(glob.glob(os.path.join(root, "supabase/migrations/*.sql")))
    if not files:
        print("error: no migration files found", file=sys.stderr)
        return 2
    raw = {f: open(f, encoding="utf-8").read() for f in files}
    low = "\n".join(v.lower() for v in raw.values())

    prod = collections.defaultdict(list)
    for line in open(argv[1], encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 4:
            parts += [""] * (4 - len(parts))
        kind, name, parent, deff = parts[:4]
        if kind in KINDS:
            prod[kind].append((name.lower(), parent.lower(), deff))

    problems = []

    # 1. forward
    tables = {n for n, _, _ in prod["TABLE"]
              if re.search(CREATE["TABLE"].format(n=re.escape(n)), low, re.S)}
    print("FORWARD  every live object is created by a migration")
    for kind in KINDS:
        counts = collections.Counter()
        for name, parent, _ in prod[kind]:
            if re.search(CREATE[kind].format(n=re.escape(name)), low, re.S):
                counts["ok"] += 1
            elif kind == "INDEX" and re.search(r"\b" + re.escape(name) + r"\b", low):
                counts["ok-constraint"] += 1        # index backing a named constraint
            elif kind == "INDEX" and (name.endswith("_pkey") or name.endswith("_key")) and parent in tables:
                counts["ok-implied"] += 1           # auto-named by PRIMARY KEY / UNIQUE
            else:
                counts["ORPHAN"] += 1
                problems.append(f"ORPHAN    {kind:<9} {name}" + (f" (on {parent})" if parent else ""))
        print(f"  {kind:<9} {len(prod[kind]):>4}  " +
              "  ".join(f"{k}={v}" for k, v in sorted(counts.items())))

    # 2. reverse
    dropped = set(re.findall(
        r"drop\s+(?:table|policy|trigger|function|index)\s+(?:if\s+exists\s+)?"
        r"(?:concurrently\s+)?(?:public\.)?\"?([a-z0-9_]+)\"?", low))
    print("\nREVERSE  every migration-created object is live or explicitly dropped")
    for kind in KINDS:
        live = {n for n, _, _ in prod[kind]}
        made = set(re.findall(HARVEST[kind], low))
        gone = made - live
        unexplained = gone - dropped
        print(f"  {kind:<9} created={len(made):>4}  live={len(made & live):>4}  "
              f"dropped={len(gone & dropped):>3}  UNEXPLAINED={len(unexplained)}")
        for n in sorted(unexplained):
            problems.append(f"MISSING   {kind:<9} {n} (created by a migration, absent from the database)")

    # 3. function bodies
    defined = collections.defaultdict(set)
    rx = re.compile(r"create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?\"?(\w+)\"?\s*\(", re.I)
    for text in raw.values():
        for m in rx.finditer(text):
            tag = re.search(r"\$(\w*)\$", text[m.end():m.end() + 4000])
            if not tag:
                continue
            delim = "$" + tag.group(1) + "$"
            start = m.end() + tag.end()
            end = text.find(delim, start)
            if end != -1:
                defined[m.group(1).lower()].add(hashlib.md5(text[start:end].encode()).hexdigest())
    matched = 0
    for name, args, live_md5 in prod["FUNCTION"]:
        if live_md5 in defined.get(name, ()):
            matched += 1
        else:
            problems.append(f"BODY      FUNCTION  {name}({args[:60]}) differs from every migration definition")
    print(f"\nBODIES   function bodies byte-identical to a migration definition: "
          f"{matched}/{len(prod['FUNCTION'])}")

    print("\n" + "-" * 60)
    if problems:
        print(f"RESULT: FAIL - {len(problems)} discrepancies\n")
        for p in problems:
            print("  " + p)
        return 1
    print("RESULT: PASS - the deployed schema is fully accounted for by supabase/migrations/")
    print("NOTE:   provenance only; a shadow-database replay is still the stronger test.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
