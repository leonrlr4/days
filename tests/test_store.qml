// Tests for lib/Store.js, the plugin's whole data layer.
//
//     tests/run
//
// Checks are recorded rather than thrown: an exception escaping
// Component.onCompleted skips the exit timer and the process hangs instead of
// failing. Each check runs its subject in a closure so a missing function
// reports as a failure with a name, not as a load error.

import QtQuick
import "../lib/Store.js" as Store

Item {
  id: root

  property int checks: 0
  property var failed: []

  // Key order in a JS object follows insertion, so two indexes that are equal
  // can still stringify differently. Comparisons below go through this.
  function canon(v) {
    if (Array.isArray(v)) return v.map(canon)
    if (v && typeof v === "object") {
      var out = {}
      Object.keys(v).sort().forEach(function(k) { out[k] = canon(v[k]) })
      return out
    }
    return v
  }

  function task(id, text, done, atts) {
    return { id: id, text: text, done: done === true, created: "2026-09-01",
             note: "", atts: (atts || []).map(function(s) { return { sha: s, ext: "png" } }),
             subs: [] }
  }

  function day(date, tasks) {
    return { v: 1, date: date, tasks: tasks }
  }

  function check(name, fn, expected) {
    checks++
    var actual
    try {
      actual = fn()
    } catch (e) {
      failed.push(name + "\n    threw: " + e)
      return
    }
    var a = JSON.stringify(actual)
    var e2 = JSON.stringify(expected)
    if (a !== e2) failed.push(name + "\n    expected " + e2 + "\n    got      " + a)
  }

  Timer {
    id: exitTimer
    interval: 0
    onTriggered: {
      if (root.failed.length) {
        console.warn("FAIL " + root.failed.length + "/" + root.checks)
        for (var i = 0; i < root.failed.length; i++) console.warn("  " + root.failed[i])
      } else {
        console.log("ok  " + root.checks + " checks")
      }
      Qt.exit(root.failed.length === 0 ? 0 : 1)
    }
  }

  Component.onCompleted: {
    // ---- parseDay: every read of a day file goes through this ------------
    check("an absent file becomes an empty day",
          function() { return Store.parseDay("", "2026-09-11") },
          { v: 1, date: "2026-09-11", tasks: [] })

    check("a stored day round-trips",
          function() {
            var d = { v: 1, date: "2026-09-11", tasks: [
              { id: "a", text: "ship it", done: false, created: "2026-09-11",
                note: "", atts: [], subs: [] } ] }
            return Store.parseDay(JSON.stringify(d), "2026-09-11")
          },
          { v: 1, date: "2026-09-11", tasks: [
            { id: "a", text: "ship it", done: false, created: "2026-09-11",
              note: "", atts: [], subs: [] } ] })

    // A half-written file must not take the day's tasks down with it. Losing
    // one day to a parse error is recoverable; a crash on open is not.
    check("malformed JSON becomes an empty day",
          function() { return Store.parseDay("{\"v\":1,\"ta", "2026-09-11") },
          { v: 1, date: "2026-09-11", tasks: [] })

    check("a task missing its optional fields is filled in",
          function() {
            return Store.parseDay(
              "{\"v\":1,\"date\":\"2026-09-11\",\"tasks\":[{\"id\":\"a\",\"text\":\"x\"}]}",
              "2026-09-11").tasks[0]
          },
          { id: "a", text: "x", done: false, created: "2026-09-11",
            note: "", atts: [], subs: [] })

    check("a task with no id is dropped rather than given one",
          function() {
            return Store.parseDay(
              "{\"v\":1,\"date\":\"2026-09-11\",\"tasks\":[{\"text\":\"x\"},{\"id\":\"b\",\"text\":\"y\"}]}",
              "2026-09-11").tasks.length
          },
          1)

    check("the date in the file never overrides the file's own name",
          function() {
            return Store.parseDay(
              "{\"v\":1,\"date\":\"1999-01-01\",\"tasks\":[]}", "2026-09-11").date
          },
          "2026-09-11")

    // ---- the index: every aggregate the UI shows comes from here ---------
    // The month grid's dots, the carried-over list and the bar widget's count
    // all read the index, so no code path ever scans days/.

    check("applying a day records its open tasks",
          function() {
            var ix = Store.applyDay(Store.emptyIndex(),
                                    day("2026-09-11", [task("a", "one"), task("b", "two", true)]))
            return canon(ix.days["2026-09-11"])
          },
          canon({ open: [{ id: "a", text: "one" }], done: 1, blobs: {} }))

    check("a day with nothing open still records its done count",
          function() {
            var ix = Store.applyDay(Store.emptyIndex(), day("2026-09-11", [task("a", "one", true)]))
            return canon(ix.days["2026-09-11"])
          },
          canon({ open: [], done: 1, blobs: {} }))

    check("re-applying a day replaces its entry rather than appending",
          function() {
            var ix = Store.applyDay(Store.emptyIndex(), day("2026-09-11", [task("a", "one")]))
            ix = Store.applyDay(ix, day("2026-09-11", [task("a", "one", true)]))
            return ix.days["2026-09-11"].open.length
          },
          0)

    check("an emptied day leaves no entry behind",
          function() {
            var ix = Store.applyDay(Store.emptyIndex(), day("2026-09-11", [task("a", "one")]))
            ix = Store.applyDay(ix, day("2026-09-11", []))
            return ix.days["2026-09-11"] === undefined
          },
          true)

    check("openCount reads a day the index has never seen",
          function() { return Store.openCount(Store.emptyIndex(), "2026-09-11") },
          0)

    // ---- carried over ----------------------------------------------------
    check("carried over lists open tasks from earlier days, oldest first",
          function() {
            var ix = Store.emptyIndex()
            ix = Store.applyDay(ix, day("2026-09-09", [task("b", "second")]))
            ix = Store.applyDay(ix, day("2026-09-08", [task("a", "first")]))
            return canon(Store.carriedOver(ix, "2026-09-11"))
          },
          canon([{ id: "a", text: "first", date: "2026-09-08" },
                 { id: "b", text: "second", date: "2026-09-09" }]))

    check("carried over excludes today and the future",
          function() {
            var ix = Store.emptyIndex()
            ix = Store.applyDay(ix, day("2026-09-11", [task("a", "today")]))
            ix = Store.applyDay(ix, day("2026-09-12", [task("b", "tomorrow")]))
            return Store.carriedOver(ix, "2026-09-11").length
          },
          0)

    check("a completed task is never carried over",
          function() {
            var ix = Store.applyDay(Store.emptyIndex(), day("2026-09-08", [task("a", "done", true)]))
            return Store.carriedOver(ix, "2026-09-11").length
          },
          0)

    // ---- blob refcounts --------------------------------------------------
    // Attachments deduplicate by content hash, so the same screenshot on two
    // tasks is one file. Deleting one of them must not delete the other's.

    check("an attachment is counted once per task that references it",
          function() {
            var ix = Store.applyDay(Store.emptyIndex(),
                                    day("2026-09-11", [task("a", "one", false, ["sha1"]),
                                                       task("b", "two", false, ["sha1"])]))
            return ix.blobs["sha1"]
          },
          2)

    check("the same attachment on two days counts on both",
          function() {
            var ix = Store.emptyIndex()
            ix = Store.applyDay(ix, day("2026-09-10", [task("a", "one", false, ["sha1"])]))
            ix = Store.applyDay(ix, day("2026-09-11", [task("b", "two", false, ["sha1"])]))
            return ix.blobs["sha1"]
          },
          2)

    check("rewriting a day subtracts the attachments it used to hold",
          function() {
            var ix = Store.applyDay(Store.emptyIndex(),
                                    day("2026-09-11", [task("a", "one", false, ["sha1", "sha2"])]))
            ix = Store.applyDay(ix, day("2026-09-11", [task("a", "one", false, ["sha1"])]))
            return [ix.blobs["sha1"], ix.blobs["sha2"]]
          },
          [1, undefined])

    check("a blob that reached zero is named as freed",
          function() {
            var before = Store.applyDay(Store.emptyIndex(),
                                        day("2026-09-11", [task("a", "one", false, ["sha1"])]))
            var after = Store.applyDay(before, day("2026-09-11", [task("a", "one")]))
            return Store.blobsFreed(before, after)
          },
          ["sha1"])

    check("a blob still referenced elsewhere is not freed",
          function() {
            var before = Store.emptyIndex()
            before = Store.applyDay(before, day("2026-09-10", [task("a", "one", false, ["sha1"])]))
            before = Store.applyDay(before, day("2026-09-11", [task("b", "two", false, ["sha1"])]))
            var after = Store.applyDay(before, day("2026-09-11", [task("b", "two")]))
            return Store.blobsFreed(before, after)
          },
          [])

    // ---- rebuild ---------------------------------------------------------
    // The index is a cache of the day files. If it is lost or its version
    // moves, it has to be reconstructible from them exactly.
    check("rebuilding from the day files matches applying them one by one",
          function() {
            var a = day("2026-09-08", [task("a", "one", false, ["sha1"]), task("b", "two", true)])
            var b = day("2026-09-11", [task("c", "three", false, ["sha1", "sha2"])])
            var incremental = Store.applyDay(Store.applyDay(Store.emptyIndex(), a), b)
            return canon(Store.rebuildIndex([a, b])) === canon(incremental)
                   || JSON.stringify(canon(Store.rebuildIndex([a, b]))) === JSON.stringify(canon(incremental))
          },
          true)

    // ---- editing ---------------------------------------------------------
    check("a new task starts open, on the day it was written",
          function() {
            var t = Store.newTask("write it down", "2026-09-11")
            return [t.text, t.done, t.created, t.note, t.atts.length, t.subs.length]
          },
          ["write it down", false, "2026-09-11", "", 0, 0])

    // Ids are minted in a burst when several tasks are typed in quickly, and a
    // collision would make two rows the same task.
    check("two tasks minted back to back get different ids",
          function() {
            var a = Store.newTask("one", "2026-09-11")
            var b = Store.newTask("two", "2026-09-11")
            return a.id !== b.id && a.id.length > 0
          },
          true)

    check("updateTask rewrites one task and leaves its neighbours alone",
          function() {
            var d = day("2026-09-11", [task("a", "one"), task("b", "two")])
            var next = Store.updateTask(d, "b", function(t) { t.done = true; return t })
            return [next.tasks[0].done, next.tasks[1].done, next.tasks.length]
          },
          [false, true, 2])

    check("updateTask leaves the day alone when the id is unknown",
          function() {
            var d = day("2026-09-11", [task("a", "one")])
            return Store.updateTask(d, "zz", function(t) { t.done = true; return t }).tasks[0].done
          },
          false)

    check("updateTask does not mutate the day it was given",
          function() {
            var d = day("2026-09-11", [task("a", "one")])
            Store.updateTask(d, "a", function(t) { t.text = "changed"; return t })
            return d.tasks[0].text
          },
          "one")

    // ---- moving between days ---------------------------------------------
    check("moving a task takes it out of one day and puts it in the other",
          function() {
            var from = day("2026-09-08", [task("a", "one"), task("b", "two")])
            var to = day("2026-09-11", [task("c", "three")])
            var r = Store.moveTask(from, to, "a")
            return [r.from.tasks.map(function(t) { return t.id }),
                    r.to.tasks.map(function(t) { return t.id })]
          },
          [["b"], ["c", "a"]])

    // The created date is the only record of how long something has been
    // waiting, so moving must not reset it to the day it landed on.
    check("moving a task keeps the date it was created on",
          function() {
            var from = day("2026-09-08", [task("a", "one")])
            var r = Store.moveTask(from, day("2026-09-11", []), "a")
            return r.to.tasks[0].created
          },
          "2026-09-01")

    check("moving an id neither day holds changes nothing",
          function() {
            var from = day("2026-09-08", [task("a", "one")])
            var to = day("2026-09-11", [task("c", "three")])
            var r = Store.moveTask(from, to, "zz")
            return [r.from.tasks.length, r.to.tasks.length]
          },
          [1, 1])

    // ---- attachments -----------------------------------------------------
    check("an attachment is appended to the task",
          function() {
            var d = day("2026-09-11", [task("a", "one")])
            var next = Store.addAttachment(d, "a", { sha: "sha1", ext: "png" })
            return next.tasks[0].atts.length
          },
          1)

    // Pasting the same screenshot twice is a slip, not a request for two
    // copies of one row.
    check("pasting a sha the task already holds adds nothing",
          function() {
            var d = day("2026-09-11", [task("a", "one", false, ["sha1"])])
            var next = Store.addAttachment(d, "a", { sha: "sha1", ext: "png" })
            return next.tasks[0].atts.length
          },
          1)

    check("removing an attachment leaves the others in place",
          function() {
            var d = day("2026-09-11", [task("a", "one", false, ["sha1", "sha2"])])
            var next = Store.removeAttachment(d, "a", "sha1")
            return next.tasks[0].atts.map(function(a) { return a.sha })
          },
          ["sha2"])

    // ---- deletion --------------------------------------------------------
    // Undo has to put the row back where it was, so deletion reports the
    // position as well as the task.
    check("deleting a task reports it and its position for undo",
          function() {
            var d = day("2026-09-11", [task("a", "one"), task("b", "two"), task("c", "three")])
            var r = Store.deleteTask(d, "b")
            return [r.day.tasks.map(function(t) { return t.id }), r.removed.id, r.at]
          },
          [["a", "c"], "b", 1])

    check("restoring a deleted task puts it back where it was",
          function() {
            var d = day("2026-09-11", [task("a", "one"), task("b", "two"), task("c", "three")])
            var r = Store.deleteTask(d, "b")
            return Store.restoreTask(r.day, r.removed, r.at).tasks.map(function(t) { return t.id })
          },
          ["a", "b", "c"])

    check("deleting an unknown id reports nothing removed",
          function() {
            var d = day("2026-09-11", [task("a", "one")])
            return Store.deleteTask(d, "zz").removed === null
          },
          true)

    exitTimer.start()
  }
}
