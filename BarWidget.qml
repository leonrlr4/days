import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "lib/Store.js" as Store

// The date, the time, and how much of the day is still waiting on you.
//
// The clock half is an ordinary bar clock. The half worth having is the count
// beside it: a clock cannot know whether the day is clear, and a task list in
// a popup cannot tell you without being opened.
//
// The widget and the overlay never talk to each other. They share index.json:
// the overlay writes it, and the watch below picks the change up, so the count
// is right whether the day changed here, in the overlay, or in another
// session entirely.
BarWidget {
  id: root
  moduleName: "leonrlr4.days"

  property var shell: null

  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/leonrlr4.days"

  // Same default as the clock this is meant to replace, so swapping one for
  // the other does not move the text under your eyes.
  readonly property string format: String(setting("format", "ddd d MMM HH:mm"))
  readonly property string verticalFormat: String(setting("verticalFormat", "HH\nmm"))

  property var index: Store.emptyIndex()
  property string today: Store.todayIso()

  readonly property int openToday: Store.openCount(root.index, root.today)
  readonly property int overdue: Store.carriedOver(root.index, root.today).length

  // One number, one meaning: everything still open that was due today or
  // earlier. Counting only today would show nothing on the morning when three
  // things are already late, which is exactly when the bar should say so.
  readonly property int waiting: root.openToday + root.overdue
  readonly property bool late: root.overdue > 0

  readonly property string clockText: Qt.formatDateTime(
    clock.date, root.vertical ? root.verticalFormat : root.format)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function reload(text) {
    try {
      var parsed = JSON.parse(text)
      if (parsed && parsed.v === 1 && parsed.days && parsed.blobs) {
        root.index = parsed
        return
      }
    } catch (e) {
      // An index being rewritten underneath us is not an error worth
      // reporting on the bar; the watch fires again when the write lands.
    }
    root.index = Store.emptyIndex()
  }

  // Minute precision, not a one-second timer: the label has no seconds in it,
  // so waking every second would be a wakeup per second to redraw nothing.
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  // Midnight moves "today", and with it both the date and which tasks count
  // as overdue.
  Connections {
    target: clock
    function onDateChanged() {
      var now = Store.todayIso()
      if (now !== root.today) root.today = now
    }
  }

  FileView {
    path: root.dataDir + "/index.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.reload(text())
    onLoadFailed: root.index = Store.emptyIndex()
    onFileChanged: reload()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar

    // The label is drawn below instead, because the count has to take a
    // different colour from the clock and WidgetButton paints one string in
    // one colour.
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : content.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? content.implicitHeight + scaledVerticalPadding * 2 : -1

    tooltipText: {
      if (root.waiting === 0) return "Days — nothing open"
      var parts = []
      if (root.openToday > 0) parts.push(root.openToday + " open today")
      if (root.overdue > 0) parts.push(root.overdue + " carried over")
      return parts.join(", ")
    }

    onPressed: function(mouseButton) {
      if (root.shell) root.shell.toggle("leonrlr4.days", "{}")
    }

    Grid {
      id: content
      anchors.centerIn: parent
      columns: root.vertical ? 1 : 2
      rows: root.vertical ? 2 : 1
      columnSpacing: Style.spacing.lg
      rowSpacing: Style.spacing.xxs
      horizontalItemAlignment: Grid.AlignHCenter

      Text {
        text: root.clockText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        horizontalAlignment: Text.AlignHCenter

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }

      // Absent rather than zero: a clock that reads "✓ 0" all evening is a
      // worse clock, and the absence is itself the answer.
      Text {
        visible: root.waiting > 0
        text: "✓ " + root.waiting
        color: root.late ? Color.urgent : Color.accent
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
