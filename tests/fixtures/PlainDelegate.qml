// A delegate with no required properties: modelData reaches it as a context
// property, the way TaskRow needs.
import QtQuick
Item {
  property var got: null
  property var seen: typeof modelData === "undefined" ? "undefined" : modelData
}
