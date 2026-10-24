import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "zakarch.fight-bell"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing : false
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: root.injectPanel()
  }

  IpcHandler {
    target: "zakarch.fight-bell.widget"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf0f3"
    iconComponent: bellIcon
    Component {
      id: bellIcon
      BellIcon {
        watching: !!(root.svc && root.svc.monitoring)
        live: !!(root.svc && (root.svc.isLive || root.svc.isWalkout))
        warning: !!(root.svc && (root.svc.error || root.svc.stale))
        color: button.foreground
        liveColor: root.bar ? root.bar.urgent : Color.urgent
      }
    }
    tooltipText: "Fight Bell · " + (root.svc ? root.svc.statusLabel : "OFF")
      + (root.svc && root.svc.monitoring && root.svc.event ? "\n" + root.svc.event.name : "")
      + "\nClick: open · Middle-click: watch / stop"

    onPressed: function(b) {
      if (b === Qt.MiddleButton && root.svc) root.svc.toggle()
      else if (b === Qt.LeftButton) root.togglePanel()
    }
  }
}
