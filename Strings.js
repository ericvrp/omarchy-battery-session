.pragma library

// UI strings. `lang` setting: "auto" follows the system locale, or force
// "en" / "zh-Hant" (Traditional Chinese) / "zh-Hans" (Simplified Chinese).
var TABLE = {
  en: {
    current: "Battery life", last: "Last discharge",
    empty: "No discharge recorded yet", calibrating: "Calibrating… (needs two samples)",
    unplugged: "Unplugged at", now: "Now",
    elapsed: "Time since unplugged", slept: "Suspended / off", sleptWh: "Used while asleep", awake: "Time in use", power: "Discharging",
    nowW: "now", remaining: "Time left", curAvg: "session avg", histAvg: "all-time avg",
    tipAwake: "in use", tipRemainCur: "left (session avg)", tipRemainHist: "left (all-time avg)",
    onAc: "Plugged in", rightClick: "Right-click to change", histUse: "awake", histSlept: "suspended",
    sleepSection: "When sleeping", btOff: "Turn off Bluetooth",
    btOffDesc: "Blocks the Bluetooth radio before suspend and restores it on wake",
    wifiOff: "Turn off Wi-Fi",
    wifiOffDesc: "Blocks the Wi-Fi radio before suspend and restores it on wake",
    sleepWatchErr: "sleep action watcher is not running",
    err: "Sampler", errNoBattery: "no battery found", errClock: "system clock not synced yet", errDataDir: "data directory failed ownership check", errKilled: "timed out and was killed"
  },
  "zh-Hant": {
    current: "電池續航力", last: "上次放電（目前接電中）",
    empty: "還沒有放電紀錄", calibrating: "還在收集中（校準 HZ 需要兩筆取樣）",
    unplugged: "停止充電於", now: "現在",
    elapsed: "拔電多久", slept: "睡/關", sleptWh: "睡/關耗掉", awake: "實際使用", power: "耗電速度",
    nowW: "現在", remaining: "還能用多久", curAvg: "本次平均", histAvg: "歷史平均",
    tipAwake: "實際使用", tipRemainCur: "還能用多久（本次平均）", tipRemainHist: "還能用多久（歷史平均）",
    onAc: "接電中", rightClick: "右鍵切換顯示", histUse: "實際", histSlept: "睡",
    sleepSection: "睡前動作", btOff: "關閉藍牙",
    btOffDesc: "睡前封鎖藍牙電台，醒來後解除封鎖",
    wifiOff: "關閉 Wi-Fi",
    wifiOffDesc: "睡前封鎖 Wi-Fi 電台，醒來後解除封鎖",
    sleepWatchErr: "睡前動作監控未執行",
    err: "取樣器", errNoBattery: "沒有電池", errClock: "系統時鐘還沒同步", errDataDir: "資料目錄擁有者檢查失敗", errKilled: "逾時被強制結束"
  },
  "zh-Hans": {
    current: "电池续航力", last: "上次放电（目前接电中）",
    empty: "还没有放电记录", calibrating: "还在收集中（校准 HZ 需要两次采样）",
    unplugged: "停止充电于", now: "现在",
    elapsed: "拔电多久", slept: "睡/关", sleptWh: "睡/关耗掉", awake: "实际使用", power: "耗电速度",
    nowW: "现在", remaining: "还能用多久", curAvg: "本次平均", histAvg: "历史平均",
    tipAwake: "实际使用", tipRemainCur: "还能用多久（本次平均）", tipRemainHist: "还能用多久（历史平均）",
    onAc: "接电中", rightClick: "右键切换显示", histUse: "实际", histSlept: "睡",
    sleepSection: "睡前动作", btOff: "关闭蓝牙",
    btOffDesc: "睡前封锁蓝牙电台，醒来后解除封锁",
    wifiOff: "关闭 Wi-Fi",
    wifiOffDesc: "睡前封锁 Wi-Fi 电台，醒来后解除封锁",
    sleepWatchErr: "睡前动作监控未运行",
    err: "采样器", errNoBattery: "没有电池", errClock: "系统时钟尚未同步", errDataDir: "数据目录所有者检查失败", errKilled: "超时被强制结束"
  }
}

// Traditional: Taiwan, Hong Kong, Macau, or an explicit Hant script tag.
// Everything else under zh (CN, SG, bare "zh") is Simplified, as in CLDR.
function zhVariant(localeName) {
  var n = String(localeName || "").replace(/-/g, "_")
  return /^zh_(TW|HK|MO)|Hant/.test(n) ? "zh-Hant" : "zh-Hans"
}

function resolve(setting, localeName) {
  if (TABLE[setting]) return setting
  if (setting === "zh") return "zh-Hant"   // value used before the two variants existed
  return String(localeName || "").indexOf("zh") === 0 ? zhVariant(localeName) : "en"
}

function isZh(lang) { return lang.indexOf("zh") === 0 }

function t(lang, key) {
  var tbl = TABLE[lang] || TABLE.en
  return tbl[key] !== undefined ? tbl[key] : (TABLE.en[key] || key)
}
