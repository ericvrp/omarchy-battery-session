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
const checks = cases.length + parseCases.length
console.log(fail ? `\n${fail} failed` : `\n${checks} passed`)
process.exit(fail ? 1 : 0)
