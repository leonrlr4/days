import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "lib/Store.js" as Store
import "components"

// Days: a task list that belongs to a day.
//
// Three panes -- the month, the day, the selected task -- and a store of one
// JSON file per day underneath. The index file beside those days answers every
// count this UI shows, so opening, changing day, ticking a box and typing all
// stay inside QML with no subprocess anywhere. The one exception is pasting an
// image, which scripts/paste-image handles.
Item {
  id: root

  // Injected by the host shell for plugins that declare it. Scoped to this
  // plugin's own id, which is all the bar widget needs to reopen us.
  property var shell: null

  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/leonrlr4.days"
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/leonrlr4.days"
  // The calendar plugin's own read-only bridge. It is documented upstream as
  // never invoking sync, push or create, which is the only reason it is safe
  // to call from here.
  readonly property string eventsScript: Quickshell.env("HOME") +
    "/.config/omarchy/plugins/omarchy-google-calendar-clock/scripts/calendar-events"

  // ---- state ---------------------------------------------------------------
  property bool opened: false
  property string today: Store.todayIso()
  property string date: today
  property string month: Store.monthOf(today)
  property var index: Store.emptyIndex()
  property var day: Store.emptyDay(today)

  // Selection is (date, id), not id alone: a carried-over task is shown on
  // today's pane but still lives in an earlier day's file, and edits to it
  // have to land there.
  property string selDate: ""
  property string selId: ""

  property bool carriedOpen: true
  property int lightboxAt: -1
  property bool editingNote: false
  property var undoEntry: null
  property var events: []
  property string eventsWanted: ""
  property string pasteError: ""

  // Days are plain JS objects held in a property var, and mutateDay assigns
  // into that object rather than replacing it -- which notifies nothing. Any
  // binding that reads a day through dayCache has to depend on this counter,
  // or it goes on rendering the task as it was before the edit.
  // tests/test_qml.qml pins the behaviour.
  property int revision: 0

  property var dayCache: ({})
  property var eventCache: ({})
  property var dirtyDates: ({})

  readonly property var carried: Store.carriedOver(root.index, root.today)
  readonly property var selTask: {
    root.revision                      // re-evaluate after every edit
    if (!root.selId) return null
    var d = root.readDay(root.selDate)
    for (var i = 0; i < d.tasks.length; i++) {
      if (d.tasks[i].id === root.selId) return d.tasks[i]
    }
    return null
  }

  // ---- theme ---------------------------------------------------------------
  readonly property color bg: Color.menu.background
  readonly property color fg: Color.menu.text
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color line: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
  readonly property color lineSoft: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
  readonly property color dim: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.55)
  readonly property color dimmer: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.34)
  readonly property color raised: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)
  readonly property string fontFamily: Style.font.menuFamily

  // ---- lifecycle -----------------------------------------------------------
  function open(payloadJson) {
    root.today = Store.todayIso()
    root.opened = true
    root.lightboxAt = -1
    root.editingNote = false
    root.pasteError = ""
    root.goToDate(root.today)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.flush()
    root.editingNote = false
    root.lightboxAt = -1
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  Component.onCompleted: root.loadIndex()

  // ---- reading -------------------------------------------------------------
  function dayPath(date) { return root.dataDir + "/days/" + date + ".json" }

  // Blocking on purpose: a day file is a couple of kilobytes, and reading it
  // synchronously is what keeps h/l from flashing an empty pane before the
  // real one arrives.
  function readDay(date) {
    if (!date) return Store.emptyDay("")
    if (root.dayCache[date]) return root.dayCache[date]
    dayReader.path = root.dayPath(date)
    var parsed = Store.parseDay(dayReader.text(), date)
    root.dayCache[date] = parsed
    return parsed
  }

  function goToDate(date) {
    root.date = date
    root.month = Store.monthOf(date)
    root.day = root.readDay(date)
    root.editingNote = false
    root.lightboxAt = -1
    if (!root.selId || root.selDate !== date) {
      var first = root.day.tasks.length ? root.day.tasks[0] : null
      root.selDate = date
      root.selId = first ? first.id : ""
    }
    root.loadEvents(date)
  }

  function select(date, id) {
    root.selDate = date
    root.selId = id
    root.editingNote = false
    root.lightboxAt = -1
  }

  // ---- writing -------------------------------------------------------------
  // One entry point for every change. It keeps the in-memory day, the cache
  // and the index in step, and leaves the file write to the debounce below.
  function mutateDay(date, fn) {
    var next = fn(root.readDay(date))
    root.dayCache[date] = next
    root.revision++
    if (date === root.date) root.day = next
    root.index = Store.applyDay(root.index, next)
    var dirty = root.dirtyDates
    dirty[date] = true
    root.dirtyDates = dirty
    writeTimer.restart()
  }

  function mutateSelected(fn) {
    if (!root.selId) return
    var id = root.selId
    root.mutateDay(root.selDate, function(d) { return Store.updateTask(d, id, fn) })
  }

  function flush() {
    writeTimer.stop()
    var dirty = root.dirtyDates
    var wrote = false
    for (var date in dirty) {
      if (!dirty[date]) continue
      dayWriter.path = root.dayPath(date)
      dayWriter.setText(JSON.stringify(root.dayCache[date]) + "\n")
      wrote = true
    }
    root.dirtyDates = ({})
    if (wrote) indexFile.setText(JSON.stringify(root.index) + "\n")
  }

  Timer {
    id: writeTimer
    interval: 400
    onTriggered: root.flush()
  }

  // ---- index ---------------------------------------------------------------
  function loadIndex() {
    indexFile.path = root.dataDir + "/index.json"
    var raw = indexFile.text()
    var parsed = null
    try {
      parsed = raw ? JSON.parse(raw) : null
    } catch (e) {
      parsed = null
    }
    if (parsed && parsed.v === 1 && parsed.days && parsed.blobs) {
      root.index = parsed
      return
    }
    // Missing or from an older schema. Rebuilding is the one path that reads
    // every day file, and it runs only here.
    listDays.running = true
  }

  function rebuildFrom(names) {
    var days = []
    for (var i = 0; i < names.length; i++) {
      var name = names[i].trim()
      if (!/^\d{4}-\d{2}-\d{2}\.json$/.test(name)) continue
      var date = name.slice(0, 10)
      dayReader.path = root.dataDir + "/days/" + name
      days.push(Store.parseDay(dayReader.text(), date))
    }
    root.index = Store.rebuildIndex(days)
    indexFile.setText(JSON.stringify(root.index) + "\n")
    root.dayCache = ({})
    if (root.opened) root.goToDate(root.date)
  }

  // ---- editing -------------------------------------------------------------
  function addTask(text) {
    var trimmed = text.trim()
    if (!trimmed) return
    var date = root.date
    var task = Store.newTask(trimmed, date)
    root.mutateDay(date, function(d) {
      var next = { v: d.v, date: d.date, tasks: d.tasks.slice() }
      next.tasks.push(task)
      return next
    })
    root.select(date, task.id)
  }

  function toggleDone(date, id) {
    root.mutateDay(date, function(d) {
      return Store.updateTask(d, id, function(t) { t.done = !t.done; return t })
    })
  }

  function moveToToday(date, id) {
    if (date === root.today) return
    var from = root.readDay(date)
    var to = root.readDay(root.today)
    var moved = Store.moveTask(from, to, id)

    root.dayCache[date] = moved.from
    root.dayCache[root.today] = moved.to
    root.revision++
    root.index = Store.applyDay(Store.applyDay(root.index, moved.from), moved.to)
    var dirty = root.dirtyDates
    dirty[date] = true
    dirty[root.today] = true
    root.dirtyDates = dirty
    if (root.date === date) root.day = moved.from
    if (root.date === root.today) root.day = moved.to
    if (root.selId === id) root.selDate = root.today
    writeTimer.restart()
  }

  function moveAllToToday() {
    var list = root.carried.slice()
    for (var i = 0; i < list.length; i++) root.moveToToday(list[i].date, list[i].id)
  }

  function deleteSelected() {
    if (!root.selId) return
    var date = root.selDate
    var id = root.selId
    var result = Store.deleteTask(root.readDay(date), id)
    if (!result.removed) return
    root.undoEntry = { date: date, task: result.removed, at: result.at }
    root.mutateDay(date, function() { return result.day })
    var list = root.readDay(root.date).tasks
    var fallback = list.length ? list[Math.min(result.at, list.length - 1)] : null
    root.select(root.date, fallback ? fallback.id : "")
  }

  function undoDelete() {
    var entry = root.undoEntry
    if (!entry) return
    root.undoEntry = null
    root.mutateDay(entry.date, function(d) {
      return Store.restoreTask(d, entry.task, entry.at)
    })
    root.select(entry.date, entry.task.id)
  }

  function moveSelection(delta) {
    var list = root.day.tasks
    if (!list.length) return
    var at = -1
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === root.selId && root.selDate === root.date) { at = i; break }
    }
    var next = at < 0 ? (delta > 0 ? 0 : list.length - 1)
                      : Math.max(0, Math.min(list.length - 1, at + delta))
    root.select(root.date, list[next].id)
  }

  // ---- attachments ---------------------------------------------------------
  function pasteImage() {
    if (!root.selId) {
      root.pasteError = "select a task first — an image attaches to one"
      return
    }
    if (pasteProc.running) return
    root.pasteError = ""
    pasteProc.running = true
  }

  function attachmentPasted(line) {
    var result = Store.parsePaste(line)
    if (!result.ok) {
      root.pasteError = result.error
      return
    }
    var id = root.selId
    root.mutateDay(root.selDate, function(d) { return Store.addAttachment(d, id, result.att) })
  }

  function removeAttachment(sha) {
    if (!root.selId) return
    var id = root.selId
    var before = root.index
    root.mutateDay(root.selDate, function(d) { return Store.removeAttachment(d, id, sha) })
    root.lightboxAt = -1
    // Only when the last reference is gone, and even then the collector
    // re-derives the count from the day files before unlinking anything.
    if (Store.blobsFreed(before, root.index).indexOf(sha) >= 0) {
      root.flush()
      collectProc.command = [root.pluginDir + "/scripts/gc-blobs", "--dir", root.dataDir, "--sha", sha]
      collectProc.running = true
    }
  }

  function blobUrl(att) {
    return "file://" + root.dataDir + "/blobs/" + att.sha + "." + att.ext
  }

  function thumbUrl(att) {
    return "file://" + root.dataDir + "/thumbs/" + att.sha + ".webp"
  }

  // ---- the day's events ----------------------------------------------------
  // The calendar plugin answers in about 2.4 seconds, so the day's events are
  // kept on disk and shown immediately while a fresh answer is fetched behind
  // them. Holding l must not queue a subprocess per day either, hence the
  // debounce and the single flight below.
  function eventPath(date) { return root.dataDir + "/events/" + date + ".json" }

  function loadEvents(date) {
    if (root.eventCache[date]) {
      root.events = root.eventCache[date]
    } else {
      eventReader.path = root.eventPath(date)
      var cached = Store.parseEventCache(eventReader.text())
      root.events = cached ? cached.events : []
      if (cached) root.eventCache[date] = cached.events
    }
    root.eventsWanted = date
    eventDebounce.restart()
  }

  function fetchEvents() {
    var date = root.eventsWanted
    if (!date || eventsProc.running) return
    eventsProc.date = date
    eventsProc.command = [root.eventsScript, date, date]
    eventsProc.running = true
  }

  function eventsArrived(date, text) {
    var list = Store.parseEvents(text)
    root.eventCache[date] = list
    eventWriter.path = root.eventPath(date)
    eventWriter.setText(JSON.stringify(Store.eventCacheDoc(list, new Date().toISOString())) + "\n")
    if (root.date === date) root.events = list
    // The day may have moved on while that was in flight.
    if (root.eventsWanted !== date) eventDebounce.restart()
  }

  // ---- files and processes -------------------------------------------------
  FileView {
    id: indexFile
    blockLoading: true
    blockAllReads: true
    atomicWrites: true
    printErrors: false
  }

  // One reader, repointed as needed. Day files are read through text() with
  // blockLoading, so there is no signal to wait on.
  // blockAllReads, not just blockLoading: blockLoading covers the first load
  // and leaves later ones asynchronous, so repointing this at another day and
  // reading it would hand back the day before. tests/test_fileview.qml pins it.
  FileView {
    id: dayReader
    blockLoading: true
    blockAllReads: true
    printErrors: false
  }

  FileView {
    id: dayWriter
    atomicWrites: true
    printErrors: false
  }

  Process {
    id: listDays
    command: ["ls", "-1", root.dataDir + "/days"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.rebuildFrom(text.split("\n"))
    }
  }

  Process {
    id: pasteProc
    command: [root.pluginDir + "/scripts/paste-image", "--dir", root.dataDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.attachmentPasted(text)
    }
  }

  Process {
    id: collectProc
  }

  Process {
    id: eventsProc
    property string date: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.eventsArrived(eventsProc.date, text)
    }
  }

  Timer {
    id: eventDebounce
    interval: 250
    onTriggered: root.fetchEvents()
  }

  FileView {
    id: eventReader
    blockLoading: true
    blockAllReads: true
    printErrors: false
  }

  FileView {
    id: eventWriter
    atomicWrites: true
    printErrors: false
  }

  // ---- the surface ---------------------------------------------------------
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-days"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    Rectangle {
      id: card
      width: Math.min(Style.space(1120), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(664), panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      color: root.bg
      radius: Style.cornerRadius
      border.width: 1
      border.color: Color.menu.border

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          if (root.lightboxAt >= 0) {
            root.lightboxAt = -1
            event.accepted = true
            return
          }
          switch (event.key) {
          case Qt.Key_Escape:
            root.close(); event.accepted = true; return
          case Qt.Key_J:
          case Qt.Key_Down:
            root.moveSelection(1); event.accepted = true; return
          case Qt.Key_K:
          case Qt.Key_Up:
            root.moveSelection(-1); event.accepted = true; return
          case Qt.Key_H:
          case Qt.Key_Left:
            root.goToDate(Store.shiftIso(root.date, -1)); event.accepted = true; return
          case Qt.Key_L:
          case Qt.Key_Right:
            root.goToDate(Store.shiftIso(root.date, 1)); event.accepted = true; return
          case Qt.Key_T:
            root.goToDate(root.today); event.accepted = true; return
          case Qt.Key_N:
            dayPane.focusAdd(); event.accepted = true; return
          case Qt.Key_Space:
            if (root.selId) root.toggleDone(root.selDate, root.selId)
            event.accepted = true; return
          case Qt.Key_U:
            root.undoDelete(); event.accepted = true; return
          case Qt.Key_D:
            // dd, the way vim spells it: a single d is not enough to delete.
            if (deleteArmed.running) {
              deleteArmed.stop()
              root.deleteSelected()
            } else {
              deleteArmed.restart()
            }
            event.accepted = true; return
          case Qt.Key_V:
            if (event.modifiers & Qt.ControlModifier) {
              root.pasteImage()
              event.accepted = true
              return
            }
            break
          case Qt.Key_Insert:
            // Omarchy's SUPER+V is "Universal paste": it forwards Ctrl+V, or
            // Shift+Insert when it decides the focused window is a terminal.
            // An overlay is a layer surface, not a window, so that check sees
            // whatever was focused behind us -- usually a terminal. Accepting
            // both is what makes SUPER+V work in here.
            if (event.modifiers & Qt.ShiftModifier) {
              root.pasteImage()
              event.accepted = true
              return
            }
            break
          }
        }

        Timer { id: deleteArmed; interval: 600 }

        // ---- three panes -----------------------------------------------
        Row {
          anchors.fill: parent
          anchors.bottomMargin: Style.space(34)

          MonthPane {
            id: monthPane
            width: Style.space(228)
            height: parent.height
            overlay: root
          }

          Rectangle { width: 1; height: parent.height; color: root.lineSoft }

          DayPane {
            id: dayPane
            width: Style.space(392)
            height: parent.height
            overlay: root
            onDismissed: keyCatcher.forceActiveFocus()
          }

          Rectangle { width: 1; height: parent.height; color: root.lineSoft }

          DetailPane {
            width: parent.width - Style.space(228) - Style.space(392) - 2
            height: parent.height
            overlay: root
          }
        }

        // ---- footer ----------------------------------------------------
        Row {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.space(34)
          leftPadding: Style.spacing.panelPadding
          rightPadding: Style.spacing.panelPadding
          spacing: Style.spacing.xxl

          Repeater {
            model: [
              { k: "j k", v: "move" },
              { k: "space", v: "done" },
              { k: "h l", v: "day" },
              { k: "t", v: "today" },
              { k: "n", v: "new" },
              { k: "ctrl+v", v: "paste image" },
              { k: "dd", v: "delete" },
              { k: "u", v: "undo" }
            ]
            Row {
              spacing: Style.spacing.sm
              height: Style.space(34)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.k
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.v
                color: root.dimmer
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---- lightbox ---------------------------------------------------
        Loader {
          anchors.fill: parent
          active: root.lightboxAt >= 0 && root.selTask
                  && root.lightboxAt < root.selTask.atts.length
          sourceComponent: Rectangle {
            color: Qt.rgba(0, 0, 0, 0.88)
            MouseArea { anchors.fill: parent; onClicked: root.lightboxAt = -1 }
            Image {
              anchors.centerIn: parent
              width: Math.min(sourceSize.width, parent.width - Style.space(80))
              height: sourceSize.height > 0
                ? width * (sourceSize.height / sourceSize.width) : 0
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: false
              source: root.selTask ? root.blobUrl(root.selTask.atts[root.lightboxAt]) : ""
            }
          }
        }
      }
    }
  }
}
