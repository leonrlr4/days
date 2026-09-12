# Days

A task list that belongs to a day.

Tasks are written on a date and stay there. Each one opens into a page with a
Markdown note, screenshots you paste straight from the clipboard, and subtasks.
The day's calendar events sit above the list, read-only. Everything lives in
your home directory and nothing leaves the machine.

![Days](preview.png)

## What it does

**A day, not a backlog.** A task belongs to the day it was written on. Today's
pane opens with a **Carried over** section listing everything still open from
earlier days, each with the date it came from, and a button to move it here.
Nothing moves on its own — so last Wednesday still shows what last Wednesday
actually held, and a task deferred eleven times looks different from one
written this morning.

**Screenshots on the task.** `Ctrl+V` in the detail pane stores whatever image
is on the clipboard, or imports it if what you copied was a path to one.
Identical images are stored once no matter how many tasks point at them. Click
a thumbnail to put it back on the clipboard, double-click to enlarge it, and
right-click to remove it.

**Notes in Markdown.** The note renders where it sits and becomes an editor
when you click it. No preview toggle, no second mode.

**One set of keys.** A task and a subtask are the same kind of thing to your
hands: `Enter` edits the line you are on and `Enter` again is done, `space`
ticks it, `Ctrl+Backspace` removes it, `u` puts it back. The mouse keeps the
same shape — one click selects a line, two copy it to the clipboard — which is
why ticking belongs to the checkbox alone and never to the row.

**Join, or find the place.** An event with a meeting link gets a `join` button
and one with a location gets a `map`, which opens Google Maps on it. Both go
through `xdg-open`, and both refuse anything that is not an ordinary `http`
or `https` link — a calendar entry is written by whoever sent the invite.

**Saved as you go.** There is no save button. Every change — a tick, a word in
a note, a pasted screenshot — is on disk within a moment, and the corner says
`saving…` and then `saved` so you can see it happen rather than hope.

**Your calendar, beside it.** If [Omarchy Google Calendar and
Clock](https://github.com/NachoRodriguezM/omarchy-google-calendar-clock) is
installed, the day's events appear above the task list. Days reads them through
that plugin's own read-only bridge and never creates, changes or syncs
anything. That bridge takes a couple of seconds to answer, so each day's events
are cached on disk: the schedule is there the moment the overlay opens, and a
fresh answer replaces it when it arrives.

**One key, nothing on the bar.** Days is an overlay and only an overlay. That
is not just taste: a plugin that declares a bar widget is only "enabled" while
it holds a slot on the bar, so four separate settings have to survive for the
key to work. With no bar widget there is one, and `scripts/setup` puts it back.

## Install

```
omarchy plugin add leonrlr4/days
~/.config/omarchy/plugins/leonrlr4.days/scripts/setup
```

`scripts/setup` enables the plugin and binds `SUPER + M` in your
`bindings.lua`. It is idempotent — run it any time, and `scripts/setup --check`
reports what is missing without changing anything.

It deliberately installs no boot hook, and you should not add one.
Enabling a plugin is a settings change, and the shell holds its live config in
a property initialised to the factory defaults and replaced only when
`shell.json` finishes loading — asynchronously. Every settings change copies
whatever that property holds *right now* and writes the whole thing back, so a
change made inside that window persists the defaults over the user's entire
configuration. Hyprland runs post-boot hooks two seconds after loading its
config, squarely inside it.

Run `scripts/setup` again by hand if something ever resets `shell.json`; the
plugin, its data and your keybinding are all untouched by that, and one command
puts the last piece back.

`scripts/setup` touches exactly two things, and only when you run it:

- **`~/.config/omarchy/shell.json`** — enables the plugin, through
  `omarchy plugin enable`. One line in the `plugins` array.
- **`~/.config/hypr/bindings.lua`** — appends a comment and one `o.bind` line,
  and does nothing if a binding for this plugin is already there.

It never edits anything else, never runs on its own, and `--check` makes no
changes at all.

Pick a different key with `--key "SUPER + D"`, or skip the binding with
`--no-key`. `SUPER + M` is free in a stock Omarchy install; `SUPER + T` toggles
floating and the whole comma family belongs to notifications.

Requires `wl-clipboard`, `imagemagick` and `jq`, all of which a stock Omarchy
install already has.

## Keys

The same keys work on a task and on a subtask, so there is one set to learn
rather than two.

| | | | |
|---|---|---|---|
| `j` `k` | move between lines | `space` | complete |
| `Enter` | edit — `Enter` again finishes | `Ctrl+Backspace` | remove |
| `u` | undo the last removal | `dd` | delete a task |
| `h` `l` | previous / next day | `t` | back to today |
| `n` | new task | `Ctrl+V` | paste an image onto the task |
| `Tab` `Shift+Tab` | through the detail pane | `Esc` | step back |
| `q` | close | | |

`Tab` moves into the detail pane and walks it in the order it reads: the title,
the note, each subtask, then the field that adds one, and round again.
`Shift+Tab` walks it backwards. `Esc` comes back out.

**`Esc` only ever steps back — it does not close.** Leaving an editor and then
tapping `Esc` again is a reflex, and it should not throw the overlay away.
Closing is `q`, the key you opened it with, or a click outside.

**Editing a subtask down to nothing removes it**, and `u` brings it back — a
blank line in a checklist is never what was meant. Emptying a *task* does not
delete it, because a task is a container: it carries the note, the screenshots
and the whole subtask list, and clearing one field is not a request to throw
all of that away. Use `dd` or `Ctrl+Backspace`, both of which `u` undoes.

Omarchy's own `SUPER + V` works too. It forwards `Ctrl+V`, or `Shift+Insert`
when it decides the focused window is a terminal — and an overlay is a layer
surface rather than a window, so that check sees whatever was behind it. Both
are accepted here.

### Mouse

**One click selects a line, two copy it.** The text goes to the clipboard and
the corner says `copied`. Ticking belongs to the checkbox alone, which is what
leaves the row free to mean something else.

Hovering a task or a subtask shows a `×` that removes it — `u` still puts it
back. A date in the month grid selects that day, and the note becomes an editor
where it sits.

Image thumbnails are the one place the rule differs: one click puts the image
back on the clipboard and a double click enlarges it, because a thumbnail has
nothing to select and a picture wants somewhere to open.

## Where your data is

```
~/.local/share/leonrlr4.days/
  days/YYYY-MM-DD.json   one file per day
  blobs/<sha256>.<ext>   images, stored under their own content hash
  thumbs/<sha256>.webp   320px renditions, the only thing lists load
  index.json             a cache: open tasks, per-day counts, image refcounts
  events/YYYY-MM-DD.json a cache of the day's calendar events
```

Plain JSON, one small file per day — readable, greppable, and trivial to back
up or put in a git repo. `index.json` and `events/` are both derived and can be
deleted at any time; the index is rebuilt from the day files on the next open,
and the events are re-fetched.

Removing the last reference to an image runs `scripts/gc-blobs`, which
re-derives what is still referenced from the day files themselves before
deleting anything, and refuses to delete at all if any day file cannot be read.
Run it by hand to sweep the whole store:

```
scripts/gc-blobs --dir ~/.local/share/leonrlr4.days
```

## Removal

```
~/.config/omarchy/plugins/leonrlr4.days/scripts/uninstall
omarchy plugin remove leonrlr4.days
```

`scripts/uninstall` removes the keybinding it added and disables the plugin.
Your tasks and images in `~/.local/share/leonrlr4.days/` are kept — add
`--purge` to delete those too, or `--check` to see what would change without
changing it.

## Tests

```
tests/run
```

Head-less, no packages beyond what the plugin already needs. The data layer is
plain JavaScript in `lib/Store.js` so it can be exercised without a shell.

The other two suites pin behaviours of Qt itself, all of which fail silently
and confusingly when they are wrong. `tests/test_qml.qml` covers how a
repointed `FileView` reads and what a Repeater delegate stops receiving once it
declares a required property. `tests/test_keys.qml` covers key delivery: which
arrow keys a focused text field declines and therefore hands to whatever is
above it, and the fact that `Shift+Tab` reaches a real compositor as
`Key_Backtab` but a synthesised event as `Key_Tab` with a modifier.

## Licence

MIT.
