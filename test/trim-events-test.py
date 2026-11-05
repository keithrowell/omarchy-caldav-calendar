#!/usr/bin/env python3
"""The event cap drops the oldest past events first and never today's events."""

from __future__ import annotations

import sys
from datetime import UTC, datetime, timedelta
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "helper" / "omarchy-calendar-helper"

loader = SourceFileLoader("calendar_helper_trim", str(HELPER))
spec = spec_from_loader(loader.name, loader)
mod = module_from_spec(spec)
sys.modules[loader.name] = mod
loader.exec_module(mod)

now = datetime(2026, 11, 4, 6, 0, tzinfo=UTC)


def event(name: str, start: datetime, hours: float = 1.0, calendar: str = "c") -> dict:
    return {
        "id": name,
        "calendarId": calendar,
        "title": name,
        "start": start.isoformat().replace("+00:00", "Z"),
        "end": (start + timedelta(hours=hours)).isoformat().replace("+00:00", "Z"),
    }


# Under the limit: unchanged, same list.
small = [event("a", now)]
assert mod.trim_events(small, 5, now) is small

# Over the limit: the oldest past events go first, order is kept.
old = [event(f"old{i}", now - timedelta(days=300 - i)) for i in range(5)]
recent = event("recent", now - timedelta(days=1))
ongoing = event("ongoing", now - timedelta(minutes=30))
today = event("roundup", now + timedelta(minutes=15), calendar="google")
future = event("future", now + timedelta(days=30))
events = old[:2] + [today] + old[2:] + [recent, ongoing, future]
kept = mod.trim_events(events, 5, now)
names = [e["title"] for e in kept]
assert names == ["roundup", "old4", "recent", "ongoing", "future"], names

# All-day events for today count as current.
all_day = {"id": "d", "calendarId": "c", "title": "today all day", "start": "2026-11-04", "end": "2026-11-05"}
kept = mod.trim_events(old + [all_day], 1, now)
assert [e["title"] for e in kept] == ["today all day"], kept

# Only when current and future events alone exceed the limit do the furthest future ones go.
upcoming = [event(f"up{i}", now + timedelta(days=i)) for i in range(4)]
kept = mod.trim_events(old + upcoming, 3, now)
assert [e["title"] for e in kept] == ["up0", "up1", "up2"], kept

# A calendar read late in the snapshot is not penalised by the ones read before it.
first = [event(f"ical{i}", now - timedelta(days=200, hours=i)) for i in range(10)]
late = [event("google today", now + timedelta(hours=1), calendar="google")]
kept = mod.trim_events(first + late, 10, now)
assert "google today" in [e["title"] for e in kept]
assert len(kept) == 10

# Bounded payloads and cached reads use the same rule.
saved = mod.MAX_EVENTS
mod.MAX_EVENTS = 10
try:
    payload = mod.bound_payload({"ok": True, "events": first + late})
finally:
    mod.MAX_EVENTS = saved
assert any(e["title"] == "google today" for e in payload["events"]), payload["events"]

print("ok - event cap drops the oldest past events first")
