// A delegate that declares a required property. Declaring one switches the
// delegate to required-properties mode, and modelData is no longer injected
// as a context property -- which is the trap this fixture exists to prove.
import QtQuick
Item {
  required property var overlay
  property var seen: typeof modelData === "undefined" ? "undefined" : modelData
}
