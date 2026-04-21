---
name: wiz
description: Discover, label, and control Wiz (Signify) smart bulbs over the local UDP API on port 38899. Use when the user wants to find bulbs on the LAN, name them, assign rooms, set presets, or issue on/off/scene/color commands. Persists device metadata to a JSON file (path configurable via WIZ_DEVICES_PATH).
---

# Wiz bulb management

Wiz bulbs expose a local JSON-over-UDP API on port `38899`. This skill manages
a registry of known bulbs keyed by MAC address, plus a preset library, and
issues `setPilot` commands to individual bulbs, rooms, or groups.

## Storage

Registry file location, in order of precedence:

1. `$WIZ_DEVICES_PATH` env var (absolute path)
2. `~/.config/wiz/devices.json` (default)

The file is created on first write. A starter template lives at
`devices.example.json` in this skill directory — copy it if you want to
hand-edit.

### Schema

```json
{
  "presets": {
    "warm":    {"state": true, "temp": 2700, "dimming": 80},
    "bright":  {"state": true, "temp": 4000, "dimming": 100},
    "cozy":    {"state": true, "sceneId": 6, "dimming": 50},
    "off":     {"state": false},
    "evening": "warm"
  },
  "devices": [
    {
      "mac":     "444f8e292f4c",
      "ip":      "192.168.1.13",
      "name":    "desk",
      "room":    "office",
      "default": "warm",
      "notes":   ""
    }
  ]
}
```

Preset values are either an object (literal `setPilot` params) or a string
token pointing at another preset. Resolution follows tokens until an object is
found; cycles raise an error. Device `default` is a preset token used when the
user says "turn on X" without specifying state. `mac` is the stable key; `ip`
is refreshed on each discover.

## Scripts

All scripts live in this directory. Invoke with the skill's working directory
as the CWD, or with absolute paths.

### `discover.py` — find bulbs

```bash
python3 .claude/skills/wiz/discover.py
```

Broadcasts `getPilot` to `255.255.255.255:38899`, collects replies for ~2s,
and prints a table of `IP  MAC  known-name  state`.

Flags:
- `--json` — emit the raw reply list
- `--broadcast ADDR` — use a specific broadcast address (e.g. `192.168.1.255`)
  when the default doesn't reach the IoT VLAN
- `--timeout SECONDS` — discovery window, default 2.0

### `label.py` — interactive label workflow

```bash
python3 .claude/skills/wiz/label.py
```

For each discovered bulb that isn't yet in the registry:

1. Send `pulse` so the bulb visibly flashes
2. Prompt for `name`, `room`, and optional `default` preset token
3. Merge into the registry and save

Re-running is safe: existing MACs get their `ip` refreshed; unknown bulbs
trigger the prompt flow.

### `ctl.py` — send commands

```bash
# By device name
python3 .claude/skills/wiz/ctl.py desk on
python3 .claude/skills/wiz/ctl.py desk off
python3 .claude/skills/wiz/ctl.py desk preset warm
python3 .claude/skills/wiz/ctl.py desk set '{"temp":3000,"dimming":60}'

# By room
python3 .claude/skills/wiz/ctl.py --room office off

# All bulbs
python3 .claude/skills/wiz/ctl.py --all off
```

`on` with no preset uses the device's `default` preset; `on` with no default
defined falls back to `{"state": true}`.

## When to invoke

Reach for this skill when the user asks to:

- Find / list / discover Wiz bulbs on the network
- Name a bulb, assign it to a room, or edit its metadata
- Turn bulbs on or off, change color / temperature / scene
- Define or apply a preset
- Run the same command across a room or all bulbs

Don't invoke for non-Wiz smart-home gear (Hue, LIFX, Matter-only devices).

## Migration notes

- The registry path is intentionally configurable. When the Mac mini becomes
  the home server, mount its share and set `WIZ_DEVICES_PATH` to the mounted
  file — no skill changes needed.
- Later, if an HTTP service takes over, add a backend adapter that reads/writes
  via HTTP when the path starts with `http(s)://`. Until then, keep it file-only.

## Protocol cheat-sheet

UDP 38899, JSON, one request → one response.

| Method | Purpose |
|---|---|
| `getPilot` | Read state |
| `setPilot` | Change state (state, dimming, temp, r/g/b, sceneId, speed) |
| `getSystemConfig` | Firmware, module, MAC |
| `pulse` | Brief flash (identify a bulb) |
| `reboot` | Restart |

`setPilot` mode fields (pick one): `temp` (2200–6500 K) · `r`/`g`/`b`
(0–255) · `sceneId` (1–32). `state`, `dimming` (10–100), and `speed`
(20–200) combine with any mode.
