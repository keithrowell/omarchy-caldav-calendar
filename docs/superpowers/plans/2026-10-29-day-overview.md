# Day Overview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A floating Day overview window with user-defined columns, an AI summary and an agent panel that writes to the calendar with undo.

**Architecture:** Pure layout rules live in `CalendarModel.js`. A new Python helper (`calendar-day-agent`) builds prompts, caches summaries and validates agent actions, sharing its agent runner with `calendar-agent` through `helper/agent_runner.py`. `DayOverview.qml` is the window. It reads events from the existing service and writes through the service's create, update and delete calls.

**Tech Stack:** Quickshell QML (Qt 6), plain JavaScript model, Python 3 helpers, Evolution Data Server through the existing helper.

**Spec:** `docs/superpowers/specs/2026-10-29-day-overview-design.md`

## Global Constraints

- No calendar names, people or account names in code, tests or defaults.
- The setting key is `dayColumns`, a list of `{ "name": string, "calendars": [calendar id] }`.
- The window title is `Day overview`. The IPC method is `openDay(date: string)` on target `omarchy.clock`.
- Agent writes use scope `this`. The agent can't delete an occurrence of a recurring event.
- Summary cache: `~/.local/share/omarchy-calendar/day-summaries/<YYYY-MM-DD>.json`, pruned after 30 days.
- Agent timeout 120 seconds. Agents supported: Claude and Codex, chosen by `omarchy-default-agent`.
- Event blocks have no accent bar.

## File structure

| File | Responsibility |
|---|---|
| `CalendarModel.js` | `dayColumns`, `dayColumnLayout` (pure functions) |
| `helper/agent_runner.py` | find and run the default agent with a schema (moved out of `calendar-agent`) |
| `helper/calendar-agent` | unchanged behaviour, imports the runner |
| `helper/calendar-day-agent` | summary and chat modes, cache, reference mapping, action validation |
| `Service.qml` | new `eventDeleted` signal, `askDayAgent` process |
| `DayOverview.qml` | the window, timeline, summary card, agent panel, undo |
| `BarWidget.qml` | load the window, `openDay` IPC |
| `Panel.qml` | header button, Day overview settings section |
| `scripts/calendar-day`, `applications/omarchy-calendar-day.desktop` | entry points |
| `test/model-test.js`, `test/day-agent-test.py`, `test/all` | tests |

### Task 1: Column rules in the model

**Files:**
- Modify: `CalendarModel.js` (append after `timelineHours`)
- Test: `test/model-test.js`

**Interfaces:**
- Produces: `dayColumns(calendars, setting, hidden) -> [{ name, calendarIds: [id] }]` and `dayColumnLayout(events, dayKey, columns, hourStart, hourEnd) -> [{ name, segments }]`, where `segments` has the shape `layoutTimedEvents` returns.

- [ ] **Step 1: Write the failing tests** (append to `test/model-test.js`)

```js
{
  const cals = [{ id: 'a' }, { id: 'b' }, { id: 'c' }, { id: 'h' }]
  const hidden = { h: true }
  assert.deepEqual(model.dayColumns(cals, [], hidden), [{ name: 'Events', calendarIds: ['a', 'b', 'c'] }])
  const cols = model.dayColumns(cals, [{ name: 'One', calendars: ['b', 'h'] }, { name: 'Two', calendars: ['c', 'b'] }], hidden)
  assert.deepEqual(cols, [{ name: 'One', calendarIds: ['b', 'a'] }, { name: 'Two', calendarIds: ['c'] }])
  const day = '2026-08-20'
  const evs = model.normalizeEvents([
    { id: '1', calendarId: 'a', title: 'A', start: localIso(day, '09:00'), end: localIso(day, '10:00') },
    { id: '2', calendarId: 'b', title: 'B', start: localIso(day, '09:30'), end: localIso(day, '10:30') },
    { id: '3', calendarId: 'c', title: 'C', start: localIso(day, '09:00'), end: localIso(day, '10:00') }
  ])
  const laid = model.dayColumnLayout(evs, day, cols, 0, 24)
  assert.equal(laid[0].segments.length, 2)
  assert.equal(laid[0].segments[0].lanes, 2)
  assert.equal(laid[1].segments.length, 1)
  assert.equal(laid[1].segments[0].lanes, 1)
  console.log('ok - day overview columns')
}
```

- [ ] **Step 2: Run, expect failure:** `node test/model-test.js` fails with `model.dayColumns is not a function`.

- [ ] **Step 3: Implement**

```js
// Columns for the day overview. Hidden calendars are left out, a calendar
// listed twice stays in its first column, and visible calendars in no
// column join the first one.
function dayColumns(calendars, setting, hidden) {
  var visible = (calendars || []).filter(function(c) { return c && c.id && !calendarHidden(hidden, c.id) }).map(function(c) { return c.id })
  var known = {}
  visible.forEach(function(id) { known[id] = true })
  var placed = {}
  var columns = (Array.isArray(setting) ? setting : []).map(function(col) {
    var ids = ((col && col.calendars) || []).filter(function(id) {
      if (!known[id] || placed[id]) return false
      placed[id] = true
      return true
    })
    return { name: String((col && col.name) || 'Events'), calendarIds: ids }
  })
  if (!columns.length) columns = [{ name: 'Events', calendarIds: [] }]
  visible.forEach(function(id) { if (!placed[id]) columns[0].calendarIds.push(id) })
  return columns
}

function dayColumnLayout(events, dayKey, columns, hourStart, hourEnd) {
  return (columns || []).map(function(col) {
    var ids = {}
    col.calendarIds.forEach(function(id) { ids[id] = true })
    var mine = (events || []).filter(function(e) { return ids[e.calendarId] })
    return { name: col.name, segments: layoutTimedEvents(mine, dayKey, hourStart, hourEnd) }
  })
}
```

Add both names to the `module.exports` block at the end of the file.

- [ ] **Step 4: Run:** `bash test/all` up to the model tests passes in every listed time zone.
- [ ] **Step 5: Commit** "Add day overview column rules".

### Task 2: Shared agent runner

**Files:**
- Create: `helper/agent_runner.py`
- Modify: `helper/calendar-agent` (remove `agent_name`, `find`, `run_claude`, `run_codex`, `RUNNERS`, import them)
- Test: `test/agent-test.py` (unchanged, must still pass)

**Interfaces:**
- Produces: `agent_name() -> str`, `run(name, system, schema, prompt, workdir) -> dict` (raises `RuntimeError`, `subprocess.TimeoutExpired`), `SUPPORTED = ("claude", "codex")`, `AGENT_TIMEOUT = 120`.

- [ ] **Step 1:** Move the four functions into `agent_runner.py`, taking `system` and `schema` as parameters instead of reading module globals.
- [ ] **Step 2:** In `calendar-agent`, add `sys.path.insert(0, str(Path(__file__).resolve().parent))`, `import agent_runner`, and call `agent_runner.run(name, SYSTEM, SCHEMA, prompt, workdir)`.
- [ ] **Step 3: Run:** `python3 test/agent-test.py` prints both ok lines.
- [ ] **Step 4: Commit** "Share the agent runner between helpers".

### Task 3: Day agent helper

**Files:**
- Create: `helper/calendar-day-agent`
- Test: `test/day-agent-test.py`, add it to `test/all`

**Interfaces:**
- Consumes: `agent_runner.agent_name`, `agent_runner.run`.
- Produces: functions `day_events(cache, date, hidden)`, `day_hash(events, columns)`, `summary(request, cache, runner, store_dir)`, `chat(request, cache, runner)`, `validate(actions, refs, calendars, hidden)`. CLI: stdin JSON, stdout JSON as the spec defines. Environment: `OMARCHY_CALENDAR_CACHE` (cache folder override, as in `calendar-agent`) and `OMARCHY_CALENDAR_SUMMARIES` (summary folder override for tests).

- [ ] **Step 1: Write the failing test** `test/day-agent-test.py`. It loads the helper with `SourceFileLoader` like `agent-test.py`, builds a cache with a writable calendar, a read-only calendar, a hidden calendar, a one-off event and a recurring occurrence, and checks:

```python
calls = []
def fake(system, schema, prompt):
    calls.append(prompt)
    return {"headline": "Busy morning", "insights": ["Gap at 11"]}
first = day.summary({"date": D, "columns": cols, "hidden": {"hid": True}}, cache, fake, store)
assert first["ok"] and not first["cached"] and first["headline"] == "Busy morning"
second = day.summary({"date": D, "columns": cols, "hidden": {"hid": True}}, cache, fake, store)
assert second["cached"] and len(calls) == 1
cache["events"].append(extra_event_on_D)
third = day.summary({"date": D, "columns": cols, "hidden": {"hid": True}}, cache, fake, store)
assert not third["cached"] and len(calls) == 2
assert "Hidden thing" not in calls[0]

def chat_fake(system, schema, prompt):
    assert "e1" in prompt and one_off["id"] not in prompt
    return {"reply": "Done", "actions": [
        {"op": "update", "ref": "e1", "title": "Moved", "date": D, "start": "12:30", "end": "13:30", "allDay": False, "location": "", "calendarId": ""},
        {"op": "delete", "ref": recurring_ref},
        {"op": "create", "calendarId": "ro", "title": "X", "date": D, "start": "08:00", "end": "09:00", "allDay": False, "location": ""},
        {"op": "create", "calendarId": "w", "title": "Gym", "date": D, "start": "18:00", "end": "19:00", "allDay": False, "location": ""}]}
answer = day.chat({"date": D, "prompt": "move lunch", "columns": cols, "hidden": {"hid": True}}, cache, chat_fake)
ops = [a["op"] for a in answer["actions"]]
assert ops == ["update", "create"], answer
assert answer["actions"][0]["eventId"] == one_off["id"]
assert len(answer["rejected"]) == 2
print("ok - day agent summary cache, references and rejections")
```

- [ ] **Step 2: Run:** `python3 test/day-agent-test.py` fails (file missing).
- [ ] **Step 3: Implement** the helper. Prompt sections: today's date and time, the day on screen, columns with their calendars, writable calendars (id and name), events in the window as `eN  <when>  <title>  [<calendar>]  @ <location>` with `(repeats)` on recurring occurrences, and the conversation so far. The summary schema is `{headline: string, insights: [string] (max 4)}`. The chat schema is `{reply: string, actions: [{op, ref, calendarId, title, date, start, end, allDay, location}]}`. `main()` reads stdin, picks the runner, handles timeouts like `calendar-agent`, and prints the answer.
- [ ] **Step 4: Run:** the test passes. `bash test/all` passes.
- [ ] **Step 5: Commit** "Add the day agent helper".

### Task 4: Service hooks

**Files:**
- Modify: `Service.qml`

**Interfaces:**
- Produces: `signal eventDeleted(bool ok, string message)`, emitted from `deleteProc.onExited` on both paths. `function askDayAgent(request)`, `function cancelDayAgent()`, `signal dayAgentAnswered(var answer)`, `property bool dayAgentBusy`. A separate `dayAgentProc` (stdin-enabled, same secret handling as `agentProc`, so `qml-test.sh` checks it) runs `helper/calendar-day-agent`. Summary and chat requests queue: a new request while one runs waits, and the answer carries the request's `mode` and `date` back.

- [ ] **Step 1:** Add the signal and emit it.
- [ ] **Step 2:** Add the process, functions and a small FIFO queue.
- [ ] **Step 3: Run:** `bash test/qml-test.sh` passes, including the stdin check for the new process.
- [ ] **Step 4: Commit** "Let the service run the day agent and report deletes".

### Task 5: The window

**Files:**
- Create: `DayOverview.qml`
- Modify: `BarWidget.qml` (loader, `openDay`, IPC method), `Panel.qml` (header button, `openEvent` hand-off)
- Create: `scripts/calendar-day`, `applications/omarchy-calendar-day.desktop`

**Interfaces:**
- Consumes: `Model.dayColumns`, `Model.dayColumnLayout`, `Model.allDayEventsForDay`, `Model.timelineHours`, `Model.calendarDisplayColor`, service `cachedEvents`, `calendars`, `createEvent`, `updateEvent`, `deleteEvent`, `eventCreated`, `eventSaved`, `eventDeleted`, `askDayAgent`, `dayAgentAnswered`.
- Produces: `DayOverview.openDay(key: string)`, `DayOverview.close()`.

- [ ] **Step 1:** Build the window: header, summary card, all-day row, scrollable timeline with columns, now line, agent panel, keys.
- [ ] **Step 2:** The action runner: apply actions one at a time, collect inverses, undo in reverse.
- [ ] **Step 3:** Wire `BarWidget.openDay(key)` and IPC `openDay(date: string)`. Add a header button in `Panel.qml` that calls `hostWidget.openDay(selectedKey)`.
- [ ] **Step 4:** Add the script and the desktop entry.
- [ ] **Step 5: Run:** offscreen render with the harness, then `omarchy-restart-shell` and `scripts/calendar-day`, and screenshot.
- [ ] **Step 6: Commit** "Add the day overview window".

### Task 6: Columns in settings

**Files:**
- Modify: `Panel.qml` (draft state, load, save, a `SettingsSection` "Day overview")

**Interfaces:**
- Produces: setting `dayColumns` saved through `persistSettings`.

- [ ] **Step 1:** Add `draftDayColumns`, loaded in `loadSettingsDraft` and saved in `saveSettings`.
- [ ] **Step 2:** Add the section: a row per column with name field, calendar picker popup, up, down, remove. An Add column button.
- [ ] **Step 3: Run:** open settings, add two columns, save, check `shell.json` holds `dayColumns`, and check the overview shows both.
- [ ] **Step 4: Commit** "Set day overview columns in settings".

### Task 7: Live check and docs

- [ ] **Step 1:** In the window on io, ask the agent to create a test event, move it and delete it, undoing each. Confirm with `agenda` that the store matches its starting state.
- [ ] **Step 2:** README: a "Day overview" section with the entry points and the columns setting.
- [ ] **Step 3:** `bash test/all` passes.
- [ ] **Step 4: Commit** "Document the day overview".
