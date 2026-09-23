.pragma library

// Reader side. Turns the TSV written by sample.sh into per-discharge figures:
// time since unplugging, awake time, energy used.
// Awake time = sum of (jiffies delta / HZ) over adjacent samples. jiffies only
// advances while the machine is awake, freezes during suspend and resets on boot
// (detected via the boot column), so missed samples do not matter: the next one
// carries the full difference.
// The optional ninth column (settings) is the sleep action policy in effect at
// sample time ("bt=off;wifi=keep"), added by the renamed fork; older rows have
// eight fields and get an empty string.

var SANE_WALL = 1500000000      // 2017. Rows written before NTP sync at boot are garbage
var WH_JITTER = 1.0             // Energy rising by more than this while discharging = charged in between. The gauge itself drifts ±0.6
var SLEEP_GAP = 120             // Wall delta exceeding jiffies delta by more than this many seconds = slept in between
var MIN_HIST_AWAKE = 600        // All-time average only counts sessions awake for ≥10 minutes
var HZ_CANDIDATES = [100, 250, 300, 1000]

function parseRow(line) {
  var p = String(line).split("\t")
  if (p.length < 8 || !/^\d+$/.test(p[0])) return null
  var wall = parseInt(p[0], 10)
  if (wall < SANE_WALL) return null
  return {
    wall: wall, jiffies: parseFloat(p[1]), boot: p[2],
    pct: p[3], state: p[4], ac: p[5],
    wh: p[6] === "" ? null : parseFloat(p[6]),
    pw: p[7] === "" || p[7] === undefined ? null : parseFloat(p[7]),
    settings: p.length >= 9 ? String(p[8]) : ""
  }
}

// The file is appended in time order already; do not sort. Sorting by wall would
// scramble rows around a wall-clock jump.
function parseRows(text) {
  var out = [], seen = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var r = parseRow(lines[i])
    if (!r || seen[r.wall]) continue
    seen[r.wall] = true
    out.push(r)
  }
  return out
}

function appendRow(rows, r) {
  if (!r) return rows
  if (rows.length && rows[rows.length - 1].wall === r.wall) return rows
  return rows.concat([r])
}

// HZ = jiffies delta / seconds delta, median over adjacent pairs about a minute
// apart, snapped to a common kernel value. Pairs spanning a suspend have a huge
// wall delta and are dropped by dw <= 130; anything that slips through is
// absorbed by the median.
function detectHz(rows) {
  var rates = []
  for (var i = 1; i < rows.length; i++) {
    var a = rows[i - 1], b = rows[i]
    if (a.boot !== b.boot) continue
    var dw = b.wall - a.wall
    if (dw < 30 || dw > 130) continue
    rates.push((b.jiffies - a.jiffies) / dw)
  }
  if (!rates.length) return 0
  rates.sort(function(x, y) { return x - y })
  var med = rates[Math.floor(rates.length / 2)]
  var best = HZ_CANDIDATES[0]
  for (var k = 1; k < HZ_CANDIDATES.length; k++)
    if (Math.abs(HZ_CANDIDATES[k] - med) < Math.abs(best - med)) best = HZ_CANDIDATES[k]
  return best
}

function onBattery(r) {
  return (r.ac === "0" || r.ac === "1") ? r.ac === "0" : r.state === "Discharging"
}

// Split rows into discharge sessions. A session ends when ac flips back to 1.
// It also ends when there is a sampling gap (> SLEEP_GAP) AND stored energy went
// up: the charger was plugged and unplugged while nobody was looking. With
// continuous sampling ac is trusted as-is: a heavy load depresses the gauge
// reading temporarily and it bounces back by 1+ Wh when the load drops, which
// must not be mistaken for charging (this misfired once on real data, 2026-09-03).
// If the row where ac flips to 1 has less energy than the last discharging row,
// it is absorbed as the session end point: no samples are taken while asleep or
// after running flat, and without this the energy and time lost overnight vanish.
function sessions(rows) {
  var out = [], cur = []
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (!onBattery(r)) {
      if (cur.length) {
        var last = cur[cur.length - 1]
        if (last.wh !== null && r.wh !== null && r.wh < last.wh) cur.push(r)
        out.push(cur)
      }
      cur = []
      continue
    }
    if (cur.length && cur[cur.length - 1].wh !== null && r.wh !== null
        && r.wall - cur[cur.length - 1].wall > SLEEP_GAP
        && r.wh > cur[cur.length - 1].wh + WH_JITTER) {
      out.push(cur)
      cur = []
    }
    cur.push(r)
  }
  if (cur.length) out.push(cur)
  return out
}

function awakeSecs(seg, hz) {
  var total = 0
  for (var i = 1; i < seg.length; i++) {
    var a = seg[i - 1], b = seg[i]
    if (a.boot !== b.boot) continue            // Across a reboot: counter reset, and the machine was off
    var d = (b.jiffies - a.jiffies) / hz
    var dw = b.wall - a.wall
    if (d > 0) total += dw > 0 ? Math.min(d, dw) : d   // Normally d ≤ dw, clamp to dw; if wall went backwards trust jiffies alone
  }
  return total
}

// Energy used while awake: sum Wh deltas only over adjacent pairs with no sleep
// in between. Suspend draws about 1 W, and since the denominator is awake time
// only, mixing it in overstates average power by ~20% and understates time left.
// Energy used while asleep is reported separately as sleptWh.
function awakeWh(seg, hz) {
  var total = 0
  for (var i = 1; i < seg.length; i++) {
    var a = seg[i - 1], b = seg[i]
    if (a.wh === null || b.wh === null || a.boot !== b.boot) continue
    var d = (b.jiffies - a.jiffies) / hz, dw = b.wall - a.wall
    if (dw - d > SLEEP_GAP) continue
    if (a.wh > b.wh) total += a.wh - b.wh
  }
  return total
}

function summarizeSeg(seg, hz, live, now) {
  var start = seg[0], end = seg[seg.length - 1]
  var wall = (live ? now : end.wall) - start.wall
  var awake = awakeSecs(seg, hz)
  var used = (start.wh !== null && end.wh !== null) ? start.wh - end.wh : null
  if (used !== null && used <= 0) used = null
  var aw = used !== null ? Math.min(used, awakeWh(seg, hz)) : null
  return {
    live: live,
    startWall: start.wall, endWall: end.wall,
    startPct: start.pct, endPct: end.pct,
    wallSecs: wall, awakeSecs: awake, sleptSecs: Math.max(0, wall - awake),
    usedWh: used, awakeWh: aw,
    sleptWh: used !== null ? used - aw : null,
    avgW: (aw !== null && aw > 0 && awake > 0) ? aw * 3600 / awake : null
  }
}

// Main entry. state: "empty" no data / "calibrating" HZ not determined yet / "ok"
function summarize(rows, now) {
  var hz = detectHz(rows)
  var segs = sessions(rows)
  var last = rows.length ? rows[rows.length - 1] : null
  var live = last ? onBattery(last) : false
  var out = { state: rows.length ? (hz ? "ok" : "calibrating") : "empty",
              hz: hz, live: live, current: null, history: [], lastWall: last ? last.wall : 0 }
  if (!hz || !segs.length) return out
  var all = []
  for (var i = 0; i < segs.length; i++)
    all.push(summarizeSeg(segs[i], hz, live && i === segs.length - 1, now))
  out.current = all[all.length - 1]
  // History: excludes the current session, at most 8. Short ones are listed too
  out.history = all.slice(0, -1)
  out.history = out.history.slice(Math.max(0, out.history.length - 8)).reverse()

  // All-time average power: awake Wh over all sessions (current included) / total awake seconds.
  // Long sessions naturally weigh more
  var wh = 0, secs = 0
  for (var k = 0; k < all.length; k++) {
    if (all[k].awakeWh === null || all[k].awakeSecs < MIN_HIST_AWAKE) continue
    wh += all[k].awakeWh; secs += all[k].awakeSecs
  }
  out.histAvgW = secs > 0 ? wh * 3600 / secs : null

  // Time left = remaining Wh / power. Only meaningful while discharging with a known energy level
  var lastWh = rows[rows.length - 1].wh
  if (live && lastWh !== null) {
    var c = out.current
    c.remainWh = lastWh
    c.nowW = rows[rows.length - 1].pw !== null ? Math.abs(rows[rows.length - 1].pw) : null   // Instantaneous power from the last sample
    c.remainCurSecs = c.avgW ? lastWh * 3600 / c.avgW : null
    c.remainHistSecs = out.histAvgW ? lastWh * 3600 / out.histAvgW : null
  }
  return out
}

function hm(s) {
  s = Math.max(0, Math.floor(s))
  var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
  return h + "h " + (m < 10 ? "0" : "") + m + "m"
}

function pad2(n) { return (n < 10 ? "0" : "") + n }

function clock(wall) {
  var d = new Date(wall * 1000)
  return pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) + " " + pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}
