import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Minimized Windows: a row of floating glass cards along the bottom of the
// screen, one per minimized window, each with a live preview.
//
//   click a card      bring that window back (the row stays open for more)
//   ✕ on a card       close that app
//   Restore all       bring every minimized window back
//   wheel             scroll the row
//   ← → Enter Del     keyboard: move, restore, close; Ctrl+A restores all
//   Esc / click away  close the row
//
// Shell commands (bind them to keys in ~/.config/hypr/bindings.lua):
//   omarchy-shell shell toggle <id>      show/hide the row
//   omarchy-shell <id> minimize          minimize the active window
//   omarchy-shell <id> restoreLast       bring back the most recent one
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "kunush.minimized-windows"

  property bool opened: false
  property int selectedIndex: 0
  // Bumped when fresh previews are saved, so the images reload.
  property int previewStamp: 0

  // The bundled helper script, run with bash so it works without +x.
  readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("minimize.sh")).replace(/^file:\/\//, ""))
  readonly property string previewDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-minimized-windows"

  function helper(args) {
    return ["bash", root.script].concat(args)
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // Same theme tokens as the dock and bar popups, so it follows the current
  // Omarchy theme. Cards are see-through; for a blurred background add the
  // layer rule from the README.
  readonly property real cardOpacity: 0.72
  property color background: Util.alpha(Commons.Color.popups.background, cardOpacity)
  property color solidBackground: Commons.Color.popups.background
  property color foreground: Commons.Color.popups.text
  property color border: Commons.Color.popups.border
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property color selectedBackground: Style.hoverFill
  property color selectedText: Commons.Color.accent
  property color muted: Commons.Color.muted
  property string fontFamily: Style.font.menuFamily

  readonly property int tileWidth: Style.space(240)
  readonly property int previewHeight: Style.space(140)
  readonly property int tileHeight: previewHeight + Style.space(60)
  readonly property int tileSpacing: Style.spacing.md

  ListModel { id: windowsModel }

  // ---- Shell lifecycle --------------------------------------------------

  function open(payloadJson) {
    root.opened = true
    root.selectedIndex = 0
    windowsModel.clear()
    clientsProc.running = true
    previewsProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else if (root.shell && typeof root.shell.summon === "function") root.shell.summon(root.pluginId, "{}")
    else root.open("{}")
  }

  ShellIpc {
    target: root.pluginId

    function toggle(): void { root.toggle() }
    function minimize(): void { Quickshell.execDetached(root.helper(["minimize"])) }
    function restoreLast(): void { Quickshell.execDetached(root.helper(["restore-last", strings.t("empty")])) }
  }

  // ---- Data -------------------------------------------------------------

  function loadClients(raw) {
    var clients = []
    try { clients = JSON.parse(raw) } catch (e) { clients = [] }
    if (!Array.isArray(clients)) clients = []

    var minimized = clients.filter(function(c) {
      return c && c.workspace && c.workspace.name === "special:minimized"
        && /^0x[0-9a-f]+$/.test(String(c.address || ""))
    })
    // Most recently minimized first.
    minimized.sort(function(a, b) { return (a.focusHistoryID || 0) - (b.focusHistoryID || 0) })

    windowsModel.clear()
    for (var i = 0; i < minimized.length && i < 100; i++) {
      var c = minimized[i]
      var appId = String(c.class || c.initialClass || "").slice(0, 200)
      var entry = appId ? DesktopEntries.heuristicLookup(appId) : null
      windowsModel.append({
        address: String(c.address),
        title: String(c.title || "").slice(0, 200),
        appName: (entry && entry.name) ? String(entry.name).slice(0, 200) : appId,
        icon: (entry && entry.icon) ? Quickshell.iconPath(entry.icon, true) : "",
        preview: "file://" + root.previewDir + "/" + c.address + ".jpg"
      })
    }
    root.selectedIndex = 0
  }

  // Brings one window back and keeps the row open, so several can be restored
  // in a row. The row closes itself once nothing is left.
  function restore(index) {
    if (index < 0 || index >= windowsModel.count) return
    Quickshell.execDetached(root.helper(["restore", windowsModel.get(index).address]))
    root.dropCard(index)
  }

  function restoreAll() {
    var addresses = []
    // Oldest first, so the most recently minimized window ends up focused.
    for (var i = windowsModel.count - 1; i >= 0; i--) addresses.push(windowsModel.get(i).address)
    if (addresses.length > 0) Quickshell.execDetached(root.helper(["restore"].concat(addresses)))
    windowsModel.clear()
    root.dismiss()
  }

  // Closes the app behind a card and drops the card right away.
  function closeWindow(index) {
    if (index < 0 || index >= windowsModel.count) return
    Quickshell.execDetached(root.helper(["close", windowsModel.get(index).address]))
    root.dropCard(index)
  }

  function dropCard(index) {
    windowsModel.remove(index)
    if (windowsModel.count === 0) { root.dismiss(); return }
    root.selectedIndex = Math.min(root.selectedIndex, windowsModel.count - 1)
  }

  function moveSelection(delta) {
    if (windowsModel.count === 0) return
    root.selectedIndex = Math.max(0, Math.min(windowsModel.count - 1, root.selectedIndex + delta))
    strip.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  Process {
    id: previewsProc
    command: root.helper(["previews"])
    onExited: root.previewStamp++
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      onStreamFinished: root.loadClients(text)
    }
  }

  // ---- UI ---------------------------------------------------------------

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "minimized-windows"

    // Anywhere outside the cards closes the row.
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    // No surrounding box: just a row of separate glass cards.
    Item {
      id: row
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.gapsOut * 2
      width: Math.min(panel.width - Style.gapsOut * 4,
                      Math.max(0, windowsModel.count * (root.tileWidth + root.tileSpacing) - root.tileSpacing))
      height: root.tileHeight

      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.97
      transformOrigin: Item.Bottom
      Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
      Behavior on scale {
        NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          var key = Util.readingKey(event)
          if (event.key === Qt.Key_Escape) root.dismiss()
          else if (key === Qt.Key_Left) root.moveSelection(-1)
          else if (key === Qt.Key_Right) root.moveSelection(1)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.restore(root.selectedIndex)
          else if (event.key === Qt.Key_Delete) root.closeWindow(root.selectedIndex)
          else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) root.restoreAll()
          else return
          event.accepted = true
        }
      }

      ListView {
        id: strip
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: root.tileSpacing
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: windowsModel

        // A normal (vertical) mouse wheel scrolls the row sideways.
        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
            var maxX = Math.max(0, strip.contentWidth - strip.width)
            strip.contentX = Math.max(0, Math.min(maxX, strip.contentX - delta))
          }
        }

        delegate: Rectangle {
          id: tile
          required property int index
          required property string address
          required property string title
          required property string appName
          required property string icon
          required property string preview

          readonly property bool current: index === root.selectedIndex
          width: root.tileWidth
          height: strip.height
          radius: Style.cornerRadius
          color: root.background
          border.width: current ? Style.normalBorderWidth * 2 : Style.normalBorderWidth
          border.color: current ? root.accent : root.border

          // Hover/selection tint on top of the glass.
          Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: tile.current || tileMouse.containsMouse ? root.selectedBackground : "transparent"
          }

          Item {
            id: previewBox
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Style.space(8)
            height: root.previewHeight

            Image {
              id: shot
              anchors.fill: parent
              source: root.previewStamp > 0 ? tile.preview + "?v=" + root.previewStamp : ""
              cache: false
              asynchronous: true
              fillMode: Image.PreserveAspectFit
              sourceSize.width: width * 2
            }

            // No preview captured: show the app icon instead.
            Image {
              anchors.centerIn: parent
              visible: shot.status !== Image.Ready
              width: Style.space(64)
              height: width
              source: tile.icon
              sourceSize.width: width * 2
              fillMode: Image.PreserveAspectFit
            }
          }

          Text {
            id: titleText
            anchors.top: previewBox.bottom
            anchors.topMargin: Style.space(6)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            textFormat: Text.PlainText
            text: tile.title || strings.t("untitled")
            elide: Text.ElideRight
            color: tile.current || tileMouse.containsMouse ? root.selectedText : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.top: titleText.bottom
            anchors.left: titleText.left
            anchors.right: titleText.right
            textFormat: Text.PlainText
            text: tile.appName
            elide: Text.ElideRight
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = tile.index
            onClicked: root.restore(tile.index)
          }

          // Close button in the card's top-right corner.
          Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.space(6)
            width: Style.space(24)
            height: width
            radius: width / 2
            color: closeMouse.containsMouse ? root.urgent : root.solidBackground
            border.width: Style.normalBorderWidth
            border.color: closeMouse.containsMouse ? root.urgent : root.border
            opacity: tile.current || tileMouse.containsMouse || closeMouse.containsMouse ? 1 : 0.75

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "✕"
              color: closeMouse.containsMouse ? root.solidBackground : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            MouseArea {
              id: closeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: root.selectedIndex = tile.index
              onClicked: root.closeWindow(tile.index)
            }
          }
        }
      }
    }

    // "Restore all" pill, floating just above the cards.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: row.top
      anchors.bottomMargin: Style.spacing.md
      visible: root.opened && windowsModel.count > 1
      width: restoreAllText.implicitWidth + Style.space(28)
      height: restoreAllText.implicitHeight + Style.space(14)
      radius: height / 2
      color: restoreAllMouse.containsMouse ? root.accent : root.background
      border.width: Style.normalBorderWidth
      border.color: restoreAllMouse.containsMouse ? root.accent : root.border
      opacity: row.opacity

      Text {
        id: restoreAllText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: strings.tn("restoreAll", windowsModel.count).arg(Commons.I18n.formatNumber(windowsModel.count))
        color: restoreAllMouse.containsMouse ? root.solidBackground : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      MouseArea {
        id: restoreAllMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.restoreAll()
      }
    }

    // Nothing minimized: a small card of its own in the same spot.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.gapsOut * 2
      visible: root.opened && windowsModel.count === 0 && !clientsProc.running
      width: emptyText.implicitWidth + Style.space(32)
      height: emptyText.implicitHeight + Style.space(20)
      radius: Style.cornerRadius
      color: root.background
      border.width: Style.normalBorderWidth
      border.color: root.border

      Text {
        id: emptyText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: strings.t("empty")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
