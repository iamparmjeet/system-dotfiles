import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import qs.Commons as Commons

BarWidget {
  id: root
  moduleName: "local.media-wave"

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayer: {
    var list = players
    var fallback = null
    for (var i = 0; i < list.length; i++) {
      var candidate = list[i]
      if (!candidate) continue
      if (!(candidate.trackTitle || candidate.trackArtist)) continue
      if (candidate.isPlaying) return candidate
      if (!fallback) fallback = candidate
    }
    if (fallback) return fallback
    for (var j = 0; j < list.length; j++)
      if (list[j] && list[j].isPlaying) return list[j]
    return list.length > 0 ? list[0] : null
  }
  readonly property bool hasMedia: activePlayer !== null && !!(activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property bool isPlaying: activePlayer ? !!activePlayer.isPlaying : false
  readonly property bool canPrevious: activePlayer ? !!activePlayer.canGoPrevious : false
  readonly property bool canNext: activePlayer ? !!activePlayer.canGoNext : false
  readonly property bool canToggle: activePlayer
    ? !!(activePlayer.canTogglePlaying || activePlayer.canPlay || activePlayer.canPause)
    : false
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "Unknown title") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string mediaUrl: activePlayer && activePlayer.metadata
    ? String(activePlayer.metadata["xesam:url"] || "")
    : ""
  readonly property string mediaFilePath: {
    var url = mediaUrl
    if (url.indexOf("file://") !== 0) return ""
    var path = url.slice(7)
    try { path = decodeURIComponent(path) } catch (e) {}
    return path
  }
  readonly property string artCacheDir: Quickshell.env("HOME") + "/.cache/omarchy/media-wave"
  property string metadataArtUrl: ""
  readonly property bool needsLocalArt: hasMedia && mediaFilePath !== ""
    && artUrl === "" && youtubeThumbnail(mediaUrl) === ""
  readonly property string effectiveArtUrl: artUrl || youtubeThumbnail(mediaUrl) || metadataArtUrl
  readonly property bool showArtwork: {
    var configured = setting("showArtwork", true)
    return configured !== false && String(configured).toLowerCase() !== "false"
  }
  readonly property real metadataDurationSeconds: activePlayer && activePlayer.metadata
    ? Math.max(0, (Number(activePlayer.metadata["mpris:length"]) || 0) / 1000000)
    : 0
  readonly property real reportedDurationSeconds: activePlayer && activePlayer.lengthSupported
    ? Math.max(0, Number(activePlayer.length) || 0)
    : 0
  readonly property real positionSeconds: activePlayer
    ? Math.max(0, Number(activePlayer.position) || 0)
    : 0
  readonly property real durationSeconds: Math.max(metadataDurationSeconds, reportedDurationSeconds)
  readonly property bool canSeek: activePlayer
    ? !!(activePlayer.canSeek && activePlayer.positionSupported && durationSeconds > 0)
    : false
  readonly property real progressRatio: durationSeconds > 0
    ? Math.max(0, Math.min(1, positionSeconds / durationSeconds))
    : 0
  readonly property bool opened: popupOpen

  property bool popupOpen: false

  visible: hasMedia
  implicitWidth: hasMedia ? controls.implicitWidth : 0
  implicitHeight: barSize

  function close() {
    popupOpen = false
  }

  function open() {
    popupOpen = true
    refreshTiming()
    Qt.callLater(refreshTiming)
  }

  function runAction(action) {
    var player = activePlayer
    if (!player) return
    if (action === "next") {
      if (player.canGoNext) player.next()
    } else if (action === "previous") {
      if (player.canGoPrevious) player.previous()
    } else if (action === "playPause") {
      if (player.isPlaying && player.canPause) player.pause()
      else if (!player.isPlaying && player.canPlay) player.play()
      else if (player.canTogglePlaying) player.togglePlaying()
    }
  }

  function refreshTiming() {
    if (activePlayer && activePlayer.positionSupported) activePlayer.positionChanged()
  }

  function formatTime(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var secs = total % 60
    if (hours > 0)
      return hours + ":" + String(minutes).padStart(2, "0") + ":" + String(secs).padStart(2, "0")
    return minutes + ":" + String(secs).padStart(2, "0")
  }

  function youtubeVideoId(url) {
    var value = String(url || "")
    var patterns = [
      /youtube\.com\/shorts\/([A-Za-z0-9_-]{6,})/,
      /[\?&]v=([A-Za-z0-9_-]{6,})/,
      /youtu\.be\/([A-Za-z0-9_-]{6,})/,
      /youtube\.com\/embed\/([A-Za-z0-9_-]{6,})/
    ]
    for (var i = 0; i < patterns.length; i++) {
      var match = value.match(patterns[i])
      if (match) return match[1]
    }
    return ""
  }

  function youtubeThumbnail(url) {
    var videoId = youtubeVideoId(url)
    return videoId ? "https://i.ytimg.com/vi/" + videoId + "/hqdefault.jpg" : ""
  }

  function isVideoFile(path) {
    return /\.(mp4|mkv|webm|mov|avi|m4v|mpe?g|ts|flv)$/.test(String(path).toLowerCase())
  }

  function hashPath(value) {
    var hash = 5381
    var text = String(value)
    for (var i = 0; i < text.length; i++)
      hash = ((hash << 5) + hash + text.charCodeAt(i)) >>> 0
    return hash.toString(16)
  }

  function refreshLocalArt() {
    metadataArtUrl = ""
    probeProc.running = false
    frameProc.running = false
    if (!needsLocalArt) return
    probeProc.sourceFile = mediaFilePath
    probeProc.running = true
  }

  Process {
    id: probeProc

    property string sourceFile: ""

    command: sourceFile !== ""
      ? ["ffprobe", "-v", "error", "-show_entries",
         "format_tags=comment,description,synopsis",
         "-of", "default=noprint_wrappers=1:nokey=1", sourceFile]
      : []

    stdout: StdioCollector {
      id: probeOut
      waitForEnd: true
    }

    onExited: {
      if (sourceFile !== root.mediaFilePath) return
      var videoId = root.youtubeVideoId(probeOut.text || "")
      if (videoId) {
        root.metadataArtUrl = "https://i.ytimg.com/vi/" + videoId + "/hqdefault.jpg"
      } else if (root.isVideoFile(root.mediaFilePath)) {
        frameProc.sourceFile = root.mediaFilePath
        frameProc.outPath = root.artCacheDir + "/" + root.hashPath(root.mediaFilePath) + ".jpg"
        frameProc.running = true
      }
    }
  }

  Process {
    id: frameProc

    property string sourceFile: ""
    property string outPath: ""

    command: (sourceFile !== "" && outPath !== "")
      ? ["ffmpegthumbnailer", "-i", sourceFile, "-o", outPath, "-s", "320", "-f", "-q", "8"]
      : []

    onExited: function(exitCode) {
      if (exitCode === 0 && outPath !== "") root.metadataArtUrl = "file://" + outPath
    }
  }

  Process {
    id: mkdirProc

    command: ["mkdir", "-p", root.artCacheDir]
    Component.onCompleted: running = true
  }

  function seekToRatio(ratio) {
    if (!canSeek || !activePlayer || durationSeconds <= 0) return
    activePlayer.position = Math.max(0, Math.min(durationSeconds, durationSeconds * ratio))
    activePlayer.positionChanged()
  }

  onHasMediaChanged: {
    if (!hasMedia) close()
    Qt.callLater(refreshLocalArt)
  }

  onMediaFilePathChanged: Qt.callLater(refreshLocalArt)

  onActivePlayerChanged: Qt.callLater(refreshTiming)

  Component.onCompleted: Qt.callLater(refreshLocalArt)

  Timer {
    interval: 500
    repeat: true
    running: root.popupOpen && root.isPlaying && root.activePlayer && root.activePlayer.positionSupported
    onTriggered: root.refreshTiming()
  }

  Row {
    id: controls
    anchors.centerIn: parent
    spacing: 0

    BarIconButton {
      bar: root.bar
      text: "󰒮"
      slotSize: Style.space(18)
      opticalSize: Style.space(12)
      fontSize: Style.font.caption
      tooltipText: "Previous"
      interactive: root.canPrevious
      dimmed: !root.canPrevious
      onPressed: root.runAction("previous")
    }

    BarIconButton {
      id: waveButton
      bar: root.bar
      slotSize: Style.space(24)
      opticalSize: Style.space(18)
      tooltipText: "Media controls"
      interactive: root.hasMedia
      dimmed: false
      active: root.isPlaying
      useActiveColor: false
      onPressed: root.popupOpen ? root.close() : root.open()

      iconComponent: Component {
        Item {
          Row {
            anchors.centerIn: parent
            spacing: Style.spaceReal(1.5)

            Repeater {
              model: [
                { low: 4, high: 9, duration: 260 },
                { low: 6, high: 15, duration: 190 },
                { low: 3, high: 11, duration: 230 },
                { low: 5, high: 14, duration: 170 },
                { low: 4, high: 8, duration: 280 }
              ]

              Rectangle {
                id: waveBar
                required property var modelData

                property real animatedHeight: Style.spaceReal(modelData.low)
                readonly property real lowHeight: Style.spaceReal(modelData.low)
                readonly property real highHeight: Style.spaceReal(modelData.high)

                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(1.5, Style.spaceReal(2))
                height: root.isPlaying ? animatedHeight : lowHeight
                radius: width / 2
                color: root.bar ? root.bar.foreground : Commons.Color.foreground
                opacity: root.isPlaying ? 1 : 0.62

                Behavior on opacity {
                  NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                  }
                }

                SequentialAnimation on animatedHeight {
                  running: root.isPlaying
                  loops: Animation.Infinite

                  NumberAnimation {
                    to: waveBar.highHeight
                    duration: waveBar.modelData.duration
                    easing.type: Easing.InOutSine
                  }

                  NumberAnimation {
                    to: waveBar.lowHeight
                    duration: waveBar.modelData.duration + 70
                    easing.type: Easing.InOutSine
                  }
                }
              }
            }
          }
        }
      }
    }

    BarIconButton {
      bar: root.bar
      text: "󰒭"
      slotSize: Style.space(18)
      opticalSize: Style.space(12)
      fontSize: Style.font.caption
      tooltipText: "Next"
      interactive: root.canNext
      dimmed: !root.canNext
      onPressed: root.runAction("next")
    }
  }

  PopupCard {
    id: popup
    anchorItem: waveButton
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(popupContent.implicitHeight)

    Item {
      id: popupContent
      anchors.fill: parent
      implicitHeight: Style.space(96)

      Row {
        anchors.fill: parent
        spacing: Style.space(12)

        BorderSurface {
          id: artwork
          width: Style.space(96)
          height: Style.space(96)
          visible: root.showArtwork
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Commons.Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent)
          clip: true

          Image {
            id: coverImage
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.effectiveArtUrl
            visible: status === Image.Ready && source !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: coverImage.status !== Image.Ready
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            opacity: 0.72
          }
        }

        Item {
          id: mediaDetails
          width: root.showArtwork
            ? parent.width - artwork.width - parent.spacing
            : parent.width
          height: parent.height

          Item {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Style.space(45)

            Column {
              anchors.left: parent.left
              anchors.right: playSurface.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.title
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.artist || root.album
                color: Qt.darker(root.bar.foreground, 1.35)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            BorderSurface {
              id: playSurface
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(42)
              height: width
              radius: width / 2
              color: playMouse.pressed
                ? Style.pressedFillFor(root.bar.foreground, Commons.Color.accent)
                : playMouse.containsMouse
                  ? Style.hoverFillFor(root.bar.foreground, Commons.Color.accent)
                  : Style.selectedFillFor(root.bar.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent)
              opacity: root.canToggle ? 1 : 0.4

              Text {
                anchors.centerIn: parent
                text: root.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.iconLarge
              }

              MouseArea {
                id: playMouse
                anchors.fill: parent
                enabled: root.canToggle
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.runAction("playPause")
              }
            }
          }

          Text {
            id: timeLabel
            anchors.left: parent.left
            anchors.top: header.bottom
            anchors.topMargin: Style.space(2)
            text: root.formatTime(root.positionSeconds) + " / " + root.formatTime(root.durationSeconds)
            color: Qt.darker(root.bar.foreground, 1.35)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            visible: root.durationSeconds > 0
          }

          Row {
            id: transport
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Style.space(26)
            spacing: Style.space(6)

            Item {
              width: Style.space(18)
              height: parent.height
              opacity: root.canPrevious ? 1 : 0.35

              Text {
                anchors.centerIn: parent
                text: "󰒮"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.canPrevious
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.runAction("previous")
              }
            }

            Item {
              id: waveProgress
              width: transport.width
                - Style.space(36)
                - transport.spacing * 2
              height: parent.height

              Canvas {
                id: progressCanvas
                anchors.fill: parent

                property real progress: root.progressRatio
                property color foreground: root.bar ? root.bar.foreground : Commons.Color.foreground

                onProgressChanged: requestPaint()
                onForegroundChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                function drawWave(ctx) {
                  var middle = height / 2
                  var amplitude = Math.max(2, height * 0.16)
                  var steps = Math.max(24, Math.floor(width))

                  ctx.beginPath()
                  for (var i = 0; i <= steps; i++) {
                    var x = i / steps * width
                    var phase = i / steps
                    var envelope = 0.45 + 0.55 * Math.sin(Math.PI * phase)
                    var y = middle
                      + Math.sin(phase * Math.PI * 10) * amplitude * envelope
                      + Math.sin(phase * Math.PI * 4) * amplitude * 0.35
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                  }
                  ctx.stroke()
                }

                onPaint: {
                  var ctx = getContext("2d")
                  ctx.clearRect(0, 0, width, height)
                  ctx.lineWidth = Math.max(1.5, Style.spaceReal(2))
                  ctx.lineCap = "round"
                  ctx.lineJoin = "round"
                  ctx.strokeStyle = foreground

                  ctx.save()
                  ctx.globalAlpha = 0.28
                  drawWave(ctx)
                  ctx.restore()

                  if (progress > 0) {
                    ctx.save()
                    ctx.beginPath()
                    ctx.rect(0, 0, width * progress, height)
                    ctx.clip()
                    ctx.globalAlpha = 0.92
                    drawWave(ctx)
                    ctx.restore()
                  }
                }
              }

              Rectangle {
                visible: root.durationSeconds > 0
                x: Math.max(0, Math.min(parent.width - width, parent.width * root.progressRatio - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                width: Style.spaceReal(4)
                height: width
                radius: width / 2
                color: root.bar.foreground
                opacity: root.canSeek ? 0.85 : 0.35
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.canSeek
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: function(mouse) {
                  root.seekToRatio(mouse.x / width)
                }
                onWheel: function(wheel) {
                  var step = wheel.angleDelta.y > 0 ? 5 : -5
                  root.seekToRatio((root.positionSeconds + step) / root.durationSeconds)
                }
              }
            }

            Item {
              width: Style.space(18)
              height: parent.height
              opacity: root.canNext ? 1 : 0.35

              Text {
                anchors.centerIn: parent
                text: "󰒭"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                anchors.fill: parent
                enabled: root.canNext
                hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.runAction("next")
              }
            }
          }
        }
      }
    }
  }
}
