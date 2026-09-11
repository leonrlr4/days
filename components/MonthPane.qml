import QtQuick
import qs.Commons
import "../lib/Store.js" as Store

// The month, and how much of it is still open.
//
// Every number here comes from the index, never from the day files: the dots
// under a date are that day's open count, and they have to stay cheap enough
// to draw for a whole month at once.
Item {
  id: pane
  required property var overlay

  readonly property string month: overlay.month
  readonly property int blanks: Store.leadingBlanks(month)
  readonly property int length: Store.daysInMonth(month)

  readonly property var weekStats: {
    // The week the selected day sits in, Monday to Sunday.
    var p = overlay.date.split("-")
    var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2]))
    var start = Store.shiftIso(overlay.date, -(((d.getUTCDay() + 6) % 7)))
    var open = 0
    var done = 0
    for (var i = 0; i < 7; i++) {
      var entry = overlay.index.days[Store.shiftIso(start, i)]
      if (!entry) continue
      open += entry.open.length
      done += entry.done
    }
    return { open: open, done: done, total: open + done }
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.xxl

    // ---- header ----
    Item {
      width: parent.width
      height: Style.space(22)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: "‹"
        color: monthBack.containsMouse ? overlay.fg : overlay.dimmer
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.title
        MouseArea {
          id: monthBack
          anchors.fill: parent
          anchors.margins: -Style.spacing.sm
          hoverEnabled: true
          onClicked: overlay.month = Store.shiftMonth(overlay.month, -1)
        }
      }

      Text {
        anchors.centerIn: parent
        text: Qt.formatDate(new Date(pane.month + "-01T00:00:00Z"), "MMMM yyyy")
        color: overlay.fg
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.subtitle
        font.weight: Font.DemiBold
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        color: monthNext.containsMouse ? overlay.fg : overlay.dimmer
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.title
        MouseArea {
          id: monthNext
          anchors.fill: parent
          anchors.margins: -Style.spacing.sm
          hoverEnabled: true
          onClicked: overlay.month = Store.shiftMonth(overlay.month, 1)
        }
      }
    }

    // ---- weekday row ----
    Row {
      width: parent.width
      Repeater {
        model: ["M", "T", "W", "T", "F", "S", "S"]
        Text {
          width: pane.width / 7 - Style.spacing.md
          horizontalAlignment: Text.AlignHCenter
          text: modelData
          color: overlay.dimmer
          font.family: overlay.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // ---- the grid ----
    Grid {
      id: grid
      width: parent.width
      columns: 7
      rowSpacing: Style.spacing.xxs

      Repeater {
        model: pane.blanks + pane.length

        Item {
          id: cell
          readonly property bool filler: index < pane.blanks
          readonly property int dayNumber: index - pane.blanks + 1
          readonly property string iso: filler ? "" : Store.dateIn(pane.month, dayNumber)
          readonly property int openCount: filler ? 0 : Store.openCount(overlay.index, iso)
          readonly property bool isToday: iso === overlay.today
          readonly property bool isSelected: iso === overlay.date
          readonly property bool isPast: !filler && iso < overlay.today

          width: grid.width / 7
          height: Style.space(34)

          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Style.cornerRadius / 2
            visible: !cell.filler && (cell.isSelected || cellHover.containsMouse)
            color: cell.isSelected
              ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.12)
              : overlay.raised
            border.width: cell.isSelected ? 1 : 0
            border.color: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.45)
          }

          Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Style.cornerRadius / 2
            visible: cell.isToday && !cell.isSelected
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.35)
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.spacing.xxs
            visible: !cell.filler

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: cell.dayNumber
              color: cell.isToday ? overlay.accent
                   : (cell.openCount ? overlay.fg : overlay.dimmer)
              font.family: overlay.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.weight: cell.isToday ? Font.DemiBold : Font.Normal
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              height: Style.space(3)
              spacing: Style.spacing.xxs
              Repeater {
                model: Math.min(cell.openCount, 3)
                Rectangle {
                  width: Style.space(3)
                  height: Style.space(3)
                  radius: width / 2
                  // Red once the day is behind you: an open task on a past
                  // date is a different fact from one still ahead.
                  color: cell.isPast ? overlay.urgent : overlay.accent
                  opacity: 0.8
                }
              }
            }
          }

          MouseArea {
            id: cellHover
            anchors.fill: parent
            hoverEnabled: !cell.filler
            enabled: !cell.filler
            onClicked: overlay.goToDate(cell.iso)
          }
        }
      }
    }

    Item { width: 1; height: Style.spacing.sm }
  }

  // ---- footer stats ----
  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.lg

    Rectangle { width: parent.width; height: 1; color: overlay.lineSoft }

    Item {
      width: parent.width
      height: Style.space(14)
      Text {
        anchors.left: parent.left
        text: "This week"
        color: overlay.dim
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        anchors.right: parent.right
        text: pane.weekStats.done + " / " + pane.weekStats.total
        color: overlay.fg
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Rectangle {
      width: parent.width
      height: Style.space(3)
      radius: height / 2
      color: overlay.lineSoft
      Rectangle {
        height: parent.height
        radius: parent.radius
        width: pane.weekStats.total
          ? parent.width * (pane.weekStats.done / pane.weekStats.total) : 0
        color: overlay.accent
      }
    }

    Item {
      width: parent.width
      height: Style.space(14)
      visible: overlay.carried.length > 0
      Text {
        anchors.left: parent.left
        text: "Open before today"
        color: overlay.dim
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        anchors.right: parent.right
        text: overlay.carried.length
        color: overlay.urgent
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }
}
