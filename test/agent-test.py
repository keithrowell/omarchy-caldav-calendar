#!/usr/bin/env python3
"""Calendar agent: prompt building, habits and clash checks, no agent call."""

import importlib.machinery
import importlib.util
import sys
from datetime import datetime, timedelta
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "helper" / "calendar-agent"
loader = importlib.machinery.SourceFileLoader("calendar_agent", str(path))
spec = importlib.util.spec_from_loader("calendar_agent", loader)
agent = importlib.util.module_from_spec(spec)
sys.modules["calendar_agent"] = agent
loader.exec_module(agent)


def iso(moment):
    return moment.astimezone().isoformat()


today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
tennis = [
    {"calendarId": "ex", "title": "Tennis", "start": iso(today - timedelta(days=7 * week) + timedelta(hours=18)),
     "end": iso(today - timedelta(days=7 * week) + timedelta(hours=19, minutes=30)), "location": "Club", "allDay": False}
    for week in range(1, 4)
]
tomorrow_meeting = {"calendarId": "work", "title": "Board", "start": iso(today + timedelta(days=1, hours=9)),
                    "end": iso(today + timedelta(days=1, hours=10)), "allDay": False}
cache = {
    "calendars": [
        {"id": "ex", "name": "Exercise", "provider": "caldav", "host": "p1-caldav.icloud.com"},
        {"id": "work", "name": "Work", "provider": "caldav", "host": "apidata.googleusercontent.com"},
        {"id": "local", "name": "Personal", "provider": "evolution-data-server"},
        {"id": "hol", "name": "Holidays", "provider": "caldav", "readonly": True},
    ],
    "events": tennis + [tomorrow_meeting],
}

prompt, facts = agent.build_prompt({"prompt": "tennis thursday", "hidden": {"hol": True}}, cache)
assert "Tennis: 3x" in prompt and "18:00" in prompt and "90 min" in prompt and "@ Club" in prompt, prompt
assert "ex  Exercise  (iCloud)" in prompt
assert "local  Personal  (this computer only)" in prompt
assert "hol" not in facts["writable"]
assert "Board" in prompt
print("ok - agent prompt carries calendars, habits and bookings")

clash = agent.clashes({"allDay": False, "date": (today + timedelta(days=1)).strftime("%Y-%m-%d"), "start": "09:30", "end": "10:30"},
                      facts["visible"], facts["names"])
assert len(clash) == 1 and "Board" in clash[0], clash
free = agent.clashes({"allDay": False, "date": (today + timedelta(days=1)).strftime("%Y-%m-%d"), "start": "11:00", "end": "12:00"},
                     facts["visible"], facts["names"])
assert free == [], free
print("ok - agent clash check")
