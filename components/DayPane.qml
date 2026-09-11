import QtQuick
import qs.Commons
import "../lib/Store.js" as Store

// One day: what is scheduled, what was carried in, and what is on the list.
Item {
  id: pane
  required property var overlay

  signal dismissed()

  function focusAdd() { addField.forceActiveFocus() }

  readonly property int dayDelta: {
    var a = Date.parse(overlay.today + "T00:00:00Z")
    var b = Date.parse(overlay.date + "T00:00:00Z")
    return Math.round((b - a) / 86400000)
  }

  // ---- header ----
  Row {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.spacing.panelPadding
    spacing: Style.spacing.lg

    Text {
      id: dateText
      text: Qt.formatDate(new Date(overlay.date + "T00:00:00Z"), "d MMMM")
      color: overlay.fg
      font.family: overlay.fontFamily
      font.pixelSize: Style.font.display
      font.weight: Font.DemiBold
    }

    Text {
      anchors.baseline: dateText.baseline
      text: Qt.formatDate(new Date(overlay.date + "T00:00:00Z"), "dddd")
      color: overlay.dim
      font.family: overlay.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // The chip says where you are relative to today, because the date alone
    // does not: "11 September" reads the same whether it is today or a week
    // behind you. Centred on the date rather than sat on its baseline, so a
    // bordered box does not hang below the text it belongs to.
    Rectangle {
      anchors.verticalCenter: dateText.verticalCenter
      width: chipText.implicitWidth + Style.spacing.xl
      height: Style.space(16)
      radius: Style.cornerRadius / 3
      color: "transparent"
      border.width: 1
      border.color: pane.dayDelta === 0
        ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.5)
        : (pane.dayDelta < 0
            ? Qt.rgba(overlay.urgent.r, overlay.urgent.g, overlay.urgent.b, 0.4)
            : overlay.line)

      Text {
        id: chipText
        anchors.centerIn: parent
        text: pane.dayDelta === 0 ? "TODAY"
            : (pane.dayDelta < 0 ? (-pane.dayDelta) + "D AGO" : "IN " + pane.dayDelta + "D")
        color: pane.dayDelta === 0 ? overlay.accent
             : (pane.dayDelta < 0 ? overlay.urgent : overlay.dim)
        font.family: overlay.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 0.6
      }
    }
  }

  // ---- the list ----
  Flickable {
    id: scroll
    anchors.top: header.bottom
    anchors.topMargin: Style.spacing.huge
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: addRow.top
    anchors.leftMargin: Style.spacing.panelPadding - Style.spacing.md
    anchors.rightMargin: Style.spacing.panelPadding - Style.spacing.md
    clip: true
    contentHeight: body.height
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: body
      width: scroll.width
      spacing: Style.spacing.md

      // ---- schedule, read-only ----
      Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: overlay.events.length > 0

        SectionHeader {
          width: parent.width
          overlay: pane.overlay
          title: "Schedule"
          trailing: "read-only · calendar"
        }

        Repeater {
          model: overlay.events
          // A rail, not a card. Cards in this UI are things you can edit;
          // these belong to the calendar plugin and cannot be touched here.
          Item {
            width: body.width
            height: Style.space(24)

            Rectangle {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(2)
              height: parent.height - Style.spacing.lg
              radius: 1
              color: modelData.color ? modelData.color : overlay.dim
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md + Style.spacing.xxl
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(40)
              text: modelData.at ? modelData.at : "all day"
              color: overlay.dim
              font.family: overlay.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.md + Style.spacing.xxl + Style.space(46)
              anchors.right: actions.left
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.title
              color: Qt.rgba(overlay.fg.r, overlay.fg.g, overlay.fg.b, 0.8)
              font.family: overlay.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            // The two things you actually do with an event. Read-only still
            // holds: opening a link changes nothing in the calendar.
            Row {
              id: actions
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.md

              PillButton {
                overlay: pane.overlay
                visible: modelData.url !== ""
                label: "join"
                highlight: true
                onActivated: overlay.openExternal(modelData.url)
              }

              PillButton {
                overlay: pane.overlay
                visible: modelData.location !== ""
                label: "map"
                onActivated: overlay.openExternal(Store.mapUrl(modelData.location))
              }
            }
          }
        }
      }

      // ---- carried over ----
      Column {
        width: parent.width
        spacing: Style.spacing.md
        visible: overlay.date === overlay.today && overlay.carried.length > 0

        SectionHeader {
          width: parent.width
          overlay: pane.overlay
          title: (overlay.carriedOpen ? "▾ " : "▸ ") + "Carried over " + overlay.carried.length
          titleClickable: true
          trailing: overlay.carriedOpen ? "move all" : ""
          trailingClickable: true
          onTitleClicked: overlay.carriedOpen = !overlay.carriedOpen
          onTrailingClicked: overlay.moveAllToToday()
        }

        Repeater {
          model: overlay.carriedOpen ? overlay.carried : []
          TaskRow {
            width: body.width
            overlay: pane.overlay
            task: {
              overlay.revision         // dayCache is mutated in place
              var found = overlay.readDay(modelData.date).tasks.filter(function(t) {
                return t.id === modelData.id
              })[0]
              return found || { id: "", text: modelData.text, done: false,
                                note: "", atts: [], subs: [] }
            }
            sourceDate: modelData.date
            selected: overlay.selId === modelData.id && overlay.selDate === modelData.date
            onToggled: overlay.toggleDone(modelData.date, modelData.id)
            onOpened: overlay.select(modelData.date, modelData.id)
            onPulled: overlay.moveToToday(modelData.date, modelData.id)
          }
        }
      }

      // ---- the day's own tasks ----
      Column {
        width: parent.width
        spacing: Style.spacing.md

        SectionHeader {
          width: parent.width
          overlay: pane.overlay
          title: overlay.date === overlay.today ? "Today" : "Tasks"
        }

        Repeater {
          model: overlay.day.tasks
          TaskRow {
            width: body.width
            overlay: pane.overlay
            task: modelData
            selected: overlay.selId === modelData.id && overlay.selDate === overlay.date
            onToggled: overlay.toggleDone(overlay.date, modelData.id)
            onOpened: overlay.select(overlay.date, modelData.id)
          }
        }

        Item {
          width: parent.width
          height: Style.space(70)
          visible: overlay.day.tasks.length === 0

          Column {
            anchors.centerIn: parent
            spacing: Style.spacing.sm
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Nothing here yet."
              color: overlay.dimmer
              font.family: overlay.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "press n to add the first one"
              color: overlay.dimmer
              font.family: overlay.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Item { width: 1; height: Style.spacing.lg }
    }
  }

  // ---- add ----
  Item {
    id: addRow
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.spacing.panelPadding
    anchors.rightMargin: Style.spacing.panelPadding
    anchors.bottomMargin: Style.spacing.panelPadding
    height: Style.space(34)

    Rectangle {
      anchors.top: parent.top
      width: parent.width
      height: 1
      color: overlay.lineSoft
    }

    Text {
      id: plus
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: Style.spacing.xs
      text: "+"
      color: addField.activeFocus ? overlay.accent : overlay.dimmer
      font.family: overlay.fontFamily
      font.pixelSize: Style.font.title
    }

    TextInput {
      id: addField
      anchors.left: plus.right
      anchors.leftMargin: Style.spacing.xl
      anchors.right: hint.left
      anchors.rightMargin: Style.spacing.lg
      anchors.verticalCenter: plus.verticalCenter
      color: overlay.fg
      font.family: overlay.fontFamily
      font.pixelSize: Style.font.body
      selectByMouse: true
      selectionColor: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.3)
      clip: true

      onAccepted: {
        overlay.addTask(text)
        text = ""
      }

      Keys.onEscapePressed: {
        text = ""
        pane.dismissed()
      }

      Text {
        anchors.fill: parent
        visible: !addField.text && !addField.activeFocus
        text: "Add a task…"
        color: overlay.dimmer
        font: addField.font
        verticalAlignment: Text.AlignVCenter
      }
    }

    Text {
      id: hint
      anchors.right: parent.right
      anchors.verticalCenter: plus.verticalCenter
      visible: addField.activeFocus
      text: "⏎"
      color: overlay.dimmer
      font.family: overlay.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      onClicked: addField.forceActiveFocus()
    }
  }
}
