#!/usr/bin/env python3
"""Interactively label newly discovered Wiz bulbs.

For each unknown bulb (by MAC), pulse it so the user can identify it, then
prompt for name/room/default preset. Refreshes cached IPs for known bulbs.
"""

from __future__ import annotations

import argparse
import sys

from _wiz import (
    discover,
    load_registry,
    mac_of,
    registry_path,
    save_registry,
    send,
    summarize_state,
)


def prompt(question: str, default: str = "") -> str:
    suffix = f" [{default}]" if default else ""
    try:
        answer = input(f"{question}{suffix}: ").strip()
    except EOFError:
        return default
    return answer or default


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--broadcast", default="255.255.255.255")
    ap.add_argument("--timeout", type=float, default=2.0)
    ap.add_argument("--pulse-delta", type=int, default=-50,
                    help="pulse dimming delta (default: -50)")
    ap.add_argument("--pulse-ms", type=int, default=500,
                    help="pulse duration in ms (default: 500)")
    args = ap.parse_args()

    registry = load_registry()
    by_mac = {d["mac"].lower(): d for d in registry["devices"]}

    bulbs = discover(broadcast=args.broadcast, timeout=args.timeout)
    if not bulbs:
        print("No bulbs found.", file=sys.stderr)
        return 1

    updated = 0
    added = 0

    for b in bulbs:
        ip = b["ip"]
        reply = b["reply"].get("result") or {}
        mac = (mac_of(b["reply"]) or "").lower()
        if not mac:
            print(f"  {ip}: no MAC in reply, skipping", file=sys.stderr)
            continue

        existing = by_mac.get(mac)
        if existing:
            if existing.get("ip") != ip:
                existing["ip"] = ip
                updated += 1
            continue

        print(f"\nUnknown bulb at {ip} (mac {mac}) — currently {summarize_state(reply)}")
        print("  flashing it now...")
        try:
            send(ip, {"method": "pulse", "params": {
                "delta": args.pulse_delta, "duration": args.pulse_ms,
            }})
        except OSError as e:
            print(f"  pulse failed: {e}", file=sys.stderr)

        name = prompt("  name (blank = skip)")
        if not name:
            print("  skipped")
            continue
        room = prompt("  room", default="")
        default_preset = prompt("  default preset (blank = none)", default="")
        notes = prompt("  notes", default="")

        record = {"mac": mac, "ip": ip, "name": name, "room": room}
        if default_preset:
            record["default"] = default_preset
        if notes:
            record["notes"] = notes
        registry["devices"].append(record)
        by_mac[mac] = record
        added += 1

    if added or updated:
        path = save_registry(registry)
        print(f"\nSaved {path} (added {added}, refreshed IP for {updated})")
    else:
        print("\nNo changes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
