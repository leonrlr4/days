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
  property bool editing: false

  signal toggled()
  signal opened()
  signal pulled()
  signal deleted()
  signal copied()
  signal edited(string text)

  // Opened by the day pane, which owns which row is being edited; the row only
  // has to put the keyboard in the right place once the field exists.
  onEditingChanged: {
    if (!row.editing) return
    field.text = row.task ? row.task.text : ""
    Qt.callLater(function() {
      field.forceActiveFocus()
      field.cursorPosition = field.length
    })
  }

  function commit() {
    if (!row.editing) return
    row.edited(field.text)
  }

  readonly property bool carried: sourceDate !== ""

  implicitHeight: Math.max(Style.space(30), label.implicitHeight + Style.spacing.xl)

  Rectangle {
    anchors.fill: parent
    anchors.rightMargin: Style.spacing.sm
    radius: Style.cornerRadius / 2
    color: row.selected ? overlay.raised
         : (hover.containsMouse ? Qt.rgba(overlay.fg.r, overlay.fg.g, overlay.fg.b, 0.03)
                                : "transparent")
    border.width: 1
    border.color: row.editing
      ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.7) : "transparent"
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

  // One click selects, two copy. The first click of a double click arrives as
  // a plain click, which is exactly why selection is the safe thing to hang on
  // it: selecting the row you are about to copy from costs nothing, where
  // ticking it twice would have needed the 220ms wait the thumbnails use.
  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    enabled: !row.editing
    onClicked: row.opened()
    onDoubleClicked: row.copied()
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
    Item {
      width: parent.width - Style.space(15) - meta.width - Style.spacing.xl * 2
      height: row.height

      TextInput {
        id: field
        visible: row.editing
        width: parent.width
        y: Style.spacing.lg - Style.spacing.xxs
        color: overlay.fg
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.body
        selectByMouse: true
        selectionColor: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.3)
        clip: true

        // Enter finishes and Escape finishes: the text has been typed, and the
        // key that means "done editing" elsewhere in this overlay must not be
        // the one that throws it away. Clicking elsewhere commits too.
        onAccepted: row.commit()
        Keys.onEscapePressed: row.commit()
        onActiveFocusChanged: if (!activeFocus) row.commit()
      }

    Text {
      id: label
      visible: !row.editing
      width: parent.width
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

      // Only on hover, and only on the row you are pointing at: a delete that
      // is always visible on every row is a delete you eventually hit by
      // accident. `dd` still works, and `u` still puts it back.
      Text {
        visible: hover.containsMouse || pullHover.containsMouse
        text: "\u00d7"
        color: deleteHover.containsMouse ? overlay.urgent : overlay.dimmer
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.body

        MouseArea {
          id: deleteHover
          anchors.fill: parent
          anchors.margins: -Style.spacing.md
          hoverEnabled: true
          onClicked: row.deleted()
        }
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
