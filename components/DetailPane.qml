import QtQuick
import qs.Commons
import "../lib/Store.js" as Store

// The selected task, in full: its note, its screenshots and its subtasks.
Item {
  id: pane
  required property var overlay

  readonly property var task: overlay.selTask

  // Escape anywhere in here hands the keyboard back to the overlay.
  signal dismissed()

  // Which subtask row is open for editing, or -1. A subtask's editor is a
  // Repeater delegate rather than a field this pane owns, so closing the
  // overlay has no other way to reach it and flush what is in it.
  property int editingAt: -1

  // The stops Tab walks between; step() below holds the order. They are
  // reached explicitly rather than through Qt's own tab navigation because the
  // note has no editor to focus until it is in edit mode: its TextEdit is
  // invisible at rest, and an invisible item cannot take focus.
  //
  // Which is also why each one checks for a task first. With none selected the
  // whole pane is a Flickable with `visible: false`, so every stop in it would
  // silently refuse focus -- Tab would look like it had done nothing and the
  // keyboard would be sitting somewhere neither pane was drawing.
  function focusTitle() {
    if (!pane.task) return
    titleEdit.forceActiveFocus()
  }

  function focusNote() {
    if (!pane.task) return
    overlay.editingNote = true
    Qt.callLater(function() {
      editor.forceActiveFocus()
      editor.cursorPosition = editor.length
    })
  }

  function focusSubAdd() {
    if (!pane.task) return
    subField.forceActiveFocus()
  }

  function focusSub(at) {
    if (!pane.task || at < 0 || at >= pane.task.subs.length) return false
    var row = subRepeater.itemAt(at)
    if (!row) return false
    row.forceActiveFocus()
    return true
  }

  // Tab can reach a row that is below the fold, and a focus ring nobody can
  // see is worse than no focus ring: the next keystroke acts on something off
  // screen. Only ever scrolls as far as it has to, so tabbing through a short
  // list leaves the pane where it was.
  function reveal(item) {
    if (!item || !scroll.contentHeight) return
    var top = item.mapToItem(column, 0, 0).y
    var bottom = top + item.height
    var pad = Style.spacing.lg
    var limit = Math.max(0, scroll.contentHeight - scroll.height)
    if (top - pad < scroll.contentY) {
      scroll.contentY = Math.max(0, top - pad)
    } else if (bottom + pad > scroll.contentY + scroll.height) {
      scroll.contentY = Math.min(limit, bottom + pad - scroll.height)
    }
  }

  function focusFirstSub() { if (!pane.focusSub(0)) pane.focusSubAdd() }
  function focusAfterSub(at) { if (!pane.focusSub(at + 1)) pane.focusSubAdd() }
  function focusLastSub() { if (!pane.focusSub(pane.subCount() - 1)) pane.focusNote() }

  function subCount() { return pane.task ? pane.task.subs.length : 0 }

  // Shift+Tab arrives two ways: a real compositor sends ISO_Left_Tab, which Qt
  // delivers as Key_Backtab, while a synthesised event stays Key_Tab and
  // carries the Shift modifier. Answering only one of them gives you a reverse
  // walk that works by hand but cannot be tested, or one that tests green and
  // does nothing on the keyboard. tests/test_keys.qml pins both.
  function goingBack(event) {
    return !!event && (event.key === Qt.Key_Backtab ||
                       (event.modifiers & Qt.ShiftModifier) !== 0)
  }

  // The ring, in the order the pane reads: title, note, each subtask, the
  // field that adds one, and round. Every stop routes through here so the
  // order lives in one place rather than in eight handlers that have to agree.
  function step(where, at, event) {
    if (pane.goingBack(event)) {
      if (where === "title") pane.focusSubAdd()
      else if (where === "note") pane.focusTitle()
      else if (where === "sub") { if (!pane.focusSub(at - 1)) pane.focusNote() }
      else pane.focusLastSub()
      return
    }
    if (where === "title") pane.focusNote()
    else if (where === "note") pane.focusFirstSub()
    else if (where === "sub") pane.focusAfterSub(at)
    else pane.focusTitle()
  }

  // Committing rebuilds the Repeater and destroys the row being edited, so
  // where the keyboard goes afterwards is the caller's to say -- Enter stays
  // on the row, Tab moves on. Returns whether anything was written.
  function setSubText(at, text) {
    if (!pane.task || at < 0 || at >= pane.task.subs.length) return false
    var value = String(text).trim()
    // Emptying a subtask removes it, down the undoable path so `u` brings it
    // back. Leaving a blank line in a checklist is never what was meant.
    if (!value) { pane.removeSub(at); return true }
    if (value === pane.task.subs[at].text) return false
    overlay.mutateSelected(function(t) { return Store.setSubText(t, at, value) })
    return true
  }

  function toggleSub(at) {
    overlay.mutateSelected(function(t) {
      if (at < 0 || at >= t.subs.length) return t
      t.subs[at].done = !t.subs[at].done
      return t
    })
    // Every edit clones the task, so `subs` comes back as a different array
    // and the Repeater tears down all of its delegates and builds them again
    // -- taking the focused row with them. Without this, ticking a subtask
    // dropped the keyboard on the floor and the second Space, the one that
    // unticks it, went nowhere.
    Qt.callLater(function() { pane.focusSub(at) })
  }

  function removeSub(at) {
    if (!pane.task || at < 0 || at >= pane.task.subs.length) return
    overlay.removeSub(at)
    // The keyboard stays where the eye is: on the row that slid up into the
    // gap, or on the add field when the list ended there. Deferred because
    // the Repeater has not rebuilt its delegates yet at this point, so
    // itemAt() would still hand back the row that was just removed.
    Qt.callLater(function() {
      if (!pane.focusSub(at)) pane.focusSubAdd()
    })
  }

  // close() flushes to disk, so anything still sitting in a debounce has to be
  // committed before that happens rather than after it.
  Connections {
    target: pane.overlay
    function onCommitEdits() {
      titleCommit.triggered()
      noteCommit.triggered()
      if (pane.editingAt >= 0) {
        var row = subRepeater.itemAt(pane.editingAt)
        if (row) row.commitEdit(null)
      }
    }
  }

  // The editors are filled when the selection changes and never bound to the
  // task afterwards. Committing as you type replaces the task object, which
  // would re-run a text binding and could put a stale value back over a
  // character typed in between -- losing it, and moving the cursor.
  readonly property string selKey: overlay.selDate + "/" + overlay.selId
  onSelKeyChanged: pane.syncEditors()
  Component.onCompleted: pane.syncEditors()

  function syncEditors() {
    titleEdit.text = pane.task ? pane.task.text : ""
    editor.text = pane.task ? pane.task.note : ""
  }

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
      // Doubles as the place a failed paste explains itself: pasting with
      // nothing selected is otherwise completely silent.
      text: overlay.pasteError ? overlay.pasteError : "pick one from the day"
      color: overlay.pasteError ? overlay.urgent : overlay.dimmer
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
          color: overlay.fg
          font.family: overlay.fontFamily
          font.pixelSize: Style.font.heading
          font.weight: Font.DemiBold
          wrapMode: Text.Wrap
          selectByMouse: true
          selectionColor: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.3)

          // Saved as you type rather than when focus leaves. Waiting for focus
          // meant a title typed and then abandoned -- by closing the overlay,
          // or by pressing Escape -- was simply thrown away.
          onTextChanged: if (activeFocus) titleCommit.restart()
          onActiveFocusChanged: if (!activeFocus) titleCommit.triggered()

          Timer {
            id: titleCommit
            interval: 200
            onTriggered: {
              if (!pane.task || titleEdit.text === pane.task.text) return
              var value = titleEdit.text
              overlay.mutateSelected(function(t) { t.text = value; return t })
            }
          }

          // Escape leaves the field. It does not undo: the text is already on
          // disk, so reverting here would throw away something already saved.
          // Focus goes back to the overlay rather than nowhere -- dropping it
          // on the floor left the pane looking navigable while every key went
          // unheard.
          Keys.onEscapePressed: {
            titleCommit.triggered()
            pane.dismissed()
          }
          Keys.onTabPressed: function(event) { pane.step("title", -1, event) }
          Keys.onBacktabPressed: function(event) { pane.step("title", -1, event) }
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
            color: overlay.fg
            font.family: overlay.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            selectByMouse: true
            selectionColor: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.3)

            onTextChanged: if (activeFocus) noteCommit.restart()
            onActiveFocusChanged: {
              if (activeFocus) return
              noteCommit.triggered()
              overlay.editingNote = false
            }

            Timer {
              id: noteCommit
              interval: 200
              onTriggered: {
                if (!pane.task || editor.text === pane.task.note) return
                var value = editor.text
                overlay.mutateSelected(function(t) { t.note = value; return t })
              }
            }

            Keys.onEscapePressed: {
              noteCommit.triggered()
              overlay.editingNote = false
              pane.dismissed()
            }

            // A note is the one place Tab could plausibly mean "indent", but
            // Markdown lists here are written with spaces and being unable to
            // leave the field by keyboard is the worse trade.
            Keys.onTabPressed: function(event) { editor.leaveFor("note", -1, event) }
            Keys.onBacktabPressed: function(event) { editor.leaveFor("note", -1, event) }

            function leaveFor(where, at, event) {
              noteCommit.triggered()
              overlay.editingNote = false
              pane.step(where, at, event)
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

                // One click copies, two enlarge. Qt delivers the first click
                // of a double click as a plain click, so the copy waits out the
                // double-click interval rather than firing underneath it.
                MouseArea {
                  id: shotHover
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton

                  Timer {
                    id: copyAfterSingle
                    interval: 220
                    onTriggered: overlay.copyAttachment(modelData)
                  }

                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) overlay.removeAttachment(modelData.sha)
                    else copyAfterSingle.restart()
                  }
                  onDoubleClicked: function(mouse) {
                    copyAfterSingle.stop()
                    overlay.lightboxAt = index
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
          id: subRepeater
          model: pane.task ? pane.task.subs : []

          // Each row is a tab stop of its own, so a subtask can be ticked or
          // removed without a mouse ever reaching for it.
          //
          // Plain properties only, no `required`: a Repeater delegate that
          // declares one stops receiving modelData as a context property and
          // every binding below would read undefined. tests/test_qml.qml pins
          // that; components/TaskRow.qml carries the longer version.
          Item {
            id: subRow
            width: column.width
            height: Style.space(26)

            // subEdit is a child, so focus being in it does not make the row
            // activeFocus. The ring has to ask about both or it goes out the
            // moment you start typing in the line it is drawn around.
            readonly property bool current: subRow.activeFocus || subEdit.activeFocus
            property bool editing: false

            onActiveFocusChanged: if (activeFocus) pane.reveal(subRow)

            function beginEdit() {
              subEdit.text = modelData.text
              subRow.editing = true
              pane.editingAt = index
              Qt.callLater(function() {
                subEdit.forceActiveFocus()
                // At the end, not selected: Enter is reached for to fix a
                // typo far more often than to replace the whole line, and a
                // select-all loses the line to the first keystroke.
                subEdit.cursorPosition = subEdit.length
              })
            }

            // `then` runs after the write has been absorbed. Committing clones
            // the task, which rebuilds this Repeater and destroys the very row
            // running this function, so nothing after the call can assume it
            // still exists.
            function commitEdit(then) {
              if (!subRow.editing) return
              subRow.editing = false
              pane.editingAt = -1
              var at = index
              pane.setSubText(at, subEdit.text)
              if (then) Qt.callLater(then)
            }

            // Behind the row rather than around it, so a long subtask keeps
            // the whole width for its text.
            Rectangle {
              anchors.fill: parent
              anchors.rightMargin: Style.spacing.sm
              radius: Style.cornerRadius / 2
              visible: subRow.current || subHover.containsMouse
              color: subRow.current
                ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.08)
                : Qt.rgba(overlay.fg.r, overlay.fg.g, overlay.fg.b, 0.03)
              border.width: 1
              border.color: subRow.editing
                ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.7)
                : (subRow.current
                    ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.35)
                    : "transparent")
            }

            // A focused row is a cursor position, not an editor, so the keys
            // that mean something here are handled here. The overlay's own
            // handler is deliberately not reached: it only fires while the
            // key catcher holds focus, and forwarding to it would let `j`/`k`
            // change the selected task -- which rebuilds this very list and
            // leaves the keyboard on a row that no longer exists.
            Keys.onPressed: function(event) {
              // The same guard the overlay needs, one level down: subEdit is a
              // child, so anything it declines -- Up, Down, and Left or Right
              // at the ends of the line -- arrives here and would tick or
              // delete the row being typed into.
              if (!subRow.activeFocus) return
              switch (event.key) {
              case Qt.Key_Return:
              case Qt.Key_Enter:
                subRow.beginEdit(); event.accepted = true; return
              case Qt.Key_Space:
                pane.toggleSub(index); event.accepted = true; return
              case Qt.Key_Backspace:
              case Qt.Key_Delete:
                // Ctrl, deliberately: a bare Backspace is what fingers reach
                // for to fix a typo, and on a focused row it would instead
                // take the whole line away.
                if (event.modifiers & Qt.ControlModifier) {
                  pane.removeSub(index)
                  event.accepted = true
                }
                return
              case Qt.Key_J:
              case Qt.Key_Down:
                pane.focusAfterSub(index); event.accepted = true; return
              case Qt.Key_K:
              case Qt.Key_Up:
                pane.focusSub(index - 1); event.accepted = true; return
              case Qt.Key_U:
                // Reachable from here on purpose: the row you just deleted
                // leaves the keyboard on its neighbour, which is exactly where
                // you are standing when you want it back.
                //
                // The undo has to be followed home. Restoring rebuilds this
                // Repeater and destroys the row the keyboard is standing on,
                // so without this `u` brought the subtask back and left every
                // key after it going nowhere.
                var entry = overlay.undoEntry
                if (entry) {
                  overlay.undoDelete()
                  if (entry.kind === "sub") {
                    Qt.callLater(function() { pane.focusSub(entry.at) })
                  } else {
                    // A whole task came back and the selection moved to it.
                    // This pane is showing something else now.
                    pane.dismissed()
                  }
                }
                event.accepted = true; return
              case Qt.Key_Q:
                overlay.close(); event.accepted = true; return
              }
            }

            Keys.onTabPressed: function(event) { pane.step("sub", index, event) }
            Keys.onBacktabPressed: function(event) { pane.step("sub", index, event) }
            Keys.onEscapePressed: pane.dismissed()

            Rectangle {
              id: subBox
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.sm
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

              // Reaches past the box it draws: 13px is a fair target to look
              // at and a poor one to hit.
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.spacing.md
                onClicked: {
                  subRow.forceActiveFocus()
                  pane.toggleSub(index)
                }
              }
            }

            Text {
              visible: !subRow.editing
              anchors.left: subBox.right
              anchors.leftMargin: Style.spacing.xl
              anchors.right: subRemove.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.text
              color: modelData.done ? overlay.dimmer : overlay.fg
              font.family: overlay.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.strikeout: modelData.done
              elide: Text.ElideRight
            }

            TextInput {
              id: subEdit
              visible: subRow.editing
              anchors.left: subBox.right
              anchors.leftMargin: Style.spacing.xl
              anchors.right: subRemove.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              color: overlay.fg
              font.family: overlay.fontFamily
              font.pixelSize: Style.font.bodySmall
              selectByMouse: true
              selectionColor: Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.3)
              clip: true

              // Enter finishes and leaves the keyboard on the row it just
              // edited, so a second Enter starts editing it again and Space
              // ticks it. Escape does the same: the line has been typed, and
              // throwing it away because of the key that means "done editing"
              // elsewhere in this pane would be a trap.
              onAccepted: subRow.commitEdit(function() { pane.focusSub(index) })
              Keys.onEscapePressed: subRow.commitEdit(function() { pane.focusSub(index) })

              Keys.onTabPressed: function(event) {
                subRow.commitEdit(function() { pane.step("sub", index, event) })
              }
              Keys.onBacktabPressed: function(event) {
                subRow.commitEdit(function() { pane.step("sub", index, event) })
              }

              // Clicking away is a commit too, not an abandon.
              onActiveFocusChanged: if (!activeFocus) subRow.commitEdit(null)
            }

            // A box with the glyph centred in it, not a bare Text anchored to
            // an edge: "×" carries its own side bearings, so anchoring the
            // text itself left it sitting off-centre and a different distance
            // from the edge than the tick on the other side.
            Item {
              id: subRemove
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: Style.space(18)
              visible: subRow.current || subRow.editing
                       || subHover.containsMouse || removeHover.containsMouse

              Text {
                anchors.centerIn: parent
                text: "×"
                color: removeHover.containsMouse ? overlay.urgent : overlay.dim
                font.family: overlay.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: removeHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: pane.removeSub(index)
              }
            }

            // The same rule as a task row: one click puts the keyboard here,
            // two copy the line. Ticking is the box's job alone -- it used to
            // be the whole row's, which left nowhere to hang a copy that did
            // not also toggle something twice on the way.
            MouseArea {
              id: subHover
              anchors.fill: parent
              anchors.rightMargin: Style.space(26)
              hoverEnabled: true
              enabled: !subRow.editing
              onClicked: subRow.forceActiveFocus()
              onDoubleClicked: overlay.copyText("sub:" + overlay.selId + ":" + index,
                                                modelData.text)
            }
          }
        }

        Item {
          id: subAddRow
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

            onActiveFocusChanged: if (activeFocus) pane.reveal(subAddRow)

            // The mirror of Down off the last row. Without it the add field is
            // a one-way door: Tab wraps to the title and there is no way back
            // up into the list.
            Keys.onUpPressed: pane.focusSub(pane.task ? pane.task.subs.length - 1 : -1)

            onAccepted: {
              var value = text.trim()
              if (!value) return
              overlay.mutateSelected(function(t) {
                t.subs.push({ text: value, done: false })
                return t
              })
              text = ""
            }

            // Wraps to the title rather than falling out of the pane: Escape
            // is the way out, and one key doing one thing is easier to keep
            // hold of than Tab meaning "next" until it suddenly means "leave".
            Keys.onTabPressed: function(event) { pane.step("add", -1, event) }
            Keys.onBacktabPressed: function(event) { pane.step("add", -1, event) }

            Keys.onEscapePressed: {
              text = ""
              pane.dismissed()
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
