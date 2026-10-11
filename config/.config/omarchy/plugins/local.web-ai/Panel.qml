import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property bool opened: false
  property var shell: null
  property var manifest: null

  property var panelScreen: null
  property var statusData: Model.blankStatus()
  property string controllerError: ""
  property string actionKind: ""
  property string pendingSummonProvider: ""
  property bool focusDismissArmed: false
  property bool keyboardExclusive: false

  readonly property string controllerPath:
    Quickshell.env("HOME") + "/.config/omarchy/scripts/web-ai-scratchpad"
  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color borderColor: Commons.Color.menu.border
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int contentWidth:
    Math.max(240, Math.min(
      360,
      Math.round((root.panelScreen ? root.panelScreen.width : 1125) * 0.32)
    ))

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    if (monitor) {
      for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === monitor.name) return screens[i]
      }
    }
    return screens.length > 0 ? screens[0] : null
  }

  function setOpen(nextOpened) {
    root.opened = nextOpened
    if (nextOpened) {
      root.focusDismissArmed = false
      root.keyboardExclusive = true
      if (!root.panelScreen) root.panelScreen = root.focusedScreen()
      focusDismissTimer.restart()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      root.focusDismissArmed = false
      root.keyboardExclusive = false
    }
  }

  function notifyHostClosed() {
    root.setOpen(false)
    root.pendingSummonProvider = ""
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "local.web-ai")
  }

  function open(payloadJson) {
    var payload = ({})
    root.controllerError = ""
    root.pendingSummonProvider = ""
    root.panelScreen = root.focusedScreen()

    try {
      payload = JSON.parse(String(payloadJson || "{}"))
    } catch (error) {
      root.controllerError = "Invalid summon payload: expected JSON."
      payload = ({})
    }

    root.setOpen(true)
    root.refreshStatus()

    if (payload.provider !== undefined) {
      var requested = String(payload.provider)
      if (requested === "last") {
        root.pendingSummonProvider = "last"
      } else if (Model.validProvider(requested)) {
        root.pendingSummonProvider = requested
        Qt.callLater(function() {
          if (root.opened && root.pendingSummonProvider === requested) {
            root.pendingSummonProvider = ""
            root.activateProvider(requested)
          }
        })
      } else {
        root.controllerError =
          "Unknown provider '" + requested + "'; choose ChatGPT or Claude."
      }
    }
  }

  function close() {
    root.setOpen(false)
    root.pendingSummonProvider = ""
  }

  function toggle() {
    if (root.opened) root.notifyHostClosed()
    else root.open("{}")
  }

  function refreshStatus() {
    if (!root.opened || statusProcess.running) return
    statusProcess.running = true
  }

  function runAction(argumentsList, kind) {
    if (actionProcess.running) {
      root.controllerError = "Another Web AI action is still running."
      return false
    }
    root.actionKind = kind
    actionProcess.command = [root.controllerPath].concat(argumentsList)
    actionProcess.running = true
    return true
  }

  function activateProvider(providerId) {
    if (!Model.validProvider(providerId)) {
      root.controllerError =
        "Unknown provider '" + providerId + "'; choose ChatGPT or Claude."
      return
    }

    root.controllerError = ""
    root.setOpen(false)
    if (!root.runAction(["show", providerId], "activate")) root.setOpen(true)
  }

  function hideAll() {
    root.controllerError = ""
    root.runAction(["hide", "all"], "hide")
  }

  function openHistory(providerId) {
    if (!Model.validProvider(providerId)) {
      root.controllerError =
        "Unknown provider '" + providerId + "'; choose ChatGPT or Claude."
      return
    }
    root.controllerError = ""
    root.runAction(["open-history", providerId], "history")
  }

  function processError(stderrText, fallback) {
    var message = String(stderrText || "").trim()
    if (message.indexOf("web-ai-scratchpad: ") === 0)
      message = message.slice("web-ai-scratchpad: ".length)
    return message || fallback
  }

  Process {
    id: statusProcess
    command: [root.controllerPath, "status", "--json"]

    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
    }

    onExited: function(exitCode) {
      var parsed = null
      try {
        parsed = JSON.parse(String(statusStdout.text || ""))
      } catch (error) {
        parsed = null
      }

      if (parsed) root.statusData = Model.normalizeStatus(parsed)

      if (exitCode !== 0) {
        root.controllerError = root.processError(
          statusStderr.text,
          parsed && parsed.error
            ? parsed.error
            : "Unable to read Web AI status."
        )
        root.pendingSummonProvider = ""
        return
      }

      if (root.statusData.error)
        root.controllerError = root.statusData.error

      if (root.opened && root.pendingSummonProvider === "last") {
        root.pendingSummonProvider = ""
        var providerId = Model.validProvider(root.statusData.lastProvider)
          ? root.statusData.lastProvider
          : "chatgpt"
        Qt.callLater(function() { root.activateProvider(providerId) })
      }
    }
  }

  Process {
    id: actionProcess
    command: []

    stdout: StdioCollector {
      id: actionStdout
      waitForEnd: true
    }

    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
    }

    onExited: function(exitCode) {
      var completedKind = root.actionKind
      root.actionKind = ""

      if (exitCode !== 0) {
        root.controllerError = root.processError(
          actionStderr.text,
          "The Web AI controller action failed."
        )
        if (completedKind === "activate") {
          root.panelScreen = root.focusedScreen()
          root.setOpen(true)
        }
        root.refreshStatus()
        return
      }

      if (completedKind === "activate") {
        root.notifyHostClosed()
      } else {
        root.refreshStatus()
      }
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: focusDismissTimer
    interval: 180
    repeat: false
    onTriggered: {
      root.focusDismissArmed = root.opened
      root.keyboardExclusive = false
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (!root.opened || !root.focusDismissArmed) return
      if (event.name === "activewindow" || event.name === "activewindowv2")
        root.notifyHostClosed()
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.panelScreen
    implicitWidth: root.contentWidth
    implicitHeight: 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: false
    }

    WlrLayershell.namespace: "local-web-ai-control"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? (root.keyboardExclusive
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.OnDemand)
      : WlrKeyboardFocus.None

    BorderSurface {
      id: panelContent
      anchors.fill: parent
      color: root.background
      radius: 0
      borderSpec: Border.surfaceSpec(
        "menu",
        "border",
        root.borderColor,
        Math.max(1, Style.normalBorderWidth)
      )

      MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) { mouse.accepted = true }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.notifyHostClosed()
            event.accepted = true
          }
        }
      }

      Flickable {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.spacing.md

          Item {
            width: parent.width
            height: Math.max(Style.space(42), heading.implicitHeight)

            Text {
              id: heading
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Web AI"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }

            Button {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "×"
              tooltipText: "Close"
              focusable: true
              bordered: true
              onClicked: root.notifyHostClosed()
            }
          }

          Text {
            width: parent.width
            text: "Choose a provider"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            width: parent.width
            text: Model.providerButtonText(root.statusData, "chatgpt")
            iconText: "◉"
            leftAlign: true
            focusable: true
            bordered: true
            active: root.statusData.providers.chatgpt.state === "visible"
            onClicked: root.activateProvider("chatgpt")
          }

          Button {
            width: parent.width
            text: Model.providerButtonText(root.statusData, "claude")
            iconText: "◇"
            leftAlign: true
            focusable: true
            bordered: true
            active: root.statusData.providers.claude.state === "visible"
            onClicked: root.activateProvider("claude")
          }

          Text {
            width: parent.width
            text: "● Last used: " +
              Model.providerName(root.statusData.lastProvider)
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Rectangle {
            width: parent.width
            height: 1
            color: root.borderColor
            opacity: 0.5
          }

          Button {
            width: parent.width
            text: "Hide all"
            iconText: "—"
            leftAlign: true
            focusable: true
            bordered: true
            onClicked: root.hideAll()
          }

          Text {
            width: parent.width
            text: "Open history in default browser"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            width: parent.width
            text: "ChatGPT history"
            iconText: "↗"
            leftAlign: true
            focusable: true
            bordered: true
            onClicked: root.openHistory("chatgpt")
          }

          Button {
            width: parent.width
            text: "Claude history"
            iconText: "↗"
            leftAlign: true
            focusable: true
            bordered: true
            onClicked: root.openHistory("claude")
          }

          Rectangle {
            width: parent.width
            height: errorText.implicitHeight + Style.spacing.md * 2
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
            border.color: root.accent
            border.width: 1
            visible: root.controllerError.length > 0

            Text {
              id: errorText
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              text: root.controllerError
              color: root.foreground
              wrapMode: Text.Wrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Rectangle {
            width: parent.width
            height: noticeColumn.implicitHeight + Style.spacing.md * 2
            radius: Style.cornerRadius
            color: Qt.rgba(
              root.foreground.r,
              root.foreground.g,
              root.foreground.b,
              0.05
            )
            border.color: root.borderColor
            border.width: 1

            Column {
              id: noticeColumn
              anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: Style.spacing.md
              }
              spacing: Style.spacing.sm

              Text {
                width: parent.width
                text: "Chats are stored by the provider, not Omarchy."
                color: root.foreground
                wrapMode: Text.Wrap
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                width: parent.width
                text: "Temporary or incognito conversations will not appear in provider history."
                color: root.foreground
                opacity: 0.72
                wrapMode: Text.Wrap
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }
  }
}
