#!/usr/bin/env python3
"""Send commands to Wiz bulbs by name, room, or all.

Usage:
  ctl.py <name> on
  ctl.py <name> off
  ctl.py <name> preset <token>
  ctl.py <name> set '<json>'
  ctl.py --room <room> on|off|preset <token>|set <json>
  ctl.py --all          on|off|preset <token>|set <json>

"on" with no preset uses the device's `default` preset, or {"state": true}.
"""

from __future__ import annotations

import argparse
import json
import sys

from _wiz import (
    devices_in_room,
    find_device,
    load_registry,
    resolve_preset,
    send,
)


def params_for_action(registry: dict, device: dict, action: str, arg: str | None) -> dict:
    if action == "off":
        return {"state": False}
    if action == "on":
        token = device.get("default")
        if token:
            return resolve_preset(registry["presets"], token)
        return {"state": True}
    if action == "preset":
        if not arg:
            raise SystemExit("preset requires a token")
        return resolve_preset(registry["presets"], arg)
    if action == "set":
        if not arg:
            raise SystemExit("set requires a JSON object")
        value = json.loads(arg)
        if not isinstance(value, dict):
            raise SystemExit("set expects a JSON object")
        return value
    raise SystemExit(f"unknown action {action!r}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    target = ap.add_mutually_exclusive_group()
    target.add_argument("--room", help="target all bulbs in a room")
    target.add_argument("--all", action="store_true", help="target every known bulb")
    ap.add_argument("name", nargs="?", help="device name or MAC (when no --room/--all)")
    ap.add_argument("action", choices=["on", "off", "preset", "set"])
    ap.add_argument("arg", nargs="?", help="preset token or JSON for 'set'")
    args = ap.parse_args()

    registry = load_registry()

    if args.room:
        targets = devices_in_room(registry, args.room)
        if not targets:
            print(f"No devices in room {args.room!r}", file=sys.stderr)
            return 1
    elif args.all:
        targets = registry["devices"]
        if not targets:
            print("Registry is empty — run label.py first.", file=sys.stderr)
            return 1
    else:
        if not args.name:
            ap.error("give a device name, --room, or --all")
        d = find_device(registry, args.name)
        if not d:
            print(f"Unknown device {args.name!r}", file=sys.stderr)
            return 1
        targets = [d]

    failures = 0
    for d in targets:
        try:
            payload = params_for_action(registry, d, args.action, args.arg)
            reply = send(d["ip"], {"method": "setPilot", "params": payload})
            ok = (reply.get("result") or {}).get("success")
            label = d.get("name") or d.get("mac")
            print(f"{label:<20} {d['ip']:<16} {'ok' if ok else 'fail'}  {json.dumps(payload)}")
            if not ok:
                failures += 1
        except OSError as e:
            failures += 1
            print(f"{d.get('name','?')} {d['ip']} error: {e}", file=sys.stderr)

    return 0 if failures == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
