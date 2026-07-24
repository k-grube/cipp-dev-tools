#!/usr/bin/env python3
"""clear cipp reporting/test data out of the dev azurite table store.

the monorepo dev stack's CIS test engine snapshots full tenant graph state into
CippReportingDB (+ CippTestResults). azurite keeps every table in one json file loaded
as a single v8 string; past ~512MB azurite crash-loops on boot (v8 max string length is
0x1fffffe8, hardcoded, so the compose --max-old-space-size bump can't help). with a
realistic tenant set this bricks the dev stack in ~2 days.

python has no 512MB string cap, so it can read+rewrite the file azurite itself can no
longer load. this empties the heavy reporting tables in-place and leaves tenant config /
secrets / settings intact. cipp recreates + refills the tables on the next collection run,
so re-run this periodically (or trim the dev tenant set) to stay under the cap.

usage:
  python tools/clear-azurite-reporting.py --list            # show table row counts + file size
  python tools/clear-azurite-reporting.py                   # empty the default reporting tables
  python tools/clear-azurite-reporting.py --tables CippReportingDB,CippLogs
  python tools/clear-azurite-reporting.py --nuke -y         # delete the whole table db (all tables)
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

CONTAINER = "cipp-azurite"
VOLUME = "cipp-ng_azurite-data"
TABLE_DB = "/workspace/__azurite_db_table__.json"  # azurite --location /workspace
DEFAULT_TABLES = ["CippReportingDB", "CippTestResults", "CippStandardsReports"]
V8_STRING_CAP = 0x1fffffe8  # ~512MB, the size azurite dies at


def docker(*args, check=True):
    return subprocess.run(["docker", *args], check=check, capture_output=True, text=True)


def state(name):
    r = docker("inspect", "-f", "{{.State.Status}}", name, check=False)
    return "missing" if r.returncode != 0 else r.stdout.strip()


def db_size():
    # size on disk without loading, works whether azurite is up or bricked
    r = docker("run", "--rm", "-v", f"{VOLUME}:/w:ro", "alpine",
               "stat", "-c", "%s", TABLE_DB.replace("/workspace", "/w"), check=False)
    return int(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip().isdigit() else None


def pull_db(dst):
    docker("cp", f"{CONTAINER}:{TABLE_DB}", dst)


def push_db(src):
    docker("cp", src, f"{CONTAINER}:{TABLE_DB}")


def load(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def short_name(coll):
    n = coll.get("name", "")
    return n.split("$", 1)[1] if "$" in n else n


def empty_collection(coll):
    # reset a lokijs collection to empty without breaking azurite's load path
    coll["data"] = []
    coll["maxId"] = 0
    coll["dirty"] = True
    for k in ("idIndex", "dirtyIds", "changes"):
        if k in coll:
            coll[k] = []
    if isinstance(coll.get("binaryIndices"), dict):
        for idx in coll["binaryIndices"]:
            coll["binaryIndices"][idx] = {"name": idx, "dirty": False, "values": []}
    for cached in ("cachedIndex", "cachedBinaryIndex", "cachedData"):
        if cached in coll:
            coll[cached] = None


def cmd_list():
    sz = db_size()
    if sz is None:
        sys.exit("could not stat the table db (is the stack up?)")
    print(f"table db: {sz / 1e6:.1f} MB  (azurite dies at {V8_STRING_CAP / 1e6:.0f} MB)")
    if sz > V8_STRING_CAP * 0.85:
        print("  WARNING: approaching the 512MB cap, clear soon or azurite will crash-loop")
    with tempfile.TemporaryDirectory() as td:
        local = os.path.join(td, "t.json")
        pull_db(local)
        db = load(local)
    rows = sorted(((short_name(c), len(c.get("data", []))) for c in db.get("collections", [])),
                  key=lambda x: -x[1])
    print(f"{'table':40} rows")
    for name, n in rows:
        if n:
            print(f"{name:40} {n}")


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="show table row counts + file size, change nothing")
    ap.add_argument("--tables", default=",".join(DEFAULT_TABLES),
                    help=f"comma list to empty (default: {','.join(DEFAULT_TABLES)})")
    ap.add_argument("--nuke", action="store_true",
                    help="delete the whole table db (wipes ALL tables, not just reporting)")
    ap.add_argument("--no-restart", action="store_true", help="leave azurite stopped after")
    ap.add_argument("--keep-backup", action="store_true",
                    help="save the pre-edit table db to ./azurite_table_db.bak.json")
    ap.add_argument("-y", "--yes", action="store_true", help="skip the confirmation prompt")
    args = ap.parse_args()

    if docker("version", "-f", "{{.Server.Version}}", check=False).returncode != 0:
        sys.exit("docker not available")
    if state(CONTAINER) == "missing":
        sys.exit(f"container {CONTAINER} not found (bring the dev stack up first)")

    if args.list:
        cmd_list()
        return

    tables = [t.strip() for t in args.tables.split(",") if t.strip()]
    plan = "DELETE the entire table db (ALL tables)" if args.nuke else f"empty: {', '.join(tables)}"
    print(f"container: {CONTAINER} ({state(CONTAINER)})")
    print(f"action   : {plan}")
    if not args.yes and input("proceed? [y/N] ").strip().lower() not in ("y", "yes"):
        sys.exit("aborted")

    was_up = state(CONTAINER) in ("running", "restarting")
    if was_up:
        print("stopping azurite (breaks the restart loop)...")
        docker("stop", CONTAINER)

    if args.nuke:
        docker("run", "--rm", "--volumes-from", CONTAINER, "alpine", "rm", "-f", TABLE_DB)
        print("deleted table db")
    else:
        with tempfile.TemporaryDirectory() as td:
            local = os.path.join(td, "table.json")
            print("copying table db out...")
            pull_db(local)
            before = os.path.getsize(local)
            if args.keep_backup:
                bak = os.path.abspath("azurite_table_db.bak.json")
                shutil.copy2(local, bak)
                print(f"backup: {bak}")
            print(f"loading {before / 1e6:.1f} MB json...")
            db = load(local)
            wanted = set(tables) | {f"devstoreaccount1${t}" for t in tables}
            emptied = []
            for coll in db.get("collections", []):
                if coll.get("name") in wanted or short_name(coll) in tables:
                    emptied.append((short_name(coll), len(coll.get("data", []))))
                    empty_collection(coll)
            if not emptied:
                print(f"no matching tables found (have: {', '.join(sorted(short_name(c) for c in db.get('collections', [])))})")
            else:
                with open(local, "w", encoding="utf-8") as f:
                    json.dump(db, f, separators=(",", ":"))
                after = os.path.getsize(local)
                print("copying table db back...")
                push_db(local)
                print("emptied " + ", ".join(f"{t} ({n} rows)" for t, n in emptied))
                print(f"size: {before / 1e6:.1f} MB -> {after / 1e6:.1f} MB")

    if args.no_restart:
        print("left azurite stopped (--no-restart)")
        return
    print("starting azurite...")
    docker("start", CONTAINER)
    time.sleep(4)
    st = state(CONTAINER)
    print(f"azurite: {st}")
    if st == "restarting":
        print("WARNING: still crash-looping — the surgery left an unloadable db. re-run with --nuke.")
    else:
        sz = db_size()
        if sz is not None:
            print(f"table db now {sz / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
