#!/usr/bin/env python3
"""empty cipp reporting/test tables in the dev azurite table store, tenant config and secrets stay.

works on the paged table db (shell + one file per page of rows) and the legacy single json file.

usage:
  python tools/clear-azurite-reporting.py --list            # show table row counts + size on disk
  python tools/clear-azurite-reporting.py                   # empty the default reporting tables
  python tools/clear-azurite-reporting.py --tables CippReportingDB,CippLogs
  python tools/clear-azurite-reporting.py --nuke -y         # delete the whole table db (all tables)
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

CONTAINER = "cipp-azurite"
VOLUME = "cipp-ng_azurite-data"
DB_NAME = "__azurite_db_table__.json"
TABLE_DB = f"/workspace/{DB_NAME}"  # azurite --location /workspace
DEFAULT_TABLES = ["CippReportingDB", "CippTestResults", "CippStandardsReports"]
V8_STRING_CAP = 0x1fffffe8  # ~512MB, the size azurite dies at loading a legacy single-file db
FIND_DB = f"find /w -maxdepth 1 -name '{DB_NAME}*'"  # shell (or legacy db) + page files


def docker(*args, check=True, **kwargs):
    kwargs.setdefault("capture_output", True)
    return subprocess.run(["docker", *args], check=check, text=True, **kwargs)


def in_volume(script, mode="ro", **kwargs):
    # works whether azurite is up, stopped or bricked
    stdin = ["-i"] if "input" in kwargs else []
    return docker("run", "--rm", *stdin, "-v", f"{VOLUME}:/w:{mode}", "alpine", "sh", "-c", script, **kwargs)


def state(name):
    r = docker("inspect", "-f", "{{.State.Status}}", name, check=False)
    return "missing" if r.returncode != 0 else r.stdout.strip()


def db_size():
    r = in_volume(FIND_DB + " -exec stat -c %s {} + | awk '{s += $1} END {print s + 0}'", check=False)
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


def page_rows():
    # page file name -> row count, rows are newline-joined with no trailing newline
    rows = {}
    for line in in_volume(FIND_DB + " -exec wc -l {} +").stdout.splitlines():
        count, path = line.split(None, 1)
        if path != "total":
            rows[os.path.basename(path)] = int(count) + 1
    return rows


def row_counts(db):
    # the paged shell lists each collection's page files under "pages", a legacy db holds the rows inline
    pages = db.get("pages")
    if pages is None:
        return {c["name"]: len(c.get("data", [])) for c in db.get("collections", [])}
    rows = page_rows()
    return {name: sum(rows.get(os.path.basename(f), 0) for f in files) for name, files in pages.items()}


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
    if not sz:
        sys.exit("could not stat the table db (is the stack up?)")
    with tempfile.TemporaryDirectory() as td:
        local = os.path.join(td, "t.json")
        pull_db(local)
        db = load(local)
    if "pages" in db:
        print(f"table db: {sz / 1e6:.1f} MB  (paged)")
    else:
        print(f"table db: {sz / 1e6:.1f} MB  (single file, azurite dies at {V8_STRING_CAP / 1e6:.0f} MB)")
        if sz > V8_STRING_CAP * 0.85:
            print("  WARNING: approaching the 512MB cap, clear soon or azurite will crash-loop")
    counts = row_counts(db)
    rows = sorted(((short_name(c), counts.get(c["name"], 0)) for c in db.get("collections", [])),
                  key=lambda x: -x[1])
    print(f"{'table':40} rows")
    for name, n in rows:
        if n:
            print(f"{name:40} {n}")


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="show table row counts + size on disk, change nothing")
    ap.add_argument("--tables", default=",".join(DEFAULT_TABLES),
                    help=f"comma list to empty (default: {','.join(DEFAULT_TABLES)})")
    ap.add_argument("--nuke", action="store_true",
                    help="delete the whole table db (wipes ALL tables, not just reporting)")
    ap.add_argument("--no-restart", action="store_true", help="leave azurite stopped after")
    ap.add_argument("--keep-backup", action="store_true",
                    help="save the pre-edit table db to ./azurite_table_db.bak.tar")
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

    if args.keep_backup:
        bak = os.path.abspath("azurite_table_db.bak.tar")
        with open(bak, "wb") as f:
            subprocess.run(["docker", "run", "--rm", "-v", f"{VOLUME}:/w:ro", "alpine", "sh", "-c",
                            f"cd /w && find . -maxdepth 1 -name '{DB_NAME}*' | tar -cf - -T -"],
                           check=True, stdout=f)
        print(f"backup: {bak}")

    if args.nuke:
        in_volume(FIND_DB + " -exec rm -f {} +", mode="rw")
        print("deleted table db")
    else:
        with tempfile.TemporaryDirectory() as td:
            local = os.path.join(td, "table.json")
            before = db_size()
            print("copying table db out...")
            pull_db(local)
            db = load(local)
            counts = row_counts(db)
            pages = db.get("pages")
            wanted = set(tables) | {f"devstoreaccount1${t}" for t in tables}
            emptied = []
            stale = []
            for coll in db.get("collections", []):
                if coll.get("name") in wanted or short_name(coll) in tables:
                    emptied.append((short_name(coll), counts.get(coll["name"], 0)))
                    empty_collection(coll)
                    if pages is not None:
                        stale += [os.path.basename(f) for f in pages.get(coll["name"], [])]
                        pages[coll["name"]] = []
            if not emptied:
                print(f"no matching tables found (have: {', '.join(sorted(short_name(c) for c in db.get('collections', [])))})")
            else:
                with open(local, "w", encoding="utf-8") as f:
                    json.dump(db, f, separators=(",", ":"))
                print("copying table db back...")
                push_db(local)
                # shell goes back first, a manifest entry without its page file stops azurite loading
                if stale:
                    in_volume("cd /w && xargs rm -f", mode="rw", input="\n".join(stale))
                print("emptied " + ", ".join(f"{t} ({n} rows)" for t, n in emptied))
                print(f"size: {before / 1e6:.1f} MB -> {db_size() / 1e6:.1f} MB")

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
