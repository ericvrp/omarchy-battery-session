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
      color: root.live ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
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
    contentWidth: popup.fittedContentWidth(Style.space(root.zh ? 360 : 400))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    component Line: Row {
      property string k: ""
      property string v: ""
      width: parent.width
      Text {
        text: k
        width: root.zh ? Style.space(120) : Style.space(180)
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        text: v
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(6)

      Text {
        text: !root.summary || root.summary.state === "empty" ? root.t("empty")
            : root.summary.state === "calibrating" ? root.t("calibrating")
            : root.live ? root.t("current") : root.t("last")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Column {
        width: parent.width
        spacing: Style.space(3)
        visible: root.cur !== null
        Line { k: root.t("unplugged"); v: root.cur ? Model.clock(root.cur.startWall) + "  " + root.cur.startPct + "%" : "" }
        Line { k: root.t("now"); visible: root.live
               v: root.cur ? Model.clock(root.cur.endWall) + "  " + root.cur.endPct + "%" : "" }
        Line { k: root.t("elapsed"); v: root.cur ? Model.hm(root.cur.wallSecs) : "" }
        Line { k: root.t("slept"); v: root.cur ? Model.hm(root.cur.sleptSecs) : "" }
        Line { k: root.t("sleptWh"); visible: root.cur && root.cur.sleptWh !== null && root.cur.sleptWh >= 0.5
               v: root.cur && root.cur.sleptWh !== null ? root.cur.sleptWh.toFixed(1) + " Wh" : "" }
        Line { k: root.t("awake"); v: root.cur ? Model.hm(root.cur.awakeSecs) : "" }
        Line { k: root.t("power")
               visible: root.live && root.cur && (root.cur.nowW || root.cur.avgW)
               v: root.cur ? [root.cur.nowW ? root.t("nowW") + " " + root.fmtW(root.cur.nowW) : "",
                              root.cur.avgW ? root.t("curAvg") + " " + root.fmtW(root.cur.avgW) : ""].filter(Boolean).join(" · ") : "" }
        Line { k: root.t("remaining")
               visible: root.live && root.cur && root.cur.remainCurSecs
               v: root.cur && root.cur.remainCurSecs ? Model.hm(root.cur.remainCurSecs) + " (" + root.t("curAvg") + " " + root.fmtW(root.cur.avgW) + ")" : "" }
        Line { k: ""
               visible: root.live && root.cur && root.cur.remainHistSecs
               v: root.cur && root.cur.remainHistSecs && root.summary.histAvgW
                  ? Model.hm(root.cur.remainHistSecs) + " (" + root.t("histAvg") + " " + root.fmtW(root.summary.histAvgW) + ")" : "" }
      }

      Text {
        visible: root.service && root.service.lastError !== ""
        text: "⚠ " + root.t("err") + ": " + (root.service ? root.t(root.service.lastError) : "")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }

      PanelSeparator {
        visible: root.summary && root.summary.history.length > 0
        foreground: root.bar.foreground
      }

      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: root.summary && root.summary.history.length > 0

        Repeater {
          model: root.summary ? root.summary.history : []
          Text {
            required property var modelData
            width: parent.width
            text: Model.clock(modelData.startWall) + "  " + modelData.startPct + "→" + modelData.endPct + "%"
                  + "  " + root.t("histUse") + " " + Model.hm(modelData.awakeSecs)
                  + (modelData.sleptSecs >= 60 ? "  " + root.t("histSlept") + " " + Model.hm(modelData.sleptSecs) : "")
                  + (modelData.avgW !== null ? "  " + modelData.avgW.toFixed(1) + "W" : "")
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      PanelSectionHeader {
        text: root.t("sleepSection")
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
      }

      Toggle {
        width: parent.width
        label: root.t("btOff")
        description: root.t("btOffDesc")
        checked: root.sleepOption("bluetooth") === "off"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: if (root.service) root.service.setSleepOption("bluetooth", checked ? "keep" : "off")
      }

      Toggle {
        width: parent.width
        label: root.t("wifiOff")
        description: root.t("wifiOffDesc")
        checked: root.sleepOption("wifi") === "off"
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        onClicked: if (root.service) root.service.setSleepOption("wifi", checked ? "keep" : "off")
      }

      Text {
        visible: root.service && root.service.sleepError !== ""
        text: "⚠ " + root.t("sleepWatchErr")
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
