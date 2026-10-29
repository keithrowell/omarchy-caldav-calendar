# CalDav Calendar

Add an event from the Omarchy clock. It shows up on your iPhone, Mac, and everywhere else your CalDAV calendar lives.

iCloud, Nextcloud, Fastmail — same two-way sync. Month, week, and day views, meeting links, and reminders, without moving the clock.

<p align="center">
  <img src="screenshots/month.png" alt="Month view" width="800">
</p>

## Install

```bash
omarchy plugin add https://github.com/SirWizardLizard/omarchy-caldav-calendar --enable
```

This replaces the built-in clock. Shortcuts stay put. If Omarchy leaves the center pin on `omarchy.clock`, the plugin retargets that pin to itself on first run. It does not change a custom or empty pin.

The plugin needs Evolution Data Server. If it is not installed, the clock opens a prompt with **Click to install** (opens a terminal for `omarchy pkg add evolution-data-server`) and **SOURCE** (the Arch package page). You do not have to run that command yourself.

## What it does

- Month, week, work week, and day views
- Create, edit, and delete events (including overnight and recurring) — they sync to your phone and other devices
- iCloud, Nextcloud, Fastmail, and other CalDAV servers
- Calendars that live only on this computer
- Join Zoom, Google Meet, or Teams from a link on the event
- Optional desktop reminder 5–30 minutes before timed events
- Show or hide each calendar from the calendar button in the header, or by account in settings. Hidden calendars keep syncing but give no reminders.
- Pick any calendar colour with a colour picker (hue strip and saturation/brightness square), from presets, from the current Omarchy theme, or by hex value
- Ask your agent to add an event in plain words ("tennis next Thursday"). It uses the agent set with `omarchy default agent` (Claude or Codex), reads your calendars and the last three months of habits, avoids clashes with your own commitments, and fills in the new-event form for you to check and save
- A day overview window with columns you set, an AI summary of the day and an agent that changes events, with undo (see Day overview below)
- Open the calendar in its own window that tiles like any other app: the window button in the header, `scripts/calendar-window`, or `omarchy-shell omarchy.clock openWindow`

<p align="center">
  <img src="screenshots/week.png" alt="Week view" width="480">
</p>

## Day overview

One day in its own window, with your events split into columns you name, a short reading of the day from your agent, and an agent panel that can change your calendar.

Open it from the day overview button in the calendar header, or run:

```bash
scripts/calendar-day            # today
scripts/calendar-day tomorrow   # or friday, or 2026-11-03
omarchy-shell omarchy.clock openDay 2026-11-03
```

Set up columns in settings under **Day overview**: name each column and tick its calendars. Calendars in no column go in the first one. A calendar you put in a column shows there even when it is hidden in the other views, which suits a child's school timetable you want beside your own day but not in your week.

| Key | Action |
| --- | --- |
| ← → | Previous or next day |
| T | Today |
| / | Ask the agent |
| Ctrl+Z | Undo the agent's last change |
| A | Show or hide the summary and agent |
| Esc | Close |

The summary and the agent use the agent set with `omarchy default agent` (Claude or Codex), with no tools. A summary is kept per day and made again only when that day's events change. The agent's changes are saved straight away and each reply has an Undo button. It can't delete a repeating event or change read-only calendars.

To float the window in Hyprland, add a window rule for class `org.quickshell` with title `Day overview`.

## Add iCloud

Do not use your Apple ID password. Apple requires an app-specific password.

1. Open [account.apple.com](https://account.apple.com) → **Sign-In and Security → App-Specific Passwords**
2. Generate a password (2FA must be on)
3. Click the clock → **Add calendar**
4. Enter:

   | Field | Value |
   | --- | --- |
   | Display name | `iCloud` |
   | CalDAV URL | `https://caldav.icloud.com/` |
   | Username | your Apple ID email |
   | Password | the app-specific password |

5. **Add CalDAV source**, then **Sync** if events are not there yet

Remove a calendar later from settings.

## Other CalDAV

Same form. Use the provider’s CalDAV URL and an app password when they require one.

- Nextcloud: `https://your-server/remote.php/dav/`
- Fastmail: `https://caldav.fastmail.com/`

## Subscribe to an iCalendar feed

For a read-only `.ics` or iCalendar subscription URL:

1. Click the clock → **Add calendar** → **iCalendar**
2. Enter a display name and the subscription URL
3. Click **Add subscription**

No username or password is needed when access is provided by a token in the URL. Subscription events refresh automatically and cannot be created, edited, or deleted from this plugin.

## Meetings

Paste a Zoom, Meet, or Teams URL on the event (`meet.google.com/…` is fine). **Join** opens it. The plugin does not sign in to Google, Zoom, or Outlook.

## Reminders

**Settings → Remind me**: off, or 5 / 10 / 15 / 30 minutes before timed events. Click a meeting toast to join.

<p align="center">
  <img src="screenshots/settings.png" alt="Settings" width="800">
</p>

## Not included

Google Calendar and Outlook need OAuth app review. They are not in this plugin. CalDAV servers and local calendars are.

## Uninstall

```bash
omarchy plugin disable sirwizardlizard.calendar
omarchy plugin remove sirwizardlizard.calendar
```

## Requirements

Omarchy 4, Python 3, and Evolution Data Server. If EDS is missing, the plugin offers to install it. License: MIT.

Credentials stay in the system keyring. They are never written to `shell.json` or this repo.

## Development

```bash
./test/all
omarchy plugin validate .
```
