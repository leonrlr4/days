import QtQuick
import qs.Commons

// A small outlined action, used on the schedule rail.
//
// Quiet until you are near it: an event row is information first, and two
// buttons shouting on every line would bury the thing you came to read.
Item {
  id: button
  property var overlay: null
  property string label: ""
  property bool highlight: false

  signal activated()

  implicitWidth: text.implicitWidth + Style.spacing.xxl
  implicitHeight: Style.space(18)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius / 3
    color: hover.containsMouse && button.highlight
      ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.14)
      : (hover.containsMouse ? Qt.rgba(overlay.fg.r, overlay.fg.g, overlay.fg.b, 0.06)
                             : "transparent")
    border.width: 1
    border.color: hover.containsMouse
      ? (button.highlight
          ? Qt.rgba(overlay.accent.r, overlay.accent.g, overlay.accent.b, 0.55)
          : Qt.rgba(overlay.fg.r, overlay.fg.g, overlay.fg.b, 0.22))
      : overlay.lineSoft
  }

  Text {
    id: text
    anchors.centerIn: parent
    text: button.label
    color: hover.containsMouse
      ? (button.highlight ? overlay.accent : overlay.fg)
      : overlay.dim
    font.family: overlay.fontFamily
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.activated()
  }
}
