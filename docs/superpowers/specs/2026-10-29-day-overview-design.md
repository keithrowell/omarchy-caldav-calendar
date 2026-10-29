# Day overview

A window that shows one day at a time. Its parts are a timeline split into columns the user defines, an AI summary of the day, and an agent panel that can change the calendar. The window works without the main calendar open, and every entry point (the calendar header, a script, IPC, a launcher entry) opens the same window.

## Goals

- Show a day's events in calendar colours, grouped into columns the user names in settings ("Me", "Kids at school", "Work").
- Give a short AI reading of the day: a headline and up to four insights.
- Let the user ask an agent to create, move, retitle or delete events, apply the change straight away, and undo it.
- Keep everything generic: no calendar names, people or accounts appear in the code, so the feature can go upstream as a pull request.

Out of scope: week overviews, attendee handling, editing recurring series from the agent, and any agent that is not Claude or Codex.

## Opening the window

| Entry point | What it runs |
|---|---|
| IPC | `omarchy-shell omarchy.clock openDay [YYYY-MM-DD]` |
| Script | `scripts/calendar-day [YYYY-MM-DD]` |
| Calendar header | a "Day overview" button that opens the selected day |
| Launcher | `omarchy-calendar-day.desktop` |

With no date given, the window opens on today. If it is already open, it moves to the requested day and comes forward. Opening a day asks the service for a sync, at most every two minutes: of its current range when that covers the day, otherwise of the month grid around the day.

On io, a Hyprland rule in `~/.config/hypr/hyprland.lua` floats and centres the window. The plugin itself sets no rule.

## Window

`DayOverview.qml` is a new file. `BarWidget.qml` loads it on first request and keeps it afterwards, the same way it handles the calendar window. It is a `FloatingWindow` titled "Day overview" (class `org.quickshell`), 1180 by 820 by default.

Keys:

| Key | Action |
|---|---|
| Left, Right | previous or next day |
| T | today |
| A | show or hide the summary and agent panel |
| / | focus the agent input |
| Ctrl+Z | undo the agent's most recent change |
| Esc | close |

The layout from top to bottom:

1. The header holds the date, previous, today and next buttons, and a status line. On today the status is the next or current event in the first column with a countdown. On other days it is the number of timed events.
2. The all-day row holds chips for all-day events and timed events that cover the whole day, each tinted with its calendar colour.
3. The timeline has a time gutter and one column per configured column. Overlapping events in a column sit side by side. On today a now line crosses every column. The visible hours follow the existing "Hours on screen" setting, widened to take in every event that day, and the timeline scrolls.

The side panel sits on the right at 360 pixels wide and collapses to nothing. Its top holds the summary card (the AI headline and insights, scrolling past 45% of the panel's height, "Reading your day" while a summary is being made). The agent chat fills the rest.

Event blocks use the calendar's display colour from `Model.calendarDisplayColor`, with the user's colour overrides, at the same fill strength as the week view. They carry no accent bar. Clicking an event opens it in the calendar window's edit form.

## Columns setting

A new widget setting, `dayColumns`, holds an ordered list:

```json
[{ "name": "Me", "calendars": ["<calendar id>", "..."] },
 { "name": "Kids at school", "calendars": ["<calendar id>"] }]
```

Rules, implemented as `Model.dayColumns(calendars, setting, hidden)`:

- A calendar named in a column shows there even when it is hidden in the calendar views. Hidden calendars in no column stay out.
- A calendar listed in several columns appears in the first one only.
- Visible calendars in no column join the first column.
- With no setting, or an empty list, there is one column named "Events".
- A column with no events that day still shows, so the layout stays stable from day to day.

Settings gains a "Day overview" section. Each column row has a name field, a calendar picker (the calendars grouped by account, as in the existing calendar list), up and down buttons and a remove button. An "Add column" button sits below the rows. The section saves with the rest of settings.

## AI summary

A new helper, `helper/calendar-day-agent`, reads one JSON request on stdin and prints one JSON answer, like `calendar-agent`. The code that finds and runs the default agent moves from `calendar-agent` into `helper/agent_runner.py`, and both helpers import it.

Summary request:

```json
{ "mode": "summary", "date": "2026-10-29", "columns": [...], "hidden": {...}, "names": {...}, "force": false }
```

The helper reads the event cache, takes the day's visible events, and hashes the events with the column names. It looks for `~/.local/share/omarchy-calendar/day-summaries/<date>.json` and returns that file's summary when the hash matches and `force` is false. Otherwise it asks the agent and writes the file. The agent gets the day by column, the first event of the next day, and today's date and time.

Summary answer:

```json
{ "ok": true, "cached": true, "headline": "...", "insights": ["..."] }
```

The window asks for a summary when it opens a day, when that day's events change, and when the user presses Refresh on the card. A day whose hash has not changed costs one cache read and no agent call. Summary files older than 30 days are deleted when a new one is written.

## Agent panel

Chat request:

```json
{ "mode": "chat", "date": "2026-10-29", "prompt": "...", "history": [...], "columns": [...], "hidden": {...}, "names": {...}, "defaultCalendarId": "..." }
```

The prompt gives the agent today's date, the writable calendars, the columns, and every visible event from 14 days before to 14 days after the day on screen. The request carries the calendar's time format, and both prompts tell the agent to write times in it. Each event has a short reference (`e1`, `e2`, ...). The agent never sees raw event ids. The helper maps references back to event ids.

Chat answer:

```json
{ "ok": true, "reply": "...", "actions": [
  { "op": "create", "calendarId": "...", "title": "...", "date": "YYYY-MM-DD", "start": "HH:MM", "end": "HH:MM", "allDay": false, "location": "" },
  { "op": "update", "eventId": "...", "title": "...", "date": "...", "start": "...", "end": "...", "allDay": false, "location": "", "calendarId": "..." },
  { "op": "delete", "eventId": "..." }
] }
```

The helper rejects an action, and names it in `rejected`, when:

- its calendar is read-only or hidden;
- an update or delete names an unknown reference;
- a delete targets an occurrence of a recurring event;
- its date or times do not parse.

The panel applies the remaining actions one at a time through the service's `createEvent`, `updateEvent` (scope `this`) and `deleteEvent`. It waits for each to finish, because the service runs one write of each kind at a time. The service gains an `eventDeleted(bool ok, string message)` signal so the panel knows when a delete has finished, and the panel reads the new event's uid from the existing `eventCreated` signal.

Each turn that changed something records its inverse:

| Action | Undo |
|---|---|
| create | delete the created event |
| update | update back to the saved title, times, location and calendar |
| delete | create a copy with the saved fields |

Undo runs a turn's inverses in reverse order and marks the turn as undone. Undo history lives in memory and ends when the window closes. When a write fails, the turn shows the helper's message and its remaining actions are skipped. Undo still covers the actions that succeeded.

## Errors

- **No default agent, or one other than Claude or Codex:** the summary card and the agent panel show the helper's existing message. The timeline works.
- **Agent timeout (120 seconds):** the card or turn says the agent took too long and offers Retry.
- **Empty or unreadable event cache:** the window shows the service's loading state until events arrive.

## Testing

| Test | Covers |
|---|---|
| `test/model-test.js` | `dayColumns` rules, column layout with overlaps, all-day selection |
| `test/day-agent-test.py` | summary cache hit and miss, hash changes, prompt contents, reference mapping, each rejection rule, with a fake runner |
| `test/agent-test.py` | the existing new-event agent still builds its prompt after the runner moves out |
| offscreen render | the window with sample events in two columns, one overlap and an all-day row |
| live run on io | create, move and delete through the panel, undo each, confirm the event store matches its starting state |
