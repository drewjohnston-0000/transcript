"""Shared helpers for the wiz skill: registry I/O, preset resolution, UDP."""

from __future__ import annotations

import json
import os
import socket
import time
from pathlib import Path

PORT = 38899


def registry_path() -> Path:
    override = os.environ.get("WIZ_DEVICES_PATH")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".config" / "wiz" / "devices.json"


def load_registry() -> dict:
    path = registry_path()
    if not path.exists():
        return {"presets": {}, "devices": []}
    with path.open() as f:
        data = json.load(f)
    data.setdefault("presets", {})
    data.setdefault("devices", [])
    return data


def save_registry(data: dict) -> Path:
    path = registry_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")
    tmp.replace(path)
    return path


def find_device(registry: dict, query: str) -> dict | None:
    q = query.lower()
    for d in registry["devices"]:
        if d.get("name", "").lower() == q or d.get("mac", "").lower() == q:
            return d
    return None


def devices_in_room(registry: dict, room: str) -> list[dict]:
    r = room.lower()
    return [d for d in registry["devices"] if d.get("room", "").lower() == r]


def resolve_preset(presets: dict, token: str, _seen: set[str] | None = None) -> dict:
    """Follow string tokens through `presets` until an object is reached.

    Raises ValueError on unknown tokens or cycles.
    """
    seen = _seen or set()
    if token in seen:
        raise ValueError(f"preset cycle through {token!r}")
    if token not in presets:
        raise ValueError(f"unknown preset {token!r}")
    value = presets[token]
    if isinstance(value, str):
        return resolve_preset(presets, value, seen | {token})
    if not isinstance(value, dict):
        raise ValueError(f"preset {token!r} must be dict or token, got {type(value).__name__}")
    return dict(value)


def send(ip: str, payload: dict, timeout: float = 1.0) -> dict:
    """Send one UDP request to a bulb and return its decoded reply."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.settimeout(timeout)
        s.sendto(json.dumps(payload).encode(), (ip, PORT))
        data, _ = s.recvfrom(2048)
    finally:
        s.close()
    return json.loads(data)


def discover(broadcast: str = "255.255.255.255", timeout: float = 2.0) -> list[dict]:
    """Broadcast getPilot and collect replies.

    Returns a list of {"ip": str, "reply": dict}, one per responding bulb.
    """
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.settimeout(0.2)
        s.sendto(b'{"method":"getPilot","params":{}}', (broadcast, PORT))
        seen: dict[str, dict] = {}
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                data, (ip, _) = s.recvfrom(2048)
            except socket.timeout:
                continue
            try:
                seen[ip] = json.loads(data)
            except json.JSONDecodeError:
                continue
    finally:
        s.close()
    return [{"ip": ip, "reply": reply} for ip, reply in sorted(seen.items())]


def mac_of(reply: dict) -> str | None:
    return (reply.get("result") or {}).get("mac")


def summarize_state(result: dict) -> str:
    """Short human-readable state blurb from a getPilot result."""
    if not result.get("state"):
        return "off"
    parts = []
    if "temp" in result:
        parts.append(f"{result['temp']}K")
    elif all(k in result for k in ("r", "g", "b")):
        parts.append(f"rgb({result['r']},{result['g']},{result['b']})")
    scene = result.get("sceneId")
    if scene:
        parts.append(f"scene {scene}")
    if "dimming" in result:
        parts.append(f"{result['dimming']}%")
    return " ".join(parts) or "on"
