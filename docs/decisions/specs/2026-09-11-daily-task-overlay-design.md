# Days — design record

> Historical record, frozen 2026-09-11. Source code is authoritative; where
> this document and the code disagree, the code wins.

A day-scoped task overlay for Omarchy: tasks belong to a date, carry Markdown
notes, pasted images and subtasks, and live entirely on this machine.

This record exists for the decisions, not the mechanics. Each section states
what was chosen, what was rejected, and the fact that settled it — none of
which is recoverable by reading the code later.

## Why not an existing plugin

The catalog held 2974 plugins on 2026-09-11. Forty are task-, journal- or
kanban-shaped. Exactly one (`chase.kanban`) stores images, and it is
board-scoped rather than day-scoped; the day-scoped ones (`ipastorsan.bujo`,
`saikomantisu.todos`, `mohuddle.myjournal`) store text only. None reads an
existing calendar. No candidate covered day scope, images and calendar
awareness together, so none was close enough to adopt or fork.

## Decisions

### 1. Separate plugin, one-way read of the calendar

`omarchy-google-calendar-clock` is not modified. Its day's events are read
through its own `scripts/calendar-events`, which is documented upstream as a
read-only bridge that never invokes sync, push or create. The section hides
itself when that plugin is absent.

Rejected: adding a task pane to the calendar plugin's `Panel.qml`. That file is
2976 lines and carries Google sync; forking it means owning that sync, and
every upstream release becomes a manual rebase. Local patches to third-party
plugins on this machine have twice been silently reverted by plugin updates.

### 2. Tasks are not calendar objects

Caldir — the binary backing the calendar plugin — implements VEVENT only; its
command surface is connect/status/pull/push/sync/events/today/week/new/discard/
invites/rsvp/config/doctor/update. There is no VTODO anywhere in it.

So storing tasks as calendar objects would not have made them visible in the
calendar plugin, which was the only reason to want it. Tasks get their own
store.

### 3. A task is a page, not a line

A task carries a title, a Markdown note, any number of image attachments and a
flat list of subtasks. Images attach to the **task**, not to the day: an
attachment is evidence for a specific piece of work, and a day-level image
tray would lose which task it belongs to.

Rejected: a flat checkbox list with inline thumbnails. Cheaper to render, but
it has nowhere to put a note, and thumbnails in a list crowd out the text that
identifies the task.

### 4. Unfinished tasks do not move on their own

A task belongs to the day it was created on and stays there until moved by
hand. Today's pane opens with a collapsible **Carried over** section listing
every open task from earlier days, each with its source date, and moving one
rewrites its date for real.

Rejected: rolling open tasks forward automatically. It empties past days, so
looking back at a week shows nothing that happened, and a task deferred
eleven times is indistinguishable from one written this morning. Also rejected:
leaving them where they fall with no prompt — that loses them.

### 5. One JSON file per day, images content-addressed

```
~/.local/share/leonrlr4.days/
  days/YYYY-MM-DD.json   one day's tasks
  blobs/<sha256>.<ext>   originals, deduplicated by content
  thumbs/<sha256>.webp   320px renditions, the only thing lists load
  index.json             open tasks, per-day counts, blob refcounts
```

Opening a day reads exactly one small file. `index.json` answers every
aggregate question — the month grid's dots, the carried-over list, the bar
widget's count — so no code path scans `days/`. It is rewritten alongside each
day write, and rebuilt by scanning if it is missing or its version is stale.

Blob refcounts live in the index because attachments deduplicate: the same
screenshot pasted onto two tasks is one file, and deleting one attachment must
not delete the other's image.

The count reaching zero is what *triggers* deletion, but not what authorises
it. Unlinking is done by `scripts/gc-blobs`, which re-derives the reference set
from the day files themselves and refuses to delete anything at all if any day
file cannot be read. The index is a cache maintained incrementally; trusting it
for the one irreversible operation in the plugin would turn any bug in that
bookkeeping into a lost screenshot.

Rejected: Markdown in the Obsidian vault. It would make tasks visible in
Obsidian, but subtasks and attachments would have to be encoded in conventions,
parsing is slower and more fragile than `JSON.parse`, and two writers on one
file invites conflicts. Also rejected: SQLite — the data is a few hundred
kilobytes of small documents, which does not need a query engine, and a binary
store cannot be inspected or repaired by hand.

### 6. QML owns the data path; one script, for pasting only

Opening the overlay, changing day, checking a box and typing all run inside
QML against `FileView`, which writes atomically on its own. No subprocess is
spawned on any of those paths.

Two scripts exist, neither on an interaction path. `scripts/paste-image` runs
when an image is actually pasted: it reads the clipboard, hashes the bytes,
reuses an existing blob on a hit, and renders the thumbnail.
`scripts/gc-blobs` runs when an attachment loses its last reference, and can
sweep the whole store by hand.

Rejected: a shell-and-jq backend in the style of the calendar plugin. It gives
a CLI for free, but it forks bash and jq to tick a checkbox. Also rejected: a
Rust helper daemon — faster in principle, but it adds a build step to install,
a resident process, and a second thing that can break, for a dataset this size.

## Amendment, 2026-09-12: no bar widget

The first version shipped a bar widget as well — a clock with the day's open
count beside it, meant to stand in for the Omarchy clock. It is removed.

A plugin that declares `bar-widget` is only *enabled* while it occupies a slot
on the bar: `omarchy plugin enable` always places it, there is no IPC to take it
off again, and the enabled state, the slot, its per-widget settings and the
neighbouring clock's settings are four separate entries in `shell.json`. On
2026-09-11 that file was restored from an older backup and all four went with
it. The plugin was still on disk, `SUPER + M` was still bound and Hyprland
still had it, and the key did nothing — because what it toggled was no longer
loaded, with nothing on screen to say so.

Overlay-only, the footprint is one line in `shell.json`'s `plugins` array, and
`scripts/setup` restores it. That script also installs a `post-boot.d` hook, so
the next login repairs a rolled-back `shell.json` without being asked. The
count on the bar was not worth four fragile settings for a failure that reads
as "the key is broken".

## Interface

A centred overlay on `SUPER + M`, three panes: month grid with per-day
open-task dots; the day's schedule (read-only), carried-over section and task
list; and the selected task's detail.

Two consequences worth recording, because they are easy to undo by accident:

- The schedule is drawn as a coloured rail, not as cards. Cards in this UI mean
  "editable"; these events belong to another plugin and cannot be edited here.
- The note renders as Markdown at rest through `Text.MarkdownText` and becomes
  a `TextEdit` on click. One control, no preview/edit toggle, no Markdown
  library.

## Scope held out of the first version

Recurring tasks, tags, cross-day drag, task reordering between days, export,
and any form of sync. Each is additive to the day file and none changes the
decisions above.
