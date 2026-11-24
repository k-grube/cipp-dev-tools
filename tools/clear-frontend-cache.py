#!/usr/bin/env python3
"""delete the CIPP frontend's generated next output (dev + build).

usage:
  python tools/clear-frontend-cache.py          # out/ + .next/
  python tools/clear-frontend-cache.py --all    # + storybook and vite caches under node_modules
"""
import argparse
import os
import shutil
import socket
import sys

FRONTEND = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "CIPP", "frontend")
NEXT_DIRS = ["out", ".next"]  # distDir in next.config.js, plus next's default
TOOL_DIRS = ["node_modules/.cache", "node_modules/.vite"]  # storybook, vite dep optimizer
DEV_PORTS = {3000: "next dev", 6006: "storybook"}


def listening(port):
    with socket.socket() as s:
        s.settimeout(0.5)
        return s.connect_ex(("127.0.0.1", port)) == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true", help="also drop the storybook + vite caches under node_modules")
    args = ap.parse_args()

    busy = [p for p in ([3000, 6006] if args.all else [3000]) if listening(p)]
    if busy:
        sys.exit("stop the dev server first: " + ", ".join(f"{DEV_PORTS[p]} on :{p}" for p in busy))

    removed = []
    for rel in NEXT_DIRS + (TOOL_DIRS if args.all else []):
        path = os.path.join(FRONTEND, rel)
        if os.path.isdir(path):
            # out/dev/node_modules holds junctions into the real node_modules, rmtree unlinks them without descending
            shutil.rmtree(path)
            removed.append(rel)
    print("removed " + ", ".join(removed) if removed else "nothing to clear")


if __name__ == "__main__":
    main()
