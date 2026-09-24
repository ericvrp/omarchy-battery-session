// Session-splitting tests for Model.js sessions(). Developer tool: node tests/cases.js
// The plugin itself does not need node; this works because Model.js is plain JS.
const fs = require("fs"), vm = require("vm"), path = require("path")

const ctx = {}
vm.createContext(ctx)
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma.*$/m, ""), ctx)

// Each row: [minute, ac, wh, wasAsleep]. jiffies only advances while awake.
const T0 = 1788400000, HZ = 1000
function rows(spec) {
  let jif = 1e9, prev = 0, out = []
  for (const [min, ac, wh, asleep] of spec) {
    jif += asleep ? 0 : (min - prev) * 60 * HZ
    out.push({ wall: T0 + min * 60, jiffies: jif, boot: "b", pct: "50",
               state: ac === "1" ? "Charging" : "Discharging", ac, wh, pw: -5 })
    prev = min
  }
  return out
}

// Expected = one "startWh→endWh" per session
const cases = [
  ["continuous sampling, gauge bounces up 1.3 after a heavy load: not charging",
   rows([[0,"0",26.0],[1,"0",25.7],[2,"0",27.0],[3,"0",26.9]]), ["26→26.9"]],
  ["shell down for two hours, charged and unplugged in between",
   rows([[0,"0",20.5],[1,"0",20.0],[121,"0",35.0],[122,"0",34.9]]), ["20.5→20", "35→34.9"]],
  ["plugged in normally, ac flips to 1 and ends the session",
   rows([[0,"0",20.5],[1,"0",20.0],[2,"1",20.1],[3,"1",20.5]]), ["20.5→20"]],
  ["slept one hour, no charger",
   rows([[0,"0",20.5],[1,"0",20.0],[61,"0",19.2,1],[62,"0",19.1]]), ["20.5→19.1"]],
  ["slept one hour on charger, still plugged on wake; the ac=1 row is absorbed only if lower, here it is higher",
   rows([[0,"0",20.5],[1,"0",20.0],[61,"1",35.0,1],[62,"1",35.5]]), ["20.5→20"]],
  ["slept one hour on charger, unplugged before wake",
   rows([[0,"0",20.5],[1,"0",20.0],[61,"0",35.0,1],[62,"0",34.9]]), ["20.5→20", "35→34.9"]],
  ["charged only 0.5 Wh while asleep, below threshold, known miss",
   rows([[0,"0",20.5],[1,"0",20.0],[61,"0",20.5,1],[62,"0",20.4]]), ["20.5→20.4"]],
  ["drained while asleep or off, plugged in on wake: ac=1 row absorbed as end point",
   rows([[0,"0",20.5],[1,"0",20.0],[481,"1",5.0,1],[482,"1",5.5]]), ["20.5→5"]],
]

let fail = 0
for (const [name, rs, want] of cases) {
  const got = ctx.sessions(rs).map(s => `${s[0].wh}→${s[s.length - 1].wh}`)
  const ok = JSON.stringify(got) === JSON.stringify(want)
  if (!ok) fail++
  console.log(`${ok ? "ok  " : "FAIL"} ${name}`)
  if (!ok) console.log(`       want ${want.join(" | ")}\n       got  ${got.join(" | ")}`)
}

// parseRow: the optional ninth column is kept; pre-fork rows still parse.
const parseCases = [
  ["eight columns (pre-fork row)", "1788400000\t1000\tb\t50\tDischarging\t0\t20.0\t-5.0", ""],
  ["nine columns with settings", "1788400000\t1000\tb\t50\tDischarging\t0\t20.0\t-5.0\tbt=off;wifi=keep", "bt=off;wifi=keep"],
]
for (const [name, line, want] of parseCases) {
  const r = ctx.parseRow(line)
  const got = r ? r.settings : null
  const ok = got === want
  if (!ok) fail++
  console.log(`${ok ? "ok  " : "FAIL"} parseRow ${name}`)
  if (!ok) console.log(`       want ${JSON.stringify(want)} got ${JSON.stringify(got)}`)
}

// sleepPeriods: only on-battery windows of at least five minutes with an
// energy drop, carrying the settings column of the pre-sleep sample.
function check(ok, name, extra) {
  if (!ok) fail++
  console.log(`${ok ? "ok  " : "FAIL"} ${name}`)
  if (!ok && extra) console.log(`       ${extra}`)
}
const sleepRows = rows([[0, "0", 20.5], [1, "0", 20.0], [61, "0", 18.0, 1], [62, "0", 18.0]])
sleepRows[1].settings = "bt=off;wifi=keep"
sleepRows[2].pw = 0            // no awake energy between wake-up and the settled sample
sleepRows[3].pw = 0
const sp = ctx.sleepPeriods(sleepRows, HZ)
check(sp.length === 1 && Math.abs(sp[0].avgW - 2.0) < 0.001
      && sp[0].settings.bluetooth === "off" && sp[0].settings.wifi === "keep"
      && sp[0].group === "bt",
      "sleepPeriods: 60 min, 2 Wh, bluetooth off recorded", JSON.stringify(sp))
// Gauge settling: the first post-wake sample understates the drain; a normal
// sample one minute later is used instead, minus the energy spent awake.
const settleRows = rows([[0, "0", 20.5], [1, "0", 20.0], [61, "0", 19.4, 1], [62, "0", 18.9]])
const settled = ctx.sleepPeriods(settleRows, HZ)
check(settled.length === 1 && Math.abs(settled[0].avgW - 1.0167) < 0.01,
      "sleepPeriods: settled sample corrects the post-wake gauge lag",
      settled.length ? String(settled[0].avgW) : "no period")
const spNoSettings = ctx.sleepPeriods(rows([[0, "0", 20.5], [1, "0", 20.0], [61, "0", 18.0, 1]]), HZ)
check(spNoSettings.length === 1 && spNoSettings[0].settings.bluetooth === null
      && spNoSettings[0].group === "unknown",
      "sleepPeriods: missing settings column reads as unrecorded")
const charger = ctx.sleepPeriods(rows([[0, "1", 20.5], [1, "1", 20.0], [61, "1", 18.0, 1]]), HZ)
check(charger.length === 1 && charger[0].charger === true && charger[0].avgW === null
      && charger[0].group === "charger",
      "sleepPeriods: on-charger window kept without a power figure")
const shortGap = ctx.sleepPeriods(rows([[0, "0", 20.5], [1, "0", 20.4], [3, "0", 20.3, 1]]), HZ)
const shortExpected = 120 < ctx.MIN_SLEEP ? 0 : 1
check(shortGap.length === shortExpected
      && (shortExpected === 0 || (shortGap[0].avgW === null && shortGap[0].usedWh === null)),
      "sleepPeriods: " + ctx.MIN_SLEEP + "s minimum respected; below "
      + ctx.MIN_MEASURE + "s listed without reading")
// Two rows a suspend apart must not be mistaken for a normal sampling pair.
const span = [
  { wall: T0, jiffies: 1e9, boot: "b", pct: "50", state: "Discharging", ac: "0", wh: 20.5, pw: -5, settings: "" },
  { wall: T0 + 95, jiffies: 1e9 + 58680, boot: "b", pct: "50", state: "Discharging", ac: "0", wh: 20.0, pw: -5, settings: "" }
]
check(ctx.detectHz(span) === 0, "detectHz: suspend-spanning pair rejected")
const sum = ctx.summarize(sleepRows, T0 + 4000)
check(sum.sleepGroups.length === 1 && sum.sleepGroups[0].key === "bt"
      && Math.abs(sum.sleepGroups[0].avgW - 2.0) < 0.01,
      "summarize: periods grouped by turned-off setting with a group average")
check(ctx.chargeKind({ state: "Discharging", ac: "0" }) === "discharging"
      && ctx.chargeKind({ state: "Charging", ac: "1" }) === "charging"
      && ctx.chargeKind({ state: "Full", ac: "1" }) === "full"
      && ctx.chargeKind({ state: "Not charging", ac: "1" }) === "full",
      "chargeKind: discharging / charging / full")

// chargeThresholdActive: charge-limit handling for the live bar icon.
const T = { Charging: 1, Discharging: 2, FullyCharged: 3, PendingCharge: 4 }
const thresholdCases = [
  ["on battery never counts as a limit", { isPresent: true, percentage: 0.8, state: T.Charging }, true, false],
  ["discharging with a charger present is not a limit", { isPresent: true, percentage: 0.8, state: T.Discharging }, false, false],
  ["FullyCharged below 99% on plug-in is a limit (anti-flash)", { isPresent: true, percentage: 0.8, state: T.FullyCharged }, false, true],
  ["PendingCharge is a limit", { isPresent: true, percentage: 0.8, state: T.PendingCharge }, false, true],
  ["Charging with no energy flowing is a limit", { isPresent: true, percentage: 0.8, state: T.Charging, changeRate: 0 }, false, true],
  ["normal charging is not a limit", { isPresent: true, percentage: 0.8, state: T.Charging, changeRate: 5, timeToFull: 1800 }, false, false],
  ["full battery is not a limit", { isPresent: true, percentage: 1, state: T.FullyCharged }, false, false],
]
for (const [name, dev, onBatt, want] of thresholdCases) {
  check(ctx.chargeThresholdActive(dev, onBatt, T) === want, "chargeThresholdActive: " + name)
}

const checks = cases.length + parseCases.length + 8 + thresholdCases.length
console.log(fail ? `\n${fail} failed` : `\n${checks} passed`)
process.exit(fail ? 1 : 0)
