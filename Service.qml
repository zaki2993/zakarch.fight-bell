import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool loaded: false
  property bool monitoring: false
  property bool soundEnabled: true
  property var event: null
  property string error: ""
  property double lastSuccess: 0
  property double now: Date.now()
  property bool initialized: false
  property var seen: ({})

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/zakarch.fight-bell"
  readonly property string statePath: stateDir + "/settings.json"

  readonly property bool loading: fetch.running
  readonly property int pollInterval: !lastSuccess || error ? Model.FAST_POLL : Model.pollInterval(event, now)
  readonly property bool stale: lastSuccess > 0 && now - lastSuccess > pollInterval + 45000
  readonly property var live: Model.liveFights(event)
  readonly property var walkouts: Model.walkoutFights(event)
  readonly property bool isLive: monitoring && !error && !stale && live.length > 0
  readonly property bool isWalkout: monitoring && !error && !stale && !isLive && walkouts.length > 0
  readonly property var currentFight: isLive ? live[0] : isWalkout ? walkouts[0] : null
  readonly property var upcoming: Model.upcomingFights(event)
  readonly property int finishedCount: event ? event.fights.filter(function(f) { return f.state === "post" }).length : 0
  readonly property bool cardStarted: !!event && (finishedCount > 0 || !!currentFight
    || event.fights.some(function(f) { return f.state === "waiting" }))
  readonly property string statusLabel: {
    if (!monitoring) return "OFF"
    if (error || stale) return "RECONNECTING"
    if (!lastSuccess) return "CHECKING"
    if (isLive) return "FIGHT LIVE"
    if (isWalkout) return "WALKOUTS"
    if (!event) return "NO CARD"
    if (!upcoming.length) return "CARD FINISHED"
    if (cardStarted) return "BETWEEN FIGHTS"
    return "WAITING FOR CARD"
  }

  function toggle() {
    monitoring = !monitoring
  }

  function refresh() {
    if (!monitoring || fetch.running) return
    now = Date.now()
    fetch.command = ["curl", "--fail", "--silent", "--show-error", "--location",
      "--connect-timeout", "5", "--max-time", "10", "--max-filesize", "2097152",
      "https://site.api.espn.com/apis/site/v2/sports/mma/ufc/scoreboard?dates=" + Model.dateRange(now) + "&limit=100"]
    fetch.running = true
  }

  function accept(raw) {
    if (!monitoring) return
    try {
      var events = Model.parseScoreboard(raw)
      now = Date.now()
      event = Model.chooseEvent(events, now)
      var result = Model.updateAlerts(event, seen, initialized)
      seen = result.seen
      initialized = true
      error = ""
      lastSuccess = now
      result.alerts.forEach(function(fight) {
        var names = fight.names.map(Model.notificationText).join(" vs. ")
        if (fight.state === "walkout") root.notify("Walkouts started", names + " are walking out — get back to your stream.")
        else root.notify("Fight is live", names + " — switch back to your stream.")
      })
    } catch (e) {
      error = "ESPN sent data Fight Bell can't read. Retrying…"
    }
  }

  function notify(title, body) {
    Quickshell.execDetached(["notify-send", "--app-name=Fight Bell", "--urgency=critical", "--expire-time=0", "--", title, body])
    if (soundEnabled && !bell.running) bell.running = true
  }

  function testAlert() {
    notify("Fight Bell test", "You'll get this alert when the fighters start walking out.")
  }

  // ── persistence ───────────────────────────────────────────────────────────
  function load(raw) {
    var d = {}
    try { d = JSON.parse(raw || "{}") || {} } catch (e) { d = {} }
    soundEnabled = d.soundEnabled !== false
    monitoring = d.monitoring === true
    loaded = true
  }

  function save() {
    if (!loaded) return
    stateFile.setText(JSON.stringify({ version: 1, monitoring: monitoring, soundEnabled: soundEnabled }, null, 2) + "\n")
  }

  onSoundEnabledChanged: save()
  onMonitoringChanged: {
    save()
    if (monitoring) {
      initialized = false
      error = ""
      lastSuccess = 0
      event = null
      Qt.callLater(refresh)
    } else {
      fetch.running = false
      error = ""
    }
  }

  Component.onCompleted: ensureDir.running = true

  Process {
    id: ensureDir
    command: ["mkdir", "-p", root.stateDir]
    onExited: stateFile.reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.load(text())
    onLoadFailed: root.load("{}")
  }

  Process {
    id: fetch
    stdout: StdioCollector {
      id: response
      waitForEnd: true
      onStreamFinished: if (text.trim()) root.accept(text)
    }
    stderr: StdioCollector {}
    onExited: function(exitCode) {
      if (root.monitoring && (exitCode !== 0 || !response.text.trim()))
        root.error = "Can't reach ESPN. Retrying…"
    }
  }

  Process {
    id: bell
    command: ["paplay", "/usr/share/sounds/freedesktop/stereo/bell.oga"]
  }

  Timer {
    interval: root.pollInterval
    running: root.monitoring
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 1000
    running: root.monitoring
    repeat: true
    onTriggered: root.now = Date.now()
  }

  IpcHandler {
    target: "zakarch.fight-bell"
    function start(): void { root.monitoring = true }
    function stop(): void { root.monitoring = false }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function test(): void { root.testAlert() }
    function status(): string {
      return JSON.stringify({ monitoring: root.monitoring, sound: root.soundEnabled, status: root.statusLabel,
        event: root.event ? root.event.name : "", pollMs: root.pollInterval,
        lastSuccess: root.lastSuccess, error: root.error })
    }
  }
}
