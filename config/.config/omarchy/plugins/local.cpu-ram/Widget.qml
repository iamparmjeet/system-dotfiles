import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

BarWidget {
  id: root
  moduleName: "local.cpu-ram"

  property real cpuPercent: 0
  property real memPercent: 0
  property real memUsedGb: 0
  property real memTotalGb: 0
  property real loadAvg: 0
  property var cpuHistory: []
  property var memHistory: []
  property var prevCpu: ({ idle: 0, total: 0 })

  readonly property int historyLimit: 30
  readonly property int refreshIntervalSec: {
    var configured = Number(setting("refreshIntervalSec", 2))
    return isFinite(configured) ? Math.max(1, Math.min(60, Math.round(configured))) : 2
  }
  readonly property string collectorPath: String(Qt.resolvedUrl("scripts/cpu-ram-stats")).replace("file://", "")
  readonly property color statColor: bar ? bar.foreground : Commons.Color.foreground

  property bool popupOpen: false

  implicitWidth: label.implicitWidth + Style.spaceReal(15)
  implicitHeight: barSize

  function close() {
    popupOpen = false
  }

  function pushHistory(arr, value) {
    var next = arr.slice()
    next.push(value)
    if (next.length > historyLimit) next.shift()
    return next
  }

  function updateCpuTotals(idle, total) {
    var idleDiff = idle - prevCpu.idle
    var totalDiff = total - prevCpu.total
    if (prevCpu.total > 0 && totalDiff > 0) {
      cpuPercent = Math.max(0, Math.min(100, (1 - idleDiff / totalDiff) * 100))
      cpuHistory = pushHistory(cpuHistory, cpuPercent)
    }
    prevCpu = { idle: idle, total: total }
  }

  function updateSample(raw) {
    var fields = String(raw || "").trim().split("\t")
    if (fields.length < 6 || fields[0] !== "sample") return

    var idle = Number(fields[1])
    var total = Number(fields[2])
    var availableKib = Number(fields[3])
    var totalKib = Number(fields[4])
    var load = Number(fields[5])

    if (isFinite(idle) && isFinite(total)) updateCpuTotals(idle, total)

    if (isFinite(availableKib) && isFinite(totalKib) && totalKib > 0) {
      var usedKib = Math.max(0, totalKib - availableKib)
      memPercent = Math.max(0, Math.min(100, usedKib / totalKib * 100))
      memUsedGb = usedKib / 1048576
      memTotalGb = totalKib / 1048576
      memHistory = pushHistory(memHistory, memPercent)
    }

    if (isFinite(load)) loadAvg = load
  }

  function restartCollector() {
    statsProc.running = false
    collectorRestart.restart()
  }

  onRefreshIntervalSecChanged: restartCollector()

  Process {
    id: statsProc
    command: ["bash", root.collectorPath, String(root.refreshIntervalSec)]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        root.updateSample(line)
      }
    }
    onExited: collectorRestart.restart()
  }

  Timer {
    id: collectorRestart
    interval: 2000
    onTriggered: {
      if (!statsProc.running) statsProc.running = true
    }
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: "󰍛 " + Math.round(root.cpuPercent) + "%  󰾆 " + root.memUsedGb.toFixed(1) + "G"
    color: root.statColor
    font.family: bar ? bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: root.popupOpen = !root.popupOpen
  }

  PopupCard {
    id: popup
    anchorItem: label
    owner: root
    bar: root.bar
    open: root.popupOpen
    triggerMode: "click"
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(detailColumn.implicitHeight)

    Column {
      id: detailColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        text: "System"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      DetailStat {
        title: "CPU"
        value: Math.round(root.cpuPercent) + "%"
        history: root.cpuHistory
        barFg: root.bar.foreground
        fontFamily: root.bar.fontFamily
        width: parent.width
      }

      DetailStat {
        title: "Memory"
        value: root.memUsedGb.toFixed(1) + "G / " + root.memTotalGb.toFixed(1) + "G  (" + Math.round(root.memPercent) + "%)"
        history: root.memHistory
        barFg: root.bar.foreground
        fontFamily: root.bar.fontFamily
        width: parent.width
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          text: "Load"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          text: root.loadAvg.toFixed(2)
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Button {
        text: "Open btop"
        bordered: true
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        width: parent.width
        onClicked: {
          root.popupOpen = false
          if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
        }
      }
    }
  }

  component DetailStat: Column {
    id: detail

    property string title: ""
    property string value: ""
    property var history: []
    property color barFg: Commons.Color.foreground
    property string fontFamily: Style.font.family

    spacing: Style.space(4)

    Row {
      width: parent.width

      Text {
        text: detail.title
        color: Qt.darker(detail.barFg, 1.4)
        font.family: detail.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Item {
        width: detail.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth
        height: 1
      }

      Text {
        text: detail.value
        color: detail.barFg
        font.family: detail.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Canvas {
      width: parent.width
      height: Style.space(40)
      property var history: detail.history
      onHistoryChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!detail.history || detail.history.length === 0) return
        ctx.strokeStyle = detail.barFg
        ctx.fillStyle = Qt.rgba(detail.barFg.r, detail.barFg.g, detail.barFg.b, 0.25)
        ctx.lineWidth = 1.5
        ctx.beginPath()
        var step = width / Math.max(1, detail.history.length - 1)
        for (var i = 0; i < detail.history.length; i++) {
          var x = i * step
          var y = height - (detail.history[i] / 100) * (height - 2) - 1
          if (i === 0) ctx.moveTo(x, y)
          else ctx.lineTo(x, y)
        }
        ctx.stroke()
        ctx.lineTo(width, height)
        ctx.lineTo(0, height)
        ctx.closePath()
        ctx.fill()
      }
    }
  }
}
