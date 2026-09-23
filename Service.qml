import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Sampler and sleep action service. The shell creates exactly one of these
// (unlike bar widgets, which exist once per screen).
//
// Sampling: every 60 seconds it runs sample.sh, appends the returned line to
// the in-memory list and recomputes the summary for widgets.
//
// Sleep actions: a long-lived sleep-watch.sh listens on the system bus for
// logind's PrepareForSleep and runs sleepctl.sh apply-pre / apply-post, which
// block and restore the radios selected in the popup (Bluetooth, Wi-Fi). The
// watcher also reconciles leftovers on start and stop, so a radio is never
// left blocked without a listener. Nothing here waits for a suspend: if either
// helper fails or is killed, sleep behaves as if the plugin were not running.
//
// Process hygiene: the only children are /usr/bin/bash by absolute path,
// started with a cleared environment (PATH=/usr/bin, LC_ALL=C, TZ), no profile
// or rc files, stdin and stderr closed, and explicit teardown on destruction.
// The two short-lived helpers get a hard deadline (TERM then KILL); the
// watcher is meant to run for the session and is restarted if it exits.
// sample.sh, sleepctl.sh and sleep-watch.sh are bash builtins plus /usr/bin/dd,
// /usr/bin/mkdir, /usr/bin/rm, /usr/bin/mv, /usr/bin/rfkill, /usr/bin/timeout,
// /usr/bin/sleep, /usr/bin/dbus-monitor and /usr/bin/bash by absolute path;
// every file they open uses O_NOFOLLOW and O_NONBLOCK, and every read is
// capped (see the scripts). Nothing here touches the data files directly.
Item {
  id: root

  property var shell: null

  readonly property string samplerPath: String(Qt.resolvedUrl("sample.sh")).replace(/^file:\/\//, "")
  readonly property string pluginDir: root.samplerPath.replace(/\/[^\/]+$/, "")
  readonly property int intervalSec: 60
  readonly property int sampleDeadlineSec: 20     // sample.sh normally finishes in well under a second
  readonly property int loadDeadlineSec: 30
  readonly property int helperDeadlineSec: 10     // sleepctl.sh get/set
  // sample.sh load emits at most 3 files x 4 MiB; anything larger is not our sampler.
  readonly property int maxLoadChars: 3 * 4194304 + 64
  readonly property int maxRows: 150000           // ~3.4 months at one row per minute
  readonly property int maxLineChars: 256

  property var rows: []
  property var summary: Model.summarize([], 0)
  property bool loaded: false
  property string lastError: ""

  // Sleep action state, mirrored from sleepctl.sh get. Keys are the settings
  // file keys, values are "keep" or "off".
  property var sleepOptions: ({ bluetooth: "keep", wifi: "keep" })
  property bool sleepWatchRunning: false
  property string sleepError: ""
  property var setQueue: []
  property bool destroying: false
  readonly property alias clearing: clearProc.running

  function recompute() {
    root.summary = Model.summarize(root.rows, Math.floor(Date.now() / 1000))
  }
  function capRows(list) {
    return list.length > root.maxRows ? list.slice(list.length - root.maxRows) : list
  }

  // ---- shared process settings ----
  readonly property var bashCommand: ["/usr/bin/bash", "--noprofile", "--norc", root.samplerPath]
  // TZ is passed through (null = system value) so the month file names the
  // sampler uses match the calendar the user sees.
  readonly property var cleanEnvironment: ({ PATH: "/usr/bin", LC_ALL: "C", TZ: null })

  function scriptCommand(name) {
    return ["/usr/bin/bash", "--noprofile", "--norc", root.pluginDir + "/" + name]
  }

  // Hard deadline for whichever process is running: TERM, then KILL 5 s later.
  property var watched: null
  function watch(proc, secs) { root.watched = proc; deadline.interval = secs * 1000; deadline.restart() }
  Timer {
    id: deadline
    onTriggered: if (root.watched && root.watched.running) { root.watched.signal(15); killer.restart() }
  }
  Timer {
    id: killer
    interval: 5000
    onTriggered: if (root.watched && root.watched.running) root.watched.signal(9)
  }
  function unwatch() { deadline.stop(); killer.stop(); root.watched = null }

  // Same idea for the sleep helpers, but one watchdog per process so a slow
  // sampler never expires a toggle click or the other way around. Item (not
  // QtObject): the Timers below need an object with a default property.
  component Watchdog: Item {
    id: watchdog
    visible: false
    implicitWidth: 0
    implicitHeight: 0
    property var proc: null
    property int secs: 20
    Timer {
      id: grace
      interval: watchdog.secs * 1000
      onTriggered: if (watchdog.proc && watchdog.proc.running) { watchdog.proc.signal(15); hard.restart() }
    }
    Timer {
      id: hard
      interval: 5000
      onTriggered: if (watchdog.proc && watchdog.proc.running) watchdog.proc.signal(9)
    }
    function arm(p, s) { watchdog.proc = p; watchdog.secs = s; grace.restart() }
    function disarm() { grace.stop(); hard.stop(); watchdog.proc = null }
  }
  Watchdog { id: optionsWatch }
  Watchdog { id: setWatch }
  Watchdog { id: clearWatch }

  // ---- startup: bounded history dump, then the first sample ----
  Process {
    id: loadProc
    running: true
    command: root.bashCommand.concat(["load"])
    clearEnvironment: true
    environment: root.cleanEnvironment
    stdinEnabled: false
    stderr: null
    stdout: StdioCollector {
      onStreamFinished: {
        var t = String(text)
        root.rows = t.length <= root.maxLoadChars ? root.capRows(Model.parseRows(t)) : []
      }
    }
    onStarted: root.watch(loadProc, root.loadDeadlineSec)
    onExited: function(code, status) {
      root.unwatch()
      root.loaded = true
      root.recompute()
      root.sample()
    }
  }

  // ---- sampling ----
  function sample() {
    if (sampleProc.running || loadProc.running) return
    sampleProc.running = true
  }

  Timer {
    id: tick
    interval: root.intervalSec * 1000
    running: root.loaded
    repeat: true
    onTriggered: root.sample()
  }

  // Settings can change from outside the UI (CLI, or a leftover restore after
  // sleep); re-read the file so the dropdown never shows a stale value.
  Timer {
    interval: 30000
    running: root.loaded
    repeat: true
    onTriggered: root.refreshSleepOptions()
  }

  Process {
    id: sampleProc
    running: false
    command: root.bashCommand
    clearEnvironment: true
    environment: root.cleanEnvironment
    stdinEnabled: false
    stderr: null
    stdout: StdioCollector {
      onStreamFinished: {
        var line = String(text).trim()
        if (line.length > root.maxLineChars) return      // not our sampler's output: ignore
        var r = Model.parseRow(line)
        if (!r) return
        root.rows = root.capRows(Model.appendRow(root.rows, r))
        root.recompute()
      }
    }
    onStarted: root.watch(sampleProc, root.sampleDeadlineSec)
    onExited: function(code, status) {
      root.unwatch()
      root.lastError = status !== 0 ? "errKilled"
        : code === 0 ? ""
        : code === 3 ? "errNoBattery"     // translated by the widget
        : code === 4 ? "errClock"
        : code === 5 ? "errDataDir"
        : "sample.sh exit " + code
    }
  }

  // ---- sleep action settings ----
  function parseSleepOptions(text) {
    var out = { bluetooth: "keep", wifi: "keep" }
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var p = lines[i].split("=")
      if (p.length !== 2) continue
      if (p[1] !== "keep" && p[1] !== "off") continue
      if (p[0] === "bluetooth" || p[0] === "wifi") out[p[0]] = p[1]
    }
    return out
  }

  function refreshSleepOptions() {
    if (optionsProc.running || setOptionProc.running) return
    optionsProc.command = root.scriptCommand("sleepctl.sh").concat(["get"])
    optionsProc.running = true
  }

  function pumpSetQueue() {
    if (setOptionProc.running || root.setQueue.length === 0) return
    var req = root.setQueue[0]
    root.setQueue = root.setQueue.slice(1)
    setOptionProc.command = root.scriptCommand("sleepctl.sh").concat(["set", req[0], req[1]])
    setOptionProc.running = true
  }

  function setSleepOption(key, value) {
    if (key !== "bluetooth" && key !== "wifi") return
    if (value !== "keep" && value !== "off") return
    var next = { bluetooth: root.sleepOptions.bluetooth, wifi: root.sleepOptions.wifi }
    next[key] = value
    root.sleepOptions = next                 // optimistic; the file is the truth
    root.setQueue = root.setQueue.concat([[key, value]])
    root.pumpSetQueue()
  }

  Process {
    id: optionsProc
    running: true
    command: root.scriptCommand("sleepctl.sh").concat(["get"])
    clearEnvironment: true
    environment: root.cleanEnvironment
    stdinEnabled: false
    stderr: null
    stdout: StdioCollector {
      onStreamFinished: root.sleepOptions = root.parseSleepOptions(String(text))
    }
    onStarted: optionsWatch.arm(optionsProc, root.helperDeadlineSec)
    onExited: function(code, status) { optionsWatch.disarm() }
  }

  Process {
    id: setOptionProc
    running: false
    clearEnvironment: true
    environment: root.cleanEnvironment
    stdinEnabled: false
    stderr: null
    stdout: StdioCollector {
      onStreamFinished: root.sleepOptions = root.parseSleepOptions(String(text))
    }
    onStarted: setWatch.arm(setOptionProc, root.helperDeadlineSec)
    onExited: function(code, status) {
      setWatch.disarm()
      if (status === 0 && code !== 0) root.sleepError = "errSleepActions"
      root.pumpSetQueue()
      root.refreshSleepOptions()
    }
  }

  // ---- clear the recorded stats ----
  function clearStats() {
    if (clearProc.running) return
    clearProc.command = root.scriptCommand("sleepctl.sh").concat(["clear"])
    clearProc.running = true
  }

  Process {
    id: clearProc
    running: false
    clearEnvironment: true
    environment: root.cleanEnvironment
    stdinEnabled: false
    stdout: null
    stderr: null
    onStarted: clearWatch.arm(clearProc, root.helperDeadlineSec)
    onExited: function(code, status) {
      clearWatch.disarm()
      if (status === 0 && code === 0) {
        root.rows = []
        root.recompute()
      } else if (status === 0) {
        root.sleepError = "errSleepActions"
      }
    }
  }

  // ---- sleep watcher ----
  Process {
    id: sleepWatchProc
    running: true
    command: root.scriptCommand("sleep-watch.sh")
    clearEnvironment: true
    environment: root.cleanEnvironment
    stdinEnabled: false
    stdout: null
    stderr: null
    onStarted: { root.sleepWatchRunning = true; root.sleepError = "" }
    onExited: function(code, status) {
      root.sleepWatchRunning = false
      if (root.destroying) return
      if (status === 0 && code !== 0) root.sleepError = "errSleepWatch"
      watchRestart.restart()
    }
  }
  Timer {
    id: watchRestart
    interval: 2000
    onTriggered: if (!root.destroying) sleepWatchProc.running = true
  }

  Component.onDestruction: {
    root.destroying = true
    tick.stop(); deadline.stop(); killer.stop(); watchRestart.stop()
    optionsWatch.disarm(); setWatch.disarm()
    if (sampleProc.running) sampleProc.signal(15)
    if (loadProc.running) loadProc.signal(15)
    if (optionsProc.running) optionsProc.signal(15)
    if (setOptionProc.running) setOptionProc.signal(15)
    if (clearProc.running) clearProc.signal(15)
    if (sleepWatchProc.running) sleepWatchProc.signal(15)
    root.setQueue = []
  }
}
