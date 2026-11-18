#!/usr/bin/env python3
"""Merge the bundle's settings into an existing ~/.claude/settings.json.

Rules:
- Objects are merged key by key; the bundle wins on scalar conflicts.
- permissions.allow / deny / ask lists are left alone (only defaultMode is set).
- Hook entries are appended, skipping any whose command is already present.
- enabledPlugins gets the plugins passed with --enable.

Usage: merge_settings.py BASE TARGET --rtk-hook PATH [--enable p@m ...] [--dry-run]
"""
import argparse
import copy
import json
import os
import sys


def merge(dst, src):
    for key, val in src.items():
        if key == "hooks":
            dst[key] = merge_hooks(dst.get(key, {}), val)
        elif isinstance(val, dict) and isinstance(dst.get(key), dict):
            merge(dst[key], val)
        else:
            dst[key] = copy.deepcopy(val)
    return dst


def existing_commands(entries):
    return {h.get("command") for e in entries for h in e.get("hooks", [])}


def merge_hooks(dst, src):
    out = copy.deepcopy(dst)
    for event, entries in src.items():
        current = out.setdefault(event, [])
        seen = existing_commands(current)
        for entry in entries:
            if existing_commands([entry]) - seen:
                current.append(copy.deepcopy(entry))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("target")
    ap.add_argument("--rtk-hook", required=True)
    ap.add_argument("--enable", nargs="*", default=[])
    ap.add_argument("--no-rtk", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    with open(args.base) as f:
        base = json.loads(f.read().replace("__RTK_HOOK_PATH__", args.rtk_hook))
    if args.no_rtk:
        base.pop("hooks", None)
    if args.enable:
        base.setdefault("enabledPlugins", {}).update({p: True for p in args.enable})

    target = {}
    if os.path.exists(args.target):
        with open(args.target) as f:
            text = f.read().strip()
            target = json.loads(text) if text else {}

    merged = merge(copy.deepcopy(target), base)
    rendered = json.dumps(merged, indent=2) + "\n"

    if args.dry_run:
        sys.stdout.write(rendered)
        return
    tmp = args.target + ".tmp"
    with open(tmp, "w") as f:
        f.write(rendered)
    os.replace(tmp, args.target)
    print(f"  settings merged into {args.target}")


if __name__ == "__main__":
    main()
