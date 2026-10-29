#!/usr/bin/env python3
"""Day agent: summary cache, prompts, references and action checks, no agent call."""

import importlib.machinery
import importlib.util
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "helper" / "calendar-day-agent"
loader = importlib.machinery.SourceFileLoader("calendar_day_agent", str(path))
spec = importlib.util.spec_from_loader("calendar_day_agent", loader)
day = importlib.util.module_from_spec(spec)
sys.modules["calendar_day_agent"] = day
loader.exec_module(day)


def iso(moment):
    return moment.astimezone().astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


midnight = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=3)
D = midnight.date().isoformat()


def at(hours, minutes=0, days=0):
    return iso(midnight + timedelta(days=days, hours=hours, minutes=minutes))


one_off = {"id": "w:lunch", "uid": "lunch", "calendarId": "w", "title": "Lunch", "start": at(12), "end": at(13), "allDay": False, "location": "Cafe"}
weekly = {"id": "w:class:1", "uid": "class", "rid": "20261101T080000Z", "recurring": True, "calendarId": "w", "title": "Class",
          "start": at(8), "end": at(9), "allDay": False}
school = {"id": "kid:maths", "uid": "maths", "calendarId": "kid", "title": "Maths", "start": at(9), "end": at(10), "allDay": False}
locked = {"id": "ro:standup", "uid": "standup", "calendarId": "ro", "title": "Standup", "start": at(10), "end": at(10, 30), "allDay": False}
secret = {"id": "hid:x", "uid": "x", "calendarId": "hid", "title": "Hidden thing", "start": at(15), "end": at(16), "allDay": False}
holiday = {"id": "w:hol", "uid": "hol", "calendarId": "w", "title": "Away", "start": D, "end": (midnight.date() + timedelta(days=2)).isoformat(), "allDay": True}
breakfast = {"id": "w:bf", "uid": "bf", "calendarId": "w", "title": "Breakfast meeting", "start": at(7, days=1), "end": at(8, days=1), "allDay": False}
cache = {
    "calendars": [
        {"id": "w", "name": "Mine"},
        {"id": "kid", "name": "School"},
        {"id": "ro", "name": "Work feed", "readonly": True},
        {"id": "hid", "name": "Secret"},
    ],
    "events": [one_off, weekly, school, locked, secret, holiday, breakfast],
}
cols = [{"name": "Me", "calendarIds": ["w", "ro"]}, {"name": "Kids", "calendarIds": ["kid"]}]
hidden = {"hid": True}

events = day.day_events(cache, midnight.date(), hidden)
assert [e["title"] for e in events] == ["Away", "Class", "Maths", "Standup", "Lunch"], [e["title"] for e in events]
print("ok - day events skip hidden calendars and include multi-day entries")

calls = []


def fake_summary(system, schema, prompt):
    calls.append(prompt)
    return {"headline": "Busy morning", "insights": ["Gap at 11", "", "b", "c", "d", "e"]}


with tempfile.TemporaryDirectory() as folder:
    store = Path(folder)
    request = {"date": D, "columns": cols, "hidden": hidden}
    first = day.summary(request, cache, fake_summary, store)
    assert first["ok"] and not first["cached"] and first["headline"] == "Busy morning", first
    assert first["insights"] == ["Gap at 11", "b", "c", "d"], first["insights"]
    assert "Hidden thing" not in calls[0]
    assert "Me:" in calls[0] and "Kids:" in calls[0] and "Maths" in calls[0].split("Kids:")[1]
    assert "Breakfast meeting" in calls[0].split("next morning:")[1]
    second = day.summary(request, cache, fake_summary, store)
    assert second["cached"] and len(calls) == 1 and second["insights"] == first["insights"]
    forced = day.summary({**request, "force": True}, cache, fake_summary, store)
    assert not forced["cached"] and len(calls) == 2
    renamed = day.summary({**request, "columns": [{"name": "Mine", "calendarIds": ["w"]}]}, cache, fake_summary, store)
    assert not renamed["cached"] and len(calls) == 3
    cache["events"].append({"id": "w:new", "calendarId": "w", "title": "New", "start": at(17), "end": at(18), "allDay": False})
    changed = day.summary({**request, "columns": [{"name": "Mine", "calendarIds": ["w"]}]}, cache, fake_summary, store)
    assert not changed["cached"] and len(calls) == 4
    cache["events"].pop()
    (store / "2001-01-01.json").write_text("{}")
    day.summary({**request, "force": True}, cache, fake_summary, store)
    assert not (store / "2001-01-01.json").exists()
print("ok - summary cache follows the day's events and columns, and prunes old days")

refs, _ = day.references(cache, midnight.date(), hidden)
by_title = {event["title"]: ref for ref, event in refs.items()}
seen = {}


def fake_chat(system, schema, prompt):
    seen["prompt"] = prompt
    return {"reply": "Done", "actions": [
        {"op": "update", "ref": by_title["Lunch"], "calendarId": "", "title": "", "date": "", "start": "12:30", "end": "", "allDay": False, "location": ""},
        {"op": "delete", "ref": by_title["Class"], "calendarId": "", "title": "", "date": "", "start": "", "end": "", "allDay": False, "location": ""},
        {"op": "delete", "ref": by_title["Standup"], "calendarId": "", "title": "", "date": "", "start": "", "end": "", "allDay": False, "location": ""},
        {"op": "create", "ref": "", "calendarId": "ro", "title": "X", "date": D, "start": "08:00", "end": "09:00", "allDay": False, "location": ""},
        {"op": "create", "ref": "", "calendarId": "hid", "title": "Y", "date": D, "start": "08:00", "end": "09:00", "allDay": False, "location": ""},
        {"op": "create", "ref": "", "calendarId": "", "title": "Gym", "date": D, "start": "18:00", "end": "19:00", "allDay": False, "location": "Gym"},
        {"op": "create", "ref": "", "calendarId": "w", "title": "Bad", "date": D, "start": "25:00", "end": "26:00", "allDay": False, "location": ""},
        {"op": "create", "ref": "", "calendarId": "w", "title": "Day off", "date": D, "start": "", "end": "", "allDay": True, "location": ""},
        {"op": "update", "ref": "e999", "calendarId": "", "title": "", "date": "", "start": "", "end": "", "allDay": False, "location": ""},
        {"op": "update", "ref": by_title["Class"], "calendarId": "", "title": "", "date": "", "start": "08:30", "end": "", "allDay": False, "location": ""},
    ]}


answer = day.chat({"date": D, "prompt": "move lunch", "columns": cols, "hidden": hidden, "defaultCalendarId": "w"}, cache, fake_chat)
prompt = seen["prompt"]
assert one_off["id"] not in prompt and "Hidden thing" not in prompt
assert f"{by_title['Standup']}  " in prompt and "(read-only)" in prompt.split(by_title["Standup"] + "  ")[1].split("\n")[0]
assert "repeats" in prompt.split(by_title["Class"] + "  ")[1].split("\n")[0]
assert "<Kids>" in prompt.split(by_title["Maths"] + "  ")[1].split("\n")[0]
ops = [(a["op"], a.get("title", a.get("eventId"))) for a in answer["actions"]]
assert ops == [("update", "Lunch"), ("create", "Gym"), ("create", "Day off"), ("update", "Class")], ops
moved = answer["actions"][0]
assert moved["eventId"] == one_off["id"] and moved["start"] == at(12, 30) and moved["end"] == at(13, 30), moved
assert moved["location"] == "Cafe" and moved["calendarId"] == "w"
gym = answer["actions"][1]
assert gym["calendarId"] == "w" and gym["start"] == at(18) and gym["end"] == at(19)
off = answer["actions"][2]
assert off["allDay"] and off["start"] == D and off["end"] == (midnight.date() + timedelta(days=1)).isoformat()
assert answer["actions"][3]["eventId"] == weekly["id"] and answer["actions"][3]["end"] == at(9, 30)
assert len(answer["rejected"]) == 6, answer["rejected"]
print("ok - chat maps references, keeps unset fields and rejects unsafe changes")
