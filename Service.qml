import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Sampler and sleep action service. The shell creates exactly one of these
// (unlike bar widgets, which exist once per screen).
//
// Sampling: every 60 seconds it runs sample.sh, appends the returned line to
// the in-memory list and recomputes the summary for widgets. On wake the
// watcher reports resume, which takes one sample right away so the finished
// sleep stops looking undetected; the regular tick then restarts so its next
// sample is a full interval later (that one refines the energy figure).
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
  readonly property int resumeSampleDelayMs: 3000 // pause after wake so the battery driver is readable
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
  // Per-group stat cutoffs: {group: wall}. Periods of that type starting at or
  // before the wall are left out of the summary (see Model.sleepPeriods).
  property var deletedGroups: ({})
  property bool sleepWatchRunning: false
  property string sleepError: ""
  property string dataDir: ""
  property var setQueue: []
  property bool destroying: false
  readonly property alias clearing: clearProc.running

  function recompute() {
    root.summary = Model.summarize(root.rows, Math.floor(Date.now() / 1000), root.deletedGroups)
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
  Watchdog { id: pathWatch }
  Watchdog { id: deletedWatch }
  Watchdog { id: deleteWatch }

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

  // The watcher reports a wake the moment logind says the machine is awake.
  // Sampling right away (after a short pause for the battery driver) makes the
  // just-finished sleep appear in the stats instead of looking undetected for
  // up to a minute. Restarting tick keeps the next regular sample a full
  // interval away, and that sample is the one the gauge settle correction in
  // Model.sleepPeriods() uses to get the energy right.
  Timer {
    id: resumeSample
    interval: root.resumeSampleDelayMs
    onTriggered: {
      if (!root.loaded) return
      root.sample()
      tick.restart()
    }
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
        root.deletedGroups = ({})
        root.recompute()
      } else if (status === 0) {
        root.sleepError = "errSleepActions"
      }
    }
  }

  // ---- per-group stat delete ----
  // sleepctl.sh stores a cutoff per group; periods of that type starting at or
  // before it are left out of the summary. The samples stay on disk, so the
  // sessions and awake-time figures keep working, and new sleeps of the same
  // type measure fresh.
  function parseDeleted(text) {
    var out = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var kv = lines[i].split("=")
      if (kv.length !== 2) continue
      if (kv[0] !== "none" && kv[0] !== "bt" && kv[0] !== "wifi" && kv[0] !== "both") continue
      var w = parseInt(kv[1], 10)
      if (!isFinite(w) || w <= 1500000000) continue
      out[kv[0]] = w
    }
    return out
  }

  function refreshDeleted() {
    if (deletedProc.running || deleteProc.running) return
    deletedProc.command = root.scriptCommand("sleepctl.sh").concat(["deleted"])
    deletedProc.running = true
  }

  function deleteGroup(key) {
    if (key !== "none" && key !== "bt" && key !== "wifi" && key !== "both") return
    if (deleteProc.running) return
    var next = {}
    for (var k in root.deletedGroups) next[k] = root.deletedGroups[k]
    next[key] = Math.floor(Date.now() / 1000)
    root.deletedGroups = next               // optimistic; the file is the truth
    root.recompute()
    deleteProc.command = root.scriptCommand("sleepctl.sh").concat(["delete", key])
    deleteProc.running = true
  }

  Process {
    id: deletedProc
    running: true
    command: root.scriptCommand("sleepctl.sh").concat(["deleted"])
    clearEnvironment: true
    environment: root.cleanEnvironment
    stdinEnabled: false
    stderr: null
    stdout: StdioCollector {
      onStreamFinished: {
        root.deletedGroups = root.parseDeleted(String(text))
        root.recompute()
      }
    }
    onStarted: deletedWatch.arm(deletedProc, root.helperDeadlineSec)
    onExited: function(code, status) { deletedWatch.disarm() }
  }

  Process {
    id: deleteProc
    running: false
    clearEnvironment: true
    environment: root.cleanEnvironment
    stdinEnabled: false
    stdout: null
    stderr: null
    onStarted: deleteWatch.arm(deleteProc, root.helperDeadlineSec)
    onExited: function(code, status) {
      deleteWatch.disarm()
      if (status === 0 && code !== 0) root.sleepError = "errSleepActions"
      root.refreshDeleted()
    }
  }

  // ---- database folder (Folder link in the panel) ----
  // One detached xdg-open; no watchdog, and the path comes from sleepctl.sh so
  // there is only one place that knows where the data lives.
  function openDataDir() {
    if (root.dataDir === "") return
    Quickshell.execDetached(["xdg-open", root.dataDir])
  }

  Process {
    id: pathProc
    running: true
    command: root.scriptCommand("sleepctl.sh").concat(["path"])
    clearEnvironment: true
    environment: root.cleanEnvironment
    stdinEnabled: false
    stderr: null
    stdout: StdioCollector {
      onStreamFinished: {
        var line = String(text).trim().split("\n")[0]
        if (line.charAt(0) === "/") root.dataDir = line
      }
    }
    onStarted: pathWatch.arm(pathProc, root.helperDeadlineSec)
    onExited: function(code, status) { pathWatch.disarm() }
  }

  // ---- sleep watcher ----
  Process {
    id: sleepWatchProc
    running: true
    command: root.scriptCommand("sleep-watch.sh")
    clearEnvironment: true
    environment: root.cleanEnvironment
    stdinEnabled: false
    // sleep-watch.sh prints "resume" after PrepareForSleep(false); ignore
    // anything else on this channel.
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).trim() !== "resume") return
        resumeSample.restart()
      }
    }
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
    if (pathProc.running) pathProc.signal(15)
    if (sleepWatchProc.running) sleepWatchProc.signal(15)
    root.setQueue = []
  }
}
