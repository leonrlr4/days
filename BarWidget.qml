import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "lib/Store.js" as Store

// Today's open count, and a way back into the day.
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
  readonly property bool hideWhenClear: setting("hideWhenClear", false) === true

  property var index: Store.emptyIndex()
  property string today: Store.todayIso()

  readonly property int openToday: Store.openCount(root.index, root.today)
  readonly property int overdue: Store.carriedOver(root.index, root.today).length

  visible: !(root.hideWhenClear && root.openToday === 0 && root.overdue === 0)

  // BarWidget is a bare Item: without these the widget occupies no space in
  // the bar and simply never appears.
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

  FileView {
    path: root.dataDir + "/index.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.reload(text())
    onLoadFailed: root.index = Store.emptyIndex()
    onFileChanged: reload()
  }

  // Only to catch midnight. The count itself is event-driven.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var now = Store.todayIso()
      if (now !== root.today) root.today = now
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "✓" : "✓ " + root.openToday
    hasVisualContent: true
    active: root.openToday > 0
    tooltipText: {
      if (root.openToday === 0 && root.overdue === 0) return "Days — nothing open"
      var parts = []
      if (root.openToday > 0) parts.push(root.openToday + " open today")
      if (root.overdue > 0) parts.push(root.overdue + " carried over")
      return parts.join(", ")
    }
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(button) {
      if (root.shell) root.shell.toggle("leonrlr4.days", "{}")
    }
  }
}
