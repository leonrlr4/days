import QtQuick
import qs.Commons

// A small caps label, a hairline, and an optional action on the right.
Item {
  id: header
  required property var overlay
  property string title: ""
  property string trailing: ""
  property bool titleClickable: false
  property bool trailingClickable: false

  signal titleClicked()
  signal trailingClicked()

  height: Style.space(16)

  Text {
    id: label
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    text: header.title.toUpperCase()
    color: header.titleClickable && titleHover.containsMouse ? overlay.fg : overlay.dimmer
    font.family: overlay.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.1

    MouseArea {
      id: titleHover
      anchors.fill: parent
      anchors.margins: -Style.spacing.sm
      enabled: header.titleClickable
      hoverEnabled: true
      onClicked: header.titleClicked()
    }
  }

  Rectangle {
    anchors.left: label.right
    anchors.leftMargin: Style.spacing.lg
    anchors.right: action.left
    anchors.rightMargin: Style.spacing.lg
    anchors.verticalCenter: parent.verticalCenter
    height: 1
    color: overlay.lineSoft
  }

  Text {
    id: action
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    visible: header.trailing !== ""
    text: header.trailing.toUpperCase()
    color: header.trailingClickable && actionHover.containsMouse ? overlay.accent : overlay.dimmer
    font.family: overlay.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 0.6

    MouseArea {
      id: actionHover
      anchors.fill: parent
      anchors.margins: -Style.spacing.sm
      enabled: header.trailingClickable
      hoverEnabled: true
      onClicked: header.trailingClicked()
    }
  }
}
