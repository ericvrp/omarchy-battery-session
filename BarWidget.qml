import QtQuick
import Quickshell
import Quickshell.Services.UPower
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

  // Live state from UPower, the same source the built-in power panel uses:
  // plug/unplug reaches the bar immediately, instead of waiting for the next
  // 60 s sample. The sampler keeps feeding the Wh statistics only.
  readonly property var upDev: UPower.displayDevice
  readonly property bool upPresent: !!(upDev && upDev.isPresent)
  // Percentage shown in the bar: live when UPower has a device, else the last sample.
  readonly property var dispPct: upPresent
    ? Math.round(Math.max(0, Math.min(1, upDev.percentage)) * 100)
    : (summary ? summary.lastPct : null)

  function levelGlyph(p) {
    return p >= 95 ? "󰁹" : p >= 85 ? "󰂂" : p >= 75 ? "󰂁" : p >= 65 ? "󰂀"
         : p >= 55 ? "󰁿" : p >= 45 ? "󰁾" : p >= 35 ? "󰁽" : p >= 25 ? "󰁼"
         : p >= 15 ? "󰁻" : p >= 5 ? "󰁺" : "󰂃"
  }

  // Icon follows the charge state: filled level while discharging, a charging
  // glyph while charging, a charged glyph when on AC and not charging.
  // Deliberately not the built-in panel's charge-limit heuristic: on Apple
  // Silicon "Full" is reported around 98%, which that heuristic would read as
  // a limit and then hide the plug-in change behind a level glyph.
  readonly property string batteryGlyph: {
    if (root.upPresent) {
      var st = root.upDev.state
      if (st === UPowerDeviceState.Charging || st === UPowerDeviceState.PendingCharge) return "󰂄"
      if (!UPower.onBattery) return "󰂅"
      return root.levelGlyph(root.dispPct === null ? 100 : root.dispPct)
    }
    // UPower not up yet: fall back to the last sampled state.
    if (!root.summary) return "󰁹"
    if (root.summary.lastKind === "charging") return "󰂄"
    if (root.summary.lastKind === "full") return "󰂅"
    return root.levelGlyph(root.summary.lastPct === null ? 100 : root.summary.lastPct)
  }

  property bool popupOpen: false
  // Used by shell.summon / hide / toggle
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  onPopupOpenChanged: if (!popupOpen) {
    root.clearArmed = false
    clearDisarm.stop()
    root.armedGroup = ""
    groupDisarm.stop()
  }

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

  // Copy: put the stats as plain text on the clipboard (Quickshell's native
  // clipboard), with a brief check glyph as confirmation.
  property bool copyDone: false
  Timer {
    id: copyReset
    interval: 1200
    onTriggered: root.copyDone = false
  }
  function statsText() {
    var s = root.summary
    var lines = []
    if (!s || s.sleepGroups.length === 0) {
      lines.push(root.t("sleepNoData"))
      return lines.join("\n") + "\n"
    }
    for (var i = 0; i < s.sleepGroups.length; i++) {
      var g = s.sleepGroups[i]
      lines.push(root.groupLabel(g.key)
                 + (g.avgW !== null ? " — " + root.t("sleepAverage") + " " + root.fmtW(g.avgW) : ""))
      for (var j = 0; j < g.periods.length; j++) {
        var p = g.periods[j]
        lines.push("  " + Model.clockRange(p.startWall, p.endWall)
                   + " — " + root.fmtW(p.avgW) + " · " + p.usedWh.toFixed(1) + " Wh")
      }
    }
    return lines.join("\n") + "\n"
  }
  function copyStats() {
    Quickshell.clipboardText = root.statsText()
    root.copyDone = true
    copyReset.restart()
  }

  // Per-group delete: first click arms (the icon turns urgent), a second click
  // deletes the recorded periods of that type.
  property string armedGroup: ""
  Timer {
    id: groupDisarm
    interval: 4000
    onTriggered: root.armedGroup = ""
  }
  function armOrDeleteGroup(key) {
    if (root.armedGroup === key) {
      root.armedGroup = ""
      groupDisarm.stop()
      if (root.service) root.service.deleteGroup(key)
    } else {
      root.armedGroup = key
      groupDisarm.restart()
    }
  }

  // Icon and charge percentage only.
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
      visible: root.dispPct !== null
      text: root.dispPct !== null ? root.dispPct + "%" : ""
      color: root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton
    onClicked: root.popupOpen = !root.popupOpen
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

      // Header row: the section title on the left, the Folder / Clear icon
      // actions on the right. On hover they get the shell's themed hover fill
      // plus a brighter glyph (same tokens the built-in panels use for their
      // inline actions), so they read as clickable.
      Row {
        width: parent.width
        spacing: Style.space(10)

        PanelSectionHeader {
          text: root.t("sleepSection")
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          width: parent.width - actions.width - parent.spacing
        }

        // The two actions sit closer to each other than to the rest of the row.
        Row {
          id: actions
          spacing: Style.space(4)

          Item {
            id: folderItem
            width: folderIcon.implicitWidth + Style.space(16)
            height: folderIcon.implicitHeight + Style.space(6)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: folderMouse.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
              Behavior on color { ColorAnimation { duration: 80 } }
            }

            Text {
              id: folderIcon
              anchors.centerIn: parent
              text: "󰉋"
              color: folderMouse.containsMouse ? root.bar.barForeground : Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              Behavior on color { ColorAnimation { duration: 80 } }
            }

            MouseArea {
              id: folderMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.service) root.service.openDataDir()
            }

            PanelToolTip {
              visible: folderMouse.containsMouse
              text: root.t("folderTip")
              fontFamily: root.bar.fontFamily
            }
          }

          Item {
            id: copyItem
            width: copyIcon.implicitWidth + Style.space(16)
            height: copyIcon.implicitHeight + Style.space(6)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: copyMouse.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
              Behavior on color { ColorAnimation { duration: 80 } }
            }

            Text {
              id: copyIcon
              anchors.centerIn: parent
              text: root.copyDone ? "󰄬" : "󰆏"
              color: root.copyDone ? root.bar.barForeground
                : copyMouse.containsMouse ? root.bar.barForeground
                : Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              Behavior on color { ColorAnimation { duration: 80 } }
            }

            MouseArea {
              id: copyMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyStats()
            }

            PanelToolTip {
              visible: copyMouse.containsMouse
              text: root.copyDone ? root.t("copyDoneTip") : root.t("copyTip")
              fontFamily: root.bar.fontFamily
            }
          }

          Item {
            id: clearItem
            width: clearIcon.implicitWidth + Style.space(16)
            height: clearIcon.implicitHeight + Style.space(6)

            Rectangle {
              anchors.fill: parent
              radius: Style.cornerRadius
              color: clearMouse.containsMouse && clearMouse.enabled
                ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
              Behavior on color { ColorAnimation { duration: 80 } }
            }

            Text {
              id: clearIcon
              anchors.centerIn: parent
              text: "󰆴"
              color: root.clearArmed ? Color.urgent
                : clearMouse.containsMouse && clearMouse.enabled ? root.bar.barForeground
                : Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.bold: root.clearArmed
              Behavior on color { ColorAnimation { duration: 80 } }
            }

            MouseArea {
              id: clearMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              enabled: !root.service || !root.service.clearing
              onClicked: root.armOrClear()
            }

            PanelToolTip {
              visible: clearMouse.containsMouse && clearMouse.enabled
              text: root.clearArmed ? root.t("clearSureTip") : root.t("clearTip")
              fontFamily: root.bar.fontFamily
            }
          }
        }
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

            Row {
              width: parent.width
              spacing: Style.space(6)

              Text {
                width: parent.width - groupDeleteItem.width - parent.spacing
                text: root.groupLabel(modelData.key)
                      + (modelData.avgW !== null ? "   " + root.fmtW(modelData.avgW) : "")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              // Delete just this group's periods: first click arms, second
              // deletes. The samples stay on disk; only the periods of this
              // type stop counting in the stats.
              Item {
                id: groupDeleteItem
                width: groupDeleteIcon.implicitWidth + Style.space(12)
                height: groupDeleteIcon.implicitHeight + Style.space(4)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: groupDeleteMouse.containsMouse ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "transparent"
                  Behavior on color { ColorAnimation { duration: 80 } }
                }

                Text {
                  id: groupDeleteIcon
                  anchors.centerIn: parent
                  text: "󰆴"
                  color: root.armedGroup === modelData.key ? Color.urgent
                    : groupDeleteMouse.containsMouse ? root.bar.barForeground
                    : Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.armedGroup === modelData.key
                  Behavior on color { ColorAnimation { duration: 80 } }
                }

                MouseArea {
                  id: groupDeleteMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.armOrDeleteGroup(modelData.key)
                }

                PanelToolTip {
                  visible: groupDeleteMouse.containsMouse
                  text: root.armedGroup === modelData.key ? root.t("clearSureTip") : root.t("groupDeleteTip")
                  fontFamily: root.bar.fontFamily
                }
              }
            }

            Repeater {
              model: modelData.periods

              Text {
                required property var modelData
                width: parent.width
                text: Model.clockRange(modelData.startWall, modelData.endWall)
                      + "   " + root.fmtW(modelData.avgW) + " · " + modelData.usedWh.toFixed(1) + " Wh"
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
