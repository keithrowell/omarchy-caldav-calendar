import QtQuick
import qs.Commons as Commons
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "CalendarModel.js" as Model

Panel {
  id: root
  moduleName: "sirwizardlizard.calendar"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null
  // The bar widget loads a second copy of this panel with windowMode set, to
  // show the calendar in an ordinary window that Hyprland tiles.
  property bool windowMode: false
  property bool windowShown: false
  readonly property bool active: opened || windowShown
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var calendarService: bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null

  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  property string selectedKey: todayKey
  property string createDateKey: todayKey
  property string viewMode: "month"
  property bool creatingEvent: false
  property var editingEvent: null
  property bool showingSetup: false
  property bool showingSettings: false
  property string createError: ""
  property string setupError: ""
  property string setupKind: "caldav"
  property string setupName: "Calendar"
  property string setupUrl: ""
  property string setupUser: ""
  property string setupPassword: ""
  property string settingsError: ""
  property bool appliedDefaultView: false
  property string createCalendarId: ""
  property string createStartTime: "09:00"
  property string createEndTime: "10:00"
  property bool createAllDay: false
  property string createMeetingUrl: ""
  property string createMeetingKind: "none"
  property var createRecurrence: Model.defaultRecurrence(todayKey)
  property string editScope: "this"
  property var contextEvent: null
  property date now: new Date()
  property string draftTimeFormat: "12h"
  property string draftWeekStartDay: "1"
  property string draftDefaultView: "month"
  property bool draftShowWeekNumbers: true
  property int draftCustomWeekStartHour: 8
  property int draftCustomWeekEndHour: 18
  property int draftCustomDayStartHour: 0
  property int draftCustomDayEndHour: 24
  property string draftDefaultCalendarId: ""
  property string draftReminderMinutes: "10"
  property var draftCalendarNames: ({})
  property var draftCalendarColors: ({})
  property var draftHiddenCalendars: ({})
  property var removeCandidate: null
  property string removeCandidateName: ""
  property bool draggingTimeSelection: false
  property string dragDayKey: ""
  property real dragStartHour: 0
  property real dragEndHour: 0
  readonly property string weekStartSetting: String(setting("weekStartDay", 1))
  readonly property int weekStart: Model.normalizedWeekStart(weekStartSetting, Qt.locale().firstDayOfWeek)
  readonly property string timeFormat: setting("timeFormat", "12h") === "24h" ? "24h" : "12h"
  readonly property string defaultView: validChoice(setting("defaultView", "month"), ["month", "week", "work-week", "day"], "month")
  readonly property bool showWeekNumbers: setting("showWeekNumbers", true) !== false
  readonly property bool showDayPanel: setting("showDayPanel", true) !== false
  readonly property bool needsEdsInstall: calendarService && calendarService.errorCode === "eds-bindings-missing"
  readonly property bool edsLoading: calendarService && calendarService.errorCode === "eds-starting"
  readonly property bool edsStuck: calendarService && calendarService.errorCode === "eds-stuck"
  readonly property bool compactEds: !showingSettings && (needsEdsInstall || edsLoading || edsStuck)
  readonly property int customWeekStartHour: clampedHour(setting("customWeekStartHour", 8), 8)
  readonly property int customWeekEndHour: clampedEndHour(setting("customWeekEndHour", 18), 18, customWeekStartHour)
  readonly property int customDayStartHour: clampedHour(setting("customDayStartHour", 0), 0)
  readonly property int customDayEndHour: clampedEndHour(setting("customDayEndHour", 24), 24, customDayStartHour)
  readonly property int weekStartHour: customWeekStartHour
  readonly property int weekEndHour: customWeekEndHour
  readonly property int workWeekStartHour: weekStartHour
  readonly property int workWeekEndHour: weekEndHour
  readonly property int dayStartHour: customDayStartHour
  readonly property int dayEndHour: customDayEndHour
  readonly property int fixedEventDurationMinutes: 60
  readonly property string defaultCalendarId: String(setting("defaultCalendarId", ""))
  readonly property int reminderMinutes: Model.normalizedReminderMinutes(setting("reminderMinutes", 10))
  readonly property var calendarNames: setting("calendarNames", {})
  readonly property var calendarColors: setting("calendarColors", {})
  readonly property var hiddenCalendars: setting("hiddenCalendars", {})
  onHiddenCalendarsChanged: if (calendarService) calendarService.setHiddenCalendars(hiddenCalendars)
  onCalendarServiceChanged: if (calendarService) calendarService.setHiddenCalendars(hiddenCalendars)
  readonly property int hiddenCalendarCount: Object.keys(hiddenCalendars).filter(function(id) { return hiddenCalendars[id] === true }).length
  readonly property var calendarColorPalette: Model.DEFAULT_CALENDAR_COLORS.concat(Model.EXTRA_CALENDAR_COLORS)
  readonly property var themeColorPalette: [String(Commons.Color.accent), String(Commons.Color.foreground), String(Commons.Color.urgent), String(Commons.Color.muted)]
  readonly property var eventGroups: Model.visibleEventsByDay(calendarService ? calendarService.eventsByDay : ({}), hiddenCalendars)
  property int monthPreviewLimit: 2
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey, eventGroups, monthPreviewLimit)
  readonly property var selectedEvents: Model.eventsForDay(eventGroups, selectedKey)
  readonly property var viewDays: Model.daysForView(selectedKey, viewMode, weekStart)
  readonly property string provider: setting("provider", "evolution-data-server")
  readonly property string headline: viewMode === "month"
    ? Qt.formatDate(new Date(viewYear, viewMonth, 1), "MMMM yyyy")
    : Model.viewTitle(selectedKey, viewMode, weekStart)

  function open() {
    if (!appliedDefaultView) {
      viewMode = defaultView
      appliedDefaultView = true
    }
    root.now = new Date()
    if (calendarService) calendarService.setReminderMinutes(root.reminderMinutes, root.timeFormat)
    refresh(!!(calendarService && calendarService.status !== "ready"))
    if (root.windowMode) {
      root.windowShown = true
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
      return
    }
    root.controller.show()
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }

  function close() {
    if (root.windowMode) {
      root.windowShown = false
      return
    }
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() { root.active ? root.close() : root.open() }

  function openInWindow() {
    if (!root.hostWidget || typeof root.hostWidget.openWindow !== "function") return
    root.close()
    root.hostWidget.openWindow()
  }

  Component.onCompleted: if (windowMode) keyCatcher.parent = windowBody

  function closeForPopoutSwitch() {
    root.popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (!root.bar) return
    // Omarchy >= 4.0.3 exposes the flag read-only on the plugin bar API and
    // provides a setter instead. Never let this abort close(): a throw here
    // would leave the panel open and holding keyboard focus.
    try {
      if (typeof root.bar.setCenterHoverRevealSuppressed === "function")
        root.bar.setCenterHoverRevealSuppressed(value)
      else if ("centerHoverRevealSuppressed" in root.bar)
        root.bar.centerHoverRevealSuppressed = value
    } catch (e) {
      console.warn("sirwizardlizard.calendar: centerHoverRevealSuppressed not writable:", e)
    }
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function clampedHour(value, fallback) {
    var parsed = parseInt(value, 10)
    return isNaN(parsed) ? fallback : Math.max(0, Math.min(23, parsed))
  }

  function clampedEndHour(value, fallback, startHour) {
    var parsed = parseInt(value, 10)
    if (isNaN(parsed)) parsed = fallback
    parsed = Math.max(1, Math.min(24, parsed))
    return Math.max(startHour + 1, parsed)
  }

  function validChoice(value, choices, fallback) {
    var stringValue = String(value || "")
    return choices.indexOf(stringValue) === -1 ? fallback : stringValue
  }

  function activeRange() {
    return viewMode === "month"
      ? Model.monthRange(viewYear, viewMonth, weekStart)
      : Model.viewRange(selectedKey, viewMode, weekStart)
  }

  function refresh(forceSync) {
    root.today = new Date()
    if (!root.selectedKey) root.selectedKey = root.todayKey
    var range = activeRange()
    if (calendarService) calendarService.snapshot(range.start, range.end, provider, forceSync === true)
  }

  function movePeriod(delta) {
    if (viewMode === "month") {
      var next = Model.stepMonth(viewYear, viewMonth, delta)
      viewYear = next.year
      viewMonth = next.month
      var day = Math.min(parseInt(selectedKey.split("-")[2], 10) || 1, new Date(next.year, next.month + 1, 0).getDate())
      selectedKey = Model.dateKey(next.year, next.month, day)
    } else {
      var selected = Model.dateFromKey(selectedKey, today)
      var step = viewMode === "day" ? delta : delta * 7
      selected.setDate(selected.getDate() + step)
      selectedKey = Model.keyForDate(selected)
      viewYear = selected.getFullYear()
      viewMonth = selected.getMonth()
    }
    refresh()
  }

  function goToToday() {
    viewYear = today.getFullYear()
    viewMonth = today.getMonth()
    selectedKey = todayKey
    refresh()
  }

  function setView(mode) {
    viewMode = mode
    creatingEvent = false
    editingEvent = null
    showingSetup = false
    showingSettings = false
    refresh()
  }

  function dayKey(date) { return Model.keyForDate(date) }

  function weekdayLabel(weekday) {
    return String(Qt.locale().dayName(weekday, Locale.ShortFormat)).replace(/\.$/, "").toUpperCase()
  }

  function startCreatingEvent() {
    createError = ""
    editingEvent = null
    showingSetup = false
    showingSettings = false
    creatingEvent = true
    editScope = "all"
    createDateKey = selectedKey
    createAllDay = false
    createMeetingUrl = ""
    createMeetingKind = "none"
    createRecurrence = Model.defaultRecurrence(createDateKey)
    createCalendarId = selectedWritableCalendarId()
    Qt.callLater(function() {
      titleField.text = ""
      root.createStartTime = root.slotValueFromHour(9)
      root.createEndTime = root.slotValueFromHour(9 + root.fixedEventDurationMinutes / 60)
      root.createRecurrence = Model.defaultRecurrence(root.createDateKey)
      locationField.text = ""
      titleField.forceActiveFocus()
    })
  }

  function timeText(hour, format) {
    var effectiveFormat = format || root.timeFormat
    var totalMinutes = Math.max(0, Math.min(24 * 60, Math.round(hour * 60)))
    var hours = Math.floor(totalMinutes / 60)
    var minutes = totalMinutes % 60
    return Model.formatClockTime(hours, minutes, effectiveFormat)
  }

  function startCreatingEventAt(dayKey, startHour, endHour) {
    var first = Math.min(startHour, endHour)
    var last = Math.max(startHour, endHour)
    if (last <= first) last = first + root.fixedEventDurationMinutes / 60
    root.createDateKey = dayKey
    root.createAllDay = false
    root.createMeetingUrl = ""
    root.createMeetingKind = "none"
    root.createError = ""
    root.editingEvent = null
    root.showingSetup = false
    root.showingSettings = false
    root.creatingEvent = true
    root.editScope = "all"
    root.createRecurrence = Model.defaultRecurrence(dayKey)
    root.createCalendarId = root.selectedWritableCalendarId()
    Qt.callLater(function() {
      titleField.text = ""
      root.createStartTime = root.slotValueFromHour(first)
      root.createEndTime = root.slotValueFromHour(last)
      root.createRecurrence = Model.defaultRecurrence(dayKey)
      locationField.text = ""
      titleField.forceActiveFocus()
    })
  }

  function beginTimeSelection(dayKey, hour) {
    if (eventMenu.opened) {
      root.closeEventMenu()
      return
    }
    root.draggingTimeSelection = true
    root.dragDayKey = dayKey
    root.dragStartHour = hour
    root.dragEndHour = hour + root.fixedEventDurationMinutes / 60
  }

  function updateTimeSelection(hour) {
    if (!root.draggingTimeSelection) return
    root.dragEndHour = hour
  }

  function finishTimeSelection() {
    if (!root.draggingTimeSelection) return
    var dayKey = root.dragDayKey
    var startHour = root.dragStartHour
    var endHour = root.dragEndHour
    root.draggingTimeSelection = false
    root.dragDayKey = ""
    root.startCreatingEventAt(dayKey, startHour, endHour)
  }

  function startSetup() {
    setupError = ""
    setupKind = "caldav"
    setupName = "Calendar"
    setupUrl = ""
    setupUser = ""
    setupPassword = ""
    showingSetup = true
  }

  function cancelSetup() {
    showingSetup = false
    setupError = ""
    setupName = "Calendar"
    setupUrl = ""
    setupUser = ""
    setupPassword = ""
  }

  function startSettings() {
    creatingEvent = false
    editingEvent = null
    showingSetup = false
    settingsError = ""
    setupError = ""
    setupKind = "caldav"
    setupName = "Calendar"
    setupUrl = ""
    setupUser = ""
    setupPassword = ""
    showingSettings = true
    loadSettingsDraft()
  }

  function cancelSettings() {
    showingSettings = false
    settingsError = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function toggleSettings() {
    if (showingSettings) cancelSettings()
    else startSettings()
  }

  function toggleDayPanel() {
    persistSettings({ showDayPanel: !root.showDayPanel })
  }

  function saveSettings() {
    if (draftCustomWeekEndHour <= draftCustomWeekStartHour) {
      settingsError = "Week hours must end after they start."
      return
    }
    if (draftCustomDayEndHour <= draftCustomDayStartHour) {
      settingsError = "Day hours must end after they start."
      return
    }
    persistSettings({
      timeFormat: draftTimeFormat,
      weekStartDay: parseInt(draftWeekStartDay, 10),
      defaultView: draftDefaultView,
      showWeekNumbers: draftShowWeekNumbers,
      customWeekStartHour: draftCustomWeekStartHour,
      customWeekEndHour: draftCustomWeekEndHour,
      customDayStartHour: draftCustomDayStartHour,
      customDayEndHour: draftCustomDayEndHour,
      defaultCalendarId: draftDefaultCalendarId,
      reminderMinutes: parseInt(draftReminderMinutes, 10),
      calendarNames: draftCalendarNames,
      calendarColors: draftCalendarColors,
      hiddenCalendars: draftHiddenCalendars
    })
    if (calendarService) {
      calendarService.setReminderMinutes(parseInt(draftReminderMinutes, 10), draftTimeFormat)
      calendarService.updateCalendars(root.calendarAppearanceEntries(), draftCalendarNames, draftCalendarColors)
    }
    appliedDefaultView = false
    showingSettings = false
    refresh()
  }

  function loadSettingsDraft() {
    draftTimeFormat = timeFormat
    draftWeekStartDay = weekStartSetting === "0" || weekStartSetting === "1" ? weekStartSetting : String(weekStart)
    draftDefaultView = defaultView
    draftShowWeekNumbers = showWeekNumbers
    draftCustomWeekStartHour = customWeekStartHour
    draftCustomWeekEndHour = customWeekEndHour
    draftCustomDayStartHour = customDayStartHour
    draftCustomDayEndHour = customDayEndHour
    draftDefaultCalendarId = defaultCalendarId
    draftReminderMinutes = String(reminderMinutes)
    draftCalendarNames = root.loadedCalendarNames()
    draftCalendarColors = root.loadedCalendarColors()
    draftHiddenCalendars = Model.copyMap(hiddenCalendars)
  }

  function restoreSettingsDefaults() {
    draftTimeFormat = "12h"
    draftWeekStartDay = "1"
    draftDefaultView = "month"
    draftShowWeekNumbers = true
    draftCustomWeekStartHour = 8
    draftCustomWeekEndHour = 18
    draftCustomDayStartHour = 0
    draftCustomDayEndHour = 24
    draftDefaultCalendarId = ""
    draftReminderMinutes = "10"
    draftCalendarNames = ({})
    draftCalendarColors = ({})
    draftHiddenCalendars = ({})
    settingsError = ""
  }

  function pad2(value) {
    return (value < 10 ? "0" : "") + String(value)
  }

  function slotValueFromMinutes(totalMinutes, snap) {
    var minutes = Math.max(0, Math.min(24 * 60, Number(totalMinutes) || 0))
    if (snap !== false) minutes = Math.round(minutes / 30) * 30
    var hours = Math.floor(minutes / 60)
    var rest = Math.round(minutes % 60)
    if (hours >= 24) return "24:00"
    return pad2(hours) + ":" + pad2(rest)
  }

  function slotValueFromHour(hour) {
    return slotValueFromMinutes(hour * 60)
  }

  function slotValueFromIso(iso) {
    var parsed = Date.parse(String(iso || ""))
    if (isNaN(parsed)) return "09:00"
    var date = new Date(parsed)
    return slotValueFromMinutes(date.getHours() * 60 + date.getMinutes(), false)
  }

  function timeSlotChoices(include24, format) {
    var result = []
    var last = include24 ? 24 * 60 : 23 * 60 + 30
    for (var minutes = 0; minutes <= last; minutes += 30) result.push({ value: slotValueFromMinutes(minutes), label: timeText(minutes / 60, format || root.timeFormat) })
    return result
  }

  function hourChoices(include24, format) {
    var result = []
    var last = include24 ? 24 : 23
    for (var hour = 0; hour <= last; hour++) result.push({ value: String(hour), label: timeText(hour, format || root.timeFormat) })
    return result
  }

  function loadedCalendarNames() {
    return Model.copyMap(calendarNames)
  }

  function loadedCalendarColors() {
    return Model.copyMap(calendarColors)
  }

  function setDraftCalendarName(calendarId, name) {
    var next = Model.copyMap(draftCalendarNames)
    next[calendarId] = name
    draftCalendarNames = next
  }

  function setDraftCalendarColor(calendarId, color) {
    var next = Model.copyMap(draftCalendarColors)
    next[calendarId] = color
    draftCalendarColors = next
  }

  function uniqueThemeColors() {
    var result = []
    for (var i = 0; i < themeColorPalette.length; i++) {
      var color = Model.normalizeColor(themeColorPalette[i])
      if (color && result.indexOf(color) === -1) result.push(color)
    }
    return result
  }

  function askRemoveCalendar(calendar, name) {
    removeCandidateName = String(name || "")
    removeCandidate = calendar
  }

  function cancelRemoveCalendar() {
    removeCandidate = null
    removeCandidateName = ""
  }

  function confirmRemoveCalendar() {
    var calendar = removeCandidate
    cancelRemoveCalendar()
    if (!calendar || !calendar.id) return
    if (root.draftDefaultCalendarId === calendar.id) root.draftDefaultCalendarId = ""
    if (calendarService) calendarService.removeCalendar(calendar.id)
  }

  function removeConfirmMessage() {
    var calendar = removeCandidate
    if (!calendar) return ""
    var account = Model.providerLabel(calendar.provider, calendar.host)
    var name = "\u201c" + removeCandidateName + "\u201d"
    if (calendar.provider === "caldav" || calendar.provider === "webcal")
      return "Remove " + name + " from this computer? It stays on " + account + ", but stops syncing here until you add it again. To keep it but not see it, switch it off instead."
    return "Delete " + name + "? It only exists on this computer, so its events are deleted."
  }

  function setDraftCalendarHidden(calendarId, hidden) {
    var next = Model.copyMap(draftHiddenCalendars)
    if (hidden) next[calendarId] = true
    else delete next[calendarId]
    draftHiddenCalendars = next
  }

  function setDraftGroupHidden(group, hidden) {
    var next = Model.copyMap(draftHiddenCalendars)
    for (var i = 0; i < group.calendars.length; i++) {
      var id = group.calendars[i].calendar.id
      if (hidden) next[id] = true
      else delete next[id]
    }
    draftHiddenCalendars = next
  }

  // The calendars menu in the header shows and hides straight away; the
  // settings page edits a draft that Save applies.
  function setCalendarHidden(calendarId, hidden) {
    var next = Model.copyMap(hiddenCalendars)
    if (hidden) next[calendarId] = true
    else delete next[calendarId]
    persistSettings({ hiddenCalendars: next })
  }

  function setGroupHidden(group, hidden) {
    var next = Model.copyMap(hiddenCalendars)
    for (var i = 0; i < group.calendars.length; i++) {
      var id = group.calendars[i].calendar.id
      if (hidden) next[id] = true
      else delete next[id]
    }
    persistSettings({ hiddenCalendars: next })
  }

  function calendarAppearanceEntries() {
    var result = []
    if (!calendarService) return result
    for (var i = 0; i < calendarService.calendars.length; i++) {
      var calendar = calendarService.calendars[i]
      if (!calendar) continue
      result.push({
        id: calendar.id,
        name: Model.calendarDisplayName(calendar, draftCalendarNames),
        color: Model.calendarDisplayColor(calendar, draftCalendarColors, i)
      })
    }
    return result
  }

  function eventColor(event) {
    if (!event) return Commons.Color.accent
    var calendar = calendarService ? calendarService.calendarById(event.calendarId) : null
    var index = 0
    if (calendarService) {
      for (var i = 0; i < calendarService.calendars.length; i++) {
        if (calendarService.calendars[i] && calendarService.calendars[i].id === event.calendarId) index = i
      }
    }
    return Model.calendarDisplayColor(calendar || { id: event.calendarId, color: event.calendarColor }, calendarColors, index)
  }

  function eventCalendarName(event) {
    if (!event) return ""
    var calendar = calendarService ? calendarService.calendarById(event.calendarId) : null
    return Model.calendarDisplayName(calendar || { id: event.calendarId, name: event.calendarName }, calendarNames)
  }

  function eventTimeRange(event) {
    if (!event) return ""
    if (event.allDay) return "All day"
    var start = Model.formatTime(event.start, false, root.timeFormat)
    var end = Model.formatTime(event.end, false, root.timeFormat)
    if (!end || end === start) return start
    return start + " – " + end
  }

  function eventTooltip(event) {
    if (!event) return ""
    var lines = [event.title || "(No title)", root.eventTimeRange(event)]
    var calendarName = root.eventCalendarName(event)
    if (calendarName) lines.push(calendarName)
    if (event.location) lines.push(event.location)
    if (event.meetingUrl) lines.push("Join " + Model.meetingProviderLabel(event.meetingProvider))
    return Model.plainDisplay(lines.join("\n"), 600)
  }

  function joinEvent(event) {
    var url = event && event.meetingUrl ? String(event.meetingUrl) : ""
    if (!/^https?:\/\//i.test(url) || !root.bar) return
    root.bar.run("xdg-open '" + url.replace(/'/g, "") + "'")
  }

  function eventIsRecurring(event) {
    return !!(event && (event.recurring === true || event.rid))
  }

  function eventIsReadonly(event) {
    if (!event) return false
    var calendar = calendarService ? calendarService.calendarById(event.calendarId) : null
    return event.provider === "webcal" || !!(calendar && calendar.readonly === true)
  }

  function handleEventClick(event, mouse, item) {
    if (!event || event.status === "saving") return
    if (eventMenu.opened) {
      root.closeEventMenu()
      return
    }
    if (mouse && mouse.button === Qt.RightButton) {
      root.openEventMenu(event, item, mouse)
      return
    }
    if (root.eventIsRecurring(event) || root.eventIsReadonly(event)) {
      root.openEventMenu(event, item, mouse)
      return
    }
    root.startEditingEvent(event, "all")
  }

  function openEventMenu(event, item, mouse) {
    root.contextEvent = event
    var pos = item.mapToItem(keyCatcher, mouse.x, mouse.y)
    eventMenu.x = Math.max(0, Math.min(pos.x, keyCatcher.width - eventMenu.width))
    eventMenu.y = Math.max(0, Math.min(pos.y, keyCatcher.height - eventMenu.height))
    eventMenu.open()
  }

  function closeEventMenu() {
    eventMenu.close()
    root.contextEvent = null
  }

  function writableCalendarOptions() {
    var result = []
    if (!calendarService) return result
    for (var i = 0; i < calendarService.calendars.length; i++) {
      var calendar = calendarService.calendars[i]
      if (calendar && calendar.readonly !== true) result.push({ value: calendar.id, label: Model.calendarChoiceLabel(calendar, showingSettings ? draftCalendarNames : calendarNames) })
    }
    return result
  }

  function writableCalendarChoices() {
    return [{ value: "", label: "Automatic" }].concat(writableCalendarOptions())
  }


  function selectedWritableCalendarId() {
    if (defaultCalendarId !== "" && calendarService) {
      for (var i = 0; i < calendarService.calendars.length; i++) {
        var calendar = calendarService.calendars[i]
        if (calendar && calendar.id === defaultCalendarId && calendar.readonly !== true) return calendar.id
      }
    }
    return calendarService ? calendarService.defaultWritableCalendarId() : ""
  }

  function commitSetup() {
    if (!calendarService) {
      setupError = "Calendar service is not loaded."
      return
    }
    if (calendarService.setupBusy) return
    if (setupKind === "local") {
      if (setupName === "") {
        setupError = "Give the calendar a name."
        return
      }
      setupError = ""
      calendarService.createLocalCalendar(setupName)
      return
    }
    if (setupKind === "webcal") {
      if (setupUrl === "") {
        setupError = "An iCalendar URL is required."
        return
      }
      setupError = ""
      calendarService.setupWebCal(setupName, setupUrl)
      return
    }
    if (setupUrl === "" || setupUser === "" || setupPassword === "") {
      setupError = "URL, username, and password are required."
      return
    }
    setupError = ""
    calendarService.setupCalDav(setupName, setupUrl, setupUser, setupPassword)
    setupPassword = ""
  }

  function cancelCreatingEvent() {
    creatingEvent = false
    editingEvent = null
    createRecurrence = Model.defaultRecurrence(selectedKey)
    createAllDay = false
    createMeetingUrl = ""
    createMeetingKind = "none"
    createError = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function startEditingEvent(event, scope) {
    if (!event) return
    if (event.status === "saving" || !event.uid || root.eventIsReadonly(event)) return
    createError = ""
    showingSetup = false
    showingSettings = false
    editingEvent = event
    editScope = scope || (root.eventIsRecurring(event) ? "this" : "all")
    selectedKey = (event.allDay ? Model.eventDateKey(event) : Model.localDateKeyFromIso(event.start)) || selectedKey
    createDateKey = selectedKey
    createAllDay = event.allDay === true
    createCalendarId = event.calendarId || selectedWritableCalendarId()
    creatingEvent = true
    Qt.callLater(function() {
      titleField.text = event.title || ""
      root.createStartTime = event.allDay ? "09:00" : root.slotValueFromIso(event.start)
      root.createEndTime = event.allDay ? "10:00" : root.slotValueFromIso(event.end)
      root.createRecurrence = Model.defaultRecurrence(root.createDateKey)
      locationField.text = event.location || ""
      root.createMeetingUrl = event.meetingUrl || ""
      root.createMeetingKind = event.meetingUrl ? "link" : "none"
      titleField.forceActiveFocus()
    })
  }

  function setCreateDate(key) {
    createDateKey = key
    createRecurrence = Model.recurrenceForDate(createRecurrence, key)
  }

  function patchRecurrence(patch) {
    var next = Model.copyRecurrence(createRecurrence)
    var keys = Object.keys(patch || {})
    for (var i = 0; i < keys.length; i++) next[keys[i]] = patch[keys[i]]
    createRecurrence = next
  }

  function restoreRecurrenceDropdownBinding(dropdown, field) {
    dropdown.value = Qt.binding(function() { return String(root.createRecurrence[field]) })
  }

  function setRecurrenceFreq(freq) {
    var next = Model.copyRecurrence(createRecurrence)
    var date = Model.dateFromKey(createDateKey, today)
    next.freq = freq
    next.weekdaysOnly = freq === "weekday"
    if (freq === "weekday") next.weekdays = [false, true, true, true, true, true, false]
    else if (freq === "weekly") next.weekdays = Model.normalizedWeekdays(null, date.getDay())
    next.weekday = date.getDay()
    createRecurrence = next
    createDateKey = Model.nextOccurrenceDate(createDateKey, next)
  }

  function toggleRecurrenceWeekday(day) {
    var next = Model.copyRecurrence(createRecurrence)
    next.weekdays = next.weekdays.slice()
    next.weekdays[day] = !next.weekdays[day]
    if (!next.weekdays.some(function(on) { return on })) next.weekdays[day] = true
    next.freq = "weekly"
    next.weekdaysOnly = false
    createRecurrence = next
    createDateKey = Model.nextOccurrenceDate(createDateKey, next)
  }

  function setMonthlyChoice(value) {
    if (value === "bymonthday") patchRecurrence({ monthlyMode: "bymonthday" })
    else patchRecurrence({ monthlyMode: "byday", bysetpos: parseInt(String(value).split(":")[1], 10) || 1 })
  }

  function setYearlyChoice(value) {
    if (value === "bymonthday") patchRecurrence({ yearlyMode: "bymonthday" })
    else patchRecurrence({ yearlyMode: "byday", bysetpos: parseInt(String(value).split(":")[1], 10) || 1 })
  }

  function recurrenceIntervalLabel() {
    var freq = createRecurrence.freq
    var plural = createRecurrence.interval === 1 ? "" : "s"
    if (freq === "daily") return "day" + plural
    if (freq === "monthly") return "month" + plural
    if (freq === "yearly") return "year" + plural
    return "week" + plural
  }

  function commitCreatingEvent() {
    if (!creatingEvent) return
    createDateKey = Model.nextOccurrenceDate(createDateKey, createRecurrence)
    var startIso = createAllDay ? createDateKey : Model.dateTimeIso(createDateKey, createStartTime)
    var endIso = createAllDay ? Model.nextDateKey(createDateKey) : Model.endDateTimeIso(createDateKey, createStartTime, createEndTime)
    if (!startIso || !endIso) {
      createError = createAllDay ? "Choose a date." : (createStartTime === createEndTime ? "End time must be after start time." : "Choose a start and end time.")
      return
    }
    if (!calendarService) {
      createError = "Calendar service is not loaded."
      return
    }
    var calendarId = editingEvent ? editingEvent.calendarId : (createCalendarId || selectedWritableCalendarId())
    if (!calendarId) {
      createError = "No writable calendar is available."
      return
    }
    var meetingInput = String(root.createMeetingUrl || "").trim()
    var meeting = meetingInput ? Model.meetingFromText(meetingInput) : { url: "", provider: "" }
    if (meetingInput && !meeting.url) {
      createError = "Paste a Zoom, Google Meet, or Teams link."
      return
    }
    var meetingUrl = meeting.url
    root.createMeetingUrl = meetingUrl
    root.createMeetingKind = meetingUrl ? "link" : "none"
    var location = locationField.text
    if (meetingUrl && location.indexOf(meetingUrl) < 0 && location.indexOf(meetingInput) < 0) location = location ? (location + " · " + meetingUrl) : meetingUrl
    var service = calendarService
    var editedEvent = editingEvent
    var title = titleField.text
    var recurrence = Model.serializeRecurrence(root.createRecurrence)
    var allDay = createAllDay
    var meetingKind = root.createMeetingKind
    var scope = root.editScope
    var destinationCalendarId = createCalendarId
    creatingEvent = false
    editingEvent = null
    createError = ""
    Qt.callLater(function() {
      if (editedEvent) service.updateEvent(editedEvent, title, startIso, endIso, location, editedEvent.description || "", scope, allDay, destinationCalendarId, meetingUrl, meetingKind)
      else service.createEvent(calendarId, title, startIso, endIso, location, "", recurrence, allDay, meetingUrl, meetingKind)
    })
  }

  function openEvolution() {
    if (root.bar) root.bar.run("evolution -c calendar")
  }

  Timer {
    interval: 10000
    running: root.active && root.viewMode !== "month"
    repeat: true
    onTriggered: root.now = new Date()
  }

  Timer {
    interval: 20000
    running: root.active
    repeat: true
    onTriggered: { if (calendarService) calendarService.pollRemote() }
  }

  Timer {
    interval: 2000
    running: root.active && root.needsEdsInstall
    repeat: true
    onTriggered: { if (calendarService) calendarService.probeEds() }
  }

  Timer {
    interval: 1000
    running: root.active && root.edsLoading
    repeat: true
    onTriggered: { if (calendarService) calendarService.retryEdsSnapshot() }
  }

  Connections {
    target: calendarService
    function onEventSaved(ok, message) {
      if (ok || root.creatingEvent) return
      root.createError = message || "Could not save the event."
    }
    function onSetupFinished(ok, message) {
      if (ok) {
        root.showingSetup = false
        root.setupError = ""
        root.setupName = "Calendar"
        root.setupUrl = ""
        root.setupUser = ""
        root.setupPassword = ""
      } else {
        root.setupError = message
      }
    }
  }

  // An ordinary xdg toplevel (class org.quickshell, title Calendar), so it
  // tiles like any other app. The calendar content is moved into it when this
  // copy of the panel is created in window mode. Closing it only hides it.
  FloatingWindow {
    id: appWindow
    visible: root.windowMode && root.windowShown
    title: "Calendar"
    color: Commons.Color.background
    implicitWidth: Style.space(1180)
    implicitHeight: Style.space(860)
    minimumSize: Qt.size(Style.space(640), Style.space(480))
    onVisibleChanged: if (!visible) root.windowShown = false

    Item {
      id: windowBody
      anchors.fill: parent
      anchors.margins: Style.space(16)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.compactEds ? 640 : (root.showDayPanel ? 1080 : 860)))
    contentHeight: panel.fittedContentHeight(calendarScroll.contentHeight + pinnedHeader.height)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.creatingEvent || root.showingSetup || root.showingSettings
      onMoveRequested: function(dx, dy) {
        if (root.showingSettings) return
        if (dx !== 0) root.movePeriod(dx)
        if (dy !== 0 && root.viewMode === "month") root.movePeriod(dy * 12)
      }
      onActivateRequested: if (!root.showingSettings) root.goToToday()
      onCloseRequested: {
        if (root.removeCandidate !== null) root.cancelRemoveCalendar()
        else if (calendarsMenu.opened) calendarsMenu.close()
        else if (root.showingSettings) root.cancelSettings()
        else if (!root.windowMode) root.close()
      }
      onTabRequested: function(direction) { if (!root.showingSettings && !root.windowMode) root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.showingSettings) return
        if (t === "[") root.movePeriod(-1)
        else if (t === "]") root.movePeriod(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "n" || t === "N") root.creatingEvent && !root.editingEvent ? root.cancelCreatingEvent() : root.startCreatingEvent()
        else if (t === "m" || t === "M") root.setView("month")
        else if (t === "d" || t === "D") root.setView("day")
        else if (t === "w" || t === "W") root.setView("week")
      }

      ConfirmDialog {
        id: removeConfirm
        anchors.fill: parent
        z: 20
        opened: root.removeCandidate !== null
        selectedIndex: 0
        message: root.removeConfirmMessage()
        confirmText: root.removeCandidate && (root.removeCandidate.provider === "caldav" || root.removeCandidate.provider === "webcal") ? "Remove" : "Delete"
        background: Commons.Color.popups.background
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onCanceled: root.cancelRemoveCalendar()
        onConfirmed: root.confirmRemoveCalendar()
        onOpenedChanged: if (opened) selectedIndex = 0
      }

      // The header stays put; only the calendar under it scrolls.
      Item {
        id: pinnedHeader
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: calendarColumn.width
        height: headerBar.visible ? headerBar.height + Style.space(12) : 0

        Item {
          id: headerBar
          visible: !root.showingSettings && !root.compactEds
          width: parent.width
          readonly property real rowHeight: Math.max(viewControls.implicitHeight, titleColumn.implicitHeight, actionControls.implicitHeight, settingsTopButton.implicitHeight)
          readonly property real rightWidth: actionControls.implicitWidth + calendarsMenuButton.width + dayPanelToggle.width + (windowButton.visible ? windowButton.width : 0) + settingsTopButton.width + Style.space(28)
          // A narrow window puts the title on its own row above the controls,
          // and a very narrow one gives the view buttons a row of their own.
          readonly property bool stacked: width < viewControls.implicitWidth + titleNav.width + rightWidth + Style.space(24)
          readonly property bool narrow: width < viewControls.implicitWidth + rightWidth + Style.space(16)
          readonly property int rows: narrow ? 3 : (stacked ? 2 : 1)
          readonly property real rowStep: rowHeight + Style.space(8)
          readonly property real titleOffset: -(rows - 1) * rowStep / 2
          readonly property real viewOffset: titleOffset + (rows > 1 ? rowStep : 0)
          readonly property real controlsOffset: (rows - 1) * rowStep / 2
          height: rowHeight * rows + Style.space(8) * (rows - 1)

          Row {
            id: viewControls
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: headerBar.viewOffset
            spacing: Style.space(4)
            ViewButton { text: "Month"; selected: root.viewMode === "month"; onClicked: root.setView("month"); onDoubleClicked: { root.setView("month"); root.goToToday() } }
            ViewButton { text: "Week"; selected: root.viewMode === "week"; onClicked: root.setView("week"); onDoubleClicked: { root.setView("week"); root.goToToday() } }
            ViewButton { text: "Work week"; selected: root.viewMode === "work-week"; onClicked: root.setView("work-week"); onDoubleClicked: { root.setView("work-week"); root.goToToday() } }
            ViewButton { text: "Day"; selected: root.viewMode === "day"; onClicked: root.setView("day"); onDoubleClicked: { root.setView("day"); root.goToToday() } }
          }

          Item {
            id: titleNav
            width: Style.space(260)
            height: Math.max(previousButton.implicitHeight, titleColumn.implicitHeight, nextButton.implicitHeight)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: headerBar.titleOffset

            PanelActionButton {
              id: previousButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "‹"
              tooltipText: "Previous"
              onClicked: root.movePeriod(-1)
            }
            Column {
              id: titleColumn
              anchors.left: previousButton.right
              anchors.right: nextButton.left
              anchors.leftMargin: Style.space(4)
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.headline
                color: Commons.Color.foreground
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.heading
                font.bold: true

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onDoubleClicked: root.goToToday()
                }
              }
              Text {
                width: parent.width
                text: calendarService ? ((calendarService.syncing ? "Syncing" : (calendarService.lastSyncText === "Cached" || calendarService.lastSyncText === "Never synced" ? calendarService.lastSyncText : "Synced " + calendarService.lastSyncText)) + " · " + calendarService.calendars.length + " calendars") : "Calendar service not loaded"
                color: Commons.Color.muted
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
            PanelActionButton {
              id: nextButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "›"
              tooltipText: "Next"
              onClicked: root.movePeriod(1)
            }
          }

          Row {
            id: actionControls
            anchors.right: calendarsMenuButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: headerBar.controlsOffset
            spacing: Style.space(6)
            Button { id: syncButton; text: "Sync"; tooltipText: "Sync now"; onClicked: root.refresh(true) }
            Button { text: "Add event"; bordered: true; enabled: calendarService && root.selectedWritableCalendarId() !== ""; selected: root.creatingEvent && !root.editingEvent; onClicked: root.creatingEvent && !root.editingEvent ? root.cancelCreatingEvent() : root.startCreatingEvent() }
          }

          PanelActionButton {
            id: calendarsMenuButton
            visible: !root.showingSettings
            anchors.right: dayPanelToggle.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: headerBar.controlsOffset
            iconText: "󰃭"
            tooltipText: root.hiddenCalendarCount > 0 ? "Calendars (" + root.hiddenCalendarCount + " hidden)" : "Show or hide calendars"
            bordered: root.hiddenCalendarCount > 0 || calendarsMenu.opened
            onClicked: calendarsMenu.opened ? calendarsMenu.close() : calendarsMenu.open()

            CalendarsMenu {
              id: calendarsMenu
              objectName: "calendarsMenu"
              x: parent.width - width
              y: parent.height + Style.space(6)
            }
          }

          PanelActionButton {
            id: dayPanelToggle
            visible: !root.showingSettings
            anchors.right: windowButton.visible ? windowButton.left : settingsTopButton.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: headerBar.controlsOffset
            iconText: "\uebf4"
            tooltipText: root.showDayPanel ? "Hide day panel" : "Show day panel"
            bordered: root.showDayPanel
            onClicked: root.toggleDayPanel()
          }

          PanelActionButton {
            id: windowButton
            visible: !root.windowMode && !root.showingSettings && !!root.hostWidget
            anchors.right: settingsTopButton.left
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: headerBar.controlsOffset
            iconText: "󰖯"
            tooltipText: "Open in a window"
            onClicked: root.openInWindow()
          }

          PanelActionButton {
            id: settingsTopButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: headerBar.controlsOffset
            iconText: "󰒓"
            tooltipText: root.showingSettings ? "Close settings" : "CalDav Calendar settings"
            bordered: root.showingSettings
            onClicked: root.toggleSettings()
          }
        }
      }

      Flickable {
        id: calendarScroll
        anchors.top: pinnedHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: contentWrap.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Item {
          id: contentWrap
          width: calendarScroll.width
          height: calendarColumn.implicitHeight

          Column {
            id: calendarColumn
            width: root.windowMode ? parent.width : Math.min(parent.width, Style.space(root.compactEds ? 620 : (root.showDayPanel ? 1060 : 820)))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(12)


            SettingsPage { visible: root.showingSettings; width: parent.width }

            Rectangle {
              visible: root.creatingEvent && !root.showingSettings
              width: parent.width
              height: createForm.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
              border.color: Commons.Color.accent
              border.width: 1

              Column {
                id: createForm
                anchors.fill: parent
                anchors.margins: Style.space(10)
                spacing: Style.space(8)

                Text {
                  width: parent.width
                  text: root.editingEvent
                    ? (root.editScope === "all" && root.eventIsRecurring(root.editingEvent) ? "Edit series" : "Edit event")
                    : "New event"
                  color: Commons.Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                TextField { id: titleField; width: parent.width; placeholderText: "Add title"; onAccepted: root.commitCreatingEvent() }

                Row {
                  spacing: Style.space(12)
                  DatePicker {
                    label: "Date"
                    value: root.createDateKey
                    onChanged: function(value) { root.setCreateDate(value) }
                  }
                  Column {
                    spacing: Style.space(4)
                    Text {
                      text: "All day"
                      color: Commons.Color.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    ToggleSwitch {
                      checked: root.createAllDay
                      onToggled: root.createAllDay = !root.createAllDay
                    }
                  }
                  TimePicker {
                    visible: !root.createAllDay
                    label: "Start"
                    value: root.createStartTime
                    onChanged: function(value) { root.createStartTime = value }
                  }
                  Text {
                    visible: !root.createAllDay
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(6)
                    text: "–"
                    color: Commons.Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                  }
                  TimePicker {
                    visible: !root.createAllDay
                    label: "End"
                    value: root.createEndTime
                    onChanged: function(value) { root.createEndTime = value }
                  }
                }

                Column {
                  visible: !root.editingEvent
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    text: "Repeat"
                    color: Commons.Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Flow {
                    width: parent.width
                    spacing: Style.space(8)

                    Dropdown {
                      id: recurrenceFrequencyDropdown
                      width: Style.space(168)
                      showLabel: false
                      value: root.createRecurrence.freq
                      options: [
                        { value: "never", label: "Does not repeat" },
                        { value: "daily", label: "Daily" },
                        { value: "weekly", label: "Weekly" },
                        { value: "monthly", label: "Monthly" },
                        { value: "yearly", label: "Yearly" }
                      ]
                      foreground: Commons.Color.foreground
                      background: Commons.Color.popups.background
                      onChanged: function(value) {
                        root.setRecurrenceFreq(value)
                        root.restoreRecurrenceDropdownBinding(recurrenceFrequencyDropdown, "freq")
                      }
                    }

                    Row {
                      visible: root.createRecurrence.freq !== "never"
                      spacing: Style.space(6)
                      height: Style.space(28)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "every"
                        color: Commons.Color.foreground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }
                      TimeSpin {
                        display: String(root.createRecurrence.interval)
                        choices: {
                          var list = []
                          for (var n = 1; n <= 30; n++) list.push({ value: String(n), label: String(n) })
                          return list
                        }
                        onAdjust: function(delta) { root.patchRecurrence({ interval: Math.max(1, Math.min(30, root.createRecurrence.interval + delta)) }) }
                        onTyped: function(number) { root.patchRecurrence({ interval: Math.max(1, Math.min(30, number)) }) }
                        onPicked: function(choice) { root.patchRecurrence({ interval: parseInt(choice, 10) || 1 }) }
                      }
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.recurrenceIntervalLabel()
                        color: Commons.Color.foreground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }
                    }

                    Row {
                      visible: root.createRecurrence.freq === "monthly"
                      spacing: Style.space(6)
                      Dropdown {
                        id: recurrenceMonthlyModeDropdown
                        width: Style.space(110)
                        showLabel: false
                        value: root.createRecurrence.monthlyMode
                        options: [
                          { value: "bymonthday", label: "On day" },
                          { value: "byday", label: "On the" }
                        ]
                        foreground: Commons.Color.foreground
                        background: Commons.Color.popups.background
                        onChanged: function(value) {
                          root.patchRecurrence({ monthlyMode: value })
                          root.restoreRecurrenceDropdownBinding(recurrenceMonthlyModeDropdown, "monthlyMode")
                        }
                      }
                      Dropdown {
                        id: recurrenceMonthlyDayDropdown
                        visible: root.createRecurrence.monthlyMode !== "byday"
                        width: Style.space(72)
                        showLabel: false
                        value: String(root.createRecurrence.monthDay)
                        options: Model.monthDayOptions()
                        foreground: Commons.Color.foreground
                        background: Commons.Color.popups.background
                        onChanged: function(value) {
                          root.patchRecurrence({ monthDay: parseInt(value, 10) || 1 })
                          root.restoreRecurrenceDropdownBinding(recurrenceMonthlyDayDropdown, "monthDay")
                        }
                      }
                      Dropdown {
                        id: recurrenceMonthlyOrdinalDropdown
                        visible: root.createRecurrence.monthlyMode === "byday"
                        width: Style.space(110)
                        showLabel: false
                        value: String(root.createRecurrence.bysetpos)
                        options: Model.ordinalOptions()
                        foreground: Commons.Color.foreground
                        background: Commons.Color.popups.background
                        onChanged: function(value) {
                          root.patchRecurrence({ bysetpos: parseInt(value, 10) || 1 })
                          root.restoreRecurrenceDropdownBinding(recurrenceMonthlyOrdinalDropdown, "bysetpos")
                        }
                      }
                      Dropdown {
                        id: recurrenceMonthlyWeekdayDropdown
                        visible: root.createRecurrence.monthlyMode === "byday"
                        width: Style.space(130)
                        showLabel: false
                        value: String(root.createRecurrence.weekday)
                        options: Model.weekdayNameOptions()
                        foreground: Commons.Color.foreground
                        background: Commons.Color.popups.background
                        onChanged: function(value) {
                          root.patchRecurrence({ weekday: parseInt(value, 10) || 0 })
                          root.restoreRecurrenceDropdownBinding(recurrenceMonthlyWeekdayDropdown, "weekday")
                        }
                      }
                    }

                    Row {
                      visible: root.createRecurrence.freq === "yearly"
                      spacing: Style.space(6)
                      Dropdown {
                        id: recurrenceYearlyModeDropdown
                        width: Style.space(110)
                        showLabel: false
                        value: root.createRecurrence.yearlyMode
                        options: [
                          { value: "bymonthday", label: "On" },
                          { value: "byday", label: "On the" }
                        ]
                        foreground: Commons.Color.foreground
                        background: Commons.Color.popups.background
                        onChanged: function(value) {
                          root.patchRecurrence({ yearlyMode: value })
                          root.restoreRecurrenceDropdownBinding(recurrenceYearlyModeDropdown, "yearlyMode")
                        }
                      }
                      Dropdown {
                        id: recurrenceYearlyOrdinalDropdown
                        visible: root.createRecurrence.yearlyMode === "byday"
                        width: Style.space(110)
                        showLabel: false
                        value: String(root.createRecurrence.bysetpos)
                        options: Model.ordinalOptions()
                        foreground: Commons.Color.foreground
                        background: Commons.Color.popups.background
                        onChanged: function(value) {
                          root.patchRecurrence({ bysetpos: parseInt(value, 10) || 1 })
                          root.restoreRecurrenceDropdownBinding(recurrenceYearlyOrdinalDropdown, "bysetpos")
                        }
                      }
                      Dropdown {
                        id: recurrenceYearlyWeekdayDropdown
                        visible: root.createRecurrence.yearlyMode === "byday"
                        width: Style.space(130)
                        showLabel: false
                        value: String(root.createRecurrence.weekday)
                        options: Model.weekdayNameOptions()
                        foreground: Commons.Color.foreground
                        background: Commons.Color.popups.background
                        onChanged: function(value) {
                          root.patchRecurrence({ weekday: parseInt(value, 10) || 0 })
                          root.restoreRecurrenceDropdownBinding(recurrenceYearlyWeekdayDropdown, "weekday")
                        }
                      }
                      Dropdown {
                        id: recurrenceYearlyMonthDropdown
                        width: Style.space(130)
                        showLabel: false
                        value: String(root.createRecurrence.month)
                        options: Model.monthNameOptions()
                        foreground: Commons.Color.foreground
                        background: Commons.Color.popups.background
                        onChanged: function(value) {
                          root.patchRecurrence({ month: parseInt(value, 10) || 1 })
                          root.restoreRecurrenceDropdownBinding(recurrenceYearlyMonthDropdown, "month")
                        }
                      }
                      Dropdown {
                        id: recurrenceYearlyDayDropdown
                        visible: root.createRecurrence.yearlyMode !== "byday"
                        width: Style.space(72)
                        showLabel: false
                        value: String(root.createRecurrence.monthDay)
                        options: Model.monthDayOptions()
                        foreground: Commons.Color.foreground
                        background: Commons.Color.popups.background
                        onChanged: function(value) {
                          root.patchRecurrence({ monthDay: parseInt(value, 10) || 1 })
                          root.restoreRecurrenceDropdownBinding(recurrenceYearlyDayDropdown, "monthDay")
                        }
                      }
                    }

                    Row {
                      visible: root.createRecurrence.freq !== "never"
                      spacing: Style.space(6)
                      height: Style.space(28)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "ends"
                        color: Commons.Color.foreground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }
                      Dropdown {
                        id: recurrenceEndDropdown
                        width: Style.space(120)
                        showLabel: false
                        value: root.createRecurrence.end
                        options: [
                          { value: "never", label: "Never" },
                          { value: "until", label: "On date" },
                          { value: "count", label: "After" }
                        ]
                        foreground: Commons.Color.foreground
                        background: Commons.Color.popups.background
                        onChanged: function(value) {
                          root.patchRecurrence({ end: value })
                          root.restoreRecurrenceDropdownBinding(recurrenceEndDropdown, "end")
                        }
                      }
                      DatePicker {
                        visible: root.createRecurrence.end === "until"
                        showLabel: false
                        width: Style.space(150)
                        value: root.createRecurrence.until || root.selectedKey
                        onChanged: function(value) { root.patchRecurrence({ until: value }) }
                      }
                      TimeSpin {
                        visible: root.createRecurrence.end === "count"
                        display: String(root.createRecurrence.count)
                        choices: {
                          var list = []
                          for (var n = 1; n <= 50; n++) list.push({ value: String(n), label: String(n) })
                          return list
                        }
                        onAdjust: function(delta) { root.patchRecurrence({ count: Math.max(1, Math.min(730, root.createRecurrence.count + delta)) }) }
                        onTyped: function(number) { root.patchRecurrence({ count: Math.max(1, Math.min(730, number)) }) }
                        onPicked: function(choice) { root.patchRecurrence({ count: parseInt(choice, 10) || 1 }) }
                      }
                      Text {
                        visible: root.createRecurrence.end === "count"
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.createRecurrence.count === 1 ? "time" : "times"
                        color: Commons.Color.foreground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.bodySmall
                      }
                    }
                  }

                  Row {
                    visible: root.createRecurrence.freq === "weekly" || root.createRecurrence.freq === "weekday"
                    spacing: Style.space(4)
                    Repeater {
                      model: Model.weekdayOrder(root.weekStart)
                      WeekdayChip {
                        required property int modelData
                        day: modelData
                        selected: root.createRecurrence.weekdays[modelData] === true
                        onClicked: root.toggleRecurrenceWeekday(day)
                      }
                    }
                  }

                  Text {
                    visible: root.createRecurrence.freq !== "never"
                    width: parent.width
                    text: Model.summarizeRecurrence(root.createRecurrence, root.createDateKey)
                    color: Commons.Color.foreground
                    wrapMode: Text.WordWrap
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                   }
                 }

                 Column {
                   width: parent.width
                   spacing: Style.space(4)
                   Text {
                     text: "Meeting"
                     color: Commons.Color.foreground
                     font.family: root.bar ? root.bar.fontFamily : Style.font.family
                     font.pixelSize: Style.font.caption
                     font.bold: true
                   }
                   TextField {
                     width: parent.width
                     height: Style.spacing.controlHeight
                     text: root.createMeetingUrl
                     placeholderText: "https://zoom.us/j/… or Meet / Teams link"
                     onTextChanged: root.createMeetingUrl = text
                     onAccepted: root.commitCreatingEvent()
                   }
                 }

                 Row {
                   width: parent.width
                   spacing: Style.space(8)
                   Column {
                     width: calendarPicker.visible ? Math.round((parent.width - parent.spacing) / 2) : parent.width
                    spacing: Style.space(4)
                    Text {
                      text: "Location"
                      color: Commons.Color.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    TextField {
                      id: locationField
                      width: parent.width
                      height: Style.spacing.controlHeight
                      verticalPadding: Math.max(2, Math.round((Style.spacing.controlHeight - font.pixelSize) / 2) - 2)
                      placeholderText: "Add location"
                      onAccepted: root.commitCreatingEvent()
                    }
                  }
                  Column {
                    id: calendarPicker
                    visible: calendarService && root.writableCalendarOptions().length > 1
                    width: Math.round((parent.width - parent.spacing) / 2)
                    spacing: Style.space(4)
                    Text {
                      text: "Calendar"
                      color: Commons.Color.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    Dropdown {
                      id: createCalendarDropdown
                      width: parent.width
                      implicitHeight: Style.spacing.controlHeight
                      rowHeight: Style.spacing.controlHeight
                      showLabel: false
                      value: root.createCalendarId
                      options: root.writableCalendarOptions()
                      foreground: Commons.Color.foreground
                      background: Commons.Color.popups.background
                      onChanged: function(value) {
                        root.createCalendarId = value
                        createCalendarDropdown.value = Qt.binding(function() { return root.createCalendarId })
                      }
                    }
                  }
                }

                Text {
                  visible: root.createError !== ""
                  width: parent.width
                   text: root.createError
                   textFormat: Text.PlainText
                  color: Commons.Color.urgent
                  wrapMode: Text.WordWrap
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                Item {
                  width: parent.width
                  height: createActions.implicitHeight
                  Row {
                    id: createActions
                    anchors.right: parent.right
                    spacing: Style.space(8)
                    Button { text: "Cancel"; onClicked: root.cancelCreatingEvent() }
                    Button { text: root.editingEvent ? "Save" : "Create"; selected: true; onClicked: root.commitCreatingEvent() }
                  }
                }
              }
            }

            Text {
              visible: !root.showingSettings && calendarService && calendarService.status === "error" && !root.compactEds
              width: parent.width
              text: calendarService ? calendarService.errorMessage : ""
              textFormat: Text.PlainText
              color: Commons.Color.urgent
              wrapMode: Text.WordWrap
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Text {
              visible: !root.showingSettings && root.edsLoading
              width: parent.width
              text: "Starting Evolution Data Server…"
              color: Commons.Color.muted
              wrapMode: Text.WordWrap
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            Column {
              visible: !root.showingSettings && root.edsStuck
              width: parent.width
              spacing: Style.space(12)
              Text {
                width: parent.width
                text: calendarService ? calendarService.errorMessage : "Couldn't start Evolution Data Server. Try Sync."
                color: Commons.Color.urgent
                wrapMode: Text.WordWrap
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }
              Button {
                text: "Sync"
                bordered: true
                onClicked: root.refresh(true)
              }
            }

            Item {
              visible: !root.showingSettings && root.needsEdsInstall
              width: parent.width
              height: Math.max(edsMissingText.implicitHeight, edsInstallActions.height)

              Column {
                id: edsMissingText
                anchors.left: parent.left
                anchors.right: edsInstallActions.left
                anchors.rightMargin: Style.space(16)
                anchors.top: edsInstallActions.top
                spacing: Style.space(4)
                Text {
                  width: parent.width
                  text: "Evolution Data Server is not installed."
                  color: Commons.Color.urgent
                  wrapMode: Text.WordWrap
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  width: parent.width
                  text: "It is required to store calendar data locally."
                  color: Commons.Color.urgent
                  wrapMode: Text.WordWrap
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Column {
                id: edsInstallActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)
                width: Math.max(edsInstallInner.implicitWidth + Style.space(32), Style.space(280))

                Rectangle {
                  id: edsInstallButton
                  width: parent.width
                  height: edsInstallInner.implicitHeight + Style.space(20)
                  radius: Style.cornerRadius
                  border.width: 1
                  border.color: edsInstallMouse.containsMouse ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.28)
                  color: edsInstallMouse.pressed ? Style.pressedFillFor(Commons.Color.foreground, Commons.Color.accent)
                    : edsInstallMouse.containsMouse ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
                    : Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent)

                  Column {
                    id: edsInstallInner
                    anchors.centerIn: parent
                    spacing: Style.space(6)
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "Click to install"
                      color: Commons.Color.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: "omarchy pkg add evolution-data-server"
                      color: Util.alpha(Commons.Color.foreground, 0.5)
                      font.family: "monospace"
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: edsInstallMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      root.close()
                      if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation omarchy pkg add evolution-data-server")
                    }
                  }
                }

                Rectangle {
                  width: parent.width
                  height: edsSourceInner.implicitHeight + Style.space(12)
                    radius: Style.cornerRadius
                    border.width: 1
                    border.color: edsSourceMouse.containsMouse ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.28)
                    color: edsSourceMouse.pressed ? Style.pressedFillFor(Commons.Color.foreground, Commons.Color.accent)
                      : edsSourceMouse.containsMouse ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
                      : "transparent"

                    Row {
                      id: edsSourceInner
                      anchors.centerIn: parent
                      spacing: Style.space(8)
                    Text {
                      text: "SOURCE"
                      color: Commons.Color.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    Text {
                      text: "↗"
                      color: Commons.Color.foreground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.body
                    }
                  }

                  MouseArea {
                    id: edsSourceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.bar) root.bar.run("xdg-open 'https://archlinux.org/packages/extra/x86_64/evolution-data-server/'")
                    }
                  }
                }
              }
            }

            Row {
              visible: !root.showingSettings && !root.compactEds
              width: parent.width
              spacing: Style.space(12)
              Item {
                width: dayPanel.visible ? parent.width - dayPanel.width - parent.spacing : parent.width
                height: root.viewMode === "month" ? monthViewRoot.height : timeGridRoot.height
                MonthView {
                  id: monthViewRoot
                  visible: root.viewMode === "month"
                  width: parent.width
                  availableHeight: root.windowMode && !root.creatingEvent ? calendarScroll.height : 0
                }
                TimeGridView {
                  id: timeGridRoot
                  visible: root.viewMode !== "month"
                  width: parent.width
                  viewportHeight: root.windowMode && !root.creatingEvent ? calendarScroll.height : 0
                }
              }
              DayPanel {
                id: dayPanel
                // A narrow window gives the whole width to the calendar.
                visible: root.showDayPanel && (!root.windowMode || parent.width >= Style.space(760))
                width: Style.space(250)
                height: parent.children[0].height
              }
            }
          }
        }
      }

      Popup {
        id: eventMenu
        padding: Style.space(4)
        modal: false
        dim: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
          color: Commons.Color.popups.background
          border.color: Commons.Color.accent
          border.width: 1
          radius: Style.cornerRadius
        }

        Column {
          spacing: Style.space(2)
          EventMenuItem {
            visible: !!(root.contextEvent && root.contextEvent.meetingUrl)
            text: "Join " + Model.meetingProviderLabel(root.contextEvent ? root.contextEvent.meetingProvider : "")
            onClicked: {
              var event = root.contextEvent
              root.closeEventMenu()
              root.joinEvent(event)
            }
          }
          EventMenuItem {
            visible: !root.eventIsReadonly(root.contextEvent)
            text: root.eventIsRecurring(root.contextEvent) ? "Edit this event" : "Edit"
            onClicked: {
              var event = root.contextEvent
              root.closeEventMenu()
              root.startEditingEvent(event, "this")
            }
          }
          EventMenuItem {
            visible: root.eventIsRecurring(root.contextEvent) && !root.eventIsReadonly(root.contextEvent)
            text: "Edit all events"
            onClicked: {
              var event = root.contextEvent
              root.closeEventMenu()
              root.startEditingEvent(event, "all")
            }
          }
          EventMenuItem {
            visible: !root.eventIsReadonly(root.contextEvent)
            text: root.eventIsRecurring(root.contextEvent) ? "Remove this event" : "Remove"
            onClicked: {
              var event = root.contextEvent
              root.closeEventMenu()
              if (calendarService) calendarService.deleteEvent(event, "this")
            }
          }
          EventMenuItem {
            visible: root.eventIsRecurring(root.contextEvent) && !root.eventIsReadonly(root.contextEvent)
            text: "Remove all events"
            onClicked: {
              var event = root.contextEvent
              root.closeEventMenu()
              if (calendarService) calendarService.deleteEvent(event, "all")
            }
          }
        }
      }
    }
  }

  component EventMenuItem: Rectangle {
    id: menuItem
    property string text: ""
    signal clicked()

    width: Math.max(Style.space(160), menuLabel.implicitWidth + Style.space(20))
    height: Style.space(28)
    radius: Style.cornerRadius
    color: menuMouse.containsMouse ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent) : "transparent"

    Text {
      id: menuLabel
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      text: menuItem.text
      color: Commons.Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: menuMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: menuItem.clicked()
    }
  }

  component WeekdayChip: Rectangle {
    id: weekdayChip
    property int day: 0
    property bool selected: false
    signal clicked()

    width: Style.space(28)
    height: Style.space(28)
    radius: width / 2
    color: mouse.pressed ? Style.pressedFillFor(Commons.Color.foreground, Commons.Color.accent)
      : selected ? Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent)
      : mouse.containsMouse ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
      : Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent)

    Text {
      anchors.centerIn: parent
      text: root.weekdayLabel(weekdayChip.day).charAt(0)
      color: weekdayChip.selected ? Style.selectedStateColor(Commons.Color.foreground, Commons.Color.accent) : Commons.Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: weekdayChip.selected
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: weekdayChip.clicked()
    }
  }

  component DatePicker: Column {
    id: datePicker
    property string label: ""
    property string value: ""
    property bool showLabel: true
    signal changed(string value)

    spacing: Style.space(4)
    width: Style.space(168)
    property date cursor: Model.dateFromKey(datePicker.value, root.today)

    Text {
      visible: datePicker.showLabel && datePicker.label !== ""
      text: datePicker.label
      color: Commons.Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Rectangle {
      width: parent.width
      height: Style.space(28)
      radius: Style.cornerRadius
      color: dateMouse.containsMouse || datePopup.visible ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent) : Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent)

      Text {
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        text: Qt.formatDate(Model.dateFromKey(datePicker.value, root.today), "ddd, MMM d")
        color: Commons.Color.foreground
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        id: dateMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: datePopup.open()
      }
    }

    Popup {
      id: datePopup
      y: datePicker.height + Style.space(2)
      width: Style.space(240)
      padding: Style.space(8)
      modal: false
      dim: false
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      onOpened: datePicker.cursor = Model.dateFromKey(datePicker.value, root.today)

      background: Rectangle {
        color: Commons.Color.popups.background
        border.color: Commons.Color.accent
        border.width: 1
        radius: Style.cornerRadius
      }

      contentItem: Column {
        spacing: Style.space(6)

        Row {
          width: parent.width
          spacing: Style.space(8)
          PanelActionButton {
            iconText: "‹"
            tooltipText: "Previous month"
            onClicked: {
              var next = Model.stepMonth(datePicker.cursor.getFullYear(), datePicker.cursor.getMonth(), -1)
              datePicker.cursor = new Date(next.year, next.month, 1)
            }
          }
          Text {
            width: Math.max(Style.space(120), parent.width - Style.space(80))
            height: parent.height
            text: Qt.formatDate(datePicker.cursor, "MMMM yyyy")
            color: Commons.Color.foreground
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          PanelActionButton {
            iconText: "›"
            tooltipText: "Next month"
            onClicked: {
              var next = Model.stepMonth(datePicker.cursor.getFullYear(), datePicker.cursor.getMonth(), 1)
              datePicker.cursor = new Date(next.year, next.month, 1)
            }
          }
        }

        Row {
          width: parent.width
          Repeater {
            model: Model.weekdayOrder(root.weekStart)
            Text {
              required property int modelData
              width: (datePopup.width - Style.space(16)) / 7
              text: root.weekdayLabel(modelData).charAt(0)
              color: Commons.Color.foreground
              horizontalAlignment: Text.AlignHCenter
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Repeater {
          model: Model.monthGrid(datePicker.cursor.getFullYear(), datePicker.cursor.getMonth(), root.weekStart, root.todayKey, {})
          Row {
            required property var modelData
            width: parent.width
            Repeater {
              model: modelData.days
              Rectangle {
                required property var modelData
                width: (datePopup.width - Style.space(16)) / 7
                height: Style.space(24)
                radius: Style.cornerRadius
                color: modelData.key === datePicker.value ? Commons.Color.accent
                  : dayMouse.containsMouse ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
                  : "transparent"
                border.width: modelData.today ? 1 : 0
                border.color: modelData.today ? Commons.Color.accent : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: modelData.day
                  color: modelData.key === datePicker.value ? Commons.Color.popups.background
                    : modelData.inMonth ? Commons.Color.foreground : Util.alpha(Commons.Color.foreground, 0.55)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: dayMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    datePicker.changed(parent.modelData.key)
                    datePopup.close()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component TimePicker: Column {
    id: timePicker
    property string label: ""
    property string value: "09:00"
    signal changed(string value)

    spacing: Style.space(4)
    readonly property var parsed: Model.parseTimeText(timePicker.value) || { hour: 9, minute: 0 }
    readonly property int hours24: parsed.hour
    readonly property int minutes: parsed.minute
    readonly property bool use12h: root.timeFormat !== "24h"

    function setTime(hour, minute) {
      var h = ((hour % 24) + 24) % 24
      var m = Math.max(0, Math.min(59, minute))
      timePicker.changed(root.pad2(h) + ":" + root.pad2(m))
    }

    Text {
      text: timePicker.label
      color: Commons.Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Row {
      spacing: Style.space(4)

      TimeSpin {
        display: timePicker.use12h ? String((timePicker.hours24 % 12) || 12) : root.pad2(timePicker.hours24)
        choices: {
          var list = []
          if (timePicker.use12h) {
            for (var h = 1; h <= 12; h++) list.push({ value: String(h), label: String(h) })
          } else {
            for (var h24 = 0; h24 <= 23; h24++) list.push({ value: String(h24), label: root.pad2(h24) })
          }
          return list
        }
        onAdjust: function(delta) { timePicker.setTime(timePicker.hours24 + delta, timePicker.minutes) }
        onTyped: function(number) {
          if (timePicker.use12h) {
            var hour12 = Math.max(1, Math.min(12, number))
            var pm = timePicker.hours24 >= 12
            timePicker.setTime((hour12 % 12) + (pm ? 12 : 0), timePicker.minutes)
          } else {
            timePicker.setTime(Math.max(0, Math.min(23, number)), timePicker.minutes)
          }
        }
        onPicked: function(choice) {
          var number = parseInt(choice, 10)
          if (timePicker.use12h) {
            var pm = timePicker.hours24 >= 12
            timePicker.setTime((number % 12) + (pm ? 12 : 0), timePicker.minutes)
          } else {
            timePicker.setTime(number, timePicker.minutes)
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ":"
        color: Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      TimeSpin {
        display: root.pad2(timePicker.minutes)
        choices: {
          var list = []
          for (var m = 0; m < 60; m++) list.push({ value: String(m), label: root.pad2(m) })
          return list
        }
        onAdjust: function(delta) {
          var next = timePicker.minutes + delta
          var hour = timePicker.hours24
          if (next > 59) { next = 0; hour = (hour + 1) % 24 }
          if (next < 0) { next = 59; hour = (hour + 23) % 24 }
          timePicker.setTime(hour, next)
        }
        onTyped: function(number) { timePicker.setTime(timePicker.hours24, Math.max(0, Math.min(59, number))) }
        onPicked: function(choice) { timePicker.setTime(timePicker.hours24, parseInt(choice, 10)) }
      }

      TimeSpin {
        visible: timePicker.use12h
        display: timePicker.hours24 >= 12 ? "PM" : "AM"
        choices: [{ value: "AM", label: "AM" }, { value: "PM", label: "PM" }]
        onAdjust: function() { timePicker.setTime((timePicker.hours24 + 12) % 24, timePicker.minutes) }
        onTyped: function() {}
        onPicked: function(choice) {
          var pm = choice === "PM"
          var hour = timePicker.hours24 % 12
          timePicker.setTime(hour + (pm ? 12 : 0), timePicker.minutes)
        }
      }
    }
  }

  component TimeSpin: Rectangle {
    id: spin
    property string display: ""
    property var choices: []
    signal adjust(int delta)
    signal typed(int number)
    signal picked(string value)

    width: Math.max(Style.space(32), spinLabel.implicitWidth + Style.space(12))
    height: Style.space(28)
    radius: Style.cornerRadius
    color: spinMouse.containsMouse || spin.activeFocus ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent) : Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent)
    border.width: spin.activeFocus ? 1 : 0
    border.color: Commons.Color.accent
    property string typeBuffer: ""

    function currentChoiceIndex() {
      var list = spin.choices || []
      var current = String(spin.display)
      for (var i = 0; i < list.length; i++) {
        if (String(list[i].label) === current || String(list[i].value) === current) return i
      }
      return 0
    }

    Text {
      id: spinLabel
      anchors.centerIn: parent
      text: spin.display
      color: Commons.Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
    }

    MouseArea {
      id: spinMouse
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        spin.forceActiveFocus()
        spin.typeBuffer = ""
        spinPopup.open()
      }
      onWheel: function(wheel) {
        spin.adjust(wheel.angleDelta.y > 0 ? 1 : -1)
        wheel.accepted = true
      }
    }

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Up) { spin.adjust(1); event.accepted = true }
      else if (event.key === Qt.Key_Down) { spin.adjust(-1); event.accepted = true }
      else if (event.text >= "0" && event.text <= "9") {
        spin.typeBuffer += event.text
        spin.typed(parseInt(spin.typeBuffer, 10))
        if (spin.typeBuffer.length >= 2) spin.typeBuffer = ""
        event.accepted = true
      } else if (event.key === Qt.Key_Escape) {
        spinPopup.close()
        event.accepted = true
      }
    }

    Popup {
      id: spinPopup
      y: spin.height + Style.space(2)
      width: Math.max(spin.width, Style.space(48))
      implicitHeight: Math.min(spin.choices.length * Style.space(24), Style.space(24) * 8)
      padding: Style.space(2)
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      onOpened: {
        var index = spin.currentChoiceIndex()
        Qt.callLater(function() { spinList.positionViewAtIndex(index, ListView.Center) })
      }

      background: Rectangle {
        color: Commons.Color.popups.background
        border.color: Commons.Color.accent
        border.width: 1
        radius: Style.cornerRadius
      }

      contentItem: ListView {
        id: spinList
        clip: true
        model: spin.choices
        boundsBehavior: Flickable.StopAtBounds
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: spinList.width
          height: Style.space(24)
          color: String(modelData.label) === String(spin.display) || String(modelData.value) === String(spin.display)
            ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
            : (choiceMouse.containsMouse ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent) : "transparent")
          Text {
            anchors.centerIn: parent
            text: modelData.label
            color: Commons.Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          MouseArea {
            id: choiceMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              spin.picked(String(modelData.value))
              spinPopup.close()
            }
          }
        }
      }
    }
  }

  component SettingsPage: Rectangle {
    id: settingsPage
    height: settingsColumn.implicitHeight + Style.space(20)
    radius: Style.cornerRadius
    color: Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
    border.color: Commons.Color.accent
    border.width: 1

    Column {
      id: settingsColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(10)
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: Math.max(0, parent.width - closeSettingsButton.implicitWidth - parent.spacing)
          text: "CalDav Calendar settings"
          color: Commons.Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
          verticalAlignment: Text.AlignVCenter
        }
        Button { id: closeSettingsButton; text: "Close"; bordered: true; onClicked: root.cancelSettings() }
      }

      SettingsSection {
        title: "Display"
        SettingsChoiceRow {
          label: "Time format"
          hint: "How times are shown in events and the grid."
          value: root.draftTimeFormat
          options: [{ value: "12h", label: "AM/PM" }, { value: "24h", label: "24-hour" }]
          onChanged: function(value) { root.draftTimeFormat = value }
        }
        SettingsChoiceRow {
          label: "Default view"
          hint: "Which calendar view opens first."
          value: root.draftDefaultView
          options: [{ value: "month", label: "Month" }, { value: "week", label: "Week" }, { value: "work-week", label: "Work week" }, { value: "day", label: "Day" }]
          onChanged: function(value) { root.draftDefaultView = value }
        }
        SettingsChoiceRow {
          label: "Week starts"
          hint: "First day shown in week and month grids."
          value: root.draftWeekStartDay
          options: [{ value: "0", label: "Sunday" }, { value: "1", label: "Monday" }]
          onChanged: function(value) { root.draftWeekStartDay = value }
        }
        SettingsChoiceRow {
          label: "Week numbers"
          hint: "ISO week numbers in month view."
          value: root.draftShowWeekNumbers ? "on" : "off"
          options: [{ value: "on", label: "Show" }, { value: "off", label: "Hide" }]
          onChanged: function(value) { root.draftShowWeekNumbers = value === "on" }
        }
        SettingsDropdownRow {
          label: "Default calendar"
          hint: "Automatic uses the first writable calendar."
          value: root.draftDefaultCalendarId
          options: root.writableCalendarChoices()
          onChanged: function(value) { root.draftDefaultCalendarId = String(value || "") }
        }
        SettingsChoiceRow {
          label: "Remind me"
          hint: "Desktop notification before timed events. Click a meeting toast to join."
          value: root.draftReminderMinutes
          options: [
            { value: "0", label: "Off" },
            { value: "5", label: "5 minutes before" },
            { value: "10", label: "10 minutes before" },
            { value: "15", label: "15 minutes before" },
            { value: "30", label: "30 minutes before" }
          ]
          onChanged: function(value) { root.draftReminderMinutes = String(value || "10") }
        }
      }

      SettingsSection {
        title: "Visible hours"
        SettingsRangeRow {
          label: "Week"
          hint: "Hour range shown in week and work week views."
          startValue: String(root.draftCustomWeekStartHour)
          endValue: String(root.draftCustomWeekEndHour)
          onStartChanged: function(value) { root.draftCustomWeekStartHour = parseInt(value, 10) }
          onEndChanged: function(value) { root.draftCustomWeekEndHour = parseInt(value, 10) }
        }
        SettingsRangeRow {
          label: "Day"
          hint: "Hour range shown in day view."
          startValue: String(root.draftCustomDayStartHour)
          endValue: String(root.draftCustomDayEndHour)
          onStartChanged: function(value) { root.draftCustomDayStartHour = parseInt(value, 10) }
          onEndChanged: function(value) { root.draftCustomDayEndHour = parseInt(value, 10) }
        }
      }

      SettingsSection {
        title: "Calendars"
        statusText: calendarService && calendarService.pendingRemoveId ? "Removing…" : (calendarService && calendarService.removeError ? calendarService.removeError : (calendarService && calendarService.syncing ? "Syncing" : ""))
        Text {
          width: parent.width
          text: "Switch a calendar off to hide its events here. Hidden calendars keep syncing. Click a colour dot to change its colour."
          color: Commons.Color.muted
          wrapMode: Text.WordWrap
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
        Repeater {
          model: calendarService ? Model.calendarGroups(calendarService.calendars, root.calendarNames) : []
          SettingsCalendarGroup {
            required property var modelData
            group: modelData
          }
        }

        Button {
          visible: !root.showingSetup
          text: "Add calendar"
          bordered: true
          onClicked: root.startSetup()
        }

        Column {
          visible: root.showingSetup
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: "Add calendar"
            color: Commons.Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Button { text: "CalDAV"; bordered: true; selected: root.setupKind === "caldav"; onClicked: root.setupKind = "caldav" }
            Button { text: "iCalendar"; bordered: true; selected: root.setupKind === "webcal"; onClicked: root.setupKind = "webcal" }
            Button { text: "On this computer"; bordered: true; selected: root.setupKind === "local"; onClicked: root.setupKind = "local" }
          }
          Text {
            width: parent.width
            text: root.setupKind === "local"
              ? "Creates a calendar that stays on this computer."
              : (root.setupKind === "webcal"
                ? "Subscribes to a read-only iCalendar feed."
                : "iCloud, Nextcloud, Fastmail, and other CalDAV servers.")
            color: Commons.Color.foreground
            wrapMode: Text.WordWrap
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
          TextField {
            width: parent.width
            text: root.setupName
            placeholderText: "Display name"
            onTextChanged: root.setupName = text
            onAccepted: root.commitSetup()
          }
          TextField {
            visible: root.setupKind === "caldav" || root.setupKind === "webcal"
            width: parent.width
            text: root.setupUrl
            placeholderText: root.setupKind === "webcal" ? "iCalendar URL" : "CalDAV URL"
            onTextChanged: root.setupUrl = text
            onAccepted: root.commitSetup()
          }
          TextField {
            visible: root.setupKind === "caldav"
            width: parent.width
            text: root.setupUser
            placeholderText: "Username / email"
            onTextChanged: root.setupUser = text
            onAccepted: root.commitSetup()
          }
          TextField {
            visible: root.setupKind === "caldav"
            width: parent.width
            text: root.setupPassword
            placeholderText: "Password or app-specific password"
            password: true
            onTextChanged: root.setupPassword = text
            onAccepted: root.commitSetup()
          }
          Text {
            visible: root.setupError !== "" || (calendarService && calendarService.setupStatus !== "")
            width: parent.width
            text: root.setupError || (calendarService ? calendarService.setupStatus : "")
            textFormat: Text.PlainText
            color: root.setupError !== "" ? Commons.Color.urgent : Commons.Color.accent
            wrapMode: Text.WordWrap
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Row {
            spacing: Style.space(8)
            Button {
              text: root.setupKind === "local" ? "Create calendar" : (root.setupKind === "webcal" ? "Add subscription" : "Add CalDAV source")
              onClicked: root.commitSetup()
            }
            Button { text: "Cancel"; bordered: true; onClicked: root.cancelSetup() }
          }
        }
      }

      Text {
        visible: root.settingsError !== ""
        width: parent.width
        text: root.settingsError
        textFormat: Text.PlainText
        color: Commons.Color.urgent
        wrapMode: Text.WordWrap
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        width: parent.width
        spacing: Style.space(8)
        height: Math.max(restoreDefaultsLabel.implicitHeight, saveSettingsButton.implicitHeight)

        Text {
          id: restoreDefaultsLabel
          anchors.verticalCenter: parent.verticalCenter
          text: "Restore defaults"
          color: restoreDefaultsMouse.containsMouse ? Commons.Color.accent : Commons.Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.underline: true
          MouseArea {
            id: restoreDefaultsMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.restoreSettingsDefaults()
          }
        }
        Item { width: Math.max(0, parent.width - restoreDefaultsLabel.implicitWidth - saveSettingsButton.implicitWidth - parent.spacing * 2); height: 1 }
        Button { id: saveSettingsButton; anchors.verticalCenter: parent.verticalCenter; text: "Save"; selected: true; bordered: true; onClicked: root.saveSettings() }
      }
    }
  }

  component SettingsSection: Column {
    id: settingsSection
    property string title: ""
    property string statusText: ""
    default property alias content: body.children

    width: parent ? parent.width : 0
    spacing: Style.space(10)

    Column {
      width: parent.width
      spacing: Style.space(4)

      Row {
        spacing: Style.space(8)
        Text {
          text: settingsSection.title
          color: Commons.Color.accent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          visible: settingsSection.statusText !== ""
          text: settingsSection.statusText
          color: Commons.Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
      Rectangle {
        width: parent.width
        height: 1
        color: Commons.Color.accent
      }
    }
    Column {
      id: body
      width: parent.width
      spacing: Style.space(6)
    }
  }

  // Header menu: every calendar by account, ticked when shown. Changes apply
  // at once, unlike the settings page.
  component CalendarsMenu: Popup {
    id: calendarsMenuPopup
    margins: Style.space(8)
    padding: Style.space(10)
    modal: false
    dim: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    width: Style.space(320)
    height: Math.min(menuColumn.implicitHeight + padding * 2, Style.space(560))
    background: Rectangle {
      color: Commons.Color.popups.background
      border.color: Commons.Color.accent
      border.width: 1
      radius: Style.cornerRadius
    }
    contentItem: Flickable {
      contentWidth: width
      contentHeight: menuColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: menuColumn
        width: parent.width
        spacing: Style.space(2)

        Repeater {
          model: calendarService && calendarsMenuPopup.opened ? Model.calendarGroups(calendarService.calendars, root.calendarNames) : []
          Column {
            id: menuGroup
            required property var modelData
            readonly property bool allShown: {
              for (var i = 0; i < modelData.calendars.length; i++)
                if (Model.calendarHidden(root.hiddenCalendars, modelData.calendars[i].calendar.id)) return false
              return true
            }
            width: menuColumn.width
            spacing: Style.space(2)

            Item {
              width: parent.width
              height: Style.space(28)
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: menuGroup.modelData.label
                color: Commons.Color.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: menuGroup.allShown ? "Hide all" : "Show all"
                color: groupToggleMouse.containsMouse ? Commons.Color.accent : Commons.Color.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                MouseArea {
                  id: groupToggleMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setGroupHidden(menuGroup.modelData, menuGroup.allShown)
                }
              }
            }

            Repeater {
              model: menuGroup.modelData.calendars
              Rectangle {
                id: menuRow
                required property var modelData
                readonly property bool shown: !Model.calendarHidden(root.hiddenCalendars, modelData.calendar.id)
                width: menuGroup.width
                height: Style.space(28)
                radius: Style.cornerRadius
                color: menuRowMouse.containsMouse ? Util.alpha(Commons.Color.foreground, 0.08) : "transparent"

                Rectangle {
                  id: menuCheck
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(16)
                  height: Style.space(16)
                  radius: Math.min(Style.cornerRadius, Style.space(4))
                  color: menuRow.shown ? Model.calendarDisplayColor(menuRow.modelData.calendar, root.calendarColors, menuRow.modelData.index) : "transparent"
                  border.width: 2
                  border.color: Model.calendarDisplayColor(menuRow.modelData.calendar, root.calendarColors, menuRow.modelData.index)
                  Text {
                    anchors.centerIn: parent
                    visible: menuRow.shown
                    text: "✓"
                    color: Model.colorLuminance(parent.color) > 0.55 ? "#000000" : "#ffffff"
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
                Text {
                  anchors.left: menuCheck.right
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: menuRow.modelData.name
                  elide: Text.ElideRight
                  color: menuRow.shown ? Commons.Color.foreground : Commons.Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                MouseArea {
                  id: menuRowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setCalendarHidden(menuRow.modelData.calendar.id, menuRow.shown)
                }
              }
            }
          }
        }
      }
    }
  }

  // One account (iCloud, Google, this computer) in the settings page.
  component SettingsCalendarGroup: Column {
    id: settingsCalendarGroup
    property var group: ({ label: "", calendars: [] })
    readonly property int shownCount: {
      var count = 0
      for (var i = 0; i < group.calendars.length; i++)
        if (!Model.calendarHidden(root.draftHiddenCalendars, group.calendars[i].calendar.id)) count++
      return count
    }
    width: parent ? parent.width : 0
    spacing: Style.space(4)

    Item {
      width: parent.width
      height: Style.spacing.controlHeight
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: settingsCalendarGroup.group.label + "  ·  " + settingsCalendarGroup.shownCount + " of " + settingsCalendarGroup.group.calendars.length + " shown"
        color: Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        Button { text: "Show all"; enabled: settingsCalendarGroup.shownCount < settingsCalendarGroup.group.calendars.length; onClicked: root.setDraftGroupHidden(settingsCalendarGroup.group, false) }
        Button { text: "Hide all"; enabled: settingsCalendarGroup.shownCount > 0; onClicked: root.setDraftGroupHidden(settingsCalendarGroup.group, true) }
      }
    }

    Repeater {
      model: settingsCalendarGroup.group.calendars
      SettingsCalendarRow {
        required property var modelData
        calendar: modelData.calendar
        calendarIndex: modelData.index
      }
    }
  }

  // Fixed columns so every row lines up: show/hide, colour, name, note, menu.
  // Remove sits behind the menu and asks first, so it can't be hit by
  // misreading which row a button belongs to.
  component SettingsCalendarRow: Rectangle {
    id: settingsCalendarRow
    property var calendar: ({})
    property int calendarIndex: 0
    width: parent ? parent.width : 0
    height: Style.spacing.controlHeight + Style.space(6)
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Util.alpha(Commons.Color.foreground, 0.06) : "transparent"
    readonly property string calendarId: calendar && calendar.id ? calendar.id : ""
    readonly property string currentName: Model.calendarDisplayName(calendar, root.draftCalendarNames)
    readonly property string currentColor: Model.calendarDisplayColor(calendar, root.draftCalendarColors, calendarIndex)
    readonly property bool removable: Model.canRemoveCalendar(calendar)
    readonly property bool shown: !Model.calendarHidden(root.draftHiddenCalendars, calendarId)

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    ToggleSwitch {
      id: shownSwitch
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      cursorRing: false
      checked: settingsCalendarRow.shown
      onToggled: root.setDraftCalendarHidden(settingsCalendarRow.calendarId, settingsCalendarRow.shown)
    }

    Rectangle {
      id: swatch
      anchors.left: shownSwitch.right
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22)
      height: Style.space(22)
      radius: width / 2
      color: settingsCalendarRow.currentColor || Commons.Color.accent
      opacity: settingsCalendarRow.shown ? 1 : 0.4
      border.width: 2
      border.color: Commons.Color.foreground
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: colorPopup.open()
      }
      CalendarColorPopup {
        id: colorPopup
        objectName: "colorPopup"
        y: parent.height + Style.space(4)
        currentColor: settingsCalendarRow.currentColor
        onPicked: function(color) { root.setDraftCalendarColor(settingsCalendarRow.calendarId, color) }
      }
    }

    TextField {
      id: nameField
      anchors.left: swatch.right
      anchors.leftMargin: Style.space(12)
      anchors.right: noteText.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      height: Style.spacing.controlHeight
      verticalPadding: Math.max(2, Math.round((Style.spacing.controlHeight - font.pixelSize) / 2) - 2)
      opacity: settingsCalendarRow.shown ? 1 : 0.55
      text: settingsCalendarRow.currentName
      placeholderText: "Calendar name"
      onEditingFinished: root.setDraftCalendarName(settingsCalendarRow.calendarId, text)
    }

    Text {
      id: noteText
      anchors.right: menuButton.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(80)
      horizontalAlignment: Text.AlignRight
      text: settingsCalendarRow.calendar && settingsCalendarRow.calendar.readonly ? "read-only" : ""
      color: Commons.Color.muted
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }

    PanelActionButton {
      id: menuButton
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      opacity: settingsCalendarRow.removable ? 1 : 0
      enabled: settingsCalendarRow.removable && (!calendarService || !calendarService.pendingRemoveId)
      iconText: "⋯"
      tooltipText: "More"
      onClicked: rowMenu.open()

      Popup {
        id: rowMenu
        margins: Style.space(8)
        x: parent.width - width
        y: parent.height + Style.space(4)
        padding: Style.space(6)
        modal: false
        dim: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
          color: Commons.Color.popups.background
          border.color: Commons.Color.accent
          border.width: 1
          radius: Style.cornerRadius
        }
        contentItem: Button {
          text: "Remove from this computer…"
          foreground: Commons.Color.urgent
          onClicked: {
            rowMenu.close()
            root.askRemoveCalendar(settingsCalendarRow.calendar, settingsCalendarRow.currentName)
          }
        }
      }
    }
  }

  // Colour picker: a saturation/brightness square with a hue strip, presets,
  // theme colours and a hex field. Picking applies to the draft.
  component CalendarColorPopup: Popup {
    id: calendarColorPopup
    property string currentColor: ""
    property real hue: 0
    property real sat: 0
    property real val: 1
    readonly property color chosen: Qt.hsva(hue, sat, val, 1)
    readonly property string chosenHex: Model.normalizeColor(String(chosen))
    property bool editingHex: false
    signal picked(string color)

    // Keep the whole popup inside the window: near the bottom of the list it
    // moves up instead of being cut off.
    margins: Style.space(8)
    padding: Style.space(12)
    modal: false
    dim: false
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpened: loadColor(currentColor)
    onChosenHexChanged: if (!editingHex) hexField.text = chosenHex

    function loadColor(text) {
      var hex = Model.hexColorInput(text)
      if (!hex) return
      var c = Qt.color(hex)
      if (c.hsvHue >= 0) hue = c.hsvHue
      sat = c.hsvSaturation
      val = c.hsvValue
      hexField.text = hex
    }

    function choose(color) {
      picked(color)
      close()
    }

    background: Rectangle {
      color: Commons.Color.popups.background
      border.color: Commons.Color.accent
      border.width: 1
      radius: Style.cornerRadius
    }

    contentItem: Column {
      spacing: Style.space(10)
      width: Style.space(300)

      Row {
        spacing: Style.space(10)

        // Saturation runs left to right, brightness top to bottom.
        Item {
          id: svSquare
          width: Style.space(250)
          height: Style.space(160)

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: Qt.hsva(calendarColorPopup.hue, 1, 1, 1)
          }
          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "#ffffffff" }
              GradientStop { position: 1; color: "#00ffffff" }
            }
          }
          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            gradient: Gradient {
              GradientStop { position: 0; color: "#00000000" }
              GradientStop { position: 1; color: "#ff000000" }
            }
          }
          Rectangle {
            width: Style.space(14)
            height: width
            radius: width / 2
            x: calendarColorPopup.sat * svSquare.width - width / 2
            y: (1 - calendarColorPopup.val) * svSquare.height - height / 2
            color: calendarColorPopup.chosen
            border.width: 2
            border.color: calendarColorPopup.val > 0.55 ? "#000000" : "#ffffff"
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.CrossCursor
            function pick(mouse) {
              calendarColorPopup.editingHex = false
              calendarColorPopup.sat = Math.max(0, Math.min(1, mouse.x / width))
              calendarColorPopup.val = Math.max(0, Math.min(1, 1 - mouse.y / height))
            }
            onPressed: function(mouse) { pick(mouse) }
            onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
          }
        }

        Item {
          id: hueStrip
          width: Style.space(22)
          height: svSquare.height

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            gradient: Gradient {
              GradientStop { position: 0.0; color: "#ff0000" }
              GradientStop { position: 0.167; color: "#ffff00" }
              GradientStop { position: 0.333; color: "#00ff00" }
              GradientStop { position: 0.5; color: "#00ffff" }
              GradientStop { position: 0.667; color: "#0000ff" }
              GradientStop { position: 0.833; color: "#ff00ff" }
              GradientStop { position: 1.0; color: "#ff0000" }
            }
          }
          Rectangle {
            x: -Style.space(2)
            width: parent.width + Style.space(4)
            height: Style.space(6)
            radius: height / 2
            y: calendarColorPopup.hue * hueStrip.height - height / 2
            color: "transparent"
            border.width: 2
            border.color: Commons.Color.foreground
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            function pick(mouse) {
              calendarColorPopup.editingHex = false
              calendarColorPopup.hue = Math.max(0, Math.min(0.999, mouse.y / height))
            }
            onPressed: function(mouse) { pick(mouse) }
            onPositionChanged: function(mouse) { if (pressed) pick(mouse) }
          }
        }
      }

      Row {
        spacing: Style.space(8)
        Rectangle {
          width: Style.space(34)
          height: Style.spacing.controlHeight
          radius: Style.cornerRadius
          anchors.verticalCenter: parent.verticalCenter
          color: calendarColorPopup.chosen
          border.width: 1
          border.color: Util.alpha(Commons.Color.foreground, 0.35)
        }
        TextField {
          id: hexField
          width: Style.space(130)
          placeholderText: "#rrggbb"
          onTextEdited: {
            var hex = Model.hexColorInput(text)
            if (!hex) return
            calendarColorPopup.editingHex = true
            calendarColorPopup.loadColor(hex)
            calendarColorPopup.editingHex = false
          }
          onAccepted: useButton.clicked()
        }
        Button {
          id: useButton
          text: "Use colour"
          bordered: true
          selected: true
          onClicked: calendarColorPopup.choose(calendarColorPopup.chosenHex)
        }
      }

      Repeater {
        model: [
          { label: "Presets", colors: root.calendarColorPalette },
          { label: "Theme", colors: root.uniqueThemeColors() }
        ]
        Column {
          required property var modelData
          spacing: Style.space(4)
          Text {
            text: modelData.label
            color: Commons.Color.muted
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
          Flow {
            width: Style.space(300)
            spacing: Style.space(5)
            Repeater {
              model: modelData.colors
              Rectangle {
                required property var modelData
                readonly property bool current: Model.colorsMatch(modelData, calendarColorPopup.chosenHex)
                width: Style.space(20)
                height: Style.space(20)
                radius: width / 2
                color: modelData
                border.width: current ? 2 : 1
                border.color: current ? Commons.Color.foreground : Util.alpha(Commons.Color.foreground, 0.35)
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  // One click previews in the picker, a double click uses it.
                  onClicked: calendarColorPopup.loadColor(parent.modelData)
                  onDoubleClicked: calendarColorPopup.choose(Model.normalizeColor(parent.modelData))
                }
              }
            }
          }
        }
      }
    }
  }

  component SettingsHintLabel: Text {
    id: hintLabel
    property string hint: ""

    color: Commons.Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.bold: true

    MouseArea {
      id: hintMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: hintLabel.hint !== ""
    }
    PanelToolTip {
      visible: hintMouse.containsMouse && hintLabel.hint !== ""
      text: hintLabel.hint
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    }
  }

  component SettingsChoiceRow: Item {
    id: settingsChoiceRow
    property string label: ""
    property string hint: ""
    property string value: ""
    property var options: []
    signal changed(string value)

    width: parent ? parent.width : 0
    height: Math.max(choiceLabel.implicitHeight, choiceButtons.implicitHeight)

    SettingsHintLabel {
      id: choiceLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: settingsChoiceRow.label
      hint: settingsChoiceRow.hint
    }
    Row {
      id: choiceButtons
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      Repeater {
        model: settingsChoiceRow.options
        Button {
          required property var modelData
          text: modelData.label
          selected: String(modelData.value) === settingsChoiceRow.value
          onClicked: settingsChoiceRow.changed(String(modelData.value))
        }
      }
    }
  }

  component SettingsDropdownRow: Item {
    id: settingsDropdownRow
    property string label: ""
    property string hint: ""
    property string value: ""
    property var options: []
    signal changed(string value)

    width: parent ? parent.width : 0
    height: Math.max(dropdownLabel.implicitHeight, Style.spacing.controlHeight)

    SettingsHintLabel {
      id: dropdownLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: settingsDropdownRow.label
      hint: settingsDropdownRow.hint
    }
    Dropdown {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(240)
      height: Style.spacing.controlHeight
      showLabel: false
      value: settingsDropdownRow.value
      options: settingsDropdownRow.options
      foreground: Commons.Color.foreground
      background: Commons.Color.popups.background
      onChanged: function(value) { settingsDropdownRow.changed(value) }
    }
  }

  component SettingsRangeRow: Item {
    id: settingsRangeRow
    property string label: ""
    property string hint: ""
    property string startValue: ""
    property string endValue: ""
    signal startChanged(string value)
    signal endChanged(string value)

    width: parent ? parent.width : 0
    height: Math.max(rangeLabel.implicitHeight, Style.spacing.controlHeight)

    SettingsHintLabel {
      id: rangeLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: settingsRangeRow.label
      hint: settingsRangeRow.hint
    }
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)
      Dropdown {
        width: Style.space(140)
        height: Style.spacing.controlHeight
        showLabel: false
        value: settingsRangeRow.startValue
        options: root.hourChoices(false, root.draftTimeFormat)
        foreground: Commons.Color.foreground
        background: Commons.Color.popups.background
        onChanged: function(value) { settingsRangeRow.startChanged(value) }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "–"
        color: Commons.Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
      }
      Dropdown {
        width: Style.space(140)
        height: Style.spacing.controlHeight
        showLabel: false
        value: settingsRangeRow.endValue
        options: root.hourChoices(true, root.draftTimeFormat)
        foreground: Commons.Color.foreground
        background: Commons.Color.popups.background
        onChanged: function(value) { settingsRangeRow.endChanged(value) }
      }
    }
  }

  component ViewButton: Rectangle {
    id: viewButton
    property string text: ""
    property bool selected: false

    signal clicked()
    signal doubleClicked()

    implicitWidth: label.implicitWidth + Style.spacing.controlPaddingX * 2 + Style.space(2)
    implicitHeight: label.implicitHeight + Style.spacing.controlPaddingY * 2 + Style.space(2)
    radius: Style.cornerRadius
    color: mouse.pressed ? Style.pressedFillFor(Commons.Color.foreground, Commons.Color.accent)
      : mouse.containsMouse ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
      : selected ? Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent)
      : "transparent"

    Text {
      id: label
      anchors.centerIn: parent
      text: viewButton.text
      color: viewButton.selected ? Style.selectedStateColor(Commons.Color.foreground, Commons.Color.accent) : Commons.Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      font.bold: viewButton.selected
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: viewButton.clicked()
      onDoubleClicked: viewButton.doubleClicked()
    }
  }

  component MonthView: Column {
    id: monthView
    spacing: Style.space(4)
    // Height the month may fill in the window (0 in the popup, which keeps
    // fixed rows). Taller rows show more events before "+N more".
    property real availableHeight: 0
    readonly property int rowCount: Math.max(1, root.weeks.length)
    readonly property real cellHeight: availableHeight > 0
      ? Math.max(Style.space(80), Math.floor((availableHeight - weekdayHeader.height - spacing * rowCount) / rowCount))
      : Style.space(80)
    readonly property int previewLimit: Math.max(2, Math.floor((cellHeight - Style.space(8) - Style.space(18) - Style.space(16)) / Style.space(16)))
    onPreviewLimitChanged: root.monthPreviewLimit = previewLimit
    Component.onCompleted: root.monthPreviewLimit = previewLimit
    readonly property int weekNumberWidth: root.showWeekNumbers ? Style.space(32) : 0
    readonly property int weekNumberGap: root.showWeekNumbers ? Style.space(4) : 0

    Row {
      id: weekdayHeader
      spacing: Style.space(4)
      Text { visible: root.showWeekNumbers; width: monthView.weekNumberWidth; text: "W"; color: Commons.Color.foreground; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Style.font.bodySmall }
      Repeater {
        model: Model.weekdayOrder(root.weekStart)
        Text {
          required property int modelData
          width: (monthView.width - monthView.weekNumberWidth - monthView.weekNumberGap - Style.space(24)) / 7
          text: root.weekdayLabel(modelData)
          color: Commons.Color.foreground
          horizontalAlignment: Text.AlignHCenter
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    Repeater {
      model: root.weeks
      Row {
        required property var modelData
        spacing: Style.space(4)
        Text {
          visible: root.showWeekNumbers
          width: monthView.weekNumberWidth
          height: monthView.cellHeight
          text: modelData.week
          color: Commons.Color.foreground
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignHCenter
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        Repeater {
          model: modelData.days
          Rectangle {
            id: monthDay
            required property var modelData
            width: (monthView.width - monthView.weekNumberWidth - monthView.weekNumberGap - Style.space(24)) / 7
            height: monthView.cellHeight
            radius: Style.cornerRadius
            color: modelData.key === root.selectedKey ? Util.alpha(Commons.Color.accent, 0.22) : Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent)
            border.color: modelData.key === root.selectedKey ? Commons.Color.accent : "transparent"
            border.width: modelData.key === root.selectedKey ? 1 : 0

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                if (eventMenu.opened) {
                  root.closeEventMenu()
                  return
                }
                root.selectedKey = monthDay.modelData.key
                if (mouse.button === Qt.RightButton) root.startCreatingEvent()
              }
              onDoubleClicked: {
                root.selectedKey = monthDay.modelData.key
                root.setView("day")
              }
            }

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(4)
              spacing: Style.space(2)

              Item {
                width: parent.width
                height: Style.space(18)
                Rectangle {
                  visible: monthDay.modelData.today
                  width: Style.space(18)
                  height: Style.space(18)
                  radius: width / 2
                  color: Commons.Color.accent
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  x: monthDay.modelData.today ? 0 : 0
                  width: monthDay.modelData.today ? Style.space(18) : implicitWidth
                  horizontalAlignment: monthDay.modelData.today ? Text.AlignHCenter : Text.AlignLeft
                  text: monthDay.modelData.day
                  color: monthDay.modelData.today ? Commons.Color.popups.background : (monthDay.modelData.inMonth ? Commons.Color.foreground : Util.alpha(Commons.Color.foreground, 0.55))
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: monthDay.modelData.today || monthDay.modelData.key === root.selectedKey
                }
              }

              Repeater {
                model: monthDay.modelData.previews
                EventCard {
                  required property var modelData
                  width: parent.width
                  height: Style.space(14)
                  mode: "chip"
                  dimmed: !monthDay.modelData.inMonth
                  event: modelData
                  onClicked: function(mouse) {
                    root.selectedKey = monthDay.modelData.key
                    root.handleEventClick(event, mouse, this)
                  }
                }
              }

              Text {
                visible: monthDay.modelData.extra > 0
                width: parent.width
                text: "+" + monthDay.modelData.extra + (width < Style.space(70) ? "" : " more")
                elide: Text.ElideRight
                color: monthDay.modelData.inMonth ? Commons.Color.foreground : Util.alpha(Commons.Color.foreground, 0.55)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Math.max(9, Style.font.caption - 1)
              }
            }
          }
        }
      }
    }

  }

  // The selected day: all-day entries on top, then the day's hours drawn to
  // scale, so the gaps between meetings are as visible as the meetings.
  component DayPanel: Rectangle {
    id: dayPanelRoot
    radius: Style.cornerRadius
    color: Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent)

    readonly property var allDayEvents: root.selectedEvents.filter(function(event) { return event && event.allDay === true })
    readonly property var hours: Model.timelineHours(root.eventGroups, root.selectedKey, 8, 18)
    readonly property var segments: Model.layoutTimedEvents(root.eventGroups, root.selectedKey, hours.start, hours.end)

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(8)

      Text {
        id: dayPanelTitle
        width: parent.width
        text: Qt.formatDate(Model.dateFromKey(root.selectedKey, root.today), "dddd, MMM d")
        color: Commons.Color.foreground
        elide: Text.ElideRight
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Flickable {
        id: allDayScroll
        visible: dayPanelRoot.allDayEvents.length > 0
        width: parent.width
        height: visible ? Math.min(allDayList.height, Math.round(dayPanelRoot.height * 0.3)) : 0
        contentWidth: width
        contentHeight: allDayList.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        EventList {
          id: allDayList
          width: parent.width
          events: dayPanelRoot.allDayEvents
          emptyText: ""
        }
      }

      Item {
        id: dayTimeline
        width: parent.width
        height: Math.max(Style.space(120), parent.height - dayPanelTitle.height - parent.spacing - (allDayScroll.visible ? allDayScroll.height + parent.spacing : 0))
        readonly property int hourCount: dayPanelRoot.hours.end - dayPanelRoot.hours.start
        readonly property real hourHeight: height / Math.max(1, hourCount)
        // Label every hour when there's room, otherwise every second hour.
        readonly property int labelStep: hourHeight >= Style.space(22) ? 1 : 2
        readonly property real labelWidth: Style.space(48)

        function yForHour(hour) {
          return (hour - dayPanelRoot.hours.start) * hourHeight
        }

        Repeater {
          model: dayTimeline.hourCount + 1
          Item {
            required property int index
            readonly property int hour: dayPanelRoot.hours.start + index
            y: dayTimeline.yForHour(hour)
            width: dayTimeline.width
            height: 1

            Rectangle {
              x: dayTimeline.labelWidth
              width: parent.width - dayTimeline.labelWidth
              height: 1
              color: Util.alpha(Commons.Color.muted, 0.35)
            }
            Text {
              visible: parent.index % dayTimeline.labelStep === 0 && parent.index < dayTimeline.hourCount
              y: -Math.round(implicitHeight / 2)
              width: dayTimeline.labelWidth - Style.space(6)
              horizontalAlignment: Text.AlignRight
              text: root.timeText(parent.hour, root.timeFormat)
              color: Commons.Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Math.max(9, Style.font.caption - 1)
            }
          }
        }

        Item {
          id: dayLanes
          x: dayTimeline.labelWidth
          width: parent.width - dayTimeline.labelWidth
          height: parent.height

          Repeater {
            model: dayPanelRoot.segments
            EventCard {
              required property var modelData
              readonly property real laneGap: Style.space(3)
              readonly property real laneWidth: (dayLanes.width - Style.space(4) - (modelData.lanes - 1) * laneGap) / modelData.lanes
              x: Style.space(4) + modelData.lane * (laneWidth + laneGap)
              y: dayTimeline.yForHour(modelData.startHour) + 1
              width: laneWidth
              height: Math.max(Style.space(14), (modelData.endHour - modelData.startHour) * dayTimeline.hourHeight - 2)
              mode: "block"
              event: modelData.event
              onClicked: function(mouse) { root.handleEventClick(event, mouse, this) }
            }
          }
        }

        Rectangle {
          readonly property real nowHour: root.now.getHours() + root.now.getMinutes() / 60
          visible: root.selectedKey === root.todayKey && nowHour >= dayPanelRoot.hours.start && nowHour <= dayPanelRoot.hours.end
          z: 5
          x: dayTimeline.labelWidth - Style.space(4)
          y: dayTimeline.yForHour(nowHour) - height / 2
          width: parent.width - x
          height: 2
          color: Commons.Color.urgent
        }

        Text {
          visible: root.selectedEvents.length === 0
          anchors.centerIn: dayLanes
          text: "No events for this day."
          color: Commons.Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  component TimeGridView: Column {
    id: timeGridView
    spacing: Style.space(6)
    readonly property int hourStart: root.viewMode === "day" ? root.dayStartHour : (root.viewMode === "work-week" ? root.workWeekStartHour : root.weekStartHour)
    readonly property int hourEnd: root.viewMode === "day" ? root.dayEndHour : (root.viewMode === "work-week" ? root.workWeekEndHour : root.weekEndHour)
    readonly property int hourCount: hourEnd - hourStart
    readonly property int baseHourHeight: root.viewMode === "day" ? Style.space(50) : Style.space(42)
    // In the window the hours stretch to fill the height below the headings,
    // and only scroll when even the base size doesn't fit.
    readonly property int hourHeight: viewportHeight > 0
      ? Math.max(baseHourHeight, Math.floor((viewportHeight - headerRowsHeight) / Math.max(1, hourCount)))
      : baseHourHeight
    readonly property int gridLeft: Style.space(48)
    readonly property int gridRight: Style.space(8)
    // Height the view may use in the window (0 in the popup), and the height
    // of the day headings and all-day row that stay above the scrolling hours.
    property real viewportHeight: 0
    readonly property real headerRowsHeight: Style.space(42) + (allDayCount > 0 ? allDayRowHeight + spacing : 0) + spacing

    function scrollToWorkingHours() {
      if (hoursScroll.height >= hoursScroll.contentHeight) return
      var target = nowDayIndex >= 0 ? Math.max(hourStart, nowHour - 1) : Math.max(hourStart, 8)
      hoursScroll.contentY = Math.max(0, Math.min(hoursScroll.contentHeight - hoursScroll.height, yForHour(Math.floor(target))))
    }
    onVisibleChanged: if (visible) Qt.callLater(scrollToWorkingHours)
    onViewportHeightChanged: Qt.callLater(scrollToWorkingHours)
    readonly property int columnGap: Style.space(4)

    function columnWidth() {
      return Math.max(1, (timeGridView.width - timeGridView.gridLeft - timeGridView.gridRight - Math.max(0, root.viewDays.length - 1) * timeGridView.columnGap) / Math.max(1, root.viewDays.length))
    }

    function hourForY(y) {
      var halfHour = timeGridView.hourHeight / 2
      var gridHeight = timeGridView.hourCount * timeGridView.hourHeight
      var slots = Math.floor(Math.max(0, Math.min(gridHeight - 1, y)) / halfHour)
      return Math.max(timeGridView.hourStart, Math.min(timeGridView.hourEnd, timeGridView.hourStart + slots / 2))
    }

    function yForHour(hour) {
      return (hour - timeGridView.hourStart) * timeGridView.hourHeight
    }

    readonly property real nowHour: root.now.getHours() + root.now.getMinutes() / 60 + root.now.getSeconds() / 3600
    readonly property int nowDayIndex: {
      var key = Model.keyForDate(root.now)
      for (var i = 0; i < root.viewDays.length; i++) {
        if (Model.keyForDate(root.viewDays[i]) === key) return i
      }
      return -1
    }
    readonly property bool nowInView: nowDayIndex >= 0 && nowHour >= hourStart && nowHour <= hourEnd
    readonly property int allDayCount: {
      var count = 0
      for (var i = 0; i < root.viewDays.length; i++) {
        count = Math.max(count, Model.allDayEventsForDay(root.eventGroups, Model.keyForDate(root.viewDays[i])).length)
      }
      return count
    }
    readonly property int allDayRowHeight: allDayCount > 0 ? allDayCount * Style.space(18) + Style.space(8) : 0

    Item {
      width: parent.width
      height: Style.space(42)
      Repeater {
        model: root.viewDays
        Item {
          required property date modelData
          required property int index
          readonly property string key: Model.keyForDate(modelData)
          readonly property bool isToday: key === root.todayKey
          readonly property bool isSelected: key === root.selectedKey
          x: timeGridView.gridLeft + index * (timeGridView.columnWidth() + timeGridView.columnGap)
          width: timeGridView.columnWidth()
          height: parent.height

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            visible: parent.isSelected
            color: Util.alpha(Commons.Color.accent, 0.22)
            border.color: Commons.Color.accent
            border.width: 1
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(1)
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Qt.formatDate(modelData, root.viewMode === "day" ? "dddd" : "ddd")
              color: Commons.Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
            Item {
              width: Style.space(20)
              height: Style.space(20)
              anchors.horizontalCenter: parent.horizontalCenter
              Rectangle {
                visible: isToday
                anchors.fill: parent
                radius: width / 2
                color: Commons.Color.accent
              }
              Text {
                anchors.centerIn: parent
                text: modelData.getDate()
                color: isToday ? Commons.Color.popups.background : Commons.Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: isToday || isSelected
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectedKey = parent.key
          }
        }
      }
    }

    Item {
      visible: timeGridView.allDayCount > 0
      width: parent.width
      height: timeGridView.allDayRowHeight

      Text {
        x: 0
        width: timeGridView.gridLeft - timeGridView.columnGap
        height: parent.height
        text: "All day"
        color: Commons.Color.foreground
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.viewDays
        Item {
          id: allDayColumn
          required property date modelData
          required property int index
          x: timeGridView.gridLeft + index * (timeGridView.columnWidth() + timeGridView.columnGap)
          width: timeGridView.columnWidth()
          height: parent.height
          Column {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            spacing: Style.space(2)
            Repeater {
              model: Model.allDayEventsForDay(root.eventGroups, Model.keyForDate(allDayColumn.modelData))
              EventCard {
                required property var modelData
                width: parent.width
                height: Style.space(16)
                mode: "chip"
                event: modelData
                onClicked: function(mouse) { root.handleEventClick(event, mouse, this) }
              }
            }
          }
        }
      }
    }

    // In the window the hours scroll on their own under the day headings;
    // in the bar popup the grid keeps its full height as before.
    Flickable {
      id: hoursScroll
      width: parent.width
      height: timeGridView.viewportHeight > 0
        ? Math.min(hoursGrid.height, Math.max(Style.space(160), timeGridView.viewportHeight - timeGridView.headerRowsHeight))
        : hoursGrid.height
      contentWidth: width
      contentHeight: hoursGrid.height
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Item {
        id: hoursGrid
        width: parent.width
        height: timeGridView.hourCount * timeGridView.hourHeight

        Repeater {
          model: timeGridView.hourCount + 1
          Text {
            required property int index
            x: 0
            y: index * timeGridView.hourHeight - (index === timeGridView.hourCount ? implicitHeight - Style.space(2) : Style.space(6))
            width: timeGridView.gridLeft - timeGridView.columnGap
            text: Model.formatHourLabel(index + timeGridView.hourStart, root.timeFormat)
            color: Commons.Color.muted
            horizontalAlignment: Text.AlignRight
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            opacity: timeGridView.nowInView && Math.abs(index * timeGridView.hourHeight - timeGridView.yForHour(timeGridView.nowHour)) < Style.space(14) ? 0 : 1
          }
        }

        Rectangle {
          z: 5
          visible: timeGridView.nowInView
          x: timeGridView.gridLeft
          y: timeGridView.yForHour(timeGridView.nowHour) - 1
          width: parent.width - timeGridView.gridLeft - timeGridView.gridRight
          height: 2
          color: Commons.Color.urgent
        }

        Rectangle {
          z: 6
          visible: timeGridView.nowInView
          width: Style.space(8)
          height: Style.space(8)
          radius: width / 2
          color: Commons.Color.urgent
          x: timeGridView.gridLeft + timeGridView.nowDayIndex * (timeGridView.columnWidth() + timeGridView.columnGap) - width / 2
          y: timeGridView.yForHour(timeGridView.nowHour) - height / 2
        }

        Text {
          z: 7
          visible: timeGridView.nowInView
          x: Math.max(0, timeGridView.gridLeft - timeGridView.columnGap - implicitWidth)
          y: timeGridView.yForHour(timeGridView.nowHour) - implicitHeight / 2
          text: Model.formatClockTime(root.now.getHours(), root.now.getMinutes(), root.timeFormat)
          color: Commons.Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Math.max(9, Style.font.caption - 1)
          wrapMode: Text.NoWrap
        }

        Repeater {
          model: root.viewDays
          Item {
            id: dayColumn
            required property date modelData
            required property int index
            property string key: Model.keyForDate(modelData)
            property var dayEvents: Model.eventsForDay(root.eventGroups, key)
            property var timedEvents: Model.layoutTimedEvents(dayEvents, key, timeGridView.hourStart, timeGridView.hourEnd)
            x: timeGridView.gridLeft + index * (timeGridView.columnWidth() + timeGridView.columnGap)
            y: 0
            width: timeGridView.columnWidth()
            height: parent.height

            Rectangle {
              z: 0
              anchors.fill: parent
              visible: dayColumn.key === root.selectedKey
              color: Util.alpha(Commons.Color.accent, 0.08)
            }

            Repeater {
              model: timeGridView.hourCount
              Rectangle {
                required property int index
                y: index * timeGridView.hourHeight
                width: parent.width
                height: timeGridView.hourHeight
                color: index % 2 === 0 ? Style.normalFillFor(Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent) : Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
                border.color: Util.alpha(Commons.Color.muted, 0.35)
                border.width: 1
              }
            }

            Rectangle {
              z: 1
              visible: root.draggingTimeSelection && root.dragDayKey === dayColumn.key
              x: Style.space(3)
              y: timeGridView.yForHour(Math.min(root.dragStartHour, root.dragEndHour))
              width: parent.width - Style.space(6)
              height: Math.max(Style.space(12), Math.abs(root.dragEndHour - root.dragStartHour) * timeGridView.hourHeight)
              radius: Style.cornerRadius
              color: Util.alpha(Commons.Color.accent, 0.45)
              border.color: Commons.Color.accent
              border.width: 1
            }

            MouseArea {
              z: 2
              anchors.fill: parent
              cursorShape: Qt.CrossCursor
              preventStealing: true
              onPressed: function(mouse) { root.beginTimeSelection(dayColumn.key, timeGridView.hourForY(mouse.y)) }
              onPositionChanged: function(mouse) { root.updateTimeSelection(timeGridView.hourForY(mouse.y)) }
              onReleased: root.finishTimeSelection()
              onCanceled: {
                root.draggingTimeSelection = false
                root.dragDayKey = ""
              }
            }

            Repeater {
              model: dayColumn.timedEvents
              EventCard {
                z: 4
                required property var modelData
                readonly property real laneGap: Style.space(3)
                readonly property real laneWidth: (parent.width - Style.space(6) - (modelData.lanes - 1) * laneGap) / modelData.lanes
                x: Style.space(3) + modelData.lane * (laneWidth + laneGap)
                y: timeGridView.yForHour(modelData.startHour)
                width: laneWidth
                height: Math.max(Style.space(22), (modelData.endHour - modelData.startHour) * timeGridView.hourHeight)
                mode: "block"
                event: modelData.event
                onClicked: function(mouse) { root.handleEventClick(event, mouse, this) }
              }
            }
          }
        }
      }
    }

  }

  component EventCard: Rectangle {
    id: card
    property var event: ({})
    property string mode: "row"
    property bool dimmed: false
    signal clicked(var mouse)

    readonly property color accentColor: root.eventColor(card.event)
    readonly property bool saving: !!(event && event.status === "saving")
    readonly property bool showTime: mode === "block" ? height >= Style.space(36) : mode === "row"
    readonly property bool wrapTitle: mode === "block" && height >= Style.space(48)
    // All-day entries are a light tint with an outline, so timed events
    // stand out against them.
    readonly property bool allDay: !!(event && event.allDay === true)
    readonly property real fillStrength: allDay ? 0.2 : 0.72
    readonly property color labelColor: allDay ? Commons.Color.foreground : Model.contrastingForeground(card.accentColor, card.fillStrength, Commons.Color.foreground, Commons.Color.popups.background)

    radius: mode === "chip" ? Style.space(3) : Style.cornerRadius
    opacity: (card.dimmed ? 0.65 : 1) * (card.saving ? 0.72 : 1)
    border.width: card.saving || card.allDay ? 1 : 0
    border.color: card.saving ? Commons.Color.accent : Util.alpha(card.accentColor, 0.7)
    color: Util.alpha(card.accentColor, cardMouse.containsMouse ? Math.min(1, card.fillStrength + 0.1) : card.fillStrength)

    Rectangle {
      visible: !card.allDay
      width: Style.space(3)
      height: parent.height
      radius: Style.space(2)
      color: card.accentColor
    }

    Column {
      visible: card.mode === "block"
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(4)
      anchors.topMargin: Style.space(4)
      anchors.bottomMargin: Style.space(4)
      spacing: Style.space(1)
      Text {
        width: parent.width
        text: (card.event && card.event.title) || ""
        textFormat: Text.PlainText
        color: card.labelColor
        wrapMode: card.wrapTitle ? Text.Wrap : Text.NoWrap
        maximumLineCount: card.wrapTitle ? 3 : 1
        elide: Text.ElideRight
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        visible: card.showTime
        width: parent.width
        text: root.eventTimeRange(card.event)
        textFormat: Text.PlainText
        color: card.labelColor
        opacity: 0.85
        elide: Text.ElideRight
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

      Text {
        visible: card.mode !== "chip" && !!(card.event && card.event.meetingUrl)
        z: 8
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(4)
        text: "Join"
        color: card.labelColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.underline: true
        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          cursorShape: Qt.PointingHandCursor
          onClicked: function(mouse) {
            mouse.accepted = true
            root.joinEvent(card.event)
          }
        }
      }

      Text {
        visible: card.mode === "chip"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(3)
      text: (card.event && card.event.title) || ""
      textFormat: Text.PlainText
      color: card.labelColor
      elide: Text.ElideRight
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Math.max(9, Style.font.caption - 1)
    }

    Row {
      visible: card.mode === "row"
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(6)
      Text {
        width: Style.space(56)
        anchors.verticalCenter: parent.verticalCenter
        text: Model.eventListTime(card.event, root.selectedKey, root.timeFormat)
        textFormat: Text.PlainText
        color: card.allDay ? Commons.Color.muted : card.labelColor
        elide: Text.ElideRight
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        width: Math.max(0, parent.width - Style.space(62))
        anchors.verticalCenter: parent.verticalCenter
        text: (card.event && card.event.title) || ""
        textFormat: Text.PlainText
        color: card.labelColor
        elide: Text.ElideRight
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: card.allDay ? Style.font.caption : Style.font.bodySmall
        font.bold: !card.allDay
      }
    }

    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { card.clicked(mouse) }
    }

    PanelToolTip {
      visible: cardMouse.containsMouse && !card.saving
      text: root.eventTooltip(card.event)
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    }
  }

  component EventList: Column {
    id: eventList
    property var events: []
    property string emptyText: "No events."
    spacing: Style.space(4)

    Repeater {
      model: eventList.events
      EventCard {
        required property var modelData
        width: eventList.width
        height: modelData && modelData.allDay ? Style.space(20) : Style.space(28)
        mode: "row"
        event: modelData
        onClicked: function(mouse) { root.handleEventClick(event, mouse, this) }
      }
    }

    Text {
      visible: events.length === 0 && (!calendarService || calendarService.status !== "loading")
      width: parent.width
      text: emptyText
      color: Commons.Color.muted
      horizontalAlignment: Text.AlignHCenter
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
    }

    Text {
      visible: calendarService && calendarService.status === "loading"
      width: parent.width
      text: "Loading events..."
      color: Commons.Color.muted
      horizontalAlignment: Text.AlignHCenter
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
    }
  }
}
