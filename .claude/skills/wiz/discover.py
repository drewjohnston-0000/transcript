#!/usr/bin/env python3
"""Discover Wiz bulbs on the LAN by broadcasting getPilot."""

from __future__ import annotations

import argparse
import json
import sys

from _wiz import discover, load_registry, mac_of, summarize_state


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--broadcast", default="255.255.255.255",
                    help="broadcast address (default: 255.255.255.255)")
    ap.add_argument("--timeout", type=float, default=2.0,
                    help="seconds to collect replies (default: 2.0)")
    ap.add_argument("--json", action="store_true",
                    help="emit raw replies as JSON")
    args = ap.parse_args()

    bulbs = discover(broadcast=args.broadcast, timeout=args.timeout)

    if args.json:
        json.dump(bulbs, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

    if not bulbs:
        print("No bulbs found.", file=sys.stderr)
        return 1

    registry = load_registry()
    by_mac = {d["mac"].lower(): d for d in registry["devices"]}

    print(f"{'IP':<16} {'MAC':<14} {'NAME':<20} {'ROOM':<14} STATE")
    for b in bulbs:
        mac = (mac_of(b["reply"]) or "").lower()
        known = by_mac.get(mac, {})
        name = known.get("name", "-")
        room = known.get("room", "-")
        state = summarize_state((b["reply"].get("result") or {}))
        print(f"{b['ip']:<16} {mac:<14} {name:<20} {room:<14} {state}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
