import QtQuick
import qs.Commons

// The selected task, in full: its note, its screenshots and its subtasks.
Item {
  id: pane
  required property var overlay

  readonly property var task: overlay.selTask

  Text {
    id: paneLabel
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.margins: Style.spacing.panelPadding
    text: "DETAIL"
    color: overlay.dimmer
    font.family: overlay.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.1
  }

  // ---- nothing selected ----
  Column {
    anchors.centerIn: parent
    spacing: Style.spacing.sm
    visible: !pane.task
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "No task selected."
      color: overlay.dimmer
      font.family: overlay.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "pick one from the day"
      color: overlay.dimmer
      font.family: overlay.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Flickable {
    id: scroll
    anchors.top: paneLabel.bottom
    anchors.topMargin: Style.spacing.lg
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.spacing.panelPadding
    anchors.rightMargin: Style.spacing.panelPadding
    anchors.bottomMargin: Style.spacing.panelPadding
    visible: !!pane.task
    clip: true
    contentHeight: column.height
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: column
      width: scroll.width
      spacing: Style.spacing.huge

      // ---- title and provenance ----
      Column {
        width: parent.width
        spacing: Style.spacing.sm

        TextEdit {
          id: titleEdit
          width: parent.width
          text: pane.task ? pane.task.text : ""
          color: overlay.fg
          font.family: overlay.fontFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
          wrapMode: Text.Wrap
          selectByMouse: true
          selectionColor: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.3)

          onActiveFocusChanged: {
            if (!activeFocus && pane.task && text !== pane.task.text) {
              var value = text
              overlay.mutateSelected(function(t) { t.text = value; return t })
            }
          }
          Keys.onEscapePressed: {
            text = pane.task ? pane.task.text : ""
            focus = false
          }
        }

        Row {
          spacing: Style.spacing.xxl

          Text {
            text: pane.task
              ? "created " + Qt.formatDate(new Date(pane.task.created + "T00:00:00Z"), "d MMM")
              : ""
            color: overlay.dimmer
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            // Only worth saying while it is still open: a finished task's age
            // is history, not a problem.
            visible: pane.task && !pane.task.done && overlay.selDate < overlay.today
            text: {
              if (!pane.task) return ""
              var a = Date.parse(overlay.selDate + "T00:00:00Z")
              var b = Date.parse(overlay.today + "T00:00:00Z")
              var days = Math.round((b - a) / 86400000)
              return days + (days === 1 ? " day overdue" : " days overdue")
            }
            color: overlay.urgent
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: pane.task && pane.task.done
            text: "done"
            color: overlay.accent
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      // ---- note ----
      Column {
        width: parent.width
        spacing: Style.spacing.lg

        Text {
          text: "NOTE"
          color: overlay.dimmer
          font.family: overlay.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.1
        }

        // Rendered at rest, editable on click. One control: a preview/edit
        // toggle would be a mode to remember, and Text renders CommonMark on
        // its own so there is no library to carry.
        Item {
          width: parent.width
          height: overlay.editingNote ? editor.implicitHeight + Style.spacing.xxl
                                      : Math.max(rendered.implicitHeight, Style.space(20))

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Style.space(2)
            visible: !overlay.editingNote
            color: noteHover.containsMouse
              ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.5)
              : overlay.line
          }

          Text {
            id: rendered
            visible: !overlay.editingNote
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.xxl
            anchors.right: parent.right
            text: pane.task && pane.task.note
              ? pane.task.note
              : "_Click to write a note — Markdown, rendered right here._"
            textFormat: Text.MarkdownText
            color: pane.task && pane.task.note
              ? Qt.rgba(overlay.fg.r, overlay.fg.g, overlay.fg.b, 0.85) : overlay.dimmer
            linkColor: overlay.accent
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap

            MouseArea {
              id: noteHover
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                overlay.editingNote = true
                Qt.callLater(function() {
                  editor.forceActiveFocus()
                  editor.cursorPosition = editor.length
                })
              }
            }
          }

          Rectangle {
            anchors.fill: parent
            visible: overlay.editingNote
            radius: Style.cornerRadius / 2
            color: Qt.rgba(0, 0, 0, 0.25)
            border.width: 1
            border.color: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.4)
          }

          TextEdit {
            id: editor
            visible: overlay.editingNote
            anchors.fill: parent
            anchors.margins: Style.spacing.xl
            text: pane.task ? pane.task.note : ""
            color: overlay.fg
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            selectByMouse: true
            selectionColor: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.3)

            onActiveFocusChanged: {
              if (activeFocus) return
              var value = text
              if (pane.task && value !== pane.task.note) {
                overlay.mutateSelected(function(t) { t.note = value; return t })
              }
              overlay.editingNote = false
            }
            Keys.onEscapePressed: {
              text = pane.task ? pane.task.note : ""
              overlay.editingNote = false
            }
          }
        }
      }

      // ---- attachments ----
      Column {
        width: parent.width
        spacing: Style.spacing.lg

        Text {
          text: "ATTACHMENTS"
          color: overlay.dimmer
          font.family: overlay.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.1
        }

        Flow {
          width: parent.width
          spacing: Style.spacing.xl

          Repeater {
            model: pane.task ? pane.task.atts : []

            Column {
              id: shot
              spacing: Style.spacing.sm

              Rectangle {
                width: Style.space(132)
                height: Style.space(84)
                radius: Style.cornerRadius / 2
                color: Qt.rgba(0, 0, 0, 0.3)
                border.width: 1
                border.color: shotHover.containsMouse
                  ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.5)
                  : overlay.line
                clip: true

                Image {
                  anchors.fill: parent
                  anchors.margins: 1
                  // Thumbnails only. The original is loaded once, by the
                  // lightbox, and never by a list.
                  source: overlay.thumbUrl(modelData)
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  sourceSize.width: Style.space(264)
                }

                MouseArea {
                  id: shotHover
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) overlay.removeAttachment(modelData.sha)
                    else overlay.lightboxAt = index
                  }
                }

                Rectangle {
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.spacing.sm
                  width: Style.space(16)
                  height: Style.space(16)
                  radius: width / 2
                  visible: shotHover.containsMouse
                  color: Qt.rgba(0, 0, 0, 0.65)
                  Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: overlay.fg
                    font.family: overlay.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: overlay.removeAttachment(modelData.sha)
                  }
                }
              }

              Text {
                text: modelData.w + "×" + modelData.h
                color: overlay.dimmer
                font.family: overlay.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // ---- paste target ----
          Column {
            spacing: Style.spacing.sm

            Rectangle {
              width: Style.space(132)
              height: Style.space(84)
              radius: Style.cornerRadius / 2
              color: pasteHover.containsMouse
                ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.05) : "transparent"
              border.width: 1
              border.color: pasteHover.containsMouse
                ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.5) : overlay.line

              Column {
                anchors.centerIn: parent
                spacing: Style.spacing.sm
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "⌃V"
                  color: pasteHover.containsMouse ? overlay.accent : overlay.dimmer
                  font.family: overlay.fontFamily
                  font.pixelSize: Style.font.title
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "paste image"
                  color: pasteHover.containsMouse ? overlay.accent : overlay.dimmer
                  font.family: overlay.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              MouseArea {
                id: pasteHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: overlay.pasteImage()
              }
            }

            Text {
              width: Style.space(132)
              visible: overlay.pasteError !== ""
              text: overlay.pasteError
              color: overlay.urgent
              font.family: overlay.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }
          }
        }
      }

      // ---- subtasks ----
      Column {
        width: parent.width
        spacing: Style.spacing.md

        Text {
          text: "SUBTASKS"
          color: overlay.dimmer
          font.family: overlay.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.1
        }

        Repeater {
          model: pane.task ? pane.task.subs : []

          Item {
            width: column.width
            height: Style.space(24)

            Rectangle {
              id: subBox
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(13)
              height: Style.space(13)
              radius: Style.cornerRadius / 4
              color: modelData.done
                ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.13) : "transparent"
              border.width: 1
              border.color: modelData.done
                ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.6)
                : Qt.rgba(overlay.fg.r, overlay.fg.g, overlay.fg.b, 0.25)

              Text {
                anchors.centerIn: parent
                visible: modelData.done
                text: "✓"
                color: overlay.accent
                font.family: overlay.fontFamily
                font.pixelSize: Style.space(8)
              }
            }

            Text {
              anchors.left: subBox.right
              anchors.leftMargin: Style.spacing.xl
              anchors.right: subRemove.left
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.text
              color: modelData.done ? overlay.dimmer : overlay.fg
              font.family: overlay.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.strikeout: modelData.done
              elide: Text.ElideRight
            }

            Text {
              id: subRemove
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: subHover.containsMouse
              text: "×"
              color: overlay.dim
              font.family: overlay.fontFamily
              font.pixelSize: Style.font.bodySmall
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.spacing.sm
                onClicked: {
                  var at = index
                  overlay.mutateSelected(function(t) {
                    t.subs.splice(at, 1)
                    return t
                  })
                }
              }
            }

            MouseArea {
              id: subHover
              anchors.fill: parent
              anchors.rightMargin: Style.space(20)
              hoverEnabled: true
              onClicked: {
                var at = index
                overlay.mutateSelected(function(t) {
                  t.subs[at].done = !t.subs[at].done
                  return t
                })
              }
            }
          }
        }

        Item {
          width: column.width
          height: Style.space(24)

          Rectangle {
            id: addBox
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(13)
            height: Style.space(13)
            radius: Style.cornerRadius / 4
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(overlay.fg.r, overlay.fg.g, overlay.fg.b, 0.15)
          }

          TextInput {
            id: subField
            anchors.left: addBox.right
            anchors.leftMargin: Style.spacing.xl
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: overlay.fg
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.bodySmall
            selectByMouse: true
            clip: true

            onAccepted: {
              var value = text.trim()
              if (!value) return
              overlay.mutateSelected(function(t) {
                t.subs.push({ text: value, done: false })
                return t
              })
              text = ""
            }

            Text {
              anchors.fill: parent
              visible: !subField.text && !subField.activeFocus
              text: "Add subtask…"
              color: overlay.dimmer
              font: subField.font
              verticalAlignment: Text.AlignVCenter
            }
          }
        }
      }

      Item { width: 1; height: Style.spacing.lg }
    }
  }
}
