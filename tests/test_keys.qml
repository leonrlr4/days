// Why the overlay's key handler is guarded on its own activeFocus.
//
//     tests/run
//
// Overlay.qml puts one Keys.onPressed on `keyCatcher`, an ancestor of every
// pane. Qt Quick sends a key to the focused item first and then walks it up
// the parent chain, so whatever a focused editor declines to consume arrives
// there anyway. Typing a subtask and pressing Up moved the selection instead,
// and re-syncing the editors to the newly selected task threw the half-typed
// line away.
//
// A TextInput consumes an arrow key only when its cursor has somewhere to go.
// Up and Down it never consumes; Left and Right it consumes in the middle of a
// line and declines at either end -- so an empty field leaks all four, and
// `h`/`l` changed the day out from under a half-typed line too.
//
// That boundary is why the fix is not a list of exceptions inside the handler:
// the same key is sometimes consumed and sometimes not, depending on where the
// cursor happens to sit. The handler runs only while the catcher itself holds
// focus.

import QtQuick
import QtTest

Item {
  width: 200
  height: 100

  // The real arrangement in miniature: one handler above, one editor below.
  Item {
    id: catcher
    anchors.fill: parent
    focus: true

    property var seen: []
    property bool guarded: false

    Keys.onPressed: function(event) {
      if (catcher.guarded && !catcher.activeFocus) return
      catcher.seen.push(event.key)
      event.accepted = true
    }

    TextInput { id: field }
  }

  // The detail pane hands focus on with Keys.onTabPressed and leaves with
  // Keys.onEscapePressed, on editors that would otherwise spend those keys
  // themselves -- a TextEdit inserts a tab, and both would go on bubbling.
  TextEdit {
    id: editor
    property int tabs: 0
    property int escapes: 0
    property int backtabs: 0
    Keys.onTabPressed: editor.tabs++
    Keys.onBacktabPressed: editor.backtabs++
    Keys.onEscapePressed: editor.escapes++
  }

  TestCase {
    name: "keyCatcher"
    when: windowShown

    function init() {
      catcher.seen = []
      catcher.guarded = false
      editor.tabs = 0
      editor.backtabs = 0
      editor.escapes = 0
      field.text = ""
      field.forceActiveFocus()
    }

    function test_up_reaches_an_ancestor_from_a_focused_field() {
      keyClick(Qt.Key_Up)
      compare(catcher.seen, [Qt.Key_Up])
    }

    function test_down_reaches_it_too() {
      keyClick(Qt.Key_Down)
      compare(catcher.seen, [Qt.Key_Down])
    }

    // Only while the cursor has room. This is the case that makes the bug look
    // intermittent: the very same key is swallowed mid-word and leaks at the
    // end of one.
    function test_left_and_right_are_consumed_mid_line() {
      field.text = "abc"
      field.cursorPosition = 1
      keyClick(Qt.Key_Right)
      keyClick(Qt.Key_Left)
      compare(catcher.seen, [])
    }

    function test_left_leaks_at_the_start_of_the_line() {
      field.text = "abc"
      field.cursorPosition = 0
      keyClick(Qt.Key_Left)
      compare(catcher.seen, [Qt.Key_Left])
    }

    function test_right_leaks_at_the_end_of_the_line() {
      field.text = "abc"
      field.cursorPosition = 3
      keyClick(Qt.Key_Right)
      compare(catcher.seen, [Qt.Key_Right])
    }

    function test_an_empty_field_leaks_both() {
      keyClick(Qt.Key_Left)
      keyClick(Qt.Key_Right)
      compare(catcher.seen, [Qt.Key_Left, Qt.Key_Right])
    }

    function test_typing_never_reaches_it() {
      keyClick(Qt.Key_J)
      compare(catcher.seen, [])
      compare(field.text, "j")
    }

    // The guard, which is what Overlay.qml actually does.
    function test_the_guard_makes_a_bubbled_key_inert() {
      catcher.guarded = true
      keyClick(Qt.Key_Up)
      keyClick(Qt.Key_Down)
      compare(catcher.seen, [])
    }

    function test_the_guard_still_lets_the_catcher_hear_its_own_keys() {
      catcher.guarded = true
      catcher.forceActiveFocus()
      keyClick(Qt.Key_Up)
      compare(catcher.seen, [Qt.Key_Up])
    }

    // Tab is the key that moves focus between the panes, which only works if
    // Qt has not already spent it on focus navigation of its own. It has not:
    // that is opt-in per item through activeFocusOnTab, and nothing here asks
    // for it.
    function test_tab_reaches_the_catcher() {
      catcher.guarded = true
      catcher.forceActiveFocus()
      keyClick(Qt.Key_Tab)
      compare(catcher.seen, [Qt.Key_Tab])
    }

    // And from inside an editor Tab belongs to the editor, which is what lets
    // each one hand focus to the next rather than every Tab meaning the same
    // thing wherever it is pressed.
    function test_tab_from_a_field_is_the_fields_to_answer() {
      catcher.guarded = true
      keyClick(Qt.Key_Tab)
      compare(catcher.seen, [])
    }

    // The named handlers accept the event on their own. If they did not, the
    // whole Tab chain would still work while quietly inserting a tab
    // character into every title it passed through.
    // Shift+Tab arrives by two different routes and the reverse walk has to
    // answer both. A real compositor sends the ISO_Left_Tab keysym, which Qt
    // delivers as Key_Backtab and onBacktabPressed. A synthesised event --
    // this test, and anything driving the overlay with wtype -- stays
    // Key_Tab and carries the Shift modifier instead, reaching
    // onTabPressed. Hanging the reverse walk on Backtab alone would work by
    // hand and be untestable; hanging it on the modifier alone would test
    // green and do nothing on the real keyboard.
    function test_synthetic_shift_tab_stays_tab_with_a_modifier() {
      editor.forceActiveFocus()
      editor.text = "ab"
      keyClick(Qt.Key_Tab, Qt.ShiftModifier)
      compare([editor.backtabs, editor.tabs], [0, 1])
      compare(editor.text, "ab")
    }

    function test_backtab_reaches_its_own_handler() {
      editor.forceActiveFocus()
      keyClick(Qt.Key_Backtab)
      compare([editor.backtabs, editor.tabs], [1, 0])
    }

    function test_a_named_handler_accepts_the_key_it_names() {
      editor.forceActiveFocus()
      editor.text = "ab"
      keyClick(Qt.Key_Tab)
      keyClick(Qt.Key_Escape)
      compare([editor.tabs, editor.escapes], [1, 1])
      compare(editor.text, "ab")
      compare(catcher.seen, [])
    }
  }
}
