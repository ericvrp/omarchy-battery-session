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
    sleepSection: "Turn off while sleeping", btOff: "Turn off Bluetooth",
    btOffDesc: "Blocks the Bluetooth radio before suspend and restores it on wake",
    wifiOff: "Turn off Wi-Fi",
    wifiOffDesc: "Blocks the Wi-Fi radio before suspend and restores it on wake",
    btOption: "Bluetooth at sleep", wifiOption: "Wi-Fi at sleep",
    keepOn: "Keep on", turnOff: "Turn off",
    btName: "Bluetooth", wifiName: "Wi-Fi",
    sleepOffNone: "Nothing turned off", sleepOffBoth: "Bluetooth + Wi-Fi off",
    sleepWatchErr: "sleep action watcher is not running",
    sleepPeriods: "Sleep periods", sleepNoData: "No sleep recorded yet",
    sleepAverage: "average", sleepSettingsUnknown: "settings not recorded",
    sleepNothingOff: "nothing turned off", btShort: "Bluetooth off", wifiShort: "Wi-Fi off",
    clear: "Clear", clearSure: "Sure?", folder: "Folder",
    folderTip: "Open data folder", clearTip: "Delete recorded samples",
    clearSureTip: "Click again to delete",
    copyTip: "Copy stats to clipboard", copyDoneTip: "Copied!",
    sleepGroupNone: "Nothing turned off", sleepGroupBt: "Bluetooth off",
    sleepGroupWifi: "Wi-Fi off", sleepGroupBoth: "Bluetooth + Wi-Fi off",
    sleepGroupUnknown: "Settings not recorded", sleepGroupCharger: "On charger",
    sleepCharging: "on charger", sleepNoReading: "no reading",
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
    sleepSection: "睡眠時關閉", btOff: "關閉藍牙",
    btOffDesc: "睡前封鎖藍牙電台，醒來後解除封鎖",
    wifiOff: "關閉 Wi-Fi",
    wifiOffDesc: "睡前封鎖 Wi-Fi 電台，醒來後解除封鎖",
    btOption: "睡眠時藍牙", wifiOption: "睡眠時 Wi-Fi",
    keepOn: "保持開啟", turnOff: "關閉",
    btName: "藍牙", wifiName: "Wi-Fi",
    sleepOffNone: "不關閉任何項目", sleepOffBoth: "藍牙與 Wi-Fi 關閉",
    sleepWatchErr: "睡前動作監控未執行",
    sleepPeriods: "睡眠期間", sleepNoData: "還沒有睡眠紀錄",
    sleepAverage: "平均", sleepSettingsUnknown: "沒有設定紀錄",
    sleepNothingOff: "沒有關閉項目", btShort: "藍牙關閉", wifiShort: "Wi-Fi 關閉",
    clear: "清除", clearSure: "確定？", folder: "資料夾",
    folderTip: "開啟資料夾", clearTip: "刪除已記錄的統計",
    clearSureTip: "再按一次刪除",
    copyTip: "複製統計到剪貼簿", copyDoneTip: "已複製！",
    sleepGroupNone: "不關閉任何項目", sleepGroupBt: "藍牙關閉",
    sleepGroupWifi: "Wi-Fi 關閉", sleepGroupBoth: "藍牙與 Wi-Fi 關閉",
    sleepGroupUnknown: "沒有設定紀錄", sleepGroupCharger: "接電中",
    sleepCharging: "接電中", sleepNoReading: "沒有讀數",
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
    sleepSection: "睡眠时关闭", btOff: "关闭蓝牙",
    btOffDesc: "睡前封锁蓝牙电台，醒来后解除封锁",
    wifiOff: "关闭 Wi-Fi",
    wifiOffDesc: "睡前封锁 Wi-Fi 电台，醒来后解除封锁",
    btOption: "睡眠时蓝牙", wifiOption: "睡眠时 Wi-Fi",
    keepOn: "保持开启", turnOff: "关闭",
    btName: "蓝牙", wifiName: "Wi-Fi",
    sleepOffNone: "不关闭任何项目", sleepOffBoth: "蓝牙与 Wi-Fi 关闭",
    sleepWatchErr: "睡前动作监控未运行",
    sleepPeriods: "睡眠期间", sleepNoData: "还没有睡眠记录",
    sleepAverage: "平均", sleepSettingsUnknown: "没有设置记录",
    sleepNothingOff: "没有关闭项目", btShort: "蓝牙关闭", wifiShort: "Wi-Fi 关闭",
    clear: "清除", clearSure: "确定？", folder: "文件夹",
    folderTip: "打开文件夹", clearTip: "删除已记录的统计",
    clearSureTip: "再按一次删除",
    copyTip: "复制统计到剪贴板", copyDoneTip: "已复制！",
    sleepGroupNone: "不关闭任何项目", sleepGroupBt: "蓝牙关闭",
    sleepGroupWifi: "Wi-Fi 关闭", sleepGroupBoth: "蓝牙与 Wi-Fi 关闭",
    sleepGroupUnknown: "没有设置记录", sleepGroupCharger: "接电中",
    sleepCharging: "接电中", sleepNoReading: "没有读数",
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
