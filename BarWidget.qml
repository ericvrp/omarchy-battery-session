import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "Strings.js" as S

// Display only. One per screen, all reading the same Service.
BarWidget {
  id: root
  moduleName: "ericvrp.sleep-actions"

  // Reading _services makes the binding re-evaluate when the service loads later
  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? (bar.shell._services, bar.shell.serviceFor(moduleName)) : null
  readonly property var summary: service ? service.summary : null
  readonly property var cur: summary ? summary.current : null
  readonly property bool live: cur ? cur.live : false

  // Which value the bar shows; set via: omarchy bar set ericvrp.sleep-actions barLabel <value>
  //   remainHist  time left, all-time average (current session included). Default:
  //               steadier than the session average right after unplugging
  //   remainCur   time left, this session's average
  //   awake       time in use since unplugging
  readonly property string lang: S.resolve(setting("lang", "auto"), Qt.locale().name)
  readonly property bool zh: S.isZh(lang)
  function t(key) { return S.t(lang, key) }
  // Watts: Chinese "6.8 W", English "6.8W" as in the built-in Omarchy panels
  function fmtW(x) { return x.toFixed(1) + (zh ? " W" : "W") }

  // Sleep action setting mirrored from sleepctl.sh; "keep" until the service
  // has read the file.
  function sleepOption(key) {
    return root.service && root.service.sleepOptions ? root.service.sleepOptions[key] : "keep"
  }

  // The one-line dropdown: keep / Bluetooth off / Wi-Fi off / both off.
  function sleepOffValue() {
    var bt = root.sleepOption("bluetooth") === "off"
    var wifi = root.sleepOption("wifi") === "off"
    return bt && wifi ? "both" : bt ? "bt" : wifi ? "wifi" : "keep"
  }
  function setSleepOff(value) {
    if (!root.service) return
    if (value === "keep") { root.service.setSleepOption("bluetooth", "keep"); root.service.setSleepOption("wifi", "keep") }
    else if (value === "bt") { root.service.setSleepOption("bluetooth", "off"); root.service.setSleepOption("wifi", "keep") }
    else if (value === "wifi") { root.service.setSleepOption("bluetooth", "keep"); root.service.setSleepOption("wifi", "off") }
    else if (value === "both") { root.service.setSleepOption("bluetooth", "off"); root.service.setSleepOption("wifi", "off") }
  }

  // "Bluetooth off · Wi-Fi off" for a sleep period, from its recorded settings.
  function offLabel(period) {
    if (!period || !period.settings) return root.t("sleepSettingsUnknown")
    if (period.settings.bluetooth === null && period.settings.wifi === null)
      return root.t("sleepSettingsUnknown")
    var parts = []
    if (period.settings.bluetooth === "off") parts.push(root.t("btShort"))
    if (period.settings.wifi === "off") parts.push(root.t("wifiShort"))
    return parts.length ? parts.join(" · ") : root.t("sleepNothingOff")
  }

  readonly property string mode: setting("barLabel", "remainHist")
  readonly property var labelSecs: !live ? null
    : mode === "awake" ? cur.awakeSecs
    : mode === "remainCur" ? cur.remainCurSecs
    : cur.remainHistSecs
  readonly property string label: labelSecs ? Model.hm(labelSecs) : ""
  readonly property string labelDesc: mode === "awake" ? t("tipAwake") : mode === "remainCur" ? t("tipRemainCur") : t("tipRemainHist")

  // Right-click cycles the mode. Written to shell.json so it persists; shell.json
  // hot-reloads, so setting() updates by itself.
  readonly property var modes: ["remainHist", "remainCur", "awake"]
  function cycleMode() {
    var next = modes[(Math.max(0, modes.indexOf(mode)) + 1) % modes.length]
    if (bar) bar.run("omarchy bar set " + moduleName + " barLabel " + next)
  }

  property bool popupOpen: false
  // Used by shell.summon / hide / toggle
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }

  // Icon and text are separate Text items (as omarchy.media does). A single Text
  // mixing a Nerd glyph and text under-reports implicitWidth by about one
  // character and overlaps the widget to the right.
  implicitWidth: row.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      text: "󱧥"
      color: root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: pctText
      anchors.verticalCenter: parent.verticalCenter
      visible: root.summary && root.summary.lastPct !== null
      text: root.summary && root.summary.lastPct !== null ? root.summary.lastPct + "%" : ""
      color: root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      id: labelText
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && root.label !== ""
      text: root.label
      color: root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) root.cycleMode()
      else root.popupOpen = !root.popupOpen
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, (root.live ? (root.zh ? root.labelDesc + " " + root.label : root.label + " " + root.labelDesc) : root.t("onAc")) + "\n" + root.t("rightClick"))
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(root.zh ? 330 : 370))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(6)

      Text {
        visible: root.service && root.service.lastError !== ""
        text: "⚠ " + root.t("err") + ": " + (root.service ? root.t(root.service.lastError) : "")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      Dropdown {
        width: parent.width
        label: root.t("sleepSection")
        value: root.sleepOffValue()
        options: [
          { value: "keep", label: root.t("sleepOffNone") },
          { value: "bt", label: root.t("btShort") },
          { value: "wifi", label: root.t("wifiShort") },
          { value: "both", label: root.t("sleepOffBoth") }
        ]
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onChanged: function(value) { root.setSleepOff(value) }
      }

      Text {
        visible: root.service && root.service.sleepError !== ""
        text: "⚠ " + root.t("sleepWatchErr")
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { foreground: root.bar.foreground }

      PanelSectionHeader {
        text: root.t("sleepPeriods")
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Text {
        visible: !root.summary || root.summary.sleeps.length === 0
        text: root.t("sleepNoData")
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      Column {
        width: parent.width
        spacing: Style.space(5)
        visible: root.summary && root.summary.sleeps.length > 0

        Repeater {
          model: root.summary ? root.summary.sleeps : []

          Column {
            required property var modelData
            width: parent.width
            spacing: Style.space(1)

            Text {
              width: parent.width
              text: Model.clockRange(modelData.startWall, modelData.endWall)
                    + "   " + Model.hm(modelData.sleepSecs)
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width
              text: root.fmtW(modelData.avgW)
                    + " · " + modelData.usedWh.toFixed(1) + " Wh"
                    + " · " + root.offLabel(modelData)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }

      Text {
        visible: root.summary && root.summary.sleepAvgW !== null && root.summary.sleepCount > 0
        text: root.summary && root.summary.sleepAvgW !== null
          ? root.t("sleepAverage") + " " + root.fmtW(root.summary.sleepAvgW)
            + "  (" + root.summary.sleepCount + ")"
          : ""
        color: Qt.darker(root.bar.foreground, 1.5)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
