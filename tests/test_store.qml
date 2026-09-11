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

    // ---- dates -----------------------------------------------------------
    // h/l steps a day at a time and the grid has to land on real month
    // boundaries, so this is arithmetic, not formatting.

    check("stepping forward crosses into the next month",
          function() { return Store.shiftIso("2026-09-30", 1) }, "2026-10-01")

    check("stepping back crosses into the previous year",
          function() { return Store.shiftIso("2026-01-01", -1) }, "2025-12-31")

    check("February ends on the 28th in a common year",
          function() { return Store.shiftIso("2026-02-28", 1) }, "2026-03-01")

    check("February ends on the 29th in a leap year",
          function() { return Store.shiftIso("2024-02-28", 1) }, "2024-02-29")

    check("a century that is not a leap year is handled",
          function() { return Store.shiftIso("2100-02-28", 1) }, "2100-03-01")

    check("stepping by zero returns the same day",
          function() { return Store.shiftIso("2026-09-11", 0) }, "2026-09-11")

    check("daysInMonth knows a 30 day month",
          function() { return Store.daysInMonth("2026-09") }, 30)

    check("daysInMonth knows February in a leap year",
          function() { return Store.daysInMonth("2024-02") }, 29)

    // The grid is Monday-first, so September 2026 -- which opens on a Tuesday
    // -- needs exactly one blank before the 1st.
    check("the month grid leaves room for the days before the 1st",
          function() { return Store.leadingBlanks("2026-09") }, 1)

    check("a month that opens on a Monday needs no blanks",
          function() { return Store.leadingBlanks("2026-06") }, 0)

    check("a month that opens on a Sunday needs six blanks",
          function() { return Store.leadingBlanks("2026-11") }, 6)

    check("shifting a month crosses the year",
          function() { return Store.shiftMonth("2026-12", 1) }, "2027-01")

    check("shifting a month backwards crosses the year",
          function() { return Store.shiftMonth("2026-01", -1) }, "2025-12")

    // ---- what the helpers hand back ---------------------------------------
    // Both of these parse output from a subprocess. Neither can assume the
    // shape it gets: one talks to the clipboard, the other to another
    // plugin's script that may be absent, older, or mid-upgrade.

    check("a successful paste becomes an attachment",
          function() {
            return Store.parsePaste('{"ok":true,"sha":"abc","ext":"png","w":800,"h":600,"bytes":42,"deduped":false}')
          },
          { ok: true, att: { sha: "abc", ext: "png", w: 800, h: 600, bytes: 42 } })

    check("a refused paste carries the reason through",
          function() { return Store.parsePaste('{"ok":false,"error":"the clipboard holds no image"}') },
          { ok: false, error: "the clipboard holds no image" })

    check("output that is not JSON is a failure, not a crash",
          function() { return Store.parsePaste("Traceback: something went wrong") },
          { ok: false, error: "the paste helper returned nothing usable" })

    check("empty output is a failure",
          function() { return Store.parsePaste("") },
          { ok: false, error: "the paste helper returned nothing usable" })

    check("a success missing its hash is not trusted",
          function() { return Store.parsePaste('{"ok":true,"ext":"png"}').ok },
          false)

    check("a timed event keeps its clock time and title",
          function() {
            return Store.parseEvents('{"ok":true,"events":[{"all_day":false,"start":"2026-09-11T11:30:00+08:00","title":"Standup","calendar_color":"#9a9cff"}]}')
          },
          [{ at: "11:30", title: "Standup", color: "#9a9cff", url: "", location: "" }])

    check("an all-day event has no time to show",
          function() {
            return Store.parseEvents('{"ok":true,"events":[{"all_day":true,"start":"2026-09-11","title":"Holiday"}]}')[0].at
          },
          "")

    // The calendar plugin may not be installed, in which case the script is
    // missing and the process produces nothing at all.
    check("no calendar plugin means no events, not an error",
          function() { return Store.parseEvents("") }, [])

    check("a failed calendar read means no events",
          function() { return Store.parseEvents('{"ok":false,"error":"Caldir is not installed"}') }, [])

    check("an event with no title still renders",
          function() {
            return Store.parseEvents('{"ok":true,"events":[{"all_day":false,"start":"2026-09-11T09:00:00+08:00"}]}')[0].title
          },
          "(untitled)")

    check("events are ordered by start time",
          function() {
            return Store.parseEvents('{"ok":true,"events":[' +
              '{"all_day":false,"start":"2026-09-11T16:30:00+08:00","title":"late"},' +
              '{"all_day":true,"start":"2026-09-11","title":"all day"},' +
              '{"all_day":false,"start":"2026-09-11T09:00:00+08:00","title":"early"}]}')
              .map(function(e) { return e.title })
          },
          ["all day", "early", "late"])

    // ---- the event cache ---------------------------------------------------
    // Asking the calendar plugin for a day costs ~2.4s, so the answer is kept
    // on disk and shown immediately on the next open while a fresh one is
    // fetched behind it. A cache file that cannot be trusted must read as
    // "nothing cached", never as "no events" -- the latter would render an
    // empty schedule over a day that has meetings.

    check("a cache document round-trips",
          function() {
            var doc = Store.eventCacheDoc(
              [{ at: "09:30", title: "Standup", color: "#6699ff", url: "", location: "" }], "2026-09-11T21:20:00Z")
            return Store.parseEventCache(JSON.stringify(doc)).events
          },
          [{ at: "09:30", title: "Standup", color: "#6699ff", url: "", location: "" }])

    check("the cache records when it was fetched",
          function() {
            var doc = Store.eventCacheDoc([], "2026-09-11T21:20:00Z")
            return Store.parseEventCache(JSON.stringify(doc)).fetchedAt
          },
          "2026-09-11T21:20:00Z")

    check("a day with no events caches as an empty list, not as nothing",
          function() {
            var doc = Store.eventCacheDoc([], "2026-09-11T21:20:00Z")
            var back = Store.parseEventCache(JSON.stringify(doc))
            return back !== null && back.events.length === 0
          },
          true)

    check("a truncated cache file reads as nothing cached",
          function() { return Store.parseEventCache('{"v":1,"eve') }, null)

    check("no cache file reads as nothing cached",
          function() { return Store.parseEventCache("") }, null)

    check("a cache from an older schema is ignored",
          function() { return Store.parseEventCache('{"v":0,"events":[]}') }, null)

    check("a cache whose events are not a list is ignored",
          function() { return Store.parseEventCache('{"v":1,"events":"soon"}') }, null)

    check("an entry missing its title is dropped rather than rendered blank",
          function() {
            return Store.parseEventCache('{"v":1,"fetchedAt":"x","events":[{"at":"09:00"},{"at":"10:00","title":"Real"}]}').events.length
          },
          1)

    // ---- what an event lets you do -----------------------------------------
    check("a meeting link comes through",
          function() {
            return Store.parseEvents('{"ok":true,"events":[{"all_day":false,"start":"2026-09-12T06:30:00+10:00","title":"Workshop","conference_url":"https://meet.google.com/abc-defg-hij"}]}')[0].url
          },
          "https://meet.google.com/abc-defg-hij")

    check("a location comes through",
          function() {
            return Store.parseEvents('{"ok":true,"events":[{"all_day":false,"start":"2026-09-12T09:00:00+08:00","title":"Lunch","location":"Din Tai Fung, Xinyi"}]}')[0].location
          },
          "Din Tai Fung, Xinyi")

    check("an event with neither reports empty strings, not null",
          function() {
            var e = Store.parseEvents('{"ok":true,"events":[{"all_day":false,"start":"2026-09-12T09:00:00+08:00","title":"Focus","location":null,"conference_url":null}]}')[0]
            return [e.url, e.location]
          },
          ["", ""])

    check("the cache keeps the link and the location",
          function() {
            var doc = Store.eventCacheDoc(Store.parseEvents(
              '{"ok":true,"events":[{"all_day":false,"start":"2026-09-12T06:30:00+10:00","title":"Workshop","location":"Room 4","conference_url":"https://meet.google.com/x"}]}'),
              "2026-09-12T00:00:00Z")
            var back = Store.parseEventCache(JSON.stringify(doc)).events[0]
            return [back.url, back.location]
          },
          ["https://meet.google.com/x", "Room 4"])

    // ---- handing a URL to the desktop --------------------------------------
    // Calendar entries are written by whoever sent the invite. The link goes to
    // xdg-open, so anything but plain web traffic is refused rather than handed
    // to whatever happens to claim that scheme.
    check("an https link is allowed",
          function() { return Store.safeUrl("https://meet.google.com/abc") },
          "https://meet.google.com/abc")

    check("plain http is allowed",
          function() { return Store.safeUrl("http://example.com/room") },
          "http://example.com/room")

    check("a file:// link is refused",
          function() { return Store.safeUrl("file:///etc/passwd") }, "")

    check("a javascript: link is refused",
          function() { return Store.safeUrl("javascript:alert(1)") }, "")

    check("a scheme-less string is refused",
          function() { return Store.safeUrl("meet.google.com/abc") }, "")

    check("leading whitespace does not smuggle a scheme past the check",
          function() { return Store.safeUrl("  javascript:alert(1)") }, "")

    check("empty is refused",
          function() { return Store.safeUrl("") }, "")

    check("a map link is built for a place",
          function() { return Store.mapUrl("Taipei 101") },
          "https://www.google.com/maps/search/?api=1&query=Taipei%20101")

    check("a place with punctuation and CJK survives encoding",
          function() { return Store.mapUrl("鼎泰豐 信義店 & Co.") },
          "https://www.google.com/maps/search/?api=1&query=" +
          encodeURIComponent("鼎泰豐 信義店 & Co."))

    check("no place means no map link",
          function() { return Store.mapUrl("  ") }, "")

    exitTimer.start()
  }
}
