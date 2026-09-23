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

  function toggleSleep(key) {
    if (!root.service) return
    root.service.setSleepOption(key, root.sleepOption(key) === "off" ? "keep" : "off")
  }

  function groupLabel(key) {
    return key === "none" ? root.t("sleepGroupNone")
      : key === "bt" ? root.t("sleepGroupBt")
      : key === "wifi" ? root.t("sleepGroupWifi")
      : key === "both" ? root.t("sleepGroupBoth")
      : key === "charger" ? root.t("sleepGroupCharger")
      : root.t("sleepGroupUnknown")
  }

  // Icon follows the charge state: filled level while discharging, a charging
  // glyph while charging, a charged glyph when full/topped up.
  readonly property string batteryGlyph: {
    if (!root.summary) return "󰁹"
    if (root.summary.lastKind === "charging") return "󰂄"
    if (root.summary.lastKind === "full") return "󰂅"
    var p = root.summary.lastPct === null ? 100 : root.summary.lastPct
    return p >= 95 ? "󰁹" : p >= 85 ? "󰂂" : p >= 75 ? "󰂁" : p >= 65 ? "󰂀"
         : p >= 55 ? "󰁿" : p >= 45 ? "󰁾" : p >= 35 ? "󰁽" : p >= 25 ? "󰁼"
         : p >= 15 ? "󰁻" : p >= 5 ? "󰁺" : "󰂃"
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
  onPopupOpenChanged: if (!popupOpen) { root.clearArmed = false; clearDisarm.stop() }

  // Two-step clear: first click arms, second click deletes the recorded stats.
  property bool clearArmed: false
  Timer {
    id: clearDisarm
    interval: 4000
    onTriggered: root.clearArmed = false
  }
  function armOrClear() {
    if (root.clearArmed) {
      root.clearArmed = false
      clearDisarm.stop()
      if (root.service) root.service.clearStats()
    } else {
      root.clearArmed = true
      clearDisarm.restart()
    }
  }

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
      text: root.batteryGlyph
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

      PanelSectionHeader {
        text: root.t("sleepSection")
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Toggle {
          width: (parent.width - parent.spacing) / 2
          label: root.t("btName")
          titleSize: Style.font.body
          checked: root.sleepOption("bluetooth") === "off"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.toggleSleep("bluetooth")
        }

        Toggle {
          width: (parent.width - parent.spacing) / 2
          label: root.t("wifiName")
          titleSize: Style.font.body
          checked: root.sleepOption("wifi") === "off"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.toggleSleep("wifi")
        }
      }

      Text {
        visible: root.service && root.service.sleepError !== ""
        text: "⚠ " + root.t("sleepWatchErr")
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator { foreground: root.bar.foreground }

      Row {
        width: parent.width
        spacing: Style.space(6)

        PanelSectionHeader {
          text: root.t("sleepPeriods")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          width: parent.width - clearItem.width - parent.spacing
        }

        Item {
          id: clearItem
          width: clearText.implicitWidth
          height: clearText.implicitHeight

          Text {
            id: clearText
            anchors.fill: parent
            text: root.clearArmed ? root.t("clearSure") : root.t("clear")
            color: root.clearArmed ? root.bar.barForeground : Qt.darker(root.bar.foreground, 1.5)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            enabled: !root.service || !root.service.clearing
            onClicked: root.armOrClear()
          }
        }
      }

      Text {
        visible: !root.summary || root.summary.sleepGroups.length === 0
        text: root.t("sleepNoData")
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      Column {
        width: parent.width
        spacing: Style.space(7)
        visible: root.summary && root.summary.sleepGroups.length > 0

        Repeater {
          model: root.summary ? root.summary.sleepGroups : []

          Column {
            required property var modelData
            width: parent.width
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: root.groupLabel(modelData.key)
                    + (modelData.avgW !== null
                       ? "   " + root.fmtW(modelData.avgW) + "  (" + modelData.avgCount + ")"
                       : "   (" + modelData.count + ")")
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Repeater {
              model: modelData.periods

              Text {
                required property var modelData
                width: parent.width
                text: Model.clockRange(modelData.startWall, modelData.endWall)
                      + (modelData.avgW !== null
                         ? "   " + root.fmtW(modelData.avgW) + " · " + modelData.usedWh.toFixed(1) + " Wh"
                         : "   " + root.t(modelData.charger ? "sleepCharging" : "sleepNoReading"))
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }
      }
    }
  }
}
