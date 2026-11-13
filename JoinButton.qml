import QtQuick
import qs.Commons as Commons
import qs.Commons
import "CalendarModel.js" as Model

// A filled button that opens an event's meeting link (Zoom, Meet, Teams
// and the rest of MEETING_PATTERNS). It hides itself when the event has no
// link. `compact` drops the provider name for tight spaces and `iconOnly`
// drops the word too (the vertical bar).
Rectangle {
  id: join

  property var bar: null
  property var event: null
  property bool compact: false
  property bool iconOnly: false
  property real fontSize: Style.font.caption

  readonly property var meeting: Model.eventMeeting(join.event)
  readonly property string url: /^https?:\/\//i.test(String(meeting.url || "")) ? String(meeting.url) : ""
  readonly property color fill: Commons.Color.accent
  readonly property color ink: Model.contrastingForeground(fill, 1, Commons.Color.foreground, Commons.Color.background)

  function openMeeting() {
    if (!join.url || !join.bar) return
    join.bar.run("xdg-open '" + join.url.replace(/'/g, "") + "'")
  }

  visible: join.url !== ""
  implicitWidth: label.implicitWidth + Style.space(join.compact ? 10 : 14)
  implicitHeight: label.implicitHeight + Style.space(join.compact ? 4 : 6)
  width: implicitWidth
  height: implicitHeight
  radius: height / 2
  color: joinMouse.pressed ? Qt.darker(fill, 1.15) : (joinMouse.containsMouse ? Qt.lighter(fill, 1.12) : fill)

  Text {
    id: label
    anchors.centerIn: parent
    text: join.iconOnly ? "󰕧" : "󰕧  " + (join.compact ? "Join" : "Join " + Model.meetingProviderLabel(join.meeting.provider))
    textFormat: Text.PlainText
    color: join.ink
    font.family: join.bar ? join.bar.fontFamily : Style.font.family
    font.pixelSize: join.fontSize
    font.bold: true
  }

  MouseArea {
    id: joinMouse
    anchors.fill: parent
    anchors.margins: -Style.space(2)
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      mouse.accepted = true
      join.openMeeting()
    }
  }
}
