import QtQuick
import Quickshell
import qs.Commons as Commons
import qs.Commons
import qs.Ui
import "CalendarModel.js" as Model

// One day at a time in its own window: the day's events in columns the user
// sets up in settings, an AI reading of the day, and an agent panel that can
// change the calendar, with undo. Events come from the calendar service, so
// the window stays in step with the rest of the calendar.
Item {
  id: root

  readonly property string moduleName: "sirwizardlizard.calendar"
  property var bar: null
  property var settings: ({})
  property var hostWidget: null
  readonly property var calendarService: bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null

  property bool shown: false
  property date now: new Date()
  readonly property string todayKey: Model.keyForDate(now)
  property string dayKey: todayKey
  readonly property bool isToday: dayKey === todayKey
  property bool agentOpen: true

  function setting(key, fallback) {
    return settings && settings[key] !== undefined ? settings[key] : fallback
  }

  readonly property string timeFormat: setting("timeFormat", "12h") === "24h" ? "24h" : "12h"
  readonly property var hiddenCalendars: setting("hiddenCalendars", {})
  readonly property var calendarColors: setting("calendarColors", {})
  readonly property var calendarNames: setting("calendarNames", {})
  readonly property int screenStartHour: clampHour(setting("screenStartHour", 7), 7)
  readonly property int screenEndHour: Math.max(screenStartHour + 1, clampHour(setting("screenEndHour", 19), 19))

  readonly property var calendars: calendarService ? calendarService.calendars : []
  readonly property var columns: Model.dayColumns(calendars, setting("dayColumns", []), hiddenCalendars)
  readonly property var dayRange: Model.dayRange(dayKey)
  // Calendars hidden in the calendar views stay out here too, unless a
  // column names them.
  readonly property var shownCalendars: {
    var shown = {}
    columns.forEach(function(column) { column.calendarIds.forEach(function(id) { shown[id] = true }) })
    return shown
  }
  readonly property var overviewHidden: {
    var hidden = {}
    for (var id in hiddenCalendars) if (hiddenCalendars[id] === true && !shownCalendars[id]) hidden[id] = true
    return hidden
  }
  readonly property var dayEvents: calendarService
    ? Model.eventsInRange(calendarService.cachedEvents, dayRange.start, dayRange.end).filter(function(event) { return root.shownCalendars[event.calendarId] === true })
    : []
  readonly property var allDayEvents: Model.allDayEventsForDay(dayEvents, dayKey)
  readonly property var hours: Model.timelineHours(dayEvents, dayKey, screenStartHour, screenEndHour)
  readonly property var layout: Model.dayColumnLayout(dayEvents, dayKey, columns, hours.start, hours.end)
  readonly property string daySignature: dayKey + "|" + columns.map(function(c) { return c.name + ":" + c.calendarIds.join(",") }).join(";") + "|"
    + dayEvents.map(function(e) { return [e.id, e.title, e.start, e.end, e.location].join("~") }).join("|")

  // Summary card state.
  property string summaryHeadline: ""
  property var summaryInsights: []
  property string summaryError: ""
  property bool summaryLoading: false
  property string summaryFor: ""
  property string summaryRequestId: ""

  // Agent panel: turns are {role, text, rejected, error, undo, undone, applying}.
  property var turns: []
  property bool agentWaiting: false
  property var actionQueue: []
  property var pendingAction: null
  property int applyingTurn: -1
  property var collectedUndo: []

  function clampHour(value, fallback) {
    var parsed = parseInt(value, 10)
    return isNaN(parsed) ? fallback : Math.max(0, Math.min(24, parsed))
  }

  function openDay(key) {
    var wanted = String(key || "")
    dayKey = /^\d{4}-\d{2}-\d{2}$/.test(wanted) ? wanted : todayKey
    now = new Date()
    shown = true
    syncDay()
    summaryTimer.restart()
    Qt.callLater(function() { body.forceActiveFocus() })
  }

  function close() {
    shown = false
    turns = []
    if (calendarService) calendarService.cancelDayAgent("")
  }

  function stepDay(delta) {
    var date = Model.dateFromKey(dayKey, new Date())
    date.setDate(date.getDate() + delta)
    dayKey = Model.keyForDate(date)
  }

  onDaySignatureChanged: if (shown) summaryTimer.restart()

  // The service only syncs when a view asks it to, so the cache can lag the
  // calendars. Ask for a sync when a day is opened, at most every two
  // minutes. When the service's range already covers the day, it syncs that
  // range; otherwise it moves to the month around this day (the calendar
  // views set their own range again when they next refresh).
  property real lastSyncAsk: 0
  function syncDay() {
    var svc = calendarService
    if (!svc || Date.now() - lastSyncAsk < 120000) return
    lastSyncAsk = Date.now()
    var covered = svc.activeStart && svc.activeEnd && Date.parse(svc.activeStart) <= Date.parse(dayRange.start) && Date.parse(svc.activeEnd) >= Date.parse(dayRange.end)
    if (covered && !svc.syncing) svc.startLiveSync(false)
    else if (!covered) {
      // Sync the month grid around the day, the range the month view uses,
      // so the cache is filled the same way as when browsing months.
      var day = Model.dateFromKey(dayKey, new Date())
      var month = Model.monthRange(day.getFullYear(), day.getMonth(), Model.normalizedWeekStart(String(setting("weekStartDay", 1)), Qt.locale().firstDayOfWeek))
      svc.snapshot(month.start, month.end, svc.provider, true)
    }
  }

  // ---- colours and labels ----
  function calendarIndex(calendarId) {
    for (var i = 0; i < calendars.length; i++) if (calendars[i] && calendars[i].id === calendarId) return i
    return 0
  }

  function eventColor(event) {
    if (!event) return Commons.Color.accent
    var calendar = calendarService ? calendarService.calendarById(event.calendarId) : null
    return Model.calendarDisplayColor(calendar || { id: event.calendarId, color: event.calendarColor }, calendarColors, calendarIndex(event.calendarId))
  }

  function calendarName(event) {
    var calendar = calendarService ? calendarService.calendarById(event.calendarId) : null
    return Model.calendarDisplayName(calendar || { id: event.calendarId, name: event.calendarName }, calendarNames)
  }

  function timeRange(event) {
    if (event.allDay || event.wholeDay) return "All day"
    return Model.formatTime(event.start, false, timeFormat) + " – " + Model.formatTime(event.end, false, timeFormat)
  }

  function span(minutes) {
    var h = Math.floor(minutes / 60), m = minutes % 60
    if (h && m) return h + " h " + m + " min"
    return h ? h + " h" : m + " min"
  }

  readonly property string statusText: {
    var timed = (layout.length ? layout[0].segments : []).map(function(s) { return s.event })
    if (!isToday) {
      var count = 0
      for (var c = 0; c < layout.length; c++) count += layout[c].segments.length
      return count === 1 ? "1 timed event" : count + " timed events"
    }
    var nowMs = now.getTime()
    for (var i = 0; i < timed.length; i++) {
      var start = Date.parse(timed[i].start), end = Date.parse(timed[i].end)
      if (nowMs >= start && nowMs < end) return "Now: " + timed[i].title + ", ends in " + span(Math.ceil((end - nowMs) / 60000))
      if (nowMs < start) return "Next: " + timed[i].title + " in " + span(Math.ceil((start - nowMs) / 60000))
    }
    return "Nothing else on today"
  }

  // ---- summary ----
  function requestSummary(force) {
    if (!calendarService || !shown) return
    summaryLoading = true
    summaryError = ""
    if (summaryFor !== dayKey) {
      summaryHeadline = ""
      summaryInsights = []
    }
    summaryFor = dayKey
    summaryRequestId = "summary-" + Date.now()
    calendarService.cancelDayAgent("summary")
    calendarService.askDayAgent({
      requestId: summaryRequestId, mode: "summary", date: dayKey, columns: columns, hidden: overviewHidden,
      names: calendarNames, force: force === true
    })
  }

  Timer { id: summaryTimer; interval: 1200; onTriggered: root.requestSummary(false) }
  Timer { interval: 30000; running: root.shown; repeat: true; onTriggered: root.now = new Date() }

  // ---- agent ----
  function ask(text) {
    var prompt = String(text || "").trim()
    if (!prompt || !calendarService || agentWaiting || applyingTurn >= 0) return
    var history = turns.filter(function(t) { return t.role === "user" || t.role === "agent" }).map(function(t) { return { role: t.role, text: t.text } })
    pushTurn({ role: "user", text: prompt })
    agentWaiting = true
    calendarService.askDayAgent({
      mode: "chat", date: dayKey, prompt: prompt, history: history, columns: columns,
      hidden: overviewHidden, names: calendarNames, defaultCalendarId: String(setting("defaultCalendarId", ""))
    })
  }

  function pushTurn(turn) {
    var next = turns.slice()
    next.push(turn)
    turns = next
    Qt.callLater(function() { chatList.positionViewAtEnd() })
  }

  function patchTurn(index, fields) {
    var next = turns.slice()
    var turn = {}
    for (var k in next[index]) turn[k] = next[index][k]
    for (var f in fields) turn[f] = fields[f]
    next[index] = turn
    turns = next
  }

  function findEvent(match) {
    var source = calendarService ? calendarService.cachedEvents : []
    for (var i = 0; i < source.length; i++) {
      var e = source[i]
      if (!e) continue
      if (match.id && e.id === match.id) return e
      if (match.uid && e.uid === match.uid && (!match.calendarId || e.calendarId === match.calendarId) && (match.rid === undefined || (e.rid || "") === match.rid)) return e
    }
    return null
  }

  function bounds(event) {
    if (event.allDay) {
      var first = Model.eventDateKey(event)
      var last = String(event.end || "").slice(0, 10) || Model.nextDateKey(first)
      return { start: first, end: last }
    }
    return { start: event.start, end: event.end }
  }

  // Applies a turn's actions one at a time: the service runs one write of each
  // kind at once, so each waits for the last to finish. Each success records
  // the action that undoes it.
  function applyActions(turnIndex, actions, undoMode) {
    applyingTurn = turnIndex
    actionQueue = actions.slice()
    collectedUndo = []
    patchTurn(turnIndex, { applying: true })
    nextAction(undoMode === true)
  }

  property bool undoing: false

  function nextAction(undoMode) {
    if (undoMode !== undefined) undoing = undoMode
    if (!actionQueue.length) { finishApplying(""); return }
    var queue = actionQueue.slice()
    var action = queue.shift()
    actionQueue = queue
    pendingAction = action
    var svc = calendarService
    if (action.op === "create") {
      svc.createEvent(action.calendarId, action.title, action.start, action.end, action.location || "", action.description || "", "never", action.allDay === true, "", "none")
      return
    }
    var target = findEvent(action.match || { id: action.eventId })
    if (!target) { finishApplying("Couldn't find that event any more."); return }
    pendingAction.before = target
    if (action.op === "update") {
      svc.updateEvent(target, action.title, action.start, action.end, action.location || "", target.description || "", "this", action.allDay === true, action.calendarId || target.calendarId, target.meetingUrl || "", target.meetingUrl ? "link" : "none")
    } else if (action.op === "delete") {
      svc.deleteEvent(target, "this")
    }
  }

  function actionDone(ok, message, created) {
    var action = pendingAction
    if (!action) return
    pendingAction = null
    if (!ok) { finishApplying(message || "The calendar didn't take that change."); return }
    var undo = collectedUndo.slice()
    if (action.op === "create" && created) {
      undo.unshift({ op: "delete", match: { uid: created.uid, calendarId: created.calendarId } })
    } else if (action.op === "update") {
      var before = action.before
      var was = bounds(before)
      undo.unshift({ op: "update", match: { uid: before.uid, rid: before.rid || "", calendarId: action.calendarId || before.calendarId },
        calendarId: before.calendarId, title: before.title, start: was.start, end: was.end, allDay: before.allDay === true, location: before.location || "" })
    } else if (action.op === "delete") {
      var gone = action.before
      var span_ = bounds(gone)
      undo.unshift({ op: "create", calendarId: gone.calendarId, title: gone.title, start: span_.start, end: span_.end,
        allDay: gone.allDay === true, location: gone.location || "", description: gone.description || "" })
    }
    collectedUndo = undo
    Qt.callLater(function() { root.nextAction() })
  }

  function finishApplying(error) {
    var index = applyingTurn
    applyingTurn = -1
    pendingAction = null
    actionQueue = []
    if (index < 0 || index >= turns.length) return
    if (undoing) patchTurn(index, { applying: false, undone: error === "", error: error })
    else patchTurn(index, { applying: false, undo: collectedUndo, error: error })
    undoing = false
  }

  function undoTurn(index) {
    var turn = turns[index]
    if (!turn || !turn.undo || !turn.undo.length || turn.undone || applyingTurn >= 0) return
    applyActions(index, turn.undo, true)
  }

  Connections {
    target: root.calendarService
    ignoreUnknownSignals: true
    function onDayAgentAnswered(answer) {
      if (!answer) return
      if (answer.mode === "summary") {
        if (answer.requestId !== root.summaryRequestId) return
        root.summaryLoading = false
        if (answer.ok) {
          root.summaryHeadline = answer.headline || ""
          root.summaryInsights = answer.insights || []
          root.summaryError = ""
        } else {
          root.summaryError = answer.error || "The agent couldn't read the day."
        }
        return
      }
      if (answer.mode !== "chat" || !root.agentWaiting) return
      root.agentWaiting = false
      if (!answer.ok) {
        root.pushTurn({ role: "error", text: answer.error || "The agent gave no answer." })
        return
      }
      root.pushTurn({ role: "agent", text: answer.reply || "", rejected: answer.rejected || [], undo: [], undone: false, error: "", applying: false })
      if ((answer.actions || []).length) root.applyActions(root.turns.length - 1, answer.actions, false)
    }
    property var createdEvent: null
    function onEventCreated(event) { if (root.pendingAction && root.pendingAction.op === "create") createdEvent = event }
    function onEventSaved(ok, message) {
      if (!root.pendingAction || root.pendingAction.op === "delete") return
      var created = createdEvent
      createdEvent = null
      root.actionDone(ok, message, created)
    }
    function onEventDeleted(ok, message) {
      if (root.pendingAction && root.pendingAction.op === "delete") root.actionDone(ok, message, null)
    }
  }

  // ---- window ----
  FloatingWindow {
    id: window
    visible: root.shown
    title: "Day overview"
    color: Commons.Color.background
    implicitWidth: Style.space(1180)
    implicitHeight: Style.space(820)
    minimumSize: Qt.size(Style.space(640), Style.space(480))
    onVisibleChanged: if (!visible && root.shown) root.close()

    Item {
      id: body
      anchors.fill: parent
      anchors.margins: Style.space(20)
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
        else if (event.key === Qt.Key_Left) { root.stepDay(-1); event.accepted = true }
        else if (event.key === Qt.Key_Right) { root.stepDay(1); event.accepted = true }
        else if (event.key === Qt.Key_T) { root.dayKey = root.todayKey; event.accepted = true }
        else if (event.key === Qt.Key_A) { root.agentOpen = !root.agentOpen; event.accepted = true }
        else if (event.key === Qt.Key_Slash) { root.agentOpen = true; agentInput.forceActiveFocus(); event.accepted = true }
      }

      MouseArea { anchors.fill: parent; onClicked: body.forceActiveFocus() }

      Item {
        id: main
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: agentPane.visible ? agentPane.left : parent.right
        anchors.rightMargin: agentPane.visible ? Style.space(20) : 0

        Column {
          id: header
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            height: titleColumn.height

            Column {
              id: titleColumn
              spacing: Style.space(4)
              Text {
                text: Qt.formatDate(Model.dateFromKey(root.dayKey, new Date()), "dddd d MMMM")
                color: Commons.Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }
              Text {
                text: root.statusText
                color: Commons.Color.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.heading
              }
            }

            Row {
              anchors.right: parent.right
              anchors.top: parent.top
              spacing: Style.space(6)
              Button { text: "‹"; bordered: true; tooltipText: "Previous day (←)"; onClicked: root.stepDay(-1) }
              Button { text: "Today"; bordered: true; selected: root.isToday; onClicked: root.dayKey = root.todayKey }
              Button { text: "›"; bordered: true; tooltipText: "Next day (→)"; onClicked: root.stepDay(1) }
              Button { text: root.agentOpen ? "Hide panel" : "Summary and agent"; bordered: true; tooltipText: "Show or hide the summary and agent (A)"; onClicked: root.agentOpen = !root.agentOpen }
            }
          }

          // All-day and whole-day entries
          Flow {
            width: parent.width
            spacing: Style.space(6)
            visible: root.allDayEvents.length > 0
            Repeater {
              model: root.allDayEvents
              Rectangle {
                required property var modelData
                readonly property color tint: root.eventColor(modelData)
                width: chipText.implicitWidth + Style.space(20)
                height: chipText.implicitHeight + Style.space(10)
                radius: height / 2
                color: Util.alpha(tint, 0.22)
                border.width: 1
                border.color: Util.alpha(tint, 0.7)
                Text {
                  id: chipText
                  anchors.centerIn: parent
                  text: modelData.title + "  ·  " + root.calendarName(modelData)
                  color: Commons.Color.foreground
                  textFormat: Text.PlainText
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.editEvent(modelData) }
              }
            }
          }
        }

        // Column titles
        Row {
          id: columnTitles
          anchors.top: header.bottom
          anchors.topMargin: Style.space(14)
          x: timeline.gutter
          width: parent.width - timeline.gutter
          Repeater {
            model: root.layout
            Text {
              required property var modelData
              width: columnTitles.width / Math.max(1, root.layout.length)
              leftPadding: Style.space(4)
              text: String(modelData.name).toUpperCase()
              color: Commons.Color.foreground
              opacity: 0.55
              elide: Text.ElideRight
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
            }
          }
        }

        Flickable {
          id: flick
          anchors.top: columnTitles.bottom
          anchors.topMargin: Style.space(8)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          clip: true
          contentWidth: width
          contentHeight: timeline.height + Style.space(12)
          boundsBehavior: Flickable.StopAtBounds

          Item {
            id: timeline
            readonly property real gutter: Style.space(58)
            readonly property int hourCount: Math.max(1, root.hours.end - root.hours.start)
            readonly property real hourHeight: Math.max(Style.space(52), (flick.height - Style.space(16)) / hourCount)
            readonly property real columnWidth: (width - gutter) / Math.max(1, root.layout.length)
            width: flick.width
            height: hourCount * hourHeight + Style.space(8)
            y: Style.space(6)

            function yFor(hour) { return (hour - root.hours.start) * hourHeight }

            Repeater {
              model: timeline.hourCount + 1
              Item {
                required property int index
                y: timeline.yFor(root.hours.start + index)
                width: timeline.width
                Text {
                  y: -height / 2
                  text: Model.formatHourLabel(root.hours.start + index, root.timeFormat)
                  color: Commons.Color.foreground
                  opacity: 0.5
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }
                Rectangle {
                  x: timeline.gutter
                  width: timeline.width - timeline.gutter
                  height: 1
                  color: Util.alpha(Commons.Color.foreground, 0.1)
                }
              }
            }

            Repeater {
              model: root.layout
              Item {
                id: columnItem
                required property var modelData
                required property int index
                x: timeline.gutter + index * timeline.columnWidth
                width: timeline.columnWidth
                height: timeline.height

                Rectangle {
                  visible: columnItem.index > 0
                  width: 1
                  height: parent.height
                  color: Util.alpha(Commons.Color.foreground, 0.08)
                }

                Repeater {
                  model: columnItem.modelData.segments
                  Rectangle {
                    id: block
                    required property var modelData
                    readonly property var event: modelData.event
                    readonly property color tint: root.eventColor(event)
                    readonly property bool past: root.now.getTime() >= Date.parse(event.end)
                    readonly property real laneWidth: (columnItem.width - Style.space(8)) / Math.max(1, modelData.lanes)
                    readonly property color label: Model.contrastingForeground(tint, 0.72, Commons.Color.foreground, Commons.Color.background)
                    x: Style.space(4) + modelData.lane * laneWidth
                    y: timeline.yFor(modelData.startHour) + 1
                    width: laneWidth - Style.space(3)
                    height: Math.max(Style.space(20), timeline.yFor(modelData.endHour) - timeline.yFor(modelData.startHour) - 2)
                    radius: Style.cornerRadius
                    color: Util.alpha(tint, blockMouse.containsMouse ? 0.85 : 0.72)
                    opacity: (past ? 0.5 : 1) * (event.status === "saving" ? 0.7 : 1)
                    clip: true

                    Column {
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      anchors.topMargin: block.height > Style.space(34) ? Style.space(5) : Style.space(2)
                      spacing: Style.space(1)
                      Text {
                        width: parent.width
                        text: block.event.title || "(No title)"
                        color: block.label
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        wrapMode: block.height > Style.space(60) ? Text.Wrap : Text.NoWrap
                        maximumLineCount: 2
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }
                      Text {
                        visible: block.height > Style.space(34)
                        width: parent.width
                        text: root.timeRange(block.event) + "  ·  " + root.calendarName(block.event) + (block.event.location ? "  ·  " + block.event.location : "")
                        color: block.label
                        opacity: 0.85
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      id: blockMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.editEvent(block.event)
                    }
                  }
                }
              }
            }

            // Now line
            Item {
              readonly property real hourNow: root.now.getHours() + root.now.getMinutes() / 60
              visible: root.isToday && hourNow >= root.hours.start && hourNow <= root.hours.end
              y: timeline.yFor(hourNow)
              width: timeline.width
              z: 10
              Rectangle { x: timeline.gutter - Style.space(4); y: -Style.space(4); width: Style.space(8); height: width; radius: width / 2; color: Commons.Color.urgent }
              Rectangle { x: timeline.gutter; y: -1; width: timeline.width - timeline.gutter; height: 2; color: Commons.Color.urgent }
            }
          }

          property bool userScrolled: false
          onMovementStarted: userScrolled = true
          onHeightChanged: if (!userScrolled) Qt.callLater(root.scrollToMorning)
          Component.onCompleted: root.scrollToMorning()
        }
      }

      // Agent panel
      Rectangle {
        id: agentPane
        visible: root.agentOpen
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(360)
        radius: Style.cornerRadius
        color: Util.alpha(Commons.Color.foreground, 0.04)

        // AI summary of the day, scrolling when the insights run long.
        Flickable {
          id: summaryFlick
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(14)
          height: Math.min(summaryColumn.implicitHeight, agentPane.height * 0.45)
          contentHeight: summaryColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: summaryColumn
            width: summaryFlick.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              height: refreshButton.height
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Your day"
                color: Commons.Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Button {
                id: refreshButton
                anchors.right: parent.right
                text: root.summaryLoading && root.summaryHeadline ? "Updating…" : "Refresh"
                enabled: !root.summaryLoading
                onClicked: root.requestSummary(true)
              }
            }
            Text {
              width: parent.width
              text: root.summaryError ? root.summaryError
                : (root.summaryHeadline || (root.summaryLoading ? "Reading your day…" : "No summary yet."))
              color: root.summaryError ? Commons.Color.urgent : Commons.Color.foreground
              opacity: !root.summaryHeadline && !root.summaryError ? 0.6 : 1
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: root.summaryHeadline !== ""
            }
            Repeater {
              model: root.summaryError ? [] : root.summaryInsights
              Text {
                required property string modelData
                width: summaryColumn.width
                text: "· " + modelData
                color: Commons.Color.foreground
                opacity: 0.85
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        Rectangle {
          id: paneRule
          anchors.top: summaryFlick.bottom
          anchors.topMargin: Style.space(12)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: Style.space(14)
          anchors.rightMargin: Style.space(14)
          height: 1
          color: Util.alpha(Commons.Color.foreground, 0.1)
        }

        Text {
          id: agentTitle
          anchors.left: parent.left
          anchors.top: paneRule.bottom
          anchors.margins: Style.space(14)
          text: "Agent"
          color: Commons.Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        ListView {
          id: chatList
          anchors.top: agentTitle.bottom
          anchors.topMargin: Style.space(10)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: inputRow.top
          anchors.margins: Style.space(14)
          anchors.bottomMargin: Style.space(10)
          clip: true
          spacing: Style.space(10)
          model: root.turns

          header: Text {
            width: chatList.width
            visible: root.turns.length === 0
            height: visible ? implicitHeight : 0
            text: "Ask about this day or change it: “move lunch to 12:30”, “add the gym at 6 tomorrow”, “what's free on Friday afternoon?” Changes are made straight away and can be undone."
            color: Commons.Color.foreground
            opacity: 0.6
            wrapMode: Text.WordWrap
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }

          delegate: Column {
            id: turnItem
            required property var modelData
            required property int index
            width: chatList.width
            spacing: Style.space(4)

            Rectangle {
              width: Math.min(turnItem.width, turnText.implicitWidth + Style.space(20))
              height: turnText.implicitHeight + Style.space(14)
              anchors.right: turnItem.modelData.role === "user" ? parent.right : undefined
              radius: Style.cornerRadius
              color: turnItem.modelData.role === "user" ? Util.alpha(Commons.Color.accent, 0.18) : Util.alpha(Commons.Color.foreground, 0.06)
              Text {
                id: turnText
                anchors.fill: parent
                anchors.margins: Style.space(7)
                anchors.leftMargin: Style.space(10)
                text: turnItem.modelData.text
                color: turnItem.modelData.role === "error" ? Commons.Color.urgent : Commons.Color.foreground
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Repeater {
              model: turnItem.modelData.rejected || []
              Text {
                required property string modelData
                width: turnItem.width
                text: modelData
                color: Commons.Color.urgent
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              visible: !!turnItem.modelData.error
              width: turnItem.width
              text: turnItem.modelData.error || ""
              color: Commons.Color.urgent
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            Row {
              visible: turnItem.modelData.applying === true || (turnItem.modelData.undo || []).length > 0
              spacing: Style.space(8)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: turnItem.modelData.applying ? "Saving…"
                  : (turnItem.modelData.undone ? "Undone" : ((turnItem.modelData.undo || []).length === 1 ? "1 change made" : (turnItem.modelData.undo || []).length + " changes made"))
                color: Commons.Color.foreground
                opacity: 0.6
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
              Button {
                visible: !turnItem.modelData.applying && !turnItem.modelData.undone && (turnItem.modelData.undo || []).length > 0
                text: "Undo"
                bordered: true
                enabled: root.applyingTurn < 0
                onClicked: root.undoTurn(turnItem.index)
              }
            }
          }

          footer: Text {
            width: chatList.width
            visible: root.agentWaiting
            height: visible ? implicitHeight + Style.space(10) : 0
            topPadding: Style.space(10)
            text: "Thinking…"
            color: Commons.Color.foreground
            opacity: 0.6
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Row {
          id: inputRow
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(14)
          spacing: Style.space(6)
          TextField {
            id: agentInput
            width: parent.width - sendButton.width - parent.spacing
            placeholderText: "Ask or change something ( / )"
            enabled: !root.agentWaiting && root.applyingTurn < 0
            onAccepted: sendButton.clicked()
            Keys.onEscapePressed: body.forceActiveFocus()
          }
          Button {
            id: sendButton
            text: root.agentWaiting ? "Thinking…" : "Ask"
            bordered: true
            enabled: !root.agentWaiting && root.applyingTurn < 0 && agentInput.text.trim() !== ""
            onClicked: {
              root.ask(agentInput.text)
              agentInput.text = ""
            }
          }
        }
      }
    }
  }

  function scrollToMorning() {
    var hour = isToday ? Math.max(hours.start, now.getHours() - 1) : screenStartHour
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, timeline.yFor(hour)))
  }

  onDayKeyChanged: {
    flick.userScrolled = false
    Qt.callLater(scrollToMorning)
    if (shown) { lastSyncAsk = 0; syncDay() }
  }

  function editEvent(event) {
    if (hostWidget && typeof hostWidget.editEventInWindow === "function") hostWidget.editEventInWindow(event)
  }
}
