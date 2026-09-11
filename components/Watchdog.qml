import QtQuick

// An upper bound on how long one helper may run.
//
// Every subprocess here is short by nature -- hash an image, read a day of
// events, hand a link to the desktop -- so one that is still going after this
// long is stuck, not busy. Without a bound it stays stuck for the life of the
// session, holding the single-flight guards closed behind it: no more pastes,
// no more event refreshes.
//
// Clearing `running` on a Quickshell Process terminates it; the timer follows
// the process, so it arms itself on every launch and disarms when one ends on
// its own.
Timer {
  property var process: null

  running: !!process && process.running
  repeat: false
  onTriggered: if (process && process.running) process.running = false
}
