import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "zakarch.fight-bell"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property int cursor: -1
  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property color fg: Color.popups.text
  readonly property color muted: Util.alpha(fg, 0.58)
  readonly property color liveColor: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color redCorner: "#d94a4a"
  readonly property color blueCorner: "#3d7fe0"
  readonly property string ff: bar ? bar.fontFamily : Style.font.family

  readonly property bool watching: !!(svc && svc.monitoring)
  readonly property bool healthy: !!(watching && svc.lastSuccess && !svc.error && !svc.stale)
  readonly property bool isLive: !!(svc && svc.isLive)
  readonly property bool isWalkout: !!(svc && svc.isWalkout)
  readonly property bool hot: isLive || isWalkout
  readonly property bool warning: !!(watching && (svc.error || svc.stale))
  // Strip, dot and current segment colour: red live, accent walkouts, amber trouble.
  readonly property color stateColor: warning ? "#e0a84e" : isLive ? liveColor : accent
  readonly property var event: healthy ? svc.event : null
  readonly property var fight: healthy ? (svc.currentFight || svc.upcoming[0] || null) : null
  readonly property int boutNumber: fight ? boutOf(fight) : 0
  readonly property var later: healthy
    ? svc.upcoming.filter(function(f) { return !root.fight || f.key !== root.fight.key }).slice(0, 3) : []

  // Repeater hands delegates copies, so fights are matched by key.
  function boutOf(f) {
    if (!event || !f) return 0
    for (var i = 0; i < event.fights.length; i++)
      if (event.fights[i].key === f.key) return i + 1
    return 0
  }

  readonly property string stripText: {
    if (!watching) return "Alerts off"
    if (warning) return "Reconnecting to ESPN"
    if (!svc.lastSuccess) return "Finding the card…"
    if (isLive) return "Live now"
    if (isWalkout) return "Walking out now"
    if (!event) return "No card this week"
    if (!fight) return "Card finished"
    if (svc.cardStarted) return "Between fights · bell is armed"
    return "Starts " + Qt.formatDateTime(new Date(event.date), "ddd d MMM · HH:mm")
  }

  readonly property string message: {
    if (!watching) return "Turn alerts on and go do something else.\nThe bell rings when the fighters walk out."
    if (svc.error) return svc.error
    if (svc.stale) return "Updates are late. Checking the connection…"
    if (!svc.lastSuccess) return "Finding the current UFC card…"
    if (!svc.event) return "No UFC card in the next 7 days."
    if (!fight) return "That's the whole card. See you next fight night."
    return ""
  }

  function sp(px) { return Style.space(px) }

  onOpenedChanged: if (opened) cursor = -1

  function activate() {
    if (!svc) return
    if (cursor === 0) svc.toggle()
    else if (cursor === 1) svc.soundEnabled = !svc.soundEnabled
    else if (cursor === 2) svc.refresh()
    else if (cursor === 3) svc.testAlert()
  }

  // ── reusable bits ─────────────────────────────────────────────────────────
  component Caps: Text {
    textFormat: Text.PlainText
    color: root.muted
    font.family: root.ff
    font.pixelSize: Style.font.caption - 1
    font.bold: true
    font.letterSpacing: 1.4
  }

  component Card: Rectangle {
    radius: root.sp(10)
    color: Util.alpha(root.fg, 0.035)
    border.width: 1
    border.color: Util.alpha(root.fg, 0.07)
  }

  component ActionButton: Rectangle {
    id: ab
    property string label: ""
    property bool lit: false
    signal clicked()
    height: root.sp(30)
    radius: root.sp(8)
    opacity: enabled ? 1 : 0.35
    color: abMouse.pressed ? Util.alpha(root.accent, 0.25)
         : abMouse.containsMouse || lit ? Util.alpha(root.fg, 0.10) : Util.alpha(root.fg, 0.04)
    border.width: 1
    border.color: abMouse.containsMouse || lit ? Util.alpha(root.accent, 0.7) : Util.alpha(root.fg, 0.10)
    Behavior on color { ColorAnimation { duration: 120 } }
    Text {
      anchors.centerIn: parent
      text: ab.label
      color: root.fg
      font.family: root.ff
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
    MouseArea {
      id: abMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ab.clicked()
    }
  }

  // One side of the tale of the tape: corner label, name and colour bar.
  component Corner: Column {
    id: cn
    property string label: ""
    property string name: ""
    property color tint: "white"
    property bool alignRight: false
    spacing: root.sp(6)
    Caps {
      width: parent.width
      text: cn.label
      horizontalAlignment: cn.alignRight ? Text.AlignRight : Text.AlignLeft
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: cn.name
      horizontalAlignment: cn.alignRight ? Text.AlignRight : Text.AlignLeft
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      color: root.fg
      font.family: root.ff
      font.pixelSize: Style.font.heading
      font.bold: true
    }
    Item {
      width: parent.width
      height: root.sp(3)
      Rectangle {
        width: parent.width * 0.4
        height: parent.height
        radius: height / 2
        x: cn.alignRight ? parent.width - width : 0
        color: cn.tint
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(root.sp(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { root.cursor = root.cursor < 0 ? 0 : (root.cursor + (dy || dx) + 4) % 4 }
      onActivateRequested: root.activate()
      onTabRequested: function(d) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.hostWidget || root, d)
      }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: root.sp(10)

        // ── header: bell tile · title · watch switch ──────────────────────
        Item {
          width: parent.width
          height: Math.max(tile.height, watchSwitch.implicitHeight)

          Rectangle {
            id: tile
            width: root.sp(38)
            height: width
            radius: root.sp(10)
            anchors.verticalCenter: parent.verticalCenter
            color: Util.alpha(root.watching ? root.stateColor : root.fg, 0.10)
            border.width: 1
            border.color: Util.alpha(root.watching ? root.stateColor : root.fg, 0.35)
            Behavior on color { ColorAnimation { duration: 200 } }
            BellIcon {
              anchors.centerIn: parent
              width: root.sp(22)
              height: width
              watching: root.watching
              live: root.hot
              warning: root.warning
              color: root.fg
              liveColor: root.liveColor
            }
          }

          Column {
            anchors.left: tile.right
            anchors.leftMargin: root.sp(12)
            anchors.right: watchSwitch.left
            anchors.rightMargin: root.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.sp(3)
            Text {
              text: "Fight Bell"
              color: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Caps {
              width: parent.width
              text: root.event ? root.event.name.toUpperCase() : "UFC WALKOUT ALERTS"
              elide: Text.ElideRight
            }
          }

          ToggleSwitch {
            id: watchSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.watching
            hasCursor: root.cursor === 0
            foreground: root.fg
            onToggled: if (root.svc) root.svc.toggle()
          }
        }

        // ── status strip ──────────────────────────────────────────────────
        Card {
          width: parent.width
          height: root.sp(34)
          radius: height / 2
          color: root.hot || root.warning ? Util.alpha(root.stateColor, 0.12) : Util.alpha(root.fg, 0.035)
          border.color: root.hot || root.warning ? Util.alpha(root.stateColor, 0.6) : Util.alpha(root.fg, 0.07)
          Behavior on color { ColorAnimation { duration: 200 } }

          Rectangle {
            id: dot
            x: root.sp(14)
            anchors.verticalCenter: parent.verticalCenter
            width: root.sp(7)
            height: width
            radius: width / 2
            color: root.watching ? root.stateColor : root.muted
            SequentialAnimation on opacity {
              running: root.hot && root.opened
              loops: Animation.Infinite
              onRunningChanged: if (!running) dot.opacity = 1
              NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
              NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
          }
          Text {
            anchors.left: dot.right
            anchors.leftMargin: root.sp(9)
            anchors.right: boutText.left
            anchors.rightMargin: root.sp(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.stripText
            elide: Text.ElideRight
            color: root.hot || root.warning ? root.stateColor : root.fg
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          Caps {
            id: boutText
            anchors.right: parent.right
            anchors.rightMargin: root.sp(14)
            anchors.verticalCenter: parent.verticalCenter
            text: root.boutNumber ? "BOUT " + root.boutNumber + " / " + root.event.fights.length : ""
          }
        }

        // ── card progress: one segment per bout, no results ───────────────
        Row {
          id: progress
          visible: root.boutNumber > 0
          width: parent.width
          spacing: root.sp(3)
          readonly property int count: root.event ? root.event.fights.length : 0
          Repeater {
            model: root.event ? root.event.fights : []
            Rectangle {
              required property var modelData
              width: (progress.width - progress.spacing * (progress.count - 1)) / Math.max(1, progress.count)
              height: root.sp(4)
              radius: height / 2
              color: root.fight && modelData.key === root.fight.key ? root.stateColor
                : modelData.state === "post" ? Util.alpha(root.fg, 0.35) : Util.alpha(root.fg, 0.08)
            }
          }
        }

        // ── tale of the tape ──────────────────────────────────────────────
        Card {
          visible: !!root.fight
          width: parent.width
          height: tape.y + tape.height + root.sp(16)
          border.color: root.hot ? Util.alpha(root.stateColor, 0.45) : Util.alpha(root.fg, 0.07)

          Caps {
            id: tapeLabel
            x: root.sp(14)
            y: root.sp(14)
            text: root.isLive ? "NOW FIGHTING" : root.isWalkout ? "WALKING OUT" : "UP NEXT"
            color: root.hot ? root.stateColor : root.muted
          }
          Caps {
            anchors.right: parent.right
            anchors.rightMargin: root.sp(14)
            y: root.sp(14)
            visible: !!root.event && root.boutNumber === root.event.fights.length
            text: "MAIN EVENT"
            color: root.accent
          }

          Item {
            id: tape
            x: root.sp(14)
            y: tapeLabel.y + tapeLabel.height + root.sp(12)
            width: parent.width - root.sp(28)
            height: Math.max(red.implicitHeight, blue.implicitHeight, vs.height)

            Corner {
              id: red
              width: (parent.width - vs.width) / 2 - root.sp(8)
              label: "RED CORNER"
              name: root.fight ? root.fight.names[0] : ""
              tint: root.redCorner
            }

            Rectangle {
              id: vs
              anchors.centerIn: parent
              width: root.sp(30)
              height: width
              radius: width / 2
              color: Util.alpha(root.fg, 0.05)
              border.width: 1
              border.color: Util.alpha(root.fg, 0.12)
              Text {
                anchors.centerIn: parent
                text: "VS"
                color: root.muted
                font.family: root.ff
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Corner {
              id: blue
              anchors.right: parent.right
              width: (parent.width - vs.width) / 2 - root.sp(8)
              label: "BLUE CORNER"
              name: root.fight ? root.fight.names[1] : ""
              tint: root.blueCorner
              alignRight: true
            }
          }
        }

        // ── off / empty / error state ─────────────────────────────────────
        Card {
          visible: root.message !== ""
          width: parent.width
          height: messageText.implicitHeight + root.sp(28)
          Text {
            id: messageText
            anchors.centerIn: parent
            width: parent.width - root.sp(28)
            textFormat: Text.PlainText
            text: root.message
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            color: root.muted
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ── rest of the card ──────────────────────────────────────────────
        Card {
          visible: root.later.length > 0
          width: parent.width
          height: laterCol.implicitHeight + root.sp(26)

          Column {
            id: laterCol
            x: root.sp(14)
            y: root.sp(13)
            width: parent.width - root.sp(28)
            spacing: root.sp(9)

            Caps { text: "LATER ON THE CARD" }

            Repeater {
              model: root.later
              Item {
                id: row
                required property var modelData
                readonly property int number: root.boutOf(modelData)
                readonly property bool main: !!root.event && number === root.event.fights.length
                width: laterCol.width
                height: Math.max(num.implicitHeight, names.implicitHeight)

                Text {
                  id: num
                  width: root.sp(24)
                  text: (row.number < 10 ? "0" : "") + row.number
                  color: root.muted
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  id: names
                  anchors.left: num.right
                  anchors.right: mainTag.visible ? mainTag.left : parent.right
                  anchors.rightMargin: mainTag.visible ? root.sp(8) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: row.modelData.names[0] + "  vs  " + row.modelData.names[1]
                  elide: Text.ElideRight
                  color: root.fg
                  font.family: root.ff
                  font.pixelSize: Style.font.bodySmall
                  font.bold: row.main
                }
                Caps {
                  id: mainTag
                  visible: row.main
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: "MAIN"
                  color: root.accent
                }
              }
            }
          }
        }

        // ── settings + actions ────────────────────────────────────────────
        Card {
          width: parent.width
          height: settingsCol.implicitHeight + root.sp(26)

          Column {
            id: settingsCol
            x: root.sp(14)
            y: root.sp(13)
            width: parent.width - root.sp(28)
            spacing: root.sp(12)

            Item {
              width: parent.width
              height: Math.max(bellText.implicitHeight, bellSwitch.implicitHeight)
              Column {
                id: bellText
                anchors.left: parent.left
                anchors.right: bellSwitch.left
                anchors.rightMargin: root.sp(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                  text: "Ring the bell"
                  color: root.fg
                  font.family: root.ff
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  width: parent.width
                  text: "Play a sound with the alert"
                  color: root.muted
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                }
              }
              ToggleSwitch {
                id: bellSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.svc ? root.svc.soundEnabled : true
                hasCursor: root.cursor === 1
                foreground: root.fg
                onToggled: if (root.svc) root.svc.soundEnabled = !root.svc.soundEnabled
              }
            }

            Row {
              width: parent.width
              spacing: root.sp(8)
              ActionButton {
                width: (parent.width - parent.spacing) / 2
                label: root.svc && root.svc.loading ? "Checking…" : "Check now"
                enabled: root.watching && !root.svc.loading
                lit: root.cursor === 2
                onClicked: if (root.svc) root.svc.refresh()
              }
              ActionButton {
                width: (parent.width - parent.spacing) / 2
                label: "Test alert"
                lit: root.cursor === 3
                onClicked: if (root.svc) root.svc.testAlert()
              }
            }
          }
        }

        Caps {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "ESPN · " + (root.watching
              ? "EVERY " + (root.svc.pollInterval >= 60000 ? Math.round(root.svc.pollInterval / 60000) + " MIN" : Math.round(root.svc.pollInterval / 1000) + "S")
                + (root.healthy ? " · UPDATED " + Math.max(0, Math.floor((root.svc.now - root.svc.lastSuccess) / 1000)) + "S AGO" : "")
              : "NO RESULTS SHOWN")
        }
      }
    }
  }
}
