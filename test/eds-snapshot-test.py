#!/usr/bin/env python3
"""Snapshot loop timing tests, against a fake Evolution Data Server.

Covers three faults seen on a 38-calendar iCloud account (3 Nov 2026):

1. ECal.Client.connect_sync waits its whole wait_for_connected timeout even when
   the backend is already online, so a 10-second wait cost 10 seconds per calendar.
2. A calendar whose direct CalDAV sync failed after using its whole time
   allowance never reached the EDS fallback, so it kept stale cached events forever.
3. A run longer than the panel's 180-second limit was killed before it saved
   anything; the helper needs its own budget so it always saves what it has.
"""

from __future__ import annotations

import os
import sys
import tempfile
import time
from datetime import UTC, datetime, timedelta
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "helper" / "omarchy-calendar-helper"


def load_helper():
    return SourceFileLoader("omarchy_calendar_helper_eds", str(HELPER)).load_module()


class FakeSource:
    def __init__(self, uid: str):
        self.uid = uid

    def get_uid(self):
        return self.uid

    def get_display_name(self):
        return self.uid


class FakeRegistry:
    def __init__(self, sources):
        self.sources = sources

    def list_sources(self, _extension):
        return list(self.sources)

    def check_enabled(self, _source):
        return True


class FakeClient:
    def __init__(self, uid: str):
        self.uid = uid

    def is_readonly(self):
        return False

    def check_refresh_supported(self):
        return False


def harness(mod, uids, caldav_result, eds_events):
    waits = []

    def connect_sync(source, _kind, wait, _cancellable):
        waits.append(wait)
        return FakeClient(source.get_uid())

    modules = SimpleNamespace(
        EDataServer=SimpleNamespace(
            SourceRegistry=SimpleNamespace(new_sync=lambda _c: FakeRegistry([FakeSource(uid) for uid in uids])),
            SOURCE_EXTENSION_CALENDAR="Calendar",
        ),
        ECal=SimpleNamespace(Client=SimpleNamespace(connect_sync=connect_sync), ClientSourceType=SimpleNamespace(EVENTS=1)),
    )
    mod.load_eds_modules = lambda: modules
    mod.eds_prune_duplicate_caldav = lambda *_a: None
    mod.is_unresolved_caldav_root = lambda *_a: False
    mod.source_provider = lambda *_a: "caldav"
    mod.caldav_source_key = lambda source, _m: source.get_uid()
    mod.source_calendar = lambda source, _r, _m: {"id": source.get_uid(), "name": source.get_uid(), "host": "caldav.example"}
    mod.caldav_sync_calendar = caldav_result

    def pull(client, calendar, _ws, _we, _m, events, _limit=0, deadline=None):
        if deadline is not None and time.monotonic() >= deadline:
            return False
        events.extend(dict(event) for event in eds_events.get(client.uid, []))
        return True

    mod.eds_pull_calendar_events = pull
    return waits


def event(cal: str, uid: str, title: str) -> dict:
    return {"id": f"{cal}:{uid}", "uid": uid, "rid": "", "calendarId": cal, "title": title, "start": "2026-11-03T05:05:00Z", "end": "2026-11-03T05:25:00Z", "allDay": False}


def run_snapshot(mod):
    start = datetime(2026, 11, 1, tzinfo=UTC)
    return mod.eds_snapshot(start, start + timedelta(days=7), True, True)


def seed_cache(mod, events):
    mod.write_cache({"ok": True, "provider": "evolution-data-server", "calendars": [], "events": events, "syncState": {}, "rev": 1})


def test_connect_waits_are_short():
    mod = load_helper()
    waits = harness(mod, ["omarchy-calendar-caldav-a", "omarchy-calendar-caldav-b"], lambda *_a, **_k: ("eds", [], []), {})
    run_snapshot(mod)
    assert waits, "no EDS clients were opened"
    assert max(waits) <= mod.EDS_CONNECT_WAIT_SECONDS <= 1, f"connect_sync waits too long: {waits}"
    print("ok - EDS connections wait at most", mod.EDS_CONNECT_WAIT_SECONDS, "second")


def test_fallback_after_slow_direct_sync():
    mod = load_helper()
    cal = "omarchy-calendar-caldav-private"
    seed_cache(mod, [event(cal, "old", "stale copy")])

    def slow_direct(*_args, **kwargs):
        deadline = kwargs.get("deadline") if "deadline" in kwargs else _args[-1]
        while time.monotonic() < deadline:
            time.sleep(0.01)
        return "eds", [], []

    mod.CALDAV_SYNC_SECONDS = 0.2
    harness(mod, [cal], slow_direct, {cal: [event(cal, "soccer", "Pick Charlotte up (soccer)")]})
    payload = run_snapshot(mod)
    titles = sorted(e["title"] for e in payload["events"] if e["calendarId"] == cal)
    assert titles == ["Pick Charlotte up (soccer)"], f"fallback did not pull from EDS: {titles}"
    print("ok - EDS fallback runs after a direct sync uses its whole allowance")


def test_budget_saves_before_panel_limit():
    mod = load_helper()
    cals = [f"omarchy-calendar-caldav-{n}" for n in range(6)]
    seed_cache(mod, [event(cal, "cached", f"cached {cal}") for cal in cals])

    def slow_updated(_source, _registry, _modules, calendar, *_args, **_kwargs):
        time.sleep(0.2)
        return "updated", [event(calendar["id"], "fresh", f"fresh {calendar['id']}")], []

    mod.SNAPSHOT_BUDGET_SECONDS = 0.5
    harness(mod, cals, slow_updated, {})
    began = time.monotonic()
    payload = run_snapshot(mod)
    elapsed = time.monotonic() - began
    assert elapsed < 1.0, f"snapshot ran past its budget: {elapsed:.2f}s"
    titles = {e["title"] for e in payload["events"]}
    fresh = {t for t in titles if t.startswith("fresh")}
    cached = {t for t in titles if t.startswith("cached")}
    assert fresh and cached and len(fresh) + len(cached) == len(cals), f"expected a mix of fresh and cached: {sorted(titles)}"
    on_disk = {e["title"] for e in mod.read_cache()["events"]}
    assert fresh <= on_disk, "budgeted snapshot was not saved"
    print("ok - snapshot stops at its budget, saves fresh calendars and keeps the rest cached")


def test_budget_rotates_skipped_calendars_first():
    mod = load_helper()
    cals = [f"omarchy-calendar-caldav-{n}" for n in range(6)]
    seed_cache(mod, [event(cal, "cached", f"cached {cal}") for cal in cals])
    order = []

    def slow_updated(_source, _registry, _modules, calendar, *_args, **_kwargs):
        order.append(calendar["id"])
        time.sleep(0.2)
        return "updated", [event(calendar["id"], "fresh", f"fresh {calendar['id']}")], []

    mod.SNAPSHOT_BUDGET_SECONDS = 0.5
    harness(mod, cals, slow_updated, {})
    run_snapshot(mod)
    first_run = list(order)
    order.clear()
    run_snapshot(mod)
    skipped = [cal for cal in cals if cal not in first_run]
    assert skipped and order[0] == skipped[0], f"second run should start with {skipped[:1]}, started with {order[:1]}"
    print("ok - the next run starts with the calendars the budget skipped")


def main():
    with tempfile.TemporaryDirectory() as tmp:
        os.environ["OMARCHY_CALENDAR_CACHE"] = tmp
        for test in (test_connect_waits_are_short, test_fallback_after_slow_direct_sync, test_budget_saves_before_panel_limit, test_budget_rotates_skipped_calendars_first):
            for name in os.listdir(tmp):
                os.remove(os.path.join(tmp, name))
            test()
    print("ok - eds snapshot tests")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as error:
        print(f"not ok - {error}")
        sys.exit(1)
