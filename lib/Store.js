// Pure data layer for Days. No I/O, no QML types: everything here is plain
// JavaScript so tests/test_store.qml can exercise it head-less.
.pragma library

var SCHEMA = 1

function emptyDay(date) {
  return { v: SCHEMA, date: date, tasks: [] }
}

// A task read off disk may predate a field, or may have been truncated by a
// write that never finished. Normalizing on the way in means the rest of the
// plugin can index fields without guarding every one of them.
function normalizeTask(raw, date) {
  if (!raw || typeof raw !== "object") return null
  if (typeof raw.id !== "string" || !raw.id) return null
  return {
    id: raw.id,
    text: typeof raw.text === "string" ? raw.text : "",
    done: raw.done === true,
    created: typeof raw.created === "string" ? raw.created : date,
    note: typeof raw.note === "string" ? raw.note : "",
    atts: Array.isArray(raw.atts) ? raw.atts.filter(function(a) {
      return a && typeof a.sha === "string" && a.sha
    }) : [],
    subs: Array.isArray(raw.subs) ? raw.subs.filter(function(s) {
      return s && typeof s.text === "string"
    }).map(function(s) {
      return { text: s.text, done: s.done === true }
    }) : []
  }
}

// `date` is the file's own name, and it wins: a day whose stored date
// disagrees with where it is filed would otherwise show up on two dates at
// once, one of which no code path could ever write back to.
function parseDay(text, date) {
  if (!text) return emptyDay(date)
  var raw
  try {
    raw = JSON.parse(text)
  } catch (e) {
    return emptyDay(date)
  }
  if (!raw || typeof raw !== "object" || !Array.isArray(raw.tasks)) return emptyDay(date)
  var tasks = []
  for (var i = 0; i < raw.tasks.length; i++) {
    var t = normalizeTask(raw.tasks[i], date)
    if (t) tasks.push(t)
  }
  return { v: SCHEMA, date: date, tasks: tasks }
}

// ---------------------------------------------------------------------------
// The index
//
// A cache over the day files, holding the three things the UI asks for
// constantly: what is still open (per day, and in total), how many tasks a day
// closed, and how many tasks reference each blob. It is rewritten beside every
// day write, which keeps the month grid, the carried-over list and the bar
// widget free of any scan over days/.
//
//   { v, days: { "YYYY-MM-DD": { open: [{id, text}], done, blobs: {sha: n} } },
//     blobs: { sha: n } }
//
// days[*].blobs is what makes the global count maintainable in place: without
// the per-day breakdown, rewriting a day could not subtract what that day used
// to contribute, and the global count would only ever grow.
// ---------------------------------------------------------------------------

function emptyIndex() {
  return { v: SCHEMA, days: {}, blobs: {} }
}

function blobsOfDay(day) {
  var counts = {}
  for (var i = 0; i < day.tasks.length; i++) {
    var atts = day.tasks[i].atts || []
    for (var j = 0; j < atts.length; j++) {
      counts[atts[j].sha] = (counts[atts[j].sha] || 0) + 1
    }
  }
  return counts
}

function addBlobs(totals, counts, sign) {
  for (var sha in counts) {
    var next = (totals[sha] || 0) + sign * counts[sha]
    if (next > 0) totals[sha] = next
    else delete totals[sha]
  }
}

function applyDay(index, day) {
  var next = { v: SCHEMA, days: {}, blobs: {} }
  for (var d in index.days) next.days[d] = index.days[d]
  for (var sha in index.blobs) next.blobs[sha] = index.blobs[sha]

  var previous = next.days[day.date]
  if (previous) addBlobs(next.blobs, previous.blobs || {}, -1)

  if (!day.tasks.length) {
    delete next.days[day.date]
    return next
  }

  var open = []
  var done = 0
  for (var i = 0; i < day.tasks.length; i++) {
    var t = day.tasks[i]
    if (t.done) done++
    else open.push({ id: t.id, text: t.text })
  }
  var blobs = blobsOfDay(day)
  next.days[day.date] = { open: open, done: done, blobs: blobs }
  addBlobs(next.blobs, blobs, 1)
  return next
}

function rebuildIndex(days) {
  var index = emptyIndex()
  for (var i = 0; i < days.length; i++) index = applyDay(index, days[i])
  return index
}

function openCount(index, date) {
  var entry = index.days[date]
  return entry ? entry.open.length : 0
}

// Open tasks from before `today`, oldest first. The UI shows these above the
// day's own list; nothing here moves them.
function carriedOver(index, today) {
  var dates = Object.keys(index.days).filter(function(d) { return d < today }).sort()
  var out = []
  for (var i = 0; i < dates.length; i++) {
    var entry = index.days[dates[i]]
    for (var j = 0; j < entry.open.length; j++) {
      out.push({ id: entry.open[j].id, text: entry.open[j].text, date: dates[i] })
    }
  }
  return out
}

// Blobs that lost their last reference between two indexes, so the caller can
// delete exactly those files and no others.
function blobsFreed(before, after) {
  var gone = []
  for (var sha in before.blobs) {
    if (!after.blobs[sha]) gone.push(sha)
  }
  return gone.sort()
}

// ---------------------------------------------------------------------------
// Editing
//
// Every function here returns new objects. The QML layer holds one day at a
// time and reassigns it, which is what makes its bindings fire; mutating in
// place would leave the UI showing the previous state.
// ---------------------------------------------------------------------------

var idCounter = 0

// Time-ordered so ids sort the way tasks were written, with a counter and a
// random tail because several can be minted inside one millisecond.
function newId() {
  idCounter = (idCounter + 1) % 1296
  return Date.now().toString(36) +
         ("00" + idCounter.toString(36)).slice(-2) +
         Math.floor(Math.random() * 1296).toString(36)
}

function newTask(text, date) {
  return { id: newId(), text: text, done: false, created: date,
           note: "", atts: [], subs: [] }
}

function cloneTask(t) {
  return { id: t.id, text: t.text, done: t.done, created: t.created, note: t.note,
           atts: t.atts.map(function(a) { return a }),
           subs: t.subs.map(function(s) { return { text: s.text, done: s.done } }) }
}

function cloneDay(day) {
  return { v: SCHEMA, date: day.date, tasks: day.tasks.map(cloneTask) }
}

function updateTask(day, id, fn) {
  var next = cloneDay(day)
  for (var i = 0; i < next.tasks.length; i++) {
    if (next.tasks[i].id === id) {
      next.tasks[i] = fn(next.tasks[i])
      break
    }
  }
  return next
}

function moveTask(fromDay, toDay, id) {
  var from = cloneDay(fromDay)
  var to = cloneDay(toDay)
  for (var i = 0; i < from.tasks.length; i++) {
    if (from.tasks[i].id === id) {
      // created is deliberately untouched: it is the only record of how long
      // this has been waiting, and the carried-over count reads it.
      to.tasks.push(from.tasks[i])
      from.tasks.splice(i, 1)
      break
    }
  }
  return { from: from, to: to }
}

function addAttachment(day, id, att) {
  return updateTask(day, id, function(t) {
    for (var i = 0; i < t.atts.length; i++) {
      if (t.atts[i].sha === att.sha) return t
    }
    t.atts.push(att)
    return t
  })
}

function removeAttachment(day, id, sha) {
  return updateTask(day, id, function(t) {
    t.atts = t.atts.filter(function(a) { return a.sha !== sha })
    return t
  })
}

function deleteTask(day, id) {
  var next = cloneDay(day)
  for (var i = 0; i < next.tasks.length; i++) {
    if (next.tasks[i].id === id) {
      var removed = next.tasks.splice(i, 1)[0]
      return { day: next, removed: removed, at: i }
    }
  }
  return { day: next, removed: null, at: -1 }
}

function restoreTask(day, task, at) {
  var next = cloneDay(day)
  var where = Math.max(0, Math.min(at, next.tasks.length))
  next.tasks.splice(where, 0, cloneTask(task))
  return next
}
