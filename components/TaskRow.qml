import QtQuick
import qs.Commons

// One task in a list.
//
// Two shapes from one component: a task on its own day shows what it carries
// (attachments, a note, subtask progress), and a carried-over task shows where
// it came from and a way to bring it here instead.
Item {
  id: row

  // Deliberately NOT `required`. A Repeater delegate that declares any
  // required property stops receiving modelData as a context property, and
  // `task: modelData` then binds undefined -- every binding below throws and
  // the row renders blank with its checkbox stuck on. tests/test_qml.qml pins
  // the behaviour; leave these plain.
  property var overlay: null
  property var task: null

  property string sourceDate: ""     // set only in the carried-over section
  property bool selected: false

  signal toggled()
  signal opened()
  signal pulled()

  readonly property bool carried: sourceDate !== ""

  implicitHeight: Math.max(Style.space(30), label.implicitHeight + Style.spacing.xl)

  Rectangle {
    anchors.fill: parent
    anchors.rightMargin: Style.spacing.sm
    radius: Style.cornerRadius / 2
    color: row.selected ? overlay.raised
         : (hover.containsMouse ? Qt.rgba(overlay.fg.r, overlay.fg.g, overlay.fg.b, 0.03)
                                : "transparent")
  }

  // The selected row is marked on its leading edge rather than by a fill, so
  // selection stays legible on top of the hover state.
  Rectangle {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(2)
    height: parent.height - Style.spacing.md
    radius: 1
    visible: row.selected
    color: overlay.accent
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    onClicked: row.opened()
  }

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.xl
    anchors.rightMargin: Style.spacing.md
    spacing: Style.spacing.xl

    // ---- the box ----
    Item {
      width: Style.space(15)
      height: row.height

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Style.spacing.lg
        width: Style.space(15)
        height: Style.space(15)
        radius: Style.cornerRadius / 3
        color: row.task && row.task.done
          ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.13)
          : "transparent"
        border.width: 1
        border.color: row.task && row.task.done
          ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.6)
          : Qt.rgba(overlay.fg.r, overlay.fg.g, overlay.fg.b, 0.25)

        Text {
          anchors.centerIn: parent
          visible: !!row.task && row.task.done
          text: "✓"
          color: overlay.accent
          font.family: overlay.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: row.toggled()
      }
    }

    // ---- the text ----
    Text {
      id: label
      width: parent.width - Style.space(15) - meta.width - Style.spacing.xl * 2
      y: Style.spacing.lg - Style.spacing.xxs
      text: row.task ? row.task.text : ""
      color: row.task && row.task.done ? overlay.dimmer : overlay.fg
      font.family: overlay.fontFamily
      font.pixelSize: Style.font.body
      font.strikeout: !!row.task && row.task.done
      wrapMode: Text.Wrap
      maximumLineCount: 3
      elide: Text.ElideRight
    }

    // ---- what it carries, or where it came from ----
    Row {
      id: meta
      y: Style.spacing.lg
      spacing: Style.spacing.lg

      Text {
        visible: row.carried
        text: Qt.formatDate(new Date(row.sourceDate + "T00:00:00Z"), "d MMM")
        color: overlay.urgent
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        visible: row.carried
        width: Style.space(20)
        height: Style.space(16)
        radius: Style.cornerRadius / 3
        color: pullHover.containsMouse
          ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.12) : "transparent"
        border.width: 1
        border.color: pullHover.containsMouse
          ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.5) : overlay.line

        Text {
          anchors.centerIn: parent
          text: "→"
          color: pullHover.containsMouse ? overlay.accent : overlay.dim
          font.family: overlay.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: pullHover
          anchors.fill: parent
          hoverEnabled: true
          onClicked: row.pulled()
        }
      }

      Text {
        visible: !row.carried && !!row.task && row.task.atts.length > 0
        text: "◧ " + (row.task ? row.task.atts.length : 0)
        color: overlay.dimmer
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: !row.carried && !!row.task && row.task.note.length > 0
        text: "≡"
        color: overlay.dimmer
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: !row.carried && !!row.task && row.task.subs.length > 0
        text: row.task
          ? row.task.subs.filter(function(s) { return s.done }).length +
            "/" + row.task.subs.length
          : ""
        color: overlay.dimmer
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
