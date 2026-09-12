import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt.labs.folderlistmodel
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
  // What was just put on the clipboard, so the corner can say so. One key for
  // images and text alike: "att:<sha>" or "task:<id>" / "sub:<id>:<n>".
  property string copiedKey: ""

  // Saving is continuous, so the only question worth answering on screen is
  // whether it has caught up. Unsaved while anything is pending, then "saved"
  // for a moment so a change you just made visibly lands.
  readonly property bool unsaved: Object.keys(root.dirtyDates).length > 0
  property bool justSaved: false

  // Days are plain JS objects held in a property var, and mutateDay assigns
  // into that object rather than replacing it -- which notifies nothing. Any
  // binding that reads a day through dayCache has to depend on this counter,
  // or it goes on rendering the task as it was before the edit.
  // tests/test_qml.qml pins the behaviour.
  property int revision: 0

  property bool rebuilding: false
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

  // Anything still in an editor's debounce is committed first: flushing before
  // asking for it would write the day as it was a moment ago.
  signal commitEdits()

  function close() {
    dayPane.commitEdit()
    root.commitEdits()
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
    if (wrote) {
      indexFile.setText(JSON.stringify(root.index) + "\n")
      root.justSaved = true
      savedTimer.restart()
    }
  }

  // Short enough that a change is on disk before you have finished reacting to
  // it, long enough that holding a key does not write once per character.
  Timer {
    id: writeTimer
    interval: 250
    onTriggered: root.flush()
  }

  Timer {
    id: savedTimer
    interval: 1600
    onTriggered: root.justSaved = false
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
    root.rebuilding = true
    // Cleared first so re-assigning the same folder still counts as a change:
    // FolderListModel emits nothing when the value is identical, and the
    // rebuild would silently never run.
    dayFiles.folder = ""
    dayFiles.folder = Store.fileUrl(root.dataDir + "/days")
    rebuildFallback.restart()
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
    root.deleteTask(root.selDate, root.selId)
  }

  function deleteTask(date, id) {
    if (!date || !id) return
    var result = Store.deleteTask(root.readDay(date), id)
    if (!result.removed) return
    root.undoEntry = { kind: "task", date: date, task: result.removed, at: result.at }
    root.mutateDay(date, function() { return result.day })
    var list = root.readDay(root.date).tasks
    var fallback = list.length ? list[Math.min(result.at, list.length - 1)] : null
    root.select(root.date, fallback ? fallback.id : "")
  }

  // Removing a subtask goes through here rather than straight to mutateDay so
  // that it lands in the same undo slot as `dd`. The × on a subtask row and
  // Ctrl+Backspace are otherwise the only destructive things in the overlay
  // with nothing behind them.
  function removeSub(at) {
    var task = root.selTask
    if (!task || at < 0 || at >= task.subs.length) return
    var id = root.selId
    var sub = { text: task.subs[at].text, done: task.subs[at].done }
    root.undoEntry = { kind: "sub", date: root.selDate, id: id, sub: sub, at: at }
    root.mutateDay(root.selDate, function(d) { return Store.removeSub(d, id, at) })
  }

  function undoDelete() {
    var entry = root.undoEntry
    if (!entry) return
    root.undoEntry = null
    if (entry.kind === "sub") {
      var id = entry.id
      var sub = entry.sub
      var at = entry.at
      root.mutateDay(entry.date, function(d) {
        return Store.restoreSub(d, id, sub, at)
      })
      // The task it belongs to, not the subtask: selection is per task, and
      // the detail pane is where the restored line is visible.
      root.select(entry.date, id)
      return
    }
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
  function copyAttachment(att) {
    if (!att || copyProc.running) return
    copyProc.command = [root.pluginDir + "/scripts/copy-image",
                        "--dir", root.dataDir, "--sha", att.sha, "--ext", att.ext]
    copyProc.running = true
  }

  // Double-clicking any line puts it on the clipboard. Text goes straight
  // through Quickshell rather than out to wl-copy: there is no file to hand
  // over, so there is no reason to start a process for it.
  function copyText(key, text) {
    var value = String(text === null || text === undefined ? "" : text)
    if (!value) return
    Quickshell.clipboardText = value
    root.copiedKey = key
    copiedFlash.restart()
  }

  function setTaskText(date, id, text) {
    root.mutateDay(date, function(d) { return Store.setTaskText(d, id, text) })
  }

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

  // ---- opening a link ---------------------------------------------------
  // Only ever a meeting link or a map search, both already filtered to plain
  // web traffic by Store.safeUrl. The overlay gets out of the way afterwards:
  // you pressed join because you are going somewhere else.
  // ---- opening a meeting or a place ------------------------------------------
  // Both come from the calendar, so both are somebody else's text on its way to
  // xdg-open. Store.safeUrl() has already refused anything that is not plain
  // web traffic; this refuses to run at all on what is left over.
  function openExternal(url) {
    var safe = Store.safeUrl(url)
    if (!safe) return
    openProc.command = [root.pluginDir + "/scripts/open-url", safe]
    openProc.running = true
    // You asked to be somewhere else. Staying open over the browser would be
    // the wrong answer.
    root.close()
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

  // Listing a directory was the one place this shelled out for something QML
  // can do itself. It also ran `ls` off the ambient PATH, which is a needless
  // thing to trust for a list of filenames.
  FolderListModel {
    id: dayFiles
    nameFilters: ["*.json"]
    showDirs: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name

    onStatusChanged: {
      if (!root.rebuilding || status !== FolderListModel.Ready) return
      rebuildFallback.stop()
      root.rebuilding = false
      var names = []
      for (var i = 0; i < count; i++) names.push(get(i, "fileName"))
      root.rebuildFrom(names)
    }
  }

  // A folder that does not exist -- which is every first run, before the first
  // task is written -- leaves the status at Null and emits no change at all,
  // so onStatusChanged above never fires and the rebuild never happens. The
  // `ls` this replaced got that case for free: it failed, and the empty output
  // still arrived. This is that behaviour put back.
  Timer {
    id: rebuildFallback
    interval: 1500
    onTriggered: {
      if (!root.rebuilding) return
      root.rebuilding = false
      root.rebuildFrom([])
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

  // hashing and rescaling a bounded image
  Watchdog { process: pasteProc; interval: 45000 }

  Process {
    id: collectProc
  }

  // re-deriving references from every day file
  Watchdog { process: collectProc; interval: 60000 }

  Process {
    id: openProc
  }

  // handing a link to xdg-open
  Watchdog { process: openProc; interval: 20000 }

  // ---- putting an image back on the clipboard --------------------------------
  // A screenshot kept on a task is usually wanted somewhere else eventually.
  // One click puts it back on the clipboard; two open it.
  Process {
    id: copyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result
        try {
          result = JSON.parse(text)
        } catch (e) {
          return
        }
        if (!result.ok) {
          root.pasteError = result.error || "could not copy the image"
          return
        }
        root.copiedKey = "att:" + result.sha
        copiedFlash.restart()
      }
    }
  }

  // reading a stored image onto the clipboard
  Watchdog { process: copyProc; interval: 20000 }

  Timer {
    id: copiedFlash
    interval: 1400
    onTriggered: root.copiedKey = ""
  }

  Process {
    id: eventsProc
    property string date: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.eventsArrived(eventsProc.date, text)
    }
  }

  // the calendar answers in about 2.4s
  Watchdog { process: eventsProc; interval: 30000 }

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

        // Every pane sits under this handler, and Qt Quick walks an unconsumed
        // key up the parent chain -- so whatever a focused editor declines
        // arrives here. An editor declines more than it looks: Up and Down
        // always, and Left or Right whenever its cursor is already at that end
        // of the line. Typing a subtask and pressing Up used to move the
        // selection, and re-syncing the editors to the newly selected task
        // threw the half-typed line away.
        //
        // Hence a guard rather than a list of exceptions: this fires only
        // while the catcher itself holds focus, which is exactly when no
        // editor is open. tests/test_keys.qml pins both halves.
        Keys.onPressed: function(event) {
          if (!keyCatcher.activeFocus) return
          if (root.lightboxAt >= 0) {
            root.lightboxAt = -1
            event.accepted = true
            return
          }
          switch (event.key) {
          case Qt.Key_Escape:
            // Escape only ever steps back, never out. It used to close, which
            // made the second of two Escapes destructive: leaving an editor
            // and then tapping it again -- the reflex any vim user has for
            // making sure they are in normal mode -- threw the overlay away
            // along with wherever you were in it. Closing is `q`, the toggle
            // key, or a click on the scrim.
            event.accepted = true; return
          case Qt.Key_Q:
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
          case Qt.Key_Return:
          case Qt.Key_Enter:
            dayPane.editSelected(); event.accepted = true; return
          case Qt.Key_Backspace:
          case Qt.Key_Delete:
            // The same key a subtask uses, so "remove the thing I am on" is
            // one gesture everywhere. `dd` still works.
            if (event.modifiers & Qt.ControlModifier) {
              root.deleteSelected()
              event.accepted = true
            }
            return
          case Qt.Key_Tab:
            // Into the detail pane and around its stops; Escape comes back
            // out. Before this the pane could only be reached with a mouse --
            // the subtask field in particular had no key that led to it.
            //
            // Shift enters at the far end instead, so the pane's own reverse
            // walk is reachable without going the long way round first.
            if (event.modifiers & Qt.ShiftModifier) detailPane.focusSubAdd()
            else detailPane.focusTitle()
            event.accepted = true; return
          case Qt.Key_Backtab:
            detailPane.focusSubAdd(); event.accepted = true; return
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
            onTabbed: detailPane.focusTitle()
            onTabbedBack: detailPane.focusSubAdd()
          }

          Rectangle { width: 1; height: parent.height; color: root.lineSoft }

          DetailPane {
            id: detailPane
            width: parent.width - Style.space(228) - Style.space(392) - 2
            height: parent.height
            overlay: root
            onDismissed: keyCatcher.forceActiveFocus()
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
              // ctrl+v is not here on purpose: the attachments box says
              // "⌃V paste image" on itself, which is where you are looking
              // when you want it.
              { k: "j k", v: "move" },
              { k: "space", v: "done" },
              { k: "h l", v: "day" },
              { k: "t", v: "today" },
              { k: "n", v: "new" },
              { k: "tab esc", v: "detail" },
              { k: "ctrl+⌫", v: "remove" },
              { k: "dd", v: "delete" },
              { k: "u", v: "undo" },
              { k: "q", v: "close" }
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

        // There is no save button and nothing to press, which leaves nothing to
        // tell you it happened. This is the whole of the feedback: a word in
        // the corner while a change is on its way, and a moment of "saved"
        // after it lands.
        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.panelPadding
          anchors.bottom: parent.bottom
          height: Style.space(34)
          verticalAlignment: Text.AlignVCenter
          // Copying is the one action with nothing else on screen to show for
          // it -- the clipboard is invisible. It takes precedence because it
          // dirties nothing, so it never competes with "saving…".
          text: root.copiedKey !== "" ? "copied"
              : (root.unsaved ? "saving…" : (root.justSaved ? "saved" : ""))
          color: root.copiedKey !== "" ? root.accent
               : (root.unsaved ? root.dimmer : root.accent)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          opacity: text === "" ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 220 } }
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
