import QtQuick
import QtQuick.Shapes

// Bar glyph: a bell. Off = slashed, watching = faint ring waves,
// live = solid waves plus a dot in the live color.
Item {
  id: root

  property bool watching: false
  property bool live: false
  property bool warning: false
  property color color: "#888888"
  property color liveColor: "#f06a59"
  property color warningColor: "#e7b66b"

  readonly property real s: width / 16
  property real pulse: 1

  SequentialAnimation on pulse {
    running: root.live
    loops: Animation.Infinite
    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
  }

  implicitWidth: 16
  implicitHeight: 16

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.color
      strokeWidth: 1.4 * root.s
      fillColor: "transparent"
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      startX: 3.5 * root.s; startY: 11.5 * root.s
      PathLine { x: 4.5 * root.s; y: 10 * root.s }
      PathLine { x: 4.5 * root.s; y: 7 * root.s }
      PathCubic { x: 8 * root.s; y: 3 * root.s; control1X: 4.5 * root.s; control1Y: 4.6 * root.s; control2X: 6 * root.s; control2Y: 3 * root.s }
      PathCubic { x: 11.5 * root.s; y: 7 * root.s; control1X: 10 * root.s; control1Y: 3 * root.s; control2X: 11.5 * root.s; control2Y: 4.6 * root.s }
      PathLine { x: 11.5 * root.s; y: 10 * root.s }
      PathLine { x: 12.5 * root.s; y: 11.5 * root.s }
      PathLine { x: 3.5 * root.s; y: 11.5 * root.s }
      PathMove { x: 8 * root.s; y: 1.6 * root.s }
      PathLine { x: 8 * root.s; y: 3 * root.s }
      PathMove { x: 6.6 * root.s; y: 13.4 * root.s }
      PathQuad { x: 9.4 * root.s; y: 13.4 * root.s; controlX: 8 * root.s; controlY: 14.8 * root.s }
    }
  }

  // Ring waves on both sides of the bell.
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    visible: root.watching
    opacity: root.live ? root.pulse : 0.25

    ShapePath {
      strokeColor: root.color
      strokeWidth: 1.3 * root.s
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      startX: 2.2 * root.s; startY: 4.6 * root.s
      PathQuad { x: 2.2 * root.s; y: 8.6 * root.s; controlX: 0.8 * root.s; controlY: 6.6 * root.s }
      PathMove { x: 13.8 * root.s; y: 4.6 * root.s }
      PathQuad { x: 13.8 * root.s; y: 8.6 * root.s; controlX: 15.2 * root.s; controlY: 6.6 * root.s }
    }
  }

  // Slash when alerts are off.
  Rectangle {
    visible: !root.watching
    width: 17 * root.s
    height: 1.4 * root.s
    radius: height / 2
    anchors.centerIn: parent
    rotation: 45
    color: root.color
  }

  Rectangle {
    visible: root.watching && (root.live || root.warning)
    width: 4.2 * root.s
    height: width
    radius: width / 2
    x: 11.2 * root.s
    y: 1.2 * root.s
    color: root.warning ? root.warningColor : root.liveColor
  }
}
