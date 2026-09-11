// The QML behaviours this plugin depends on.
//
//     tests/run
//
// Days are read through a single FileView that is repointed at each day file
// in turn, synchronously, so switching day does not flash an empty pane. That
// only holds if a repointed FileView returns the new file's contents to the
// very next text() call.
//
// It does not hold under blockLoading alone: that blocks the first load and
// leaves later ones asynchronous, so text() hands back the *previous* file.
// The symptom is silent and awful -- every day renders the first day's tasks
// under its own date -- which is why it is pinned here rather than left to be
// rediscovered.

import QtQuick
import Quickshell
import Quickshell.Io
import "fixtures" as Fixtures

Item {
  id: root

  property int checks: 0
  property var failed: []
  readonly property string dir: Quickshell.env("XDG_RUNTIME_DIR") + "/days-fileview-test"

  function check(name, actual, expected) {
    checks++
    if (actual !== expected) {
      failed.push(name + "\n    expected " + JSON.stringify(expected) +
                  "\n    got      " + JSON.stringify(actual))
    }
  }

  // 就地改一個 property var 裡的物件,不會讓依賴它的 binding 重算。
  Item {
    id: mutationProbe
    property var box: ({ n: 1 })
    readonly property int derived: box.n
  }

  Repeater {
    id: plainRepeater
    model: ["alpha", "beta"]
    Fixtures.PlainDelegate { }
  }

  Repeater {
    id: requiringRepeater
    model: ["alpha", "beta"]
    Fixtures.RequiringDelegate { overlay: root }
  }

  FileView {
    id: writer
    atomicWrites: true
    printErrors: false
  }

  // Exactly the configuration Overlay.qml reads days with.
  FileView {
    id: reader
    blockLoading: true
    blockAllReads: true
    printErrors: false
  }

  function write(name, body) {
    writer.path = root.dir + "/" + name
    writer.setText(body)
  }

  function read(name) {
    reader.path = root.dir + "/" + name
    return reader.text()
  }

  Timer {
    id: exitTimer
    interval: 0
    onTriggered: {
      if (root.failed.length) {
        console.warn("FAIL " + root.failed.length + "/" + root.checks)
        for (var i = 0; i < root.failed.length; i++) console.warn("  " + root.failed[i])
      } else {
        console.log("ok  " + root.checks + " checks qml")
      }
      Qt.exit(root.failed.length === 0 ? 0 : 1)
    }
  }

  Component.onCompleted: {
    root.write("a.json", "first")
    root.write("b.json", "second")
    root.write("c.json", "third")

    check("the first read returns its own file", root.read("a.json"), "first")
    check("a repointed reader does not return the previous file",
          root.read("b.json"), "second")
    check("and again for a third", root.read("c.json"), "third")
    check("going back returns the earlier file, not the latest",
          root.read("a.json"), "first")

    // A day with no file yet is the common case for any date never used.
    check("a path with no file reads as empty", root.read("missing.json"), "")
    check("and the reader recovers from it", root.read("b.json"), "second")

    // Parent directories are created on write, which is why nothing has to
    // mkdir the store before the first task is added. Checked on a later tick
    // because writes are queued, not synchronous -- the overlay never reads
    // back what it just wrote, it keeps the day it wrote in memory.
    root.write("nested/deep/d.json", "fourth")

    // ---- Repeater delegates and modelData ------------------------------
    // TaskRow is a Repeater delegate that takes its task as `task: modelData`.
    // That only works while the delegate declares no required property: one
    // required property and modelData stops being injected, `task` binds
    // undefined, and every binding in the row throws -- the row renders blank
    // with its checkbox stuck on, because a throwing binding leaves the
    // property at its default. Pinned here so nobody "tidies" TaskRow's plain
    // properties back into required ones.
    check("a delegate with no required property receives modelData",
          plainRepeater.itemAt(0).seen, "alpha")
    check("a delegate that declares a required property does not",
          requiringRepeater.itemAt(0).seen, "undefined")

    // ---- property var and in-place mutation ------------------------------
    // The overlay keeps each day as a plain JS object in a property var and the
    // detail pane binds through it. Assigning into that object does not notify
    // anything, so the pane kept rendering the note, subtasks and attachments
    // as they were before the edit -- and only refreshed when the selection
    // changed, which read as "you have to click it before it shows".
    // Anything deriving from a mutated object needs an explicit revision to
    // depend on. Pinned here because nothing about the code looks wrong.
    check("a binding sees the initial value", mutationProbe.derived, 1)
    mutationProbe.box.n = 2
    check("mutating the object in place does not re-evaluate the binding",
          mutationProbe.derived, 1)
    mutationProbe.box = { n: 3 }
    check("reassigning the property does", mutationProbe.derived, 3)

    settleTimer.start()
  }

  Timer {
    id: settleTimer
    interval: 300
    onTriggered: {
      check("writing creates the directories above it",
            root.read("nested/deep/d.json"), "fourth")
      exitTimer.start()
    }
  }
}
